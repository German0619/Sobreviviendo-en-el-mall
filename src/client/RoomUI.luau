-- RoomUI (solo en el mall): datos de la sala, sala de espera y volver al lobby.
--   * Arriba a la izquierda: nombre de la sala y su codigo (para invitar amigos).
--   * Fase Waiting: en una sala del lobby, "llegando jugadores" (la partida ya
--     se inicio en el lobby y empieza sola). En Studio / servidor de prueba, el
--     anfitrion la inicia con INICIAR PARTIDA (tecla P; en movil se toca).
--   * [L]: ventana de confirmacion para volver al lobby (se pierde la partida).
-- Los datos de la sala los publica RoomService en atributos de GameState.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local GameState = require(Shared.GameState)
local UIKit = require(script.Parent.UIKit)

local player = Players.LocalPlayer
local C = UIKit.COLORS

local RoomUI = {}

local infoLabel, window
local waitPanel, waitTitle, waitSubtitle, startButton

local function requestStart()
	Remotes.event("RequestStartGame"):FireServer()
end

local function isHost(): boolean
	return GameState.Folder:GetAttribute("HostUserId") == player.UserId
end

-- Panel de la sala de espera y la tecla P (solo para el anfitrion)
local function updateWaiting()
	local state = GameState.Folder
	local waiting = state:GetAttribute("Phase") == "Waiting"
	waitPanel.Visible = waiting
	-- Sala del lobby: solo esperar a que lleguen todos
	local expected = state:GetAttribute("ExpectedPlayers")
	local fromLobby = type(expected) == "number" and expected > 0
	local host = isHost() and not fromLobby

	if waiting and host then
		ContextActionService:BindAction("StartGame", function(_, inputState)
			if inputState == Enum.UserInputState.Begin then
				requestStart()
			end
			return Enum.ContextActionResult.Pass
		end, false, Enum.KeyCode.P, Enum.KeyCode.ButtonSelect)
	else
		ContextActionService:UnbindAction("StartGame")
	end
	if not waiting then
		return
	end

	startButton.Visible = host
	if fromLobby then
		waitTitle.Text = string.format("LLEGANDO JUGADORES  ·  %d/%d", #Players:GetPlayers(), expected)
		waitSubtitle.Text = "La partida empieza en cuanto lleguen todos."
		return
	end
	waitTitle.Text = string.format("MODO PRUEBA  ·  %d/%d jugadores", #Players:GetPlayers(), Config.MaxPlayersPerRoom)
	if host then
		waitSubtitle.Text = "Eres el anfitrión. Cuando estén todos, inicia la partida."
	else
		local hostPlayer = Players:GetPlayerByUserId(state:GetAttribute("HostUserId") or 0)
		waitSubtitle.Text = string.format(
			"Esperando a que %s inicie la partida...",
			if hostPlayer then hostPlayer.DisplayName else "el anfitrión"
		)
	end
end

local function updateInfo()
	local state = GameState.Folder
	local code = state:GetAttribute("RoomCode")
	if type(code) ~= "string" or code == "" then
		infoLabel.Text = "[L] Volver al lobby"
		return
	end
	infoLabel.Text = string.format(
		'<b>%s</b>  ·  %s  ·  código <font color="#FFC850"><b>%s</b></font>\n<font color="#9696A0">[L] Volver al lobby</font>',
		state:GetAttribute("RoomName") or "Sala",
		if state:GetAttribute("RoomPublic") then "pública" else "privada",
		code
	)
end

function RoomUI.Open()
	window.Visible = true
end

function RoomUI.Close()
	window.Visible = false
end

local function build()
	local gui = UIKit.make("ScreenGui", {
		Name = "RoomUI",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 6,
		Parent = player:WaitForChild("PlayerGui"),
	})

	infoLabel = UIKit.text({
		Position = UDim2.fromOffset(18, 14),
		Size = UDim2.fromOffset(360, 40),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextSize = 14,
		RichText = true,
		TextStrokeTransparency = 0.6,
		Text = "",
		Parent = gui,
	})

	-- Sala de espera
	waitPanel = UIKit.make("Frame", {
		-- Abajo al centro, encima de las lineas de objetos/habilidades del HUD
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -110),
		Size = UDim2.fromOffset(440, 130),
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.15,
		Visible = false,
		Parent = gui,
	}, {
		UIKit.corner(12),
		UIKit.make("UIStroke", { Color = C.Accent, Thickness = 1.5, Transparency = 0.4 }),
	})
	waitTitle = UIKit.text({
		Position = UDim2.fromOffset(0, 10),
		Size = UDim2.new(1, 0, 0, 24),
		TextSize = 20,
		TextColor3 = C.Accent,
		Text = "",
		Parent = waitPanel,
	})
	waitSubtitle = UIKit.text({
		Position = UDim2.fromOffset(12, 36),
		Size = UDim2.new(1, -24, 0, 20),
		TextSize = 14,
		Font = UIKit.FONT_LIGHT,
		TextColor3 = C.Text,
		TextWrapped = true,
		Text = "",
		Parent = waitPanel,
	})
	-- En PC el raton esta bloqueado en primera persona: se usa la tecla P.
	-- En movil/tactil se puede tocar el boton directamente.
	startButton = UIKit.button({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		Size = UDim2.fromOffset(260, 44),
		TextSize = 20,
		Text = "INICIAR PARTIDA  [P]",
		Visible = false,
		Parent = waitPanel,
	}, requestStart)

	-- Confirmacion (el boton X es Modal: libera el raton en primera persona)
	local content
	window, content = UIKit.window(gui, "¿VOLVER AL LOBBY?", Vector2.new(420, 210), RoomUI.Close)
	UIKit.text({
		Size = UDim2.new(1, 0, 0, 60),
		TextSize = 15,
		Font = UIKit.FONT_LIGHT,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Text = "Saldrás de esta partida y perderás los billetes, mejoras y objetos. Tus diamantes y clases se guardan.",
		ZIndex = 22,
		Parent = content,
	})
	UIKit.button({
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(0.5, -6, 0, 40),
		BackgroundColor3 = C.Bad,
		Text = "Volver al lobby",
		ZIndex = 22,
		Parent = content,
	}, function()
		Remotes.event("RequestReturnToLobby"):FireServer()
		RoomUI.Close()
	end)
	UIKit.button({
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.fromScale(1, 1),
		Size = UDim2.new(0.5, -6, 0, 40),
		BackgroundColor3 = C.ButtonOff,
		Text = "Seguir jugando",
		ZIndex = 22,
		Parent = content,
	}, RoomUI.Close)
end

function RoomUI.Start()
	build()
	updateInfo()
	for _, attr in { "RoomCode", "RoomName", "RoomPublic" } do
		GameState.Folder:GetAttributeChangedSignal(attr):Connect(updateInfo)
	end

	updateWaiting()
	GameState.Folder:GetAttributeChangedSignal("Phase"):Connect(updateWaiting)
	GameState.Folder:GetAttributeChangedSignal("HostUserId"):Connect(updateWaiting)
	GameState.Folder:GetAttributeChangedSignal("ExpectedPlayers"):Connect(updateWaiting)
	Players.PlayerAdded:Connect(updateWaiting)
	Players.PlayerRemoving:Connect(function()
		task.delay(0.2, updateWaiting) -- que ya no cuente al que sale
	end)

	ContextActionService:BindAction("ReturnToLobby", function(_, state)
		if state == Enum.UserInputState.Begin then
			if window.Visible then
				RoomUI.Close()
			else
				RoomUI.Open()
			end
		end
		return Enum.ContextActionResult.Pass
	end, true, Enum.KeyCode.L)
	ContextActionService:SetTitle("ReturnToLobby", "Lobby")
	ContextActionService:SetPosition("ReturnToLobby", UDim2.new(0, 20, 0, 70))
end

return RoomUI
