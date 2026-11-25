-- Ducto: una criatura flaca que se arrastra por dentro del techo, de rejilla en
-- rejilla (tag CeilingVent). No se la ve, pero se la OYE arriba (golpes metalicos).
-- Oye a quien corre cerca: va a la rejilla mas cercana a esa persona, la hace temblar
-- y se deja caer encima. Persigue unos segundos y vuelve a subir.
--
-- Contramedidas: caminar (sin correr) cerca de las rejillas; al oir la rejilla temblar,
-- apartarse; el destello, el porrazo, el trapeador y el taser la hacen subir; un petardo
-- la hace bajar donde explota (lejos de ti); los escondites rompen la persecucion.
--
-- Estados: Crawl (dentro del techo) -> Rattle (aviso) -> Hunt (en el suelo) -> Climb -> Crawl

local CollectionService = game:GetService("CollectionService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Tags = require(Shared.Tags)
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Server = ServerScriptService:WaitForChild("Server")
local DefenseService = require(Server:WaitForChild("DefenseService"))

local Common = require(script.Parent.Common)

local HEIGHT = 3
local SKIN = Color3.fromRGB(14, 14, 16) -- negro: a oscuras solo se le ven los ojos
local EYE_COLOR = Color3.fromRGB(255, 170, 60)
local CRAWL_SOUND = "rbxasset://sounds/action_footsteps_plastic.mp3" -- a poca velocidad suena a golpes
local ABOVE_CEILING = 1.2 -- studs por encima de la rejilla mientras se arrastra
local DROP_SECONDS = 0.45
local CLIMB_SECONDS = 1
local RECOIL_SECONDS = 0.8 -- tras golpear se queda un momento a la vista antes de subir

local Duct = {}
Duct.__index = Duct

local function buildModel(): Model
	local model, root = Common.newModel("Duct", HEIGHT)
	local function add(name, size, cf: CFrame, color: Color3?, material, shape: Enum.PartType?)
		local p = Common.part({
			Name = name,
			Size = size,
			CFrame = cf,
			Color = color or SKIN,
			Material = material or Enum.Material.SmoothPlastic,
		})
		if shape then
			p.Shape = shape
		end
		-- Detalles soldados (Common.prepareModel); las patas se mueven solas (EnemyAnimator)
		if name ~= "UpperLeg" and name ~= "LowerLeg" then
			p:SetAttribute("Detail", true)
		end
		p.Parent = model
		return p
	end
	local BONE = Color3.fromRGB(34, 33, 38) -- costillas y vertebras: un poco mas claras
	local TOOTH = Color3.fromRGB(190, 180, 160)
	local sideways = CFrame.Angles(0, math.rad(90), 0) -- cuña con el triangulo de frente

	-- Cuerpo bajo y alargado (frente = -Z): torax, cintura de avispa y abdomen caido
	add("Body", Vector3.new(1.3, 0.85, 1.5), CFrame.new(0, 0.15, -0.55))
	add("Waist", Vector3.new(0.7, 0.55, 0.7), CFrame.new(0, 0.12, 0.45))
	add("Abdomen", Vector3.new(1.15, 0.75, 1.6), CFrame.new(0, 0.02, 1.5) * CFrame.Angles(math.rad(6), 0, 0))
	for i, z in { 2.45, 2.85, 3.15 } do
		local s = 0.42 - i * 0.1
		add("Tail", Vector3.new(s, s, 0.45), CFrame.new(0, -0.05 - i * 0.08, z) * CFrame.Angles(math.rad(10 * i), 0, 0))
	end
	-- Columna (vertebras salientes) y costillas marcadas
	for i = 0, 7 do
		local z = -1.15 + i * 0.4
		local y = if z < 0.1 then 0.62 elseif z < 0.8 then 0.43 else 0.43 - (z - 0.8) * 0.06
		add("Vertebra", Vector3.new(0.28, 0.18, 0.22), CFrame.new(0, y, z) * CFrame.Angles(math.rad(45), 0, 0), BONE)
	end
	for _, side in { -1, 1 } do
		for i = 0, 2 do
			add("Rib", Vector3.new(0.08, 0.7, 0.12), CFrame.new(side * 0.66, 0.12, -1.05 + i * 0.4) * CFrame.Angles(0, 0, math.rad(side * 10)), BONE)
		end
	end
	-- Craneo alargado, mandibula entreabierta con dientes y seis ojos
	add("Head", Vector3.new(0.95, 0.65, 1.15), CFrame.new(0, 0.4, -1.85))
	add("Brow", Vector3.new(1.0, 0.18, 0.35), CFrame.new(0, 0.66, -2.25), BONE)
	add("Jaw", Vector3.new(0.8, 0.22, 0.95), CFrame.new(0, -0.02, -1.95) * CFrame.Angles(math.rad(-14), 0, 0), BONE)
	for i = -2, 2 do
		add("Tooth", Vector3.new(0.04, 0.2, 0.12), CFrame.new(i * 0.16, 0.0, -2.42) * sideways * CFrame.Angles(math.rad(180), 0, 0), TOOTH, nil, Enum.PartType.Wedge)
		add("Tooth", Vector3.new(0.04, 0.13, 0.1), CFrame.new(i * 0.16 + 0.08, -0.1, -2.38) * sideways, TOOTH, nil, Enum.PartType.Wedge)
	end
	for _, eye in { { 0.25, 0.5, 0.17 }, { 0.12, 0.33, 0.1 }, { 0.38, 0.32, 0.09 } } do
		for _, side in { -1, 1 } do
			add("Eye", Vector3.new(eye[3], eye[3], 0.05), CFrame.new(side * eye[1], eye[2], -2.44), EYE_COLOR, Enum.Material.Neon)
		end
	end
	-- Seis patas largas dobladas como una araña, con garras
	for _, z in { -1.0, 0.25, 1.35 } do
		for _, side in { -1, 1 } do
			add("UpperLeg", Vector3.new(1.6, 0.22, 0.22), CFrame.new(side * 1.3, 0.55, z) * CFrame.Angles(0, 0, math.rad(side * -25)))
			add("LowerLeg", Vector3.new(0.22, 1.8, 0.22), CFrame.new(side * 2.05, -0.55, z) * CFrame.Angles(0, 0, math.rad(side * 12)))
			add("Knee", Vector3.new(0.34, 0.34, 0.34), CFrame.new(side * 2.0, 0.3, z), BONE, nil, Enum.PartType.Ball):SetAttribute("Follow", "UpperLeg")
			add("Claw", Vector3.new(0.12, 0.14, 0.32), CFrame.new(side * 2.24, -1.4, z - 0.12), TOOTH, nil, Enum.PartType.Wedge):SetAttribute("Follow", "UpperLeg")
		end
	end
	-- Telarañas y polvo del conducto colgando del cuerpo
	for _, spot in { { -0.5, -0.4 }, { 0.45, 0.9 }, { -0.3, 1.9 } } do
		add("Cobweb", Vector3.new(0.03, 0.55, 0.03), CFrame.new(spot[1], -0.5, spot[2]) * CFrame.Angles(0, 0, math.rad(8)), Color3.fromRGB(150, 150, 145), Enum.Material.Fabric)
	end
	-- Brillo de los ojos (se ve venir a oscuras)
	local glow = Instance.new("PointLight")
	glow.Name = "EyeGlow"
	glow.Color = EYE_COLOR
	glow.Range = 9
	glow.Brightness = 1.5
	glow.Enabled = false
	glow.Parent = model:FindFirstChild("Head")
	local steps = Instance.new("Sound")
	steps.Name = "Crawl"
	steps.SoundId = CRAWL_SOUND
	steps.Looped = true
	steps.Volume = 1.2
	steps.PlaybackSpeed = 0.55
	steps.RollOffMinDistance = 10
	steps.RollOffMaxDistance = 60
	steps.Parent = root
	return model
end

function Duct.new(_spawnPosition: Vector3, ctx)
	local def = Config.Enemies.Duct
	local model = Common.getTemplate("Duct") or buildModel()
	local height = Common.getHeight(model)
	Common.prepareModel(model)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
		end
	end

	local self = setmetatable({}, Duct)
	self.Def = def
	self.Ctx = ctx
	self.Model = model
	self.Height = height
	self.Mover = Common.newMover(model, { Speed = def.HuntSpeed, Height = height })
	self.State = "Crawl"
	self.StateUntil = 0
	self.Vent = nil :: BasePart? -- rejilla hacia la que va (o en la que esta)
	self.Target = nil :: Player?
	self.NextDropAt = os.clock() + 8 -- no cae nada mas empezar la noche
	self.NextWander = 0
	self.LastAttack = 0
	self.Warned = false
	self.Parts = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d ~= model.PrimaryPart then
			table.insert(self.Parts, d)
		end
	end
	self.Sound = model:FindFirstChild("Crawl", true) :: Sound?
	self:SetHidden(true)
	model.Parent = ctx.Container
	return self
end

function Duct:SpeedMultiplier(): number
	return self.Ctx.Difficulty.SpeedMultiplier * (1 + Config.Threat.SpeedPerFailedMission * self.Ctx.GetTotalThreat())
end

-- Dentro del techo es invisible (pero se oye).
function Duct:SetHidden(hidden: boolean)
	self.Hidden = hidden
	for _, p in self.Parts do
		p.Transparency = if hidden then 1 else 0
	end
	local glow = self.Model:FindFirstChild("EyeGlow", true) :: PointLight?
	if glow then
		glow.Enabled = not hidden
	end
	self.Model:SetAttribute("Ghost", hidden) -- el Medium la ve dentro del techo
end

local function getVents(): { BasePart }
	local list = {}
	for _, inst in CollectionService:GetTagged(Tags.CeilingVent) do
		if inst:IsA("BasePart") and inst:IsDescendantOf(workspace) then
			table.insert(list, inst)
		end
	end
	return list
end

local function nearestVent(vents: { BasePart }, position: Vector3): (BasePart?, number)
	local best, bestDist = nil, math.huge
	for _, vent in vents do
		-- Solo rejillas por encima del punto (su techo, no el de otra planta)
		local dy = vent.Position.Y - position.Y
		if dy > 0 and dy < 22 then
			local d = Vector3.new(vent.Position.X - position.X, 0, vent.Position.Z - position.Z).Magnitude
			if d < bestDist then
				best, bestDist = vent, d
			end
		end
	end
	return best, bestDist
end

-- Hace ruido: corre (va mas rapido que caminando) y no esta escondido.
local function isNoisy(player: Player, root: BasePart): boolean
	if DefenseService.IsHidden(player) then
		return false
	end
	local v = root.AssemblyLinearVelocity
	local walk = player:GetAttribute("WalkSpeed") or 16
	return Vector3.new(v.X, 0, v.Z).Magnitude > walk * 1.15
end

function Duct:CeilingPoint(vent: BasePart): Vector3
	return vent.Position + Vector3.new(0, ABOVE_CEILING, 0)
end

-- Se arrastra por dentro del techo (en linea recta, atravesando lo que haya).
function Duct:CrawlTowards(vent: BasePart, dt: number): boolean
	local pos = self.Model:GetPivot().Position
	local goal = self:CeilingPoint(vent)
	local offset = goal - pos
	local dist = offset.Magnitude
	if dist < 0.5 then
		if self.Sound and self.Sound.IsPlaying then
			self.Sound:Stop()
		end
		return true
	end
	local step = math.min(dist, self.Def.CrawlSpeed * self:SpeedMultiplier() * dt)
	local newPos = pos + offset.Unit * step
	local flat = Vector3.new(offset.X, 0, offset.Z)
	local look = if flat.Magnitude > 0.1 then flat.Unit else Vector3.new(0, 0, -1)
	self.Model:PivotTo(CFrame.lookAt(newPos, newPos + look))
	if self.Sound and not self.Sound.IsPlaying then
		self.Sound:Play()
	end
	return false
end

function Duct:StartRattle(vent: BasePart, target: Player?)
	self.State = "Rattle"
	self.StateUntil = os.clock() + self.Def.RattleSeconds
	self.Vent = vent
	self.Target = target
	self.VentCFrame = vent.CFrame
	if RunService:IsStudio() then
		print(string.format("[Ducto] Va a caer en %s (%s)", tostring(vent.Position), if target then target.Name else "petardo"))
	end
	-- Aviso tambien en texto (sin sonido, o en el telefono, no se oiria)
	for _, player in Common.getAlivePlayers() do
		local root = Common.getRoot(player)
		if root then
			local offset = root.Position - vent.Position
			if Vector3.new(offset.X, 0, offset.Z).Magnitude <= self.Def.DropRange + 6 and offset.Y < 0 and offset.Y > -22 then
				Remotes.event("Notify"):FireClient(player, "¡Algo se mueve en la rejilla de arriba!", "bad")
			end
		end
	end
	if self.Sound then
		self.Sound.PlaybackSpeed = 1.4
		self.Sound:Play()
	end
end

function Duct:StopRattle()
	if self.Vent and self.VentCFrame then
		self.Vent.CFrame = self.VentCFrame
	end
	self.VentCFrame = nil
	if self.Sound then
		self.Sound.PlaybackSpeed = 0.55
		self.Sound:Stop()
	end
end

-- Cae de la rejilla al suelo.
function Duct:Drop()
	self:StopRattle()
	local vent = self.Vent :: BasePart
	local floorY = Common.floorBelow(vent.Position - Vector3.new(0, 1, 0), 30) or (vent.Position.Y - 15)
	local from = vent.Position - Vector3.new(0, 0.5, 0)
	local to = Vector3.new(vent.Position.X, floorY + self.Height / 2, vent.Position.Z)
	self:SetHidden(false)
	self.State = "Falling"
	self.FallFrom, self.FallTo = from, to
	self.StateUntil = os.clock() + DROP_SECONDS
	self.HuntUntil = os.clock() + DROP_SECONDS + self.Def.HuntSeconds
end

function Duct:StartClimb()
	local vents = getVents()
	local pos = self.Model:GetPivot().Position
	local vent = nearestVent(vents, pos)
	self.Mover:Clear()
	self.Target = nil
	if not vent then
		self:SetHidden(true)
		self.State = "Crawl"
		return
	end
	self.Vent = vent
	self.State = "Climb"
	self.ClimbFrom = pos
	self.StateUntil = os.clock() + CLIMB_SECONDS
end

function Duct:UpdateCrawl(dt: number, now: number)
	local vents = getVents()
	if #vents == 0 then
		if not self.Warned then
			self.Warned = true
			warn("[Duct] No hay partes con el tag CeilingVent: el Ducto no aparece")
		end
		return
	end
	local pos = self.Model:GetPivot().Position
	if not self.Vent then
		-- Primera vez: a una rejilla al azar
		self.Vent = vents[math.random(1, #vents)]
		self.Model:PivotTo(CFrame.new(self:CeilingPoint(self.Vent :: BasePart)))
		return
	end

	-- Un petardo: baja alli (lejos de quien lo lanzo)
	local lure = DefenseService.GetLure(pos)
	local canDrop = now >= self.NextDropAt

	-- Quien corre cerca: hacia la rejilla mas cercana a esa persona
	local noisy, noisyRoot, noisyDist = nil, nil, math.huge
	for _, player in Common.getAlivePlayers() do
		local root = Common.getRoot(player)
		if root and isNoisy(player, root) then
			local d = (root.Position - pos).Magnitude
			if d <= self.Def.HearRange and d < noisyDist then
				noisy, noisyRoot, noisyDist = player, root, d
			end
		end
	end

	local goalVent = self.Vent :: BasePart
	local dropTarget: Player? = nil
	if lure and canDrop then
		goalVent = nearestVent(vents, lure) or goalVent
	elseif noisy and noisyRoot and canDrop then
		local vent, d = nearestVent(vents, noisyRoot.Position)
		if vent and d <= self.Def.DropRange * 2 then
			goalVent = vent
			dropTarget = noisy
		end
	elseif now >= self.NextWander then
		-- Merodea por las rejillas cercanas a algun jugador
		self.NextWander = now + 10 + math.random() * 8
		local players = Common.getAlivePlayers()
		if #players > 0 then
			local root = Common.getRoot(players[math.random(1, #players)])
			if root then
				local options = {}
				for _, vent in vents do
					local dy = vent.Position.Y - root.Position.Y
					local d = Vector3.new(vent.Position.X - root.Position.X, 0, vent.Position.Z - root.Position.Z).Magnitude
					if dy > 0 and dy < 22 and d < 60 then
						table.insert(options, vent)
					end
				end
				if #options > 0 then
					goalVent = options[math.random(1, #options)]
				end
			end
		end
	end
	self.Vent = goalVent

	local arrived = self:CrawlTowards(goalVent, dt)
	if not arrived or not canDrop then
		return
	end
	-- En la rejilla: se deja caer si la presa sigue debajo (o si es el petardo)
	if lure and nearestVent(vents, lure) == goalVent then
		self:StartRattle(goalVent, nil)
		return
	end
	if dropTarget and noisyRoot then
		local flat = Vector3.new(noisyRoot.Position.X - goalVent.Position.X, 0, noisyRoot.Position.Z - goalVent.Position.Z).Magnitude
		if flat <= self.Def.DropRange then
			self:StartRattle(goalVent, dropTarget)
		end
	end
end

function Duct:Update(dt: number)
	local now = os.clock()

	if self.State == "Crawl" then
		self:UpdateCrawl(dt, now)
		return
	end

	if self.State == "Rattle" then
		-- La rejilla tiembla (aviso)
		local vent = self.Vent :: BasePart
		local base = self.VentCFrame :: CFrame
		vent.CFrame = base * CFrame.new((math.random() - 0.5) * 0.12, (math.random() - 0.5) * 0.08, (math.random() - 0.5) * 0.12)
			* CFrame.Angles(0, 0, (math.random() - 0.5) * 0.08)
		if now >= self.StateUntil then
			self:Drop()
		end
		return
	end

	if self.State == "Falling" then
		local t = 1 - math.max(0, self.StateUntil - now) / DROP_SECONDS
		local p = (self.FallFrom :: Vector3):Lerp(self.FallTo :: Vector3, t * t)
		self.Model:PivotTo(CFrame.new(p) * (self.Model:GetPivot() - self.Model:GetPivot().Position))
		if now >= self.StateUntil then
			-- Aterriza: se queda agazapado mirando a su presa (tiempo para reaccionar)
			self.State = "Land"
			self.StateUntil = now + self.Def.LandSeconds
			self.HuntUntil = self.StateUntil + self.Def.HuntSeconds
		end
		return
	end

	if self.State == "Land" or self.State == "Recoil" then
		local target = self.Target
		local root = target and Common.getRoot(target)
		local pos = self.Model:GetPivot().Position
		if root then
			local flat = Vector3.new(root.Position.X - pos.X, 0, root.Position.Z - pos.Z)
			if flat.Magnitude > 0.1 then
				self.Model:PivotTo(CFrame.lookAt(pos, pos + flat.Unit))
			end
		end
		if now >= self.StateUntil then
			if self.State == "Recoil" then
				self:StartClimb()
			else
				self.State = "Hunt"
			end
		end
		return
	end

	if self.State == "Climb" then
		local vent = self.Vent :: BasePart
		local t = 1 - math.max(0, self.StateUntil - now) / CLIMB_SECONDS
		local from = self.ClimbFrom :: Vector3
		local to = self:CeilingPoint(vent)
		-- Primero hasta debajo de la rejilla, luego arriba
		local under = Vector3.new(to.X, from.Y, to.Z)
		local p = if t < 0.5 then from:Lerp(under, t * 2) else under:Lerp(to, (t - 0.5) * 2)
		self.Model:PivotTo(CFrame.new(p))
		if now >= self.StateUntil then
			self:SetHidden(true)
			self.State = "Crawl"
			self.NextDropAt = now + self.Def.ClimbCooldown
		end
		return
	end

	-- Hunt: en el suelo
	if Common.isStunned(self.Model) then
		self.Mover:Clear()
		return
	end
	local target = self.Target
	if not target then
		-- Cayo por un petardo: mira alrededor y vuelve a subir... salvo que oiga a alguien cerca
		local pos = self.Model:GetPivot().Position
		local player, root, d = Common.nearestAlive(pos, function(p, r)
			return not DefenseService.IsHidden(p) and Common.canSee(pos, r)
		end)
		if player and root and d < 25 then
			self.Target = player
		elseif now >= (self.HuntUntil or 0) - self.Def.HuntSeconds + 2 then
			self:StartClimb()
		end
		return
	end
	if now >= (self.HuntUntil or 0) or not Common.isAlive(target) or DefenseService.IsHidden(target) then
		self:StartClimb()
		return
	end
	local root = Common.getRoot(target) :: BasePart
	local pos = self.Model:GetPivot().Position
	self.Mover.Speed = self.Def.HuntSpeed * self:SpeedMultiplier()
	self.Mover:MoveTowards(root.Position)
	self.Mover:Step(dt)
	if (root.Position - pos).Magnitude <= self.Def.AttackRange + 1 and now - self.LastAttack >= self.Def.AttackCooldown then
		self.LastAttack = now
		Common.damage(target, self.Def.Damage)
		-- Golpea, se queda un instante a la vista y huye al techo
		self.Mover:Clear()
		self.State = "Recoil"
		self.StateUntil = now + RECOIL_SECONDS
	end
end

-- Destello, porrazo, trapeador y taser: vuelve al techo (aturdida un momento si estaba abajo).
function Duct:Repel(stunSeconds: number)
	if self.State == "Rattle" then
		self:StopRattle()
		self.State = "Crawl"
		self.NextDropAt = os.clock() + self.Def.ClimbCooldown
		return
	end
	if self.State == "Hunt" or self.State == "Land" then
		-- Aturdido un momento y luego sube
		self.Mover:Clear()
		DefenseService.Stun(self.Model, math.min(stunSeconds, 1.5))
		self.State = "Recoil"
		self.StateUntil = os.clock() + math.min(stunSeconds, 1.5)
	end
end

function Duct:OnFlash(_player: Player)
	self:Repel(Config.Defense.Flash.StunSeconds)
end

function Duct:OnShove(_player: Player, direction: Vector3, strength: { StunSeconds: number, Distance: number }?)
	local s = strength or Config.Defense.Shove
	if self.State == "Hunt" then
		Common.knockback(self.Model, direction, s.Distance)
	end
	self:Repel(s.StunSeconds)
end

function Duct:OnTaser(_player: Player)
	self:Repel(Config.Weapons.Taser.StunSeconds)
end

function Duct:Destroy()
	self:StopRattle()
	self.Mover:Destroy()
	self.Model:Destroy()
end

return Duct
