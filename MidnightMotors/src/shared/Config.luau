--!strict
-- All gameplay tunables in one place. The client can read this file, so every
-- price/limit here is re-checked on the server before it is trusted.

local Config = {}

-- 1 stud = 0.28 m (Roblox convention) -> mph
Config.STUDS_TO_MPH = 0.626
Config.MILE_STUDS = 5748

Config.StartingCash = 15000
Config.CashPerMileDriven = 20
Config.GasPricePerGallon = 3.5

-- Speed limits in mph per zone ("Track" is unlimited)
Config.SpeedLimits = {
	City = 45,
	Rural = 55,
	Highway = 70,
	Track = math.huge,
}

----------------------------------------------------------------------
-- Map layout
----------------------------------------------------------------------
Config.Map = {
	CityBlocks = 18, -- 18x18 grid of city blocks (~5,400 studs across)
	CellSize = 300, -- road-centre to road-centre
	RoadWidth = 52,
	SidewalkWidth = 8,
	RingHalfSize = 3200, -- highway ring around the city (centreline)
	HighwayWidth = 96,
	InterstateLength = 9000, -- long straight highway out to the tracks
	DeckHeight = 32, -- elevated highway surface height
	QuarterMile = 1437, -- studs
	HalfMile = 2874,
}

----------------------------------------------------------------------
-- Cars
--  Power      : drive acceleration (studs/s^2) in 1st gear at peak torque
--  TopSpeed   : mph at redline in top gear
--  Brake      : braking deceleration (studs/s^2)
--  Grip       : tyre friction coefficient
----------------------------------------------------------------------
export type CarDef = {
	Name: string,
	Price: number,
	Style: string,
	Drivetrain: string,
	Width: number,
	Length: number,
	BodyHeight: number,
	CabinHeight: number,
	WheelBase: number,
	WheelRadius: number,
	Power: number,
	TopSpeed: number,
	Redline: number,
	Gears: { number },
	Grip: number,
	Brake: number,
	SpringFreq: number,
	Damping: number,
	RideHeight: number,
	FuelCapacity: number,
	Weight: number,
	DefaultPaint: string,
	Seats: number,
}

