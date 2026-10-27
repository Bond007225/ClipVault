-- Runs the MidnightMotors place under Lune (https://lune-org.github.io) with
-- stubbed engine services, to smoke-test startup outside Roblox Studio.
--   lune run tools/harness.luau MidnightMotors.rbxlx both   -- start server + client, report
--   lune run tools/harness.luau MidnightMotors.rbxlx place  -- bake the map into the place file
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local task = require("@lune/task")
local process = require("@lune/process")

local placePath = process.args[1]
local mode = process.args[2] or "server"
local game = roblox.deserializePlace(fs.readFile(placePath))

local function signal()
	local s = { handlers = {} }
	function s:Connect(fn)
		table.insert(self.handlers, fn)
		return { Disconnect = function() end, Connected = true }
	end
	function s:Once(fn)
		return self:Connect(fn)
	end
	function s:Wait()
		return coroutine.yield()
	end
	function s:Fire(...)
		for _, h in self.handlers do
			task.spawn(h, ...)
		end
	end
	return s
end
local signals = {}
-- Lune hands out a fresh userdata per access, so key signals by path
local function sigFor(inst, name)
	local key = inst:GetFullName() .. "::" .. name
	signals[key] = signals[key] or signal()
	return signals[key]
end

local I = roblox.implementMethod
local P = roblox.implementProperty
I("Instance", "WaitForChild", function(self, name)
	local c = self:FindFirstChild(name)
	if not c then
		error("WaitForChild would yield forever: " .. self:GetFullName() .. "." .. tostring(name))
	end
	return c
end)
I("Instance", "GetPropertyChangedSignal", function(self, name)
	return sigFor(self, "Changed:" .. name)
end)
I("Instance", "GetAttributeChangedSignal", function(self, name)
	return sigFor(self, "AttrChanged:" .. name)
end)
for _, ev in { "Touched", "Triggered", "Seated", "Died", "CharacterAdded", "OnServerEvent", "OnClientEvent", "AttributeChanged", "Activated", "Completed", "ChildAdded" } do
	P("Instance", ev, function(self)
		return sigFor(self, ev)
	end)
end
local PART_CLASSES = { "BasePart", "Part", "WedgePart", "SpawnLocation", "Seat", "VehicleSeat", "MeshPart" }
P("RemoteFunction", "OnServerInvoke", function() return nil end, function() end)
P("RemoteFunction", "OnClientInvoke", function() return nil end, function() end)
for _, cls in PART_CLASSES do
P(cls, "Position", function(self)
	return self.CFrame.Position
end, function(self, v)
	self.CFrame = self.CFrame - self.CFrame.Position + v
end)
end
local PB = P
P = function(cls, ...)
	if cls == "BasePart" then
		for _, c in PART_CLASSES do PB(c, ...) end
	else
		PB(cls, ...)
	end
end
local IB = I
I = function(cls, ...)
	if cls == "BasePart" then
		for _, c in PART_CLASSES do IB(c, ...) end
	else
		IB(cls, ...)
	end
end
for _, prop in { "AssemblyLinearVelocity", "AssemblyAngularVelocity" } do
	P("BasePart", prop, function()
		return roblox.Vector3.new(0, 0, 0)
	end, function() end)
end
P("BasePart", "AssemblyMass", function()
	return 200
end)
P("BasePart", "AssemblyCenterOfMass", function(self)
	return self.CFrame.Position
end)
I("BasePart", "SetNetworkOwner", function() end)
I("BasePart", "ApplyImpulse", function() end)
I("BasePart", "ApplyImpulseAtPosition", function() end)
I("BasePart", "ApplyAngularImpulse", function() end)
I("BasePart", "GetVelocityAtPosition", function()
	return roblox.Vector3.new(0, 0, 0)
end)
I("Model", "GetPivot", function(self)
	if self.PrimaryPart then
		return self.PrimaryPart.CFrame
	end
	return roblox.CFrame.new()
end)
I("Model", "PivotTo", function(self, cf)
	local pivot = self.PrimaryPart and self.PrimaryPart.CFrame or roblox.CFrame.new()
	local delta = cf * pivot:Inverse()
	for _, d in self:GetDescendants() do
		if d:IsA("BasePart") then
			d.CFrame = delta * d.CFrame
		end
	end
end)
I("Seat", "Sit", function() end)
I("VehicleSeat", "Sit", function() end)
I("RemoteEvent", "FireClient", function() end)
I("RemoteEvent", "FireAllClients", function() end)
I("RemoteEvent", "FireServer", function() end)
I("RemoteFunction", "InvokeServer", function() return nil end)

-- Fake services
local services = {}
services.RunService = {
	IsServer = function() return mode == "server" end,
	IsClient = function() return mode ~= "server" end,
	IsStudio = function() return true end,
	Heartbeat = signal(),
	Stepped = signal(),
	RenderStepped = signal(),
}
local localPlayer
services.Players = {
	PlayerAdded = signal(),
	PlayerRemoving = signal(),
	GetPlayers = function() return {} end,
	GetPlayerFromCharacter = function() return nil end,
	GetPlayerByUserId = function() return nil end,
}
services.DataStoreService = {
	GetDataStore = function()
		error("DataStores disabled in harness")
	end,
}
local tags = {}
services.CollectionService = {
	AddTag = function(_, inst, tag)
		tags[tag] = tags[tag] or {}
		table.insert(tags[tag], inst)
	end,
	GetTagged = function(_, tag) return tags[tag] or {} end,
	GetInstanceAddedSignal = function() return signal() end,
	GetInstanceRemovedSignal = function() return signal() end,
}
local serde = require("@lune/serde")
services.HttpService = {
	JSONEncode = function(_, v) return serde.encode("json", v) end,
	JSONDecode = function(_, s) return serde.decode("json", s) end,
}
services.TweenService = { Create = function() return { Play = function() end, Completed = signal() } end }
services.ContextActionService = {
	BindActionAtPriority = function() end,
	UnbindAction = function() end,
	GetButton = function() return nil end,
}
services.UserInputService = { IsKeyDown = function() return false end, InputBegan = signal() }

local realGetService = game.GetService
local gameProxy = setmetatable({}, {
	__index = function(_, k)
		if k == "GetService" then
			return function(_, name)
				if services[name] then
					return services[name]
				end
				return realGetService(game, name)
			end
		elseif k == "BindToClose" then
			return function() end
		end
		local v = game[k]
		if type(v) == "function" then
			return function(_, ...) return v(game, ...) end
		end
		return v
	end,
})

local function Random_new(seed)
	local r = {}
	math.randomseed(seed or os.clock() * 1000)
	function r:NextNumber(a, b)
		a = a or 0
		b = b or 1
		return a + math.random() * (b - a)
	end
	function r:NextInteger(a, b)
		return math.random(a, b)
	end
	return r
end

local globals = {
	game = gameProxy,
	workspace = realGetService(game, "Workspace"),
	Instance = roblox.Instance,
	Vector3 = roblox.Vector3,
	Vector2 = roblox.Vector2,
	CFrame = roblox.CFrame,
	Color3 = roblox.Color3,
	UDim = roblox.UDim,
	UDim2 = roblox.UDim2,
	Enum = roblox.Enum,
	Font = roblox.Font,
	PhysicalProperties = roblox.PhysicalProperties,
	TweenInfo = { new = function() return {} end },
	Random = { new = Random_new },
	RaycastParams = { new = function() return { FilterDescendantsInstances = {} } end },
	task = task,
	typeof = typeof,
	tick = os.clock,
	warn = function(...) print("[warn]", ...) end,
}
setmetatable(globals, { __index = _G })
-- raycasts never hit in the harness
globals.workspace = globals.workspace
roblox.implementMethod("Workspace", "Raycast", function() return nil end)
P("Workspace", "Gravity", function() return 196.2 end, function() end)

local fakeChars = {}
globals.__get = function(obj, prop)
	if typeof(obj) == "Instance" then
		if prop == "Character" then
			return fakeChars[obj.Name]
		elseif prop == "Health" then
			return 100
		elseif prop == "SeatPart" or prop == "Occupant" then
			return nil
		end
		if prop == "Position" then
			if obj:IsA("BasePart") then return obj.CFrame.Position end
			return obj.Position
		elseif prop == "AssemblyMass" then
			return 200
		elseif prop == "AssemblyCenterOfMass" then
			return obj.CFrame.Position
		end
		return roblox.Vector3.new(0, 0, 0)
	end
	return obj[prop]
end
local cache = {}
local function runScript(inst)
	local env = { script = inst }
	for k, v in globals do
		env[k] = v
	end
	env.require = function(mod)
		if cache[mod] ~= nil then
			return cache[mod]
		end
		local result = runScript(mod)
		cache[mod] = result
		return result
	end
	local src = inst.Source
	for _, prop in { "Position", "AssemblyLinearVelocity", "AssemblyAngularVelocity", "AssemblyMass", "AssemblyCenterOfMass", "Character", "Health", "SeatPart", "Occupant" } do
		src = src:gsub("([%w_%.]+)%." .. prop .. "(%s*)(=?)(=?)", function(obj, sp, e1, e2)
			if e1 == "=" and e2 ~= "=" then
				return obj .. "." .. prop .. sp .. e1 .. e2 -- assignment, keep
			end
			return "__get(" .. obj .. ", \"" .. prop .. "\")" .. sp .. e1 .. e2
		end)
	end
	local fn = luau.load(src, { debugName = inst:GetFullName(), environment = env })
	return fn()
end

local root
local function runSide(side)
	mode = side
	cache = {}
	local r
	if side == "server" then
		r = realGetService(game, "ServerScriptService"):FindFirstChild("Server")
	else
		r = realGetService(game, "StarterPlayer"):FindFirstChild("StarterPlayerScripts"):FindFirstChild("Client")
	end
	local ok, err = pcall(runScript, r)
	print(side, "entry ran:", ok, err)
end
if mode == "place" then
	mode = "server"
	local systems = realGetService(game, "ServerScriptService"):FindFirstChild("Server"):FindFirstChild("Systems")
	local MapBuilder = runScript(systems:FindFirstChild("MapBuilder"))
	MapBuilder.init()
	local map = realGetService(game, "Workspace"):FindFirstChild("Map")
	print("baked map parts:", #map:GetDescendants())
	fs.writeFile(placePath, roblox.serializePlace(game, true))
	print("wrote", placePath)
	process.exit(0)
end
if mode == "events" then
	-- fake player with a character, joined into a race event end-to-end
	runSide("server")
	local systems = realGetService(game, "ServerScriptService"):FindFirstChild("Server"):FindFirstChild("Systems")
	local Events = cache[systems:FindFirstChild("Events")]
	local CarService = cache[systems:FindFirstChild("CarService")]
	local PlayerData = cache[systems:FindFirstChild("PlayerData")]
	local MapBuilder = cache[systems:FindFirstChild("MapBuilder")]
	local plr = roblox.Instance.new("Player")
	plr.Name = "Tester"
	plr.UserId = 42
	plr.DisplayName = "Tester"
	plr.Parent = realGetService(game, "Players")
	local char = roblox.Instance.new("Model")
	char.Name = "Tester"
	local hrp = roblox.Instance.new("Part")
	hrp.Name = "HumanoidRootPart"
	hrp.CFrame = roblox.CFrame.new(150, 3, 130)
	hrp.Parent = char
	local hum = roblox.Instance.new("Humanoid")
	hum.Parent = char
	char.Parent = realGetService(game, "Workspace")
	fakeChars[plr.Name] = char
	services.Players.GetPlayers = function() return { plr } end
	services.Players.GetPlayerByUserId = function(_, id) return if id == 42 then plr else nil end
	services.Players.PlayerAdded:Fire(plr)
	task.wait(0.5)
	print("profile cash:", PlayerData.get(plr) and PlayerData.get(plr).Cash, "owns Hatch:", PlayerData.get(plr) and PlayerData.get(plr).Cars.Hatch ~= nil)
	local spot = CarService.findRoadSpot(hrp.CFrame.Position)
	print("road spawn spot:", spot and spot.Position)
	local car = CarService.spawnCar(plr)
	print("spawned car:", car and car.Name, car and car.PrimaryPart.CFrame.Position)
	-- join an event
	Events._force("DowntownCircuit")
	local remotes = realGetService(game, "ReplicatedStorage"):FindFirstChild("Remotes")
	sigFor(remotes:FindFirstChild("EventJoin"), "OnServerEvent"):Fire(plr, true)
	task.wait(0.2)
	print("joined:", #Events._state.joined, "phase:", Events._state.phase)
	Events._state.phaseEnds = 0
	task.wait(0.3)
	print("phase after lobby:", Events._state.phase, "racers:", #Events._state.racers, "InEvent:", plr:GetAttribute("InEvent"))
	local c = CarService.getCar(plr)
	print("car frozen on grid:", c and c:GetAttribute("Frozen"), c and c.PrimaryPart.Anchored, c and c.PrimaryPart.CFrame.Position)
	Events._state.phaseEnds = 0
	task.wait(0.3)
	print("phase after countdown:", Events._state.phase, "frozen:", c and c:GetAttribute("Frozen"))
	-- drive through every checkpoint (teleport the chassis) as the driver
	c:SetAttribute("Driver", 42)
	local route = MapBuilder.Layout.EventRoutes.DowntownCircuit
	for lap = 1, route.Laps do
		for _, cp in route.Checkpoints do
			c.PrimaryPart.CFrame = roblox.CFrame.new(cp + roblox.Vector3.new(0, 2, 0))
			task.wait(0.15)
		end
	end
	task.wait(0.3)
	print("after driving route: phase", Events._state.phase, "cash", PlayerData.get(plr).Cash, "EventWins", PlayerData.get(plr).Stats.EventWins)
	process.exit(0)
end
if mode == "both" then
	runSide("server")
	task.wait(1)
	local ws = realGetService(game, "Workspace")
	local veh = ws:FindFirstChild("Vehicles")
	print("Map:", ws:FindFirstChild("Map") ~= nil, "Vehicles:", veh and #veh:GetDescendants())
	if veh then
		for _, f in veh:GetChildren() do print("  ", f.Name, #f:GetChildren()) end
	end
	-- traffic: spawn around the downtown spawn and the highway, drive 2 s,
	-- then check every city car is still on a street
	local systems = realGetService(game, "ServerScriptService"):FindFirstChild("Server"):FindFirstChild("Systems")
	local Traffic = cache[systems:FindFirstChild("Traffic")]
	local Config = cache[realGetService(game, "ReplicatedStorage"):FindFirstChild("Shared"):FindFirstChild("Config")]
	local M = Config.Map
	local C = M.CityBlocks * M.CellSize / 2
	Traffic._spawnAround(roblox.Vector3.new(150, 0, 150))
	Traffic._spawnAround(roblox.Vector3.new(M.RingHalfSize, 0, 1000))
	print("traffic cars after spawn:", Traffic._count())
	local off, onDeck = 0, 0
	for _, car in ws.Vehicles.Traffic:GetChildren() do
		local p = car.PrimaryPart.CFrame.Position
		if p.Y > M.DeckHeight then
			onDeck += 1
		else
			local rx = math.abs(((p.X + C) % M.CellSize + M.CellSize / 2) % M.CellSize - M.CellSize / 2)
			local rz = math.abs(((p.Z + C) % M.CellSize + M.CellSize / 2) % M.CellSize - M.CellSize / 2)
			if math.min(rx, rz) > M.RoadWidth / 2 then
				off += 1
				print("  off-road car at", p)
			end
		end
	end
	print("highway cars on deck:", onDeck, "city cars off-road:", off)
	-- fake local player for the client
	local plr = roblox.Instance.new("Player")
	plr.Name = "Tester"
	plr.DisplayName = "Tester"
	plr.UserId = 1
	local pg = roblox.Instance.new("Folder")
	pg.Name = "PlayerGui"
	pg.Parent = plr
	services.Players.LocalPlayer = plr
	runSide("client")
	task.wait(1)
	for _, g in pg:GetChildren() do print("PlayerGui:", g.ClassName, g.Name, #g:GetDescendants()) end
	-- drive the client UI with real payloads
	local ctrl = realGetService(game, "StarterPlayer"):FindFirstChild("StarterPlayerScripts"):FindFirstChild("Client"):FindFirstChild("Controllers")
	local GarageUI = cache[ctrl:FindFirstChild("GarageUI")]
	local RaceEventUI = cache[ctrl:FindFirstChild("RaceEventUI")]
	local Shared = realGetService(game, "ReplicatedStorage"):FindFirstChild("Shared")
	local CarStats = cache[Shared:FindFirstChild("CarStats")]
	local remotes = realGetService(game, "ReplicatedStorage"):FindFirstChild("Remotes")
	local profile = { Cash = 50000, Selected = "Hatch", Cars = { Hatch = CarStats.defaultData("Hatch"), Coupe = CarStats.defaultData("Coupe") }, Best = { Quarter = 12.3 }, Stats = { Races = 1, Wins = 0, Escapes = 2, Busts = 1 } }
	sigFor(remotes:FindFirstChild("ProfileUpdated"), "OnClientEvent"):Fire(profile)
	sigFor(remotes:FindFirstChild("EventUpdate"), "OnClientEvent"):Fire({ type = "Status", phase = "Lobby", eventId = "RingRun", name = "Ring Highway Run", desc = "x", endsIn = 30, joined = { "Tester" }, maxRacers = 12 })
	task.wait(0.1)
	for _, t in { "Shop", "My Cars", "Performance", "Visual", "Tuning", "Events" } do
		local ok, e = pcall(GarageUI.open, t)
		print("menu tab", t, ok, e)
	end
	local cps = { roblox.Vector3.new(0, 0, 0), roblox.Vector3.new(100, 0, 0) }
	for _, msg in {
		{ type = "Start", checkpoints = cps, laps = 2, radius = 45, countdown = 5, racers = 3 },
		{ type = "Go" },
		{ type = "Checkpoint", cp = 2, total = 2, lap = 1 },
		{ type = "Lap", lap = 2, laps = 2 },
		{ type = "Finished", place = 1, time = 83.4 },
		{ type = "Results", name = "Ring Highway Run", results = { { name = "Tester", place = 1, time = 83.4, status = "Finished" }, { name = "Bot", status = "DNF" } } },
	} do
		local ok, e = pcall(function()
			RaceEventUI._onUpdate(msg)
			RaceEventUI._render()
		end)
		print("race msg", msg.type, ok, e)
	end
	process.exit(0)
end
if mode == "server" then
	root = realGetService(game, "ServerScriptService"):FindFirstChild("Server")
else
	root = realGetService(game, "StarterPlayer"):FindFirstChild("StarterPlayerScripts"):FindFirstChild("Client")
end
local ok, err = pcall(runScript, root)
print("entry ran:", ok, err)
task.wait(1)
local ws = realGetService(game, "Workspace")
local map = ws:FindFirstChild("Map")
print("Map built:", map ~= nil, map and #map:GetDescendants() or 0)
local remotes = realGetService(game, "ReplicatedStorage"):FindFirstChild("Remotes")
print("Remotes:", remotes and #remotes:GetChildren() or 0)
process.exit(0)
