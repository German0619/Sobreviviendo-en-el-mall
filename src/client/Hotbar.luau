-- Hotbar (mall): inventario con imagenes, abajo al centro (sustituye a la mochila nativa).
--
-- Cada herramienta de la mochila (las crea server/BackpackService: objetos, armas y el
-- fumigador) es una casilla con su modelo 3D (el mismo de HeldModels, en un
-- ViewportFrame), el numero de tecla, la cantidad o los usos y un fondo por rareza.
--
-- Controles:
--   * PC: teclas 1-9 y 0, rueda del raton (siguiente / anterior) y clic en la casilla.
--     Pulsar la tecla de lo que ya tienes en la mano lo guarda.
--   * Tactil: tocar la casilla (otra vez para guardarlo). Se usa tocando la pantalla.
--   * Mando: cruceta izquierda / derecha (anterior / siguiente) y abajo para guardar.
-- Usar el objeto sigue siendo lo de siempre (clic / tocar con la herramienta en la mano).

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local HeldModels = require(Shared.HeldModels)

local player = Players.LocalPlayer

local Hotbar = {}

local MAX_KEYS = 10 -- 1..9 y 0
local NUMBER_KEYS = {
	[Enum.KeyCode.One] = 1,
	[Enum.KeyCode.Two] = 2,
	[Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.Four] = 4,
	[Enum.KeyCode.Five] = 5,
	[Enum.KeyCode.Six] = 6,
	[Enum.KeyCode.Seven] = 7,
	[Enum.KeyCode.Eight] = 8,
	[Enum.KeyCode.Nine] = 9,
	[Enum.KeyCode.Zero] = 10,
	[Enum.KeyCode.KeypadOne] = 1,
	[Enum.KeyCode.KeypadTwo] = 2,
	[Enum.KeyCode.KeypadThree] = 3,
	[Enum.KeyCode.KeypadFour] = 4,
	[Enum.KeyCode.KeypadFive] = 5,
	[Enum.KeyCode.KeypadSix] = 6,
	[Enum.KeyCode.KeypadSeven] = 7,
	[Enum.KeyCode.KeypadEight] = 8,
	[Enum.KeyCode.KeypadNine] = 9,
	[Enum.KeyCode.KeypadZero] = 10,
}

-- Rareza de cada objeto (solo el color de la casilla, como en los shooters)
local RARITY = {
	Common = { Color3.fromRGB(120, 126, 138), Color3.fromRGB(62, 66, 76) },
	Uncommon = { Color3.fromRGB(96, 170, 58), Color3.fromRGB(34, 82, 30) },
	Rare = { Color3.fromRGB(56, 150, 230), Color3.fromRGB(22, 62, 130) },
	Epic = { Color3.fromRGB(178, 84, 232), Color3.fromRGB(78, 30, 128) },
	Legendary = { Color3.fromRGB(240, 160, 48), Color3.fromRGB(140, 66, 18) },
}
local ITEM_RARITY = {
	Battery = "Uncommon",
	Medkit = "Uncommon",
	Flare = "Uncommon",
	Firecracker = "Uncommon",
	LithiumBattery = "Rare",
	BigMedkit = "Rare",
	MagnesiumFlare = "Rare",
	BigFirecracker = "Rare",
	SmokeBomb = "Epic",
	MysterySoda = "Epic",
	Taser = "Rare",
	Extinguisher = "Rare",
	WetFloorSign = "Uncommon",
	Mop = "Uncommon",
	UVFlashlight = "Epic",
	Machete = "Epic",
	Pistol = "Legendary",
	Fumigator = "Legendary",
}

-- Desde donde se mira cada modelo en su casilla (direccion desde el objeto a la camara,
-- en el espacio del modelo: -Z es su frente). Por defecto, de lado y un poco de frente.
local VIEW_DIR = {
	Medkit = Vector3.new(0.35, 0.35, -1),
	BigMedkit = Vector3.new(0.35, 0.35, -1),
	WetFloorSign = Vector3.new(0.3, 0.2, -1),
	Battery = Vector3.new(0.6, 0.45, -1),
	LithiumBattery = Vector3.new(0.6, 0.45, -1),
	MysterySoda = Vector3.new(0.6, 0.35, -1),
	SmokeBomb = Vector3.new(0.6, 0.35, -1),
	Firecracker = Vector3.new(0.6, 0.35, -1),
	BigFirecracker = Vector3.new(0.6, 0.35, -1),
	Extinguisher = Vector3.new(1, 0.3, -0.6),
}
local DEFAULT_VIEW = Vector3.new(1, 0.4, -0.45)

