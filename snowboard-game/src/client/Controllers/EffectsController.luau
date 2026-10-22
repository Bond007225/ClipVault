--!strict
-- Ambient snowfall that follows the camera.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local EffectsController = {}

function EffectsController.start()
	local emitterPart = Instance.new("Part")
	emitterPart.Name = "Snowfall"
	emitterPart.Anchored = true
	emitterPart.CanCollide = false
	emitterPart.CanQuery = false
	emitterPart.CanTouch = false
	emitterPart.Transparency = 1
	emitterPart.Size = Vector3.new(140, 1, 140)

	local snow = Instance.new("ParticleEmitter")
	snow.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	snow.Color = ColorSequence.new(Color3.new(1, 1, 1))
	snow.LightEmission = 0.3
	snow.Size = NumberSequence.new(0.18, 0.28)
	snow.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(0.85, 0.3), NumberSequenceKeypoint.new(1, 1) })
	snow.Lifetime = NumberRange.new(6, 9)
	snow.Rate = 220
	snow.Speed = NumberRange.new(6, 10)
	snow.EmissionDirection = Enum.NormalId.Bottom
	snow.SpreadAngle = Vector2.new(15, 15)
	snow.RotSpeed = NumberRange.new(-60, 60)
	snow.Acceleration = Vector3.new(1.5, 0, 0.5)
	snow.Parent = emitterPart
	emitterPart.Parent = Workspace

	RunService.RenderStepped:Connect(function()
		local camera = Workspace.CurrentCamera
		emitterPart.CFrame = CFrame.new(camera.CFrame.Position + Vector3.new(0, 45, 0))
	end)
end

return EffectsController
