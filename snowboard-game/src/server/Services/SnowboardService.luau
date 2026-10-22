--!strict
-- Owns each player's snowboard: strapped to their feet while riding, slung on
-- their back while walking, dropped as a loose prop when they wipe out. The server
-- is the authority on the "Riding" attribute; the client only asks to toggle.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cosmetics = require(Shared.Cosmetics)
local Remotes = require(Shared.Remotes)

local DataService = require(script.Parent.DataService)
local RateLimiter = require(script.Parent.RateLimiter)

local SnowboardService = {}

local POSES = {
	None = true,
	Ride = true,
	Crouch = true,
	Air = true,
	Grind = true,
	Indy = true,
	Method = true,
	Nose = true,
	Tail = true,
}

local toggleLimiter = RateLimiter.new(3, 2)
local poseLimiter = RateLimiter.new(30, 20)

local looseFolder: Folder

local function getParts(character: Model): (Humanoid?, BasePart?, BasePart?)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local torso = (character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")) :: BasePart?
	return humanoid, root, torso
end

local function getBoard(character: Model): Model?
	return character:FindFirstChild("Snowboard") :: Model?
end

-- Distance from the HumanoidRootPart centre down to the soles of the feet.
function SnowboardService.footOffset(character: Model): number
	local humanoid, root = getParts(character)
	if not humanoid or not root then
		return 3
	end
	local legs = if humanoid.RigType == Enum.HumanoidRigType.R6 then 2 else humanoid.HipHeight
	return root.Size.Y / 2 + legs
end

local function weldBoard(character: Model, board: Model, riding: boolean)
	local _, root, torso = getParts(character)
	local deck = board.PrimaryPart
	if not root or not torso or not deck then
		return
	end
	local old = deck:FindFirstChild("BoardWeld")
	if old then
		old:Destroy()
	end

	local w = Instance.new("Weld")
	w.Name = "BoardWeld"
	if riding then
		w.Part0 = root
		w.C0 = CFrame.new(0, -(SnowboardService.footOffset(character) + 0.11), 0)
	else
		-- Slung diagonally across the back.
		w.Part0 = torso
		w.C0 = CFrame.new(0, 0, torso.Size.Z / 2 + 0.25) * CFrame.Angles(0, 0, math.rad(60)) * CFrame.Angles(math.rad(90), 0, 0)
	end
	w.Part1 = deck
	w.Parent = deck
end

local function giveBoard(player: Player, character: Model)
	local existing = getBoard(character)
	if existing then
		existing:Destroy()
	end
	local profile = DataService.get(player)
	local boardId = if profile then profile.Data.Equipped.Board else nil
	local board = Cosmetics.buildBoard(boardId)
	local riding = character:GetAttribute("Riding") == true
	local _, root = getParts(character)
	if root and board.PrimaryPart then
		board:PivotTo(root.CFrame)
	end
	board.Parent = character
	weldBoard(character, board, riding)
end

function SnowboardService.isRiding(player: Player): boolean
	local character = player.Character
	return character ~= nil and character:GetAttribute("Riding") == true
end

function SnowboardService.setRiding(player: Player, riding: boolean)
	local character = player.Character
	if not character then
		return
	end
	local board = getBoard(character)
	if not board then
		giveBoard(player, character)
		board = getBoard(character)
	end
	character:SetAttribute("Riding", riding)
	character:SetAttribute("Pose", if riding then "Ride" else "None")
	character:SetAttribute("Lean", 0)
	if board then
		weldBoard(character, board, riding)
	end
end

-- Wipeout: the board flies off on its own and a fresh one appears on the
-- player's back after `respawnDelay`.
function SnowboardService.dropBoard(player: Player, respawnDelay: number)
	local character = player.Character
	if not character then
		return
	end
	character:SetAttribute("Riding", false)
	character:SetAttribute("Pose", "None")
	local board = getBoard(character)
	if board then
		local deck = board.PrimaryPart
		local weldInst = deck and deck:FindFirstChild("BoardWeld")
		if weldInst then
			weldInst:Destroy()
		end
		board.Parent = looseFolder
		if deck then
			deck.CanCollide = true
			deck.Massless = false
			pcall(function()
				deck:SetNetworkOwner(nil)
			end)
			deck.AssemblyAngularVelocity = Vector3.new(math.random() * 10 - 5, math.random() * 10 - 5, math.random() * 10 - 5)
		end
		task.delay(respawnDelay + 2, function()
			board:Destroy()
		end)
	end
	task.delay(respawnDelay, function()
		if player.Character == character and character.Parent then
			giveBoard(player, character)
		end
	end)
end

-- Rebuild after the player equips a different board in the shop.
function SnowboardService.refreshBoard(player: Player)
	local character = player.Character
	if character and getBoard(character) then
		giveBoard(player, character)
	end
end

local function onCharacterAdded(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not humanoid or not root then
		return
	end
	humanoid.BreakJointsOnDeath = false
	character:SetAttribute("Riding", false)
	character:SetAttribute("Ragdolled", false)
	character:SetAttribute("Pose", "None")
	character:SetAttribute("Lean", 0)
	-- Wait for the R15 body parts to be assembled before welding to them.
	character:WaitForChild(if humanoid.RigType == Enum.HumanoidRigType.R6 then "Torso" else "UpperTorso", 10)
	DataService.waitFor(player)
	if player.Character == character then
		giveBoard(player, character)
	end
end

function SnowboardService.start()
	looseFolder = Instance.new("Folder")
	looseFolder.Name = "LooseBoards"
	looseFolder.Parent = Workspace

	local function hook(player: Player)
		player.CharacterAdded:Connect(function(character)
			onCharacterAdded(player, character)
		end)
		player.CharacterAppearanceLoaded:Connect(function(character)
			-- Body parts may have been swapped by the avatar loader; re-weld the board.
			if player.Character == character and DataService.get(player) and character:GetAttribute("Ragdolled") ~= true then
				giveBoard(player, character)
			end
		end)
		if player.Character then
			task.spawn(onCharacterAdded, player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(hook)
	for _, p in Players:GetPlayers() do
		hook(p)
	end

	Remotes.event("ToggleBoard").OnServerEvent:Connect(function(player)
		if not toggleLimiter:take(player) then
			return
		end
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not character or not humanoid or humanoid.Health <= 0 then
			return
		end
		if character:GetAttribute("Ragdolled") == true or not getBoard(character) then
			return
		end
		SnowboardService.setRiding(player, not SnowboardService.isRiding(player))
	end)

	Remotes.unreliable("PoseUpdate").OnServerEvent:Connect(function(player, pose: any, lean: any)
		if not poseLimiter:take(player) then
			return
		end
		local character = player.Character
		if not character or character:GetAttribute("Riding") ~= true then
			return
		end
		if type(pose) ~= "string" or not POSES[pose] then
			return
		end
		if type(lean) ~= "number" or lean ~= lean then
			return
		end
		character:SetAttribute("Pose", pose)
		character:SetAttribute("Lean", math.round(math.clamp(lean, -1, 1) * 20) / 20)
	end)
end

return SnowboardService
