--!strict
-- Local snowboard physics. The client owns its character's physics, so riding is
-- simulated here: carving on any surface (slopes, kickers, pipe walls), ollies,
-- air spins/flips/grabs with smoothed rotation, rail grinds, landing checks and
-- crash detection. Tricks are reported to the server as raw data; the server
-- validates and scores them.

local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Catalog = require(Shared.Catalog)
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Tricks = require(Shared.Tricks)
local LocalRider = require(script.Parent.LocalRider)

local R = Config.Riding
local player = Players.LocalPlayer

local SnowboardController = {}

type Mode = "Off" | "Ground" | "Air" | "Grind"

local BOARD_THICKNESS = 0.22
local GRAB_ACTIONS = {
	SB_Grab_Indy = "Indy",
	SB_Grab_Method = "Method",
	SB_Grab_Nose = "Nose",
	SB_Grab_Tail = "Tail",
}

-- Character
local character: Model? = nil
local humanoid: Humanoid? = nil
local root: BasePart? = nil
local footOffset = 3
local rideHeight = 3.2
local stats: Catalog.BoardStats = { Speed = 1, Turn = 1, Pop = 1 }

-- Riding state
local mode: Mode = "Off"
local boardAxis = Vector3.new(0, 0, -1) -- direction the nose points, tangent to the ground
local groundUp = Vector3.yAxis
local lean = 0
local travelSign = 1
local lastSetVelocity = Vector3.zero
local crashed = false

-- Input
local jumpHeld = false
local jumpHeldSince = 0
local grabStack: { string } = {}

-- Air
local airTime = 0
local airGrace = 0
local airBase = CFrame.identity
local takeoffSign = 1
local spin, spinVel = 0, 0
local flip, flipVel = 0, 0
local grabTimes: { [string]: number } = {}
local airRotation = CFrame.identity

-- Grind
local rail: BasePart? = nil
local railT = 0
local railSign = 1
local railSpeed = 0
local grindTime = 0
local grindStyle = "50-50"

-- Plumbing
local controls: any = nil
local stepConnection: RBXScriptConnection? = nil
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true
local railParams = RaycastParams.new()
railParams.FilterType = Enum.RaycastFilterType.Include

local trickLanded: RemoteEvent
local crashRemote: RemoteEvent
local poseUpdate: UnreliableRemoteEvent
local lastPoseSent = ""
local lastLeanSent = 0
local lastPoseTime = 0

local GRAVITY_DIR = Vector3.new(0, -1, 0)

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function project(v: Vector3, n: Vector3): Vector3
	return v - n * v:Dot(n)
end

local function expAlpha(rate: number, dt: number): number
	return 1 - math.exp(-rate * dt)
end

-- Rider frame: the board's nose runs along -X, the rider faces their toe edge.
local function riderCFrame(pos: Vector3, nose: Vector3, up: Vector3, leanAngle: number): CFrame
	local x = -nose
	local y = (up - x * up:Dot(x)).Unit
	return CFrame.fromMatrix(pos, x, y) * CFrame.Angles(leanAngle, 0, 0)
end

local function rotationBetween(a: Vector3, b: Vector3, fraction: number): CFrame
	local axis = a:Cross(b)
	if axis.Magnitude < 1e-4 then
		return CFrame.identity
	end
	local angle = math.acos(math.clamp(a:Dot(b), -1, 1))
	return CFrame.fromAxisAngle(axis.Unit, angle * fraction)
end

local function moveInput(): Vector3
	if controls then
		local ok, v = pcall(function()
			return controls:GetMoveVector()
		end)
		if ok and typeof(v) == "Vector3" then
			return v
		end
	end
	return Vector3.zero
end

