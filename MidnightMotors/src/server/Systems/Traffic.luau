--!strict
-- NPC traffic: kinematic (anchored) cars that follow lane loops on the
-- highway ring, the interstate and city streets. They brake for anything in
-- front of them and a few of them are police patrols that can witness
-- violations. Collisions with players are reported to the Police system.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)
local Lanes = require(script.Parent.Lanes)
local CarFactory = require(script.Parent.CarFactory)

local Traffic = {}

export type Npc = {
	model: Model,
	chassis: BasePart,
	lane: Lanes.Lane,
	s: number,
	speed: number,
	height: number,
	halfLen: number,
	isPolice: boolean,
	stuck: number,
	ghost: number,
	waited: number,
	lastHit: number,
}

local npcs: { Npc } = {}
local folder: Folder
local vehicles: Folder
local rayParams = RaycastParams.new()
local rng = Random.new()

local TRAFFIC_GEOMETRY = { "Hatch", "Coupe", "Pickup", "Muscle", "Rally" }
local ROAD_TOP = 0.2

-- Set by the Police system: (player, kind, position) -> ()
Traffic.OnPlayerCollision = nil :: ((Player, string, Vector3) -> ())?

local function randomCosmetics(): { [string]: string }
	local paint = Config.Paints[rng:NextInteger(1, #Config.Paints)].Name
	return { Paint = paint, Finish = "Gloss", Rims = "Silver", Underglow = "Off", Spoiler = "None", Tint = "Light" }
end

local function poseAt(npc: Npc): CFrame
	local p = Lanes.sample(npc.lane, npc.s)
	local ahead = Lanes.sample(npc.lane, npc.s + 14)
	local y = ROAD_TOP + npc.height
	local a = Vector3.new(p.X, y, p.Z)
	local b = Vector3.new(ahead.X, y, ahead.Z)
	if (b - a).Magnitude < 0.01 then
		return CFrame.new(a)
	end
	return CFrame.lookAt(a, b)
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
	local npcVel = npc.chassis.CFrame.LookVector * npc.speed
	local rel = (chassis.AssemblyLinearVelocity - npcVel).Magnitude
	if rel > 30 then
		npc.lastHit = now
		npc.speed = 0
		npc.stuck = 2
		if Traffic.OnPlayerCollision then
			Traffic.OnPlayerCollision(player, if npc.isPolice then "HitPolice" else "HitCar", npc.chassis.Position)
		end
	end
end

local function spawnNpc(lane: Lanes.Lane, s: number, isPolice: boolean): Npc
	local geometry = if isPolice then "Rally" else TRAFFIC_GEOMETRY[rng:NextInteger(1, #TRAFFIC_GEOMETRY)]
	local def = Config.Cars[geometry]
	local model = CarFactory.build(geometry, {
		Kind = if isPolice then "Police" else "Traffic",
		Cosmetics = randomCosmetics(),
		RideHeight = def.RideHeight,
		WheelRadius = def.WheelRadius,
		Name = if isPolice then "PolicePatrol" else "Traffic",
	})
	local chassis = model:FindFirstChild("Chassis") :: BasePart
	chassis.Anchored = true
	if isPolice then
		-- patrols are scenery until they start a pursuit; remove their seat
		local seat = model:FindFirstChild("DriverSeat")
		if seat then
			seat:Destroy()
		end
		model:SetAttribute("Patrol", true)
	end
	local npc: Npc = {
		model = model,
		chassis = chassis,
		lane = lane,
		s = s,
		speed = lane.Speed * rng:NextNumber(0.8, 1),
		height = model:GetAttribute("RestHeight") :: number,
		halfLen = def.Length / 2,
		isPolice = isPolice,
		stuck = 0,
		ghost = 0,
		waited = 0,
		lastHit = 0,
	}
	chassis.CFrame = poseAt(npc)
	model.Parent = folder
	chassis.Touched:Connect(function(hit)
		onTouched(npc, hit)
	end)
	table.insert(npcs, npc)
	return npc
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

-- Remove a patrol (it is replaced by a physics pursuit unit) and respawn it later
function Traffic.takePatrol(npc: Npc): CFrame
	local cf = npc.chassis.CFrame
	local idx = table.find(npcs, npc)
	if idx then
		table.remove(npcs, idx)
	end
	npc.model:Destroy()
	task.delay(60, function()
		spawnNpc(npc.lane, rng:NextNumber(0, npc.lane.Length), true)
	end)
	return cf
end

local function populate()
	local patrolBudget: { [string]: number } = {}
	for _, lane in Lanes.all() do
		local count = if lane.Kind == "Highway"
			then Config.Traffic.HighwayCarsPerLane
			elseif lane.Kind == "Interstate" then Config.Traffic.InterstateCarsPerLane
			else Config.Traffic.CityCarsPerLane
		local spacing = lane.Length / count
		patrolBudget[lane.Kind] = patrolBudget[lane.Kind] or Config.Police.PatrolsPerLaneGroup
		for i = 0, count - 1 do
			local isPolice = false
			if i == 0 and patrolBudget[lane.Kind] > 0 then
				patrolBudget[lane.Kind] -= 1
				isPolice = true
			end
			spawnNpc(lane, i * spacing + rng:NextNumber(0, spacing * 0.5), isPolice)
		end
	end
end

local function refreshFilter()
	local list: { Instance } = { vehicles }
	for _, plr in Players:GetPlayers() do
		if plr.Character then
			table.insert(list, plr.Character)
		end
	end
	rayParams.FilterDescendantsInstances = list
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
	populate()
	refreshFilter()
	local filterTimer = 0
	local acc = 0
	local step = 1 / Config.Traffic.UpdateHz
	local range = Config.Traffic.ActiveRange

	RunService.Heartbeat:Connect(function(dt)
		filterTimer += dt
		if filterTimer > 2 then
			filterTimer = 0
			refreshFilter()
		end
		acc += dt
		if acc < step then
			return
		end
		local frameDt = acc
		acc = 0

		local playerPositions = {}
		for _, plr in Players:GetPlayers() do
			local char = plr.Character
			local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root then
				table.insert(playerPositions, root.Position)
			end
		end

		for _, npc in npcs do
			local cf = npc.chassis.CFrame
			local near = false
			for _, p in playerPositions do
				if (p - cf.Position).Magnitude < range then
					near = true
					break
				end
			end

			local target = npc.lane.Speed
			if near then
				-- brake for anything ahead
				if npc.ghost > 0 then
					npc.ghost -= frameDt
				else
					local look = cf.LookVector
					local origin = cf.Position + look * (npc.halfLen + 1.5) + Vector3.new(0, -0.3, 0)
					local dist = 14 + npc.speed * 1.1
					local hit = workspace:Raycast(origin, look * dist, rayParams)
					if hit then
						local free = hit.Distance - 8
						target = if free <= 0 then 0 else math.min(target, npc.lane.Speed * free / dist)
					end
				end
			end
			if npc.stuck > 0 then
				npc.stuck -= frameDt
				target = 0
			end
			local accel = if target > npc.speed then 18 else 60
			npc.speed += math.clamp(target - npc.speed, -accel * frameDt, accel * frameDt)
			if npc.speed < 1 and target < 1 and npc.stuck <= 0 then
				-- after a long wait, ignore obstacles briefly to untangle jams
				npc.waited += frameDt
				if npc.waited > 4 then
					npc.ghost = 2.5
					npc.waited = 0
				end
			else
				npc.waited = 0
			end
			npc.s = (npc.s + npc.speed * frameDt) % npc.lane.Length
			if near then
				npc.chassis.CFrame = poseAt(npc)
			end
		end
	end)
end

return Traffic
