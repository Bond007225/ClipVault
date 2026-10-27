--!strict
-- Main menu (G key, HUD button, or a garage terminal): shop for cars, spawn
-- the cars you own, install performance upgrades, paint & body kits, free
-- tuning, and join race events. All purchases are requests; the server
-- validates price, ownership and whether you're allowed right now.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local CarStats = require(Shared.CarStats)
local Remotes = require(Shared.Remotes)

local UI = require(script.Parent.UI)

local GarageUI = {}

local player = Players.LocalPlayer
local gui: ScreenGui
local root: Frame
local content: ScrollingFrame
local statsPanel: Frame
local tab = "My Cars"
local profile: any = nil
local eventStatus: any = nil
local eventStatusAt = 0

local TABS = { "Shop", "My Cars", "Performance", "Visual", "Tuning", "Events" }

local function clear(frame: Instance)
	for _, c in frame:GetChildren() do
		if not c:IsA("UIListLayout") and not c:IsA("UIPadding") then
			c:Destroy()
		end
	end
end

local function row(height: number): Frame
	local f = UI.frame(content, UDim2.new(1, -12, 0, height), UDim2.new(), UI.Colors.Panel)
	UI.corner(f)
	return f
end

local function selectedData(): (string?, any)
	if not profile then
		return nil, nil
	end
	return profile.Selected, profile.Cars[profile.Selected]
end

----------------------------------------------------------------------
-- Tabs
----------------------------------------------------------------------
local function carRow(carId: string): Frame
	local def = Config.Cars[carId]
	local data = profile.Cars[carId]
	local stats = CarStats.compute(carId, data)
	local f = row(76)
	local name = UI.label(f, def.Name, UDim2.new(0.6, 0, 0, 26), UDim2.fromOffset(12, 6), 20, UI.Colors.Text, Enum.Font.GothamBlack)
	name.TextXAlignment = Enum.TextXAlignment.Left
	local info = UI.label(
		f,
		string.format("Class %s (%d)  •  %s  •  %d mph  •  %s lbs", stats.Class, stats.Rating, def.Drivetrain, math.floor(stats.TopSpeedMph), tostring(def.Weight)),
		UDim2.new(0.65, 0, 0, 20),
		UDim2.fromOffset(12, 34),
		13,
		UI.Colors.Dim
	)
	info.TextXAlignment = Enum.TextXAlignment.Left
	return f
end

local function renderShop()
	local order = table.clone(Config.CarOrder)
	table.sort(order, function(a, b)
		return Config.Cars[a].Price < Config.Cars[b].Price
	end)
	for _, carId in order do
		local def = Config.Cars[carId]
		local f = carRow(carId)
		if profile.Cars[carId] then
			UI.label(f, "OWNED", UDim2.fromOffset(130, 40), UDim2.new(1, -142, 0, 18), 16, UI.Colors.Good, Enum.Font.GothamBlack)
		else
			local afford = profile.Cash >= def.Price
			UI.button(f, "Buy " .. UI.money(def.Price), UDim2.fromOffset(130, 40), UDim2.new(1, -142, 0, 18), if afford then UI.Colors.Good else Color3.fromRGB(80, 80, 90), function()
				Remotes.event("BuyCar"):FireServer(carId)
			end)
		end
	end
end

local function renderMyCars()
	for _, carId in Config.CarOrder do
		if profile.Cars[carId] then
			local f = carRow(carId)
			local selected = profile.Selected == carId
			if selected then
				UI.label(f, "SELECTED", UDim2.fromOffset(100, 20), UDim2.new(1, -250, 0, 28), 13, UI.Colors.Pink, Enum.Font.GothamBlack)
			end
			UI.button(f, "Spawn", UDim2.fromOffset(130, 40), UDim2.new(1, -142, 0, 18), UI.Colors.Accent, function()
				Remotes.event("SpawnCar"):FireServer(carId)
				GarageUI.close()
			end)
		end
	end
	local hint = row(46)
	UI.label(hint, "Spawning puts your car on the nearest road. Upgrades and paint apply to the SELECTED car.", UDim2.new(1, -24, 1, 0), UDim2.fromOffset(12, 0), 12, UI.Colors.Dim)
