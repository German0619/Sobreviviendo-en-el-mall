--!strict
-- PlayerStats: calcula las estadisticas finales de cada jugador y las aplica.
--
--   final = (Base + PerLevel * nivel) * modificador de clase * efectos temporales
--
-- Las estadisticas se publican como atributos del Player para que el cliente
-- (HUD, linterna, sprint) las lea:
--   MaxHealth, MaxStamina, MaxBattery, WalkSpeed, SprintSpeed
-- Las banderas de efectos temporales (sodas) se publican como "Flag_<Nombre>".

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Types = require(Shared.Types)
local Remotes = require(Shared.Remotes)
local GameState = require(Shared.GameState)

local DataService = require(script.Parent.DataService)
local RunState = require(script.Parent.RunState)

type ComputedStats = Types.ComputedStats

type Effect = {
	Modifiers: { [string]: number },
	Flags: { [string]: any },
	Token: number,
}

local PlayerStats = {}

local effects: { [Player]: { [string]: Effect } } = {}
local publishedFlags: { [Player]: { [string]: boolean } } = {}
local publishedPerks: { [Player]: { [string]: boolean } } = {}
local effectCounter = 0

local function getClassDef(player: Player): Types.ClassDef
	local className = DataService.GetEquippedClass(player)
	return Config.Classes[className] or Config.Classes[Config.DefaultClass]
end

----------------------------------------------------------------------
-- Calculo
----------------------------------------------------------------------

function PlayerStats.GetLevel(player: Player, statName: string): number
	return RunState.GetUpgrade(player, statName)
end

function PlayerStats.Compute(player: Player): ComputedStats
	local classDef = getClassDef(player)
	local playerEffects = effects[player]
	local result = {} :: { [string]: number }

	for statName, stat in Config.Stats do
		local value = stat.Base + stat.PerLevel * PlayerStats.GetLevel(player, statName)
		value *= classDef.Modifiers[statName] or 1
		if playerEffects then
			for _, effect in playerEffects do
				value *= effect.Modifiers[statName] or 1
			end
		end
		result[statName] = value
	end

	return (result :: any) :: ComputedStats
end

-- Habilidad pasiva de la clase equipada (nil si no la tiene).
function PlayerStats.GetPerk(player: Player, perkName: string): any
	return getClassDef(player).Perks[perkName]
end

-- Bandera activa por efecto temporal (sodas) o por la clase.
function PlayerStats.HasFlag(player: Player, flagName: string): any
	local playerEffects = effects[player]
	if playerEffects then
		for _, effect in playerEffects do
			if effect.Flags[flagName] ~= nil then
				return effect.Flags[flagName]
			end
		end
	end
	return PlayerStats.GetPerk(player, flagName)
end

----------------------------------------------------------------------
-- Aplicar al jugador / personaje
----------------------------------------------------------------------

local function publishFlags(player: Player)
	local active: { [string]: boolean } = {}
	local playerEffects = effects[player]
	if playerEffects then
		for _, effect in playerEffects do
			for flag in effect.Flags do
				active[flag] = true
			end
		end
	end

	local previous = publishedFlags[player] or {}
	for flag in previous do
		if not active[flag] then
			player:SetAttribute("Flag_" .. flag, nil)
		end
	end
	for flag in active do
		player:SetAttribute("Flag_" .. flag, PlayerStats.HasFlag(player, flag))
	end
	publishedFlags[player] = active
end

-- Habilidades de la clase equipada como atributos "Perk_<Nombre>" (las usa el cliente).
local function publishPerks(player: Player)
	local perks = getClassDef(player).Perks
	local previous = publishedPerks[player] or {}
	for perk in previous do
		if perks[perk] == nil then
			player:SetAttribute("Perk_" .. perk, nil)
		end
	end
	local current: { [string]: boolean } = {}
	for perk, value in perks do
		player:SetAttribute("Perk_" .. perk, value)
		current[perk] = true
	end
	publishedPerks[player] = current
end

function PlayerStats.Apply(player: Player)
	if not DataService.GetData(player) then
		return
	end

	local stats = PlayerStats.Compute(player)

	player:SetAttribute("MaxHealth", stats.Health)
	player:SetAttribute("MaxStamina", stats.Stamina)
	player:SetAttribute("MaxBattery", stats.Battery)
	player:SetAttribute("WalkSpeed", stats.WalkSpeed)
	player:SetAttribute("SprintSpeed", stats.WalkSpeed * Config.Movement.SprintMultiplier)
	for statName in Config.Stats do
		player:SetAttribute("Level_" .. statName, PlayerStats.GetLevel(player, statName))
	end
	publishFlags(player)
	publishPerks(player)

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		-- Mantener el mismo porcentaje de vida al cambiar la vida maxima.
		local ratio = if humanoid.MaxHealth > 0 then humanoid.Health / humanoid.MaxHealth else 1
		humanoid.MaxHealth = stats.Health
		humanoid.Health = math.clamp(stats.Health * ratio, 1, stats.Health)
		humanoid.WalkSpeed = stats.WalkSpeed
	end
