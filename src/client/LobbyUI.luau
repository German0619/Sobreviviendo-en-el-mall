-- LobbyUI (solo en el lobby): menu principal, ventana de salas y tu sala.
--
--   Sin sala:  JUGAR -> ventana SALAS (crear sala publica/privada, unirse con
--              codigo, lista de salas publicas que se refresca sola).
--   Con sala:  panel TU SALA (codigo, miembros) y el boton principal pasa a
--              INICIAR PARTIDA (solo el anfitrion). Todos esperan aqui, en el
--              lobby; al iniciar (o al llenarse la sala) viajan juntos al mall.
--   CLASES -> ClassUI (se puede cambiar de clase mientras esperas).
--   TIENDA -> StoreUI (diamantes, slots y pases con Robux).
--
-- El servidor (LobbyService) valida todo y envia el estado de tu sala por PartyState.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local UIKit = require(script.Parent.UIKit)
local ClassUI = require(script.Parent.ClassUI)
local StoreUI = require(script.Parent.StoreUI)
local HUD = require(script.Parent.HUD)

local player = Players.LocalPlayer
local C = UIKit.COLORS

local LobbyUI = {}

local ROW_HEIGHT = 52

local window, statusLabel, nameBox, publicButton, codeBox, listFrame, emptyLabel
local classInfo, playButton
local partyPanel, partyTitle, partyCode, partyMembers, partyFooter
local party = nil -- estado de tu sala (lo envia el servidor) o nil
local isPublic = true
local busy = false
local listGeneration = 0

----------------------------------------------------------------------
-- Llamadas al servidor
----------------------------------------------------------------------

-- Llama a una RemoteFunction que devuelve (ok, mensaje).
-- El mensaje va a la ventana de salas si esta abierta; si no, como aviso.
local function invoke(remoteName: string, ...): boolean
	if busy then
		return false
	end
	busy = true
	if window.Visible then
		statusLabel.Text = "Conectando..."
		statusLabel.TextColor3 = C.Dim
	end
	local args = table.pack(...)
	local ok, result, message = pcall(function()
		return Remotes.func(remoteName):InvokeServer(table.unpack(args, 1, args.n))
	end)
	busy = false
	if not ok then
		warn("[LobbyUI]", remoteName, "fallo:", result)
		message, result = "Error: " .. tostring(result), false
	end
	local good = result == true
	if window.Visible then
		statusLabel.Text = message or ""
		statusLabel.TextColor3 = if good then C.Good else C.Bad
	elseif message and message ~= "" then
		HUD.Toast(message, if good then "good" else "bad")
	end
	return good
end

----------------------------------------------------------------------
-- Lista de salas publicas
----------------------------------------------------------------------

