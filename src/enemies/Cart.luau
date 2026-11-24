-- Carrito: un carrito de supermercado poseido. Patrulla despacio y, cuando te ve
-- en linea recta, tiembla un instante y EMBISTE en esa direccion (no gira).
--
-- Contramedida: apartarse a un lado cuando tiembla. Si choca con una pared queda
-- aturdido unos segundos. Tambien lo frenan el destello, el porrazo, el trapeador,
-- el taser y el cartel de piso mojado; los petardos lo distraen.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Server = ServerScriptService:WaitForChild("Server")
local DefenseService = require(Server:WaitForChild("DefenseService"))

local Common = require(script.Parent.Common)

local HEIGHT = 3.6
local MAX_DROP = 4 -- no se tira por el atrio ni por las escaleras

local Cart = {}
Cart.__index = Cart

local GHOST_COLOR = Color3.fromRGB(150, 220, 255)

local function buildModel(): Model
	local model, _root = Common.newModel("Cart", HEIGHT)
	local function add(name, size, offset: CFrame, props)
		local p = Common.part({
			Name = name,
			Size = size,
			CFrame = offset,
			Color = Color3.fromRGB(170, 180, 190),
			Material = Enum.Material.Metal,
		})
		for k, v in props or {} do
			p[k] = v
		end
		p.Parent = model
		return p
	end
	-- Cesta (paredes finas, se ve "hueca")
	local basketY = 0.3
	add("Bottom", Vector3.new(2.4, 0.15, 3.4), CFrame.new(0, basketY - 0.8, 0))
	add("Left", Vector3.new(0.12, 1.6, 3.4), CFrame.new(-1.2, basketY, 0), { Transparency = 0.35 })
	add("Right", Vector3.new(0.12, 1.6, 3.4), CFrame.new(1.2, basketY, 0), { Transparency = 0.35 })
	add("Front", Vector3.new(2.4, 1.6, 0.12), CFrame.new(0, basketY, -1.7), { Transparency = 0.35 })
	add("Back", Vector3.new(2.4, 1.6, 0.12), CFrame.new(0, basketY, 1.7), { Transparency = 0.35 })
	-- Asa
	add("Handle", Vector3.new(2.6, 0.2, 0.2), CFrame.new(0, basketY + 1.1, 2.1), { Color = Color3.fromRGB(200, 40, 40), Material = Enum.Material.SmoothPlastic })
	-- Patas y ruedas
	for _, x in { -1, 1 } do
		for _, z in { -1.4, 1.4 } do
			add("Leg", Vector3.new(0.12, 1.1, 0.12), CFrame.new(x, -1.05, z))
			add("Wheel", Vector3.new(0.3, 0.45, 0.45), CFrame.new(x, -1.55, z), {
				Shape = Enum.PartType.Cylinder,
				Color = Color3.fromRGB(30, 30, 30),
				Material = Enum.Material.SmoothPlastic,
			})
		end
	end
	-- "Ojos" dentro de la cesta: lo delatan en la oscuridad
	for _, x in { -0.4, 0.4 } do
		add("Eye", Vector3.new(0.3, 0.3, 0.1), CFrame.new(x, basketY + 0.2, -1.6), {
			Color = GHOST_COLOR,
			Material = Enum.Material.Neon,
		})
	end
	local glow = Instance.new("PointLight")
	glow.Color = GHOST_COLOR
	glow.Range = 7
	glow.Brightness = 0.7
	glow.Parent = model:FindFirstChild("Bottom")

	local wisps = Instance.new("ParticleEmitter")
	wisps.Name = "Wisps"
	wisps.Color = ColorSequence.new(GHOST_COLOR)
	wisps.LightEmission = 0.6
	wisps.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) })
	wisps.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1) })
	wisps.Lifetime = NumberRange.new(0.6, 1.2)
	wisps.Rate = 8
	wisps.Speed = NumberRange.new(0.5, 1.5)
	wisps.SpreadAngle = Vector2.new(60, 60)
	wisps.Acceleration = Vector3.new(0, 2, 0)
	wisps.Parent = model:FindFirstChild("Bottom")
	return model
end

