-- HUD: hora, noche, fase, dinero, barras (vida/estamina/bateria), tareas,
-- avisos y pantalla de resultados. Todo construido por codigo.
-- En el lobby solo muestra avisos, diamantes y la clase equipada.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Tags = require(Shared.Tags)
local Util = require(Shared.Util)
local Remotes = require(Shared.Remotes)
local GameState = require(Shared.GameState)
local Place = require(Shared.Place)
local UIKit = require(script.Parent.UIKit)
local InputHints = require(script.Parent.InputHints)

local player = Players.LocalPlayer

local HUD = {}

local COLORS = {
	Panel = Color3.fromRGB(12, 12, 16),
	Text = Color3.fromRGB(235, 235, 235),
	Dim = Color3.fromRGB(150, 150, 160),
	Health = Color3.fromRGB(205, 55, 55),
	Stamina = Color3.fromRGB(230, 190, 60),
	Battery = Color3.fromRGB(120, 190, 255),
	Good = Color3.fromRGB(90, 210, 120),
	Bad = Color3.fromRGB(230, 80, 80),
	Accent = Color3.fromRGB(255, 200, 80),
	Event = Color3.fromRGB(190, 120, 255), -- avisos y misiones de evento
}

-- Color de la linea del evento activo segun su tipo (Config.Events[x].Kind)
local EVENT_KIND_COLORS = {
	Bad = Color3.fromRGB(240, 90, 90),
	Good = Color3.fromRGB(100, 220, 130),
	Mixed = Color3.fromRGB(240, 190, 70),
}
local EVENT_SOUND = "rbxasset://sounds/electronicpingshort.wav"
local FLOOR_NAMES = { "planta baja", "planta alta" }

local PHASE_NAMES = {
	Waiting = "Esperando jugadores",
	Preparation = "Preparación",
	Night = "Turno nocturno",
	Results = "Resultados",
	Upgrades = "Mejoras",
	GameOver = "Fin del turno",
}

local FONT = Enum.Font.GothamBold
local FONT_LIGHT = Enum.Font.Gotham

----------------------------------------------------------------------
-- Helpers de UI
----------------------------------------------------------------------

local function make(className: string, props, children)
	local inst = Instance.new(className)
	for k, v in props do
		if k ~= "Parent" then
			inst[k] = v
		end
	end
	for _, child in children or {} do
		child.Parent = inst
	end
	if props.Parent then
		inst.Parent = props.Parent
	end
	return inst
end

local function corner(radius: number?)
	return make("UICorner", { CornerRadius = UDim.new(0, radius or 8) })
end

local function text(props)
	local base = {
		BackgroundTransparency = 1,
		Font = FONT,
		TextColor3 = COLORS.Text,
		TextSize = 18,
		TextStrokeTransparency = 0.6,
	}
	for k, v in props do
		base[k] = v
	end
	return make("TextLabel", base)
end

