-- MissionService: genera misiones emergentes durante la noche.
--
-- * Cada noche el equipo tiene una CUOTA de tareas (Config.getMissionGoal).
--   Al completarla, la noche se gana (NightManager lo comprueba con GetProgress).
-- * Lo que dan las tareas va a un FONDO COMUN del equipo (TakeTeamEarnings),
--   que NightManager reparte a partes iguales.
-- * Elige un tipo al azar (con pesos de Config.Missions) entre los que tengan
--   un punto libre (parte con tag MissionSpot y atributo MissionType).
-- * Cada mision tiene zona, tiempo limite y recompensa.
-- * Las misiones ignoradas disparan MissionService.Failed (EnemyService lo
--   usa para potenciar a los enemigos).
-- * Se replican al cliente en ReplicatedStorage.GameState.Missions.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Tags = require(Shared.Tags)
local Util = require(Shared.Util)
local Signal = require(Shared.Signal)
local Remotes = require(Shared.Remotes)
local GameState = require(Shared.GameState)

local DataService = require(script.Parent.DataService)
local LightService = require(script.Parent.LightService)

local MissionsFolder = script.Parent:WaitForChild("Missions")

-- Tipos implementados. Para agregar uno: crear el modulo en server/Missions
-- y registrarlo aqui (debe existir tambien en Config.Missions).
local handlers = {
	FixLights = require(MissionsFolder.FixLights),
	CleanSpill = require(MissionsFolder.CleanSpill),
	TakeOutTrash = require(MissionsFolder.TakeOutTrash),
	RestartGenerator = require(MissionsFolder.RestartGenerator),
	LockDoors = require(MissionsFolder.LockDoors),
	RestockStore = require(MissionsFolder.RestockStore),
	CheckCameras = require(MissionsFolder.CheckCameras),
	UnclogToilet = require(MissionsFolder.UnclogToilet),
	SilenceAlarm = require(MissionsFolder.SilenceAlarm),
	LostItem = require(MissionsFolder.LostItem),
	WaterPlants = require(MissionsFolder.WaterPlants),
}

local MissionService = {}
MissionService.Completed = Signal.new() -- (mission, player)
MissionService.Failed = Signal.new() -- (mission)

local rng = Random.new()
local active = {} -- [id] = mission
local spotBusy = {} -- [BasePart] = true
local teamEarnings = 0 -- fondo comun del equipo esta noche
local doneCount = 0 -- tareas completadas esta noche
local goal = 1 -- cuota de la noche
local teamSize = 1
local running = false
local currentNight = 1
local idCounter = 0
local runToken = 0
local rewardMultiplier = 1 -- evento Hora de oro
local eventMissions = {} -- [handle] = true (misiones de evento activas)
local eventCounter = 0

local function notifyAll(text: string, kind: string)
	Remotes.event("Notify"):FireAllClients(text, kind)
end

local function zoneForSpot(spot: BasePart): string
	local z = spot:GetAttribute("Zone")
	if type(z) == "string" and z ~= "" then
		return z
	end
	return LightService.GetZoneAt(spot.Position) or "Mall"
end

local function getFreeSpots(missionType: string): { BasePart }
	local handler = handlers[missionType]
	local result = {}
	for _, inst in CollectionService:GetTagged(Tags.MissionSpot) do
		if inst:IsA("BasePart") and inst:GetAttribute("MissionType") == missionType and not spotBusy[inst] then
			if not handler.CanStart or handler.CanStart(inst, zoneForSpot(inst)) then
				table.insert(result, inst)
			end
		end
	end
	return result
end

local function addMarker(mission, part: BasePart)
	local gui = Instance.new("BillboardGui")
	gui.Name = "MissionMarker"
	gui.Size = UDim2.fromOffset(36, 36)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 3, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 90
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = "!"
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 200, 60)
	label.TextStrokeTransparency = 0.3
	label.Parent = gui
	gui.Parent = part
	mission.MarkerGui = gui
end

local function endMission(mission, player: Player?, silent: boolean?)
	if mission.Done then
		return
	end
	mission.Done = true
	active[mission.Id] = nil
	spotBusy[mission.Spot] = nil
	if mission.Value then
		mission.Value:Destroy()
	end
	if mission.MarkerGui then
		mission.MarkerGui:Destroy()
	end
	if mission.Handle then
		local ok, err = pcall(mission.Handle.Cleanup, player ~= nil)
		if not ok then
			warn("[MissionService] Error limpiando", mission.Type, err)
		end
	end

	if player then
		local reward = math.floor(mission.Reward * rewardMultiplier)
		teamEarnings += reward
		doneCount += 1
		GameState.Folder:SetAttribute("MissionsDone", doneCount)
		DataService.Update(player, function(d)
			d.Lifetime.MissionsCompleted += 1
		end)
		notifyAll(
			string.format(
				"%s completó: %s (+%s para el equipo)  ·  %d/%d",
				player.DisplayName,
				mission.DisplayName,
				Util.formatMoney(reward),
				math.min(doneCount, goal),
				goal
			),
			"good"
		)
		MissionService.Completed:Fire(mission, player)
	elseif not silent then
		notifyAll(string.format("Tarea fallida: %s. Algo se vuelve mas fuerte...", mission.DisplayName), "bad")
		MissionService.Failed:Fire(mission)
	end
