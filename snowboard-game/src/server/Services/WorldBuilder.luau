--!strict
-- Generates the whole map at server start so the place works straight out of Rojo:
-- snowy mountain terrain, five trails (beginner, rail garden, Olympic slopestyle,
-- superpipe and big air), the lobby with leaderboards and teleport pads, and the
-- cabin village with the shop. Swap any piece for hand-built models later; the
-- gameplay code only depends on the "Grindable" tag, pad attributes, the
-- leaderboard "Stat"/"Rows" names and the shop prompt's "OpensShop" attribute.

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Catalog = require(Shared.Catalog)
local Cosmetics = require(Shared.Cosmetics)
local Remotes = require(Shared.Remotes)

local WorldBuilder = {}

---------------------------------------------------------------------------
-- Mountain geometry. The slope runs downhill toward +Z.
---------------------------------------------------------------------------

local TOP_Y, BOTTOM_Y = 260, 0
local TOP_Z, BOTTOM_Z = -1150, -250
local SLOPE_DIR = Vector3.new(0, BOTTOM_Y - TOP_Y, BOTTOM_Z - TOP_Z).Unit
local SLOPE_UP = Vector3.new(0, BOTTOM_Z - TOP_Z, TOP_Y - BOTTOM_Y).Unit
local SLOPE_LENGTH = Vector3.new(0, TOP_Y - BOTTOM_Y, BOTTOM_Z - TOP_Z).Magnitude
local MOUNTAIN_HALF_WIDTH = 400
local SLOPE_ORIGIN = Vector3.new(0, TOP_Y, TOP_Z)

local function surface(x: number, d: number): Vector3
	return SLOPE_ORIGIN + Vector3.new(x, 0, 0) + SLOPE_DIR * d
end

-- CFrame on the slope: looking downhill, up = slope normal, `h` studs above the snow.
local function slopeCF(x: number, d: number, h: number): CFrame
	local pos = surface(x, d) + SLOPE_UP * h
	return CFrame.lookAt(pos, pos + SLOPE_DIR, SLOPE_UP)
end

local function heightAboveSlope(p: Vector3): number
	return (p - SLOPE_ORIGIN):Dot(SLOPE_UP)
end

---------------------------------------------------------------------------
-- Part helpers
---------------------------------------------------------------------------

local SNOW_WHITE = Color3.fromRGB(240, 246, 255)
local WOOD = Color3.fromRGB(120, 78, 45)
local WOOD_DARK = Color3.fromRGB(86, 55, 32)
local METAL = Color3.fromRGB(170, 175, 185)

local function make(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function folder(parent: Instance, name: string): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

local function surfaceText(p: BasePart, face: Enum.NormalId, text: string, textColor: Color3, bg: Color3?, font: Enum.Font?)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 30
	gui.LightInfluence = 0.2
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = bg or Color3.new(0, 0, 0)
	label.BackgroundTransparency = if bg then 0 else 1
	label.TextColor3 = textColor
	label.TextScaled = true
	label.Font = font or Enum.Font.FredokaOne
	label.Text = text
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0.04, 0)
	pad.PaddingRight = UDim.new(0.04, 0)
	pad.PaddingTop = UDim.new(0.08, 0)
	pad.PaddingBottom = UDim.new(0.08, 0)
	pad.Parent = label
	label.Parent = gui
	gui.Parent = p
end

local function billboard(adornee: BasePart, text: string, color: Color3, offset: Vector3)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(260, 70)
	gui.StudsOffsetWorldSpace = offset
	gui.AlwaysOnTop = false
	gui.MaxDistance = 220
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.2
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.Text = text
	label.Parent = gui
	gui.Parent = adornee
end

local function disc(parent: Instance, name: string, center: Vector3, diameter: number, color: Color3, material: Enum.Material?): Part
	local p = make(parent, name, Vector3.new(0.6, diameter, diameter), CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90)), color, material)
	p.Shape = Enum.PartType.Cylinder
	return p
end

local function tree(parent: Instance, base: Vector3, scale: number)
	local m = Instance.new("Model")
	m.Name = "PineTree"
	local trunkH = 4 * scale
	make(m, "Trunk", Vector3.new(1.4 * scale, trunkH, 1.4 * scale), CFrame.new(base + Vector3.new(0, trunkH / 2, 0)), WOOD_DARK, Enum.Material.Wood)
	local y = trunkH * 0.6
	local green = Color3.fromRGB(38, 92, 58)
	for i = 1, 3 do
		local size = (10 - i * 2.4) * scale
		local h = 4.2 * scale
		local layer = make(m, "Needles", Vector3.new(size, h, size), CFrame.new(base + Vector3.new(0, y + h / 2, 0)) * CFrame.Angles(0, math.rad(i * 30), 0), green, Enum.Material.Grass)
		layer.CastShadow = true
		make(m, "SnowCap", Vector3.new(size * 0.85, 0.5 * scale, size * 0.85), layer.CFrame * CFrame.new(0, h / 2 + 0.2 * scale, 0), SNOW_WHITE, Enum.Material.Snow)
		y += h * 0.7
	end
	m.Parent = parent
end

---------------------------------------------------------------------------
-- Terrain & lighting
---------------------------------------------------------------------------

local function buildTerrain()
	local terrain = Workspace.Terrain
	terrain:SetMaterialColor(Enum.Material.Snow, SNOW_WHITE)
	terrain:SetMaterialColor(Enum.Material.Glacier, Color3.fromRGB(190, 225, 255))

	-- Valley floor (lobby, village, run-out).
	terrain:FillBlock(CFrame.new(0, -8, -400), Vector3.new(1400, 16, 1800), Enum.Material.Snow)
	-- The ski slope surface.
	terrain:FillBlock(slopeCF(0, SLOPE_LENGTH / 2, -20), Vector3.new(MOUNTAIN_HALF_WIDTH * 2, 40, SLOPE_LENGTH + 30), Enum.Material.Snow)
	-- Stepped mass underneath so the mountain looks solid from the side.
	local steps = 10
	local stepLen = (BOTTOM_Z - TOP_Z) / steps
	for k = 0, steps - 1 do
		local z0 = TOP_Z + k * stepLen
		local z1 = z0 + stepLen
		local yTop = TOP_Y * (1 - (z1 - TOP_Z) / (BOTTOM_Z - TOP_Z)) - 8
		if yTop > 2 then
			terrain:FillBlock(CFrame.new(0, yTop / 2, (z0 + z1) / 2), Vector3.new(MOUNTAIN_HALF_WIDTH * 2, yTop, stepLen), Enum.Material.Snow)
		end
	end
	-- Summit plateau where every trail starts.
	terrain:FillBlock(CFrame.new(0, TOP_Y / 2, TOP_Z - 75), Vector3.new(MOUNTAIN_HALF_WIDTH * 2, TOP_Y, 150), Enum.Material.Snow)
	-- Rocky backdrop peaks behind the summit.
	for i = -3, 3 do
		local h = 140 + (i % 2) * 60
		terrain:FillBall(Vector3.new(i * 130, TOP_Y + h * 0.3, TOP_Z - 230), h * 0.75, Enum.Material.Snow)
		terrain:FillBall(Vector3.new(i * 130 + 40, TOP_Y + h * 0.15, TOP_Z - 200), h * 0.4, Enum.Material.Glacier)
	end
