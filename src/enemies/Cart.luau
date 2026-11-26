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
		-- Todo va soldado a la raiz salvo las ruedas, que giran (EnemyAnimator); el buje y
		-- el radio van soldados a su rueda (Follow)
		if name ~= "Wheel" and p:GetAttribute("Follow") == nil then
			p:SetAttribute("Detail", true)
		end
		p.Parent = model
		return p
	end
	-- Barra de a hasta b
	local function beam(name: string, a: Vector3, b: Vector3, thickness: number, props)
		return add(name, Vector3.new(thickness, thickness, (b - a).Magnitude), CFrame.lookAt((a + b) / 2, b), props)
	end
	local RUST = { Material = Enum.Material.CorrodedMetal, Color = Color3.fromRGB(150, 110, 80) }
	local RED = Color3.fromRGB(200, 40, 40)

	-- Cesta de rejilla: fondo, paneles casi transparentes y barras (se ve "hueca")
	local basketY = 0.3
	local top, low = basketY + 0.8, basketY - 0.8
	add("Bottom", Vector3.new(2.4, 0.12, 3.4), CFrame.new(0, low, 0), { Transparency = 0.25, Material = Enum.Material.DiamondPlate })
	add("Left", Vector3.new(0.05, 1.6, 3.4), CFrame.new(-1.2, basketY, 0), { Transparency = 0.8 })
	add("Right", Vector3.new(0.05, 1.6, 3.4), CFrame.new(1.2, basketY, 0), { Transparency = 0.8 })
	add("Front", Vector3.new(2.4, 1.6, 0.05), CFrame.new(0, basketY, -1.7), { Transparency = 0.8 })
	add("Back", Vector3.new(2.4, 1.6, 0.05), CFrame.new(0, basketY, 1.7), { Transparency = 0.8 })
	-- Raíles: borde de arriba, uno a media altura y el de abajo
	for _, y in { top, basketY, low + 0.05 } do
		local t = if y == top then 0.14 else 0.07
		for _, x in { -1.2, 1.2 } do
			add("Rail", Vector3.new(t, t, 3.5), CFrame.new(x, y, 0), if y == basketY and x > 0 then RUST else nil)
		end
		for _, z in { -1.72, 1.72 } do
			add("Rail", Vector3.new(2.5, t, t), CFrame.new(0, y, z))
		end
	end
	-- Barras verticales de la rejilla
	for i = 0, 8 do
		local z = -1.5 + i * 0.375
		for _, x in { -1.2, 1.2 } do
			add("Bar", Vector3.new(0.05, 1.6, 0.05), CFrame.new(x, basketY, z), if (i + (if x > 0 then 1 else 0)) % 5 == 0 then RUST else nil)
		end
	end
	for i = 0, 6 do
		local x = -1.0 + i * (2 / 6)
		for _, z in { -1.72, 1.72 } do
			add("Bar", Vector3.new(0.05, 1.6, 0.05), CFrame.new(x, basketY, z))
		end
	end
	-- Esquinas mas gruesas
	for _, x in { -1.2, 1.2 } do
		for _, z in { -1.72, 1.72 } do
			add("Post", Vector3.new(0.12, 1.7, 0.12), CFrame.new(x, basketY, z))
		end
	end
	-- Asiento de niño plegado contra la pared de atras (plastico rojo)
	add("ChildSeat", Vector3.new(2.1, 1.1, 0.06), CFrame.new(0, basketY + 0.2, 1.55) * CFrame.Angles(math.rad(-12), 0, 0), {
		Color = RED,
		Material = Enum.Material.SmoothPlastic,
		Transparency = 0.15,
	})
	-- Asa: dos brazos desde el borde de atras y la barra roja con su placa
	for _, x in { -1.2, 1.2 } do
		beam("HandleArm", Vector3.new(x, top, 1.72), Vector3.new(x * 1.05, top + 0.3, 2.1), 0.1)
	end
	add("Handle", Vector3.new(2.6, 0.2, 0.2), CFrame.new(0, top + 0.3, 2.1), { Color = RED, Material = Enum.Material.SmoothPlastic })
	local plate = add("AdPlate", Vector3.new(1.2, 0.32, 0.04), CFrame.new(0, top + 0.12, 2.0) * CFrame.Angles(math.rad(-20), 0, 0), {
		Color = Color3.fromRGB(240, 240, 235),
		Material = Enum.Material.SmoothPlastic,
	})
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back -- mira hacia atras (hacia quien empuja)
	gui.CanvasSize = Vector2.new(240, 64)
	gui.LightInfluence = 1
	gui.Parent = plate
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.GothamBlack
	text.TextScaled = true
	text.TextColor3 = RED
	text.Text = "PLAZA LUNA"
	text.Parent = gui
	-- Chasis: dos largueros, la bandeja de abajo y los soportes de las ruedas
	for _, x in { -0.9, 0.9 } do
		add("Frame", Vector3.new(0.12, 0.12, 3.6), CFrame.new(x, -1.0, 0.1))
	end
	add("Tray", Vector3.new(2.0, 0.06, 2.6), CFrame.new(0, -1.05, 0.3), { Transparency = 0.3, Material = Enum.Material.DiamondPlate })
	for _, x in { -1, 1 } do
		for _, z in { -1.4, 1.4 } do
			add("Leg", Vector3.new(0.12, 0.8, 0.12), CFrame.new(x, -0.9, z))
			add("Caster", Vector3.new(0.4, 0.1, 0.36), CFrame.new(x, -1.3, z), { Color = Color3.fromRGB(110, 115, 120) })
			for _, side in { -1, 1 } do
				add("Fork", Vector3.new(0.04, 0.32, 0.28), CFrame.new(x + side * 0.19, -1.47, z), { Color = Color3.fromRGB(110, 115, 120) })
			end
			add("Wheel", Vector3.new(0.3, 0.45, 0.45), CFrame.new(x, -1.55, z), {
				Shape = Enum.PartType.Cylinder,
				Color = Color3.fromRGB(30, 30, 30),
				Material = Enum.Material.SmoothPlastic,
			})
			-- Buje y radio (giran con la rueda)
			local hub = add("Hub", Vector3.new(0.32, 0.2, 0.2), CFrame.new(x, -1.55, z), {
				Shape = Enum.PartType.Cylinder,
				Color = Color3.fromRGB(200, 200, 205),
			})
			hub:SetAttribute("Follow", "Wheel")
			local spoke = add("Spoke", Vector3.new(0.31, 0.4, 0.07), CFrame.new(x, -1.55, z), { Color = Color3.fromRGB(200, 200, 205) })
			spoke:SetAttribute("Follow", "Wheel")
		end
	end
	-- Compras abandonadas al fondo de la cesta
	add("Cereal", Vector3.new(0.7, 1.0, 0.25), CFrame.new(-0.5, low + 0.55, 0.9) * CFrame.Angles(math.rad(-15), math.rad(20), 0), {
		Color = Color3.fromRGB(240, 190, 40),
		Material = Enum.Material.SmoothPlastic,
	})
	add("Milk", Vector3.new(0.75, 0.4, 0.4), CFrame.new(0.55, low + 0.42, 0.7) * CFrame.Angles(0, 0, math.rad(90)), {
		Shape = Enum.PartType.Cylinder,
		Color = Color3.fromRGB(245, 245, 245),
		Material = Enum.Material.SmoothPlastic,
	})
	add("MilkCap", Vector3.new(0.12, 0.2, 0.2), CFrame.new(0.55, low + 0.86, 0.7) * CFrame.Angles(0, 0, math.rad(90)), {
		Shape = Enum.PartType.Cylinder,
		Color = Color3.fromRGB(40, 110, 220),
		Material = Enum.Material.SmoothPlastic,
	})
	add("Can", Vector3.new(0.45, 0.3, 0.3), CFrame.new(0.1, low + 0.2, 1.3) * CFrame.Angles(0, math.rad(70), 0), {
		Shape = Enum.PartType.Cylinder,
		Color = Color3.fromRGB(180, 30, 40),
	})
	-- "Cara" fantasma dentro de la cesta: ojos y una boca dentada; lo delatan a oscuras
	for _, x in { -0.4, 0.4 } do
		add("Eye", Vector3.new(0.3, 0.3, 0.1), CFrame.new(x, basketY + 0.2, -1.6), {
			Color = GHOST_COLOR,
			Material = Enum.Material.Neon,
		})
	end
	for i = -2, 2 do
		add("Mouth", Vector3.new(0.14, 0.14, 0.06), CFrame.new(i * 0.16, basketY - 0.25 + (i % 2) * 0.07, -1.6) * CFrame.Angles(0, 0, math.rad(45)), {
			Color = GHOST_COLOR,
			Material = Enum.Material.Neon,
			Transparency = 0.2,
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

-- Version con el carrito 3D realista (ServerStorage.PropTemplates.ShoppingCart, el mismo de
-- los carritos del mapa) y la cara fantasma dentro de la cesta. nil si no hay plantilla.
-- La malla mide 3.6 de alto (= HEIGHT): base en -HEIGHT/2, cesta de y 0 a 1.1, frente en -Z
-- y asa en +Z.
local function buildMeshModel(): Model?
	local folder = game:GetService("ServerStorage"):FindFirstChild("PropTemplates")
	local template = folder and folder:FindFirstChild("ShoppingCart")
	if not template or not template:IsA("Model") then
		return nil
	end
	local model, _root = Common.newModel("Cart", HEIGHT)
	local cart = template:Clone()
	cart:PivotTo(CFrame.new(0, -HEIGHT / 2, 0))
	for _, d in cart:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d:SetAttribute("Detail", true)
			d.Parent = model
		end
	end
	cart:Destroy()

	local function add(name, size, offset: CFrame, props)
		local p = Common.part({
			Name = name,
			Size = size,
			CFrame = offset,
			Material = Enum.Material.SmoothPlastic,
			Color = Color3.new(1, 1, 1),
		})
		for k, v in props do
			p[k] = v
		end
		p:SetAttribute("Detail", true)
		p.Parent = model
		return p
	end
	local floor = 0.05 -- fondo de la cesta
	-- Pieza invisible del fondo: lleva el brillo y las particulas
	local bottom = add("Bottom", Vector3.new(1.6, 0.1, 2.2), CFrame.new(0, floor, -0.3), { Transparency = 1 })
	-- Compras abandonadas
	add("Cereal", Vector3.new(0.7, 1.0, 0.25), CFrame.new(-0.45, floor + 0.5, 0.5) * CFrame.Angles(math.rad(-15), math.rad(20), 0), {
		Color = Color3.fromRGB(240, 190, 40),
	})
	add("Milk", Vector3.new(0.75, 0.4, 0.4), CFrame.new(0.5, floor + 0.38, 0.3) * CFrame.Angles(0, 0, math.rad(90)), {
		Shape = Enum.PartType.Cylinder,
		Color = Color3.fromRGB(245, 245, 245),
	})
	add("MilkCap", Vector3.new(0.12, 0.2, 0.2), CFrame.new(0.5, floor + 0.82, 0.3) * CFrame.Angles(0, 0, math.rad(90)), {
		Shape = Enum.PartType.Cylinder,
		Color = Color3.fromRGB(40, 110, 220),
	})
	add("Can", Vector3.new(0.45, 0.3, 0.3), CFrame.new(0.05, floor + 0.17, 0.85) * CFrame.Angles(0, math.rad(70), 0), {
		Shape = Enum.PartType.Cylinder,
		Color = Color3.fromRGB(180, 30, 40),
		Material = Enum.Material.Metal,
	})
	-- "Cara" fantasma en el frente de la cesta: ojos y boca dentada; lo delatan a oscuras
	for _, x in { -0.38, 0.38 } do
		add("Eye", Vector3.new(0.28, 0.28, 0.08), CFrame.new(x, 0.78, -1.45), { Color = GHOST_COLOR, Material = Enum.Material.Neon })
	end
	for i = -2, 2 do
		add("Mouth", Vector3.new(0.13, 0.13, 0.06), CFrame.new(i * 0.15, 0.36 + (i % 2) * 0.07, -1.45) * CFrame.Angles(0, 0, math.rad(45)), {
			Color = GHOST_COLOR,
			Material = Enum.Material.Neon,
			Transparency = 0.2,
		})
	end
	local glow = Instance.new("PointLight")
	glow.Color = GHOST_COLOR
	glow.Range = 7
	glow.Brightness = 0.7
	glow.Parent = bottom

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
	wisps.Parent = bottom
	return model
end

function Cart.new(spawnPosition: Vector3, ctx)
	local def = Config.Enemies.Cart
	local model = Common.getTemplate("Cart") or buildMeshModel() or buildModel()
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
