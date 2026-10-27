--!strict
-- Player profiles: load/save with retries, autosave, BindToClose, schema
-- versioning. If a load fails we never save over the player's real data.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local CarStats = require(Shared.CarStats)
local Remotes = require(Shared.Remotes)

local SCHEMA_VERSION = 1
local AUTOSAVE_INTERVAL = 120

local PlayerData = {}

export type Profile = {
	Version: number,
	Cash: number,
	Cars: { [string]: CarStats.CarData },
	Selected: string,
	Best: { [string]: number },
	Stats: { [string]: number },
}

type Session = {
	profile: Profile,
	canSave: boolean,
	dirty: boolean,
}

local sessions: { [Player]: Session } = {}
local store: DataStore? = nil
local listeners: { (Player, Profile) -> () } = {}

local function defaultProfile(): Profile
	return {
		Version = SCHEMA_VERSION,
		Cash = Config.StartingCash,
		Cars = { Hatch = CarStats.defaultData("Hatch") },
		Selected = "Hatch",
		Best = {},
		Stats = { Busts = 0, Escapes = 0, Races = 0, Wins = 0, Tickets = 0, Miles = 0 },
	}
end

-- Fill in any fields added since the profile was saved
local function reconcile(data: any): Profile
	local base = defaultProfile()
	if typeof(data) ~= "table" then
		return base
	end
	local p: any = data
	p.Version = SCHEMA_VERSION
	p.Cash = if typeof(p.Cash) == "number" then p.Cash else base.Cash
	p.Cars = if typeof(p.Cars) == "table" then p.Cars else base.Cars
	p.Best = if typeof(p.Best) == "table" then p.Best else {}
	p.Stats = if typeof(p.Stats) == "table" then p.Stats else base.Stats
	for k, v in base.Stats do
		if p.Stats[k] == nil then
			p.Stats[k] = v
		end
	end
	for carId, carData in p.Cars do
		if not Config.Cars[carId] then
			p.Cars[carId] = nil
			continue
		end
		local def = CarStats.defaultData(carId)
		for _, section in { "Upgrades", "Cosmetics", "Tuning" } do
			if typeof(carData[section]) ~= "table" then
				carData[section] = def[section]
			else
				for k, v in (def :: any)[section] do
					if carData[section][k] == nil then
						carData[section][k] = v
					end
				end
			end
		end
	end
	-- everyone always owns the free starter car
	if not p.Cars.Hatch then
		p.Cars.Hatch = CarStats.defaultData("Hatch")
	end
	if typeof(p.Selected) ~= "string" or not p.Cars[p.Selected] then
		p.Selected = next(p.Cars) :: string
	end
	return p :: Profile
end

local function withRetries<T>(fn: () -> T): (boolean, T | string)
	local lastErr: any
	-- in Studio a failure usually means API access is off; don't stall for 30s
	local attempts = if RunService:IsStudio() then 1 else 4
	for attempt = 1, attempts do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		lastErr = result
		if attempt < attempts then
			task.wait(2 ^ attempt)
		end
	end
	return false, tostring(lastErr)
end

local function keyFor(player: Player): string
	return "p_" .. player.UserId
end

local function save(player: Player)
	local session = sessions[player]
	if not session or not session.canSave or not store then
		return
	end
	local snapshot = session.profile
	local ok, err = withRetries(function()
		return (store :: DataStore):UpdateAsync(keyFor(player), function()
			return snapshot
		end)
	end)
	if ok then
		session.dirty = false
	else
		warn("[PlayerData] save failed for", player.Name, err)
	end
end

local function updateLeaderstats(player: Player, profile: Profile)
	local ls = player:FindFirstChild("leaderstats")
	if ls then
		local cash = ls:FindFirstChild("Cash") :: IntValue?
		if cash then
			cash.Value = math.floor(profile.Cash)
		end
	end
end

function PlayerData.get(player: Player): Profile?
	local s = sessions[player]
	return s and s.profile
end

function PlayerData.waitFor(player: Player): Profile?
	local t = 0
	while not sessions[player] and player.Parent and t < 30 do
		t += task.wait(0.1)
	end
	return PlayerData.get(player)
end

-- Call after every mutation so the client UI stays in sync
function PlayerData.changed(player: Player)
	local s = sessions[player]
	if not s then
		return
	end
	s.dirty = true
	updateLeaderstats(player, s.profile)
	Remotes.event("ProfileUpdated"):FireClient(player, s.profile)
	for _, fn in listeners do
		task.spawn(fn, player, s.profile)
	end
end

function PlayerData.onChanged(fn: (Player, Profile) -> ())
	table.insert(listeners, fn)
end

function PlayerData.addCash(player: Player, amount: number, reason: string?)
	local p = PlayerData.get(player)
	if not p or amount ~= amount then
		return
	end
	p.Cash = math.max(0, math.floor(p.Cash + amount))
	PlayerData.changed(player)
	if reason and amount ~= 0 then
		local sign = if amount > 0 then "+" else "-"
		Remotes.event("Notify"):FireClient(player, string.format("%s$%d  %s", sign, math.abs(math.floor(amount)), reason), if amount > 0 then "money" else "warn")
	end
end

function PlayerData.trySpend(player: Player, amount: number): boolean
	local p = PlayerData.get(player)
	if not p or amount < 0 or p.Cash < amount then
		return false
	end
	p.Cash -= amount
	PlayerData.changed(player)
	return true
end

function PlayerData.bumpStat(player: Player, stat: string, by: number)
	local p = PlayerData.get(player)
	if p then
		p.Stats[stat] = (p.Stats[stat] or 0) + by
		PlayerData.changed(player)
	end
end

local function onPlayerAdded(player: Player)
	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	local cash = Instance.new("IntValue")
	cash.Name = "Cash"
	cash.Parent = ls
	ls.Parent = player

	local profile: Profile
	local canSave = false
	if store then
		local ok, result = withRetries(function()
			return (store :: DataStore):GetAsync(keyFor(player))
		end)
		if ok then
			profile = reconcile(result)
			canSave = true
		else
			warn("[PlayerData] load failed, playing with a temporary profile:", result)
			profile = defaultProfile()
		end
	else
		profile = defaultProfile()
	end
	if not player.Parent then
		return
	end
	sessions[player] = { profile = profile, canSave = canSave, dirty = false }
	PlayerData.changed(player)
	if not canSave and store then
		Remotes.event("Notify"):FireClient(player, "Could not load your save. Progress this session will not be saved.", "warn")
	end
end

local function onPlayerRemoving(player: Player)
	save(player)
	sessions[player] = nil
end

function PlayerData.init()
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore("MidnightMotors_v1")
	end)
	if ok then
		store = result
	else
		warn("[PlayerData] DataStores unavailable (enable Studio API access to test saving):", result)
	end

	Remotes.func("GetProfile").OnServerInvoke = function(player: Player)
		return PlayerData.waitFor(player)
	end
end

function PlayerData.start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, p in Players:GetPlayers() do
		task.spawn(onPlayerAdded, p)
	end

	game:BindToClose(function()
		if RunService:IsStudio() and not store then
			return
		end
		local threads = {}
		for player in sessions do
			table.insert(threads, task.spawn(save, player))
		end
		local t = 0
		while t < 25 do
			local busy = false
			for _, th in threads do
				if coroutine.status(th) ~= "dead" then
					busy = true
				end
			end
			if not busy then
				break
			end
			t += task.wait(0.5)
		end
	end)

	while true do
		task.wait(AUTOSAVE_INTERVAL)
		for player, session in sessions do
			if session.dirty then
				task.spawn(save, player)
			end
		end
	end
end

return PlayerData
