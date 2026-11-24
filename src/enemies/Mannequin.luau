-- Maniqui: solo se mueve cuando NINGUN jugador vivo lo esta mirando.
--
-- "Mirar" = esta dentro del cono de vision del jugador, hay linea de vision
-- y se le puede ver: si su zona esta a oscuras hace falta alumbrarlo con la
-- linterna, una bengala cerca o vision nocturna. Desde un escondite no se le mira.
--
-- Contramedidas: mirarlo, el destello (queda congelado aunque nadie lo mire),
-- el porrazo del Guardia, los petardos (lo distraen) y esconderse.

local ServerScriptService = game:GetService("ServerScriptService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)

local Server = ServerScriptService:WaitForChild("Server")
local LightService = require(Server:WaitForChild("LightService"))
local FlashlightService = require(Server:WaitForChild("FlashlightService"))
local PlayerStats = require(Server:WaitForChild("PlayerStats"))
local DefenseService = require(Server:WaitForChild("DefenseService"))

local Common = require(script.Parent.Common)

local HEIGHT = 6

local Mannequin = {}
Mannequin.__index = Mannequin

local function buildModel(): Model
	local model, _root = Common.newModel("Mannequin", HEIGHT)
	local skin = Color3.fromRGB(226, 216, 200)
	local function add(name, size, offset, shape)
		local p = Common.part({
			Name = name,
			Size = size,
			CFrame = CFrame.new(offset),
			Color = skin,
			Material = Enum.Material.SmoothPlastic,
			CanCollide = true,
		})
		if shape then
			p.Shape = shape
		end
		p.Parent = model
		return p
	end
	add("LeftLeg", Vector3.new(0.9, 2.6, 0.9), Vector3.new(-0.5, -1.7, 0))
	add("RightLeg", Vector3.new(0.9, 2.6, 0.9), Vector3.new(0.5, -1.7, 0))
	add("Torso", Vector3.new(2, 2.4, 1), Vector3.new(0, 0.8, 0))
	add("LeftArm", Vector3.new(0.7, 2.5, 0.7), Vector3.new(-1.4, 0.75, 0))
	add("RightArm", Vector3.new(0.7, 2.5, 0.7), Vector3.new(1.4, 0.75, 0))
	add("Head", Vector3.new(1.3, 1.3, 1.3), Vector3.new(0, 2.4, 0), Enum.PartType.Ball)
	return model
end

function Mannequin.new(spawnPosition: Vector3, ctx)
	local def = Config.Enemies.Mannequin
	local model = Common.getTemplate("Mannequin") or buildModel()
	local height = Common.getHeight(model)
	Common.prepareModel(model)
	model:PivotTo(CFrame.new(spawnPosition + Vector3.new(0, height / 2, 0)))
	model.Parent = ctx.Container

	local self = setmetatable({}, Mannequin)
	self.Def = def
	self.Ctx = ctx
	self.Model = model
	self.Height = height
	self.Mover = Common.newMover(model, { Speed = def.Speed, Height = height })
	self.Awareness = Common.newAwareness(ctx)
	self.PatrolPoint = nil
	self.LastAttack = 0
	self.NextRetarget = 0
	self.CosView = math.cos(math.rad(def.ViewHalfAngle))
	return self
end

function Mannequin:GetSpeed(): number
	local threatBonus = 1 + Config.Threat.SpeedPerFailedMission * self.Ctx.GetTotalThreat()
	return self.Def.Speed * self.Ctx.Difficulty.SpeedMultiplier * threatBonus
end

-- Puntos del cuerpo que se comprueban (cabeza y cintura).
function Mannequin:GetCheckPoints(): { Vector3 }
	local pivot = self.Model:GetPivot().Position
	return {
		pivot + Vector3.new(0, self.Height * 0.35, 0),
		pivot - Vector3.new(0, self.Height * 0.15, 0),
	}
end

function Mannequin:IsSeenBy(player: Player, points: { Vector3 }): boolean
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not head or not root then
		return false
	end

	local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	if look.Magnitude < 0.01 then
		return false
	end
	look = look.Unit

	for _, point in points do
		local toPoint = point - head.Position
		local dist = toPoint.Magnitude
		local flat = Vector3.new(toPoint.X, 0, toPoint.Z)
		if dist <= self.Def.ViewRange and flat.Magnitude > 0.01 and look:Dot(flat.Unit) >= self.CosView then
			if Common.lineOfSight(head.Position, point) then
				-- A oscuras solo se ve si lo alumbras, hay una bengala o tienes vision nocturna.
				if not LightService.IsDarkAt(point) or DefenseService.IsInFlare(point) then
					return true
				end
				if FlashlightService.IsLighting(player, point) or PlayerStats.HasFlag(player, "NightVision") then
					return true
				end
			end
		end
	end
	return false
end

function Mannequin:IsObserved(): boolean
	local points = self:GetCheckPoints()
	for _, player in Common.getAlivePlayers() do
		if not DefenseService.IsHidden(player) and self:IsSeenBy(player, points) then
			return true
		end
	end
	return false
end

function Mannequin:Update(dt: number)
	local position = self.Model:GetPivot().Position
	local eye = position + Vector3.new(0, self.Height * 0.35, 0)

	-- Sigue "viendo" aunque este congelado
	local target, root, dist, targetPos = self.Awareness:Update(dt, position, function(_player, r)
		return Common.canSee(eye, r)
	end)

	if Common.isStunned(self.Model) or self:IsObserved() then
		self.Mover:Clear()
		return
	end

	local now = os.clock()

	-- Un petardo lo distrae, salvo que ya este encima de su presa
	local lure = DefenseService.GetLure(position)
	if lure and (not target or dist > Config.Defense.Firecracker.IgnoreIfTargetWithin) then
		self.PatrolPoint = nil
		if now >= self.NextRetarget or not self.Mover:HasPath() then
			self.Mover:MoveTowards(lure)
			self.NextRetarget = now + 0.5
		end
		self.Mover.Speed = self:GetSpeed()
		self.Mover:Step(dt)
		return
	end

	if not target or not root or not targetPos then
		-- Nadie detectado: patrullar despacio entre zonas
		if not self.PatrolPoint or (Vector3.new(self.PatrolPoint.X - position.X, 0, self.PatrolPoint.Z - position.Z)).Magnitude < 4 then
			self.PatrolPoint = Common.randomPatrolPoint()
		end
		if self.PatrolPoint then
			if now >= self.NextRetarget or not self.Mover:HasPath() then
				self.Mover:MoveTowards(self.PatrolPoint)
				self.NextRetarget = now + 1
			end
			self.Mover.Speed = self:GetSpeed() * 0.4
			self.Mover:Step(dt)
		end
		return
	end

	self.PatrolPoint = nil
	if now >= self.NextRetarget or not self.Mover:HasPath() then
		self.Mover:MoveTowards(targetPos)
		self.NextRetarget = now + 0.3
	end
	self.Mover.Speed = self:GetSpeed()
	self.Mover:Step(dt)

	if dist <= self.Def.AttackRange + 1 and now - self.LastAttack >= self.Def.AttackCooldown then
		self.LastAttack = now
		Common.damage(target, self.Def.Damage)
	end
end

-- Destello: queda congelado aunque nadie lo mire.
function Mannequin:OnFlash(_player: Player)
	self.Mover:Clear()
	DefenseService.Stun(self.Model, Config.Defense.Flash.StunSeconds)
end

-- Porrazo: sale despedido y queda aturdido.
-- strength: { StunSeconds, Distance } (Porrazo por defecto; el Trapeador es mas debil)
function Mannequin:OnShove(_player: Player, direction: Vector3, strength: { StunSeconds: number, Distance: number }?)
	local s = strength or Config.Defense.Shove
	self.Mover:Clear()
	DefenseService.Stun(self.Model, s.StunSeconds)
	Common.knockback(self.Model, direction, s.Distance)
end

function Mannequin:Destroy()
	self.Mover:Destroy()
	self.Model:Destroy()
end

return Mannequin
