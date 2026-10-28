--!strict
-- XP, levels and daily quests. Other systems report activity through
-- Progression.addXp / Progression.track; levels gate upgrade tiers.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)

local PlayerData = require(script.Parent.PlayerData)

local Progression = {}

local P = Config.Progression
local Q = Config.Quests

-- Level for a total XP amount, plus XP into / needed for the current level
function Progression.levelFor(xp: number): (number, number, number)
	local level = 1
	local need = P.BaseXp + P.XpPerLevel * level
	while xp >= need do
		xp -= need
		level += 1
		need = P.BaseXp + P.XpPerLevel * level
	end
	return level, xp, need
end

function Progression.levelOf(player: Player): number
	local profile = PlayerData.get(player)
	if not profile then
		return 1
	end
	return (Progression.levelFor(profile.XP))
end

local function questDef(id: string): any
	for _, q in Q.Pool do
		if q.Id == id then
			return q
		end
	end
	return nil
end

local function today(): number
	return os.time() // 86400
end

-- Make sure the profile holds today's quests (re-rolled every UTC day)
local function ensureQuests(player: Player)
	local profile = PlayerData.get(player)
	if not profile then
		return
	end
	local day = today()
	if profile.Quests.Day == day and #profile.Quests.List > 0 then
		return
	end
	-- deterministic per player and day so rejoining doesn't re-roll
	local rng = Random.new(day * 7919 + player.UserId % 100000)
	local pool = table.clone(Q.Pool)
	local list = {}
	for _ = 1, math.min(Q.PerDay, #pool) do
		local q = table.remove(pool, rng:NextInteger(1, #pool))
		table.insert(list, { Id = q.Id, Progress = 0, Claimed = false })
	end
	profile.Quests = { Day = day, List = list }
	PlayerData.changed(player)
end

function Progression.addXp(player: Player, amount: number)
	local profile = PlayerData.get(player)
	if not profile or amount <= 0 then
		return
	end
	local before = Progression.levelFor(profile.XP)
	profile.XP += math.floor(amount)
	local after = Progression.levelFor(profile.XP)
	player:SetAttribute("Level", after)
	PlayerData.changed(player)
	if after > before then
		Remotes.event("LevelUp"):FireClient(player, after)
		local unlocks = {}
		for tier, lvl in P.TierLevels do
			if lvl > before and lvl <= after then
				table.insert(unlocks, Config.Upgrades.Engine.Tiers[tier].Name)
			end
		end
		if #unlocks > 0 then
			Remotes.event("Notify"):FireClient(player, "Unlocked " .. table.concat(unlocks, ", ") .. " upgrades!", "money")
		end
	end
end

-- Report quest progress. For "Max" quests (top speed, best combo) the amount
-- is the value reached; for the rest it is added.
function Progression.track(player: Player, questId: string, amount: number)
	local profile = PlayerData.get(player)
	if not profile then
		return
	end
	ensureQuests(player)
	local def = questDef(questId)
	if not def then
		return
	end
	for _, q in profile.Quests.List do
		if q.Id == questId and not q.Claimed and q.Progress < def.Goal then
			local before = q.Progress
			if def.Max then
				q.Progress = math.max(q.Progress, math.floor(amount))
			else
				q.Progress += amount
			end
			q.Progress = math.min(q.Progress, def.Goal)
			if q.Progress >= def.Goal and before < def.Goal then
				Remotes.event("Notify"):FireClient(player, "Quest complete! Claim it in the Quests tab.", "money")
			end
			if math.floor(q.Progress) ~= math.floor(before) then
				PlayerData.changed(player)
			end
		end
	end
end

local lastClaim: { [Player]: number } = {}
local function onClaim(player: Player, index: unknown)
	if typeof(index) ~= "number" or index % 1 ~= 0 then
		return
	end
	local now = os.clock()
	if lastClaim[player] and now - lastClaim[player] < 0.5 then
		return
	end
	lastClaim[player] = now
	ensureQuests(player)
	local profile = PlayerData.get(player)
	local q = profile and profile.Quests.List[index]
	local def = q and questDef(q.Id)
	if not q or not def or q.Claimed or q.Progress < def.Goal then
		return
	end
	q.Claimed = true
	PlayerData.addCash(player, def.Cash, "Quest reward")
	Progression.addXp(player, def.Xp)
end

function Progression.init()
	Remotes.event("ClaimQuest").OnServerEvent:Connect(onClaim)
end

function Progression.start()
	local function setup(player: Player)
		if PlayerData.waitFor(player) then
			ensureQuests(player)
			player:SetAttribute("Level", Progression.levelOf(player))
		end
	end
	Players.PlayerAdded:Connect(function(player)
		task.spawn(setup, player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(setup, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		lastClaim[player] = nil
	end)
	-- roll over quests at midnight UTC for players who stay online
	while true do
		task.wait(60)
		for _, player in Players:GetPlayers() do
			ensureQuests(player)
		end
	end
end

return Progression