Config.Cars = {
	Hatch = {
		Name = "Kanto Hatch",
		Price = 0,
		Style = "hatch",
		Drivetrain = "FWD",
		Width = 6.2,
		Length = 12.5,
		BodyHeight = 2.2,
		CabinHeight = 2.2,
		WheelBase = 8.4,
		WheelRadius = 1.15,
		Power = 34,
		TopSpeed = 118,
		Redline = 7200,
		Gears = { 3.3, 2.1, 1.5, 1.15, 0.92 },
		Grip = 1.05,
		Brake = 110,
		SpringFreq = 1.8,
		Damping = 0.45,
		RideHeight = 0.9,
		FuelCapacity = 11,
		Weight = 2600,
		DefaultPaint = "Arctic White",
		Seats = 4,
	},
	Coupe = {
		Name = "Shiro S-Coupe",
		Price = 18000,
		Style = "coupe",
		Drivetrain = "RWD",
		Width = 6.5,
		Length = 14,
		BodyHeight = 2.0,
		CabinHeight = 2.0,
		WheelBase = 9.4,
		WheelRadius = 1.2,
		Power = 42,
		TopSpeed = 145,
		Redline = 7800,
		Gears = { 3.6, 2.3, 1.65, 1.25, 1.0, 0.82 },
		Grip = 1.1,
		Brake = 125,
		SpringFreq = 2.0,
		Damping = 0.5,
		RideHeight = 0.8,
		FuelCapacity = 13,
		Weight = 2800,
		DefaultPaint = "Midnight Purple",
		Seats = 2,
	},
	Pickup = {
		Name = "Ridge 1500 Pickup",
		Price = 22000,
		Style = "truck",
		Drivetrain = "RWD",
		Width = 7.4,
		Length = 17,
		BodyHeight = 2.8,
		CabinHeight = 2.6,
		WheelBase = 11.5,
		WheelRadius = 1.55,
		Power = 40,
		TopSpeed = 120,
		Redline = 5800,
		Gears = { 3.0, 1.95, 1.4, 1.0, 0.8 },
		Grip = 0.95,
		Brake = 105,
		SpringFreq = 1.5,
		Damping = 0.4,
		RideHeight = 1.6,
		FuelCapacity = 20,
		Weight = 4800,
		DefaultPaint = "Forest Green",
		Seats = 2,
	},
	Muscle = {
		Name = "Detroit Charger 69",
		Price = 26000,
		Style = "muscle",
		Drivetrain = "RWD",
		Width = 7,
		Length = 16,
		BodyHeight = 2.3,
		CabinHeight = 2.0,
		WheelBase = 10.6,
		WheelRadius = 1.3,
		Power = 52,
		TopSpeed = 155,
		Redline = 6200,
		Gears = { 2.9, 1.9, 1.35, 1.0, 0.78 },
		Grip = 1.0,
		Brake = 115,
		SpringFreq = 1.6,
		Damping = 0.4,
		RideHeight = 1.0,
		FuelCapacity = 17,
		Weight = 3700,
		DefaultPaint = "Race Red",
		Seats = 4,
	},
	Rally = {
		Name = "Akira Rally Sedan",
		Price = 38000,
		Style = "sedan",
		Drivetrain = "AWD",
		Width = 6.6,
		Length = 14.5,
		BodyHeight = 2.3,
		CabinHeight = 2.2,
		WheelBase = 9.8,
		WheelRadius = 1.25,
		Power = 50,
		TopSpeed = 150,
		Redline = 7500,
		Gears = { 3.5, 2.25, 1.6, 1.22, 0.98, 0.8 },
		Grip = 1.15,
		Brake = 130,
		SpringFreq = 1.9,
		Damping = 0.5,
		RideHeight = 1.1,
		FuelCapacity = 15,
		Weight = 3200,
		DefaultPaint = "Rally Blue",
		Seats = 4,
	},
	Super = {
		Name = "Vortex GT-R",
		Price = 120000,
		Style = "super",
		Drivetrain = "AWD",
		Width = 7.2,
		Length = 15,
		BodyHeight = 1.8,
		CabinHeight = 1.7,
		WheelBase = 10,
		WheelRadius = 1.3,
		Power = 68,
		TopSpeed = 205,
		Redline = 8500,
		Gears = { 3.8, 2.5, 1.85, 1.45, 1.17, 0.96, 0.8 },
		Grip = 1.3,
		Brake = 150,
		SpringFreq = 2.3,
		Damping = 0.55,
		RideHeight = 0.7,
		FuelCapacity = 18,
		Weight = 3300,
		DefaultPaint = "Lime Rush",
		Seats = 2,
	},
} :: { [string]: CarDef }

Config.CarOrder = { "Hatch", "Coupe", "Pickup", "Muscle", "Rally", "Super" }

----------------------------------------------------------------------
-- Performance upgrades. Tier 1 is always stock.
--  Mul : multiplies the stat     Add : adds to the stat     Set : overrides
----------------------------------------------------------------------
export type Tier = {
	Name: string,
	Price: number,
	Mul: { [string]: number }?,
	Add: { [string]: number }?,
	Set: { [string]: number }?,
}

local TIER_NAMES = { "Stock", "Street", "Sport", "Race", "Pro" }
local STD_PRICES = { 0, 1500, 4000, 9000, 18000 }

local function tiers(prices: { number }, mods: { { Mul: any?, Add: any?, Set: any? } }): { Tier }
	local out = {}
	for i = 1, 5 do
		local m = mods[i] or {}
		out[i] = { Name = TIER_NAMES[i], Price = prices[i], Mul = m.Mul, Add = m.Add, Set = m.Set }
	end
	return out
end

