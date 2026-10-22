--!strict
-- Procedural, smoothly blended riding poses (stance, crouch, grabs, grinds) and the
-- snowball throw, driven by Motor6D.Transform. Runs for every player's character
-- on every client: the local rider uses its own state, others use the replicated
-- "Pose"/"Lean" attributes. No animation assets need to be uploaded. (R15 rigs.)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local LocalRider = require(script.Parent.LocalRider)

local PoseController = {}

type PoseDef = { [string]: Vector3 } -- motor name -> rotation in degrees (Root: Y = drop)

local function v(x: number, y: number, z: number): Vector3
	return Vector3.new(x, y, z)
end

local POSES: { [string]: PoseDef } = {
	Ride = {
		Root = v(0, 0.22, 0),
		Waist = v(-8, 18, 0),
		Neck = v(0, 55, 0),
		LeftShoulder = v(10, 0, -38),
		RightShoulder = v(10, 0, 38),
		LeftElbow = v(25, 0, 0),
		RightElbow = v(25, 0, 0),
		LeftHip = v(28, 0, -14),
		RightHip = v(28, 0, 14),
		LeftKnee = v(-45, 0, 0),
		RightKnee = v(-45, 0, 0),
		LeftAnkle = v(17, 0, 0),
		RightAnkle = v(17, 0, 0),
	},
	Crouch = {
		Root = v(0, 0.66, 0),
		Waist = v(-25, 15, 0),
		Neck = v(10, 50, 0),
		LeftShoulder = v(30, 0, -45),
		RightShoulder = v(30, 0, 45),
		LeftElbow = v(45, 0, 0),
		RightElbow = v(45, 0, 0),
		LeftHip = v(60, 0, -14),
		RightHip = v(60, 0, 14),
		LeftKnee = v(-95, 0, 0),
		RightKnee = v(-95, 0, 0),
		LeftAnkle = v(35, 0, 0),
		RightAnkle = v(35, 0, 0),
	},
	Air = {
		Root = v(0, 0.5, 0),
		Waist = v(-15, 10, 0),
		Neck = v(0, 45, 0),
		LeftShoulder = v(0, 0, -75),
		RightShoulder = v(0, 0, 75),
		LeftElbow = v(15, 0, 0),
		RightElbow = v(15, 0, 0),
		LeftHip = v(50, 0, -12),
		RightHip = v(50, 0, 12),
		LeftKnee = v(-80, 0, 0),
		RightKnee = v(-80, 0, 0),
		LeftAnkle = v(30, 0, 0),
		RightAnkle = v(30, 0, 0),
	},
	Grind = {
		Root = v(0, 0.3, 0),
		Waist = v(-10, 10, 0),
		Neck = v(0, 35, 0),
		LeftShoulder = v(0, 0, -82),
		RightShoulder = v(0, 0, 82),
		LeftElbow = v(10, 0, 0),
		RightElbow = v(10, 0, 0),
		LeftHip = v(32, 0, -14),
		RightHip = v(32, 0, 14),
		LeftKnee = v(-52, 0, 0),
		RightKnee = v(-52, 0, 0),
		LeftAnkle = v(20, 0, 0),
		RightAnkle = v(20, 0, 0),
	},
	-- Rear hand grabs the toe edge between the feet.
	Indy = {
		Root = v(0, 0.95, 0),
		Waist = v(-35, 0, 0),
		Neck = v(0, 50, 0),
		LeftShoulder = v(0, 0, -95),
		RightShoulder = v(55, 0, 10),
		LeftElbow = v(10, 0, 0),
		RightElbow = v(10, 0, 0),
		LeftHip = v(80, 0, -12),
		RightHip = v(80, 0, 12),
		LeftKnee = v(-115, 0, 0),
		RightKnee = v(-115, 0, 0),
		LeftAnkle = v(35, 0, 0),
		RightAnkle = v(35, 0, 0),
	},
	-- Front hand grabs the heel edge, board tweaked up behind, back arched.
	Method = {
		Root = v(0, 0.9, 0),
		Waist = v(15, -10, 0),
		Neck = v(5, 70, 0),
		LeftShoulder = v(-40, 0, -10),
		RightShoulder = v(0, 0, 100),
		LeftElbow = v(15, 0, 0),
		RightElbow = v(5, 0, 0),
		LeftHip = v(70, 0, -10),
		RightHip = v(70, 0, 10),
		LeftKnee = v(-120, 0, 0),
		RightKnee = v(-120, 0, 0),
		LeftAnkle = v(40, 0, 0),
		RightAnkle = v(40, 0, 0),
	},
	-- Front hand reaches for the nose.
	Nose = {
		Root = v(0, 0.9, 0),
		Waist = v(-30, 25, -15),
		Neck = v(0, 60, 0),
		LeftShoulder = v(40, 0, -40),
		RightShoulder = v(0, 0, 70),
		LeftElbow = v(5, 0, 0),
		RightElbow = v(10, 0, 0),
		LeftHip = v(85, 0, -10),
		RightHip = v(55, 0, 14),
		LeftKnee = v(-120, 0, 0),
		RightKnee = v(-80, 0, 0),
		LeftAnkle = v(35, 0, 0),
		RightAnkle = v(30, 0, 0),
	},
	-- Rear hand reaches for the tail.
	Tail = {
		Root = v(0, 0.9, 0),
		Waist = v(-30, -20, 15),
		Neck = v(0, 60, 0),
		LeftShoulder = v(0, 0, -70),
		RightShoulder = v(40, 0, 40),
		LeftElbow = v(10, 0, 0),
		RightElbow = v(5, 0, 0),
		LeftHip = v(55, 0, -14),
		RightHip = v(85, 0, 10),
		LeftKnee = v(-80, 0, 0),
		RightKnee = v(-120, 0, 0),
		LeftAnkle = v(30, 0, 0),
		RightAnkle = v(35, 0, 0),
	},
}

