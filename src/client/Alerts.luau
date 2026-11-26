-- Alerts (mall): avisos que se leen mientras se juega.
--   * Toast: tarjeta con icono y color segun el tipo (good/bad/info/event/mission),
--     barra de tiempo, entra con un pequeno "pop" y se apila (max. 4). Si llega el
--     mismo aviso otra vez, la tarjeta se renueva y muestra "x2", "x3"...
--   * Banner: franja grande en el centro de la pantalla para lo importante
--     (empieza un evento, empieza la noche). Con borde de pantalla de color si es malo.
-- El HUD reenvia aqui los Notify del servidor (HUD.Toast) y coloca la pila de avisos
-- debajo del reloj y del evento activo (Alerts.SetToastTop).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local GameState = require(Shared.GameState)
local UIKit = require(script.Parent.UIKit)

local player = Players.LocalPlayer
local C = UIKit.COLORS

local Alerts = {}

local TOAST_WIDTH = 470
local TOAST_TEXT = 17
local TEXT_X = 56 -- donde empieza el texto (despues del icono)
local MAX_TOASTS = 4
local PING = "rbxasset://sounds/electronicpingshort.wav"
local FLOOR_NAMES = { "planta baja", "planta alta" }

local KINDS = {
	good = { Color = C.Good, Glyph = "✓", Pitch = 1.6 },
	bad = { Color = C.Bad, Glyph = "!", Pitch = 0.8 },
	info = { Color = C.Info, Glyph = "i", Pitch = 1.2 },
	event = { Color = C.Event, Glyph = "★", Pitch = 1.0 },
	mission = { Color = C.Accent, Glyph = "+", Pitch = 1.35 },
}

local EVENT_KINDS = {
	Bad = { Color = Color3.fromRGB(240, 90, 90), Tag = "⚠  EVENTO PELIGROSO" },
	Good = { Color = Color3.fromRGB(100, 220, 130), Tag = "★  EVENTO FAVORABLE" },
	Mixed = { Color = Color3.fromRGB(240, 190, 70), Tag = "◆  EVENTO" },
}

local gui: ScreenGui
local toastList: Frame
local sfx: Sound
local lastSound = 0
local toastOrder = 0
local live = {} -- [message] = entrada viva (para agrupar repetidos)

local banner, bannerScale, bannerTag, bannerTitle, bannerTitleStroke, bannerBody, bannerLines, edgeStroke
local bannerToken = 0

