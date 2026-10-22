--!strict
-- On-screen HUD: coins/points, trick popups, combo meter, notifications, speed,
-- and a context-sensitive controls hint (H to hide).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))
local LocalRider = require(script.Parent.LocalRider)

local HUDController = {}

-- Replaced once the HUD is built; other controllers can call it any time.
HUDController.notify = function(_: string, _: string?) end

local player = Players.LocalPlayer

local function formatNumber(n: number): string
	local s = tostring(math.floor(n))
	local formatted = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if formatted:sub(1, 1) == "," then
		formatted = formatted:sub(2)
	end
	return formatted
end

local function label(parent: Instance, name: string, size: UDim2, pos: UDim2, text: string, color: Color3?): TextLabel
	local t = Instance.new("TextLabel")
	t.Name = name
	t.Size = size
	t.Position = pos
	t.BackgroundTransparency = 1
	t.Font = Enum.Font.FredokaOne
	t.TextScaled = true
	t.TextColor3 = color or Color3.new(1, 1, 1)
	t.TextStrokeTransparency = 0.4
	t.Text = text
	t.Parent = parent
	return t
end

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

function HUDController.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "SnowHUD"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	-- Stats panel (top-left).
	local stats = Instance.new("Frame")
	stats.Name = "Stats"
	stats.Size = UDim2.fromOffset(220, 100)
	stats.Position = UDim2.fromOffset(12, 12)
	stats.BackgroundColor3 = Color3.fromRGB(15, 30, 55)
	stats.BackgroundTransparency = 0.25
	corner(stats, 12)
	stats.Parent = gui
	local coins = label(stats, "Coins", UDim2.new(1, -20, 0, 28), UDim2.fromOffset(10, 6), "❄ 0 coins", Color3.fromRGB(160, 220, 255))
	coins.TextXAlignment = Enum.TextXAlignment.Left
	local points = label(stats, "Points", UDim2.new(1, -20, 0, 28), UDim2.fromOffset(10, 36), "★ 0 pts", Color3.fromRGB(255, 220, 90))
	points.TextXAlignment = Enum.TextXAlignment.Left
	local best = label(stats, "Best", UDim2.new(1, -20, 0, 24), UDim2.fromOffset(10, 68), "Best combo: 0", Color3.fromRGB(255, 150, 160))
	best.TextXAlignment = Enum.TextXAlignment.Left

	local function refreshStats()
		coins.Text = "❄ " .. formatNumber((player:GetAttribute("Coins") :: number?) or 0) .. " coins"
		points.Text = "★ " .. formatNumber((player:GetAttribute("TotalPoints") :: number?) or 0) .. " pts"
		best.Text = "Best combo: " .. formatNumber((player:GetAttribute("BestCombo") :: number?) or 0)
	end
	for _, attr in { "Coins", "TotalPoints", "BestCombo" } do
		player:GetAttributeChangedSignal(attr):Connect(refreshStats)
	end
	refreshStats()

	-- Trick popup + combo meter (top-centre).
	local trickLabel = label(gui, "Trick", UDim2.new(0.6, 0, 0, 54), UDim2.new(0.2, 0, 0, 70), "", Color3.new(1, 1, 1))
	trickLabel.TextTransparency = 1
	trickLabel.TextStrokeTransparency = 1
	local trickScale = Instance.new("UIScale")
	trickScale.Parent = trickLabel
	local pointsLabel = label(gui, "TrickPoints", UDim2.new(0.3, 0, 0, 34), UDim2.new(0.35, 0, 0, 124), "", Color3.fromRGB(255, 220, 90))
	pointsLabel.TextTransparency = 1
	pointsLabel.TextStrokeTransparency = 1
	local comboLabel = label(gui, "Combo", UDim2.new(0.4, 0, 0, 30), UDim2.new(0.3, 0, 0, 160), "", Color3.fromRGB(120, 230, 255))
	comboLabel.Visible = false
	local banner = label(gui, "Banner", UDim2.new(0.5, 0, 0, 46), UDim2.new(0.25, 0, 0, 196), "", Color3.fromRGB(110, 255, 140))
	banner.TextTransparency = 1
	banner.TextStrokeTransparency = 1

	local popToken = 0
	local function popTrick(name: string, pts: number)
		popToken += 1
		local token = popToken
		trickLabel.Text = string.upper(name)
		pointsLabel.Text = "+" .. formatNumber(pts)
		trickLabel.TextTransparency = 0
		trickLabel.TextStrokeTransparency = 0.3
		pointsLabel.TextTransparency = 0
		pointsLabel.TextStrokeTransparency = 0.4
		trickScale.Scale = 1.5
		TweenService:Create(trickScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		task.delay(1.8, function()
			if token ~= popToken then
				return
			end
			local info = TweenInfo.new(0.5)
			TweenService:Create(trickLabel, info, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
			TweenService:Create(pointsLabel, info, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		end)
	end

	local bannerToken = 0
	local function showBanner(text: string, color: Color3)
		bannerToken += 1
		local token = bannerToken
		banner.Text = text
		banner.TextColor3 = color
		banner.TextTransparency = 0
		banner.TextStrokeTransparency = 0.3
		task.delay(1.6, function()
			if token == bannerToken then
				TweenService:Create(banner, TweenInfo.new(0.6), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
			end
		end)
	end

	Remotes.event("TrickAwarded").OnClientEvent:Connect(function(data: any)
		if type(data) ~= "table" then
			return
		end
		popTrick(tostring(data.name), tonumber(data.points) or 0)
		comboLabel.Visible = true
		comboLabel.Text = string.format("x%.1f COMBO  •  %s", tonumber(data.multiplier) or 1, formatNumber(tonumber(data.pending) or 0))
	end)
	Remotes.event("ComboUpdate").OnClientEvent:Connect(function(data: any)
		if type(data) ~= "table" then
			return
		end
		comboLabel.Visible = false
		if data.state == "Banked" then
			showBanner("+" .. formatNumber(tonumber(data.total) or 0) .. " BANKED!", Color3.fromRGB(110, 255, 140))
		elseif data.state == "Lost" then
			showBanner("COMBO LOST", Color3.fromRGB(255, 90, 90))
		end
	end)

	-- Toast notifications (bottom-centre).
	local toast = label(gui, "Toast", UDim2.new(0.5, 0, 0, 30), UDim2.new(0.25, 0, 1, -170), "", Color3.new(1, 1, 1))
	toast.TextTransparency = 1
	toast.TextStrokeTransparency = 1
	local toastToken = 0
	local function notify(message: string, kind: string?)
		toastToken += 1
		local token = toastToken
		toast.Text = message
		toast.TextColor3 = if kind == "Warning" then Color3.fromRGB(255, 180, 80) elseif kind == "Hit" then Color3.fromRGB(140, 220, 255) else Color3.new(1, 1, 1)
		toast.TextTransparency = 0
		toast.TextStrokeTransparency = 0.3
		task.delay(2.5, function()
			if token == toastToken then
				TweenService:Create(toast, TweenInfo.new(0.5), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
			end
		end)
	end
	Remotes.event("Notify").OnClientEvent:Connect(function(message: any, kind: any)
		notify(tostring(message), if type(kind) == "string" then kind else nil)
	end)
	HUDController.notify = notify

	-- Speedometer (bottom-right, riding only).
	local speedLabel = label(gui, "Speed", UDim2.fromOffset(160, 40), UDim2.new(1, -176, 1, -240), "", Color3.new(1, 1, 1))
	speedLabel.TextXAlignment = Enum.TextXAlignment.Right

	-- Controls hint (bottom-left).
	local hint = Instance.new("TextLabel")
	hint.Name = "Controls"
	hint.Size = UDim2.fromOffset(330, 150)
	hint.Position = UDim2.new(0, 12, 1, -162)
	hint.BackgroundColor3 = Color3.fromRGB(15, 30, 55)
	hint.BackgroundTransparency = 0.35
	hint.TextColor3 = Color3.new(1, 1, 1)
	hint.Font = Enum.Font.GothamMedium
	hint.TextSize = 14
	hint.TextXAlignment = Enum.TextXAlignment.Left
	hint.TextYAlignment = Enum.TextYAlignment.Top
	hint.TextWrapped = true
	corner(hint, 10)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 10)
	pad.PaddingTop = UDim.new(0, 8)
	pad.Parent = hint
	hint.Parent = gui

	local RIDING_HINT = "RIDING   (H to hide)\nA / D  carve  •  in air: spin\nW / S  push / brake  •  in air: flip\nHold SPACE, release to ollie\nQ Indy  F Method  R Nose  T Tail grabs\nDrop onto rails & boxes to grind\nE  unstrap"
	local FOOT_HINT = "ON FOOT   (H to hide)\nE  strap into your snowboard\nCLICK  throw a snowball\nStep on a glowing pad to travel\nVisit the Snow Shop (G) to change gear"

	local hintVisible = not UserInputService.TouchEnabled
	UserInputService.InputBegan:Connect(function(input, gp)
		if not gp and input.KeyCode == Enum.KeyCode.H then
			hintVisible = not hintVisible
		end
	end)

	RunService.RenderStepped:Connect(function()
		hint.Visible = hintVisible
		hint.Text = if LocalRider.riding then RIDING_HINT else FOOT_HINT
		speedLabel.Visible = LocalRider.riding
		if LocalRider.riding then
			-- 1 stud ≈ 0.28 m, so studs/s ≈ km/h.
			speedLabel.Text = string.format("%d km/h", math.floor(LocalRider.speed))
		end
	end)

	gui.Parent = player:WaitForChild("PlayerGui")
end

return HUDController
