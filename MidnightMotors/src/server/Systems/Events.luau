--!strict
-- Race events. Every few minutes an event opens a join window; players join
-- from the menu. When the window closes, every racer's car is frozen on a grid
-- slot, a countdown runs, then they race through checkpoints. Positions are
-- tracked live and the top three (plus every finisher) get paid.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)

local PlayerData = require(script.Parent.PlayerData)
local MapBuilder = require(script.Parent.MapBuilder)
local CarService = require(script.Parent.CarService)

local Events = {}

local E = Config.Events
local TICK = 0.1

type Racer = {
	player: Player,
	car: Model?,
	cp: number, -- index of the next checkpoint
	lap: number,
	finished: boolean,
	dnf: boolean,
	time: number?,
	place: number?,
}

type State = {
	phase: string, -- "Idle" | "Lobby" | "Countdown" | "Racing"
	eventId: string?,
	route: MapBuilder.EventRoute?,
	joined: { Player },
	racers: { Racer },
	phaseEnds: number,
	startedAt: number,
	finishedCount: number,
	nextIndex: number,
}

local state: State = {
	phase = "Idle",
	eventId = nil,
	route = nil,
	joined = {},
	racers = {},
	phaseEnds = 0,
	startedAt = 0,
	finishedCount = 0,
	nextIndex = 1,
}

local function info(id: string?): { Name: string, Desc: string }
	return if id then E.Info[id] else { Name = "", Desc = "" }
end

-- Status everyone can see (menu Events tab + HUD banner)
local function broadcastStatus()
	local names = {}
	for _, p in state.joined do
		table.insert(names, p.DisplayName)
	end
	Remotes.event("EventUpdate"):FireAllClients({
		type = "Status",
		phase = state.phase,
		eventId = state.eventId,
		name = info(state.eventId).Name,
		desc = info(state.eventId).Desc,
		endsIn = math.max(0, state.phaseEnds - os.clock()),
		joined = names,
		maxRacers = E.MaxRacers,
	})
end

local function sendTo(player: Player, payload: { [string]: any })
	payload.eventId = state.eventId
	payload.name = info(state.eventId).Name
	Remotes.event("EventUpdate"):FireClient(player, payload)
end

local function setInEvent(player: Player, on: boolean)
	player:SetAttribute("InEvent", if on then true else nil)
end

local function resetToIdle()
	for _, r in state.racers do
		setInEvent(r.player, false)
		if r.car and r.car.Parent and r.car:GetAttribute("Frozen") then
			CarService.release(r.player, r.car)
		end
	end
	state.phase = "Idle"
	state.eventId = nil
	state.route = nil
	state.joined = {}
	state.racers = {}
	state.finishedCount = 0
	state.phaseEnds = os.clock() + E.Interval
	broadcastStatus()
end

local function openLobby()
	local id = E.Order[state.nextIndex]
	state.nextIndex = state.nextIndex % #E.Order + 1
	local route = MapBuilder.Layout.EventRoutes[id]
	if not route then
		state.phaseEnds = os.clock() + E.Interval
		return
	end
	state.phase = "Lobby"
	state.eventId = id
	state.route = route
	state.joined = {}
	state.phaseEnds = os.clock() + E.LobbyTime
	broadcastStatus()
	Remotes.event("Notify"):FireAllClients(string.format("RACE EVENT: %s starts in %ds. Open the menu (G) to join!", info(id).Name, E.LobbyTime), "info")
end

