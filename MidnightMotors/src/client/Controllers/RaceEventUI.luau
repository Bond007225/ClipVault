--!strict
-- Race event HUD: join banner (J to join), countdown, checkpoint beacons
-- (local-only parts), lap/checkpoint/position/timer panel and results.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)

local UI = require(script.Parent.UI)

local RaceEventUI = {}

local player = Players.LocalPlayer
local gui: ScreenGui
local banner: Frame
local bannerText: TextLabel
local joinButton: TextButton
local panel: Frame
local panelText: TextLabel
local big: TextLabel
local results: Frame
local resultsText: TextLabel
local markers: Folder

local status: any = nil
local statusAt = 0
local race: {
	checkpoints: { Vector3 },
	laps: number,
	radius: number,
	cp: number,
	lap: number,
	startAt: number?,
	countdownEnd: number,
	finished: boolean,
}? = nil

local function joined(): boolean
	return status ~= nil and status.joined ~= nil and table.find(status.joined, player.DisplayName) ~= nil
end

local function formatTime(t: number): string
	return string.format("%d:%04.1f", t // 60, t % 60)
end

----------------------------------------------------------------------
-- Checkpoint beacons
----------------------------------------------------------------------
local function beacon(pos: Vector3, radius: number, color: Color3, transparency: number, label: string?): Part
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(90, radius * 0.5, radius * 0.5)
	p.CFrame = CFrame.new(pos + Vector3.new(0, 45, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Transparency = transparency
	p.Parent = markers
	if label then
		local bb = Instance.new("BillboardGui")
		bb.Size = UDim2.fromOffset(160, 40)
		bb.StudsOffset = Vector3.new(0, 0, 0)
		bb.AlwaysOnTop = true
		bb.Parent = p
		local l = UI.label(bb, label, UDim2.fromScale(1, 1), UDim2.new(), 20, Color3.new(1, 1, 1), Enum.Font.GothamBlack)
		l.Name = "Label"
		l.TextStrokeTransparency = 0
	end
	return p
end

local function refreshMarkers()
	markers:ClearAllChildren()
	if not race or race.finished then
		return
	end
	local cps = race.checkpoints
	local isFinal = race.lap == race.laps and race.cp == #cps
	beacon(cps[race.cp], race.radius, if isFinal then Color3.fromRGB(255, 255, 255) else Color3.fromRGB(255, 200, 0), 0.35, if isFinal then "FINISH" else "CP " .. race.cp)
	local nextIndex = race.cp + 1
	if nextIndex > #cps and race.lap < race.laps then
		nextIndex = 1
	end
	if cps[nextIndex] and not isFinal then
		beacon(cps[nextIndex], race.radius * 0.7, Color3.fromRGB(255, 120, 0), 0.75, nil)
	end
end

----------------------------------------------------------------------
-- Event messages
----------------------------------------------------------------------
local function onUpdate(payload: any)
	if payload.type == "Status" then
		status = payload
		statusAt = os.clock()
	elseif payload.type == "Start" then
		race = {
			checkpoints = payload.checkpoints,
			laps = payload.laps,
			radius = payload.radius,
			cp = 1,
			lap = 1,
			startAt = nil,
			countdownEnd = os.clock() + payload.countdown,
			finished = false,
		}
		results.Visible = false
		refreshMarkers()
	elseif payload.type == "Go" and race then
		race.startAt = os.clock()
		big.Text = "GO!"
		big.TextColor3 = UI.Colors.Good
		big.Visible = true
		task.delay(1.2, function()
			if big.Text == "GO!" then
				big.Visible = false
			end
		end)
	elseif payload.type == "Checkpoint" and race then
		race.cp = payload.cp
		race.lap = payload.lap
		refreshMarkers()
	elseif payload.type == "Lap" and race then
		race.lap = payload.lap
		race.cp = 1
		refreshMarkers()
		big.Text = string.format("LAP %d/%d", payload.lap, payload.laps)
		big.TextColor3 = UI.Colors.Accent
		big.Visible = true
		task.delay(1.5, function()
			big.Visible = false
		end)
	elseif payload.type == "Finished" and race then
		race.finished = true
		refreshMarkers()
		big.Text = string.format("FINISHED P%d  %s", payload.place, formatTime(payload.time))
		big.TextColor3 = UI.Colors.Good
		big.Visible = true
		task.delay(3, function()
			big.Visible = false
		end)
	elseif payload.type == "Results" then
		race = nil
		refreshMarkers()
		local lines = { string.upper(payload.name or "Race") .. " RESULTS", "" }
		for i, r in payload.results do
			local t = if r.time then formatTime(r.time) else r.status
			table.insert(lines, string.format("%d. %s   %s", i, r.name, t))
		end
		resultsText.Text = table.concat(lines, "\n")
		results.Visible = true
		task.delay(10, function()
			results.Visible = false
		end)
	end
end

local function render()
	-- join banner while an event lobby is open
	local lobbyOpen = status and status.phase == "Lobby"
	banner.Visible = lobbyOpen == true and race == nil
	if lobbyOpen then
		local left = math.max(0, math.floor(status.endsIn - (os.clock() - statusAt)))
		local inIt = joined()
		bannerText.Text = string.format("RACE EVENT: %s  •  starts in %ds  •  %d joined", status.name, left, #status.joined)
		joinButton.Text = if inIt then "LEAVE (J)" else "JOIN (J)"
		joinButton.BackgroundColor3 = if inIt then UI.Colors.Bad else UI.Colors.Good
	end

	-- live race panel
	panel.Visible = race ~= nil and not race.finished
	if race then
		local now = os.clock()
		if not race.startAt then
			local left = math.ceil(race.countdownEnd - now)
			if left > 0 then
				big.Text = tostring(left)
				big.TextColor3 = UI.Colors.Warn
				big.Visible = true
			end
		end
		local elapsed = if race.startAt then now - race.startAt else 0
		local pos = player:GetAttribute("RacePosition") :: number?
		local count = player:GetAttribute("RaceCount") :: number?
		local cps = race.checkpoints
		local distText = ""
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root and cps[race.cp] then
			distText = string.format("  •  %dm", math.floor((root.Position - cps[race.cp]).Magnitude * 0.28))
		end
		panelText.Text = string.format(
			"LAP %d/%d\nCHECKPOINT %d/%d%s\nPOSITION %s\nTIME %s",
			race.lap,
			race.laps,
			race.cp,
			#cps,
			distText,
			if pos and count then string.format("%d/%d", pos, count) else "-",
			formatTime(elapsed)
		)
	end
end

function RaceEventUI.init()
	gui = Instance.new("ScreenGui")
	gui.Name = "RaceEvents"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 3
	gui.Parent = player:WaitForChild("PlayerGui")

	banner = UI.frame(gui, UDim2.fromOffset(560, 46), UDim2.new(0.5, -280, 1, -200), UI.Colors.Bg, 0.1)
	UI.corner(banner, 8)
	banner.Visible = false
	local stroke = Instance.new("UIStroke")
	stroke.Color = UI.Colors.Pink
	stroke.Thickness = 2
	stroke.Parent = banner
	bannerText = UI.label(banner, "", UDim2.new(1, -140, 1, 0), UDim2.fromOffset(12, 0), 14, UI.Colors.Text, Enum.Font.GothamBlack)
	bannerText.TextXAlignment = Enum.TextXAlignment.Left
	joinButton = UI.button(banner, "JOIN (J)", UDim2.fromOffset(110, 34), UDim2.new(1, -118, 0, 6), UI.Colors.Good, function()
		Remotes.event("EventJoin"):FireServer(not joined())
	end)

	panel = UI.frame(gui, UDim2.fromOffset(250, 104), UDim2.new(1, -266, 0, 124), UI.Colors.Bg, 0.2)
	UI.corner(panel, 8)
	panel.Visible = false
	panelText = UI.label(panel, "", UDim2.new(1, -20, 1, -12), UDim2.fromOffset(10, 6), 16, UI.Colors.Text, Enum.Font.GothamBlack)
	panelText.TextXAlignment = Enum.TextXAlignment.Left

	big = UI.label(gui, "", UDim2.fromOffset(700, 100), UDim2.new(0.5, -350, 0.22, 0), 72, UI.Colors.Warn, Enum.Font.GothamBlack)
	big.Visible = false

	results = UI.frame(gui, UDim2.fromOffset(340, 320), UDim2.new(0.5, -170, 0.25, 0), UI.Colors.Bg, 0.08)
	UI.corner(results, 10)
	results.Visible = false
	resultsText = UI.label(results, "", UDim2.new(1, -24, 1, -24), UDim2.fromOffset(12, 12), 17, UI.Colors.Text, Enum.Font.GothamBlack)
	resultsText.TextYAlignment = Enum.TextYAlignment.Top

	markers = Instance.new("Folder")
	markers.Name = "RaceMarkers"
	markers.Parent = workspace
end

function RaceEventUI.start()
	Remotes.event("EventUpdate").OnClientEvent:Connect(onUpdate)
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.J and status and status.phase == "Lobby" then
			Remotes.event("EventJoin"):FireServer(not joined())
		end
	end)
	RunService.RenderStepped:Connect(render)
end

-- exposed for the smoke-test harness
RaceEventUI._onUpdate = onUpdate
RaceEventUI._render = render

return RaceEventUI
