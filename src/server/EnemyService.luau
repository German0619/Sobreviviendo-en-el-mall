-- EnemyService: aparece los enemigos de cada noche y los actualiza.
--
-- * Cantidad por tipo: Config.getEnemyCount (crece con las noches hasta MaxCount).
--   Solo salen los tipos cuya UnlockNight ya se alcanzo.
-- * El primero de cada tipo aparece al empezar la noche; los demas, escalonados
--   cada Config.EnemySpawn.StaggerSeconds.
-- * La noche en que un tipo aparece por primera vez se avisa con su Hint.
-- * Las noches con Vigilante se activan las camaras de seguridad (tag SecurityCamera).
-- * Cada mision fallada suma "amenaza", que potencia a los enemigos.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Tags = require(Shared.Tags)
local Remotes = require(Shared.Remotes)

local LightService = require(script.Parent.LightService)
local MissionService = require(script.Parent.MissionService)
local DefenseService = require(script.Parent.DefenseService)

local EnemiesFolder = ServerScriptService:WaitForChild("Enemies")
local Common = require(EnemiesFolder.Common)
local SecurityCamera = require(EnemiesFolder.SecurityCamera)

-- Tipos de enemigo (cada uno con su modulo en src/enemies). Orden = orden de los avisos.
local ENEMY_ORDER = { "Mannequin", "Blackout", "Echo", "Tracker", "Watcher" }
local enemyModules = {
	Mannequin = require(EnemiesFolder.Mannequin),
	Blackout = require(EnemiesFolder.Blackout),
	Echo = require(EnemiesFolder.Echo),
	Tracker = require(EnemiesFolder.Tracker),
	Watcher = require(EnemiesFolder.Watcher),
}

local EnemyService = {}

local activeEnemies = {}
local threat = {} -- [missionType] = misiones falladas esta noche
local heartbeatConn: RBXScriptConnection? = nil
local nightToken = 0 -- invalida las apariciones escalonadas de una noche anterior
local currentDifficulty = nil -- tabla compartida con los enemigos (ctx.Difficulty)
local baseSpeedMultiplier = 1
local rng = Random.new()

local function getTotalThreat(): number
	local total = 0
	for _, n in threat do
		total += n
	end
	return total
end

local function isAllowed(enemyType: string): boolean
	local only = Config.Debug.OnlyEnemies
	return only == nil or table.find(only, enemyType) ~= nil
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
	-- Repartir por el mapa (2 plantas): de unos cuantos al azar, el mas lejano a los
	-- enemigos que ya estan vivos, para que no se amontonen en una zona.
	local function distanceToEnemies(part: BasePart): number
		local best = math.huge
		for _, enemy in activeEnemies do
			local model = enemy.Model
			if model and model.Parent and model:IsA("Model") then
				best = math.min(best, (model:GetPivot().Position - part.Position).Magnitude)
			end
		end
		return best
	end
	local chosen = pool[rng:NextInteger(1, #pool)]
	local chosenScore = distanceToEnemies(chosen)
	for _ = 1, 3 do
		local other = pool[rng:NextInteger(1, #pool)]
		local score = distanceToEnemies(other)
		if score > chosenScore then
			chosen, chosenScore = other, score
		end
	end
	local offset = Vector3.new(rng:NextNumber(-2, 2), 0, rng:NextNumber(-2, 2))
	return chosen.Position - Vector3.new(0, chosen.Size.Y / 2, 0) + offset
end

local function spawnEnemy(enemyType: string, ctx)
	local position = pickSpawnPosition(enemyType)
	if not position then
		warn("[EnemyService] No hay donde aparecer", enemyType, "(faltan EnemySpawn o MallZone)")
		return
	end
	local ok, enemy = pcall(enemyModules[enemyType].new, position, ctx)
	if ok then
		table.insert(activeEnemies, enemy)
	else
		warn("[EnemyService] Error creando", enemyType, enemy)
	end
end

local function startCameras(ctx)
	for _, part in CollectionService:GetTagged(Tags.SecurityCamera) do
		if part:IsA("BasePart") then
			local ok, camera = pcall(SecurityCamera.new, part, ctx)
			if ok then
				table.insert(activeEnemies, camera)
			else
				warn("[EnemyService] Error creando camara", camera)
			end
		end
	end
end

function EnemyService.StartNight(night: number)
	EnemyService.StopNight()
	threat = {}
	nightToken += 1
	local token = nightToken

	local difficulty = Config.getDifficulty(night)
	currentDifficulty = difficulty
	baseSpeedMultiplier = difficulty.SpeedMultiplier
	local ctx = {
		Night = night,
		Difficulty = difficulty,
		Container = Common.getEnemiesFolder(),
		GetThreat = function(missionType: string): number
			return threat[missionType] or 0
		end,
		GetTotalThreat = getTotalThreat,
	}

	local hintDelay = 3
	for _, enemyType in ENEMY_ORDER do
		local def = Config.Enemies[enemyType]
		local count = if isAllowed(enemyType) then Config.getEnemyCount(enemyType, night) else 0
		for i = 1, count do
			if i == 1 then
				spawnEnemy(enemyType, ctx)
			else
				task.delay((i - 1) * Config.EnemySpawn.StaggerSeconds, function()
					if token == nightToken then
						spawnEnemy(enemyType, ctx)
					end
				end)
			end
		end

		if count > 0 then
			if enemyType == "Watcher" then
				startCameras(ctx)
			end
			-- Aviso la primera noche en que aparece (con su contramedida)
			if night == def.UnlockNight and def.Hint then
				task.delay(hintDelay, function()
					if token == nightToken then
						Remotes.event("Notify"):FireAllClients(def.Hint, "bad")
					end
				end)
				hintDelay += 5
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

-- Horas extra (NightManager): bonus = 0.1 -> enemigos un 10% mas rapidos.
function EnemyService.SetOvertime(bonus: number)
	if currentDifficulty then
		currentDifficulty.SpeedMultiplier = baseSpeedMultiplier * (1 + bonus)
	end
end

function EnemyService.StopNight()
	nightToken += 1
	if heartbeatConn then
		heartbeatConn:Disconnect()
		heartbeatConn = nil
	end
	for _, enemy in activeEnemies do
		pcall(enemy.Destroy, enemy)
	end
	activeEnemies = {}
	DefenseService.ClearAll() -- bengalas y petardos
end

function EnemyService.Start()
	-- El destello y el porrazo necesitan saber que enemigos hay
	DefenseService.SetEnemyProvider(function()
		return activeEnemies
	end)
	MissionService.Failed:Connect(function(mission)
		threat[mission.Type] = (threat[mission.Type] or 0) + 1
	end)
end

return EnemyService
