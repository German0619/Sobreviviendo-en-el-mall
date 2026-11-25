-- Apagon: un ente de sombra que viaja entre zonas y las deja a oscuras.
-- Caza a los jugadores que esten en su zona. La luz de la linterna lo hace
-- retroceder; si lo alumbras el tiempo suficiente, huye a otra zona.
-- Cada mision "Reparar luces" fallada lo hace mas rapido y resistente.
--
-- Estados: Roam (va a una zona) -> Darken (parpadeo) -> Hunt -> (Flee) -> Roam
--
-- Contramedidas: linterna (retrocede y huye), destello y porrazo (huye al instante),
-- bengalas (no entra en su radio y no siente a quien este dentro), petardos
-- (lo distraen) y esconderse.

local ServerScriptService = game:GetService("ServerScriptService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)

local Server = ServerScriptService:WaitForChild("Server")
local LightService = require(Server:WaitForChild("LightService"))
local FlashlightService = require(Server:WaitForChild("FlashlightService"))
local DefenseService = require(Server:WaitForChild("DefenseService"))

local Common = require(script.Parent.Common)

local HEIGHT = 7
local idCounter = 0

local Blackout = {}
Blackout.__index = Blackout

local function buildModel(): Model
	local model, _root = Common.newModel("Blackout", HEIGHT)
	local body = Common.part({
		Name = "Body",
		Size = Vector3.new(2.6, 5.5, 2.6),
		CFrame = CFrame.new(0, -0.6, 0),
		Color = Color3.fromRGB(5, 5, 8),
		Material = Enum.Material.SmoothPlastic,
		Transparency = 0.15,
	})
	body.Parent = model
	local head = Common.part({
		Name = "Head",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(2.2, 2.2, 2.2),
		CFrame = CFrame.new(0, 2.6, 0),
		Color = Color3.fromRGB(5, 5, 8),
		Material = Enum.Material.SmoothPlastic,
		Transparency = 0.1,
	})
	head.Parent = model
	for _, x in { -0.45, 0.45 } do
		local eye = Common.part({
			Name = "Eye",
			Size = Vector3.new(0.3, 0.2, 0.1),
			CFrame = CFrame.new(x, 2.75, -1.05),
			Color = Color3.fromRGB(255, 30, 30),
			Material = Enum.Material.Neon,
		})
		eye.Parent = model
	end
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(255, 40, 40)
	glow.Range = 6
	glow.Brightness = 0.6
	glow.Parent = head

	local smoke = Instance.new("ParticleEmitter")
	smoke.Color = ColorSequence.new(Color3.fromRGB(0, 0, 0))
	smoke.LightEmission = 0
	smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 4) })
	smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1) })
	smoke.Lifetime = NumberRange.new(1, 2)
	smoke.Rate = 12
	smoke.Speed = NumberRange.new(0.5, 1.5)
	smoke.SpreadAngle = Vector2.new(180, 180)
	smoke.Parent = body
	return model
end

function Blackout.new(spawnPosition: Vector3, ctx)
	local def = Config.Enemies.Blackout
	local model = Common.getTemplate("Blackout") or buildModel()
	local height = Common.getHeight(model)
	Common.prepareModel(model)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
		end
	end

	-- Es un fantasma para el Medium (lo ve a traves de las paredes). Desde el 2026-11-24 no
	-- las atraviesa ni vuela: va por los pasillos y flota a FloatLift del suelo solo de
	-- aspecto (EnemyAnimator, estilo Float, Config.Enemies.Blackout.FloatLift).
	model:SetAttribute("Ghost", true)

	model:PivotTo(CFrame.new(spawnPosition + Vector3.new(0, height / 2, 0)))
	model.Parent = ctx.Container

	idCounter += 1
	local self = setmetatable({}, Blackout)
	self.Def = def
	self.Ctx = ctx
	self.Model = model
	self.ReasonKey = "Blackout_" .. idCounter
	-- Busca el camino por los pasillos (y las escaleras para cambiar de planta).
	-- AgentHeight 5: es alto, pero pasa por las puertas
	self.Mover = Common.newMover(model, {
		Speed = def.Speed,
		Height = height,
		AgentHeight = 5,
	})
	self.State = "Roam"
	self.Zone = nil
	self.DarkZone = nil
	self.StateTime = os.clock()
	self.LastSeenVictim = os.clock()
	self.Exposure = 0
	self.LastAttack = 0
	self.RepelUntil = 0
	self.RepelFrom = nil :: Vector3?
	self.Awareness = Common.newAwareness(ctx)
	return self