end

local function startMission(missionType: string, spot: BasePart)
	local def = Config.Missions[missionType]
	idCounter += 1

	local mission = {
		Id = "M" .. idCounter,
		Type = missionType,
		DisplayName = def.DisplayName,
		Zone = zoneForSpot(spot),
		Spot = spot,
		ExpiresAt = Workspace:GetServerTimeNow() + def.TimeLimit,
		Reward = math.floor(def.Reward * (1 + Config.MissionSpawn.RewardPerNight * (currentNight - 1))),
		Done = false,
	}
	spotBusy[spot] = true
	active[mission.Id] = mission

	local value = Instance.new("Configuration")
	value.Name = mission.Id
	value:SetAttribute("Type", missionType)
	value:SetAttribute("DisplayName", mission.DisplayName)
	value:SetAttribute("Zone", mission.Zone)
	value:SetAttribute("ExpiresAt", mission.ExpiresAt)
	value:SetAttribute("Reward", mission.Reward)
	value.Parent = GameState.Missions
	mission.Value = value

	local function complete(player: Player): boolean
		if not running or mission.Done then
			return false
		end
		if player:GetAttribute("Alive") ~= true then
			return false
		end
		endMission(mission, player)
		return true
	end

	local ok, handle = pcall(handlers[missionType].Begin, mission, complete)
	if not ok then
		warn("[MissionService] Error iniciando", missionType, handle)
		endMission(mission, nil, true)
		return
	end
	mission.Handle = handle
	if handle.Marker then
		addMarker(mission, handle.Marker)
	end

	notifyAll(string.format("Nueva tarea: %s (%s)", mission.DisplayName, mission.Zone), "info")
end

local function countActive(): number
	local n = 0
	for _ in active do
		n += 1
	end
	return n
end