local gui: ScreenGui
local bar: Frame
local nameLabel: TextLabel
local descLabel: TextLabel
local nameGroup: Frame

-- [Tool] = { Order, Slot, ... }
local entries: { [Tool]: any } = {}
local nextOrder = 0
local ordered: { Tool } = {}
local lastSelected: Tool? = nil

local function slotSize(): number
	local camera = workspace.CurrentCamera
	local h = camera and camera.ViewportSize.Y or 720
	return math.clamp(math.floor(h * 0.085), 46, 70)
end

local function humanoid(): Humanoid?
	local character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

local function equippedTool(): Tool?
	local character = player.Character
	return character and character:FindFirstChildOfClass("Tool")
end

local function modelIdOf(tool: Tool): string
	local id = tool:GetAttribute("ModelId")
	return if type(id) == "string" then id else tool.Name
end

local function displayName(tool: Tool): string
	local id = modelIdOf(tool)
	local item = Config.ShopItems[id]
	if item then
		return item.DisplayName
	end
	if id == "Fumigator" then
		return "Fumigador"
	end
	return (string.gsub(tool.Name, "%s*[x%(].*$", ""))
end

-- "Bateria x2" -> "x2"; "Taser (9)" -> "9"; "Taser (∞)" -> "∞"
local function badgeText(tool: Tool): string
	local count = string.match(tool.Name, "x(%d+)%s*$")
	if count then
		return if count == "1" then "" else "x" .. count
	end
	local uses = string.match(tool.Name, "%((.-)%)%s*$")
	if uses and not string.find(uses, " ") then
		return uses
	end
	return ""
end

----------------------------------------------------------------------
-- Imagen 3D de la casilla
----------------------------------------------------------------------

local function buildIcon(viewport: ViewportFrame, tool: Tool)
	viewport:ClearAllChildren()
	local id = modelIdOf(tool)
	local skin = tool:GetAttribute("Skin")
	local model = HeldModels.build(id, if type(skin) == "string" then skin else nil)
	if not model then
		return
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CastShadow = false
		end
	end
	local handle = model.PrimaryPart
	if handle then
		handle.Transparency = 1
	end
	model:PivotTo(CFrame.identity)
	model.Parent = viewport

	-- Encuadre: esfera que envuelve las piezas visibles, vista desde VIEW_DIR
	local minV, maxV = Vector3.one * math.huge, -Vector3.one * math.huge
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d ~= handle and d.Transparency < 1 then
			local half = d.Size / 2
			for _, sx in { -1, 1 } do
				for _, sy in { -1, 1 } do
					for _, sz in { -1, 1 } do
						local p = d.CFrame:PointToWorldSpace(Vector3.new(half.X * sx, half.Y * sy, half.Z * sz))
						minV = minV:Min(p)
						maxV = maxV:Max(p)
					end
				end
			end
		end
	end
	if minV.X == math.huge then
		return
	end
	local center = (minV + maxV) / 2
	local radius = math.max((maxV - minV).Magnitude / 2, 0.2)
	local camera = Instance.new("Camera")
	camera.FieldOfView = 30
	local dir = (VIEW_DIR[id] or DEFAULT_VIEW).Unit
	local distance = radius / math.sin(math.rad(camera.FieldOfView / 2)) * 0.92
	camera.CFrame = CFrame.lookAt(center + dir * distance, center)
	camera.Parent = viewport
	viewport.CurrentCamera = camera
end

----------------------------------------------------------------------
-- Casillas
----------------------------------------------------------------------

