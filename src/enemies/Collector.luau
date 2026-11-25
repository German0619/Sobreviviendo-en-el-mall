-- El Coleccionista (jefe de la noche 15): una figura altisima y delgada con abrigo largo,
-- mascara de porcelana y una vitrina a la espalda. Persigue a quien ve. Cada jugador que
-- convierte en maniqui lo hace mas rapido (SetConverted). Su modulo de jefe
-- (server/Bosses/Collector) lleva las conversiones y las ofrendas.
--
-- Contramedidas: esconderse; el destello, el taser y los empujones lo frenan un momento.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local ServerScriptService = game:GetService("ServerScriptService")

local Server = ServerScriptService:WaitForChild("Server")
local DefenseService = require(Server:WaitForChild("DefenseService"))

local Common = require(script.Parent.Common)

local H = 8.2
local COAT = Color3.fromRGB(45, 30, 35)
local PORCELAIN = Color3.fromRGB(240, 236, 228)

local Collector = {}
Collector.__index = Collector

local function buildModel(): Model
	local model, _root = Common.newModel("Collector", H)
	local function at(x: number, yFromFeet: number, z: number): CFrame
		return CFrame.new(x, yFromFeet - H / 2, z)
	end
	local function add(name, size, cf: CFrame, color: Color3, material, shape)
		local p = Common.part({
			Name = name,
			Size = size,
			CFrame = cf,
			Color = color,
			Material = material or Enum.Material.Fabric,
		})
		if shape then
			p.Shape = shape
		end
		p.Parent = model
		return p
	end
	-- Detalle soldado (Common.prepareModel): a la raiz o, con `follow`, a esa pieza
	local function detail(name, size, cf: CFrame, color: Color3, material, shape, follow: string?)
		local p = add(name, size, cf, color, material, shape)
		if follow then
			p:SetAttribute("Follow", follow)
		else
			p:SetAttribute("Detail", true)
		end
		return p
	end
	local DARK = Color3.fromRGB(30, 25, 25)
	local WOOD = Color3.fromRGB(120, 90, 50)
	local BRASS = Color3.fromRGB(180, 140, 70)
	local LACE = Color3.fromRGB(235, 230, 220)
	local CRIMSON = Color3.fromRGB(110, 20, 30)

	-- Abrigo largo hasta el suelo, piernas apenas visibles
	add("Coat", Vector3.new(1.9, 5.4, 1.2), at(0, 3.2, 0), COAT)
	add("CoatHem", Vector3.new(2.3, 0.8, 1.5), at(0, 0.6, 0), COAT)
	add("Shoulders", Vector3.new(2.6, 0.6, 1.3), at(0, 5.8, 0), COAT)
	-- Pliegues del bajo, solapas, botonadura de laton y fajin
	for i = -1, 1 do
		detail("Pleat", Vector3.new(0.1, 0.8, 0.06), at(i * 0.6, 0.6, -0.76), Color3.fromRGB(32, 20, 25), Enum.Material.Fabric)
	end
	for _, side in { -1, 1 } do
		detail("Lapel", Vector3.new(0.4, 1.6, 0.06), at(side * 0.42, 5.0, -0.62) * CFrame.Angles(0, 0, side * math.rad(-14)), Color3.fromRGB(32, 20, 25), Enum.Material.Fabric)
		-- Cuello alto a los lados de la cabeza
		detail("HighCollar", Vector3.new(0.18, 1.1, 0.9), at(side * 0.6, 6.55, 0.05) * CFrame.Angles(0, 0, side * math.rad(-10)), COAT, Enum.Material.Fabric)
		-- Correas de cuero de la vitrina por encima de los hombros
		detail("Strap", Vector3.new(0.22, 1.6, 0.07), at(side * 0.6, 5.2, -0.63), Color3.fromRGB(70, 45, 30), Enum.Material.Leather)
		detail("StrapTop", Vector3.new(0.22, 0.07, 1.4), at(side * 0.6, 6.12, 0.05), Color3.fromRGB(70, 45, 30), Enum.Material.Leather)
	end
	for i = 0, 5 do
		detail("Button", Vector3.new(0.14, 0.14, 0.14), at(0, 5.3 - i * 0.55, -0.62), BRASS, Enum.Material.Metal, Enum.PartType.Ball)
	end
	detail("Sash", Vector3.new(1.95, 0.35, 1.25), at(0, 3.1, 0), CRIMSON, Enum.Material.Fabric)
	-- Gorguera de encaje alrededor del cuello
	for i = 0, 9 do
		local a = i / 10 * math.pi * 2
		detail("Ruff", Vector3.new(0.32, 0.32, 0.32), at(math.cos(a) * 0.38, 6.15, math.sin(a) * 0.38), LACE, Enum.Material.Fabric, Enum.PartType.Ball)
	end
	-- Brazos larguisimos con dedos finos
	for _, side in { -1, 1 } do
		add("Arm", Vector3.new(0.4, 4.2, 0.4), at(side * 1.4, 3.8, -0.2) * CFrame.Angles(math.rad(-10), 0, 0), COAT)
		detail("Cuff", Vector3.new(0.5, 0.3, 0.5), at(side * 1.4, 1.85, -0.53) * CFrame.Angles(math.rad(-10), 0, 0), LACE, Enum.Material.Fabric, nil, "Arm")
		add("Hand", Vector3.new(0.5, 0.9, 0.25), at(side * 1.4, 1.4, -0.55), PORCELAIN, Enum.Material.SmoothPlastic)
		for i = -1, 2 do
			detail("Finger", Vector3.new(0.08, 0.75, 0.08), at(side * 1.4 + (i - 0.5) * 0.12 * side, 0.65 + math.abs(i - 0.5) * 0.08, -0.57), PORCELAIN, Enum.Material.SmoothPlastic, nil, "Arm")
		end
		detail("Thumb", Vector3.new(0.08, 0.4, 0.08), at(side * 1.15, 1.15, -0.6) * CFrame.Angles(0, 0, side * math.rad(30)), PORCELAIN, Enum.Material.SmoothPlastic, nil, "Arm")
	end
	add("Neck", Vector3.new(0.35, 0.7, 0.35), at(0, 6.4, 0), DARK)
	-- Cabeza con mascara de porcelana pintada (cuencas negras, mejillas, labios y una grieta)
	add("Head", Vector3.new(1.1, 1.4, 1.1), at(0, 7.3, 0), DARK, Enum.Material.SmoothPlastic)
	add("Mask", Vector3.new(1, 1.3, 0.12), at(0, 7.3, -0.58), PORCELAIN, Enum.Material.SmoothPlastic)
	for _, side in { -1, 1 } do
		detail("Socket", Vector3.new(0.3, 0.22, 0.04), at(side * 0.22, 7.45, -0.645), Color3.fromRGB(10, 8, 8), Enum.Material.SmoothPlastic)
		detail("PaintedBrow", Vector3.new(0.3, 0.04, 0.03), at(side * 0.23, 7.7, -0.65) * CFrame.Angles(0, 0, side * math.rad(12)), Color3.fromRGB(60, 40, 40), Enum.Material.SmoothPlastic)
		detail("Blush", Vector3.new(0.2, 0.14, 0.03), at(side * 0.3, 7.05, -0.65), Color3.fromRGB(230, 140, 150), Enum.Material.SmoothPlastic)
	end
	detail("Lips", Vector3.new(0.22, 0.08, 0.03), at(0, 6.85, -0.65), Color3.fromRGB(170, 30, 40), Enum.Material.SmoothPlastic)
	detail("Crack", Vector3.new(0.03, 0.5, 0.03), at(0.3, 7.15, -0.655) * CFrame.Angles(0, 0, math.rad(20)), Color3.fromRGB(40, 35, 35), Enum.Material.SmoothPlastic)
	detail("Crack", Vector3.new(0.03, 0.3, 0.03), at(0.36, 6.85, -0.655) * CFrame.Angles(0, 0, math.rad(-25)), Color3.fromRGB(40, 35, 35), Enum.Material.SmoothPlastic)
	for _, x in { -0.22, 0.22 } do
		add("Eye", Vector3.new(0.2, 0.12, 0.05), at(x, 7.45, -0.65), Color3.fromRGB(255, 210, 120), Enum.Material.Neon)
	end
	-- Chistera con cinta carmesi
	add("Hat", Vector3.new(0.12, 1.9, 1.9), at(0, 8.02, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(20, 15, 15), Enum.Material.Fabric, Enum.PartType.Cylinder)
	detail("HatCrown", Vector3.new(1.0, 1.2, 1.2), at(0, 8.55, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(20, 15, 15), Enum.Material.Fabric, Enum.PartType.Cylinder)
	detail("HatBand", Vector3.new(0.22, 1.24, 1.24), at(0, 8.2, 0) * CFrame.Angles(0, 0, math.rad(90)), CRIMSON, Enum.Material.Fabric, Enum.PartType.Cylinder)
	-- Vitrina a la espalda: cristal, marco de madera, estantes y figuritas (maniquies en miniatura)
	-- (nombres que no son Case/Figurine: van soldados al cuerpo, no al brazo)
	detail("Vitrine", Vector3.new(1.8, 2.6, 0.9), at(0, 4.3, 1.1), Color3.fromRGB(190, 210, 220), Enum.Material.Glass).Transparency = 0.6
	for _, y in { 3.0, 5.65 } do
		detail("VitrineFrame", Vector3.new(1.95, 0.15, 1.0), at(0, y, 1.1), WOOD, Enum.Material.Wood)
	end
	detail("VitrineShelf", Vector3.new(1.75, 0.08, 0.85), at(0, 4.3, 1.1), WOOD, Enum.Material.Wood)
	for _, x in { -0.92, 0.92 } do
		for _, z in { 0.67, 1.53 } do
			detail("VitrinePost", Vector3.new(0.12, 2.6, 0.12), at(x, 4.3, z), WOOD, Enum.Material.Wood)
		end
	end
	detail("VitrineLock", Vector3.new(0.2, 0.25, 0.06), at(0, 3.35, 1.58), BRASS, Enum.Material.Metal)
	for i = 0, 3 do
		local x = -0.6 + i * 0.4
		local y = if i % 2 == 0 then 3.1 else 4.35
		detail("Curio", Vector3.new(0.22, 0.5, 0.18), at(x, y + 0.3, 1.1), Color3.fromRGB(226, 216, 200), Enum.Material.SmoothPlastic)
		detail("Curio", Vector3.new(0.2, 0.2, 0.2), at(x, y + 0.65, 1.1), Color3.fromRGB(226, 216, 200), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	end
	-- Una cabecita de muñeca en el estante de abajo (mira hacia atras: a quien lo sigue)
	detail("Curio", Vector3.new(0.4, 0.4, 0.4), at(0.6, 3.3, 1.1), PORCELAIN, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	for _, dx in { -0.07, 0.07 } do
		detail("CurioEye", Vector3.new(0.06, 0.06, 0.03), at(0.6 + dx, 3.35, 1.3), Color3.fromRGB(20, 20, 20), Enum.Material.SmoothPlastic)
	end
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(255, 210, 140)
	glow.Range = 8
	glow.Brightness = 0.6
	glow.Parent = model:FindFirstChild("Mask")
	return model
end

function Collector.new(spawnPosition: Vector3, ctx)
	local def = Config.Enemies.Collector
	local model = Common.getTemplate("Collector") or buildModel()
	local height = Common.getHeight(model)
	Common.prepareModel(model)
	model:PivotTo(CFrame.new(spawnPosition + Vector3.new(0, height / 2, 0)))
	model.Parent = ctx.Container

	local self = setmetatable({}, Collector)
	self.Def = def
	self.Ctx = ctx
	self.Model = model
	self.Height = height
	self.Mover = Common.newMover(model, { Speed = def.Speed, Height = height, AgentHeight = 6.5 })
	self.Awareness = Common.newAwareness(ctx)
	self.Converted = 0
	self.LastAttack = 0
	self.PatrolPoint = nil
	self.NextRetarget = 0
	return self
end

-- Cuantos jugadores ha convertido (cada uno lo hace mas rapido).
function Collector:SetConverted(count: number)
	self.Converted = count
end

function Collector:SpeedMultiplier(): number
	-- BossSpeed: refuerzo del jefe desde la noche 25 (lo pone su modulo de jefe)
	return (1 + self.Def.SpeedPerConverted * self.Converted)
		* (self.BossSpeed or 1)
		* self.Ctx.Difficulty.SpeedMultiplier
		* (1 + Config.Threat.SpeedPerFailedMission * self.Ctx.GetTotalThreat())
end

function Collector:Walk(dt: number, goal: Vector3, speed: number, retarget: number)
	local now = os.clock()
	if now >= self.NextRetarget or not self.Mover:HasPath() then
		self.Mover:MoveTowards(goal)
		self.NextRetarget = now + retarget
	end
	self.Mover.Speed = speed
	self.Mover:Step(dt)
end

function Collector:Update(dt: number)
	local now = os.clock()
	if Common.isStunned(self.Model) then
		self.Mover:Clear()
		return
	end
	local pos = self.Model:GetPivot().Position
	local eye = pos + Vector3.new(0, self.Height * 0.4, 0)
	local target, _root, dist, targetPos = self.Awareness:Update(dt, pos, function(_player, r)
		return Common.canSee(eye, r)
	end)
	local mul = self:SpeedMultiplier()

	if target and targetPos then
		self.PatrolPoint = nil
		self:Walk(dt, targetPos, self.Def.ChaseSpeed * mul, 0.3)
		if dist <= self.Def.AttackRange + 1 and now - self.LastAttack >= self.Def.AttackCooldown then
			self.LastAttack = now
			Common.playAttack(self.Model)
			Common.damage(target, self.Def.Damage)
		end
		return
	end

	local lure = DefenseService.GetLure(pos)
	if lure then
		self:Walk(dt, lure, self.Def.Speed * mul, 0.5)
		return
	end
	if not self.PatrolPoint or Vector3.new(self.PatrolPoint.X - pos.X, 0, self.PatrolPoint.Z - pos.Z).Magnitude < 4 then
		self.PatrolPoint = Common.randomPatrolPoint()
	end
	if self.PatrolPoint then
		self:Walk(dt, self.PatrolPoint, self.Def.Speed * mul, 1)
	end
end

function Collector:Stun(seconds: number)
	self.Mover:Clear()
	DefenseService.Stun(self.Model, seconds)
end

function Collector:OnFlash(_player: Player)
	self:Stun(self.Def.StunSeconds)
end

function Collector:OnTaser(_player: Player)
	self:Stun(self.Def.StunSeconds)
end

function Collector:OnShove(_player: Player, direction: Vector3, strength: { StunSeconds: number, Distance: number }?)
	local s = strength or Config.Defense.Shove
	self:Stun(math.min(s.StunSeconds, self.Def.StunSeconds))
	Common.knockback(self.Model, direction, s.Distance * 0.5)
end

function Collector:Destroy()
	self.Mover:Destroy()
	self.Model:Destroy()
end

return Collector
