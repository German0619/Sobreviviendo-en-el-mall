-- Audio (cliente): musica, ambiente y sonidos personales (Config.Sounds).
--
--   Musica: una pista por fase, con un fundido al cambiar (lobby; en el mall: espera y
--     preparacion, noche, noche avanzada desde LateNightFrom). En la noche de
--     jefe se calla: la pone BossAlert. Fin de partida: un golpe de sonido.
--   Ambiente (mall): zumbido de fluorescentes (preparacion y noche), eco de nave grande
--     (noche) y, de noche, sonidos sueltos al azar a tu alrededor (goteos, metal, crujidos).
--   Sonidos personales: los que pide el servidor (remote PlaySfx: compras, tareas...),
--     las campanas al empezar la noche, las 6 AM y el de morir.
-- (Los sonidos 3D de armas, defensas y enemigos los pone el servidor: SfxService, EnemySounds.)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local GameState = require(Shared.GameState)
local Place = require(Shared.Place)
local Remotes = require(Shared.Remotes)

local player = Players.LocalPlayer
local S = Config.Sounds
local rng = Random.new()

local Audio = {}

local container: Folder
local musicTracks: { [string]: Sound } = {}
local currentKey: string? = nil
local current: Sound? = nil

local function makeSound(def, looped: boolean, name: string, parent: Instance?): Sound
	local s = Instance.new("Sound")
	s.Name = name
	s.SoundId = def.Id
	s.Volume = def.Volume
	s.PlaybackSpeed = def.Pitch or 1
	s.Looped = looped
	s.Parent = parent or container
	return s
end

local function fade(sound: Sound, volume: number, seconds: number, stopAfter: boolean?)
	local tween = TweenService:Create(sound, TweenInfo.new(seconds, Enum.EasingStyle.Sine), { Volume = volume })
	tween:Play()
	if stopAfter then
		tween.Completed:Once(function()
			if sound.Volume <= 0.001 then
				sound:Stop()
			end
		end)
	end
end

-- Sonido suelto en 2D (se borra al acabar).
local function playOnce(def)
	if not def or def.Volume <= 0 then
		return
	end
	local s = makeSound(def, false, "OneShot")
	s:Play()
	s.Ended:Once(function()
		s:Destroy()
	end)
	task.delay(15, function()
		if s.Parent then
			s:Destroy()
		end
	end)
end

----------------------------------------------------------------------
-- Musica
----------------------------------------------------------------------

local function setMusic(key: string?)
	if key == currentKey then
		return
	end
	local seconds = S.FadeSeconds or 2
	if current then
		fade(current, 0, seconds, true)
	end
	currentKey = key
	current = nil
	local def = key and S.Music[key]
	if not def or def.Volume <= 0 then
		return
	end
	local track = musicTracks[key :: string]
	if not track then
		track = makeSound(def, true, "Music_" .. key)
		musicTracks[key :: string] = track
	end
	track.Volume = 0
	track.TimePosition = 0
	track:Play()
	fade(track, def.Volume, seconds)
	current = track
end

local function bossActive(): boolean
	local f = GameState.Folder
	return type(f:GetAttribute("BossName")) == "string" and f:GetAttribute("BossDefeated") ~= true
end

local function wantedMusic(): string?
	if Place.IsLobby then
		return "Lobby"
	end
	local f = GameState.Folder
	local phase = f:GetAttribute("Phase")
	if phase == "Night" then
		if bossActive() then
			return nil -- (la musica del jefe: BossAlert)
		end
		local night = f:GetAttribute("Night") or 1
		return if night >= (S.LateNightFrom or math.huge) then "LateNight" else "Night"
	elseif phase == "Waiting" or phase == "Preparation" then
		return "Preparation"
	end
	return nil -- GameOver: solo el golpe de sonido
end

local function refreshMusic()
	setMusic(wantedMusic())
end

----------------------------------------------------------------------
-- Ambiente (mall)
----------------------------------------------------------------------

local hum: Sound? = nil
local interior: Sound? = nil

