--!strict
-- Car meets: park your car in a meet lot to show it off. Every payout interval
-- each parked owner earns cash scaled by how many cars are at the meet.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)
local PlayerData = require(script.Parent.PlayerData)
local MapBuilder = require(script.Parent.MapBuilder)
local CarService = require(script.Parent.CarService)

local Meets = {}

function Meets.init() end

function Meets.start()
	local payoutTimer = 0
	while true do
		local dt = task.wait(1)
		payoutTimer += dt

		-- which meet is each player's car parked at?
		local parkedAt: { [Player]: string } = {}
		local counts: { [string]: number } = {}
		for _, player in Players:GetPlayers() do
			local car = CarService.getCar(player)
			local chassis = car and car:FindFirstChild("Chassis") :: BasePart?
			if chassis and chassis.AssemblyLinearVelocity.Magnitude < 3 then
				local meet = MapBuilder.meetAt(chassis.Position)
				if meet then
					parkedAt[player] = meet
					counts[meet] = (counts[meet] or 0) + 1
				end
			end
		end

		for _, player in Players:GetPlayers() do
			local meet = parkedAt[player]
			player:SetAttribute("Meet", meet or "")
			player:SetAttribute("MeetCount", if meet then counts[meet] else 0)
		end

		if payoutTimer >= Config.Meet.PayoutInterval then
			payoutTimer = 0
			for player, meet in parkedAt do
				local char = player.Character
				local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
				local car = CarService.getCar(player)
				-- the owner has to actually be hanging out at the meet
				if root and car and (root.Position - car:GetPivot().Position).Magnitude < 200 then
					PlayerData.addCash(player, Config.Meet.PayPerCar * counts[meet], "Car meet rep (" .. meet .. ")")
				end
			end
		end
	end
end

return Meets
