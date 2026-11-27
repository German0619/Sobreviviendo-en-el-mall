-- HeldModels: modelos de lo que se lleva en la mano (armas, objetos de la mochila y la
-- linterna). Los usan:
--   * el servidor (BackpackService / FlashlightService): el modelo va en la mano del
--     personaje y lo ven los demas jugadores;
--   * el cliente (ViewModel): una copia local delante de la camara, porque en primera
--     persona Roblox esconde tu propio personaje (y lo que lleva en la mano).
--
-- Convencion: Model con PrimaryPart "Handle" (invisible) en el punto por donde se agarra.
-- El frente (hacia donde apunta) es -Z del Handle; arriba es +Y.
--
-- Skins (Fase 11): build(id, skin) aplica Config.Skins[skin] (material y colores) a las
-- partes marcadas con el atributo "Paint" ("Body" | "Accent" | "Glow" | "Lens") y, segun
-- la rareza, anillos de neon, luz y particulas. Lo que se anima lo hace client/SkinFX.
-- Sin skin: los colores originales.

local Shared = script.Parent
local Config = require(Shared.Config)

local HeldModels = {}

local function newModel(name: string): (Model, Part)
	local model = Instance.new("Model")
	model.Name = name
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.2, 0.2, 0.2)
	handle.Transparency = 1
	handle.CanCollide = false
	handle.CanQuery = false
	handle.CanTouch = false
	handle.Massless = true
	handle.CFrame = CFrame.new()
	handle.Parent = model
	model.PrimaryPart = handle
	return model, handle
end

