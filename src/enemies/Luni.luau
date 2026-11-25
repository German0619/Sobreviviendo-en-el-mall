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
	-- Cabeza: una luna llena
	add("Head", Vector3.new(4.6, 4.6, 4.6), at(0, 8.2, 0), MOON, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	-- Cara: ojos enormes y sonrisa
	for _, x in { -0.75, 0.75 } do
		add("EyeWhite", Vector3.new(1.05, 1.05, 1.05), at(x, 8.7, -1.95), Color3.fromRGB(250, 250, 250), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
		add("Pupil", Vector3.new(0.45, 0.45, 0.45), at(x, 8.65, -2.42), Color3.fromRGB(255, 60, 40), Enum.Material.Neon, Enum.PartType.Ball)
	end
	add("Smile", Vector3.new(1.8, 0.18, 0.15), at(0, 7.35, -2.2), Color3.fromRGB(30, 20, 30), Enum.Material.SmoothPlastic)
	for _, side in { -1, 1 } do
		add("SmileEnd", Vector3.new(0.5, 0.18, 0.15), at(side * 1.05, 7.5, -2.15) * CFrame.Angles(0, 0, side * math.rad(30)), Color3.fromRGB(30, 20, 30), Enum.Material.SmoothPlastic)
	end

	-- Detalles soldados (Common.prepareModel): a la raiz o, con `follow`, a esa extremidad
	local function detail(name, size, cf: CFrame, color: Color3, material, shape, follow: string?)
		local p = add(name, size, cf, color, material or Enum.Material.SmoothPlastic, shape)
		if follow then
			p:SetAttribute("Follow", follow)
		else
			p:SetAttribute("Detail", true)
		end
		return p
	end
	-- Pegado a la superficie de la cabeza (x, y desde los pies), mirando hacia fuera
	local HEAD_Y, HEAD_R = 8.2, 2.3
	local function onHead(name, x: number, y: number, size: Vector3, color: Color3, roll: number?, material)
		local dy = y - HEAD_Y
		local z = -math.sqrt(math.max(HEAD_R ^ 2 - x ^ 2 - dy ^ 2, 0.01))
		local pos = Vector3.new(x, dy, z * 0.98)
		local cf = CFrame.lookAt(pos, pos * 2) * CFrame.Angles(0, 0, math.rad(roll or 0))
		return detail(name, size, at(0, HEAD_Y, 0) * cf, color, material)
	end
	local WHITE = Color3.fromRGB(245, 245, 250)
	local STAR = Color3.fromRGB(255, 215, 80)
	local INK = Color3.fromRGB(30, 20, 30)
	local CAP = Color3.fromRGB(70, 80, 170)
	-- Estrella de 8 puntas (dos cuadrados girados) en `cf`
	local function star(cf: CFrame, s: number, follow: string?)
		detail("Star", Vector3.new(s, s, 0.06), cf, STAR, Enum.Material.Fabric, nil, follow)
		detail("Star", Vector3.new(s, s, 0.06), cf * CFrame.Angles(0, 0, math.rad(45)), STAR, Enum.Material.Fabric, nil, follow)
	end

	-- Cara de luna: crateres, cejas, brillo en los ojos y la boca abierta con dientes
	local craters = {
		{ -1.3, 9.4, 0.55 },
		{ -1.55, 8.0, 0.4 },
		{ -0.95, 6.8, 0.3 },
		{ -0.2, 10.05, 0.32 },
		{ 1.35, 9.35, 0.48 },
		{ 1.6, 7.85, 0.38 },
		{ 1.0, 6.75, 0.26 },
		{ 0.55, 10.0, 0.25 },
	}
	for _, c in craters do
		-- (disco: cilindro con el eje hacia fuera de la cabeza)
		local crater = onHead("Crater", c[1], c[2], Vector3.new(0.1, c[3], c[3]), Color3.fromRGB(225, 195, 110))
		crater.Shape = Enum.PartType.Cylinder
		crater.CFrame *= CFrame.Angles(0, math.rad(90), 0)
	end
	for _, eye in { { -0.75, -18 }, { 0.75, 18 } } do
		onHead("Brow", eye[1], 9.45, Vector3.new(0.75, 0.16, 0.12), INK, eye[2])
		detail("Shine", Vector3.new(0.14, 0.14, 0.14), at(eye[1] - 0.1, 8.78, -2.62), WHITE, nil, Enum.PartType.Ball)
	end
	detail("MouthOpen", Vector3.new(1.6, 0.42, 0.1), at(0, 7.15, -2.12), Color3.fromRGB(70, 15, 30))
	for i = 0, 5 do
		detail("Tooth", Vector3.new(0.22, 0.2, 0.08), at(-0.725 + i * 0.29, 7.24, -2.19), WHITE)
	end
	detail("Tongue", Vector3.new(0.6, 0.15, 0.08), at(0.15, 7.0, -2.17), Color3.fromRGB(220, 90, 110))

	-- Gorro de dormir caido hacia un lado, con borde blanco, estrellas y pompon
	detail("CapTrim", Vector3.new(0.55, 3.6, 3.6), at(-0.2, 9.95, 0.2) * CFrame.Angles(0, 0, math.rad(90 - 12)), WHITE, Enum.Material.Fabric, Enum.PartType.Cylinder)
	local capParts = { { -0.05, 10.45, 3.2, 0.9 }, { 0.4, 11.05, 2.5, 0.8 }, { 1.0, 11.5, 1.8, 0.7 }, { 1.65, 11.6, 1.1, 0.6 } }
	for i, c in capParts do
		detail("Cap", Vector3.new(c[4], c[3], c[3]), at(c[1], c[2], 0.2) * CFrame.Angles(0, 0, math.rad(90 - 12 - i * 22)), CAP, Enum.Material.Fabric, Enum.PartType.Cylinder)
	end
	detail("CapEnd", Vector3.new(0.6, 0.7, 0.7), at(2.15, 11.4, 0.2) * CFrame.Angles(0, 0, math.rad(-20)), CAP, Enum.Material.Fabric, Enum.PartType.Cylinder)
	detail("PomPom", Vector3.new(0.9, 0.9, 0.9), at(2.45, 11.1, 0.2), WHITE, Enum.Material.Fabric, Enum.PartType.Ball)
	star(at(-0.3, 10.6, -1.42) * CFrame.Angles(math.rad(-20), 0, 0), 0.45)
	star(at(0.6, 11.15, -1.05) * CFrame.Angles(math.rad(-20), 0, 0), 0.32)

	-- Gorguera de peluche en el cuello
	for i = 0, 11 do
		local a = i / 12 * math.pi * 2
		detail("Ruff", Vector3.new(0.85, 0.85, 0.85), at(math.cos(a) * 1.35, 6.05, math.sin(a) * 1.0), WHITE, Enum.Material.Fabric, Enum.PartType.Ball)
	end
	-- Barriga con su nombre y estrellas bordadas; cremallera del disfraz en la espalda
	local belly = model:FindFirstChild("Belly") :: BasePart
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.CanvasSize = Vector2.new(220, 240)
	gui.LightInfluence = 1
	gui.Parent = belly
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 0.45)
	label.Position = UDim2.fromScale(0, 0.08)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(90, 70, 170)
	label.Text = "LUNI"
	label.Parent = gui
	star(at(-0.5, 3.6, -1.48), 0.45)
	star(at(0.5, 3.35, -1.48), 0.35)
	star(at(0.05, 3.05, -1.48), 0.28)
	for _, side in { -1, 1 } do
		star(at(side * 1.72, 4.6, -0.4) * CFrame.Angles(0, side * math.rad(-90), 0), 0.5)
	end
	detail("Zipper", Vector3.new(0.08, 3.4, 0.06), at(0, 4.3, 1.31), Color3.fromRGB(190, 190, 200), Enum.Material.Metal)
	detail("ZipperTab", Vector3.new(0.18, 0.35, 0.06), at(0, 5.85, 1.35), Color3.fromRGB(190, 190, 200), Enum.Material.Metal)
	-- Guantes de dibujo animado: puño, tres dedos y pulgar (siguen al brazo)
	for _, side in { -1, 1 } do
		detail("GloveCuff", Vector3.new(0.4, 1.35, 1.35), at(side * 2.55, 3.35, 0) * CFrame.Angles(0, 0, side * math.rad(18) + math.rad(90)), WHITE, nil, Enum.PartType.Cylinder, "Arm")
		for i = -1, 1 do
			detail("GloveFinger", Vector3.new(0.5, 0.5, 0.5), at(side * 2.75 + i * 0.33, 2.1, -0.25), WHITE, nil, Enum.PartType.Ball, "Arm")
		end
		detail("GloveThumb", Vector3.new(0.45, 0.45, 0.45), at(side * 2.25, 2.85, -0.5), WHITE, nil, Enum.PartType.Ball, "Arm")
	end
	-- Zapatones: suela, puntera redonda y cordones (siguen a la pierna)
	for _, x in { -0.75, 0.75 } do
		detail("Sole", Vector3.new(1.7, 0.2, 2.1), at(x, 0.1, -0.3), Color3.fromRGB(60, 60, 75), nil, nil, "Leg")
		detail("ToeCap", Vector3.new(1.2, 1.2, 1.2), at(x, 0.6, -1.1), WHITE, nil, Enum.PartType.Ball, "Leg")
		for i = 0, 1 do
			detail("Lace", Vector3.new(0.9, 0.08, 0.1), at(x, 0.72, -0.05 - i * 0.35), Color3.fromRGB(240, 90, 120), nil, nil, "Leg")
		end
		star(at(x, 1.9, -0.67), 0.4, "Leg")
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
	-- BossSpeed: refuerzo del jefe desde la noche 25 (lo pone su modulo de jefe)
	return slow
		* (self.BossSpeed or 1)
		* self.Ctx.Difficulty.SpeedMultiplier
		* (1 + Config.Threat.SpeedPerFailedMission * self.Ctx.GetTotalThreat())
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
					Common.playAttack(self.Model)
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
	self.Eyes = {} -- (para PowerUp)
	for _, d in self.Model:GetDescendants() do
		if d:IsA("BasePart") and d.Name == "Pupil" then
			table.insert(self.Eyes, { Part = d, Color = d.Color, Material = d.Material })
			d.Color = Color3.fromRGB(20, 20, 20)
			d.Material = Enum.Material.SmoothPlastic
		elseif d:IsA("PointLight") then
			d.Enabled = false
		end
	end
	local pivot = self.Model:GetPivot()
	self.StandPivot = pivot
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

-- Recupera la energia tras un apagon (desde la noche 25 hay que apagarla varias veces).
function Luni:PowerUp()
	if self.Powered or not self.Model.Parent then
		return
	end
	for _, eye in self.Eyes or {} do
		eye.Part.Color = eye.Color
		eye.Part.Material = eye.Material
	end
	for _, d in self.Model:GetDescendants() do
		if d:IsA("PointLight") then
			d.Enabled = true
		end
	end
	if self.StandPivot then
		self.Model:PivotTo(self.StandPivot)
	end
	self.Powered = true
	if self.Steps then
		self.Steps:Play()
	end
end

function Luni:GetPosition(): Vector3
	return self.Model:GetPivot().Position
end

function Luni:Destroy()
	self.Mover:Destroy()
	self.Model:Destroy()
end

return Luni
