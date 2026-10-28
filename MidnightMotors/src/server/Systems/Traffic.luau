--!strict
-- NPC traffic, spawned around each player and recycled when nobody is near:
--   * city cars drive the street grid, picking a random turn at every
--     intersection and keeping to the right-hand lane
--   * highway cars follow the elevated ring and interstate lane loops
-- Cars are kinematic (anchored, moved by CFrame), brake for anything ahead,
-- and a few are police patrols that can witness violations. Collisions with
-- players are reported to the Police system.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)
local Lanes = require(script.Parent.Lanes)
local CarFactory = require(script.Parent.CarFactory)

local Traffic = {}

local T = Config.Traffic
local M = Config.Map
local N = M.CityBlocks
local CELL = M.CellSize
local C = N * CELL / 2
local ROAD_TOP = 0.2
local LANE_OFFSET = 9 -- right-hand lane offset from the street centreline
local TURN_IN = 30 -- distance from the intersection centre where turns start
local CITY_SPEED = 55

export type Npc = {
	model: Model,
	chassis: BasePart,
	isPolice: boolean,
	speed: number,
	cruise: number,
	height: number,
	halfLen: number,
	stuck: number,
	ghost: number,
	waited: number,
	lastHit: number,
	look: Vector3,
	-- highway lane mode
	lane: Lanes.Lane?,
	s: number,
	-- city grid mode
	pos: Vector3,
	waypoints: { Vector3 },
	node: Vector2?, -- grid node the car is heading towards
	dir: Vector2?, -- current street direction (unit grid step)
}

local npcs: { Npc } = {}
local folder: Folder
local vehicles: Folder
local rayParams = RaycastParams.new()
local rng = Random.new()

local TRAFFIC_GEOMETRY = { "Hatch", "Coupe", "Pickup", "Muscle", "Rally" }

-- Systems interested in players crashing into traffic: (player, kind, position)
local collisionListeners: { (Player, string, Vector3) -> () } = {}
function Traffic.onPlayerCollision(fn: (Player, string, Vector3) -> ())
	table.insert(collisionListeners, fn)
end

----------------------------------------------------------------------
-- Grid helpers
----------------------------------------------------------------------
local function nodePos(node: Vector2): Vector3
	return Vector3.new(-C + node.X * CELL, ROAD_TOP, -C + node.Y * CELL)
end

local function dir3(d: Vector2): Vector3
	return Vector3.new(d.X, 0, d.Y)
end

local function rightOf(d: Vector3): Vector3
	return d:Cross(Vector3.yAxis)
end

local function validNode(n: Vector2): boolean
	return n.X >= 0 and n.X <= N and n.Y >= 0 and n.Y <= N
end

local STEPS = { Vector2.new(1, 0), Vector2.new(-1, 0), Vector2.new(0, 1), Vector2.new(0, -1) }