local function ensureGui()
	if gui then
		return
	end
	gui = UIKit.make("ScreenGui", {
		Name = "Alerts",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 3, -- encima del HUD, debajo de las ventanas (5)
		Parent = player:WaitForChild("PlayerGui"),
	})
	UIKit.adapt(gui)

	toastList = UIKit.make("Frame", {
		Name = "Toasts",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 126),
		Size = UDim2.fromOffset(TOAST_WIDTH, 320),
		BackgroundTransparency = 1,
		Parent = gui,
	}, {
		UIKit.make("UIListLayout", {
			Padding = UDim.new(0, 6),
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})

	sfx = UIKit.make("Sound", { SoundId = PING, Volume = 0.25, Parent = gui })

	-- Bordes de pantalla de color (eventos malos): su propio ScreenGui sin margenes
	-- para llegar hasta el borde real, con cuatro franjas difuminadas hacia dentro
	local edgeGui = UIKit.make("ScreenGui", {
		Name = "AlertsEdge",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ScreenInsets = Enum.ScreenInsets.None,
		DisplayOrder = 3,
		Parent = player:WaitForChild("PlayerGui"),
	})
	local strips = {}
	for _, spec in {
		{ UDim2.fromScale(0, 0), UDim2.fromScale(1, 0.14), 90 },
		{ UDim2.fromScale(0, 0.86), UDim2.fromScale(1, 0.14), -90 },
		{ UDim2.fromScale(0, 0), UDim2.fromScale(0.1, 1), 0 },
		{ UDim2.fromScale(0.9, 0), UDim2.fromScale(0.1, 1), 180 },
	} do
		local strip = UIKit.make("Frame", {
			Position = spec[1],
			Size = spec[2],
			BackgroundColor3 = C.Bad,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Parent = edgeGui,
		}, {
			UIKit.make("UIGradient", { Rotation = spec[3], Transparency = NumberSequence.new(0, 1) }),
		})
		table.insert(strips, strip)
	end
	-- (edgeStroke: objeto con Color/Transparency que mueve las cuatro franjas a la vez)
	local edgeValue = Instance.new("NumberValue")
	edgeValue.Value = 1
	edgeValue.Parent = edgeGui
	edgeValue.Changed:Connect(function(v)
		for _, strip in strips do
			strip.BackgroundTransparency = v
		end
	end)
	edgeStroke = {
		Set = function(color: Color3)
			for _, strip in strips do
				strip.BackgroundColor3 = color
			end
			edgeValue.Value = 0.25
			UIKit.tween(edgeValue, 2.5, { Value = 1 }, Enum.EasingStyle.Sine)
		end,
	}

	-- Banner central
	banner = UIKit.make("Frame", {
		Name = "Banner",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.6), -- (debajo de los avisos, que van arriba)
		Size = UDim2.fromOffset(920, 168),
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.12,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 30,
		Parent = gui,
	})
	bannerScale = UIKit.make("UIScale", { Parent = banner })
	-- Bordes laterales difuminados
	UIKit.make("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.16, 0),
			NumberSequenceKeypoint.new(0.84, 0),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Parent = banner,
	})
	bannerLines = {}
	for i, y in { 0, 1 } do
		local line = UIKit.make("Frame", {
			AnchorPoint = Vector2.new(0.5, y),
			Position = UDim2.fromScale(0.5, y),
			Size = UDim2.new(1, 0, 0, 3),
			BorderSizePixel = 0,
			ZIndex = 31,
			Parent = banner,
		})
		UIKit.make("UIGradient", {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.5, 0),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Parent = line,
		})
		bannerLines[i] = line
	end
	bannerTag = UIKit.text({
		Position = UDim2.fromOffset(0, 14),
		Size = UDim2.new(1, 0, 0, 22),
		TextSize = 17,
		Font = UIKit.FONT_BLACK,
		Text = "",
		ZIndex = 32,
		Parent = banner,
	})
	bannerTitle = UIKit.text({
		Position = UDim2.fromOffset(110, 38),
		Size = UDim2.new(1, -220, 0, 58),
		TextScaled = true,
		Font = UIKit.FONT_BLACK,
		Text = "",
		ZIndex = 32,
		Parent = banner,
	})
	UIKit.make("UITextSizeConstraint", { MaxTextSize = 52, MinTextSize = 18, Parent = bannerTitle })
	bannerTitleStroke = UIKit.make("UIStroke", {
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		Thickness = 2.5,
		Transparency = 0.2,
		Parent = bannerTitle,
	})
	bannerBody = UIKit.text({
		Position = UDim2.fromOffset(150, 100),
		Size = UDim2.new(1, -300, 0, 54),
		TextSize = 18,
		Font = UIKit.FONT,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = Color3.fromRGB(215, 215, 222),
		Text = "",
		ZIndex = 32,
		Parent = banner,
	})
end

local function playSound(pitch: number)
	local now = os.clock()
	if now - lastSound < 0.3 then
		return -- muchos avisos seguidos: un solo pitido
	end
	lastSound = now
	sfx.PlaybackSpeed = pitch
	sfx:Play()
end

-- Tipo de aviso: los de "Nueva tarea" se ven como tarea aunque lleguen como info
local function resolveKind(message: string, kind: string?): string
	if kind == "info" or kind == nil then
		if string.find(message, "^Nueva tarea") or string.find(message, "^Nueva misi") then
			return "mission"
		end
	end
	return if kind and KINDS[kind] then kind else "info"
end

local function textHeight(message: string): number
	local plain = string.gsub(message, "<[^>]->", "")
	local ok, bounds = pcall(function()
		return TextService:GetTextSize(plain, TOAST_TEXT, UIKit.FONT, Vector2.new(TOAST_WIDTH - TEXT_X - 46, 1000))
	end)
	return if ok then bounds.Y else TOAST_TEXT
end

local function removeToast(entry, quick: boolean?)
	if entry.Gone then
		return
	end
	entry.Gone = true
	entry.Card:SetAttribute("Leaving", true)
	if live[entry.Message] == entry then
		live[entry.Message] = nil
	end
	local t = if quick then 0.15 else 0.35
	UIKit.fade(entry.Card, 1, t)
	UIKit.tween(entry.Scale, t, { Scale = 0.92 })
	task.delay(t, function()
		entry.Card:Destroy()
	end)