local function currentGrab(): string?
	return grabStack[#grabStack]
end

local function refreshRailList()
	railParams.FilterDescendantsInstances = CollectionService:GetTagged("Grindable")
end

local function refreshExclusions()
	local list: { Instance } = {}
	if character then
		table.insert(list, character)
	end
	local loose = Workspace:FindFirstChild("LooseBoards")
	if loose then
		table.insert(list, loose)
	end
	for _, p in Players:GetPlayers() do
		if p.Character and p.Character ~= character then
			table.insert(list, p.Character)
		end
	end
	rayParams.FilterDescendantsInstances = list
end

---------------------------------------------------------------------------
-- Pose replication (so other players see grabs/crouches)
---------------------------------------------------------------------------

local function updatePose()
	local pose = "Ride"
	if mode == "Ground" then
		pose = if jumpHeld then "Crouch" else "Ride"
	elseif mode == "Air" then
		pose = currentGrab() or "Air"
	elseif mode == "Grind" then
		pose = "Grind"
	end
	LocalRider.pose = pose
	LocalRider.lean = lean / R.MaxLean

	local now = os.clock()
	if pose ~= lastPoseSent or (math.abs(LocalRider.lean - lastLeanSent) > 0.1 and now - lastPoseTime > 0.1) then
		lastPoseSent = pose
		lastLeanSent = LocalRider.lean
		lastPoseTime = now
		poseUpdate:FireServer(pose, LocalRider.lean)
	end
end

---------------------------------------------------------------------------
-- Tricks
---------------------------------------------------------------------------

local function reportAir()
	if airTime < Config.Tricks.MinAirTime then
		return
	end
	local bestGrab: string? = nil
	local bestTime = 0
	for name, t in grabTimes do
		if t > bestTime then
			bestGrab, bestTime = name, t
		end
	end
	trickLanded:FireServer({
		kind = "Air",
		air = airTime,
		spin = Tricks.countSpin(math.deg(spin)),
		spinDir = (if spin >= 0 then 1 else -1) * takeoffSign,
		flips = Tricks.countFlips(math.deg(flip)),
		flipDir = (if flip >= 0 then 1 else -1) * takeoffSign,
		grab = bestGrab,
		grabTime = bestTime,
	})
	airTime = 0
end

local function endGrind()
	if rail and grindTime >= Config.Tricks.GrindMinSeconds then
		trickLanded:FireServer({ kind = "Grind", duration = grindTime, style = grindStyle })
	end
	rail = nil
	grindTime = 0
end

local function crash(reason: string)
	if mode == "Off" or crashed then
		return
	end
	crashed = true
	if mode == "Grind" then
		rail = nil
	end
	mode = "Off"
	LocalRider.mode = "Off"
	if stepConnection then
		stepConnection:Disconnect()
		stepConnection = nil
	end
	local h = humanoid
	if h then
		h.PlatformStand = false
		h:ChangeState(Enum.HumanoidStateType.Physics)
	end
	crashRemote:FireServer(reason)
	-- If the server disagrees (no ragdoll arrives), stand back up.
	task.delay(1.5, function()
		local c = character
		if h and c and c:GetAttribute("Ragdolled") ~= true and h:GetState() == Enum.HumanoidStateType.Physics then
			h:ChangeState(Enum.HumanoidStateType.GettingUp)
			if c:GetAttribute("Riding") == true then
				Remotes.event("ToggleBoard"):FireServer()
			end
		end
	end)
end

---------------------------------------------------------------------------
-- Mode transitions
---------------------------------------------------------------------------

local function enterAir(velocity: Vector3, grace: number)
	local r = root
	if not r then
		return
	end
	mode = "Air"
	airTime = 0
	airGrace = grace
	spin, spinVel, flip, flipVel = 0, 0, 0, 0
	grabTimes = {}
	takeoffSign = if velocity:Dot(boardAxis) >= 0 then 1 else -1
	airBase = riderCFrame(Vector3.zero, boardAxis, groundUp, 0).Rotation
	airRotation = airBase
	r.AssemblyLinearVelocity = velocity
	lastSetVelocity = velocity
end

local function ollie()
	local r = root
	if not r then
		return
	end
	local charge = math.clamp((os.clock() - jumpHeldSince) / R.OllieChargeTime, R.OllieMinCharge, 1)
	local impulse = R.OllieImpulse * charge * stats.Pop
	if mode == "Grind" then
		local part = rail
		local up = if part then part.CFrame.UpVector else Vector3.yAxis
		local v = lastSetVelocity + up * impulse * 0.85
		groundUp = up
		endGrind()
		enterAir(v, R.AirGraceTime)
	elseif mode == "Ground" then
		local v = lastSetVelocity + groundUp * impulse
		enterAir(v, R.AirGraceTime)
	end
end

-- Checks for a rail/box under the rider and starts grinding if one is found.
local function tryEnterGrind(velocity: Vector3, noseNow: Vector3, upNow: Vector3): boolean
	local r = root
	if not r then
		return false
	end
	local result = Workspace:Spherecast(r.Position, R.RailDetectRadius, GRAVITY_DIR * (footOffset + 1.6), railParams)
	if not result or not result.Instance:IsA("BasePart") then
		return false
	end
	local part = result.Instance :: BasePart
	local axis = part.CFrame.LookVector
	local up = part.CFrame.UpVector
	if velocity:Dot(up) > 4 then
		return false -- still rising; let them clear the rail first
	end
	local top = part.Position + up * (part.Size.Y / 2)
	local t = (r.Position - top):Dot(axis)
	local half = part.Size.Z / 2
	if math.abs(t) > half - 0.5 then
		return false
	end
	if upNow:Dot(up) < math.cos(math.rad(65)) then
		return false -- coming in sideways/upside down: not a grind
	end

	if mode == "Air" then
		reportAir()
	end

	local along = velocity:Dot(axis)
	mode = "Grind"
	rail = part
	railT = t
	railSign = if along >= 0 then 1 else -1
	railSpeed = math.max(math.abs(along), R.GrindMinSpeed)
	grindTime = 0
	grindStyle = if math.abs(project(noseNow, up).Unit:Dot(axis)) > 0.6 then "50-50" else "Boardslide"
	return true
end

local function land(hit: RaycastResult, velocity: Vector3)
	local r = root
	if not r then
		return
	end
	local n = hit.Normal
	local rot = airRotation
	local nose = project(-rot.RightVector, n)
	local vt = project(velocity, n)

	local upOK = rot.UpVector:Dot(n) > math.cos(R.LandUpTolerance)
	local axisOK = true
	if vt.Magnitude > 8 and nose.Magnitude > 0.2 then
		axisOK = math.abs(nose.Unit:Dot(vt.Unit)) > math.cos(R.LandAxisTolerance)
	end
	if not upOK or not axisOK then
		crash("Bad landing")
		return
	end

	if nose.Magnitude > 0.2 then
		boardAxis = nose.Unit
	else
		boardAxis = project(boardAxis, n).Unit
	end
	-- Snap the board onto the line of travel so landings feel clean.
	if vt.Magnitude > 8 then
		boardAxis = vt.Unit * (if boardAxis:Dot(vt) >= 0 then 1 else -1)
	end
	groundUp = n
	mode = "Ground"
	r.CFrame = riderCFrame(hit.Position + n * rideHeight, boardAxis, n, 0)
	r.AssemblyLinearVelocity = vt
	r.AssemblyAngularVelocity = Vector3.zero
	lastSetVelocity = vt
	reportAir()
end

---------------------------------------------------------------------------
-- Per-mode simulation
---------------------------------------------------------------------------

local function impactCheck(vActual: Vector3, dt: number): boolean
	local expected = lastSetVelocity + GRAVITY_DIR * Workspace.Gravity * dt
	if lastSetVelocity.Magnitude > 35 and (vActual - expected).Magnitude > R.CrashImpact then
		crash("Wipeout")
		return true
	end
	return false
end

local function groundStep(r: BasePart, dt: number)
	local vActual = r.AssemblyLinearVelocity
	if impactCheck(vActual, dt) then
		return
	end

	local hit = Workspace:Raycast(r.Position, -groundUp * (rideHeight + R.StickDistance), rayParams)
	if not hit then
		-- Ran off a lip or a cliff.
		enterAir(vActual, 0.08)
		return
	end
	if tryEnterGrind(vActual, boardAxis, groundUp) then
		return
	end

	local n = hit.Normal
	groundUp = n
	local v = project(vActual, n)
	local axis = project(boardAxis, n)
	if axis.Magnitude < 0.1 then
		axis = project(r.CFrame.LookVector, n)
	end
	boardAxis = axis.Unit

	local input = moveInput()
	local steer = math.clamp(input.X, -1, 1)
	local throttle = math.clamp(-input.Z, -1, 1)
	local speed = v.Magnitude

	local turnRate = (R.TurnRate + (R.TurnRateHighSpeed - R.TurnRate) * math.clamp(speed / 100, 0, 1)) * stats.Turn
	if math.abs(steer) > 0.05 then
		boardAxis = CFrame.fromAxisAngle(n, -steer * turnRate * dt):VectorToWorldSpace(boardAxis)
	end

	local along = v:Dot(boardAxis)
	local lateral = v - boardAxis * along
	-- The edge bites: sideways slide dies off, which is what makes carving turn you.
	lateral *= math.exp(-R.Grip * dt)

	if math.abs(along) > 1 then
		travelSign = if along >= 0 then 1 else -1
	end
	local decel = R.Friction + R.Drag * along * along
	if throttle < -0.3 then
		decel += R.BrakeDecel * -throttle
	end
	along = travelSign * math.max(0, math.abs(along) - decel * dt)
	if throttle > 0.3 and math.abs(along) < R.PushMaxSpeed then
		along += travelSign * R.PushAccel * throttle * dt
	end
	local maxSpeed = R.MaxSpeed * stats.Speed
	along = math.clamp(along, -maxSpeed, maxSpeed)

	local targetLean = -steer * R.MaxLean * travelSign * math.clamp(speed / 30, 0.3, 1)
	lean += (targetLean - lean) * expAlpha(10, dt)

	local vNew = boardAxis * along + lateral
	r.CFrame = riderCFrame(hit.Position + n * rideHeight, boardAxis, n, lean)
	r.AssemblyLinearVelocity = vNew
	r.AssemblyAngularVelocity = Vector3.zero
	lastSetVelocity = vNew
	LocalRider.speed = vNew.Magnitude
end

local function airStep(r: BasePart, dt: number)
	local vActual = r.AssemblyLinearVelocity
	if impactCheck(vActual, dt) then
		return
	end
	lastSetVelocity = vActual
	airTime += dt
	airGrace -= dt
	LocalRider.speed = vActual.Magnitude

	local input = moveInput()
	local steer = math.clamp(input.X, -1, 1)
	local throttle = math.clamp(-input.Z, -1, 1)
	local alpha = expAlpha(R.RotationResponsiveness, dt)

	-- Spins: hold a direction to rotate; let go and the spin eases to the nearest 180.
	local spinTarget: number
	if math.abs(steer) > 0.2 then
		spinTarget = -steer * R.SpinRate
	else
		local snap = math.round(spin / math.pi) * math.pi
		spinTarget = math.clamp((snap - spin) * R.AutoCompleteStrength, -R.SpinRate, R.SpinRate)
	end
	spinVel += (spinTarget - spinVel) * alpha
	spin += spinVel * dt

	local flipTarget: number
	if math.abs(throttle) > 0.2 then
		flipTarget = throttle * R.FlipRate * takeoffSign
	else
		local snap = math.round(flip / (2 * math.pi)) * 2 * math.pi
		flipTarget = math.clamp((snap - flip) * R.AutoCompleteStrength, -R.FlipRate, R.FlipRate)
	end
	flipVel += (flipTarget - flipVel) * alpha
	flip += flipVel * dt

	local grab = currentGrab()
	if grab then
		grabTimes[grab] = (grabTimes[grab] or 0) + dt
	end

	-- Let the board's pitch follow the arc of the jump (not in the pipe, where
	-- you go straight up and down).
	local nose = -airBase.RightVector * takeoffSign
	if vActual.Magnitude > 15 and math.abs(vActual.Unit.Y) < 0.85 and math.abs(nose.Y) < 0.9 then
		local flatNose = Vector3.new(nose.X, 0, nose.Z)
		if flatNose.Magnitude > 0.1 then
			local horizontalSpeed = Vector3.new(vActual.X, 0, vActual.Z).Magnitude
			local target = (flatNose.Unit * horizontalSpeed + Vector3.yAxis * vActual.Y).Unit
			airBase = rotationBetween(nose, target, expAlpha(3, dt)) * airBase
		end
	end

	airRotation = airBase * CFrame.Angles(0, spin, 0) * CFrame.Angles(0, 0, flip)
	r.CFrame = CFrame.new(r.Position) * airRotation
	r.AssemblyAngularVelocity = Vector3.zero

	if airGrace > 0 then
		return
	end

	if tryEnterGrind(vActual, -airRotation.RightVector, airRotation.UpVector) then
		return
	end

	-- Look for the ground straight down and below the board (pipe walls).
	local reach = rideHeight + 0.8 + math.max(0, -vActual.Y) * dt * 1.5
	local best: RaycastResult? = nil
	for _, dir in { GRAVITY_DIR, -airRotation.UpVector } do
		local hit = Workspace:Raycast(r.Position, dir * reach, rayParams)
		if hit and vActual:Dot(hit.Normal) < 0 and (not best or hit.Distance < best.Distance) then
			best = hit
		end
	end
	if best and best.Distance <= rideHeight + 0.6 + math.max(0, -vActual.Y) * dt then
		land(best, vActual)
	end
