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

local player = Players.LocalPlayer
local C = UIKit.COLORS

local Defense = {}

local SLITS = 14 -- rendijas de la puerta del escondite

local gui, abilitiesLabel, overlay, overlayLabel, flashFrame
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

	-- Encima de la linea de objetos y soda del HUD
	abilitiesLabel = UIKit.text({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -72),
		Size = UDim2.fromOffset(600, 22),
		TextSize = 15,
		RichText = true,
		TextStrokeTransparency = 0.6,
		Text = "",
		Parent = gui,
	})

	-- Vista desde dentro del escondite: franjas oscuras con rendijas
	overlay = UIKit.make("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 3,
		Parent = gui,
	})
	for i = 0, SLITS - 1 do
		UIKit.make("Frame", {
			Position = UDim2.fromScale(0, i / SLITS),
			Size = UDim2.fromScale(1, 0.78 / SLITS),
			BackgroundColor3 = Color3.fromRGB(4, 4, 6),
			BackgroundTransparency = 0.03,
			BorderSizePixel = 0,
			ZIndex = 3,
			Parent = overlay,
		})
	end
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

local function cooldownText(key: string, name: string, readyAt: number, now: number, blockedReason: string?): string
	local remaining = readyAt - now
	if remaining > 0 then
		return string.format('<font color="#9696A0">[%s] %s  %ds</font>', key, name, math.ceil(remaining))
	elseif blockedReason then
		return string.format('<font color="#E65050">[%s] %s  (%s)</font>', key, name, blockedReason)
	end
	return string.format('<font color="#5AD278">[%s] %s  listo</font>', key, name)
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
			cooldownText("G", "Destello", player:GetAttribute("FlashReadyAt") or 0, now, if battery < cost then "sin batería" else nil),
		}
		if player:GetAttribute("Perk_Shove") then
			table.insert(parts, cooldownText("Q", "Porrazo", player:GetAttribute("AbilityReadyAt") or 0, now, nil))
		end
		abilitiesLabel.Text = table.concat(parts, "     ")
	end

	overlay.Visible = hidden and alive
	if overlay.Visible then
		local remaining = math.max(0, math.ceil((player:GetAttribute("HiddenUntil") or now) - now))
		overlayLabel.Text = string.format("Escondido  ·  [Espacio] o [E] para salir  ·  aire: %ds", remaining)
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
		local eye = spot.CFrame * CFrame.new(0, -size.Y / 2 + EYE_HEIGHT + breathe, -(size.Z / 2) + 0.35)
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
		ContextActionService:SetTitle("ExitHiding", "Salir")
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
		ContextActionService:SetTitle("ClassAbility", "Porrazo")
		ContextActionService:SetPosition("ClassAbility", UDim2.new(1, -100, 1, -230))
	else
		ContextActionService:UnbindAction("ClassAbility")
	end
end

function Defense.Start()
	build()

	ContextActionService:BindAction("Flash", function(_, state)
		if state == Enum.UserInputState.Begin then
			Remotes.event("UseFlash"):FireServer()
		end
		return Enum.ContextActionResult.Pass
	end, true, Enum.KeyCode.G, Enum.KeyCode.ButtonX)
	ContextActionService:SetTitle("Flash", "Destello")
	ContextActionService:SetPosition("Flash", UDim2.new(1, -100, 1, -160))

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
