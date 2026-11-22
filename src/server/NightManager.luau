-- NightManager: ciclo de la partida.
--
--   Waiting -> Preparation -> Night (12 AM -> 6 AM) -> Results -> Upgrades -> (siguiente noche)
--                                  \-> si todos mueren -> GameOver -> nueva partida en la noche 1
--
-- Los personajes NO aparecen solos (CharacterAutoLoads = false): se crean en
-- la preparacion. Quien muere durante la noche espera a la siguiente.
-- Atributo del Player: Alive (true mientras participa vivo)

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Tags = require(Shared.Tags)
local Remotes = require(Shared.Remotes)
local GameState = require(Shared.GameState)

local DataService = require(script.Parent.DataService)
local PlayerStats = require(script.Parent.PlayerStats)
local LightService = require(script.Parent.LightService)
local FlashlightService = require(script.Parent.FlashlightService)
local MissionService = require(script.Parent.MissionService)
local EnemyService = require(script.Parent.EnemyService)

local NightManager = {}

local phase = "Waiting"
local participants = {} -- [Player] = true (jugadores que empezaron la noche)
local rng = Random.new()

local function notifyAll(text: string, kind: string?)
	Remotes.event("Notify"):FireAllClients(text, kind or "info")
end

local function setPhase(name: string, duration: number?)
	phase = name
	GameState.Folder:SetAttribute("Phase", name)
	GameState.Folder:SetAttribute(
		"PhaseEndsAt",
		if duration then Workspace:GetServerTimeNow() + duration else 0
	)
end

local function waitSeconds(seconds: number, earlyExit: (() -> boolean)?)
	local endAt = os.clock() + seconds
	while os.clock() < endAt do
		if earlyExit and earlyExit() then
			return
		end
		task.wait(0.25)
	end
end

local function getHumanoid(player: Player): Humanoid?
	local character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

local function isAliveNow(player: Player): boolean
	local humanoid = getHumanoid(player)
	return player:GetAttribute("Alive") == true and humanoid ~= nil and humanoid.Health > 0
end

local function aliveParticipants(): number
	local n = 0
	for player in participants do
		if player.Parent and isAliveNow(player) then
			n += 1
		end
	end
	return n
end

----------------------------------------------------------------------
-- Aparicion de jugadores
----------------------------------------------------------------------

