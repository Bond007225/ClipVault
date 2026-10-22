--!strict
-- Builds cosmetics and snowboards out of welded parts, so the game works without
-- uploading any mesh/clothing assets. Works on R15 and (more roughly) R6 rigs.

local Catalog = require(script.Parent.Catalog)

type Item = Catalog.Item

local Cosmetics = {}

local FOLDER_NAME = "Cosmetics"

local function newPart(name: string, size: Vector3, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.Fabric
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = true
	return p
end

local function sphereMesh(part: BasePart)
	local m = Instance.new("SpecialMesh")
	m.MeshType = Enum.MeshType.Sphere
	m.Parent = part
end

local function weld(part: BasePart, to: BasePart, offset: CFrame, parent: Instance)
	part.CFrame = to.CFrame * offset
	local w = Instance.new("Weld")
	w.Part0 = to
	w.Part1 = part
	w.C0 = offset
	w.Parent = part
	part.Parent = parent
end

local function findPart(character: Model, ...: string): BasePart?
	for _, name in { ... } do
		local p = character:FindFirstChild(name)
		if p and p:IsA("BasePart") then
			return p
		end
	end
	return nil
end

-- A slightly inflated copy of a limb, used for sleeves, pant legs, boots etc.
local function shell(folder: Instance, limb: BasePart?, scale: Vector3, color: Color3, material: Enum.Material?, offset: CFrame?)
	if not limb then
		return
	end
	local p = newPart(limb.Name .. "Shell", limb.Size * scale, color, material)
	weld(p, limb, offset or CFrame.identity, folder)
end

local function isR15(character: Model): boolean
	return character:FindFirstChild("UpperTorso") ~= nil
end

local function ring(folder: Instance, attachTo: BasePart, offset: CFrame, height: number, diameter: number, color: Color3, material: Enum.Material?): Part
	local p = newPart("Ring", Vector3.new(height, diameter, diameter), color, material)
	p.Shape = Enum.PartType.Cylinder
	-- Cylinders run along X; rotate so the ring's axis is vertical.
	weld(p, attachTo, offset * CFrame.Angles(0, 0, math.rad(90)), folder)
	return p
end

---------------------------------------------------------------------------
-- Slot builders
---------------------------------------------------------------------------

local builders: { [string]: (character: Model, folder: Folder, item: Item) -> () } = {}

builders.Hat = function(character, folder, item)
	local head = findPart(character, "Head")
	if not head then
		return
	end
	local s = head.Size.Y
	local mat = item.Material or Enum.Material.Fabric

	if item.Style == "Helmet" then
		local shellPart = newPart("Helmet", Vector3.new(s * 1.22, s * 0.95, s * 1.25), item.Color, mat)
		sphereMesh(shellPart)
		weld(shellPart, head, CFrame.new(0, s * 0.2, s * 0.03), folder)
		local stripe = newPart("Stripe", Vector3.new(s * 0.18, s * 0.97, s * 1.27), item.Accent, Enum.Material.SmoothPlastic)
		sphereMesh(stripe)
		weld(stripe, head, CFrame.new(0, s * 0.21, s * 0.03), folder)
		return
	end

	local dome = newPart("Dome", Vector3.new(s * 1.12, s * 0.8, s * 1.12), item.Color, mat)
	sphereMesh(dome)
	weld(dome, head, CFrame.new(0, s * 0.28, 0), folder)

	if item.Style == "Cap" then
		local brim = newPart("Brim", Vector3.new(s * 0.8, s * 0.06, s * 0.5), item.Accent, Enum.Material.SmoothPlastic)
		weld(brim, head, CFrame.new(0, s * 0.28, -s * 0.68), folder)
		return
	end

	ring(folder, head, CFrame.new(0, s * 0.22, 0), s * 0.22, s * 1.14, item.Accent, mat)

	if item.Style == "PomBeanie" then
		local pom = newPart("Pom", Vector3.new(s * 0.38, s * 0.38, s * 0.38), item.Accent, Enum.Material.Fabric)
		pom.Shape = Enum.PartType.Ball
		weld(pom, head, CFrame.new(0, s * 0.72, 0), folder)
	elseif item.Style == "Trapper" then
		for _, side in { -1, 1 } do
			local flap = newPart("EarFlap", Vector3.new(s * 0.14, s * 0.55, s * 0.5), item.Accent, Enum.Material.Fabric)
			weld(flap, head, CFrame.new(side * s * 0.56, -s * 0.05, 0), folder)
		end
	end
end

builders.Glasses = function(character, folder, item)
	local head = findPart(character, "Head")
	if not head then
		return
	end
	local s = head.Size.Y
	local front = -head.Size.Z / 2 - 0.03
	local eyeY = s * 0.08

	if item.Style == "Goggles" then
		local lens = newPart("Lens", Vector3.new(s * 0.95, s * 0.32, 0.12), item.Color, item.Material or Enum.Material.Glass)
		lens.Reflectance = 0.35
		weld(lens, head, CFrame.new(0, eyeY, front - 0.04), folder)
		local frame = newPart("Frame", Vector3.new(s * 1.0, s * 0.38, 0.1), item.Accent, Enum.Material.SmoothPlastic)
		weld(frame, head, CFrame.new(0, eyeY, front + 0.04), folder)
		ring(folder, head, CFrame.new(0, eyeY, 0), s * 0.14, s * 1.08, item.Accent, Enum.Material.Fabric)
	elseif item.Style == "Round" then
		for _, side in { -1, 1 } do
			local lens = newPart("Lens", Vector3.new(0.05, s * 0.28, s * 0.28), item.Color, Enum.Material.Glass)
			lens.Shape = Enum.PartType.Cylinder
			lens.Transparency = 0.3
			weld(lens, head, CFrame.new(side * s * 0.2, eyeY, front) * CFrame.Angles(0, math.rad(90), 0), folder)
		end
		local bridge = newPart("Bridge", Vector3.new(s * 0.14, 0.05, 0.05), item.Accent, Enum.Material.Metal)
		weld(bridge, head, CFrame.new(0, eyeY, front), folder)
	else -- Shades
		for _, side in { -1, 1 } do
			local lens = newPart("Lens", Vector3.new(s * 0.32, s * 0.2, 0.06), item.Color, Enum.Material.Glass)
			lens.Reflectance = 0.25
			weld(lens, head, CFrame.new(side * s * 0.2, eyeY, front), folder)
		end
		local bridge = newPart("Bridge", Vector3.new(s * 0.8, 0.05, 0.06), item.Accent, Enum.Material.Metal)
		weld(bridge, head, CFrame.new(0, eyeY + s * 0.1, front), folder)
	end
end

builders.Scarf = function(character, folder, item)
	local head = findPart(character, "Head")
	local torso = findPart(character, "UpperTorso", "Torso")
	if not head or not torso then
		return
	end
	local s = head.Size.Y
	local mat = item.Material or Enum.Material.Fabric

	if item.Style == "Gaiter" then
		ring(folder, head, CFrame.new(0, -s * 0.3, 0), s * 0.5, s * 1.08, item.Color, mat)
		ring(folder, head, CFrame.new(0, -s * 0.22, 0), s * 0.06, s * 1.1, item.Accent, Enum.Material.Neon)
		return
	end

	local neckY = torso.Size.Y / 2
	ring(folder, torso, CFrame.new(0, neckY, 0), 0.35, math.min(torso.Size.X, 1.5) * 0.85, item.Color, mat)

	local tailLength = if item.Style == "Long" then 1.8 else 1.1
	local tail = newPart("Tail", Vector3.new(0.4, tailLength, 0.12), item.Color, mat)
	weld(tail, torso, CFrame.new(-torso.Size.X * 0.22, neckY - tailLength / 2, -torso.Size.Z / 2 - 0.08) * CFrame.Angles(0, 0, math.rad(-6)), folder)

	if item.Style == "Striped" then
		for i = 1, 3 do
			local stripe = newPart("Stripe", Vector3.new(0.42, 0.14, 0.13), item.Accent, mat)
			weld(stripe, tail, CFrame.new(0, tailLength / 2 - i * (tailLength / 4), 0), folder)
		end
	elseif item.Style == "Long" then
		local back = newPart("BackTail", Vector3.new(0.4, 2.2, 0.12), item.Color, mat)
		weld(back, torso, CFrame.new(torso.Size.X * 0.2, neckY - 1.0, torso.Size.Z / 2 + 0.25) * CFrame.Angles(math.rad(-25), 0, 0), folder)
		local fringe = newPart("Fringe", Vector3.new(0.42, 0.1, 0.14), item.Accent, mat)
		weld(fringe, tail, CFrame.new(0, -tailLength / 2, 0), folder)
	end
end

local function torsoParts(character: Model): { BasePart }
	local out = {}
	for _, n in { "UpperTorso", "LowerTorso", "Torso" } do
		local p = findPart(character, n)
		if p then
			table.insert(out, p)
		end
	end
	return out
end

builders.Shirt = function(character, folder, item)
	local mat = item.Material or Enum.Material.Fabric
	local sc = Vector3.new(1.04, 1.02, 1.06)
	for _, p in torsoParts(character) do
		shell(folder, p, sc, item.Color, mat)
	end
	local armColor = if item.Style == "Raglan" then item.Accent else item.Color
	if isR15(character) then
		for _, n in { "LeftUpperArm", "RightUpperArm", "LeftLowerArm", "RightLowerArm" } do
			shell(folder, findPart(character, n), Vector3.new(1.08, 1.02, 1.08), armColor, mat)
		end
	else
		for _, n in { "Left Arm", "Right Arm" } do
			shell(folder, findPart(character, n), Vector3.new(1.06, 1.0, 1.06), armColor, mat)
		end
	end
	if item.Style == "Flannel" then
		for _, p in torsoParts(character) do
			for i = -1, 1 do
				local band = newPart("Check", Vector3.new(p.Size.X * 1.06, 0.12, p.Size.Z * 1.08), item.Accent, mat)
				weld(band, p, CFrame.new(0, i * p.Size.Y * 0.3, 0), folder)
			end
		end
	end
end

builders.Jacket = function(character, folder, item)
	local mat = item.Material or (if item.Style == "Puffer" then Enum.Material.SmoothPlastic else Enum.Material.Fabric)
	local puff = if item.Style == "Puffer" then 1.16 else 1.1
	local upper = findPart(character, "UpperTorso", "Torso")
	for _, p in torsoParts(character) do
		shell(folder, p, Vector3.new(puff, 1.04, puff + 0.06), item.Color, mat)
	end
	local armNames: { string } = if isR15(character)
		then { "LeftUpperArm", "RightUpperArm", "LeftLowerArm", "RightLowerArm" }
		else { "Left Arm", "Right Arm" }
	for _, n in armNames do
		shell(folder, findPart(character, n), Vector3.new(puff + 0.04, 1.03, puff + 0.04), item.Color, mat)
	end

	if not upper then
		return
	end
	if item.Style == "Puffer" then
		for i = -1, 1 do
			local band = newPart("Quilt", Vector3.new(upper.Size.X * (puff + 0.02), 0.08, upper.Size.Z * (puff + 0.1)), item.Accent, mat)
			weld(band, upper, CFrame.new(0, i * upper.Size.Y * 0.28, 0), folder)
		end
	else
		local zip = newPart("Zip", Vector3.new(0.1, upper.Size.Y * 1.02, 0.05), item.Accent, Enum.Material.SmoothPlastic)
		weld(zip, upper, CFrame.new(0, 0, -upper.Size.Z * (puff + 0.06) / 2 - 0.02), folder)
	end
	if item.Style == "Neon" then
		for _, n in armNames do
			local arm = findPart(character, n)
			if arm then
				local stripe = newPart("Stripe", Vector3.new(arm.Size.X * 1.22, arm.Size.Y * 0.9, 0.08), item.Accent, Enum.Material.Neon)
				weld(stripe, arm, CFrame.new(0, 0, arm.Size.Z * 0.1), folder)
			end
		end
	end
end

builders.Gloves = function(character, folder, item)
	local mat = item.Material or Enum.Material.Fabric
	local scale = if item.Style == "Mitten" then Vector3.new(1.4, 1.3, 1.5) else Vector3.new(1.2, 1.15, 1.25)
	if isR15(character) then
		for _, n in { "LeftHand", "RightHand" } do
			local hand = findPart(character, n)
			shell(folder, hand, scale, item.Color, mat)
			if hand and item.Style == "Glove" then
				local cuff = newPart("Cuff", Vector3.new(hand.Size.X * 1.35, 0.15, hand.Size.Z * 1.4), item.Accent, mat)
				weld(cuff, hand, CFrame.new(0, hand.Size.Y * 0.45, 0), folder)
			end
		end
	else
		for _, n in { "Left Arm", "Right Arm" } do
			local arm = findPart(character, n)
			if arm then
				local g = newPart("Glove", Vector3.new(arm.Size.X * 1.12, 0.6, arm.Size.Z * 1.12), item.Color, mat)
				weld(g, arm, CFrame.new(0, -arm.Size.Y / 2 + 0.3, 0), folder)
			end
		end
	end
end

builders.Pants = function(character, folder, item)
	local mat = item.Material or Enum.Material.Fabric
	local lower = findPart(character, "LowerTorso")
	if lower then
		shell(folder, lower, Vector3.new(1.08, 1.04, 1.1), item.Color, mat)
	end
	local legNames: { string } = if isR15(character)
		then { "LeftUpperLeg", "RightUpperLeg", "LeftLowerLeg", "RightLowerLeg" }
		else { "Left Leg", "Right Leg" }
	for _, n in legNames do
		shell(folder, findPart(character, n), Vector3.new(1.12, 1.02, 1.12), item.Color, mat)
	end
	if item.Style == "Cargo" then
		for _, n in { "LeftUpperLeg", "RightUpperLeg", "Left Leg", "Right Leg" } do
			local leg = findPart(character, n)
			if leg then
				local side = if string.find(n, "Left") then -1 else 1
				local pocket = newPart("Pocket", Vector3.new(0.12, leg.Size.Y * 0.4, leg.Size.Z * 0.7), item.Accent, mat)
				weld(pocket, leg, CFrame.new(side * leg.Size.X * 0.6, 0, 0), folder)
			end
		end
	elseif item.Style == "Bib" then
		local upper = findPart(character, "UpperTorso", "Torso")
		if upper then
			local bib = newPart("Bib", Vector3.new(upper.Size.X * 0.6, upper.Size.Y * 0.7, 0.08), item.Color, mat)
			weld(bib, upper, CFrame.new(0, -upper.Size.Y * 0.12, -upper.Size.Z * 0.62), folder)
			for _, side in { -1, 1 } do
				local strap = newPart("Strap", Vector3.new(0.18, upper.Size.Y * 1.02, upper.Size.Z * 1.2), item.Accent, mat)
				weld(strap, upper, CFrame.new(side * upper.Size.X * 0.25, 0, 0), folder)
			end
		end
	end
end

builders.Boots = function(character, folder, item)
	local mat = item.Material or Enum.Material.SmoothPlastic
	local big = if item.Style == "Moon" then 1.45 else 1.2
	if isR15(character) then
		for _, side in { "Left", "Right" } do
			local foot = findPart(character, side .. "Foot")
			shell(folder, foot, Vector3.new(big, big, big * 1.05), item.Color, mat)
			local shin = findPart(character, side .. "LowerLeg")
			if shin then
				local cuff = newPart("BootCuff", Vector3.new(shin.Size.X * (big + 0.05), shin.Size.Y * 0.4, shin.Size.Z * (big + 0.05)), item.Color, mat)
				weld(cuff, shin, CFrame.new(0, -shin.Size.Y * 0.3, 0), folder)
				if item.Style == "Pro" then
					local strap = newPart("Strap", Vector3.new(shin.Size.X * (big + 0.1), 0.15, shin.Size.Z * (big + 0.1)), item.Accent, mat)
					weld(strap, shin, CFrame.new(0, -shin.Size.Y * 0.2, 0), folder)
				end
			end
		end
	else
		for _, n in { "Left Leg", "Right Leg" } do
			local leg = findPart(character, n)
			if leg then
				local boot = newPart("Boot", Vector3.new(leg.Size.X * big, 0.8, leg.Size.Z * big), item.Color, mat)
				weld(boot, leg, CFrame.new(0, -leg.Size.Y / 2 + 0.4, 0), folder)
			end
		end
	end
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

-- Avatar accessories that would poke through (or clash with) each equipped slot.
local HIDES: { [string]: { string } } = {
	Hat = { "Hat", "Hair" },
	Glasses = { "Face" },
	Scarf = { "Neck" },
	Jacket = { "Jacket", "Sweater", "Shirt", "TShirt", "Shoulder", "Front", "Back" },
	Shirt = { "Sweater", "Shirt", "TShirt" },
	Pants = { "Pants", "Shorts", "DressSkirt", "Waist" },
	Boots = { "LeftShoe", "RightShoe" },
}

local function updateAvatarAccessories(character: Model, equipped: { [string]: string })
	local hidden: { [string]: boolean } = {}
	for slot, types in HIDES do
		if equipped[slot] then
			for _, t in types do
				hidden[t] = true
			end
		end
	end
	for _, accessory in character:GetChildren() do
		if accessory:IsA("Accessory") then
			local handle = accessory:FindFirstChild("Handle")
			if handle and handle:IsA("BasePart") then
				local original = handle:GetAttribute("OriginalTransparency")
				if type(original) ~= "number" then
					original = handle.Transparency
					handle:SetAttribute("OriginalTransparency", original)
				end
				handle.Transparency = if hidden[accessory.AccessoryType.Name] then 1 else original :: number
			end
		end
	end
end

-- Order matters: inner layers first so outer shells cover them.
local LAYER_ORDER = { "Shirt", "Pants", "Jacket", "Boots", "Gloves", "Scarf", "Hat", "Glasses" }

function Cosmetics.apply(character: Model, equipped: { [string]: string })
	local old = character:FindFirstChild(FOLDER_NAME)
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME

	for _, slot in LAYER_ORDER do
		local id = equipped[slot]
		local item = if id then Catalog.get(id) else nil
		local build = builders[slot]
		if item and item.Slot == slot and build then
			local ok, err = pcall(function()
				build(character, folder, item)
			end)
			if not ok then
				warn(`[Cosmetics] failed to build {item.Id}: {err}`)
			end
		end
	end
	folder.Parent = character
	updateAvatarAccessories(character, equipped)
end

-- Builds a snowboard model. The board's long axis is X; "Deck" is the primary part.
function Cosmetics.buildBoard(boardId: string?): Model
	local item = if boardId then Catalog.get(boardId) else nil
	if not item then
		item = Catalog.get(Catalog.DefaultBoard)
	end
	if not item then
		error("Default board missing from catalog")
	end

	local model = Instance.new("Model")
	model.Name = "Snowboard"
	model:SetAttribute("BoardId", item.Id)

	local length, thickness, width = 5.4, 0.22, 1.35
	local mat = item.Material or Enum.Material.SmoothPlastic

	local deck = newPart("Deck", Vector3.new(length - width, thickness, width), item.Color, mat)
	deck.Parent = model
	model.PrimaryPart = deck

	local function attach(p: BasePart, offset: CFrame)
		p.CFrame = deck.CFrame * offset
		local w = Instance.new("WeldConstraint")
		w.Part0 = deck
		w.Part1 = p
		w.Parent = p
		p.Parent = model
	end

	-- Rounded nose and tail.
	for _, side in { -1, 1 } do
		local cap = newPart("Tip", Vector3.new(thickness, width, width), item.Color, mat)
		cap.Shape = Enum.PartType.Cylinder
		attach(cap, CFrame.new(side * (length - width) / 2, 0, 0) * CFrame.Angles(0, 0, math.rad(90)))
		local kick = newPart("Kick", Vector3.new(width * 0.4, thickness, width * 0.98), item.Color, mat)
		attach(kick, CFrame.new(side * (length / 2 - width * 0.25), thickness * 0.6, 0) * CFrame.Angles(0, 0, math.rad(side * 18)))
	end

	local stripeMat = if item.Style == "GlowBoard" then Enum.Material.Neon else Enum.Material.SmoothPlastic
	local stripe = newPart("Stripe", Vector3.new(length - width - 0.2, 0.02, width * 0.25), item.Accent, stripeMat)
	attach(stripe, CFrame.new(0, thickness / 2 + 0.01, 0))

	for _, x in { -0.95, 0.95 } do
		local binding = newPart("Binding", Vector3.new(0.75, 0.35, width * 0.9), Color3.fromRGB(25, 25, 28), Enum.Material.SmoothPlastic)
		attach(binding, CFrame.new(x, thickness / 2 + 0.17, 0))
		local highback = newPart("Highback", Vector3.new(0.6, 0.55, 0.1), item.Accent, Enum.Material.SmoothPlastic)
		attach(highback, CFrame.new(x, thickness / 2 + 0.45, width * 0.42))
	end

	if item.Style == "GlowBoard" then
		local light = Instance.new("PointLight")
		light.Color = item.Accent
		light.Range = 8
		light.Brightness = 1.5
		light.Parent = deck
	end

	-- Snow spray, rate driven at runtime by the client.
	local sprayAttachment = Instance.new("Attachment")
	sprayAttachment.Name = "SprayAttachment"
	sprayAttachment.Position = Vector3.new(0, -thickness / 2, 0)
	sprayAttachment.Parent = deck
	local spray = Instance.new("ParticleEmitter")
	spray.Name = "Spray"
	spray.Texture = "rbxasset://textures/particles/smoke_main.dds"
	spray.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255))
	spray.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 2.4) })
	spray.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	spray.Lifetime = NumberRange.new(0.35, 0.7)
	spray.Speed = NumberRange.new(6, 14)
	spray.SpreadAngle = Vector2.new(35, 35)
	spray.Acceleration = Vector3.new(0, -25, 0)
	spray.Drag = 3
	spray.EmissionDirection = Enum.NormalId.Top
	spray.LightEmission = 0.2
	spray.Rate = 0
	spray.Parent = sprayAttachment

	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Massless = true
		end
	end

	return model
end

return Cosmetics