local function trySpawn(): boolean
	local weights = {}
	for missionType in handlers do
		local def = Config.Missions[missionType]
		if def and #getFreeSpots(missionType) > 0 then
			weights[missionType] = def.Weight
		end
	end
	local missionType = Util.weightedRandom(weights, rng)
	if not missionType then
		return false
	end
	local spots = getFreeSpots(missionType)
	startMission(missionType, spots[rng:NextInteger(1, #spots)])
	return true
end

-- Con pocas tareas activas salen enseguida; con equipos grandes, mas seguido.
local function spawnInterval(): number
	local s = Config.MissionSpawn
	if countActive() < s.MinActive then
		return s.RefillInterval
	end
	local interval = s.BaseInterval + s.IntervalPerNight * (currentNight - 1)
	interval /= 1 + s.PerExtraPlayer * (teamSize - 1)
	return math.max(s.MinInterval, interval)
end

----------------------------------------------------------------------
-- API
----------------------------------------------------------------------

-- players = tamano del equipo esta noche (para la cuota y las misiones simultaneas)
function MissionService.StartNight(night: number, players: number?)
	currentNight = night
	teamSize = math.max(players or 1, 1)
	goal = Config.getMissionGoal(night, teamSize)
	doneCount = 0
	GameState.Folder:SetAttribute("MissionGoal", goal)
	GameState.Folder:SetAttribute("MissionsDone", 0)
	running = true
	runToken += 1
	local token = runToken

	task.spawn(function()
		local nextSpawn = os.clock() + Config.MissionSpawn.FirstDelay
		while running and runToken == token do
			local now = Workspace:GetServerTimeNow()
			for _, mission in active do
				if now >= mission.ExpiresAt then
					endMission(mission, nil)
				end
			end
			-- Si se quedan pocas tareas activas, no esperar al intervalo completo
			if countActive() < Config.MissionSpawn.MinActive then
				nextSpawn = math.min(nextSpawn, os.clock() + Config.MissionSpawn.RefillInterval)
			end
			if os.clock() >= nextSpawn then
				if doneCount < goal and countActive() < Config.getMaxConcurrentMissions(currentNight, teamSize) then
					trySpawn()
				end
				nextSpawn = os.clock() + spawnInterval()
			end
			task.wait(0.5)
		end
	end)
end

-- Al terminar la noche: las misiones pendientes se retiran sin penalizacion.
function MissionService.StopNight()
	running = false
	for _, mission in active do
		endMission(mission, nil, true)
	end
	for handle in eventMissions do
		handle.Cancel()
	end
	MissionService.SetRewardMultiplier(1)
end

-- Evento Hora de oro: las tareas pagan x multiplier (el HUD lo muestra).
function MissionService.SetRewardMultiplier(multiplier: number)
	rewardMultiplier = multiplier
	GameState.Folder:SetAttribute("RewardMultiplier", if multiplier ~= 1 then multiplier else nil)
end

-- Un punto libre de un tipo de mision (para las misiones de evento: generadores,
-- monitores, paneles de alarma). floor: solo de esa planta, si la hay. near: el mas
-- cercano a ese punto (si no, uno al azar).
function MissionService.GetFreeSpot(missionType: string, floor: number?, near: Vector3?): BasePart?
	local list = {}
	for _, inst in CollectionService:GetTagged(Tags.MissionSpot) do
		if inst:IsA("BasePart") and inst:GetAttribute("MissionType") == missionType and not spotBusy[inst] then
			if not floor or Config.getFloor(inst.Position.Y) == floor then
				table.insert(list, inst)
			end
		end
	end
	if #list == 0 then
		return nil
	end
	if near then
		table.sort(list, function(a, b)
			return (a.Position - near).Magnitude < (b.Position - near).Magnitude
		end)
		return list[1]
	end
	return list[rng:NextInteger(1, #list)]
end

----------------------------------------------------------------------
-- Misiones de evento (EventDirector)
----------------------------------------------------------------------
-- No cuentan para la cuota, no pagan y no avanzan el reloj. Se ven en la lista de
-- tareas con otro color (atributo Event). Si caducan, no hay penalizacion: el evento
-- decide (normalmente sigue activo y crea otra).
--
-- opts = {
--   DisplayName: string, Spot: BasePart, ActionText: string, ObjectText: string?,
--   HoldSeconds: number?, TimeLimit: number, RepairTask: boolean?,
--   OnComplete: (player) -> (), OnExpire: () -> ()?,
-- }
-- Devuelve { Cancel: () -> () }.
function MissionService.StartEventMission(opts)
	eventCounter += 1
	local spot: BasePart = opts.Spot
	local done = false
	local handle = {}
	spotBusy[spot] = true

	local value = Instance.new("Configuration")
	value.Name = "E" .. eventCounter
	value:SetAttribute("Event", true)
	value:SetAttribute("Type", "Event")
	value:SetAttribute("DisplayName", opts.DisplayName)
	value:SetAttribute("Zone", zoneForSpot(spot))
	value:SetAttribute("ExpiresAt", Workspace:GetServerTimeNow() + opts.TimeLimit)
	value:SetAttribute("Reward", 0)
	value.Parent = GameState.Missions

	local MissionsCommon = require(MissionsFolder.Common)
	local prompt = MissionsCommon.makePrompt(spot, opts.ActionText, opts.ObjectText, opts.HoldSeconds)
	if opts.RepairTask then
		prompt:SetAttribute("RepairTask", true)
	end
	local marker = MissionsCommon.makeMarker(spot, "!", Color3.fromRGB(190, 120, 255))

	local function finish()
		if done then
			return false
		end
		done = true
		eventMissions[handle] = nil
		spotBusy[spot] = nil
		value:Destroy()
		prompt:Destroy()
		marker:Destroy()
		return true
	end
	handle.Cancel = finish

	prompt.Triggered:Connect(function(player: Player)
		if done or player:GetAttribute("Alive") ~= true then
			return
		end
		finish()
		notifyAll(string.format("%s resolvió: %s", player.DisplayName, opts.DisplayName), "good")
		task.spawn(opts.OnComplete, player)
	end)

	eventMissions[handle] = true
	task.delay(opts.TimeLimit, function()
		if finish() and opts.OnExpire then
			opts.OnExpire()
		end
	end)
	return handle
end

-- Al empezar la preparacion: quitar restos (charcos, etc.) de la noche anterior.
function MissionService.ResetNight()
	for _, handler in handlers do
		if handler.ResetNight then
			handler.ResetNight()
		end
	end
	teamEarnings = 0
	doneCount = 0
end

-- (completadas, cuota) de la noche actual.
function MissionService.GetProgress(): (number, number)
	return doneCount, goal
end

-- Devuelve el fondo comun de la noche y lo pone a 0.
function MissionService.TakeTeamEarnings(): number
	local amount = teamEarnings
	teamEarnings = 0
	return amount
end

function MissionService.Start()
	GameState.Folder:SetAttribute("MissionGoal", 0)
	GameState.Folder:SetAttribute("MissionsDone", 0)
end

return MissionService
