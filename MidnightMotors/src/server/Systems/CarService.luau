--!strict
-- Player cars: buying, spawning, entering/exiting, upgrades & cosmetics,
-- fuel, gas pumps and garage terminals. All purchases are validated here.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local CarStats = require(Shared.CarStats)
local Remotes = require(Shared.Remotes)

local PlayerData = require(script.Parent.PlayerData)
local MapBuilder = require(script.Parent.MapBuilder)
local CarFactory = require(script.Parent.CarFactory)
local Lanes = require(script.Parent.Lanes)

local CarService = {}

local GARAGE_RANGE = 140
local SPAWN_COOLDOWN = 5

local vehiclesFolder: Folder
local playerCarsFolder: Folder
local cars: { [Player]: Model } = {}
local lastSpawn: { [Player]: number } = {}
local lastRemote: { [Player]: { [string]: number } } = {}
local mileage: { [Player]: { last: Vector3?, acc: number } } = {}

local function notify(player: Player, text: string, kind: string?)
	Remotes.event("Notify"):FireClient(player, text, kind or "info")
end

-- Simple per-player, per-remote rate limit
local function allow(player: Player, name: string, interval: number): boolean
	local t = os.clock()
	local map = lastRemote[player]
	if not map then
		map = {}
		lastRemote[player] = map
	end
	if map[name] and t - map[name] < interval then
		return false
	end
	map[name] = t
	return true
end

local function humanoidOf(player: Player): Humanoid?
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum and hum.Health > 0 then
		return hum
	end
	return nil
end

local function rootOf(player: Player): BasePart?
	local char = player.Character
	return char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

function CarService.getCar(player: Player): Model?
	local car = cars[player]
	if car and car.Parent then
		return car
	end
	return nil
end

-- The car the player is currently driving (their own, in the driver seat)
function CarService.getDrivenCar(player: Player): Model?
	local car = CarService.getCar(player)
	if car and car:GetAttribute("Driver") == player.UserId then
		return car
	end
	return nil
end

-- Buying, upgrading and spawning work anywhere, except during a police
-- chase or a race event. Notifies the player when refused.
function CarService.canShop(player: Player): boolean
	if ((player:GetAttribute("Heat") :: number?) or 0) > 0 then
		notify(player, "Not while the police are after you!", "warn")
		return false
	end
	if player:GetAttribute("InEvent") then
		notify(player, "Not during a race event.", "warn")
		return false
	end
	return true
end

function CarService.isNearGarage(player: Player): boolean
	local root = rootOf(player)
	if not root then
		return false
	end
	for _, g in MapBuilder.Layout.Garages do
		if (g.Terminal.Position - root.Position).Magnitude < GARAGE_RANGE then
			return true
		end
	end
	return false
end

local function resetWheels(car: Model, rideHeight: number)
	local chassis = car:FindFirstChild("Chassis") :: BasePart
	for _, name in { "FL", "FR", "RL", "RR" } do
		local weld = chassis:FindFirstChild("Weld_" .. name) :: Weld?
		local att = chassis:FindFirstChild("Wheel" .. name) :: Attachment?
		if weld and att then
			weld.C0 = CFrame.new(att.Position - Vector3.new(0, rideHeight, 0))
		end
	end
end

-- Settle a car that nobody is driving: snap it upright onto the ground and anchor
local function park(car: Model)
	local chassis = car:FindFirstChild("Chassis") :: BasePart?
	if not chassis or chassis.Anchored then
		return
	end
	local t = 0
	while t < 4 and chassis.AssemblyLinearVelocity.Magnitude > 2 do
		t += task.wait(0.25)
		if car:GetAttribute("Driver") then
			return
		end
	end
	if car:GetAttribute("Driver") or not car.Parent then
		return
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { vehiclesFolder }
	local hit = workspace:Raycast(chassis.Position + Vector3.new(0, 4, 0), Vector3.new(0, -60, 0), params)
	local groundY = if hit then hit.Position.Y else chassis.Position.Y - (car:GetAttribute("RestHeight") :: number)
	local look = chassis.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.1 then
		flat = Vector3.new(0, 0, -1)
	end
	local pos = Vector3.new(chassis.Position.X, groundY, chassis.Position.Z)
	pcall(function()
		chassis:SetNetworkOwner(nil)
	end)
	chassis.Anchored = true
	CarFactory.place(car, CFrame.lookAt(pos, pos + flat.Unit))
	local stats = HttpService:JSONDecode(car:GetAttribute("Stats") :: string)
	resetWheels(car, stats.RideHeight)