Config.Upgrades = {
	Engine = {
		Name = "Engine",
		Desc = "Cams, intake, exhaust and a bigger bore. More power and a higher redline.",
		Tiers = tiers(STD_PRICES, {
			{},
			{ Mul = { Power = 1.10, TopSpeedMph = 1.03, Economy = 1.05 }, Add = { Redline = 200 } },
			{ Mul = { Power = 1.22, TopSpeedMph = 1.06, Economy = 1.10 }, Add = { Redline = 400 } },
			{ Mul = { Power = 1.36, TopSpeedMph = 1.10, Economy = 1.18 }, Add = { Redline = 700 } },
			{ Mul = { Power = 1.52, TopSpeedMph = 1.14, Economy = 1.28 }, Add = { Redline = 1000 } },
		}),
	},
	Turbo = {
		Name = "Forced Induction",
		Desc = "Turbochargers and intercoolers.",
		Tiers = tiers({ 0, 2000, 5000, 11000, 22000 }, {
			{},
			{ Mul = { Power = 1.08, TopSpeedMph = 1.02 } },
			{ Mul = { Power = 1.16, TopSpeedMph = 1.04 } },
			{ Mul = { Power = 1.26, TopSpeedMph = 1.06 } },
			{ Mul = { Power = 1.38, TopSpeedMph = 1.08 } },
		}),
	},
	Transmission = {
		Name = "Transmission",
		Desc = "Faster shifts and taller top gear.",
		Tiers = tiers(STD_PRICES, {
			{},
			{ Set = { ShiftTime = 0.28 }, Mul = { TopSpeedMph = 1.02, Power = 1.02 } },
			{ Set = { ShiftTime = 0.20 }, Mul = { TopSpeedMph = 1.04, Power = 1.04 } },
			{ Set = { ShiftTime = 0.13 }, Mul = { TopSpeedMph = 1.06, Power = 1.06 } },
			{ Set = { ShiftTime = 0.07 }, Mul = { TopSpeedMph = 1.08, Power = 1.08 } },
		}),
	},
	Suspension = {
		Name = "Suspension",
		Desc = "Coilovers, sway bars, bushings. Stiffer, lower, more cornering grip.",
		Tiers = tiers(STD_PRICES, {
			{},
			{ Mul = { SpringFreq = 1.08, Grip = 1.03 }, Add = { Damping = 0.05, RideHeight = -0.1 } },
			{ Mul = { SpringFreq = 1.16, Grip = 1.06 }, Add = { Damping = 0.10, RideHeight = -0.2 } },
			{ Mul = { SpringFreq = 1.25, Grip = 1.09 }, Add = { Damping = 0.15, RideHeight = -0.3 } },
			{ Mul = { SpringFreq = 1.35, Grip = 1.12 }, Add = { Damping = 0.20, RideHeight = -0.4 } },
		}),
	},
	Brakes = {
		Name = "Brakes",
		Desc = "Bigger rotors and multi-piston calipers.",
		Tiers = tiers({ 0, 1000, 3000, 7000, 14000 }, {
			{},
			{ Mul = { Brake = 1.15 } },
			{ Mul = { Brake = 1.30 } },
			{ Mul = { Brake = 1.45 } },
			{ Mul = { Brake = 1.60 } },
		}),
	},
	Tires = {
		Name = "Tires",
		Desc = "Stickier compounds for launches, braking and corners.",
		Tiers = tiers({ 0, 1200, 3500, 8000, 16000 }, {
			{},
			{ Mul = { Grip = 1.06 } },
			{ Mul = { Grip = 1.12 } },
			{ Mul = { Grip = 1.20 } },
			{ Mul = { Grip = 1.30 } },
		}),
	},
	Weight = {
		Name = "Weight Reduction",
		Desc = "Carbon panels, stripped interior.",
		Tiers = tiers({ 0, 1500, 4500, 10000, 20000 }, {
			{},
			{ Mul = { WeightFactor = 1.04, Brake = 1.02 } },
			{ Mul = { WeightFactor = 1.08, Brake = 1.04 } },
			{ Mul = { WeightFactor = 1.13, Brake = 1.06 } },
			{ Mul = { WeightFactor = 1.18, Brake = 1.08 } },
		}),
	},
	Nitrous = {
		Name = "Nitrous",
		Desc = "Bottle size (seconds) and shot strength. Hold Shift to spray.",
		Tiers = tiers({ 0, 2500, 6000, 12000, 22000 }, {
			{},
			{ Set = { NitroCapacity = 3, NitroBoost = 1.30 } },
			{ Set = { NitroCapacity = 5, NitroBoost = 1.40 } },
			{ Set = { NitroCapacity = 7, NitroBoost = 1.50 } },
			{ Set = { NitroCapacity = 10, NitroBoost = 1.65 } },
		}),
	},
	FuelTank = {
		Name = "Fuel Tank",
		Desc = "Bigger fuel cell, fewer stops at the pump.",
		Tiers = tiers({ 0, 800, 2000, 4500, 9000 }, {
			{},
			{ Mul = { FuelCapacity = 1.25 } },
			{ Mul = { FuelCapacity = 1.5 } },
			{ Mul = { FuelCapacity = 1.8 } },
			{ Mul = { FuelCapacity = 2.2 } },
		}),
	},
}

