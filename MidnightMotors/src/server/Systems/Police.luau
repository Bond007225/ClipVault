--!strict
-- Police: detects traffic violations (speeding, swerving, reckless driving,
-- hitting police) when a patrol car or speed camera witnesses them, then runs
-- a escalating chase:
--   heat 1  pull-over attempt: stop for a few seconds and you only get a ticket
--   heat 2+ pursuit: more units, interceptors, SUVs, roadblocks, spike strips
--   heat 5  helicopter
-- Stop near a unit long enough and you're BUSTED (fine + impound); get far
-- enough away for long enough and you ESCAPE (reward).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local CarStats = require(Shared.CarStats)
local CarPhysics = require(Shared.CarPhysics)
local Remotes = require(Shared.Remotes)

local PlayerData = require(script.Parent.PlayerData)
local MapBuilder = require(script.Parent.MapBuilder)
local CarFactory = require(script.Parent.CarFactory)
local CarService = require(script.Parent.CarService)
local Traffic = require(script.Parent.Traffic)
local Lanes = require(script.Parent.Lanes)

local Police = {}

local P = Config.Police
local MAX_TOTAL_UNITS = 14
local TICK = 0.2

type Unit = {
	model: Model,
	chassis: BasePart,
	physics: any,
	kind: string,
	normalStats: CarStats.Stats,
	boostStats: CarStats.Stats,
	boosted: boolean,
	stuck: number,
	reverse: number,
	reverseSteer: number,
}

type Pursuit = {
	player: Player,
	heat: number,
	status: string, -- "PullOver" | "Pursuit"
	units: { Unit },
	timer: number, -- pull-over countdown
	stopTimer: number,
	bustTimer: number,
	escapeTimer: number,
	heatTimer: number,
	spawnTimer: number,
	roadblockTimer: number,
	spikeTimer: number,
	ticket: number,
	reasons: { string },
	heli: Model?,
	props: { Instance },
}

type Watch = {
	lastSign: number,
	flips: { number },
	cooldowns: { [string]: number },
}

local pursuits: { [Player]: Pursuit } = {}
local watches: { [Player]: Watch } = {}
local policeFolder: Folder
local mapParams = RaycastParams.new()

local function notify(player: Player, text: string, kind: string?)
	Remotes.event("Notify"):FireClient(player, text, kind or "police")
end

----------------------------------------------------------------------
-- Target helpers
----------------------------------------------------------------------
local function targetOf(player: Player): (Vector3?, Vector3, Vector3, boolean)
	local car = CarService.getDrivenCar(player)
	if car then
		local chassis = car:FindFirstChild("Chassis") :: BasePart?
		if chassis then
			return chassis.Position, chassis.AssemblyLinearVelocity, chassis.CFrame.LookVector, true
		end
	end
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		return root.Position, root.AssemblyLinearVelocity, root.CFrame.LookVector, false
	end
	return nil, Vector3.zero, Vector3.zAxis, false
end

local function totalUnits(): number
	local n = 0
	for _, p in pursuits do
		n += #p.units
	end
	return n
end

local function nearestUnitDistance(p: Pursuit, pos: Vector3): number
	local best = math.huge
	for _, u in p.units do
		local d = (u.chassis.Position - pos).Magnitude
		if d < best then
			best = d
		end
	end
	return best
end

----------------------------------------------------------------------
-- Units
----------------------------------------------------------------------
local function spawnUnit(p: Pursuit, kind: string, groundCf: CFrame): Unit?
	if totalUnits() >= MAX_TOTAL_UNITS then
		return nil
	end
	local spec = P.Units[kind]
	local heatScale = 1 + 0.05 * (p.heat - 1)
	local stats = CarStats.fromUnit(spec, heatScale)
	local boost = CarStats.fromUnit(spec, heatScale * 1.35)
	local model = CarFactory.build(spec.Geometry, {
		Kind = "Police",
		RideHeight = stats.RideHeight,
		WheelRadius = stats.WheelRadius,
		Suv = kind == "SUV",
		Name = "Police_" .. kind,
	})
	local seat = model:FindFirstChild("DriverSeat")
	if seat then
		seat:Destroy()
	end
	model:SetAttribute("Sirens", true)
	model:SetAttribute("Target", p.player.UserId)
	CarFactory.place(model, groundCf + Vector3.new(0, 0.3, 0))
	model.Parent = policeFolder
	local chassis = model:FindFirstChild("Chassis") :: BasePart
	chassis.Anchored = false
	pcall(function()
		chassis:SetNetworkOwner(nil)
	end)
	chassis.AssemblyLinearVelocity = groundCf.LookVector * 40
	local unit: Unit = {
		model = model,
		chassis = chassis,
		physics = CarPhysics.new(model, stats, false),
		kind = kind,
		normalStats = stats,
		boostStats = boost,
		boosted = false,
		stuck = 0,
		reverse = 0,
		reverseSteer = 0,
	}
	table.insert(p.units, unit)
	return unit