end

local function setupLighting()
	Lighting.ClockTime = 14.2
	Lighting.Brightness = 3
	Lighting.GlobalShadows = true
	Lighting.Ambient = Color3.fromRGB(110, 120, 140)
	Lighting.OutdoorAmbient = Color3.fromRGB(160, 175, 200)
	Lighting.EnvironmentDiffuseScale = 0.6
	Lighting.EnvironmentSpecularScale = 0.6

	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
	atmosphere.Density = 0.32
	atmosphere.Offset = 0.12
	atmosphere.Color = Color3.fromRGB(205, 225, 255)
	atmosphere.Decay = Color3.fromRGB(110, 140, 185)
	atmosphere.Glare = 0.25
	atmosphere.Haze = 1.4
	atmosphere.Parent = Lighting

	local cc = Lighting:FindFirstChildOfClass("ColorCorrectionEffect") or Instance.new("ColorCorrectionEffect")
	cc.TintColor = Color3.fromRGB(245, 250, 255)
	cc.Contrast = 0.06
	cc.Saturation = 0.08
	cc.Parent = Lighting

	local bloom = Lighting:FindFirstChildOfClass("BloomEffect") or Instance.new("BloomEffect")
	bloom.Intensity = 0.35
	bloom.Size = 30
	bloom.Threshold = 1.6
	bloom.Parent = Lighting
end

---------------------------------------------------------------------------
-- Park features
---------------------------------------------------------------------------

type Segment = { len: number, angle: number } -- angle in degrees relative to the slope

-- Builds a grindable rail or box following `segments`, starting `hStart` studs above
-- the slope at distance `dStart`. Each segment becomes its own tagged part, so
-- kinks chain into combos.
local function railPath(parent: Instance, x: number, dStart: number, hStart: number, segments: { Segment }, kind: "Rail" | "Box", width: number?)
	local model = Instance.new("Model")
	model.Name = kind
	local p = surface(x, dStart) + SLOPE_UP * hStart
	local w = width or 3
	for i, seg in segments do
		local a = math.rad(seg.angle)
		local dir = SLOPE_DIR * math.cos(a) + SLOPE_UP * math.sin(a)
		local up = SLOPE_UP * math.cos(a) - SLOPE_DIR * math.sin(a)
		local center = p + dir * (seg.len / 2)
		local cf = CFrame.lookAt(center, center + dir, up)
		local piece: Part
		if kind == "Rail" then
			piece = make(model, "Rail" .. i, Vector3.new(0.6, 0.6, seg.len), cf * CFrame.new(0, -0.3, 0), METAL, Enum.Material.DiamondPlate)
			piece.Reflectance = 0.15
		else
			piece = make(model, "Box" .. i, Vector3.new(w, 1, seg.len), cf * CFrame.new(0, -0.5, 0), Color3.fromRGB(255, 120, 30), Enum.Material.SmoothPlastic)
			make(model, "Edge", Vector3.new(w + 0.2, 0.08, seg.len), cf * CFrame.new(0, 0.02, 0), METAL, Enum.Material.Metal).CanQuery = false
		end
		piece.CanCollide = false
		CollectionService:AddTag(piece, "Grindable")

		-- Support posts down to the snow.
		local posts = math.max(1, math.floor(seg.len / 12))
		for k = 0, posts do
			local at = p + dir * (seg.len * (k / posts))
			local h = heightAboveSlope(at) - (if kind == "Rail" then 0.6 else 1)
			if h > 0.3 then
				local post = make(model, "Post", Vector3.new(0.4, h, 0.4), CFrame.lookAt(at, at + SLOPE_DIR, SLOPE_UP) * CFrame.new(0, -(if kind == "Rail" then 0.6 else 1) - h / 2, 0), Color3.fromRGB(60, 60, 66), Enum.Material.Metal)
				post.CanCollide = false
				post.CanQuery = false
			end
		end
		p += dir * seg.len
	end
	model.Parent = parent
end

-- Builds a plank ramp along `segments`; positive angles make a kicker, negative an
-- in-run. Returns the end point (the lip).
local function plankPath(parent: Instance, x: number, dStart: number, hStart: number, width: number, segments: { Segment }, color: Color3?): Vector3
	local model = Instance.new("Model")
	model.Name = "Ramp"
	local p = surface(x, dStart) + SLOPE_UP * hStart
	local thick = 1.5
	for _, seg in segments do
		local a = math.rad(seg.angle)
		local dir = SLOPE_DIR * math.cos(a) + SLOPE_UP * math.sin(a)
		local up = SLOPE_UP * math.cos(a) - SLOPE_DIR * math.sin(a)
		local center = p + dir * (seg.len / 2) - up * (thick / 2)
		-- Slight overlap between segments hides seams.
		make(model, "Plank", Vector3.new(width, thick, seg.len + 0.6), CFrame.lookAt(center, center + dir, up), color or SNOW_WHITE, Enum.Material.Snow)

		-- Solid body under the plank.
		local endP = p + dir * seg.len
		local hLow = math.min(heightAboveSlope(p), heightAboveSlope(endP)) - thick
		if hLow > 0.5 then
			local mid = (p + endP) / 2
			local d = (mid - SLOPE_ORIGIN):Dot(SLOPE_DIR)
			make(model, "Body", Vector3.new(width, hLow, seg.len), slopeCF(x, d, hLow / 2), Color3.fromRGB(225, 235, 248), Enum.Material.Snow)
		end
		p = endP
	end
	model.Parent = parent
	return p
