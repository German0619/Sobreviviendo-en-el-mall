-- Defense: controles y efectos locales de las defensas (Fase 5).
--   [G]       Destello de linterna
--   [Q]       Habilidad de clase (Porrazo del Guardia), solo si la clase la tiene
--   [Espacio] Salir del escondite (tambien con E sobre el escondite)
-- Tambien dibuja la vista desde dentro del escondite y los tiempos de recarga.
-- El servidor (DefenseService) valida todo; aqui solo se piden las acciones.

local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Tags = require(Shared.Tags)
local Remotes = require(Shared.Remotes)
local UIKit = require(script.Parent.UIKit)
local InputHints = require(script.Parent.InputHints)

local player = Players.LocalPlayer
local C = UIKit.COLORS

local Defense = {}

local gui, abilitiesLabel, overlay, overlayLabel, flashFrame
local slitsView, carView -- vista por defecto (taquilla) y la del coche
local views: { [string]: Frame } = {} -- vista desde dentro de cada tipo de escondite
local CAR_SPOTS = { Coche = true } -- escondites con vista de coche (DisplayName)
-- Tipo de vista segun el escondite (DisplayName). Los que no estan: taquilla.
local HIDE_VIEWS = {
	Taquilla = "Locker",
	Casillero = "Locker",
	Armario = "Cabinet",
	["Armario de limpieza"] = "Cabinet",
	["Armario de obra"] = "Cabinet",
	Probador = "CurtainRed",
	Cortina = "CurtainDark",
	["Fotomatón"] = "CurtainBooth",
	["Baño portátil"] = "Toilet",
}
local lastFlashReadyAt = 0

----------------------------------------------------------------------
-- Interfaz
----------------------------------------------------------------------