end

local function unitKindFor(heat: number): string
	local mix = P.UnitMix[math.clamp(math.floor(heat), 1, #P.UnitMix)]
	return mix[math.random(1, #mix)]
end

local function spawnNear(p: Pursuit)
	local pos, vel = targetOf(p.player)
	if not pos then
		return
	end
	local cf = Lanes.findSpawn(pos, 220, 520, vel)
	if cf then
		spawnUnit(p, unitKindFor(p.heat), cf + Vector3.new(0, 0.2, 0))
	end
end

local function destroyUnit(p: Pursuit, unit: Unit)
	local i = table.find(p.units, unit)
	if i then
		table.remove(p.units, i)
	end
	unit.model:Destroy()
end

----------------------------------------------------------------------
-- Helicopter, roadblocks, spikes
----------------------------------------------------------------------
local function buildHeli(pos: Vector3): Model
	local m = Instance.new("Model")
	m.Name = "PoliceHelicopter"
	local function part(size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material?): Part
		local x = Instance.new("Part")
		x.Size = size
		x.CFrame = cf
		x.Color = color
		x.Material = mat or Enum.Material.SmoothPlastic
		x.Anchored = true
		x.CanCollide = false
		x.CanQuery = false
		x.Parent = m
		return x
	end
	local body = part(Vector3.new(8, 7, 16), CFrame.new(pos), Color3.fromRGB(20, 30, 70))
	m.PrimaryPart = body
	part(Vector3.new(7.6, 4, 5), CFrame.new(pos + Vector3.new(0, 0.5, -8.5)), Color3.fromRGB(30, 40, 60), Enum.Material.Glass)
	part(Vector3.new(1.5, 1.5, 16), CFrame.new(pos + Vector3.new(0, 1.5, 15)), Color3.fromRGB(20, 30, 70))
	part(Vector3.new(0.4, 0.3, 40), CFrame.new(pos + Vector3.new(0, 4.2, 0)), Color3.fromRGB(30, 30, 30))
	part(Vector3.new(40, 0.3, 0.4), CFrame.new(pos + Vector3.new(0, 4.2, 0)), Color3.fromRGB(30, 30, 30))
	local lamp = part(Vector3.new(1.5, 1, 1.5), CFrame.new(pos + Vector3.new(0, -3.8, -5)) * CFrame.Angles(-math.pi / 2, 0, 0), Color3.fromRGB(255, 255, 230), Enum.Material.Neon)
	local spot = Instance.new("SpotLight")
	spot.Face = Enum.NormalId.Front
	spot.Range = 220
	spot.Angle = 30
	spot.Brightness = 8
	spot.Parent = lamp
	for _, side in { -1, 1 } do
		local l = part(Vector3.new(1, 0.6, 1), CFrame.new(pos + Vector3.new(side * 4.1, -2, 0)), if side < 0 then Color3.fromRGB(255, 20, 20) else Color3.fromRGB(20, 60, 255), Enum.Material.Neon)
		l.Name = "Lightbar"
		l:SetAttribute("LightColor", l.Color)
		game:GetService("CollectionService"):AddTag(l, "Lightbar")
	end
	m:SetAttribute("Sirens", true)
	m.Parent = policeFolder
	return m
end

local function closestLanePoint(pos: Vector3): (CFrame?, number)
	local bestCf, bestD = nil, math.huge
	for _, lane in Lanes.all() do
		local s, d = Lanes.closest(lane, pos)
		if d < bestD then
			local p, dir = Lanes.sample(lane, s)
			bestCf, bestD = CFrame.lookAt(p, p + dir), d
		end
	end
	return bestCf, bestD
end

local function spawnRoadblock(p: Pursuit)
	local pos, vel = targetOf(p.player)
	if not pos or vel.Magnitude < 30 then
		return
	end
	local ahead = pos + Vector3.new(vel.X, 0, vel.Z).Unit * 420
	local cf, d = closestLanePoint(ahead)
	if not cf or d > 40 then
		return
	end
	local ground = cf
	local folder = Instance.new("Folder")
	folder.Name = "Roadblock"
	for _, offset in { -9, 9 } do
		local car = CarFactory.build("Rally", { Kind = "Police", RideHeight = 1.1, WheelRadius = 1.25, Name = "RoadblockCar" })
		local seat = car:FindFirstChild("DriverSeat")
		if seat then
			seat:Destroy()
		end
		car:SetAttribute("Sirens", true)
		CarFactory.place(car, ground * CFrame.new(offset, 0, 0) * CFrame.Angles(0, math.rad(80 * math.sign(offset)), 0))
		local chassis = car:FindFirstChild("Chassis") :: BasePart
		chassis.Anchored = true
		car.Parent = folder
	end
	for _, offset in { -24, 24 } do
		local b = Instance.new("Part")
		b.Size = Vector3.new(14, 3, 1)
		b.CFrame = ground * CFrame.new(offset, 1.7, -6)
		b.Color = Color3.fromRGB(255, 120, 0)
		b.Material = Enum.Material.SmoothPlastic
		b.Anchored = true
		b.Parent = folder
	end
	folder.Parent = policeFolder
	table.insert(p.props, folder)
	notify(p.player, "Roadblock ahead!", "police")
	task.delay(40, function()
		folder:Destroy()
	end)
end

local function spawnSpikes(p: Pursuit)
	local pos, vel = targetOf(p.player)
	if not pos or vel.Magnitude < 40 then
		return
	end
	local ahead = pos + Vector3.new(vel.X, 0, vel.Z).Unit * 260
	local cf, d = closestLanePoint(ahead)
	if not cf or d > 40 then
		return
	end
	local ground = cf
	local folder = Instance.new("Folder")
	folder.Name = "SpikeStrip"
	local strip = Instance.new("Part")
	strip.Size = Vector3.new(30, 0.25, 1.4)
	strip.CFrame = ground * CFrame.new(0, 0.15, 0)
	strip.Color = Color3.fromRGB(40, 40, 40)
	strip.Material = Enum.Material.DiamondPlate
	strip.Anchored = true
	strip.CanCollide = false
	strip.Parent = folder
	local trigger = Instance.new("Part")
	trigger.Size = Vector3.new(30, 8, 4)
	trigger.CFrame = ground * CFrame.new(0, 4, 0)
	trigger.Transparency = 1
	trigger.Anchored = true
	trigger.CanCollide = false
	trigger.CanQuery = false
	trigger.Parent = folder
	trigger.Touched:Connect(function(hit)
		local car = hit.Parent
		if car and car:IsA("Model") and car:GetAttribute("Kind") == "Player" and not car:GetAttribute("TiresPopped") then
			car:SetAttribute("TiresPopped", true)
			local owner = Players:GetPlayerByUserId(car:GetAttribute("Owner") :: number)
			if owner then
				notify(owner, "SPIKE STRIP! Your tyres are shredded for 20 seconds.", "warn")
			end
			task.delay(20, function()
				if car.Parent then
					car:SetAttribute("TiresPopped", nil)
				end
			end)
		end
	end)
	folder.Parent = policeFolder
	table.insert(p.props, folder)
	task.delay(30, function()
		folder:Destroy()
	end)
end

----------------------------------------------------------------------
-- Pursuit lifecycle
----------------------------------------------------------------------
local function setAttrs(p: Pursuit?, player: Player)
	if not p then
		player:SetAttribute("Heat", 0)
		player:SetAttribute("PoliceStatus", "")
		player:SetAttribute("BustProgress", 0)
		player:SetAttribute("EscapeProgress", 0)
		player:SetAttribute("PullOverTime", 0)
		return
	end
	player:SetAttribute("Heat", math.floor(p.heat))
	player:SetAttribute("PoliceStatus", p.status)
	player:SetAttribute("BustProgress", math.clamp(p.bustTimer / P.BustTime, 0, 1))
	player:SetAttribute("EscapeProgress", math.clamp(p.escapeTimer / P.EscapeTime, 0, 1))
	player:SetAttribute("PullOverTime", if p.status == "PullOver" then math.max(0, p.timer) else 0)
end

local function endPursuit(player: Player)
	local p = pursuits[player]
	if not p then
		return
	end
	pursuits[player] = nil
	for _, u in table.clone(p.units) do
		destroyUnit(p, u)
	end
	if p.heli then
		p.heli:Destroy()
	end
	for _, prop in p.props do
		prop:Destroy()
	end
	setAttrs(nil, player)
end

local function startPursuit(player: Player, fromPatrol: any?)
	local p: Pursuit = {
		player = player,
		heat = 1,
		status = "PullOver",
		units = {},
		timer = P.PullOverTime,
		stopTimer = 0,
		bustTimer = 0,
		escapeTimer = 0,
		heatTimer = 0,
		spawnTimer = 0,
		roadblockTimer = 15,
		spikeTimer = 20,
		ticket = 0,
		reasons = {},
		heli = nil,
		props = {},
	}
	pursuits[player] = p
	if fromPatrol then
		local cf = Traffic.takePatrol(fromPatrol)
		local ground = cf
		spawnUnit(p, "Cruiser", ground)
	else
		spawnNear(p)
	end
	return p
end

local function escalate(p: Pursuit, amount: number)
	if p.status == "PullOver" then
		p.status = "Pursuit"
		p.heat = math.max(p.heat, 2)
		notify(p.player, "You're evading the police! Lose them or get busted.", "police")
	else
		local before = math.floor(p.heat)
		p.heat = math.min(P.MaxHeat, p.heat + amount)
		if math.floor(p.heat) > before then
			notify(p.player, string.format("Heat level %d!", math.floor(p.heat)), "police")
		end
	end
end

local function bust(player: Player)
	local p = pursuits[player]
	if not p then
		return
	end
	local fine = math.floor(P.BustFinePerHeat * math.max(1, p.heat) + p.ticket)
	local profile = PlayerData.get(player)
	if profile then
		fine = math.min(fine, profile.Cash)
	end
	endPursuit(player)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum and hum.SeatPart then
		CarService.exitSeat(hum)
	end
	CarService.despawn(player)
	task.defer(function()
		if player.Character then
			player.Character:PivotTo(MapBuilder.Layout.PoliceStation)
		end
	end)
	PlayerData.addCash(player, -fine, "BUSTED - fine & impound")
	PlayerData.bumpStat(player, "Busts", 1)
	Remotes.event("Notify"):FireClient(player, "BUSTED! Your car was impounded. Respawn it from the HUD.", "bust")
end

local function escape(player: Player)
	local p = pursuits[player]
	if not p then
		return
	end
	local heat = p.heat
	endPursuit(player)
	if heat >= 2 then
		PlayerData.addCash(player, math.floor(P.EscapeRewardPerHeat * heat), "Escaped the police!")
		PlayerData.bumpStat(player, "Escapes", 1)
	else
		notify(player, "The police lost interest.", "info")
	end
end

local function ticketAndRelease(player: Player)
	local p = pursuits[player]
	if not p then
		return
	end
	local fine = math.floor(p.ticket)
	local profile = PlayerData.get(player)
	if profile then
		fine = math.min(fine, profile.Cash)
	end
	local reasons = table.concat(p.reasons, ", ")
	endPursuit(player)
	PlayerData.addCash(player, -fine, "Ticket: " .. reasons)
	PlayerData.bumpStat(player, "Tickets", 1)
end

----------------------------------------------------------------------
-- Violations
----------------------------------------------------------------------
local function findWitness(pos: Vector3, allowCamera: boolean): (boolean, any?)
	for _, patrol in Traffic.getPatrols() do
		if (patrol.chassis.Position - pos).Magnitude < P.WitnessRange then
			return true, patrol
		end
	end
	for _, p in pursuits do
		if nearestUnitDistance(p, pos) < 400 then
			return true, nil
		end
	end
	if allowCamera then
		for _, cam in MapBuilder.Layout.SpeedCameras do
			if (cam.Position - pos).Magnitude < P.CameraRange then
				local flash = cam.Flash
				flash.Material = Enum.Material.Neon
				flash.Color = Color3.new(1, 1, 1)
				task.delay(0.3, function()
					flash.Material = Enum.Material.SmoothPlastic
					flash.Color = Color3.fromRGB(80, 80, 80)
				end)
				return true, "camera"
			end
		end
	end
	return false, nil
end

function Police.reportViolation(player: Player, kind: string, detail: string, fine: number, witness: any?)
	local w = watches[player]
	if not w then
		return
	end
	local now = os.clock()
	if w.cooldowns[kind] and now - w.cooldowns[kind] < 8 then
		return
	end
	w.cooldowns[kind] = now

	local p = pursuits[player]
	if not p then
		if witness == "camera" then
			-- cameras mail you a ticket and alert nearby units
			local profile = PlayerData.get(player)
			if profile then
				PlayerData.addCash(player, -math.min(fine, profile.Cash), "Speed camera: " .. detail)
			end
			Remotes.event("CameraFlash"):FireClient(player)
			if math.random() < 0.5 then
				p = startPursuit(player, nil)
				p.ticket += fine * 0.5
				table.insert(p.reasons, detail)
				notify(player, "A unit responded to the camera. PULL OVER!", "police")
			end
			return
		end
		p = startPursuit(player, if typeof(witness) == "table" then witness else nil)
		p.ticket += fine
		table.insert(p.reasons, detail)
		notify(player, "Police: PULL OVER! (" .. detail .. ")", "police")
		if kind == "HitPolice" then
			escalate(p, 1)
		end
		return
	end
	p.ticket += fine
	if not table.find(p.reasons, detail) then
		table.insert(p.reasons, detail)
	end
	escalate(p, if kind == "HitPolice" then 1 else 0.5)
end

local function monitor(player: Player, dt: number)
	local car = CarService.getDrivenCar(player)
	local w = watches[player]
	if not car or not w then
		return
	end
	local chassis = car:FindFirstChild("Chassis") :: BasePart?
	if not chassis then
		return
	end
	local pos = chassis.Position
	local zone = MapBuilder.getZone(pos)
	local limit = Config.SpeedLimits[zone] or 55
	player:SetAttribute("Zone", zone)
	player:SetAttribute("SpeedLimit", if limit == math.huge then 0 else limit)
	local vel = chassis.AssemblyLinearVelocity
	local mph = Vector3.new(vel.X, 0, vel.Z).Magnitude * Config.STUDS_TO_MPH
	if zone == "Track" then
		return
	end

	if mph > limit + P.SpeedingTolerance then
		local seen, witness = findWitness(pos, true)
		if seen then
			local over = math.floor(mph - limit)
			Police.reportViolation(player, "Speeding", string.format("Speeding %d over", over), P.TicketBase + P.TicketPerMph * over, witness)
		end
	end

	-- swerving: rapid left/right yaw reversals at speed
	local yaw = chassis.AssemblyAngularVelocity.Y
	local now = os.clock()
	if mph > 35 and math.abs(yaw) > 0.8 then
		local s = math.sign(yaw)
		if s ~= w.lastSign then
			w.lastSign = s
			table.insert(w.flips, now)
		end
	end
	while #w.flips > 0 and now - w.flips[1] > 4 do
		table.remove(w.flips, 1)
	end
	if #w.flips >= 4 then
		w.flips = {}
		local seen, witness = findWitness(pos, false)
		if seen then
			Police.reportViolation(player, "Swerving", "Swerving / reckless lane changes", 300, witness)
		end
	end
end

----------------------------------------------------------------------
-- Unit AI (runs every physics step)
----------------------------------------------------------------------
local function driveUnit(p: Pursuit, u: Unit, dt: number, tpos: Vector3, tvel: Vector3, tlook: Vector3)
	local chassis = u.chassis
	local cf = chassis.CFrame
	local speed = chassis.AssemblyLinearVelocity.Magnitude
	local toT = tpos - cf.Position
	local dist = toT.Magnitude
	local aim = tpos + tvel * math.clamp(dist / 140, 0, 1.2)
	if p.status == "PullOver" then
		aim = tpos - Vector3.new(tlook.X, 0, tlook.Z).Unit * 22
	end
	local dir = aim - cf.Position
	local localDir = cf:VectorToObjectSpace(Vector3.new(dir.X, 0, dir.Z))
	local angle = math.atan2(localDir.X, -localDir.Z)
	local steer = math.clamp(angle * 2.2, -1, 1)
	local throttle = 1

	if p.status == "PullOver" and dist < 45 then
		local targetSpeed = tvel.Magnitude
		throttle = math.clamp((targetSpeed - speed) * 0.08 + (dist - 22) * 0.02, -1, 1)
	end
	if math.abs(angle) > 2.3 and dist < 70 then
		throttle = -1
		steer = -math.sign(angle)
	end

	-- avoid walls and buildings
	if speed > 10 then
		local look = cf.LookVector
		local probe = 25 + speed * 0.45
		local hit = workspace:Raycast(cf.Position, look * probe, mapParams)
		if hit and hit.Distance < dist then
			local left = workspace:Raycast(cf.Position, (cf * CFrame.Angles(0, math.rad(35), 0)).LookVector * probe, mapParams)
			local right = workspace:Raycast(cf.Position, (cf * CFrame.Angles(0, math.rad(-35), 0)).LookVector * probe, mapParams)
			local ld = if left then left.Distance else probe
			local rd = if right then right.Distance else probe
			steer = if ld > rd then -1 else 1
			if hit.Distance < 20 then
				throttle = math.min(throttle, -0.5)
			end
		end
	end

	-- stuck: back up
	if u.reverse > 0 then
		u.reverse -= dt
		throttle = -1
		steer = u.reverseSteer
	elseif throttle > 0.5 and speed < 4 then
		u.stuck += dt
		if u.stuck > 2 then
			u.stuck = 0
			u.reverse = 1.4
			u.reverseSteer = -steer
		end
	else
		u.stuck = 0
	end

	-- rubber-band when far behind
	local wantBoost = dist > 300 and p.status == "Pursuit"
	if wantBoost ~= u.boosted then
		u.boosted = wantBoost
		u.physics:setStats(if wantBoost then u.boostStats else u.normalStats)
	end

	u.physics:step(dt, { throttle = throttle, steer = steer, handbrake = math.abs(angle) > 1.2 and speed > 60, nitro = false })
end

local function updatePursuit(p: Pursuit, dt: number)
	local player = p.player
	local pos, vel, _, inCar = targetOf(player)
	if not pos then
		return
	end
	local nearest = nearestUnitDistance(p, pos)
	local speed = vel.Magnitude

	-- remove units that are hopelessly far or destroyed; replace them
	for _, u in table.clone(p.units) do
		if not u.chassis.Parent or (u.chassis.Position - pos).Magnitude > 1600 or u.chassis.Position.Y < -50 then
			destroyUnit(p, u)
		end
	end

	if p.status == "PullOver" then
		if #p.units == 0 then
			spawnNear(p)
		end
		if speed < 4 and nearest < 70 then
			p.stopTimer += dt
			if p.stopTimer >= P.StopToTicketTime then
				ticketAndRelease(player)
				return
			end
		else
			p.stopTimer = 0
			p.timer -= dt
			if p.timer <= 0 then
				escalate(p, 0)
			end
		end
	else
		p.heatTimer += dt
		if p.heatTimer >= P.HeatGainInterval then
			p.heatTimer = 0
			escalate(p, 1)
		end
		local want = P.UnitsPerHeat[math.clamp(math.floor(p.heat), 1, #P.UnitsPerHeat)]
		p.spawnTimer -= dt
		if #p.units < want and p.spawnTimer <= 0 then
			p.spawnTimer = 3
			spawnNear(p)
		end

		-- bust
		local bustRange = if inCar then P.BustRange else 25
		if nearest < bustRange and (speed < 6 or not inCar) then
			p.bustTimer += dt * (if inCar then 1 else 1.5)
			if p.bustTimer >= P.BustTime then
				bust(player)
				return
			end
		else
			p.bustTimer = math.max(0, p.bustTimer - dt * 0.5)
		end

		-- escape
		local heliSees = false
		if p.heli and p.heli.PrimaryPart then
			local hp = p.heli.PrimaryPart.Position
			heliSees = (Vector3.new(hp.X, 0, hp.Z) - Vector3.new(pos.X, 0, pos.Z)).Magnitude < 350
		end
		if nearest > P.EscapeRange and not heliSees then
			p.escapeTimer += dt
			if p.escapeTimer >= P.EscapeTime then
				escape(player)
				return
			end
		else
			p.escapeTimer = math.max(0, p.escapeTimer - dt * 2)
		end

		-- tactics
		if p.heat >= P.RoadblockHeat then
			p.roadblockTimer -= dt
			if p.roadblockTimer <= 0 then
				p.roadblockTimer = 35
				spawnRoadblock(p)
			end
		end
		if p.heat >= P.SpikeHeat then
			p.spikeTimer -= dt
			if p.spikeTimer <= 0 then
				p.spikeTimer = 28
				spawnSpikes(p)
			end
		end
		if p.heat >= P.HelicopterHeat and not p.heli then
			p.heli = buildHeli(pos + Vector3.new(0, 150, 200))
			notify(player, "Police helicopter inbound!", "police")
		end
	end
	setAttrs(p, player)
end

local function updateHeli(p: Pursuit, dt: number)
	local heli = p.heli
	if not heli or not heli.PrimaryPart then
		return
	end
	local pos, vel = targetOf(p.player)
	if not pos then
		return
	end
	local current = heli:GetPivot()
	local goal = pos + Vector3.new(vel.X, 0, vel.Z) * 0.8 + Vector3.new(0, 150, 0)
	local delta = goal - current.Position
	local maxStep = 150 * dt
	local step = if delta.Magnitude > maxStep then delta.Unit * maxStep else delta
	local newPos = current.Position + step
	local flatTo = Vector3.new(pos.X - newPos.X, 0, pos.Z - newPos.Z)
	local look = if flatTo.Magnitude > 1 then flatTo.Unit else current.LookVector
	heli:PivotTo(CFrame.lookAt(newPos, newPos + look) * CFrame.Angles(math.rad(-8), 0, 0))
end

function Police.getHeat(player: Player): number
	local p = pursuits[player]
	return if p then p.heat else 0
end

function Police.init()
	local vehicles = workspace:WaitForChild("Vehicles")
	policeFolder = Instance.new("Folder")
	policeFolder.Name = "Police"
	policeFolder.Parent = vehicles
	mapParams.FilterType = Enum.RaycastFilterType.Include
	mapParams.FilterDescendantsInstances = { workspace:WaitForChild("Map") }

	Traffic.OnPlayerCollision = function(player: Player, kind: string, pos: Vector3)
		if kind == "HitPolice" then
			Police.reportViolation(player, "HitPolice", "Hitting a police car", 800, nil)
		else
			local seen, witness = findWitness(pos, false)
			if seen then
				Police.reportViolation(player, "Reckless", "Reckless driving (collision)", 400, witness)
			end
		end
	end
end

function Police.start()
	local function onAdded(player: Player)
		watches[player] = { lastSign = 0, flips = {}, cooldowns = {} }
		setAttrs(nil, player)
		player.CharacterAdded:Connect(function(char)
			local hum = char:WaitForChild("Humanoid") :: Humanoid
			hum.Died:Connect(function()
				endPursuit(player)
			end)
		end)
	end
	Players.PlayerAdded:Connect(onAdded)
	for _, player in Players:GetPlayers() do
		onAdded(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		endPursuit(player)
		watches[player] = nil
	end)

	RunService.Stepped:Connect(function(_, dt)
		for _, p in pursuits do
			local pos, vel, look = targetOf(p.player)
			if pos then
				for _, u in p.units do
					if u.chassis.Parent then
						driveUnit(p, u, dt, pos, vel, look)
					end
				end
			end
		end
	end)
	RunService.Heartbeat:Connect(function(dt)
		for _, p in pursuits do
			updateHeli(p, dt)
		end
	end)

	while true do
		local dt = task.wait(TICK)
		for _, player in Players:GetPlayers() do
			monitor(player, dt)
			local p = pursuits[player]
			if p then
				updatePursuit(p, dt)
			end
		end
	end
end

return Police
