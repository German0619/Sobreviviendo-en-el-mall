-- EventDirector: lanza los eventos de la noche (Config.Events / Config.EventDirector).
--
-- * Uno cada 2-3 minutos, como mucho 1 activo, con enfriamiento por evento.
-- * Cuantos hay cada noche se decide al empezarla (Config.EventDirector.PerNight):
--   noches 1-4 como mucho 1, 5-10 como mucho 2, 11+ tres (2 negativos seguros).
-- * Los negativos pesan algo mas; los positivos, cada vez menos con las noches.
-- * Cada evento se anuncia con texto y sonido (el HUD lee los atributos Event* de
--   GameState) y puede ocurrir en una planta concreta (la de mas jugadores, con azar).
-- * Cada evento es un modulo en server/Events/<Id>:
--     return {
--       CanStart = function(ctx) -> boolean,   -- opcional
--       Start = function(ctx) -> cleanup?,     -- cleanup() deshace todo al terminar
--     }
--   ctx = { Id, Def, Night, Floor (1|2|nil), Ended, Finish(), SetEndsAt(segundos|nil) }
--   Si el Def tiene Duration, el director lo termina solo a ese tiempo; si no, el
--   evento llama a ctx.Finish() cuando se resuelve.
--
-- Atributos de GameState: EventId, EventName, EventKind, EventFloor, EventEndsAt
-- (hora del servidor; 0 = hasta que se resuelva).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local GameState = require(Shared.GameState)
local Util = require(Shared.Util)

local EventsFolder = script.Parent:WaitForChild("Events")

local EventDirector = {}

local modules = {}
for id in Config.Events do
	local module = EventsFolder:FindFirstChild(id)
	if module then
		modules[id] = require(module)
	else
		warn("[EventDirector] Evento sin modulo:", id)
	end
end

local rng = Random.new()
local token = 0
local active = nil -- { Ctx, Cleanup }
local lastUsed: { [string]: number } = {}
local lastEndedAt = 0
local eventsThisNight = 0

local FLOOR_NAMES = { "planta baja", "planta alta" }

local function clearState()
	for _, name in { "EventId", "EventName", "EventKind", "EventFloor", "EventEndsAt" } do
		GameState.Folder:SetAttribute(name, nil)
	end
end

local function finishActive()
	local current = active
	if not current then
		return
	end
	active = nil
	current.Ctx.Ended = true
	if RunService:IsStudio() then
		print("[EventDirector] Termina:", current.Ctx.Id)
	end
	if current.Cleanup then
		local ok, err = pcall(current.Cleanup)
		if not ok then
			warn("[EventDirector] Error terminando", current.Ctx.Id, err)
		end
	end
	clearState()
	lastEndedAt = os.clock()
end

-- Planta con mas jugadores vivos (con algo de azar si estan repartidos).
local function pickFloor(): number
	local counts = { 0, 0 }
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root and player:GetAttribute("Alive") == true then
			local floor = Config.getFloor(root.Position.Y)
			counts[floor] += 1
		end
	end
	local total = counts[1] + counts[2]
	if total == 0 then
		return rng:NextInteger(1, 2)
	end
	return if rng:NextNumber() * total < counts[1] then 1 else 2
end

local function eligible(night: number): { string }
	local only = Config.Debug.OnlyEvents
	local now = os.clock()
	local list = {}
	for id, def in Config.Events do
		if modules[id] and (only == nil or table.find(only, id)) then
			local cooled = only ~= nil or lastUsed[id] == nil or now - lastUsed[id] >= (def.Cooldown or 0)
			if night >= (def.MinNight or 1) and cooled then
				table.insert(list, id)
			end
		end
	end
	table.sort(list)
	-- Probando (OnlyEvents): no repetir hasta que hayan salido todos
	if only ~= nil then
		local unused = {}
		for _, id in list do
			if lastUsed[id] == nil then
				table.insert(unused, id)
			end
		end
		if #unused > 0 then
			return unused
		end
		lastUsed = {}
	end
	return list
end

