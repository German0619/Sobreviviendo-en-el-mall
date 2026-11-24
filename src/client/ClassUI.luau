-- ClassUI: ruleta de clases y slots (tecla C, o el boton CLASES del lobby).
-- Se usa en el lobby; en el mall solo en Studio para probar
-- (Config.Debug.ClassesInMallInStudio).
--
-- * Girar cuesta diamantes; el servidor decide el resultado y aqui solo se anima.
-- * La clase que sale reemplaza automaticamente a la del slot equipado.
-- * Las probabilidades se muestran siempre (politica de Roblox).

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local Remotes = require(Shared.Remotes)
local GameState = require(Shared.GameState)
local Place = require(Shared.Place)
local UIKit = require(script.Parent.UIKit)
local HUD = require(script.Parent.HUD)
local StoreUI = require(script.Parent.StoreUI)

local player = Players.LocalPlayer
local C = UIKit.COLORS

local ClassUI = {}

local DIAMOND = "◆"
local DIAMOND_COLOR = Color3.fromRGB(110, 220, 255)
local ITEM_WIDTH = 130
local SPIN_SECONDS = 3.2

local window, statusLabel, diamondsLabel, slotsFrame, stripWindow, strip, resultLabel, spinButton
local busy = false
local animating = false

local function setStatus(message: string, good: boolean?)
	statusLabel.Text = message
	statusLabel.TextColor3 = if good then C.Good else C.Bad
end

local function classColor(className: string): Color3
	local def = Config.Classes[className]
	return if def then Config.Rarities[def.Rarity].Color else C.Dim
end

local function getSlots(): { string }
	local slots = {}
	for i = 1, Config.Roulette.MaxSlots do
		local className = player:GetAttribute("Slot_" .. i)
		if type(className) == "string" and className ~= "" then
			slots[i] = className
		end
	end
	return slots
end

local function invoke(remoteName: string, ...): (boolean, string?, any)
	if busy then
		return false, nil, nil
	end
	busy = true
	local args = table.pack(...)
	local ok, result, message, extra = pcall(function()
		return Remotes.func(remoteName):InvokeServer(table.unpack(args, 1, args.n))
	end)
	busy = false
	if not ok then
		warn("[ClassUI]", remoteName, "fallo:", result)
		setStatus("Error: " .. tostring(result))
		return false, nil, nil
	end
	setStatus(message or "", result == true)
	return result == true, message, extra
end

----------------------------------------------------------------------
-- Slots
----------------------------------------------------------------------

local refresh -- (declarada abajo)

local function makeCard(index: number, layoutOrder: number)
	local slots = getSlots()
	local className = slots[index]
	local maxSlots = player:GetAttribute("MaxSlots") or Config.Roulette.DefaultSlots
	local equipped = player:GetAttribute("EquippedSlot") == index

	local card = UIKit.make("Frame", {
		Size = UDim2.fromOffset(100, 110),
		BackgroundColor3 = C.Row,
		LayoutOrder = layoutOrder,
		ZIndex = 23,
		Parent = slotsFrame,
	}, {
		UIKit.corner(8),
		UIKit.make("UIStroke", {
			Color = if equipped then C.Accent elseif className then classColor(className) else C.ButtonOff,
			Thickness = if equipped then 2 else 1,
		}),
	})
	UIKit.text({
		Position = UDim2.fromOffset(0, 4),
		Size = UDim2.new(1, 0, 0, 14),
		TextSize = 11,
		Font = UIKit.FONT_LIGHT,
		TextColor3 = C.Dim,
		Text = "SLOT " .. index,
		ZIndex = 24,
		Parent = card,
	})

	if index > maxSlots then
		return
	end

	if className then
		local def = Config.Classes[className]
		UIKit.text({
			Position = UDim2.fromOffset(4, 20),
			Size = UDim2.new(1, -8, 0, 34),
			TextSize = 14,
			TextWrapped = true,
			TextColor3 = classColor(className),
			Text = def.DisplayName,
			ZIndex = 24,
			Parent = card,
		})
		UIKit.text({
			Position = UDim2.fromOffset(0, 52),
			Size = UDim2.new(1, 0, 0, 14),
			TextSize = 11,
			Font = UIKit.FONT_LIGHT,
			TextColor3 = classColor(className),
			Text = Config.Rarities[def.Rarity].DisplayName,
			ZIndex = 24,
			Parent = card,
		})
	else
		UIKit.text({
			Position = UDim2.fromOffset(0, 30),
			Size = UDim2.new(1, 0, 0, 20),
			TextSize = 14,
			TextColor3 = C.Dim,
			Text = "Vacío",
			ZIndex = 24,
			Parent = card,
		})
	end

	-- Boton segun el estado
	local label, color, action
	if className and equipped then
		label, color = "EQUIPADA", C.ButtonOff
	elseif className then
		label, color = "Equipar", C.Button
		action = function()
			invoke("RequestEquipSlot", index)
			refresh()
		end
	end
	if label then
		local button = UIKit.button({
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -6),
			Size = UDim2.new(1, -12, 0, 28),
			BackgroundColor3 = color,
			TextColor3 = if color == C.Accent then Color3.new(0, 0, 0) else C.Text,
			TextSize = 13,
			Text = label,
			ZIndex = 24,
			Parent = card,
		}, function()
			if action then
				action()
			end
		end)
		button.AutoButtonColor = action ~= nil
	end
