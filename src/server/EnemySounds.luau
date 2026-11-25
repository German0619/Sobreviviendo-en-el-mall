-- EnemySounds: los sonidos de cada enemigo (Config.Sounds.Enemies), en 3D desde su raiz.
--   Loop   en bucle; con Moving = true solo mientras anda (ruedas, piedra arrastrandose...)
--   Voice  uno al azar cada VoiceEvery segundos (gruñidos, el walkie, la cadena del farol)
--   Attack al golpear (Common.playAttack pone el atributo AttackAt del modelo)
-- Lo crea y lo avanza EnemyService (como EnemyAnimator). Al quitar el enemigo se borran
-- sus sonidos: los modelos del mapa (Estatua, maniquies) vuelven a su sitio sin ellos.
-- (Algunos enemigos traen ademas sus propios pasos: Eco, Luni, la Estatua, el Ducto.)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local EnemySounds = {}
EnemySounds.__index = EnemySounds

local rng = Random.new()

local function makeSound(parent: Instance, def, looped: boolean, name: string): Sound
	local s = Instance.new("Sound")
	s.Name = name
	s.SoundId = def.Id
	s.Volume = def.Volume
	s.PlaybackSpeed = def.Pitch or 1
	s.Looped = looped
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = 10
	s.RollOffMaxDistance = 80
	s.Parent = parent
	return s
end

local function nextVoiceAt(def): number
	local every = def.VoiceEvery or { 8, 16 }
	return os.clock() + rng:NextNumber(every[1], every[2])
end

function EnemySounds.attach(model: Instance, enemyType: string)
	if not model:IsA("Model") or not model.PrimaryPart then
		return nil
	end
	local all = Config.Sounds.Enemies
	local def = all[enemyType] or (if enemyType == "Converted" then all.Mannequin else nil) or {}
	local root = model.PrimaryPart :: BasePart
	local self = setmetatable({
		Model = model,
		Root = root,
		Def = def,
		Created = {} :: { Sound },
		LastPos = root.Position,
		MovingUntil = 0,
	}, EnemySounds)

	if def.Loop and def.Loop.Volume > 0 then
		self.Loop = makeSound(root, def.Loop, true, "EnemyLoop")
		table.insert(self.Created, self.Loop)
		if not def.Moving then
			self.Loop:Play()
		end
	end
	local attack = def.Attack or all.Default.Attack
	if attack and attack.Volume > 0 then
		local attackSound = makeSound(root, attack, false, "EnemyAttack")
		table.insert(self.Created, attackSound)
		self.Conn = model:GetAttributeChangedSignal("AttackAt"):Connect(function()
			attackSound.TimePosition = 0
			attackSound:Play()
		end)
	end
	if def.Voice then
		self.Voices = {}
		for _, d in def.Voice do
			if d.Volume > 0 then
				local voice = makeSound(root, d, false, "EnemyVoice")
				table.insert(self.Voices, voice)
				table.insert(self.Created, voice)
			end
		end
		self.NextVoice = nextVoiceAt(def)
	end
	return self
end

function EnemySounds:Step(dt: number)
	local root = self.Root
	if not root.Parent then
		return
	end
	local now = os.clock()
	local pos = root.Position
	local moved = Vector3.new(pos.X - self.LastPos.X, 0, pos.Z - self.LastPos.Z).Magnitude
	self.LastPos = pos
	-- Anda si se desplaza (no cuenta un teletransporte); sigue "andando" un instante al parar
	if moved < 6 and moved / math.max(dt, 1e-3) > 0.6 then
		self.MovingUntil = now + 0.25
	end
	local moving = now < self.MovingUntil

	local loop = self.Loop
	if loop and self.Def.Moving then
		if moving and not loop.IsPlaying then
			loop:Resume()
		elseif not moving and loop.IsPlaying then
			loop:Pause()
		end
	end

	local voices = self.Voices
	if voices and #voices > 0 and now >= self.NextVoice then
		self.NextVoice = nextVoiceAt(self.Def)
		-- (no si esta escondido: fuera del mapa o bajo el suelo, como el Eco desaparecido)
		if self.Model:IsDescendantOf(Workspace) and pos.Y > -100 then
			voices[rng:NextInteger(1, #voices)]:Play()
		end
	end
end

function EnemySounds:Destroy()
	if self.Conn then
		self.Conn:Disconnect()
	end
	for _, sound in self.Created do
		sound:Destroy()
	end
end

return EnemySounds
