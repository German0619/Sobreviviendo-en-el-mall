-- Polillas de luz: un enjambre que revolotea por el mall y persigue las linternas
-- encendidas. Si te alcanza con la linterna encendida, le chupa la bateria.
-- No hace dano: el peligro es quedarte a oscuras con los demas enemigos.
--
-- Contramedidas: apagar la linterna (te pierden a los pocos segundos), lanzar una
-- bengala (prefieren su luz) o un petardo, y el destello (las dispersa un rato).

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local ServerScriptService = game:GetService("ServerScriptService")

local Server = ServerScriptService:WaitForChild("Server")
local DefenseService = require(Server:WaitForChild("DefenseService"))
local FlashlightService = require(Server:WaitForChild("FlashlightService"))

local Common = require(script.Parent.Common)

local HEIGHT = 3
local MOTH_COLOR = Color3.fromRGB(235, 225, 190)
local FLARE_SEARCH = 40 -- studs extra sobre el radio de la bengala para notarla

local Moth = {}
Moth.__index = Moth

local WING_EDGE = Color3.fromRGB(165, 145, 110)
local MOTH_BODY = Color3.fromRGB(120, 100, 75)
local WING_SPOT = Color3.fromRGB(60, 45, 35)

-- Una polilla en `cf` (frente = -Z), con las alas abiertas `flap` grados.
local function buildMoth(model: Model, cf: CFrame, scale: number, flap: number)
	local function add(name: string, size: Vector3, offset: CFrame, color: Color3, props)
		local p = Common.part({
			Name = name,
			Size = size * scale,
			CFrame = cf * (offset - offset.Position + offset.Position * scale),
			Color = color,
			Material = Enum.Material.Fabric,
		})
		for k, v in props or {} do
			p[k] = v
		end
		p:SetAttribute("Detail", true) -- soldada a la raiz: solo se mueve la raiz
		p.Parent = model
		return p
	end
	-- Cuerpo peludo: torax, abdomen a rayas y cabeza con ojos negros
	add("MothThorax", Vector3.new(0.16, 0.16, 0.18), CFrame.new(0, 0, -0.06), MOTH_BODY, { Shape = Enum.PartType.Ball })
	add("MothAbdomen", Vector3.new(0.13, 0.12, 0.32), CFrame.new(0, -0.01, 0.15), MOTH_BODY)
	add("MothStripe", Vector3.new(0.14, 0.13, 0.04), CFrame.new(0, -0.01, 0.17), WING_SPOT)
	add("MothHead", Vector3.new(0.11, 0.11, 0.11), CFrame.new(0, 0.01, -0.19), MOTH_BODY, { Shape = Enum.PartType.Ball })
	for _, side in { -1, 1 } do
		add("MothEye", Vector3.new(0.05, 0.05, 0.05), CFrame.new(side * 0.045, 0.02, -0.23), Color3.fromRGB(10, 10, 10), {
			Shape = Enum.PartType.Ball,
			Material = Enum.Material.SmoothPlastic,
			Reflectance = 0.3,
		})
		-- Antenas plumosas hacia delante
		add("MothAntenna", Vector3.new(0.02, 0.02, 0.24), CFrame.new(side * 0.06, 0.07, -0.33) * CFrame.Angles(math.rad(25), side * math.rad(-25), 0), WING_SPOT)
		-- Alas: articuladas en el costado del torax, abiertas en V
		local hinge = CFrame.new(side * 0.06, 0.02, -0.04) * CFrame.Angles(0, 0, side * math.rad(flap))
		add("MothWing", Vector3.new(0.48, 0.025, 0.3), hinge * CFrame.new(side * 0.26, 0, -0.02) * CFrame.Angles(0, side * math.rad(12), 0), MOTH_COLOR)
		add("MothWingEdge", Vector3.new(0.12, 0.03, 0.31), hinge * CFrame.new(side * 0.47, 0, -0.03) * CFrame.Angles(0, side * math.rad(12), 0), WING_EDGE)
		add("MothWingSpot", Vector3.new(0.09, 0.032, 0.09), hinge * CFrame.new(side * 0.3, 0, -0.03) * CFrame.Angles(0, math.rad(45), 0), WING_SPOT)
		add("MothHindWing", Vector3.new(0.32, 0.022, 0.22), hinge * CFrame.new(side * 0.18, -0.005, 0.2) * CFrame.Angles(0, side * math.rad(-20), 0), WING_EDGE)
	end
end