end

local function grindStep(r: BasePart, dt: number)
	local part = rail
	if not part or not part.Parent then
		endGrind()
		enterAir(lastSetVelocity, 0.05)
		return
	end
	local axis = part.CFrame.LookVector
	local up = part.CFrame.UpVector
	local dir = axis * railSign

	railSpeed += (GRAVITY_DIR * Workspace.Gravity):Dot(dir) * dt - R.GrindFriction * dt
	railT += railSign * railSpeed * dt
	grindTime += dt
	LocalRider.speed = railSpeed

	local half = part.Size.Z / 2
	if railSpeed < 3 or math.abs(railT) > half then
		groundUp = up
		boardAxis = if grindStyle == "50-50" then dir else up:Cross(dir)
		endGrind()
		enterAir(dir * math.max(railSpeed, 0) + up * 3, 0.05)
		return
	end

	local top = part.Position + up * (part.Size.Y / 2)
	local pos = top + axis * railT + up * (footOffset + BOARD_THICKNESS)
	local nose = if grindStyle == "50-50" then dir else up:Cross(dir)
	boardAxis = nose
	groundUp = up
	-- A little balance wobble.
	lean = math.sin(grindTime * 7) * 0.06
	local v = dir * railSpeed
	r.CFrame = riderCFrame(pos, nose, up, lean)
	r.AssemblyLinearVelocity = v
	r.AssemblyAngularVelocity = Vector3.zero
	lastSetVelocity = v