end

local function kicker(parent: Instance, x: number, d: number, width: number, segments: { Segment })
	local lip = plankPath(parent, x, d, 0, width, segments)
	-- Back wall of the kicker down to the snow.
	local h = heightAboveSlope(lip)
	local dl = (lip - SLOPE_ORIGIN):Dot(SLOPE_DIR)
	make(parent, "KickerBack", Vector3.new(width, h, 2), slopeCF(x, dl - 1, h / 2), Color3.fromRGB(225, 235, 248), Enum.Material.Snow)
	-- Blue lip line for visibility.
	make(parent, "LipLine", Vector3.new(width, 0.1, 0.8), CFrame.lookAt(lip, lip + SLOPE_DIR, SLOPE_UP) * CFrame.new(0, 0.05, 0.4), Color3.fromRGB(40, 120, 255), Enum.Material.Neon).CanCollide = false
end

local function halfpipe(parent: Instance, x: number, dStart: number, length: number)
	local model = Instance.new("Model")
	model.Name = "Superpipe"
	local flatHalf, radius, segments, maxAngle = 18, 22, 10, 88
	local thick = 2.5
	local dMid = dStart + length / 2
	local step = maxAngle / segments
	for _, side in { -1, 1 } do
		for i = 1, segments do
			local a = math.rad((i - 0.5) * step)
			local lateral = flatHalf + radius * math.sin(a)
			local h = radius * (1 - math.cos(a))
			local normal = SLOPE_UP * math.cos(a) - Vector3.xAxis * side * math.sin(a)
			local surfacePoint = surface(x + side * lateral, dMid) + SLOPE_UP * h
			local center = surfacePoint - normal * (thick / 2)
			local chord = 2 * radius * math.sin(math.rad(step) / 2) + 0.35
			make(model, "Wall", Vector3.new(chord, thick, length), CFrame.lookAt(center, center + SLOPE_DIR, normal), SNOW_WHITE, Enum.Material.Snow)
		end
		-- Deck and coping along the top of each wall.
		local topH = radius * (1 - math.cos(math.rad(maxAngle)))
		local deckW = 14
		local deckLateral = flatHalf + radius + deckW / 2 + 0.6
		make(model, "Deck", Vector3.new(deckW, topH, length), slopeCF(x + side * deckLateral, dMid, topH / 2), Color3.fromRGB(230, 238, 250), Enum.Material.Snow)
		make(model, "Coping", Vector3.new(0.5, 0.5, length), slopeCF(x + side * (flatHalf + radius + 0.3), dMid, topH), Color3.fromRGB(40, 120, 255), Enum.Material.Neon).CanCollide = false
	end
	-- Flat bottom floor slightly above the terrain for a clean groomed look.
	make(model, "Floor", Vector3.new(flatHalf * 2 + 1, 1, length), slopeCF(x, dMid, -0.45), Color3.fromRGB(235, 242, 252), Enum.Material.Snow)
	model.Parent = parent
end

local function gate(parent: Instance, x: number, d: number, width: number, text: string, color: Color3)
	local cf = slopeCF(x, d, 0)
	local h = 12
	for _, side in { -1, 1 } do
		local post = make(parent, "GatePost", Vector3.new(1.2, h, 1.2), CFrame.new((cf * CFrame.new(side * width / 2, 0, 0)).Position + Vector3.new(0, h / 2, 0)), color, Enum.Material.SmoothPlastic)
		post.CanCollide = false
	end
	local bannerPos = cf.Position + Vector3.new(0, h - 1.5, 0)
	local banner = make(parent, "Banner", Vector3.new(width, 3.5, 0.4), CFrame.lookAt(bannerPos, bannerPos - Vector3.new(SLOPE_DIR.X, 0, SLOPE_DIR.Z).Unit), color, Enum.Material.SmoothPlastic)
	banner.CanCollide = false
	surfaceText(banner, Enum.NormalId.Front, text, Color3.new(1, 1, 1), color)
	surfaceText(banner, Enum.NormalId.Back, text, Color3.new(1, 1, 1), color)
end

---------------------------------------------------------------------------
-- Trails
---------------------------------------------------------------------------

type Lane = { id: string, name: string, x: number, color: Color3 }

local LANES: { Lane } = {
	{ id = "Beginner", name = "Beginner Run", x = -300, color = Color3.fromRGB(40, 170, 80) },
	{ id = "Rails", name = "Rail Garden", x = -150, color = Color3.fromRGB(40, 120, 230) },
	{ id = "Slopestyle", name = "Olympic Slopestyle", x = 0, color = Color3.fromRGB(220, 40, 50) },
	{ id = "Halfpipe", name = "Olympic Superpipe", x = 150, color = Color3.fromRGB(140, 60, 210) },
	{ id = "BigAir", name = "Olympic Big Air", x = 300, color = Color3.fromRGB(25, 25, 30) },
}

local function destination(destFolder: Folder, name: string, cf: CFrame)
	local p = make(destFolder, name, Vector3.new(4, 1, 4), cf, Color3.new(1, 1, 1))
	p.Transparency = 1
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
end

local function buildBeginner(parent: Instance, x: number)
	for _, d in { 140, 300, 460, 620 } do
		kicker(parent, x + (if d % 320 == 140 then -15 else 15), d, 18, { { len = 10, angle = 8 }, { len = 8, angle = 16 } })
	end
	railPath(parent, x + 18, 220, 1.2, { { len = 28, angle = 0 } }, "Box", 4)
	railPath(parent, x - 20, 380, 1.2, { { len = 30, angle = 0 } }, "Box", 4)
	railPath(parent, x + 10, 540, 1.2, { { len = 24, angle = 0 }, { len = 16, angle = -6 } }, "Box", 3.5)
	for _, d in { 700, 760 } do
		kicker(parent, x, d, 30, { { len = 8, angle = 6 }, { len = 6, angle = 12 } })
	end
end