end

function CarService.despawn(player: Player)
	local car = cars[player]
	if car then
		for _, d in car:GetDescendants() do
			if d:IsA("Seat") or d:IsA("VehicleSeat") then
				local occ = d.Occupant
				if occ then
					occ.Sit = false
				end
			end
		end
		car:Destroy()
		cars[player] = nil
	end
end

local function exitSeat(humanoid: Humanoid)
	local seat = humanoid.SeatPart
	if not seat then
		return
	end
	local car = seat.Parent :: Model
	local chassis = car and car:FindFirstChild("Chassis") :: BasePart?
	local weld = seat:FindFirstChild("SeatWeld")
	if weld then
		weld:Destroy()
	end
	humanoid.Sit = false
	local char = humanoid.Parent :: Model
	if chassis and char then
		local localX = chassis.CFrame:PointToObjectSpace(seat.Position).X
		local side = if localX < 0 then -1 else 1
		local W = (car:GetAttribute("W") :: number?) or 6
		local cf = chassis.CFrame * CFrame.new(side * (W / 2 + 3), 1.5, 0)
		local up = Vector3.new(cf.Position.X, cf.Position.Y + 2, cf.Position.Z)
		task.defer(function()
			char:PivotTo(CFrame.lookAt(up, up + Vector3.new(chassis.CFrame.LookVector.X, 0, chassis.CFrame.LookVector.Z)))
		end)
	end
end
CarService.exitSeat = exitSeat

local function connectCar(player: Player, car: Model)
	local chassis = car:FindFirstChild("Chassis") :: BasePart
	local driverSeat = car:FindFirstChild("DriverSeat") :: VehicleSeat
	local drivePrompt = (chassis:FindFirstChild("DriverDoor") :: Attachment):FindFirstChildOfClass("ProximityPrompt") :: ProximityPrompt
	local ridePrompt = (chassis:FindFirstChild("PassengerDoor") :: Attachment):FindFirstChildOfClass("ProximityPrompt") :: ProximityPrompt

	drivePrompt.Triggered:Connect(function(who: Player)
		local hum = humanoidOf(who)
		if not hum or hum.SeatPart then
			return
		end
		if who ~= player then
			notify(who, "This is " .. player.DisplayName .. "'s car.", "warn")
			return
		end
		if driverSeat.Occupant then
			return
		end
		driverSeat:Sit(hum)
	end)

	ridePrompt.Triggered:Connect(function(who: Player)
		local hum = humanoidOf(who)
		if not hum or hum.SeatPart then
			return
		end
		for _, child in car:GetChildren() do
			if child:IsA("Seat") and not child.Occupant then
				child:Sit(hum)
				return
			end
		end
		notify(who, "No free seats.", "warn")
	end)

	driverSeat:GetPropertyChangedSignal("Occupant"):Connect(function()
		local occ = driverSeat.Occupant
		if occ then
			local who = Players:GetPlayerFromCharacter(occ.Parent)
			if who ~= player then
				exitSeat(occ)
				return
			end
			car:SetAttribute("Driver", player.UserId)
			drivePrompt.Enabled = false
			if not car:GetAttribute("Frozen") then
				chassis.Anchored = false
				local ok, err = pcall(function()
					chassis:SetNetworkOwner(player)
				end)
				if not ok then
					warn("[CarService] SetNetworkOwner failed:", err)
				end
			end
			mileage[player] = { last = chassis.Position, acc = (mileage[player] and mileage[player].acc) or 0 }
		else
			car:SetAttribute("Driver", nil)
			drivePrompt.Enabled = true
			task.spawn(park, car)
		end
	end)