end

local function step(dt: number)
	local r = root
	local h = humanoid
	if not r or not h or h.Health <= 0 then
		return
	end
	dt = math.min(dt, 1 / 20)
	if mode == "Ground" then
		groundStep(r, dt)
	elseif mode == "Air" then
		airStep(r, dt)
	elseif mode == "Grind" then
		grindStep(r, dt)
	end
	LocalRider.mode = mode
	if mode ~= "Off" then
		updatePose()
	end
end

---------------------------------------------------------------------------
-- Input
---------------------------------------------------------------------------

local function onJump(_: string, state: Enum.UserInputState, _: InputObject): Enum.ContextActionResult
	if state == Enum.UserInputState.Begin then
		jumpHeld = true
		jumpHeldSince = os.clock()
	elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
		if jumpHeld and state == Enum.UserInputState.End then
			jumpHeld = false
			ollie()
		end
		jumpHeld = false
	end
	return Enum.ContextActionResult.Sink
end

local function onGrab(actionName: string, state: Enum.UserInputState, _: InputObject): Enum.ContextActionResult
	local grab = GRAB_ACTIONS[actionName]
	if not grab then
		return Enum.ContextActionResult.Pass
	end
	local idx = table.find(grabStack, grab)
	if idx then
		table.remove(grabStack, idx)
	end
	if state == Enum.UserInputState.Begin then
		table.insert(grabStack, grab)
	end
	return Enum.ContextActionResult.Sink
