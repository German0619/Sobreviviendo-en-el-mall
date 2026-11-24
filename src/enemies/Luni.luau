-- Luni (jefe de la noche 5): la mascota gigante de Plaza Luna. Una luna sonriente con
-- traje de peluche que CORRE detras del grupo mas numeroso (sabe donde esta). Golpea a
-- quien tenga cerca. El destello, el taser y los empujones la frenan un rato, pero no la
-- paran. Como se la vence (apagon de sector con ella en el cuarto del generador) lo lleva
-- su modulo de jefe (server/Bosses/Luni), que llama a PowerDown().

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local ServerScriptService = game:GetService("ServerScriptService")

local Server = ServerScriptService:WaitForChild("Server")
local DefenseService = require(Server:WaitForChild("DefenseService"))

local Common = require(script.Parent.Common)

local H = 10.5
local MOON = Color3.fromRGB(250, 225, 140)
local SHADE = Color3.fromRGB(70, 55, 110)
local SUIT = Color3.fromRGB(120, 130, 210)
local STEPS = "rbxasset://sounds/action_footsteps_plastic.mp3"

local Luni = {}
Luni.__index = Luni

local function buildModel(): Model
	local model, root = Common.newModel("Luni", H)
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
	-- Traje de peluche
	for _, x in { -0.75, 0.75 } do
		add("Leg", Vector3.new(1.3, 2.6, 1.3), at(x, 1.3, 0), SUIT)
		add("Shoe", Vector3.new(1.6, 0.7, 2), at(x, 0.35, -0.3), Color3.fromRGB(240, 240, 245), Enum.Material.SmoothPlastic)
	end
	add("Body", Vector3.new(3.4, 3.6, 2.6), at(0, 4.3, 0), SUIT)
	add("Belly", Vector3.new(2.2, 2.4, 0.2), at(0, 4.1, -1.35), Color3.fromRGB(235, 235, 245))
	for _, side in { -1, 1 } do
		add("Arm", Vector3.new(1.1, 3.2, 1.1), at(side * 2.2, 4.4, 0) * CFrame.Angles(0, 0, side * math.rad(18)), SUIT)
		add("Glove", Vector3.new(1.3, 1.3, 1.3), at(side * 2.7, 2.7, 0), Color3.fromRGB(245, 245, 245), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	end
	-- Cabeza: una luna con su lado oscuro (creciente)
	add("Head", Vector3.new(4.6, 4.6, 4.6), at(0, 8.2, 0), MOON, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	add("HeadShade", Vector3.new(4.3, 4.3, 4.3), at(1.35, 8.5, 0.55), SHADE, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	-- Cara: ojos enormes y sonrisa
	for _, x in { -0.8, 0.55 } do
		add("EyeWhite", Vector3.new(1.05, 1.05, 1.05), at(x, 8.7, -1.95), Color3.fromRGB(250, 250, 250), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
		add("Pupil", Vector3.new(0.45, 0.45, 0.45), at(x, 8.65, -2.42), Color3.fromRGB(255, 60, 40), Enum.Material.Neon, Enum.PartType.Ball)
	end
	add("Smile", Vector3.new(1.8, 0.18, 0.15), at(-0.1, 7.35, -2.2), Color3.fromRGB(30, 20, 30), Enum.Material.SmoothPlastic)
	for _, side in { -1, 1 } do
		add("SmileEnd", Vector3.new(0.5, 0.18, 0.15), at(-0.1 + side * 1.05, 7.5, -2.15) * CFrame.Angles(0, 0, side * math.rad(30)), Color3.fromRGB(30, 20, 30), Enum.Material.SmoothPlastic)
	end
	local glow = Instance.new("PointLight")
	glow.Name = "Glow"
	glow.Color = MOON
	glow.Range = 16
	glow.Brightness = 0.8
	glow.Parent = model:FindFirstChild("Head")

	local steps = Instance.new("Sound")
	steps.Name = "Steps"
	steps.SoundId = STEPS
	steps.Looped = true
	steps.Volume = 2
	steps.PlaybackSpeed = 0.6
	steps.RollOffMinDistance = 15
	steps.RollOffMaxDistance = 110
	steps.Parent = root
	return model
end

function Luni.new(spawnPosition: Vector3, ctx)
	local def = Config.Enemies.Luni
	local model = Common.getTemplate("Luni") or buildModel()
	local height = Common.getHeight(model)
	Common.prepareModel(model)
	model:PivotTo(CFrame.new(spawnPosition + Vector3.new(0, height / 2, 0)))
	model.Parent = ctx.Container

	local self = setmetatable({}, Luni)
	self.Def = def
	self.Ctx = ctx
	self.Model = model
	self.Height = height
	-- (agente bajo para pasar por las puertas: el disfraz atraviesa el marco)
	self.Mover = Common.newMover(model, { Speed = def.ChaseSpeed, Height = height, AgentHeight = 6.5 })
	self.Target = nil :: Player?
	self.NextPick = 0
	self.SlowUntil = 0
	self.LastAttack = 0
	self.Powered = true
	self.NextRetarget = 0
	self.PatrolPoint = nil
	self.Steps = model:FindFirstChild("Steps", true) :: Sound?
	return self
end

function Luni:SpeedMultiplier(): number
	local slow = if os.clock() < self.SlowUntil then self.Def.SlowMultiplier else 1
	return slow * self.Ctx.Difficulty.SpeedMultiplier * (1 + Config.Threat.SpeedPerFailedMission * self.Ctx.GetTotalThreat())
end

-- El jugador del grupo mas numeroso (si hay empate, el mas cercano).
function Luni:PickTarget(position: Vector3): Player?
	local players = {}
	for _, player in Common.getAlivePlayers() do
		local root = Common.getRoot(player)
		if root and not DefenseService.IsHidden(player) then
			table.insert(players, { Player = player, Pos = root.Position })
		end
	end
	local best, bestCount, bestDist = nil, -1, math.huge
	for _, a in players do
		local count = 0
		for _, b in players do
			if (a.Pos - b.Pos).Magnitude <= self.Def.GroupRadius then
				count += 1
			end
		end
		local d = (a.Pos - position).Magnitude
		if count > bestCount or (count == bestCount and d < bestDist) then
			best, bestCount, bestDist = a.Player, count, d
		end
	end
	return best
end

function Luni:Walk(dt: number, goal: Vector3, speed: number, retarget: number): boolean
	local now = os.clock()
	if now >= self.NextRetarget or not self.Mover:HasPath() then
		self.Mover:MoveTowards(goal)
		self.NextRetarget = now + retarget
	end
	self.Mover.Speed = speed
	return self.Mover:Step(dt)
end

function Luni:Update(dt: number)
	if not self.Powered then
		return
	end
	local now = os.clock()
	if Common.isStunned(self.Model) then
		self.Mover:Clear()
		return
	end
	local pos = self.Model:GetPivot().Position
	local mul = self:SpeedMultiplier()

	if now >= self.NextPick or (self.Target and not Common.isAlive(self.Target)) then
		self.NextPick = now + 1.5
		self.Target = self:PickTarget(pos)
	end

	local moved
	local target = self.Target
	local root = target and Common.getRoot(target)
	if target and root then
		self.PatrolPoint = nil
		moved = self:Walk(dt, Common.targetPosition(target, root), self.Def.ChaseSpeed * mul, 0.3)
	else
		if not self.PatrolPoint or Vector3.new(self.PatrolPoint.X - pos.X, 0, self.PatrolPoint.Z - pos.Z).Magnitude < 4 then
			self.PatrolPoint = Common.randomPatrolPoint()
		end
		moved = self.PatrolPoint ~= nil and self:Walk(dt, self.PatrolPoint, self.Def.Speed * mul, 1)
	end
	if self.Steps then
		if moved and not self.Steps.IsPlaying then
			self.Steps:Play()
		elseif not moved and self.Steps.IsPlaying then
			self.Steps:Stop()
		end
	end

	-- Golpea a cualquiera que tenga al lado (es enorme)
	if now - self.LastAttack >= self.Def.AttackCooldown then
		for _, player in Common.getAlivePlayers() do
			local r = Common.getRoot(player)
			if r and not DefenseService.IsHidden(player) then
				local offset = r.Position - pos
				if Vector3.new(offset.X, 0, offset.Z).Magnitude <= self.Def.AttackRange + 1 and math.abs(offset.Y) < self.Height then
					self.LastAttack = now
					Common.damage(player, self.Def.Damage)
					break
				end
			end
		end
	end
end

-- Destello, taser, empujones: la frenan, no la paran.
function Luni:Slow()
	self.SlowUntil = os.clock() + self.Def.SlowSeconds
end

function Luni:OnFlash(_player: Player)
	self:Slow()
end

function Luni:OnTaser(_player: Player)
	self:Slow()
end

function Luni:OnShove(_player: Player, direction: Vector3, strength: { StunSeconds: number, Distance: number }?)
	local s = strength or Config.Defense.Shove
	self:Slow()
	Common.knockback(self.Model, direction, s.Distance * 0.3)
end

-- Apagon de sector con ella dentro: se queda sin energia (se apagan los ojos y se inclina).
function Luni:PowerDown()
	if not self.Powered then
		return
	end
	self.Powered = false
	self.Mover:Clear()
	if self.Steps then
		self.Steps:Stop()
	end
	for _, d in self.Model:GetDescendants() do
		if d:IsA("BasePart") and d.Name == "Pupil" then
			d.Color = Color3.fromRGB(20, 20, 20)
			d.Material = Enum.Material.SmoothPlastic
		elseif d:IsA("PointLight") then
			d.Enabled = false
		end
	end
	local pivot = self.Model:GetPivot()
	local fall = pivot * CFrame.new(0, -1.2, 0) * CFrame.Angles(math.rad(-25), 0, 0)
	task.spawn(function()
		for i = 1, 20 do
			if not self.Model.Parent then
				return
			end
			self.Model:PivotTo(pivot:Lerp(fall, i / 20))
			task.wait(0.03)
		end
	end)
end

function Luni:GetPosition(): Vector3
	return self.Model:GetPivot().Position
end

function Luni:Destroy()
	self.Mover:Destroy()
	self.Model:Destroy()
end

return Luni