function Cart.new(spawnPosition: Vector3, ctx)
	local def = Config.Enemies.Cart
	local model = Common.getTemplate("Cart") or buildModel()
	local height = Common.getHeight(model)
	Common.prepareModel(model)
	model:SetAttribute("Ghost", true) -- poseido: el Medium lo ve a traves de las paredes
	model:PivotTo(CFrame.new(spawnPosition + Vector3.new(0, height / 2, 0)))
	model.Parent = ctx.Container

	local self = setmetatable({}, Cart)
	self.Def = def
	self.Ctx = ctx
	self.Model = model
	self.Height = height
	self.Mover = Common.newMover(model, { Speed = def.Speed, Height = height })
	self.Awareness = Common.newAwareness(ctx)
	self.State = "Roam" -- Roam | Windup | Charge | Recover
	self.StateUntil = 0
	self.ChargeDir = nil :: Vector3?
	self.Charged = 0
	self.HitThisCharge = {} :: { [Player]: boolean }
	self.PatrolPoint = nil
	self.NextRetarget = 0
	self.Wisps = model:FindFirstChild("Wisps", true) :: ParticleEmitter?
	return self
end

function Cart:SpeedMultiplier(): number
	return self.Ctx.Difficulty.SpeedMultiplier * (1 + Config.Threat.SpeedPerFailedMission * self.Ctx.GetTotalThreat())
end

function Cart:SetState(state: string, seconds: number?)
	self.State = state
	self.StateUntil = os.clock() + (seconds or 0)
	if self.Wisps then
		self.Wisps.Rate = if state == "Charge" then 40 elseif state == "Windup" then 25 else 8
	end
end

-- Linea recta y despejada hasta el jugador, en la misma planta.
function Cart:CanChargeAt(root: BasePart): boolean
	local pos = self.Model:GetPivot().Position
	local offset = root.Position - pos
	local flat = Vector3.new(offset.X, 0, offset.Z)
	if flat.Magnitude > self.Def.ChargeRange or math.abs(offset.Y) > 5 then
		return false
	end
	-- Despejado a media altura y a ras de suelo (si no, se estrellaria contra un banco)
	local feet = pos - Vector3.new(0, self.Height / 2 - 0.6, 0)
	return Common.lineOfSight(pos, Vector3.new(root.Position.X, pos.Y, root.Position.Z))
		and Common.lineOfSight(feet, Vector3.new(root.Position.X, feet.Y, root.Position.Z))
end

-- Chocar contra una pared: aturdido.
function Cart:Crash()
	self.Mover:Clear()
	self:SetState("Recover", self.Def.WallStunSeconds)
	DefenseService.Stun(self.Model, self.Def.WallStunSeconds)
	-- Rebote corto hacia atras
	if self.ChargeDir then
		Common.knockback(self.Model, -self.ChargeDir, 1.5)
	end
end

function Cart:StepCharge(dt: number)
	local dir = self.ChargeDir :: Vector3
	local pos = self.Model:GetPivot().Position
	local step = self.Def.ChargeSpeed * self:SpeedMultiplier() * DefenseService.GetSpeedFactor(pos) * dt
	local params = Common.raycastParams()

	-- Pared delante (a media altura y a ras de suelo, para los bancos)
	local feet = pos - Vector3.new(0, self.Height / 2 - 0.6, 0)
	local reach = dir * (step + 1.8)
	if Workspace:Raycast(pos, reach, params) or Workspace:Raycast(feet, reach, params) then
		self:Crash()
		return
	end

	-- Sin suelo delante: frena en seco (no se cae, pero tampoco queda aturdido)
	local newPos = pos + dir * step
	local hit = Workspace:Raycast(newPos + Vector3.new(0, 1, 0), Vector3.new(0, -(self.Height + 6), 0), params)
	local feetY = pos.Y - self.Height / 2
	if not hit or feetY - hit.Position.Y > MAX_DROP then
		self:SetState("Recover", self.Def.RecoverSeconds)
		return
	end
	newPos = Vector3.new(newPos.X, hit.Position.Y + self.Height / 2, newPos.Z)
	self.Model:PivotTo(CFrame.lookAt(newPos, newPos + dir))
	self.Charged += step

	-- Atropella a quien este en su camino (una vez por embestida)
	for _, player in Common.getAlivePlayers() do
		local root = Common.getRoot(player)
		if root and not self.HitThisCharge[player] and not DefenseService.IsHidden(player) then
			local offset = root.Position - newPos
			if Vector3.new(offset.X, 0, offset.Z).Magnitude <= self.Def.HitRadius and math.abs(offset.Y) < 5 then
				self.HitThisCharge[player] = true
				Common.damage(player, self.Def.Damage)
			end
		end
	end

	if self.Charged >= self.Def.ChargeDistance then
		self:SetState("Recover", self.Def.RecoverSeconds)
	end
