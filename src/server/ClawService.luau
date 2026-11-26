-- ClawService: La Garra (Config.Claw), entidad sin cuerpo que castiga dejar caducar tareas.
--
-- * Cuenta las tareas falladas del equipo (MissionService.Failed) y las completadas por
--   cada jugador esta noche (MissionService.Completed).
-- * Desde Config.Claw.UnlockNight, al llegar a FailsToTrigger falladas se agarra al
--   jugador vivo con MENOS completadas (empate: al azar).
-- * El agarrado tiene Seconds para completar EL MISMO Required tareas. Si no, muere
--   (revivible como cualquier caida: NightManager se encarga al morir el Humanoid).
-- * Se suelta si las completa, si se llega a la cuota (ya no quedan tareas), si cae por
--   otra cosa, si se va del juego o al acabar la noche. Al soltarse, la cuenta de
--   falladas vuelve a 0; las falladas mientras esta agarrada no cuentan.
--
-- Al cliente (client/ClawFX) le llega por atributos del jugador:
--   ClawUntil (hora del servidor del final), ClawDone, ClawNeed; ClawKilledAt al matar.
-- Los demas ven un contorno rojo oscuro en el agarrado (Highlight "ClawMark").

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local GameState = require(Shared.GameState)

local MissionService = require(script.Parent.MissionService)
local DefenseService = require(script.Parent.DefenseService)
local SfxService = require(script.Parent.SfxService)
local BestiaryService = require(script.Parent.BestiaryService)

local ClawService = {}

local MARK_COLOR = Color3.fromRGB(150, 0, 0)

local running = false
local night = 1
local fails = 0 -- falladas desde que empezo la noche o desde que se solto
local completedBy: { [Player]: number } = {} -- tareas completadas esta noche

-- Agarre actual (solo uno a la vez)
local target: Player? = nil
local deadline = 0
local done = 0
local token = 0

local function debugPrint(...)
	if RunService:IsStudio() then
		print("[Garra]", ...)
	end
end

local function notifyAll(text: string, kind: string)
	Remotes.event("Notify"):FireAllClients(text, kind)
end

local function isAlive(player: Player): boolean
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return player.Parent ~= nil
		and player:GetAttribute("Alive") == true
		and humanoid ~= nil
		and humanoid.Health > 0
end

local function failsNeeded(): number
	return Config.Debug.ClawFailsOverride or Config.Claw.FailsToTrigger
end

local function unlocked(): boolean
	return Config.Debug.ClawFailsOverride ~= nil or night >= Config.Claw.UnlockNight
end

local function clearAttributes(player: Player)
	player:SetAttribute("ClawUntil", nil)
	player:SetAttribute("ClawDone", nil)
	player:SetAttribute("ClawNeed", nil)
	local character = player.Character
	local mark = character and character:FindFirstChild("ClawMark")
	if mark then
		mark:Destroy()
	end
end

-- Suelta al agarrado. reason: "done" (cumplio), "quota", "dead", "night", "kill"
local function release(reason: string)
	local player = target
	if not player then
		return
	end
	target = nil
	token += 1
	fails = 0
	clearAttributes(player)
	debugPrint("suelta a", player.Name, "(" .. reason .. ")")
	if reason == "done" then
		notifyAll(string.format("La Garra soltó a %s.", player.DisplayName), "good")
	elseif reason == "quota" and player.Parent then
		Remotes.event("Notify"):FireClient(player, "La Garra te soltó: ya no quedan tareas.", "good")
	end
end