local function chooseDir(node: Vector2, incoming: Vector2?): Vector2
	local options = {}
	for _, d in STEPS do
		local isReverse = incoming and d == -incoming
		if not isReverse and validNode(node + d) then
			table.insert(options, d)
			if incoming and d == incoming then
				table.insert(options, d) -- going straight is twice as likely
			end
		end
	end
	if #options == 0 then
		return -(incoming :: Vector2) -- dead end: U-turn
	end
	return options[rng:NextInteger(1, #options)]
end

-- Queue the turn through `npc.node` and the next street leg
local function appendLeg(npc: Npc)
	local node = npc.node :: Vector2
	local incoming = npc.dir :: Vector2
	local d = chooseDir(node, incoming)
	local centre = nodePos(node)
	local d1, d2 = dir3(incoming), dir3(d)
	local r1, r2 = rightOf(d1), rightOf(d2)
	local p0 = centre - d1 * TURN_IN + r1 * LANE_OFFSET
	local p2 = centre + d2 * TURN_IN + r2 * LANE_OFFSET
	if d ~= incoming then
		-- quadratic bezier through the corner where the two lane lines meet
		local q: Vector3
		local denom = d1:Dot(r2)
		if math.abs(denom) > 0.5 then
			q = centre + d1 * (LANE_OFFSET / denom) + r1 * LANE_OFFSET
		else
			q = centre -- U-turn
		end
		for _, t in { 0.33, 0.66 } do
			local a = p0:Lerp(q, t)
			local b = q:Lerp(p2, t)
			table.insert(npc.waypoints, a:Lerp(b, t))
		end
	end
	table.insert(npc.waypoints, p2)
	local nextNode = node + d
	table.insert(npc.waypoints, nodePos(nextNode) - d2 * TURN_IN + r2 * LANE_OFFSET)
	npc.node = nextNode
	npc.dir = d
end

----------------------------------------------------------------------
-- Spawning
----------------------------------------------------------------------
local function patrolCount(): number
	local n = 0
	for _, npc in npcs do
		if npc.isPolice then
			n += 1
		end
	end
	return n
end

local function onTouched(npc: Npc, hit: BasePart)
	local now = os.clock()
	if now - npc.lastHit < 2 then
		return
	end
	-- every part of a player car is a direct child of its model
	local car = hit.Parent
	if not car or not car:IsA("Model") or car:GetAttribute("Kind") ~= "Player" then
		return
	end
	local driverId = car:GetAttribute("Driver") :: number?
	if not driverId then
		return
	end
	local player = Players:GetPlayerByUserId(driverId)
	local chassis = car:FindFirstChild("Chassis") :: BasePart?
	if not player or not chassis then
		return
	end
	local rel = (chassis.AssemblyLinearVelocity - npc.look * npc.speed).Magnitude
	if rel > 30 then
		npc.lastHit = now
		npc.speed = 0
		npc.stuck = 2
		for _, fn in collisionListeners do
			task.spawn(fn, player, if npc.isPolice then "HitPolice" else "HitCar", npc.chassis.Position)
		end
	end
end

local function makeNpc(pos: Vector3, look: Vector3, cruise: number): Npc
	local isPolice = patrolCount() < T.MaxPatrols and rng:NextNumber() < T.PatrolChance
	local geometry = if isPolice then "Rally" else TRAFFIC_GEOMETRY[rng:NextInteger(1, #TRAFFIC_GEOMETRY)]
	local def = Config.Cars[geometry]
	local paint = Config.Paints[rng:NextInteger(1, #Config.Paints)].Name
	local model = CarFactory.build(geometry, {
		Kind = if isPolice then "Police" else "Traffic",
		Cosmetics = { Paint = paint, Finish = "Gloss", Rims = "Silver", Underglow = "Off", Spoiler = "None", Tint = "Light" },
		RideHeight = def.RideHeight,
		WheelRadius = def.WheelRadius,
		Name = if isPolice then "PolicePatrol" else "Traffic",
	})
	local chassis = model:FindFirstChild("Chassis") :: BasePart
	chassis.Anchored = true
	if isPolice then
		local seat = model:FindFirstChild("DriverSeat")
		if seat then
			seat:Destroy()
		end
		model:SetAttribute("Patrol", true)
	end
	local npc: Npc = {
		model = model,
		chassis = chassis,
		isPolice = isPolice,
		speed = cruise * 0.8,
		cruise = cruise * rng:NextNumber(0.85, 1),
		height = model:GetAttribute("RestHeight") :: number,
		halfLen = def.Length / 2,
		stuck = 0,
		ghost = 0,
		waited = 0,
		lastHit = 0,
		look = look,
		lane = nil,
		s = 0,
		pos = pos,
		waypoints = {},
		node = nil,
		dir = nil,
	}
	chassis.CFrame = CFrame.lookAt(pos + Vector3.new(0, npc.height, 0), pos + Vector3.new(0, npc.height, 0) + look)
	model.Parent = folder
	chassis.Touched:Connect(function(hit)
		onTouched(npc, hit)
	end)
	table.insert(npcs, npc)
	return npc
end

local function clearAt(pos: Vector3, radius: number): boolean
	for _, npc in npcs do
		if (npc.pos - pos).Magnitude < radius then
			return false
		end
	end
	for _, plr in Players:GetPlayers() do
		local char = plr.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root and (root.Position - pos).Magnitude < 120 then
			return false -- never pop a car into existence right next to someone
		end
	end
	return true
end

local function spawnCityNear(center: Vector3): boolean
	local ci = math.round((center.X + C) / CELL)
	local cj = math.round((center.Z + C) / CELL)
	for _ = 1, 8 do
		local node = Vector2.new(math.clamp(ci + rng:NextInteger(-3, 3), 0, N), math.clamp(cj + rng:NextInteger(-3, 3), 0, N))
		local d = chooseDir(node, nil)
		local nextNode = node + d
		local d3 = dir3(d)
		local r3 = rightOf(d3)
		local pos = nodePos(node):Lerp(nodePos(nextNode), rng:NextNumber(0.25, 0.75)) + r3 * LANE_OFFSET
		local dist = (pos - Vector3.new(center.X, ROAD_TOP, center.Z)).Magnitude
		if dist > 160 and dist < T.CityRange and clearAt(pos, 30) then
			local npc = makeNpc(pos, d3, CITY_SPEED)
			npc.node = nextNode
			npc.dir = d
			table.insert(npc.waypoints, nodePos(nextNode) - d3 * TURN_IN + r3 * LANE_OFFSET)
			return true
		end
	end
	return false
end

local function spawnOnLane(lane: Lanes.Lane, center: Vector3): boolean
	local s0 = Lanes.closest(lane, center)
	for _ = 1, 4 do
		local s = (s0 + (if rng:NextNumber() < 0.5 then -1 else 1) * rng:NextNumber(220, T.HighwayRange * 0.8)) % lane.Length
		local pos, dir = Lanes.sample(lane, s)
		if clearAt(pos, 45) then
			local npc = makeNpc(pos, dir, lane.Speed)
			npc.lane = lane
			npc.s = s
			return true
		end
	end
	return false
end

local function destroyNpc(index: number)
	local npc = npcs[index]
	table.remove(npcs, index)
	npc.model:Destroy()
end

function Traffic.getAll(): { Npc }
	return npcs
end

function Traffic.getPatrols(): { Npc }
	local out = {}
	for _, npc in npcs do
		if npc.isPolice and npc.model.Parent then
			table.insert(out, npc)
		end
	end
	return out
end

-- Remove a patrol (it is replaced by a physics pursuit unit).
-- Returns the ground-level CFrame where it was.
function Traffic.takePatrol(npc: Npc): CFrame
	local cf = npc.chassis.CFrame * CFrame.new(0, -npc.height, 0)
	local idx = table.find(npcs, npc)
	if idx then
		destroyNpc(idx)
	end
	return cf
end

----------------------------------------------------------------------
-- Density management: keep traffic around every player
----------------------------------------------------------------------
local function playerPositions(): { Vector3 }
	local out = {}
	for _, plr in Players:GetPlayers() do
		local char = plr.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			table.insert(out, root.Position)
		end
	end
	return out
end

local function manageDensity()
	local positions = playerPositions()
	-- recycle cars nobody is near
	for i = #npcs, 1, -1 do
		local npc = npcs[i]
		local near = false
		for _, p in positions do
			if (p - npc.pos).Magnitude < T.DespawnRange then
				near = true
				break
			end
		end
		if not near then
			destroyNpc(i)
		end
	end

	local budget = T.SpawnPerTick
	for _, p in positions do
		if #npcs >= T.MaxCars or budget <= 0 then
			break
		end
		-- city
		if math.abs(p.X) < C + 300 and math.abs(p.Z) < C + 300 then
			local count = 0
			for _, npc in npcs do
				if not npc.lane and (npc.pos - p).Magnitude < T.CityRange then
					count += 1
				end
			end
			local want = math.min(T.CityCarsNearPlayer - count, budget)
			for _ = 1, want do
				if spawnCityNear(p) then
					budget -= 1
				end
			end
		end
		-- highway lanes near the player
		for _, lane in Lanes.all() do
			if lane.Kind ~= "Highway" and lane.Kind ~= "Interstate" then
				continue
			end
			local _, d = Lanes.closest(lane, p)
			if d < T.HighwayRange * 0.7 and budget > 0 and #npcs < T.MaxCars then
				local count = 0
				for _, npc in npcs do
					if npc.lane == lane and (npc.pos - p).Magnitude < T.HighwayRange then
						count += 1
					end
				end
				if count < T.HighwayCarsPerLaneNearPlayer and spawnOnLane(lane, p) then
					budget -= 1
				end
			end
		end
	end
end

----------------------------------------------------------------------
-- Movement
----------------------------------------------------------------------
local function refreshFilter()
	local list: { Instance } = { vehicles }
	for _, plr in Players:GetPlayers() do
		if plr.Character then
			table.insert(list, plr.Character)
		end
	end
	rayParams.FilterDescendantsInstances = list
end

local function obstacleSpeed(npc: Npc, cruise: number): number
	if npc.ghost > 0 then
		return cruise
	end
	local origin = npc.chassis.Position + npc.look * (npc.halfLen + 1.5) + Vector3.new(0, -0.3, 0)
	local dist = 14 + npc.speed * 1.1
	local hit = workspace:Raycast(origin, npc.look * dist, rayParams)
	if hit then
		local free = hit.Distance - 8
		return if free <= 0 then 0 else math.min(cruise, cruise * free / dist)
	end
	return cruise
end

local function moveNpc(npc: Npc, dt: number)
	local target = npc.cruise
	-- slow down for corners in the city
	if not npc.lane and #npc.waypoints >= 2 then
		local a = npc.waypoints[1] - npc.pos
		local b = npc.waypoints[2] - npc.waypoints[1]
		if a.Magnitude < 40 and b.Magnitude > 0.1 and a.Magnitude > 0.1 and a.Unit:Dot(b.Unit) < 0.9 then
			target = math.min(target, 28)
		end
	end
	if npc.ghost > 0 then
		npc.ghost -= dt
	end
	target = math.min(target, obstacleSpeed(npc, target))
	if npc.stuck > 0 then
		npc.stuck -= dt
		target = 0
	end
	local accel = if target > npc.speed then 18 else 60
	npc.speed += math.clamp(target - npc.speed, -accel * dt, accel * dt)

	-- untangle jams: after waiting a while, ignore obstacles briefly
	if npc.speed < 1 and target < 1 and npc.stuck <= 0 then
		npc.waited += dt
		if npc.waited > 4 then
			npc.ghost = 2.5
			npc.waited = 0
		end
	else
		npc.waited = 0
	end

	local step = npc.speed * dt
	local desiredLook = npc.look
	if npc.lane then
		local lane = npc.lane :: Lanes.Lane
		npc.s = (npc.s + step) % lane.Length
		local p = Lanes.sample(lane, npc.s)
		local ahead = Lanes.sample(lane, npc.s + 14)
		npc.pos = p
		if (ahead - p).Magnitude > 0.1 then
			desiredLook = (ahead - p).Unit
		end
	else
		while #npc.waypoints < 4 do
			appendLeg(npc)
		end
		while step > 0 and #npc.waypoints > 0 do
			local seg = npc.waypoints[1] - npc.pos
			local len = seg.Magnitude
			if len <= step then
				npc.pos = npc.waypoints[1]
				table.remove(npc.waypoints, 1)
				step -= len
			else
				npc.pos += seg / len * step
				step = 0
			end
		end
		local nextWp = npc.waypoints[1]
		if nextWp and (nextWp - npc.pos).Magnitude < 3 then
			nextWp = npc.waypoints[2] or nextWp
		end
		if nextWp and (nextWp - npc.pos).Magnitude > 0.1 then
			desiredLook = (nextWp - npc.pos).Unit
		end
	end
	npc.look = npc.look:Lerp(desiredLook, math.min(1, dt * 8))
	if npc.look.Magnitude < 0.01 then
		npc.look = desiredLook
	end
	npc.look = npc.look.Unit
	local base = npc.pos + Vector3.new(0, npc.height, 0)
	npc.chassis.CFrame = CFrame.lookAt(base, base + npc.look)
end

function Traffic.init()
	vehicles = workspace:FindFirstChild("Vehicles") :: Folder
	if not vehicles then
		vehicles = Instance.new("Folder")
		vehicles.Name = "Vehicles"
		vehicles.Parent = workspace
	end
	folder = Instance.new("Folder")
	folder.Name = "Traffic"
	folder.Parent = vehicles
	rayParams.FilterType = Enum.RaycastFilterType.Include
end

function Traffic.start()
	refreshFilter()
	local filterTimer = 0
	local densityTimer = 0
	local acc = 0
	local stepTime = 1 / T.UpdateHz

	RunService.Heartbeat:Connect(function(dt)
		filterTimer += dt
		if filterTimer > 2 then
			filterTimer = 0
			refreshFilter()
		end
		densityTimer += dt
		if densityTimer > 0.5 then
			densityTimer = 0
			manageDensity()
		end
		acc += dt
		if acc < stepTime then
			return
		end
		local frameDt = math.min(acc, 0.2)
		acc = 0
		for _, npc in npcs do
			moveNpc(npc, frameDt)
		end
	end)
end

-- exposed for the smoke-test harness
Traffic._count = function(): number
	return #npcs
end
Traffic._spawnAround = function(pos: Vector3)
	for _ = 1, 30 do
		spawnCityNear(pos)
	end
	for _, lane in Lanes.all() do
		if lane.Kind == "Highway" or lane.Kind == "Interstate" then
			spawnOnLane(lane, pos)
		end
	end
	for _ = 1, 60 do
		for _, npc in npcs do
			moveNpc(npc, 1 / 30)
		end
	end
end

return Traffic
