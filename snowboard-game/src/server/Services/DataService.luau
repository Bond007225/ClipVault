--!strict
-- Player persistence: session-locked DataStore profiles with retries, autosave,
-- save-on-leave and BindToClose. Falls back to an unsaved profile (with a warning)
-- when DataStores are unavailable, e.g. Studio without API access.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Catalog = require(Shared.Catalog)
local Remotes = require(Shared.Remotes)

local SCHEMA_VERSION = 1

export type ProfileData = {
	Version: number,
	Coins: number,
	TotalPoints: number,
	BestCombo: number,
	SnowballHits: number,
	Owned: { [string]: boolean },
	Equipped: { [string]: string },
}

export type Profile = {
	Data: ProfileData,
	CanSave: boolean,
	Dirty: boolean,
	Released: boolean,
}

local DataService = {}

local profiles: { [Player]: Profile } = {}
local loadedCallbacks: { (Player, Profile) -> () } = {}
local releaseCallbacks: { (Player) -> () } = {}
local store: DataStore? = nil

local function defaultData(): ProfileData
	local owned = {}
	for _, item in Catalog.Items do
		if item.Price == 0 then
			owned[item.Id] = true
		end
	end
	return {
		Version = SCHEMA_VERSION,
		Coins = Config.Economy.StartingCoins,
		TotalPoints = 0,
		BestCombo = 0,
		SnowballHits = 0,
		Owned = owned,
		Equipped = table.clone(Catalog.DefaultEquipped),
	}
end

-- Fills in fields added after a profile was first saved and drops unknown items.
local function reconcile(data: any): ProfileData
	local fresh = defaultData()
	if type(data) ~= "table" then
		return fresh
	end
	for key, value in fresh :: any do
		if type(data[key]) ~= type(value) then
			data[key] = value
		end
	end
	for id in fresh.Owned do
		data.Owned[id] = true
	end
	for id in data.Owned do
		if not Catalog.get(id) then
			data.Owned[id] = nil
		end
	end
	for slot, id in data.Equipped do
		local item = Catalog.get(id)
		if not item or item.Slot ~= slot or not data.Owned[id] then
			data.Equipped[slot] = nil
		end
	end
	if not data.Equipped.Board then
		data.Equipped.Board = Catalog.DefaultBoard
	end
	data.Version = SCHEMA_VERSION
	return data :: ProfileData
end

local function key(player: Player): string
	return "u_" .. player.UserId
end

local function retry<T>(attempts: number, fn: () -> T): (boolean, T | string)
	local lastErr: any = nil
	for i = 1, attempts do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		lastErr = result
		task.wait(math.min(2 ^ i, 8))
	end
	return false, tostring(lastErr)
end

local function publishStats(player: Player, data: ProfileData)
	player:SetAttribute("Coins", data.Coins)
	player:SetAttribute("TotalPoints", data.TotalPoints)
	player:SetAttribute("BestCombo", data.BestCombo)
	player:SetAttribute("SnowballHits", data.SnowballHits)

	local stats: Instance? = player:FindFirstChild("leaderstats")
	if not stats then
		local f = Instance.new("Folder")
		f.Name = "leaderstats"
		local pointsValue = Instance.new("IntValue")
		pointsValue.Name = "Points"
		pointsValue.Parent = f
		local comboValue = Instance.new("IntValue")
		comboValue.Name = "Best Combo"
		comboValue.Parent = f
		f.Parent = player
		stats = f
	end
	assert(stats)
	local points = stats:FindFirstChild("Points") :: IntValue?
	local combo = stats:FindFirstChild("Best Combo") :: IntValue?
	if points then
		points.Value = data.TotalPoints
	end
	if combo then
		combo.Value = data.BestCombo
	end
end

