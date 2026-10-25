--!strict
-- Quarter-mile and half-mile drag strips. Roll into a lane's staging box and
-- sit still to stage; a second racer has a few seconds to stage in the other
-- lane. Then the christmas tree counts down (3 ambers, green). Leaving early
-- is a red light. Elapsed time (ET), reaction time and trap speed are
-- measured on the server.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)

local PlayerData = require(script.Parent.PlayerData)
local MapBuilder = require(script.Parent.MapBuilder)

local Racing = {}

local R = Config.Racing
local OFF = Color3.fromRGB(35, 35, 35)
local TIMEOUT = 45

type Racer = {
	player: Player,
	car: Model,
	chassis: BasePart,
	laneIndex: number,
	lastX: number,
	reaction: number?,
	et: number?,
	trap: number?,
	result: string?, -- nil while running, else "Finished" | "Red light" | "DQ" | "DNF"
}

type StripState = {
	strip: MapBuilder.Strip,
	status: string, -- Idle | Staging | Countdown | Racing | Cooldown
	stageTimers: { number },
	stagedBy: { Player? },
	timer: number,
	treeStep: number,
	greenAt: number,
	racers: { Racer },
	record: { name: string, et: number }?,
}

local states: { StripState } = {}

local function light(part: BasePart, on: boolean)
	if on then
		part.Color = part:GetAttribute("OnColor") :: Color3
		part.Material = Enum.Material.Neon
	else
		part.Color = OFF
		part.Material = Enum.Material.SmoothPlastic
	end
end

local function resetTree(st: StripState)
	for _, lane in st.strip.Lanes do
		local t = lane.Tree
		light(t.Stage, false)
		light(t.Green, false)
		light(t.Red, false)
		for _, a in t.Amber do
			light(a, false)
		end
	end
end

local function fire(st: StripState, payload: { [string]: any })
	payload.strip = st.strip.Name
	for _, r in st.racers do
		Remotes.event("RaceUpdate"):FireClient(r.player, payload)
	end
end

-- Player car currently driven by someone and sitting in the given lane's staging box
local function carInStage(st: StripState, laneIndex: number): (Player?, Model?, BasePart?)
	local lane = st.strip.Lanes[laneIndex]
	local vehicles = workspace:FindFirstChild("Vehicles")
	local folder = vehicles and vehicles:FindFirstChild("Players")
	if not folder then
		return nil, nil, nil
	end
	for _, car in folder:GetChildren() do
		if not car:IsA("Model") then
			continue
		end
		local driverId = car:GetAttribute("Driver") :: number?
		local chassis = car:FindFirstChild("Chassis") :: BasePart?
		if driverId and chassis then
			local p = chassis.Position
			if p.X > st.strip.StartX - 18 and p.X < st.strip.StartX - 1 and math.abs(p.Z - lane.Z) < 7 then
				return Players:GetPlayerByUserId(driverId), car, chassis
			end
		end
	end
	return nil, nil, nil
end

local function boardText(st: StripState): string
	local lines = { string.upper(st.strip.Name) .. " MILE" }
	for i, r in st.racers do
		local laneName = if r.laneIndex == 1 then "L" else "R"
		if r.et then
			table.insert(lines, string.format("%s %s  %.3fs @ %d MPH", laneName, r.player.DisplayName, r.et, math.floor(r.trap or 0)))
		else
			table.insert(lines, string.format("%s %s  %s", laneName, r.player.DisplayName, r.result or "--"))
		end
		if i >= 2 then
			break
		end
	end
	if st.record then
		table.insert(lines, string.format("RECORD %.3fs %s", st.record.et, st.record.name))
	end
	return table.concat(lines, "\n")
end

local function finishRace(st: StripState)
	local payout = R.Payout[st.strip.Name]
	local finishers = {}
	for _, r in st.racers do
		if r.result == "Finished" and r.et then
			table.insert(finishers, r)
		end
	end
	table.sort(finishers, function(a, b)
		return (a.et :: number) < (b.et :: number)
	end)
	for _, r in st.racers do
		local place = table.find(finishers, r)
		local cash = 0
		local isPb = false
		if r.result == "Finished" and r.et then
			cash = payout.Base
			if place == 1 and #st.racers > 1 then
				cash += payout.WinBonus
				PlayerData.bumpStat(r.player, "Wins", 1)
			end
			local profile = PlayerData.get(r.player)
			if profile then
				local best = profile.Best[st.strip.Name]
				if not best or r.et < best then
					profile.Best[st.strip.Name] = r.et
					isPb = true
				end
			end
			if not st.record or r.et < st.record.et then
				st.record = { name = r.player.DisplayName, et = r.et }
				cash += R.RecordBonus
			end
		end
		PlayerData.bumpStat(r.player, "Races", 1)
		if cash > 0 then
			PlayerData.addCash(r.player, cash, st.strip.Name .. " mile run")
		end
		Remotes.event("RaceUpdate"):FireClient(r.player, {
			type = "Result",
			strip = st.strip.Name,
			result = r.result,
			et = r.et,
			trap = r.trap,
			reaction = r.reaction,
			place = place,
			racers = #st.racers,
			pb = isPb,
			payout = cash,
		})
	end
	st.strip.Board.Text = boardText(st)
	st.status = "Cooldown"
	st.timer = 4