local function build()
	gui = UIKit.make("ScreenGui", {
		Name = "DefenseUI",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 2,
		Parent = player:WaitForChild("PlayerGui"),
	})
	UIKit.adapt(gui)

	-- Arriba al centro, bajo la hora y la fase del HUD (abajo esta la mochila)
	abilitiesLabel = UIKit.text({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 98),
		Size = UDim2.fromOffset(600, 22),
		TextSize = 15,
		RichText = true,
		TextStrokeTransparency = 0.6,
		Text = "",
		Parent = gui,
	})
	-- En telefono el bloque central del HUD es mas pequeno y esta mas arriba (HUD.applyCenterLayout)
	local function placeAbilities()
		abilitiesLabel.Position = UDim2.new(0.5, 0, 0, if UIKit.isPhone(gui) then 66 else 98)
	end
	placeAbilities()
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(placeAbilities)

	-- Vista desde dentro del escondite: franjas oscuras con rendijas
	overlay = UIKit.make("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 3,
		Parent = gui,
	})
	-- Una vista por tipo de escondite (HIDE_VIEWS): lo que se ve por dentro de la puerta
	local function view(): Frame
		return UIKit.make("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Visible = false,
			ZIndex = 3,
			Parent = overlay,
		})
	end
	local function solid(parent: Instance, x: number, y: number, w: number, h: number, color: Color3, props: { [string]: any }?): Frame
		-- Los paneles que tocan un borde se alargan fuera de la pantalla (si no, queda a la
		-- vista la franja del margen seguro de arriba / los lados)
		local EDGE = 0.25
		if y <= 0 then
			y, h = y - EDGE, h + EDGE
		end
		if y + h >= 0.999 then
			h += EDGE
		end
		if x <= 0 then
			x, w = x - EDGE, w + EDGE
		end
		if x + w >= 0.999 then
			w += EDGE
		end
		local f = UIKit.make("Frame", {
			Position = UDim2.fromScale(x, y),
			Size = UDim2.fromScale(w, h),
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			ZIndex = 3,
			Parent = parent,
		})
		for k, v in props or {} do
			(f :: any)[k] = v
		end
		return f
	end
	local function shade(parent: Instance, rotation: number, from: number, to: number)
		UIKit.make("UIGradient", {
			Rotation = rotation,
			Color = ColorSequence.new(Color3.new(from, from, from), Color3.new(to, to, to)),
			Parent = parent,
		})
	end

	-- Taquilla / casillero: puerta de chapa con la rejilla de ventilacion a la altura de los ojos
	do
		local v = view()
		local steel = Color3.fromRGB(30, 36, 44)
		local top, bottom, left, right = 0.24, 0.68, 0.16, 0.84
		shade(solid(v, 0, 0, 1, top, steel), 90, 0.7, 1)
		shade(solid(v, 0, bottom, 1, 1 - bottom, steel), 90, 1, 0.6)
		solid(v, 0, top, left, bottom - top, steel)
		solid(v, right, top, 1 - right, bottom - top, steel)
		local slits = 7
		local step = (bottom - top) / slits
		for i = 0, slits - 1 do
			-- lama inclinada: franja solida con un borde claro (luz rozando el metal)
			solid(v, left, top + i * step + step * 0.45, right - left, step * 0.55, steel)
			solid(v, left, top + i * step + step * 0.45, right - left, step * 0.06, Color3.fromRGB(70, 78, 88))
		end
		views.Locker = v
	end

	-- Armario de dos puertas: se mira por la rendija entre las hojas
	do
		local v = view()
		local metal = Color3.fromRGB(34, 35, 40)
		local gapL, gapR = 0.47, 0.53
		local leftDoor = solid(v, 0, 0, gapL, 1, metal)
		shade(leftDoor, 0, 0.55, 1)
		local rightDoor = solid(v, gapR, 0, 1 - gapR, 1, metal)
		shade(rightDoor, 0, 1, 0.55)
		-- Cantos de las puertas (refuerzo) y bisagras
		solid(v, gapL - 0.012, 0, 0.012, 1, Color3.fromRGB(58, 60, 66))
		solid(v, gapR, 0, 0.012, 1, Color3.fromRGB(58, 60, 66))
		for _, y in { 0.15, 0.8 } do
			solid(v, 0.02, y, 0.02, 0.07, Color3.fromRGB(70, 72, 78))
			solid(v, 0.96, y, 0.02, 0.07, Color3.fromRGB(70, 72, 78))
		end
		-- Balda de arriba (sombra) y mecanismo de la cerradura en la hoja derecha
		solid(v, 0, 0, 1, 0.06, Color3.fromRGB(12, 12, 14))
		solid(v, gapR + 0.02, 0.46, 0.05, 0.1, Color3.fromRGB(80, 82, 88))
		views.Cabinet = v
	end

	-- Cortinas (probador, cortina del cine, fotomaton): dos paños con pliegues y una abertura
	local function curtainView(color: Color3): Frame
		local v = view()
		local keys = {}
		for i = 0, 10 do
			local k = if i % 2 == 0 then 1 else 0.45
			table.insert(keys, ColorSequenceKeypoint.new(i / 10, Color3.new(k, k, k)))
		end
		for _, side in { { 0, 0.41 }, { 0.59, 0.41 } } do
			local panel = solid(v, side[1], 0.03, side[2], 0.97, color)
			UIKit.make("UIGradient", { Color = ColorSequence.new(keys), Parent = panel })
		end
		-- Bordes de los paños algo mas oscuros (sombra del pliegue en la abertura)
		solid(v, 0.4, 0.03, 0.012, 0.97, color:Lerp(Color3.new(0, 0, 0), 0.6))
		solid(v, 0.588, 0.03, 0.012, 0.97, color:Lerp(Color3.new(0, 0, 0), 0.6))
		-- Barra y anillas
		solid(v, 0, 0, 1, 0.03, Color3.fromRGB(90, 92, 98))
		for i = 0, 11 do
			local x = if i < 6 then 0.02 + i * 0.07 else 0.6 + (i - 6) * 0.07
			local ring = solid(v, x, 0.012, 0.02, 0.035, Color3.fromRGB(150, 152, 158))
			UIKit.make("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = ring })
		end
		return v
	end
	views.CurtainRed = curtainView(Color3.fromRGB(125, 22, 34))
	views.CurtainDark = curtainView(Color3.fromRGB(80, 14, 24))
	views.CurtainBooth = curtainView(Color3.fromRGB(150, 30, 70))

	-- Baño portatil: plastico azul por todas partes; se mira por la rejilla de arriba y por la
	-- rendija de la puerta
	do
		local v = view()
		local plastic = Color3.fromRGB(26, 58, 100)
		local crackX, crackW = 0.6, 0.032
		local ventL, ventR, ventT, ventB = 0.28, 0.52, 0.07, 0.22
		-- Pared/puerta (todo menos la rejilla y la rendija)
		shade(solid(v, 0, 0, crackX, ventT, plastic), 90, 0.7, 1)
		solid(v, 0, ventT, ventL, ventB - ventT, plastic)
		solid(v, ventR, ventT, crackX - ventR, ventB - ventT, plastic)
		shade(solid(v, 0, ventB, crackX, 1 - ventB, plastic), 90, 1, 0.55)
		shade(solid(v, crackX + crackW, 0, 1 - crackX - crackW, 1, plastic:Lerp(Color3.new(0, 0, 0), 0.25)), 0, 1, 0.6)
		-- Lamas de la rejilla
		for i = 0, 3 do
			solid(v, ventL, ventT + i * (ventB - ventT) / 4 + 0.012, ventR - ventL, (ventB - ventT) / 4 * 0.55, plastic)
		end
		-- Paneles moldeados de la puerta y el pestillo "OCUPADO" (rojo)
		for _, y in { 0.3, 0.62 } do
			local p = solid(v, 0.08, y, 0.44, 0.26, plastic, { BackgroundTransparency = 1 })
			UIKit.make("UICorner", { CornerRadius = UDim.new(0.12, 0), Parent = p })
			UIKit.make("UIStroke", { Color = Color3.fromRGB(44, 80, 128), Thickness = 4, Parent = p })
		end
		solid(v, crackX - 0.06, 0.48, 0.05, 0.05, Color3.fromRGB(190, 40, 40))
		views.Toilet = v
	end
	slitsView = views.Locker
	-- Dentro de un coche: techo, montantes, salpicadero con volante y el cristal tintado
	carView = UIKit.make("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 3,
		Parent = overlay,
	})
	local interior = Color3.fromRGB(10, 10, 13)
	local function piece(props)
		props.BorderSizePixel = 0
		props.ZIndex = props.ZIndex or 3
		props.Parent = props.Parent or carView
		props.BackgroundColor3 = props.BackgroundColor3 or interior
		return UIKit.make("Frame", props)
	end
	piece({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(20, 40, 60), BackgroundTransparency = 0.82 }) -- tinte
	piece({ Size = UDim2.fromScale(1, 0.16) }) -- techo
	piece({ Position = UDim2.fromScale(0, 0.7), Size = UDim2.fromScale(1, 0.3) }) -- salpicadero
	piece({ Position = UDim2.fromScale(0, 0.68), Size = UDim2.fromScale(1, 0.025), BackgroundColor3 = Color3.fromRGB(28, 28, 32) }) -- borde
	for _, x in { 0, 0.94 } do
		piece({ Position = UDim2.fromScale(x, 0), Size = UDim2.fromScale(0.06, 1) }) -- montantes
	end
	local wheel = piece({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.3, 0.88),
		Size = UDim2.fromScale(0.42, 0.42),
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		BackgroundTransparency = 1,
		ZIndex = 4,
	})
	UIKit.make("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = wheel })
	UIKit.make("UIStroke", { Color = Color3.fromRGB(32, 32, 36), Thickness = 10, Parent = wheel })
	piece({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 0.12),
		BackgroundColor3 = Color3.fromRGB(32, 32, 36),
		ZIndex = 4,
		Parent = wheel,
	})
	local mirrorPart = piece({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.15), Size = UDim2.fromScale(0.14, 0.05), ZIndex = 4 })
	UIKit.make("UICorner", { CornerRadius = UDim.new(0, 6), Parent = mirrorPart })
	overlayLabel = UIKit.text({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -110),
		Size = UDim2.fromOffset(600, 26),
		TextSize = 17,
		TextStrokeTransparency = 0.4,
		Text = "",
		ZIndex = 4,
		Parent = overlay,
	})

	-- Fogonazo al usar el destello
	flashFrame = UIKit.make("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(255, 252, 235),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = gui,
	})
