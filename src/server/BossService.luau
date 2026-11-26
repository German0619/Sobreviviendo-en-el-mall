-- BossService: las noches de jefe (Config.Bosses). Cada Every noches sale un jefe, en
-- el orden de Config.Bosses.Order. Despues del ultimo (noche 20) salen DOS a la vez
-- (Config.Bosses.Pairs) y cada vuelta por las parejas los refuerza (Config.Bosses.Scaling).
-- Cada jefe es un modulo en server/Bosses/<Id>:
--     return { Start = function(ctx) -> cleanup? }
--   ctx = { Id, Def, Night, Round, SpeedBoost, Ended, Defeated, Defeat(), SetProgress(texto) }
--   * Def es una COPIA de Config.Bosses[Id] ya reforzada: su ExtraField (radios, objetos,
--     servidores, apagones) sube y sus FasterFields (tiempos) bajan.
--   * SpeedBoost: multiplicador de velocidad de su cuerpo (enemy.BossSpeed).
-- El modulo decide como se le vence y llama a ctx.Defeat(). La noche se gana cuando
-- estan vencidos TODOS los jefes de la noche; cada uno da su premio al vencerlo.
--
-- NightManager: en la noche de jefe usa la mitad del presupuesto de enemigos y de tareas,
-- no lanza eventos al azar y no da la noche por ganada hasta que los jefes estan vencidos.
--
-- Atributos de GameState (los lee el HUD y la alerta del cliente): BossId, BossName,
-- BossObjective, BossProgress, BossDefeated (con dos jefes: nombres y objetivos juntos y
-- el progreso de cada uno).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local GameState = require(Shared.GameState)
local Util = require(Shared.Util)

local DataService = require(script.Parent.DataService)
local RunState = require(script.Parent.RunState)
local BestiaryService = require(script.Parent.BestiaryService)

local BossesFolder = script.Parent:WaitForChild("Bosses")

local BossService = {}

local modules = {}
for _, id in Config.Bosses.Order do
	local module = BossesFolder:FindFirstChild(id)
	if module then
		modules[id] = require(module)
	end
end

-- Jefes de la noche en curso: { { Ctx, Cleanup } }
local active: { { Ctx: any, Cleanup: any } } = {}

local ATTRIBUTES = { "BossId", "BossName", "BossObjective", "BossProgress", "BossDefeated" }

local function clearState()
	for _, name in ATTRIBUTES do
		GameState.Folder:SetAttribute(name, nil)
	end
end

