-- El Gerente (jefe de la noche 10): un hombre de traje con un walkie. Patrulla y, si ve
-- a alguien, lo MARCA (contorno rojo y aviso) y lo persigue. Lo que hace con el walkie
-- (pedir refuerzos, cerrar persianas) y como se le vence (destruir sus radios) lo lleva
-- su modulo de jefe (server/Bosses/Manager); aqui solo esta su cuerpo.
--
-- Contramedidas: esconderse; el destello, el taser y los empujones lo frenan un momento.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local ServerScriptService = game:GetService("ServerScriptService")

local Server = ServerScriptService:WaitForChild("Server")
local DefenseService = require(Server:WaitForChild("DefenseService"))

local Common = require(script.Parent.Common)

local HEIGHT = 6.6
local SUIT = Color3.fromRGB(38, 40, 48)
local SHIRT = Color3.fromRGB(230, 230, 228)
local SKIN = Color3.fromRGB(205, 175, 150)
local MARK = Color3.fromRGB(255, 60, 50)

local Manager = {}
Manager.__index = Manager

local function buildModel(): Model
	local model, _root = Common.newModel("Manager", HEIGHT)
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
		local p = add(name, size, cf, color, material or Enum.Material.SmoothPlastic, shape)
		if follow then
			p:SetAttribute("Follow", follow)
		else
			p:SetAttribute("Detail", true)
		end
		return p
	end
	local SHOE = Color3.fromRGB(20, 18, 16)
	local GOLD = Color3.fromRGB(210, 170, 70)
	local DARK = Color3.fromRGB(18, 18, 20)
	local HAIR = Color3.fromRGB(30, 25, 22)

	add("LeftLeg", Vector3.new(0.8, 2.8, 0.8), CFrame.new(-0.45, -1.9, 0), SUIT)
	add("RightLeg", Vector3.new(0.8, 2.8, 0.8), CFrame.new(0.45, -1.9, 0), SUIT)
	-- Zapatos de cuero brillante, uno en cada pie (siguen a la pierna)
	for _, x in { -0.45, 0.45 } do
		add("Shoe", Vector3.new(0.85, 0.3, 1.15), CFrame.new(x, -3.15, -0.12), SHOE, Enum.Material.Leather).Reflectance = 0.15
		detail("Crease", Vector3.new(0.05, 2.4, 0.03), CFrame.new(x, -1.75, -0.41), Color3.fromRGB(28, 30, 36), nil, nil, if x < 0 then "LeftLeg" else "RightLeg")
	end
	add("Jacket", Vector3.new(2.1, 2.6, 1.05), CFrame.new(0, 0.8, 0), SUIT)
	add("Shirt", Vector3.new(0.6, 2.2, 0.05), CFrame.new(0, 1, -0.53), SHIRT, Enum.Material.SmoothPlastic)
	add("Tie", Vector3.new(0.25, 1.8, 0.06), CFrame.new(0, 0.95, -0.56), Color3.fromRGB(170, 20, 25), Enum.Material.SmoothPlastic)
	-- Traje: solapas, cuello de camisa, nudo y pasador de la corbata, botones y bolsillo
	for _, side in { -1, 1 } do
		detail("Lapel", Vector3.new(0.38, 1.3, 0.06), CFrame.new(side * 0.38, 1.45, -0.55) * CFrame.Angles(0, 0, side * math.rad(-16)), Color3.fromRGB(30, 32, 40), Enum.Material.Fabric)
		detail("Collar", Vector3.new(0.3, 0.22, 0.06), CFrame.new(side * 0.17, 2.0, -0.56) * CFrame.Angles(0, 0, side * math.rad(35)), SHIRT)
	end
	detail("TieKnot", Vector3.new(0.3, 0.24, 0.1), CFrame.new(0, 1.92, -0.58), Color3.fromRGB(140, 15, 20))
	detail("TieClip", Vector3.new(0.34, 0.05, 0.04), CFrame.new(0, 0.95, -0.6), GOLD, Enum.Material.Metal)
	for _, y in { 0.45, 0.05 } do
		detail("Button", Vector3.new(0.13, 0.13, 0.13), CFrame.new(0.2, y, -0.53), DARK, nil, Enum.PartType.Ball)
	end
	detail("Pocket", Vector3.new(0.5, 0.08, 0.06), CFrame.new(-0.6, 1.4, -0.55), Color3.fromRGB(28, 30, 38), Enum.Material.Fabric)
	detail("PocketSquare", Vector3.new(0.3, 0.16, 0.05), CFrame.new(-0.6, 1.5, -0.55) * CFrame.Angles(0, 0, math.rad(10)), SHIRT)
	-- Placa con su cargo
	local badge = detail("Badge", Vector3.new(0.55, 0.2, 0.04), CFrame.new(0.6, 1.4, -0.55), GOLD, Enum.Material.Metal)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.CanvasSize = Vector2.new(110, 40)
	gui.LightInfluence = 0.6
	gui.Parent = badge
	local tag = Instance.new("TextLabel")
	tag.Size = UDim2.fromScale(1, 1)
	tag.BackgroundTransparency = 1
	tag.Font = Enum.Font.GothamBlack
	tag.TextScaled = true
	tag.TextColor3 = Color3.fromRGB(40, 30, 10)
	tag.Text = "GERENTE"
	tag.Parent = gui
	-- Cinturon con hebilla y un manojo de llaves (las de todas las persianas)
	detail("Belt", Vector3.new(2.12, 0.18, 1.07), CFrame.new(0, -0.4, 0), DARK, Enum.Material.Leather)
	detail("Buckle", Vector3.new(0.3, 0.22, 0.05), CFrame.new(0, -0.4, -0.55), Color3.fromRGB(200, 200, 205), Enum.Material.Metal)
	detail("KeyRing", Vector3.new(0.05, 0.28, 0.28), CFrame.new(-1.08, -0.6, -0.2), GOLD, Enum.Material.Metal, Enum.PartType.Cylinder)
	for i = -1, 1 do
		detail("Key", Vector3.new(0.06, 0.32, 0.1), CFrame.new(-1.09, -0.85, -0.2 + i * 0.1) * CFrame.Angles(math.rad(i * 18), 0, 0), GOLD, Enum.Material.Metal)
	end
	add("LeftArm", Vector3.new(0.65, 2.5, 0.65), CFrame.new(-1.4, 0.6, 0), SUIT)
	-- Brazo derecho doblado: el walkie junto a la cara
	add("RightArm", Vector3.new(0.65, 2.3, 0.65), CFrame.new(1.25, 1.3, -0.4) * CFrame.Angles(math.rad(-50), 0, math.rad(15)), SUIT)
	-- Puños de camisa, gemelos y manos
	detail("ShirtCuff", Vector3.new(0.68, 0.22, 0.68), CFrame.new(-1.4, -0.58, 0), SHIRT, nil, nil, "LeftArm")
	detail("Cufflink", Vector3.new(0.08, 0.08, 0.08), CFrame.new(-1.75, -0.58, 0), GOLD, Enum.Material.Metal, nil, "LeftArm")
	add("Hand", Vector3.new(0.45, 0.55, 0.45), CFrame.new(-1.4, -0.95, 0), SKIN, Enum.Material.SmoothPlastic)
	add("Hand", Vector3.new(0.4, 0.5, 0.4), CFrame.new(0.95, 2.3, -0.62), SKIN, Enum.Material.SmoothPlastic)
	-- Cabeza: orejas, nariz, cejas fruncidas, ojeras, boca torcida y gafas
	add("Head", Vector3.new(1.1, 1.25, 1.1), CFrame.new(0, 2.75, 0), SKIN, Enum.Material.SmoothPlastic)
	add("Hair", Vector3.new(1.15, 0.35, 1.15), CFrame.new(0, 3.3, 0.05), HAIR, Enum.Material.SmoothPlastic)
	detail("HairBack", Vector3.new(1.15, 0.7, 0.3), CFrame.new(0, 2.95, 0.45), HAIR)
	detail("HairPart", Vector3.new(0.5, 0.15, 0.9), CFrame.new(0.3, 3.18, -0.05) * CFrame.Angles(0, 0, math.rad(-12)), HAIR)
	for _, side in { -1, 1 } do
		detail("Ear", Vector3.new(0.14, 0.35, 0.25), CFrame.new(side * 0.6, 2.75, 0.05), SKIN)
		detail("Sideburn", Vector3.new(0.06, 0.35, 0.2), CFrame.new(side * 0.56, 2.95, 0.1), HAIR)
		detail("Brow", Vector3.new(0.3, 0.07, 0.05), CFrame.new(side * 0.22, 3.02, -0.57) * CFrame.Angles(0, 0, side * math.rad(-18)), HAIR)
		detail("EyeBag", Vector3.new(0.22, 0.05, 0.03), CFrame.new(side * 0.22, 2.74, -0.56), Color3.fromRGB(150, 110, 100))
		-- Montura de las gafas (arriba y abajo de cada cristal) y patilla hasta la oreja
		detail("GlassesRim", Vector3.new(0.36, 0.05, 0.04), CFrame.new(side * 0.22, 2.97, -0.6), DARK)
		detail("GlassesRim", Vector3.new(0.36, 0.04, 0.04), CFrame.new(side * 0.22, 2.73, -0.6), DARK)
		detail("GlassesRim", Vector3.new(0.04, 0.24, 0.04), CFrame.new(side * 0.4, 2.85, -0.6), DARK)
		detail("Lens", Vector3.new(0.32, 0.2, 0.02), CFrame.new(side * 0.22, 2.85, -0.6), Color3.fromRGB(200, 220, 230), Enum.Material.Glass).Transparency = 0.6
		detail("GlassesArm", Vector3.new(0.03, 0.03, 0.62), CFrame.new(side * 0.58, 2.93, -0.3), DARK)
	end
	detail("GlassesBridge", Vector3.new(0.1, 0.04, 0.04), CFrame.new(0, 2.92, -0.6), DARK)
	detail("Nose", Vector3.new(0.18, 0.28, 0.16), CFrame.new(0, 2.66, -0.6), SKIN)
	detail("Mouth", Vector3.new(0.38, 0.05, 0.03), CFrame.new(0.04, 2.38, -0.56) * CFrame.Angles(0, 0, math.rad(-6)), Color3.fromRGB(110, 50, 45))
	-- Auricular con su cable en la oreja izquierda
	detail("Earpiece", Vector3.new(0.12, 0.12, 0.12), CFrame.new(-0.66, 2.72, -0.05), DARK, nil, Enum.PartType.Ball)
	detail("EarCord", Vector3.new(0.035, 0.75, 0.035), CFrame.new(-0.62, 2.3, 0.05) * CFrame.Angles(0, 0, math.rad(-8)), Color3.fromRGB(200, 200, 200))
	for _, x in { -0.22, 0.22 } do
		add("Eye", Vector3.new(0.18, 0.08, 0.05), CFrame.new(x, 2.85, -0.56), Color3.fromRGB(255, 230, 200), Enum.Material.Neon)
	end
	add("Walkie", Vector3.new(0.35, 0.8, 0.25), CFrame.new(0.85, 2.6, -0.55), Color3.fromRGB(25, 25, 25), Enum.Material.SmoothPlastic)
	detail("WalkieAntenna", Vector3.new(0.07, 0.3, 0.07), CFrame.new(0.95, 3.12, -0.55), DARK, nil, nil, "Walkie")
	for i = 0, 2 do
		detail("WalkieGrill", Vector3.new(0.22, 0.03, 0.03), CFrame.new(0.85, 2.45 + i * 0.08, -0.68), Color3.fromRGB(70, 70, 75), nil, nil, "Walkie")
	end
	local led = add("WalkieLed", Vector3.new(0.12, 0.12, 0.12), CFrame.new(0.85, 3.05, -0.55), Color3.fromRGB(255, 40, 30), Enum.Material.Neon)
	local light = Instance.new("PointLight")
	light.Name = "WalkieLight"
	light.Color = Color3.fromRGB(255, 50, 40)
	light.Range = 6
	light.Brightness = 0.8
	light.Parent = led
	return model
