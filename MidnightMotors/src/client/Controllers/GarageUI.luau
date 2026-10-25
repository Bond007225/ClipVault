--!strict
-- Garage screen (opened from a garage terminal): buy/switch cars, install
-- performance upgrades, paint & body kits, and free tuning sliders. All
-- purchases are requests; the server validates price, ownership and location.

local Players = game:GetService("Players")
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
local tab = "Dealership"
local profile: any = nil

local TABS = { "Dealership", "Performance", "Visual", "Tuning" }

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
local function renderDealership()
	for _, carId in Config.CarOrder do
		local def = Config.Cars[carId]
		local stats = CarStats.compute(carId, nil)
		local owned = profile.Cars[carId] ~= nil
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
		if profile.Selected == carId then
			UI.label(f, "DRIVING", UDim2.fromOffset(120, 40), UDim2.new(1, -132, 0, 18), 16, UI.Colors.Good, Enum.Font.GothamBlack)
		elseif owned then
			UI.button(f, "Select & Spawn", UDim2.fromOffset(130, 40), UDim2.new(1, -142, 0, 18), UI.Colors.Accent, function()
				Remotes.event("SelectCar"):FireServer(carId)
			end)
		else
			local afford = profile.Cash >= def.Price
			UI.button(f, "Buy " .. UI.money(def.Price), UDim2.fromOffset(130, 40), UDim2.new(1, -142, 0, 18), if afford then UI.Colors.Good else Color3.fromRGB(80, 80, 90), function()
				Remotes.event("BuyCar"):FireServer(carId)
			end)
		end
	end
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
	if tab == "Dealership" then
		renderDealership()
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

function GarageUI.open()
	root.Visible = true
	render()
end

function GarageUI.close()
	root.Visible = false
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

	local title = UI.label(root, "MIDNIGHT MOTORS GARAGE", UDim2.new(0.6, 0, 0, 40), UDim2.fromOffset(18, 8), 26, UI.Colors.Accent, Enum.Font.GothamBlack)
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
		local b = UI.button(tabs, name, UDim2.fromOffset(140, 38), UDim2.new(), Color3.fromRGB(50, 50, 62), function()
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
	Remotes.event("OpenGarage").OnClientEvent:Connect(GarageUI.open)
	Remotes.event("ProfileUpdated").OnClientEvent:Connect(function(p)
		profile = p
		render()
	end)
	task.spawn(function()
		profile = Remotes.func("GetProfile"):InvokeServer()
		render()
	end)
	-- close automatically when you walk/drive away from the terminal
	task.spawn(function()
		local openedAt: Vector3? = nil
		while true do
			task.wait(0.5)
			local char = player.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root.Visible and hrp then
				openedAt = openedAt or hrp.Position
				if (hrp.Position - (openedAt :: Vector3)).Magnitude > 60 then
					GarageUI.close()
				end
			else
				openedAt = nil
			end
		end
	end)
end

return GarageUI