-- Vuelta por las parejas (0 = aun estan los jefes de uno en uno, 1 = noches 25-40...).
local function roundFor(night: number): number
	local cfg = Config.Bosses
	local index = night // cfg.Every -- 1 = noche 5
	if index <= #cfg.Order then
		return 0
	end
	return (index - #cfg.Order - 1) // #cfg.Pairs + 1
end

-- Jefes de esa noche (lista vacia si es una noche normal).
-- Config.Debug.ForceBoss: "Luni" o { "Luni", "Manager" } en TODAS las noches.
function BossService.GetBossesFor(night: number): { string }
	local list = {}
	local forced = Config.Debug.ForceBoss
	if forced then
		for _, id in (if type(forced) == "table" then forced else { forced }) :: { string } do
			if modules[id] then
				table.insert(list, id)
			end
		end
		return list
	end
	local cfg = Config.Bosses
	if night < cfg.Every or night % cfg.Every ~= 0 then
		return list
	end
	local index = night // cfg.Every
	local ids
	if index <= #cfg.Order then
		ids = { cfg.Order[index] }
	else
		ids = cfg.Pairs[(index - #cfg.Order - 1) % #cfg.Pairs + 1]
	end
	for _, id in ids do
		if modules[id] then
			table.insert(list, id)
		end
	end
	return list
end

local scaledDef: (id: string, round: number) -> (any, number)

-- Objetivo de un jefe ya reforzado: {n} = su ExtraField (radios, objetos...). Si tiene
-- ObjectiveMany (Luni) y le hace falta mas de uno, se usa ese.
local function objectiveOf(def): string
	local n = if def.ExtraField then def[def.ExtraField] else nil
	local text = if def.ObjectiveMany and type(n) == "number" and n > 1 then def.ObjectiveMany else def.Objective
	return (string.gsub(text, "{n}", tostring(n or "")))
end

-- Nombre y objetivo juntos de los jefes de una noche (para los avisos y la alerta).
function BossService.Describe(ids: { string }, night: number): (string, string)
	local round = roundFor(night)
	local names, objectives = {}, {}
	for _, id in ids do
		local def = scaledDef(id, round)
		table.insert(names, def.DisplayName)
		local objective = objectiveOf(def)
		table.insert(objectives, if #ids > 1 then def.DisplayName .. ": " .. objective else objective)
	end
	return table.concat(names, " y "), table.concat(objectives, "\n")
end

-- Todos los jefes de la noche vencidos.
function BossService.IsDefeated(): boolean
	if #active == 0 then
		return false
	end
	for _, entry in active do
		if not entry.Ctx.Defeated then
			return false
		end
	end
	return true
end

-- Copia de la definicion de un jefe con el refuerzo de la vuelta.
function scaledDef(id: string, round: number): (any, number)
	local def = table.clone(Config.Bosses[id])
	local s = Config.Bosses.Scaling
	local speed = 1 + math.min(s.SpeedPerRound * round, s.MaxSpeed)
	local extra = math.min(s.ExtraPerRound * round, s.MaxExtra)
	if def.ExtraField and type(def[def.ExtraField]) == "number" then
		def[def.ExtraField] += extra
	end
	for _, field in def.FasterFields or {} do
		if type(def[field]) == "number" then
			def[field] /= speed
		end
	end
	return def, speed
end

-- Premio al vencerlo: billetes para todos, el contador de jefes y el de ese jefe (logro).
-- Si ya lo habia vencido antes, el logro ya esta cobrado: recibe al momento
-- RepeatDiamondFraction de los diamantes de ese logro.
local function reward(id: string, def)
	local key = "Boss_" .. id
	local achievement = Config.Achievements["Boss" .. id]
	local repeatDiamonds = if achievement then math.floor(achievement.Diamonds * Config.Bosses.RepeatDiamondFraction) else 0
	for _, player in Players:GetPlayers() do
		local data = DataService.GetData(player)
		if data then
			local before = (data.Lifetime :: any)[key] or 0
			RunState.AddCash(player, def.Reward or 0)
			DataService.Update(player, function(d)
				d.Lifetime.BossesDefeated = (d.Lifetime.BossesDefeated or 0) + 1
				d.Lifetime[key] = ((d.Lifetime :: any)[key] or 0) + 1
			end)
			if before >= 1 and repeatDiamonds > 0 then
				DataService.AddDiamonds(player, repeatDiamonds, false)
				Remotes.event("Notify"):FireClient(player, string.format("Jefe repetido: +%d diamantes.", repeatDiamonds), "good")
			elseif achievement then
				Remotes.event("Notify"):FireClient(
					player,
					string.format("¡Primera vez! Reclama el logro \"%s\" en el lobby (+%d diamantes).", achievement.DisplayName, achievement.Diamonds),
					"good"
				)
			end
		end
	end
	Remotes.event("Notify"):FireAllClients(
		string.format("¡Vencieron a %s! +%s para cada uno.", def.DisplayName, Util.formatMoney(def.Reward or 0)),
		"good"
	)
end

-- Progreso de la noche: el de cada jefe (con dos, "Nombre: progreso" en lineas).
local function publishProgress()
	if #active == 1 then
		local ctx = active[1].Ctx
		GameState.Folder:SetAttribute("BossProgress", ctx.Progress or "")
		return
	end
	local lines = {}
	for _, entry in active do
		local ctx = entry.Ctx
		local name = string.split(ctx.Def.DisplayName, ",")[1] -- "Luni, la mascota" -> "Luni"
		table.insert(lines, string.format("%s: %s", name, if ctx.Defeated then "¡vencido!" else (ctx.Progress or "")))
	end
	GameState.Folder:SetAttribute("BossProgress", table.concat(lines, "\n"))
end

function BossService.StartNight(night: number, ids: { string })
	BossService.StopNight()
	if #ids == 0 then
		return
	end
	local round = roundFor(night)
	local name, objective = BossService.Describe(ids, night)
	if round > 0 then
		name ..= string.format(" (vuelta %d)", round)
	end
	GameState.Folder:SetAttribute("BossId", table.concat(ids, "+"))
	GameState.Folder:SetAttribute("BossName", name)
	GameState.Folder:SetAttribute("BossObjective", objective)
	GameState.Folder:SetAttribute("BossProgress", "")
	GameState.Folder:SetAttribute("BossDefeated", false)
	-- Noche de jefe: todos los presentes lo descubren en el bestiario
	for _, id in ids do
		BestiaryService.DiscoverForAll(id)
	end

	local started = {}
	for _, id in ids do
		local def, speed = scaledDef(id, round)
		local ctx = {
			Id = id,
			Def = def,
			Night = night,
			Round = round,
			SpeedBoost = speed,
			Ended = false,
			Defeated = false,
			Progress = "",
		}
		function ctx.SetProgress(text: string)
			if not ctx.Ended then
				ctx.Progress = text
				publishProgress()
			end
		end
		function ctx.Defeat()
			if ctx.Ended or ctx.Defeated then
				return
			end
			ctx.Defeated = true
			reward(id, def)
			publishProgress()
			if BossService.IsDefeated() then
				GameState.Folder:SetAttribute("BossDefeated", true)
			end
		end
		local entry = { Ctx = ctx, Cleanup = nil }
		table.insert(active, entry)
		table.insert(started, entry)
		if RunService:IsStudio() then
			print(
				string.format(
					"[BossService] Noche %d: jefe %s (vuelta %d, velocidad x%.2f, %s=%s)",
					night,
					id,
					round,
					speed,
					tostring(def.ExtraField),
					tostring(def.ExtraField and def[def.ExtraField])
				)
			)
		end
	end

	for _, entry in started do
		local ctx = entry.Ctx
		local ok, cleanup = pcall(modules[ctx.Id].Start, ctx)
		if ok then
			entry.Cleanup = cleanup
		else
			warn("[BossService] Error iniciando", ctx.Id, cleanup)
			-- Que la noche se pueda ganar igual
			ctx.Defeated = true
		end
	end
	if BossService.IsDefeated() then
		GameState.Folder:SetAttribute("BossDefeated", true)
	end
end

function BossService.StopNight()
	local current = active
	active = {}
	for _, entry in current do
		entry.Ctx.Ended = true
		if entry.Cleanup then
			local ok, err = pcall(entry.Cleanup)
			if not ok then
				warn("[BossService] Error terminando", entry.Ctx.Id, err)
			end
		end
	end
	clearState()
end

-- Lo llama NightManager al pagar una noche sobrevivida. Despues del ultimo jefe (noche
-- Every x #Order), cada Every noches de la partida: PostBossDiamonds diamantes.
function BossService.OnNightSurvived(player: Player, night: number)
	local cfg = Config.Bosses
	local lastBossNight = cfg.Every * #cfg.Order
	if night > lastBossNight and night % cfg.Every == 0 and cfg.PostBossDiamonds > 0 then
		DataService.AddDiamonds(player, cfg.PostBossDiamonds, false)
		Remotes.event("Notify"):FireClient(
			player,
			string.format("¡Noche %d superada! +%d diamantes.", night, cfg.PostBossDiamonds),
			"good"
		)
	end
end

function BossService.Start()
	clearState()
end

return BossService