end

local function bindRidingActions()
	local priority = Enum.ContextActionPriority.High.Value
	ContextActionService:BindActionAtPriority("SB_Jump", onJump, true, priority, Enum.KeyCode.Space, Enum.KeyCode.ButtonA)
	ContextActionService:SetTitle("SB_Jump", "Ollie")
	ContextActionService:SetPosition("SB_Jump", UDim2.new(1, -110, 1, -110))

	ContextActionService:BindActionAtPriority("SB_Grab_Indy", onGrab, true, priority, Enum.KeyCode.Q, Enum.KeyCode.ButtonX)
	ContextActionService:SetTitle("SB_Grab_Indy", "Grab")
	ContextActionService:SetPosition("SB_Grab_Indy", UDim2.new(1, -190, 1, -80))
	ContextActionService:BindActionAtPriority("SB_Grab_Method", onGrab, false, priority, Enum.KeyCode.F, Enum.KeyCode.ButtonY)
	ContextActionService:BindActionAtPriority("SB_Grab_Nose", onGrab, false, priority, Enum.KeyCode.R, Enum.KeyCode.ButtonL1)
	ContextActionService:BindActionAtPriority("SB_Grab_Tail", onGrab, false, priority, Enum.KeyCode.T, Enum.KeyCode.ButtonR1)
