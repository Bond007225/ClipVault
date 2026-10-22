--!strict
-- Snow Shop / fitting room UI. Opens from the shop counter or fitting-room prompts.
-- Tabs per slot, item cards with buy/equip, and a live rotating preview of your
-- character wearing the current outfit.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Catalog = require(Shared.Catalog)
local Remotes = require(Shared.Remotes)
local LocalRider = require(script.Parent.LocalRider)

local ShopController = {}

local player = Players.LocalPlayer

type ProfileView = { Coins: number, Owned: { [string]: boolean }, Equipped: { [string]: string } }

local gui: ScreenGui
local window: Frame
local grid: ScrollingFrame
local coinsLabel: TextLabel
local statusLabel: TextLabel
local viewport: ViewportFrame
local tabButtons: { [string]: TextButton } = {}

local profile: ProfileView? = nil
local currentSlot = "Hat"
local openedAt: Vector3? = nil
local busy = false
local previewModel: Model? = nil
local previewAngle = 0

local ACCENT = Color3.fromRGB(60, 140, 255)
local PANEL = Color3.fromRGB(18, 32, 58)

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function text(parent: Instance, props: { [string]: any }): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Font = Enum.Font.FredokaOne
	t.TextColor3 = Color3.new(1, 1, 1)
	t.TextScaled = true
	for k, v in props do
		(t :: any)[k] = v
	end
	t.Parent = parent
	return t
end

local function button(parent: Instance, props: { [string]: any }): TextButton
	local b = Instance.new("TextButton")
	b.Font = Enum.Font.FredokaOne
	b.TextColor3 = Color3.new(1, 1, 1)
	b.TextScaled = true
	b.AutoButtonColor = true
	b.BorderSizePixel = 0
	for k, v in props do
		(b :: any)[k] = v
	end
	corner(b, 8)
	b.Parent = parent
	return b
end

local function setStatus(msg: string, good: boolean?)
	statusLabel.Text = msg
	statusLabel.TextColor3 = if good == false then Color3.fromRGB(255, 130, 130) else Color3.fromRGB(170, 255, 190)
end

local function refreshPreview()
	local character = player.Character
	if not character then
		return
	end
	if previewModel then
		previewModel:Destroy()
		previewModel = nil
	end
	character.Archivable = true
	local clone = character:Clone()
	character.Archivable = false
	if not clone then
		return
	end
	for _, d in clone:GetDescendants() do
		if d:IsA("Script") or d:IsA("LocalScript") or d:IsA("ParticleEmitter") or d:IsA("Sound") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = true
		end
	end
	local hum = clone:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
	clone:PivotTo(CFrame.new())
	local worldModel = viewport:FindFirstChildOfClass("WorldModel") or Instance.new("WorldModel")
	worldModel.Parent = viewport
	clone.Parent = worldModel
	previewModel = clone
end

local renderGrid: () -> ()

local function applyResult(result: any)
	if type(result) ~= "table" then
		setStatus("Shop is busy, try again", false)
		return
	end
	if result.profile then
		profile = result.profile
	end
	setStatus(tostring(result.message), result.ok == true)
	renderGrid()
	if result.ok then
		task.delay(0.35, refreshPreview)
	end
end

local function purchase(itemId: string)
	if busy then
		return
	end
	busy = true
	local ok, result = pcall(function()
		return Remotes.func("PurchaseItem"):InvokeServer(itemId)
	end)
	busy = false
	applyResult(if ok then result else nil)
end

local function equip(slot: string, itemId: string?)
	if busy then
		return
	end
	busy = true
	local ok, result = pcall(function()
		return Remotes.func("EquipItem"):InvokeServer(slot, itemId)
	end)
	busy = false
	applyResult(if ok then result else nil)
end

