--!strict
-- Builds car models out of parts (no external assets needed). One invisible
-- "Chassis" box carries all the physics; every visual part is massless,
-- non-colliding and welded to it. Wheels use Welds so the driver's client can
-- animate suspension travel, steering and spin by changing C0.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)

local CarFactory = {}

export type BuildOptions = {
	Kind: string, -- "Player" | "Traffic" | "Police"
	Cosmetics: { [string]: string }?,
	RideHeight: number,
	WheelRadius: number,
	Suv: boolean?,
	Name: string?,
}

local DARK = Color3.fromRGB(25, 25, 28)
local TRIM = Color3.fromRGB(40, 40, 44)

local function findOption(list: { any }, name: string?): any
	for _, opt in list do
		if opt.Name == name then
			return opt
		end
	end
	return list[1]
end

local function addPart(model: Model, chassis: BasePart, size: Vector3, localCf: CFrame, color: Color3, material: Enum.Material?, cls: string?): BasePart
	local p = Instance.new((cls or "Part") :: any) :: BasePart
	p.Size = size
	p.CFrame = chassis.CFrame * localCf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.Anchored = false
	local w = Instance.new("WeldConstraint")
	w.Part0 = chassis
	w.Part1 = p
	w.Parent = p
	p.Parent = model
	return p
end

local function paint(p: BasePart)
	p:SetAttribute("Paint", true)
end

----------------------------------------------------------------------
-- Spoilers can be swapped on a live car, so they are built separately
----------------------------------------------------------------------
local function buildSpoiler(model: Model, chassis: BasePart, kind: string)
	for _, child in model:GetChildren() do
		if child:GetAttribute("Spoiler") then
			child:Destroy()
		end
	end
	local W = model:GetAttribute("W") :: number
	local L = model:GetAttribute("L") :: number
	local top = model:GetAttribute("DeckTop") :: number
	local color = model:GetAttribute("PaintColor") :: Color3? or Color3.new(1, 1, 1)
	local parts: { BasePart } = {}
	local z = L / 2 - 0.9
	if kind == "Ducktail" then
		table.insert(parts, addPart(model, chassis, Vector3.new(W - 0.6, 0.35, 1.4), CFrame.new(0, top + 0.25, z) * CFrame.Angles(math.rad(-12), 0, 0), color))
	elseif kind == "Wing" then
		for _, x in { -W / 3, W / 3 } do
			table.insert(parts, addPart(model, chassis, Vector3.new(0.3, 1.2, 0.6), CFrame.new(x, top + 0.6, z), TRIM))
		end
		table.insert(parts, addPart(model, chassis, Vector3.new(W - 0.4, 0.25, 1.6), CFrame.new(0, top + 1.25, z) * CFrame.Angles(math.rad(-8), 0, 0), color))
	elseif kind == "GT Wing" then
		for _, x in { -W / 4, W / 4 } do
			table.insert(parts, addPart(model, chassis, Vector3.new(0.3, 2.2, 0.8), CFrame.new(x, top + 1.1, z + 0.3), TRIM))
		end
		table.insert(parts, addPart(model, chassis, Vector3.new(W + 0.6, 0.25, 2), CFrame.new(0, top + 2.3, z + 0.4) * CFrame.Angles(math.rad(-10), 0, 0), DARK, Enum.Material.Fabric))
		for _, x in { -(W / 2 + 0.35), W / 2 + 0.35 } do
			table.insert(parts, addPart(model, chassis, Vector3.new(0.15, 1, 2.4), CFrame.new(x, top + 2.2, z + 0.4), DARK))
		end
	end
	for _, p in parts do
		p:SetAttribute("Spoiler", true)
		if p.Color == color then
			paint(p)
		end
	end
end

