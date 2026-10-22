--!strict
-- Physics ragdolls: every Motor6D (except the root joint) is swapped for a limited
-- BallSocketConstraint so the body flops realistically, then restored. The owning
-- client switches its Humanoid into the Physics state when it sees "Ragdolled".

local Players = game:GetService("Players")

local RagdollService = {}

local FOLDER = "RagdollConstraints"

type Saved = {
	collisions: { [BasePart]: boolean },
	token: number,
}

local saved: { [Model]: Saved } = {}
local tokenCounter = 0

-- Joint limits (degrees): cone angle, twist range.
local LIMITS: { [string]: { number } } = {
	Neck = { 35, 30 },
	Waist = { 25, 20 },
	LeftShoulder = { 100, 70 },
	RightShoulder = { 100, 70 },
	["Left Shoulder"] = { 100, 70 },
	["Right Shoulder"] = { 100, 70 },
	LeftElbow = { 70, 5 },
	RightElbow = { 70, 5 },
	LeftWrist = { 30, 10 },
	RightWrist = { 30, 10 },
	LeftHip = { 60, 25 },
	RightHip = { 60, 25 },
	["Left Hip"] = { 60, 25 },
	["Right Hip"] = { 60, 25 },
	LeftKnee = { 70, 5 },
	RightKnee = { 70, 5 },
	LeftAnkle = { 25, 5 },
	RightAnkle = { 25, 5 },
}

local function isRootJoint(m: Motor6D): boolean
	return m.Name == "Root" or m.Name == "RootJoint"
end

function RagdollService.isRagdolled(character: Model): boolean
	return character:GetAttribute("Ragdolled") == true
end

function RagdollService.unragdoll(character: Model)
	local state = saved[character]
	if not state then
		return
	end
	saved[character] = nil
	local folder = character:FindFirstChild(FOLDER)
	if folder then
		folder:Destroy()
	end
	for _, d in character:GetDescendants() do
		if d:IsA("Motor6D") then
			d.Enabled = true
		end
	end
	for part, canCollide in state.collisions do
		if part.Parent then
			part.CanCollide = canCollide
		end
	end
	character:SetAttribute("Ragdolled", false)
end

-- duration = nil keeps the ragdoll until the character is removed (death).
function RagdollService.ragdoll(character: Model, duration: number?)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	tokenCounter += 1
	local token = tokenCounter
	local existing = saved[character]
	if existing then
		existing.token = token -- extend the current ragdoll
	else
		local folder = Instance.new("Folder")
		folder.Name = FOLDER
		local collisions: { [BasePart]: boolean } = {}

		for _, motor in character:GetDescendants() do
			if motor:IsA("Motor6D") and not isRootJoint(motor) and motor.Part0 and motor.Part1 then
				local p0 = motor.Part0 :: BasePart
				local p1 = motor.Part1 :: BasePart
				local a0 = Instance.new("Attachment")
				a0.Name = "RagdollA0"
				a0.CFrame = motor.C0
				a0.Parent = p0
				local a1 = Instance.new("Attachment")
				a1.Name = "RagdollA1"
				a1.CFrame = motor.C1
				a1.Parent = p1

				local limits = LIMITS[motor.Name] or { 45, 20 }
				local socket = Instance.new("BallSocketConstraint")
				socket.Attachment0 = a0
				socket.Attachment1 = a1
				socket.LimitsEnabled = true
				socket.UpperAngle = limits[1]
				socket.TwistLimitsEnabled = true
				socket.TwistLowerAngle = -limits[2]
				socket.TwistUpperAngle = limits[2]
				socket.Parent = folder

				local nc = Instance.new("NoCollisionConstraint")
				nc.Part0 = p0
				nc.Part1 = p1
				nc.Parent = folder

				motor.Enabled = false
			end
		end

		for _, part in character:GetChildren() do
			if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
				collisions[part] = part.CanCollide
				part.CanCollide = true
			end
		end
		local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			collisions[root] = root.CanCollide
			root.CanCollide = false
		end

		folder.Parent = character
		saved[character] = { collisions = collisions, token = token }
		character:SetAttribute("Ragdolled", true)
	end

	if duration then
		task.delay(duration, function()
			local state = saved[character]
			if state and state.token == token and humanoid.Health > 0 then
				RagdollService.unragdoll(character)
			end
		end)
	end
end

function RagdollService.start()
	local function hook(player: Player)
		player.CharacterAdded:Connect(function(character)
			local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
			if not humanoid then
				return
			end
			humanoid.Died:Connect(function()
				RagdollService.ragdoll(character, nil)
			end)
			character.AncestryChanged:Connect(function(_, parent)
				if parent == nil then
					saved[character] = nil
				end
			end)
		end)
	end
	Players.PlayerAdded:Connect(hook)
	for _, p in Players:GetPlayers() do
		hook(p)
	end
end

return RagdollService
