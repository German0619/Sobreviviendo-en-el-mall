-- Globo: un globo de fiesta con una cara pintada que flota quieto en el aire.
-- Si alguien lo mira fijamente, se hincha... y al rato REVIENTA con un estruendo
-- que atrae a todos los enemigos cercanos. No hace dano por si mismo.
--
-- "Mirarlo" = tenerlo casi en el centro de la vista, con linea de vision y que se
-- le vea (a oscuras hace falta alumbrarlo, una bengala o vision nocturna).
--
-- Contramedidas: no mirarlo, o reventarlo DE LEJOS (taser, destello, porrazo o
-- trapeador): asi revienta sin atraer a nadie. Reventarlo de cerca hace ruido.
-- Tras reventar vuelve a aparecer en otro sitio al cabo de un rato.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local ServerScriptService = game:GetService("ServerScriptService")
local TweenService = game:GetService("TweenService")

local Server = ServerScriptService:WaitForChild("Server")
local DefenseService = require(Server:WaitForChild("DefenseService"))
local FlashlightService = require(Server:WaitForChild("FlashlightService"))
local LightService = require(Server:WaitForChild("LightService"))
local PlayerStats = require(Server:WaitForChild("PlayerStats"))

local Common = require(script.Parent.Common)

local HEIGHT = 5
local COLORS = {
	Color3.fromRGB(220, 50, 60),
	Color3.fromRGB(240, 200, 60),
	Color3.fromRGB(80, 170, 230),
	Color3.fromRGB(120, 210, 110),
	Color3.fromRGB(200, 100, 220),
}

local Balloon = {}
Balloon.__index = Balloon

local INK = Color3.fromRGB(22, 18, 20)
local BODY_CENTER = Vector3.new(0, 1, 0)
local BODY_RADIUS = 1.4

