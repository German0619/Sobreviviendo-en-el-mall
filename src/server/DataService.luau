--!strict
-- DataService: carga, guarda y expone los datos persistentes de cada jugador.
--
-- * Bloqueo de sesion: al teletransportarse lobby <-> mall, el servidor nuevo
--   espera a que el anterior termine de guardar antes de cargar, para no
--   perder progreso.
-- * Si DataStore no esta disponible (Studio sin "Enable Studio Access to API
--   Services"), el jugador juega con datos por defecto que NO se guardan.
-- * Si DataStore esta disponible pero la carga falla, se expulsa al jugador
--   para no sobrescribir sus datos reales con datos vacios.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Types = require(Shared.Types)
local Util = require(Shared.Util)
local Signal = require(Shared.Signal)

type PlayerData = Types.PlayerData

local LOCK_TIMEOUT = 600 -- un bloqueo mas viejo que esto se considera abandonado
local LOAD_ATTEMPTS = 10
local LOAD_RETRY_SECONDS = 3
local SAVE_ATTEMPTS = 5

local DataService = {}

-- (player: Player, data: PlayerData)
DataService.ProfileLoaded = Signal.new()
-- (player: Player, newAmount: number, delta: number)
DataService.MoneyChanged = Signal.new()

local profiles: { [Player]: PlayerData } = {}
local canSave: { [Player]: boolean } = {}
local saving: { [Player]: boolean } = {}

local store: DataStore? = nil

local function keyFor(userId: number): string
	return "Player_" .. userId
end

local function initStore()
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.Data.StoreName)
	end)
	if not ok then
		warn("[DataService] DataStore no disponible, los datos NO se guardaran:", result)
		return
	end
	-- Una lectura de prueba detecta "Studio access to API services" desactivado.
	local probeOk, probeErr = pcall(function()
		return (result :: DataStore):GetAsync("__probe")
	end)
	if not probeOk then
		warn("[DataService] DataStore no accesible, los datos NO se guardaran:", probeErr)
		return
	end
	store = result
end

-- Atributos replicados al cliente para que la UI los lea sin remotes.
local function pushAttributes(player: Player, data: PlayerData)
	player:SetAttribute("Money", data.Money)
	player:SetAttribute("BestNight", data.BestNight)
	player:SetAttribute("EquippedClass", data.EquippedClass)
	for itemId in Config.ShopItems do
		player:SetAttribute("Item_" .. itemId, data.Inventory[itemId] or 0)
	end
end

local function sanitize(data: PlayerData)
	data.SessionLock = nil
	Util.reconcile(data :: any, Config.DefaultData :: any)
	-- Si la clase equipada ya no existe o no es suya, volver a la por defecto.
	if not Config.Classes[data.EquippedClass] or not data.OwnedClasses[data.EquippedClass] then
		data.EquippedClass = Config.DefaultClass
	end
	data.OwnedClasses[Config.DefaultClass] = true
end

-- Devuelve (ok, data). ok=false significa error real de DataStore.
local function loadFromStore(userId: number): (boolean, PlayerData?)
	local activeStore = store :: DataStore
	local key = keyFor(userId)

	for attempt = 1, LOAD_ATTEMPTS do
		local lockedByOther = false
		local isLastAttempt = attempt == LOAD_ATTEMPTS

		local ok, result = pcall(function()
			return activeStore:UpdateAsync(key, function(old: PlayerData?)
				lockedByOther = false
				local data: PlayerData = old or Util.deepCopy(Config.DefaultData)
				local lock = data.SessionLock
				local lockIsFresh = lock ~= nil and os.time() - lock.Time < LOCK_TIMEOUT
				if lock and lock.JobId ~= game.JobId and lockIsFresh and not isLastAttempt then
					-- Otro servidor aun tiene la sesion; esperar a que guarde.
					lockedByOther = true
					return nil
				end
				data.SessionLock = { JobId = game.JobId, Time = os.time() }
				return data
			end)
		end)

		if ok and not lockedByOther and result then
			return true, result :: PlayerData
		end

		if not ok then
			warn(string.format("[DataService] Error cargando %d (intento %d): %s", userId, attempt, tostring(result)))
		end
		task.wait(LOAD_RETRY_SECONDS)
	end

	return false, nil
end