local function formatTime(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

local function makeBar(parent, labelText: string, color: Color3, order: number)
	local frame = make("Frame", {
		Name = labelText,
		Size = UDim2.new(1, 0, 0, 24),
		BackgroundColor3 = COLORS.Panel,
		BackgroundTransparency = 0.25,
		LayoutOrder = order,
		Parent = parent,
	}, { corner(6) })
	local fill = make("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Parent = frame,
	}, { corner(6) })
	local label = text({
		Size = UDim2.new(1, -12, 1, 0),
		Position = UDim2.fromOffset(8, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 14,
		Text = labelText,
		ZIndex = 2,
		Parent = frame,
	})
	return {
		Set = function(ratio: number, caption: string)
			fill.Size = UDim2.fromScale(math.clamp(ratio, 0, 1), 1)
			label.Text = caption
		end,
		Fill = fill,
	}
end

----------------------------------------------------------------------
-- Construccion
----------------------------------------------------------------------

local eventLabel
local gui, clockLabel, nightLabel, phaseLabel, moneyLabel, zoneLabel, itemsLabel, sodaLabel, classLabel, barsFrame
local diamondsLabel, deadSubtitle, reviveButton, missionsTitle
local bars = {}
local missionList, missionEntries = nil, {}
local toastList
local resultsPanel, resultsTitle, resultsBody
local deadOverlay
local nightOnly = {} -- elementos que no se muestran en el lobby

local function build()
	gui = make("ScreenGui", {
		Name = "HUD",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = player:WaitForChild("PlayerGui"),
	})
	UIKit.adapt(gui) -- escala segun la pantalla y respeta el notch

	-- Arriba al centro: reloj, noche, fase
	local top = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 14),
		Size = UDim2.fromOffset(420, 136),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	table.insert(nightOnly, top)
	clockLabel = text({ Size = UDim2.new(1, 0, 0, 40), TextSize = 38, Text = "12:00 AM", Parent = top })
	nightLabel = text({
		Position = UDim2.fromOffset(0, 40),
		Size = UDim2.new(1, 0, 0, 20),
		TextSize = 16,
		TextColor3 = COLORS.Accent,
		Text = "NOCHE 1",
		Parent = top,
	})
	phaseLabel = text({
		Position = UDim2.fromOffset(0, 62),
		Size = UDim2.new(1, 0, 0, 20),
		TextSize = 14,
		Font = FONT_LIGHT,
		TextColor3 = COLORS.Dim,
		Text = "",
		Parent = top,
	})
	-- Evento activo (EventDirector): nombre, planta y tiempo que le queda.
	-- Debajo de la linea de habilidades (Defense: "Destello [G]", a 98 px de arriba)
	eventLabel = text({
		Position = UDim2.fromOffset(0, 110),
		Size = UDim2.new(1, 0, 0, 22),
		TextSize = 16,
		RichText = true,
		Text = "",
		Visible = false,
		Parent = top,
	})

	-- Arriba a la derecha: dinero
	moneyLabel = text({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -18, 0, 14),
		Size = UDim2.fromOffset(220, 34),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextSize = 26,
		TextColor3 = COLORS.Accent,
		Text = "$0",
		Parent = gui,
	})
	table.insert(nightOnly, moneyLabel)

	-- Debajo de los billetes: diamantes y clase equipada
	diamondsLabel = text({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -18, 0, 46),
		Size = UDim2.fromOffset(220, 20),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextSize = 16,
		TextColor3 = Color3.fromRGB(110, 220, 255),
		Text = "",
		Parent = gui,
	})
	classLabel = text({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -18, 0, 66),
		Size = UDim2.fromOffset(220, 20),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextSize = 15,
		Text = "",
		Parent = gui,
	})

	-- Columna de estado: sodas, arma, zona y barras. Abajo a la izquierda con teclado
	-- o mando; arriba a la izquierda en tactil (abajo esta el joystick).
	-- Abajo al centro queda libre para la mochila nativa de Roblox (objetos y armas).
	barsFrame = make("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 18, 1, -18),
		Size = UDim2.fromOffset(280, 170),
		BackgroundTransparency = 1,
		Parent = gui,
	}, {
		make("UIListLayout", {
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
			VerticalAlignment = Enum.VerticalAlignment.Bottom,
		}),
	})
	table.insert(nightOnly, barsFrame)
	sodaLabel = text({
		Size = UDim2.new(1, 0, 0, 18),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		TextSize = 14,
		Text = "",
		RichText = true, -- cada soda con su color
		LayoutOrder = -2,
		Parent = barsFrame,
	})
	itemsLabel = text({ -- estado del arma (usos, espera)
		Size = UDim2.new(1, 0, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 14,
		Text = "",
		LayoutOrder = -1,
		Parent = barsFrame,
	})
	zoneLabel = text({
		Size = UDim2.new(1, 0, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 14,
		Font = FONT_LIGHT,
		TextColor3 = COLORS.Dim,
		RichText = true, -- (el aviso PROTEGIDO va en azul)
		Text = "",
		LayoutOrder = 0,
		Parent = barsFrame,
	})
	bars.Health = makeBar(barsFrame, "VIDA", COLORS.Health, 1)
	bars.Stamina = makeBar(barsFrame, "ESTAMINA", COLORS.Stamina, 2)
	bars.Battery = makeBar(barsFrame, "BATERÍA", COLORS.Battery, 3)

	-- Derecha: tareas
	local missionsFrame = make("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -18, 0, 94),
		Size = UDim2.fromOffset(290, 360),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	table.insert(nightOnly, missionsFrame)
	missionsTitle = text({
		Size = UDim2.new(1, 0, 0, 22),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextSize = 16,
		Text = "TAREAS",
		RichText = true,
		Parent = missionsFrame,
	})
	missionList = make("Frame", {
		Position = UDim2.fromOffset(0, 26),
		Size = UDim2.new(1, 0, 1, -26),
		BackgroundTransparency = 1,
		Parent = missionsFrame,
	}, {
		make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
	})

	-- Avisos
	toastList = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 112),
		Size = UDim2.fromOffset(520, 220),
		BackgroundTransparency = 1,
		Parent = gui,
	}, {
		make("UIListLayout", {
			Padding = UDim.new(0, 6),
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})

	-- Pantalla de muerte
	deadOverlay = make("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		Visible = false,
		ZIndex = 5,
		Parent = gui,
	})
	text({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromOffset(600, 50),
		TextSize = 40,
		TextColor3 = COLORS.Bad,
		Text = "HAS CAÍDO",
		ZIndex = 6,
		Parent = deadOverlay,
	})
	deadSubtitle = text({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.45, 44),
		Size = UDim2.fromOffset(640, 30),
		TextSize = 18,
		Font = FONT_LIGHT,
		Text = "",
		ZIndex = 6,
		Parent = deadOverlay,
	})
	-- Boton para revivirse (Modal: libera el raton en primera persona)
	reviveButton = make("TextButton", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.45, 100),
		Size = UDim2.fromOffset(260, 44),
		BackgroundColor3 = Color3.fromRGB(0, 140, 70),
		Font = FONT,
		TextSize = 18,
		TextColor3 = COLORS.Text,
		Text = "Revivir (Robux)",
		Modal = true,
		ZIndex = 7,
		Parent = deadOverlay,
	}, { corner(8) })
	reviveButton.Activated:Connect(function()
		Remotes.event("RequestSelfRevive"):FireServer()
	end)

	-- Resultados
	resultsPanel = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(380, 290),
		BackgroundColor3 = COLORS.Panel,
		BackgroundTransparency = 0.08,
		Visible = false,
		ZIndex = 10,
		Parent = gui,
	}, {
		corner(12),
		make("UIStroke", { Color = COLORS.Accent, Thickness = 1.5, Transparency = 0.4 }),
		make("UIPadding", {
			PaddingTop = UDim.new(0, 18),
			PaddingBottom = UDim.new(0, 18),
			PaddingLeft = UDim.new(0, 22),
			PaddingRight = UDim.new(0, 22),
		}),
	})
	resultsTitle = text({
		Size = UDim2.new(1, 0, 0, 34),
		TextSize = 26,
		Text = "",
		ZIndex = 11,
		Parent = resultsPanel,
	})
	resultsBody = text({
		Position = UDim2.fromOffset(0, 46),
		Size = UDim2.new(1, 0, 1, -46),
		TextSize = 18,
		Font = FONT_LIGHT,
		RichText = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		LineHeight = 1.25,
		Text = "",
		ZIndex = 11,
		Parent = resultsPanel,
	})