end

local function playFlash()
	flashFrame.BackgroundTransparency = 0.55
	TweenService:Create(flashFrame, TweenInfo.new(0.35, Enum.EasingStyle.Quad), { BackgroundTransparency = 1 }):Play()
end

-- action: nombre en InputHints (la tecla solo se muestra con teclado o mando).
local function cooldownText(action: string, name: string, readyAt: number, now: number, blockedReason: string?): string
	local label = InputHints.Label(action, name)
	local remaining = readyAt - now
	if remaining > 0 then
		return string.format('<font color="#9696A0">%s  %ds</font>', label, math.ceil(remaining))
	elseif blockedReason then
		return string.format('<font color="#E65050">%s  (%s)</font>', label, blockedReason)
	end
	return string.format('<font color="#5AD278">%s  listo</font>', label)
end

local function update()
	local now = Workspace:GetServerTimeNow()
	local hidden = player:GetAttribute("Hidden") == true
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local alive = humanoid ~= nil and humanoid.Health > 0

	if not alive or hidden then
		abilitiesLabel.Text = ""
	else
		local cost = Config.Defense.Flash.BatteryCost * (player:GetAttribute("Perk_FlashCostMultiplier") or 1)
		local battery = player:GetAttribute("Battery") or 0
		local parts = {
			cooldownText("Flash", "Destello", player:GetAttribute("FlashReadyAt") or 0, now, if battery < cost then "sin batería" else nil),
		}
		if player:GetAttribute("Perk_Shove") then
			table.insert(parts, cooldownText("Ability", "Porrazo", player:GetAttribute("AbilityReadyAt") or 0, now, nil))
		end
		abilitiesLabel.Text = table.concat(parts, "     ")
	end

	overlay.Visible = hidden and alive
	if overlay.Visible then
		local remaining = math.max(0, math.ceil((player:GetAttribute("HiddenUntil") or now) - now))
		local exitHint = if InputHints.IsTouch() then "toca Salir" else InputHints.Label("Unhide", "para salir")
		overlayLabel.Text = string.format("Escondido  ·  %s  ·  aire: %ds", exitHint, remaining)
		overlayLabel.TextColor3 = if remaining <= 5 then C.Bad else C.Text
	end