local function saveToStore(player: Player, release: boolean): boolean
	local activeStore = store
	local data = profiles[player]
	if not activeStore or not data or not canSave[player] then
		return false
	end

	local snapshot = Util.deepCopy(data)
	local key = keyFor(player.UserId)

	for attempt = 1, SAVE_ATTEMPTS do
		local lostLock = false
		local ok, err = pcall(function()
			activeStore:UpdateAsync(key, function(old: PlayerData?)
				lostLock = false
				local oldLock = old and old.SessionLock
				if oldLock and oldLock.JobId ~= game.JobId then
					-- Otro servidor tomo la sesion; no lo pisamos.
					lostLock = true
					return nil
				end
				snapshot.SessionLock = if release then nil else { JobId = game.JobId, Time = os.time() }
				return snapshot
			end)
		end)

		if ok then
			if lostLock then
				warn("[DataService] Sesion de", player.Name, "tomada por otro servidor; no se guardo.")
				canSave[player] = false
				return false
			end
			return true
		end

		warn(string.format("[DataService] Error guardando %s (intento %d): %s", player.Name, attempt, tostring(err)))
		task.wait(2 ^ attempt)
	end

	return false
end

local function onPlayerAdded(player: Player)
	local data: PlayerData
	if store then
		local ok, loaded = loadFromStore(player.UserId)
		if not ok or not loaded then
			player:Kick("No pudimos cargar tus datos. Vuelve a entrar en un momento.")
			return
		end
		data = loaded
		canSave[player] = true
	else
		data = Util.deepCopy(Config.DefaultData)
		canSave[player] = false
	end

	sanitize(data)

	if player.Parent == nil then
		-- Se fue mientras cargaba: liberar el bloqueo y salir.
		profiles[player] = data
		saveToStore(player, true)
		profiles[player] = nil
		canSave[player] = nil
		return
	end

	profiles[player] = data
	pushAttributes(player, data)
	DataService.ProfileLoaded:Fire(player, data)
end

local function onPlayerRemoving(player: Player)
	if not profiles[player] or saving[player] then
		return
	end
	saving[player] = true
	saveToStore(player, true)
	profiles[player] = nil
	canSave[player] = nil
	saving[player] = nil
end

----------------------------------------------------------------------
-- API publica
----------------------------------------------------------------------

function DataService.GetData(player: Player): PlayerData?
	return profiles[player]
end

-- Espera a que el perfil cargue (o a que el jugador se vaya / timeout).
function DataService.WaitForData(player: Player, timeout: number?): PlayerData?
	local deadline = os.clock() + (timeout or 60)
	while not profiles[player] and player.Parent and os.clock() < deadline do
		task.wait(0.1)
	end
	return profiles[player]
end

-- Modifica los datos y vuelve a publicar los atributos.
function DataService.Update(player: Player, fn: (data: PlayerData) -> ())
	local data = profiles[player]
	if not data then
		return
	end
	fn(data)
	pushAttributes(player, data)
end

function DataService.GetMoney(player: Player): number
	local data = profiles[player]
	return if data then data.Money else 0
end

function DataService.AddMoney(player: Player, amount: number)
	local data = profiles[player]
	if not data or amount <= 0 then
		return
	end
	amount = math.floor(amount)
	data.Money += amount
	data.Lifetime.MoneyEarned += amount
	pushAttributes(player, data)
	DataService.MoneyChanged:Fire(player, data.Money, amount)
end

-- Cobra si alcanza. Devuelve true si se cobro.
function DataService.TrySpend(player: Player, amount: number): boolean
	local data = profiles[player]
	if not data or amount < 0 or data.Money < amount then
		return false
	end
	amount = math.floor(amount)
	data.Money -= amount
	pushAttributes(player, data)
	DataService.MoneyChanged:Fire(player, data.Money, -amount)
	return true
end

function DataService.IsPersistent(player: Player): boolean
	return canSave[player] == true
end

function DataService.Save(player: Player): boolean
	return saveToStore(player, false)
end

----------------------------------------------------------------------
-- Arranque
----------------------------------------------------------------------

function DataService.Start()
	initStore()

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	-- Autoguardado
	task.spawn(function()
		while true do
			task.wait(Config.Data.AutosaveSeconds)
			for player in profiles do
				if not saving[player] then
					task.spawn(saveToStore, player, false)
				end
			end
		end
	end)

	-- Guardar a todos al cerrar el servidor
	-- (onPlayerRemoving borra el perfil al terminar, asi que esperamos a que
	-- no quede ninguno, incluidos los que ya se estaban guardando.)
	game:BindToClose(function()
		for player in profiles do
			if not saving[player] then
				task.spawn(onPlayerRemoving, player)
			end
		end
		local deadline = os.clock() + 25
		while next(profiles) ~= nil and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

return DataService