end

-- El centro de una zona esta a media altura (el centro de su caja): para buscar el
-- camino hace falta el punto del suelo debajo.
local function onFloor(point: Vector3): Vector3
	local floorY = Common.floorBelow(point + Vector3.new(0, 2, 0))
	return if floorY then Vector3.new(point.X, floorY, point.Z) else point
end

function Blackout:GetPower(): number
	return 1 + Config.Threat.BlackoutPerFailedLights * self.Ctx.GetThreat("FixLights")
end

function Blackout:GetSpeed(): number
	local threatBonus = 1 + Config.Threat.SpeedPerFailedMission * self.Ctx.GetTotalThreat()
	return self.Def.Speed * self.Ctx.Difficulty.SpeedMultiplier * threatBonus * self:GetPower()
end

function Blackout:ReleaseZone()
	if self.DarkZone then
		LightService.SetReason(self.DarkZone, self.ReasonKey, false)
		self.DarkZone = nil
	end
end

-- Elige una zona, preferiblemente con jugadores dentro.
function Blackout:ChooseZone(exclude: string?): string?
	local weights = {}
	local total = 0
	for _, zone in LightService.GetZones() do
		-- Las zonas oscuras por diseño (servicio, oficinas...) no tiene sentido apagarlas
		if zone ~= exclude and not LightService.IsAmbientDark(zone) then
			local w = 1
			for _, player in Common.getAlivePlayers() do
				local root = Common.getRoot(player)
				if root and LightService.GetZoneAt(root.Position) == zone then
					w += 3
				end
			end
			weights[zone] = w
			total += w
		end
	end
	if total == 0 then
		return exclude
	end
	local roll = math.random() * total
	for zone, w in weights do
		roll -= w
		if roll <= 0 then
			return zone
		end
	end
	return next(weights)
end

function Blackout:SetState(state: string)
	self.State = state
	self.StateTime = os.clock()
end

function Blackout:Flee()
	self:ReleaseZone()
	self.Zone = self:ChooseZone(self.Zone)
	self.Exposure = 0
	self:SetState("Flee")
	local center = self.Zone and LightService.GetZoneCenter(self.Zone)
	if center then
		self.Mover:MoveTowards(onFloor(center))
	end
end

-- Se aleja de `from` en horizontal.
function Blackout:MoveAway(dt: number, position: Vector3, from: Vector3, speedMultiplier: number)
	local away = Vector3.new(position.X - from.X, 0, position.Z - from.Z)
	if away.Magnitude < 0.01 then
		away = Vector3.new(1, 0, 0)
	end
	self.Mover:MoveTowards(position + away.Unit * 8)
	self.Mover.Speed = self:GetSpeed() * speedMultiplier
	self.Mover:Step(dt)
end

