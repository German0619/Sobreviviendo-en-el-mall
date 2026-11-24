-- LeaderboardService: tablas de clasificacion globales (Config.Leaderboards).
--
-- * Subir (lobby y mall): cuando cambia el atributo de una tabla (BestNight,
--   BossesDefeated) se guarda en su OrderedDataStore, solo si mejora. Tambien al
--   cargar el perfil (para records antiguos) y al salir.
-- * Mostrar (solo lobby): rellena las pantallas de la plaza (tag LobbyLeaderboard,
--   atributo Board) con el top: puesto, avatar, nombre y valor. Se relee cada
--   Config.Leaderboards.RefreshSeconds y cuando entra alguien al lobby.
--
-- Todo va en pcall: si DataStore no esta disponible (Studio sin API Services),
-- las pantallas muestran su texto de "vacio" y el juego sigue.

local CollectionService = game:GetService("CollectionService")
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserService = game:GetService("UserService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Tags = require(Shared.Tags)
local Place = require(Shared.Place)

local DataService = require(script.Parent.DataService)

local LeaderboardService = {}

local BOARDS = Config.Leaderboards.Boards
local TOP = Config.Leaderboards.Top
local MEDALS = {
	Color3.fromRGB(255, 205, 70), -- oro
	Color3.fromRGB(200, 210, 225), -- plata
	Color3.fromRGB(215, 140, 80), -- bronce
}

local stores: { [string]: OrderedDataStore } = {}
local submitted: { [Player]: { [string]: number } } = {} -- ultimo valor subido por tabla
local nameCache: { [number]: string } = {}
local refreshQueued = false

local function storeFor(boardId: string): OrderedDataStore?
	if stores[boardId] then
		return stores[boardId]
	end
	local ok, store = pcall(function()
		return DataStoreService:GetOrderedDataStore(BOARDS[boardId].Store)
	end)
	if ok then
		stores[boardId] = store
		return store
	end
	return nil
end

----------------------------------------------------------------------
-- Subir records
----------------------------------------------------------------------

local function submit(player: Player, boardId: string)
	local board = BOARDS[boardId]
	local value = player:GetAttribute(board.Stat)
	if type(value) ~= "number" or value <= 0 then
		return
	end
	value = math.floor(value)
	local mine = submitted[player] or {}
	submitted[player] = mine
	if (mine[boardId] or 0) >= value then
		return -- ya esta subido
	end
	local store = storeFor(boardId)
	if not store then
		return
	end
	local ok, err = pcall(function()
		store:UpdateAsync(tostring(player.UserId), function(old)
			if type(old) == "number" and old >= value then
				return nil -- el guardado ya es igual o mejor
			end
			return value
		end)
	end)
	if ok then
		mine[boardId] = value
	else
		warn("[LeaderboardService] No se pudo subir", boardId, err)
	end
end

local function submitAll(player: Player)
	for boardId in BOARDS do
		task.spawn(submit, player, boardId)
	end
end

----------------------------------------------------------------------
-- Pantallas (lobby)
----------------------------------------------------------------------

local function displayNames(userIds: { number }): { [number]: string }
	local missing = {}
	for _, id in userIds do
		if not nameCache[id] then
			table.insert(missing, id)
		end
	end
	if #missing > 0 then
		local ok, infos = pcall(function()
			return UserService:GetUserInfosByUserIdsAsync(missing)
		end)
		if ok and infos then
			for _, info in infos do
				nameCache[info.Id] = info.DisplayName
			end
		end
	end
	local result = {}
	for _, id in userIds do
		result[id] = nameCache[id] or ("Jugador " .. id)
	end
	return result
end

local function newLabel(parent: Instance, name: string, size: UDim2, position: UDim2): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Size = size
	l.Position = position
	l.Font = Enum.Font.GothamBold
	l.TextScaled = true
	l.TextColor3 = Color3.new(1, 1, 1)
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Text = ""
	l.Parent = parent
	return l
end

-- Crea (una vez) las filas del top dentro del marco "Entries" de la pantalla.
local function ensureRows(entries: Frame): { Frame }
	local rows = {}
	for i = 1, TOP do
		local row = entries:FindFirstChild("Row" .. i) :: Frame?
		if not row then
			local r = Instance.new("Frame")
			r.Name = "Row" .. i
			r.Size = UDim2.fromScale(1, 1 / TOP - 0.012)
			r.Position = UDim2.fromScale(0, (i - 1) / TOP)
			r.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
			r.BackgroundTransparency = if i % 2 == 0 then 0.96 else 0.92
			r.BorderSizePixel = 0
			r.Parent = entries
			local c = Instance.new("UICorner")
			c.CornerRadius = UDim.new(0.25, 0)
			c.Parent = r
			newLabel(r, "Rank", UDim2.fromScale(0.09, 0.8), UDim2.fromScale(0.015, 0.1)).TextXAlignment = Enum.TextXAlignment.Center
			local avatar = Instance.new("ImageLabel")
			avatar.Name = "Avatar"
			avatar.BackgroundColor3 = Color3.fromRGB(40, 44, 70)
			avatar.Size = UDim2.fromScale(0.07, 0.9)
			avatar.Position = UDim2.fromScale(0.11, 0.05)
			avatar.Parent = r
			local aspect = Instance.new("UIAspectRatioConstraint")
			aspect.AspectRatio = 1
			aspect.Parent = avatar
			local ac = Instance.new("UICorner")
			ac.CornerRadius = UDim.new(0.5, 0)
			ac.Parent = avatar
			newLabel(r, "PlayerName", UDim2.fromScale(0.5, 0.75), UDim2.fromScale(0.2, 0.125))
			local value = newLabel(r, "Value", UDim2.fromScale(0.27, 0.75), UDim2.fromScale(0.71, 0.125))
			value.TextXAlignment = Enum.TextXAlignment.Right
			row = r
		end
		rows[i] = row :: Frame
	end
	return rows
end

local function renderBoard(model: Instance, boardId: string, top: { { UserId: number, Value: number } })
	local board = BOARDS[boardId]
	local screen = model:FindFirstChild("Screen")
	local gui = screen and screen:FindFirstChildWhichIsA("SurfaceGui")
	local background = gui and gui:FindFirstChildWhichIsA("Frame")
	local entries = background and background:FindFirstChild("Entries") :: Frame?
	if not entries then
		warn("[LeaderboardService] La pantalla", model:GetFullName(), "no tiene Screen > SurfaceGui > Frame > Entries")
		return
	end
	local title = background:FindFirstChild("Title")
	if title and title:IsA("TextLabel") then
		title.Text = board.Title
	end

	local placeholder = entries:FindFirstChild("Placeholder")
	if placeholder and placeholder:IsA("TextLabel") then
		placeholder.Text = board.Empty
		placeholder.Visible = #top == 0
	end

	local ids = {}
	for _, entry in top do
		table.insert(ids, entry.UserId)
	end
	local names = displayNames(ids)

	for i, row in ensureRows(entries) do
		local entry = top[i]
		row.Visible = entry ~= nil
		if entry then
			local rank = row:FindFirstChild("Rank") :: TextLabel
			rank.Text = "#" .. i
			rank.TextColor3 = MEDALS[i] or Color3.fromRGB(170, 175, 200)
			local avatar = row:FindFirstChild("Avatar") :: ImageLabel
			avatar.Image = string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150", entry.UserId)
			local name = row:FindFirstChild("PlayerName") :: TextLabel
			name.Text = names[entry.UserId]
			name.TextColor3 = MEDALS[i] or Color3.new(1, 1, 1)
			local value = row:FindFirstChild("Value") :: TextLabel
			value.Text = string.format(board.Format, entry.Value)
		end
	end
end

local function readTop(boardId: string): { { UserId: number, Value: number } }
	local store = storeFor(boardId)
	local top = {}
	if not store then
		return top
	end
	local ok, pages = pcall(function()
		return store:GetSortedAsync(false, TOP, 1)
	end)
	if not ok or not pages then
		warn("[LeaderboardService] No se pudo leer", boardId, pages)
		return top
	end
	for _, item in pages:GetCurrentPage() do
		local userId = tonumber(item.key)
		if userId then
			table.insert(top, { UserId = userId, Value = item.value })
		end
	end
	return top
end

function LeaderboardService.Refresh()
	for _, model in CollectionService:GetTagged(Tags.LobbyLeaderboard) do
		local boardId = model:GetAttribute("Board")
		if type(boardId) == "string" and BOARDS[boardId] then
			renderBoard(model, boardId, readTop(boardId))
		end
	end
end

-- Pide un refresco pronto (se agrupan varios seguidos).
local function queueRefresh()
	if refreshQueued then
		return
	end
	refreshQueued = true
	task.delay(5, function()
		refreshQueued = false
		LeaderboardService.Refresh()
	end)
end

----------------------------------------------------------------------
-- Arranque
----------------------------------------------------------------------

function LeaderboardService.Start()
	DataService.ProfileLoaded:Connect(function(player: Player)
		submitAll(player)
		for _, board in BOARDS do
			player:GetAttributeChangedSignal(board.Stat):Connect(function()
				submitAll(player)
				if Place.IsLobby then
					queueRefresh()
				end
			end)
		end
		if Place.IsLobby then
			queueRefresh()
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		submitAll(player)
		submitted[player] = nil
	end)

	if Place.IsLobby then
		task.spawn(function()
			LeaderboardService.Refresh()
			while true do
				task.wait(Config.Leaderboards.RefreshSeconds)
				LeaderboardService.Refresh()
			end
		end)
	end
end

return LeaderboardService