end

local function startTimer(entry)
	entry.Token += 1
	local token = entry.Token
	-- Duracion segun lo largo del texto (los malos duran un poco mas)
	local duration = math.clamp(3.5 + #entry.Message / 28, 4, 8) + (if entry.Kind == "bad" then 1 else 0)
	entry.Timer.Size = UDim2.new(1, -20, 0, 3)
	UIKit.tween(entry.Timer, duration, { Size = UDim2.new(0, 0, 0, 3) }, Enum.EasingStyle.Linear)
	task.delay(duration, function()
		if entry.Token == token then
			removeToast(entry)
		end
	end)
end

local function pop(entry, from: number)
	entry.Scale.Scale = from
	UIKit.tween(entry.Scale, 0.28, { Scale = 1 }, Enum.EasingStyle.Back)
end

function Alerts.Toast(message: string, kind: string?)
	ensureGui()
	message = tostring(message)
	-- Estos ya salen en el banner central
	if string.find(message, "^EVENTO:") or string.find(message, "^Noche %d+: completen") then
		return
	end
	local k = resolveKind(message, kind)
	local style = KINDS[k]

	-- Repetido: renovar la tarjeta que ya esta en pantalla
	local existing = live[message]
	if existing and not existing.Gone then
		existing.Count += 1
		existing.Badge.Text = "x" .. existing.Count
		existing.Badge.Visible = true
		toastOrder += 1
		existing.Card.LayoutOrder = toastOrder
		pop(existing, 0.9)
		startTimer(existing)
		return
	end

	toastOrder += 1
	local height = math.max(48, textHeight(message) + 22)
	local card = UIKit.make("Frame", {
		Name = "Toast",
		Size = UDim2.fromOffset(TOAST_WIDTH, height),
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.08,
		LayoutOrder = toastOrder,
		Parent = toastList,
	}, { UIKit.corner(10) })
	UIKit.stroke(card, style.Color, 1.5, 0.35)
	local scale = UIKit.make("UIScale", { Parent = card })
	-- Tinte del color del aviso de izquierda a derecha
	local tint = UIKit.make("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = style.Color,
		BackgroundTransparency = 0.82,
		Parent = card,
	}, { UIKit.corner(10) })
	UIKit.make("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.45, 1),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Parent = tint,
	})
	UIKit.make("Frame", { -- barra de color a la izquierda
		Position = UDim2.fromOffset(0, 6),
		Size = UDim2.new(0, 4, 1, -12),
		BackgroundColor3 = style.Color,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = card,
	}, { UIKit.corner(2) })
	UIKit.iconBox({
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 14, 0.5, 0),
		Size = UDim2.fromOffset(30, 30),
		Radius = 15,
		ZIndex = 2,
		Parent = card,
	}, style.Glyph, style.Color)
	UIKit.text({
		Position = UDim2.fromOffset(TEXT_X, 0),
		Size = UDim2.new(1, -(TEXT_X + 46), 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		RichText = true,
		TextSize = TOAST_TEXT,
		TextColor3 = C.Text,
		TextStrokeTransparency = 0.7,
		Text = message,
		ZIndex = 2,
		Parent = card,
	})
	local badge = UIKit.text({
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(32, 22),
		BackgroundColor3 = style.Color,
		BackgroundTransparency = 0.15,
		TextColor3 = C.Panel,
		TextSize = 14,
		Font = UIKit.FONT_BLACK,
		Text = "x2",
		Visible = false,
		ZIndex = 3,
		Parent = card,
	})
	UIKit.corner(11).Parent = badge
	local timer = UIKit.make("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 10, 1, -3),
		Size = UDim2.new(1, -20, 0, 3),
		BackgroundColor3 = style.Color,
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = card,
	}, { UIKit.corner(2) })

	local entry = {
		Card = card,
		Scale = scale,
		Badge = badge,
		Timer = timer,
		Message = message,
		Kind = k,
		Count = 1,
		Token = 0,
		Gone = false,
	}
	live[message] = entry

	UIKit.fade(card, 1, 0)
	UIKit.fade(card, 0, 0.18)
	pop(entry, 0.75)
	startTimer(entry)
	playSound(style.Pitch)

	-- Maximo MAX_TOASTS: los mas viejos se van rapido
	local cards = {}
	for _, child in toastList:GetChildren() do
		if child:IsA("Frame") and child:GetAttribute("Leaving") ~= true then
			table.insert(cards, child)
		end
	end
	table.sort(cards, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	for i = 1, #cards - MAX_TOASTS do
		local old = cards[i]
		local found = nil
		for _, e in live do
			if e.Card == old then
				found = e
			end
		end
		if found then
			removeToast(found, true)
		else
			old:Destroy()
		end
	end
end

-- Altura (px de diseno) donde empieza la pila de avisos
function Alerts.SetToastTop(y: number)
	ensureGui()
	toastList.Position = UDim2.new(0.5, 0, 0, y)
end

-- Banner central. opts: Tag, Title, Body, Color, Seconds, Edge (borde de pantalla)
function Alerts.Banner(opts)
	ensureGui()
	bannerToken += 1
	local token = bannerToken
	local color: Color3 = opts.Color or C.Accent
	bannerTag.Text = opts.Tag or ""
	bannerTag.TextColor3 = color
	bannerTitle.Text = UIKit.upper(opts.Title or "")
	bannerTitle.TextColor3 = C.Text
	bannerTitleStroke.Color = UIKit.shade(color, -0.35)
	bannerBody.Text = opts.Body or ""
	for _, line in bannerLines do
		line.BackgroundColor3 = color
		line.Size = UDim2.new(0, 0, 0, 3)
		UIKit.tween(line, 0.5, { Size = UDim2.new(1, 0, 0, 3) }, Enum.EasingStyle.Quint)
	end
	local hasBody = (opts.Body or "") ~= ""
	banner.Size = UDim2.fromOffset(920, if hasBody then 168 else 112)

	banner.Visible = true
	UIKit.fade(banner, 1, 0)
	UIKit.fade(banner, 0, 0.25)
	bannerScale.Scale = 1.25
	UIKit.tween(bannerScale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)

	if opts.Edge then
		edgeStroke.Set(color)
	end

	task.delay(opts.Seconds or 4.5, function()
		if bannerToken ~= token then
			return
		end
		UIKit.fade(banner, 1, 0.6)
		UIKit.tween(bannerScale, 0.6, { Scale = 0.94 })
		task.wait(0.6)
		if bannerToken == token then
			banner.Visible = false
		end
	end)
end

function Alerts.Start()
	ensureGui()
	local folder = GameState.Folder

	-- Empieza un evento: banner con su nombre, planta y descripcion
	folder:GetAttributeChangedSignal("EventName"):Connect(function()
		local name = folder:GetAttribute("EventName")
		if type(name) ~= "string" then
			return
		end
		local id = folder:GetAttribute("EventId")
		local def = if type(id) == "string" then Config.Events[id] else nil
		local kind = folder:GetAttribute("EventKind") or (def and def.Kind) or "Mixed"
		local style = EVENT_KINDS[kind] or EVENT_KINDS.Mixed
		local floor = folder:GetAttribute("EventFloor")
		local title = name
		if type(floor) == "number" and FLOOR_NAMES[floor] then
			title ..= "  ·  " .. FLOOR_NAMES[floor]
		end
		Alerts.Banner({
			Tag = style.Tag,
			Title = title,
			Body = def and def.Description or "",
			Color = style.Color,
			Seconds = 5.5,
			Edge = kind == "Bad",
		})
	end)

	-- Empieza la noche (las de jefe ya tienen su alerta: BossAlert)
	folder:GetAttributeChangedSignal("Phase"):Connect(function()
		if folder:GetAttribute("Phase") ~= "Night" then
			return
		end
		task.delay(0.6, function()
			if folder:GetAttribute("Phase") ~= "Night" or type(folder:GetAttribute("BossName")) == "string" then
				return
			end
			local goal = folder:GetAttribute("MissionGoal") or 0
			Alerts.Banner({
				Tag = "TURNO NOCTURNO",
				Title = "NOCHE " .. tostring(folder:GetAttribute("Night") or 1),
				Body = if goal > 0
					then string.format("Completen %d tareas en equipo para llegar a las 6 AM.", goal)
					else "Sobrevivan hasta las 6 AM.",
				Color = C.Accent,
				Seconds = 4.5,
			})
		end)
	end)
end

return Alerts