local function moveToSpawn(character: Model)
	local spawns = {}
	for _, inst in CollectionService:GetTagged(Tags.PlayerSpawn) do
		if inst:IsA("BasePart") then
			table.insert(spawns, inst)
		end
	end
	if #spawns == 0 then
		return
	end
	local spawnPart = spawns[rng:NextInteger(1, #spawns)]
	local offset = Vector3.new(rng:NextNumber(-3, 3), spawnPart.Size.Y / 2 + 3.5, rng:NextNumber(-3, 3))
	character:PivotTo(CFrame.new(spawnPart.Position + offset))
end

local function spawnPlayer(player: Player)
	if not player.Parent or not DataService.GetData(player) then
		return
	end
	player:LoadCharacter()
	if player.Character then
		moveToSpawn(player.Character)
	end
	player:SetAttribute("Alive", true)
end

local function healFully(player: Player)
	local humanoid = getHumanoid(player)
	if humanoid and humanoid.Health > 0 then
		humanoid.Health = humanoid.MaxHealth
	end
end

local function onCharacterAdded(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid then
		return
	end
	humanoid.Died:Connect(function()
		if player.Character ~= character then
			return
		end
		if phase == "Night" and participants[player] then
			player:SetAttribute("Alive", false)
			DataService.Update(player, function(d)
				d.Lifetime.Deaths += 1
			end)
			notifyAll(player.DisplayName .. " ha caido...", "bad")
		else
			-- Fuera de la noche no se muere de verdad: reaparece
			task.delay(3, function()
				if player.Parent and phase ~= "Night" and player.Character == character then
					spawnPlayer(player)
				end
			end)
		end
	end)
end

----------------------------------------------------------------------
-- Pago
----------------------------------------------------------------------

local function payout(night: number, wiped: boolean)
	for player in participants do
		if player.Parent and DataService.GetData(player) then
			local survived = not wiped and isAliveNow(player)
			local base = Config.Pay.Base + Config.Pay.PerNight * (night - 1)
			local missions = MissionService.TakeEarnings(player)
			local survival = if survived then Config.Pay.SurvivalBonus else 0
			local subtotal = base + missions + survival
			local bonusPct = PlayerStats.GetPerk(player, "PayBonus") or 0
			local bonus = math.floor(subtotal * bonusPct)
			local total = subtotal + bonus

			DataService.AddMoney(player, total)
			DataService.Update(player, function(d)
				if survived then
					d.Lifetime.NightsSurvived += 1
					d.BestNight = math.max(d.BestNight, night)
				end
			end)

			Remotes.event("NightResults"):FireClient(player, {
				Night = night,
				Base = base,
				Missions = missions,
				Survival = survival,
				Bonus = bonus,
				Total = total,
				Survived = survived,
				GameOver = wiped,
			})
		end
	end
end

----------------------------------------------------------------------
-- Ciclo
----------------------------------------------------------------------

local function runNight(night: number): boolean -- devuelve true si todos murieron
	GameState.Folder:SetAttribute("Night", night)
	GameState.Folder:SetAttribute("GameHour", 0)

	-- Preparacion
	local prepSeconds = Config.Debug.PreparationSecondsOverride or Config.Night.PreparationSeconds
	setPhase("Preparation", prepSeconds)
	EnemyService.StopNight()
	LightService.ResetAll()
	MissionService.ResetNight()
	for _, player in Players:GetPlayers() do
		if not isAliveNow(player) then
			task.spawn(spawnPlayer, player)
		else
			healFully(player)
		end
		FlashlightService.Recharge(player)
	end
	notifyAll(string.format("La noche %d empieza en %d segundos. Preparate.", night, prepSeconds))
	waitSeconds(prepSeconds)

	-- Noche
	participants = {}
	for _, player in Players:GetPlayers() do
		if isAliveNow(player) then
			participants[player] = true
		end
	end
	if next(participants) == nil then
		return false -- nadie listo (cargando datos); repetir la preparacion
	end

	local nightSeconds = Config.Debug.NightSecondsOverride or Config.Night.RealSeconds
	setPhase("Night", nightSeconds)
	notifyAll(string.format("Noche %d: sobrevive hasta las 6 AM.", night), "bad")
	EnemyService.StartNight(night)
	MissionService.StartNight(night)

	local startedAt = os.clock()
	local wiped = false
	while true do
		local elapsed = os.clock() - startedAt
		local hour = Config.Night.StartHour
			+ (Config.Night.EndHour - Config.Night.StartHour) * math.min(elapsed / nightSeconds, 1)
		GameState.Folder:SetAttribute("GameHour", hour)
		if elapsed >= nightSeconds then
			break
		end
		if aliveParticipants() == 0 then
			wiped = true
			break
		end
		task.wait(0.25)
	end

	EnemyService.StopNight()
	MissionService.StopNight()
	for player in participants do
		if player.Parent then
			FlashlightService.SetOn(player, false)
		end
	end

	payout(night, wiped)
	return wiped
end

local function runGame()
	local night = Config.Debug.StartNight
	for _, player in Players:GetPlayers() do
		DataService.Update(player, function(d)
			d.Lifetime.RunsPlayed += 1
		end)
	end

	while #Players:GetPlayers() > 0 do
		local wiped = runNight(night)
		if next(participants) == nil then
			task.wait(1)
		elseif wiped then
			setPhase("GameOver", 12)
			notifyAll(string.format("Todo el equipo ha caido en la noche %d.", night), "bad")
			waitSeconds(12)
			participants = {}
			return
		else
			notifyAll(string.format("Son las 6 AM. Sobreviviste la noche %d.", night), "good")
			setPhase("Results", Config.Night.ResultsSeconds)
			waitSeconds(Config.Night.ResultsSeconds)
			setPhase("Upgrades", Config.Night.UpgradeSeconds)
			waitSeconds(Config.Night.UpgradeSeconds)
			night += 1
		end
	end
end

----------------------------------------------------------------------
-- Arranque
----------------------------------------------------------------------

function NightManager.GetPhase(): string
	return phase
end

function NightManager.Start()
	Players.CharacterAutoLoads = false

	local function setup(player: Player)
		player:SetAttribute("Alive", false)
		player.CharacterAdded:Connect(function(character)
			onCharacterAdded(player, character)
		end)
	end
	Players.PlayerAdded:Connect(setup)
	for _, player in Players:GetPlayers() do
		setup(player)
	end

	-- Al cargar los datos: aparecer si no estamos en plena noche
	DataService.ProfileLoaded:Connect(function(player: Player)
		if phase == "Night" or phase == "GameOver" then
			Remotes.event("Notify"):FireClient(player, "Partida en curso. Entraras en la proxima noche.", "info")
		else
			spawnPlayer(player)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		participants[player] = nil
	end)

	task.spawn(function()
		while true do
			setPhase("Waiting")
			while #Players:GetPlayers() == 0 do
				task.wait(1)
			end
			local ok, err = pcall(runGame)
			if not ok then
				warn("[NightManager] Error en la partida:", err)
				EnemyService.StopNight()
				MissionService.StopNight()
				task.wait(3)
			end
		end
	end)
end

return NightManager