end

local function unbindRidingActions()
	for _, name in { "SB_Jump", "SB_Grab_Indy", "SB_Grab_Method", "SB_Grab_Nose", "SB_Grab_Tail" } do
		ContextActionService:UnbindAction(name)
	end
	jumpHeld = false
	table.clear(grabStack)
end

---------------------------------------------------------------------------
-- Start / stop riding (driven by the server's "Riding" attribute)
---------------------------------------------------------------------------

local function setAnimate(enabled: boolean)
	local c = character
	local h = humanoid
	if not c or not h then
		return
	end
	local animate = c:FindFirstChild("Animate")
	if animate and animate:IsA("BaseScript") then
		animate.Enabled = enabled
	end
	if not enabled then
		local animator = h:FindFirstChildOfClass("Animator")
		if animator then
			for _, track in animator:GetPlayingAnimationTracks() do
				track:Stop(0.15)
			end
		end
	end
end

local function startRiding()
	local c, h, r = character, humanoid, root
	if not c or not h or not r or mode ~= "Off" then
		return
	end
	crashed = false
	footOffset = r.Size.Y / 2 + (if h.RigType == Enum.HumanoidRigType.R6 then 2 else h.HipHeight)
	rideHeight = footOffset + BOARD_THICKNESS
	local board = c:FindFirstChild("Snowboard")
	stats = Catalog.boardStats(if board then board:GetAttribute("BoardId") :: string? else nil)

	refreshExclusions()
	refreshRailList()

	h.PlatformStand = true
	h:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
	h:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
	setAnimate(false)

	local look = r.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	boardAxis = if flat.Magnitude > 0.1 then flat.Unit else Vector3.new(0, 0, -1)
	groundUp = Vector3.yAxis
	travelSign = 1
	lean = 0
	lastSetVelocity = r.AssemblyLinearVelocity
	enterAir(r.AssemblyLinearVelocity, 0)

	bindRidingActions()
	LocalRider.riding = true
	if stepConnection then
		stepConnection:Disconnect()
	end
	stepConnection = RunService.PreSimulation:Connect(step)
end

local function stopRiding()
	if stepConnection then
		stepConnection:Disconnect()
		stepConnection = nil
	end
	if mode == "Grind" then
		rail = nil
	end
	mode = "Off"
	LocalRider.mode = "Off"
	LocalRider.riding = false
	LocalRider.pose = "None"
	LocalRider.speed = 0
	unbindRidingActions()

	local c, h, r = character, humanoid, root
	if not c or not h then
		return
	end
	setAnimate(true)
	h:SetStateEnabled(Enum.HumanoidStateType.FallingDown, true)
	h:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, true)
	if c:GetAttribute("Ragdolled") ~= true and not crashed then
		h.PlatformStand = false
		if r then
			-- Stand upright facing the way we were riding.
			local flat = Vector3.new(boardAxis.X, 0, boardAxis.Z)
			if flat.Magnitude > 0.1 then
				r.CFrame = CFrame.lookAt(r.Position, r.Position + flat.Unit)
			end
			r.AssemblyLinearVelocity = Vector3.new(0, math.min(r.AssemblyLinearVelocity.Y, 0), 0) + lastSetVelocity * 0.3
		end
		h:ChangeState(Enum.HumanoidStateType.GettingUp)
	end
