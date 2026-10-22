--!strict
-- Central tuning values shared by server and client.

local Config = {
	Riding = {
		RideHeightPadding = 0.15, -- gap between feet and board top
		StickDistance = 2.5, -- how far the board "sticks" over bumps before going airborne
		MaxSpeed = 150,
		PushAccel = 28, -- flat-ground pushing (W)
		PushMaxSpeed = 30,
		BrakeDecel = 70, -- S on the ground
		Friction = 3,
		Drag = 0.004, -- quadratic air drag
		Grip = 8, -- how hard the edge kills sideways slide
		TurnRate = math.rad(150),
		TurnRateHighSpeed = math.rad(80),
		MaxLean = math.rad(24),
		OllieImpulse = 44, -- full-charge ollie
		OllieMinCharge = 0.55,
		OllieChargeTime = 0.35,
		SpinRate = math.rad(620),
		FlipRate = math.rad(470),
		RotationResponsiveness = 9, -- higher = snappier spin acceleration
		AutoCompleteStrength = 7, -- eases rotation to the nearest clean landing when input is released
		LandUpTolerance = math.rad(55),
		LandAxisTolerance = math.rad(50),
		CrashImpact = 75, -- sudden velocity change (studs/s) that counts as hitting something
		AirGraceTime = 0.18,
		GrindMinSpeed = 14,
		GrindFriction = 2,
		RailDetectRadius = 1.4,
	},

	Tricks = {
		MinAirTime = 0.45,
		ComboWindow = 3,
		MaxMultiplier = 5,
		MultiplierStep = 0.5,
		SpinPointsPer180 = 100,
		FlipPoints = 350,
		GrabBase = 120,
		GrabPerSecond = 80,
		GrabMaxSeconds = 2,
		GrabMinSeconds = 0.25,
		AirPerSecond = 40,
		GrindBase = 60,
		GrindPerSecond = 150,
		GrindMinSeconds = 0.3,
		BoardslideBonus = 1.25,
	},

	Snowball = {
		Cooldown = 0.45,
		Speed = 115,
		Gravity = 70,
		Lifetime = 3,
		HitRadius = 1.2,
		RagdollTargets = true, -- a direct hit knocks the target over
		RagdollTime = 1.5,
		KnockRidersOff = true,
		Knockback = 35,
		LobbySafeRadius = 0, -- set > 0 to disable hits near the lobby spawn
	},

	Ragdoll = {
		CrashDuration = 2.75,
	},

	Economy = {
		CoinsPerPoint = 0.1,
		StartingCoins = 250,
	},

	Leaderboard = {
		RefreshInterval = 60,
		TopCount = 10,
		TotalStore = "SnowPeak_TotalTrickPoints_v1",
		ComboStore = "SnowPeak_BestCombo_v1",
	},

	Data = {
		StoreName = "SnowPeak_PlayerData_v1",
		AutosaveInterval = 120,
		SessionLockTimeout = 1800,
	},
}

return Config
