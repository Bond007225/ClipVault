--!strict
-- Drives the local player's car. When you sit in your own driver seat, the
-- server hands you network ownership and this controller runs CarPhysics
-- every frame using the VehicleSeat's throttle/steer (keyboard, gamepad and
-- mobile thumbstick all feed those), plus extra driving actions.

local ContextActionService = game:GetService("ContextActionService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CarPhysics = require(Shared.CarPhysics)
local Remotes = require(Shared.Remotes)

local HUD = require(script.Parent.HUD)

local DriveController = {}

local player = Players.LocalPlayer
local active: { disconnect: () -> () }? = nil

local input = { throttle = 0, steer = 0, handbrake = false, nitro = false }

local function keyAxis(pos: { Enum.KeyCode }, neg: { Enum.KeyCode }): number
	local v = 0
	for _, k in pos do
		if UserInputService:IsKeyDown(k) then
			v += 1
			break
		end
	end
	for _, k in neg do
		if UserInputService:IsKeyDown(k) then
			v -= 1
			break
		end
	end
	return v
end

local function stopDriving()
	if active then
		active.disconnect()
		active = nil
	end
end

local function startDriving(car: Model, seat: VehicleSeat)
	stopDriving()
	local statsJson = car:GetAttribute("Stats") :: string?
	if not statsJson then
		return
	end
	local physics = CarPhysics.new(car, HttpService:JSONDecode(statsJson), true)
	local connections: { RBXScriptConnection } = {}
	local actions = { "MM_Handbrake", "MM_Nitro", "MM_Exit", "MM_ShiftUp", "MM_ShiftDown", "MM_Manual", "MM_Reset" }

	local function syncAttrs()
		physics.fuelEmpty = ((car:GetAttribute("Fuel") :: number?) or 1) <= 0
		physics.tiresPopped = car:GetAttribute("TiresPopped") == true
	end
	syncAttrs()
	table.insert(connections, car.AttributeChanged:Connect(function(name)
		if name == "Stats" then
			local json = car:GetAttribute("Stats") :: string?
			if json then
				physics:setStats(HttpService:JSONDecode(json))
			end
		elseif name == "Fuel" or name == "TiresPopped" then
			local wasEmpty = physics.fuelEmpty
			syncAttrs()
			if physics.fuelEmpty and not wasEmpty then
				HUD.notify("Out of fuel! Push to a gas station... or call your car from the garage.", "warn")
			end
		end
	end))

	local function handle(name: string, state: Enum.UserInputState): Enum.ContextActionResult
		local down = state == Enum.UserInputState.Begin
		if name == "MM_Handbrake" then
			input.handbrake = state ~= Enum.UserInputState.End and state ~= Enum.UserInputState.Cancel
		elseif name == "MM_Nitro" then
			input.nitro = state ~= Enum.UserInputState.End and state ~= Enum.UserInputState.Cancel
		elseif down and name == "MM_Exit" then
			Remotes.event("ExitCar"):FireServer()
		elseif down and name == "MM_ShiftUp" and physics.manual then
			physics:shift(1)
		elseif down and name == "MM_ShiftDown" and physics.manual then
			physics:shift(-1)
		elseif down and name == "MM_Manual" then
			physics.manual = not physics.manual
			HUD.notify(if physics.manual then "Manual gearbox (E/Q to shift)" else "Automatic gearbox", "info")
		elseif down and name == "MM_Reset" then
			if physics.chassis.AssemblyLinearVelocity.Magnitude < 15 then
				physics:reset()
			end
		end
		return Enum.ContextActionResult.Sink
	end

	local prio = Enum.ContextActionPriority.High.Value + 10
	-- Space is sunk here so it acts as handbrake instead of jumping out of the seat
	ContextActionService:BindActionAtPriority("MM_Handbrake", handle, true, prio, Enum.KeyCode.Space, Enum.KeyCode.ButtonA)
	ContextActionService:BindActionAtPriority("MM_Nitro", handle, true, prio, Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonX)
	ContextActionService:BindActionAtPriority("MM_Exit", handle, true, prio, Enum.KeyCode.F, Enum.KeyCode.ButtonY)
	ContextActionService:BindActionAtPriority("MM_ShiftUp", handle, false, prio, Enum.KeyCode.E, Enum.KeyCode.ButtonR1)
	ContextActionService:BindActionAtPriority("MM_ShiftDown", handle, false, prio, Enum.KeyCode.Q, Enum.KeyCode.ButtonL1)
	ContextActionService:BindActionAtPriority("MM_Manual", handle, false, prio, Enum.KeyCode.M)
	ContextActionService:BindActionAtPriority("MM_Reset", handle, false, prio, Enum.KeyCode.R)
	for name, title in { MM_Handbrake = "Brake", MM_Nitro = "NOS", MM_Exit = "Exit" } do
		local btn = ContextActionService:GetButton(name)
		if btn then
			ContextActionService:SetTitle(name, title)
		end
	end
	if ContextActionService:GetButton("MM_Nitro") then
		ContextActionService:SetPosition("MM_Nitro", UDim2.new(1, -200, 1, -150))
		ContextActionService:SetPosition("MM_Handbrake", UDim2.new(1, -130, 1, -210))
		ContextActionService:SetPosition("MM_Exit", UDim2.new(1, -80, 0, 60))
	end

	table.insert(connections, RunService.Stepped:Connect(function(_, dt)
		if not car.Parent then
			stopDriving()
			return
		end
		local kThrottle = keyAxis({ Enum.KeyCode.W, Enum.KeyCode.Up }, { Enum.KeyCode.S, Enum.KeyCode.Down })
		local kSteer = keyAxis({ Enum.KeyCode.D, Enum.KeyCode.Right }, { Enum.KeyCode.A, Enum.KeyCode.Left })
		input.throttle = if kThrottle ~= 0 then kThrottle else seat.ThrottleFloat
		input.steer = if kSteer ~= 0 then kSteer else seat.SteerFloat
		local telemetry = physics:step(dt, input)
		HUD.setTelemetry(telemetry, physics.manual, (car:GetAttribute("Fuel") :: number? or 0) / (car:GetAttribute("FuelCapacity") :: number? or 1), physics.tiresPopped)
	end))

	active = {
		disconnect = function()
			for _, c in connections do
				c:Disconnect()
			end
			for _, a in actions do
				ContextActionService:UnbindAction(a)
			end
			input.handbrake = false
			input.nitro = false
			HUD.setTelemetry(nil, false, 0, false)
		end,
	}
end

local function onCharacter(char: Model)
	stopDriving()
	local hum = char:WaitForChild("Humanoid") :: Humanoid
	hum.Seated:Connect(function(isSeated: boolean, seatPart: BasePart?)
		if isSeated and seatPart and seatPart:IsA("VehicleSeat") and seatPart.Name == "DriverSeat" then
			local car = seatPart.Parent
			if car and car:IsA("Model") and car:GetAttribute("Owner") == player.UserId then
				startDriving(car, seatPart)
			end
		else
			stopDriving()
		end
	end)
	hum.Died:Connect(stopDriving)
end

function DriveController.init() end

function DriveController.start()
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
	player.CharacterAdded:Connect(onCharacter)
end

return DriveController
