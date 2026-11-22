-- EnemyService: aparece los enemigos de cada noche y los actualiza.
--
-- Cantidad = BaseCount + extra por noche (Config.getDifficulty).
-- Solo salen los tipos cuya UnlockNight ya se alcanzo.
-- Cada mision fallada suma "amenaza", que potencia a los enemigos.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Tags = require(Shared.Tags)

local LightService = require(script.Parent.LightService)
local MissionService = require(script.Parent.MissionService)

local EnemiesFolder = ServerScriptService:WaitForChild("Enemies")
local Common = require(EnemiesFolder.Common)

-- Tipos implementados (el resto se agrega en la Fase 6)
local enemyModules = {
	Mannequin = require(EnemiesFolder.Mannequin),
	Blackout = require(EnemiesFolder.Blackout),
}

local EnemyService = {}

local activeEnemies = {}
local threat = {} -- [missionType] = misiones falladas esta noche
local heartbeatConn: RBXScriptConnection? = nil
local rng = Random.new()

local function getTotalThreat(): number
	local total = 0
	for _, n in threat do
		total += n
	end
	return total
end

-- Punto del suelo donde aparecer, lejos de los jugadores si se puede.
local function pickSpawnPosition(enemyType: string): Vector3?
	local candidates = {}
	for _, inst in CollectionService:GetTagged(Tags.EnemySpawn) do
		if inst:IsA("BasePart") then
			local only = inst:GetAttribute("EnemyType")
			if not only or only == enemyType then
				table.insert(candidates, inst)
			end
		end
	end

	if #candidates == 0 then
		-- Sin spawns marcados: centro de una zona al azar
		local zones = LightService.GetZones()
		if #zones == 0 then
			return nil
		end
		local part = LightService.GetZonePart(zones[rng:NextInteger(1, #zones)])
		if not part then
			return nil
		end
		return part.Position - Vector3.new(0, part.Size.Y / 2, 0)
	end

	-- Preferir spawns a mas de 40 studs de cualquier jugador
	local far = {}
	for _, spawnPart in candidates do
		local _, _, dist = Common.nearestAlive(spawnPart.Position)
		if dist > 40 then
			table.insert(far, spawnPart)
		end
	end
	local pool = if #far > 0 then far else candidates
	local chosen = pool[rng:NextInteger(1, #pool)]
	local offset = Vector3.new(rng:NextNumber(-2, 2), 0, rng:NextNumber(-2, 2))
	return chosen.Position - Vector3.new(0, chosen.Size.Y / 2, 0) + offset
end

function EnemyService.StartNight(night: number)
	EnemyService.StopNight()
	threat = {}

	local difficulty = Config.getDifficulty(night)
	local ctx = {
		Night = night,
		Difficulty = difficulty,
		Container = Common.getEnemiesFolder(),
		GetThreat = function(missionType: string): number
			return threat[missionType] or 0
		end,
		GetTotalThreat = getTotalThreat,
	}

	for enemyType, module in enemyModules do
		local def = Config.Enemies[enemyType]
		if def and night >= def.UnlockNight then
			local count = def.BaseCount + difficulty.ExtraCount
			for _ = 1, count do
				local position = pickSpawnPosition(enemyType)
				if position then
					local ok, enemy = pcall(module.new, position, ctx)
					if ok then
						table.insert(activeEnemies, enemy)
					else
						warn("[EnemyService] Error creando", enemyType, enemy)
					end
				else
					warn("[EnemyService] No hay donde aparecer", enemyType, "(faltan EnemySpawn o MallZone)")
				end
			end
		end
	end

	local errored = {}
	heartbeatConn = RunService.Heartbeat:Connect(function(dt)
		for _, enemy in activeEnemies do
			local ok, err = pcall(enemy.Update, enemy, dt)
			if not ok and not errored[enemy] then
				errored[enemy] = true -- avisar una sola vez por enemigo
				warn("[EnemyService] Error en Update:", err)
			end
		end
	end)
end

function EnemyService.StopNight()
	if heartbeatConn then
		heartbeatConn:Disconnect()
		heartbeatConn = nil
	end
	for _, enemy in activeEnemies do
		pcall(enemy.Destroy, enemy)
	end
	activeEnemies = {}
end

function EnemyService.Start()
	MissionService.Failed:Connect(function(mission)
		threat[mission.Type] = (threat[mission.Type] or 0) + 1
	end)
end

return EnemyService
