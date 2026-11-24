-- ClassService: ruleta de clases, slots y diamantes ganados jugando.
--
-- * La ruleta cuesta diamantes y da una clase al azar (Config.Roulette.Weights).
--   La clase que sale REEMPLAZA automaticamente a la del slot equipado,
--   sea mejor o peor.
-- * Free to play = 1 slot; mas slots se compran con Robux (MonetizationService).
--   Cada slot nuevo empieza con la clase por defecto.
-- * Antes de la partida eliges que slot usar (solo fuera de la noche).
--   Para cambiar la clase de otro slot: equipalo y gira.
-- * Politica de Roblox: si el pais del jugador restringe objetos aleatorios
--   pagados, solo puede girar con diamantes ganados jugando.
-- * Diamantes gratis: cada N noches sobrevividas y con logros.
--
-- La ruleta y los slots se usan en el LOBBY. En el mall solo se permiten en
-- Studio para probar (Config.Debug.ClassesInMallInStudio). Los diamantes por
-- noches y logros se dan en el mall.

local Players = game:GetService("Players")
local PolicyService = game:GetService("PolicyService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local Remotes = require(Shared.Remotes)
local GameState = require(Shared.GameState)
local Place = require(Shared.Place)

local DataService = require(script.Parent.DataService)
local PlayerStats = require(script.Parent.PlayerStats)

local ClassService = {}

local rng = Random.new()
local restricted = {} -- [Player] = boolean (PaidRandomItemsRestricted)
local lastRequest = {} -- [Player] = os.clock()

local function notify(player: Player, message: string, kind: string?)
	Remotes.event("Notify"):FireClient(player, message, kind or "info")
end

local function isNight(): boolean
	return GameState.Folder:GetAttribute("Phase") == "Night"
end

-- Ante la duda (error consultando la politica), se trata como restringido.
local function loadPolicy(player: Player)
	local ok, info = pcall(function()
		return PolicyService:GetPolicyInfoForPlayerAsync(player)
	end)
	local isRestricted = not ok or (info and info.ArePaidRandomItemsRestricted == true)
	restricted[player] = isRestricted
	player:SetAttribute("PaidRandomRestricted", isRestricted)
end

function ClassService.IsRestricted(player: Player): boolean
	return restricted[player] ~= false
end

-- Probabilidades en porcentaje (para mostrarlas). Ordenadas como Config.ClassOrder.
function ClassService.GetOdds(): { { Class: string, Percent: number } }
	local total = 0
	for _, w in Config.Roulette.Weights do
		total += w
	end
	local list = {}
	for _, className in Config.ClassOrder do
		local w = Config.Roulette.Weights[className] or 0
		table.insert(list, { Class = className, Percent = w / total * 100 })
	end
	return list
end

----------------------------------------------------------------------
-- Ruleta y slots
----------------------------------------------------------------------

function ClassService.Spin(player: Player): (boolean, string, string?)
	local data = DataService.GetData(player)
	if not data then
		return false, "Datos no cargados", nil
	end
	if not Place.ClassesEnabledHere() then
		return false, "La ruleta está en el lobby", nil
	end
	if isNight() then
		return false, "La ruleta no está disponible durante la noche", nil
	end
	if not DataService.TrySpendDiamonds(player, Config.Roulette.SpinCost, ClassService.IsRestricted(player)) then
		if ClassService.IsRestricted(player) and data.Diamonds >= Config.Roulette.SpinCost then
			return false, "En tu país solo puedes girar con diamantes ganados jugando", nil
		end
		return false, "Diamantes insuficientes", nil
	end

	local className = Util.weightedRandom(Config.Roulette.Weights, rng) or Config.DefaultClass
	local slot = data.EquippedSlot
	local previous = data.ClassSlots[slot] or Config.DefaultClass

	-- Reemplaza la clase del slot equipado, sea mejor o peor
	DataService.Update(player, function(d)
		d.ClassSlots[slot] = className
	end)
	PlayerStats.Apply(player)
	DataService.Save(player) -- que no se pierda el giro si se cae el servidor

	return true,
		string.format(
			"¡Obtuviste %s! Reemplazó a %s en el slot %d.",
			Config.Classes[className].DisplayName,
			Config.Classes[previous].DisplayName,
			slot
		),
		className
end

function ClassService.EquipSlot(player: Player, slot: any): (boolean, string)
	local data = DataService.GetData(player)
	if not data then
		return false, "Datos no cargados"
	end
	if not Place.ClassesEnabledHere() then
		return false, "Los slots se cambian en el lobby"
	end
	if isNight() then
		return false, "No puedes cambiar de clase durante la noche"
	end
	if type(slot) ~= "number" or not data.ClassSlots[slot] then
		return false, "Slot vacío"
	end
	DataService.Update(player, function(d)
		d.EquippedSlot = slot
	end)
	PlayerStats.Apply(player)
	return true, "Clase equipada: " .. Config.Classes[data.ClassSlots[slot]].DisplayName
end

----------------------------------------------------------------------
-- Diamantes ganados jugando
----------------------------------------------------------------------

function ClassService.CheckAchievements(player: Player)
	local data = DataService.GetData(player)
	if not data then
		return
	end
	for achievementId, achievement in Config.Achievements do
		if not data.Achievements[achievementId] and achievement.BestNight and data.BestNight >= achievement.BestNight then
			DataService.Update(player, function(d)
				d.Achievements[achievementId] = true
			end)
			local reward = achievement.Diamonds or 0
			DataService.AddDiamonds(player, reward, false)
			notify(player, string.format("Logro: %s  (+%d diamantes)", achievement.DisplayName, reward), "good")
		end
	end
end

-- Llamar cuando el jugador sobrevive una noche (despues de sumar NightsSurvived).
function ClassService.OnNightSurvived(player: Player)
	local data = DataService.GetData(player)
	if not data then
		return
	end
	local every = Config.Diamonds.MilestoneNights
	if every > 0 and data.Lifetime.NightsSurvived % every == 0 then
		DataService.AddDiamonds(player, Config.Diamonds.MilestoneReward, false)
		notify(
			player,
			string.format("¡%d noches sobrevividas! +%d diamantes", data.Lifetime.NightsSurvived, Config.Diamonds.MilestoneReward),
			"good"
		)
	end
	ClassService.CheckAchievements(player)
end

----------------------------------------------------------------------
-- Arranque
----------------------------------------------------------------------

local function throttled(player: Player): boolean
	local now = os.clock()
	if lastRequest[player] and now - lastRequest[player] < 0.4 then
		return true
	end
	lastRequest[player] = now
	return false
end

function ClassService.Start()
	Remotes.func("RequestSpin").OnServerInvoke = function(player: Player)
		if throttled(player) then
			return false, "Demasiado rápido", nil
		end
		return ClassService.Spin(player)
	end
	Remotes.func("RequestEquipSlot").OnServerInvoke = function(player: Player, slot: any)
		if throttled(player) then
			return false, "Demasiado rápido"
		end
		return ClassService.EquipSlot(player, slot)
	end

	Players.PlayerAdded:Connect(loadPolicy)
	for _, player in Players:GetPlayers() do
		task.spawn(loadPolicy, player)
	end
	DataService.ProfileLoaded:Connect(ClassService.CheckAchievements)

	Players.PlayerRemoving:Connect(function(player)
		lastRequest[player] = nil
		restricted[player] = nil
	end)
end

return ClassService
