--!strict
-- Trick naming, scoring and report validation. Pure functions so the server can
-- recompute everything from the raw report and never trust client-sent points.

local Config = require(script.Parent.Config)

local Tricks = {}

export type AirReport = {
	kind: "Air",
	air: number, -- seconds airborne
	spin: number, -- completed spin degrees (multiple of 180)
	spinDir: number, -- 1 frontside, -1 backside
	flips: number, -- completed flips
	flipDir: number, -- 1 front, -1 back
	grab: string?,
	grabTime: number,
}

export type GrindReport = {
	kind: "Grind",
	duration: number,
	style: string,
}

export type Report = AirReport | GrindReport

Tricks.Grabs = { "Indy", "Method", "Nose", "Tail" }
Tricks.GrindStyles = { "50-50", "Boardslide" }

local GRAB_SET: { [string]: boolean } = {}
for _, g in Tricks.Grabs do
	GRAB_SET[g] = true
end
local GRIND_SET: { [string]: boolean } = {}
for _, g in Tricks.GrindStyles do
	GRIND_SET[g] = true
end

local MAX_SPIN_RATE = math.deg(Config.Riding.SpinRate)
local MAX_FLIP_RATE = math.deg(Config.Riding.FlipRate)

-- Rounds a raw rotation (degrees) to the completed amount a judge would call.
function Tricks.countSpin(degrees: number): number
	return math.floor((math.abs(degrees) + 50) / 180) * 180
end

function Tricks.countFlips(degrees: number): number
	return math.floor((math.abs(degrees) + 70) / 360)
end

local FLIP_WORDS = { "", "Double", "Triple", "Quad" }

function Tricks.describe(report: Report): string
	if report.kind == "Grind" then
		return report.style
	end

	local r = report :: AirReport
	local parts = {}
	if r.flips > 0 and r.spin >= 360 then
		local prefix = FLIP_WORDS[math.min(r.flips, 4)]
		table.insert(parts, (prefix ~= "" and prefix .. " " or "") .. "Cork " .. r.spin)
	else
		if r.spin > 0 then
			table.insert(parts, (r.spinDir >= 0 and "Frontside " or "Backside ") .. r.spin)
		end
		if r.flips > 0 then
			local prefix = FLIP_WORDS[math.min(r.flips, 4)]
			local flipWord = r.flipDir >= 0 and "Frontflip" or "Backflip"
			table.insert(parts, (prefix ~= "" and prefix .. " " or "") .. flipWord)
		end
	end
	if r.grab then
		table.insert(parts, if #parts == 0 then r.grab .. " Grab" else r.grab)
	end
	if #parts == 0 then
		return if r.air >= 1.5 then "Big Air" else "Air"
	end
	return table.concat(parts, " ")
end

function Tricks.score(report: Report): number
	local t = Config.Tricks
	if report.kind == "Grind" then
		local g = report :: GrindReport
		local pts = t.GrindBase + g.duration * t.GrindPerSecond
		if g.style == "Boardslide" then
			pts *= t.BoardslideBonus
		end
		return math.floor(pts)
	end

	local r = report :: AirReport
	local pts = r.air * t.AirPerSecond
	pts += (r.spin / 180) * t.SpinPointsPer180
	pts += r.flips * t.FlipPoints
	if r.grab then
		pts += t.GrabBase + math.min(r.grabTime, t.GrabMaxSeconds) * t.GrabPerSecond
	end
	-- Corks (flip + spin together) are harder than the sum of their parts.
	if r.flips > 0 and r.spin >= 360 then
		pts *= 1.25
	end
	return math.floor(pts)
end

function Tricks.multiplier(comboCount: number): number
	local t = Config.Tricks
	return math.min(1 + t.MultiplierStep * (comboCount - 1), t.MaxMultiplier)
end

local function isFiniteNumber(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

-- Validates and normalizes an untrusted report table. Returns nil when the report
-- is malformed or physically implausible.
function Tricks.sanitize(raw: any): Report?
	if type(raw) ~= "table" then
		return nil
	end

	if raw.kind == "Grind" then
		if not isFiniteNumber(raw.duration) or type(raw.style) ~= "string" then
			return nil
		end
		if raw.duration < Config.Tricks.GrindMinSeconds or raw.duration > 20 then
			return nil
		end
		if not GRIND_SET[raw.style] then
			return nil
		end
		return { kind = "Grind", duration = raw.duration, style = raw.style } :: GrindReport
	elseif raw.kind == "Air" then
		for _, key in { "air", "spin", "spinDir", "flips", "flipDir", "grabTime" } do
			if not isFiniteNumber(raw[key]) then
				return nil
			end
		end
		local air: number = raw.air
		if air < Config.Tricks.MinAirTime or air > 15 then
			return nil
		end
		local spin: number = raw.spin
		if spin < 0 or spin > 2160 or spin % 180 ~= 0 then
			return nil
		end
		if spin > air * MAX_SPIN_RATE * 1.15 + 180 then
			return nil
		end
		local flips: number = raw.flips
		if flips < 0 or flips > 4 or flips % 1 ~= 0 then
			return nil
		end
		if flips * 360 > air * MAX_FLIP_RATE * 1.15 + 180 then
			return nil
		end
		local grab: string? = nil
		local grabTime: number = 0
		if raw.grab ~= nil then
			if type(raw.grab) ~= "string" or not GRAB_SET[raw.grab] then
				return nil
			end
			grabTime = math.clamp(raw.grabTime, 0, air + 0.1)
			if grabTime >= Config.Tricks.GrabMinSeconds then
				grab = raw.grab
			else
				grabTime = 0
			end
		end
		return {
			kind = "Air",
			air = air,
			spin = spin,
			spinDir = if raw.spinDir >= 0 then 1 else -1,
			flips = flips,
			flipDir = if raw.flipDir >= 0 then 1 else -1,
			grab = grab,
			grabTime = grabTime,
		} :: AirReport
	end
	return nil
end

-- Length of time the report claims, used to stop overlapping/duplicated reports.
function Tricks.claimedDuration(report: Report): number
	if report.kind == "Grind" then
		return (report :: GrindReport).duration
	end
	return (report :: AirReport).air
end

return Tricks