end

function Cart:Update(dt: number)
	local now = os.clock()
	local pos = self.Model:GetPivot().Position
	local target, root, dist, targetPos = self.Awareness:Update(dt, pos, function(_player, r)
		return Common.canSee(pos, r)
	end)

	if Common.isStunned(self.Model) then
		self.Mover:Clear()
		if self.State == "Windup" or self.State == "Charge" then
			self:SetState("Recover", 0.5)
		end
		return
	end

	if self.State == "Charge" then
		self:StepCharge(dt)
		return
	end

	if self.State == "Windup" then
		-- Tiembla en el sitio (la direccion ya esta fijada)
		local base = self.WindupFrom :: Vector3
		local jitter = Vector3.new((math.random() - 0.5) * 0.3, 0, (math.random() - 0.5) * 0.3)
		self.Model:PivotTo(CFrame.lookAt(base + jitter, base + jitter + (self.ChargeDir :: Vector3)))
		if now >= self.StateUntil then
			self.Model:PivotTo(CFrame.lookAt(base, base + (self.ChargeDir :: Vector3)))
			self.Charged = 0
			self.HitThisCharge = {}
			self:SetState("Charge")
		end
		return
	end

	if self.State == "Recover" then
		if now < self.StateUntil then
			return
		end
		self:SetState("Roam")
	end

	-- Petardo: lo distrae
	local lure = DefenseService.GetLure(pos)
	if lure and (not target or dist > Config.Defense.Firecracker.IgnoreIfTargetWithin) then
		if now >= self.NextRetarget or not self.Mover:HasPath() then
			self.Mover:MoveTowards(lure)
			self.NextRetarget = now + 0.5
		end
		self.Mover.Speed = self.Def.Speed * self:SpeedMultiplier()
		self.Mover:Step(dt)
		return
	end

	-- Te ve en linea recta: prepara la embestida
	if target and root and not DefenseService.IsHidden(target) and self:CanChargeAt(root) then
		local flat = Vector3.new(root.Position.X - pos.X, 0, root.Position.Z - pos.Z)
		if flat.Magnitude > 0.5 then
			self.Mover:Clear()
			self.ChargeDir = flat.Unit
			self.WindupFrom = pos
			self:SetState("Windup", self.Def.WindupSeconds)
			return
		end
	end

	if target and targetPos then
		-- Lo busca hasta tenerlo en linea recta
		self.PatrolPoint = nil
		if now >= self.NextRetarget or not self.Mover:HasPath() then
			self.Mover:MoveTowards(targetPos)
			self.NextRetarget = now + 0.4
		end
		self.Mover.Speed = self.Def.Speed * self:SpeedMultiplier()
		self.Mover:Step(dt)
		return
	end

	-- Patrulla
	if not self.PatrolPoint or Vector3.new(self.PatrolPoint.X - pos.X, 0, self.PatrolPoint.Z - pos.Z).Magnitude < 4 then
		self.PatrolPoint = Common.randomPatrolPoint()
	end
	if self.PatrolPoint then
		if now >= self.NextRetarget or not self.Mover:HasPath() then
			self.Mover:MoveTowards(self.PatrolPoint)
			self.NextRetarget = now + 1
		end
		self.Mover.Speed = self.Def.Speed * 0.6 * self:SpeedMultiplier()
		self.Mover:Step(dt)
	end
end

function Cart:OnFlash(_player: Player)
	self.Mover:Clear()
	self:SetState("Recover", 0.5)
	DefenseService.Stun(self.Model, Config.Defense.Flash.StunSeconds)
end

function Cart:OnShove(_player: Player, direction: Vector3, strength: { StunSeconds: number, Distance: number }?)
	local s = strength or Config.Defense.Shove
	self.Mover:Clear()
	self:SetState("Recover", 0.5)
	DefenseService.Stun(self.Model, s.StunSeconds)
	Common.knockback(self.Model, direction, s.Distance)
end

function Cart:Destroy()
	self.Mover:Destroy()
	self.Model:Destroy()
end

return Cart