Config.UpgradeOrder =
	{ "Engine", "Turbo", "Transmission", "Suspension", "Brakes", "Tires", "Weight", "Nitrous", "FuelTank" }

----------------------------------------------------------------------
-- Free tuning sliders (garage only)
----------------------------------------------------------------------
Config.Tuning = {
	RideHeight = { Min = -0.6, Max = 1.5, Step = 0.1, Default = 0, Label = "Ride Height" },
	Stiffness = { Min = 0.75, Max = 1.35, Step = 0.05, Default = 1, Label = "Spring Stiffness" },
	Gearing = { Min = -1, Max = 1, Step = 0.1, Default = 0, Label = "Gearing (Top Speed <-> Accel)" },
	Camber = { Min = 0, Max = 12, Step = 1, Default = 0, Label = "Camber (visual)" },
}
Config.TuningOrder = { "RideHeight", "Stiffness", "Gearing", "Camber" }

----------------------------------------------------------------------
-- Visual customisation
----------------------------------------------------------------------
Config.Paints = {
	{ Name = "Arctic White", Color = Color3.fromRGB(235, 235, 235) },
	{ Name = "Jet Black", Color = Color3.fromRGB(20, 20, 22) },
	{ Name = "Race Red", Color = Color3.fromRGB(196, 22, 28) },
	{ Name = "Rally Blue", Color = Color3.fromRGB(20, 70, 190) },
	{ Name = "Midnight Purple", Color = Color3.fromRGB(70, 20, 110) },
	{ Name = "Lime Rush", Color = Color3.fromRGB(140, 220, 30) },
	{ Name = "Sunset Orange", Color = Color3.fromRGB(240, 110, 20) },
	{ Name = "Canary Yellow", Color = Color3.fromRGB(245, 205, 30) },
	{ Name = "Forest Green", Color = Color3.fromRGB(30, 90, 50) },
	{ Name = "Gunmetal", Color = Color3.fromRGB(70, 74, 80) },
	{ Name = "Silver", Color = Color3.fromRGB(170, 175, 180) },
	{ Name = "Hot Pink", Color = Color3.fromRGB(240, 60, 160) },
	{ Name = "Teal", Color = Color3.fromRGB(10, 150, 150) },
	{ Name = "Bronze", Color = Color3.fromRGB(150, 100, 50) },
}

Config.Finishes = {
	{ Name = "Gloss", Material = Enum.Material.SmoothPlastic, Reflectance = 0.12 },
	{ Name = "Matte", Material = Enum.Material.SmoothPlastic, Reflectance = 0 },
	{ Name = "Metallic", Material = Enum.Material.Metal, Reflectance = 0.1 },
	{ Name = "Chrome", Material = Enum.Material.Foil, Reflectance = 0.45 },
	{ Name = "Carbon", Material = Enum.Material.Fabric, Reflectance = 0 },
}

Config.RimColors = {
	{ Name = "Silver", Color = Color3.fromRGB(190, 190, 195) },
	{ Name = "Black", Color = Color3.fromRGB(25, 25, 25) },
	{ Name = "Gold", Color = Color3.fromRGB(212, 175, 55) },
	{ Name = "Bronze", Color = Color3.fromRGB(150, 100, 50) },
	{ Name = "Red", Color = Color3.fromRGB(200, 20, 20) },
	{ Name = "White", Color = Color3.fromRGB(240, 240, 240) },
	{ Name = "Neon Green", Color = Color3.fromRGB(60, 255, 60) },
}

Config.Underglows = {
	{ Name = "Off" },
	{ Name = "Blue", Color = Color3.fromRGB(0, 120, 255) },
	{ Name = "Purple", Color = Color3.fromRGB(170, 0, 255) },
	{ Name = "Green", Color = Color3.fromRGB(0, 255, 90) },
	{ Name = "Red", Color = Color3.fromRGB(255, 20, 20) },
	{ Name = "Pink", Color = Color3.fromRGB(255, 60, 200) },
	{ Name = "White", Color = Color3.fromRGB(255, 255, 255) },
}

Config.Spoilers = { "None", "Ducktail", "Wing", "GT Wing" }

Config.Tints = {
	{ Name = "None", Transparency = 0.55 },
	{ Name = "Light", Transparency = 0.35 },
	{ Name = "Dark", Transparency = 0.15 },
	{ Name = "Limo", Transparency = 0.02 },
}