local function buildModel(): Model
	local model, _root = Common.newModel("Balloon", HEIGHT)
	local color = COLORS[math.random(1, #COLORS)]
	local function add(name: string, size: Vector3, cf: CFrame, props)
		local p = Common.part({
			Name = name,
			Size = size,
			CFrame = cf,
			Color = color,
			Material = Enum.Material.SmoothPlastic,
		})
		for k, v in props or {} do
			p[k] = v
		end
		if name ~= "Body" then
			p:SetAttribute("Detail", true) -- soldado a la raiz (Common.prepareModel)
		end
		p.Parent = model
		return p
	end
	-- Pintado sobre la goma: (x, y) en el frente del globo; la pieza se apoya en la superficie
	local function paint(name: string, x: number, y: number, size: Vector3, roll: number, props)
		local z = -math.sqrt(math.max(BODY_RADIUS ^ 2 - x ^ 2 - (y - BODY_CENTER.Y) ^ 2, 0.01))
		local pos = Vector3.new(x, y, z * 0.97)
		local normal = (pos - BODY_CENTER).Unit
		return add(name, size, CFrame.lookAt(pos, pos + normal) * CFrame.Angles(0, 0, math.rad(roll)), props)
	end

	-- Goma en forma de gota: esfera grande arriba y otra menor abajo
	add("Body", Vector3.new(2.8, 2.8, 2.8), CFrame.new(BODY_CENTER), {
		Shape = Enum.PartType.Ball,
		Reflectance = 0.15,
		CanQuery = true, -- el taser y la vista lo detectan
	})
	add("BodyLow", Vector3.new(2, 2, 2), CFrame.new(0, 0.3, 0), { Shape = Enum.PartType.Ball, Reflectance = 0.15 })
	add("Neck", Vector3.new(0.9, 0.9, 0.9), CFrame.new(0, -0.45, 0), { Shape = Enum.PartType.Ball, Reflectance = 0.15 })
	-- Brillo del plastico (arriba a la izquierda)
	add("Shine", Vector3.new(0.55, 0.55, 0.55), CFrame.new(-0.55, 1.85, -0.95), {
		Shape = Enum.PartType.Ball,
		Color = Color3.fromRGB(255, 255, 255),
		Transparency = 0.45,
	})
	add("ShineSmall", Vector3.new(0.25, 0.25, 0.25), CFrame.new(-0.85, 1.45, -1.02), {
		Shape = Enum.PartType.Ball,
		Color = Color3.fromRGB(255, 255, 255),
		Transparency = 0.55,
	})
	-- Nudo con su "labio" y el cordel rizado
	add("Knot", Vector3.new(0.4, 0.3, 0.4), CFrame.new(0, -0.95, 0), { Shape = Enum.PartType.Ball })
	add("KnotLip", Vector3.new(0.12, 0.55, 0.55), CFrame.new(0, -1.1, 0) * CFrame.Angles(0, 0, math.rad(90)), {
		Shape = Enum.PartType.Cylinder,
	})
	local white = Color3.fromRGB(240, 240, 240)
	local y = -1.25
	for i = 1, 5 do
		local lean = if i % 2 == 0 then 18 else -18
		add("String", Vector3.new(0.05, 0.23, 0.05), CFrame.new(math.sin(i * 1.3) * 0.08, y - 0.1, 0) * CFrame.Angles(0, 0, math.rad(lean)), {
			Color = white,
		})
		y -= 0.2
	end
	add("String", Vector3.new(0.05, 0.28, 0.05), CFrame.new(0.03, y - 0.14, 0), { Color = white })

	-- Cara pintada (frente = -Z): ojos ovalados con brillo, cejas y sonrisa torcida
	for _, side in { -1, 1 } do
		paint("FaceEye", side * 0.45, 1.4, Vector3.new(0.32, 0.5, 0.06), 0, { Color = INK })
		paint("FaceEyeShine", side * 0.45 - 0.06, 1.52, Vector3.new(0.1, 0.12, 0.07), 0, { Color = Color3.fromRGB(255, 255, 255) })
		paint("FaceBrow", side * 0.48, 1.85, Vector3.new(0.4, 0.07, 0.06), side * -14, { Color = INK })
		paint("FaceCheek", side * 0.85, 1.0, Vector3.new(0.3, 0.2, 0.05), 0, {
			Color = Color3.fromRGB(255, 120, 140),
			Transparency = 0.35,
		})
	end
	-- Sonrisa: arco de trazos (un poco mas alta de un lado: inquietante)
	local segments = 7
	for i = 0, segments - 1 do
		local t = math.rad(205 + i * (130 / (segments - 1)))
		local x = math.cos(t) * 0.7
		local yy = 1.05 + math.sin(t) * 0.45 + (i / segments) * 0.1
		local tangent = math.deg(math.atan2(math.cos(t) * 0.45, -math.sin(t) * 0.7))
		paint("FaceSmile", x, yy, Vector3.new(0.26, 0.08, 0.06), -tangent, { Color = INK })
	end
	-- Dientes pintados dentro de la sonrisa
	for i = -2, 2 do
		paint("FaceTooth", i * 0.17, 0.72 + math.abs(i) * 0.04, Vector3.new(0.12, 0.13, 0.055), 0, {
			Color = Color3.fromRGB(245, 245, 235),
		})
	end
	return model
end

function Balloon.new(spawnPosition: Vector3, ctx)
	local def = Config.Enemies.Balloon
	local model = Common.getTemplate("Balloon") or buildModel()
	local height = Common.getHeight(model)
	Common.prepareModel(model)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
		end
	end
	model.Parent = ctx.Container

	local self = setmetatable({}, Balloon)
	self.Def = def
	self.Ctx = ctx
	self.Model = model
	self.Height = height
	self.CosLook = math.cos(math.rad(def.LookHalfAngle))
	self.Stare = 0 -- 0..1: al llegar a 1 revienta
	self.RespawnAt = nil :: number?
	self.Scale = 1
	self:PlaceAt(spawnPosition)
	return self
end

-- Coloca el globo flotando sobre un punto del suelo.
function Balloon:PlaceAt(ground: Vector3)
	self.Anchor = ground + Vector3.new(0, self.Def.HoverHeight, 0)
	self.Phase = math.random() * math.pi * 2
	self.Stare = 0
	self:SetScale(1)
	self.Model:PivotTo(CFrame.new(self.Anchor))
end

function Balloon:SetScale(scale: number)
	if math.abs(scale - self.Scale) > 0.01 then
		self.Scale = scale
		pcall(function()
			self.Model:ScaleTo(scale)
		end)
	end
end

function Balloon:GetLookPoint(): Vector3
	return self.Model:GetPivot().Position + Vector3.new(0, 1, 0) -- centro del globo
end

-- Lo mira de frente (cono estrecho: hay que mirarlo, no basta con que este en pantalla).
function Balloon:IsStaredBy(player: Player, point: Vector3): boolean
	local character = player.Character
	local head = character and character:FindFirstChild("Head") :: BasePart?
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not head or not root or DefenseService.IsHidden(player) then
		return false
	end
	local toPoint = point - head.Position
	local dist = toPoint.Magnitude
	if dist > self.Def.LookRange or dist < 0.01 then
		return false
	end
	-- En primera persona el personaje gira con la camara: su frente es hacia donde mira
	-- (en horizontal, como el Maniqui)
	local look = root.CFrame.LookVector
	local flatLook = Vector3.new(look.X, 0, look.Z)
	local flat = Vector3.new(toPoint.X, 0, toPoint.Z)
	if flatLook.Magnitude < 0.01 then
		return false
	end
	if flat.Magnitude > 0.5 and flatLook.Unit:Dot(flat.Unit) < self.CosLook then
		return false
	end
	if DefenseService.IsInSmoke(point) or not Common.lineOfSight(head.Position, point) then
		return false
	end
	if not LightService.IsDarkAt(point) or DefenseService.IsInFlare(point) then
		return true
	end
	return FlashlightService.IsLighting(player, point) or PlayerStats.HasFlag(player, "NightVision")
end

-- Revienta. noisy = true: estruendo que atrae a los enemigos.
function Balloon:Pop(noisy: boolean)
	if self.RespawnAt then
		return
	end
	local position = self:GetLookPoint()
	local color = (self.Model:FindFirstChild("Body") :: BasePart?)
	local burstColor = if color then color.Color else Color3.new(1, 1, 1)

	-- Confeti / jirones
	local fx = Common.part({
		Name = "BalloonPop",
		Size = Vector3.new(0.2, 0.2, 0.2),
		Transparency = 1,
		CFrame = CFrame.new(position),
		CanQuery = false,
	})
	local scraps = Instance.new("ParticleEmitter")
	scraps.Color = ColorSequence.new(burstColor)
	scraps.Size = NumberSequence.new(0.35)
	scraps.Lifetime = NumberRange.new(0.6, 1.2)
	scraps.Speed = NumberRange.new(10, 20)
	scraps.SpreadAngle = Vector2.new(180, 180)
	scraps.Acceleration = Vector3.new(0, -25, 0)
	scraps.RotSpeed = NumberRange.new(-300, 300)
	scraps.Rate = 0
	scraps.Parent = fx
	local flash = Instance.new("PointLight")
	flash.Range = 12
	flash.Brightness = if noisy then 3 else 0.8
	flash.Color = burstColor
	flash.Parent = fx
	fx.Parent = self.Ctx.Container
	scraps:Emit(if noisy then 40 else 20)
	TweenService:Create(flash, TweenInfo.new(0.4), { Brightness = 0 }):Play()
	task.delay(1.5, function()
		fx:Destroy()
	end)

	if noisy then
		DefenseService.AddLure(position, self.Def.LureSeconds, self.Def.LureRadius)
		for _, player in Common.getAlivePlayers() do
			local root = Common.getRoot(player)
			if root and (root.Position - position).Magnitude <= self.Def.LureRadius then
				Remotes.event("Notify"):FireClient(player, "¡PUM! Un globo reventó y los enemigos van hacia allí.", "bad")
			end
		end
	end

	self.Model.Parent = nil
	self.RespawnAt = os.clock() + self.Def.RespawnSeconds
end

-- Golpes y destellos: de lejos revienta en silencio; de cerca, con estruendo.
function Balloon:PopBy(player: Player)
	local root = Common.getRoot(player)
	local far = root ~= nil and (root.Position - self:GetLookPoint()).Magnitude >= self.Def.SafeDistance
	self:Pop(not far)
end

function Balloon:TryRespawn()
	for _ = 1, 4 do
		local point = Common.randomPatrolPoint()
		if point then
			local _, _, d = Common.nearestAlive(point)
			if d >= self.Def.RespawnMinDistance then
				self.RespawnAt = nil
				self:PlaceAt(point)
				self.Model.Parent = self.Ctx.Container
				return
			end
		end
	end
	self.RespawnAt = os.clock() + 2 -- reintentar
end

function Balloon:Update(dt: number)
	local now = os.clock()
	if self.RespawnAt then
		if now >= self.RespawnAt then
			self:TryRespawn()
		end
		return
	end

	-- Flota meciendose un poco, siempre "mirando" al jugador mas cercano
	local bob = math.sin(now * 1.3 + self.Phase) * 0.35
	local pos = self.Anchor + Vector3.new(0, bob, 0)
	local _, nearest = Common.nearestAlive(pos)
	local lookAt = if nearest then Vector3.new(nearest.Position.X, pos.Y, nearest.Position.Z) else pos + Vector3.new(0, 0, -1)
	if (lookAt - pos).Magnitude < 0.1 then
		lookAt = pos + Vector3.new(0, 0, -1)
	end
	self.Model:PivotTo(CFrame.lookAt(pos, lookAt))

	-- Aturdido (destello de lejos ya lo revento): no se hincha
	if Common.isStunned(self.Model) then
		return
	end

	local point = self:GetLookPoint()
	local staring = 0
	for _, player in Common.getAlivePlayers() do
		if self:IsStaredBy(player, point) then
			staring += 1
		end
	end
	if staring > 0 then
		-- Cada mirada extra lo hincha un poco mas rapido
		self.Stare += dt / self.Def.PopSeconds * (1 + 0.35 * (staring - 1))
	else
		self.Stare = math.max(0, self.Stare - dt * self.Def.DeflatePerSecond)
	end
	self:SetScale(1 + self.Stare * 0.6)
	if self.Stare >= 1 then
		self:Pop(true)
	end
end

function Balloon:OnFlash(player: Player)
	self:PopBy(player)
end

function Balloon:OnShove(player: Player, _direction: Vector3, _strength: any)
	self:PopBy(player)
end

function Balloon:OnTaser(player: Player)
	self:PopBy(player)
end

function Balloon:Destroy()
	self.Model:Destroy()
end

return Balloon