end

local function spotIsFree(pos: Vector3): boolean
	for _, folder in vehiclesFolder:GetChildren() do
		for _, other in folder:GetChildren() do
			if other:IsA("Model") and (other:GetPivot().Position - pos).Magnitude < 16 then
				return false
			end
		end
	end
	return true
end

-- A free spot in a driving lane close to `pos`, or nil if no road is nearby
function CarService.findRoadSpot(pos: Vector3): CFrame?
	for _ = 1, 4 do
		local cf, lane = Lanes.findSpawn(pos, 15, 140, nil)
		if cf and lane then
			if lane.Kind == "Street" then
				cf = cf * CFrame.new(9, 0, 0) -- right-hand lane, not the centre line
			end
			if spotIsFree(cf.Position) then
				return cf
			end
		end
	end
	return nil
end

function CarService.spawnCar(player: Player, at: CFrame?): Model?
	local profile = PlayerData.get(player)
	if not profile then
		return nil
	end
	local carId = profile.Selected
	local data = profile.Cars[carId]
	if not data then
		return nil
	end
	CarService.despawn(player)

	local stats = CarStats.compute(carId, data)
	local car = CarFactory.build(carId, {
		Kind = "Player",
		Cosmetics = data.Cosmetics,
		RideHeight = stats.RideHeight,
		WheelRadius = stats.WheelRadius,
		Name = player.Name .. "_Car",
	})
	car:SetAttribute("Owner", player.UserId)
	car:SetAttribute("OwnerName", player.DisplayName)
	car:SetAttribute("CarId", carId)
	car:SetAttribute("Stats", HttpService:JSONEncode(stats))
	car:SetAttribute("FuelCapacity", stats.FuelCapacity)
	car:SetAttribute("Fuel", stats.FuelCapacity)
	car:SetAttribute("Economy", stats.Economy)
	local chassis = car:FindFirstChild("Chassis") :: BasePart
	chassis.Anchored = true

	-- choose a spawn point: given CFrame, else the road next to the player,
	-- else a free pad at the nearest garage
	local target = at
	if not target then
		local root = rootOf(player)
		if root then
			target = CarService.findRoadSpot(root.Position)
		end
	end
	if not target then
		local root = rootOf(player)
		local here = if root then root.Position else MapBuilder.Layout.Spawn.Position
		local bestGarage, bestD = nil, math.huge
		for _, g in MapBuilder.Layout.Garages do
			local d = (g.Terminal.Position - here).Magnitude
			if d < bestD then
				bestGarage, bestD = g, d
			end
		end
		if bestGarage then
			for _, pad in bestGarage.Pads do
				local free = true
				for _, other in playerCarsFolder:GetChildren() do
					if other:IsA("Model") and (other:GetPivot().Position - pad.Position).Magnitude < 12 then
						free = false
					end
				end
				if free then
					target = pad
					break
				end
			end
			target = target or bestGarage.Pads[1]
		end
	end
	CarFactory.place(car, target or MapBuilder.Layout.Spawn)
	car.Parent = playerCarsFolder
	cars[player] = car
	connectCar(player, car)
	return car
end

local function refreshCar(player: Player)
	local car = CarService.getCar(player)
	local profile = PlayerData.get(player)
	if not car or not profile then
		return
	end
	local carId = car:GetAttribute("CarId") :: string
	local data = profile.Cars[carId]
	if not data then
		return
	end
	local stats = CarStats.compute(carId, data)
	car:SetAttribute("Stats", HttpService:JSONEncode(stats))
	car:SetAttribute("FuelCapacity", stats.FuelCapacity)
	car:SetAttribute("Economy", stats.Economy)
	car:SetAttribute("Fuel", math.min(car:GetAttribute("Fuel") :: number, stats.FuelCapacity))
	CarFactory.applyCosmetics(car, data.Cosmetics)
	local chassis = car:FindFirstChild("Chassis") :: BasePart
	if chassis.Anchored then
		resetWheels(car, stats.RideHeight)
		local rest = CarFactory.restHeight(stats.RideHeight, stats.WheelRadius)
		local oldRest = car:GetAttribute("RestHeight") :: number
		car:SetAttribute("RestHeight", rest)
		car:PivotTo(car:GetPivot() * CFrame.new(0, rest - oldRest, 0))
	else
		car:SetAttribute("RestHeight", CarFactory.restHeight(stats.RideHeight, stats.WheelRadius))
	end