local MOTOR_NAMES = {
	"Root",
	"Waist",
	"Neck",
	"LeftShoulder",
	"RightShoulder",
	"LeftElbow",
	"RightElbow",
	"LeftHip",
	"RightHip",
	"LeftKnee",
	"RightKnee",
	"LeftAnkle",
	"RightAnkle",
}

type Rig = {
	motors: { [string]: Motor6D },
	motorCount: number,
	scannedAt: number,
	current: { [string]: Vector3 },
	posing: boolean,
	throwStart: number?,
	spray: ParticleEmitter?,
	root: BasePart?,
}

local rigs: { [Model]: Rig } = {}
local BLEND_RATE = 14
local THROW_DURATION = 0.55

local function scanMotors(character: Model): ({ [string]: Motor6D }, number)
	local motors: { [string]: Motor6D } = {}
	local count = 0
	for _, d in character:GetDescendants() do
		if d:IsA("Motor6D") and table.find(MOTOR_NAMES, d.Name) then
			motors[d.Name] = d
			count += 1
		end
	end
	return motors, count
end

local function getRig(character: Model): Rig?
	local rig = rigs[character]
	if rig then
		-- Body parts can stream in after the character first appears.
		if rig.motorCount < #MOTOR_NAMES and os.clock() - rig.scannedAt > 1 then
			rig.motors, rig.motorCount = scanMotors(character)
			rig.scannedAt = os.clock()
		end
		return rig
	end
	if not character:FindFirstChild("UpperTorso") then
		return nil -- R6: leave default animations alone
	end
	local motors, count = scanMotors(character)
	local current: { [string]: Vector3 } = {}
	for _, name in MOTOR_NAMES do
		current[name] = Vector3.zero
	end
	rig = {
		motors = motors,
		motorCount = count,
		scannedAt = os.clock(),
		current = current,
		posing = false,
		throwStart = nil,
		spray = nil,
		root = character:FindFirstChild("HumanoidRootPart") :: BasePart?,
	}
	rigs[character] = rig
	character.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			rigs[character] = nil
		end
	end)
	return rig
