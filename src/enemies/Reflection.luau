-- Reflejo: una silueta oscura que acecha pegada a los vidrios de los escaparates y
-- a los espejos (tag ReflectiveSurface). Cambia de cristal cada tanto, siempre cerca
-- de algun jugador. Si alguien la mira fijamente, SALE del cristal y lo persigue
-- un rato; tras golpear (o un destello) vuelve a desaparecer en los cristales.
--
-- "Mirarla" = tenerla casi en el centro de la vista, con linea de vision y que se vea
-- (a oscuras hace falta alumbrarla, una bengala o vision nocturna), como el Globo.
--
-- Contramedidas: no mirar las siluetas de los cristales; la linterna UV la marca a
-- traves de las paredes (sabes en que cristal esta); el destello la devuelve al cristal
-- (de dentro o de fuera); el porrazo, el trapeador y el taser la aturden.
--
-- Estados: Lurk (en un cristal) -> Emerge (sale) -> Chase -> Vanished -> Lurk

local CollectionService = game:GetService("CollectionService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Tags = require(Shared.Tags)
local ServerScriptService = game:GetService("ServerScriptService")

local Server = ServerScriptService:WaitForChild("Server")
local DefenseService = require(Server:WaitForChild("DefenseService"))
local FlashlightService = require(Server:WaitForChild("FlashlightService"))
local LightService = require(Server:WaitForChild("LightService"))
local PlayerStats = require(Server:WaitForChild("PlayerStats"))

local Common = require(script.Parent.Common)

local HEIGHT = 5.5
local HEAD_OFFSET = 1.85 -- altura de la cabeza sobre el pivote
local SILHOUETTE = Color3.fromRGB(12, 12, 16)
local EYE_COLOR = Color3.fromRGB(230, 240, 255)
local LURK_TRANSPARENCY = 0.45 -- en el cristal se ve "a medias"
local GLASS_OFFSET = 0.6 -- studs delante del cristal (del lado del jugador)

local Reflection = {}
Reflection.__index = Reflection

local function buildModel(): Model
	local model, _root = Common.newModel("Reflection", HEIGHT)
	local function add(name, size, offset, shape)
		local p = Common.part({
			Name = name,
			Size = size,
			CFrame = CFrame.new(offset),
			Color = SILHOUETTE,
			Material = Enum.Material.SmoothPlastic,
		})
		if shape then
			p.Shape = shape
		end
		p:SetAttribute("Body", true)
		p.Parent = model
		return p
	end
	-- Detalle de la silueta (se desvanece con ella): soldado a la raiz o a `follow`
	local function detail(name: string, size: Vector3, cf: CFrame, follow: string?, props)
		local p = add(name, size, Vector3.zero)
		p.CFrame = cf
		if follow then
			p:SetAttribute("Follow", follow)
		else
			p:SetAttribute("Detail", true)
		end
		for k, v in props or {} do
			p[k] = v
		end
		return p
	end
	local SHARD = { Color = Color3.fromRGB(150, 165, 185), Material = Enum.Material.Glass, Reflectance = 0.4 }

	-- Silueta humana alargada (un poco mas alta y delgada que un jugador)
	add("LeftLeg", Vector3.new(0.5, 2.2, 0.5), Vector3.new(-0.38, -1.65, 0))
	add("RightLeg", Vector3.new(0.5, 2.2, 0.5), Vector3.new(0.38, -1.65, 0))
	add("Torso", Vector3.new(1.5, 2.1, 0.65), Vector3.new(0, 0.5, 0))
	add("LeftArm", Vector3.new(0.4, 2.6, 0.4), Vector3.new(-1.0, 0.1, 0))
	add("RightArm", Vector3.new(0.4, 2.6, 0.4), Vector3.new(1.0, 0.1, 0))
	add("Head", Vector3.new(0.9, 1.2, 0.95), Vector3.new(0, HEAD_OFFSET, 0))
	-- Cuello largo, hombros caidos y cintura estrecha
	detail("Neck", Vector3.new(0.35, 0.45, 0.35), CFrame.new(0, 1.35, 0))
	for _, side in { -1, 1 } do
		detail("Shoulder", Vector3.new(0.6, 0.6, 0.6), CFrame.new(side * 0.85, 1.35, 0), nil, { Shape = Enum.PartType.Ball })
		-- Pies en punta (siguen a la pierna)
		detail("Foot", Vector3.new(0.4, 0.2, 0.9), CFrame.new(side * 0.38, -2.65, -0.25), if side < 0 then "LeftLeg" else "RightLeg")
		-- Manos con dedos larguisimos, por debajo de las rodillas
		local armName = if side < 0 then "LeftArm" else "RightArm"
		detail("Palm", Vector3.new(0.38, 0.4, 0.2), CFrame.new(side * 1.0, -1.35, 0), armName)
		for i = -1, 1 do
			detail("Finger", Vector3.new(0.07, 0.85, 0.07), CFrame.new(side * 1.0 + i * 0.11, -1.95, -0.02) * CFrame.Angles(0, 0, math.rad(i * 4)), armName)
		end
		detail("Thumb", Vector3.new(0.07, 0.45, 0.07), CFrame.new(side * 0.83, -1.55, -0.05) * CFrame.Angles(0, 0, side * math.rad(25)), armName)
	end
	detail("Waist", Vector3.new(1.1, 0.4, 0.55), CFrame.new(0, -0.7, 0))
	-- Pelo largo y lacio cayendo por la espalda y a los lados de la cara
	for i, x in { -0.45, -0.25, 0, 0.25, 0.45 } do
		local length = 1.3 + (i % 2) * 0.4
		detail("Hair", Vector3.new(0.18, length, 0.1), CFrame.new(x, HEAD_OFFSET + 0.45 - length / 2, 0.48) * CFrame.Angles(math.rad(-6), 0, 0))
	end
	for _, side in { -1, 1 } do
		detail("Hair", Vector3.new(0.1, 1.5, 0.3), CFrame.new(side * 0.47, HEAD_OFFSET - 0.25, -0.15))
	end
	detail("HairTop", Vector3.new(0.95, 0.25, 1.0), CFrame.new(0, HEAD_OFFSET + 0.62, 0.02))
	-- Trozos de espejo clavados (sale de los cristales)
	detail("Shard", Vector3.new(0.3, 0.45, 0.05), CFrame.new(0.4, 0.9, -0.34) * CFrame.Angles(0, 0, math.rad(25)), nil, SHARD)
	detail("Shard", Vector3.new(0.2, 0.35, 0.05), CFrame.new(-0.35, 0.2, -0.34) * CFrame.Angles(0, 0, math.rad(-35)), nil, SHARD)
	detail("Shard", Vector3.new(0.25, 0.3, 0.05), CFrame.new(-0.2, 1.2, 0.34) * CFrame.Angles(0, 0, math.rad(60)), nil, SHARD)
	detail("Shard", Vector3.new(0.05, 0.3, 0.2), CFrame.new(1.21, 0.4, 0) * CFrame.Angles(math.rad(20), 0, 0), "RightArm", SHARD)
	detail("Shard", Vector3.new(0.18, 0.28, 0.05), CFrame.new(-0.25, HEAD_OFFSET + 0.35, -0.48) * CFrame.Angles(0, 0, math.rad(15)), nil, SHARD)
	-- Ojos y una sonrisa palida demasiado ancha: brillan juntos (atributo Glow)
	local function glow(name: string, size: Vector3, cf: CFrame)
		local p = Common.part({
			Name = name,
			Size = size,
			CFrame = cf,
			Color = EYE_COLOR,
			Material = Enum.Material.Neon,
		})
		p:SetAttribute("Detail", true)
		p:SetAttribute("Glow", true)
		p.Parent = model
		return p
	end
	for _, x in { -0.2, 0.2 } do
		glow("Eye", Vector3.new(0.18, 0.1, 0.05), CFrame.new(x, HEAD_OFFSET + 0.1, -0.48))
	end
	for i = -3, 3 do
		local x = i * 0.1
		glow("Grin", Vector3.new(0.11, 0.04, 0.04), CFrame.new(x, HEAD_OFFSET - 0.28 + (x * x) * 0.6, -0.48) * CFrame.Angles(0, 0, math.rad(x * 70)))
	end
	return model
end

function Reflection.new(_spawnPosition: Vector3, ctx)
	local def = Config.Enemies.Reflection
	local model = Common.getTemplate("Reflection") or buildModel()
	local height = Common.getHeight(model)
	Common.prepareModel(model)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
		end
	end
	model:SetAttribute("Ghost", true) -- el Medium la ve a traves de las paredes

	local self = setmetatable({}, Reflection)
	self.Def = def
	self.Ctx = ctx
	self.Model = model
	self.Height = height
	self.CosLook = math.cos(math.rad(def.LookHalfAngle))
	self.Mover = Common.newMover(model, { Speed = def.ChaseSpeed, Height = height, Ghost = true, HoverY = 0 })
	self.State = "Vanished"
	self.StateUntil = os.clock() + 2 -- aparece en un cristal enseguida
	self.Surface = nil :: BasePart?
	self.Normal = Vector3.zero
	self.Stare = 0
	self.Target = nil :: Player?
	self.LastAttack = 0
	self.Warned = false
	self.Bodies = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("Body") then
			table.insert(self.Bodies, d)
		end
	end
	self.Eyes = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and (d.Name == "Eye" or d:GetAttribute("Glow")) then
			table.insert(self.Eyes, d)
		end
	end
	return self
end

function Reflection:SpeedMultiplier(): number
	return self.Ctx.Difficulty.SpeedMultiplier * (1 + Config.Threat.SpeedPerFailedMission * self.Ctx.GetTotalThreat())
end

function Reflection:SetLook(transparency: number, eyeBrightness: number)
	for _, p in self.Bodies do
		p.Transparency = transparency
	end
	for _, eye in self.Eyes do
		eye.Transparency = 1 - eyeBrightness
	end
end

-- Normal (el eje mas fino) de una parte plana.
local function surfaceNormal(part: BasePart): Vector3
	local s = part.Size
	if s.X <= s.Y and s.X <= s.Z then
		return part.CFrame.RightVector
	elseif s.Y <= s.X and s.Y <= s.Z then
		return part.CFrame.UpVector
	end
	return part.CFrame.LookVector
end

local function getSurfaces(): { BasePart }
	local list = {}
	for _, inst in CollectionService:GetTagged(Tags.ReflectiveSurface) do
		if inst:IsA("BasePart") and inst:IsDescendantOf(workspace) then
			table.insert(list, inst)
		end
	end
	return list
end

-- Coloca la silueta en un cristal, del lado de `viewer` (punto de un jugador).
function Reflection:PlaceAt(surface: BasePart, viewer: Vector3)
	local normal = surfaceNormal(surface)
	if normal.Y > 0.7 or normal.Y < -0.7 then
		return false -- cristal horizontal (claraboya): no sirve
	end
	normal = Vector3.new(normal.X, 0, normal.Z).Unit
	if (viewer - surface.Position):Dot(normal) < 0 then
		normal = -normal
	end
	-- Un poco al azar a lo largo del cristal
	local along = normal:Cross(Vector3.yAxis)
	local width = math.max(surface.Size.X, surface.Size.Z)
	local offset = along * (math.random() - 0.5) * math.max(width - 2, 0) * 0.8
	local front = surface.Position + normal * GLASS_OFFSET + offset
	local top = surface.Position.Y + surface.Size.Y / 2
	local bottom = surface.Position.Y - surface.Size.Y / 2
	local floorY = Common.floorBelow(Vector3.new(front.X, top, front.Z), surface.Size.Y + 12) or bottom
	-- De pie en el suelo, con la cabeza dentro del cristal (espejos sobre lavabos)
	local headY = math.clamp(floorY + self.Height / 2 + HEAD_OFFSET, bottom + 0.6, top - 0.4)
	local pivotY = headY - HEAD_OFFSET
	local pos = Vector3.new(front.X, pivotY, front.Z)
	self.Surface = surface
	self.Normal = normal
	self.Model:PivotTo(CFrame.lookAt(pos, pos + normal))
	self.Model.Parent = self.Ctx.Container
	self.Stare = 0
	self:SetLook(LURK_TRANSPARENCY, 0.3)
	self.State = "Lurk"
	self.StateUntil = os.clock() + self.Def.RelocateSeconds * (0.75 + math.random() * 0.5)
	return true
end

-- Elige un cristal cerca de algun jugador (pero no pegado a el). minDistance: lejos de todos.
function Reflection:Relocate(minDistance: number?): boolean
	local surfaces = getSurfaces()
	if #surfaces == 0 then
		if not self.Warned then
			self.Warned = true
			warn("[Reflection] No hay partes con el tag ReflectiveSurface: el Reflejo no aparece")
		end
		return false
	end
	local players = Common.getAlivePlayers()
	local candidates = {}
	for _, surface in surfaces do
		local _, root, d = Common.nearestAlive(surface.Position)
		if root and d >= (minDistance or 12) and d <= self.Def.LurkRange and math.abs(root.Position.Y - surface.Position.Y) < 10 then
			table.insert(candidates, { surface, root.Position })
		end
	end
	local pick
	if #candidates > 0 then
		pick = candidates[math.random(1, #candidates)]
	elseif #players > 0 then
		local surface = surfaces[math.random(1, #surfaces)]
		local _, root = Common.nearestAlive(surface.Position)
		pick = { surface, if root then root.Position else surface.Position + Vector3.new(0, 0, 1) }
	else
		return false
	end
	return self:PlaceAt(pick[1], pick[2])
end

function Reflection:Vanish(seconds: number)
	self.State = "Vanished"
	self.StateUntil = os.clock() + seconds
	self.Target = nil
	self.Surface = nil
	self.Mover:Clear()
	self.Model.Parent = nil
	self:SetUVMark(false)
end

function Reflection:GetHeadPoint(): Vector3
	return self.Model:GetPivot().Position + Vector3.new(0, HEAD_OFFSET, 0)
end

-- La mira de frente, con linea de vision y viendose (como el Globo).
function Reflection:IsStaredBy(player: Player, point: Vector3): boolean
	local character = player.Character
	local head = character and character:FindFirstChild("Head") :: BasePart?
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not head or not root or DefenseService.IsHidden(player) then
		return false
	end
	local toPoint = point - head.Position
	local dist = toPoint.Magnitude
	if dist > self.Def.LookRange or dist < 0.01 then
		return false
	end
	-- Del lado del cristal donde esta la silueta
	if (head.Position - (self.Surface :: BasePart).Position):Dot(self.Normal) < 0 then
		return false
	end
	local look = root.CFrame.LookVector
	local flatLook = Vector3.new(look.X, 0, look.Z)
	local flat = Vector3.new(toPoint.X, 0, toPoint.Z)
	if flatLook.Magnitude < 0.01 then
		return false
	end
	if flat.Magnitude > 0.5 and flatLook.Unit:Dot(flat.Unit) < self.CosLook then
		return false
	end
	if DefenseService.IsInSmoke(point) or not Common.lineOfSight(head.Position, point) then
		return false
	end
	if not LightService.IsDarkAt(point) or DefenseService.IsInFlare(point) then
		return true
	end
	return FlashlightService.IsLighting(player, point) or PlayerStats.HasFlag(player, "NightVision")
end

function Reflection:UpdateLurk(dt: number, now: number)
	local point = self:GetHeadPoint()
	local starer, staring = nil, 0
	for _, player in Common.getAlivePlayers() do
		if self:IsStaredBy(player, point) then
			staring += 1
			starer = starer or player
		end
	end
	if staring > 0 then
		self.Stare += dt / self.Def.EmergeSeconds
		self.StateUntil = math.max(self.StateUntil, now + 2) -- no se cambia de cristal mientras la miran
	else
		self.Stare = math.max(0, self.Stare - dt * 0.5)
	end
	-- Los ojos brillan mas cuanto mas la miran
	self:SetLook(LURK_TRANSPARENCY - self.Stare * 0.3, 0.3 + self.Stare * 0.7)

	if self.Stare >= 1 and starer then
		self.Target = starer
		self.State = "Emerge"
		self.StateUntil = now + self.Def.EmergeWindup
		self.EmergeFrom = self.Model:GetPivot().Position
		return
	end
	if now >= self.StateUntil then
		self:Relocate()
	end
end

function Reflection:Update(dt: number)
	local now = os.clock()

	if self.State == "Vanished" then
		if now >= self.StateUntil and not self:Relocate(self.Def.ReappearMinDistance) then
			self.StateUntil = now + 3
		end
		return
	end

	-- Su cristal ya no existe (mapa cambiado): a otro
	if self.Surface and not self.Surface:IsDescendantOf(workspace) then
		self:Vanish(2)
		return
	end

	if Common.isStunned(self.Model) then
		self.Mover:Clear()
		return
	end

	if self.State == "Lurk" then
		self:UpdateLurk(dt, now)
		return
	end

	if self.State == "Emerge" then
		-- Sale despacio del cristal (aviso de que viene)
		local t = 1 - math.max(0, self.StateUntil - now) / self.Def.EmergeWindup
		local from = self.EmergeFrom :: Vector3
		local pos = from + self.Normal * (t * 1.5)
		self.Model:PivotTo(CFrame.lookAt(pos, pos + self.Normal))
		self:SetLook(LURK_TRANSPARENCY * (1 - t), 1)
		if now >= self.StateUntil then
			self.State = "Chase"
			self.StateUntil = now + self.Def.ChaseSeconds
			self.Mover.HoverY = pos.Y
		end
		return
	end

	-- Chase: persigue a quien la miro
	local target = self.Target
	if not target or not Common.isAlive(target) or now >= self.StateUntil then
		self:Vanish(self.Def.VanishSeconds * 0.5)
		return
	end
	local root = Common.getRoot(target) :: BasePart
	local pos = self.Model:GetPivot().Position
	local goal = Common.targetPosition(target, root)
	local floorY = Common.floorBelow(goal + Vector3.new(0, 2, 0))
	if floorY then
		self.Mover.HoverY = floorY + self.Height / 2
	end
	self.Mover.Speed = self.Def.ChaseSpeed * self:SpeedMultiplier()
	self.Mover:MoveTowards(goal)
	self.Mover:Step(dt)
	if (goal - pos).Magnitude <= self.Def.AttackRange + 1 and now - self.LastAttack > 1 then
		self.LastAttack = now
		Common.playAttack(self.Model)
		Common.damage(target, self.Def.Damage)
		self:Vanish(self.Def.VanishSeconds)
	end
end

-- Contorno morado visible a traves de las paredes (linterna UV).
function Reflection:SetUVMark(on: boolean)
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

function Reflection:OnUV(_player: Player, seconds: number)
	if self.State == "Vanished" then
		return
	end
	self:SetUVMark(true)
	local token = {}
	self.UVToken = token
	task.delay(seconds, function()
		if self.UVToken == token then
			self:SetUVMark(false)
		end
	end)
end

-- Destello: vuelve a los cristales (lejos)
function Reflection:OnFlash(_player: Player)
	if self.State ~= "Vanished" then
		self:Vanish(self.Def.VanishSeconds)
	end
end

function Reflection:OnShove(_player: Player, direction: Vector3, strength: { StunSeconds: number, Distance: number }?)
	local s = strength or Config.Defense.Shove
	self.Mover:Clear()
	DefenseService.Stun(self.Model, s.StunSeconds)
	if self.State == "Chase" then
		Common.knockback(self.Model, direction, s.Distance)
	end
end

function Reflection:Destroy()
	self.Mover:Destroy()
	self.Model:Destroy()
end

return Reflection