local function startCountdown()
	local route = state.route :: MapBuilder.EventRoute
	state.racers = {}
	for i, player in state.joined do
		if not player.Parent then
			continue
		end
		local slot = route.Grid[math.min(i, #route.Grid)]
		local car = CarService.placeOnGrid(player, slot)
		if car then
			table.insert(state.racers, {
				player = player,
				car = car,
				cp = 1,
				lap = 1,
				finished = false,
				dnf = false,
				time = nil,
				place = nil,
			})
			setInEvent(player, true)
		else
			Remotes.event("Notify"):FireClient(player, "Couldn't get your car to the start grid.", "warn")
		end
	end
	if #state.racers == 0 then
		resetToIdle()
		return
	end
	state.phase = "Countdown"
	state.phaseEnds = os.clock() + E.CountdownTime
	for _, r in state.racers do
		sendTo(r.player, {
			type = "Start",
			checkpoints = route.Checkpoints,
			laps = route.Laps,
			radius = route.Radius,
			countdown = E.CountdownTime,
			racers = #state.racers,
		})
	end
	broadcastStatus()
end

local function go()
	state.phase = "Racing"
	state.startedAt = os.clock()
	state.phaseEnds = state.startedAt + (state.route :: MapBuilder.EventRoute).TimeLimit
	for _, r in state.racers do
		if r.car then
			CarService.release(r.player, r.car)
		end
		sendTo(r.player, { type = "Go" })
	end
	broadcastStatus()
end

local function progressScore(r: Racer, route: MapBuilder.EventRoute): number
	if r.finished then
		return 1e9 - (r.place or 0)
	end
	local cp = route.Checkpoints[r.cp]
	local dist = 0
	local chassis = r.car and r.car:FindFirstChild("Chassis") :: BasePart?
	if chassis and cp then
		dist = (chassis.Position - cp).Magnitude
	end
	return (r.lap * #route.Checkpoints + r.cp) * 100000 - dist
end

local function finishRace()
	local results = {}
	local sorted = table.clone(state.racers)
	local route = state.route :: MapBuilder.EventRoute
	table.sort(sorted, function(a, b)
		return progressScore(a, route) > progressScore(b, route)
	end)
	for _, r in sorted do
		table.insert(results, {
			name = r.player.DisplayName,
			place = r.place,
			time = r.time,
			status = if r.finished then "Finished" else "DNF",
		})
	end
	for _, r in state.racers do
		if r.player.Parent then
			sendTo(r.player, { type = "Results", results = results, place = r.place, time = r.time })
		end
	end
	resetToIdle()
end

local function updateRace()
	local route = state.route :: MapBuilder.EventRoute
	local running = 0
	for _, r in state.racers do
		if r.finished or r.dnf then
			continue
		end
		if not r.player.Parent then
			r.dnf = true
			continue
		end
		running += 1
		local car = CarService.getDrivenCar(r.player)
		local chassis = car and car:FindFirstChild("Chassis") :: BasePart?
		if not chassis then
			continue -- out of the car: no progress until they get back in
		end
		local target = route.Checkpoints[r.cp]
		if (chassis.Position - target).Magnitude < route.Radius then
			r.cp += 1
			if r.cp > #route.Checkpoints then
				if r.lap < route.Laps then
					r.lap += 1
					r.cp = 1
					sendTo(r.player, { type = "Lap", lap = r.lap, laps = route.Laps })
				else
					state.finishedCount += 1
					r.finished = true
					r.place = state.finishedCount
					r.time = os.clock() - state.startedAt
					local pay = E.FinishPay + (E.Payouts[state.finishedCount] or 0)
					PlayerData.addCash(r.player, pay, string.format("%s - P%d", info(state.eventId).Name, state.finishedCount))
					if state.finishedCount == 1 then
						PlayerData.bumpStat(r.player, "EventWins", 1)
					end
					sendTo(r.player, { type = "Finished", place = r.place, time = r.time })
					setInEvent(r.player, false)
					continue
				end
			end
			sendTo(r.player, { type = "Checkpoint", cp = r.cp, total = #route.Checkpoints, lap = r.lap })
		end
	end

	-- live standings
	local order = table.clone(state.racers)
	table.sort(order, function(a, b)
		return progressScore(a, route) > progressScore(b, route)
	end)
	for i, r in order do
		if not r.finished and r.player.Parent then
			r.player:SetAttribute("RacePosition", i)
			r.player:SetAttribute("RaceCount", #order)
		end
	end

	if running == 0 or os.clock() > state.phaseEnds then
		for _, r in state.racers do
			r.player:SetAttribute("RacePosition", nil)
		end
		finishRace()
	end
end

local function onJoin(player: Player, join: unknown)
	if typeof(join) ~= "boolean" then
		return
	end
	if state.phase ~= "Lobby" then
		Remotes.event("Notify"):FireClient(player, "No event is open right now. Watch for the next one!", "warn")
		return
	end
	local idx = table.find(state.joined, player)
	if join and not idx then
		if ((player:GetAttribute("Heat") :: number?) or 0) > 0 then
			Remotes.event("Notify"):FireClient(player, "Lose the police before joining a race.", "warn")
			return
		end
		if #state.joined >= E.MaxRacers then
			Remotes.event("Notify"):FireClient(player, "This event is full.", "warn")
			return
		end
		table.insert(state.joined, player)
		Remotes.event("Notify"):FireClient(player, "Joined " .. info(state.eventId).Name .. "! You'll be moved to the start grid.", "money")
	elseif not join and idx then
		table.remove(state.joined, idx)
	end
	broadcastStatus()
end

function Events.init()
	Remotes.event("EventJoin").OnServerEvent:Connect(onJoin)
end

function Events.start()
	state.phaseEnds = os.clock() + E.FirstDelay
	Players.PlayerRemoving:Connect(function(player)
		local idx = table.find(state.joined, player)
		if idx then
			table.remove(state.joined, idx)
		end
	end)
	Players.PlayerAdded:Connect(function()
		task.wait(3)
		broadcastStatus()
	end)
	local statusTimer = 0
	while true do
		task.wait(TICK)
		local now = os.clock()
		if state.phase == "Idle" then
			if now >= state.phaseEnds then
				openLobby()
			end
		elseif state.phase == "Lobby" then
			if now >= state.phaseEnds then
				if #state.joined == 0 then
					resetToIdle()
				else
					startCountdown()
				end
			end
		elseif state.phase == "Countdown" then
			if now >= state.phaseEnds then
				go()
			end
		elseif state.phase == "Racing" then
			updateRace()
		end
		statusTimer += TICK
		if statusTimer >= 5 then
			statusTimer = 0
			broadcastStatus()
		end
	end
end

-- exposed for the smoke-test harness
Events._state = state
Events._force = function(id: string)
	state.nextIndex = table.find(E.Order, id) or 1
	openLobby()
end

return Events