local function renderList(rooms)
	for _, child in listFrame:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	emptyLabel.Visible = #rooms == 0
	for i, room in rooms do
		local row = UIKit.make("Frame", {
			Size = UDim2.new(1, -8, 0, ROW_HEIGHT - 6),
			BackgroundColor3 = C.Row,
			LayoutOrder = i,
			ZIndex = 23,
			Parent = listFrame,
		}, { UIKit.corner(8) })
		UIKit.text({
			Position = UDim2.fromOffset(12, 4),
			Size = UDim2.new(1, -140, 0, 20),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextSize = 16,
			Text = room.Name,
			ZIndex = 24,
			Parent = row,
		})
		UIKit.text({
			Position = UDim2.fromOffset(12, 24),
			Size = UDim2.new(1, -140, 0, 16),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextSize = 13,
			Font = UIKit.FONT_LIGHT,
			TextColor3 = C.Dim,
			Text = string.format("Anfitrión: %s  ·  %d/%d jugadores", room.HostName, room.Players, room.Max),
			ZIndex = 24,
			Parent = row,
		})
		UIKit.button({
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -8, 0.5, 0),
			Size = UDim2.fromOffset(110, 32),
			Text = "Unirse",
			ZIndex = 24,
			Parent = row,
		}, function()
			invoke("RequestJoinRoom", room.Id)
		end)
	end
	listFrame.CanvasSize = UDim2.fromOffset(0, #rooms * ROW_HEIGHT)
end

local function refreshList()
	local ok, rooms = pcall(function()
		return Remotes.func("RequestRoomList"):InvokeServer()
	end)
	if ok and type(rooms) == "table" then
		renderList(rooms)
	elseif not ok then
		warn("[LobbyUI] RequestRoomList fallo:", rooms)
	end
end

----------------------------------------------------------------------
-- Ventana de salas
----------------------------------------------------------------------

local function updatePublicButton()
	publicButton.Text = if isPublic then "Pública" else "Privada"
	publicButton.BackgroundColor3 = if isPublic then Color3.fromRGB(50, 110, 170) else Color3.fromRGB(120, 70, 150)
end

function LobbyUI.OpenRooms()
	ClassUI.Close()
	StoreUI.Close()
	statusLabel.Text = "Crea una sala y espera aquí a tus amigos, o únete a una."
	statusLabel.TextColor3 = C.Dim
	window.Visible = true

	-- Refrescar la lista mientras la ventana siga abierta
	listGeneration += 1
	local generation = listGeneration
	task.spawn(function()
		while window.Visible and generation == listGeneration do
			refreshList()
			task.wait(Config.Rooms.ListRefreshSeconds)
		end
	end)
end

function LobbyUI.CloseRooms()
	window.Visible = false
	listGeneration += 1
end

local function sectionTitle(parent: Instance, y: number, title: string)
	UIKit.text({
		Position = UDim2.fromOffset(0, y),
		Size = UDim2.new(1, 0, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 14,
		TextColor3 = C.Dim,
		Text = title,
		ZIndex = 22,
		Parent = parent,
	})
end

local function textBox(props)
	local base = {
		BackgroundColor3 = C.Row,
		Font = UIKit.FONT,
		TextColor3 = C.Text,
		PlaceholderColor3 = C.Dim,
		TextSize = 16,
		ClearTextOnFocus = false,
		Text = "",
		ZIndex = 22,
	}
	for k, v in props do
		base[k] = v
	end
	return UIKit.make("TextBox", base, {
		UIKit.corner(6),
		UIKit.make("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }),
	})
end

local function buildRoomsWindow(gui: ScreenGui)
	local content
	window, content = UIKit.window(gui, "SALAS", Vector2.new(640, 540), LobbyUI.CloseRooms)

	-- Crear sala
	sectionTitle(content, 0, string.format("CREAR SALA  (hasta %d jugadores)", Config.MaxPlayersPerRoom))
	nameBox = textBox({
		Position = UDim2.fromOffset(0, 22),
		Size = UDim2.new(1, -270, 0, 36),
		PlaceholderText = "Nombre de la sala (opcional)",
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = content,
	})
	nameBox:GetPropertyChangedSignal("Text"):Connect(function()
		local length = utf8.len(nameBox.Text)
		if length and length > Config.Rooms.NameMaxLength then
			local cut = utf8.offset(nameBox.Text, Config.Rooms.NameMaxLength + 1)
			if cut then
				nameBox.Text = string.sub(nameBox.Text, 1, cut - 1)
			end
		end
	end)
	publicButton = UIKit.button({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -150, 0, 22),
		Size = UDim2.fromOffset(110, 36),
		ZIndex = 22,
		Parent = content,
	}, function()
		isPublic = not isPublic
		updatePublicButton()
	end)
	updatePublicButton()
	UIKit.button({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 22),
		Size = UDim2.fromOffset(140, 36),
		Text = "Crear sala",
		ZIndex = 22,
		Parent = content,
	}, function()
		invoke("RequestCreateRoom", isPublic, nameBox.Text)
	end)

	-- Unirse con codigo
	sectionTitle(content, 72, "UNIRSE CON CÓDIGO")
	codeBox = textBox({
		Position = UDim2.fromOffset(0, 94),
		Size = UDim2.fromOffset(180, 36),
		PlaceholderText = string.rep("X", Config.Rooms.CodeLength),
		Parent = content,
	})
	codeBox:GetPropertyChangedSignal("Text"):Connect(function()
		local clean = string.sub(string.upper((string.gsub(codeBox.Text, "[^%w]", ""))), 1, Config.Rooms.CodeLength)
		if clean ~= codeBox.Text then
			codeBox.Text = clean
		end
	end)
	UIKit.button({
		Position = UDim2.fromOffset(190, 94),
		Size = UDim2.fromOffset(110, 36),
		Text = "Unirse",
		ZIndex = 22,
		Parent = content,
	}, function()
		invoke("RequestJoinByCode", codeBox.Text)
	end)

	-- Salas publicas
	sectionTitle(content, 144, "SALAS PÚBLICAS  (esperando jugadores)")
	UIKit.button({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 140),
		Size = UDim2.fromOffset(110, 26),
		BackgroundColor3 = C.ButtonOff,
		TextSize = 13,
		Text = "Actualizar",
		ZIndex = 22,
		Parent = content,
	}, refreshList)
	listFrame = UIKit.make("ScrollingFrame", {
		Position = UDim2.fromOffset(0, 172),
		Size = UDim2.new(1, 0, 1, -204),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		CanvasSize = UDim2.new(),
		ZIndex = 22,
		Parent = content,
	}, {
		UIKit.make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	emptyLabel = UIKit.text({
		Position = UDim2.fromOffset(0, 190),
		Size = UDim2.new(1, 0, 0, 24),
		TextSize = 15,
		Font = UIKit.FONT_LIGHT,
		TextColor3 = C.Dim,
		Text = "No hay salas públicas esperando jugadores. ¡Crea una!",
		ZIndex = 22,
		Parent = content,
	})

	statusLabel = UIKit.text({
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 22),
		TextSize = 14,
		TextWrapped = true,
		Text = "",
		ZIndex = 22,
		Parent = content,
	})
end

----------------------------------------------------------------------
-- Tu sala
----------------------------------------------------------------------

local function amHost(): boolean
	return party ~= nil and party.HostUserId == player.UserId
end

local function updateParty()
	partyPanel.Visible = party ~= nil
	if not party then
		return
	end

	partyTitle.Text = party.Name
	partyCode.Text = string.format(
		'%s  ·  código <font color="#FFC850"><b>%s</b></font>',
		if party.Public then "Pública" else "Privada",
		party.Code
	)

	local lines = {}
	for i = 1, party.Max do
		local member = party.Members[i]
		if member then
			local isHost = member.UserId == party.HostUserId
			local isMe = member.UserId == player.UserId
			table.insert(
				lines,
				string.format(
					"%s%s%s%s",
					if isHost then '<font color="#FFC850">★</font> ' else "•  ",
					if member.VIP then '<font color="#FFC83C">' .. member.Name .. "</font>" else member.Name,
					if member.VIP then ' <font color="#FFC83C"><b>VIP</b></font>' else "",
					if isMe then ' <font color="#9696A0">(tú)</font>' else ""
				)
			)
		else
			table.insert(lines, '<font color="#5A5A64">•  libre</font>')
		end
	end
	partyMembers.Text = table.concat(lines, "\n")

	if party.State ~= "Open" then
		partyFooter.Text = "¡La partida empieza! Viajando al mall..."
		partyFooter.TextColor3 = C.Good
	elseif amHost() then
		partyFooter.Text = string.format(
			"Eres el anfitrión. Pulsa INICIAR PARTIDA cuando estén todos (empieza sola al llegar a %d).",
			party.Max
		)
		partyFooter.TextColor3 = C.Text
	else
		partyFooter.Text = string.format(
			"Esperando a que %s inicie la partida (empieza sola al llegar a %d).",
			party.HostName,
			party.Max
		)
		partyFooter.TextColor3 = C.Text
	end
end

local function updatePlayButton()
	if not party then
		playButton.Text = "JUGAR"
		playButton.BackgroundColor3 = C.Button
	elseif party.State ~= "Open" then
		playButton.Text = "VIAJANDO..."
		playButton.BackgroundColor3 = C.ButtonOff
	elseif amHost() then
		playButton.Text = string.format("INICIAR PARTIDA  (%d/%d)", #party.Members, party.Max)
		playButton.BackgroundColor3 = C.Button
	else
		playButton.Text = "ESPERANDO AL ANFITRIÓN"
		playButton.BackgroundColor3 = C.ButtonOff
	end
end

local function onPlayPressed()
	if not party then
		if window.Visible then
			LobbyUI.CloseRooms()
		else
			LobbyUI.OpenRooms()
		end
	elseif party.State == "Open" and amHost() then
		invoke("RequestStartRoom")
	elseif party.State == "Open" then
		HUD.Toast(string.format("Solo %s (el anfitrión) puede iniciar la partida.", party.HostName))
	end
end

local function buildPartyPanel(gui: ScreenGui)
	partyPanel = UIKit.make("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 24, 1, -246),
		Size = UDim2.fromOffset(340, 250),
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.15,
		Visible = false,
		Parent = gui,
	}, {
		UIKit.corner(12),
		UIKit.make("UIStroke", { Color = C.Good, Thickness = 1.5, Transparency = 0.5 }),
		UIKit.make("UIPadding", {
			PaddingTop = UDim.new(0, 12),
			PaddingBottom = UDim.new(0, 12),
			PaddingLeft = UDim.new(0, 16),
			PaddingRight = UDim.new(0, 16),
		}),
	})
	UIKit.text({
		Size = UDim2.new(1, 0, 0, 14),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 12,
		TextColor3 = C.Dim,
		Text = "TU SALA",
		Parent = partyPanel,
	})
	partyTitle = UIKit.text({
		Position = UDim2.fromOffset(0, 14),
		Size = UDim2.new(1, 0, 0, 24),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextSize = 20,
		Text = "",
		Parent = partyPanel,
	})
	partyCode = UIKit.text({
		Position = UDim2.fromOffset(0, 38),
		Size = UDim2.new(1, 0, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 14,
		Font = UIKit.FONT_LIGHT,
		RichText = true,
		Text = "",
		Parent = partyPanel,
	})
	partyMembers = UIKit.text({
		Position = UDim2.fromOffset(0, 62),
		Size = UDim2.new(1, 0, 0, 100),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextSize = 15,
		RichText = true,
		LineHeight = 1.15,
		Text = "",
		Parent = partyPanel,
	})
	partyFooter = UIKit.text({
		Position = UDim2.fromOffset(0, 164),
		Size = UDim2.new(1, 0, 0, 34),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextSize = 13,
		Font = UIKit.FONT_LIGHT,
		TextWrapped = true,
		Text = "",
		Parent = partyPanel,
	})
	UIKit.button({
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 28),
		BackgroundColor3 = Color3.fromRGB(120, 45, 45),
		TextSize = 14,
		Text = "Salir de la sala",
		Parent = partyPanel,
	}, function()
		if party and party.State == "Open" then
			invoke("RequestLeaveRoom")
		end
	end)
end

----------------------------------------------------------------------
-- Menu principal
----------------------------------------------------------------------

local function updateClassInfo()
	local def = Config.Classes[player:GetAttribute("EquippedClass") or ""] or Config.Classes[Config.DefaultClass]
	local color = Config.Rarities[def.Rarity].Color
	classInfo.Text = string.format(
		'Entrarás como <font color="#%s"><b>%s</b></font>  (slot %d)',
		color:ToHex(),
		def.DisplayName,
		player:GetAttribute("EquippedSlot") or 1
	)
end

local function buildMenu(gui: ScreenGui)
	local menu = UIKit.make("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 24, 1, -24),
		Size = UDim2.fromOffset(340, 210),
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.15,
		Parent = gui,
	}, {
		UIKit.corner(12),
		UIKit.make("UIStroke", { Color = C.Accent, Thickness = 1.5, Transparency = 0.5 }),
		UIKit.make("UIPadding", {
			PaddingTop = UDim.new(0, 14),
			PaddingBottom = UDim.new(0, 14),
			PaddingLeft = UDim.new(0, 16),
			PaddingRight = UDim.new(0, 16),
		}),
	})
	UIKit.text({
		Size = UDim2.new(1, 0, 0, 26),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = C.Accent,
		Text = "SOBREVIVIENDO EN EL MALL",
		TextScaled = true,
		Parent = menu,
	})
	UIKit.text({
		Position = UDim2.fromOffset(0, 28),
		Size = UDim2.new(1, 0, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 14,
		Font = UIKit.FONT_LIGHT,
		TextColor3 = C.Dim,
		Text = "Sala de descanso · turno de noche",
		Parent = menu,
	})
	classInfo = UIKit.text({
		Position = UDim2.fromOffset(0, 54),
		Size = UDim2.new(1, 0, 0, 20),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 15,
		RichText = true,
		Text = "",
		Parent = menu,
	})
	playButton = UIKit.button({
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, -54),
		Size = UDim2.new(1, 0, 0, 46),
		TextSize = 20,
		Text = "JUGAR",
		Parent = menu,
	}, onPlayPressed)
	UIKit.button({
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(0.5, -4, 0, 44),
		BackgroundColor3 = Color3.fromRGB(110, 70, 160),
		TextSize = 17,
		Text = "CLASES",
		Parent = menu,
	}, function()
		LobbyUI.CloseRooms()
		StoreUI.Close()
		ClassUI.Open()
	end)
	UIKit.button({
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.fromScale(1, 1),
		Size = UDim2.new(0.5, -4, 0, 44),
		BackgroundColor3 = Color3.fromRGB(170, 120, 20),
		TextSize = 17,
		Text = "TIENDA",
		Parent = menu,
	}, function()
		LobbyUI.CloseRooms()
		ClassUI.Close()
		if StoreUI.IsOpen() then
			StoreUI.Close()
		else
			StoreUI.Open()
		end
	end)
end

function LobbyUI.Start()
	local gui = UIKit.make("ScreenGui", {
		Name = "LobbyUI",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 4,
		Parent = player:WaitForChild("PlayerGui"),
	})
	buildRoomsWindow(gui)
	buildPartyPanel(gui)
	buildMenu(gui)

	updateClassInfo()
	player:GetAttributeChangedSignal("EquippedClass"):Connect(updateClassInfo)
	player:GetAttributeChangedSignal("EquippedSlot"):Connect(updateClassInfo)

	Remotes.event("PartyState").OnClientEvent:Connect(function(data)
		local wasInParty = party ~= nil
		party = if type(data) == "table" then data else nil
		if party and not wasInParty then
			LobbyUI.CloseRooms() -- ya estas en una sala: la ventana sobra
		end
		updateParty()
		updatePlayButton()
	end)
	updateParty()
	updatePlayButton()
end

return LobbyUI
