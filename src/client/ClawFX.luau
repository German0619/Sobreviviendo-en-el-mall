-- ClawFX (mall): lo que ve y oye el jugador al que se agarra La Garra (server/ClawService).
--   * Dos manos monstruosas (Config.Claw.HandImage), una desde abajo y otra desde arriba
--     con los dedos encajados, se cierran DESPACIO sobre la camara durante el minuto.
--     Solo "respiran" (crecen y giran un poco, lento); nada de sacudidas.
--   * La oscuridad de los bordes (Config.Claw.VignetteImage) se va cerrando a la vez.
--   * Respiracion gruñida y latido que se acelera. Arriba: "LA GARRA · 0/2 tareas · 0:42".
--   * Al matarte: las manos se cierran de golpe y tres zarpazos rojos cruzan la pantalla.
-- Lee los atributos ClawUntil / ClawDone / ClawNeed / ClawKilledAt del jugador.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local UIKit = require(script.Parent.UIKit)

local player = Players.LocalPlayer

local ClawFX = {}

local HAND_ASPECT = 1024 / 800 -- ancho / alto de la imagen de la mano
local HAND_HEIGHT = 1.05 -- alto de cada mano, en fraccion del alto de la pantalla
local REACH_START = 0.16 -- cuanto asoma cada mano al agarrarte (solo las garras)
local REACH_END = 0.66 -- al acabarse el tiempo (los dedos se cruzan en el centro)
local REACH_KILL = 0.9
local HAND_OFFSET_X = 0.07 -- las dos manos desplazadas para que los dedos encajen

local fxGui: ScreenGui -- efectos a pantalla completa (sin UIScale)
local hudGui: ScreenGui -- texto (con UIKit.adapt)
local bottomHand: ImageLabel
local topHand: ImageLabel
local vignette: ImageLabel
local label: TextLabel
local breath: Sound?
local heartbeat: Sound?
local renderConn: RBXScriptConnection? = nil
local reach = 0 -- lo que asoman ahora las manos (se suaviza hacia el objetivo)
local killedAt = 0

local function makeSound(def, name: string): Sound?
	if not def or def.Volume <= 0 then
		return nil
	end
	local s = Instance.new("Sound")
	s.Name = name
	s.SoundId = def.Id
	s.Volume = 0
	s.PlaybackSpeed = def.Pitch or 1
	s.Looped = true
	s.Parent = fxGui
	return s
end

local function makeHand(name: string, fromTop: boolean): ImageLabel
	local hand = Instance.new("ImageLabel")
	hand.Name = name
	hand.Image = Config.Claw.HandImage
	hand.BackgroundTransparency = 1
	hand.ScaleType = Enum.ScaleType.Stretch
	-- Proporcional al alto de la pantalla (RelativeYY): igual en telefono y en PC
	hand.SizeConstraint = Enum.SizeConstraint.RelativeYY
	hand.Size = UDim2.fromScale(HAND_HEIGHT * HAND_ASPECT, HAND_HEIGHT)
	hand.AnchorPoint = Vector2.new(0.5, if fromTop then 1 else 0)
	hand.Rotation = if fromTop then 180 else 0
	hand.ImageColor3 = Color3.fromRGB(200, 190, 190)
	hand.Visible = false
	hand.ZIndex = 2
	hand.Parent = fxGui
	return hand
end

