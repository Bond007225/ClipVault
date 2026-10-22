--!strict
-- Buying and equipping cosmetics/boards. All prices and ownership checks happen
-- here; the client only sends item ids.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Catalog = require(Shared.Catalog)
local Cosmetics = require(Shared.Cosmetics)
local Remotes = require(Shared.Remotes)

local DataService = require(script.Parent.DataService)
local SnowboardService = require(script.Parent.SnowboardService)
local RateLimiter = require(script.Parent.RateLimiter)

local ShopService = {}

local limiter = RateLimiter.new(6, 4)

export type ProfileView = {
	Coins: number,
	Owned: { [string]: boolean },
	Equipped: { [string]: string },
}

local function view(player: Player): ProfileView?
	local profile = DataService.get(player)
	if not profile then
		return nil
	end
	return {
		Coins = profile.Data.Coins,
		Owned = table.clone(profile.Data.Owned),
		Equipped = table.clone(profile.Data.Equipped),
	}
end

local function applyOutfit(player: Player)
	local character = player.Character
	local profile = DataService.get(player)
	if character and profile then
		Cosmetics.apply(character, profile.Data.Equipped)
	end
end

local function purchase(player: Player, itemId: any): (boolean, string, ProfileView?)
	if not limiter:take(player) then
		return false, "Slow down!", nil
	end
	if type(itemId) ~= "string" then
		return false, "Unknown item", nil
	end
	local item = Catalog.get(itemId)
	local profile = DataService.get(player)
	if not item or not profile then
		return false, "Unknown item", nil
	end
	local data = profile.Data
	if data.Owned[item.Id] then
		return false, "You already own this", view(player)
	end
	if data.Coins < item.Price then
		return false, `You need {item.Price - data.Coins} more coins`, view(player)
	end
	data.Coins -= item.Price
	data.Owned[item.Id] = true
	-- Wear new purchases straight away.
	data.Equipped[item.Slot] = item.Id
	DataService.markDirty(player)
	applyOutfit(player)
	if item.Slot == "Board" then
		SnowboardService.refreshBoard(player)
	end
	return true, `Bought {item.Name}!`, view(player)
end

local function equip(player: Player, slot: any, itemId: any): (boolean, string, ProfileView?)
	if not limiter:take(player) then
		return false, "Slow down!", nil
	end
	if not Catalog.isSlot(slot) then
		return false, "Unknown slot", nil
	end
	local profile = DataService.get(player)
	if not profile then
		return false, "Profile not loaded", nil
	end
	local data = profile.Data
	if itemId == nil then
		if slot == "Board" then
			return false, "You need a board to ride!", view(player)
		end
		data.Equipped[slot] = nil
	else
		if type(itemId) ~= "string" then
			return false, "Unknown item", nil
		end
		local item = Catalog.get(itemId)
		if not item or item.Slot ~= slot then
			return false, "Unknown item", nil
		end
		if not data.Owned[item.Id] then
			return false, "You don't own that yet", view(player)
		end
		data.Equipped[slot] = item.Id
	end
	DataService.markDirty(player)
	applyOutfit(player)
	if slot == "Board" then
		SnowboardService.refreshBoard(player)
	end
	return true, "Equipped", view(player)
end

function ShopService.start()
	Remotes.func("GetProfile").OnServerInvoke = function(player)
		DataService.waitFor(player)
		return view(player)
	end
	Remotes.func("PurchaseItem").OnServerInvoke = function(player, itemId)
		local ok, msg, v = purchase(player, itemId)
		return { ok = ok, message = msg, profile = v }
	end
	Remotes.func("EquipItem").OnServerInvoke = function(player, slot, itemId)
		local ok, msg, v = equip(player, slot, itemId)
		return { ok = ok, message = msg, profile = v }
	end

	local function onCharacter(player: Player, character: Model)
		local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
		if not humanoid then
			return
		end
		character:WaitForChild(if humanoid.RigType == Enum.HumanoidRigType.R6 then "Torso" else "UpperTorso", 10)
		DataService.waitFor(player)
		if player.Character == character then
			applyOutfit(player)
		end
	end
	local function hook(player: Player)
		player.CharacterAdded:Connect(function(c)
			onCharacter(player, c)
		end)
		-- Accessories/body parts can arrive after CharacterAdded; dress again once loaded.
		player.CharacterAppearanceLoaded:Connect(function(c)
			if player.Character == c and DataService.get(player) then
				applyOutfit(player)
			end
		end)
		if player.Character then
			task.spawn(onCharacter, player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(hook)
	for _, p in Players:GetPlayers() do
		hook(p)
	end
end

return ShopService