local function buildRailGarden(parent: Instance, x: number)
	railPath(parent, x - 20, 80, 2.5, { { len = 40, angle = 0 } }, "Rail")
	railPath(parent, x + 20, 80, 2.5, { { len = 40, angle = 0 } }, "Rail")
	railPath(parent, x, 160, 3.6, { { len = 12, angle = 0 }, { len = 12, angle = -10 }, { len = 12, angle = 0 } }, "Rail")
	railPath(parent, x - 22, 240, 2.4, { { len = 8, angle = 14 }, { len = 8, angle = 5 }, { len = 8, angle = -5 }, { len = 8, angle = -14 } }, "Rail")
	railPath(parent, x + 25, 240, 1, { { len = 30, angle = 0 } }, "Box", 3)
	railPath(parent, x, 320, 3, { { len = 70, angle = 0 } }, "Rail")
	railPath(parent, x + 22, 430, 3.6, { { len = 14, angle = 0 }, { len = 14, angle = -12 } }, "Rail")
	railPath(parent, x - 25, 430, 1, { { len = 20, angle = 0 }, { len = 16, angle = -8 }, { len = 12, angle = 0 } }, "Box", 3)
	railPath(parent, x, 520, 1, { { len = 40, angle = 0 } }, "Box", 6)
	-- Jump-to-rail: small kicker that pops you onto a raised rail.
	kicker(parent, x, 600, 10, { { len = 6, angle = 10 }, { len = 5, angle = 20 } })
	railPath(parent, x, 618, 4.4, { { len = 30, angle = 0 } }, "Rail")
	railPath(parent, x - 18, 700, 2.5, { { len = 50, angle = 0 } }, "Rail")
	railPath(parent, x + 18, 700, 2.5, { { len = 50, angle = 0 } }, "Rail")
end

local function buildSlopestyle(parent: Instance, x: number)
	-- Rail section (top), like an Olympic slopestyle course.
	railPath(parent, x - 22, 60, 2.6, { { len = 36, angle = 0 } }, "Rail")
	railPath(parent, x + 22, 60, 1, { { len = 30, angle = 0 } }, "Box", 3)
	railPath(parent, x, 130, 4, { { len = 14, angle = 0 }, { len = 14, angle = -12 }, { len = 12, angle = 0 } }, "Rail")
	railPath(parent, x - 25, 205, 2.5, { { len = 8, angle = 14 }, { len = 8, angle = 5 }, { len = 8, angle = -5 }, { len = 8, angle = -14 } }, "Rail")
	railPath(parent, x + 25, 205, 1, { { len = 18, angle = 6 }, { len = 18, angle = -6 } }, "Box", 3)
	-- Jump section: three big kickers.
	for _, d in { 320, 470, 620 } do
		kicker(parent, x, d, 28, { { len = 14, angle = 10 }, { len = 12, angle = 20 }, { len = 10, angle = 28 } })
	end
	railPath(parent, x - 30, 760, 3, { { len = 40, angle = 0 } }, "Rail")
	railPath(parent, x + 30, 760, 3, { { len = 40, angle = 0 } }, "Rail")
end

local function buildBigAir(parent: Instance, destFolder: Folder, x: number, color: Color3)
	-- Scaffold in-run tower.
	local inrun: { Segment } = { { len = 100, angle = -20 }, { len = 16, angle = -10 }, { len = 16, angle = -4 } }
	local hStart = 0
	for _, s in inrun do
		hStart += s.len * math.sin(math.rad(-s.angle))
	end
	local dTop = 70
	local platformLen = 26
	local platCF = slopeCF(x, dTop - platformLen / 2, hStart - 1)
	make(parent, "StartDeck", Vector3.new(30, 2, platformLen), platCF, Color3.fromRGB(70, 75, 85), Enum.Material.DiamondPlate)
	for _, side in { -1, 1 } do
		local railPos = platCF * CFrame.new(side * 14.5, 2.5, 0)
		make(parent, "Railing", Vector3.new(0.4, 3, platformLen), railPos, color, Enum.Material.Metal)
	end
	plankPath(parent, x, dTop, hStart, 26, inrun)
	-- Scaffold legs under the deck and the steep part of the in-run.
	local steepRun = inrun[1].len * math.cos(math.rad(20))
	for d = dTop - platformLen, dTop + steepRun, 18 do
		local deckH = if d <= dTop then hStart - 2 else hStart - (d - dTop) * math.tan(math.rad(20)) - 2
		if deckH > 2 then
			for _, side in { -1, 1 } do
				local base = surface(x + side * 12, d)
				local h = deckH / math.cos(math.atan2(TOP_Y - BOTTOM_Y, BOTTOM_Z - TOP_Z))
				make(parent, "Scaffold", Vector3.new(1, h, 1), CFrame.new(base + Vector3.new(0, h / 2, 0)), Color3.fromRGB(90, 95, 105), Enum.Material.Metal)
			end
		end
	end
	destination(destFolder, "BigAir", platCF * CFrame.new(0, 5, 6))

	-- The kicker itself.
	kicker(parent, x, 330, 26, { { len = 14, angle = 12 }, { len = 14, angle = 20 }, { len = 14, angle = 30 } })
	-- Landing markers.
	for i, d in { 420, 470, 520 } do
		local marker = make(parent, "Marker" .. i, Vector3.new(60, 0.1, 1), slopeCF(x, d, 0.1), color, Enum.Material.Neon)
		marker.CanCollide = false
		marker.CanQuery = false
	end
	-- Second, smaller kicker for a two-hit run.
	kicker(parent, x, 640, 22, { { len = 12, angle = 10 }, { len = 10, angle = 22 } })
end