local function build()
	fxGui = Instance.new("ScreenGui")
	fxGui.Name = "ClawFX"
	fxGui.ResetOnSpawn = false
	fxGui.IgnoreGuiInset = true
	fxGui.DisplayOrder = 15
	fxGui.Parent = player:WaitForChild("PlayerGui")

	vignette = Instance.new("ImageLabel")
	vignette.Name = "Darkness"
	vignette.Image = Config.Claw.VignetteImage
	vignette.ImageColor3 = Color3.fromRGB(18, 0, 0)
	vignette.BackgroundTransparency = 1
	vignette.AnchorPoint = Vector2.new(0.5, 0.5)
	vignette.Position = UDim2.fromScale(0.5, 0.5)
	vignette.Size = UDim2.fromScale(2.4, 2.4)
	vignette.Visible = false
	vignette.ZIndex = 1
	vignette.Parent = fxGui

	bottomHand = makeHand("ClawBottom", false)
	topHand = makeHand("ClawTop", true)

	hudGui = Instance.new("ScreenGui")
	hudGui.Name = "ClawHUD"
	hudGui.ResetOnSpawn = false
	hudGui.DisplayOrder = 16
	hudGui.Parent = player:WaitForChild("PlayerGui")
	UIKit.adapt(hudGui)
	label = UIKit.text({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.2),
		Size = UDim2.fromOffset(520, 40),
		Font = Enum.Font.GothamBlack,
		TextSize = 26,
		TextColor3 = Color3.fromRGB(255, 70, 70),
		TextStrokeTransparency = 0.2,
		Text = "",
		Visible = false,
		Parent = hudGui,
	})

	breath = makeSound(Config.Sounds.Claw.Breath, "ClawBreath")
	heartbeat = makeSound(Config.Sounds.Claw.Heartbeat, "ClawHeartbeat")
end

local function setSounds(on: boolean)
	for _, entry in { { breath, Config.Sounds.Claw.Breath }, { heartbeat, Config.Sounds.Claw.Heartbeat } } do
		local sound, def = entry[1], entry[2]
		if sound then
			if on then
				sound.Volume = def.Volume
				if not sound.IsPlaying then
					sound:Play()
				end
			else
				sound:Stop()
			end
		end
	end
end

-- Coloca las dos manos segun lo que asoman (0-1 del alto de la pantalla) y su respiracion.
local function placeHands(amount: number, t: number)
	local breathe = math.sin(t * 1.3) -- lento: una respiracion cada ~5 s
	local scale = 1 + 0.025 * breathe
	local size = UDim2.fromScale(HAND_HEIGHT * HAND_ASPECT * scale, HAND_HEIGHT * scale)
	bottomHand.Size = size
	topHand.Size = size
	bottomHand.Position = UDim2.fromScale(0.5 - HAND_OFFSET_X, 1 - amount)
	topHand.Position = UDim2.fromScale(0.5 + HAND_OFFSET_X, amount)
	bottomHand.Rotation = 1.5 * breathe
	topHand.Rotation = 180 - 1.5 * breathe
end

local function stopEffects()
	if renderConn then
		renderConn:Disconnect()
		renderConn = nil
	end
	bottomHand.Visible = false
	topHand.Visible = false
	vignette.Visible = false
	label.Visible = false
	setSounds(false)
end

