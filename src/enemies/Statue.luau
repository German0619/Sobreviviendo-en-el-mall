-- Estatua de la fuente: la estatua de marmol de la fuente central (tag FountainStatue)
-- DESPIERTA: le brillan los ojos, tiembla, salta de la fuente y te sigue sin descanso.
-- Al terminar la noche vuelve a su sitio en la fuente.
--
-- Te siente a traves de las paredes (pasos) a SenseRange. Es algo mas lenta que caminar,
-- pero nunca se detiene: si te paras o te arrinconas, te alcanza.
--
-- Contramedida: SOLO la luz de una bengala la frena (no entra en ella y se queda de
-- piedra mientras dure). El destello, el porrazo, el trapeador, el taser y los petardos
-- no le hacen nada. Los escondites funcionan si no te ve entrar.
--
-- Estados: Wake (en la fuente) -> Leap (salta al suelo) -> Hunt

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local EntityModels = require(Shared.EntityModels)
local Remotes = require(Shared.Remotes)
local Tags = require(Shared.Tags)
local ServerScriptService = game:GetService("ServerScriptService")

local Server = ServerScriptService:WaitForChild("Server")
local DefenseService = require(Server:WaitForChild("DefenseService"))

local Common = require(script.Parent.Common)

local STEPS = "rbxasset://sounds/action_footsteps_plastic.mp3"
local LEAP_SECONDS = 0.9

local Statue = {}
Statue.__index = Statue

function Statue.new(spawnPosition: Vector3, ctx)
	local def = Config.Enemies.Statue
	local model = Common.findMapModel(Tags.FountainStatue)
	local home = nil
	if model then
		home = Common.claimMapModel(model, ctx.Container)
	else
		-- Sin fuente con estatua (mapa propio): aparece en el spawn
		model = EntityModels.statue()
		local h = (model.PrimaryPart :: BasePart).Size.Y
		model:PivotTo(CFrame.new(spawnPosition + Vector3.new(0, h / 2, 0)))
		model.Parent = ctx.Container
	end
	local height = (model.PrimaryPart :: BasePart).Size.Y
	Common.prepareModel(model)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false -- se mueve con PivotTo: sin empujones raros
		end
	end
	EntityModels.setStatueAwake(model, true)

	local steps = Instance.new("Sound")
	steps.Name = "StoneSteps"
	steps.SoundId = STEPS
	steps.Looped = true
	steps.Volume = 2
	steps.PlaybackSpeed = 0.45 -- pasos lentos y pesados
	steps.RollOffMinDistance = 12
	steps.RollOffMaxDistance = 90
	steps.Parent = model.PrimaryPart

	local self = setmetatable({}, Statue)
	self.Def = def
	self.Ctx = ctx
	self.Model = model
	self.Home = home
	self.Height = height
	self.Steps = steps
	self.Mover = Common.newMover(model, { Speed = def.Speed, Height = height, AgentHeight = 6.5 })
	self.Awareness = Common.newAwareness(ctx)
	self.State = if home then "Wake" else "Hunt"
	self.StateUntil = os.clock() + def.WakeSeconds
	self.WakeFrom = model:GetPivot()
	self.LastAttack = 0
	self.PatrolPoint = nil
	self.NextRetarget = 0
	self.Frozen = false

	if home then
		Remotes.event("Notify"):FireAllClients("Se oye piedra crujir en la fuente central...", "bad")
	end
	return self
end

function Statue:SpeedMultiplier(): number
	return self.Ctx.Difficulty.SpeedMultiplier * (1 + Config.Threat.SpeedPerFailedMission * self.Ctx.GetTotalThreat())
end

-- Punto del suelo junto a la fuente, hacia el jugador mas cercano.
function Statue:LeapTarget(): Vector3
	local pos = self.Model:GetPivot().Position
	local _, root = Common.nearestAlive(pos)
	local dir = if root then Vector3.new(root.Position.X - pos.X, 0, root.Position.Z - pos.Z) else Vector3.new(1, 0, 0)
	dir = if dir.Magnitude > 0.1 then dir.Unit else Vector3.new(1, 0, 0)
	-- Fuera del vaso de la fuente: busca suelo cada vez mas lejos
	for dist = 10, 20, 2 do
		local probe = pos + dir * dist
		local floorY = Common.floorBelow(probe + Vector3.new(0, 2, 0), 30)
		if floorY and floorY < pos.Y - 3 then
			return Vector3.new(probe.X, floorY, probe.Z)
		end
	end
	local floorY = Common.floorBelow(pos + dir * 12, 30) or (pos.Y - self.Height)
	return Vector3.new(pos.X + dir.X * 12, floorY, pos.Z + dir.Z * 12)