local function startEvent(id: string, night: number): boolean
	local def = Config.Events[id]
	local module = modules[id]
	local ctx = {
		Id = id,
		Def = def,
		Night = night,
		Floor = if def.Floor then pickFloor() else nil,
		Ended = false,
	}
	function ctx.Finish()
		if active and active.Ctx == ctx then
			finishActive()
		end
	end
	function ctx.SetEndsAt(seconds: number?)
		if not ctx.Ended then
			GameState.Folder:SetAttribute("EventEndsAt", if seconds then Workspace:GetServerTimeNow() + seconds else 0)
		end
	end
	if module.CanStart and not module.CanStart(ctx) then
		return false
	end

	active = { Ctx = ctx }
	GameState.Folder:SetAttribute("EventId", id)
	GameState.Folder:SetAttribute("EventName", def.DisplayName)
	GameState.Folder:SetAttribute("EventKind", def.Kind)
	GameState.Folder:SetAttribute("EventFloor", ctx.Floor)
	GameState.Folder:SetAttribute("EventEndsAt", 0)
	local where = if ctx.Floor then " (" .. FLOOR_NAMES[ctx.Floor] .. ")" else ""
	if RunService:IsStudio() then
		print(string.format("[EventDirector] Empieza: %s%s", id, where))
	end
	Remotes.event("Notify"):FireAllClients(
		string.format("EVENTO: %s%s. %s", def.DisplayName, where, def.Description or ""),
		"event"
	)

	local ok, cleanup = pcall(module.Start, ctx)
	if not ok then
		warn("[EventDirector] Error iniciando", id, cleanup)
		active = nil
		clearState()
		return false
	end
	if ctx.Ended then
		-- Se resolvio dentro de Start (p. ej. sin sitio donde ocurrir)
		if cleanup then
			pcall(cleanup)
		end
	else
		active.Cleanup = cleanup
		if def.Duration then
			ctx.SetEndsAt(def.Duration)
			task.delay(def.Duration, ctx.Finish)
		end
	end
	lastUsed[id] = os.clock()
	eventsThisNight += 1
	return true
end

-- Multiplicador de peso por tipo: los negativos algo mas; los positivos, cada vez menos.
local function kindMultiplier(kind: string?, night: number): number
	local cfg = Config.EventDirector
	if kind == "Bad" then
		return cfg.BadWeightMultiplier
	elseif kind == "Good" then
		return math.max(cfg.GoodMin, 1 - cfg.GoodFadePerNight * (night - 1))
	end
	return 1
end

-- requiredKind: "Bad" = solo negativos; "Any" = cualquiera.
local function pickEvent(night: number, requiredKind: string): string?
	local weights = {}
	for _, id in eligible(night) do
		local def = Config.Events[id]
		if requiredKind ~= "Bad" or def.Kind == "Bad" then
			weights[id] = (def.Weight or 1) * kindMultiplier(def.Kind, night)
		end
	end
	return Util.weightedRandom(weights, rng)
end

-- Huecos de evento de la noche (ver Config.EventDirector.PerNight): lista de "Bad" | "Any".
-- nil = sin limite (probando con Config.Debug.OnlyEvents).
local function planNight(night: number): { string }?
	if Config.Debug.OnlyEvents ~= nil then
		return nil
	end
	local rule = nil
	for _, r in Config.EventDirector.PerNight do
		if night <= r.UpToNight then
			rule = r
			break
		end
	end
	if not rule then
		return {}
	end
	local slots = {}
	for _ = 1, rule.Max do
		if rng:NextNumber() < rule.Chance then
			table.insert(slots, "Any")
		end
	end
	for i = 1, math.min(rule.GuaranteedBad or 0, #slots) do
		slots[i] = "Bad"
	end
	-- Orden al azar (los negativos asegurados no van siempre primero)
	for i = #slots, 2, -1 do
		local j = rng:NextInteger(1, i)
		slots[i], slots[j] = slots[j], slots[i]
	end
	return slots
end

----------------------------------------------------------------------
-- API
----------------------------------------------------------------------

function EventDirector.StartNight(night: number)
	EventDirector.StopNight()
	token += 1
	local myToken = token
	lastUsed = {}
	eventsThisNight = 0
	lastEndedAt = 0

	local cfg = Config.EventDirector
	local override = Config.Debug.EventDelayOverride
	local plan = planNight(night)
	if RunService:IsStudio() then
		print(string.format("[EventDirector] Noche %d: %s", night, if plan then (if #plan > 0 then table.concat(plan, ", ") else "sin eventos") else "sin limite (OnlyEvents)"))
	end
	task.spawn(function()
		local nextAt = os.clock() + (override or cfg.FirstDelay)
		local slot = 1
		while token == myToken do
			task.wait(1)
			if token ~= myToken or (plan and slot > #plan) then
				break -- ya salieron todos los de esta noche
			end
			if active then
				continue
			end
			local gap = override or cfg.GapAfterEnd
			if lastEndedAt > 0 then
				nextAt = math.max(nextAt, lastEndedAt + gap)
			end
			if os.clock() >= nextAt then
				local id = pickEvent(night, if plan then plan[slot] else "Any")
				if id and startEvent(id, night) then
					slot += 1
					nextAt = os.clock() + (override or rng:NextNumber(cfg.Interval[1], cfg.Interval[2]))
				else
					nextAt = os.clock() + 10
				end
			end
		end
	end)
end

function EventDirector.StopNight()
	token += 1
	finishActive()
	clearState()
end

-- Para probar desde la consola del servidor: EventDirector.Force("Fog")
function EventDirector.Force(id: string): boolean
	if active or not Config.Events[id] or not modules[id] then
		return false
	end
	return startEvent(id, GameState.Folder:GetAttribute("Night") or 1)
end

function EventDirector.Start()
	clearState()
end

return EventDirector