local function startEffects()
	if renderConn then
		return
	end
	local total = Config.Claw.Seconds
	reach = 0
	bottomHand.Visible = true
	topHand.Visible = true
	vignette.Visible = true
	label.Visible = true
	setSounds(true)
	renderConn = RunService.RenderStepped:Connect(function(dt)
		local untilAt = player:GetAttribute("ClawUntil")
		if type(untilAt) ~= "number" then
			return
		end
		local remaining = math.max(0, untilAt - Workspace:GetServerTimeNow())
		local danger = 1 - math.clamp(remaining / total, 0, 1) -- 0 al agarrar, 1 al final
		local t = os.clock()

		-- Se cierran poco a poco (suavizado: nunca da saltos)
		local wanted = REACH_START + (REACH_END - REACH_START) * danger ^ 1.15
		reach += (wanted - reach) * math.min(1, dt * 1.2)
		placeHands(reach, t)

		-- La oscuridad se cierra con ellas y late con el corazon en los ultimos segundos
		local pulse = if danger > 0.75 then 0.04 * math.sin(t * 7) else 0
		local vsize = 2.4 - 1.35 * danger + pulse
		vignette.Size = UDim2.fromScale(vsize, vsize)
		vignette.ImageTransparency = 0.25 - 0.25 * danger
		if heartbeat then
			heartbeat.PlaybackSpeed = 1 + 0.5 * danger
		end
		if breath then
			breath.Volume = Config.Sounds.Claw.Breath.Volume * (0.6 + 0.6 * danger)
		end

		local need = player:GetAttribute("ClawNeed") or Config.Claw.Required
		local done = player:GetAttribute("ClawDone") or 0
		local secs = math.ceil(remaining)
		label.Text = string.format("LA GARRA  ·  %d/%d tareas  ·  %d:%02d", done, need, secs // 60, secs % 60)
	end)
end

-- Las manos se cierran de golpe, destello rojo y tres zarpazos en diagonal
local function killEffect()
	if renderConn then
		renderConn:Disconnect()
		renderConn = nil
	end
	label.Visible = false
	setSounds(false)
	bottomHand.Visible = true
	topHand.Visible = true
	local info = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	TweenService:Create(bottomHand, info, { Position = UDim2.fromScale(0.5 - HAND_OFFSET_X, 1 - REACH_KILL) }):Play()
	TweenService:Create(topHand, info, { Position = UDim2.fromScale(0.5 + HAND_OFFSET_X, REACH_KILL) }):Play()

	task.delay(0.2, function()
		local flash = Instance.new("Frame")
		flash.Size = UDim2.fromScale(1, 1)
		flash.BackgroundColor3 = Color3.fromRGB(110, 0, 0)
		flash.BackgroundTransparency = 0.25
		flash.BorderSizePixel = 0
		flash.ZIndex = 5
		flash.Parent = fxGui
		TweenService:Create(flash, TweenInfo.new(1.8), { BackgroundTransparency = 1 }):Play()
		local marks = { flash }
		for i = -1, 1 do
			local mark = Instance.new("Frame")
			mark.AnchorPoint = Vector2.new(0.5, 0.5)
			mark.Position = UDim2.fromScale(0.5 + i * 0.12, 0.5)
			mark.Size = UDim2.fromScale(0, 0.03)
			mark.Rotation = 35
			mark.BackgroundColor3 = Color3.fromRGB(150, 0, 0)
			mark.BorderSizePixel = 0
			mark.ZIndex = 6
			mark.Parent = fxGui
			UIKit.make("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = mark })
			table.insert(marks, mark)
			task.delay((i + 1) * 0.07, function()
				TweenService:Create(mark, TweenInfo.new(0.14, Enum.EasingStyle.Quad), { Size = UDim2.fromScale(1.3, 0.03) }):Play()
				task.wait(1.2)
				TweenService:Create(mark, TweenInfo.new(1.2), { BackgroundTransparency = 1 }):Play()
			end)
		end
		-- Las manos y la oscuridad se desvanecen
		local fade = TweenInfo.new(1.5)
		TweenService:Create(bottomHand, fade, { ImageTransparency = 1 }):Play()
		TweenService:Create(topHand, fade, { ImageTransparency = 1 }):Play()
		TweenService:Create(vignette, fade, { ImageTransparency = 1 }):Play()
		task.delay(3, function()
			for _, m in marks do
				m:Destroy()
			end
			if not renderConn then
				stopEffects()
			end
			bottomHand.ImageTransparency = 0
			topHand.ImageTransparency = 0
		end)
	end)
end

function ClawFX.Start()
	build()
	local function refresh()
		if type(player:GetAttribute("ClawUntil")) == "number" then
			startEffects()
		elseif os.clock() - killedAt > 0.5 then
			-- (si acaba de matarte, el efecto de muerte se encarga de quitarlo)
			task.delay(0.15, function()
				if os.clock() - killedAt > 0.5 and type(player:GetAttribute("ClawUntil")) ~= "number" then
					stopEffects()
				end
			end)
		end
	end
	player:GetAttributeChangedSignal("ClawUntil"):Connect(refresh)
	player:GetAttributeChangedSignal("ClawKilledAt"):Connect(function()
		killedAt = os.clock()
		killEffect()
	end)
	refresh()
end

return ClawFX