local function kill(player: Player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 then
		release("dead")
		return
	end
	-- Antes de soltar: el cliente cierra las manos de golpe en vez de quitarlas
	player:SetAttribute("ClawKilledAt", Workspace:GetServerTimeNow())
	release("kill")
	if root then
		SfxService.PlayAt("ClawKill", root :: BasePart)
	end
	if DefenseService.IsHidden(player) then
		DefenseService.ForceOut(player)
	end
	notifyAll(string.format("La Garra se llevó a %s.", player.DisplayName), "bad")
	debugPrint("mata a", player.Name)
	humanoid.Health = 0
end

-- Jugador vivo con menos tareas completadas esta noche (empate: al azar).
local function pickTarget(): Player?
	local best: { Player } = {}
	local bestCount = math.huge
	for _, player in Players:GetPlayers() do
		if isAlive(player) then
			local count = completedBy[player] or 0
			if count < bestCount then
				best, bestCount = { player }, count
			elseif count == bestCount then
				table.insert(best, player)
			end
		end
	end
	if #best == 0 then
		return nil
	end
	return best[math.random(1, #best)]
end

local function grab()
	local player = pickTarget()
	if not player then
		return
	end
	local def = Config.Claw
	target = player
	done = 0
	deadline = Workspace:GetServerTimeNow() + def.Seconds
	token += 1
	local myToken = token

	-- (Sin aviso de como funciona: el atrapado la descubre en el bestiario)
	BestiaryService.Discover(player, "Claw")

	player:SetAttribute("ClawNeed", def.Required)
	player:SetAttribute("ClawDone", 0)
	player:SetAttribute("ClawUntil", deadline)
	local character = player.Character
	if character then
		local mark = Instance.new("Highlight")
		mark.Name = "ClawMark"
		mark.FillColor = MARK_COLOR
		mark.FillTransparency = 0.75
		mark.OutlineColor = MARK_COLOR
		mark.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		mark.Parent = character
		local root = character:FindFirstChild("HumanoidRootPart")
		if root then
			SfxService.PlayAt("ClawGrab", root :: BasePart)
		end
	end

	Remotes.event("Notify"):FireClient(
		player,
		string.format("¡La Garra te atrapó! Completa %d tareas tú mismo en %d segundos o te llevará.", def.Required, def.Seconds),
		"bad"
	)
	for _, other in Players:GetPlayers() do
		if other ~= player then
			Remotes.event("Notify"):FireClient(
				other,
				string.format("La Garra atrapó a %s: tiene %d s para completar %d tareas. ¡Cúbrele!", player.DisplayName, def.Seconds, def.Required),
				"bad"
			)
		end
	end
	debugPrint(string.format("agarra a %s (%d completadas esta noche)", player.Name, completedBy[player] or 0))

	-- Cuenta atras
	task.spawn(function()
		while token == myToken and target == player do
			if not isAlive(player) then
				release("dead")
				return
			end
			if Workspace:GetServerTimeNow() >= deadline then
				kill(player)
				return
			end
			task.wait(0.2)
		end
	end)
end

local function onFailed()
	if not running or target or not unlocked() then
		return
	end
	fails += 1
	debugPrint(string.format("tarea fallada (%d/%d)", fails, failsNeeded()))
	if fails >= failsNeeded() then
		grab()
	end
end

local function onCompleted(_mission, player: Player)
	if not running then
		return
	end
	completedBy[player] = (completedBy[player] or 0) + 1
	if target == nil then
		return
	end
	if player == target then
		done += 1
		player:SetAttribute("ClawDone", done)
		debugPrint(string.format("%s lleva %d/%d", player.Name, done, Config.Claw.Required))
		if done >= Config.Claw.Required then
			release("done")
			return
		end
	end
	-- Cuota completa: ya no salen tareas, no tendria como librarse
	local doneCount, goal = MissionService.GetProgress()
	if doneCount >= goal then
		release("quota")
	end
end

local function startNight()
	running = true
	night = GameState.Folder:GetAttribute("Night") or 1
	fails = 0
	completedBy = {}
	debugPrint(string.format("noche %d (%s)", night, if unlocked() then "activa" else "aun no sale"))
	-- Prueba: agarrar sola al empezar la noche
	local delaySeconds = Config.Debug.ClawGrabOnStart
	if delaySeconds and RunService:IsStudio() then
		task.delay(delaySeconds, function()
			if running and not target then
				debugPrint("agarre de prueba (Config.Debug.ClawGrabOnStart)")
				grab()
			end
		end)
	end
end

local function stopNight()
	running = false
	release("night")
	fails = 0
	completedBy = {}
end

function ClawService.Start()
	MissionService.Failed:Connect(onFailed)
	MissionService.Completed:Connect(onCompleted)
	-- La noche la marca NightManager con el atributo Phase de GameState
	local folder = GameState.Folder
	folder:GetAttributeChangedSignal("Phase"):Connect(function()
		if folder:GetAttribute("Phase") == "Night" then
			startNight()
		elseif running then
			stopNight()
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		completedBy[player] = nil
		if player == target then
			release("dead")
		end
	end)

	-- SOLO en Studio: ServerStorage.DebugClaw:Invoke() la agarra ya (durante la noche),
	-- desde la barra de comandos del servidor o el MCP.
	if RunService:IsStudio() then
		local debugGrab = Instance.new("BindableFunction")
		debugGrab.Name = "DebugClaw"
		debugGrab.OnInvoke = function(): boolean
			if not running or target then
				return false
			end
			grab()
			return target ~= nil
		end
		debugGrab.Parent = game:GetService("ServerStorage")
	end
end

return ClawService