end

local function onCharacter(c: Model)
	stopRiding()
	character = c
	humanoid = c:WaitForChild("Humanoid") :: Humanoid
	root = c:WaitForChild("HumanoidRootPart") :: BasePart
	mode = "Off"
	crashed = false

	c:GetAttributeChangedSignal("Riding"):Connect(function()
		if character ~= c then
			return
		end
		if c:GetAttribute("Riding") == true then
			startRiding()
		else
			stopRiding()
		end
	end)
	if c:GetAttribute("Riding") == true then
		startRiding()
	end
end

function SnowboardController.start()
	trickLanded = Remotes.event("TrickLanded")
	crashRemote = Remotes.event("Crash")
	poseUpdate = Remotes.unreliable("PoseUpdate")

	task.spawn(function()
		local ok, module = pcall(function()
			local playerModule = player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule")
			return (require :: any)(playerModule)
		end)
		if ok and module then
			controls = module:GetControls()
		else
			warn("[Snowboard] PlayerModule not found; movement input unavailable")
		end
	end)

	CollectionService:GetInstanceAddedSignal("Grindable"):Connect(refreshRailList)
	CollectionService:GetInstanceRemovedSignal("Grindable"):Connect(refreshRailList)
	Players.PlayerAdded:Connect(function(p)
		p.CharacterAdded:Connect(function()
			task.wait()
			refreshExclusions()
		end)
	end)
	for _, p in Players:GetPlayers() do
		p.CharacterAdded:Connect(function()
			task.wait()
			refreshExclusions()
		end)
	end

	-- Strap in / out works whether or not you're riding.
	ContextActionService:BindAction("SB_ToggleBoard", function(_, state)
		if state == Enum.UserInputState.Begin then
			Remotes.event("ToggleBoard"):FireServer()
		end
		return Enum.ContextActionResult.Sink
	end, true, Enum.KeyCode.E, Enum.KeyCode.ButtonB)
	ContextActionService:SetTitle("SB_ToggleBoard", "Board")
	ContextActionService:SetPosition("SB_ToggleBoard", UDim2.new(1, -190, 1, -160))

	Remotes.event("Teleported").OnClientEvent:Connect(function(dest: CFrame)
		local r = root
		if not r then
			return
		end
		r.AssemblyLinearVelocity = Vector3.zero
		lastSetVelocity = Vector3.zero
		local flat = Vector3.new(dest.LookVector.X, 0, dest.LookVector.Z)
		if flat.Magnitude > 0.1 then
			boardAxis = flat.Unit
		end
		if mode ~= "Off" then
			if mode == "Grind" then
				rail = nil
			end
			groundUp = Vector3.yAxis
			enterAir(Vector3.zero, 0.1)
		end
	end)

	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
end

return SnowboardController
