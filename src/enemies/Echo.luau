-- Eco: un fantasma que se hace pasar por un companero.
--
-- Tiene el MISMO aspecto que otro jugador de la partida (su avatar: ropa, accesorios y
-- cara) y su nombre encima, una "linterna" y suena a pasos. Nunca copia a su presa;
-- jugando solo, te copia a TI. Te oye a traves de las paredes (Config SenseRange), se
-- acerca despacio y, si nadie lo alumbra, se lanza contra ti al estar cerca. Tras
-- golpear, se esfuma (y vuelve con el aspecto de otro).
--
-- Contramedidas: alumbrarlo con la linterna (o tenerlo dentro de una bengala) lo revela
-- (silueta negra con ojos blancos) y lo hace desaparecer; el destello y el porrazo, al
-- instante; los petardos lo distraen; esconderse rompe la persecucion. El Medium lo ve a
-- traves de las paredes (es un fantasma).
--
-- El cuerpo: Players:CreateHumanoidModelFromDescription con la descripcion del avatar
-- del jugador copiado (se construye una vez por jugador y se reutiliza), soldado a una
-- raiz invisible y animado con las animaciones de Roblox (quieto, andar, correr).
--
-- Estados: Stalk (acecha) <-> Vanished (desaparecido unos segundos)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ServerScriptService = game:GetService("ServerScriptService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)

local Server = ServerScriptService:WaitForChild("Server")
local FlashlightService = require(Server:WaitForChild("FlashlightService"))
local DefenseService = require(Server:WaitForChild("DefenseService"))

local Common = require(script.Parent.Common)

local HEIGHT = 5.5 -- raiz invisible: los pies del avatar van a su fondo
local HIDDEN_CFRAME = CFrame.new(0, -500, 0) -- donde espera mientras esta desaparecido
local FOOTSTEPS = "rbxasset://sounds/action_footsteps_plastic.mp3" -- sonido incluido en Roblox
local REVEALED_COLOR = Color3.fromRGB(8, 8, 10)
local EYE_COLOR = Color3.fromRGB(255, 255, 255)

-- Animaciones por defecto de Roblox (las mismas que usan los jugadores)
local ANIMATIONS = {
	[Enum.HumanoidRigType.R15] = {
		Idle = "rbxassetid://507766388",
		Walk = "rbxassetid://507777826",
		Run = "rbxassetid://507767714",
	},
	[Enum.HumanoidRigType.R6] = {
		Idle = "rbxassetid://180435571",
		Walk = "rbxassetid://180426354",
		Run = "rbxassetid://180426354",
	},
}

local Echo = {}
Echo.__index = Echo

----------------------------------------------------------------------
-- Avatares copiados (compartidos por todos los Ecos de la partida)
----------------------------------------------------------------------

local avatarTemplates: { [number]: Model } = {} -- [UserId] = cuerpo ya construido
local building: { [number]: boolean } = {}
local waiting: { [number]: { (Model?) -> () } } = {}

Players.PlayerRemoving:Connect(function(player)
	local template = avatarTemplates[player.UserId]
	avatarTemplates[player.UserId] = nil
	if template then
		template:Destroy()
	end
end)

-- Aspecto actual del jugador (y si es R6 o R15).
local function describe(player: Player): (HumanoidDescription?, Enum.HumanoidRigType)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local rigType = if humanoid then humanoid.RigType else Enum.HumanoidRigType.R15
	if humanoid then
		local ok, desc = pcall(function()
			return humanoid:GetAppliedDescription()
		end)
		if ok and desc then
			return desc, rigType
		end
	end
	if player.UserId > 0 then
		local ok, desc = pcall(function()
			return Players:GetHumanoidDescriptionFromUserId(player.UserId)
		end)
		if ok and desc then
			return desc, rigType
		end
	end
	return nil, rigType
end

-- Construye (una sola vez por jugador) un cuerpo identico a su avatar y llama a
-- done(plantilla) al terminar (nil si no se pudo). Tarda un momento: carga el avatar.
local function withAvatar(player: Player, done: (Model?) -> ())
	local id = player.UserId
	local cached = avatarTemplates[id]
	if cached then
		done(cached)
		return
	end
	waiting[id] = waiting[id] or {}
	table.insert(waiting[id], done)
	if building[id] then
		return
	end
	building[id] = true
	task.spawn(function()
		local desc, rigType = describe(player)
		local ok, model = pcall(function()
			return Players:CreateHumanoidModelFromDescription(desc or Instance.new("HumanoidDescription"), rigType)
		end)
		local template: Model? = nil
		if ok and model then
			-- (sin scripts: lo anima el servidor)
			for _, d in model:GetDescendants() do
				if d:IsA("LuaSourceContainer") then
					d:Destroy()
				end
			end
			template = model
			if player.Parent then
				avatarTemplates[id] = model
			end
		else
			warn("[Eco] No se pudo copiar el avatar de", player.Name, model)
		end
		building[id] = nil
		local callbacks = waiting[id] or {}
		waiting[id] = nil
		for _, callback in callbacks do
			task.spawn(callback, template)
		end
	end)
end

----------------------------------------------------------------------
-- Eco
----------------------------------------------------------------------

function Echo.new(spawnPosition: Vector3, ctx)
	local def = Config.Enemies.Echo
	local model, root = Common.newModel("Echo", HEIGHT)
	Common.prepareModel(model)
	-- (Sigue siendo un fantasma para el Medium, que lo ve a traves de las paredes; pero desde
	-- el 2026-11-24 no las atraviesa: va por los pasillos como el compañero al que imita.)
	model:SetAttribute("Ghost", true)
	model:PivotTo(HIDDEN_CFRAME) -- aparece cuando su cuerpo este listo
	model.Parent = ctx.Container

	local steps = Instance.new("Sound")
	steps.Name = "Footsteps"
	steps.SoundId = FOOTSTEPS
	steps.Looped = true
	steps.Volume = 0.9
	steps.PlaybackSpeed = 1.1
	steps.RollOffMaxDistance = 70
	steps.RollOffMinDistance = 8
	steps.Parent = root

	local self = setmetatable({}, Echo)
	self.Def = def
	self.Ctx = ctx
	self.Model = model
	self.Height = HEIGHT
	self.Steps = steps
	-- Camina por los pasillos (busca el camino); AgentHeight 5: pasa por las puertas
	self.Mover = Common.newMover(model, { Speed = def.Speed, Height = HEIGHT, AgentHeight = 5 })
	self.Awareness = Common.newAwareness(ctx)
	self.State = "Vanished"
	self.ReappearAt = 0 -- en cuanto tenga cuerpo, en su punto de aparicion
	self.SpawnPoint = spawnPosition
	self.Exposure = 0
	self.Revealed = false
	self.LastAttack = 0
	self.PatrolPoint = nil :: Vector3?
	self.NextDisguise = 0
	self.Avatar = nil :: Model?
	self.Humanoid = nil :: Humanoid?
	self.Silhouette = nil :: Highlight?
	self.Eyes = {} :: { BasePart }
	self.Tracks = {} :: { [string]: AnimationTrack }
	self.Disguise = nil :: Player?
	-- Prepara ya el cuerpo de todos: asi cambiar de disfraz despues es instantaneo
	for _, player in Common.getAlivePlayers() do
		withAvatar(player, function() end)
	end
	self:SetDisguise(self:PickDisguise(nil))
	return self
end

function Echo:GetSpeedMultiplier(): number
	local threatBonus = 1 + Config.Threat.SpeedPerFailedMission * self.Ctx.GetTotalThreat()
	return self.Ctx.Difficulty.SpeedMultiplier * threatBonus
end

-- A quien imitar: otro jugador vivo que no sea su presa. Jugando solo: a ti.
function Echo:PickDisguise(target: Player?): Player?
	local others = {}
	for _, player in Common.getAlivePlayers() do
		if player ~= target then
			table.insert(others, player)
		end
	end
	if #others > 0 then
		return others[math.random(1, #others)]
	end
	return target
end

-- Toma el aspecto de ese jugador (en cuanto su cuerpo este construido).
function Echo:SetDisguise(player: Player?)
	if not player then
		return
	end
	self.Disguise = player
	self.DisguiseToken = (self.DisguiseToken or 0) + 1
	local token = self.DisguiseToken
	withAvatar(player, function(template: Model?)
		if template and token == self.DisguiseToken and not self.Destroyed then
			self:MountAvatar(template, player)
		end
	end)
end

-- Pone el cuerpo copiado dentro del modelo, de pie sobre el fondo de la raiz.
function Echo:MountAvatar(template: Model, player: Player)
	if self.Avatar then
		self.Avatar:Destroy()
	end
	for _, eye in self.Eyes do
		eye:Destroy()
	end
	self.Eyes = {}
	self.Tracks = {}
	self.Anim = nil

	local avatar = template:Clone()
	avatar.Name = "Avatar"
	local root = self.Model.PrimaryPart :: BasePart
	local hrp = avatar:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = avatar:FindFirstChildOfClass("Humanoid")
	if not hrp or not humanoid then
		avatar:Destroy()
		return
	end
	for _, d in avatar:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
			d.Massless = true
		end
	end
	hrp.Transparency = 1
	avatar.PrimaryPart = hrp
	-- De pie: lo mas bajo de los pies (R15 LeftFoot/RightFoot, R6 Left/Right Leg) en el fondo
	-- de la raiz (HipHeight no siempre coincide con los pies)
	avatar:PivotTo(root.CFrame)
	local bottom = math.huge
	for _, d in avatar:GetDescendants() do
		if d:IsA("BasePart") and (string.find(d.Name, "Foot") or d.Name == "Left Leg" or d.Name == "Right Leg") then
			bottom = math.min(bottom, d.Position.Y - d.Size.Y / 2)
		end
	end
	if bottom == math.huge then
		local cf, size = avatar:GetBoundingBox()
		bottom = cf.Position.Y - size.Y / 2
	end
	avatar:PivotTo(root.CFrame + Vector3.new(0, (root.Position.Y - HEIGHT / 2) - bottom, 0))
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = hrp
	weld.Parent = hrp

	-- El nombre encima es el del jugador copiado, como el de un jugador de verdad
	humanoid.DisplayName = player.DisplayName
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = false
	humanoid.EvaluateStateMachine = false -- no es un personaje: lo mueve el servidor

	-- Silueta negra al alumbrarlo
	local silhouette = Instance.new("Highlight")
	silhouette.Name = "Silhouette"
	silhouette.FillColor = REVEALED_COLOR
	silhouette.FillTransparency = 0
	silhouette.OutlineTransparency = 1
	silhouette.DepthMode = Enum.HighlightDepthMode.Occluded
	silhouette.Enabled = false
	silhouette.Adornee = avatar
	silhouette.Parent = avatar

	-- Linterna falsa y ojos (fuera del avatar: la silueta no los tapa)
	local head = avatar:FindFirstChild("Head") :: BasePart?
	if head then
		local light = Instance.new("SpotLight")
		light.Name = "FakeFlashlight"
		light.Face = Enum.NormalId.Front
		light.Range = 30
		light.Angle = 50
		light.Brightness = 2
		light.Color = Color3.fromRGB(255, 244, 214)
		light.Parent = head
		for _, side in { -1, 1 } do
			local eye = Common.part({
				Name = "Eye",
				Size = Vector3.new(head.Size.X * 0.17, head.Size.Y * 0.09, 0.05),
				CFrame = head.CFrame * CFrame.new(side * head.Size.X * 0.2, head.Size.Y * 0.08, -head.Size.Z / 2 - 0.03),
				Color = EYE_COLOR,
				Material = Enum.Material.Neon,
				Transparency = 1,
			})
			eye.Anchored = false
			eye.CanQuery = false
			eye.Massless = true
			local eyeWeld = Instance.new("WeldConstraint")
			eyeWeld.Part0 = head
			eyeWeld.Part1 = eye
			eyeWeld.Parent = eye
			eye.Parent = self.Model
			table.insert(self.Eyes, eye)
		end
	end
	avatar.Parent = self.Model

	-- Animaciones de Roblox (quieto, andar, correr)
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	for name, id in ANIMATIONS[humanoid.RigType] or ANIMATIONS[Enum.HumanoidRigType.R15] do
		local animation = Instance.new("Animation")
		animation.AnimationId = id
		local ok, track = pcall(function()
			return (animator :: Animator):LoadAnimation(animation)
		end)
		if ok and track then
			track.Looped = true
			track.Priority = if name == "Idle" then Enum.AnimationPriority.Idle else Enum.AnimationPriority.Movement
			self.Tracks[name] = track
		end
	end
	self:PlayAnimation("Idle", 1)
	-- Hombros (R15 RightShoulder, R6 "Right Shoulder"): para estirar los brazos al atacar
	self.Shoulders = {}
	for _, d in avatar:GetDescendants() do
		if d:IsA("Motor6D") and string.find(d.Name, "Shoulder") then
			table.insert(self.Shoulders, { Motor = d, C0 = d.C0 })
		end
	end

	self.Avatar = avatar
	self.Humanoid = humanoid
	self.Silhouette = silhouette
	local revealed = self.Revealed
	self.Revealed = nil
	self:SetRevealed(revealed == true)
	if RunService:IsStudio() then
		print(string.format("[Eco] Ahora tiene el aspecto de %s", player.Name))
	end
end

-- Ataque: estira los brazos hacia ti de golpe (gira los hombros hacia delante, sobre el
-- torso: vale para R15 y R6). angle 0 = brazos en su sitio.
function Echo:SetReach(angle: number, seconds: number)
	for _, shoulder in self.Shoulders or {} do
		local c0 = shoulder.C0
		local goal = CFrame.new(c0.Position) * CFrame.Angles(math.rad(angle), 0, 0) * c0.Rotation
		if seconds <= 0 then
			shoulder.Motor.C0 = goal
		else
			TweenService:Create(shoulder.Motor, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { C0 = goal }):Play()
		end
	end
end

function Echo:PlayAnimation(name: string, speed: number)
	local track = self.Tracks[name]
	if not track then
		return
	end
	if self.Anim ~= track then
		if self.Anim then
			self.Anim:Stop(0.2)
		end
		track:Play(0.2)
		self.Anim = track
	end
	track:AdjustSpeed(speed)
end

-- Al alumbrarlo se ve lo que es: silueta negra, ojos brillantes, sin linterna ni nombre.
function Echo:SetRevealed(revealed: boolean)
	if self.Revealed == revealed then
		return
	end
	self.Revealed = revealed
	if self.Silhouette then
		self.Silhouette.Enabled = revealed
	end
	for _, eye in self.Eyes do
		eye.Transparency = if revealed then 0 else 1
	end
	if self.Humanoid then
		self.Humanoid.DisplayDistanceType = if revealed then Enum.HumanoidDisplayDistanceType.None else Enum.HumanoidDisplayDistanceType.Viewer
	end
	for _, d in self.Model:GetDescendants() do
		if d:IsA("SpotLight") then
			d.Enabled = not revealed
		end
	end
end

function Echo:Vanish()
	self.VanishAt = nil
	self:SetReach(0, 0)
	self.State = "Vanished"
	self.ReappearAt = os.clock() + self.Def.VanishSeconds
	self.Exposure = 0
	self.Mover:Clear()
	self.Steps:Stop()
	self:PlayAnimation("Idle", 1)
	self.Model:PivotTo(HIDDEN_CFRAME)
	self:SetRevealed(false)
	self.UVUntil = 0
	self:SetUVMark(false)
	-- Volvera con el aspecto de otro compañero
	self:SetDisguise(self:PickDisguise(nil))
end

-- Vuelve en un punto lejos de los jugadores (la primera vez, donde le toco aparecer).
function Echo:Reappear(): boolean
	if not self.Avatar then
		return false -- aun cargando el aspecto que va a copiar
	end
	local best = self.SpawnPoint
	self.SpawnPoint = nil
	if not best then
		for _ = 1, 8 do
			local point = Common.randomPatrolPoint()
			if point then
				local _, _, dist = Common.nearestAlive(point)
				if dist >= self.Def.ReappearMinDistance then
					best = point
					break
				end
				best = best or point
			end
		end
	end
	if not best then
		return false
	end
	local y = best.Y + self.Height / 2
	self.Mover:Clear()
	self.Model:PivotTo(CFrame.new(best.X, y, best.Z))
	self.State = "Stalk"
	self.PatrolPoint = nil
	return true
end

-- Avanza con el sonido de pasos (anda o corre segun la velocidad).
function Echo:Walk(dt: number, target: Vector3, speed: number, _groundY: number)
	self.Mover.Speed = speed
	self.Mover:MoveTowards(target)
	if self.Mover:Step(dt) then
		if not self.Steps.IsPlaying then
			self.Steps:Play()
		end
		if speed > 12 then
			self:PlayAnimation("Run", math.clamp(speed / 16, 0.7, 1.6))
		else
			self:PlayAnimation("Walk", math.clamp(speed / 10, 0.5, 1.5))
		end
	else
		if self.Steps.IsPlaying then
			self.Steps:Stop()
		end
		self:PlayAnimation("Idle", 1)
	end
end

function Echo:Update(dt: number)
	local now = os.clock()

	if self.State == "Vanished" then
		if now >= self.ReappearAt and not self:Reappear() then
			self.ReappearAt = now + 0.5
		end
		return
	end

	-- Acaba de golpear: se queda con los brazos estirados y se esfuma
	if self.VanishAt then
		if now >= self.VanishAt then
			self:Vanish()
		end
		return
	end

	if Common.isStunned(self.Model) then
		self.Steps:Stop()
		self:PlayAnimation("Idle", 1)
		return
	end

	local position = self.Model:GetPivot().Position

	-- 1) Alumbrado: se queda quieto, se revela y desaparece
	local chest = position + Vector3.new(0, self.Height * 0.15, 0)
	local lighting = FlashlightService.GetLightingPlayers(chest)
	local lit = #lighting > 0 or DefenseService.IsInFlare(position)
	if lit then
		-- Quien lo alumbra ve lo que es de verdad
		for _, p in lighting do
			Common.discover(p, "Echo")
		end
		self:SetRevealed(true)
		self.Steps:Stop()
		self:PlayAnimation("Idle", 1)
		self.Exposure += dt
		if self.Exposure >= self.Def.ExposureToVanish then
			self:Vanish()
		end
		return
	end
	self.Exposure = math.max(0, self.Exposure - dt)
	-- La linterna UV lo deja marcado un rato (se ve lo que es, aunque no lo ahuyenta)
	local uvMarked = now < (self.UVUntil or 0)
	self:SetRevealed(uvMarked)
	self:SetUVMark(uvMarked)

	local multiplier = self:GetSpeedMultiplier()

	-- 2) Un petardo lo distrae
	local lure = DefenseService.GetLure(position)
	if lure then
		self:Walk(dt, lure, self.Def.LungeSpeed * multiplier, lure.Y)
		return
	end

	-- 3) Te oye aunque haya paredes
	local target, root, dist, targetPos = self.Awareness:Update(dt, position, function(_player, r)
		return (r.Position - position).Magnitude <= self.Def.SenseRange
	end)

	if not target or not root or not targetPos then
		-- Merodea entre zonas
		local flat = self.PatrolPoint
			and Vector3.new(self.PatrolPoint.X - position.X, 0, self.PatrolPoint.Z - position.Z).Magnitude
		if not self.PatrolPoint or (flat and flat < 4) then
			self.PatrolPoint = Common.randomPatrolPoint()
		end
		if self.PatrolPoint then
			self:Walk(dt, self.PatrolPoint, self.Def.Speed * multiplier, self.PatrolPoint.Y)
		end
		return
	end

	-- No se disfraza de su presa: si la copia a ella y hay otro compañero, cambia de aspecto
	if self.Disguise == target and now >= self.NextDisguise then
		self.NextDisguise = now + 5
		local other = self:PickDisguise(target)
		if other and other ~= target then
			self:SetDisguise(other)
		end
	end

	local speed = if dist <= self.Def.LungeDistance then self.Def.LungeSpeed else self.Def.Speed
	self:Walk(dt, targetPos, speed * multiplier, targetPos.Y - 3)

	if dist <= self.Def.AttackRange + 1 and now - self.LastAttack >= self.Def.AttackCooldown then
		self.LastAttack = now
		Common.damage(target, self.Def.Damage)
		Common.discover(target, "Echo")
		-- Golpea (brazos estirados hacia ti) y se esfuma al terminar
		self.Mover:Clear()
		self.Steps:Stop()
		self:PlayAnimation("Idle", 1)
		self:SetReach(95, 0.08)
		self.VanishAt = now + 0.45
	end
