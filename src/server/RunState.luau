--!strict
-- RunState: lo que dura UNA partida (no se guarda en DataStore).
--   * Billetes ($): se ganan cada noche y se gastan en mejoras, tienda y sodas.
--   * Niveles de mejora de las estadisticas.
-- Se reinicia al empezar una partida nueva, y se pierde al salir.
-- Atributos del Player: Money (billetes)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Signal = require(Shared.Signal)

type Run = {
	Cash: number,
	Upgrades: { [string]: number },
}

local RunState = {}

-- (player) se reinicio su partida
RunState.Reset = Signal.new()

local runs: { [Player]: Run } = {}

local function newRun(): Run
	local cash = if RunService:IsStudio() then Config.Debug.StudioStartCash or 0 else 0
	return { Cash = cash, Upgrades = {} }
end

local function get(player: Player): Run
	local run = runs[player]
	if not run then
		run = newRun()
		runs[player] = run
		player:SetAttribute("Money", run.Cash)
	end
	return run
end

function RunState.ResetPlayer(player: Player)
	runs[player] = newRun()
	player:SetAttribute("Money", runs[player].Cash)
	RunState.Reset:Fire(player)
end

function RunState.ResetAll()
	for _, player in Players:GetPlayers() do
		RunState.ResetPlayer(player)
	end
end

function RunState.GetCash(player: Player): number
	return get(player).Cash
end

function RunState.AddCash(player: Player, amount: number)
	if amount <= 0 then
		return
	end
	local run = get(player)
	run.Cash += math.floor(amount)
	player:SetAttribute("Money", run.Cash)
end

-- Cobra si alcanza. Devuelve true si se cobro.
function RunState.TrySpend(player: Player, amount: number): boolean
	local run = get(player)
	if amount < 0 or run.Cash < amount then
		return false
	end
	run.Cash -= math.floor(amount)
	player:SetAttribute("Money", run.Cash)
	return true
end

function RunState.GetUpgrade(player: Player, statName: string): number
	return get(player).Upgrades[statName] or 0
end

function RunState.SetUpgrade(player: Player, statName: string, level: number)
	get(player).Upgrades[statName] = level
end

function RunState.Start()
	Players.PlayerAdded:Connect(function(player)
		get(player)
	end)
	for _, player in Players:GetPlayers() do
		get(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		runs[player] = nil
	end)
end

return RunState