end

function Manager.new(spawnPosition: Vector3, ctx)
	local def = Config.Enemies.Manager
	local model = Common.getTemplate("Manager") or buildModel()
	local height = Common.getHeight(model)
	Common.prepareModel(model)
	model:PivotTo(CFrame.new(spawnPosition + Vector3.new(0, height / 2, 0)))
	model.Parent = ctx.Container

	local self = setmetatable({}, Manager)
	self.Def = def
	self.Ctx = ctx
	self.Model = model
	self.Height = height
	self.Mover = Common.newMover(model, { Speed = def.Speed, Height = height, AgentHeight = 6 })
	self.Awareness = Common.newAwareness(ctx)
	self.Marked = nil :: Player?
	self.LastAttack = 0
	self.PatrolPoint = nil
	self.NextRetarget = 0
	self.Led = model:FindFirstChild("WalkieLed", true) :: BasePart?
	return self
end

function Manager:SpeedMultiplier(): number
	-- BossSpeed: refuerzo del jefe desde la noche 25 (lo pone su modulo de jefe)
	return (self.BossSpeed or 1)
		* self.Ctx.Difficulty.SpeedMultiplier
		* (1 + Config.Threat.SpeedPerFailedMission * self.Ctx.GetTotalThreat())
end

-- Habla por el walkie (lo usa su modulo de jefe): el led parpadea.
function Manager:Radio(seconds: number)
	local led = self.Led
	if not led then
		return
	end
	task.spawn(function()
		local untilAt = os.clock() + seconds
		while os.clock() < untilAt and led.Parent do
			led.Transparency = if led.Transparency == 0 then 0.8 else 0
			task.wait(0.15)
		end
		if led.Parent then
			led.Transparency = 0
		end
	end)