end

----------------------------------------------------------------------
-- Race events: freeze a player's car on a grid slot, then release it
----------------------------------------------------------------------
function CarService.placeOnGrid(player: Player, gridCf: CFrame): Model?
	local hum = humanoidOf(player)
	if not hum then
		return nil
	end
	local car = CarService.getCar(player)
	if not car then
		car = CarService.spawnCar(player, gridCf)
	end
	if not car then
		return nil
	end
	local chassis = car:FindFirstChild("Chassis") :: BasePart
	local driverSeat = car:FindFirstChild("DriverSeat") :: VehicleSeat
	car:SetAttribute("Frozen", true)
	pcall(function()
		chassis:SetNetworkOwner(nil)
	end)
	chassis.Anchored = true
	chassis.AssemblyLinearVelocity = Vector3.zero
	chassis.AssemblyAngularVelocity = Vector3.zero
	CarFactory.place(car, gridCf)
	car:SetAttribute("Fuel", car:GetAttribute("FuelCapacity"))
	if hum.SeatPart ~= driverSeat then
		if hum.SeatPart then
			exitSeat(hum)
		end
		task.defer(function()
			if driverSeat.Occupant == nil then
				driverSeat:Sit(hum)
			end
		end)
	end
	return car
end

function CarService.release(player: Player, car: Model)
	car:SetAttribute("Frozen", nil)
	local chassis = car:FindFirstChild("Chassis") :: BasePart?
	if not chassis or not car.Parent then
		return
	end
	if car:GetAttribute("Driver") == player.UserId then
		chassis.Anchored = false
		pcall(function()
			chassis:SetNetworkOwner(player)
		end)
	end
end

----------------------------------------------------------------------
-- Remote handlers
----------------------------------------------------------------------
local function onSpawnCar(player: Player, carId: unknown)
	if not allow(player, "SpawnCar", 1) then
		return
	end
	if not CarService.canShop(player) then
		return
	end
	local profile = PlayerData.get(player)
	if profile and typeof(carId) == "string" and profile.Cars[carId] and profile.Selected ~= carId then
		profile.Selected = carId
		PlayerData.changed(player)
	end
	local now = os.clock()
	if lastSpawn[player] and now - lastSpawn[player] < SPAWN_COOLDOWN then
		notify(player, "Wait a moment before spawning again.", "warn")
		return
	end
	local hum = humanoidOf(player)
	if hum and hum.SeatPart then
		exitSeat(hum)
	end
	lastSpawn[player] = now
	if CarService.spawnCar(player) then
		notify(player, "Your car is ready. Walk up and press E to drive.", "info")
	end
end

local function onBuyCar(player: Player, carId: unknown)
	if not allow(player, "BuyCar", 0.5) or typeof(carId) ~= "string" then
		return
	end
	local def = Config.Cars[carId]
	local profile = PlayerData.get(player)
	if not def or not profile then
		return
	end
	if profile.Cars[carId] then
		notify(player, "You already own this car.", "warn")
		return
	end
	if not CarService.canShop(player) then
		return
	end
	if not PlayerData.trySpend(player, def.Price) then
		notify(player, "Not enough cash.", "warn")
		return
	end
	profile.Cars[carId] = CarStats.defaultData(carId)
	profile.Selected = carId
	PlayerData.changed(player)
	notify(player, "Purchased " .. def.Name .. "!", "money")
	CarService.spawnCar(player)
end

local function onSelectCar(player: Player, carId: unknown)
	if not allow(player, "SelectCar", 1) or typeof(carId) ~= "string" then
		return
	end
	local profile = PlayerData.get(player)
	if not profile or not profile.Cars[carId] then
		return
	end
	if not CarService.canShop(player) then
		return
	end
	profile.Selected = carId
	PlayerData.changed(player)
	CarService.spawnCar(player)
