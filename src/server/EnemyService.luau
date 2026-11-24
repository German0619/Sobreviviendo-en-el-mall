-- EnemyService: aparece los enemigos de cada noche y los actualiza.
--
-- * Que enemigos, en que planta y cuando lo decide SpawnDirector (presupuesto de
--   peligro por noche y jugadores, % por nivel, topes por nivel y por planta).
-- * La primera vez que un tipo aparece en la partida se avisa con su Hint (contramedida).
-- * Cuando aparece un Vigilante se activan las camaras de seguridad (tag SecurityCamera).
-- * Cada mision fallada suma "amenaza", que potencia a los enemigos.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Tags = require(Shared.Tags)
local Remotes = require(Shared.Remotes)

local Players = game:GetService("Players")

local LightService = require(script.Parent.LightService)
local MissionService = require(script.Parent.MissionService)
local DefenseService = require(script.Parent.DefenseService)
local SpawnDirector = require(script.Parent.SpawnDirector)

local EnemiesFolder = ServerScriptService:WaitForChild("Enemies")
local Common = require(EnemiesFolder.Common)
local SecurityCamera = require(EnemiesFolder.SecurityCamera)

-- Tipos de enemigo (cada uno con su modulo en src/enemies)
local enemyModules = {
	Mannequin = require(EnemiesFolder.Mannequin),
	Blackout = require(EnemiesFolder.Blackout),
	Cart = require(EnemiesFolder.Cart),
	Balloon = require(EnemiesFolder.Balloon),
	Moth = require(EnemiesFolder.Moth),
	Reflection = require(EnemiesFolder.Reflection),
	Duct = require(EnemiesFolder.Duct),
	Cashier = require(EnemiesFolder.Cashier),
	Intercom = require(EnemiesFolder.Intercom),
	Echo = require(EnemiesFolder.Echo),
	Tracker = require(EnemiesFolder.Tracker),
	Watcher = require(EnemiesFolder.Watcher),
	Statue = require(EnemiesFolder.Statue),
	Mimic = require(EnemiesFolder.Mimic),
	Hunter = require(EnemiesFolder.Hunter),
	-- Jefes (los pone BossService)
	Manager = require(EnemiesFolder.Manager),
	Luni = require(EnemiesFolder.Luni),
	Collector = require(EnemiesFolder.Collector),
	Converted = require(EnemiesFolder.Converted),
}

local EnemyService = {}

local activeEnemies = {}
local threat = {} -- [missionType] = misiones falladas esta noche
local heartbeatConn: RBXScriptConnection? = nil
local nightToken = 0 -- invalida las apariciones escalonadas de una noche anterior
local currentDifficulty = nil -- tabla compartida con los enemigos (ctx.Difficulty)
local currentCtx = nil -- ctx de la noche (para las apariciones de los eventos)
local baseSpeedMultiplier = 1
local overtimeBonus = 0 -- horas extra (NightManager)
local eventSpeed = 1 -- evento Hora de oro (EventDirector)
local rng = Random.new()
local hinted: { [string]: boolean } = {} -- tipos cuyo aviso ya se mostro en esta partida
local camerasStarted = false

local function getTotalThreat(): number
	local total = 0
	for _, n in threat do
		total += n
	end
	return total
end

-- Jugadores vivos en cada planta (para repartir los enemigos).
local function playersPerFloor(): { number }
	local counts = { 0, 0 }
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if root and humanoid and humanoid.Health > 0 then
			local floor = Config.getFloor(root.Position.Y)
			counts[floor] = (counts[floor] or 0) + 1
		end
	end
	return counts
end

-- Punto del suelo donde aparecer (en la planta pedida si la hay), lejos de los jugadores si se puede.
local function pickSpawnPosition(enemyType: string, floor: number?): Vector3?
	local candidates = {}
	for _, inst in CollectionService:GetTagged(Tags.EnemySpawn) do
		if inst:IsA("BasePart") then
			local only = inst:GetAttribute("EnemyType")
			if not only or only == enemyType then
				table.insert(candidates, inst)
			end
		end
	end
	-- Solo los de esa planta (si no hay ninguno, cualquiera)
	if floor then
		local onFloor = {}
		for _, part in candidates do
			if Config.getFloor(part.Position.Y) == floor then
				table.insert(onFloor, part)
			end
		end
		if #onFloor > 0 then
			candidates = onFloor
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

local startCameras

local function spawnEnemy(enemyType: string, ctx, floor: number?, at: Vector3?)
	local module = enemyModules[enemyType]
	if not module then
		warn("[EnemyService] Enemigo sin modulo:", enemyType)
		return
	end
	local position = at or pickSpawnPosition(enemyType, floor)
	if not position then
		warn("[EnemyService] No hay donde aparecer", enemyType, "(faltan EnemySpawn o MallZone)")
		return
	end
	local ok, enemy = pcall(module.new, position, ctx)
	if not ok then
		warn("[EnemyService] Error creando", enemyType, enemy)
		return nil
	end
	enemy.EnemyType = enemyType -- lo usan las armas (nivel del enemigo)
	if enemy.Model then
		enemy.Model:SetAttribute("EnemyType", enemyType)
	end
	table.insert(activeEnemies, enemy)

	-- El Vigilante ve por las camaras: se encienden cuando aparece el primero
	if enemyType == "Watcher" and not camerasStarted then
		camerasStarted = true
		startCameras(ctx)
	end
	-- Primera vez en la partida: aviso con su contramedida
	local def = Config.Enemies[enemyType]
	if def.Hint and not hinted[enemyType] then
		hinted[enemyType] = true
		Remotes.event("Notify"):FireAllClients(def.Hint, "bad")
	end
	return enemy