end

-- Se queda de piedra junto a una bengala.
function Statue:SetFrozen(frozen: boolean)
	if self.Frozen == frozen then
		return
	end
	self.Frozen = frozen
	EntityModels.setStatueAwake(self.Model, not frozen)
	if frozen then
		self.Mover:Clear()
		self.Steps:Stop()
	end
end

function Statue:Update(dt: number)
	local now = os.clock()

	if self.State == "Wake" then
		-- Tiembla en la fuente
		local base = self.WakeFrom :: CFrame
		local shake = CFrame.new((math.random() - 0.5) * 0.2, 0, (math.random() - 0.5) * 0.2)
		self.Model:PivotTo(base * shake)
		if now >= self.StateUntil then
			self.Model:PivotTo(base)
			self.State = "Leap"
			self.LeapFrom = base.Position
			self.LeapTo = self:LeapTarget() + Vector3.new(0, self.Height / 2, 0)
			self.StateUntil = now + LEAP_SECONDS
		end
		return
	end

	if self.State == "Leap" then
		local t = 1 - math.max(0, self.StateUntil - now) / LEAP_SECONDS
		local from, to = self.LeapFrom :: Vector3, self.LeapTo :: Vector3
		local p = from:Lerp(to, t) + Vector3.new(0, math.sin(t * math.pi) * 4, 0)
		local flat = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
		local look = if flat.Magnitude > 0.1 then flat.Unit else Vector3.new(0, 0, -1)
		self.Model:PivotTo(CFrame.lookAt(p, p + look))
		if now >= self.StateUntil then
			self.State = "Hunt"
		end
		return
	end

	local pos = self.Model:GetPivot().Position

	-- La luz de una bengala la frena
	if DefenseService.GetFlareNear(pos, self.Def.FlareMargin) then
		self:SetFrozen(true)
		return
	end
	self:SetFrozen(false)

	-- Siente los pasos a traves de las paredes (salvo dentro de una bengala)
	local target, root, dist, targetPos = self.Awareness:Update(dt, pos, function(_player, r)
		return (r.Position - pos).Magnitude <= self.Def.SenseRange and not DefenseService.IsInFlare(r.Position)
	end)
	local mul = self:SpeedMultiplier()
	local goal: Vector3?
	if target and root and targetPos then
		self.PatrolPoint = nil
		goal = targetPos
	else
		if not self.PatrolPoint or Vector3.new(self.PatrolPoint.X - pos.X, 0, self.PatrolPoint.Z - pos.Z).Magnitude < 4 then
			self.PatrolPoint = Common.randomPatrolPoint()
		end
		goal = self.PatrolPoint
	end
	if not goal then
		return
	end

	if now >= self.NextRetarget or not self.Mover:HasPath() then
		self.Mover:MoveTowards(goal)
		self.NextRetarget = now + (if target then 0.4 else 1.2)
	end
	self.Mover.Speed = self.Def.Speed * mul * (if target then 1 else 0.6)
	-- No entra en la luz de una bengala: si el siguiente paso la pisa, se queda quieta
	local moved = false
	local wp = self.Mover.Waypoints[self.Mover.Index]
	if not (wp and DefenseService.GetFlareNear(wp, self.Def.FlareMargin)) then
		moved = self.Mover:Step(dt)
	end
	if moved then
		if not self.Steps.IsPlaying then
			self.Steps:Play()
		end
	elseif self.Steps.IsPlaying then
		self.Steps:Stop()
	end

	if target and dist <= self.Def.AttackRange + 1 and now - self.LastAttack >= self.Def.AttackCooldown then
		self.LastAttack = now
		Common.damage(target, self.Def.Damage)
	end
end

-- Inmune a todo lo demas (TaserImmune en Config: el taser avisa "no le hace nada").
function Statue:OnFlash(_player: Player) end
function Statue:OnShove(_player: Player, _direction: Vector3, _strength: any) end

function Statue:Destroy()
	self.Mover:Destroy()
	self.Steps:Destroy()
	if self.Home then
		EntityModels.setStatueAwake(self.Model, false)
		Common.releaseMapModel(self.Model, self.Home) -- vuelve a la fuente
	else
		self.Model:Destroy()
	end
end

return Statue