local function setLoop(sound: Sound?, def, on: boolean)
	if not sound or not def then
		return
	end
	if on and not sound.IsPlaying then
		sound.Volume = 0
		sound:Play()
		fade(sound, def.Volume, 3)
	elseif not on and sound.IsPlaying then
		fade(sound, 0, 3, true)
	end
end

local function refreshAmbience()
	local phase = GameState.Folder:GetAttribute("Phase")
	local A = S.Ambience
	setLoop(hum, A.Hum, phase == "Preparation" or phase == "Night" or phase == "Waiting")
	setLoop(interior, A.Interior, phase == "Night")
end

-- Un sonido suelto en 3D en un punto al azar a tu alrededor (solo lo oyes tu).
local function randomAmbientSound()
	local A = S.Ambience
	local list = A.Random
	if not list or #list == 0 then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	local def = list[rng:NextInteger(1, #list)]
	if def.Volume <= 0 then
		return
	end
	local angle = rng:NextNumber(0, math.pi * 2)
	local dist = rng:NextNumber(A.RandomDistance[1], A.RandomDistance[2])
	local pos = root.Position + Vector3.new(math.cos(angle) * dist, rng:NextNumber(-2, 6), math.sin(angle) * dist)
	local holder = Instance.new("Part")
	holder.Name = "AmbientSound"
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.Transparency = 1
	holder.Size = Vector3.new(0.2, 0.2, 0.2)
	holder.Position = pos
	holder.Parent = Workspace.CurrentCamera
	local s = makeSound(def, false, "Ambient", holder)
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = 10
	s.RollOffMaxDistance = 80
	s:Play()
	s.Ended:Once(function()
		holder:Destroy()
	end)
	task.delay(60, function()
		if holder.Parent then
			holder:Destroy()
		end
	end)
end

local function startAmbience()
	local A = S.Ambience
	hum = if A.Hum and A.Hum.Volume > 0 then makeSound(A.Hum, true, "AmbienceHum") else nil
	interior = if A.Interior and A.Interior.Volume > 0 then makeSound(A.Interior, true, "AmbienceInterior") else nil
	if hum then
		hum.Volume = 0
	end
	if interior then
		interior.Volume = 0
	end
	task.spawn(function()
		while true do
			task.wait(rng:NextNumber(A.RandomEvery[1], A.RandomEvery[2]))
			if GameState.Folder:GetAttribute("Phase") == "Night" then
				pcall(randomAmbientSound)
			end
		end
	end)
end

----------------------------------------------------------------------
-- Arranque
----------------------------------------------------------------------

function Audio.Start()
	container = Instance.new("Folder")
	container.Name = "GameAudio"
	container.Parent = SoundService

	-- Sonidos que pide el servidor solo para ti
	Remotes.event("PlaySfx").OnClientEvent:Connect(function(name: string)
		playOnce(S.Sfx[name])
	end)

	if Place.IsLobby then
		refreshMusic()
		return
	end

	startAmbience()
	local f = GameState.Folder
	local lastPhase = f:GetAttribute("Phase")
	f:GetAttributeChangedSignal("Phase"):Connect(function()
		local phase = f:GetAttribute("Phase")
		if phase == "Night" and lastPhase ~= "Night" then
			playOnce(S.Sfx.NightStart)
		elseif lastPhase == "Night" and phase == "Preparation" then -- noche ganada
			playOnce(S.Sfx.NightEnd)
		elseif phase == "GameOver" and lastPhase ~= "GameOver" then
			playOnce(S.Music.GameOver)
		end
		lastPhase = phase
		refreshMusic()
		refreshAmbience()
	end)
	for _, attr in { "Night", "BossName", "BossDefeated" } do
		f:GetAttributeChangedSignal(attr):Connect(refreshMusic)
	end
	refreshMusic()
	refreshAmbience()

	-- Al morir
	local function onCharacter(character: Model)
		local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
		if humanoid then
			humanoid.Died:Once(function()
				playOnce(S.Sfx.Death)
			end)
		end
	end
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
	player.CharacterAdded:Connect(onCharacter)
end

return Audio
