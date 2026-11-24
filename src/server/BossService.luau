-- BossService: las noches de jefe (Config.Bosses). Cada Every noches sale un jefe, en
-- el orden de Config.Bosses.Order (y se repiten). Cada jefe es un modulo en
-- server/Bosses/<Id>:
--     return { Start = function(ctx) -> cleanup? }
--   ctx = { Id, Def, Night, Ended, Defeated, Defeat(), SetProgress(texto) }
-- El modulo decide como se le vence y llama a ctx.Defeat().
--
-- NightManager: en la noche de jefe usa la mitad del presupuesto de enemigos y de tareas,
-- no lanza eventos al azar y no da la noche por ganada hasta que el jefe esta vencido.
--
-- Atributos de GameState (los lee el HUD y la alerta del cliente): BossId, BossName,
-- BossObjective, BossProgress, BossDefeated.

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

local BossesFolder = script.Parent:WaitForChild("Bosses")

local BossService = {}

local modules = {}
for _, id in Config.Bosses.Order do
	local module = BossesFolder:FindFirstChild(id)
	if module then
		modules[id] = require(module)
	end
end

local active = nil -- { Ctx, Cleanup }

local ATTRIBUTES = { "BossId", "BossName", "BossObjective", "BossProgress", "BossDefeated" }

local function clearState()
	for _, name in ATTRIBUTES do
		GameState.Folder:SetAttribute(name, nil)
	end
end

-- Jefe de esa noche (o nil si es una noche normal o el jefe aun no esta hecho).
function BossService.GetBossFor(night: number): string?
	local forced = Config.Debug.ForceBoss
	if forced then
		return if modules[forced] then forced else nil
	end
	local cfg = Config.Bosses
	if night < cfg.Every or night % cfg.Every ~= 0 then
		return nil
	end
	local index = (night // cfg.Every - 1) % #cfg.Order + 1
	local id = cfg.Order[index]
	return if modules[id] then id else nil
end

function BossService.IsDefeated(): boolean
	return active ~= nil and active.Ctx.Defeated
end

-- Premio al vencerlo: billetes para todos, el contador de jefes y el de ese jefe (logro).
local function reward(id: string, def)
	for _, player in Players:GetPlayers() do
		if DataService.GetData(player) then
			RunState.AddCash(player, def.Reward or 0)
			DataService.Update(player, function(d)
				d.Lifetime.BossesDefeated = (d.Lifetime.BossesDefeated or 0) + 1
				local key = "Boss_" .. id
				d.Lifetime[key] = ((d.Lifetime :: any)[key] or 0) + 1
			end)
		end
	end
	Remotes.event("Notify"):FireAllClients(
		string.format("¡Vencieron a %s! +%s para cada uno.", def.DisplayName, Util.formatMoney(def.Reward or 0)),
		"good"
	)
end

function BossService.StartNight(night: number, id: string)
	BossService.StopNight()
	local def = Config.Bosses[id]
	local ctx = {
		Id = id,
		Def = def,
		Night = night,
		Ended = false,
		Defeated = false,
	}
	function ctx.SetProgress(text: string)
		if not ctx.Ended then
			GameState.Folder:SetAttribute("BossProgress", text)
		end
	end
	function ctx.Defeat()
		if ctx.Ended or ctx.Defeated then
			return
		end
		ctx.Defeated = true
		GameState.Folder:SetAttribute("BossDefeated", true)
		reward(id, def)
	end

	GameState.Folder:SetAttribute("BossId", id)
	GameState.Folder:SetAttribute("BossName", def.DisplayName)
	GameState.Folder:SetAttribute("BossObjective", def.Objective)
	GameState.Folder:SetAttribute("BossProgress", "")
	GameState.Folder:SetAttribute("BossDefeated", false)
	if RunService:IsStudio() then
		print(string.format("[BossService] Noche %d: jefe %s", night, id))
	end

	active = { Ctx = ctx }
	local ok, cleanup = pcall(modules[id].Start, ctx)
	if not ok then
		warn("[BossService] Error iniciando", id, cleanup)
		-- Que la noche se pueda ganar igual
		ctx.Defeated = true
		GameState.Folder:SetAttribute("BossDefeated", true)
		return
	end
	active.Cleanup = cleanup
end

function BossService.StopNight()
	local current = active
	active = nil
	if current then
		current.Ctx.Ended = true
		if current.Cleanup then
			local ok, err = pcall(current.Cleanup)
			if not ok then
				warn("[BossService] Error terminando", current.Ctx.Id, err)
			end
		end
	end
	clearState()
end

function BossService.Start()
	clearState()
end

return BossService
