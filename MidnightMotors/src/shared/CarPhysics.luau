--!strict
-- Raycast-suspension vehicle simulation.
-- Runs on whichever machine owns the car's physics: the driver's client for
-- player cars, the server for police units. Forces are applied as impulses to
-- the chassis each step; wheels are purely visual (massless, no collision).

local Players = game:GetService("Players")

local CarStats = require(script.Parent.CarStats)

local CarPhysics = {}
CarPhysics.__index = CarPhysics

export type Input = {
	throttle: number, -- -1..1 (negative = brake / reverse)
	steer: number, -- -1..1 (positive = right)
	handbrake: boolean,
	nitro: boolean,
}

export type Telemetry = {
	speed: number, -- signed forward speed, studs/s
	mph: number,
	rpm: number,
	redline: number,
	gear: string,
	nitro: number, -- 0..1
	grounded: boolean,
	drifting: boolean,
}

type Wheel = {
	name: string,
	attachment: Attachment,
	weld: Weld?,
	front: boolean,
	left: boolean,
	lastLength: number?,
	length: number,
	spin: number,
}

local WHEEL_NAMES = { "FL", "FR", "RL", "RR" }
local TAU = math.pi * 2

function CarPhysics.new(model: Model, stats: CarStats.Stats, animateWheels: boolean)
	local chassis = model:FindFirstChild("Chassis") :: BasePart
	assert(chassis, "car has no Chassis")
	local self = setmetatable({}, CarPhysics)
	self.model = model
	self.chassis = chassis
	self.animateWheels = animateWheels
	self.wheels = {} :: { Wheel }
	for _, name in WHEEL_NAMES do
		local att = chassis:FindFirstChild("Wheel" .. name) :: Attachment
		table.insert(self.wheels, {
			name = name,
			attachment = att,
			weld = chassis:FindFirstChild("Weld_" .. name) :: Weld?,
			front = string.sub(name, 1, 1) == "F",
			left = string.sub(name, 2, 2) == "L",
			lastLength = nil,
			length = 0,
			spin = 0,
		})
	end
	self.params = RaycastParams.new()
	self.params.FilterType = Enum.RaycastFilterType.Exclude
	self.params.IgnoreWater = true
	self.ignoreTimer = 0
	self.gear = 1
	self.reverse = false
	self.rpm = 900
	self.shiftTimer = 0
	self.steerAngle = 0
	self.manual = false
	self.flipTimer = 0
	self.grounded = 0
	self.drifting = false
	self.fuelEmpty = false
	self.tiresPopped = false
	self:setStats(stats)
	self.nitro = stats.NitroCapacity
	self:refreshIgnore()
	return self
end