local function newSlot(): any
	local slot = Instance.new("TextButton")
	slot.Name = "Slot"
	slot.AutoButtonColor = false
	slot.Text = ""
	slot.BackgroundColor3 = Color3.new(1, 1, 1)
	slot.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.14, 0)
	corner.Parent = slot
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Parent = slot
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Thickness = 2
	stroke.Color = Color3.fromRGB(20, 22, 30)
	stroke.Transparency = 0.2
	stroke.Parent = slot

	-- Brillo radial detras del objeto
	local glow = Instance.new("Frame")
	glow.Name = "Glow"
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.Position = UDim2.fromScale(0.5, 0.45)
	glow.Size = UDim2.fromScale(0.95, 0.95)
	glow.BackgroundColor3 = Color3.new(1, 1, 1)
	glow.BackgroundTransparency = 0.75
	glow.BorderSizePixel = 0
	glow.ZIndex = 1
	glow.Parent = slot
	local glowCorner = Instance.new("UICorner")
	glowCorner.CornerRadius = UDim.new(0.5, 0)
	glowCorner.Parent = glow
	local glowGradient = Instance.new("UIGradient")
	glowGradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(0.6, 0.85),
		NumberSequenceKeypoint.new(1, 1),
	})
	glowGradient.Parent = glow

	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "Icon"
	viewport.BackgroundTransparency = 1
	viewport.AnchorPoint = Vector2.new(0.5, 0.5)
	viewport.Position = UDim2.fromScale(0.5, 0.48)
	viewport.Size = UDim2.fromScale(0.92, 0.92)
	viewport.Ambient = Color3.fromRGB(170, 170, 180)
	viewport.LightColor = Color3.fromRGB(255, 250, 240)
	viewport.LightDirection = Vector3.new(-1, -1.4, -0.6)
	viewport.ZIndex = 2
	viewport.Parent = slot

	-- Franja oscura abajo (cantidad)
	local shade = Instance.new("Frame")
	shade.Name = "Shade"
	shade.AnchorPoint = Vector2.new(0, 1)
	shade.Position = UDim2.fromScale(0, 1)
	shade.Size = UDim2.fromScale(1, 0.3)
	shade.BackgroundColor3 = Color3.new(0, 0, 0)
	shade.BorderSizePixel = 0
	shade.ZIndex = 3
	shade.Parent = slot
	local shadeGradient = Instance.new("UIGradient")
	shadeGradient.Rotation = 90
	shadeGradient.Transparency = NumberSequence.new(1, 0.35)
	shadeGradient.Parent = shade
	local shadeCorner = Instance.new("UICorner")
	shadeCorner.CornerRadius = UDim.new(0.3, 0)
	shadeCorner.Parent = shade

	local key = Instance.new("TextLabel")
	key.Name = "Key"
	key.BackgroundTransparency = 1
	key.Position = UDim2.fromScale(0.07, 0.04)
	key.Size = UDim2.fromScale(0.32, 0.3)
	key.Font = Enum.Font.GothamBlack
	key.TextScaled = true
	key.TextXAlignment = Enum.TextXAlignment.Left
	key.TextYAlignment = Enum.TextYAlignment.Top
	key.TextColor3 = Color3.new(1, 1, 1)
	key.TextStrokeTransparency = 0.4
	key.ZIndex = 4
	key.Parent = slot

	local count = Instance.new("TextLabel")
	count.Name = "Count"
	count.BackgroundTransparency = 1
	count.AnchorPoint = Vector2.new(1, 1)
	count.Position = UDim2.fromScale(0.94, 0.97)
	count.Size = UDim2.fromScale(0.7, 0.3)
	count.Font = Enum.Font.GothamBlack
	count.TextScaled = true
	count.TextXAlignment = Enum.TextXAlignment.Right
	count.TextColor3 = Color3.new(1, 1, 1)
	count.TextStrokeTransparency = 0.3
	count.ZIndex = 4
	count.Parent = slot

	local scale = Instance.new("UIScale")
	scale.Parent = slot

	return {
		Button = slot,
		Gradient = gradient,
		Stroke = stroke,
		Glow = glow,
		Viewport = viewport,
		Key = key,
		Count = count,
		Scale = scale,
	}
end

local function styleSlot(entry, index: number, selected: boolean)
	local slot = entry.Slot
	local rarity = RARITY[ITEM_RARITY[modelIdOf(entry.Tool)] or "Common"] or RARITY.Common
	slot.Gradient.Color = ColorSequence.new(rarity[1], rarity[2])
	slot.Glow.BackgroundColor3 = rarity[1]:Lerp(Color3.new(1, 1, 1), 0.5)
	slot.Key.Text = if index <= MAX_KEYS then tostring(index % 10) else ""
	slot.Count.Text = badgeText(entry.Tool)
	slot.Button.LayoutOrder = index
	slot.Stroke.Color = if selected then Color3.fromRGB(255, 255, 255) else Color3.fromRGB(20, 22, 30)
	slot.Stroke.Thickness = if selected then 3 else 2
	slot.Stroke.Transparency = if selected then 0 else 0.2
	TweenService:Create(slot.Scale, TweenInfo.new(0.12, Enum.EasingStyle.Quad), { Scale = if selected then 1.14 else 1 }):Play()