end

----------------------------------------------------------------------
-- Tareas
----------------------------------------------------------------------

local function addMissionEntry(value: Instance)
	-- Misiones de evento (EventDirector): arriba del todo, en morado y sin pago
	local isEvent = value:GetAttribute("Event") == true
	local order = tonumber(string.sub(value.Name, 2)) or 0
	local frame = make("Frame", {
		Size = UDim2.new(1, 0, 0, 48),
		BackgroundColor3 = if isEvent then Color3.fromRGB(40, 20, 60) else COLORS.Panel,
		BackgroundTransparency = 0.25,
		LayoutOrder = if isEvent then order - 100000 else order,
		Parent = missionList,
	}, {
		corner(8),
		isEvent and make("UIStroke", { Color = COLORS.Event, Thickness = 1.5, Transparency = 0.2 }) or nil,
	})
	text({
		Position = UDim2.fromOffset(10, 4),
		Size = UDim2.new(1, -20, 0, 22),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 16,
		TextColor3 = if isEvent then COLORS.Event else COLORS.Text,
		Text = (if isEvent then "EVENTO · " else "") .. (value:GetAttribute("DisplayName") or "?"),
		Parent = frame,
	})
	local detail = text({
		Position = UDim2.fromOffset(10, 25),
		Size = UDim2.new(1, -20, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 13,
		Font = FONT_LIGHT,
		TextColor3 = COLORS.Dim,
		Text = "",
		Parent = frame,
	})
	missionEntries[value] = { Frame = frame, Detail = detail }
end

local function removeMissionEntry(value: Instance)
	local entry = missionEntries[value]
	if entry then
		entry.Frame:Destroy()
		missionEntries[value] = nil
	end
end

local function updateMissions(now: number)
	-- Hora de oro: las tareas pagan x RewardMultiplier
	local multiplier = GameState.Folder:GetAttribute("RewardMultiplier")
	for value, entry in missionEntries do
		local remaining = (value:GetAttribute("ExpiresAt") or now) - now
		local progress = value:GetAttribute("Progress")
		local pay
		if value:GetAttribute("Event") == true then
			pay = "sin pago"
		else
			local reward = value:GetAttribute("Reward") or 0
			pay = if type(multiplier) == "number"
				then string.format("+%s x%g", Util.formatMoney(math.floor(reward * multiplier)), multiplier)
				else "+" .. Util.formatMoney(reward)
		end
		entry.Detail.Text = string.format(
			"%s%s  ·  %s  ·  %s",
			if type(progress) == "string" then progress .. "  ·  " else "",
			value:GetAttribute("Zone") or "?",
			formatTime(remaining),
			pay
		)
		entry.Detail.TextColor3 = if remaining <= 15 then COLORS.Bad else COLORS.Dim
	end
end

----------------------------------------------------------------------
-- Avisos y resultados
----------------------------------------------------------------------

local toastOrder = 0

local function toast(message: string, kind: string?)
	toastOrder += 1
	local color = if kind == "good"
		then COLORS.Good
		elseif kind == "bad" then COLORS.Bad
		elseif kind == "event" then COLORS.Event
		else COLORS.Text
	local label = text({
		Size = UDim2.fromOffset(0, 30),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = COLORS.Panel,
		BackgroundTransparency = 0.3,
		TextSize = 16,
		TextColor3 = color,
		Text = message,
		LayoutOrder = toastOrder,
		Parent = toastList,
	})
	corner(8).Parent = label
	make("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12), Parent = label })

	-- Maximo 4 avisos a la vez
	local labels = {}
	for _, child in toastList:GetChildren() do
		if child:IsA("TextLabel") then
			table.insert(labels, child)
		end
	end
	table.sort(labels, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	for i = 1, #labels - 4 do
		labels[i]:Destroy()
	end

	task.delay(4, function()
		if label.Parent then
			local info = TweenInfo.new(0.6)
			TweenService:Create(label, info, { TextTransparency = 1, BackgroundTransparency = 1, TextStrokeTransparency = 1 })
				:Play()
			task.wait(0.6)
			label:Destroy()
		end
	end)
end

-- Aviso local (lo usan otros modulos del cliente)
function HUD.Toast(message: string, kind: string?)
	if toastList then
		toast(message, kind)
	else
		-- En el lobby este HUD no se arranca (lo reemplaza LobbyHUD): aviso nativo.
		pcall(function()
			game:GetService("StarterGui"):SetCore("SendNotification", {
				Title = "Plaza Luna",
				Text = message,
				Duration = 4,
			})
		end)
	end
end

local function showResults(data)
	local title
	if data.GameOver then
		title = "FIN DEL TURNO"
		resultsTitle.TextColor3 = COLORS.Bad
	elseif data.Survived then
		title = string.format("NOCHE %d SUPERADA", data.Night)
		resultsTitle.TextColor3 = COLORS.Good
	else
		title = string.format("CAÍSTE EN LA NOCHE %d", data.Night)
		resultsTitle.TextColor3 = COLORS.Bad
	end
	resultsTitle.Text = title

	-- Cayo todo el equipo: sin pago
	if data.GameOver then
		local goal = GameState.Folder:GetAttribute("MissionGoal") or 0
		local done = math.min(GameState.Folder:GetAttribute("MissionsDone") or 0, goal)
		resultsBody.Text = table.concat({
			string.format("Todo el equipo cayó en la noche %d.", data.Night),
			string.format("Tareas completadas: <b>%d/%d</b>", done, goal),
			"",
			"Sin pago esta noche.",
			"Volviendo al lobby en breve...",
		}, "\n")
		resultsPanel.Visible = true
		return
	end

	local lines = {
		string.format("Pago base: <b>%s</b>", Util.formatMoney(data.Base)),
		string.format(
			"Tareas: <b>%s</b>  <font color=\"#9696A0\">(tu parte de %s entre %d)</font>",
			Util.formatMoney(data.Missions),
			Util.formatMoney(data.MissionsPool or data.Missions),
			data.TeamSize or 1
		),
		string.format("Noche completada: <b>%s</b>", Util.formatMoney(data.Survival)),
	}
	if data.Bonus > 0 then
		table.insert(lines, string.format("Bonus de clase: <b>%s</b>", Util.formatMoney(data.Bonus)))
	end
	if (data.PassBonus or 0) > 0 then
		table.insert(lines, string.format('<font color="#FFC850">Pase x2 Billetes: <b>%s</b></font>', Util.formatMoney(data.PassBonus)))
	end
	table.insert(lines, "")
	table.insert(lines, string.format('<font size="24" color="#FFC850"><b>TOTAL: %s</b></font>', Util.formatMoney(data.Total)))
	resultsBody.Text = table.concat(lines, "\n")
	resultsPanel.Visible = true
end

----------------------------------------------------------------------
-- Actualizacion
----------------------------------------------------------------------

-- Lobby: solo diamantes y clase equipada
local function updateLobby()
	local classDef = Config.Classes[player:GetAttribute("EquippedClass") or ""]
	if classDef and not player:GetAttribute("SpinAnimating") then
		classLabel.Text = classDef.DisplayName
		classLabel.TextColor3 = Config.Rarities[classDef.Rarity].Color
	end
	diamondsLabel.Text = string.format("◆ %d", player:GetAttribute("Diamonds") or 0)
end

local function update()
	if Place.IsLobby then
		updateLobby()
		return
	end
	local state = GameState.Folder
	local now = Workspace:GetServerTimeNow()
	local phase = state:GetAttribute("Phase") or "Waiting"

	clockLabel.Text = Util.formatGameHour(state:GetAttribute("GameHour") or 0)
	nightLabel.Text = "NOCHE " .. tostring(state:GetAttribute("Night") or 1)

	local endsAt = state:GetAttribute("PhaseEndsAt") or 0
	local phaseText = PHASE_NAMES[phase] or phase
	if endsAt > 0 and phase ~= "Night" then
		phaseText ..= "  ·  " .. formatTime(endsAt - now)
	end
	if phase ~= "Night" then
		-- (las clases solo se cambian en el lobby)
		phaseText ..= "   ·   " .. InputHints.Label("Upgrades", "Mejoras")
	end
	phaseLabel.Text = phaseText

	-- Jefe (noche de jefe): "☠ EL GERENTE · Radios destruidas 1/3"; si no, el evento activo:
	-- "APAGÓN GENERAL (planta alta) · 1:23"
	local bossName = state:GetAttribute("BossName")
	local eventName = state:GetAttribute("EventName")
	if type(bossName) == "string" and phase == "Night" then
		if state:GetAttribute("BossDefeated") == true then
			eventLabel.Text = string.upper(bossName) .. " VENCIDO"
			eventLabel.TextColor3 = COLORS.Good
		else
			local progress = state:GetAttribute("BossProgress")
			eventLabel.Text = "☠ " .. string.upper(bossName) .. (if type(progress) == "string" and progress ~= "" then "  ·  " .. progress else "")
			eventLabel.TextColor3 = COLORS.Bad
		end
		eventLabel.Visible = true
	elseif type(eventName) == "string" and phase == "Night" then
		local floor = state:GetAttribute("EventFloor")
		local eventEnds = state:GetAttribute("EventEndsAt") or 0
		local textValue = string.upper(eventName)
		if type(floor) == "number" and FLOOR_NAMES[floor] then
			textValue ..= " (" .. FLOOR_NAMES[floor] .. ")"
		end
		if eventEnds > 0 then
			textValue ..= "  ·  " .. formatTime(eventEnds - now)
		end
		eventLabel.Text = "⚠ " .. textValue
		eventLabel.TextColor3 = EVENT_KIND_COLORS[state:GetAttribute("EventKind") or ""] or COLORS.Event
		eventLabel.Visible = true
	else
		eventLabel.Visible = false
	end

	local classDef = Config.Classes[player:GetAttribute("EquippedClass") or ""]
	if classDef and not player:GetAttribute("SpinAnimating") then
		classLabel.Text = classDef.DisplayName
		classLabel.TextColor3 = Config.Rarities[classDef.Rarity].Color
	end

	-- Los objetos y el arma estan en la mochila nativa (abajo). Aqui solo el estado
	-- del arma: usos, luz UV y espera.
	local weaponId = player:GetAttribute("Weapon")
	local weaponItem = if type(weaponId) == "string" then Config.ShopItems[weaponId] else nil
	if weaponItem then
		local weaponText = weaponItem.DisplayName
		if weaponId == "UVFlashlight" then
			weaponText ..= if player:GetAttribute("UVOn") == true then "  ·  UV encendida" else "  ·  UV apagada"
		else
			local uses = player:GetAttribute("WeaponUses") or -1
			if uses >= 0 then
				weaponText ..= string.format("  ·  %d usos", uses)
			end
		end
		local readyIn = (player:GetAttribute("WeaponReadyAt") or 0) - now
		weaponText ..= if readyIn > 0.05 then string.format("  ·  %d s", math.ceil(readyIn)) else "  ·  lista"
		itemsLabel.Text = weaponText
		itemsLabel.TextColor3 = if readyIn > 0.05 then COLORS.Dim else COLORS.Good
	else
		itemsLabel.Text = ""
	end

	-- Sodas activas (positiva en verde, negativas acumuladas en rojo, cada una con su tiempo)
	local sodas = {}
	for name, value in player:GetAttributes() do
		if string.sub(name, 1, 9) == "SodaEnds_" and type(value) == "number" and value > now then
			local id = string.sub(name, 10)
			local effect = Config.SodaEffects[id]
			if effect then
				table.insert(sodas, { Effect = effect, Remaining = value - now })
			end
		end
	end
	table.sort(sodas, function(a, b)
		if a.Effect.Positive ~= b.Effect.Positive then
			return a.Effect.Positive
		end
		return a.Remaining > b.Remaining
	end)
	local parts = {}
	for _, s in sodas do
		local hex = if s.Effect.Positive then "#6EDC82" else "#EB6464"
		table.insert(parts, string.format('<font color="%s">%s %ds</font>', hex, s.Effect.DisplayName, math.ceil(s.Remaining)))
	end
	sodaLabel.Text = if #parts > 0 then "Sodas: " .. table.concat(parts, "  ·  ") else ""

	moneyLabel.Text = Util.formatMoney(player:GetAttribute("Money") or 0)
	diamondsLabel.Text = string.format("◆ %d", player:GetAttribute("Diamonds") or 0)

	-- Barras
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		bars.Health.Set(
			humanoid.Health / math.max(humanoid.MaxHealth, 1),
			string.format("VIDA  %d / %d", math.ceil(humanoid.Health), humanoid.MaxHealth)
		)
	end
	local maxStamina = player:GetAttribute("MaxStamina") or Config.Stats.Stamina.Base
	local stamina = player:GetAttribute("Stamina") or maxStamina
	bars.Stamina.Set(stamina / maxStamina, if player:GetAttribute("Exhausted") then "ESTAMINA  (agotado)" else "ESTAMINA")
	bars.Stamina.Fill.BackgroundColor3 = if player:GetAttribute("Exhausted") then COLORS.Bad else COLORS.Stamina

	local maxBattery = player:GetAttribute("MaxBattery") or Config.Stats.Battery.Base
	local battery = player:GetAttribute("Battery") or 0
	local on = player:GetAttribute("FlashlightOn") == true
	bars.Battery.Set(
		battery / maxBattery,
		string.format("BATERÍA  %d%%  %s", math.floor(battery / maxBattery * 100), InputHints.Label("Flashlight", if on then "ON" else "OFF"))
	)

	-- Zona actual y si esta sin luz
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local zoneName = nil
	if root then
		for _, inst in CollectionService:GetTagged(Tags.Zone) do
			if inst:IsA("BasePart") then
				local rel = inst.CFrame:PointToObjectSpace(root.Position)
				local half = inst.Size / 2
				if math.abs(rel.X) <= half.X and math.abs(rel.Y) <= half.Y and math.abs(rel.Z) <= half.Z then
					zoneName = inst:GetAttribute("Zone")
					break
				end
			end
		end
	end
	local zoneText, zoneBad = "", false
	if zoneName then
		local key = Util.attributeKey(zoneName)
		local dark = state:GetAttribute("Dark_" .. key) == true
		if state:GetAttribute("Ambient_" .. key) == true then
			-- Zona de servicio: oscura siempre (no es un apagon)
			zoneText = zoneName .. "  ·  SIN LUZ: enciende la linterna"
		else
			zoneText = if dark then zoneName .. "  ·  SIN LUZ" else zoneName
		end
		zoneBad = dark
	end
	-- Escudo al revivir pagando: los enemigos te ignoran (ReviveService)
	local protectedUntil = player:GetAttribute("ProtectedUntil")
	if type(protectedUntil) == "number" and protectedUntil > now then
		local shieldText = string.format('<font color="#8CD2FF">PROTEGIDO %ds</font>', math.ceil(protectedUntil - now))
		zoneText = if zoneText ~= "" then zoneText .. "  ·  " .. shieldText else shieldText
	end
	-- Olor de derrame: el Rastro te sigue (Tracker)
	local scentUntil = player:GetAttribute("ScentUntil")
	if type(scentUntil) == "number" and scentUntil > now then
		local scentText = string.format("OLOR A DERRAME %ds", math.ceil(scentUntil - now))
		zoneText = if zoneText ~= "" then zoneText .. "  ·  " .. scentText else scentText
		zoneBad = true
	end
	zoneLabel.Text = zoneText
	zoneLabel.TextColor3 = if zoneBad then COLORS.Bad else COLORS.Dim

	updateMissions(now)
	-- Cuota del equipo
	local goal = state:GetAttribute("MissionGoal") or 0
	if phase == "Night" and goal > 0 then
		local done = math.min(state:GetAttribute("MissionsDone") or 0, goal)
		missionsTitle.Text = string.format('TAREAS DEL EQUIPO  <font color="#FFC850">%d/%d</font>', done, goal)
	else
		missionsTitle.Text = "TAREAS"
	end

	-- Overlays
	deadOverlay.Visible = phase == "Night" and player:GetAttribute("Alive") == false and humanoid ~= nil
		and humanoid.Health <= 0
	if deadOverlay.Visible then
		local downed = player:GetAttribute("Downed") == true
		local tokens = player:GetAttribute("ReviveTokens") or 0
		local wipeAt = state:GetAttribute("WipeAt")
		reviveButton.Visible = downed
		reviveButton.Text = if tokens > 0 then string.format("Revivir (ficha, tienes %d)", tokens) else "Revivir (Robux)"
		if type(wipeAt) == "number" then
			deadSubtitle.Text = string.format("Todo el equipo cayó. %d s para revivir.", math.max(0, math.ceil(wipeAt - now)))
			deadSubtitle.TextColor3 = COLORS.Bad
		else
			deadSubtitle.Text = "Un Médico puede revivirte gratis, o con Robux. Si no, volverás en la próxima noche."
			deadSubtitle.TextColor3 = COLORS.Text
		end
	end
	if phase ~= "Results" and phase ~= "GameOver" and phase ~= "Upgrades" then
		resultsPanel.Visible = false
	end
end

function HUD.Start()
	build()

	if Place.IsLobby then
		for _, element in nightOnly do
			element.Visible = false
		end
		diamondsLabel.Position = UDim2.new(1, -18, 0, 14)
		diamondsLabel.TextSize = 22
		classLabel.Position = UDim2.new(1, -18, 0, 40)
		classLabel.TextSize = 17
	end

	-- Tactil: la columna de estado arriba a la izquierda (abajo esta el joystick)
	local function applyLayout()
		local layout = barsFrame:FindFirstChildOfClass("UIListLayout")
		if InputHints.IsTouch() then
			barsFrame.AnchorPoint = Vector2.new(0, 0)
			barsFrame.Position = UDim2.new(0, 18, 0, 10)
			layout.VerticalAlignment = Enum.VerticalAlignment.Top
		else
			barsFrame.AnchorPoint = Vector2.new(0, 1)
			barsFrame.Position = UDim2.new(0, 18, 1, -18)
			layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
		end
	end
	applyLayout()
	InputHints.Changed.Event:Connect(applyLayout)

	for _, value in GameState.Missions:GetChildren() do
		addMissionEntry(value)
	end
	GameState.Missions.ChildAdded:Connect(addMissionEntry)
	GameState.Missions.ChildRemoved:Connect(removeMissionEntry)

	Remotes.event("Notify").OnClientEvent:Connect(toast)
	Remotes.event("NightResults").OnClientEvent:Connect(showResults)

	-- Aviso sonoro al empezar un evento: dos pitidos (graves si es malo, agudos si es bueno)
	local eventSound = make("Sound", { Name = "EventAlert", SoundId = EVENT_SOUND, Volume = 0.8, Parent = gui })
	GameState.Folder:GetAttributeChangedSignal("EventName"):Connect(function()
		if GameState.Folder:GetAttribute("EventName") == nil then
			return
		end
		local good = GameState.Folder:GetAttribute("EventKind") == "Good"
		eventSound.PlaybackSpeed = if good then 1.3 else 0.75
		eventSound:Play()
		task.delay(0.35, function()
			eventSound:Play()
		end)
	end)

	-- Ocultar el panel de resultados al empezar la fase de mejoras tras unos segundos
	GameState.Folder:GetAttributeChangedSignal("Phase"):Connect(function()
		if GameState.Folder:GetAttribute("Phase") == "Upgrades" then
			task.delay(4, function()
				if GameState.Folder:GetAttribute("Phase") == "Upgrades" then
					resultsPanel.Visible = false
				end
			end)
		end
	end)

	local accumulator = 0
	RunService.RenderStepped:Connect(function(dt)
		accumulator += dt
		if accumulator >= 0.1 then
			accumulator = 0
			update()
		end
	end)
end

return HUD
