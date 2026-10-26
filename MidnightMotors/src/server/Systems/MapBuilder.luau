--!strict
-- Builds the whole world procedurally at server start:
--   * an 18x18 block city: downtown towers, mid-rise, suburbs, industrial
--   * an elevated highway ring around the city with diamond interchanges
--     (exit/entrance ramps) where the avenues pass underneath
--   * a long elevated interstate east to the outskirts, with interchanges
--   * quarter-mile and half-mile drag strips with christmas trees
--   * gas stations, garages, a police station, car-meet lots, speed cameras
-- Everything other systems need (lanes, pumps, zones...) is exposed in Layout.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)
local Lanes = require(script.Parent.Lanes)

local MapBuilder = {}

local M = Config.Map
local N = M.CityBlocks
local CELL = M.CellSize
local C = N * CELL / 2 -- city half extent (outer road centreline)
local RW = M.RoadWidth
local H = M.RingHalfSize
local HW = M.HighwayWidth / 2
local X0 = H + HW -- interstate start
local X1 = X0 + M.InterstateLength -- interstate end (back at ground level)
local DECK_TOP = M.DeckHeight -- elevated highway surface height
local AVENUES = { -6 * CELL, 0, 6 * CELL } -- avenues with highway interchanges
local DX = X1 + 150 - 7350 -- offset applied to the track complex layout

local ROAD_TOP = 0.2
local WALK_TOP = 0.6
local LOT_TOP = 0.65
local MAX_PART = 2000

local ASPHALT = Color3.fromRGB(38, 38, 42)
local HIGHWAY = Color3.fromRGB(48, 48, 52)
local CONCRETE = Color3.fromRGB(160, 160, 155)
local WHITE = Color3.fromRGB(235, 235, 235)
local YELLOW = Color3.fromRGB(240, 190, 20)

