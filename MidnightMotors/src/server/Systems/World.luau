--!strict
-- Day/night cycle. Car headlights switch on automatically at night.

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)

local World = {}

local isNight = false

local function nightNow(): boolean
	local t = Lighting.ClockTime
	return t < 6.4 or t > 17.9
end

local function applyLight(light: Instance)
	if light:IsA("Light") then
		light.Enabled = isNight
	end
end

function World.init() end

function World.start()
	CollectionService:GetInstanceAddedSignal("CarLight"):Connect(applyLight)
	local hoursPerSecond = 24 / (Config.DayLengthMinutes * 60)
	while true do
		local dt = task.wait(0.5)
		Lighting.ClockTime = (Lighting.ClockTime + dt * hoursPerSecond) % 24
		local night = nightNow()
		if night ~= isNight then
			isNight = night
			for _, light in CollectionService:GetTagged("CarLight") do
				applyLight(light)
			end
		end
	end
end

return World