end

local function renderEvents()
	local st = eventStatus
	if st then
		st = table.clone(st)
		st.endsIn = math.max(0, st.endsIn - (os.clock() - eventStatusAt))
	end
	local f = row(150)
	if not st or st.phase == "Idle" or not st.eventId then
		local secs = if st then math.floor(st.endsIn) else 0
		UI.label(f, "NEXT RACE EVENT", UDim2.new(1, -24, 0, 30), UDim2.fromOffset(12, 10), 20, UI.Colors.Accent, Enum.Font.GothamBlack)
		UI.label(f, if st then string.format("Opens in %d:%02d", secs // 60, secs % 60) else "Waiting for the server...", UDim2.new(1, -24, 0, 30), UDim2.fromOffset(12, 50), 18, UI.Colors.Text)
	else
		local joined = table.find(st.joined, player.DisplayName) ~= nil
		local title = UI.label(f, string.upper(st.name), UDim2.new(1, -170, 0, 30), UDim2.fromOffset(12, 10), 22, UI.Colors.Pink, Enum.Font.GothamBlack)
		title.TextXAlignment = Enum.TextXAlignment.Left
		local desc = UI.label(f, st.desc, UDim2.new(1, -170, 0, 36), UDim2.fromOffset(12, 42), 13, UI.Colors.Dim)
		desc.TextXAlignment = Enum.TextXAlignment.Left
		local status = if st.phase == "Lobby"
			then string.format("Join window closes in %ds  •  %d/%d racers", math.floor(st.endsIn), #st.joined, st.maxRacers)
			else "Race in progress"
		local sl = UI.label(f, status, UDim2.new(1, -170, 0, 22), UDim2.fromOffset(12, 84), 15, UI.Colors.Text)
		sl.TextXAlignment = Enum.TextXAlignment.Left
		local names = UI.label(f, table.concat(st.joined, ", "), UDim2.new(1, -170, 0, 36), UDim2.fromOffset(12, 108), 12, UI.Colors.Dim)
		names.TextXAlignment = Enum.TextXAlignment.Left
		if st.phase == "Lobby" then
			UI.button(f, if joined then "Leave" else "JOIN RACE", UDim2.fromOffset(140, 50), UDim2.new(1, -152, 0, 50), if joined then UI.Colors.Bad else UI.Colors.Good, function()
				Remotes.event("EventJoin"):FireServer(not joined)
			end)
		end
	end
	for _, id in Config.Events.Order do
		local i = Config.Events.Info[id]
		local r = row(56)
		local t = UI.label(r, i.Name, UDim2.new(1, -24, 0, 22), UDim2.fromOffset(12, 6), 16, UI.Colors.Text, Enum.Font.GothamBlack)
		t.TextXAlignment = Enum.TextXAlignment.Left
		local d = UI.label(r, i.Desc, UDim2.new(1, -24, 0, 20), UDim2.fromOffset(12, 30), 12, UI.Colors.Dim)
		d.TextXAlignment = Enum.TextXAlignment.Left
	end
	local pays = Config.Events.Payouts
	local note = row(40)
	UI.label(note, string.format("Payouts: 1st %s  •  2nd %s  •  3rd %s  •  every finisher +%s", UI.money(pays[1]), UI.money(pays[2]), UI.money(pays[3]), UI.money(Config.Events.FinishPay)), UDim2.new(1, -24, 1, 0), UDim2.fromOffset(12, 0), 13, UI.Colors.Good)
end

local function renderPerformance()
	local _, data = selectedData()
	if not data then
		return
	end
	for _, cat in Config.UpgradeOrder do
		local def = Config.Upgrades[cat]
		local tier = data.Upgrades[cat] or 1
		local f = row(84)
		local title = UI.label(f, def.Name .. "  —  " .. def.Tiers[tier].Name, UDim2.new(0.6, 0, 0, 24), UDim2.fromOffset(12, 6), 18, UI.Colors.Text, Enum.Font.GothamBlack)
		title.TextXAlignment = Enum.TextXAlignment.Left
		local desc = UI.label(f, def.Desc, UDim2.new(0.62, 0, 0, 30), UDim2.fromOffset(12, 30), 12, UI.Colors.Dim)
		desc.TextXAlignment = Enum.TextXAlignment.Left
		desc.TextYAlignment = Enum.TextYAlignment.Top
		-- tier pips (click a lower one to downgrade for free)
		for i = 1, #def.Tiers do
			local pip = UI.button(f, "", UDim2.fromOffset(26, 10), UDim2.fromOffset(12 + (i - 1) * 30, 64), if i <= tier then UI.Colors.Accent else Color3.fromRGB(60, 60, 70), function()
				if i < tier then
					Remotes.event("BuyUpgrade"):FireServer(cat, i)
				end
			end)
			pip.AutoButtonColor = i < tier
		end
		if tier < #def.Tiers then
			local nextTier = def.Tiers[tier + 1]
			local afford = profile.Cash >= nextTier.Price
			UI.button(f, string.format("%s\n%s", nextTier.Name, UI.money(nextTier.Price)), UDim2.fromOffset(130, 52), UDim2.new(1, -142, 0, 16), if afford then UI.Colors.Good else Color3.fromRGB(80, 80, 90), function()
				Remotes.event("BuyUpgrade"):FireServer(cat, tier + 1)
			end)
		else
			UI.label(f, "MAXED", UDim2.fromOffset(130, 52), UDim2.new(1, -142, 0, 16), 18, UI.Colors.Pink, Enum.Font.GothamBlack)
		end
	end
end

local function renderVisual()
	local _, data = selectedData()
	if not data then
		return
	end
	local function optionRow(key: string, title: string, options: { { name: string, color: Color3? } })
		local price = Config.CosmeticPrices[key]
		local f = row(96)
		local t = UI.label(f, string.format("%s  (%s each)", title, UI.money(price)), UDim2.new(1, -24, 0, 22), UDim2.fromOffset(12, 6), 16, UI.Colors.Text, Enum.Font.GothamBlack)
		t.TextXAlignment = Enum.TextXAlignment.Left
		local holder = Instance.new("ScrollingFrame")
		holder.Size = UDim2.new(1, -24, 0, 60)
		holder.Position = UDim2.fromOffset(12, 30)
		holder.BackgroundTransparency = 1
		holder.BorderSizePixel = 0
		holder.ScrollBarThickness = 4
		holder.ScrollingDirection = Enum.ScrollingDirection.X
		holder.AutomaticCanvasSize = Enum.AutomaticSize.X
		holder.CanvasSize = UDim2.new()
		holder.Parent = f
		local layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Horizontal
		layout.Padding = UDim.new(0, 6)
		layout.Parent = holder
		for _, opt in options do
			local current = data.Cosmetics[key] == opt.name
			local b = UI.button(holder, if opt.color then "" else opt.name, UDim2.fromOffset(if opt.color then 48 else 96, 48), UDim2.new(), opt.color or Color3.fromRGB(50, 50, 62), function()
				Remotes.event("SetCosmetic"):FireServer(key, opt.name)
			end)
			if opt.color then
				b.Text = if current then "✔" else ""
				b.TextStrokeTransparency = 0
			end
			if current then
				local s = Instance.new("UIStroke")
				s.Color = UI.Colors.Pink
				s.Thickness = 3
				s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
				s.Parent = b
			end
		end
	end
	local function named(list: { any }, withColor: boolean): { { name: string, color: Color3? } }
		local out = {}
		for _, o in list do
			table.insert(out, { name = o.Name, color = if withColor then o.Color else nil })
		end
		return out
	end
	optionRow("Paint", "Paint", named(Config.Paints, true))
	optionRow("Finish", "Finish", named(Config.Finishes, false))
	optionRow("Rims", "Rim Color", named(Config.RimColors, true))
	local glows = {}
	for _, g in Config.Underglows do
		table.insert(glows, { name = g.Name, color = g.Color })
	end
	optionRow("Underglow", "Underglow (Off = grey)", glows)
	local spoilers = {}
	for _, s in Config.Spoilers do
		table.insert(spoilers, { name = s })
	end
	optionRow("Spoiler", "Spoiler / Body Kit", spoilers)
	optionRow("Tint", "Window Tint", named(Config.Tints, false))
end

local function renderTuning()
	local _, data = selectedData()
	if not data then
		return
	end
	for _, key in Config.TuningOrder do
		local spec = Config.Tuning[key]
		local value = data.Tuning[key] or spec.Default
		local f = row(60)
		local t = UI.label(f, spec.Label, UDim2.new(0.5, 0, 1, 0), UDim2.fromOffset(12, 0), 16, UI.Colors.Text, Enum.Font.GothamBlack)
		t.TextXAlignment = Enum.TextXAlignment.Left
		UI.button(f, "−", UDim2.fromOffset(40, 40), UDim2.new(1, -190, 0, 10), Color3.fromRGB(60, 60, 75), function()
			Remotes.event("SetTuning"):FireServer(key, value - spec.Step)
		end)
		UI.label(f, string.format("%.2f", value), UDim2.fromOffset(90, 40), UDim2.new(1, -146, 0, 10), 18, UI.Colors.Accent, Enum.Font.GothamBlack)
		UI.button(f, "+", UDim2.fromOffset(40, 40), UDim2.new(1, -52, 0, 10), Color3.fromRGB(60, 60, 75), function()
			Remotes.event("SetTuning"):FireServer(key, value + spec.Step)
		end)
	end
	local note = row(46)
	UI.label(note, "Tuning is free. Lower + stiffer = more grip on smooth tarmac. Gearing + = quicker launch, lower top speed.", UDim2.new(1, -24, 1, 0), UDim2.fromOffset(12, 0), 12, UI.Colors.Dim)
end

local function renderStats()
	clear(statsPanel)
	local carId, data = selectedData()
	if not carId or not data then
		return
	end
	local s = CarStats.compute(carId, data)
	local lines = {
		string.format("%s", Config.Cars[carId].Name),
		string.format("CLASS %s  •  PI %d", s.Class, s.Rating),
		"",
		string.format("Top speed      %d mph", math.floor(s.TopSpeedMph)),
		string.format("Power          %.1f", s.Power * s.WeightFactor),
		string.format("Redline        %d rpm", s.Redline),
		string.format("Shift time     %.2f s", s.ShiftTime),
		string.format("Grip           %.2f g", s.Grip),
		string.format("Brakes         %.0f", s.Brake),
		string.format("Springs        %.2f Hz", s.SpringFreq),
		string.format("Ride height    %.2f", s.RideHeight),
		string.format("Nitrous        %ds  x%.2f", s.NitroCapacity, s.NitroBoost),
		string.format("Fuel tank      %.1f gal", s.FuelCapacity),
		string.format("Drivetrain     %s", s.Drivetrain),
		"",
		string.format("Best 1/4 mile  %s", if profile.Best.Quarter then string.format("%.3fs", profile.Best.Quarter) else "--"),
		string.format("Best 1/2 mile  %s", if profile.Best.Half then string.format("%.3fs", profile.Best.Half) else "--"),
		string.format("Races %d  Wins %d", profile.Stats.Races or 0, profile.Stats.Wins or 0),
		string.format("Escapes %d  Busts %d", profile.Stats.Escapes or 0, profile.Stats.Busts or 0),
	}
	local l = UI.label(statsPanel, table.concat(lines, "\n"), UDim2.new(1, -20, 1, -20), UDim2.fromOffset(10, 10), 14, UI.Colors.Text, Enum.Font.Code)
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextYAlignment = Enum.TextYAlignment.Top
end

local function render()
	if not root or not root.Visible or not profile then
		return
	end
	clear(content)
	if tab == "Shop" then
		renderShop()
	elseif tab == "My Cars" then
		renderMyCars()
	elseif tab == "Events" then
		renderEvents()
	elseif tab == "Performance" then
		renderPerformance()
	elseif tab == "Visual" then
		renderVisual()
	elseif tab == "Tuning" then
		renderTuning()
	end
	renderStats()
	local cashLabel = root:FindFirstChild("Cash") :: TextLabel?
	if cashLabel then
		cashLabel.Text = UI.money(profile.Cash)
	end
	for _, b in (root:FindFirstChild("Tabs") :: Frame):GetChildren() do
		if b:IsA("TextButton") then
			b.BackgroundColor3 = if b.Name == tab then UI.Colors.Pink else Color3.fromRGB(50, 50, 62)
		end
	end
end

function GarageUI.open(toTab: string?)
	if toTab then
		tab = toTab
	end
	root.Visible = true
	render()
end

function GarageUI.close()
	root.Visible = false
end

function GarageUI.toggle(toTab: string?)
	if root.Visible and (not toTab or toTab == tab) then
		GarageUI.close()
	else
		GarageUI.open(toTab)
	end
end

function GarageUI.init()
	gui = Instance.new("ScreenGui")
	gui.Name = "Garage"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 5
	gui.Parent = player:WaitForChild("PlayerGui")

	root = UI.frame(gui, UDim2.new(0.86, 0, 0.84, 0), UDim2.new(0.07, 0, 0.08, 0), UI.Colors.Bg, 0.05)
	UI.corner(root, 12)
	root.Visible = false
	local size = Instance.new("UISizeConstraint")
	size.MaxSize = Vector2.new(1100, 720)
	size.Parent = root

	local title = UI.label(root, "MIDNIGHT MOTORS", UDim2.new(0.6, 0, 0, 40), UDim2.fromOffset(18, 8), 26, UI.Colors.Accent, Enum.Font.GothamBlack)
	title.TextXAlignment = Enum.TextXAlignment.Left
	local cash = UI.label(root, "$0", UDim2.fromOffset(200, 40), UDim2.new(1, -270, 0, 8), 24, UI.Colors.Good, Enum.Font.GothamBlack)
	cash.Name = "Cash"
	cash.TextXAlignment = Enum.TextXAlignment.Right
	UI.button(root, "X", UDim2.fromOffset(40, 40), UDim2.new(1, -54, 0, 8), UI.Colors.Bad, GarageUI.close)

	local tabs = UI.frame(root, UDim2.new(1, -36, 0, 40), UDim2.fromOffset(18, 56), nil, 1)
	tabs.Name = "Tabs"
	local tl = Instance.new("UIListLayout")
	tl.FillDirection = Enum.FillDirection.Horizontal
	tl.Padding = UDim.new(0, 8)
	tl.Parent = tabs
	for _, name in TABS do
		local b = UI.button(tabs, name, UDim2.fromOffset(118, 38), UDim2.new(), Color3.fromRGB(50, 50, 62), function()
			tab = name
			render()
		end)
		b.Name = name
	end

	content = Instance.new("ScrollingFrame")
	content.Size = UDim2.new(0.66, -24, 1, -116)
	content.Position = UDim2.fromOffset(18, 104)
	content.BackgroundTransparency = 1
	content.BorderSizePixel = 0
	content.ScrollBarThickness = 6
	content.AutomaticCanvasSize = Enum.AutomaticSize.Y
	content.CanvasSize = UDim2.new()
	content.Parent = root
	local cl = Instance.new("UIListLayout")
	cl.Padding = UDim.new(0, 8)
	cl.Parent = content

	statsPanel = UI.frame(root, UDim2.new(0.34, -18, 1, -116), UDim2.new(0.66, 0, 0, 104), UI.Colors.Panel)
	UI.corner(statsPanel)
end

function GarageUI.start()
	Remotes.event("OpenGarage").OnClientEvent:Connect(function()
		GarageUI.open("Performance")
	end)
	Remotes.event("ProfileUpdated").OnClientEvent:Connect(function(p)
		profile = p
		render()
	end)
	task.spawn(function()
		profile = Remotes.func("GetProfile"):InvokeServer()
		render()
	end)
	Remotes.event("EventUpdate").OnClientEvent:Connect(function(payload)
		if payload.type == "Status" then
			eventStatus = payload
			eventStatusAt = os.clock()
			if tab == "Events" then
				render()
			end
		end
	end)
	-- keep the Events tab countdown ticking
	task.spawn(function()
		while true do
			task.wait(1)
			if root.Visible and tab == "Events" then
				render()
			end
		end
	end)
	-- G opens/closes the menu anywhere
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.G then
			GarageUI.toggle()
		end
	end)
end

return GarageUI