-- Deterministic Park-Miller RNG (instead of Roblox's Random) so the map built
-- into the place file for edit-mode preview matches the one built at runtime.
local rngState = 20261025
local rng = {}
local function nextRaw(): number
	rngState = (rngState * 16807) % 2147483647
	return rngState / 2147483647
end
function rng:NextNumber(a: number?, b: number?): number
	local lo, hi = a or 0, b or 1
	return lo + nextRaw() * (hi - lo)
end
function rng:NextInteger(a: number, b: number): number
	return math.min(b, a + math.floor(nextRaw() * (b - a + 1)))
end

export type TreeLights = { Stage: BasePart, Amber: { BasePart }, Green: BasePart, Red: BasePart }
export type Strip = {
	Name: string,
	StartX: number,
	FinishX: number,
	EndX: number,
	Lanes: { { Z: number, Tree: TreeLights } },
	Board: TextLabel,
}

MapBuilder.Layout = {
	GasPumps = {} :: { BasePart },
	Garages = {} :: { { Name: string, Terminal: BasePart, Pads: { CFrame } } },
	PoliceStation = CFrame.new(),
	Meets = {} :: { { Name: string, CFrame: CFrame, Size: Vector3 } },
	Strips = {} :: { [string]: Strip },
	SpeedCameras = {} :: { { Position: Vector3, Flash: BasePart } },
	Spawn = CFrame.new(),
	TrackBox = { Min = Vector3.new(DX + 7000, -50, -900), Max = Vector3.new(DX + 11300, 500, -60) },
}
local Layout = MapBuilder.Layout

local root: Folder
local folders: { [string]: Folder } = {}

----------------------------------------------------------------------
-- Part helpers
----------------------------------------------------------------------
local function newPart(parent: Instance, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Parent = parent
	return p
end

-- Like newPart but splits anything longer than the engine's part size limit
local function box(parent: Instance, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): { Part }
	local out = {}
	local longest = math.max(size.X, size.Z)
	if longest <= MAX_PART then
		table.insert(out, newPart(parent, size, cf, color, material))
		return out
	end
	local n = math.ceil(longest / MAX_PART)
	for i = 1, n do
		local f = (i - 0.5) / n - 0.5
		if size.X >= size.Z then
			local seg = Vector3.new(size.X / n, size.Y, size.Z)
			table.insert(out, newPart(parent, seg, cf * CFrame.new(f * size.X, 0, 0), color, material))
		else
			local seg = Vector3.new(size.X, size.Y, size.Z / n)
			table.insert(out, newPart(parent, seg, cf * CFrame.new(0, 0, f * size.Z), color, material))
		end
	end
	return out
end

-- Flat strip between two XZ points, with its top surface at topY
local function strip(parent: Instance, a: Vector3, b: Vector3, width: number, height: number, topY: number, color: Color3, material: Enum.Material?): { Part }
	local a2 = Vector3.new(a.X, 0, a.Z)
	local b2 = Vector3.new(b.X, 0, b.Z)
	local len = (b2 - a2).Magnitude
	local centre = (a2 + b2) / 2 + Vector3.new(0, topY - height / 2, 0)
	local cf = CFrame.lookAt(centre, centre + (b2 - a2).Unit)
	return box(parent, Vector3.new(width, height, len), cf, color, material)
end

local function v(x: number, z: number): Vector3
	return Vector3.new(x, 0, z)
end

local function sign(parent: Instance, text: string, size: Vector3, cf: CFrame, bg: Color3, fg: Color3): (Part, TextLabel)
	local p = newPart(parent, size, cf, bg, Enum.Material.SmoothPlastic)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 20
	gui.LightInfluence = 0
	gui.Parent = p
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextScaled = true
	label.FontFace = Font.fromEnum(Enum.Font.GothamBlack)
	label.TextColor3 = fg
	label.Parent = gui
	return p, label
end

local function prompt(parent: BasePart, action: string, object: string, hold: number, dist: number): ProximityPrompt
	local pp = Instance.new("ProximityPrompt")
	pp.ActionText = action
	pp.ObjectText = object
	pp.HoldDuration = hold
	pp.MaxActivationDistance = dist
	pp.RequiresLineOfSight = false
	pp.Parent = parent
	return pp
end

local function lamp(parent: Instance, pos: Vector3, height: number, withLight: boolean)
	newPart(parent, Vector3.new(0.8, height, 0.8), CFrame.new(pos + Vector3.new(0, height / 2, 0)), Color3.fromRGB(60, 60, 65), Enum.Material.Metal)
	local head = newPart(parent, Vector3.new(3, 0.6, 1.6), CFrame.new(pos + Vector3.new(0, height, 0)), Color3.fromRGB(255, 230, 170), Enum.Material.Neon)
	head.CanCollide = false
	if withLight then
		local light = Instance.new("PointLight")
		light.Range = 60
		light.Brightness = 2
		light.Color = Color3.fromRGB(255, 220, 160)
		light.Parent = head
	end
end

local function tree(parent: Instance, pos: Vector3, scale: number)
	newPart(parent, Vector3.new(1.5, 10, 1.5) * scale, CFrame.new(pos + Vector3.new(0, 5 * scale, 0)), Color3.fromRGB(90, 60, 35), Enum.Material.Wood)
	local leaves = newPart(parent, Vector3.new(11, 11, 11) * scale, CFrame.new(pos + Vector3.new(0, 13 * scale, 0)), Color3.fromRGB(40, 110 + rng:NextInteger(0, 40), 45), Enum.Material.Grass)
	leaves.Shape = Enum.PartType.Ball
end

----------------------------------------------------------------------
-- Buildings & special lots
----------------------------------------------------------------------
local BUILDING_COLORS = {
	Color3.fromRGB(120, 120, 125),
	Color3.fromRGB(150, 140, 125),
	Color3.fromRGB(95, 70, 60),
	Color3.fromRGB(180, 175, 165),
	Color3.fromRGB(60, 70, 85),
	Color3.fromRGB(130, 90, 70),
	Color3.fromRGB(200, 195, 180),
}

local HOUSE_COLORS = {
	Color3.fromRGB(230, 220, 200),
	Color3.fromRGB(200, 215, 230),
	Color3.fromRGB(235, 205, 180),
	Color3.fromRGB(210, 230, 205),
	Color3.fromRGB(240, 240, 235),
	Color3.fromRGB(190, 170, 150),
}

local function tower(parent: Instance, pos: Vector3, fx: number, fz: number, h: number, glassy: boolean)
	local color = BUILDING_COLORS[rng:NextInteger(1, #BUILDING_COLORS)]
	local material = if glassy
		then Enum.Material.Glass
		else ({ Enum.Material.Concrete, Enum.Material.Brick, Enum.Material.SmoothPlastic })[rng:NextInteger(1, 3)]
	if glassy then
		color = ({ Color3.fromRGB(60, 85, 110), Color3.fromRGB(40, 60, 80), Color3.fromRGB(90, 110, 120) })[rng:NextInteger(1, 3)]
	end
	local b = newPart(parent, Vector3.new(fx, h, fz), CFrame.new(pos + Vector3.new(0, WALK_TOP + h / 2, 0)), color, material)
	if glassy then
		b.Reflectance = 0.25
	end
	newPart(parent, Vector3.new(fx + 1, 2, fz + 1), CFrame.new(pos + Vector3.new(0, WALK_TOP + h + 1, 0)), Color3.fromRGB(50, 50, 55), Enum.Material.Concrete)
	if glassy and h > 200 then
		-- setback crown on the tallest towers
		newPart(parent, Vector3.new(fx * 0.6, h * 0.12, fz * 0.6), CFrame.new(pos + Vector3.new(0, WALK_TOP + h + h * 0.06, 0)), color, material)
	elseif not glassy and h > 60 then
		local bands = math.min(10, math.floor(h / 28))
		for i = 1, bands do
			local band = newPart(parent, Vector3.new(fx + 0.4, 5, fz + 0.4), CFrame.new(pos + Vector3.new(0, WALK_TOP + i * 28 - 10, 0)), Color3.fromRGB(40, 55, 75), Enum.Material.Glass)
			band.Reflectance = 0.3
		end
	end
end

local function house(parent: Instance, pos: Vector3)
	local color = HOUSE_COLORS[rng:NextInteger(1, #HOUSE_COLORS)]
	local roof = ({ Color3.fromRGB(110, 50, 40), Color3.fromRGB(60, 60, 65), Color3.fromRGB(90, 70, 50) })[rng:NextInteger(1, 3)]
	local w, d, h = rng:NextNumber(38, 48), rng:NextNumber(30, 38), rng:NextNumber(14, 22)
	local base = pos + Vector3.new(0, WALK_TOP + 0.2, 0)
	newPart(parent, Vector3.new(w, h, d), CFrame.new(base + Vector3.new(0, h / 2, 0)), color, Enum.Material.SmoothPlastic)
	-- gable roof from two wedges
	local rh = 8
	local front = Instance.new("WedgePart")
	front.Anchored = true
	front.Size = Vector3.new(w + 2, rh, d / 2 + 1)
	front.CFrame = CFrame.new(base + Vector3.new(0, h + rh / 2, -d / 4 - 0.5))
	front.Color = roof
	front.Parent = parent
	local back = front:Clone()
	back.CFrame = CFrame.new(base + Vector3.new(0, h + rh / 2, d / 4 + 0.5)) * CFrame.Angles(0, math.pi, 0)
	back.Parent = parent
	-- door
	newPart(parent, Vector3.new(4, 8, 0.4), CFrame.new(base + Vector3.new(0, 4, -d / 2 - 0.2)), Color3.fromRGB(90, 55, 35), Enum.Material.Wood)
end

local function buildBlockBuildings(centre: Vector3)
	local parent = folders.Buildings
	local cheb = math.max(math.abs(centre.X), math.abs(centre.Z)) / C
	if cheb < 0.3 then
		-- downtown: tall towers, mostly glass
		local downtown = 1 - cheb / 0.3
		for lx = -1, 1, 2 do
			for lz = -1, 1, 2 do
				local h = 110 + downtown * 380 * rng:NextNumber(0.5, 1) + rng:NextNumber(0, 40)
				tower(parent, centre + Vector3.new(lx * 58, 0, lz * 58), rng:NextNumber(70, 100), rng:NextNumber(70, 100), h, rng:NextNumber() < 0.75)
			end
		end
	elseif cheb < 0.62 or (cheb < 0.75 and rng:NextNumber() < 0.4) then
		-- mid-rise: offices and apartments
		for lx = -1, 1, 2 do
			for lz = -1, 1, 2 do
				local h = rng:NextNumber(35, 140) * (1.4 - cheb)
				tower(parent, centre + Vector3.new(lx * 58, 0, lz * 58), rng:NextNumber(60, 100), rng:NextNumber(60, 100), h, rng:NextNumber() < 0.15)
			end
		end
	elseif centre.X > 0 and centre.Z > 0 then
		-- industrial (south-east): warehouses and a chimney
		for _, lz in { -58, 58 } do
			local h = rng:NextNumber(24, 40)
			local wh = newPart(parent, Vector3.new(210, h, 92), CFrame.new(centre + Vector3.new(0, WALK_TOP + h / 2, lz)), Color3.fromRGB(150, 150, 155), Enum.Material.Metal)
			wh.Name = "Warehouse"
			newPart(parent, Vector3.new(30, 18, 0.5), CFrame.new(centre + Vector3.new(rng:NextNumber(-70, 70), WALK_TOP + 9, lz - 46.3)), Color3.fromRGB(70, 75, 80), Enum.Material.DiamondPlate)
		end
		if rng:NextNumber() < 0.35 then
			newPart(parent, Vector3.new(8, 90, 8), CFrame.new(centre + Vector3.new(90, WALK_TOP + 45, 0)), Color3.fromRGB(130, 80, 60), Enum.Material.Brick)
		end
	else
		-- suburbs: lawns, houses and trees
		newPart(parent, Vector3.new(CELL - RW - 16, 0.2, CELL - RW - 16), CFrame.new(centre + Vector3.new(0, WALK_TOP + 0.1, 0)), Color3.fromRGB(85, 150, 70), Enum.Material.Grass)
		for _, lx in { -75, 0, 75 } do
			for _, lz in { -62, 62 } do
				house(parent, centre + Vector3.new(lx, 0, lz))
			end
		end
		for _ = 1, 2 do
			tree(parent, centre + Vector3.new(rng:NextNumber(-100, 100), WALK_TOP, rng:NextNumber(-12, 12)), rng:NextNumber(0.7, 1.1))
		end
	end
end

local function lotSlab(parent: Instance, centre: Vector3, size: Vector3, color: Color3, material: Enum.Material)
	newPart(parent, Vector3.new(size.X, 1, size.Z), CFrame.new(centre.X, LOT_TOP - 0.5, centre.Z), color, material)
end

local function buildGasStation(centre: Vector3, name: string)
	local parent = folders.Props
	lotSlab(parent, centre, Vector3.new(200, 1, 200), Color3.fromRGB(130, 130, 128), Enum.Material.Concrete)
	local base = Vector3.new(centre.X, LOT_TOP, centre.Z)
	-- canopy
	for _, o in { Vector3.new(-45, 0, -30), Vector3.new(45, 0, -30), Vector3.new(-45, 0, 30), Vector3.new(45, 0, 30) } do
		newPart(parent, Vector3.new(2, 18, 2), CFrame.new(base + o + Vector3.new(0, 9, 0)), WHITE, Enum.Material.SmoothPlastic)
	end
	newPart(parent, Vector3.new(110, 2, 80), CFrame.new(base + Vector3.new(0, 19, 0)), WHITE, Enum.Material.SmoothPlastic)
	local trim = newPart(parent, Vector3.new(110.4, 1, 80.4), CFrame.new(base + Vector3.new(0, 17.6, 0)), Color3.fromRGB(220, 30, 30), Enum.Material.Neon)
	trim.CanCollide = false
	-- pump islands
	for _, x in { -30, 0, 30 } do
		newPart(parent, Vector3.new(8, 0.6, 18), CFrame.new(base + Vector3.new(x, 0.3, 0)), CONCRETE, Enum.Material.Concrete)
		for _, z in { -5, 5 } do
			local pump = newPart(parent, Vector3.new(3, 6, 2), CFrame.new(base + Vector3.new(x, 3.6, z)), Color3.fromRGB(200, 30, 30), Enum.Material.SmoothPlastic)
			pump.Name = "GasPump"
			local screen = newPart(parent, Vector3.new(2, 1.4, 2.1), CFrame.new(base + Vector3.new(x, 5, z)), Color3.fromRGB(20, 20, 20), Enum.Material.Neon)
			screen.CanCollide = false
			prompt(pump, "Refuel", name, 0.6, 18)
			table.insert(Layout.GasPumps, pump)
		end
	end
	-- store
	newPart(parent, Vector3.new(70, 20, 36), CFrame.new(base + Vector3.new(0, 10, 75)), Color3.fromRGB(210, 205, 195), Enum.Material.Brick)
	sign(parent, name .. " MART", Vector3.new(40, 5, 0.5), CFrame.lookAt(base + Vector3.new(0, 16, 56.8), base + Vector3.new(0, 16, 0)), Color3.fromRGB(200, 30, 30), WHITE)
	-- price sign
	newPart(parent, Vector3.new(1.5, 26, 1.5), CFrame.new(base + Vector3.new(85, 13, -85)), Color3.fromRGB(60, 60, 60), Enum.Material.Metal)
	sign(parent, string.format("GAS\n$%.2f", Config.GasPricePerGallon), Vector3.new(14, 12, 1), CFrame.new(base + Vector3.new(85, 30, -85)), Color3.fromRGB(20, 20, 20), YELLOW)
end

local function buildGarage(centre: Vector3, name: string, facing: Vector3)
	local parent = folders.Props
	-- local frame: building at the back, pads at the front facing the road
	local cf = CFrame.lookAt(Vector3.new(centre.X, LOT_TOP, centre.Z), Vector3.new(centre.X, LOT_TOP, centre.Z) + facing)
	lotSlab(parent, centre, Vector3.new(210, 1, 210), Color3.fromRGB(45, 45, 50), Enum.Material.Asphalt)
	local wallColor = Color3.fromRGB(30, 30, 36)
	newPart(parent, Vector3.new(130, 32, 2), cf * CFrame.new(0, 16, 95), wallColor, Enum.Material.Metal)
	newPart(parent, Vector3.new(2, 32, 60), cf * CFrame.new(-65, 16, 66), wallColor, Enum.Material.Metal)
	newPart(parent, Vector3.new(2, 32, 60), cf * CFrame.new(65, 16, 66), wallColor, Enum.Material.Metal)
	newPart(parent, Vector3.new(132, 2, 62), cf * CFrame.new(0, 33, 66), wallColor, Enum.Material.Metal)
	local neon = newPart(parent, Vector3.new(132, 1, 1), cf * CFrame.new(0, 31.5, 36), Color3.fromRGB(0, 170, 255), Enum.Material.Neon)
	neon.CanCollide = false
	sign(parent, name, Vector3.new(80, 10, 1), cf * CFrame.new(0, 40, 36), Color3.fromRGB(15, 15, 20), Color3.fromRGB(0, 200, 255))
	for i = -1, 1 do
		local l = Instance.new("PointLight")
		l.Range = 40
		l.Brightness = 1.5
		l.Parent = newPart(parent, Vector3.new(6, 0.4, 6), cf * CFrame.new(i * 40, 31.8, 66), Color3.fromRGB(255, 255, 240), Enum.Material.Neon)
	end
	local terminal = newPart(parent, Vector3.new(4, 7, 2), cf * CFrame.new(0, 3.5, 40), Color3.fromRGB(0, 120, 220), Enum.Material.Neon)
	terminal.Name = "GarageTerminal"
	prompt(terminal, "Open Garage", name, 0, 16)
	local pads = {}
	for i = -1, 1 do
		local padCf = cf * CFrame.new(i * 40, 0, -40)
		local pad = newPart(parent, Vector3.new(14, 0.1, 22), padCf * CFrame.new(0, 0.05, 0), Color3.fromRGB(0, 170, 255), Enum.Material.Neon)
		pad.Transparency = 0.6
		pad.CanCollide = false
		pad.CanQuery = false
		-- cars spawn facing the road
		table.insert(pads, CFrame.lookAt(padCf.Position, padCf.Position + facing))
	end
	table.insert(Layout.Garages, { Name = name, Terminal = terminal, Pads = pads })
end

local function buildMeet(centre: Vector3, size: Vector3, name: string)
	local parent = folders.Props
	lotSlab(parent, centre, size, Color3.fromRGB(30, 30, 34), Enum.Material.Asphalt)
	local base = Vector3.new(centre.X, LOT_TOP, centre.Z)
	-- parking stripes in two rows
	for _, rowZ in { -size.Z / 4, size.Z / 4 } do
		local x = -size.X / 2 + 14
		while x < size.X / 2 - 7 do
			local s = newPart(parent, Vector3.new(0.5, 0.05, 22), CFrame.new(base + Vector3.new(x, 0.03, rowZ)), WHITE, Enum.Material.SmoothPlastic)
			s.CanCollide = false
			x += 14
		end
	end
	for _, o in { Vector3.new(-1, 0, -1), Vector3.new(1, 0, -1), Vector3.new(-1, 0, 1), Vector3.new(1, 0, 1) } do
		lamp(parent, base + Vector3.new(o.X * (size.X / 2 - 4), 0, o.Z * (size.Z / 2 - 4)), 24, true)
	end
	newPart(parent, Vector3.new(1.5, 18, 1.5), CFrame.new(base + Vector3.new(0, 9, -size.Z / 2 + 2)), Color3.fromRGB(60, 60, 60), Enum.Material.Metal)
	local s = sign(parent, "CAR MEET\n" .. string.upper(name), Vector3.new(30, 10, 1), CFrame.new(base + Vector3.new(0, 22, -size.Z / 2 + 2)), Color3.fromRGB(15, 10, 25), Color3.fromRGB(255, 60, 200))
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(255, 60, 200)
	glow.Range = 30
	glow.Parent = s
	table.insert(Layout.Meets, { Name = name, CFrame = CFrame.new(base + Vector3.new(0, 10, 0)), Size = Vector3.new(size.X, 30, size.Z) })
end

local function buildPoliceStation(centre: Vector3)
	local parent = folders.Props
	lotSlab(parent, centre, Vector3.new(210, 1, 210), Color3.fromRGB(70, 70, 75), Enum.Material.Asphalt)
	local base = Vector3.new(centre.X, LOT_TOP, centre.Z)
	newPart(parent, Vector3.new(150, 40, 80), CFrame.new(base + Vector3.new(0, 20, 50)), Color3.fromRGB(200, 205, 215), Enum.Material.Concrete)
	newPart(parent, Vector3.new(150.4, 4, 80.4), CFrame.new(base + Vector3.new(0, 30, 50)), Color3.fromRGB(20, 50, 140), Enum.Material.SmoothPlastic)
	sign(parent, "POLICE", Vector3.new(50, 10, 1), CFrame.lookAt(base + Vector3.new(0, 34, 9.4), base + Vector3.new(0, 34, -10)), Color3.fromRGB(20, 50, 140), WHITE)
	Layout.PoliceStation = CFrame.lookAt(base + Vector3.new(0, 3, 0), base + Vector3.new(0, 3, -10))
end

local function buildPark(centre: Vector3)
	local parent = folders.Props
	lotSlab(parent, centre, Vector3.new(212, 1, 212), Color3.fromRGB(60, 140, 60), Enum.Material.Grass)
	local base = Vector3.new(centre.X, LOT_TOP, centre.Z)
	for _ = 1, 16 do
		tree(parent, base + Vector3.new(rng:NextNumber(-95, 95), 0, rng:NextNumber(-95, 95)), rng:NextNumber(0.8, 1.4))
	end
	local f = newPart(parent, Vector3.new(30, 2, 30), CFrame.new(base + Vector3.new(0, 1, 0)), CONCRETE, Enum.Material.Concrete)
	f.Shape = Enum.PartType.Cylinder
	f.CFrame = CFrame.new(base + Vector3.new(0, 1, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	local water = newPart(parent, Vector3.new(1, 26, 26), CFrame.new(base + Vector3.new(0, 1.8, 0)) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(60, 140, 220), Enum.Material.Glass)
	water.Shape = Enum.PartType.Cylinder
	water.Transparency = 0.3
end

local function speedCamera(pos: Vector3)
	local parent = folders.Props
	newPart(parent, Vector3.new(1, 14, 1), CFrame.new(pos + Vector3.new(0, 7, 0)), Color3.fromRGB(70, 70, 70), Enum.Material.Metal)
	newPart(parent, Vector3.new(2.5, 2.5, 3.5), CFrame.new(pos + Vector3.new(0, 15, 0)), Color3.fromRGB(230, 180, 20), Enum.Material.SmoothPlastic)
	local flash = newPart(parent, Vector3.new(1.2, 1.2, 0.3), CFrame.new(pos + Vector3.new(0, 15, -1.9)), Color3.fromRGB(80, 80, 80), Enum.Material.SmoothPlastic)
	flash.CanCollide = false
	table.insert(Layout.SpeedCameras, { Position = pos, Flash = flash })
end

----------------------------------------------------------------------
-- Roads
----------------------------------------------------------------------
-- Barrier along a->b at `offset` (to the right of travel), leaving gaps
-- centred at the given distances along the barrier. Its base sits at baseY.
local function barrier(a: Vector3, b: Vector3, offset: number, gaps: { number }, gapWidth: number, baseY: number?)
	local dir = (b - a).Unit
	local right = dir:Cross(Vector3.yAxis)
	local len = (b - a).Magnitude
	local y = (baseY or ROAD_TOP) + 3
	table.sort(gaps)
	local cursor = 0
	local function piece(from: number, to: number)
		if to - from > 2 then
			strip(folders.Roads, a + dir * from + right * offset, a + dir * to + right * offset, 1.6, 3.2, y, CONCRETE, Enum.Material.Concrete)
		end
	end
	for _, g in gaps do
		piece(cursor, g - gapWidth / 2)
		cursor = math.max(cursor, g + gapWidth / 2)
	end
	piece(cursor, len)
end

-- A sloped slab whose top surface runs from a to b (3D points)
local function ramp(parent: Instance, a: Vector3, b: Vector3, width: number, thickness: number, color: Color3, material: Enum.Material?): Part
	local centre = (a + b) / 2
	local cf = CFrame.lookAt(centre, b) * CFrame.new(0, -thickness / 2, 0)
	return newPart(parent, Vector3.new(width, thickness, (b - a).Magnitude), cf, color, material)
end

-- A multi-lane divided road along a->b (centreline), markings inset from the ends
local function divided(a: Vector3, b: Vector3, halfWidth: number, extend: number, inset: number, color: Color3, topY: number)
	local dir = (b - a).Unit
	local right = dir:Cross(Vector3.yAxis)
	strip(folders.Roads, a - dir * extend, b + dir * extend, halfWidth * 2, 2, topY, color, Enum.Material.Asphalt)
	local la, lb = a + dir * inset, b - dir * inset
	for _, o in { -halfWidth + 2, -24, 24, halfWidth - 2 } do
		strip(folders.Roads, la + right * o, lb + right * o, 0.5, 0.1, topY + 0.05, WHITE)
	end
	for _, o in { -1, 1 } do
		strip(folders.Roads, la + right * o, lb + right * o, 0.5, 0.1, topY + 0.05, YELLOW)
	end
end

local function cityRoad(a: Vector3, b: Vector3)
	strip(folders.Roads, a, b, RW, 1, ROAD_TOP, ASPHALT, Enum.Material.Asphalt)
	strip(folders.Roads, a, b, 0.6, 0.1, ROAD_TOP + 0.05, YELLOW)
end

local function pillar(pos: Vector3, height: number)
	newPart(folders.Roads, Vector3.new(7, height, 7), CFrame.new(pos.X, height / 2, pos.Z), Color3.fromRGB(140, 140, 136), Enum.Material.Concrete)
end

----------------------------------------------------------------------
-- Elevated highway with diamond interchanges
--
-- A highway segment is described in a local frame: `a` is its start on the
-- ground, `d` its direction, `r` = d x Up. The "+" carriageway (offset > 0)
-- travels +d, the "-" carriageway travels -d, so the median is always on the
-- driver's left. At an interchange a surface road crosses under the deck at
-- along-distance s0; each carriageway gets an exit ramp that leaves on the
-- right before the crossing and an entrance ramp that merges after it.
----------------------------------------------------------------------
type Frame = { a: Vector3, d: Vector3, r: Vector3, len: number }

local RAMP_O = 56 -- ramp centreline offset from the highway centreline
local RAMP_W = 16

local function framePoint(f: Frame, s: number, o: number, y: number): Vector3
	return f.a + f.d * s + f.r * o + Vector3.new(0, y, 0)
end

local function buildRamps(f: Frame, s0: number, sides: { number })
	for _, sigma in sides do
		local function P(t: number, o: number, y: number): Vector3
			return framePoint(f, s0 + sigma * t, sigma * o, y)
		end
		local parent = folders.Roads
		-- exit (t < 0, before the crossing) and entrance (t > 0, after it)
		for _, dirSign in { -1, 1 } do
			local tFlatFar, tFlatNear, tGround, tEnd = 560 * dirSign, 440 * dirSign, 80 * dirSign, 20 * dirSign
			-- flat lane alongside the deck (deceleration / acceleration lane)
			strip(parent, P(tFlatFar, RAMP_O, 0), P(tFlatNear, RAMP_O, 0), RAMP_W, 2, DECK_TOP, HIGHWAY, Enum.Material.Asphalt)
			-- the slope
			ramp(parent, P(tFlatNear, RAMP_O, DECK_TOP), P(tGround, RAMP_O, ROAD_TOP), RAMP_W, 2, HIGHWAY, Enum.Material.Asphalt)
			-- short ground link into the crossing road
			strip(parent, P(tGround, RAMP_O, 0), P(tEnd, RAMP_O, 0), RAMP_W, 1, ROAD_TOP, ASPHALT, Enum.Material.Asphalt)
			-- barriers: outer edge all the way, inner edge once the ramp drops below the deck
			local outer = RAMP_O + RAMP_W / 2 + 0.8
			strip(parent, P(tFlatFar, outer, 0), P(tFlatNear, outer, 0), 1.6, 3.2, DECK_TOP + 3, CONCRETE, Enum.Material.Concrete)
			ramp(parent, P(tFlatNear, outer, DECK_TOP + 3), P(tGround, outer, ROAD_TOP + 3), 1.6, 3.2, CONCRETE, Enum.Material.Concrete)
			local inner = RAMP_O - RAMP_W / 2 - 0.8
			local tInner = 400 * dirSign
			local yInner = DECK_TOP - (DECK_TOP - ROAD_TOP) * (40 / 360) -- slope height at t = 400
			ramp(parent, P(tInner, inner, yInner + 3), P(tGround, inner, ROAD_TOP + 3), 1.6, 3.2, CONCRETE, Enum.Material.Concrete)
			-- supports under the slope
			for k = 1, 2 do
				local t = tFlatNear + (tGround - tFlatNear) * (k / 3)
				local y = DECK_TOP + (ROAD_TOP - DECK_TOP) * (k / 3)
				pillar(P(t, RAMP_O, 0), y - 2)
			end
			pillar(P((tFlatFar + tFlatNear) / 2, RAMP_O, 0), DECK_TOP - 2)
		end
	end
end

-- Elevated highway segment: deck, markings, barriers (with gaps where ramps
-- merge or diverge), pillars, and ramps for every crossing in `crossings`.
local function elevated(f: Frame, extend: number, crossings: { { s: number, sides: { number } } }, extraOuterGaps: { [number]: { number } }?)
	local b = framePoint(f, f.len, 0, 0)
	divided(f.a, b, HW, extend, extend, HIGHWAY, DECK_TOP)
	local gapsBySide: { [number]: { number } } = { [1] = {}, [-1] = {} }
	for _, c in crossings do
		for _, sigma in c.sides do
			table.insert(gapsBySide[sigma], c.s - 500 + extend)
			table.insert(gapsBySide[sigma], c.s + 500 + extend)
		end
	end
	if extraOuterGaps then
		for sigma, list in extraOuterGaps do
			for _, g in list do
				table.insert(gapsBySide[sigma], g + extend)
			end
		end
	end
	local a2 = f.a - f.d * extend
	local b2 = b + f.d * extend
	barrier(a2, b2, HW + 1, gapsBySide[1], 120, DECK_TOP)
	barrier(a2, b2, -(HW + 1), gapsBySide[-1], 120, DECK_TOP)
	-- pillars, keeping clear of crossing roads
	local s = 60
	while s < f.len - 40 do
		local clear = true
		for _, c in crossings do
			if math.abs(s - c.s) < 50 then
				clear = false
			end
		end
		if clear then
			for _, o in { -26, 26 } do
				pillar(framePoint(f, s, o, 0), DECK_TOP - 2)
			end
		end
		s += 150
	end
	for _, c in crossings do
		buildRamps(f, c.s, c.sides)
	end
end

local function buildGround()
	for x = -4400, X1 + 4400, 2000 do
		for z = -4400, 4400, 2000 do
			newPart(folders.Ground, Vector3.new(2000, 2, 2000), CFrame.new(x + 1000, -1, z + 1000), Color3.fromRGB(80, 140, 65), Enum.Material.Grass)
		end
	end
	-- scenic hills at the edges
	for i = 1, 24 do
		local x = rng:NextNumber(-4200, X1 + 4000)
		local z = if i % 2 == 0 then rng:NextNumber(4000, 5200) else -rng:NextNumber(4000, 5200)
		local r = rng:NextNumber(700, 1600)
		local hill = newPart(folders.Ground, Vector3.new(r, r, r), CFrame.new(x, -r * 0.3, z), Color3.fromRGB(70, 125, 60), Enum.Material.Grass)
		hill.Shape = Enum.PartType.Ball
	end
end

local function blockCentre(i: number, j: number): Vector3
	return Vector3.new(-C + (i + 0.5) * CELL, 0, -C + (j + 0.5) * CELL)
end

local function buildCity()
	local ext = C + RW / 2
	for i = 0, N do
		local p = -C + i * CELL
		cityRoad(v(p, -ext), v(p, ext))
		cityRoad(v(-ext, p), v(ext, p))
		Lanes.add("StreetX" .. i, "Street", { Vector3.new(p, ROAD_TOP, -C), Vector3.new(p, ROAD_TOP, C) }, 0)
		Lanes.add("StreetZ" .. i, "Street", { Vector3.new(-C, ROAD_TOP, p), Vector3.new(C, ROAD_TOP, p) }, 0)
	end
	-- avenues continue out of the city, under the ring highway (interchanges)
	for _, p in AVENUES do
		for _, sgn in { -1, 1 } do
			local outerEnd = H + HW + 200
			if not (p == 0 and sgn == 1) then -- east z=0 is the interstate junction
				cityRoad(v(sgn * ext, p), v(sgn * outerEnd, p))
			end
			cityRoad(v(p, sgn * ext), v(p, sgn * outerEnd))
		end
	end

	-- streetlights at every intersection
	for i = 0, N do
		for j = 0, N do
			lamp(folders.Props, Vector3.new(-C + i * CELL + RW / 2 + 3, WALK_TOP, -C + j * CELL + RW / 2 + 3), 22, false)
		end
	end

	local special: { [string]: (Vector3) -> () } = {
		["9,9"] = function(c)
			buildGarage(c, "MIDNIGHT MOTORS", Vector3.new(0, 0, -1))
		end,
		["3,9"] = function(c)
			buildGarage(c, "WESTSIDE CUSTOMS", Vector3.new(1, 0, 0))
		end,
		["7,10"] = buildPoliceStation,
		["4,4"] = function(c)
			buildGasStation(c, "FUEL STOP")
		end,
		["13,4"] = function(c)
			buildGasStation(c, "QUICK GAS")
		end,
		["4,13"] = function(c)
			buildGasStation(c, "PETRO")
		end,
		["13,13"] = function(c)
			buildGasStation(c, "FUEL STOP")
		end,
		["9,1"] = function(c)
			buildGasStation(c, "NORTH GAS")
		end,
		["9,16"] = function(c)
			buildGasStation(c, "SOUTH GAS")
		end,
		["11,6"] = function(c)
			buildMeet(c, Vector3.new(232, 1, 232), "Downtown Lot")
		end,
		["5,12"] = function(c)
			buildMeet(c, Vector3.new(232, 1, 232), "Neon Plaza")
		end,
		["15,9"] = function(c)
			buildMeet(c, Vector3.new(232, 1, 232), "Warehouse Lot")
		end,
		["8,8"] = buildPark,
		["10,11"] = buildPark,
	}

	for i = 0, N - 1 do
		for j = 0, N - 1 do
			local centre = blockCentre(i, j)
			local walk = CELL - RW
			newPart(folders.Roads, Vector3.new(walk, 1, walk), CFrame.new(centre.X, WALK_TOP - 0.5, centre.Z), Color3.fromRGB(150, 150, 145), Enum.Material.Concrete)
			local fn = special[i .. "," .. j]
			if fn then
				fn(centre)
			else
				buildBlockBuildings(centre)
			end
		end
	end
end

local function buildRing()
	local corners = { v(-H, -H), v(H, -H), v(H, H), v(-H, H) }
	for i = 1, 4 do
		local a = corners[i]
		local b = corners[i % 4 + 1]
		local d = (b - a).Unit
		local f: Frame = { a = a, d = d, r = d:Cross(Vector3.yAxis), len = 2 * H }
		local crossings = {}
		for _, p in AVENUES do
			local s0 = H + p
			if i >= 3 then
				s0 = H - p
			end
			-- the east side's middle avenue is where the interstate joins instead
			if not (i == 2 and p == 0) then
				table.insert(crossings, { s = s0, sides = { 1, -1 } })
			end
		end
		local extra = if i == 2 then { [-1] = { H } } else nil
		elevated(f, HW, crossings, extra)
		for _, frac in { 0.25, 0.75 } do
			speedCamera(framePoint(f, f.len * frac, 0, DECK_TOP))
		end
	end

	-- inner ("+") lanes travel the corner order, outer ("-") lanes the reverse
	for _, o in { 14, 34 } do
		local r = H + o
		Lanes.add("RingOuter" .. o, "Highway", {
			Vector3.new(r, DECK_TOP, r),
			Vector3.new(r, DECK_TOP, -r),
			Vector3.new(-r, DECK_TOP, -r),
			Vector3.new(-r, DECK_TOP, r),
		}, if o == 14 then 104 else 88)
		local q = H - o
		Lanes.add("RingInner" .. o, "Highway", {
			Vector3.new(q, DECK_TOP, q),
			Vector3.new(-q, DECK_TOP, q),
			Vector3.new(-q, DECK_TOP, -q),
			Vector3.new(q, DECK_TOP, -q),
		}, if o == 14 then 104 else 88)
	end
end

local function buildInterstate()
	local L = M.InterstateLength
	local f: Frame = { a = v(X0, 0), d = Vector3.xAxis, r = Vector3.zAxis, len = L - 500 }
	local gasS, restS = 2500, 5200
	elevated(f, 0, { { s = gasS, sides = { 1, -1 } }, { s = restS, sides = { 1, -1 } } }, nil)

	-- the end of the interstate slopes down to ground level at the outskirts
	local slopeTop = framePoint(f, L - 500, 0, DECK_TOP)
	local slopeBottom = framePoint(f, L - 100, 0, ROAD_TOP)
	ramp(folders.Roads, slopeTop, slopeBottom, HW * 2, 2, HIGHWAY, Enum.Material.Asphalt)
	for _, o in { -(HW + 1), HW + 1 } do
		ramp(folders.Roads, slopeTop + Vector3.new(0, 3, o), slopeBottom + Vector3.new(0, 3, o), 1.6, 3.2, CONCRETE, Enum.Material.Concrete)
	end
	pillar(framePoint(f, L - 400, -26, 0), DECK_TOP * 0.75 - 2)
	pillar(framePoint(f, L - 400, 26, 0), DECK_TOP * 0.75 - 2)
	pillar(framePoint(f, L - 250, -26, 0), DECK_TOP * 0.4 - 2)
	pillar(framePoint(f, L - 250, 26, 0), DECK_TOP * 0.4 - 2)
	divided(v(X1 - 100, 0), v(X1 + 220, 0), HW, 0, 0, HIGHWAY, ROAD_TOP)
	barrier(v(X1 - 100, 0), v(X1 + 220, 0), HW + 1, {}, 0)
	barrier(v(X1 - 100, 0), v(X1 + 220, 0), -(HW + 1), { 250 }, 50)
	strip(folders.Roads, v(X1 + 220, -HW - 2), v(X1 + 220, HW + 2), 3, 6, ROAD_TOP + 6, CONCRETE, Enum.Material.Concrete)

	-- surface roads under the two interchanges
	local gasX, restX = X0 + gasS, X0 + restS
	cityRoad(v(gasX, -240), v(gasX, 340))
	cityRoad(v(restX, -340), v(restX, 240))
	buildGasStation(Vector3.new(gasX + 140, 0, 230), "HIGHWAY 9")
	strip(folders.Roads, v(gasX, 230), v(gasX + 45, 230), 40, 1, ROAD_TOP, ASPHALT, Enum.Material.Asphalt)
	buildMeet(Vector3.new(restX - 150, 0, -210), Vector3.new(240, 1, 220), "Rest Stop")
	strip(folders.Roads, v(restX, -210), v(restX - 35, -210), 40, 1, ROAD_TOP, ASPHALT, Enum.Material.Asphalt)

	for s = 300, L - 600, 300 do
		lamp(folders.Props, framePoint(f, s, 0, DECK_TOP), 26, false)
	end
	for _, s in { 1500, 3800, 6800 } do
		speedCamera(framePoint(f, s, 0, DECK_TOP))
	end
	-- billboards
	for k, s in { 1800, 4600, 7400 } do
		local text = ({ "MIDNIGHT MOTORS\nUPGRADE YOUR RIDE", "DRAG STRIP\nEND OF HIGHWAY", "OBEY THE LIMIT\n70 MPH" })[k]
		local base = framePoint(f, s, -150, 0)
		newPart(folders.Props, Vector3.new(2, 56, 2), CFrame.new(base + Vector3.new(0, 28, 0)), Color3.fromRGB(60, 60, 60), Enum.Material.Metal)
		sign(folders.Props, text, Vector3.new(60, 20, 1), CFrame.lookAt(base + Vector3.new(0, 64, 0), base + Vector3.new(0, 64, 150)), Color3.fromRGB(20, 20, 30), Color3.fromRGB(255, 200, 40))
	end

	-- traffic loops: eastbound z>0, westbound z<0, U-turning at both ends
	for _, o in { 14, 34 } do
		Lanes.add("Interstate" .. o, "Interstate", {
			Vector3.new(X0 + 10, DECK_TOP, o),
			Vector3.new(X1 - 500, DECK_TOP, o),
			Vector3.new(X1 - 100, ROAD_TOP, o),
			Vector3.new(X1 + 150, ROAD_TOP, o),
			Vector3.new(X1 + 150, ROAD_TOP, -o),
			Vector3.new(X1 - 100, ROAD_TOP, -o),
			Vector3.new(X1 - 500, DECK_TOP, -o),
			Vector3.new(X0 + 10, DECK_TOP, -o),
		}, if o == 14 then 112 else 94)
	end
end

local function buildTree(parent: Instance, x: number, laneZs: { number }): { TreeLights }
	local mid = (laneZs[1] + laneZs[2]) / 2
	newPart(parent, Vector3.new(1, 14, 1), CFrame.new(x, ROAD_TOP + 7, mid), Color3.fromRGB(30, 30, 30), Enum.Material.Metal)
	local out = {}
	for li, z in laneZs do
		local side = if z < mid then -1 else 1
		local function light(y: number, color: Color3): BasePart
			local p = newPart(parent, Vector3.new(1, 1, 1), CFrame.new(x - 0.6, ROAD_TOP + y, mid + side * 1.2), color, Enum.Material.SmoothPlastic)
			p.Shape = Enum.PartType.Ball
			p.CanCollide = false
			p:SetAttribute("OnColor", color)
			p.Color = Color3.fromRGB(35, 35, 35)
			return p
		end
		out[li] = {
			Stage = light(13, Color3.fromRGB(255, 255, 255)),
			Amber = { light(11, Color3.fromRGB(255, 170, 0)), light(9.6, Color3.fromRGB(255, 170, 0)), light(8.2, Color3.fromRGB(255, 170, 0)) },
			Green = light(6.8, Color3.fromRGB(0, 255, 60)),
			Red = light(5.4, Color3.fromRGB(255, 0, 0)),
		}
	end
	return out
end

local function buildStrip(name: string, centreZ: number, length: number)
	local parent = folders.Track
	local startX = DX + 7600
	local finishX = startX + length
	local endX = finishX + 600
	strip(parent, v(DX + 7450, centreZ), v(endX, centreZ), 44, 1, ROAD_TOP + 0.05, Color3.fromRGB(55, 55, 58), Enum.Material.Concrete)
	strip(parent, v(DX + 7450, centreZ), v(endX, centreZ), 0.6, 0.1, ROAD_TOP + 0.1, WHITE)
	for _, o in { -23, 23 } do
		strip(parent, v(DX + 7470, centreZ + o), v(endX, centreZ + o), 1.6, 3.5, ROAD_TOP + 3.5, Color3.fromRGB(230, 230, 230), Enum.Material.Concrete)
	end
	strip(parent, v(endX, centreZ - 23), v(endX, centreZ + 23), 4, 6, ROAD_TOP + 6, Color3.fromRGB(210, 40, 40), Enum.Material.Concrete)
	strip(parent, v(startX, centreZ - 22), v(startX, centreZ + 22), 1, 0.1, ROAD_TOP + 0.12, WHITE)
	-- checkered finish line
	for i = 0, 21 do
		for j = 0, 1 do
			local c = if (i + j) % 2 == 0 then WHITE else Color3.fromRGB(15, 15, 15)
			local p = newPart(parent, Vector3.new(1, 0.1, 2), CFrame.new(finishX + j - 0.5, ROAD_TOP + 0.12, centreZ - 21 + i * 2), c)
			p.CanCollide = false
		end
	end
	for _, o in { -24, 24 } do
		newPart(parent, Vector3.new(2, 24, 2), CFrame.new(finishX, ROAD_TOP + 12, centreZ + o), Color3.fromRGB(30, 30, 30), Enum.Material.Metal)
	end
	sign(parent, "FINISH", Vector3.new(1, 6, 50), CFrame.new(finishX, ROAD_TOP + 26, centreZ) * CFrame.Angles(0, -math.pi / 2, 0), Color3.fromRGB(15, 15, 15), WHITE)

	local laneZs = { centreZ - 11, centreZ + 11 }
	local trees = buildTree(parent, startX - 4, laneZs)
	local boardZ = centreZ + (if centreZ > -470 then 40 else -40)
	local _, board = sign(parent, name .. "\nREADY", Vector3.new(30, 12, 1), CFrame.lookAt(Vector3.new(DX + 7470, 20, boardZ), Vector3.new(DX + 7400, 20, boardZ)), Color3.fromRGB(10, 10, 10), Color3.fromRGB(255, 200, 0))
	newPart(parent, Vector3.new(1.5, 14, 1.5), CFrame.new(DX + 7470, 7, boardZ), Color3.fromRGB(40, 40, 40), Enum.Material.Metal)

	Layout.Strips[name] = {
		Name = name,
		StartX = startX,
		FinishX = finishX,
		EndX = endX,
		Lanes = { { Z = laneZs[1], Tree = trees[1] }, { Z = laneZs[2], Tree = trees[2] } },
		Board = board,
	}
end

local function buildTrackComplex()
	-- access road north from the end of the interstate
	strip(folders.Roads, v(DX + 7350, -HW + 2), v(DX + 7350, -840), 44, 1, ROAD_TOP, ASPHALT, Enum.Material.Asphalt)
	strip(folders.Roads, v(DX + 7350, -HW + 2), v(DX + 7350, -840), 0.6, 0.1, ROAD_TOP + 0.05, YELLOW)
	-- pit / staging lot
	lotSlab(folders.Track, Vector3.new(DX + 7416, 0, -470), Vector3.new(92, 1, 270), Color3.fromRGB(50, 50, 55), Enum.Material.Asphalt)

	buildStrip("Quarter", -400, M.QuarterMile)
	buildStrip("Half", -540, M.HalfMile)

	-- grandstand between the strip and the highway
	for i = 0, 5 do
		newPart(folders.Track, Vector3.new(900, 2 + i * 2, 8), CFrame.new(DX + 8300, (2 + i * 2) / 2, -355 + i * 8), Color3.fromRGB(120, 125, 135), Enum.Material.Concrete)
	end
	newPart(folders.Track, Vector3.new(900, 1, 50), CFrame.new(DX + 8300, 26, -335), Color3.fromRGB(200, 30, 30), Enum.Material.Metal)
	for x = 7900, 8700, 200 do
		newPart(folders.Track, Vector3.new(1.5, 26, 1.5), CFrame.new(DX + x, 13, -312), Color3.fromRGB(60, 60, 60), Enum.Material.Metal)
	end
	-- light towers along the strips
	for x = 7700, 10900, 400 do
		lamp(folders.Track, Vector3.new(DX + x, ROAD_TOP, -620), 40, x < 9200)
	end

	buildGarage(Vector3.new(DX + 7190, 0, -200), "STRIP GARAGE", Vector3.new(1, 0, 0))
	buildMeet(Vector3.new(DX + 7190, 0, -470), Vector3.new(260, 1, 220), "Strip Meet")
	buildGasStation(Vector3.new(DX + 7190, 0, -720), "PIT FUEL")
end

local function inBand(x: number, z: number): boolean
	if math.abs(x) < C + 80 and math.abs(z) < C + 80 then
		return true
	end
	if math.abs(math.max(math.abs(x), math.abs(z)) - H) < HW + 250 then
		return true -- ring highway, ramps and crossing roads
	end
	for _, p in AVENUES do
		if (math.abs(x - p) < 45 and math.abs(z) < H + 300) or (math.abs(z - p) < 45 and math.abs(x) < H + 300) then
			return true
		end
	end
	if x > H and x < X1 + 300 and math.abs(z) < HW + 140 then
		return true
	end
	local gasX, restX = X0 + 2500, X0 + 5200
	if math.abs(z) < 380 and (math.abs(x - gasX) < 620 or math.abs(x - restX) < 620) then
		return true
	end
	if x > DX + 6950 and x < DX + 11300 and z > -950 and z < -30 then
		return true
	end
	return false
end

local function buildCountryside()
	local placed = 0
	local attempts = 0
	while placed < 520 and attempts < 8000 do
		attempts += 1
		local x = rng:NextNumber(-4200, X1 + 4000)
		local z = rng:NextNumber(-4200, 4200)
		if not inBand(x, z) then
			tree(folders.Props, Vector3.new(x, 0, z), rng:NextNumber(0.9, 1.8))
			placed += 1
		end
	end
end

local function buildLighting()
	Lighting.Brightness = 2.2
	Lighting.EnvironmentDiffuseScale = 0.6
	Lighting.EnvironmentSpecularScale = 0.8
	Lighting.OutdoorAmbient = Color3.fromRGB(120, 120, 130)
	if not Lighting:FindFirstChildOfClass("Atmosphere") then
		local atm = Instance.new("Atmosphere")
		atm.Density = 0.28
		atm.Haze = 1.2
		atm.Color = Color3.fromRGB(200, 190, 210)
		atm.Decay = Color3.fromRGB(100, 90, 120)
		atm.Parent = Lighting
	end
	if not Lighting:FindFirstChildOfClass("BloomEffect") then
		local bloom = Instance.new("BloomEffect")
		bloom.Intensity = 0.6
		bloom.Size = 30
		bloom.Threshold = 1.6
		bloom.Parent = Lighting
	end
end

----------------------------------------------------------------------
-- Zone queries
----------------------------------------------------------------------
function MapBuilder.isOnTrack(pos: Vector3): boolean
	local b = Layout.TrackBox
	return pos.X > b.Min.X and pos.X < b.Max.X and pos.Z > b.Min.Z and pos.Z < b.Max.Z
end

function MapBuilder.getZone(pos: Vector3): string
	if MapBuilder.isOnTrack(pos) then
		return "Track"
	end
	local x, z = pos.X, pos.Z
	local onDeck = pos.Y > DECK_TOP - 8
	if onDeck and math.abs(math.max(math.abs(x), math.abs(z)) - H) <= HW + 2 then
		return "Highway"
	end
	if x >= X0 - 2 and x <= X1 + 220 and math.abs(z) <= HW + 2 and (onDeck or x > X1 - 520) then
		return "Highway"
	end
	if math.abs(x) <= C + RW and math.abs(z) <= C + RW then
		return "City"
	end
	return "Rural"
end

function MapBuilder.meetAt(pos: Vector3): string?
	for _, meet in Layout.Meets do
		local rel = meet.CFrame:PointToObjectSpace(pos)
		if math.abs(rel.X) <= meet.Size.X / 2 and math.abs(rel.Z) <= meet.Size.Z / 2 and math.abs(rel.Y) <= meet.Size.Y / 2 then
			return meet.Name
		end
	end
	return nil
end

function MapBuilder.init()
	-- The place file ships with a preview copy of the map so it is visible in
	-- edit mode; rebuild it so every part is wired up to the systems below.
	local preview = workspace:FindFirstChild("Map")
	if preview then
		preview:Destroy()
	end
	for _, child in workspace:GetChildren() do
		if child:IsA("SpawnLocation") or (child:IsA("BasePart") and child.Name == "Baseplate") then
			child:Destroy()
		end
	end
	root = Instance.new("Folder")
	root.Name = "Map"
	for _, name in { "Ground", "Roads", "Buildings", "Props", "Track" } do
		local f = Instance.new("Folder")
		f.Name = name
		f.Parent = root
		folders[name] = f
	end

	buildLighting()
	buildGround()
	buildCity()
	buildRing()
	buildInterstate()
	buildTrackComplex()
	buildCountryside()

	-- player spawn at the downtown garage
	local garage = Layout.Garages[1]
	local spawnPos = garage.Terminal.Position + Vector3.new(0, 0, -20)
	local spawn = Instance.new("SpawnLocation")
	spawn.Anchored = true
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.CFrame = CFrame.new(spawnPos.X, LOT_TOP + 0.5, spawnPos.Z)
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.CanQuery = false -- car suspension raycasts must not ride on it
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = root
	Layout.Spawn = spawn.CFrame

	root.Parent = workspace
end

return MapBuilder
