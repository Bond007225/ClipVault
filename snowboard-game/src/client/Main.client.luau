--!strict
-- Client bootstrap.

local Controllers = script.Parent:WaitForChild("Controllers")

local order = {
	"EffectsController",
	"HUDController",
	"PoseController",
	"RagdollController",
	"CameraController",
	"SnowboardController",
	"SnowballController",
	"ShopController",
}

for _, name in order do
	local module = require(Controllers:WaitForChild(name)) :: any
	local ok, err = pcall(module.start)
	if not ok then
		warn(`[Client] {name} failed to start: {err}`)
	end
end