end

local function currentData(player: Player): (CarStats.CarData?, string?)
	local profile = PlayerData.get(player)
	if not profile then
		return nil, nil
	end
	return profile.Cars[profile.Selected], profile.Selected
end

local function onBuyUpgrade(player: Player, category: unknown, tier: unknown)
	if not allow(player, "BuyUpgrade", 0.3) or typeof(category) ~= "string" or typeof(tier) ~= "number" then
		return
	end
	local def = Config.Upgrades[category]
	local data = currentData(player)
	if not def or not data then
		return
	end
	if tier ~= tier or tier % 1 ~= 0 or tier < 1 or tier > #def.Tiers then
		return
	end
	if not CarService.canShop(player) then
		return
	end
	local current = data.Upgrades[category] or 1
	if tier <= current then
		-- downgrading to an earlier part is free (parts are kept)
		data.Upgrades[category] = tier
	elseif tier == current + 1 then
		local price = def.Tiers[tier].Price
		if not PlayerData.trySpend(player, price) then
			notify(player, "Not enough cash.", "warn")
			return
		end
		data.Upgrades[category] = tier
		notify(player, string.format("Installed %s %s", def.Tiers[tier].Name, def.Name), "money")
	else
		notify(player, "Install the previous tier first.", "warn")
		return
	end
	PlayerData.changed(player)
	refreshCar(player)
end

local COSMETIC_LISTS: { [string]: { any } } = {
	Paint = Config.Paints,
	Finish = Config.Finishes,
	Rims = Config.RimColors,
	Underglow = Config.Underglows,
	Tint = Config.Tints,
}

local function optionExists(key: string, value: string): boolean
	if key == "Spoiler" then
		return table.find(Config.Spoilers, value) ~= nil
	end
	local list = COSMETIC_LISTS[key]
	if not list then
		return false
	end
	for _, opt in list do
		if opt.Name == value then
			return true
		end
	end
	return false
end

local function onSetCosmetic(player: Player, key: unknown, value: unknown)
	if not allow(player, "SetCosmetic", 0.3) or typeof(key) ~= "string" or typeof(value) ~= "string" then
		return
	end
	local price = Config.CosmeticPrices[key]
	local data = currentData(player)
	if not price or not data or not optionExists(key, value) then
		return
	end
	if data.Cosmetics[key] == value then
		return
	end
	if not CarService.canShop(player) then
		return
	end
	if not PlayerData.trySpend(player, price) then
		notify(player, "Not enough cash.", "warn")
		return
	end
	data.Cosmetics[key] = value
	PlayerData.changed(player)
	refreshCar(player)
end

local function onSetTuning(player: Player, key: unknown, value: unknown)
	if not allow(player, "SetTuning", 0.1) or typeof(key) ~= "string" or typeof(value) ~= "number" then
		return
	end
	local spec = Config.Tuning[key]
	local data = currentData(player)
	if not spec or not data or value ~= value then
		return
	end
	if not CarService.canShop(player) then
		return
	end
	local snapped = math.clamp(math.round(value / spec.Step) * spec.Step, spec.Min, spec.Max)
	data.Tuning[key] = snapped
	PlayerData.changed(player)
	refreshCar(player)
end

local function onExitCar(player: Player)
	if not allow(player, "ExitCar", 0.3) then
		return
	end
	local hum = humanoidOf(player)
	if hum and hum.SeatPart then
		exitSeat(hum)
	end
end