end

local function updateStrip(st: StripState, dt: number)
	local strip = st.strip
	if st.status == "Idle" or st.status == "Staging" then
		for i = 1, 2 do
			local player, car, chassis = carInStage(st, i)
			local tree = strip.Lanes[i].Tree
			if player and car and chassis and chassis.AssemblyLinearVelocity.Magnitude < 3 then
				st.stageTimers[i] += dt
				if st.stageTimers[i] >= R.StageHoldTime and st.stagedBy[i] ~= player then
					st.stagedBy[i] = player
					light(tree.Stage, true)
					Remotes.event("RaceUpdate"):FireClient(player, { type = "Staged", strip = strip.Name })
					if st.status == "Idle" then
						st.status = "Staging"
						st.timer = R.OpponentWait
					end
				end
			elseif not player then
				st.stageTimers[i] = 0
				if st.stagedBy[i] then
					st.stagedBy[i] = nil
					light(tree.Stage, false)
				end
			end
		end
		if st.status == "Staging" then
			st.timer -= dt
			local both = st.stagedBy[1] and st.stagedBy[2]
			local any = st.stagedBy[1] or st.stagedBy[2]
			if not any then
				st.status = "Idle"
			elseif both or st.timer <= 0 then
				-- lock in racers and start the tree
				st.racers = {}
				for i = 1, 2 do
					local player, car, chassis = carInStage(st, i)
					if player and car and chassis and st.stagedBy[i] == player then
						table.insert(st.racers, {
							player = player,
							car = car,
							chassis = chassis,
							laneIndex = i,
							lastX = chassis.Position.X,
						})
					end
				end
				if #st.racers == 0 then
					st.status = "Idle"
					resetTree(st)
					return
				end
				st.status = "Countdown"
				st.timer = 0
				st.treeStep = 0
			end
		end
	elseif st.status == "Countdown" then
		st.timer += dt
		local step = math.floor(st.timer / R.AmberInterval) + 1
		if step > st.treeStep then
			st.treeStep = step
			for _, r in st.racers do
				local tree = strip.Lanes[r.laneIndex].Tree
				if step <= 3 then
					light(tree.Amber[step], true)
				end
			end
			if step >= 4 then
				st.greenAt = os.clock()
				st.status = "Racing"
				for _, r in st.racers do
					local tree = strip.Lanes[r.laneIndex].Tree
					for _, a in tree.Amber do
						light(a, false)
					end
					if not r.result then
						light(tree.Green, true)
					end
				end
				fire(st, { type = "Tree", step = 4 })
				return
			end
			fire(st, { type = "Tree", step = step })
		end
		-- red light: moving past the start line before green
		for _, r in st.racers do
			if not r.result and r.chassis.Position.X > strip.StartX then
				r.result = "Red light"
				light(strip.Lanes[r.laneIndex].Tree.Red, true)
			end
		end
	elseif st.status == "Racing" then
		local now = os.clock()
		local running = 0
		for _, r in st.racers do
			if r.result then
				continue
			end
			local chassis = r.chassis
			if not chassis.Parent or r.car:GetAttribute("Driver") ~= r.player.UserId then
				r.result = "DNF"
				continue
			end
			local x = chassis.Position.X
			local lane = strip.Lanes[r.laneIndex]
			if math.abs(chassis.Position.Z - lane.Z) > 12 then
				r.result = "DQ"
				continue
			end
			if not r.reaction and x > strip.StartX - 1 then
				r.reaction = now - st.greenAt
			end
			if x >= strip.FinishX then
				-- interpolate the crossing within this frame
				local frac = if x > r.lastX then (strip.FinishX - r.lastX) / (x - r.lastX) else 1
				r.et = (now - dt * (1 - frac)) - st.greenAt
				r.trap = chassis.AssemblyLinearVelocity.Magnitude * Config.STUDS_TO_MPH
				r.result = "Finished"
				continue
			end
			r.lastX = x
			running += 1
		end
		if running == 0 or now - st.greenAt > TIMEOUT then
			for _, r in st.racers do
				r.result = r.result or "DNF"
			end
			finishRace(st)
		end
	elseif st.status == "Cooldown" then
		st.timer -= dt
		if st.timer <= 0 then
			st.status = "Idle"
			st.racers = {}
			st.stagedBy = {}
			st.stageTimers = { 0, 0 }
			resetTree(st)
		end
	end
end

function Racing.init() end

function Racing.start()
	for _, strip in MapBuilder.Layout.Strips do
		local st: StripState = {
			strip = strip,
			status = "Idle",
			stageTimers = { 0, 0 },
			stagedBy = {},
			timer = 0,
			treeStep = 0,
			greenAt = 0,
			racers = {},
			record = nil,
		}
		resetTree(st)
		table.insert(states, st)
	end
	RunService.Heartbeat:Connect(function(dt)
		for _, st in states do
			updateStrip(st, dt)
		end
	end)
end

return Racing
