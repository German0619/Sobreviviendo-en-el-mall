-- HUD: hora, noche, fase, dinero, barras (vida/estamina/bateria), tareas,
-- avisos y pantalla de resultados. Todo construido por codigo.

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
}

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

local gui, clockLabel, nightLabel, phaseLabel, moneyLabel, zoneLabel, itemsLabel, sodaLabel, classLabel
local diamondsLabel, deadSubtitle, reviveButton
local bars = {}
local missionList, missionEntries = nil, {}
local toastList
local resultsPanel, resultsTitle, resultsBody
local deadOverlay

local function build()
	gui = make("ScreenGui", {
		Name = "HUD",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = player:WaitForChild("PlayerGui"),
	})

	-- Arriba al centro: reloj, noche, fase
	local top = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 14),
		Size = UDim2.fromOffset(320, 90),
		BackgroundTransparency = 1,
		Parent = gui,
	})
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

	-- Abajo a la izquierda: barras y zona actual
	local barsFrame = make("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 18, 1, -18),
		Size = UDim2.fromOffset(260, 108),
		BackgroundTransparency = 1,
		Parent = gui,
	}, {
		make("UIListLayout", {
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
			VerticalAlignment = Enum.VerticalAlignment.Bottom,
		}),
	})
	zoneLabel = text({
		Size = UDim2.new(1, 0, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 14,
		Font = FONT_LIGHT,
		TextColor3 = COLORS.Dim,
		Text = "",
		LayoutOrder = 0,
		Parent = barsFrame,
	})
	bars.Health = makeBar(barsFrame, "VIDA", COLORS.Health, 1)
	bars.Stamina = makeBar(barsFrame, "ESTAMINA", COLORS.Stamina, 2)
	bars.Battery = makeBar(barsFrame, "BATERÍA", COLORS.Battery, 3)

	-- Abajo al centro: objetos y soda activa
	itemsLabel = text({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -18),
		Size = UDim2.fromOffset(520, 24),
		TextSize = 16,
		Text = "",
		Parent = gui,
	})
	sodaLabel = text({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -46),
		Size = UDim2.fromOffset(520, 22),
		TextSize = 15,
		Text = "",
		Parent = gui,
	})

	-- Derecha: tareas
	local missionsFrame = make("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -18, 0, 94),
		Size = UDim2.fromOffset(290, 360),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	text({
		Size = UDim2.new(1, 0, 0, 22),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextSize = 16,
		Text = "TAREAS",
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
	local frame = make("Frame", {
		Size = UDim2.new(1, 0, 0, 48),
		BackgroundColor3 = COLORS.Panel,
		BackgroundTransparency = 0.25,
		LayoutOrder = tonumber(string.sub(value.Name, 2)) or 0,
		Parent = missionList,
	}, { corner(8) })
	text({
		Position = UDim2.fromOffset(10, 4),
		Size = UDim2.new(1, -20, 0, 22),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 16,
		Text = value:GetAttribute("DisplayName") or "?",
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
	for value, entry in missionEntries do
		local remaining = (value:GetAttribute("ExpiresAt") or now) - now
		entry.Detail.Text = string.format(
			"%s  ·  %s  ·  +%s",
			value:GetAttribute("Zone") or "?",
			formatTime(remaining),
			Util.formatMoney(value:GetAttribute("Reward") or 0)
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
	local color = if kind == "good" then COLORS.Good elseif kind == "bad" then COLORS.Bad else COLORS.Text
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

	local lines = {
		string.format("Pago base: <b>%s</b>", Util.formatMoney(data.Base)),
		string.format("Tareas: <b>%s</b>", Util.formatMoney(data.Missions)),
		string.format("Supervivencia: <b>%s</b>", Util.formatMoney(data.Survival)),
	}
	if data.Bonus > 0 then
		table.insert(lines, string.format("Bonus de clase: <b>%s</b>", Util.formatMoney(data.Bonus)))
	end
	table.insert(lines, "")
	table.insert(lines, string.format('<font size="24" color="#FFC850"><b>TOTAL: %s</b></font>', Util.formatMoney(data.Total)))
	if data.GameOver then
		table.insert(lines, "")
		table.insert(lines, string.format("Llegaste a la noche %d. Nueva partida en breve.", data.Night))
	end
	resultsBody.Text = table.concat(lines, "\n")
	resultsPanel.Visible = true
end

----------------------------------------------------------------------
-- Actualizacion
----------------------------------------------------------------------

local function update()
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
		phaseText ..= "   [U] Mejoras   [C] Clases"
	end
	phaseLabel.Text = phaseText

	local classDef = Config.Classes[player:GetAttribute("EquippedClass") or ""]
	if classDef and not player:GetAttribute("SpinAnimating") then
		classLabel.Text = classDef.DisplayName
		classLabel.TextColor3 = Config.Rarities[classDef.Rarity].Color
	end

	-- Objetos con tecla
	local slots = {}
	for _, itemId in Config.ShopOrder do
		local item = Config.ShopItems[itemId]
		if item.Hotkey and item.Use then
			table.insert(slots, string.format("[%d] %s x%d", item.Hotkey, item.DisplayName, player:GetAttribute("Item_" .. itemId) or 0))
		end
	end
	itemsLabel.Text = table.concat(slots, "     ")

	-- Soda activa
	local sodaName = player:GetAttribute("SodaName")
	if sodaName then
		local remaining = (player:GetAttribute("SodaEndsAt") or now) - now
		sodaLabel.Text = string.format("Soda: %s  (%ds)", sodaName, math.max(0, math.ceil(remaining)))
		sodaLabel.TextColor3 = if player:GetAttribute("SodaPositive") then COLORS.Good else COLORS.Bad
	else
		sodaLabel.Text = ""
	end

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
		string.format("BATERÍA  %d%%  [F] %s", math.floor(battery / maxBattery * 100), if on then "ON" else "OFF")
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
	if zoneName then
		local dark = state:GetAttribute("Dark_" .. Util.attributeKey(zoneName)) == true
		zoneLabel.Text = if dark then zoneName .. "  ·  SIN LUZ" else zoneName
		zoneLabel.TextColor3 = if dark then COLORS.Bad else COLORS.Dim
	else
		zoneLabel.Text = ""
	end

	updateMissions(now)

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

	for _, value in GameState.Missions:GetChildren() do
		addMissionEntry(value)
	end
	GameState.Missions.ChildAdded:Connect(addMissionEntry)
	GameState.Missions.ChildRemoved:Connect(removeMissionEntry)

	Remotes.event("Notify").OnClientEvent:Connect(toast)
	Remotes.event("NightResults").OnClientEvent:Connect(showResults)

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
