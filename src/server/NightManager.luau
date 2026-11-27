-- NightManager: ciclo de la partida.
--
--   Waiting -> Preparation -> Night (12 AM -> 6 AM) -> Preparation de la siguiente noche
--   (al ganar, el cliente muestra la pantalla de victoria y el pago al empezar la preparacion)
--                                  \-> si todos mueren -> GameOver -> todos al lobby
--
-- La sala se arma en el LOBBY (LobbyService): al mall solo se llega con la
-- partida ya iniciada. Waiting aqui es solo esperar a que terminen de llegar
-- todos los miembros (como mucho Config.Rooms.ArrivalTimeout segundos).
-- En Studio / servidor no reservado (para probar) el anfitrion inicia con [P]
-- (RequestStartGame), o sola con Config.Debug.AutoStart = true.
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
local EventDirector = require(script.Parent.EventDirector)
local BossService = require(script.Parent.BossService)
local ReviveService = require(script.Parent.ReviveService)
local ClassService = require(script.Parent.ClassService)
local RunState = require(script.Parent.RunState)
local RoomService = require(script.Parent.RoomService)
local PassService = require(script.Parent.PassService)
local PermanentUpgradeService = require(script.Parent.PermanentUpgradeService)
local LockerService = require(script.Parent.LockerService)

local NightManager = {}

