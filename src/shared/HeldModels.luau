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
-- partes marcadas con el atributo "Paint" ("Body" | "Accent"). Sin skin: los colores
-- originales.

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

function HeldModels.has(id: string): boolean
	return builders[id] ~= nil
end

-- Aplica una skin (Config.Skins[skinId]) a las piezas pintables del modelo.
function HeldModels.applySkin(model: Model, skinId: string?)
	local skins = (Config :: any).Skins
	local skin = skinId and skins and skins[skinId]
	if not skin then
		return
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local paint = d:GetAttribute("Paint")
			local style = paint and skin[paint]
			if style then
				if style.Color then
					d.Color = style.Color
				end
				if style.Material then
					d.Material = style.Material
				end
				if style.Reflectance then
					d.Reflectance = style.Reflectance
				end
			end
		end
	end
end

-- Modelo nuevo de `id` (con su skin, si la hay). nil si no hay modelo para ese id.
function HeldModels.build(id: string, skinId: string?): Model?
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
