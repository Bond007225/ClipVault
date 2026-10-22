--!strict
-- Chase camera while riding: follows the direction of travel (not the board, so
-- spins and flips don't whip the camera around), widens FOV with speed, and can
-- be orbited with right-mouse drag or the right thumbstick.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local LocalRider = require(script.Parent.LocalRider)

local CameraController = {}

local player = Players.LocalPlayer
local active = false
local camDir = Vector3.new(0, 0, -1)
local camPos: Vector3? = nil
local yawOffset = 0
local dragging = false
local thumbstickX = 0
local BASE_FOV = 70

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude

local function update(dt: number)
	local camera = Workspace.CurrentCamera
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local shouldBeActive = LocalRider.riding and root ~= nil

	if shouldBeActive ~= active then
		active = shouldBeActive
		if active then
			camera.CameraType = Enum.CameraType.Scriptable
			camPos = camera.CFrame.Position
			local look = camera.CFrame.LookVector
			camDir = Vector3.new(look.X, 0, look.Z).Unit
			yawOffset = 0
		else
			camera.CameraType = Enum.CameraType.Custom
			camera.FieldOfView = BASE_FOV
			local h = character and character:FindFirstChildOfClass("Humanoid")
			if h then
				camera.CameraSubject = h
			end
		end
	end
	if not active or not root or not character then
		return
	end

	local vel = root.AssemblyLinearVelocity
	local flat = Vector3.new(vel.X, 0, vel.Z)
	if flat.Magnitude > 4 then
		camDir = camDir:Lerp(flat.Unit, 1 - math.exp(-3 * dt))
		if camDir.Magnitude > 0.01 then
			camDir = camDir.Unit
		end
	end

	yawOffset -= thumbstickX * 2.5 * dt
	if not dragging and math.abs(thumbstickX) < 0.1 then
		yawOffset *= math.exp(-1.5 * dt)
	end

	local dir = CFrame.fromAxisAngle(Vector3.yAxis, yawOffset):VectorToWorldSpace(camDir)
	local speed = vel.Magnitude
	local dist = 15 + math.min(speed, 120) * 0.05
	local focus = root.Position + Vector3.new(0, 2, 0)
	local desired = focus - dir * dist + Vector3.new(0, 5.5, 0)

	-- Don't clip through terrain or walls.
	params.FilterDescendantsInstances = { character }
	local hit = Workspace:Raycast(focus, desired - focus, params)
	if hit then
		desired = hit.Position + hit.Normal * 0.8
	end

	local cur = camPos or desired
	cur = cur:Lerp(desired, 1 - math.exp(-9 * dt))
	camPos = cur
	camera.CFrame = CFrame.lookAt(cur, focus + dir * 6)
	camera.FieldOfView = BASE_FOV + math.clamp((speed - 30) * 0.25, 0, 22)
end

function CameraController.start()
	RunService:BindToRenderStep("SnowboardCamera", Enum.RenderPriority.Camera.Value + 1, update)

	UserInputService.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton2 and active then
			dragging = true
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			dragging = false
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		elseif input.KeyCode == Enum.KeyCode.Thumbstick2 then
			thumbstickX = 0
		end
	end)
	UserInputService.InputChanged:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseMovement and dragging then
			yawOffset -= input.Delta.X * 0.006
		elseif input.KeyCode == Enum.KeyCode.Thumbstick2 then
			thumbstickX = if math.abs(input.Position.X) > 0.15 then input.Position.X else 0
		end
	end)
end

return CameraController
