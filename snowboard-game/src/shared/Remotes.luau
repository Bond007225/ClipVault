--!strict
-- Single place that declares every remote. The server creates them once; clients
-- wait for them by name.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "Remotes"

local EVENTS = {
	-- client -> server
	"ToggleBoard",
	"TrickLanded",
	"Crash",
	"ThrowSnowball",
	-- server -> client
	"SnowballFx",
	"SnowballSplat",
	"TrickAwarded",
	"ComboUpdate",
	"Notify",
	"Teleported",
	"Knockback",
}

local UNRELIABLE = {
	"PoseUpdate", -- client -> server, riding pose/lean for other players to see
}

local FUNCTIONS = {
	"GetProfile",
	"PurchaseItem",
	"EquipItem",
}

local Remotes = {}

local folder: Folder? = nil

function Remotes.setup()
	assert(RunService:IsServer(), "Remotes.setup is server-only")
	local f = Instance.new("Folder")
	f.Name = FOLDER_NAME
	for _, name in EVENTS do
		local r = Instance.new("RemoteEvent")
		r.Name = name
		r.Parent = f
	end
	for _, name in UNRELIABLE do
		local r = Instance.new("UnreliableRemoteEvent")
		r.Name = name
		r.Parent = f
	end
	for _, name in FUNCTIONS do
		local r = Instance.new("RemoteFunction")
		r.Name = name
		r.Parent = f
	end
	f.Parent = ReplicatedStorage
	folder = f
end

local function getFolder(): Folder
	if folder then
		return folder
	end
	local f = ReplicatedStorage:WaitForChild(FOLDER_NAME) :: Folder
	folder = f
	return f
end

function Remotes.event(name: string): RemoteEvent
	return getFolder():WaitForChild(name) :: RemoteEvent
end

function Remotes.unreliable(name: string): UnreliableRemoteEvent
	return getFolder():WaitForChild(name) :: UnreliableRemoteEvent
end

function Remotes.func(name: string): RemoteFunction
	return getFolder():WaitForChild(name) :: RemoteFunction
end

return Remotes
