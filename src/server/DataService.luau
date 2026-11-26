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
local RunService = game:GetService("RunService")

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
-- Clase del slot equipado (o la por defecto si algo no cuadra).
local function equippedClassOf(data: PlayerData): string
	local className = data.ClassSlots[data.EquippedSlot]
	return if className and Config.Classes[className] then className else Config.DefaultClass
end

local function pushAttributes(player: Player, data: PlayerData)
	player:SetAttribute("Diamonds", data.Diamonds)
	player:SetAttribute("PaidDiamonds", data.PaidDiamonds)
	player:SetAttribute("BestNight", data.BestNight)
	player:SetAttribute("ReviveTokens", data.ReviveTokens)
	player:SetAttribute("SodaTokens", data.SodaTokens)
	player:SetAttribute("MaxSlots", data.MaxSlots)
	player:SetAttribute("EquippedSlot", data.EquippedSlot)
	player:SetAttribute("EquippedClass", equippedClassOf(data))
	for i = 1, Config.Roulette.MaxSlots do
		player:SetAttribute("Slot_" .. i, data.ClassSlots[i] or "")
	end
	-- Logros: estado ("locked" | "claimable" | "claimed") y progreso actual
	for achievementId, achievement in Config.Achievements do
		local state = if data.ClaimedAchievements[achievementId]
			then "claimed"
			elseif data.Achievements[achievementId] then "claimable"
			else "locked"
		player:SetAttribute("Ach_" .. achievementId, state)
		player:SetAttribute("AchProg_" .. achievementId, Config.getAchievementProgress(data, achievement))
	end
	player:SetAttribute("VipDailyDay", data.VipDailyDay)
	player:SetAttribute("BossesDefeated", data.Lifetime.BossesDefeated or 0) -- tabla "Jefes vencidos"
	-- Skins: la equipada de cada objeto (Skin_<objeto>, la usa el mall) y las que tienes
	-- (OwnedSkins: "Taser:Gold,Mop:Camo", para el panel de cosmeticos)
	local owned = {}
	for key, has in data.Skins or {} do
		if has then
			table.insert(owned, key)
		end
	end
	table.sort(owned)
	player:SetAttribute("OwnedSkins", table.concat(owned, ","))
	for _, itemId in Config.Cosmetics.Items do
		local skin = (data.EquippedSkins or {})[itemId]
		player:SetAttribute("Skin_" .. itemId, if skin and Config.Skins[skin] then skin else nil)
	end
	-- Mejoras permanentes: nivel de cada una (Perm_<id>) y puntos de mejora
	for upgradeId in Config.PermanentUpgrades do
		player:SetAttribute("Perm_" .. upgradeId, (data.PermanentUpgrades or {})[upgradeId] or 0)
	end
	player:SetAttribute("UpgradePoints", data.UpgradePoints or 0)
	-- Maestria: noches sobrevividas con cada clase (Mastery_<clase>)
	for className in Config.Classes do
		player:SetAttribute("Mastery_" .. className, (data.ClassMastery or {})[className] or 0)
	end
	-- Taquilla del conserje: cantidad guardada de cada objeto (Locker_<objeto>)
	for itemId in Config.Locker.Items do
		player:SetAttribute("Locker_" .. itemId, (data.Locker or {})[itemId] or 0)
	end
	-- Bestiario: entidades encontradas ("Cart,Mannequin", para el panel BESTIARIO)
	local found = {}
	for entityId, has in data.Bestiary or {} do
		if has then
			table.insert(found, entityId)
		end
	end
	table.sort(found)
	player:SetAttribute("Bestiary", table.concat(found, ","))
end

