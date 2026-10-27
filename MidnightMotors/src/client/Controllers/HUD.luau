--!strict
-- Heads-up display: speedometer/tach/gear/nitro/fuel, cash, speed limit sign,
-- wanted stars with bust/escape meters, car meet indicator, drag-race tree and
-- results, notifications and the speed-camera flash.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)

local UI = require(script.Parent.UI)
local GarageUI = require(script.Parent.GarageUI)

local HUD = {}

local player = Players.LocalPlayer
local gui: ScreenGui
local refs: { [string]: any } = {}
local toastHolder: Frame

----------------------------------------------------------------------
-- Notifications
----------------------------------------------------------------------
local KIND_COLORS = {
	info = UI.Colors.Accent,
	money = UI.Colors.Good,
	warn = UI.Colors.Warn,
	police = Color3.fromRGB(70, 110, 255),
	bust = UI.Colors.Bad,
}

function HUD.notify(text: string, kind: string?)
	if not toastHolder then
		return
	end
	local color = KIND_COLORS[kind or "info"] or UI.Colors.Accent
	local f = UI.frame(toastHolder, UDim2.new(1, 0, 0, 34), UDim2.new(), UI.Colors.Bg, 0.15)
	UI.corner(f, 6)
	local stripe = UI.frame(f, UDim2.new(0, 5, 1, 0), UDim2.new(), color)
	UI.corner(stripe, 3)
	local l = UI.label(f, text, UDim2.new(1, -16, 1, 0), UDim2.fromOffset(12, 0), 15, UI.Colors.Text)
	l.TextXAlignment = Enum.TextXAlignment.Left
	task.delay(if kind == "bust" then 7 else 4.5, function()
		local tween = TweenService:Create(f, TweenInfo.new(0.4), { BackgroundTransparency = 1 })
		TweenService:Create(l, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
		TweenService:Create(stripe, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
		tween:Play()
		tween.Completed:Wait()
		f:Destroy()
	end)
end

----------------------------------------------------------------------
-- Speedometer
----------------------------------------------------------------------
function HUD.setTelemetry(t: any?, manual: boolean, fuel: number, popped: boolean)
	local speedo = refs.speedo :: Frame
	if not speedo then
		return
	end
	speedo.Visible = t ~= nil
	if not t then
		return
	end
	refs.mph.Text = tostring(math.floor(t.mph))
	refs.gear.Text = t.gear
	local rpmFrac = math.clamp(t.rpm / t.redline, 0, 1)
	refs.rpmFill.Size = UDim2.fromScale(rpmFrac, 1)
	refs.rpmFill.BackgroundColor3 = if rpmFrac > 0.92 then UI.Colors.Bad elseif rpmFrac > 0.75 then UI.Colors.Warn else UI.Colors.Accent
	refs.rpmText.Text = string.format("%d RPM", math.floor(t.rpm / 10) * 10)
	refs.nitroFill.Size = UDim2.fromScale(math.clamp(t.nitro, 0, 1), 1)
	refs.fuelFill.Size = UDim2.fromScale(math.clamp(fuel, 0, 1), 1)
	refs.fuelFill.BackgroundColor3 = if fuel < 0.15 then UI.Colors.Bad else UI.Colors.Warn
	local tags = {}
	table.insert(tags, if manual then "MANUAL" else "AUTO")
	if t.drifting then
		table.insert(tags, "DRIFT!")
	end
	if popped then
		table.insert(tags, "TIRES POPPED")
	end
	refs.mode.Text = table.concat(tags, "  ")
end

----------------------------------------------------------------------
-- Drag racing overlay
----------------------------------------------------------------------
local function showRace(payload: { [string]: any })
	local big = refs.raceBig :: TextLabel
	if payload.type == "Staged" then
		big.Text = "STAGED"
		big.TextColor3 = UI.Colors.Text
		big.Visible = true
	elseif payload.type == "Tree" then
		big.Visible = true
		if payload.step < 4 then
			big.Text = string.rep("● ", payload.step)
			big.TextColor3 = UI.Colors.Warn
		else
			big.Text = "GO!"
			big.TextColor3 = UI.Colors.Good
			task.delay(1.2, function()
				if big.Text == "GO!" then
					big.Visible = false
				end
			end)
		end
	elseif payload.type == "Result" then
		big.Visible = false
		local panel = refs.racePanel :: Frame
		local text: string
		if payload.result == "Finished" then
			text = string.format(
				"%s MILE\nET  %.3f s\nTRAP  %d MPH\nR/T  %s%s%s\n+%s",
				string.upper(payload.strip),
				payload.et,
				math.floor(payload.trap),
				if payload.reaction then string.format("%.3f", payload.reaction) else "--",
				if payload.racers > 1 then (if payload.place == 1 then "\nWINNER!" else "\nYou lost") else "",
				if payload.pb then "\nNEW PERSONAL BEST" else "",
				UI.money(payload.payout)
			)
		else
			text = string.format("%s MILE\n%s", string.upper(payload.strip), string.upper(payload.result))
		end
		refs.raceText.Text = text
		panel.Visible = true
		task.delay(7, function()
			panel.Visible = false
		end)
	end
end

----------------------------------------------------------------------
-- Police / zone / meet attributes
----------------------------------------------------------------------
local function refreshPolice()
	local heat = (player:GetAttribute("Heat") :: number?) or 0
	local status = (player:GetAttribute("PoliceStatus") :: string?) or ""
	local wanted = refs.wanted :: Frame
	wanted.Visible = heat > 0
	for i, star in refs.stars do
		star.TextColor3 = if i <= heat then UI.Colors.Warn else Color3.fromRGB(70, 70, 80)
	end
	if status == "PullOver" then
		refs.policeText.Text = string.format("PULL OVER!  %ds", math.ceil((player:GetAttribute("PullOverTime") :: number?) or 0))
	elseif status == "Pursuit" then
		refs.policeText.Text = "EVADING POLICE"
	else
		refs.policeText.Text = ""
	end
	refs.bustFill.Size = UDim2.fromScale((player:GetAttribute("BustProgress") :: number?) or 0, 1)
	refs.escapeFill.Size = UDim2.fromScale((player:GetAttribute("EscapeProgress") :: number?) or 0, 1)
end

local function refreshZone()
	local limit = (player:GetAttribute("SpeedLimit") :: number?) or 0
	local zone = (player:GetAttribute("Zone") :: string?) or ""
	refs.limitNum.Text = if limit > 0 then tostring(limit) else "--"
	refs.zone.Text = string.upper(zone)
	local meet = (player:GetAttribute("Meet") :: string?) or ""
	refs.meet.Visible = meet ~= ""
	refs.meet.Text = string.format("CAR MEET: %s  •  %d car(s) parked", meet, (player:GetAttribute("MeetCount") :: number?) or 0)
end

----------------------------------------------------------------------
-- Build
----------------------------------------------------------------------
function HUD.init()
	gui = Instance.new("ScreenGui")
	gui.Name = "MidnightHUD"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.Parent = player:WaitForChild("PlayerGui")

	-- cash + speed limit (top left)
	local cash = UI.label(gui, "$0", UDim2.fromOffset(240, 36), UDim2.fromOffset(16, 10), 28, UI.Colors.Good, Enum.Font.GothamBlack)
	cash.TextXAlignment = Enum.TextXAlignment.Left
	refs.cash = cash
	local sign = UI.frame(gui, UDim2.fromOffset(70, 86), UDim2.fromOffset(16, 52), Color3.fromRGB(245, 245, 245))
	UI.corner(sign, 6)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Color3.fromRGB(20, 20, 20)
	stroke.Parent = sign
	UI.label(sign, "SPEED\nLIMIT", UDim2.new(1, 0, 0, 30), UDim2.fromOffset(0, 4), 11, Color3.fromRGB(20, 20, 20), Enum.Font.GothamBlack)
	refs.limitNum = UI.label(sign, "--", UDim2.new(1, 0, 0, 40), UDim2.fromOffset(0, 36), 32, Color3.fromRGB(20, 20, 20), Enum.Font.GothamBlack)
	refs.zone = UI.label(gui, "", UDim2.fromOffset(160, 20), UDim2.fromOffset(92, 52), 14, UI.Colors.Dim)
	refs.zone.TextXAlignment = Enum.TextXAlignment.Left

	-- wanted (top right)
	local wanted = UI.frame(gui, UDim2.fromOffset(250, 104), UDim2.new(1, -266, 0, 10), UI.Colors.Bg, 0.25)
	UI.corner(wanted)
	wanted.Visible = false
	refs.wanted = wanted
	refs.stars = {}
	for i = 1, 5 do
		local s = UI.label(wanted, "★", UDim2.fromOffset(40, 36), UDim2.fromOffset(10 + (i - 1) * 46, 4), 34, UI.Colors.Warn, Enum.Font.GothamBlack)
		refs.stars[i] = s
	end
	refs.policeText = UI.label(wanted, "", UDim2.new(1, -20, 0, 20), UDim2.fromOffset(10, 42), 15, Color3.fromRGB(120, 160, 255), Enum.Font.GothamBlack)
	UI.label(wanted, "BUST", UDim2.fromOffset(50, 14), UDim2.fromOffset(10, 66), 11, UI.Colors.Bad)
	local _, bustFill = UI.bar(wanted, UDim2.new(1, -76, 0, 8), UDim2.fromOffset(64, 69), UI.Colors.Bad)
	refs.bustFill = bustFill
	UI.label(wanted, "ESCAPE", UDim2.fromOffset(50, 14), UDim2.fromOffset(10, 84), 11, UI.Colors.Good)
	local _, escapeFill = UI.bar(wanted, UDim2.new(1, -76, 0, 8), UDim2.fromOffset(64, 87), UI.Colors.Good)
	refs.escapeFill = escapeFill

	-- notifications (top centre)
	toastHolder = UI.frame(gui, UDim2.fromOffset(420, 300), UDim2.new(0.5, -210, 0, 10), nil, 1)
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 6)
	list.Parent = toastHolder

	-- meet indicator
	local meet = UI.label(gui, "", UDim2.fromOffset(420, 30), UDim2.new(0.5, -210, 1, -150), 18, UI.Colors.Pink, Enum.Font.GothamBlack)
	meet.Visible = false
	refs.meet = meet

	-- speedometer (bottom right)
	local speedo = UI.frame(gui, UDim2.fromOffset(260, 150), UDim2.new(1, -276, 1, -166), UI.Colors.Bg, 0.2)
	UI.corner(speedo, 10)
	speedo.Visible = false
	refs.speedo = speedo
	refs.mph = UI.label(speedo, "0", UDim2.fromOffset(150, 64), UDim2.fromOffset(10, 4), 60, UI.Colors.Text, Enum.Font.GothamBlack)
	refs.mph.TextXAlignment = Enum.TextXAlignment.Right
	UI.label(speedo, "MPH", UDim2.fromOffset(40, 20), UDim2.fromOffset(162, 42), 14, UI.Colors.Dim)
	refs.gear = UI.label(speedo, "N", UDim2.fromOffset(50, 56), UDim2.fromOffset(204, 8), 44, UI.Colors.Accent, Enum.Font.GothamBlack)
	local _, rpmFill = UI.bar(speedo, UDim2.new(1, -20, 0, 12), UDim2.fromOffset(10, 74), UI.Colors.Accent)
	refs.rpmFill = rpmFill
	refs.rpmText = UI.label(speedo, "", UDim2.fromOffset(120, 14), UDim2.fromOffset(10, 88), 11, UI.Colors.Dim)
	refs.rpmText.TextXAlignment = Enum.TextXAlignment.Left
	UI.label(speedo, "NOS", UDim2.fromOffset(34, 14), UDim2.fromOffset(10, 106), 11, Color3.fromRGB(80, 160, 255))
	local _, nitroFill = UI.bar(speedo, UDim2.new(1, -60, 0, 8), UDim2.fromOffset(48, 109), Color3.fromRGB(80, 160, 255))
	refs.nitroFill = nitroFill
	UI.label(speedo, "FUEL", UDim2.fromOffset(34, 14), UDim2.fromOffset(10, 122), 11, UI.Colors.Warn)
	local _, fuelFill = UI.bar(speedo, UDim2.new(1, -60, 0, 8), UDim2.fromOffset(48, 125), UI.Colors.Warn)
	refs.fuelFill = fuelFill
	refs.mode = UI.label(speedo, "", UDim2.fromOffset(150, 14), UDim2.fromOffset(100, 88), 11, UI.Colors.Pink)
	refs.mode.TextXAlignment = Enum.TextXAlignment.Right

	-- buttons (bottom left)
	UI.button(gui, "Menu / Shop (G)", UDim2.fromOffset(150, 38), UDim2.new(0, 16, 1, -100), UI.Colors.Pink, function()
		GarageUI.toggle("Shop")
	end)
	UI.button(gui, "Spawn Car", UDim2.fromOffset(120, 38), UDim2.new(0, 174, 1, -100), UI.Colors.Accent, function()
		Remotes.event("SpawnCar"):FireServer()
	end)
	UI.button(gui, "Events", UDim2.fromOffset(90, 38), UDim2.new(0, 302, 1, -100), UI.Colors.Warn, function()
		GarageUI.toggle("Events")
	end)
	local help = UI.label(
		gui,
		"W/S throttle & brake • A/D steer • Space handbrake • Shift nitro • F exit car\nG menu & shop • J join race event • M manual • E/Q shift • R flip • E near car to drive",
		UDim2.fromOffset(460, 36),
		UDim2.new(0, 16, 1, -54),
		12,
		UI.Colors.Dim
	)
	help.TextXAlignment = Enum.TextXAlignment.Left

	-- race overlay
	local big = UI.label(gui, "", UDim2.fromOffset(500, 90), UDim2.new(0.5, -250, 0.3, 0), 72, UI.Colors.Warn, Enum.Font.GothamBlack)
	big.Visible = false
	refs.raceBig = big
	local panel = UI.frame(gui, UDim2.fromOffset(280, 190), UDim2.new(0.5, -140, 0.25, 0), UI.Colors.Bg, 0.1)
	UI.corner(panel, 10)
	panel.Visible = false
	refs.racePanel = panel
	refs.raceText = UI.label(panel, "", UDim2.new(1, -20, 1, -20), UDim2.fromOffset(10, 10), 20, UI.Colors.Text, Enum.Font.GothamBlack)

	-- camera flash
	local flash = UI.frame(gui, UDim2.fromScale(1, 1), UDim2.new(), Color3.new(1, 1, 1), 1)
	flash.ZIndex = 50
	refs.flash = flash
end

function HUD.flash()
	local flash = refs.flash :: Frame
	flash.BackgroundTransparency = 0.1
	TweenService:Create(flash, TweenInfo.new(0.8), { BackgroundTransparency = 1 }):Play()
end

function HUD.start()
	Remotes.event("Notify").OnClientEvent:Connect(function(text: string, kind: string?)
		HUD.notify(text, kind)
	end)
	Remotes.event("RaceUpdate").OnClientEvent:Connect(showRace)
	Remotes.event("CameraFlash").OnClientEvent:Connect(HUD.flash)
	Remotes.event("ProfileUpdated").OnClientEvent:Connect(function(profile)
		refs.cash.Text = UI.money(profile.Cash)
	end)
	for _, attr in { "Heat", "PoliceStatus", "BustProgress", "EscapeProgress", "PullOverTime" } do
		player:GetAttributeChangedSignal(attr):Connect(refreshPolice)
	end
	for _, attr in { "Zone", "SpeedLimit", "Meet", "MeetCount" } do
		player:GetAttributeChangedSignal(attr):Connect(refreshZone)
	end
	refreshPolice()
	refreshZone()
	task.spawn(function()
		local profile = Remotes.func("GetProfile"):InvokeServer()
		if profile then
			refs.cash.Text = UI.money(profile.Cash)
		end
	end)
end

return HUD