end

local function toTransform(name: string, value: Vector3): CFrame
	if name == "Root" then
		return CFrame.new(0, -value.Y, 0)
	end
	return CFrame.Angles(math.rad(value.X), math.rad(value.Y), math.rad(value.Z))
end

-- Over-arm throw: wind up behind the head, whip forward, recover.
local function throwAngle(t: number): number
	if t < 0.18 then
		return -150 * (t / 0.18)
	elseif t < 0.3 then
		local k = (t - 0.18) / 0.12
		return -150 + 210 * k
	end
	local k = math.min((t - 0.3) / (THROW_DURATION - 0.3), 1)
	return 60 * (1 - k)
end

local function findSpray(character: Model): ParticleEmitter?
	local board = character:FindFirstChild("Snowboard")
	local deck = board and board:FindFirstChild("Deck")
	local attachment = deck and deck:FindFirstChild("SprayAttachment")
	local spray = attachment and attachment:FindFirstChild("Spray")
	if spray and spray:IsA("ParticleEmitter") then
		return spray
	end
	return nil
end

local function updateCharacter(character: Model, isLocal: boolean, dt: number, now: number)
	local rig = getRig(character)
	if not rig then
		return
	end
	local ragdolled = character:GetAttribute("Ragdolled") == true
	local riding = character:GetAttribute("Riding") == true and not ragdolled
	if isLocal then
		riding = riding and LocalRider.riding
	end

	-- Snow spray from the board edge while carving.
	if not rig.spray or not rig.spray.Parent then
		rig.spray = findSpray(character)
	end
	local spray = rig.spray
	local poseName = if isLocal then LocalRider.pose else (character:GetAttribute("Pose") :: string?) or "Ride"
	local leanValue = if isLocal then LocalRider.lean else (character:GetAttribute("Lean") :: number?) or 0
	if spray then
		local rate = 0
		local root = rig.root
		if riding and root and (poseName == "Ride" or poseName == "Crouch") then
			local speed = root.AssemblyLinearVelocity.Magnitude
			rate = math.clamp(speed * 1.2 + math.abs(leanValue) * 70 - 12, 0, 170)
		end
		spray.Rate = rate
	end

	if riding then
		local target = POSES[poseName] or POSES.Ride
		local alpha = 1 - math.exp(-BLEND_RATE * dt)
		for _, name in MOTOR_NAMES do
			local goal = target[name] or Vector3.zero
			if name == "Waist" then
				goal += Vector3.new(0, 0, leanValue * 12)
			end
			local cur = rig.current[name]:Lerp(goal, alpha)
			rig.current[name] = cur
			local motor = rig.motors[name]
			if motor then
				motor.Transform = toTransform(name, cur)
			end
		end
		rig.posing = true
	elseif rig.posing then
		-- Hand control back to the Animator.
		rig.posing = false
		for _, name in MOTOR_NAMES do
			rig.current[name] = Vector3.zero
			local motor = rig.motors[name]
			if motor and not ragdolled then
				motor.Transform = CFrame.identity
			end
		end
	end

	local throwStart = rig.throwStart
	if throwStart then
		local t = now - throwStart
		local motor = rig.motors.RightShoulder
		if t > THROW_DURATION or riding or ragdolled then
			rig.throwStart = nil
		elseif motor then
			motor.Transform = CFrame.Angles(math.rad(throwAngle(t)), 0, math.rad(10))
		end
	end
end

function PoseController.playThrow(character: Model)
	local rig = getRig(character)
	if rig then
		rig.throwStart = os.clock()
	end
end

function PoseController.start()
	local localPlayer = Players.LocalPlayer
	-- PreSimulation runs after the Animator has written its transforms for the frame.
	RunService.PreSimulation:Connect(function(dt)
		local now = os.clock()
		for _, p in Players:GetPlayers() do
			local character = p.Character
			if character and character.Parent then
				updateCharacter(character, p == localPlayer, dt, now)
			end
		end
	end)
end

return PoseController