function Blackout:Update(dt: number)
	local now = os.clock()
	local position = self.Model:GetPivot().Position
	self.Mover.Speed = self:GetSpeed()

	if Common.isStunned(self.Model) then
		return
	end

	-- 0) Las bengalas lo repelen (sigue alejandose un momento para no temblar en el borde)
	if self.State ~= "Flee" then
		local flare = DefenseService.GetFlareNear(position, 3)
		if flare then
			self.RepelFrom = flare
			self.RepelUntil = now + 1
		end
		if self.RepelFrom and now < self.RepelUntil then
			self:MoveAway(dt, position, self.RepelFrom, 1.3)
			return
		end
		self.RepelFrom = nil
	end

	-- 1) La linterna lo empuja hacia atras
	if self.State ~= "Flee" then
		local lighters = FlashlightService.GetLightingPlayers(position)
		if #lighters > 0 then
			self.Exposure += dt
			local root = Common.getRoot(lighters[1])
			if root then
				self:MoveAway(dt, position, root.Position, 1.3)
			end
			if self.Exposure >= self.Def.ExposureToFlee * self:GetPower() then
				self:Flee()
			end
			return
		end
		self.Exposure = math.max(0, self.Exposure - dt * 0.5)
	end

	-- 2) Un petardo lo distrae mientras busca o caza
	if self.State == "Roam" or self.State == "Hunt" then
		local lure = DefenseService.GetLure(position)
		if lure then
			self.Mover:MoveTowards(lure)
			self.Mover:Step(dt)
			return
		end
	end

	-- 3) Maquina de estados
	if self.State == "Roam" then
		if not self.Zone then
			self.Zone = self:ChooseZone(nil)
		end
		local center = self.Zone and LightService.GetZoneCenter(self.Zone)
		if not center then
			return
		end
		-- No apaga una zona con una bengala en el centro: busca otra
		if DefenseService.IsInFlare(center) then
			self.Zone = self:ChooseZone(self.Zone)
			return
		end
		self.Mover:MoveTowards(onFloor(center))
		self.Mover:Step(dt)
		-- (yendo a pie puede no llegar justo al centro si hay muebles: basta con acercarse)
		local flat = Vector3.new(center.X - position.X, 0, center.Z - position.Z)
		if flat.Magnitude < 7 then
			LightService.Flicker(self.Zone, self.Def.DarkenDelay)
			self:SetState("Darken")
		end
	elseif self.State == "Darken" then
		if now - self.StateTime >= self.Def.DarkenDelay then
			self.DarkZone = self.Zone
			LightService.SetReason(self.Zone, self.ReasonKey, true)
			self.LastSeenVictim = now
			self:SetState("Hunt")
		end
	elseif self.State == "Hunt" then
		-- Siente a quien este en su zona oscura (tras el tiempo de deteccion),
		-- salvo que este dentro de la luz de una bengala
		local target, root, dist, targetPos = self.Awareness:Update(dt, position, function(_player, r)
			return LightService.GetZoneAt(r.Position) == self.Zone and not DefenseService.IsInFlare(r.Position)
		end)
		if target and root and targetPos then
			self.LastSeenVictim = now
			self.Mover:MoveTowards(targetPos)
			self.Mover:Step(dt)
			if dist <= self.Def.AttackRange + 2 and now - self.LastAttack >= self.Def.AttackCooldown then
				self.LastAttack = now
				Common.playAttack(self.Model)
				Common.damage(target, self.Def.Damage)
			end
		elseif now - self.LastSeenVictim > self.Def.ZoneLinger then
			self:ReleaseZone()
			self.Zone = self:ChooseZone(self.Zone)
			self:SetState("Roam")
		end
	elseif self.State == "Flee" then
		self.Mover.Speed = self:GetSpeed() * 1.5
		self.Mover:Step(dt)
		if now - self.StateTime >= self.Def.FleeCooldown then
			self:SetState("Roam")
		end
	end
end

-- Destello o porrazo: huye al instante a otra zona.
function Blackout:OnFlash(_player: Player)
	if self.State ~= "Flee" then
		self:Flee()
	end
end

function Blackout:OnShove(player: Player, _direction: Vector3)
	self:OnFlash(player)
end

function Blackout:Destroy()
	self:ReleaseZone()
	self.Mover:Destroy()
	self.Model:Destroy()
end

return Blackout
