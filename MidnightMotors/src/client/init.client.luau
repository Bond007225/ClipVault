--!strict
-- THE client entry point. Two-phase startup like the server.

local Controllers = script:WaitForChild("Controllers")

local ORDER = { "HUD", "GarageUI", "DriveController", "Sirens" }

local loaded = {}
for _, name in ORDER do
	table.insert(loaded, require(Controllers:WaitForChild(name) :: ModuleScript) :: any)
end
for _, c in loaded do
	if typeof(c.init) == "function" then
		c.init()
	end
end
for _, c in loaded do
	if typeof(c.start) == "function" then
		task.spawn(c.start)
	end
end