renderGrid = function()
	for _, child in grid:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	for slot, b in tabButtons do
		b.BackgroundColor3 = if slot == currentSlot then ACCENT else Color3.fromRGB(35, 55, 90)
	end
	local p = profile
	if not p then
		return
	end
	coinsLabel.Text = "❄ " .. p.Coins

	local order = 0
	for _, item in Catalog.Items do
		if item.Slot == currentSlot then
			order += 1
			local owned = p.Owned[item.Id] == true
			local equipped = p.Equipped[item.Slot] == item.Id

			local card = Instance.new("Frame")
			card.Name = item.Id
			card.LayoutOrder = order
			card.BackgroundColor3 = Color3.fromRGB(28, 46, 78)
			card.BorderSizePixel = 0
			corner(card, 10)
			if equipped then
				local stroke = Instance.new("UIStroke")
				stroke.Color = Color3.fromRGB(110, 255, 140)
				stroke.Thickness = 3
				stroke.Parent = card
			end

			local swatch = Instance.new("Frame")
			swatch.Size = UDim2.new(1, -16, 0.45, 0)
			swatch.Position = UDim2.fromOffset(8, 8)
			swatch.BackgroundColor3 = item.Color
			swatch.BorderSizePixel = 0
			corner(swatch, 8)
			swatch.Parent = card
			local accent = Instance.new("Frame")
			accent.Size = UDim2.new(1, 0, 0.25, 0)
			accent.Position = UDim2.fromScale(0, 0.75)
			accent.BackgroundColor3 = item.Accent
			accent.BorderSizePixel = 0
			corner(accent, 8)
			accent.Parent = swatch

			text(card, {
				Text = item.Name,
				Size = UDim2.new(1, -12, 0.15, 0),
				Position = UDim2.new(0, 6, 0.5, 4),
			})
			local sub = if item.Stats
				then string.format("SPD %.2f  TRN %.2f  POP %.2f", item.Stats.Speed, item.Stats.Turn, item.Stats.Pop)
				else item.Style
			text(card, {
				Text = sub,
				Font = Enum.Font.Gotham,
				TextColor3 = Color3.fromRGB(180, 200, 230),
				Size = UDim2.new(1, -12, 0.1, 0),
				Position = UDim2.new(0, 6, 0.65, 4),
			})

			local label: string
			local color: Color3
			if not owned then
				label = "Buy ❄" .. item.Price
				color = if p.Coins >= item.Price then Color3.fromRGB(255, 160, 40) else Color3.fromRGB(90, 90, 100)
			elseif equipped then
				label = if item.Slot == "Board" then "Riding" else "Unequip"
				color = Color3.fromRGB(70, 170, 90)
			else
				label = "Equip"
				color = ACCENT
			end
			local action = button(card, {
				Text = label,
				BackgroundColor3 = color,
				Size = UDim2.new(1, -16, 0.16, 0),
				Position = UDim2.new(0, 8, 0.82, -2),
			})
			action.Activated:Connect(function()
				if not owned then
					purchase(item.Id)
				elseif equipped then
					if item.Slot ~= "Board" then
						equip(item.Slot, nil)
					end
				else
					equip(item.Slot, item.Id)
				end
			end)
			card.Parent = grid
		end
	end
end

local function close()
	gui.Enabled = false
	LocalRider.uiOpen = false
	openedAt = nil
	if previewModel then
		previewModel:Destroy()
		previewModel = nil
	end
end