----------------------------------------------------------------------
-- Cosmetics
----------------------------------------------------------------------
function CarFactory.applyCosmetics(model: Model, cosmetics: { [string]: string })
	local chassis = model:FindFirstChild("Chassis") :: BasePart
	local paintOpt = findOption(Config.Paints, cosmetics.Paint)
	local finish = findOption(Config.Finishes, cosmetics.Finish)
	local rims = findOption(Config.RimColors, cosmetics.Rims)
	local tint = findOption(Config.Tints, cosmetics.Tint)
	local glow = findOption(Config.Underglows, cosmetics.Underglow)
	model:SetAttribute("PaintColor", paintOpt.Color)

	if (model:GetAttribute("Spoiler") or "None") ~= cosmetics.Spoiler and model:GetAttribute("Kind") == "Player" then
		buildSpoiler(model, chassis, cosmetics.Spoiler or "None")
		model:SetAttribute("Spoiler", cosmetics.Spoiler or "None")
	end

	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			if d:GetAttribute("Paint") then
				d.Color = paintOpt.Color
				d.Material = finish.Material
				d.Reflectance = finish.Reflectance
			elseif d:GetAttribute("Rim") then
				d.Color = rims.Color
			elseif d:GetAttribute("Glass") then
				d.Transparency = tint.Transparency
			elseif d.Name == "Underglow" then
				local light = d:FindFirstChildOfClass("PointLight")
				if glow.Color then
					d.Transparency = 0.2
					d.Color = glow.Color
					if light then
						light.Enabled = true
						light.Color = glow.Color
					end
				else
					d.Transparency = 1
					if light then
						light.Enabled = false
					end
				end
			end
		end
	end
end

----------------------------------------------------------------------
-- Build
----------------------------------------------------------------------
function CarFactory.restHeight(rideHeight: number, wheelRadius: number): number
	return rideHeight + wheelRadius
end

