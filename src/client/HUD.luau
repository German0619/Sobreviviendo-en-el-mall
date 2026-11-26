-- HUD: hora, noche, fase, dinero, barras (vida/estamina/bateria), tareas,
-- avisos y pantalla de resultados. Todo construido por codigo.
-- En el lobby solo muestra avisos, diamantes y la clase equipada.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
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
local Spectate = require(script.Parent.Spectate)
local Alerts = require(script.Parent.Alerts)

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
	Track = Color3.fromRGB(8, 8, 11),
	Stroke = Color3.fromRGB(70, 70, 82),
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

-- Barra de estado: icono a la izquierda, relleno con brillo, nombre y valor.
-- trail = true: al bajar deja un rastro claro que se vacia despues (el golpe se ve).
local function makeBar(parent, glyph: string, labelText: string, color: Color3, order: number, trail: boolean?)
	local row = make("Frame", {
		Name = labelText,
		Size = UDim2.new(1, 0, 0, 28),
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Parent = parent,
	})
	local _, glyphLabel = UIKit.iconBox({ Size = UDim2.fromOffset(28, 28), Radius = 7, Parent = row }, glyph, color)
	local track = make("Frame", {
		Name = "Track",
		Position = UDim2.fromOffset(34, 2),
		Size = UDim2.new(1, -34, 0, 24),
		BackgroundColor3 = COLORS.Track,
		BackgroundTransparency = 0.15,
		Parent = row,
	}, { corner(6) })
	UIKit.stroke(track, color, 1, 0.55)
	local trailFrame = make("Frame", {
		Name = "Trail",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(255, 235, 220),
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		Visible = trail == true,
		Parent = track,
	}, { corner(6) })
	local fill = make("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Parent = track,
	}, { corner(6) })
	UIKit.gloss(fill, 0.4)
	make("Frame", { -- brillo en la mitad de arriba
		Size = UDim2.new(1, 0, 0.45, 0),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.82,
		BorderSizePixel = 0,
		Parent = fill,
	}, { corner(6) })
	local label = text({
		Size = UDim2.new(0.6, 0, 1, 0),
		Position = UDim2.fromOffset(9, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 13,
		Font = Enum.Font.GothamBlack,
		TextStrokeTransparency = 0.35,
		Text = labelText,
		ZIndex = 2,
		Parent = track,
	})
	local value = text({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -9, 0, 0),
		Size = UDim2.new(0.6, 0, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextSize = 14,
		TextStrokeTransparency = 0.35,
		RichText = true,
		Text = "",
		ZIndex = 2,
		Parent = track,
	})

	local current = -1
	local trailToken = 0
	local bar = {
		Fill = fill,
		Glyph = glyphLabel,
		Color = color,
		Low = false,
	}
	function bar.Set(ratio: number, valueText: string, caption: string?)
		ratio = math.clamp(ratio, 0, 1)
		value.Text = valueText
		label.Text = caption or labelText
		if math.abs(ratio - current) < 0.002 then
			return
		end
		local goal = UDim2.fromScale(ratio, 1)
		if current < 0 then
			fill.Size = goal
			trailFrame.Size = goal
		elseif ratio < current then
			UIKit.tween(fill, 0.12, { Size = goal })
			trailToken += 1
			local token = trailToken
			task.delay(0.45, function()
				if token == trailToken then
					UIKit.tween(trailFrame, 0.45, { Size = goal })
				end
			end)
		else
			UIKit.tween(fill, 0.2, { Size = goal })
			trailToken += 1
			trailFrame.Size = goal
		end
		current = ratio
	end
	-- Parpadeo cuando queda poco (lo llama el bucle de cada frame)
	function bar.Pulse(t: number)
		if bar.Low then
			local a = (math.sin(t * 9) + 1) / 2
			fill.BackgroundTransparency = 0.35 * a
			glyphLabel.TextTransparency = 0.5 * a
		elseif fill.BackgroundTransparency ~= 0 then
			fill.BackgroundTransparency = 0
			glyphLabel.TextTransparency = 0
		end
	end
	return bar
end

-- Viñeta roja en los bordes (golpes y poca vida): cuatro franjas con degradado
local function makeVignette(parent)
	local holder = make("Frame", {
		Name = "DamageVignette",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 0,
		Parent = parent,
	})
	local strips = {}
	local specs = {
		{ UDim2.fromScale(0, 0), UDim2.fromScale(1, 0.22), 90 }, -- arriba
		{ UDim2.fromScale(0, 0.78), UDim2.fromScale(1, 0.22), -90 }, -- abajo
		{ UDim2.fromScale(0, 0), UDim2.fromScale(0.16, 1), 0 }, -- izquierda
		{ UDim2.fromScale(0.84, 0), UDim2.fromScale(0.16, 1), 180 }, -- derecha
	}
	for _, spec in specs do
		local strip = make("Frame", {
			Position = spec[1],
			Size = spec[2],
			BackgroundColor3 = Color3.fromRGB(170, 0, 0),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = 0,
			Parent = holder,
		})
		make("UIGradient", {
			Rotation = spec[3],
			Transparency = NumberSequence.new(0, 1),
			Parent = strip,
		})
		table.insert(strips, strip)
	end
	return function(intensity: number)
		local t = 1 - math.clamp(intensity, 0, 1) * 0.75
		for _, strip in strips do
			strip.BackgroundTransparency = t
		end
	end
end

----------------------------------------------------------------------
-- Construccion
----------------------------------------------------------------------

local eventLabel, eventChip, eventStroke
local top: Frame
local TOAST_TOP = 126 -- donde empiezan los avisos (si no hay evento ni jefe), bajo las habilidades
local toastTop = -1
local missionsFrame: Frame
local gui, clockLabel, nightLabel, phaseLabel, moneyLabel, zoneLabel, itemsLabel, sodaLabel, classLabel, barsFrame
local diamondsLabel, deadSubtitle, reviveButton, spectateButton, missionsTitle, goalFill
local bars = {}
local missionList, missionEntries = nil, {}
local resultsPanel, resultsTitle, resultsBody
local deadOverlay
local setVignette
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
	-- (en su propio ScreenGui sin margenes: llega hasta el borde real de la pantalla)
	setVignette = makeVignette(make("ScreenGui", {
		Name = "DamageVignette",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ScreenInsets = Enum.ScreenInsets.None,
		DisplayOrder = -1,
		Parent = player:WaitForChild("PlayerGui"),
	}))

	-- Arriba al centro: reloj, noche, fase (en telefono, mas pequeno y mas arriba:
	-- ver applyCenterLayout)
	top = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 14),
		Size = UDim2.fromOffset(420, 136),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	table.insert(nightOnly, top)
	clockLabel = text({
		Size = UDim2.new(1, 0, 0, 40),
		TextSize = 38,
		Font = Enum.Font.GothamBlack,
		TextStrokeTransparency = 0.3,
		Text = "12:00 AM",
		Parent = top,
	})
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
	-- Evento activo (EventDirector) o jefe: pastilla con borde del color del evento.
	-- Debajo de la linea de habilidades (Defense: "Destello [G]", a 98 px de arriba)
	eventChip = make("Frame", {
		Name = "EventChip",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 110),
		Size = UDim2.fromOffset(0, 32),
		AutomaticSize = Enum.AutomaticSize.XY,
		BackgroundColor3 = COLORS.Panel,
		BackgroundTransparency = 0.12,
		Visible = false,
		Parent = top,
	}, {
		corner(10),
		make("UIPadding", {
			PaddingLeft = UDim.new(0, 16),
			PaddingRight = UDim.new(0, 16),
			PaddingTop = UDim.new(0, 5),
			PaddingBottom = UDim.new(0, 5),
		}),
	})
	eventStroke = UIKit.stroke(eventChip, COLORS.Event, 2, 0.15)
	eventLabel = text({
		Size = UDim2.fromOffset(0, 22),
		AutomaticSize = Enum.AutomaticSize.XY,
		TextSize = 17,
		RichText = true,
		TextStrokeTransparency = 0.5,
		Text = "",
		Parent = eventChip,
	})

	-- Arriba a la derecha: dinero
	moneyLabel = text({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -18, 0, 14),
		Size = UDim2.fromOffset(220, 34),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextSize = 28,
		Font = Enum.Font.GothamBlack,
		TextStrokeTransparency = 0.3,
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
		Size = UDim2.fromOffset(300, 230),
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
	-- Las tres barras en una tarjeta oscura (se leen sobre cualquier fondo)
	local vitals = make("Frame", {
		Name = "Vitals",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = COLORS.Panel,
		BackgroundTransparency = 0.3,
		LayoutOrder = 1,
		Parent = barsFrame,
	}, {
		corner(10),
		make("UIPadding", {
			PaddingTop = UDim.new(0, 7),
			PaddingBottom = UDim.new(0, 7),
			PaddingLeft = UDim.new(0, 7),
			PaddingRight = UDim.new(0, 7),
		}),
		make("UIListLayout", { Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	UIKit.stroke(vitals, COLORS.Stroke, 1, 0.5)
	bars.Health = makeBar(vitals, "♥", "VIDA", COLORS.Health, 1, true)
	bars.Stamina = makeBar(vitals, "»", "ESTAMINA", COLORS.Stamina, 2)
	bars.Battery = makeBar(vitals, "☀", "BATERÍA", COLORS.Battery, 3)

	-- Derecha: tareas
	missionsFrame = make("Frame", {
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
		Font = Enum.Font.GothamBlack,
		TextStrokeTransparency = 0.4,
		Text = "TAREAS",
		RichText = true,
		Parent = missionsFrame,
	})
	-- Cuota del equipo: barra fina bajo el titulo
	local goalTrack = make("Frame", {
		Name = "GoalTrack",
		Position = UDim2.fromOffset(0, 24),
		Size = UDim2.new(1, 0, 0, 5),
		BackgroundColor3 = COLORS.Track,
		BackgroundTransparency = 0.2,
		Visible = false,
		Parent = missionsFrame,
	}, { corner(3) })
	goalFill = make("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = COLORS.Accent,
		BorderSizePixel = 0,
		Parent = goalTrack,
	}, { corner(3) })
	missionList = make("Frame", {
		Position = UDim2.fromOffset(0, 36),
		Size = UDim2.new(1, 0, 1, -36),
		BackgroundTransparency = 1,
		Parent = missionsFrame,
	}, {
		make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
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
	-- No revivir: ver la partida desde un companero vivo (Spectate). El cuerpo sigue
	-- en el suelo: te pueden revivir igual, y "Volver" regresa a esta pantalla.
	spectateButton = make("TextButton", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.45, 152),
		Size = UDim2.fromOffset(260, 44),
		BackgroundColor3 = Color3.fromRGB(45, 45, 55),
		Font = FONT,
		TextSize = 18,
		TextColor3 = COLORS.Text,
		Text = "No revivir · ver a un compañero",
		Modal = true,
		ZIndex = 7,
		Parent = deadOverlay,
	}, { corner(8) })
	spectateButton.Activated:Connect(function()
		Spectate.Begin() -- (el boton solo se ve si queda algun companero en pie)
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
	local accent = if isEvent then COLORS.Event else COLORS.Accent
	local baseColor = if isEvent then Color3.fromRGB(34, 18, 52) else COLORS.Panel
	local frame = make("Frame", {
		Size = UDim2.new(1, 0, 0, 56),
		BackgroundColor3 = baseColor,
		BackgroundTransparency = 0.18,
		LayoutOrder = if isEvent then order - 100000 else order,
		Parent = missionList,
	}, { corner(8) })
	local stroke = UIKit.stroke(frame, if isEvent then COLORS.Event else COLORS.Stroke, if isEvent then 1.5 else 1, if isEvent then 0.2 else 0.5)
	local scale = make("UIScale", { Parent = frame })
	make("Frame", { -- barra de color a la izquierda
		Position = UDim2.fromOffset(0, 6),
		Size = UDim2.new(0, 4, 1, -12),
		BackgroundColor3 = accent,
		BorderSizePixel = 0,
		Parent = frame,
	}, { corner(2) })
	text({
		Position = UDim2.fromOffset(14, 5),
		Size = UDim2.new(1, -24, 0, 22),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 16,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextStrokeTransparency = 0.5,
		TextColor3 = if isEvent then COLORS.Event else COLORS.Text,
		Text = (if isEvent then "★ EVENTO · " else "") .. (value:GetAttribute("DisplayName") or "?"),
		Parent = frame,
	})
	local detail = text({
		Position = UDim2.fromOffset(14, 27),
		Size = UDim2.new(1, -24, 0, 16),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 13,
		Font = FONT_LIGHT,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextColor3 = COLORS.Dim,
		Text = "",
		Parent = frame,
	})
	-- Tiempo que le queda: barra que se vacia (verde -> amarilla -> roja)
	local timeTrack = make("Frame", {
		Position = UDim2.new(0, 14, 1, -9),
		Size = UDim2.new(1, -24, 0, 4),
		BackgroundColor3 = COLORS.Track,
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
		Parent = frame,
	}, { corner(2) })
	local timeFill = make("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = COLORS.Good,
		BorderSizePixel = 0,
		Parent = timeTrack,
	}, { corner(2) })
	local now = Workspace:GetServerTimeNow()
	missionEntries[value] = {
		Frame = frame,
		Detail = detail,
		Stroke = stroke,
		StrokeColor = stroke.Color,
		StrokeTransparency = stroke.Transparency,
		TimeFill = timeFill,
		Total = math.max(1, (value:GetAttribute("ExpiresAt") or now) - now),
	}
	-- Entra con un pequeno salto y un destello del color de la tarea
	scale.Scale = 0.7
	UIKit.tween(scale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
	frame.BackgroundColor3 = UIKit.shade(accent, -0.35)
	UIKit.tween(frame, 0.8, { BackgroundColor3 = baseColor })
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
		local urgent = remaining <= 15
		entry.Detail.TextColor3 = if urgent then COLORS.Bad else COLORS.Dim
		-- (si la tarea se renueva y le dan mas tiempo, la barra parte de ahi)
		if remaining > entry.Total then
			entry.Total = remaining
		end
		local ratio = math.clamp(remaining / entry.Total, 0, 1)
		entry.TimeFill.Size = UDim2.fromScale(ratio, 1)
		entry.TimeFill.BackgroundColor3 = if ratio > 0.5
			then COLORS.Good:Lerp(COLORS.Accent, (1 - ratio) * 2)
			else COLORS.Accent:Lerp(COLORS.Bad, 1 - ratio * 2)
		if urgent then
			entry.Stroke.Color = COLORS.Bad
			entry.Stroke.Transparency = 0.1 + 0.5 * (math.sin(now * 8) + 1) / 2
		else
			entry.Stroke.Color = entry.StrokeColor
			entry.Stroke.Transparency = entry.StrokeTransparency
		end
	end
end

----------------------------------------------------------------------
-- Avisos y resultados
----------------------------------------------------------------------

-- Avisos: tarjetas animadas del modulo Alerts
local function toast(message: string, kind: string?)
	Alerts.Toast(message, kind)
end

-- Aviso local (lo usan otros modulos del cliente)
function HUD.Toast(message: string, kind: string?)
	if not Place.IsLobby then
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
	local chipPulse = false
	if type(bossName) == "string" and phase == "Night" then
		if state:GetAttribute("BossDefeated") == true then
			eventLabel.Text = "✓ " .. UIKit.upper(bossName) .. " VENCIDO"
			eventLabel.TextColor3 = COLORS.Good
		else
			chipPulse = true
			local progress = state:GetAttribute("BossProgress")
			local text = "☠ " .. UIKit.upper(bossName)
			if type(progress) == "string" and progress ~= "" then
				-- Dos jefes: el progreso de cada uno en su linea, debajo del nombre
				text ..= if string.find(progress, "\n") then "\n" .. progress else "  ·  " .. progress
			end
			eventLabel.Text = text
			eventLabel.TextColor3 = COLORS.Bad
		end
		eventChip.Visible = true
	elseif type(eventName) == "string" and phase == "Night" then
		local floor = state:GetAttribute("EventFloor")
		local eventEnds = state:GetAttribute("EventEndsAt") or 0
		local textValue = UIKit.upper(eventName)
		if type(floor) == "number" and FLOOR_NAMES[floor] then
			textValue ..= " (" .. FLOOR_NAMES[floor] .. ")"
		end
		local kind = state:GetAttribute("EventKind") or ""
		if eventEnds > 0 then
			local left = eventEnds - now
			textValue ..= "  ·  " .. formatTime(left)
			chipPulse = left <= 10
		end
		eventLabel.Text = (if kind == "Good" then "★ " elseif kind == "Bad" then "⚠ " else "◆ ") .. textValue
		eventLabel.TextColor3 = EVENT_KIND_COLORS[kind] or COLORS.Event
		eventChip.Visible = true
	else
		eventChip.Visible = false
	end
	if eventChip.Visible then
		eventStroke.Color = eventLabel.TextColor3
		eventStroke.Transparency = if chipPulse then 0.1 + 0.5 * (math.sin(now * 6) + 1) / 2 else 0.15
		eventChip.BackgroundColor3 = COLORS.Panel:Lerp(eventLabel.TextColor3, 0.12)
	end
	-- Alto segun las lineas, y los avisos debajo para no taparse
	local lines = if eventChip.Visible then #string.split(eventLabel.Text, "\n") else 0
	local eventBottom = top.Position.Y.Offset + eventChip.Position.Y.Offset + 22 * lines + 10
	local newTop = if lines > 0 then math.max(TOAST_TOP, eventBottom + 8) else TOAST_TOP
	if newTop ~= toastTop then
		toastTop = newTop
		Alerts.SetToastTop(newTop)
	end

	local classDef = Config.Classes[player:GetAttribute("EquippedClass") or ""]
	if classDef and not player:GetAttribute("SpinAnimating") then
		classLabel.Text = classDef.DisplayName
		classLabel.TextColor3 = Config.Rarities[classDef.Rarity].Color
	end

	-- Los objetos y las armas estan en la mochila nativa (abajo). Aqui solo el estado
	-- del arma activa ([R]: la de la mano o la ultima que tuviste): usos, luz UV y espera.
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
		-- Las demas armas que lleva (cada una en su casilla de la mochila)
		local list = player:GetAttribute("Weapons")
		local count = if type(list) == "string" then #string.split(list, ",") else 1
		if count > 1 then
			weaponText ..= string.format("  (+%d)", count - 1)
		end
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
		local ratio = humanoid.Health / math.max(humanoid.MaxHealth, 1)
		bars.Health.Set(ratio, string.format("%d / %d", math.ceil(humanoid.Health), humanoid.MaxHealth))
		bars.Health.Low = ratio <= 0.3 and humanoid.Health > 0
	end
	local maxStamina = player:GetAttribute("MaxStamina") or Config.Stats.Stamina.Base
	local stamina = player:GetAttribute("Stamina") or maxStamina
	local exhausted = player:GetAttribute("Exhausted") == true
	bars.Stamina.Set(
		stamina / maxStamina,
		string.format("%d%%", math.floor(stamina / maxStamina * 100)),
		if exhausted then "AGOTADO" else "ESTAMINA"
	)
	bars.Stamina.Fill.BackgroundColor3 = if exhausted then COLORS.Bad else COLORS.Stamina
	bars.Stamina.Low = exhausted

	local maxBattery = player:GetAttribute("MaxBattery") or Config.Stats.Battery.Base
	local battery = player:GetAttribute("Battery") or 0
	local on = player:GetAttribute("FlashlightOn") == true
	local batteryRatio = battery / maxBattery
	bars.Battery.Set(
		batteryRatio,
		string.format(
			'%d%%  <font color="%s">%s</font>',
			math.floor(batteryRatio * 100),
			if on then "#FFE08A" else "#8C8C96",
			InputHints.Label("Flashlight", if on then "ON" else "OFF")
		)
	)
	bars.Battery.Fill.BackgroundColor3 = if batteryRatio <= 0.15 then COLORS.Bad else COLORS.Battery
	bars.Battery.Low = batteryRatio <= 0.15

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
	-- Fumigando (pase Fumigador): no te muevas
	local fumigateEnds = player:GetAttribute("FumigateEndsAt")
	if type(fumigateEnds) == "number" and fumigateEnds > now then
		local text = string.format('<font color="#8CFF8C">FUMIGANDO %.1fs · no te muevas</font>', fumigateEnds - now)
		zoneText = if zoneText ~= "" then zoneText .. "  ·  " .. text else text
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
		goalFill.Parent.Visible = true
		if goalFill:GetAttribute("Ratio") ~= done / goal then
			goalFill:SetAttribute("Ratio", done / goal)
			UIKit.tween(goalFill, 0.4, { Size = UDim2.fromScale(done / goal, 1) })
			goalFill.BackgroundColor3 = if done >= goal then COLORS.Good else COLORS.Accent
		end
	else
		missionsTitle.Text = "TAREAS"
		goalFill.Parent.Visible = false
	end

	-- Overlays
	deadOverlay.Visible = phase == "Night" and player:GetAttribute("Alive") == false and humanoid ~= nil
		and humanoid.Health <= 0 and not Spectate.IsActive()
	if deadOverlay.Visible then
		spectateButton.Visible = Spectate.HasTargets()
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
			-- En telefono, pegada a la barra de Roblox
			barsFrame.Position = UDim2.new(0, 18, 0, if UIKit.isPhone(gui) then 2 else 10)
			layout.VerticalAlignment = Enum.VerticalAlignment.Top
		else
			barsFrame.AnchorPoint = Vector2.new(0, 1)
			barsFrame.Position = UDim2.new(0, 18, 1, -18)
			layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
		end
	end
	applyLayout()
	InputHints.Changed.Event:Connect(applyLayout)
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(applyLayout)

	-- Las lineas de sodas y del arma no ocupan sitio mientras estan vacias
	-- (en tactil la columna va arriba y dejaban un hueco encima de la zona)
	for _, line in { sodaLabel, itemsLabel } do
		local function sync()
			line.Visible = line.Text ~= ""
		end
		sync()
		line:GetPropertyChangedSignal("Text"):Connect(sync)
	end

	-- Columna derecha (billetes, diamantes, clase y tareas): en telefono pegada arriba
	local function applyRightLayout()
		if Place.IsLobby then
			return -- (en el lobby la colocan arriba)
		end
		local lift = if UIKit.isPhone(gui) then 12 else 0
		moneyLabel.Position = UDim2.new(1, -18, 0, 14 - lift)
		diamondsLabel.Position = UDim2.new(1, -18, 0, 46 - lift)
		classLabel.Position = UDim2.new(1, -18, 0, 66 - lift)
		missionsFrame.Position = UDim2.new(1, -18, 0, 94 - lift)
	end
	applyRightLayout()
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(applyRightLayout)

	-- Bloque central (reloj, noche, fase, evento): en telefono mas pequeno y mas arriba.
	-- La linea de habilidades (Defense) se coloca debajo con UIKit.isPhone igual.
	local function applyCenterLayout()
		local phone = UIKit.isPhone(gui)
		top.Position = UDim2.new(0.5, 0, 0, if phone then 2 else 14)
		clockLabel.Size = UDim2.new(1, 0, 0, if phone then 26 else 40)
		UIKit.setTextSize(clockLabel, if phone then 24 else 38)
		nightLabel.Position = UDim2.fromOffset(0, if phone then 26 else 40)
		phaseLabel.Position = UDim2.fromOffset(0, if phone then 44 else 62)
		eventChip.Position = UDim2.new(0.5, 0, 0, if phone then 90 else 110) -- bajo las habilidades
	end
	applyCenterLayout()
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(applyCenterLayout)

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

	-- Dinero: "+$120" / "-$75" que sube y se desvanece junto a la cifra
	local lastMoney = player:GetAttribute("Money") or 0
	player:GetAttributeChangedSignal("Money"):Connect(function()
		local money = player:GetAttribute("Money") or 0
		local delta = money - lastMoney
		lastMoney = money
		if delta == 0 or Place.IsLobby or not moneyLabel.Visible then
			return
		end
		local gain = delta > 0
		local float = text({
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -18 - moneyLabel.TextBounds.X / math.max(gui:FindFirstChildOfClass("UIScale").Scale, 0.01) - 10, 0, moneyLabel.Position.Y.Offset + 6),
			Size = UDim2.fromOffset(160, 24),
			TextXAlignment = Enum.TextXAlignment.Right,
			TextSize = 20,
			Font = Enum.Font.GothamBlack,
			TextStrokeTransparency = 0.3,
			TextColor3 = if gain then COLORS.Good else COLORS.Bad,
			Text = (if gain then "+" else "-") .. Util.formatMoney(math.abs(delta)),
			Parent = gui,
		})
		local goal = float.Position + UDim2.fromOffset(0, if gain then -12 else 12)
		UIKit.tween(float, 1.4, { Position = goal })
		task.delay(0.7, function()
			UIKit.tween(float, 0.7, { TextTransparency = 1, TextStrokeTransparency = 1 })
			task.wait(0.7)
			float:Destroy()
		end)
		-- La cifra da un pequeno salto
		moneyLabel.TextColor3 = if gain then Color3.fromRGB(255, 235, 150) else COLORS.Bad
		UIKit.tween(moneyLabel, 0.5, { TextColor3 = COLORS.Accent })
	end)

	-- Golpes: destello rojo en los bordes; con poca vida, latido continuo
	local flash = 0
	local lastHealth = nil
	local function watchHumanoid(character: Model)
		local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
		if not humanoid then
			return
		end
		lastHealth = humanoid.Health
		humanoid.HealthChanged:Connect(function(health)
			if lastHealth and health < lastHealth - 2 then
				flash = math.clamp(flash + (lastHealth - health) / 40 + 0.35, 0, 1)
			end
			lastHealth = health
		end)
	end
	if player.Character then
		task.spawn(watchHumanoid, player.Character)
	end
	player.CharacterAdded:Connect(watchHumanoid)

	local accumulator = 0
	RunService.RenderStepped:Connect(function(dt)
		accumulator += dt
		if accumulator >= 0.1 then
			accumulator = 0
			update()
		end
		-- Animaciones de cada frame (parpadeos y viñeta)
		local t = os.clock()
		for _, bar in bars do
			bar.Pulse(t)
		end
		flash = math.max(0, flash - dt * 1.6)
		local low = 0
		if bars.Health.Low and barsFrame.Visible then
			low = 0.22 + 0.18 * (math.sin(t * 5) + 1) / 2
		end
		setVignette(math.max(flash, low))
	end)
end

return HUD
