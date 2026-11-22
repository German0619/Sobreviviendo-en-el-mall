-- MissionService: genera misiones emergentes durante la noche.
--
-- * Elige un tipo al azar (con pesos de Config.Missions) entre los que tengan
--   un punto libre (parte con tag MissionSpot y atributo MissionType).
-- * Cada mision tiene zona, tiempo limite y recompensa.
-- * Las misiones ignoradas disparan MissionService.Failed (EnemyService lo
--   usa para potenciar a los enemigos).
-- * Se replican al cliente en ReplicatedStorage.GameState.Missions.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
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
}

local MissionService = {}
MissionService.Completed = Signal.new() -- (mission, player)
MissionService.Failed = Signal.new() -- (mission)

local rng = Random.new()
local active = {} -- [id] = mission
local spotBusy = {} -- [BasePart] = true
local earnings = {} -- [Player] = numero ganado en la noche actual
local running = false
local currentNight = 1
local idCounter = 0
local runToken = 0

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
		earnings[player] = (earnings[player] or 0) + mission.Reward
		DataService.Update(player, function(d)
			d.Lifetime.MissionsCompleted += 1
		end)
		notifyAll(
			string.format("%s completo: %s (+%s)", player.DisplayName, mission.DisplayName, Util.formatMoney(mission.Reward)),
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

local function spawnInterval(): number
	local s = Config.MissionSpawn
	return math.max(s.MinInterval, s.BaseInterval + s.IntervalPerNight * (currentNight - 1))
end

----------------------------------------------------------------------
-- API
----------------------------------------------------------------------

function MissionService.StartNight(night: number)
	currentNight = night
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
			if os.clock() >= nextSpawn then
				if countActive() < Config.getMaxConcurrentMissions(currentNight) then
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
end

-- Al empezar la preparacion: quitar restos (charcos, etc.) de la noche anterior.
function MissionService.ResetNight()
	for _, handler in handlers do
		if handler.ResetNight then
			handler.ResetNight()
		end
	end
	earnings = {}
end

-- Devuelve lo ganado en misiones esta noche y lo pone a 0.
function MissionService.TakeEarnings(player: Player): number
	local amount = earnings[player] or 0
	earnings[player] = nil
	return amount
end

function MissionService.Start()
	Players.PlayerRemoving:Connect(function(player)
		earnings[player] = nil
	end)
end

return MissionService