function CarFactory.build(geometryId: string, opts: BuildOptions): Model
	local def = Config.Cars[geometryId]
	assert(def, "unknown geometry " .. geometryId)
	local W, L, BH, CH = def.Width, def.Length, def.BodyHeight, def.CabinHeight
	local WB, R = def.WheelBase, opts.WheelRadius
	local style = if opts.Suv then "suv" else def.Style

	local model = Instance.new("Model")
	model.Name = opts.Name or def.Name
	model:SetAttribute("Kind", opts.Kind)
	model:SetAttribute("Geometry", geometryId)
	model:SetAttribute("W", W)
	model:SetAttribute("L", L)

	local chassis = Instance.new("Part")
	chassis.Name = "Chassis"
	chassis.Size = Vector3.new(W - 0.4, 1.4, L - 0.6)
	chassis.CFrame = CFrame.new()
	chassis.Transparency = 1
	chassis.CanCollide = true
	chassis.CustomPhysicalProperties = PhysicalProperties.new(2, 0.1, 0, 10, 1)
	chassis.Parent = model
	model.PrimaryPart = chassis

	local yB = -0.5 -- body bottom
	local yT = yB + BH -- deck top
	model:SetAttribute("DeckTop", yT)

	-- cabin layout per style
	local cabinL, cabinZ, fastback = L * 0.45, 0, false
	if style == "hatch" then
		cabinL, cabinZ = L * 0.55, L * 0.12
	elseif style == "coupe" then
		cabinL, cabinZ, fastback = L * 0.38, L * 0.04, true
	elseif style == "sedan" then
		cabinL, cabinZ = L * 0.42, L * 0.02
	elseif style == "muscle" then
		cabinL, cabinZ, fastback = L * 0.34, L * 0.08, true
	elseif style == "truck" then
		cabinL, cabinZ = L * 0.26, -L * 0.1
	elseif style == "suv" then
		cabinL, cabinZ = L * 0.6, L * 0.12
	elseif style == "super" then
		cabinL, cabinZ, fastback = L * 0.32, L * 0.0, true
	end
	local paintColor = Color3.new(1, 1, 1)

	-- lower body
	if style == "truck" then
		local bedTop = yT + 0.8
		paint(addPart(model, chassis, Vector3.new(W, BH, L * 0.5), CFrame.new(0, yB + BH / 2, -L * 0.25), paintColor))
		paint(addPart(model, chassis, Vector3.new(W, BH * 0.6, L * 0.5), CFrame.new(0, yB + BH * 0.3, L * 0.25), paintColor))
		for _, x in { -W / 2 + 0.2, W / 2 - 0.2 } do
			paint(addPart(model, chassis, Vector3.new(0.4, bedTop - (yB + BH * 0.6) + 0.6, L * 0.5), CFrame.new(x, (bedTop + yB + BH * 0.6) / 2, L * 0.25), paintColor))
		end
		paint(addPart(model, chassis, Vector3.new(W, bedTop - (yB + BH * 0.6) + 0.6, 0.4), CFrame.new(0, (bedTop + yB + BH * 0.6) / 2, L / 2 - 0.2), paintColor))
		model:SetAttribute("DeckTop", bedTop)
	else
		paint(addPart(model, chassis, Vector3.new(W, BH, L), CFrame.new(0, yB + BH / 2, 0), paintColor))
		-- hood bulge
		paint(addPart(model, chassis, Vector3.new(W - 1.6, 0.3, L * 0.25), CFrame.new(0, yT + 0.15, -L * 0.3), paintColor))
	end
	if style == "muscle" then
		addPart(model, chassis, Vector3.new(1.6, 0.6, 2.2), CFrame.new(0, yT + 0.5, -L * 0.28), DARK)
	elseif style == "super" then
		for _, x in { -W / 2 - 0.02, W / 2 + 0.02 } do
			addPart(model, chassis, Vector3.new(0.1, BH * 0.5, 2.4), CFrame.new(x, yB + BH * 0.55, L * 0.12), DARK)
		end
	end

	-- cabin: glass box + roof + sloped windshield
	local glass = addPart(model, chassis, Vector3.new(W - 0.7, CH, cabinL), CFrame.new(0, yT + CH / 2, cabinZ), Color3.fromRGB(20, 25, 35), Enum.Material.Glass)
	glass:SetAttribute("Glass", true)
	paint(addPart(model, chassis, Vector3.new(W - 0.6, 0.3, cabinL - 0.4), CFrame.new(0, yT + CH + 0.15, cabinZ), paintColor))
	local shield = addPart(model, chassis, Vector3.new(W - 0.7, CH, CH * 0.9), CFrame.new(0, yT + CH / 2, cabinZ - cabinL / 2 - CH * 0.45), Color3.fromRGB(20, 25, 35), Enum.Material.Glass, "WedgePart")
	shield:SetAttribute("Glass", true)
	if fastback then
		local rear = addPart(model, chassis, Vector3.new(W - 0.7, CH, CH * 1.6), CFrame.new(0, yT + CH / 2, cabinZ + cabinL / 2 + CH * 0.8) * CFrame.Angles(0, math.pi, 0), Color3.fromRGB(20, 25, 35), Enum.Material.Glass, "WedgePart")
		rear:SetAttribute("Glass", true)
	end
	-- pillars
	for _, x in { -(W / 2 - 0.4), W / 2 - 0.4 } do
		paint(addPart(model, chassis, Vector3.new(0.25, CH, 0.4), CFrame.new(x, yT + CH / 2, cabinZ - cabinL / 2 + 0.2), paintColor))
		paint(addPart(model, chassis, Vector3.new(0.25, CH, 0.4), CFrame.new(x, yT + CH / 2, cabinZ + cabinL / 2 - 0.2), paintColor))
	end

	-- bumpers, lights, mirrors, plate
	addPart(model, chassis, Vector3.new(W + 0.1, 0.9, 0.6), CFrame.new(0, yB + 0.45, -L / 2 - 0.2), TRIM)
	addPart(model, chassis, Vector3.new(W + 0.1, 0.9, 0.6), CFrame.new(0, yB + 0.45, L / 2 + 0.2), TRIM)
	for _, x in { -(W / 2 - 1), W / 2 - 1 } do
		local head = addPart(model, chassis, Vector3.new(1.4, 0.5, 0.2), CFrame.new(x, yT - 0.45, -L / 2 - 0.05), Color3.fromRGB(255, 250, 230), Enum.Material.Neon)
		local spot = Instance.new("SpotLight")
		spot.Name = "Headlight"
		spot.Face = Enum.NormalId.Front
		spot.Range = 70
		spot.Angle = 70
		spot.Brightness = 3
		spot.Enabled = false
		spot.Parent = head
		CollectionService:AddTag(spot, "CarLight")
		local tail = addPart(model, chassis, Vector3.new(1.4, 0.5, 0.2), CFrame.new(x, yT - 0.45, L / 2 + 0.05), Color3.fromRGB(200, 0, 0), Enum.Material.Neon)
		tail.Name = "Taillight"
		paint(addPart(model, chassis, Vector3.new(0.6, 0.4, 0.3), CFrame.new(if x < 0 then -W / 2 - 0.2 else W / 2 + 0.2, yT + 0.4, cabinZ - cabinL / 2 + 0.4), paintColor))
	end
	addPart(model, chassis, Vector3.new(2, 0.6, 0.05), CFrame.new(0, yB + 1.2, L / 2 + 0.03), Color3.fromRGB(240, 240, 240))

	-- underglow
	local glow = addPart(model, chassis, Vector3.new(W - 1.2, 0.1, L - 2), CFrame.new(0, yB - 0.05, 0), Color3.new(0, 0, 0), Enum.Material.Neon)
	glow.Name = "Underglow"
	glow.Transparency = 1
	local glowLight = Instance.new("PointLight")
	glowLight.Range = 14
	glowLight.Brightness = 3
	glowLight.Enabled = false
	glowLight.Parent = glow

	-- wheels
	local rest = opts.RideHeight
	for _, name in { "FL", "FR", "RL", "RR" } do
		local front = string.sub(name, 1, 1) == "F"
		local left = string.sub(name, 2, 2) == "L"
		local pos = Vector3.new((if left then -1 else 1) * (W / 2 - 0.55), 0, (if front then -1 else 1) * WB / 2)
		local att = Instance.new("Attachment")
		att.Name = "Wheel" .. name
		att.Position = pos
		att.Parent = chassis

		local tire = Instance.new("Part")
		tire.Name = "Tire" .. name
		tire.Shape = Enum.PartType.Cylinder
		tire.Size = Vector3.new(1.1, R * 2, R * 2)
		tire.Color = Color3.fromRGB(22, 22, 22)
		tire.Material = Enum.Material.Rubber
		tire.CanCollide = false
		tire.CanQuery = false
		tire.CanTouch = false
		tire.Massless = true
		local c0 = CFrame.new(pos - Vector3.new(0, rest, 0))
		tire.CFrame = chassis.CFrame * c0
		tire.Parent = model
		local weld = Instance.new("Weld")
		weld.Name = "Weld_" .. name
		weld.Part0 = chassis
		weld.Part1 = tire
		weld.C0 = c0
		weld.Parent = chassis

		local rim = Instance.new("Part")
		rim.Name = "Rim"
		rim.Shape = Enum.PartType.Cylinder
		rim.Size = Vector3.new(1.16, R * 1.3, R * 1.3)
		rim.Material = Enum.Material.Metal
		rim.CanCollide = false
		rim.CanQuery = false
		rim.CanTouch = false
		rim.Massless = true
		rim.CFrame = tire.CFrame
		rim:SetAttribute("Rim", true)
		rim.Parent = model
		local rw = Instance.new("WeldConstraint")
		rw.Part0 = tire
		rw.Part1 = rim
		rw.Parent = rim
		-- hub cap
		local hub = Instance.new("Part")
		hub.Name = "Hub"
		hub.Shape = Enum.PartType.Cylinder
		hub.Size = Vector3.new(1.2, R * 0.4, R * 0.4)
		hub.Color = TRIM
		hub.CanCollide = false
		hub.CanQuery = false
		hub.CanTouch = false
		hub.Massless = true
		hub.CFrame = tire.CFrame
		hub.Parent = model
		local hw = Instance.new("WeldConstraint")
		hw.Part0 = tire
		hw.Part1 = hub
		hw.Parent = hub
	end

	-- seats
	if opts.Kind ~= "Traffic" then
		local seatY = yT - 1.3
		local frontZ = if def.Seats > 2 then cabinZ - cabinL * 0.15 else cabinZ
		local function seat(cls: string, name: string, x: number, z: number): Seat | VehicleSeat
			local s = Instance.new(cls :: any) :: any
			s.Name = name
			s.Size = Vector3.new(1.8, 0.4, 1.8)
			s.CFrame = chassis.CFrame * CFrame.new(x, seatY, z)
			s.Transparency = 1
			s.CanCollide = false
			s.CanTouch = false -- only enter via prompts
			s.Massless = true
			s.Parent = model
			local w = Instance.new("WeldConstraint")
			w.Part0 = chassis
			w.Part1 = s
			w.Parent = s
			return s
		end
		local driver = seat("VehicleSeat", "DriverSeat", -W / 4, frontZ) :: VehicleSeat
		driver.MaxSpeed = 0
		driver.Torque = 0
		driver.TurnSpeed = 0
		driver.HeadsUpDisplay = false
		if opts.Kind == "Player" then
			seat("Seat", "PassengerSeat", W / 4, frontZ)
			if def.Seats > 2 and style ~= "truck" then
				seat("Seat", "RearSeatL", -W / 4, cabinZ + cabinL * 0.3)
				seat("Seat", "RearSeatR", W / 4, cabinZ + cabinL * 0.3)
			end
			for _, side in { -1, 1 } do
				local att = Instance.new("Attachment")
				att.Name = if side < 0 then "DriverDoor" else "PassengerDoor"
				att.Position = Vector3.new(side * (W / 2 + 0.5), 0.5, frontZ)
				att.Parent = chassis
				local pp = Instance.new("ProximityPrompt")
				pp.Name = if side < 0 then "DrivePrompt" else "RidePrompt"
				pp.ActionText = if side < 0 then "Drive" else "Ride"
				pp.ObjectText = def.Name
				pp.KeyboardKeyCode = if side < 0 then Enum.KeyCode.E else Enum.KeyCode.R
				pp.GamepadKeyCode = if side < 0 then Enum.KeyCode.ButtonY else Enum.KeyCode.ButtonX
				pp.HoldDuration = 0
				pp.MaxActivationDistance = 10
				pp.RequiresLineOfSight = false
				pp.Parent = att
			end
		end
	end

	-- police livery & lightbar
	if opts.Kind == "Police" then
		for _, side in { -1, 1 } do
			local door = addPart(model, chassis, Vector3.new(0.1, BH * 0.7, L * 0.38), CFrame.new(side * (W / 2 + 0.03), yB + BH * 0.5, cabinZ), Color3.fromRGB(240, 240, 240))
			local gui = Instance.new("SurfaceGui")
			gui.Face = if side < 0 then Enum.NormalId.Left else Enum.NormalId.Right
			gui.Parent = door
			local label = Instance.new("TextLabel")
			label.Size = UDim2.fromScale(1, 1)
			label.BackgroundTransparency = 1
			label.Text = "POLICE"
			label.TextScaled = true
			label.FontFace = Font.fromEnum(Enum.Font.GothamBlack)
			label.TextColor3 = Color3.fromRGB(20, 40, 120)
			label.Parent = gui
		end
		local barY = yT + CH + 0.55
		addPart(model, chassis, Vector3.new(W - 1.6, 0.3, 1.2), CFrame.new(0, barY - 0.25, cabinZ), DARK)
		for _, side in { -1, 1 } do
			local color = if side < 0 then Color3.fromRGB(255, 20, 20) else Color3.fromRGB(20, 60, 255)
			local light = addPart(model, chassis, Vector3.new((W - 1.8) / 2, 0.4, 1), CFrame.new(side * (W - 1.8) / 4, barY, cabinZ), color, Enum.Material.Neon)
			light:SetAttribute("LightColor", color)
			light.Name = "Lightbar"
			local pl = Instance.new("PointLight")
			pl.Color = color
			pl.Range = 30
			pl.Brightness = 4
			pl.Enabled = false
			pl.Parent = light
			CollectionService:AddTag(light, "Lightbar")
		end
		-- push bar
		addPart(model, chassis, Vector3.new(W - 1, 1.4, 0.4), CFrame.new(0, yB + 0.9, -L / 2 - 0.6), DARK)
	end

	model:SetAttribute("RestHeight", CarFactory.restHeight(opts.RideHeight, R))
	model:SetAttribute("Spoiler", "None")
	local cosmetics = opts.Cosmetics
		or { Paint = def.DefaultPaint, Finish = "Gloss", Rims = "Silver", Underglow = "Off", Spoiler = "None", Tint = "Light" }
	if opts.Kind == "Police" then
		cosmetics = { Paint = "Jet Black", Finish = "Gloss", Rims = "Black", Underglow = "Off", Spoiler = "None", Tint = "Dark" }
	end
	CarFactory.applyCosmetics(model, cosmetics)
	return model
end

-- Place a built car so it rests on the ground at `cf` (cf = ground point + facing)
function CarFactory.place(model: Model, cf: CFrame)
	local h = model:GetAttribute("RestHeight") :: number
	model:PivotTo(cf * CFrame.new(0, h, 0))
end

return CarFactory