local function sanitize(data: PlayerData)
	local raw = data :: any
	data.SessionLock = nil

	-- Migracion v1 -> v2: el dinero, las mejoras y los objetos pasaron a ser por partida,
	-- y las clases ahora van en slots (se conserva la que tenias equipada).
	if (raw.Version or 1) < 2 then
		local oldClass = raw.EquippedClass
		raw.ClassSlots = { if type(oldClass) == "string" and Config.Classes[oldClass] then oldClass else Config.DefaultClass }
		raw.Version = 2
	end
	raw.Money = nil
	raw.Upgrades = nil
	raw.Inventory = nil
	raw.OwnedClasses = nil
	raw.EquippedClass = nil
	raw.PendingClass = nil

	-- Migracion v2 -> v3: los logros pasan a reclamarse a mano. Los que ya estaban
	-- desbloqueados se pagaron solos al conseguirlos: quedan como reclamados.
	if (raw.Version or 1) < 3 then
		raw.ClaimedAchievements = raw.ClaimedAchievements or {}
		for achievementId, unlocked in raw.Achievements or {} do
			if unlocked then
				raw.ClaimedAchievements[achievementId] = true
			end
		end
		raw.Version = 3
	end

	Util.reconcile(raw, Config.DefaultData :: any)

	-- Todos los slots desbloqueados tienen clase (los nuevos empiezan con la por defecto)
	data.MaxSlots = math.clamp(data.MaxSlots, Config.Roulette.DefaultSlots, Config.Roulette.MaxSlots)
	local slots = {}
	for i = 1, data.MaxSlots do
		local className = data.ClassSlots[i]
		slots[i] = if className and Config.Classes[className] then className else Config.DefaultClass
	end
	data.ClassSlots = slots
	if not data.ClassSlots[data.EquippedSlot] then
		data.EquippedSlot = 1
	end

	-- Mejoras permanentes: solo las que existen y sin pasar su nivel maximo
	local permanent = {}
	for upgradeId, level in data.PermanentUpgrades do
		local upgrade = Config.PermanentUpgrades[upgradeId]
		if upgrade and type(level) == "number" and level > 0 then
			permanent[upgradeId] = math.min(math.floor(level), #upgrade.Costs)
		end
	end
	data.PermanentUpgrades = permanent
	data.UpgradePoints = math.max(0, math.floor(data.UpgradePoints))

	-- Maestria: solo clases que existen, con un numero de noches valido
	local mastery = {}
	for className, nights in data.ClassMastery do
		if Config.Classes[className] and type(nights) == "number" and nights > 0 then
			mastery[className] = math.floor(nights)
		end
	end
	data.ClassMastery = mastery

	-- Taquilla: solo objetos que se venden en ella, sin pasar su maximo
	local locker = {}
	for itemId, count in data.Locker do
		local entry = Config.Locker.Items[itemId]
		if entry and type(count) == "number" and count > 0 then
			locker[itemId] = math.min(math.floor(count), entry.Max)
		end
	end
	data.Locker = locker

	-- Bestiario: solo entidades que existen
	local bestiary = {}
	for entityId, has in data.Bestiary do
		if has == true and Config.Bestiary.Entries[entityId] then
			bestiary[entityId] = true
		end
	end
	data.Bestiary = bestiary
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

	if RunService:IsStudio() and (Config.Debug.StudioBonusDiamonds or 0) > 0 then
		data.Diamonds += Config.Debug.StudioBonusDiamonds
	end
	local masteryNights = Config.Debug.StudioMasteryNights
	if RunService:IsStudio() and masteryNights and masteryNights > 0 then
		for className in Config.Classes do
			data.ClassMastery[className] = math.max(data.ClassMastery[className] or 0, masteryNights)
		end
	end

	local bestiaryDebug = Config.Debug.StudioBestiary
	if RunService:IsStudio() and bestiaryDebug == "All" then
		for entityId in Config.Bestiary.Entries do
			data.Bestiary[entityId] = true
		end
	elseif RunService:IsStudio() and bestiaryDebug == "Empty" then
		data.Bestiary = {}
	end

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

function DataService.GetEquippedClass(player: Player): string
	local data = profiles[player]
	return if data then equippedClassOf(data) else Config.DefaultClass
end

----------------------------------------------------------------------
-- Diamantes (moneda permanente)
----------------------------------------------------------------------

-- paid = true si vienen de una compra con Robux.
function DataService.AddDiamonds(player: Player, amount: number, paid: boolean?)
	local data = profiles[player]
	if not data or amount <= 0 then
		return
	end
	amount = math.floor(amount)
	data.Diamonds += amount
	if paid then
		data.PaidDiamonds += amount
	else
		data.Lifetime.DiamondsEarned += amount
	end
	pushAttributes(player, data)
end

-- Diamantes que puede gastar en algo aleatorio (la ruleta).
-- Si su pais restringe objetos aleatorios pagados, solo cuentan los ganados jugando.
function DataService.GetSpendableDiamonds(player: Player, paidRandomRestricted: boolean): number
	local data = profiles[player]
	if not data then
		return 0
	end
	return if paidRandomRestricted then math.max(0, data.Diamonds - data.PaidDiamonds) else data.Diamonds
end

function DataService.TrySpendDiamonds(player: Player, amount: number, paidRandomRestricted: boolean): boolean
	local data = profiles[player]
	if not data or amount < 0 or DataService.GetSpendableDiamonds(player, paidRandomRestricted) < amount then
		return false
	end
	amount = math.floor(amount)
	data.Diamonds -= amount
	if not paidRandomRestricted then
		-- Se gastan primero los comprados, para que los ganados sigan sirviendo en cualquier pais
		data.PaidDiamonds = math.max(0, data.PaidDiamonds - amount)
	end
	data.PaidDiamonds = math.min(data.PaidDiamonds, data.Diamonds)
	pushAttributes(player, data)
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