-- Pieza del modelo. paint: "Body" | "Accent" | nil (las skins solo cambian las marcadas).
local function piece(model: Model, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, opts: { [string]: any }?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in opts or {} do
		if k == "Paint" then
			p:SetAttribute("Paint", v)
		else
			(p :: any)[k] = v
		end
	end
	p.Parent = model
	return p
end

-- Cilindro a lo largo de Z (hacia delante), con centro en `cf`.
local function tube(model: Model, name: string, length: number, diameter: number, cf: CFrame, color: Color3, material: Enum.Material?, opts: { [string]: any }?): Part
	local p = piece(model, name, Vector3.new(length, diameter, diameter), cf * CFrame.Angles(0, math.rad(90), 0), color, material, opts)
	p.Shape = Enum.PartType.Cylinder
	return p
end

-- Cilindro vertical (eje Y).
local function vtube(model: Model, name: string, height: number, diameter: number, cf: CFrame, color: Color3, material: Enum.Material?, opts: { [string]: any }?): Part
	local p = piece(model, name, Vector3.new(height, diameter, diameter), cf * CFrame.Angles(0, 0, math.rad(90)), color, material, opts)
	p.Shape = Enum.PartType.Cylinder
	return p
end

local DARK = Color3.fromRGB(30, 30, 34)
local STEEL = Color3.fromRGB(150, 152, 158)

----------------------------------------------------------------------
-- Constructores (uno por id: armas y objetos de Config.ShopItems, y "Flashlight")
----------------------------------------------------------------------

local builders: { [string]: (Model) -> () } = {}

-- Linterna (la de siempre, en la otra mano). Lente "Lens": la enciende SetLit.
builders.Flashlight = function(m)
	tube(m, "Body", 1.3, 0.32, CFrame.new(0, 0, -0.35), Color3.fromRGB(45, 45, 50), Enum.Material.Metal, { Paint = "Body" })
	tube(m, "Head", 0.45, 0.48, CFrame.new(0, 0, -1.15), Color3.fromRGB(45, 45, 50), Enum.Material.Metal, { Paint = "Body" })
	tube(m, "Lens", 0.06, 0.4, CFrame.new(0, 0, -1.4), Color3.fromRGB(210, 210, 200), Enum.Material.Glass, { Paint = "Lens" })
	piece(m, "Button", Vector3.new(0.12, 0.08, 0.2), CFrame.new(0, 0.17, -0.45), Color3.fromRGB(200, 40, 40), nil, { Paint = "Accent" })
	tube(m, "Grip", 0.6, 0.34, CFrame.new(0, 0, 0.15), Color3.fromRGB(25, 25, 28), Enum.Material.Rubber)
end

builders.Taser = function(m)
	piece(m, "Grip", Vector3.new(0.28, 0.75, 0.38), CFrame.new(0, -0.25, 0.1) * CFrame.Angles(math.rad(-12), 0, 0), DARK, Enum.Material.Rubber)
	piece(m, "Body", Vector3.new(0.36, 0.42, 1.1), CFrame.new(0, 0.18, -0.35), Color3.fromRGB(240, 200, 30), nil, { Paint = "Body" })
	piece(m, "Stripe", Vector3.new(0.37, 0.1, 0.9), CFrame.new(0, 0.3, -0.35), DARK, nil, { Paint = "Accent" })
	for _, x in { -0.1, 0.1 } do
		piece(m, "Prong", Vector3.new(0.05, 0.05, 0.18), CFrame.new(x, 0.18, -0.98), STEEL, Enum.Material.Metal)
	end
	piece(m, "Spark", Vector3.new(0.3, 0.12, 0.04), CFrame.new(0, 0.18, -0.92), Color3.fromRGB(120, 200, 255), Enum.Material.Neon, { Paint = "Glow" })
end

builders.Extinguisher = function(m)
	vtube(m, "Tank", 1.5, 0.62, CFrame.new(0, -0.55, 0.1), Color3.fromRGB(200, 30, 30), Enum.Material.SmoothPlastic, { Paint = "Body" })
	vtube(m, "Cap", 0.2, 0.4, CFrame.new(0, 0.28, 0.1), DARK, Enum.Material.Metal)
	piece(m, "Lever", Vector3.new(0.12, 0.08, 0.6), CFrame.new(0, 0.42, -0.05), STEEL, Enum.Material.Metal, { Paint = "Accent" })
	tube(m, "Hose", 0.7, 0.12, CFrame.new(0.25, 0.25, -0.35), DARK, Enum.Material.Rubber)
	tube(m, "Nozzle", 0.25, 0.2, CFrame.new(0.25, 0.25, -0.8), DARK, Enum.Material.Metal)
	piece(m, "Label", Vector3.new(0.05, 0.4, 0.3), CFrame.new(0.31, -0.5, 0.1), Color3.fromRGB(240, 240, 240), nil, { Paint = "Accent" })
end

builders.WetFloorSign = function(m)
	-- Plegado, bajo el brazo
	piece(m, "Panel", Vector3.new(0.9, 1.5, 0.08), CFrame.new(0, -0.4, 0.05), Color3.fromRGB(255, 210, 40), nil, { Paint = "Body" })
	piece(m, "Panel2", Vector3.new(0.9, 1.5, 0.08), CFrame.new(0, -0.4, 0.17), Color3.fromRGB(255, 210, 40), nil, { Paint = "Body" })
	piece(m, "Top", Vector3.new(0.5, 0.15, 0.3), CFrame.new(0, 0.4, 0.11), DARK)
	piece(m, "Stripe", Vector3.new(0.92, 0.18, 0.02), CFrame.new(0, -0.2, 0.0), DARK, nil, { Paint = "Accent" })
end

builders.UVFlashlight = function(m)
	tube(m, "Body", 1.4, 0.34, CFrame.new(0, 0, -0.3), Color3.fromRGB(70, 40, 110), Enum.Material.Metal, { Paint = "Body" })
	tube(m, "Head", 0.4, 0.5, CFrame.new(0, 0, -1.15), Color3.fromRGB(40, 30, 60), Enum.Material.Metal, { Paint = "Accent" })
	tube(m, "Lens", 0.06, 0.42, CFrame.new(0, 0, -1.38), Color3.fromRGB(170, 80, 255), Enum.Material.Neon, { Paint = "Glow" })
end

builders.Mop = function(m)
	-- Palo largo hacia delante y abajo, con la fregona al final
	tube(m, "Stick", 4.2, 0.14, CFrame.new(0, -0.3, -1.3) * CFrame.Angles(math.rad(-20), 0, 0), Color3.fromRGB(80, 140, 200), Enum.Material.Metal, { Paint = "Body" })
	piece(m, "MopHead", Vector3.new(0.9, 0.35, 0.35), CFrame.new(0, -1.05, -3.25) * CFrame.Angles(math.rad(-20), 0, 0), Color3.fromRGB(210, 210, 200), Enum.Material.Fabric, { Paint = "Accent" })
	for i = -2, 2 do
		piece(m, "Strand", Vector3.new(0.12, 0.6, 0.12), CFrame.new(i * 0.18, -1.35, -3.35), Color3.fromRGB(200, 200, 190), Enum.Material.Fabric, { Paint = "Accent" })
	end
end

-- Machete: mango negro, guarda y hoja larga hacia delante con la punta en cuña
builders.Machete = function(m)
	piece(m, "Grip", Vector3.new(0.22, 0.3, 0.85), CFrame.new(0, 0, 0.1), Color3.fromRGB(28, 24, 22), Enum.Material.Rubber, { Paint = "Accent" })
	piece(m, "Guard", Vector3.new(0.26, 0.42, 0.1), CFrame.new(0, 0.02, -0.38), STEEL, Enum.Material.Metal)
	piece(m, "Blade", Vector3.new(0.05, 0.42, 2.3), CFrame.new(0, 0.06, -1.55), Color3.fromRGB(190, 195, 200), Enum.Material.Metal, { Paint = "Body" })
	piece(m, "Edge", Vector3.new(0.06, 0.06, 2.3), CFrame.new(0, -0.14, -1.55), Color3.fromRGB(235, 238, 242), Enum.Material.Metal)
	local tip = Instance.new("WedgePart")
	tip.Name = "Tip"
	tip.Size = Vector3.new(0.05, 0.42, 0.5)
	tip.CFrame = CFrame.new(0, 0.06, -2.95) * CFrame.Angles(0, math.pi, 0)
	tip.Color = Color3.fromRGB(190, 195, 200)
	tip.Material = Enum.Material.Metal
	tip.CanCollide = false
	tip.CanQuery = false
	tip.CanTouch = false
	tip.Massless = true
	tip.CastShadow = false
	tip:SetAttribute("Paint", "Body")
	tip.Parent = m
end

-- Pistola: empuñadura inclinada, corredera, cañon y mira
builders.Pistol = function(m)
	piece(m, "Grip", Vector3.new(0.26, 0.7, 0.36), CFrame.new(0, -0.28, 0.08) * CFrame.Angles(math.rad(-15), 0, 0), DARK, Enum.Material.Rubber)
	piece(m, "Slide", Vector3.new(0.28, 0.3, 1.05), CFrame.new(0, 0.12, -0.3), Color3.fromRGB(45, 46, 50), Enum.Material.Metal, { Paint = "Body" })
	piece(m, "Frame", Vector3.new(0.25, 0.14, 0.8), CFrame.new(0, -0.07, -0.2), DARK, Enum.Material.Metal)
	tube(m, "Barrel", 0.12, 0.12, CFrame.new(0, 0.12, -0.86), Color3.fromRGB(20, 20, 22), Enum.Material.Metal)
	piece(m, "TriggerGuard", Vector3.new(0.06, 0.22, 0.3), CFrame.new(0, -0.24, -0.25), DARK, Enum.Material.Metal)
	piece(m, "FrontSight", Vector3.new(0.05, 0.07, 0.05), CFrame.new(0, 0.3, -0.78), Color3.fromRGB(240, 120, 40), Enum.Material.Neon, { Paint = "Accent" })
	piece(m, "RearSight", Vector3.new(0.16, 0.06, 0.05), CFrame.new(0, 0.3, 0.18), DARK, Enum.Material.Metal)
end

builders.Battery = function(m)
	vtube(m, "Body", 0.9, 0.42, CFrame.new(0, 0, 0), Color3.fromRGB(40, 160, 70), nil, { Paint = "Body" })
	vtube(m, "Top", 0.12, 0.2, CFrame.new(0, 0.5, 0), STEEL, Enum.Material.Metal)
	vtube(m, "Band", 0.2, 0.43, CFrame.new(0, -0.25, 0), DARK, nil, { Paint = "Accent" })
end

builders.LithiumBattery = function(m)
	vtube(m, "Body", 1, 0.46, CFrame.new(0, 0, 0), Color3.fromRGB(40, 110, 220), Enum.Material.Metal, { Paint = "Body" })
	vtube(m, "Top", 0.12, 0.22, CFrame.new(0, 0.56, 0), STEEL, Enum.Material.Metal)
	vtube(m, "Glow", 0.12, 0.47, CFrame.new(0, 0.1, 0), Color3.fromRGB(120, 220, 255), Enum.Material.Neon, { Paint = "Glow" })
end

local function medkit(m: Model, size: Vector3, box: Color3, cross: Color3)
	piece(m, "Box", size, CFrame.new(0, 0, 0), box, nil, { Paint = "Body" })
	piece(m, "Handle2", Vector3.new(size.X * 0.4, 0.12, 0.1), CFrame.new(0, size.Y / 2 + 0.06, 0), DARK)
	local face = -size.Z / 2 - 0.01
	piece(m, "CrossA", Vector3.new(size.X * 0.45, size.Y * 0.15, 0.02), CFrame.new(0, 0, face), cross, nil, { Paint = "Accent" })
	piece(m, "CrossB", Vector3.new(size.X * 0.15, size.Y * 0.6, 0.02), CFrame.new(0, 0, face), cross, nil, { Paint = "Accent" })
end

builders.Medkit = function(m)
	medkit(m, Vector3.new(0.9, 0.65, 0.35), Color3.fromRGB(240, 240, 240), Color3.fromRGB(210, 30, 30))
end

builders.BigMedkit = function(m)
	medkit(m, Vector3.new(1.2, 0.85, 0.45), Color3.fromRGB(200, 30, 30), Color3.fromRGB(245, 245, 245))
end

local function flare(m: Model, body: Color3, cap: Color3)
	tube(m, "Stick", 1.1, 0.24, CFrame.new(0, 0, -0.3), body, nil, { Paint = "Body" })
	tube(m, "Cap", 0.18, 0.27, CFrame.new(0, 0, -0.9), cap, nil, { Paint = "Accent" })
end

builders.Flare = function(m)
	flare(m, Color3.fromRGB(220, 40, 30), Color3.fromRGB(40, 40, 40))
end

builders.MagnesiumFlare = function(m)
	flare(m, Color3.fromRGB(225, 228, 235), Color3.fromRGB(120, 125, 135))
end

local function firecracker(m: Model, count: number)
	for i = 1, count do
		local angle = (i - 1) / count * math.pi * 2
		local offset = if count > 1 then Vector3.new(math.cos(angle) * 0.14, 0, math.sin(angle) * 0.14) else Vector3.zero
		vtube(m, "Tube", 0.8, 0.22, CFrame.new(offset), Color3.fromRGB(200, 30, 30), nil, { Paint = "Body" })
	end
	piece(m, "Fuse", Vector3.new(0.04, 0.35, 0.04), CFrame.new(0, 0.55, 0) * CFrame.Angles(0, 0, math.rad(20)), Color3.fromRGB(200, 190, 160))
	piece(m, "Wrap", Vector3.new(0.5, 0.12, 0.5), CFrame.new(0, 0.1, 0), Color3.fromRGB(240, 200, 40), nil, { Paint = "Accent" })
end

builders.Firecracker = function(m)
	firecracker(m, 1)
end

builders.BigFirecracker = function(m)
	firecracker(m, 3)
end

builders.SmokeBomb = function(m)
	local ball = piece(m, "Ball", Vector3.new(0.7, 0.7, 0.7), CFrame.new(0, 0, 0), Color3.fromRGB(90, 95, 100), Enum.Material.Metal, { Paint = "Body" })
	ball.Shape = Enum.PartType.Ball
	vtube(m, "Neck", 0.15, 0.25, CFrame.new(0, 0.4, 0), DARK, Enum.Material.Metal)
	local ring = piece(m, "Pin", Vector3.new(0.05, 0.25, 0.25), CFrame.new(0.18, 0.48, 0), STEEL, Enum.Material.Metal, { Paint = "Accent" })
	ring.Shape = Enum.PartType.Cylinder
end

builders.MysterySoda = function(m)
	vtube(m, "Can", 0.85, 0.42, CFrame.new(0, 0, 0), Color3.fromRGB(130, 50, 200), Enum.Material.Metal, { Paint = "Body" })
	vtube(m, "Lid", 0.06, 0.38, CFrame.new(0, 0.45, 0), STEEL, Enum.Material.Metal)
	vtube(m, "Band", 0.22, 0.43, CFrame.new(0, 0, 0), Color3.fromRGB(255, 220, 60), Enum.Material.Neon, { Paint = "Accent" })
end

-- Fumigador de entidades (pase): mochila-tanque pequeña con lanza
builders.Fumigator = function(m)
	vtube(m, "Tank", 1.2, 0.7, CFrame.new(0.15, -0.45, 0.35), Color3.fromRGB(60, 150, 70), Enum.Material.Metal, { Paint = "Body" })
	vtube(m, "TankCap", 0.15, 0.4, CFrame.new(0.15, 0.2, 0.35), DARK, Enum.Material.Metal)
	piece(m, "Hazard", Vector3.new(0.05, 0.4, 0.4), CFrame.new(0.51, -0.45, 0.35), Color3.fromRGB(245, 210, 40), nil, { Paint = "Accent" })
	tube(m, "Wand", 1.4, 0.12, CFrame.new(0, 0.05, -0.6), STEEL, Enum.Material.Metal)
	tube(m, "WandGrip", 0.35, 0.2, CFrame.new(0, 0.05, 0), DARK, Enum.Material.Rubber)
	tube(m, "Nozzle", 0.2, 0.22, CFrame.new(0, 0.05, -1.35), DARK, Enum.Material.Metal)
	piece(m, "Mist", Vector3.new(0.18, 0.18, 0.05), CFrame.new(0, 0.05, -1.47), Color3.fromRGB(140, 255, 140), Enum.Material.Neon, { Paint = "Glow" })
end

builders.FlashlightPro = builders.Flashlight

----------------------------------------------------------------------
-- API
----------------------------------------------------------------------

-- Modelos 3D realistas (ReplicatedStorage.HeldTemplates, guardados en el place): Model con
-- "Handle" invisible en el agarre y la malla "Body" (mas piezas utiles, p. ej. "Lens").
-- Se usan si no hay skin: las skins pintan las piezas del modelo de piezas (las mallas
-- llevan su textura y no se pueden repintar).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local function template(id: string): Model?
	local folder = ReplicatedStorage:FindFirstChild("HeldTemplates")
	local t = folder and folder:FindFirstChild(id)
	if t and t:IsA("Model") and t:FindFirstChild("Handle") then
		return t
	end
	return nil
end

function HeldModels.has(id: string): boolean
	return builders[id] ~= nil or template(id) ~= nil
end

-- Pieza animada por client/SkinFX (tag SkinAnim; atributo SkinAnim = modo, SkinFxPhase = desfase)
local CollectionService = game:GetService("CollectionService")
local ANIM_TAG = "SkinAnim"
HeldModels.ANIM_TAG = ANIM_TAG

local function markAnim(inst: Instance, mode: string?, phase: number)
	if mode then
		inst:SetAttribute("SkinAnim", mode)
		inst:SetAttribute("SkinFxPhase", phase)
		CollectionService:AddTag(inst, ANIM_TAG)
	end
end

local function toRange(v: any): NumberRange
	if type(v) == "table" then
		return NumberRange.new(v[1], v[2] or v[1])
	end
	return NumberRange.new(v or 0)
end

local function toSequence(v: any, default: number): NumberSequence
	if typeof(v) == "NumberSequence" then
		return v
	end
	return NumberSequence.new(v or default)
end

-- Anillos de neon alrededor de una pieza del cuerpo, repartidos a lo largo de su eje mas
-- largo (las piezas cilindro van a lo largo de su X). Se sueldan con el resto al
-- llevarlo en la mano (intoTool / attach sueldan todas las BasePart del modelo).
local function addBands(model: Model, body: BasePart, bands, mode: string?, index: number)
	local isCylinder = body:IsA("Part") and body.Shape == Enum.PartType.Cylinder
	if not isCylinder then
		return -- (en las piezas de caja los anillos parecian un peine)
	end
	local size = body.Size
	local axis: Vector3, length: number
	if isCylinder or (size.X >= size.Y and size.X >= size.Z) then
		axis, length = Vector3.xAxis, size.X
	elseif size.Y >= size.Z then
		axis, length = Vector3.yAxis, size.Y
	else
		axis, length = Vector3.zAxis, size.Z
	end
	local count = if length < 0.6 then 1 else math.min(bands.Count or 2, math.max(1, math.floor(length / 0.3)))
	local thick = math.clamp(length * 0.06, 0.05, 0.1)
	for i = 1, count do
		local offset = (i / (count + 1) - 0.5) * length
		local ring = Instance.new("Part")
		ring.Name = "SkinBand"
		ring.CanCollide = false
		ring.CanQuery = false
		ring.CanTouch = false
		ring.Massless = true
		ring.CastShadow = false
		ring.Color = bands.Color
		ring.Material = bands.Material or Enum.Material.Neon
		if isCylinder then
			ring.Shape = Enum.PartType.Cylinder
			ring.Size = Vector3.new(thick, size.Y * 1.16 + 0.02, size.Z * 1.16 + 0.02)
		else
			local grown = size * 1.08 + Vector3.new(0.02, 0.02, 0.02)
			ring.Size = Vector3.new(
				if axis == Vector3.xAxis then thick else grown.X,
				if axis == Vector3.yAxis then thick else grown.Y,
				if axis == Vector3.zAxis then thick else grown.Z
			)
		end
		ring.CFrame = body.CFrame * CFrame.new(axis * offset)
		ring:SetAttribute("Paint", "Band")
		markAnim(ring, mode, index * 0.7 + i * 0.45)
		ring.Parent = model
	end
end

----------------------------------------------------------------------
-- Texturas, emblemas y piezas propias de cada skin (Config.Skins: Texture, Emblem, Decor)
----------------------------------------------------------------------

local FACES = Enum.NormalId:GetEnumItems()

-- Textura de mosaico en todas las caras de una pieza.
function HeldModels.applyTexture(part: BasePart, tex: { Id: string, Tile: number? })
	for _, face in FACES do
		local t = Instance.new("Texture")
		t.Name = "SkinTexture"
		t.Texture = tex.Id
		t.Face = face
		t.StudsPerTileU = tex.Tile or 1.2
		t.StudsPerTileV = tex.Tile or 1.2
		t.Parent = part
	end
end

-- Ejes de una pieza del cuerpo en el espacio del modelo: L (a lo largo, hacia delante),
-- U (arriba), S (al lado) y la mitad de su tamano en cada eje. Sirve para cualquier
-- forma y orientacion (el palo inclinado del trapeador, el cartel vertical...).
type BodyFrame = { Center: Vector3, L: Vector3, U: Vector3, S: Vector3, HL: number, HU: number, HS: number }
local function bodyFrame(body: BasePart): BodyFrame
	local cf = body.CFrame
	local axes = { cf.XVector, cf.YVector, cf.ZVector }
	local sizes = { body.Size.X, body.Size.Y, body.Size.Z }
	local li = 1
	if not (body:IsA("Part") and body.Shape == Enum.PartType.Cylinder) then
		for i = 2, 3 do
			if sizes[i] > sizes[li] then
				li = i
			end
		end
	end
	local L = axes[li]
	local U
	if math.abs(L.Y) > 0.7 then
		-- pieza vertical (cartel): "arriba" es su largo y "delante" el frente del modelo
		U = if L.Y > 0 then L else -L
		local f = -Vector3.zAxis - U * (-U.Z)
		L = if f.Magnitude > 0.1 then f.Unit else Vector3.xAxis
	else
		if L:Dot(-Vector3.zAxis) < 0 then
			L = -L -- que L apunte hacia delante (-Z del modelo)
		end
		U = (Vector3.yAxis - L * L.Y).Unit
	end
	local S = L:Cross(U)
	local function extent(dir: Vector3): number
		local e = 0
		for i = 1, 3 do
			e += math.abs(axes[i]:Dot(dir)) * sizes[i] / 2
		end
		return e
	end
	return { Center = cf.Position, L = L, U = U, S = S, HL = extent(L), HU = extent(U), HS = extent(S) }
end

-- Pieza decorativa (no la repinta otra skin; se anima si es de neon y la skin tiene Anim)
local function decor(model: Model, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material, mode: string?, phase: number): Part
	local p = piece(model, name, size, cf, color, material, { Paint = "Decor" })
	if material == Enum.Material.Neon then
		markAnim(p, mode, phase)
	end
	return p
end

-- Emblema (calcomania) a los dos lados del cuerpo, en una placa invisible cuadrada para
-- que la imagen no se estire con la forma de la pieza.
local function addEmblem(model: Model, f: BodyFrame, id: string)
	local size = math.clamp(math.min(f.HU, f.HL) * 1.5, 0.18, 0.55)
	for _, side in { 1, -1 } do
		local pos = f.Center + f.S * side * (f.HS + 0.012)
		local plate = piece(model, "SkinEmblem", Vector3.new(size, size, 0.02), CFrame.fromMatrix(pos, f.L * side, f.U, f.S * side), Color3.new(1, 1, 1), nil, { Paint = "Emblem", Transparency = 1 })
		local decal = Instance.new("Decal")
		decal.Name = "SkinEmblem"
		decal.Texture = id
		decal.Face = Enum.NormalId.Back -- (+Z de la placa: hacia fuera)
		decal.Parent = plate
	end
end

local decorBuilders: { [string]: (Model, BodyFrame, any, string?, any) -> () } = {}

-- Gemas engastadas arriba (Dorado)
decorBuilders.Gems = function(m, f, d, mode, skin)
	local size = math.clamp(math.min(f.HU, f.HS) * 0.95, 0.1, 0.28)
	local count = if f.HL > 0.6 then 3 else 2
	for i = 1, count do
		local along = (if count == 1 then 0 else (i - 1) / (count - 1) - 0.5) * f.HL * 0.9
		local base = f.Center + f.U * f.HU + f.L * along
		decor(m, "Bezel", Vector3.new(size * 0.3, size * 1.35, size * 1.35), CFrame.fromMatrix(base, f.U, f.L), skin.Body.Color, Enum.Material.Foil, nil, 0).Shape = Enum.PartType.Cylinder
		local gem = decor(m, "Gem", Vector3.one * size, CFrame.new(base + f.U * size * 0.35), d.Color, d.Material or Enum.Material.Glass, mode, i)
		gem.Shape = Enum.PartType.Ball
		gem.Reflectance = 0.4
	end
end

-- Cristales que brotan del lomo (Diamante)
decorBuilders.Crystals = function(m, f, d, mode)
	local rng = Random.new(17)
	local a = math.clamp(math.min(f.HU, f.HS) * 0.85, 0.09, 0.26)
	for i = 1, d.Count or 3 do
		local along = (i / ((d.Count or 3) + 1) - 0.55) * f.HL * 1.3
		local up = (f.U + f.S * (if i % 2 == 0 then 0.6 else -0.6) * rng:NextNumber(0.6, 1) - f.L * rng:NextNumber(0.1, 0.5)).Unit
		local h = a * (2.8 + (i % 2) * 1.1)
		local pos = f.Center + f.U * f.HU * 0.8 + f.L * along + up * h * 0.4
		local cf = CFrame.fromMatrix(pos, up:Cross(f.L).Unit, up) * CFrame.Angles(0, math.rad(45), 0)
		local shard = decor(m, "Crystal", Vector3.new(a, h, a), cf, d.Color, d.Material or Enum.Material.Glass, mode, i)
		shard.Transparency = 0.45
		shard.Reflectance = 0.4
		decor(m, "CrystalCore", Vector3.new(a * 0.55, h * 0.8, a * 0.55), cf, d.Color, Enum.Material.Neon, mode, i)
	end
end

-- Dos orbes de energia a los lados, unidos al cuerpo (Plasma)
decorBuilders.Orbs = function(m, f, d, mode)
	local r = math.clamp(math.min(f.HU, f.HS) * 1.25, 0.14, 0.3)
	for i, side in { 1, -1 } do
		local pos = f.Center + f.S * side * (f.HS + r * 1.2) - f.L * f.HL * 0.3
		local orb = decor(m, "Orb", Vector3.one * r, CFrame.new(pos), d.Color, Enum.Material.Neon, mode, i)
		orb.Shape = Enum.PartType.Ball
		local shell = decor(m, "OrbShell", Vector3.one * r * 1.45, CFrame.new(pos), d.Color, Enum.Material.Glass, nil, 0)
		shell.Shape = Enum.PartType.Ball
		shell.Transparency = 0.6
		local rodLen = r * 1.3
		local rod = decor(m, "OrbRod", Vector3.new(rodLen, r * 0.25, r * 0.25), CFrame.fromMatrix(f.Center + f.S * side * (f.HS + rodLen * 0.35) - f.L * f.HL * 0.3, f.S, f.U), d.Color, Enum.Material.Neon, mode, i)
		rod.Shape = Enum.PartType.Cylinder
	end
end

-- Luna creciente flotando sobre el cuerpo, con dos estrellas (Luna)
decorBuilders.Moon = function(m, f, d, mode)
	local R = math.clamp(math.min(f.HU, f.HS) * 3, 0.24, 0.5)
	local c = f.Center + f.U * (f.HU + R * 1.15)
	local steps = 9
	for i = 0, steps - 1 do
		local t = -1.35 + 2.7 * i / (steps - 1)
		local p = c + (f.U * math.sin(t) - f.L * math.cos(t)) * R
		local tangent = (f.U * math.cos(t) + f.L * math.sin(t)).Unit
		local w = R * 0.3 * (1 - (t / 1.6) ^ 2) + 0.025
		decor(m, "Moon", Vector3.new(w * 0.7, 2.7 * R / steps * 1.15, w), CFrame.fromMatrix(p, f.S, tangent), d.Color, Enum.Material.Neon, mode, i * 0.3)
	end
	for i, off in { f.L * R * 0.7 + f.U * R * 0.55, f.L * R * 0.25 - f.U * R * 0.6 } do
		local s = R * (if i == 1 then 0.28 else 0.18)
		decor(m, "Star", Vector3.one * s, CFrame.new(c + off) * CFrame.Angles(math.rad(45), 0, math.rad(45)), Color3.fromRGB(255, 245, 210), Enum.Material.Neon, mode, 2 + i)
	end
end

-- Cuernos curvados hacia atras con la punta de lava (Infierno)
decorBuilders.Horns = function(m, f, d, mode, skin)
	local s0 = math.clamp(math.min(f.HU, f.HS) * 1.1, 0.11, 0.26)
	for i, side in { 1, -1 } do
		local p = f.Center + f.U * f.HU * 0.85 + f.S * side * f.HS * 0.45 + f.L * f.HL * 0.25
		local s = s0
		for k = 0, 3 do
			local a = math.rad(15 + k * 24)
			local dir = (f.U * math.cos(a) - f.L * math.sin(a) + f.S * side * 0.15).Unit
			local len = s * 1.6
			local last = k == 3
			local seg = decor(m, "Horn", Vector3.new(s, len, s), CFrame.fromMatrix(p + dir * len / 2, f.S, dir), if last then d.Tip else d.Color, if last then Enum.Material.Neon else Enum.Material.Basalt, mode, i + k * 0.2)
			if not last and skin.Texture then
				HeldModels.applyTexture(seg, skin.Texture)
			end
			p += dir * len * 0.85
			s *= 0.72
		end
	end
end

-- Rayos en zigzag por los dos lados (Tormenta)
decorBuilders.Bolts = function(m, f, d, mode)
	local th = math.clamp(math.min(f.HU, f.HS) * 0.28, 0.035, 0.07)
	for _, side in { 1, -1 } do
		local pts = {}
		for i = 0, 5 do
			local x = (-0.85 + 1.7 * i / 5) * f.HL
			local y = (if i % 2 == 0 then 0.7 else -0.7) * f.HU
			table.insert(pts, f.Center + f.L * x + f.U * y + f.S * side * (f.HS + 0.015))
		end
		for i = 1, #pts - 1 do
			local a, b = pts[i], pts[i + 1]
			decor(m, "Bolt", Vector3.new(th, th, (b - a).Magnitude + th), CFrame.lookAt((a + b) / 2, b, f.S * side), d.Color, Enum.Material.Neon, mode, i * 0.5)
		end
	end
end

-- Anillo orbital inclinado alrededor del cuerpo, con un planeta (Galaxia)
decorBuilders.Orbit = function(m, f, d, mode, skin)
	local R = math.max(f.HU, f.HS) * 2.1 + 0.1
	local c = f.Center + f.L * f.HL * 0.1
	local n = (f.L + f.U * 0.4).Unit
	local a1 = (f.U - n * f.U:Dot(n)).Unit
	local a2 = n:Cross(a1)
	local count = 24
	local th = math.clamp(R * 0.07, 0.025, 0.05)
	local seg = 2 * math.pi * R / count
	for i = 0, count - 1 do
		local t = i / count * 2 * math.pi
		local p = c + (a1 * math.cos(t) + a2 * math.sin(t)) * R
		local tangent = -a1 * math.sin(t) + a2 * math.cos(t)
		decor(m, "Orbit", Vector3.new(th * 1.6, th * 0.6, seg * 1.08), CFrame.lookAt(p, p + tangent, n), d.Color, Enum.Material.Neon, mode, i * 0.26)
	end
	local planet = decor(m, "Planet", Vector3.one * R * 0.42, CFrame.new(c + (a1 * 0.6 + a2 * 0.8) * R), d.Planet or d.Color, Enum.Material.SmoothPlastic, nil, 0)
	planet.Shape = Enum.PartType.Ball
	if skin.Texture then
		HeldModels.applyTexture(planet, { Id = skin.Texture.Id, Tile = 0.6 })
	end
	local moon = decor(m, "PlanetMoon", Vector3.one * R * 0.16, CFrame.new(c - (a1 * 0.7 + a2 * 0.7) * R), Color3.fromRGB(235, 225, 255), Enum.Material.Neon, mode, 1.5)
	moon.Shape = Enum.PartType.Ball
end

-- Corona de prismas alrededor de la punta (Prisma)
decorBuilders.Crown = function(m, f, d, mode)
	local rr = math.max(f.HU, f.HS) * 1.05
	local front = f.Center + f.L * f.HL * 0.75
	local a = math.clamp(math.min(f.HU, f.HS) * 0.6, 0.07, 0.17)
	local count = 6
	for i = 0, count - 1 do
		local t = i / count * 2 * math.pi
		local radial = f.U * math.cos(t) + f.S * math.sin(t)
		local dir = (radial * 0.85 + f.L * 0.55).Unit
		local h = a * (if i % 2 == 0 then 4.2 else 3)
		local pos = front + radial * rr + dir * h * 0.4
		local cf = CFrame.fromMatrix(pos, dir:Cross(f.L).Magnitude > 0.01 and dir:Cross(f.L).Unit or f.S, dir) * CFrame.Angles(0, math.rad(45), 0)
		local glass = decor(m, "Prism", Vector3.new(a, h, a), cf, d.Color, Enum.Material.Glass, nil, 0)
		glass.Transparency = 0.55
		glass.Reflectance = 0.5
		decor(m, "PrismCore", Vector3.new(a * 0.65, h * 0.85, a * 0.65), cf, Color3.fromHSV(i / count, 0.8, 1), Enum.Material.Neon, mode, i * 1.05)
	end
end

-- Alas de plumas de fuego y cola (Fenix)
decorBuilders.Wings = function(m, f, d, mode, skin)
	local W = math.clamp(f.HL * 1.15, 0.5, 0.9)
	local anchor = f.Center - f.L * f.HL * 0.1 + f.U * f.HU * 0.35
	local function feather(root: Vector3, dir: Vector3, len: number, width: number, color: Color3, phase: number)
		local normal = (f.U - dir * f.U:Dot(dir))
		normal = if normal.Magnitude > 0.05 then normal.Unit else f.S
		local th = 0.03
		local body = decor(m, "Feather", Vector3.new(len, th, width), CFrame.fromMatrix(root + dir * len / 2, dir, normal), color, Enum.Material.SmoothPlastic, nil, 0)
		if skin.Texture then
			HeldModels.applyTexture(body, { Id = skin.Texture.Id, Tile = 0.5 })
		end
		decor(m, "FeatherTip", Vector3.new(len * 0.28, th * 1.3, width * 0.75), CFrame.fromMatrix(root + dir * len * 0.88, dir, normal), d.Tip, Enum.Material.Neon, mode, phase)
	end
	for _, side in { 1, -1 } do
		local root = anchor + f.S * side * f.HS * 0.9
		for k = 1, 5 do
			local phi = math.rad(5 + (k - 1) * 16)
			local psi = math.rad(58 - k * 8) -- alzadas: se leen como alas
			local dir = ((f.S * side * math.cos(phi) - f.L * math.sin(phi)) * math.cos(psi) + f.U * math.sin(psi)).Unit
			local color = if k <= 2 then d.Base:Lerp(d.Mid, (k - 1) / 2) else d.Mid:Lerp(d.Tip, (k - 3) / 2)
			feather(root + f.U * k * 0.008, dir, W * (0.62 + 0.1 * k), W * 0.3, color, k * 0.4)
		end
	end
	-- cola: tres plumas largas hacia atras
	local tail = f.Center - f.L * f.HL * 0.9
	for k = -1, 1 do
		local dir = (-f.L + f.S * k * 0.35 - f.U * 0.15).Unit
		feather(tail, dir, W * 1.1, W * 0.2, d.Mid, 3 + k)
	end
end

-- Aplica una skin (Config.Skins[skinId]) a las piezas pintables del modelo y le pone sus
-- adornos segun la rareza: textura, emblema, anillos, piezas propias, luz, particulas y
-- animacion (ver Config.Skins).
function HeldModels.applySkin(model: Model, skinId: string?)
	local skins = (Config :: any).Skins
	local skin = skinId and skins and skins[skinId]
	if not skin then
		return
	end
	local mode = skin.Anim
	local bodies: { BasePart } = {}
	local index = 0
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local paint = d:GetAttribute("Paint")
			local style = paint and skin[paint]
			if style then
				index += 1
				if style.Color then
					d.Color = style.Color
				end
				if style.Material then
					d.Material = style.Material
				end
				if style.Reflectance then
					d.Reflectance = style.Reflectance
				end
				if style.Transparency then
					d.Transparency = style.Transparency
				end
				if paint == "Body" and skin.Texture then
					HeldModels.applyTexture(d, skin.Texture)
				end
				-- Lo que brilla (neon) se anima; el cuerpo no
				if paint ~= "Body" and d.Material == Enum.Material.Neon then
					markAnim(d, mode, index * 0.9)
				end
			end
			if paint == "Body" then
				table.insert(bodies, d)
			end
		end
	end
	if #bodies == 0 then
		return
	end
	if skin.Bands then
		for i, body in bodies do
			addBands(model, body, skin.Bands, mode, i)
		end
	end
	-- Luz y particulas en la pieza del cuerpo mas grande
	table.sort(bodies, function(a, b)
		return a.Size.Magnitude > b.Size.Magnitude
	end)
	local main = bodies[1]
	local frame = bodyFrame(main)
	if skin.Emblem then
		addEmblem(model, frame, skin.Emblem)
	end
	local build = skin.Decor and decorBuilders[skin.Decor.Type]
	if build then
		build(model, frame, skin.Decor, mode, skin)
	end
	if skin.Light then
		local light = Instance.new("PointLight")
		light.Name = "SkinLight"
		light.Color = skin.Light.Color
		light.Brightness = skin.Light.Brightness or 1
		light.Range = skin.Light.Range or 6
		light.Shadows = false
		light.Parent = main
		markAnim(light, mode, 0)
	end
	for i, p in skin.Particles or {} do
		local emitter = Instance.new("ParticleEmitter")
		emitter.Name = "SkinParticles" .. i
		emitter.Texture = p.Texture
		emitter.Color = if typeof(p.Color) == "ColorSequence" then p.Color else ColorSequence.new(p.Color or Color3.new(1, 1, 1))
		emitter.Rate = p.Rate or 5
		emitter.Lifetime = toRange(p.Lifetime or { 0.5, 1 })
		emitter.Size = toSequence(p.Size, 0.15)
		emitter.Speed = toRange(p.Speed or { 0, 0.3 })
		emitter.SpreadAngle = Vector2.new(p.Spread or 180, p.Spread or 180)
		emitter.LightEmission = p.LightEmission or 0
		emitter.Transparency = if p.Transparency
			then NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.2, p.Transparency), NumberSequenceKeypoint.new(1, 1) })
			else NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.7, 0.2), NumberSequenceKeypoint.new(1, 1) })
		emitter.Acceleration = p.Accel or Vector3.zero
		emitter.Rotation = NumberRange.new(0, 360)
		emitter.RotSpeed = NumberRange.new(-90, 90)
		emitter.LightInfluence = 0
		emitter.Parent = main
	end