local function buildMountain(map: Instance, destFolder: Folder)
	local mountain = folder(map, "Mountain")

	for _, lane in LANES do
		local laneFolder = folder(mountain, lane.id)
		gate(laneFolder, lane.x, 8, 40, lane.name, lane.color)
		if lane.id ~= "BigAir" then
			destination(destFolder, lane.id, slopeCF(lane.x, 20, 4))
		end
		if lane.id == "Beginner" then
			buildBeginner(laneFolder, lane.x)
		elseif lane.id == "Rails" then
			buildRailGarden(laneFolder, lane.x)
		elseif lane.id == "Slopestyle" then
			buildSlopestyle(laneFolder, lane.x)
		elseif lane.id == "Halfpipe" then
			halfpipe(laneFolder, lane.x, 120, 520)
		elseif lane.id == "BigAir" then
			buildBigAir(laneFolder, destFolder, lane.x, lane.color)
		end
		-- Lane colour flags down both sides.
		for d = 60, SLOPE_LENGTH - 40, 80 do
			for _, side in { -1, 1 } do
				local base = surface(lane.x + side * 68, d)
				local pole = make(laneFolder, "Flag", Vector3.new(0.4, 6, 0.4), CFrame.new(base + Vector3.new(0, 3, 0)), lane.color, Enum.Material.SmoothPlastic)
				pole.CanCollide = false
			end
		end
	end

	-- Tree lines between trails (crash into them at your own risk).
	local trees = folder(mountain, "Trees")
	local rng = Random.new(7)
	for _, lx in { -375, -225, -75, 75, 225, 375 } do
		for d = 30, SLOPE_LENGTH - 30, 34 do
			local jitter = rng:NextNumber(-5, 5)
			tree(trees, surface(lx + jitter, d + rng:NextNumber(-8, 8)) - Vector3.new(0, 0.5, 0), rng:NextNumber(0.9, 1.4))
		end
	end

	-- Decorative chairlift towers along the left edge.
	local lift = folder(mountain, "Chairlift")
	local prev: Vector3? = nil
	for d = 0, SLOPE_LENGTH, 90 do
		local base = surface(-392, d)
		local h = 30
		make(lift, "Tower", Vector3.new(2, h, 2), CFrame.new(base + Vector3.new(0, h / 2, 0)), Color3.fromRGB(90, 95, 105), Enum.Material.Metal)
		make(lift, "Crossbar", Vector3.new(14, 1, 1), CFrame.new(base + Vector3.new(0, h, 0)), Color3.fromRGB(90, 95, 105), Enum.Material.Metal)
		local top = base + Vector3.new(0, h - 0.5, 0)
		if prev then
			local mid = (prev + top) / 2
			for _, off in { -6, 6 } do
				local o = Vector3.new(off, 0, 0)
				make(lift, "Cable", Vector3.new(0.2, 0.2, (top - prev).Magnitude), CFrame.lookAt(mid + o, top + o), Color3.fromRGB(30, 30, 30), Enum.Material.Metal).CanCollide = false
			end
			local chairPos = mid + Vector3.new(6, -4, 0)
			make(lift, "Chair", Vector3.new(5, 0.6, 2.5), CFrame.new(chairPos), Color3.fromRGB(200, 40, 40), Enum.Material.Metal).CanCollide = false
			make(lift, "Hanger", Vector3.new(0.3, 4, 0.3), CFrame.new(chairPos + Vector3.new(0, 2, 0)), Color3.fromRGB(30, 30, 30), Enum.Material.Metal).CanCollide = false
		end
		prev = top
	end

	-- Summit: warming hut + pad back to the lobby.
	local summit = folder(mountain, "Summit")
	local padPos = Vector3.new(0, TOP_Y + 0.3, TOP_Z - 40)
	local pad = disc(summit, "LobbyPad", padPos, 12, Color3.fromRGB(255, 200, 40), Enum.Material.Neon)
	pad:SetAttribute("Destination", "Lobby")
	billboard(pad, "Back to Lobby", Color3.fromRGB(255, 220, 90), Vector3.new(0, 6, 0))

	-- Finish banner across the bottom.
	local finishPos = Vector3.new(0, 26, BOTTOM_Z - 5)
	local finish = make(map, "FinishBanner", Vector3.new(MOUNTAIN_HALF_WIDTH * 2 - 20, 6, 0.6), CFrame.lookAt(finishPos, finishPos - Vector3.zAxis), Color3.fromRGB(220, 40, 50), Enum.Material.SmoothPlastic)
	finish.CanCollide = false
	surfaceText(finish, Enum.NormalId.Front, "F I N I S H", Color3.new(1, 1, 1), Color3.fromRGB(220, 40, 50))
	surfaceText(finish, Enum.NormalId.Back, "S N O W   P E A K", Color3.new(1, 1, 1), Color3.fromRGB(220, 40, 50))
	for _, side in { -1, 1 } do
		make(map, "FinishPost", Vector3.new(2, 29, 2), CFrame.new(side * (MOUNTAIN_HALF_WIDTH - 10), 14.5, BOTTOM_Z - 5), Color3.fromRGB(40, 40, 45), Enum.Material.Metal)
	end
end

---------------------------------------------------------------------------
-- Lobby & village
---------------------------------------------------------------------------

local function leaderboard(parent: Instance, cf: CFrame, title: string, stat: string, color: Color3)
	local board = make(parent, title, Vector3.new(22, 16, 1), cf, Color3.fromRGB(20, 30, 50), Enum.Material.SmoothPlastic)
	board:SetAttribute("Stat", stat)
	for _, side in { -1, 1 } do
		make(parent, "Leg", Vector3.new(1, cf.Position.Y, 1), CFrame.new((cf * CFrame.new(side * 9, 0, 0)).Position.X, cf.Position.Y / 2, cf.Position.Z), WOOD_DARK, Enum.Material.Wood)
	end
	make(parent, "Frame", Vector3.new(23, 17, 0.8), cf * CFrame.new(0, 0, 0.3), color, Enum.Material.SmoothPlastic)

	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0

	local header = Instance.new("TextLabel")
	header.Name = "Title"
	header.Size = UDim2.new(1, 0, 0, 90)
	header.BackgroundColor3 = color
	header.BorderSizePixel = 0
	header.Font = Enum.Font.FredokaOne
	header.TextScaled = true
	header.TextColor3 = Color3.new(1, 1, 1)
	header.Text = title
	header.Parent = gui

	local rows = Instance.new("Frame")
	rows.Name = "Rows"
	rows.Position = UDim2.fromOffset(16, 100)
	rows.Size = UDim2.new(1, -32, 1, -110)
	rows.BackgroundTransparency = 1
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 4)
	layout.Parent = rows
	rows.Parent = gui
	gui.Parent = board
end

