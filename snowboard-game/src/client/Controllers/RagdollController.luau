--!strict
-- The client owns its character's physics, so it must put its own Humanoid into the
-- Physics state while the server has it ragdolled, and stand back up afterwards.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local RagdollController = {}

local player = Players.LocalPlayer

local function onCharacter(character: Model)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid

	local function apply()
		if humanoid.Health <= 0 then
			return
		end
		if character:GetAttribute("Ragdolled") == true then
			humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, false)
			humanoid.PlatformStand = false
			humanoid:ChangeState(Enum.HumanoidStateType.Physics)
		else
			humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, true)
			if humanoid:GetState() == Enum.HumanoidStateType.Physics then
				humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
			end
		end
	end
	character:GetAttributeChangedSignal("Ragdolled"):Connect(apply)
	apply()
end

function RagdollController.start()
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end

	Remotes.event("Knockback").OnClientEvent:Connect(function(push: Vector3)
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root and typeof(push) == "Vector3" then
			task.defer(function()
				root.AssemblyLinearVelocity += push
			end)
		end
	end)
end

return RagdollController