end

----------------------------------------------------------------------
-- Nombre del objeto en la mano (aparece al cambiar y se desvanece)
----------------------------------------------------------------------

local nameToken = 0
local function fadeName(transparency: number, seconds: number)
	local info = TweenInfo.new(seconds)
	TweenService:Create(nameLabel, info, { TextTransparency = transparency, TextStrokeTransparency = math.max(transparency, 0.5) }):Play()
	TweenService:Create(descLabel, info, { TextTransparency = transparency, TextStrokeTransparency = math.max(transparency, 0.6) }):Play()
end

local function showName(tool: Tool?)
	nameToken += 1
	local token = nameToken
	if not tool then
		fadeName(1, 0.2)
		return
	end
	local id = modelIdOf(tool)
	local item = Config.ShopItems[id]
	nameLabel.Text = string.upper(displayName(tool))
	local rarity = RARITY[ITEM_RARITY[id] or "Common"] or RARITY.Common
	nameLabel.TextColor3 = rarity[1]:Lerp(Color3.new(1, 1, 1), 0.35)
	descLabel.Text = if item and item.Description then item.Description else tool.ToolTip
	fadeName(0, 0.1)
	task.delay(2.5, function()
		if token == nameToken then
			fadeName(1, 0.6)
		end
	end)
end

----------------------------------------------------------------------
-- Estado
----------------------------------------------------------------------

local function refresh()
	table.clear(ordered)
	for tool in entries do
		table.insert(ordered, tool)
	end
	table.sort(ordered, function(a, b)
		return entries[a].Order < entries[b].Order
	end)
	local current = equippedTool()
	for i, tool in ordered do
		styleSlot(entries[tool], i, tool == current)
	end
	bar.Visible = #ordered > 0
	if current ~= lastSelected then
		lastSelected = current
		showName(current)
	end
end

local function track(tool: Instance)
	if not tool:IsA("Tool") or entries[tool] then
		return
	end
	nextOrder += 1
	local slot = newSlot()
	local entry = { Tool = tool, Order = nextOrder, Slot = slot, Conns = {} }
	entries[tool] = entry
	slot.Button.Size = UDim2.fromOffset(slotSize(), slotSize())
	slot.Button.Parent = bar
	buildIcon(slot.Viewport, tool)

	slot.Button.Activated:Connect(function()
		Hotbar.Toggle(tool)
	end)
	table.insert(entry.Conns, tool:GetPropertyChangedSignal("Name"):Connect(refresh))
	table.insert(entry.Conns, tool:GetAttributeChangedSignal("Skin"):Connect(function()
		buildIcon(slot.Viewport, tool)
	end))
	table.insert(entry.Conns, tool.AncestryChanged:Connect(function()
		local character = player.Character
		local backpack = player:FindFirstChildOfClass("Backpack")
		local parent = tool.Parent
		if parent == nil or (parent ~= character and parent ~= backpack) then
			for _, c in entry.Conns do
				c:Disconnect()
			end
			slot.Button:Destroy()
			entries[tool] = nil
		end
		task.defer(refresh)
	end))
	refresh()
end

function Hotbar.Toggle(tool: Tool)
	local hum = humanoid()
	if not hum or hum.Health <= 0 then
		return
	end
	if tool.Parent == player.Character then
		hum:UnequipTools()
	else
		hum:EquipTool(tool)
	end
end

local function selectIndex(index: number)
	local tool = ordered[index]
	if tool then
		Hotbar.Toggle(tool)
	end
end

local function cycle(step: number)
	if #ordered == 0 then
		return
	end
	local hum = humanoid()
	if not hum or hum.Health <= 0 then
		return
	end
	local current = equippedTool()
	local index = table.find(ordered, current :: any)
	local nextIndex
	if index then
		nextIndex = (index - 1 + step) % #ordered + 1
	else
		nextIndex = if step > 0 then 1 else #ordered
	end
	hum:EquipTool(ordered[nextIndex])
end

local function watchContainer(container: Instance)
	for _, child in container:GetChildren() do
		track(child)
	end
	container.ChildAdded:Connect(function(child)
		track(child)
		task.defer(refresh)
	end)
	container.ChildRemoved:Connect(function()
		task.defer(refresh)
	end)