function CarPhysics.setStats(self: any, stats: CarStats.Stats)
	self.stats = stats
	self.gear = math.clamp(self.gear, 1, #stats.Gears)
	if self.nitro then
		self.nitro = math.min(self.nitro, stats.NitroCapacity)
	end
end

function CarPhysics.refreshIgnore(self: any)
	local list: { Instance } = { self.model }
	for _, plr in Players:GetPlayers() do
		if plr.Character then
			table.insert(list, plr.Character)
		end
	end
	self.params.FilterDescendantsInstances = list
end

function CarPhysics.shift(self: any, dir: number)
	local stats = self.stats
	local newGear = math.clamp(self.gear + dir, 1, #stats.Gears)
	if newGear ~= self.gear then
		self.gear = newGear
		self.shiftTimer = stats.ShiftTime
	end
end

function CarPhysics.step(self: any, dt: number, input: Input): Telemetry
	dt = math.min(dt, 1 / 20)
	local stats: CarStats.Stats = self.stats
	local chassis: BasePart = self.chassis
	if chassis.Anchored then
		return self:_telemetry(0)
	end

	self.ignoreTimer -= dt
	if self.ignoreTimer <= 0 then
		self.ignoreTimer = 1
		self:refreshIgnore()
	end

	local cf = chassis.CFrame
	local up = cf.UpVector
	local look = cf.LookVector
	local mass = chassis.AssemblyMass
	local vel = chassis.AssemblyLinearVelocity
	local fwdSpeed = vel:Dot(look)
	local speed = vel.Magnitude
	local g = workspace.Gravity
	local com = chassis.AssemblyCenterOfMass

	local throttleIn = math.clamp(input.throttle, -1, 1)
	if self.fuelEmpty and throttleIn > 0 then
		throttleIn = 0
	end

	-- Steering: less lock at speed
	local speedRatio = math.clamp(math.abs(fwdSpeed) / stats.TopSpeed, 0, 1)
	local steerLimit = math.rad(stats.SteerAngle) * (1 - speedRatio * 0.72)
	local targetSteer = -math.clamp(input.steer, -1, 1) * steerLimit
	self.steerAngle += (targetSteer - self.steerAngle) * math.min(1, dt * 10)

	-- Pedals: forward/reverse/brake resolution
	local drive = 0
	local braking = 0
	if throttleIn > 0.05 then
		if fwdSpeed < -3 then
			braking = throttleIn
		else
			self.reverse = false
			drive = throttleIn
		end
	elseif throttleIn < -0.05 then
		if fwdSpeed > 3 and not self.reverse then
			braking = -throttleIn
		else
			self.reverse = true
			drive = throttleIn
		end
	end

	-- Engine & gearbox
	local gears = stats.Gears
	local rpmPerSps = stats.Redline / (stats.TopSpeed * gears[#gears])
	local ratio = gears[self.gear]
	local wheelRpm = math.abs(fwdSpeed) * rpmPerSps * (self.reverse and gears[1] or ratio)
	local targetRpm = math.max(stats.IdleRpm, wheelRpm)
	if self.grounded == 0 or self.shiftTimer > 0 then
		targetRpm = stats.IdleRpm + math.abs(throttleIn) * (stats.Redline - stats.IdleRpm) * 0.9
	elseif drive > 0 and self.gear == 1 then
		-- clutch slip on launch
		targetRpm = math.max(targetRpm, stats.IdleRpm + (stats.Redline * 0.55 - stats.IdleRpm) * drive)
	end
	self.rpm += (targetRpm - self.rpm) * math.min(1, dt * 12)

	if self.shiftTimer > 0 then
		self.shiftTimer -= dt
	elseif not self.manual and not self.reverse and self.grounded > 0 then
		if self.rpm >= stats.Redline * 0.95 and self.gear < #gears and drive > 0 then
			self:shift(1)
		elseif self.gear > 1 then
			local lowerRpm = wheelRpm * gears[self.gear - 1] / ratio
			if lowerRpm < stats.Redline * 0.78 and self.rpm < stats.Redline * 0.5 then
				self:shift(-1)
			end
		end
	end

	local accel = 0
	if self.shiftTimer <= 0 then
		if drive > 0 then
			if wheelRpm < stats.Redline then
				accel = stats.Power * CarStats.torqueCurve(self.rpm / stats.Redline) * (ratio / gears[1]) * drive
			end
		elseif drive < 0 then
			if fwdSpeed > -stats.ReverseSpeed then
				accel = stats.Power * 0.45 * drive
			end
		end
	end

	-- Nitrous
	local usingNitro = false
	if input.nitro and drive > 0 and self.nitro > 0 and stats.NitroCapacity > 0 then
		usingNitro = true
		self.nitro = math.max(0, self.nitro - dt)
		accel = accel * stats.NitroBoost + stats.Power * 0.12
	elseif stats.NitroCapacity > 0 then
		self.nitro = math.min(stats.NitroCapacity, self.nitro + dt * stats.NitroCapacity / 45)
	end
	self.usingNitro = usingNitro

	accel *= stats.WeightFactor
	if self.tiresPopped then
		accel *= 0.6
	end

	-- Suspension
	local quarterMass = mass / 4
	local omega = TAU * stats.SpringFreq
	local k = quarterMass * omega * omega
	local c = 2 * stats.Damping * math.sqrt(k * quarterMass)
	local restLen = g / (omega * omega) + stats.RideHeight
	local radius = stats.WheelRadius
	local grip = stats.Grip * (self.tiresPopped and 0.45 or 1)
	local driven = stats.Drivetrain
	local nDriven = driven == "AWD" and 4 or 2
	local grounded = 0
	local drifting = false
	local stopped = math.abs(throttleIn) < 0.05 and speed < 2.5

	for _, w in self.wheels do
		local mount = cf:PointToWorldSpace(w.attachment.Position)
		local result = workspace:Raycast(mount, -up * (restLen + radius), self.params)
		if result then
			grounded += 1
			local length = math.max(0, result.Distance - radius)
			local compression = restLen - length
			local compVel = if w.lastLength then (w.lastLength - length) / dt else 0
			w.lastLength = length
			w.length = length
			local springForce = math.max(0, k * compression + c * compVel)
			if length < 0.15 then
				springForce += k * (0.15 - length) * 4 -- bump stop
			end
			chassis:ApplyImpulseAtPosition(up * springForce * dt, mount)

			-- Tyre forces on the ground plane
			local normal = result.Normal
			local wheelLook = if w.front then (cf * CFrame.Angles(0, self.steerAngle, 0)).LookVector else look
			local fwd = wheelLook - normal * wheelLook:Dot(normal)
			if fwd.Magnitude > 1e-3 then
				fwd = fwd.Unit
				local side = fwd:Cross(normal)
				local pv = chassis:GetVelocityAtPosition(result.Position)
				local vLong = pv:Dot(fwd)
				local vLat = pv:Dot(side)
				local isRear = not w.front
				local maxF = grip * springForce
				if input.handbrake and isRear then
					maxF *= 0.35
				end

				local latF = math.clamp(-vLat * quarterMass / dt * 0.6, -maxF, maxF)
				local longF = 0
				local isDriven = driven == "AWD" or (driven == "FWD" and w.front) or (driven == "RWD" and isRear)
				if isDriven then
					longF += accel * mass / nDriven
				end
				if braking > 0 then
					local b = stats.Brake * quarterMass * braking * (if w.front then 1.15 else 0.85)
					longF -= math.sign(vLong) * math.min(b, math.abs(vLong) * quarterMass / dt)
				end
				if input.handbrake and isRear then
					longF -= math.sign(vLong) * math.min(stats.Brake * quarterMass * 0.8, math.abs(vLong) * quarterMass / dt)
				end
				if stopped then
					longF -= vLong * quarterMass / dt * 0.5
				else
					longF -= vLong * quarterMass * 0.01 -- rolling resistance
				end

				-- friction circle
				local total = math.sqrt(latF * latF + longF * longF)
				if total > maxF * 1.1 and total > 0 then
					local scale = maxF * 1.1 / total
					latF *= scale
					longF *= scale
				end
				if isRear and math.abs(vLat) > 12 then
					drifting = true
				end

				-- Apply at centre-of-mass height to keep the car from rolling over
				local offset = result.Position - com
				offset -= up * offset:Dot(up)
				chassis:ApplyImpulseAtPosition((fwd * longF + side * latF) * dt, com + offset)
				w.spin -= vLong / radius * dt
			end
		else
			w.lastLength = nil
			w.length = restLen
		end

		if self.animateWheels and w.weld then
			local steer = if w.front then self.steerAngle else 0
			local camber = math.rad(stats.Camber) * (if w.left then 1 else -1)
			w.weld.C0 = CFrame.new(w.attachment.Position - Vector3.new(0, w.length, 0))
				* CFrame.Angles(0, steer, 0)
				* CFrame.Angles(0, 0, camber)
				* CFrame.Angles(w.spin, 0, 0)
		end
	end
	self.grounded = grounded
	self.drifting = drifting

	-- Aero: drag and downforce
	if speed > 0.5 then
		chassis:ApplyImpulse(-vel * speed * stats.DragK * mass * dt)
		if grounded > 0 then
			chassis:ApplyImpulse(-up * mass * speed * speed * stats.Downforce * dt)
		end
	end

	-- Air: damp pitch/roll so jumps land wheels-down
	if grounded == 0 then
		local av = chassis.AssemblyAngularVelocity
		local yaw = up * av:Dot(up)
		chassis:ApplyAngularImpulse(-(av - yaw) * mass * 12 * dt)
	end

	-- Flip recovery
	if up.Y < 0.3 and speed < 12 then
		self.flipTimer += dt
		if self.flipTimer > 2.5 then
			self.flipTimer = 0
			self:reset()
		end
	else
		self.flipTimer = 0
	end

	return self:_telemetry(fwdSpeed)
end

function CarPhysics.reset(self: any)
	local chassis: BasePart = self.chassis
	local look = chassis.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.1 then
		flat = Vector3.new(0, 0, -1)
	end
	local pos = chassis.Position + Vector3.new(0, 5, 0)
	chassis.AssemblyLinearVelocity = Vector3.zero
	chassis.AssemblyAngularVelocity = Vector3.zero
	chassis.CFrame = CFrame.lookAt(pos, pos + flat.Unit)
end

function CarPhysics._telemetry(self: any, fwdSpeed: number): Telemetry
	local stats = self.stats
	local gear = if self.reverse then "R" elseif math.abs(fwdSpeed) < 0.5 and self.rpm < 1000 then "N" else tostring(self.gear)
	return {
		speed = fwdSpeed,
		mph = math.abs(fwdSpeed) * 0.626,
		rpm = self.rpm,
		redline = stats.Redline,
		gear = gear,
		nitro = if stats.NitroCapacity > 0 then self.nitro / stats.NitroCapacity else 0,
		grounded = self.grounded > 0,
		drifting = self.drifting,
	}
end

return CarPhysics