local function buildModel(): Model
	local model, root = Common.newModel("Moth", HEIGHT)
	-- Unas cuantas polillas fijas (se ven aunque las particulas esten desactivadas), cada
	-- una en otra fase del aleteo y mirando hacia fuera del enjambre
	local count = 5
	for i = 1, count do
		local angle = i / count * math.pi * 2
		local radius = 0.9 + (i % 2) * 0.35
		local pos = Vector3.new(math.cos(angle) * radius, math.sin(angle * 2) * 0.5, math.sin(angle) * radius)
		-- Vuelan en circulo (tangente al enjambre), un poco inclinadas
		local cf = CFrame.lookAt(pos, pos + Vector3.new(-math.sin(angle), 0.15 * math.cos(angle * 3), math.cos(angle)))
			* CFrame.Angles(0, 0, math.rad(math.sin(i * 2.1) * 12))
		buildMoth(model, cf, 1.6 + (i % 2) * 0.3, ({ 10, 35, -5, 50, 20 })[i])
	end
	-- Pelusa luminosa en el centro (las polillas rodean "algo")
	local dust = Common.part({
		Name = "MothDust",
		Size = Vector3.new(0.6, 0.6, 0.6),
		Shape = Enum.PartType.Ball,
		CFrame = CFrame.new(),
		Color = Color3.fromRGB(255, 240, 190),
		Material = Enum.Material.Neon,
		Transparency = 0.75,
	})
	dust:SetAttribute("Detail", true)
	dust.Parent = model
	local swarm = Instance.new("ParticleEmitter")
	swarm.Name = "Swarm"
	swarm.Color = ColorSequence.new(MOTH_COLOR)
	swarm.LightEmission = 0.25
	swarm.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 0.2) })
	swarm.Lifetime = NumberRange.new(0.8, 1.4)
	swarm.Rate = 30
	swarm.Speed = NumberRange.new(2, 4)
	swarm.SpreadAngle = Vector2.new(180, 180)
	swarm.Drag = 3
	swarm.RotSpeed = NumberRange.new(-400, 400)
	swarm.Rotation = NumberRange.new(0, 360)
	swarm.Parent = root
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(255, 240, 180)
	glow.Range = 5
	glow.Brightness = 0.35
	glow.Parent = root
	return model
end

function Moth.new(spawnPosition: Vector3, ctx)
	local def = Config.Enemies.Moth
	local model = Common.getTemplate("Moth") or buildModel()
	local height = Common.getHeight(model)
	Common.prepareModel(model)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
		end
	end
	local hoverY = spawnPosition.Y + def.HoverHeight
	model:PivotTo(CFrame.new(spawnPosition.X, hoverY, spawnPosition.Z))
	model.Parent = ctx.Container

	local self = setmetatable({}, Moth)
	self.Def = def
	self.Ctx = ctx
	self.Model = model
	self.Mover = Common.newMover(model, {
		Speed = def.Speed,
		Height = height,
		Ghost = true, -- vuelan por encima de los muebles
		HoverY = hoverY,
		HoverOffset = def.HoverHeight,
	})
	self.Target = nil :: Player?
	self.LostAt = 0 -- cuando dejo de ver la linterna de su objetivo
	self.ScatteredUntil = 0
	self.WanderPoint = nil
	self.NextRetarget = 0
	self.Warned = {} :: { [Player]: boolean }
	self.Swarm = model:FindFirstChild("Swarm", true) :: ParticleEmitter?
	return self
end

function Moth:SpeedMultiplier(): number
	return self.Ctx.Difficulty.SpeedMultiplier * (1 + Config.Threat.SpeedPerFailedMission * self.Ctx.GetTotalThreat())
end