local function buildCabin(parent: Instance, cf: CFrame, w: number, d: number, h: number, name: string, wallColor: Color3, roofColor: Color3): Model
	local m = Instance.new("Model")
	m.Name = name
	local function at(x: number, y: number, z: number): CFrame
		return cf * CFrame.new(x, y, z)
	end
	make(m, "Floor", Vector3.new(w, 1, d), at(0, 0.5, 0), WOOD, Enum.Material.WoodPlanks)

	local wallY = 1 + h / 2
	make(m, "BackWall", Vector3.new(w, h, 1), at(0, wallY, d / 2 - 0.5), wallColor, Enum.Material.Wood)
	make(m, "LeftWall", Vector3.new(1, h, d), at(-w / 2 + 0.5, wallY, 0), wallColor, Enum.Material.Wood)
	make(m, "RightWall", Vector3.new(1, h, d), at(w / 2 - 0.5, wallY, 0), wallColor, Enum.Material.Wood)
	local doorW, doorH = 7, 9
	local sideW = (w - doorW) / 2
	make(m, "FrontLeft", Vector3.new(sideW, h, 1), at(-(doorW / 2 + sideW / 2), wallY, -d / 2 + 0.5), wallColor, Enum.Material.Wood)
	make(m, "FrontRight", Vector3.new(sideW, h, 1), at(doorW / 2 + sideW / 2, wallY, -d / 2 + 0.5), wallColor, Enum.Material.Wood)
	make(m, "FrontTop", Vector3.new(doorW, h - doorH, 1), at(0, 1 + doorH + (h - doorH) / 2, -d / 2 + 0.5), wallColor, Enum.Material.Wood)
	make(m, "DoorFrame", Vector3.new(doorW + 1, 0.8, 1.4), at(0, 1 + doorH + 0.4, -d / 2 + 0.5), WOOD_DARK, Enum.Material.Wood)

	-- Log lines.
	for y = 2, h, 2.5 do
		make(m, "Log", Vector3.new(w + 0.4, 0.5, 0.4), at(0, y, d / 2 + 0.1), WOOD_DARK, Enum.Material.Wood)
		for _, sx in { -1, 1 } do
			make(m, "Log", Vector3.new(0.4, 0.5, d + 0.4), at(sx * (w / 2 + 0.1), y, 0), WOOD_DARK, Enum.Material.Wood)
		end
	end

	-- Warm glowing windows.
	local glow = Color3.fromRGB(255, 196, 110)
	for _, sx in { -1, 1 } do
		for _, z in { -d / 4, d / 4 } do
			make(m, "Window", Vector3.new(0.3, 3.5, 4.5), at(sx * (w / 2 + 0.05), 1 + h * 0.55, z), glow, Enum.Material.Neon)
			make(m, "WindowSill", Vector3.new(0.8, 0.4, 5), at(sx * (w / 2 + 0.2), 1 + h * 0.55 - 2, z), SNOW_WHITE, Enum.Material.Snow)
		end
	end
	for _, sx in { -1, 1 } do
		make(m, "FrontWindow", Vector3.new(3.5, 3, 0.3), at(sx * (doorW / 2 + sideW / 2), 1 + h * 0.55, -d / 2 - 0.05), glow, Enum.Material.Neon)
	end

	-- A-frame roof with snow.
	local pitch = math.rad(32)
	local ridgeH = (w / 2) * math.tan(pitch)
	local slabW = (w / 2 + 2.5) / math.cos(pitch)
	for _, side in { -1, 1 } do
		local rot = CFrame.Angles(0, 0, -side * pitch)
		local base = at(side * (w / 4 + 0.6), 1 + h + ridgeH / 2 - 0.4, 0) * rot
		make(m, "Roof", Vector3.new(slabW, 1, d + 4), base, roofColor, Enum.Material.WoodPlanks)
		make(m, "RoofSnow", Vector3.new(slabW - 0.4, 0.7, d + 3.6), base * CFrame.new(0, 0.8, 0), SNOW_WHITE, Enum.Material.Snow)
	end
	-- Gables.
	local steps = 5
	for i = 1, steps do
		local gw = w * (1 - (i - 0.5) / steps)
		local y = 1 + h + (i - 0.5) * ridgeH / steps
		for _, z in { -d / 2 + 0.5, d / 2 - 0.5 } do
			make(m, "Gable", Vector3.new(gw, ridgeH / steps, 1), at(0, y, z), wallColor, Enum.Material.Wood)
		end
	end
	-- Chimney with smoke.
	local chimney = make(m, "Chimney", Vector3.new(3, ridgeH + 4, 3), at(w / 4, 1 + h + (ridgeH + 4) / 2, d / 4), Color3.fromRGB(130, 70, 60), Enum.Material.Brick)
	local smoke = Instance.new("ParticleEmitter")
	smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smoke.Color = ColorSequence.new(Color3.fromRGB(200, 200, 205))
	smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.5), NumberSequenceKeypoint.new(1, 6) })
	smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1) })
	smoke.Lifetime = NumberRange.new(3, 5)
	smoke.Rate = 4
	smoke.Speed = NumberRange.new(3, 5)
	smoke.EmissionDirection = Enum.NormalId.Top
	smoke.Acceleration = Vector3.new(2, 0.5, 0)
	smoke.Parent = chimney

	local lamp = make(m, "Lamp", Vector3.new(1, 1, 1), at(0, 1 + h - 1.5, 0), glow, Enum.Material.Neon)
	local light = Instance.new("PointLight")
	light.Color = glow
	light.Range = math.max(w, d)
	light.Brightness = 1.4
	light.Parent = lamp

	m.Parent = parent
	return m
end

