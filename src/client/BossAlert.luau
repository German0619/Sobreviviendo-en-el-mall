-- BossAlert (mall): la noche de jefe se siente distinta.
--   * Al empezar: pantalla de alerta (bordes rojos, nombre del jefe y su objetivo) unos
--     segundos, con un golpe de sonido.
--   * Mientras dura: musica propia (Config.Bosses.MusicSoundId) o, si no hay, un latido
--     grave hecho con los sonidos de Roblox.
--   * Al vencerlo: "JEFE VENCIDO" y la musica se apaga.
-- La linea de progreso bajo el reloj la pinta el HUD (atributos Boss* de GameState).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local GameState = require(Shared.GameState)
local UIKit = require(script.Parent.UIKit)

local player = Players.LocalPlayer

local BossAlert = {}

local HEARTBEAT = "rbxasset://sounds/bass.mp3"
local STINGER = "rbxasset://sounds/HalloweenGhost.wav"
local RED = Color3.fromRGB(220, 30, 30)

local gui, frame, title, subtitle, vignette
local music: Sound? = nil
local heartbeatToken = 0

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "BossAlert"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 20
	gui.Parent = player:WaitForChild("PlayerGui")
	UIKit.adapt(gui)

	-- Bordes rojos (un marco a pantalla completa con borde grueso)
	vignette = Instance.new("Frame")
	vignette.Size = UDim2.fromScale(1, 1)
	vignette.BackgroundTransparency = 1
	vignette.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Color = RED
	stroke.Thickness = 28
	stroke.Transparency = 1
	stroke.Parent = vignette

	frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.35)
	frame.Size = UDim2.fromOffset(640, 130)
	frame.BackgroundTransparency = 1
	frame.Visible = false
	frame.Parent = gui
	title = UIKit.text({
		Size = UDim2.new(1, 0, 0, 70),
		TextSize = 54,
		Font = Enum.Font.GothamBlack,
		TextColor3 = RED,
		TextStrokeTransparency = 0.2,
		Text = "",
		Parent = frame,
	})
	subtitle = UIKit.text({
		Position = UDim2.fromOffset(0, 74),
		Size = UDim2.new(1, 0, 0, 50),
		TextSize = 20,
		TextWrapped = true,
		TextStrokeTransparency = 0.4,
		Text = "",
		Parent = frame,
	})
end

local function flashBorders(seconds: number)
	local stroke = vignette:FindFirstChildOfClass("UIStroke")
	if not stroke then
		return
	end
	stroke.Transparency = 0.1
	TweenService:Create(stroke, TweenInfo.new(seconds, Enum.EasingStyle.Sine), { Transparency = 1 }):Play()
end

local function show(text: string, sub: string, color: Color3, seconds: number)
	title.Text = text
	title.TextColor3 = color
	subtitle.Text = sub
	frame.Visible = true
	title.TextTransparency = 0
	subtitle.TextTransparency = 0
	task.delay(seconds, function()
		local info = TweenInfo.new(0.8)
		TweenService:Create(title, info, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		TweenService:Create(subtitle, info, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		task.wait(0.8)
		frame.Visible = false
		title.TextStrokeTransparency = 0.2
		subtitle.TextStrokeTransparency = 0.4
	end)
end

local function playOnce(soundId: string, speed: number, volume: number)
	local s = Instance.new("Sound")
	s.SoundId = soundId
	s.PlaybackSpeed = speed
	s.Volume = volume
	s.Parent = gui
	s:Play()
	s.Ended:Once(function()
		s:Destroy()
	end)
end

local function startMusic()
	heartbeatToken += 1
	local token = heartbeatToken
	if Config.Bosses.MusicSoundId ~= "" then
		music = Instance.new("Sound")
		music.SoundId = Config.Bosses.MusicSoundId
		music.Looped = true
		music.Volume = 0.5
		music.Parent = gui
		music:Play()
		return
	end
	-- Latido grave (doble golpe) mientras el jefe siga en pie
	task.spawn(function()
		while heartbeatToken == token do
			playOnce(HEARTBEAT, 0.55, 0.45)
			task.wait(0.28)
			if heartbeatToken ~= token then
				break
			end
			playOnce(HEARTBEAT, 0.5, 0.35)
			task.wait(1.1)
		end
	end)
end

local function stopMusic()
	heartbeatToken += 1
	if music then
		music:Destroy()
		music = nil
	end
end

function BossAlert.Start()
	build()
	local folder = GameState.Folder
	folder:GetAttributeChangedSignal("BossName"):Connect(function()
		local name = folder:GetAttribute("BossName")
		if type(name) == "string" then
			show("⚠ " .. string.upper(name), folder:GetAttribute("BossObjective") or "", RED, 5)
			flashBorders(3)
			playOnce(STINGER, 0.6, 0.9)
			startMusic()
		else
			stopMusic()
		end
	end)
	folder:GetAttributeChangedSignal("BossDefeated"):Connect(function()
		if folder:GetAttribute("BossDefeated") == true then
			stopMusic()
			show("JEFE VENCIDO", "Completen las tareas para llegar a las 6 AM.", Color3.fromRGB(100, 220, 130), 4)
		end
	end)
end

return BossAlert