local function getHead(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("Head") :: BasePart?
end

-- Ven una linterna encendida si estan cerca o hay linea de vision.
function Moth:SeesLight(player: Player, position: Vector3): boolean
	if not FlashlightService.IsOn(player) or DefenseService.IsHidden(player) then
		return false
	end
	local head = getHead(player)
	if not head then
		return false
	end
	local d = (head.Position - position).Magnitude
	if d > self.Def.SenseRange then
		return false
	end
	if DefenseService.IsInSmoke(position) or DefenseService.IsInSmoke(head.Position) then
		return false
	end
	return d <= Config.Detection.CloseRange or Common.lineOfSight(position, head.Position)
end

function Moth:FindTarget(position: Vector3): Player?
	local best, bestDist = nil, math.huge
	for _, player in Common.getAlivePlayers() do
		local head = getHead(player)
		if head and self:SeesLight(player, position) then
			local d = (head.Position - position).Magnitude
			if d < bestDist then
				best, bestDist = player, d
			end
		end
	end
	return best
end

function Moth:FlyTo(point: Vector3, speed: number, dt: number)
	local now = os.clock()
	if now >= self.NextRetarget or not self.Mover:HasPath() then
		self.Mover:MoveTowards(point)
		self.NextRetarget = now + 0.25
	end
	self.Mover.Speed = speed
	self.Mover:Step(dt)
end

function Moth:SetVisible(visible: boolean)
	if visible then
		self.Model.Parent = self.Ctx.Container
	else
		self.Model.Parent = nil
	end
end

function Moth:Update(dt: number)
	local now = os.clock()
	if now < self.ScatteredUntil then
		return
	end
	if not self.Model.Parent then
		-- Vuelven a juntarse lejos de los jugadores
		local point = Common.randomPatrolPoint()
		if point then
			local _, _, d = Common.nearestAlive(point)
			if d < 30 then
				self.ScatteredUntil = now + 1 -- probar otro punto en un segundo
				return
			end
			local y = point.Y + self.Def.HoverHeight
			self.Model:PivotTo(CFrame.new(point.X, y, point.Z))
			self.Mover:Clear()
			self.Mover.HoverY = y
		end
		self:SetVisible(true)
	end

	if Common.isStunned(self.Model) then
		self.Mover:Clear()
		return
	end

	local position = self.Model:GetPivot().Position
	local speedMul = self:SpeedMultiplier()

	-- Objetivo: la linterna encendida mas cercana. Tras perderla siguen un rato a donde estaba.
	local seen = self:FindTarget(position)
	if seen then
		self.Target = seen
		self.LostAt = 0
	elseif self.Target then
		if self.LostAt == 0 then
			self.LostAt = now
		elseif now - self.LostAt > self.Def.LingerSeconds or not Common.isAlive(self.Target) then
			self.Target = nil
		end
	end

	-- Una bengala las atrae mas que una linterna (petardo: solo si no persiguen a nadie)
	local flare = DefenseService.GetFlareNear(position, FLARE_SEARCH)
	local lure = if not self.Target then DefenseService.GetLure(position) else nil
	local bait = flare or lure
	if bait then
		self.Target = nil
		-- Revolotean alrededor
		local t = now * 1.7
		local orbit = bait + Vector3.new(math.cos(t) * 3, 0, math.sin(t) * 3)
		self:FlyTo(orbit, self.Def.ChaseSpeed * speedMul, dt)
		return
	end

	local target = self.Target
	local head = target and getHead(target)
	if target and head then
		self:FlyTo(head.Position, self.Def.ChaseSpeed * speedMul, dt)
		-- Encima de la linterna: le chupan la bateria
		if FlashlightService.IsOn(target) and (head.Position - position).Magnitude <= self.Def.DrainRange then
			local battery = target:GetAttribute("Battery") or 0
			if battery > 0 then
				FlashlightService.TrySpendBattery(target, math.min(battery, self.Def.DrainPerSecond * dt))
			end
			if not self.Warned[target] then
				self.Warned[target] = true
				Remotes.event("Notify"):FireClient(target, "¡Las polillas te chupan la batería! Apaga la linterna.", "bad")
			end
		end
		if self.Swarm then
			self.Swarm.Rate = 55
		end
		return
	end

	-- Sin luz a la vista: revolotean despacio por el mall
	if self.Swarm then
		self.Swarm.Rate = 30
	end
	if not self.WanderPoint or Vector3.new(self.WanderPoint.X - position.X, 0, self.WanderPoint.Z - position.Z).Magnitude < 3 then
		self.WanderPoint = Common.randomPatrolPoint()
	end
	if self.WanderPoint then
		self:FlyTo(self.WanderPoint, self.Def.Speed * speedMul, dt)
	end
end

-- Destello: el fogonazo las dispersa y se juntan lejos al rato.
function Moth:OnFlash(_player: Player)
	self.Target = nil
	self.Mover:Clear()
	self.ScatteredUntil = os.clock() + self.Def.ScatterSeconds
	self:SetVisible(false)
end

-- Porrazo / trapeador: las espanta un momento.
function Moth:OnShove(_player: Player, direction: Vector3, strength: { StunSeconds: number, Distance: number }?)
	local s = strength or Config.Defense.Shove
	self.Mover:Clear()
	DefenseService.Stun(self.Model, s.StunSeconds)
	Common.knockback(self.Model, direction, s.Distance)
end

function Moth:Destroy()
	self.Mover:Destroy()
	self.Model:Destroy()
end

return Moth
