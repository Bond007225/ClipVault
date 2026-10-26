--!strict
-- Polyline lanes used by traffic, patrols and police spawning.

local Lanes = {}

export type Lane = {
	Name: string,
	Kind: string, -- "Highway" | "Interstate" | "City"
	Points: { Vector3 },
	Cum: { number },
	Length: number,
	Speed: number, -- studs/s cruising speed
}

local all: { Lane } = {}

function Lanes.add(name: string, kind: string, points: { Vector3 }, speed: number): Lane
	local pts = table.clone(points)
	table.insert(pts, points[1]) -- lanes are closed loops
	local cum = { 0 }
	local total = 0
	for i = 2, #pts do
		total += (pts[i] - pts[i - 1]).Magnitude
		cum[i] = total
	end
	local lane: Lane = { Name = name, Kind = kind, Points = pts, Cum = cum, Length = total, Speed = speed }
	table.insert(all, lane)
	return lane
end

function Lanes.all(): { Lane }
	return all
end

-- Position and direction at distance s along the lane
function Lanes.sample(lane: Lane, s: number): (Vector3, Vector3)
	s = s % lane.Length
	local cum = lane.Cum
	local lo, hi = 1, #cum
	while hi - lo > 1 do
		local mid = (lo + hi) // 2
		if cum[mid] <= s then
			lo = mid
		else
			hi = mid
		end
	end
	local a, b = lane.Points[lo], lane.Points[lo + 1]
	local segLen = cum[lo + 1] - cum[lo]
	local t = if segLen > 0 then (s - cum[lo]) / segLen else 0
	return a:Lerp(b, t), (b - a).Unit
end

-- Closest point on a lane: returns s and planar distance
function Lanes.closest(lane: Lane, pos: Vector3): (number, number)
	local flat = Vector3.new(pos.X, 0, pos.Z)
	local bestS, bestD = 0, math.huge
	for i = 1, #lane.Points - 1 do
		local pa, pb = lane.Points[i], lane.Points[i + 1]
		local a = Vector3.new(pa.X, 0, pa.Z)
		local b = Vector3.new(pb.X, 0, pb.Z)
		local ab = b - a
		local len = ab.Magnitude
		if len > 0 then
			local t = math.clamp((flat - a):Dot(ab) / (len * len), 0, 1)
			local p = a + ab * t
			local d = (flat - p).Magnitude
			if d < bestD then
				bestD = d
				bestS = lane.Cum[i] + len * t
			end
		end
	end
	return bestS, bestD
end

-- Find a lane point between minDist and maxDist from pos, preferring points
-- behind `facing` (so police arrive from behind the player).
function Lanes.findSpawn(pos: Vector3, minDist: number, maxDist: number, facing: Vector3?): (CFrame?, Lane?)
	local best: CFrame? = nil
	local bestLane: Lane? = nil
	local bestScore = -math.huge
	for _, lane in all do
		local s0, d0 = Lanes.closest(lane, pos)
		if d0 < maxDist then
			for _, offset in { -maxDist * 0.6, -minDist * 1.2, minDist * 1.2, maxDist * 0.6 } do
				local p, dir = Lanes.sample(lane, s0 + offset)
				local dist = (Vector3.new(p.X, 0, p.Z) - Vector3.new(pos.X, 0, pos.Z)).Magnitude
				if dist >= minDist and dist <= maxDist then
					-- prefer the same level (elevated highway vs streets)
					local score = -dist * 0.01 + math.random() - math.abs(p.Y - pos.Y) * 0.3
					if facing and facing.Magnitude > 0 then
						score -= (p - pos).Unit:Dot(facing.Unit) * 2
					end
					if score > bestScore then
						bestScore = score
						best = CFrame.lookAt(p, p + dir)
						bestLane = lane
					end
				end
			end
		end
	end
	return best, bestLane
end

return Lanes