local phase = "Waiting"
local startRequested = false
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
	-- El cuerpo queda entero en el suelo para que lo puedan revivir
	humanoid.BreakJointsOnDeath = false
	humanoid.Died:Connect(function()
		if player.Character ~= character then
			return
		end
		if phase == "Night" and participants[player] then
			player:SetAttribute("Alive", false)
			DataService.Update(player, function(d)
				d.Lifetime.Deaths += 1
			end)
			-- El cuerpo siempre queda revivible (el propio caido puede pagar por revivir)
			ReviveService.OnDowned(player, character)
			notifyAll(player.DisplayName .. " ha caído.", "bad")
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

-- Al ganar la noche: el fondo de tareas del equipo se reparte a partes iguales
-- entre todos los que empezaron la noche (vivos o caidos). Si cae todo el equipo
-- no hay pago (la partida termina).
local function payout(night: number, wiped: boolean)
	local team = {}
	for player in participants do
		if player.Parent and DataService.GetData(player) then
			table.insert(team, player)
		end
	end
	local pool = MissionService.TakeTeamEarnings()
	local share = if #team > 0 then math.floor(pool / #team) else 0

	for _, player in team do
		local base, teamBonus, bonus, passBonus, total = 0, 0, 0, 0, 0
		if not wiped then
			base = Config.Pay.Base + Config.Pay.PerNight * (night - 1)
			teamBonus = Config.Pay.NightCompleteBonus
			local subtotal = base + share + teamBonus
			bonus = math.floor(subtotal * (PlayerStats.GetPerk(player, "PayBonus") or 0)) -- Ahorrador
			-- Pase x2 Billetes: duplica todo el pago
			passBonus = if PassService.Owns(player, "DoubleMoney") then subtotal + bonus else 0
			total = subtotal + bonus + passBonus

			RunState.AddCash(player, total)
			DataService.Update(player, function(d)
				d.Lifetime.MoneyEarned += total
				d.Lifetime.NightsSurvived += 1
				d.BestNight = math.max(d.BestNight, night)
			end)
			ClassService.OnNightSurvived(player) -- diamantes cada N noches y logros
			BossService.OnNightSurvived(player, night) -- desde la noche 25: diamantes cada 5 noches
		end

		Remotes.event("NightResults"):FireClient(player, {
			Night = night,
			Base = base,
			Missions = if wiped then 0 else share,
			MissionsPool = pool,
			TeamSize = #team,
			Survival = teamBonus,
			Bonus = bonus,
			PassBonus = passBonus,
			Total = total,
			Survived = not wiped,
			GameOver = wiped,
		})
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
	BossService.StopNight()
	EventDirector.StopNight()
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

	local teamSize = 0
	for _ in participants do
		teamSize += 1
	end
	setPhase("Night")
	-- Noche de jefe: mitad de enemigos y de tareas, sin eventos al azar (el jefe es el evento)
	-- (desde la noche 25, dos jefes a la vez: BossService)
	local bossIds = BossService.GetBossesFor(night)
	local isBossNight = #bossIds > 0
	EnemyService.StartNight(night, if isBossNight then { BudgetMultiplier = Config.SpawnDirector.BossBudgetMultiplier } else nil)
	MissionService.StartNight(night, teamSize, if isBossNight then Config.Bosses.GoalMultiplier else nil)
	if isBossNight then
		BossService.StartNight(night, bossIds)
	else
		EventDirector.StartNight(night)
	end
	local _, goal = MissionService.GetProgress()
	if isBossNight then
		local name, objective = BossService.Describe(bossIds, night)
		local title = if #bossIds > 1 then "¡DOS JEFES!" else "¡JEFE!"
		notifyAll(string.format("¡Noche %d: %s %s. %s Y completen %d tareas.", night, title, name, string.gsub(objective, "\n", " "), goal), "bad")
	else
		notifyAll(string.format("Noche %d: completen %d tareas en equipo para llegar a las 6 AM.", night, goal), "bad")
	end

	-- Si caen todos, hay unos segundos para revivir con Robux (solo si el producto existe)
	local graceSeconds = if Config.DevProducts.Revive ~= 0 then Config.Revive.WipeGraceSeconds else 0
	local wipeDeadline: number? = nil

	local startedAt = os.clock()
	local wiped = false
	local overtimeLevel = 0
	while true do
		local elapsed = os.clock() - startedAt

		-- El reloj avanza con las tareas completadas: la cuota completa = 6 AM
		local done, total = MissionService.GetProgress()
		local hour = Config.Night.StartHour
			+ (Config.Night.EndHour - Config.Night.StartHour) * math.min(done / math.max(total, 1), 1)
		-- Con el jefe aun en pie, el reloj se queda en 5:59
		local bossAlive = isBossNight and not BossService.IsDefeated()
		if bossAlive then
			hour = math.min(hour, Config.Night.EndHour - 1 / 60)
		end
		GameState.Folder:SetAttribute("GameHour", hour)

		local alive = aliveParticipants()
		if done >= total and alive > 0 and not bossAlive then
			break -- noche ganada
		end

		-- Horas extra: cada minuto pasado OvertimeSeconds, los enemigos son mas rapidos
		if elapsed > Config.Night.OvertimeSeconds then
			local level = math.floor((elapsed - Config.Night.OvertimeSeconds) / 60) + 1
			if level ~= overtimeLevel then
				overtimeLevel = level
				EnemyService.SetOvertime(
					math.min(level * Config.Night.OvertimeSpeedPerMinute, Config.Night.MaxOvertimeBonus)
				)
				if level == 1 then
					notifyAll("Se hace tarde... las cosas del mall se impacientan.", "bad")
				end
			end
		end

		if alive == 0 then
			if not wipeDeadline then
				wipeDeadline = os.clock() + graceSeconds
				GameState.Folder:SetAttribute("WipeAt", Workspace:GetServerTimeNow() + graceSeconds)
				if graceSeconds > 0 then
					notifyAll(string.format("Todo el equipo cayó. %d segundos para revivir...", graceSeconds), "bad")
				end
			end
			if os.clock() >= wipeDeadline then
				wiped = true
				break
			end
		elseif wipeDeadline then
			wipeDeadline = nil
			GameState.Folder:SetAttribute("WipeAt", nil)
		end
		task.wait(0.25)
	end
	GameState.Folder:SetAttribute("WipeAt", nil)

	BossService.StopNight() -- antes que enemigos y misiones: deshacen sus efectos
	EventDirector.StopNight()
	EnemyService.StopNight()
	MissionService.StopNight()
	ReviveService.Clear()
	for player in participants do
		if player.Parent then
			FlashlightService.SetOn(player, false)
		end
	end

	payout(night, wiped)
	return wiped
end

-- Antes de empezar: todos de pie y sin enemigos.
local function waitForStart()
	startRequested = false
	setPhase("Waiting")
	BossService.StopNight()
	EventDirector.StopNight()
	EnemyService.StopNight()
	MissionService.StopNight()
	LightService.ResetAll()
	-- Quien cayo en la partida anterior (o entro a mitad) vuelve a aparecer
	for _, player in Players:GetPlayers() do
		if DataService.GetData(player) and not isAliveNow(player) then
			task.spawn(spawnPlayer, player)
		end
	end
	if RoomService.IsReserved() then
		-- Partida iniciada en el lobby: esperar a que lleguen todos los miembros
		while #Players:GetPlayers() == 0 do
			task.wait(0.25)
		end
		local timeout = Config.Rooms.ArrivalTimeout
		setPhase("Waiting", timeout)
		local deadline = os.clock() + timeout
		while os.clock() < deadline and not RoomService.AllMembersArrived() do
			task.wait(0.25)
		end
		return
	end

	if #Players:GetPlayers() > 0 and not Config.Debug.AutoStart then
		notifyAll("Modo prueba: el anfitrión inicia la partida.")
	end
	while #Players:GetPlayers() == 0 or not (startRequested or Config.Debug.AutoStart) do
		task.wait(0.25)
	end
end

local function runGame()
	local night = Config.Debug.StartNight
	-- Partida nueva: billetes y mejoras a 0
	RunState.ResetAll()
	for _, player in Players:GetPlayers() do
		DataService.Update(player, function(d)
			d.Lifetime.RunsPlayed += 1
		end)
		-- Mejoras permanentes: billetes extra y kit de inicio
		PermanentUpgradeService.GrantRunStart(player)
		-- Taquilla del conserje: 1 de cada objeto guardado
		LockerService.GrantRunStart(player)
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
			-- Partida de una sala del lobby: todos vuelven al lobby a armar otra
			if RoomService.IsReserved() and RoomService.SendAllToLobby("Fin del turno. Volviendo al lobby...") then
				local deadline = os.clock() + 30
				while #Players:GetPlayers() > 0 and os.clock() < deadline do
					task.wait(0.5)
				end
			end
			return
		else
			-- Los del equipo ya ven la pantalla de victoria; el aviso es para quien entro a mitad
			for _, player in Players:GetPlayers() do
				if not participants[player] then
					Remotes.event("Notify"):FireClient(player, string.format("Son las 6 AM. ¡El equipo completó la noche %d!", night), "good")
				end
			end
			night += 1 -- (sin pausa: runNight empieza ya la preparacion de la siguiente)
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

	-- El anfitrion inicia la partida desde la sala de espera
	Remotes.event("RequestStartGame").OnServerEvent:Connect(function(player: Player)
		-- En las salas del lobby la partida ya viene iniciada
		if RoomService.IsReserved() or phase ~= "Waiting" or startRequested or not DataService.GetData(player) then
			return
		end
		local host = RoomService.GetHost()
		if host and host ~= player then
			Remotes.event("Notify"):FireClient(
				player,
				string.format("Solo el anfitrión (%s) puede iniciar la partida.", host.DisplayName),
				"bad"
			)
			return
		end
		startRequested = true
		notifyAll(player.DisplayName .. " inició la partida.", "good")
	end)

	task.spawn(function()
		while true do
			waitForStart()
			local ok, err = pcall(runGame)
			if not ok then
				warn("[NightManager] Error en la partida:", err)
				BossService.StopNight()
				EventDirector.StopNight()
				EnemyService.StopNight()
				MissionService.StopNight()
				task.wait(3)
			end
		end
	end)
end

return NightManager
