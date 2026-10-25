--!strict
-- THE server entry point. Two-phase startup: every system's init() runs
-- (in dependency order) before any system's start() is spawned.

local Systems = script:WaitForChild("Systems")

local ORDER = {
	"PlayerData",
	"MapBuilder", -- must build before anything queries the layout
	"CarService",
	"Traffic",
	"Police",
	"Racing",
	"Meets",
	"World",
}

local loaded: { { name: string, mod: any } } = {}
for _, name in ORDER do
	local mod = require(Systems:WaitForChild(name) :: ModuleScript) :: any
	table.insert(loaded, { name = name, mod = mod })
end

for _, entry in loaded do
	if typeof(entry.mod.init) == "function" then
		local ok, err = pcall(entry.mod.init)
		if not ok then
			warn("[Server] init failed for " .. entry.name .. ": " .. tostring(err))
		end
	end
end

for _, entry in loaded do
	if typeof(entry.mod.start) == "function" then
		task.spawn(entry.mod.start)
	end
end

print("[MidnightMotors] server started")
