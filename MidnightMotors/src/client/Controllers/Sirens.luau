--!strict
-- Flashes police lightbars locally (no network cost) for any police vehicle
-- or helicopter whose model has the "Sirens" attribute set.

local CollectionService = game:GetService("CollectionService")

local Sirens = {}

local OFF = Color3.fromRGB(30, 30, 30)

function Sirens.init() end

function Sirens.start()
	local tick = 0
	while true do
		task.wait(0.12)
		tick += 1
		for _, part in CollectionService:GetTagged("Lightbar") do
			if not part:IsA("BasePart") then
				continue
			end
			local model = part:FindFirstAncestorOfClass("Model")
			local on = model ~= nil and model:GetAttribute("Sirens") == true
			local color = part:GetAttribute("LightColor") :: Color3?
			local isRed = color ~= nil and color.R > color.B
			local lit = on and ((tick % 2 == 0) == isRed)
			part.Color = if lit and color then color else OFF
			local light = part:FindFirstChildOfClass("PointLight")
			if light then
				light.Enabled = lit
			end
		end
	end
end

return Sirens