local function loadProfile(player: Player): Profile
	local s = store
	if not s then
		return { Data = defaultData(), CanSave = false, Dirty = false, Released = false }
	end

	local data: ProfileData? = nil
	for attempt = 1, 5 do
		local lockedByOther = false
		local ok, err = pcall(function()
			s:UpdateAsync(key(player), function(old: any): any
				old = old or {}
				local lock = old.Lock
				if type(lock) == "table" and lock.JobId ~= game.JobId and os.time() - (lock.Time or 0) < Config.Data.SessionLockTimeout and attempt < 5 then
					lockedByOther = true
					return nil -- cancel the write; another server still owns this profile
				end
				data = reconcile(old.Data)
				return { Data = data, Lock = { JobId = game.JobId, Time = os.time() } }
			end)
		end)
		if ok and not lockedByOther and data then
			return { Data = data, CanSave = true, Dirty = false, Released = false }
		end
		if not ok then
			warn(`[DataService] load attempt {attempt} failed for {player.Name}: {err}`)
		end
		task.wait(if lockedByOther then 6 else 2 * attempt)
		if not player.Parent then
			break
		end
	end

	warn(`[DataService] using temporary data for {player.Name}; progress will not save`)
	return { Data = defaultData(), CanSave = false, Dirty = false, Released = false }
end

local function saveProfile(player: Player, profile: Profile, release: boolean)
	local s = store
	if not s or not profile.CanSave or profile.Released then
		return
	end
	if release then
		profile.Released = true
	end
	local data = profile.Data
	local ok, err = retry(3, function()
		s:UpdateAsync(key(player), function(old: any): any
			old = old or {}
			local lock = old.Lock
			if type(lock) == "table" and lock.JobId ~= game.JobId then
				return nil -- another server took over this profile; never overwrite it
			end
			return {
				Data = data,
				Lock = if release then nil else { JobId = game.JobId, Time = os.time() },
			}
		end)
		return true
	end)
	if ok then
		profile.Dirty = false
	else
		warn(`[DataService] save failed for {player.Name}: {err}`)
	end
end

local function onPlayerAdded(player: Player)
	local profile = loadProfile(player)
	if not player.Parent then
		return
	end
	profiles[player] = profile
	publishStats(player, profile.Data)
	if not profile.CanSave then
		Remotes.event("Notify"):FireClient(player, "Your progress could not be loaded and won't be saved this session.", "Warning")
	end
	for _, cb in loadedCallbacks do
		task.spawn(cb, player, profile)
	end
end

function DataService.get(player: Player): Profile?
	return profiles[player]
end

-- Yields until the player's profile has loaded (or the player leaves).
function DataService.waitFor(player: Player): Profile?
	while player.Parent and not profiles[player] do
		task.wait(0.1)
	end
	return profiles[player]
end

function DataService.onLoaded(cb: (Player, Profile) -> ())
	table.insert(loadedCallbacks, cb)
	for player, profile in profiles do
		task.spawn(cb, player, profile)
	end
end

-- Runs just before a leaving player's profile is saved for the last time.
function DataService.onRelease(cb: (Player) -> ())
	table.insert(releaseCallbacks, cb)
end

function DataService.markDirty(player: Player)
	local profile = profiles[player]
	if profile then
		profile.Dirty = true
		publishStats(player, profile.Data)
	end
end

function DataService.awardTrickPoints(player: Player, points: number)
	local profile = profiles[player]
	if not profile or points <= 0 then
		return
	end
	local data = profile.Data
	data.TotalPoints += points
	data.Coins += math.floor(points * Config.Economy.CoinsPerPoint)
	data.BestCombo = math.max(data.BestCombo, points)
	DataService.markDirty(player)
end

function DataService.start()
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.Data.StoreName)
	end)
	if ok then
		store = result
	else
		warn("[DataService] DataStores unavailable, running without saving: " .. tostring(result))
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	Players.PlayerRemoving:Connect(function(player)
		for _, cb in releaseCallbacks do
			pcall(cb, player)
		end
		local profile = profiles[player]
		if profile then
			saveProfile(player, profile, true)
			profiles[player] = nil
		end
	end)

	task.spawn(function()
		while true do
			task.wait(Config.Data.AutosaveInterval)
			for player, profile in profiles do
				-- Always write, so the session lock timestamp stays fresh.
				task.spawn(saveProfile, player, profile, false)
			end
		end
	end)

	game:BindToClose(function()
		if RunService:IsStudio() and not store then
			return
		end
		local pending = 0
		for player, profile in profiles do
			pending += 1
			task.spawn(function()
				saveProfile(player, profile, true)
				pending -= 1
			end)
		end
		local deadline = os.clock() + 25
		while pending > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

return DataService
