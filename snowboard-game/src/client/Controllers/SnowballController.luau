--!strict
-- Off the board: click (or R2 / the touch button) to throw a snowball where you're
-- aiming. The server decides hits; this draws the balls, splats and throw pose.

local ContextActionService = game:GetService("ContextActionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local LocalRider = require(script.Parent.LocalRider)
local PoseController = require(script.Parent.PoseController)

local SnowballController = {}

local player = Players.LocalPlayer
local lastThrow = 0
local GRAVITY = Vector3.new(0, -Config.Snowball.Gravity, 0)

type VisualBall = { part: Part, velocity: Vector3, age: number, ignore: Model? }
local visuals: { VisualBall } = {}

local fxFolder: Folder
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function canThrow(): boolean
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid or humanoid.Health <= 0 then
		return false
	end
	if LocalRider.riding or LocalRider.uiOpen then
		return false
	end
	if character:GetAttribute("Riding") == true or character:GetAttribute("Ragdolled") == true then
		return false
	end
	return os.clock() - lastThrow >= Config.Snowball.Cooldown
end

local function throwAt(screenPoint: Vector2)
	if not canThrow() then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not character or not root then
		return
	end
	local camera = Workspace.CurrentCamera
	local ray = camera:ViewportPointToRay(screenPoint.X, screenPoint.Y)
	rayParams.FilterDescendantsInstances = { character, fxFolder }
	local hit = Workspace:Raycast(ray.Origin, ray.Direction * 600, rayParams)
	local aim = if hit then hit.Position else ray.Origin + ray.Direction * 600
	local origin = root.Position + Vector3.new(0, 1.6, 0)
	local dir = aim - origin
	if dir.Magnitude < 1 then
		return
	end
	-- Aim a little high to account for the drop over distance.
	local distance = dir.Magnitude
	local flight = distance / Config.Snowball.Speed
	dir = (dir + Vector3.new(0, 0.5 * Config.Snowball.Gravity * flight * flight, 0)).Unit
	lastThrow = os.clock()
	Remotes.event("ThrowSnowball"):FireServer(dir)
end

local function throwFromCenter()
	local camera = Workspace.CurrentCamera
	throwAt(camera.ViewportSize / 2)
end

local function splat(position: Vector3, hitPlayer: boolean)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Transparency = 1
	p.Size = Vector3.one
	p.CFrame = CFrame.new(position)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
	emitter.Color = ColorSequence.new(Color3.new(1, 1, 1))
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) })
	emitter.Lifetime = NumberRange.new(0.3, 0.6)
	emitter.Speed = NumberRange.new(8, 18)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Acceleration = Vector3.new(0, -40, 0)
	emitter.Rate = 0
	emitter.Parent = p
	p.Parent = fxFolder
	emitter:Emit(if hitPlayer then 40 else 22)
	Debris:AddItem(p, 1.2)
end

local function spawnVisual(thrower: Player, origin: Vector3, velocity: Vector3)
	local ball = Instance.new("Part")
	ball.Name = "Snowball"
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.new(0.9, 0.9, 0.9)
	ball.Color = Color3.new(1, 1, 1)
	ball.Material = Enum.Material.Snow
	ball.Anchored = true
	ball.CanCollide = false
	ball.CanQuery = false
	ball.CanTouch = false
	ball.CFrame = CFrame.new(origin)
	ball.Parent = fxFolder
	table.insert(visuals, { part = ball, velocity = velocity, age = 0, ignore = thrower.Character })
	if thrower.Character then
		PoseController.playThrow(thrower.Character)
	end
end

local function stepVisuals(dt: number)
	for i = #visuals, 1, -1 do
		local b = visuals[i]
		b.age += dt
		local nextVelocity = b.velocity + GRAVITY * dt
		local delta = (b.velocity + nextVelocity) * 0.5 * dt
		local ignore: { Instance } = { fxFolder }
		if b.ignore then
			table.insert(ignore, b.ignore)
		end
		rayParams.FilterDescendantsInstances = ignore
		local from = b.part.Position
		local hit = Workspace:Raycast(from, delta, rayParams)
		if hit or b.age > Config.Snowball.Lifetime then
			b.part:Destroy()
			table.remove(visuals, i)
		else
			b.velocity = nextVelocity
			b.part.CFrame = CFrame.new(from + delta)
		end
	end
end

local function bindGamepadThrow()
	ContextActionService:BindAction("SB_Throw", function(_, state)
		if state == Enum.UserInputState.Begin then
			throwFromCenter()
		end
		return Enum.ContextActionResult.Sink
	end, true, Enum.KeyCode.ButtonR2)
	ContextActionService:SetTitle("SB_Throw", "Throw")
	ContextActionService:SetPosition("SB_Throw", UDim2.new(1, -110, 1, -200))
end

function SnowballController.start()
	fxFolder = Instance.new("Folder")
	fxFolder.Name = "LocalFx"
	fxFolder.Parent = Workspace

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			throwAt(UserInputService:GetMouseLocation())
		end
	end)

	-- Touch/gamepad throw button only while on foot.
	local bound = false
	RunService.Heartbeat:Connect(function(dt)
		stepVisuals(dt)
		local want = not LocalRider.riding
		if want ~= bound then
			bound = want
			if want then
				bindGamepadThrow()
			else
				ContextActionService:UnbindAction("SB_Throw")
			end
		end
	end)

	Remotes.event("SnowballFx").OnClientEvent:Connect(spawnVisual)
	Remotes.event("SnowballSplat").OnClientEvent:Connect(splat)
end

return SnowballController