end

function startCameras(ctx)
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

-- options.BudgetMultiplier: noches de jefe (Config.SpawnDirector.BossBudgetMultiplier).
function EnemyService.StartNight(night: number, options: { BudgetMultiplier: number? }?)
	EnemyService.StopNight()
	threat = {}
	nightToken += 1
	local token = nightToken
	camerasStarted = false

	local difficulty = Config.getDifficulty(night)
	currentDifficulty = difficulty
	baseSpeedMultiplier = difficulty.SpeedMultiplier
	overtimeBonus = 0
	eventSpeed = 1
	local ctx = {
		Night = night,
		Difficulty = difficulty,
		Container = Common.getEnemiesFolder(),
		GetThreat = function(missionType: string): number
			return threat[missionType] or 0
		end,
		GetTotalThreat = getTotalThreat,
	}
	currentCtx = ctx

	-- El director decide que aparece, en que planta y cuando
	local plan, budget = SpawnDirector.Plan(night, playersPerFloor(), {
		Rng = rng,
		Allowed = Config.Debug.OnlyEnemies,
		BudgetMultiplier = options and options.BudgetMultiplier,
	})
	if RunService:IsStudio() then
		print(string.format("[SpawnDirector] Noche %d: %s", night, SpawnDirector.Describe(plan, budget)))
	end
	for _, spawn in plan do
		if spawn.Delay <= 0 then
			spawnEnemy(spawn.Type, ctx, spawn.Floor)
		else
			task.delay(spawn.Delay, function()
				if token == nightToken then
					spawnEnemy(spawn.Type, ctx, spawn.Floor)
				end
			end)
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

local function applySpeed()
	if currentDifficulty then
		currentDifficulty.SpeedMultiplier = baseSpeedMultiplier * (1 + overtimeBonus) * eventSpeed
	end
end

-- Horas extra (NightManager): bonus = 0.1 -> enemigos un 10% mas rapidos.
function EnemyService.SetOvertime(bonus: number)
	overtimeBonus = bonus
	applySpeed()
end

-- Eventos (Hora de oro): multiplicador extra de velocidad (1 = normal).
function EnemyService.SetEventSpeed(multiplier: number)
	eventSpeed = multiplier
	applySpeed()
end

-- Quita un enemigo antes de que acabe la noche (al terminar un evento).
function EnemyService.RemoveEnemy(enemy)
	local index = table.find(activeEnemies, enemy)
	if index then
		table.remove(activeEnemies, index)
		pcall(enemy.Destroy, enemy)
	end
end

-- Aparicion de un evento (Oleada, Megafonia hackeada): un enemigo que se va solo a
-- los `seconds`. Devuelve el enemigo (o nil).
-- at: punto del suelo exacto donde aparece (si no, un EnemySpawn de esa planta).
function EnemyService.SpawnTemporary(enemyType: string, floor: number?, seconds: number, at: Vector3?)
	if not currentCtx then
		return nil
	end
	local token = nightToken
	local enemy = spawnEnemy(enemyType, currentCtx, floor, at)
	if enemy then
		task.delay(seconds, function()
			if token == nightToken then
				EnemyService.RemoveEnemy(enemy)
			end
		end)
	end
	return enemy
end

-- Tipos de esos niveles que ya pueden salir esta noche (Oleada, refuerzos del Gerente).
-- exclude: tipos que no sirven (p. ej. los que no tienen cuerpo).
function EnemyService.GetTypesForTiers(tiers: { number }, exclude: { [string]: boolean }?): { string }
	local night = currentCtx and currentCtx.Night or 1
	local list = {}
	for enemyType, def in Config.Enemies do
		if
			def.Tier
			and table.find(tiers, def.Tier)
			and night >= (def.UnlockNight or 1)
			and enemyModules[enemyType]
			and not (exclude and exclude[enemyType])
		then
			table.insert(list, enemyType)
		end
	end
	table.sort(list)
	return list
end

function EnemyService.GetTier1Types(): { string }
	return EnemyService.GetTypesForTiers({ 1 })
end

-- Enciende las camaras de seguridad esta noche aunque no haya Vigilante (la Central).
function EnemyService.EnsureCameras()
	if currentCtx and not camerasStarted then
		camerasStarted = true
		startCameras(currentCtx)
	end
end

-- Evento Camaras amigas: contorno de todas las entidades visible a traves de las paredes.
function EnemyService.RevealAll(seconds: number)
	local marks = {}
	for _, enemy in activeEnemies do
		local model = enemy.Model
		if model and model:IsA("Model") and not model:FindFirstChild("EventReveal") then
			local h = Instance.new("Highlight")
			h.Name = "EventReveal"
			h.FillColor = Color3.fromRGB(255, 120, 40)
			h.FillTransparency = 0.7
			h.OutlineColor = Color3.fromRGB(255, 170, 60)
			h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
			h.Parent = model
			table.insert(marks, h)
		end
	end
	task.delay(seconds, function()
		for _, h in marks do
			h:Destroy()
		end
	end)
	return #marks
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