local function buildShop(parent: Instance, cf: CFrame)
	local w, d, h = 44, 32, 14
	local shop = buildCabin(parent, cf, w, d, h, "ShopCenter", Color3.fromRGB(150, 98, 58), Color3.fromRGB(150, 40, 40))
	local function at(x: number, y: number, z: number): CFrame
		return cf * CFrame.new(x, y, z)
	end

	local sign = make(shop, "Sign", Vector3.new(24, 4.5, 0.6), at(0, h + 2.2, -d / 2 - 0.9), Color3.fromRGB(30, 60, 110), Enum.Material.SmoothPlastic)
	surfaceText(sign, Enum.NormalId.Front, "SNOW SHOP  •  Gear & Boards", Color3.fromRGB(255, 240, 200), Color3.fromRGB(30, 60, 110))

	-- Counter with the shop prompt.
	local counter = make(shop, "ShopCounter", Vector3.new(16, 4, 3), at(0, 3, d / 2 - 8), Color3.fromRGB(95, 60, 35), Enum.Material.WoodPlanks)
	make(shop, "CounterTop", Vector3.new(16.6, 0.4, 3.6), at(0, 5.2, d / 2 - 8), Color3.fromRGB(230, 230, 235), Enum.Material.Marble)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ShopPrompt"
	prompt.ActionText = "Browse Gear"
	prompt.ObjectText = "Snow Shop"
	prompt.KeyboardKeyCode = Enum.KeyCode.G
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("OpensShop", true)
	prompt.Parent = counter

	-- Changing booths along the left wall (also open the shop).
	for i, z in { -6, 4 } do
		local booth = make(shop, "FittingRoom" .. i, Vector3.new(6, 9, 6), at(-w / 2 + 4.5, 5.5, z), Color3.fromRGB(180, 40, 60), Enum.Material.Fabric)
		booth.Transparency = 0.15
		booth.CanCollide = false
		local p = prompt:Clone()
		p.ActionText = "Change Clothes"
		p.ObjectText = "Fitting Room"
		p.Parent = booth
	end

	-- Clothing racks along the right wall: a coloured block per jacket/shirt.
	local rackItems = {}
	for _, item in Catalog.Items do
		if item.Slot == "Jacket" or item.Slot == "Shirt" then
			table.insert(rackItems, item)
		end
	end
	make(shop, "RackBar", Vector3.new(0.4, 0.4, 20), at(w / 2 - 4, 8, 0), METAL, Enum.Material.Metal)
	for i, item in rackItems do
		local z = -10 + (i - 0.5) * (20 / #rackItems)
		make(shop, "Hanger", Vector3.new(2.6, 3.2, 0.9), at(w / 2 - 4, 6.1, z), item.Color, Enum.Material.Fabric)
	end

	-- Board wall: every board on display.
	local boardIndex = 0
	for _, item in Catalog.Items do
		if item.Slot == "Board" then
			boardIndex += 1
			local model = Cosmetics.buildBoard(item.Id)
			for _, part in model:GetDescendants() do
				if part:IsA("BasePart") then
					part.Anchored = true
				end
			end
			local x = -w / 2 + 8 + boardIndex * 4.6
			model:PivotTo(at(x, 7.2, d / 2 - 1.6) * CFrame.Angles(0, math.rad(90), math.rad(90)))
			model.Parent = shop
		end
	end

	local warmLight = Instance.new("PointLight")
	warmLight.Range = 30
	warmLight.Brightness = 1.2
	warmLight.Color = Color3.fromRGB(255, 220, 170)
	warmLight.Parent = counter
end

local function buildLobby(map: Instance, destFolder: Folder)
	local lobby = folder(map, "Lobby")

	disc(lobby, "Plaza", Vector3.new(0, 0.2, 0), 150, Color3.fromRGB(150, 110, 75), Enum.Material.WoodPlanks)
	for _, pos in { Vector3.new(-10, 0.6, -10), Vector3.new(10, 0.6, -10), Vector3.new(-10, 0.6, 10), Vector3.new(10, 0.6, 10) } do
		local spawnPad = Instance.new("SpawnLocation")
		spawnPad.Anchored = true
		spawnPad.Size = Vector3.new(7, 0.6, 7)
		spawnPad.CFrame = CFrame.lookAt(pos, pos - Vector3.zAxis)
		spawnPad.Color = Color3.fromRGB(120, 200, 255)
		spawnPad.Material = Enum.Material.Ice
		spawnPad.Neutral = true
		spawnPad.Duration = 0
		spawnPad.Parent = lobby
	end
	destination(destFolder, "Lobby", CFrame.lookAt(Vector3.new(0, 4, 20), Vector3.new(0, 4, 0)))

	-- Title sign.
	local titlePos = Vector3.new(0, 22, -78)
	local title = make(lobby, "TitleSign", Vector3.new(50, 10, 1), CFrame.lookAt(titlePos, titlePos + Vector3.zAxis), Color3.fromRGB(25, 60, 120), Enum.Material.SmoothPlastic)
	surfaceText(title, Enum.NormalId.Front, "❄ SNOW PEAK ❄", Color3.fromRGB(255, 255, 255), Color3.fromRGB(25, 60, 120))
	for _, sx in { -1, 1 } do
		make(lobby, "TitlePost", Vector3.new(1.5, 22, 1.5), CFrame.new(sx * 22, 11, -78.5), WOOD_DARK, Enum.Material.Wood)
	end

	-- Leaderboards.
	leaderboard(lobby, CFrame.lookAt(Vector3.new(-56, 10, -34), Vector3.new(0, 10, 0)), "TOP TRICK POINTS", "TotalPoints", Color3.fromRGB(230, 160, 30))
	leaderboard(lobby, CFrame.lookAt(Vector3.new(56, 10, -34), Vector3.new(0, 10, 0)), "BEST COMBO", "BestCombo", Color3.fromRGB(200, 50, 80))

	-- Trail teleport pads.
	for i, lane in LANES do
		local x = -88 + (i - 1) * 44
		local pad = disc(lobby, "Pad_" .. lane.id, Vector3.new(x, 0.55, -64), 11, lane.color, Enum.Material.Neon)
		pad:SetAttribute("Destination", lane.id)
		billboard(pad, lane.name, Color3.new(1, 1, 1), Vector3.new(0, 6, 0))
		local ring = disc(lobby, "PadRing", Vector3.new(x, 0.45, -64), 13, Color3.fromRGB(240, 240, 245), Enum.Material.SmoothPlastic)
		ring.CanQuery = false
	end

	-- How-to-play sign.
	local infoPos = Vector3.new(60, 7, 16)
	local info = make(lobby, "HowToPlay", Vector3.new(18, 12, 0.6), CFrame.lookAt(infoPos, Vector3.new(0, 7, 0)), Color3.fromRGB(245, 245, 250), Enum.Material.SmoothPlastic)
	surfaceText(info, Enum.NormalId.Front,
		"HOW TO RIDE\nE  strap in / unstrap\nA/D  carve • spin in air\nW/S  push/brake • flip in air\nHold SPACE + release  ollie\nQ F R T  grabs\nLand rails from above to grind\nOff the board: CLICK to throw snowballs",
		Color3.fromRGB(20, 40, 70), nil, Enum.Font.GothamBold)

	-- Lobby centrepiece tree with lights.
	tree(lobby, Vector3.new(0, 0.5, 42), 2.2)
	for i = 1, 14 do
		local a = i / 14 * math.pi * 2
		local bulb = make(lobby, "Bulb", Vector3.new(0.8, 0.8, 0.8), CFrame.new(math.cos(a) * 6, 6 + (i % 3) * 5, 42 + math.sin(a) * 6), Color3.fromHSV(i / 14, 0.8, 1), Enum.Material.Neon)
		bulb.Shape = Enum.PartType.Ball
	end

	-- Lift station at the bottom of the mountain: step on (slowly) to ride back up.
	for _, lane in LANES do
		local pos = Vector3.new(lane.x + 40, 0.5, BOTTOM_Z + 75)
		local pad = disc(lobby, "Lift_" .. lane.id, pos, 10, lane.color, Enum.Material.Neon)
		pad:SetAttribute("Destination", lane.id)
		billboard(pad, "Lift ↑ " .. lane.name, Color3.new(1, 1, 1), Vector3.new(0, 6, 0))
	end
end

local function buildVillage(map: Instance)
	local village = folder(map, "Village")
	buildShop(village, CFrame.lookAt(Vector3.new(0, 0, 140), Vector3.new(0, 0, 0)))

	local cabins = {
		{ pos = Vector3.new(-62, 0, 112), name = "Cocoa Cabin" },
		{ pos = Vector3.new(62, 0, 112), name = "Ski Patrol" },
		{ pos = Vector3.new(-62, 0, 172), name = "Rider Lodge" },
		{ pos = Vector3.new(62, 0, 172), name = "Wax Hut" },
		{ pos = Vector3.new(-112, 0, 142), name = "Bunk House" },
		{ pos = Vector3.new(112, 0, 142), name = "Trail Office" },
	}
	local palette = { Color3.fromRGB(140, 90, 52), Color3.fromRGB(120, 76, 44), Color3.fromRGB(160, 110, 70) }
	local roofs = { Color3.fromRGB(60, 80, 110), Color3.fromRGB(110, 40, 40), Color3.fromRGB(50, 90, 60) }
	for i, c in cabins do
		local face = Vector3.new(0, 0, 142) - c.pos
		face = Vector3.new(face.X, 0, face.Z).Unit
		local cf = CFrame.lookAt(c.pos, c.pos + face)
		local cabin = buildCabin(village, cf, 22, 18, 10, c.name, palette[(i % 3) + 1], roofs[(i % 3) + 1])
		local sign = make(cabin, "NameSign", Vector3.new(10, 2, 0.4), cf * CFrame.new(0, 12.8, -9.6), WOOD_DARK, Enum.Material.Wood)
		surfaceText(sign, Enum.NormalId.Front, c.name, Color3.fromRGB(255, 235, 200), WOOD_DARK)
	end

	-- Path and lamp posts from the lobby to the village.
	make(village, "Path", Vector3.new(14, 0.3, 80), CFrame.new(0, 0.15, 95), Color3.fromRGB(200, 200, 210), Enum.Material.Pebble)
	for z = 70, 180, 22 do
		for _, sx in { -1, 1 } do
			local x = sx * 11
			make(village, "LampPost", Vector3.new(0.6, 9, 0.6), CFrame.new(x, 4.5, z), Color3.fromRGB(30, 30, 35), Enum.Material.Metal)
			local head = make(village, "LampHead", Vector3.new(1.4, 1.4, 1.4), CFrame.new(x, 9.4, z), Color3.fromRGB(255, 210, 140), Enum.Material.Neon)
			local light = Instance.new("PointLight")
			light.Range = 18
			light.Brightness = 1.2
			light.Color = Color3.fromRGB(255, 210, 140)
			light.Parent = head
		end
	end

	-- Forest ring around the village.
	local rng = Random.new(11)
	for i = 1, 60 do
		local a = i / 60 * math.pi * 2
		local r = rng:NextNumber(190, 260)
		local pos = Vector3.new(math.cos(a) * r, 0, 60 + math.sin(a) * r * 0.9)
		if pos.Z > -60 then
			tree(village, pos, rng:NextNumber(1, 1.8))
		end
	end
end

---------------------------------------------------------------------------
-- Teleport pads
---------------------------------------------------------------------------

local function connectPads(map: Instance, destFolder: Folder)
	local cooldown: { [Player]: number } = {}
	local teleported = Remotes.event("Teleported")

	Players.PlayerRemoving:Connect(function(p)
		cooldown[p] = nil
	end)

	for _, pad in map:GetDescendants() do
		local destName = pad:GetAttribute("Destination")
		if pad:IsA("BasePart") and type(destName) == "string" then
			pad.Touched:Connect(function(hit)
				local character = hit.Parent
				if not character or not character:IsA("Model") then
					return
				end
				local player = Players:GetPlayerFromCharacter(character)
				local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
				if not player or not root or character:GetAttribute("Ragdolled") == true then
					return
				end
				local now = os.clock()
				if now - (cooldown[player] or 0) < 3 then
					return
				end
				-- Riders blasting through the run-out shouldn't get yanked away.
				if root.AssemblyLinearVelocity.Magnitude > 30 then
					return
				end
				local dest = destFolder:FindFirstChild(destName) :: BasePart?
				if not dest then
					return
				end
				cooldown[player] = now
				character:PivotTo(dest.CFrame + Vector3.new(0, 3, 0))
				teleported:FireClient(player, dest.CFrame)
			end)
		end
	end
end

function WorldBuilder.build()
	local started = os.clock()
	local map = Instance.new("Folder")
	map.Name = "Map"
	local destFolder = folder(map, "Destinations")

	setupLighting()
	buildTerrain()
	buildMountain(map, destFolder)
	buildLobby(map, destFolder)
	buildVillage(map)
	-- Decorative non-solid parts shouldn't block rider ground rays or snowballs.
	for _, d in map:GetDescendants() do
		if d:IsA("BasePart") and not d.CanCollide and not CollectionService:HasTag(d, "Grindable") then
			d.CanQuery = false
		end
	end
	map.Parent = Workspace
	connectPads(map, destFolder)

	print(string.format("[WorldBuilder] map built in %.2fs", os.clock() - started))
end

return WorldBuilder
