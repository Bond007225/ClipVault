--!strict
-- Server-authoritative snowballs. The server simulates each ball with raycasts and
-- decides hits; clients only draw the visuals (SnowballFx / SnowballSplat).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)

local DataService = require(script.Parent.DataService)
local SnowboardService = require(script.Parent.SnowboardService)
local RagdollService = require(script.Parent.RagdollService)
local TrickService = require(script.Parent.TrickService)

local SnowballService = {}

type Ball = {
	thrower: Player,
	throwerCharacter: Model,
	position: Vector3,
	velocity: Vector3,
	age: number,
}

local balls: { Ball } = {}
local lastThrow: { [Player]: number } = {}
local GRAVITY = Vector3.new(0, -Config.Snowball.Gravity, 0)

local fxEvent: RemoteEvent
local splatEvent: RemoteEvent
local knockbackEvent: RemoteEvent

local function onHitCharacter(ball: Ball, target: Player, character: Model)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then
		return
	end
	local safe = Config.Snowball.LobbySafeRadius
	if safe > 0 and root.Position.Magnitude < safe then
		return
	end

	local profile = DataService.get(ball.thrower)
	if profile then
		profile.Data.SnowballHits += 1
		DataService.markDirty(ball.thrower)
	end

	local riding = SnowboardService.isRiding(target)
	if Config.Snowball.RagdollTargets and (not riding or Config.Snowball.KnockRidersOff) and not RagdollService.isRagdolled(character) then
		TrickService.wipeout(target, Config.Snowball.RagdollTime)
	end
	local push = ball.velocity.Unit * Config.Snowball.Knockback + Vector3.new(0, 12, 0)
	knockbackEvent:FireClient(target, push)
	Remotes.event("Notify"):FireClient(ball.thrower, `Direct hit on {target.DisplayName}!`, "Hit")
end

local function step(dt: number)
	if #balls == 0 then
		return
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.IgnoreWater = true

	for i = #balls, 1, -1 do
		local ball = balls[i]
		ball.age += dt
		local nextVelocity = ball.velocity + GRAVITY * dt
		local delta = (ball.velocity + nextVelocity) * 0.5 * dt
		params.FilterDescendantsInstances = { ball.throwerCharacter }
		local result = Workspace:Spherecast(ball.position, Config.Snowball.HitRadius * 0.5, delta, params)
		if result then
			table.remove(balls, i)
			local model = result.Instance:FindFirstAncestorOfClass("Model")
			local target = if model then Players:GetPlayerFromCharacter(model) else nil
			splatEvent:FireAllClients(result.Position, target ~= nil)
			if target and model and target ~= ball.thrower then
				onHitCharacter(ball, target, model)
			end
		elseif ball.age > Config.Snowball.Lifetime then
			table.remove(balls, i)
		else
			ball.position += delta
			ball.velocity = nextVelocity
		end
	end
end

local function onThrow(player: Player, direction: any)
	if typeof(direction) ~= "Vector3" then
		return
	end
	local dir = direction :: Vector3
	if dir ~= dir or dir.Magnitude < 0.5 or dir.Magnitude > 1.5 then
		return
	end
	local now = os.clock()
	if now - (lastThrow[player] or 0) < Config.Snowball.Cooldown then
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not character or not humanoid or not root or humanoid.Health <= 0 then
		return
	end
	if SnowboardService.isRiding(player) or RagdollService.isRagdolled(character) then
		return
	end
	lastThrow[player] = now

	dir = dir.Unit
	local origin = root.Position + Vector3.new(0, 1.6, 0) + dir * 2
	local velocity = dir * Config.Snowball.Speed + root.AssemblyLinearVelocity * 0.5
	table.insert(balls, {
		thrower = player,
		throwerCharacter = character,
		position = origin,
		velocity = velocity,
		age = 0,
	})
	fxEvent:FireAllClients(player, origin, velocity)
end

function SnowballService.start()
	fxEvent = Remotes.event("SnowballFx")
	splatEvent = Remotes.event("SnowballSplat")
	knockbackEvent = Remotes.event("Knockback")

	Remotes.event("ThrowSnowball").OnServerEvent:Connect(onThrow)
	RunService.Heartbeat:Connect(step)
	Players.PlayerRemoving:Connect(function(player)
		lastThrow[player] = nil
		for i = #balls, 1, -1 do
			if balls[i].thrower == player then
				table.remove(balls, i)
			end
		end
	end)
end

return SnowballService
