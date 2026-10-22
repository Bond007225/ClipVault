--!strict
-- Server bootstrap. Order matters: remotes and the map exist before any service
-- starts listening.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))
Remotes.setup()

local Services = script.Parent:WaitForChild("Services")
local WorldBuilder = require(Services.WorldBuilder)
local DataService = require(Services.DataService)
local RagdollService = require(Services.RagdollService)
local SnowboardService = require(Services.SnowboardService)
local TrickService = require(Services.TrickService)
local SnowballService = require(Services.SnowballService)
local ShopService = require(Services.ShopService)
local LeaderboardService = require(Services.LeaderboardService)

WorldBuilder.build()
DataService.start()
RagdollService.start()
SnowboardService.start()
TrickService.start()
SnowballService.start()
ShopService.start()
LeaderboardService.start()