end

local function makeBuySlotCard(layoutOrder: number)
	local card = UIKit.make("Frame", {
		Size = UDim2.fromOffset(100, 110),
		BackgroundColor3 = C.Row,
		BackgroundTransparency = 0.4,
		LayoutOrder = layoutOrder,
		ZIndex = 23,
		Parent = slotsFrame,
	}, { UIKit.corner(8) })
	UIKit.text({
		Position = UDim2.fromOffset(0, 18),
		Size = UDim2.new(1, 0, 0, 40),
		TextSize = 30,
		TextColor3 = C.Dim,
		Text = "+",
		ZIndex = 24,
		Parent = card,
	})
	UIKit.button({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -6),
		Size = UDim2.new(1, -12, 0, 28),
		BackgroundColor3 = Color3.fromRGB(0, 140, 70),
		TextSize = 12,
		Text = "Slot (Robux)",
		ZIndex = 24,
		Parent = card,
	}, function()
		Remotes.event("RequestBuyProduct"):FireServer("ClassSlot")
	end)
end

----------------------------------------------------------------------
-- Ruleta
----------------------------------------------------------------------

local function randomClassForStrip(): string
	return Util.weightedRandom(Config.Roulette.Weights) or Config.DefaultClass
end

local function playSpin(result: string, onDone: () -> ())
	animating = true
	strip:ClearAllChildren()
	strip.Position = UDim2.fromOffset(0, 0)

	local count = 40
	local finalIndex = 34
	for i = 1, count do
		local className = if i == finalIndex then result else randomClassForStrip()
		local def = Config.Classes[className]
		local cell = UIKit.make("Frame", {
			Position = UDim2.fromOffset((i - 1) * ITEM_WIDTH, 0),
			Size = UDim2.fromOffset(ITEM_WIDTH - 6, 56),
			BackgroundColor3 = C.Row,
			ZIndex = 24,
			Parent = strip,
		}, {
			UIKit.corner(6),
			UIKit.make("UIStroke", { Color = classColor(className), Thickness = 1.5 }),
		})
		UIKit.text({
			Size = UDim2.fromScale(1, 1),
			TextSize = 15,
			TextWrapped = true,
			TextColor3 = classColor(className),
			Text = def.DisplayName,
			ZIndex = 25,
			Parent = cell,
		})
	end

	local windowWidth = stripWindow.AbsoluteSize.X
	local maxJitter = math.floor(ITEM_WIDTH * 0.3)
	local jitter = math.random(-maxJitter, maxJitter)
	local targetX = windowWidth / 2 - (finalIndex - 1) * ITEM_WIDTH - (ITEM_WIDTH - 6) / 2 + jitter
	local tween = TweenService:Create(
		strip,
		TweenInfo.new(SPIN_SECONDS, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{ Position = UDim2.fromOffset(targetX, 0) }
	)
	tween.Completed:Once(function()
		animating = false
		onDone()
	end)
	tween:Play()
end

local function onSpin()
	if animating or busy then
		return
	end
	-- Congelar la vista (y la clase del HUD) mientras se pide el giro,
	-- para no revelar el resultado antes de la animacion
	animating = true
	player:SetAttribute("SpinAnimating", true)
	local ok, message, className = invoke("RequestSpin")
	if not ok or type(className) ~= "string" then
		animating = false
		player:SetAttribute("SpinAnimating", nil)
		refresh()
		return
	end
	statusLabel.Text = ""
	resultLabel.Text = "Girando..."
	resultLabel.TextColor3 = C.Dim
	playSpin(className, function()
		player:SetAttribute("SpinAnimating", nil)
		resultLabel.Text = message or ""
		resultLabel.TextColor3 = classColor(className)
		refresh()
	end)
end

----------------------------------------------------------------------
-- Refresco
----------------------------------------------------------------------

refresh = function()
	if not window then
		return
	end
	-- Diamantes
	local diamonds = player:GetAttribute("Diamonds") or 0
	local text = string.format("%s %d diamantes", DIAMOND, diamonds)
	if player:GetAttribute("PaidRandomRestricted") then
		local spendable = math.max(0, diamonds - (player:GetAttribute("PaidDiamonds") or 0))
		text ..= string.format("  (%d usables en la ruleta en tu país)", spendable)
	end
	diamondsLabel.Text = text

	-- Slots
	for _, child in slotsFrame:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local maxSlots = player:GetAttribute("MaxSlots") or Config.Roulette.DefaultSlots
	for i = 1, maxSlots do
		makeCard(i, i)
	end
	if maxSlots < Config.Roulette.MaxSlots then
		makeBuySlotCard(99)
	end

	-- Ruleta
	spinButton.Text = string.format("Girar  (%d %s)", Config.Roulette.SpinCost, DIAMOND)
	spinButton.BackgroundColor3 = if animating or diamonds < Config.Roulette.SpinCost then C.ButtonOff else C.Button
end

function ClassUI.Open()
	if not Place.ClassesEnabledHere() then
		HUD.Toast("La ruleta y los slots están en el lobby. Pulsa [L] para volver.", "info")
		return
	end
	if GameState.Folder:GetAttribute("Phase") == "Night" then
		HUD.Toast("La ruleta y los slots no están disponibles durante la noche.", "bad")
		return
	end
	statusLabel.Text = ""
	refresh()
	window.Visible = true
end

function ClassUI.Close()
	window.Visible = false
end

----------------------------------------------------------------------
-- Construccion
----------------------------------------------------------------------

local function sectionTitle(parent, y: number, title: string)
	UIKit.text({
		Position = UDim2.fromOffset(0, y),
		Size = UDim2.new(1, 0, 0, 20),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 14,
		TextColor3 = C.Dim,
		Text = title,
		ZIndex = 22,
		Parent = parent,
	})
end

local function build()
	local gui = UIKit.make("ScreenGui", {
		Name = "ClassUI",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 5,
		Parent = player:WaitForChild("PlayerGui"),
	})
	local content
	window, content = UIKit.window(gui, "CLASES", Vector2.new(680, 560), ClassUI.Close)

	-- Diamantes + paquetes
	diamondsLabel = UIKit.text({
		Size = UDim2.new(1, -250, 0, 28),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = DIAMOND_COLOR,
		ZIndex = 22,
		Parent = content,
	})
	-- Comprar diamantes: en la tienda del lobby
	UIKit.button({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.fromOffset(170, 28),
		BackgroundColor3 = Color3.fromRGB(170, 120, 20),
		TextSize = 13,
		Text = "Tienda  (" .. DIAMOND .. ", slots, pases)",
		Visible = Place.IsLobby,
		ZIndex = 22,
		Parent = content,
	}, function()
		ClassUI.Close()
		StoreUI.Open()
	end)

	-- Slots
	sectionTitle(content, 38, "TUS SLOTS  (la clase equipada es la que usas en la partida)")
	slotsFrame = UIKit.make("Frame", {
		Position = UDim2.fromOffset(0, 60),
		Size = UDim2.new(1, 0, 0, 110),
		BackgroundTransparency = 1,
		ZIndex = 22,
		Parent = content,
	}, {
		UIKit.make("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})

	-- Ruleta
	sectionTitle(content, 182, "RULETA  (la clase que salga REEMPLAZA a la del slot equipado)")
	stripWindow = UIKit.make("Frame", {
		Position = UDim2.fromOffset(0, 204),
		Size = UDim2.new(1, 0, 0, 56),
		BackgroundColor3 = Color3.fromRGB(6, 6, 9),
		ClipsDescendants = true,
		ZIndex = 23,
		Parent = content,
	}, { UIKit.corner(8) })
	strip = UIKit.make("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 24,
		Parent = stripWindow,
	})
	-- Marcador central
	UIKit.make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.new(0, 3, 1, 0),
		BackgroundColor3 = C.Accent,
		BorderSizePixel = 0,
		ZIndex = 30,
		Parent = stripWindow,
	})
	resultLabel = UIKit.text({
		Position = UDim2.fromOffset(0, 264),
		Size = UDim2.new(1, 0, 0, 22),
		TextSize = 15,
		Text = "",
		ZIndex = 22,
		Parent = content,
	})
	spinButton = UIKit.button({
		Position = UDim2.fromOffset(0, 290),
		Size = UDim2.fromOffset(200, 36),
		ZIndex = 22,
		Parent = content,
	}, onSpin)

	-- Probabilidades (siempre visibles)
	sectionTitle(content, 336, "PROBABILIDADES")
	local oddsFrame = UIKit.make("Frame", {
		Position = UDim2.fromOffset(0, 358),
		Size = UDim2.new(1, 0, 0, 100),
		BackgroundTransparency = 1,
		ZIndex = 22,
		Parent = content,
	}, {
		UIKit.make("UIGridLayout", {
			CellSize = UDim2.new(0.5, -6, 0, 18),
			CellPadding = UDim2.fromOffset(6, 2),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	local total = 0
	for _, w in Config.Roulette.Weights do
		total += w
	end
	for i, className in Config.ClassOrder do
		local def = Config.Classes[className]
		local percent = (Config.Roulette.Weights[className] or 0) / total * 100
		UIKit.text({
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextSize = 13,
			Font = UIKit.FONT_LIGHT,
			RichText = true,
			Text = string.format(
				'<font color="#%s"><b>%s</b></font>  %s%%  <font color="#999999">· %s</font>',
				classColor(className):ToHex(),
				def.DisplayName,
				if percent < 10 then string.format("%.1f", percent) else tostring(math.floor(percent + 0.5)),
				def.Description
			),
			LayoutOrder = i,
			ZIndex = 23,
			Parent = oddsFrame,
		})
	end

	statusLabel = UIKit.text({
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 22),
		TextSize = 15,
		Text = "",
		ZIndex = 22,
		Parent = content,
	})
end

function ClassUI.Start()
	build()

	local watched = { "Diamonds", "PaidDiamonds", "MaxSlots", "EquippedSlot", "PaidRandomRestricted" }
	for i = 1, Config.Roulette.MaxSlots do
		table.insert(watched, "Slot_" .. i)
	end
	for _, attr in watched do
		player:GetAttributeChangedSignal(attr):Connect(function()
			if window.Visible and not animating then
				refresh()
			end
		end)
	end

	GameState.Folder:GetAttributeChangedSignal("Phase"):Connect(function()
		if GameState.Folder:GetAttribute("Phase") == "Night" and not animating then
			ClassUI.Close()
		end
	end)

	ContextActionService:BindAction("Classes", function(_, state)
		if state == Enum.UserInputState.Begin then
			if window.Visible then
				ClassUI.Close()
			else
				ClassUI.Open()
			end
		end
		return Enum.ContextActionResult.Pass
	end, not Place.IsLobby, Enum.KeyCode.C) -- en el lobby el boton tactil sobra (puesto CLASES)
	ContextActionService:SetTitle("Classes", "Clases")
	ContextActionService:SetPosition("Classes", UDim2.new(1, -100, 1, -300))
end

return ClassUI
