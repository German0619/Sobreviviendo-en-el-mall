-- Vigilante: un guardia sin rostro que patrulla y ve a traves de las camaras.
--
-- Persigue a quien vea (como los demas, tiene que notarte primero). Si una
-- camara de seguridad te ve (SecurityCamera), va corriendo hacia donde te vio.
-- Es el que mas dano hace.
--
-- Contramedidas: esquivar los haces rojos de las camaras o cegarlas con el
-- destello; el destello tambien lo aturde a el; el porrazo lo empuja;
-- los petardos lo distraen; esconderse rompe la persecucion.

local ServerScriptService = game:GetService("ServerScriptService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)

local Server = ServerScriptService:WaitForChild("Server")
local DefenseService = require(Server:WaitForChild("DefenseService"))

local Common = require(script.Parent.Common)
local SecurityCamera = require(script.Parent.SecurityCamera)

local HEIGHT = 7

local Watcher = {}
Watcher.__index = Watcher

local function buildModel(): Model
	local model, _root = Common.newModel("Watcher", HEIGHT)
	local uniform = Color3.fromRGB(25, 28, 38)
	local function add(name, size, offset, color, material)
		local p = Common.part({
			Name = name,
			Size = size,
			CFrame = CFrame.new(offset),
			Color = color or uniform,
			Material = material or Enum.Material.SmoothPlastic,
			CanCollide = true,
		})
		p.Parent = model
		return p
	end
	add("LeftLeg", Vector3.new(1, 3, 1), Vector3.new(-0.55, -2, 0))
	add("RightLeg", Vector3.new(1, 3, 1), Vector3.new(0.55, -2, 0))
	add("Torso", Vector3.new(2.4, 2.8, 1.2), Vector3.new(0, 0.9, 0))
	add("LeftArm", Vector3.new(0.8, 3, 0.8), Vector3.new(-1.65, 0.6, 0))
	add("RightArm", Vector3.new(0.8, 3, 0.8), Vector3.new(1.65, 0.6, 0))
	add("Head", Vector3.new(1.4, 1.4, 1.4), Vector3.new(0, 3, 0), Color3.fromRGB(200, 200, 205))
	add("Cap", Vector3.new(1.6, 0.4, 1.8), Vector3.new(0, 3.85, -0.1))
	-- Un solo "ojo" de camara
	local lens = add("Lens", Vector3.new(0.5, 0.5, 0.2), Vector3.new(0, 3.1, -0.75), Color3.fromRGB(255, 30, 30), Enum.Material.Neon)
	lens.CanCollide = false
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(255, 40, 40)
	glow.Range = 7
	glow.Brightness = 1
	glow.Parent = lens
	return model
end

function Watcher.new(spawnPosition: Vector3, ctx)
	local def = Config.Enemies.Watcher
	local model = Common.getTemplate("Watcher") or buildModel()
	local height = Common.getHeight(model)
	Common.prepareModel(model)
	model:PivotTo(CFrame.new(spawnPosition + Vector3.new(0, height / 2, 0)))
	model.Parent = ctx.Container

	local self = setmetatable({}, Watcher)
	self.Def = def
	self.Ctx = ctx
	self.Model = model
	self.Height = height
	self.Mover = Common.newMover(model, { Speed = def.Speed, Height = height })
	self.Awareness = Common.newAwareness(ctx)
	self.PatrolPoint = nil :: Vector3?
	self.LastAttack = 0
	self.NextRetarget = 0
	return self
end

function Watcher:GetSpeed(base: number): number
	local threatBonus = 1 + Config.Threat.SpeedPerFailedMission * self.Ctx.GetTotalThreat()
	return base * self.Ctx.Difficulty.SpeedMultiplier * threatBonus
end

function Watcher:GoTo(dt: number, point: Vector3, speed: number, retargetEvery: number)
	local now = os.clock()
	if now >= self.NextRetarget or not self.Mover:HasPath() then
		self.Mover:MoveTowards(point)
		self.NextRetarget = now + retargetEvery
	end
	self.Mover.Speed = speed
	self.Mover:Step(dt)
end

function Watcher:Update(dt: number)
	if Common.isStunned(self.Model) then
		self.Mover:Clear()
		return
	end

	local now = os.clock()
	local position = self.Model:GetPivot().Position
	local eye = position + Vector3.new(0, self.Height * 0.4, 0)

	local target, root, dist, targetPos = self.Awareness:Update(dt, position, function(_player, r)
		return Common.canSee(eye, r)
	end)

	-- 1) Un petardo lo distrae, salvo que ya este encima de su presa
	local lure = DefenseService.GetLure(position)
	if lure and (not target or dist > Config.Defense.Firecracker.IgnoreIfTargetWithin) then
		self.PatrolPoint = nil
		self:GoTo(dt, lure, self:GetSpeed(self.Def.ChaseSpeed), 0.5)
		return
	end

	-- 2) Persecucion
	if target and root and targetPos then
		self.PatrolPoint = nil
		self:GoTo(dt, targetPos, self:GetSpeed(self.Def.ChaseSpeed), 0.3)
		if dist <= self.Def.AttackRange + 1 and now - self.LastAttack >= self.Def.AttackCooldown then
			self.LastAttack = now
			Common.damage(target, self.Def.Damage)
		end
		return
	end

	-- 3) Una camara te vio: va hacia alli
	local sighting = SecurityCamera.GetSighting()
	if sighting and now - sighting.Time <= self.Def.AlertMemory then
		self.PatrolPoint = nil
		self:GoTo(dt, sighting.Position, self:GetSpeed(self.Def.ChaseSpeed), 0.5)
		local flat = Vector3.new(sighting.Position.X - position.X, 0, sighting.Position.Z - position.Z)
		if flat.Magnitude < 5 then
			SecurityCamera.ClearSighting() -- llego y no hay nadie
		end
		return
	end

	-- 4) Patrulla
	local point = self.PatrolPoint
	if not point or Vector3.new(point.X - position.X, 0, point.Z - position.Z).Magnitude < 4 then
		point = Common.randomPatrolPoint()
		self.PatrolPoint = point
	end
	if point then
		self:GoTo(dt, point, self:GetSpeed(self.Def.Speed) * 0.6, 1)
	end
end

-- Destello: aturdido.
function Watcher:OnFlash(_player: Player)
	self.Mover:Clear()
	DefenseService.Stun(self.Model, Config.Defense.Flash.StunSeconds)
end

-- Porrazo: sale despedido y queda aturdido.
function Watcher:OnShove(_player: Player, direction: Vector3)
	self.Mover:Clear()
	DefenseService.Stun(self.Model, Config.Defense.Shove.StunSeconds)
	Common.knockback(self.Model, direction, Config.Defense.Shove.Distance)
end

function Watcher:Destroy()
	self.Mover:Destroy()
	self.Model:Destroy()
end

return Watcher