local function open()
	if gui.Enabled then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	openedAt = if root then root.Position else nil
	gui.Enabled = true
	LocalRider.uiOpen = true
	setStatus("Pick a category, then buy or equip.", true)
	local ok, result = pcall(function()
		return Remotes.func("GetProfile"):InvokeServer()
	end)
	if ok and type(result) == "table" then
		profile = result
	end
	renderGrid()
	refreshPreview()
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "SnowShop"
	gui.ResetOnSpawn = false
	gui.Enabled = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	window = Instance.new("Frame")
	window.Name = "Window"
	window.AnchorPoint = Vector2.new(0.5, 0.5)
	window.Position = UDim2.fromScale(0.5, 0.5)
	window.Size = UDim2.fromScale(0.86, 0.8)
	window.BackgroundColor3 = PANEL
	window.BorderSizePixel = 0
	corner(window, 16)
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(1000, 640)
	limit.Parent = window
	window.Parent = gui

	text(window, { Text = "SNOW SHOP", Size = UDim2.new(0.4, 0, 0, 44), Position = UDim2.fromOffset(18, 10), TextXAlignment = Enum.TextXAlignment.Left })
	coinsLabel = text(window, { Text = "❄ 0", Size = UDim2.new(0.25, 0, 0, 34), Position = UDim2.new(0.6, -60, 0, 14), TextColor3 = Color3.fromRGB(160, 220, 255), TextXAlignment = Enum.TextXAlignment.Right })
	local closeButton = button(window, { Text = "X", BackgroundColor3 = Color3.fromRGB(200, 60, 70), Size = UDim2.fromOffset(40, 40), Position = UDim2.new(1, -52, 0, 12) })
	closeButton.Activated:Connect(close)

	-- Category tabs (left).
	local tabs = Instance.new("ScrollingFrame")
	tabs.Name = "Tabs"
	tabs.Position = UDim2.fromOffset(14, 64)
	tabs.Size = UDim2.new(0, 150, 1, -110)
	tabs.BackgroundTransparency = 1
	tabs.BorderSizePixel = 0
	tabs.ScrollBarThickness = 4
	tabs.AutomaticCanvasSize = Enum.AutomaticSize.Y
	tabs.CanvasSize = UDim2.new()
	local tabLayout = Instance.new("UIListLayout")
	tabLayout.Padding = UDim.new(0, 6)
	tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tabLayout.Parent = tabs
	tabs.Parent = window
	for i, slot in Catalog.Slots do
		local b = button(tabs, { Text = (Catalog.SlotLabels :: any)[slot], LayoutOrder = i, Size = UDim2.new(1, -8, 0, 38), BackgroundColor3 = Color3.fromRGB(35, 55, 90) })
		b.Activated:Connect(function()
			currentSlot = slot
			renderGrid()
		end)
		tabButtons[slot] = b
	end

	-- Item grid (middle).
	grid = Instance.new("ScrollingFrame")
	grid.Name = "Items"
	grid.Position = UDim2.fromOffset(176, 64)
	grid.Size = UDim2.new(0.62, -176, 1, -110)
	grid.BackgroundTransparency = 1
	grid.BorderSizePixel = 0
	grid.ScrollBarThickness = 6
	grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
	grid.CanvasSize = UDim2.new()
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(150, 190)
	layout.CellPadding = UDim2.fromOffset(10, 10)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid
	grid.Parent = window

	-- Preview (right).
	viewport = Instance.new("ViewportFrame")
	viewport.Name = "Preview"
	viewport.Position = UDim2.new(0.62, 10, 0, 64)
	viewport.Size = UDim2.new(0.38, -24, 1, -110)
	viewport.BackgroundColor3 = Color3.fromRGB(205, 225, 250)
	viewport.Ambient = Color3.fromRGB(200, 200, 210)
	viewport.LightColor = Color3.fromRGB(255, 255, 255)
	viewport.LightDirection = Vector3.new(-1, -1, -1)
	corner(viewport, 12)
	local cam = Instance.new("Camera")
	cam.FieldOfView = 40
	cam.CFrame = CFrame.lookAt(Vector3.new(0, 1, -11), Vector3.new(0, 0.2, 0))
	cam.Parent = viewport
	viewport.CurrentCamera = cam
	viewport.Parent = window

	statusLabel = text(window, { Text = "", Font = Enum.Font.GothamBold, Size = UDim2.new(1, -40, 0, 26), Position = UDim2.new(0, 20, 1, -38), TextXAlignment = Enum.TextXAlignment.Left })

	gui.Parent = player:WaitForChild("PlayerGui")
end

function ShopController.start()
	build()

	ProximityPromptService.PromptTriggered:Connect(function(prompt, who)
		if who == player and prompt:GetAttribute("OpensShop") == true then
			open()
		end
	end)

	player:GetAttributeChangedSignal("Coins"):Connect(function()
		local p = profile
		local coins = player:GetAttribute("Coins")
		if p and type(coins) == "number" then
			p.Coins = coins
			if gui.Enabled then
				coinsLabel.Text = "❄ " .. coins
			end
		end
	end)

	RunService.RenderStepped:Connect(function(dt: number)
		if not gui.Enabled then
			return
		end
		local model = previewModel
		if model then
			previewAngle += dt * 0.8
			model:PivotTo(CFrame.Angles(0, previewAngle, 0))
		end
		-- Walk away (or start riding) and the shop closes.
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local start = openedAt
		if LocalRider.riding or (root and start and (root.Position - start).Magnitude > 20) then
			close()
		end
	end)
end

return ShopController