end

-- Modelo nuevo de `id` (con su skin, si la hay). nil si no hay modelo para ese id.
function HeldModels.build(id: string, skinId: string?): Model?
	local skins = (Config :: any).Skins
	local skinned = skinId ~= nil and skins ~= nil and skins[skinId] ~= nil
	local t = if skinned then nil else template(id)
	if t then
		local model = t:Clone()
		model.Name = id
		model.PrimaryPart = model:FindFirstChild("Handle") :: BasePart
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = false
				d.CanCollide = false
				d.CanQuery = false
				d.CanTouch = false
				d.Massless = true
				d.CastShadow = false
			end
		end
		model:PivotTo(CFrame.identity)
		return model
	end
	local builder = builders[id]
	if not builder then
		return nil
	end
	local model = newModel(id)
	builder(model)
	HeldModels.applySkin(model, skinId)
	return model
end

-- Enciende o apaga la lente de la linterna (Neon cuando alumbra).
function HeldModels.setLit(model: Model, lit: boolean, color: Color3?)
	local lens = model:FindFirstChild("Lens")
	if lens and lens:IsA("BasePart") then
		lens.Material = if lit then Enum.Material.Neon else Enum.Material.Glass
		lens.Color = if lit then (color or Color3.fromRGB(255, 244, 214)) else Color3.fromRGB(210, 210, 200)
	end
end

-- Convierte el modelo en el contenido de una Tool: el Handle pasa a ser el de la Tool
-- y las demas piezas se sueldan a el. Devuelve el Handle.
function HeldModels.intoTool(model: Model, tool: Tool): BasePart
	local handle = model.PrimaryPart :: BasePart
	for _, d in model:GetChildren() do
		if d:IsA("BasePart") and d ~= handle then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = handle
			weld.Part1 = d
			weld.Parent = d
			d.Anchored = false
			d.Parent = handle
		end
	end
	handle.Anchored = false
	handle.Parent = tool
	model:Destroy()
	return handle
end

-- Suelda el modelo (sin anclar) a una parte del personaje (la linterna a la mano izquierda).
function HeldModels.attach(model: Model, to: BasePart, offset: CFrame)
	local handle = model.PrimaryPart :: BasePart
	model:PivotTo(to.CFrame * offset)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = false
			if d ~= handle then
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = handle
				weld.Part1 = d
				weld.Parent = d
			end
		end
	end
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = to
	weld.Part1 = handle
	weld.Parent = handle
	model.Parent = to.Parent
end

return HeldModels