end

----------------------------------------------------------------------
-- Escondites
----------------------------------------------------------------------

-- El texto del prompt es distinto para quien esta dentro (solo en este cliente).
local function refreshHidePrompts()
	local hidden = player:GetAttribute("Hidden") == true
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?

	-- Escondido: el escondite propio es el mas cercano (estabas a su lado al entrar)
	local mine: Instance? = nil
	if hidden and root then
		local bestDist = math.huge
		for _, spot in CollectionService:GetTagged(Tags.HidingSpot) do
			if spot:IsA("BasePart") then
				local d = (root.Position - spot.Position).Magnitude
				if d < bestDist then
					mine, bestDist = spot, d
				end
			end
		end
	end

	for _, spot in CollectionService:GetTagged(Tags.HidingSpot) do
		local prompt = spot:FindFirstChild("HidePrompt")
		if prompt and prompt:IsA("ProximityPrompt") then
			local inside = spot == mine
			prompt.ActionText = if inside then "Salir" else "Esconderse"
			-- Escondido solo se puede usar el prompt del propio escondite
			prompt.Enabled = not hidden or inside
		end
	end
end

----------------------------------------------------------------------
-- Camara dentro del escondite: fija mirando por la rejilla del frente
----------------------------------------------------------------------
-- Antes se podia girar 360° dentro del casillero. Ahora la camara se coloca junto a la
-- puerta mirando hacia fuera (el frente del escondite = su LookVector) y el raton solo
-- permite asomarse un poco.

local HIDE_CAMERA = "HideCamera"
local PEEK_YAW, PEEK_PITCH = math.rad(25), math.rad(12)
local PEEK_SENSITIVITY = 0.004
local EYE_HEIGHT = 4.6 -- sobre el suelo del escondite
local CAR_EYE_HEIGHT = 2.9 -- en un coche: a la altura de la ventanilla

local peekYaw, peekPitch = 0, 0

-- El escondite en el que estas (el mas cercano: el servidor te coloca dentro).
local function findMySpot(): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return nil
	end
	local best, bestDist = nil, math.huge
	for _, spot in CollectionService:GetTagged(Tags.HidingSpot) do
		if spot:IsA("BasePart") then
			local d = (root.Position - spot.Position).Magnitude
			if d < bestDist then
				best, bestDist = spot, d
			end
		end
	end
	return best
end

local function startHideCamera()
	local spot = findMySpot()
	local camera = Workspace.CurrentCamera
	if not spot or not camera then
		return
	end
	peekYaw, peekPitch = 0, 0
	local spotName = spot:GetAttribute("DisplayName") or spot.Name
	local inCar = CAR_SPOTS[spotName] == true
	local chosen = if inCar then nil else (views[HIDE_VIEWS[spotName] or "Locker"] or slitsView)
	for _, v in views do
		v.Visible = v == chosen
	end
	carView.Visible = inCar
	local eyeHeight = if inCar then CAR_EYE_HEIGHT else EYE_HEIGHT
	camera.CameraType = Enum.CameraType.Scriptable
	RunService:BindToRenderStep(HIDE_CAMERA, Enum.RenderPriority.Camera.Value + 1, function()
		if not spot.Parent then
			return
		end
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		local delta = UserInputService:GetMouseDelta()
		peekYaw = math.clamp(peekYaw - delta.X * PEEK_SENSITIVITY, -PEEK_YAW, PEEK_YAW)
		peekPitch = math.clamp(peekPitch - delta.Y * PEEK_SENSITIVITY, -PEEK_PITCH, PEEK_PITCH)
		-- Respiracion: un vaiven muy leve
		local breathe = math.sin(os.clock() * 1.6) * 0.03
		local size = spot.Size
		local eye = spot.CFrame * CFrame.new(0, -size.Y / 2 + eyeHeight + breathe, -(size.Z / 2) + 0.35)
		camera.CFrame = CFrame.new(eye.Position) * spot.CFrame.Rotation * CFrame.Angles(0, peekYaw, 0) * CFrame.Angles(peekPitch, 0, 0)
	end)