----------------------------------------------------------------------
-- Fuel, mileage pay, pumps, garage terminals
----------------------------------------------------------------------
local function onRefuel(player: Player, pump: BasePart)
	local car = CarService.getCar(player)
	if not car then
		notify(player, "You don't have a car out.", "warn")
		return
	end
	if (car:GetPivot().Position - pump.Position).Magnitude > 45 then
		notify(player, "Bring your car closer to the pump.", "warn")
		return
	end
	local cap = car:GetAttribute("FuelCapacity") :: number
	local fuel = car:GetAttribute("Fuel") :: number
	local need = cap - fuel
	if need < 0.1 then
		notify(player, "Tank is already full.", "info")
		return
	end
	local profile = PlayerData.get(player)
	if not profile then
		return
	end
	local affordable = math.min(need, profile.Cash / Config.GasPricePerGallon)
	local cost = math.ceil(affordable * Config.GasPricePerGallon)
	if affordable < 0.1 or not PlayerData.trySpend(player, cost) then
		notify(player, "Not enough cash for gas.", "warn")
		return
	end
	car:SetAttribute("Fuel", fuel + affordable)
	notify(player, string.format("Filled %.1f gal for $%d", affordable, cost), "money")
end

function CarService.init()
	vehiclesFolder = workspace:FindFirstChild("Vehicles") :: Folder
	if not vehiclesFolder then
		vehiclesFolder = Instance.new("Folder")
		vehiclesFolder.Name = "Vehicles"
		vehiclesFolder.Parent = workspace
	end
	playerCarsFolder = Instance.new("Folder")
	playerCarsFolder.Name = "Players"
	playerCarsFolder.Parent = vehiclesFolder

	Remotes.event("SpawnCar").OnServerEvent:Connect(onSpawnCar)
	Remotes.event("BuyCar").OnServerEvent:Connect(onBuyCar)
	Remotes.event("SelectCar").OnServerEvent:Connect(onSelectCar)
	Remotes.event("BuyUpgrade").OnServerEvent:Connect(onBuyUpgrade)
	Remotes.event("SetCosmetic").OnServerEvent:Connect(onSetCosmetic)
	Remotes.event("SetTuning").OnServerEvent:Connect(onSetTuning)
	Remotes.event("ExitCar").OnServerEvent:Connect(onExitCar)

	for _, pump in MapBuilder.Layout.GasPumps do
		local pp = pump:FindFirstChildOfClass("ProximityPrompt")
		if pp then
			pp.Triggered:Connect(function(player)
				onRefuel(player, pump)
			end)
		end
	end
	for _, g in MapBuilder.Layout.Garages do
		local pp = g.Terminal:FindFirstChildOfClass("ProximityPrompt")
		if pp then
			pp.Triggered:Connect(function(player)
				Remotes.event("OpenGarage"):FireClient(player)
			end)
		end
	end
end

function CarService.start()
	local function onAdded(player: Player)
		if PlayerData.waitFor(player) then
			if not player.Character then
				player.CharacterAdded:Wait()
			end
			task.wait(1)
			if player.Parent and not cars[player] then
				CarService.spawnCar(player)
			end
		end
	end
	Players.PlayerAdded:Connect(function(player)
		task.spawn(onAdded, player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(onAdded, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		CarService.despawn(player)
		lastSpawn[player] = nil
		lastRemote[player] = nil
		mileage[player] = nil
	end)

	RunService.Heartbeat:Connect(function(dt)
		for player, car in cars do
			if not car.Parent or car:GetAttribute("Driver") ~= player.UserId then
				continue
			end
			local chassis = car:FindFirstChild("Chassis") :: BasePart?
			if not chassis then
				continue
			end
			local speed = chassis.AssemblyLinearVelocity.Magnitude
			local fuel = car:GetAttribute("Fuel") :: number
			if fuel > 0 then
				local economy = (car:GetAttribute("Economy") :: number?) or 1
				local drain = (0.004 + speed * 0.00012) * economy * dt
				car:SetAttribute("Fuel", math.max(0, fuel - drain))
			end

			local m = mileage[player]
			if m and m.last then
				local d = (chassis.Position - m.last).Magnitude
				m.last = chassis.Position
				if d < 20 then -- ignore teleports
					m.acc += d
					if m.acc >= Config.MILE_STUDS then
						m.acc -= Config.MILE_STUDS
						PlayerData.addCash(player, Config.CashPerMileDriven, "Mile driven")
						local p = PlayerData.get(player)
						if p then
							p.Stats.Miles = (p.Stats.Miles or 0) + 1
						end
					end
				end
			end
		end
	end)
end

return CarService
