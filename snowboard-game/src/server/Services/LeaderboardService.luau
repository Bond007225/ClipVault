--!strict
-- Global leaderboards backed by OrderedDataStores, shown on the boards in the lobby
-- (built by WorldBuilder; each board has a "Stat" attribute and a "Rows" frame).

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local DataService = require(script.Parent.DataService)

local LeaderboardService = {}

type BoardDef = { stat: string, storeName: string, store: OrderedDataStore? }

local boards: { BoardDef } = {
	{ stat = "TotalPoints", storeName = Config.Leaderboard.TotalStore },
	{ stat = "BestCombo", storeName = Config.Leaderboard.ComboStore },
}

local lastWritten: { [Player]: { [string]: number } } = {}
local nameCache: { [number]: string } = {}

local function nameFor(userId: number): string
	local cached = nameCache[userId]
	if cached then
		return cached
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	local result = if ok and name then name else "Player " .. userId
	nameCache[userId] = result
	return result
end

local function writePlayer(player: Player)
	local profile = DataService.get(player)
	if not profile or not profile.CanSave then
		return
	end
	local written = lastWritten[player] or {}
	lastWritten[player] = written
	for _, def in boards do
		local value = (profile.Data :: any)[def.stat] :: number
		local s = def.store
		if s and value > 0 and written[def.stat] ~= value then
			local ok, err = pcall(function()
				s:SetAsync("u_" .. player.UserId, math.floor(value))
			end)
			if ok then
				written[def.stat] = value
			else
				warn("[Leaderboard] write failed: " .. tostring(err))
			end
		end
	end
end

local function formatNumber(n: number): string
	local s = tostring(math.floor(n))
	local formatted = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if formatted:sub(1, 1) == "," then
		formatted = formatted:sub(2)
	end
	return formatted
end

local function renderBoard(boardPart: Instance, entries: { { name: string, value: number } })
	local rows = boardPart:FindFirstChild("Rows", true) :: Frame?
	if not rows then
		return
	end
	for _, child in rows:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local medal = { Color3.fromRGB(255, 205, 60), Color3.fromRGB(200, 210, 225), Color3.fromRGB(215, 140, 80) }
	for rank, entry in entries do
		local row = Instance.new("Frame")
		row.Name = "Row" .. rank
		row.LayoutOrder = rank
		row.Size = UDim2.new(1, 0, 0, 44)
		row.BackgroundColor3 = if rank % 2 == 0 then Color3.fromRGB(30, 50, 80) else Color3.fromRGB(24, 40, 66)
		row.BorderSizePixel = 0

		local function label(text: string, x: number, w: number, align: Enum.TextXAlignment, color: Color3)
			local t = Instance.new("TextLabel")
			t.BackgroundTransparency = 1
			t.Position = UDim2.new(x, 8, 0, 0)
			t.Size = UDim2.new(w, -16, 1, 0)
			t.Font = Enum.Font.GothamBold
			t.TextScaled = true
			t.TextXAlignment = align
			t.TextColor3 = color
			t.Text = text
			t.Parent = row
		end
		local rankColor = medal[rank] or Color3.fromRGB(230, 240, 255)
		label("#" .. rank, 0, 0.15, Enum.TextXAlignment.Left, rankColor)
		label(entry.name, 0.15, 0.55, Enum.TextXAlignment.Left, Color3.fromRGB(240, 248, 255))
		label(formatNumber(entry.value), 0.7, 0.3, Enum.TextXAlignment.Right, rankColor)
		row.Parent = rows
	end
	if #entries == 0 then
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, 44)
		row.BackgroundTransparency = 1
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.Size = UDim2.fromScale(1, 1)
		t.Font = Enum.Font.Gotham
		t.TextScaled = true
		t.TextColor3 = Color3.fromRGB(200, 215, 235)
		t.Text = "Land some tricks to claim #1!"
		t.Parent = row
		row.Parent = rows
	end
end

local function refresh()
	local map = Workspace:FindFirstChild("Map")
	local lobby = map and map:FindFirstChild("Lobby")
	if not lobby then
		return
	end
	for _, def in boards do
		local s = def.store
		local entries = {}
		local fromStore = false
		if s then
			local ok, pages = pcall(function()
				return s:GetSortedAsync(false, Config.Leaderboard.TopCount)
			end)
			if ok and pages then
				fromStore = true
				for _, item in pages:GetCurrentPage() do
					local userId = tonumber(string.sub(item.key, 3))
					if userId then
						table.insert(entries, { name = nameFor(userId), value = item.value })
					end
				end
			end
		end
		if not fromStore then
			-- No DataStore access (e.g. Studio): rank the players in this server.
			for _, p in Players:GetPlayers() do
				local v = p:GetAttribute(def.stat)
				if type(v) == "number" and v > 0 then
					table.insert(entries, { name = p.Name, value = v })
				end
			end
			table.sort(entries, function(a, b)
				return a.value > b.value
			end)
		end
		for _, board in lobby:GetDescendants() do
			if board:GetAttribute("Stat") == def.stat then
				renderBoard(board, entries)
			end
		end
	end
end

function LeaderboardService.start()
	for _, def in boards do
		local ok, s = pcall(function()
			return DataStoreService:GetOrderedDataStore(def.storeName)
		end)
		if ok then
			def.store = s
		end
	end

	DataService.onRelease(function(player)
		task.spawn(writePlayer, player)
		lastWritten[player] = nil
	end)

	task.spawn(function()
		while true do
			for _, p in Players:GetPlayers() do
				writePlayer(p)
			end
			refresh()
			task.wait(Config.Leaderboard.RefreshInterval)
		end
	end)
end

return LeaderboardService