end

local function disableNativeBackpack()
	for _ = 1, 20 do
		local ok = pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.Backpack, false)
		if ok then
			return
		end
		task.wait(0.5)
	end
end

----------------------------------------------------------------------
-- Arranque
----------------------------------------------------------------------

function Hotbar.Start()
	task.spawn(disableNativeBackpack)

	gui = Instance.new("ScreenGui")
	gui.Name = "Hotbar"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 5
	gui.Parent = player:WaitForChild("PlayerGui")

	bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.Position = UDim2.new(0.5, 0, 1, -14)
	bar.Size = UDim2.fromScale(0, 0)
	bar.AutomaticSize = Enum.AutomaticSize.XY
	bar.BackgroundTransparency = 1
	bar.Visible = false
	bar.Parent = gui
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Bottom
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 8)
	list.Parent = bar

	nameGroup = Instance.new("Frame")
	nameGroup.Name = "ItemName"
	nameGroup.AnchorPoint = Vector2.new(0.5, 1)
	nameGroup.BackgroundTransparency = 1
	nameGroup.Size = UDim2.fromOffset(420, 46)
	nameGroup.Parent = gui
	nameLabel = Instance.new("TextLabel")
	nameLabel.BackgroundTransparency = 1
	nameLabel.Size = UDim2.new(1, 0, 0, 26)
	nameLabel.Font = Enum.Font.GothamBlack
	nameLabel.TextSize = 22
	nameLabel.Text = ""
	nameLabel.TextTransparency = 1
	nameLabel.TextStrokeTransparency = 1
	nameLabel.Parent = nameGroup
	descLabel = Instance.new("TextLabel")
	descLabel.BackgroundTransparency = 1
	descLabel.Position = UDim2.fromOffset(0, 26)
	descLabel.Size = UDim2.new(1, 0, 0, 18)
	descLabel.Font = Enum.Font.GothamMedium
	descLabel.TextSize = 14
	descLabel.TextColor3 = Color3.fromRGB(225, 228, 238)
	descLabel.Text = ""
	descLabel.TextTransparency = 1
	descLabel.TextStrokeTransparency = 1
	descLabel.Parent = nameGroup

	-- El nombre va justo encima de la barra (la barra cambia de alto con la pantalla)
	local function placeName()
		nameGroup.Position = UDim2.new(0.5, 0, 1, -14 - slotSize() * 1.14 - 10)
		for _, entry in entries do
			entry.Slot.Button.Size = UDim2.fromOffset(slotSize(), slotSize())
		end
	end
	placeName()
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(placeName)
	if workspace.CurrentCamera then
		workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(placeName)
	end

	-- Mochila y personaje (al reaparecer, la mochila es nueva)
	local function onCharacter(character: Model)
		watchContainer(character)
		local backpack = player:WaitForChild("Backpack", 10)
		if backpack then
			watchContainer(backpack)
		end
		refresh()
	end
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
	player.CharacterAdded:Connect(onCharacter)

	-- Teclas 1-9 / 0 y rueda del raton
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or UserInputService:GetFocusedTextBox() then
			return
		end
		local index = NUMBER_KEYS[input.KeyCode]
		if index then
			selectIndex(index)
		end
	end)
	UserInputService.InputChanged:Connect(function(input, gameProcessed)
		if gameProcessed or input.UserInputType ~= Enum.UserInputType.MouseWheel then
			return
		end
		if GuiService.MenuIsOpen then
			return
		end
		-- Rueda hacia abajo = siguiente casilla (como en Fortnite / Minecraft)
		cycle(if input.Position.Z < 0 then 1 else -1)
	end)

	-- Mando: cruceta
	ContextActionService:BindAction("HotbarGamepad", function(_, state, input)
		if state ~= Enum.UserInputState.Begin then
			return Enum.ContextActionResult.Pass
		end
		if input.KeyCode == Enum.KeyCode.DPadRight then
			cycle(1)
		elseif input.KeyCode == Enum.KeyCode.DPadLeft then
			cycle(-1)
		elseif input.KeyCode == Enum.KeyCode.DPadDown then
			local hum = humanoid()
			if hum then
				hum:UnequipTools()
			end
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.DPadLeft, Enum.KeyCode.DPadRight, Enum.KeyCode.DPadDown)
end

return Hotbar