end

local function setMark(player: Player, on: boolean)
	local character = player.Character
	local mark = character and character:FindFirstChild("ManagerMark")
	if on and character and not mark then
		local h = Instance.new("Highlight")
		h.Name = "ManagerMark"
		h.FillTransparency = 1
		h.OutlineColor = MARK
		h.OutlineTransparency = 0.2
		h.DepthMode = Enum.HighlightDepthMode.Occluded
		h.Parent = character
	elseif not on and mark then
		mark:Destroy()
	end
end

function Manager:SetMarked(player: Player?)
	if self.Marked == player then
		return
	end
	if self.Marked then
		setMark(self.Marked, false)
	end
	self.Marked = player
	if player then
		setMark(player, true)
		Remotes.event("Notify"):FireClient(player, "¡El Gerente te ha visto! Te persigue: escóndete o despístalo.", "bad")
	end
end

function Manager:Walk(dt: number, goal: Vector3, speed: number, retarget: number)
	local now = os.clock()
	if now >= self.NextRetarget or not self.Mover:HasPath() then
		self.Mover:MoveTowards(goal)
		self.NextRetarget = now + retarget
	end
	self.Mover.Speed = speed
	self.Mover:Step(dt)
end

function Manager:Update(dt: number)
	local now = os.clock()
	if Common.isStunned(self.Model) then
		self.Mover:Clear()
		return
	end
	local pos = self.Model:GetPivot().Position
	local eye = pos + Vector3.new(0, self.Height * 0.35, 0)
	local target, _root, dist, targetPos = self.Awareness:Update(dt, pos, function(_player, r)
		return Common.canSee(eye, r)
	end)
	local mul = self:SpeedMultiplier()

	if target and targetPos then
		self:SetMarked(target)
		self.PatrolPoint = nil
		self:Walk(dt, targetPos, self.Def.ChaseSpeed * mul, 0.3)
		if dist <= self.Def.AttackRange + 1 and now - self.LastAttack >= self.Def.AttackCooldown then
			self.LastAttack = now
			Common.damage(target, self.Def.Damage)
		end
		return
	end
	self:SetMarked(nil)

	-- Un petardo lo distrae
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

function Manager:Stun(seconds: number)
	self.Mover:Clear()
	DefenseService.Stun(self.Model, seconds)
end

function Manager:OnFlash(_player: Player)
	self:Stun(self.Def.StunSeconds)
end

function Manager:OnTaser(_player: Player)
	self:Stun(self.Def.StunSeconds)
end

function Manager:OnShove(_player: Player, direction: Vector3, strength: { StunSeconds: number, Distance: number }?)
	local s = strength or Config.Defense.Shove
	self:Stun(math.min(s.StunSeconds, self.Def.StunSeconds))
	Common.knockback(self.Model, direction, s.Distance * 0.5)
end

function Manager:Destroy()
	self:SetMarked(nil)
	self.Mover:Destroy()
	self.Model:Destroy()
end

return Manager