end

local function stopHideCamera()
	RunService:UnbindFromRenderStep(HIDE_CAMERA)
	local camera = Workspace.CurrentCamera
	if camera and camera.CameraType == Enum.CameraType.Scriptable then
		camera.CameraType = Enum.CameraType.Custom
	end
end

local function onHiddenChanged()
	local hidden = player:GetAttribute("Hidden") == true
	stopHideCamera()
	if hidden then
		-- Esperar a que llegue la posicion dentro del escondite
		task.delay(0.1, function()
			if player:GetAttribute("Hidden") == true then
				startHideCamera()
			end
		end)
	end
	if hidden then
		ContextActionService:BindActionAtPriority("ExitHiding", function(_, state)
			if state == Enum.UserInputState.Begin then
				Remotes.event("RequestUnhide"):FireServer()
			end
			return Enum.ContextActionResult.Sink -- no saltar
		end, true, Enum.ContextActionPriority.High.Value, Enum.KeyCode.Space, Enum.KeyCode.ButtonA)
		ContextActionService:SetTitle("ExitHiding", "🚪")
	else
		ContextActionService:UnbindAction("ExitHiding")
	end
	-- Esperar un instante a que llegue la nueva posicion del personaje
	task.delay(0.1, refreshHidePrompts)
end

----------------------------------------------------------------------
-- Controles
----------------------------------------------------------------------

local function bindClassAbility()
	if player:GetAttribute("Perk_Shove") then
		ContextActionService:BindAction("ClassAbility", function(_, state)
			if state == Enum.UserInputState.Begin then
				Remotes.event("UseClassAbility"):FireServer()
			end
			return Enum.ContextActionResult.Pass
		end, true, Enum.KeyCode.Q, Enum.KeyCode.ButtonY)
		ContextActionService:SetTitle("ClassAbility", "🛡")
		-- (posicion: la coloca Roblox)
	else
		ContextActionService:UnbindAction("ClassAbility")
	end
end

-- Arma equipada: se usa desde la mochila nativa (herramienta). [R] queda como
-- atajo de teclado (sin boton tactil: en tactil se toca la herramienta).
local function bindWeapon()
	local weaponId = player:GetAttribute("Weapon")
	local item = if type(weaponId) == "string" then Config.ShopItems[weaponId] else nil
	if item then
		ContextActionService:BindAction("Weapon", function(_, state)
			if state == Enum.UserInputState.Begin then
				-- (con la direccion de la camara: la pistola dispara hacia la mirilla)
				local camera = Workspace.CurrentCamera
				Remotes.event("UseWeapon"):FireServer(nil, if camera then camera.CFrame.LookVector else nil)
			end
			return Enum.ContextActionResult.Pass
		end, false, Enum.KeyCode.R)
	else
		ContextActionService:UnbindAction("Weapon")
	end
end

function Defense.Start()
	build()

	bindWeapon()
	player:GetAttributeChangedSignal("Weapon"):Connect(bindWeapon)

	ContextActionService:BindAction("Flash", function(_, state)
		if state == Enum.UserInputState.Begin then
			Remotes.event("UseFlash"):FireServer()
		end
		return Enum.ContextActionResult.Pass
	end, true, Enum.KeyCode.G, Enum.KeyCode.ButtonX)
	ContextActionService:SetTitle("Flash", "💥")
	-- (posicion: la coloca Roblox)

	bindClassAbility()
	player:GetAttributeChangedSignal("Perk_Shove"):Connect(bindClassAbility)

	-- El servidor adelanta FlashReadyAt cuando el destello se usa de verdad
	player:GetAttributeChangedSignal("FlashReadyAt"):Connect(function()
		local readyAt = player:GetAttribute("FlashReadyAt") or 0
		if readyAt > lastFlashReadyAt then
			playFlash()
		end
		lastFlashReadyAt = readyAt
	end)
	lastFlashReadyAt = player:GetAttribute("FlashReadyAt") or 0

	player:GetAttributeChangedSignal("Hidden"):Connect(onHiddenChanged)
	CollectionService:GetInstanceAddedSignal(Tags.HidingSpot):Connect(function()
		task.defer(refreshHidePrompts)
	end)
	onHiddenChanged()

	local accumulator = 0
	RunService.RenderStepped:Connect(function(dt)
		accumulator += dt
		if accumulator >= 0.1 then
			accumulator = 0
			update()
		end
	end)
end

return Defense
