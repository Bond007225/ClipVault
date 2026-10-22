--!strict
-- Shared local state between client controllers (the local player's rider).

local LocalRider = {
	riding = false,
	mode = "Off", -- Off | Ground | Air | Grind
	pose = "None",
	lean = 0,
	speed = 0,
	uiOpen = false,
}

return LocalRider
