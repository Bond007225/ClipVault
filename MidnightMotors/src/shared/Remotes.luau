--!strict
-- Single list of every remote. The server creates them at startup; the client
-- waits for them. Add a remote = add one line here.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local EVENTS = {
	-- client -> server
	"SpawnCar", -- ()
	"BuyCar", -- (carId)
	"SelectCar", -- (carId)
	"BuyUpgrade", -- (category, tier)
	"SetCosmetic", -- (key, optionName)
	"SetTuning", -- (key, value)
	"ExitCar", -- ()
	"EventJoin", -- (join: boolean)
	-- server -> client
	"ProfileUpdated", -- (profileSnapshot)
	"Notify", -- (text, kind)
	"OpenGarage", -- ()
	"RaceUpdate", -- (payload)
	"CameraFlash", -- ()
	"EventUpdate", -- (payload)
}

local FUNCTIONS = {
	"GetProfile", -- () -> profileSnapshot
}

local Remotes = {}

local folder: Folder
if RunService:IsServer() then
	folder = Instance.new("Folder")
	folder.Name = "Remotes"
	for _, name in EVENTS do
		local r = Instance.new("RemoteEvent")
		r.Name = name
		r.Parent = folder
	end
	for _, name in FUNCTIONS do
		local r = Instance.new("RemoteFunction")
		r.Name = name
		r.Parent = folder
	end
	folder.Parent = ReplicatedStorage
else
	folder = ReplicatedStorage:WaitForChild("Remotes") :: Folder
end

function Remotes.event(name: string): RemoteEvent
	return folder:WaitForChild(name) :: RemoteEvent
end

function Remotes.func(name: string): RemoteFunction
	return folder:WaitForChild(name) :: RemoteFunction
end

return Remotes