end

local function onCharacterAdded(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if not humanoid or not DataService.GetData(player) then
		return
	end
	local stats = PlayerStats.Compute(player)
	-- Al revivir se vuelve con parte de la vida (lo fija ReviveService antes de reaparecer).
	local fraction = player:GetAttribute("SpawnHealthFraction")
	player:SetAttribute("SpawnHealthFraction", nil)
	humanoid.MaxHealth = stats.Health
	humanoid.Health = stats.Health * (if type(fraction) == "number" then fraction else 1)
	PlayerStats.Apply(player)
end

----------------------------------------------------------------------
-- Efectos temporales (sodas, items...)
----------------------------------------------------------------------

-- Agrega (o reemplaza) un efecto. Devuelve una funcion para quitarlo antes.
function PlayerStats.AddEffect(
	player: Player,
	effectId: string,
	modifiers: { [string]: number }?,
	flags: { [string]: any }?,
	duration: number?
): () -> ()
	effectCounter += 1
	local token = effectCounter

	local playerEffects = effects[player] or {}
	effects[player] = playerEffects
	playerEffects[effectId] = {
		Modifiers = modifiers or {},
		Flags = flags or {},
		Token = token,
	}
	PlayerStats.Apply(player)

	local function remove()
		local list = effects[player]
		local current = list and list[effectId]
		-- Solo quitar si no fue reemplazado por una version mas nueva.
		if list and current and current.Token == token then
			list[effectId] = nil
			if player.Parent then
				PlayerStats.Apply(player)
			end
		end
	end

	if duration then
		task.delay(duration, remove)
	end
	return remove
end

function PlayerStats.ClearEffects(player: Player)
	effects[player] = nil
	PlayerStats.Apply(player)
end

----------------------------------------------------------------------
-- Mejoras
----------------------------------------------------------------------

-- Compra un nivel de `statName`. Devuelve (exito, motivo).
function PlayerStats.TryUpgrade(player: Player, statName: string): (boolean, string?)
	if type(statName) ~= "string" or not Config.Stats[statName] then
		return false, "Estadistica invalida"
	end
	local data = DataService.GetData(player)
	if not data then
		return false, "Datos no cargados"
	end
	if GameState.Folder:GetAttribute("Phase") == "Night" then
		return false, "No puedes mejorar durante la noche"
	end

	local level = RunState.GetUpgrade(player, statName)
	local cost = Config.getUpgradeCost(statName, level)
	if not cost then
		return false, "Nivel maximo"
	end
	if not RunState.TrySpend(player, cost) then
		return false, "Billetes insuficientes"
	end

	RunState.SetUpgrade(player, statName, level + 1)
	PlayerStats.Apply(player)
	return true, nil
end

----------------------------------------------------------------------
-- Arranque
----------------------------------------------------------------------

function PlayerStats.Start()
	DataService.ProfileLoaded:Connect(function(player: Player)
		player.CharacterAdded:Connect(function(character)
			onCharacterAdded(player, character)
		end)
		if player.Character then
			task.spawn(onCharacterAdded, player, player.Character)
		end
		PlayerStats.Apply(player)
	end)

	-- Partida nueva: las mejoras vuelven a 0
	RunState.Reset:Connect(PlayerStats.Apply)

	Players.PlayerRemoving:Connect(function(player)
		effects[player] = nil
		publishedFlags[player] = nil
		publishedPerks[player] = nil
	end)

	-- Anti-spam simple para el remote de mejoras
	local lastRequest: { [Player]: number } = {}
	Remotes.func("RequestUpgrade").OnServerInvoke = function(player: Player, statName: any)
		local now = os.clock()
		if lastRequest[player] and now - lastRequest[player] < 0.25 then
			return false, "Demasiado rapido"
		end
		lastRequest[player] = now
		return PlayerStats.TryUpgrade(player, statName)
	end
	Players.PlayerRemoving:Connect(function(player)
		lastRequest[player] = nil
	end)
end

return PlayerStats
