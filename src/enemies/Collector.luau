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
	-- Abrigo largo hasta el suelo, piernas apenas visibles
	add("Coat", Vector3.new(1.9, 5.4, 1.2), at(0, 3.2, 0), COAT)
	add("CoatHem", Vector3.new(2.3, 0.8, 1.5), at(0, 0.6, 0), COAT)
	add("Shoulders", Vector3.new(2.6, 0.6, 1.3), at(0, 5.8, 0), COAT)
	-- Brazos larguisimos con dedos finos
	for _, side in { -1, 1 } do
		add("Arm", Vector3.new(0.4, 4.2, 0.4), at(side * 1.4, 3.8, -0.2) * CFrame.Angles(math.rad(-10), 0, 0), COAT)
		add("Hand", Vector3.new(0.5, 0.9, 0.25), at(side * 1.4, 1.4, -0.55), PORCELAIN, Enum.Material.SmoothPlastic)
	end
	add("Neck", Vector3.new(0.35, 0.7, 0.35), at(0, 6.4, 0), Color3.fromRGB(30, 25, 25))
	-- Cabeza con mascara de porcelana y ojos huecos
	add("Head", Vector3.new(1.1, 1.4, 1.1), at(0, 7.3, 0), Color3.fromRGB(30, 25, 25), Enum.Material.SmoothPlastic)
	add("Mask", Vector3.new(1, 1.3, 0.12), at(0, 7.3, -0.58), PORCELAIN, Enum.Material.SmoothPlastic)
	for _, x in { -0.22, 0.22 } do
		add("Eye", Vector3.new(0.2, 0.12, 0.05), at(x, 7.45, -0.65), Color3.fromRGB(255, 210, 120), Enum.Material.Neon)
	end
	add("Hat", Vector3.new(1.4, 0.8, 1.4), at(0, 8.1, 0), Color3.fromRGB(20, 15, 15), Enum.Material.Fabric)
	-- Vitrina a la espalda con figuritas
	add("Case", Vector3.new(1.8, 2.6, 0.9), at(0, 4.3, 1.1), Color3.fromRGB(190, 210, 220), Enum.Material.Glass).Transparency = 0.5
	add("CaseFrame", Vector3.new(1.9, 0.15, 1), at(0, 5.65, 1.1), Color3.fromRGB(120, 90, 50), Enum.Material.Wood)
	for i = 0, 2 do
		add("Figurine", Vector3.new(0.3, 0.6, 0.3), at(-0.5 + i * 0.5, 3.6 + (i % 2) * 0.9, 1.1), Color3.fromRGB(226, 216, 200), Enum.Material.SmoothPlastic)
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
	return (1 + self.Def.SpeedPerConverted * self.Converted)
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