-- Cosmetic key -> { price, list of allowed option names }
Config.CosmeticPrices = {
	Paint = 300,
	Finish = 500,
	Rims = 400,
	Underglow = 800,
	Spoiler = 1200,
	Tint = 250,
}

----------------------------------------------------------------------
-- Police
----------------------------------------------------------------------
Config.Police = {
	SpeedingTolerance = 7, -- mph over the limit before it counts
	WitnessRange = 260, -- a patrol car must be this close to see you
	CameraRange = 110,
	PullOverTime = 12, -- seconds to stop before it becomes a pursuit
	StopToTicketTime = 3,
	BustTime = 4,
	BustRange = 35,
	EscapeRange = 480,
	EscapeTime = 12,
	HeatGainInterval = 45, -- evading for this long raises heat by 1
	MaxHeat = 5,
	TicketBase = 250,
	TicketPerMph = 10,
	BustFinePerHeat = 600,
	EscapeRewardPerHeat = 300,
	-- How many pursuit units chase you at each heat level
	UnitsPerHeat = { 1, 2, 3, 4, 5 },
	Units = {
		Cruiser = {
			Name = "Cruiser",
			Geometry = "Rally",
			Drivetrain = "RWD",
			Power = 50,
			TopSpeed = 150,
			Grip = 1.15,
			Brake = 130,
		},
		Interceptor = {
			Name = "Interceptor",
			Geometry = "Coupe",
			Drivetrain = "AWD",
			Power = 64,
			TopSpeed = 190,
			Grip = 1.3,
			Brake = 150,
		},
		SUV = {
			Name = "Pursuit SUV",
			Geometry = "Pickup",
			Drivetrain = "AWD",
			Power = 52,
			TopSpeed = 150,
			Grip = 1.15,
			Brake = 130,
		},
	},
	-- Unit mix by heat level
	UnitMix = {
		{ "Cruiser" },
		{ "Cruiser" },
		{ "Cruiser", "Interceptor" },
		{ "Cruiser", "Interceptor", "SUV" },
		{ "Interceptor", "SUV" },
	},
	RoadblockHeat = 4,
	SpikeHeat = 4,
	HelicopterHeat = 5,
}

----------------------------------------------------------------------
-- Racing
----------------------------------------------------------------------
Config.Racing = {
	StageHoldTime = 1.0,
	OpponentWait = 4.0,
	AmberInterval = 0.5,
	Payout = {
		Quarter = { Base = 400, WinBonus = 600 },
		Half = { Base = 700, WinBonus = 900 },
	},
	RecordBonus = 500,
}

-- Race events: one opens every Interval seconds; players join from the menu
Config.Events = {
	Interval = 180, -- seconds between events
	FirstDelay = 45, -- first event after server start
	LobbyTime = 40, -- how long the join window stays open
	CountdownTime = 5,
	MaxRacers = 12,
	Payouts = { 2500, 1500, 900 }, -- 1st, 2nd, 3rd
	FinishPay = 300, -- everyone who finishes
	-- descriptions shown in the menu; routes are built by MapBuilder
	Order = { "DowntownCircuit", "CrossTownSprint", "RingRun", "InterstateRun" },
	Info = {
		DowntownCircuit = { Name = "Downtown Circuit", Desc = "2 laps around the downtown towers. Tight 90° corners." },
		CrossTownSprint = { Name = "Cross-Town Sprint", Desc = "Point-to-point dash from the west suburbs to the east side." },
		RingRun = { Name = "Ring Highway Run", Desc = "One full lap of the elevated ring highway, dodging traffic." },
		InterstateRun = { Name = "Interstate Top Speed", Desc = "Flat-out sprint down the interstate. Pure top speed." },
	},
}

Config.Meet = {
	PayoutInterval = 30,
	PayPerCar = 40,
}

Config.Traffic = {
	-- traffic is spawned around each player and recycled when far away
	CityCarsNearPlayer = 18, -- within CityRange of a player
	CityRange = 700,
	HighwayCarsPerLaneNearPlayer = 4, -- per highway lane near a player
	HighwayRange = 1000,
	MaxCars = 90,
	DespawnRange = 1400,
	SpawnPerTick = 4,
	UpdateHz = 30,
	PatrolChance = 0.12,
	MaxPatrols = 6,
}

-- Fill these with your own uploaded audio asset ids (rbxassetid://...)
Config.Sounds = {
	Engine = "",
	Siren = "",
	Horn = "",
}

Config.DayLengthMinutes = 24

return Config