end

-- Contorno morado visible a traves de las paredes para todos (linterna UV).
function Echo:SetUVMark(on: boolean)
	local mark = self.Model:FindFirstChild("UVMark") :: Highlight?
	if on and not mark then
		local h = Instance.new("Highlight")
		h.Name = "UVMark"
		h.FillColor = Color3.fromRGB(170, 60, 255)
		h.FillTransparency = 0.6
		h.OutlineColor = Color3.fromRGB(210, 140, 255)
		h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		h.Parent = self.Model
	elseif not on and mark then
		mark:Destroy()
	end
end

-- Linterna UV (WeaponService): lo revela de lejos durante unos segundos.
function Echo:OnUV(player: Player, seconds: number)
	if self.State ~= "Vanished" then
		self.UVUntil = os.clock() + seconds
		Common.discover(player, "Echo")
	end
end

-- Destello o porrazo: desaparece al instante.
function Echo:OnFlash(player: Player)
	if self.State ~= "Vanished" then
		Common.discover(player, "Echo")
		self:Vanish()
	end
end

function Echo:OnShove(player: Player, _direction: Vector3)
	self:OnFlash(player)
end

function Echo:Destroy()
	self.Destroyed = true
	self.Mover:Destroy()
	self.Model:Destroy()
end

return Echo
