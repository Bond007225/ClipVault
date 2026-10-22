--!strict
-- Receives raw trick reports, validates them, scores them server-side and runs the
-- combo system. Combos bank automatically after a few seconds without a new trick;
-- crashing loses the pending combo.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Tricks = require(Shared.Tricks)

local DataService = require(script.Parent.DataService)
local SnowboardService = require(script.Parent.SnowboardService)
local RagdollService = require(script.Parent.RagdollService)
local RateLimiter = require(script.Parent.RateLimiter)

local TrickService = {}

type Combo = {
	count: number,
	base: number,
	lastTrickAt: number,
	lastReportAt: number,
}

local combos: { [Player]: Combo } = {}
local reportLimiter = RateLimiter.new(8, 3)
local crashLimiter = RateLimiter.new(2, 0.5)

local trickAwarded: RemoteEvent
local comboUpdate: RemoteEvent

local function getCombo(player: Player): Combo
	local c = combos[player]
	if not c then
		c = { count = 0, base = 0, lastTrickAt = 0, lastReportAt = 0 }
		combos[player] = c
	end
	return c
end

local function bank(player: Player, c: Combo)
	if c.count == 0 then
		return
	end
	local total = math.floor(c.base * Tricks.multiplier(c.count))
	local count = c.count
	c.count = 0
	c.base = 0
	DataService.awardTrickPoints(player, total)
	comboUpdate:FireClient(player, { state = "Banked", total = total, count = count })
end

function TrickService.loseCombo(player: Player)
	local c = combos[player]
	if c and c.count > 0 then
		c.count = 0
		c.base = 0
		comboUpdate:FireClient(player, { state = "Lost" })
	end
end

local function onTrick(player: Player, raw: any)
	if not reportLimiter:take(player) then
		return
	end
	local character = player.Character
	if not character or not SnowboardService.isRiding(player) or RagdollService.isRagdolled(character) then
		return
	end
	local report = Tricks.sanitize(raw)
	if not report then
		return
	end

	local now = os.clock()
	local c = getCombo(player)
	-- Two reports can't claim overlapping time in the air / on a rail.
	if now - c.lastReportAt < Tricks.claimedDuration(report) * 0.7 then
		return
	end
	c.lastReportAt = now

	if c.count > 0 and now - c.lastTrickAt > Config.Tricks.ComboWindow then
		bank(player, c)
	end

	local points = Tricks.score(report)
	c.count += 1
	c.base += points
	c.lastTrickAt = now

	trickAwarded:FireClient(player, {
		name = Tricks.describe(report),
		points = points,
		count = c.count,
		multiplier = Tricks.multiplier(c.count),
		pending = math.floor(c.base * Tricks.multiplier(c.count)),
	})
end

local function onCrash(player: Player)
	if not crashLimiter:take(player) then
		return
	end
	local character = player.Character
	if not character or not SnowboardService.isRiding(player) or RagdollService.isRagdolled(character) then
		return
	end
	TrickService.loseCombo(player)
	TrickService.wipeout(player, Config.Ragdoll.CrashDuration)
end

-- Knock a riding player off their board (crash or snowball hit).
function TrickService.wipeout(player: Player, duration: number)
	local character = player.Character
	if not character then
		return
	end
	RagdollService.ragdoll(character, duration)
	if SnowboardService.isRiding(player) then
		TrickService.loseCombo(player)
		SnowboardService.dropBoard(player, duration)
	end
end

function TrickService.start()
	trickAwarded = Remotes.event("TrickAwarded")
	comboUpdate = Remotes.event("ComboUpdate")

	Remotes.event("TrickLanded").OnServerEvent:Connect(onTrick)
	Remotes.event("Crash").OnServerEvent:Connect(onCrash)

	DataService.onRelease(function(player)
		local c = combos[player]
		if c then
			bank(player, c)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		combos[player] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(0.25)
			local now = os.clock()
			for player, c in combos do
				if c.count > 0 and now - c.lastTrickAt > Config.Tricks.ComboWindow then
					bank(player, c)
				end
			end
		end
	end)
end

return TrickService
