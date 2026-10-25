--!strict
-- Pure stat computation: base car + upgrades + tuning -> physics stats.
-- The server's result is authoritative (it is written onto the car model);
-- the client runs the same code to preview numbers in the garage.

local Config = require(script.Parent.Config)

local CarStats = {}

export type CarData = {
	Upgrades: { [string]: number },
	Cosmetics: { [string]: string },
	Tuning: { [string]: number },
}

export type Stats = {
	Power: number,
	TopSpeedMph: number,
	TopSpeed: number,
	Redline: number,
	IdleRpm: number,
	Gears: { number },
	ShiftTime: number,
	Grip: number,
	Brake: number,
	SpringFreq: number,
	Damping: number,
	RideHeight: number,
	WheelRadius: number,
	Drivetrain: string,
	NitroCapacity: number,
	NitroBoost: number,
	FuelCapacity: number,
	Economy: number,
	WeightFactor: number,
	SteerAngle: number,
	Downforce: number,
	DragK: number,
	ReverseSpeed: number,
	Camber: number,
	Rating: number,
	Class: string,
}

-- Normalised torque curve, peak 1.0 at ~67% of redline
function CarStats.torqueCurve(t: number): number
	t = math.clamp(t, 0, 1.05)
	return (0.6 + 0.8 * t - 0.6 * t * t) / 0.8667
end

function CarStats.defaultData(carId: string): CarData
	local def = Config.Cars[carId]
	local upgrades = {}
	for _, cat in Config.UpgradeOrder do
		upgrades[cat] = 1
	end
	local tuning = {}
	for key, t in Config.Tuning do
		tuning[key] = t.Default
	end
	return {
		Upgrades = upgrades,
		Cosmetics = {
			Paint = def and def.DefaultPaint or "Arctic White",
			Finish = "Gloss",
			Rims = "Silver",
			Underglow = "Off",
			Spoiler = "None",
			Tint = "Light",
		},
		Tuning = tuning,
	}
end

local function classFor(rating: number): string
	if rating >= 900 then
		return "S"
	elseif rating >= 750 then
		return "A"
	elseif rating >= 600 then
		return "B"
	elseif rating >= 450 then
		return "C"
	end
	return "D"
end

function CarStats.finalize(s: any): Stats
	s.TopSpeed = s.TopSpeedMph / Config.STUDS_TO_MPH
	local gears = s.Gears
	-- Drag tuned so drive force at redline in top gear balances drag at TopSpeed
	local topAccel = s.Power * s.WeightFactor * CarStats.torqueCurve(1) * (gears[#gears] / gears[1])
	s.DragK = topAccel / (s.TopSpeed * s.TopSpeed)
	local rating = s.Power * s.WeightFactor * 6
		+ s.TopSpeedMph * 1.6
		+ s.Grip * 140
		+ s.Brake * 0.6
		+ (0.4 - s.ShiftTime) * 200
		+ s.NitroCapacity * s.NitroBoost * 8
	s.Rating = math.floor(rating)
	s.Class = classFor(s.Rating)
	return s :: Stats
end

function CarStats.compute(carId: string, data: CarData?): Stats
	local base = Config.Cars[carId]
	assert(base, "unknown car " .. tostring(carId))
	local upgrades = data and data.Upgrades or {}
	local tuning = data and data.Tuning or {}

	local s: { [string]: any } = {
		Power = base.Power,
		TopSpeedMph = base.TopSpeed,
		Redline = base.Redline,
		IdleRpm = 900,
		Gears = table.clone(base.Gears),
		ShiftTime = 0.35,
		Grip = base.Grip,
		Brake = base.Brake,
		SpringFreq = base.SpringFreq,
		Damping = base.Damping,
		RideHeight = base.RideHeight,
		WheelRadius = base.WheelRadius,
		Drivetrain = base.Drivetrain,
		NitroCapacity = 0,
		NitroBoost = 1,
		FuelCapacity = base.FuelCapacity,
		Economy = 1,
		WeightFactor = 1,
		SteerAngle = 34,
		Downforce = 0.0003,
		ReverseSpeed = 40,
		Camber = 0,
	}

	for cat, def in Config.Upgrades do
		local tier = math.clamp(math.floor(tonumber(upgrades[cat]) or 1), 1, #def.Tiers)
		local t = def.Tiers[tier]
		if t.Mul then
			for k, v in t.Mul do
				s[k] *= v
			end
		end
		if t.Add then
			for k, v in t.Add do
				s[k] += v
			end
		end
		if t.Set then
			for k, v in t.Set do
				s[k] = v
			end
		end
	end

	local function tune(key: string): number
		local spec = Config.Tuning[key]
		return math.clamp(tonumber(tuning[key]) or spec.Default, spec.Min, spec.Max)
	end
	s.RideHeight = math.max(0.25, s.RideHeight + tune("RideHeight"))
	s.SpringFreq *= tune("Stiffness")
	local gearing = tune("Gearing")
	s.Power *= 1 + 0.1 * gearing
	s.TopSpeedMph *= 1 - 0.06 * gearing
	s.Camber = tune("Camber")

	return CarStats.finalize(s)
end

-- Build stats directly from a police unit spec (no upgrades)
function CarStats.fromUnit(unit: { [string]: any }, heatScale: number): Stats
	local geo = Config.Cars[unit.Geometry]
	local s: { [string]: any } = {
		Power = unit.Power * heatScale,
		TopSpeedMph = unit.TopSpeed * math.sqrt(heatScale),
		Redline = 7000,
		IdleRpm = 900,
		Gears = { 3.4, 2.2, 1.6, 1.2, 0.95, 0.78 },
		ShiftTime = 0.15,
		Grip = unit.Grip,
		Brake = unit.Brake,
		SpringFreq = 2.0,
		Damping = 0.55,
		RideHeight = geo.RideHeight,
		WheelRadius = geo.WheelRadius,
		Drivetrain = unit.Drivetrain,
		NitroCapacity = 0,
		NitroBoost = 1,
		FuelCapacity = 20,
		Economy = 1,
		WeightFactor = 1,
		SteerAngle = 36,
		Downforce = 0.0004,
		ReverseSpeed = 40,
		Camber = 0,
	}
	return CarStats.finalize(s)
end

return CarStats
