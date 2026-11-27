-- MallBuilder: construye el centro comercial "Plaza Luna" (2 plantas) si el place no
-- tiene un mapa propio (se salta si existe Workspace.Mall o partes con tag MallZone).
-- Desactivar: Config.Debug.BuildTestMap = false
--
-- PLANTA BAJA (suelo y = 0). Norte = +Z.
--   z=110 +------------------------------------------------------------------------+
--         | BODEGA          | SERVICIO: generador · baños · seguridad · escalera   |
--   z=70  +---------+--[1]--[2]--[3]--[4]--[5]--+----------------------------------+
--         | PATIO   |  GALERIA: atrio con fuente y  |  ENTRADA                     |
--         | DE      |  2 pares de escaleras         |  (spawn, info, tienda del    |
--         | COMIDAS |  mecanicas (x = ±61..±92)     |   conserje)                  |
--   z=-70 +---------+--[6]--[7]--[8]--[9]--[10]-+----------------------------------+
--       x=-180    -120                          120                            180
--
-- PLANTA ALTA (suelo y = F2 = 18)
--   z=110 | ALMACEN ALTO | admin · descanso · baños · archivo · maquinas | escalera |
--   z=70  +---------+-[11]-[12]-[13]-[14]-[15]-+--------------------------+
--         |  CINE   | pasillos con barandal (|z| 12..20) y 2   | ZONA DE        |
--         | lobby + | puentes sobre el atrio (x ±53..±61) donde | JUEGOS         |
--         | 2 salas | llegan las escaleras mecanicas            | (arcade)       |
--   z=-70 +---------+-[16]-[17]-[18]-[19]-[20]-+--------------------------+
--
-- ALAS (2026-11-25), un pasaje en el centro de la galeria (x -24..24, donde estaban las
-- tiendas de la columna 3), en las dos plantas:
--   ALA NORTE  z 20..207: cruza servicio/oficinas; 4 tiendas por planta (x ±24..±74),
--              pasillo de servicio oscuro detras (x ±74..±84 y z 207..222) con escalera.
--   ALA SUR    z -167..-20: en obras y a oscuras, 4 locales por planta; al fondo los
--              grandes almacenes cerrados (z -227..-167, x -74..74) con escaleras paradas.
-- El atrio es mas estrecho (|z| < 6): los pasillos de la planta alta miden 14.
--
-- Usa los tags de shared/Tags (zonas, luces, misiones, escondites, camaras...).
-- Modelos 3D opcionales (si no estan, se usan versiones hechas con piezas):
--   ServerStorage.PropTemplates.<Nombre>  (pivote = centro de la base, mirando a -Z)
--   ServerStorage.EnemyTemplates.Mannequin.Body (maniquies de escaparate)

local CollectionService = game:GetService("CollectionService")
local MaterialService = game:GetService("MaterialService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Tags = require(Shared.Tags)
local EntityModels = require(Shared.EntityModels)

local MallBuilder = {}

local Y0 = 0.05 -- el suelo queda un poco por encima del Baseplate (evita parpadeo)
local F2 = 18 -- altura del suelo de la planta alta
local STORE_W, STORE_D, STORE_H = 48, 50, 16
local GALLERY_TOP = F2 + 18 -- techo de los pasillos altos y base del tragaluz
-- El atrio (hueco entre plantas) ocupa |z| < VOID. Era 12 (pasillos altos de 8): con 6 los
-- pasillos de la planta alta miden 14 y cuesta mas que te acorralen.
local VOID = 6
-- Alas nuevas: el pasillo de cada ala ocupa |x| < WING (el hueco de la tienda central)
local WING = 24
local FOOD_H, ENTRY_H, SERVICE_H = 16, 16, 16
local ESC_SPEED = 6 -- studs/s de las escaleras mecanicas

local M = Enum.Material
local WHITE = Color3.fromRGB(236, 234, 228)
local WALL = Color3.fromRGB(214, 206, 192)
local METAL = Color3.fromRGB(120, 124, 130)
local DARK = Color3.fromRGB(28, 28, 32)
local STEEL = Color3.fromRGB(176, 180, 186)
local TRIM = Color3.fromRGB(62, 60, 58)
local GLASS = Color3.fromRGB(190, 215, 220)

local map: Model
local currentParent: Instance
local levelY = 0 -- planta en construccion (0 o F2): at(), wall() y zone() la suman

----------------------------------------------------------------------
-- Materiales PBR (MaterialVariant)
----------------------------------------------------------------------
-- Si MaterialService tiene estas variantes (generadas en Studio), las partes las usan.
-- Si no existen, se queda el material normal de Roblox: el mapa funciona igual.
-- (La IA genero 4 versiones de cada material; estas son las elegidas.)

local VARIANT_BY_MATERIAL = {
	[M.Marble] = "Mall_PolishedMarble",
	[M.CeramicTiles] = "Mall_PorcelainTile2",
	[M.Plaster] = "Mall_PaintedWall1",
	[M.Concrete] = "Mall_ServiceConcrete2",
	[M.WoodPlanks] = "Mall_OakPlanks",
	[M.Carpet] = "Mall_Carpet",
	[M.Metal] = "Mall_BrushedSteel",
}
local CEILING_VARIANT = "Mall_CeilingTile2"

local availableVariants: { [string]: Enum.Material } = {}

local function loadVariants()
	table.clear(availableVariants)
	for _, v in MaterialService:GetDescendants() do
		if v:IsA("MaterialVariant") then
			availableVariants[v.Name] = v.BaseMaterial
		end
	end
end

----------------------------------------------------------------------
-- Helpers basicos
----------------------------------------------------------------------

local function tag(inst: Instance, tagName: string, attributes)
	for k, v in attributes or {} do
		inst:SetAttribute(k, v)
	end
	CollectionService:AddTag(inst, tagName)
end

-- props admite Variant = "Nombre" (MaterialVariant concreto) o false (ninguno).
local function make(className: string, name: string, size: Vector3, cframe: CFrame, material, color: Color3, props): BasePart
	local p = Instance.new(className) :: BasePart
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cframe
	p.Material = material
	p.Color = color
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	local variant = VARIANT_BY_MATERIAL[material]
	for k, v in props or {} do
		if k == "Variant" then
			variant = v
		else
			(p :: any)[k] = v
		end
	end
	if variant and availableVariants[variant] == p.Material then
		p.MaterialVariant = variant
	end
	p.Parent = currentParent
	return p
end

local function box(name: string, size: Vector3, cframe: CFrame, material, color: Color3, props): Part
	return make("Part", name, size, cframe, material, color, props) :: Part
end

-- Pieza decorativa: sin colision ni rayos (no estorba al pathfinding ni a la vision).
local function deco(name: string, size: Vector3, cframe: CFrame, material, color: Color3, props): Part
	local all = { CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = true }
	for k, v in props or {} do
		all[k] = v
	end
	return box(name, size, cframe, material, color, all)
end

local function at(x: number, y: number, z: number): CFrame
	return CFrame.new(x, Y0 + levelY + y, z)
end

local function folder(name: string): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = map
	currentParent = f
	return f
end

-- Rectangulo de suelo (cara superior en y) o techo (con y = altura + 1: cara inferior en altura).
local function slab(name: string, x1, x2, z1, z2, y: number, material, color: Color3, props)
	return box(name, Vector3.new(x2 - x1, 1, z2 - z1), at((x1 + x2) / 2, y - 0.5, (z1 + z2) / 2), material, color, props)
end

-- Igual que slab pero con un hueco rectangular { x1, x2, z1, z2 } (escalera).
local function slabWithHole(name: string, x1, x2, z1, z2, y: number, hole, material, color: Color3, props)
	slab(name, x1, hole[1], z1, z2, y, material, color, props)
	slab(name, hole[2], x2, z1, z2, y, material, color, props)
	slab(name, hole[1], hole[2], z1, hole[3], y, material, color, props)
	slab(name, hole[1], hole[2], hole[4], z2, y, material, color, props)
end

-- Techo de placas acusticas (cara inferior en y - 1).
local function ceiling(x1, x2, z1, z2, y: number)
	return slab("Ceiling", x1, x2, z1, z2, y, M.Plaster, WHITE, { Variant = CEILING_VARIANT })
end

-- Pared recta de p1 a p2 (en el suelo de la planta actual) con huecos: { { From, To, Height } }
-- (From/To = distancia desde p1). Encima de cada hueco queda un dintel.
local function wall(p1: Vector3, p2: Vector3, height: number, opts)
	opts = opts or {}
	local thick = opts.Thickness or 1
	local material = opts.Material or M.Plaster
	local color = opts.Color or WALL
	local delta = Vector3.new(p2.X - p1.X, 0, p2.Z - p1.Z)
	local length = delta.Magnitude
	local dir = delta.Unit
	local origin = Vector3.new(p1.X, Y0 + levelY, p1.Z)

	local function piece(t0, t1, y0, y1)
		if t1 - t0 < 0.05 or y1 - y0 < 0.05 then
			return
		end
		local center = origin + dir * ((t0 + t1) / 2) + Vector3.new(0, (y0 + y1) / 2, 0)
		box("Wall", Vector3.new(thick, y1 - y0, t1 - t0), CFrame.lookAt(center, center + dir), material, color)
		-- Zocalo a los dos lados (los muros "terminados" se ven mucho mas reales)
		if y0 == 0 and opts.Baseboard ~= false then
			local base = origin + dir * ((t0 + t1) / 2) + Vector3.new(0, 0.35, 0)
			deco("Baseboard", Vector3.new(thick + 0.24, 0.7, t1 - t0), CFrame.lookAt(base, base + dir), M.SmoothPlastic, opts.BaseboardColor or TRIM)
		end
	end

	local openings = table.clone(opts.Openings or {})
	table.sort(openings, function(a, b)
		return a.From < b.From
	end)
	local cursor = 0
	for _, o in openings do
		piece(cursor, o.From, 0, height)
		piece(o.From, o.To, o.Height, height)
		cursor = o.To
	end
	piece(cursor, length, 0, height)
end

-- Volumen invisible de zona (desde el suelo de la planta actual hasta `height`).
local function zone(name: string, x1, x2, z1, z2, height: number)
	local p = box(
		"Zone_" .. name,
		Vector3.new(x2 - x1 - 1, height, z2 - z1 - 1),
		at((x1 + x2) / 2, height / 2, (z1 + z2) / 2),
		M.SmoothPlastic,
		Color3.new(1, 1, 1),
		{ Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false, Variant = false }
	)
	tag(p, Tags.Zone, { Zone = name })
end

----------------------------------------------------------------------
-- Luces
----------------------------------------------------------------------

-- Panel LED empotrado en un techo: marco metalico + difusor que ilumina hacia abajo
-- (SurfaceLight: la luz sale del panel como en un mall de verdad, no de un punto).
-- `ceilingCF` = punto del techo (cara inferior). Color frio = servicio (fluorescente).
local function ceilingPanel(ceilingCF: CFrame, zoneName: string, size: Vector2, range: number, brightness: number, cold: boolean?, shadows: boolean?)
	local cf = ceilingCF * CFrame.new(0, -0.12, 0)
	deco("PanelFrame", Vector3.new(size.X + 0.4, 0.2, size.Y + 0.4), cf * CFrame.new(0, 0.02, 0), M.Metal, Color3.fromRGB(215, 215, 218), { CastShadow = false })
	local color = if cold then Color3.fromRGB(225, 240, 255) else Color3.fromRGB(255, 246, 230)
	local p = box("Lamp", Vector3.new(size.X, 0.2, size.Y), cf * CFrame.new(0, -0.04, 0), M.Neon, color, {
		CanCollide = false,
		CanQuery = false,
		CastShadow = false,
	})
	local light = Instance.new("SurfaceLight")
	light.Face = Enum.NormalId.Bottom
	light.Angle = 120
	light.Range = range
	light.Brightness = brightness
	light.Color = if cold then Color3.fromRGB(215, 232, 255) else Color3.fromRGB(255, 232, 200)
	light.Shadows = shadows == true
	light.Parent = p
	tag(p, Tags.Light, { Zone = zoneName })
	return p
end

-- Rejilla de ventilacion del techo (por ella baja el Ducto). ceilingCF = punto del techo.
-- Rejilla de difusor: marco de aluminio con biseles, hueco oscuro, lamas inclinadas y
-- 4 tornillos. Las piezas van soldadas a la rejilla (tag) para temblar con ella cuando el
-- Ducto la sacude (mueve su CFrame).
local function ceilingVent(ceilingCF: CFrame): Part
	local frameColor = Color3.fromRGB(200, 202, 204)
	local vent = deco("CeilingVent", Vector3.new(2.6, 0.06, 2.6), ceilingCF * CFrame.new(0, -0.03, 0), M.Metal, Color3.fromRGB(18, 18, 20), { Variant = false })
	local function attach(part: BasePart)
		part.Anchored = false
		part.Massless = true
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = vent
		weld.Part1 = part
		weld.Parent = part
		part.Parent = vent
	end
	-- Marco (4 listones con bisel)
	for _, side in { -1, 1 } do
		attach(deco("VentFrame", Vector3.new(2.8, 0.14, 0.22), ceilingCF * CFrame.new(0, -0.08, side * 1.29), M.Metal, frameColor, { Variant = false }))
		attach(deco("VentFrame", Vector3.new(0.22, 0.14, 2.8), ceilingCF * CFrame.new(side * 1.29, -0.08, 0), M.Metal, frameColor, { Variant = false }))
	end
	-- Lamas inclinadas (se ve la oscuridad entre ellas)
	for i = -3, 3 do
		attach(deco("VentSlat", Vector3.new(2.36, 0.04, 0.3), ceilingCF * CFrame.new(0, -0.12, i * 0.33) * CFrame.Angles(math.rad(35), 0, 0), M.Metal, Color3.fromRGB(175, 178, 182), {
			CastShadow = false,
			Variant = false,
		}))
	end
	-- Tornillos de las esquinas
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			attach(deco("VentScrew", Vector3.new(0.05, 0.12, 0.12), ceilingCF * CFrame.new(sx * 1.29, -0.16, sz * 1.29) * CFrame.Angles(0, 0, math.rad(90)), M.Metal, Color3.fromRGB(120, 122, 126), {
				Shape = Enum.PartType.Cylinder,
				CastShadow = false,
			}))
		end
	end
	tag(vent, Tags.CeilingVent)
	return vent
end

-- Lampara colgante: cable, pantalla metalica y foco hacia abajo (alturas absolutas de la planta).
local function pendant(x: number, z: number, hangFrom: number, bottom: number, zoneName: string, accent: Color3?)
	deco("LampCable", Vector3.new(0.12, hangFrom - bottom, 0.12), at(x, bottom + (hangFrom - bottom) / 2, z), M.Metal, DARK)
	deco("LampShade", Vector3.new(1.4, 3.6, 3.6), at(x, bottom + 0.4, z) * CFrame.Angles(0, 0, math.rad(90)), M.Metal, accent or Color3.fromRGB(40, 40, 44), {
		Shape = Enum.PartType.Cylinder,
	})
	local p = box("Lamp", Vector3.new(0.2, 3.1, 3.1), at(x, bottom - 0.35, z) * CFrame.Angles(0, 0, math.rad(90)), M.Neon, Color3.fromRGB(255, 240, 215), {
		Shape = Enum.PartType.Cylinder,
		CanCollide = false,
		CanQuery = false,
		CastShadow = false,
	})
	local down = Instance.new("SpotLight")
	down.Face = Enum.NormalId.Left -- el cilindro esta girado: Left mira hacia abajo
	down.Angle = 100
	down.Range = 40
	down.Brightness = 2.2
	down.Color = Color3.fromRGB(255, 234, 205)
	down.Shadows = true
	down.Parent = p
	local fill = Instance.new("PointLight")
	fill.Range = 18
	fill.Brightness = 0.35
	fill.Color = Color3.fromRGB(255, 234, 205)
	fill.Parent = p
	tag(p, Tags.Light, { Zone = zoneName })
	return p
end

-- Luz de emergencia (zonas de servicio, siempre oscuras): caja con piloto rojo/ambar y
-- una luz muy tenue. No lleva el tag MallLight: no se apaga ni se "repara".
local function emergencyLight(ceilingCF: CFrame, amber: boolean?)
	local color = if amber then Color3.fromRGB(255, 150, 50) else Color3.fromRGB(255, 50, 40)
	local cf = ceilingCF * CFrame.new(0, -0.25, 0)
	deco("EmergencyBox", Vector3.new(1.4, 0.45, 0.7), cf, M.SmoothPlastic, Color3.fromRGB(225, 225, 220))
	local lens = deco("EmergencyLens", Vector3.new(1, 0.12, 0.45), cf * CFrame.new(0, -0.26, 0), M.Neon, color, { CastShadow = false })
	local light = Instance.new("PointLight")
	light.Range = 11
	light.Brightness = 0.35
	light.Color = color
	light.Parent = lens
	return lens
end

-- Foco empotrado pequeño (bajo los pasillos altos, en techos bajos).
local function downlight(cf: CFrame, zoneName: string, range: number?, brightness: number?)
	local p = deco("Downlight", Vector3.new(1.2, 0.15, 1.2), cf * CFrame.new(0, -0.08, 0), M.Neon, Color3.fromRGB(255, 240, 220), { CastShadow = false })
	local light = Instance.new("SpotLight")
	light.Face = Enum.NormalId.Bottom
	light.Angle = 90
	light.Range = range or 20
	light.Brightness = brightness or 1.2
	light.Color = Color3.fromRGB(255, 232, 200)
	light.Parent = p
	tag(p, Tags.Light, { Zone = zoneName })
	return p
end

-- Tira de neon de color (decoracion luminosa que se apaga con la zona).
local function neonStrip(size: Vector3, cf: CFrame, color: Color3, zoneName: string, glow: number?)
	local p = deco("NeonStrip", size, cf, M.Neon, color, { CastShadow = false })
	if glow then
		local light = Instance.new("PointLight")
		light.Color = color
		light.Range = 14
		light.Brightness = glow
		light.Parent = p
	end
	tag(p, Tags.Light, { Zone = zoneName })
	return p
end

----------------------------------------------------------------------
-- Carteles y pantallas
----------------------------------------------------------------------

-- Cartel con texto (en la cara `face` de la parte).
local function sign(part: BasePart, text: string, color: Color3, font: Enum.Font, face: Enum.NormalId?)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face or Enum.NormalId.Front
	gui.LightInfluence = 0.2
	gui.Brightness = 1.4
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = font
	label.TextScaled = true
	label.TextColor3 = color
	label.Text = text
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0.12, 0)
	padding.PaddingBottom = UDim.new(0.12, 0)
	padding.PaddingLeft = UDim.new(0.04, 0)
	padding.PaddingRight = UDim.new(0.04, 0)
	padding.Parent = label
	label.Parent = gui
	gui.Parent = part
	return gui
end

-- Cartel retroiluminado: no depende de la luz de la escena (se lee a oscuras).
local function litSign(part: BasePart, text: string, color: Color3, font: Enum.Font, face: Enum.NormalId?)
	local gui = sign(part, text, color, font, face)
	gui.LightInfluence = 0
	gui.Brightness = 2.2
	return gui
end

-- Pantalla encendida (degradado de color + texto opcional): TVs, monitores, cartelera.
local function glowScreen(part: BasePart, face: Enum.NormalId, colorA: Color3, colorB: Color3, text: string?)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.LightInfluence = 0
	gui.Brightness = 1.3
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 24
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Color3.new(1, 1, 1)
	frame.BorderSizePixel = 0
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(colorA, colorB)
	gradient.Rotation = 35
	gradient.Parent = frame
	if text then
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(0.9, 0.6)
		label.Position = UDim2.fromScale(0.05, 0.2)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBlack
		label.TextScaled = true
		label.TextColor3 = Color3.new(1, 1, 1)
		label.TextTransparency = 0.1
		label.Text = text
		label.Parent = frame
	end
	frame.Parent = gui
	gui.Parent = part
	return gui
end

-- Cartel luminoso de "SALIDA" (siempre encendido: tiene bateria propia).
local function exitSign(cframe: CFrame)
	local p = deco("ExitSign", Vector3.new(2.6, 0.9, 0.25), cframe, M.SmoothPlastic, Color3.fromRGB(240, 240, 240))
	local face = deco("ExitFace", Vector3.new(2.4, 0.7, 0.05), cframe * CFrame.new(0, 0, -0.14), M.Neon, Color3.fromRGB(30, 190, 80))
	local light = Instance.new("SurfaceLight")
	light.Face = Enum.NormalId.Front
	light.Range = 8
	light.Brightness = 0.6
	light.Color = Color3.fromRGB(60, 255, 120)
	light.Parent = face
	litSign(face, "SALIDA", Color3.new(1, 1, 1), Enum.Font.GothamBold, Enum.NormalId.Front)
	return p
end

-- Señal amarilla de "piso mojado" (decoracion).
local function wetFloorSign(cframe: CFrame)
	local yellow = Color3.fromRGB(245, 200, 20)
	for _, side in { -1, 1 } do
		local leaf = deco("WetFloorSign", Vector3.new(1.3, 2.4, 0.08), cframe * CFrame.new(0, 1.15, side * 0.38) * CFrame.Angles(math.rad(-side * 18), 0, 0), M.Plastic, yellow)
		sign(leaf, "⚠\nPISO\nMOJADO", Color3.fromRGB(20, 20, 20), Enum.Font.GothamBlack, if side == 1 then Enum.NormalId.Back else Enum.NormalId.Front)
	end
end

-- Cartel publicitario retroiluminado (caja de luz) en una pared. `cf` mira hacia la sala.
local function lightbox(cf: CFrame, width: number, height: number, text: string, accent: Color3, zoneName: string)
	deco("LightboxFrame", Vector3.new(width + 0.4, height + 0.4, 0.3), cf * CFrame.new(0, 0, 0.1), M.Metal, Color3.fromRGB(40, 40, 44))
	local panel = deco("Lightbox", Vector3.new(width, height, 0.1), cf * CFrame.new(0, 0, -0.08), M.SmoothPlastic, accent:Lerp(Color3.new(0, 0, 0), 0.55))
	glowScreen(panel, Enum.NormalId.Front, accent, accent:Lerp(Color3.new(0, 0, 0), 0.6), text)
	local light = Instance.new("SurfaceLight")
	light.Face = Enum.NormalId.Front
	light.Range = 10
	light.Angle = 80
	light.Brightness = 0.6
	light.Color = accent
	light.Parent = panel
	tag(panel, Tags.Light, { Zone = zoneName })
	return panel
end

----------------------------------------------------------------------
-- Modelos 3D (ServerStorage.PropTemplates) con alternativa hecha de piezas
----------------------------------------------------------------------

local propFolder: Instance? = nil

-- Coloca un modelo de PropTemplates con su base en `cframe` (mirando a su -Z).
-- collide = false: decoracion sin colision. Devuelve nil si no existe el modelo.
local function prop(name: string, cframe: CFrame, collide: boolean?): Model?
	local template = propFolder and propFolder:FindFirstChild(name)
	if not template or not template:IsA("Model") then
		return nil
	end
	local clone = template:Clone()
	for _, d in clone:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanTouch = false
			if collide == false then
				d.CanCollide = false
				d.CanQuery = false
			end
		end
	end
	clone:PivotTo(cframe)
	clone.Parent = currentParent
	return clone
end

-- Tiñe las mallas con SurfaceAppearance del modelo (los coches blancos se pintan asi).
local function tintModel(model: Instance, color: Color3)
	for _, d in model:GetDescendants() do
		if d:IsA("SurfaceAppearance") then
			pcall(function()
				(d :: any).Color = color
			end)
		end
	end
end

-- prop o, si no existe, la version de piezas (fallback(cframe)).
-- prop escalado (uniforme) para caber en `size`. `base` = centro de la base, frente -Z.
local function fitProp(name: string, base: CFrame, size: Vector3, collide: boolean?): Model?
	local model = prop(name, base, collide)
	if not model then
		return nil
	end
	local _, extents = model:GetBoundingBox()
	local k = math.min(size.X / extents.X, size.Y / extents.Y, size.Z / extents.Z)
	if math.abs(k - 1) > 0.01 then
		model:ScaleTo(model:GetScale() * k)
		model:PivotTo(base)
	end
	return model
end

local function propOr(name: string, cframe: CFrame, fallback: (CFrame) -> (), collide: boolean?)
	if not prop(name, cframe, collide) then
		fallback(cframe)
	end
end

----------------------------------------------------------------------
-- Mobiliario comun
----------------------------------------------------------------------

local function enemySpawn(x: number, z: number)
	local p = box("EnemySpawn", Vector3.new(2, 0.2, 2), at(x, 0.1, z), M.SmoothPlastic, Color3.new(1, 1, 1), {
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Variant = false,
	})
	tag(p, Tags.EnemySpawn)
end

-- Punto invisible en el suelo para una mision.
local function spot(x: number, z: number, missionType: string, zoneName: string, extra)
	local p = box("Spot_" .. missionType, Vector3.new(1, 0.2, 1), at(x, 0.1, z), M.SmoothPlastic, Color3.new(1, 1, 1), {
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Variant = false,
	})
	local attrs = { MissionType = missionType, Zone = zoneName }
	for k, v in extra or {} do
		attrs[k] = v
	end
	tag(p, Tags.MissionSpot, attrs)
	return p
end

-- Camara de seguridad (tag SecurityCamera). Posiciones relativas a la planta actual.
local function camera(x: number, y: number, z: number, lx: number, ly: number, lz: number)
	local position = Vector3.new(x, Y0 + levelY + y, z)
	local cf = CFrame.lookAt(position, Vector3.new(lx, Y0 + levelY + ly, lz))
	local p = box("SecurityCamera", Vector3.new(1.2, 1, 2), cf, M.SmoothPlastic, Color3.fromRGB(232, 232, 228), {
		CanCollide = false,
		Variant = false,
	})
	tag(p, Tags.SecurityCamera)
	-- Modelo 3D (PropTemplates.SecurityCam): soldado a la pieza (invisible), gira con el barrido
	local mesh = fitProp("SecurityCam", cf * CFrame.new(0, -0.55, 0), Vector3.new(1.3, 1.2, 2.4), false)
	if mesh then
		p.Transparency = 1
		for _, d in mesh:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = false
				d.Massless = true
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = p
				weld.Part1 = d
				weld.Parent = d
				d.Parent = p
			end
		end
		mesh:Destroy()
		-- Soporte: brazo y placa en el techo/pared
		deco("CamMount", Vector3.new(0.25, 1.2, 0.25), CFrame.new(position + Vector3.new(0, 1, 0)), M.Metal, Color3.fromRGB(210, 210, 206))
		deco("CamMountPlate", Vector3.new(0.7, 0.12, 0.7), CFrame.new(position + Vector3.new(0, 1.6, 0)), M.Metal, Color3.fromRGB(210, 210, 206))
		return
	end
	-- Visera y lente: soldadas a la camara para que giren con el barrido
	local hood = deco("CamHood", Vector3.new(1.4, 0.15, 2.3), cf * CFrame.new(0, 0.58, -0.1), M.SmoothPlastic, Color3.fromRGB(210, 210, 206))
	local lens = deco("CamLens", Vector3.new(0.2, 0.7, 0.7), cf * CFrame.new(0, 0, -1.02) * CFrame.Angles(0, math.rad(90), 0), M.Glass, Color3.fromRGB(15, 15, 18), {
		Shape = Enum.PartType.Cylinder,
		Reflectance = 0.3,
	})
	for _, piece in { hood, lens } do
		piece.Anchored = false
		piece.Massless = true
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = p
		weld.Part1 = piece
		weld.Parent = piece
		piece.Parent = p
	end
	deco("CamMount", Vector3.new(0.25, 1.4, 0.25), CFrame.new(position + Vector3.new(0, 1.1, 0)), M.Metal, DARK)
end

-- Escondite (casillero, probador, armario). `cframe` mira hacia donde se sale.
-- Modelo 3D de cada tipo de escondite (PropTemplates). La caja etiquetada se queda
-- (invisible) como colision y punto del escondite.
local HIDE_MODELS = {
	Taquilla = "Locker",
	Casillero = "Locker",
	Armario = "Cabinet",
	["Armario de limpieza"] = "Cabinet",
	["Armario de obra"] = "Cabinet",
	["Baño portátil"] = "PortableToilet",
	["Fotomatón"] = "PhotoBooth",
}

local function hidingSpot(name: string, cframe: CFrame, size: Vector3, material, color: Color3)
	local p = box(name, size, cframe, material, color)
	p:SetAttribute("DisplayName", name)
	tag(p, Tags.HidingSpot)
	local base = cframe * CFrame.new(0, -size.Y / 2, 0)
	local modelName = HIDE_MODELS[name]
	if modelName and fitProp(modelName, base, size, false) then
		p.Transparency = 1
		return p
	end
	-- Probador y cortina del cine: cabina (o tela) con una cortina 3D delante
	if (name == "Probador" or name == "Cortina") and fitProp("FittingCurtain", base * CFrame.new(0, 0, -(size.Z / 2 + 0.3)), Vector3.new(size.X, size.Y, 0.6), false) then
		if name == "Probador" then
			p.Material = M.Wood
			p.Color = Color3.fromRGB(150, 118, 88)
			deco("BoothRail", Vector3.new(size.X + 0.2, 0.25, 0.25), cframe * CFrame.new(0, size.Y / 2 - 0.4, -(size.Z / 2 + 0.3)), M.Metal, STEEL)
		end
		return p
	end
	for i = 0, 2 do
		deco("Vent", Vector3.new(size.X * 0.6, 0.15, 0.1), cframe * CFrame.new(0, size.Y * 0.3 - i * 0.35, -(size.Z / 2 + 0.05)), M.SmoothPlastic, DARK)
	end
	deco("Handle", Vector3.new(0.12, 0.8, 0.12), cframe * CFrame.new(size.X * 0.35, 0, -(size.Z / 2 + 0.08)), M.Metal, STEEL)
	return p
end

-- Tablero electrico (mision Reparar luces).
-- Contenedor de basura: modelo 3D (PropTemplates.Dumpster) con bolsas tiradas al lado, o
-- la caja verde de antes. `cf` en el suelo, frente (tapas) mirando a -Z, largo en X.
-- Devuelve la caja (invisible con el modelo 3D) que lleva el tag de "Tirar basura".
local function dumpster(cf: CFrame): Part
	local body = box("Dumpster", Vector3.new(9, 5, 4.5), cf * CFrame.new(0, 2.5, 0), M.Metal, Color3.fromRGB(40, 85, 45))
	if prop("Dumpster", cf) then
		body.Size = Vector3.new(6.8, 5.6, 4.6)
		body.CFrame = cf * CFrame.new(0, 2.8, 0)
		body.Transparency = 1
		prop("TrashBag", cf * CFrame.new(4.4, 0, -1.2) * CFrame.Angles(0, math.rad(25), math.rad(6)), false)
		prop("TrashBag", cf * CFrame.new(-4.2, 0, -1.6) * CFrame.Angles(0, math.rad(-40), 0), false)
	else
		deco("DumpsterLid", Vector3.new(9.2, 0.3, 4.7), cf * CFrame.new(0, 5.15, 0) * CFrame.Angles(math.rad(-8), 0, 0), M.Plastic, Color3.fromRGB(30, 30, 32))
	end
	return body
end

-- Cajas de carton sobre un palet (centro de la carga en x, z; la tapa del palet a 0.6).
-- Modelo 3D (PropTemplates.StockBox) o el bloque de carton de antes.
local function palletBoxes(x: number, z: number)
	local placed = false
	for i, p in { { -0.95, -1.3 }, { 0.95, -1.3 }, { -0.95, 0 }, { 0.95, 0 }, { -0.95, 1.3 }, { 0.95, 1.3 }, { 0, -0.6, 1 }, { 0.2, 0.8, 1 } } do
		local yaw = math.rad(((i * 37) % 9) - 4)
		if prop("StockBox", at(x + p[1], 0.6 + (p[3] or 0) * 2.08, z + p[2]) * CFrame.Angles(0, math.rad(90) + yaw, 0), false) then
			placed = true
		end
	end
	if not placed then
		box("PalletBoxes", Vector3.new(4, 2.4, 4), at(x, 1.8, z), M.Cardboard, Color3.fromRGB(180, 140, 95), { CanCollide = false })
	end
end

-- Grupo electrogeno: bancada de hormigon con dos generadores 3D (PropTemplates.Generator;
-- si falta, la caja amarilla de antes). Devuelve el panel de la mision Reiniciar
-- generador, delante (invisible con el modelo 3D: el generador ya trae su cuadro).
local function generatorSet(x: number, z: number): Part
	local hasMesh = false
	for _, dx in { -2.6, 2.6 } do
		if prop("Generator", at(x + dx, 0.4, z)) then
			hasMesh = true
		end
	end
	local panel = box("GeneratorPanel", Vector3.new(3, 3, 0.6), at(x, 3.5, z - 2.8), M.Metal, Color3.fromRGB(60, 62, 66))
	if hasMesh then
		box("GeneratorPad", Vector3.new(10.6, 0.4, 6.2), at(x, 0.2, z), M.Concrete, Color3.fromRGB(125, 124, 120))
		deco("GeneratorConduit", Vector3.new(9, 0.5, 0.5), at(x, 0.65, z + 2.9), M.Metal, Color3.fromRGB(60, 62, 66))
		panel.Transparency = 1
		panel.CanCollide = false
	else
		box("Generator", Vector3.new(10, 6, 5), at(x, 3, z), M.Metal, Color3.fromRGB(200, 160, 40))
	end
	return panel
end

-- Imagen de camara de seguridad (CCTV) en la cara Front de `screen`: pasillo en
-- perspectiva en grises verdosos, lineas de barrido, REC, nombre y hora.
-- kind: nil = normal, "NoSignal" = sin señal, "Figure" = una silueta al fondo.
local function cctvFeed(screen: BasePart, camName: string, place: string, kind: string?)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "CCTV"
	gui.Face = Enum.NormalId.Front
	gui.LightInfluence = 0
	gui.Brightness = 1.6
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 90
	gui.ClipsDescendants = true
	gui.Parent = screen

	local function frame(parent: Instance, props): Frame
		local f = Instance.new("Frame")
		f.BorderSizePixel = 0
		for k, v in props do
			(f :: any)[k] = v
		end
		f.Parent = parent
		return f
	end
	local function label(parent: Instance, props): TextLabel
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.Font = Enum.Font.Code
		t.TextScaled = true
		t.TextColor3 = Color3.fromRGB(225, 235, 225)
		t.TextStrokeTransparency = 0.6
		for k, v in props do
			(t :: any)[k] = v
		end
		t.Parent = parent
		return t
	end

	local root = frame(gui, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 1 })
	if kind == "NoSignal" then
		local g = Instance.new("UIGradient")
		g.Color = ColorSequence.new(Color3.fromRGB(70, 72, 78), Color3.fromRGB(28, 30, 34))
		g.Rotation = 90
		g.Parent = root
		label(root, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.7, 0.18),
			Text = "SIN SEÑAL",
			TextColor3 = Color3.fromRGB(240, 240, 240),
			ZIndex = 5,
		})
	else
		local g = Instance.new("UIGradient")
		g.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(26, 32, 29)),
			ColorSequenceKeypoint.new(0.45, Color3.fromRGB(44, 54, 48)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(78, 92, 82)),
		})
		g.Rotation = 90
		g.Parent = root
		-- Pared del fondo, techo con un fluorescente y lineas del suelo hacia el fondo
		frame(root, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.46),
			Size = UDim2.fromScale(0.26, 0.3),
			BackgroundColor3 = Color3.fromRGB(36, 44, 39),
			ZIndex = 2,
		})
		frame(root, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.12),
			Size = UDim2.fromScale(0.22, 0.04),
			BackgroundColor3 = Color3.fromRGB(205, 220, 205),
			ZIndex = 2,
		})
		for _, side in { -1, 1 } do
			frame(root, {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5 + side * 0.3, 0.8),
				Size = UDim2.fromScale(0.55, 0.012),
				Rotation = side * 33,
				BackgroundColor3 = Color3.fromRGB(120, 138, 124),
				ZIndex = 2,
			})
			frame(root, {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5 + side * 0.3, 0.15),
				Size = UDim2.fromScale(0.55, 0.01),
				Rotation = -side * 26,
				BackgroundColor3 = Color3.fromRGB(70, 82, 74),
				ZIndex = 2,
			})
		end
		if kind == "Figure" then
			-- Alguien de pie al fondo del pasillo...
			local figure = frame(root, {
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.fromScale(0.54, 0.6),
				Size = UDim2.fromScale(0.035, 0.17),
				BackgroundColor3 = Color3.fromRGB(8, 10, 9),
				ZIndex = 3,
			})
			local head = frame(figure, {
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.fromScale(0.5, 0),
				Size = UDim2.fromScale(0.9, 0.22),
				BackgroundColor3 = Color3.fromRGB(8, 10, 9),
				ZIndex = 3,
			})
			local c = Instance.new("UICorner")
			c.CornerRadius = UDim.new(0.5, 0)
			c.Parent = head
		end
	end
	-- Lineas de barrido (franjas oscuras) y viñeta
	local scan = frame(root, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), ZIndex = 4 })
	local keys = {}
	for i = 0, 18 do
		table.insert(keys, NumberSequenceKeypoint.new(i / 18, if i % 2 == 0 then 0.82 else 0.97))
	end
	local scanGradient = Instance.new("UIGradient")
	scanGradient.Rotation = 90
	scanGradient.Transparency = NumberSequence.new(keys)
	scanGradient.Parent = scan
	local vignette = frame(root, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), ZIndex = 4 })
	local vg = Instance.new("UIGradient")
	vg.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(0.2, 1),
		NumberSequenceKeypoint.new(0.8, 1),
		NumberSequenceKeypoint.new(1, 0.35),
	})
	vg.Parent = vignette

	-- Rotulos
	label(root, { Position = UDim2.fromScale(0.04, 0.04), Size = UDim2.fromScale(0.4, 0.11), Text = camName, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 6 })
	label(root, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(0.96, 0.04),
		Size = UDim2.fromScale(0.3, 0.11),
		Text = "● REC",
		TextColor3 = Color3.fromRGB(255, 70, 70),
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 6,
	})
	label(root, {
		Position = UDim2.fromScale(0.04, 0.84),
		Size = UDim2.fromScale(0.5, 0.1),
		Text = place,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 6,
	})
	label(root, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(0.96, 0.84),
		Size = UDim2.fromScale(0.42, 0.1),
		Text = string.format("03:%02d:%02d", math.random(0, 59), math.random(0, 59)),
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 6,
	})
end

-- Pared de monitores de seguridad (2 filas x 3) sobre la mesa. `cf` = centro de la pared
-- de monitores (mirando a -Z, hacia la silla). cams = { { "CAM 01", "PASILLO" }, ... }
local function monitorWall(cf: CFrame, cams: { { string } })
	local W, H, GAP = 3.05, 1.8, 0.14
	deco("MonitorRail", Vector3.new(3 * W + 2 * GAP + 0.6, 0.25, 0.25), cf * CFrame.new(0, 0, 0.35), M.Metal, Color3.fromRGB(45, 46, 50))
	deco("MonitorRail", Vector3.new(3 * W + 2 * GAP + 0.6, 0.25, 0.25), cf * CFrame.new(0, H + GAP, 0.35), M.Metal, Color3.fromRGB(45, 46, 50))
	local i = 0
	for row = 0, 1 do
		for _, col in { 1, 0, -1 } do -- (+X queda a la izquierda de quien mira la pared)
			i += 1
			local cam = cams[i]
			local mcf = cf * CFrame.new(col * (W + GAP), (0.5 - row) * (H + GAP), 0) * CFrame.Angles(math.rad(row == 0 and -4 or 3), math.rad(-col * 6), 0)
			deco("MonitorBezel", Vector3.new(W, H, 0.22), mcf, M.SmoothPlastic, Color3.fromRGB(22, 22, 25))
			deco("MonitorBack", Vector3.new(W * 0.6, H * 0.6, 0.3), mcf * CFrame.new(0, 0, 0.25), M.SmoothPlastic, Color3.fromRGB(30, 30, 34))
			local screen = deco("MonitorScreen", Vector3.new(W - 0.18, H - 0.18, 0.04), mcf * CFrame.new(0, 0.02, -0.12), M.Glass, Color3.fromRGB(10, 12, 12), {
				Reflectance = 0.06,
				Variant = false,
			})
			if cam then
				cctvFeed(screen, cam[1], cam[2], cam[3])
			end
			-- LED de encendido
			deco("MonitorLed", Vector3.new(0.06, 0.06, 0.03), mcf * CFrame.new(W / 2 - 0.2, -H / 2 + 0.05, -0.12), M.Neon, Color3.fromRGB(80, 255, 120))
		end
	end
end

-- Silla de oficina con ruedas (asiento, respaldo, columna y base en estrella). `cf` en el suelo,
-- mirando a -Z.
local function officeChair(cf: CFrame)
	local black = Color3.fromRGB(28, 28, 32)
	deco("ChairSeat", Vector3.new(2.2, 0.35, 2.1), cf * CFrame.new(0, 2.1, 0), M.Fabric, black)
	deco("ChairBack", Vector3.new(2.1, 2.4, 0.3), cf * CFrame.new(0, 3.6, 1) * CFrame.Angles(math.rad(-8), 0, 0), M.Fabric, black)
	deco("ChairPole", Vector3.new(0.25, 1.6, 0.25), cf * CFrame.new(0, 1.15, 0), M.Metal, STEEL)
	for k = 0, 4 do
		local leg = cf * CFrame.Angles(0, k * math.pi * 2 / 5, 0)
		deco("ChairLeg", Vector3.new(0.18, 0.15, 1.1), leg * CFrame.new(0, 0.38, -0.55), M.Metal, black)
		deco("ChairWheel", Vector3.new(0.2, 0.28, 0.28), leg * CFrame.new(0, 0.15, -1.05), M.Rubber, black, { Shape = Enum.PartType.Cylinder })
	end
	for _, s in { -1, 1 } do
		deco("ChairArm", Vector3.new(0.2, 0.15, 1.4), cf * CFrame.new(s * 1.1, 2.9, 0.1), M.SmoothPlastic, black)
		deco("ChairArmPost", Vector3.new(0.15, 0.7, 0.15), cf * CFrame.new(s * 1.1, 2.5, 0.4), M.Metal, black)
	end
end

-- Mesa de seguridad: teclado, raton, grabador (DVR) con luces, taza y papeles. `cf` = centro
-- de la superficie de la mesa (y de la tabla), el operador esta en -Z.
local function securityDeskTop(cf: CFrame, minimal: boolean?)
	deco("Keyboard", Vector3.new(1.7, 0.08, 0.55), cf * CFrame.new(-0.4, 0.04, -0.6) * CFrame.Angles(math.rad(4), 0, 0), M.SmoothPlastic, Color3.fromRGB(30, 30, 34))
	deco("Mouse", Vector3.new(0.22, 0.1, 0.35), cf * CFrame.new(0.9, 0.05, -0.6), M.SmoothPlastic, Color3.fromRGB(30, 30, 34))
	if minimal then
		return
	end
	deco("Joystick", Vector3.new(0.6, 0.15, 0.5), cf * CFrame.new(2, 0.08, -0.5), M.SmoothPlastic, Color3.fromRGB(40, 40, 46))
	deco("JoystickStick", Vector3.new(0.1, 0.4, 0.1), cf * CFrame.new(2, 0.35, -0.5), M.SmoothPlastic, Color3.fromRGB(20, 20, 22))
	local dvr = deco("DVR", Vector3.new(2.2, 0.45, 1.3), cf * CFrame.new(-3.2, 0.23, 0.2), M.Metal, Color3.fromRGB(35, 36, 40))
	for k = 0, 3 do
		deco("DvrLed", Vector3.new(0.08, 0.08, 0.02), dvr.CFrame * CFrame.new(-0.8 + k * 0.18, 0.05, -0.66), M.Neon, if k == 3 then Color3.fromRGB(255, 80, 60) else Color3.fromRGB(80, 255, 120))
	end
	deco("CoffeeCup", Vector3.new(0.45, 0.32, 0.32), cf * CFrame.new(3.4, 0.23, -0.3) * CFrame.Angles(0, 0, math.rad(90)), M.SmoothPlastic, Color3.fromRGB(235, 235, 230), {
		Shape = Enum.PartType.Cylinder,
	})
	deco("Papers", Vector3.new(1, 0.04, 1.3), cf * CFrame.new(2.6, 0.02, 0.3) * CFrame.Angles(0, math.rad(12), 0), M.SmoothPlastic, Color3.fromRGB(235, 232, 222))
	deco("Radio", Vector3.new(0.35, 0.9, 0.2), cf * CFrame.new(-1.8, 0.45, 0.1), M.SmoothPlastic, Color3.fromRGB(25, 25, 28))
end

local function electricPanel(cframe: CFrame, zoneName: string)
	local p = box("ElectricPanel", Vector3.new(2.4, 3.6, 0.6), cframe, M.DiamondPlate, Color3.fromRGB(90, 95, 100))
	tag(p, Tags.MissionSpot, { MissionType = "FixLights", Zone = zoneName })
	deco("PanelWarning", Vector3.new(1, 0.6, 0.05), cframe * CFrame.new(0, 1.2, -0.33), M.SmoothPlastic, Color3.fromRGB(240, 200, 30))
	deco("Conduit", Vector3.new(0.3, 6, 0.3), cframe * CFrame.new(0.6, 4.8, 0.1), M.Metal, METAL)
	return p
end

-- Reloj de control de la ronda de seguridad (mision Ronda de seguridad): poste con una
-- caja y un piloto (hijo "Led": rojo, verde al fichar).
-- Es un punto de fichaje fino y SIN colision (antes era un poste negro que estorbaba).
local function patrolClock(x: number, z: number, zoneName: string)
	local steel = Color3.fromRGB(165, 170, 178)
	deco("ClockBase", Vector3.new(0.12, 1.1, 1.1), at(x, 0.06, z) * CFrame.Angles(0, 0, math.rad(90)), M.Metal, steel, { Shape = Enum.PartType.Cylinder })
	deco("ClockPost", Vector3.new(3.6, 0.22, 0.22), at(x, 1.9, z) * CFrame.Angles(0, 0, math.rad(90)), M.Metal, steel, { Shape = Enum.PartType.Cylinder })
	local clock = deco("PatrolClock", Vector3.new(0.9, 1.1, 0.5), at(x, 4.15, z), M.SmoothPlastic, Color3.fromRGB(32, 34, 40), { Variant = false })
	-- Lector de tarjeta a cada lado (con la leyenda) y piloto arriba (rojo; verde al fichar)
	for _, side in { -1, 1 } do
		local reader = deco("ClockReader", Vector3.new(0.6, 0.45, 0.04), at(x, 4.0, z + side * 0.27), M.SmoothPlastic, Color3.fromRGB(20, 60, 110))
		litSign(reader, "RONDA", Color3.fromRGB(170, 220, 255), Enum.Font.Code, if side < 0 then Enum.NormalId.Front else Enum.NormalId.Back)
	end
	local led = deco("Led", Vector3.new(0.3, 0.12, 0.54), at(x, 4.6, z), M.Neon, Color3.fromRGB(220, 40, 40), { CastShadow = false })
	led.Parent = clock
	tag(clock, Tags.PatrolClock, { Zone = zoneName })
	return clock
end

-- Pie de pared: `cf` = punto de la pared a ras de suelo, con el frente (-Z) hacia la sala.

-- Extintor de pared con soporte y cartel (mision Revisar extintores). floorName = "Planta baja" / "Planta alta".
local function wallExtinguisher(cf: CFrame, floorName: string)
	deco("ExtBracket", Vector3.new(0.9, 0.3, 0.3), cf * CFrame.new(0, 3.4, -0.15), M.Metal, DARK)
	-- Extintor 3D (el mismo de la mano, PropTemplates.WallExtinguisher) colgado del soporte
	local mesh = fitProp("WallExtinguisher", cf * CFrame.new(0, 1.55, -0.5), Vector3.new(1, 2.3, 1), false)
	local body = box("WallExtinguisher", Vector3.new(2, 0.7, 0.7), cf * CFrame.new(0, 2.6, -0.5) * CFrame.Angles(0, 0, math.rad(90)), M.SmoothPlastic, Color3.fromRGB(200, 25, 25), {
		Shape = Enum.PartType.Cylinder,
		CanCollide = false,
		Variant = false,
	})
	if mesh then
		body.Transparency = 1
	else
		deco("ExtHead", Vector3.new(0.35, 0.4, 0.35), cf * CFrame.new(0, 3.75, -0.5), M.Metal, DARK)
		deco("ExtHose", Vector3.new(0.12, 1.4, 0.12), cf * CFrame.new(0.3, 3.1, -0.85) * CFrame.Angles(0, 0, math.rad(15)), M.Rubber, Color3.fromRGB(25, 25, 25))
	end
	local signPart = deco("ExtSign", Vector3.new(1.4, 0.8, 0.06), cf * CFrame.new(0, 5, -0.05), M.SmoothPlastic, Color3.fromRGB(200, 25, 25))
	litSign(signPart, "EXTINTOR", Color3.new(1, 1, 1), Enum.Font.GothamBlack, Enum.NormalId.Front)
	tag(body, Tags.Extinguisher, { Floor = floorName })
end

-- Telefono publico de pared (mision Telefono sonando).
local function payPhone(cf: CFrame, zoneName: string)
	local phone = box("PayPhone", Vector3.new(1.6, 2.6, 0.8), cf * CFrame.new(0, 4.2, -0.4), M.Metal, Color3.fromRGB(45, 70, 110), { Variant = false })
	-- Telefono 3D (PropTemplates.PayPhone); la caja etiquetada queda invisible
	if fitProp("PayPhone", cf * CFrame.new(0, 2.8, -0.5), Vector3.new(1.8, 2.9, 1), false) then
		phone.Transparency = 1
		phone.CanCollide = false
	else
		deco("PhoneHandset", Vector3.new(0.3, 1.4, 0.35), cf * CFrame.new(-0.55, 4.4, -0.95), M.SmoothPlastic, DARK)
		deco("PhoneKeypad", Vector3.new(0.7, 0.9, 0.05), cf * CFrame.new(0.25, 4.2, -0.82), M.SmoothPlastic, Color3.fromRGB(180, 182, 186))
		deco("PhoneCord", Vector3.new(0.08, 1.2, 0.08), cf * CFrame.new(-0.55, 3.4, -0.9), M.Rubber, DARK)
	end
	local signPart = deco("PhoneSign", Vector3.new(1.6, 0.5, 0.06), cf * CFrame.new(0, 5.8, -0.4), M.SmoothPlastic, Color3.fromRGB(30, 60, 120))
	litSign(signPart, "TELÉFONO", Color3.new(1, 1, 1), Enum.Font.GothamBold, Enum.NormalId.Front)
	tag(phone, Tags.PayPhone, { Zone = zoneName })
end

-- Valvula de purga de la caldera en una pared: tubo, cuerpo y rueda roja (hijo "Wheel").
local function boilerValve(cf: CFrame, zoneName: string)
	deco("ValvePipe", Vector3.new(0.5, 6, 0.5), cf * CFrame.new(0, 3, -0.4), M.Metal, METAL)
	local body = box("BoilerValve", Vector3.new(1, 1, 1), cf * CFrame.new(0, 3.6, -0.6), M.Metal, Color3.fromRGB(90, 92, 96), { Variant = false })
	-- (cilindro: su eje X apunta hacia fuera de la pared)
	local wheel = deco("Wheel", Vector3.new(0.2, 1.8, 1.8), cf * CFrame.new(0, 3.6, -1.25) * CFrame.Angles(0, math.rad(90), 0), M.Metal, Color3.fromRGB(190, 40, 35), {
		Shape = Enum.PartType.Cylinder,
	})
	wheel.Parent = body
	tag(body, Tags.BoilerValve, { Zone = zoneName })
end

local LEAF_COLORS = {
	Color3.fromRGB(52, 98, 44),
	Color3.fromRGB(66, 118, 52),
	Color3.fromRGB(44, 84, 40),
}

-- Macetero de granito con planta (tag Planter, mision Regar plantas).
-- small = version estrecha para los pasillos altos.
local function planter(x: number, z: number, zoneName: string, small: boolean?)
	local w, h, d = 7, 2.4, 3.6
	if small then
		w, h, d = 5, 2.2, 2.4
	end
	local base = box("Planter", Vector3.new(w, h, d), at(x, h / 2, z), M.Granite, Color3.fromRGB(120, 116, 110))
	deco("PlanterLip", Vector3.new(w + 0.4, 0.3, d + 0.4), at(x, h + 0.05, z), M.Granite, Color3.fromRGB(95, 92, 88))
	deco("Soil", Vector3.new(w - 0.6, 0.3, d - 0.6), at(x, h + 0.1, z), M.Ground, Color3.fromRGB(55, 40, 30))
	tag(base, Tags.Planter, { Zone = zoneName })
	-- Planta: modelo 3D (ficus) o arbol de piezas
	local plantCF = at(x, h + 0.2, z)
	if small then
		for i, ox in { -1.4, 1.4 } do
			if not prop("FicusSmall", plantCF * CFrame.new(ox, 0, 0) * CFrame.Angles(0, i * 2, 0), false) then
				deco("Leaves", Vector3.new(2.4, 2.6, 2.4), plantCF * CFrame.new(ox, 1.4, 0), M.Grass, LEAF_COLORS[i], { Shape = Enum.PartType.Ball })
			end
		end
		return
	end
	if prop("Ficus", plantCF, false) then
		return
	end
	deco("Trunk", Vector3.new(0.5, 5.6, 0.5), at(x, h + 3, z) * CFrame.Angles(0, 0, math.rad(4)), M.Wood, Color3.fromRGB(95, 75, 55))
	deco("Branch", Vector3.new(0.3, 3, 0.3), at(x + 0.8, h + 4.6, z) * CFrame.Angles(0, 0, math.rad(-35)), M.Wood, Color3.fromRGB(95, 75, 55))
	local clumps = { { 0, 6.8, 0, 4.2 }, { 1.6, 5.6, 0.8, 3.2 }, { -1.4, 5.2, -0.6, 3 }, { 0.4, 8.2, -0.4, 2.8 }, { -0.6, 3.8, 1, 2.2 } }
	for i, c in clumps do
		deco("Leaves", Vector3.new(c[4], c[4] * 0.85, c[4]), at(x + c[1], h + c[2], z + c[3]), M.Grass, LEAF_COLORS[i % #LEAF_COLORS + 1], {
			Shape = Enum.PartType.Ball,
		})
	end
end

-- Banca de listones de madera sobre patas de acero.
local function bench(cframe: CFrame)
	-- Banca 3D (PropTemplates.MallBench: patas de acero, listones, respaldo y apoyabrazos)
	if prop("MallBench", cframe) then
		return
	end
	local wood = Color3.fromRGB(140, 98, 62)
	for i = -1, 1 do
		box("BenchSlat", Vector3.new(6, 0.22, 0.55), cframe * CFrame.new(0, 1.55, i * 0.68), M.Wood, wood)
	end
	for i = 0, 1 do
		deco("BenchBackSlat", Vector3.new(6, 0.5, 0.18), cframe * CFrame.new(0, 2.3 + i * 0.7, 1.05) * CFrame.Angles(math.rad(-10), 0, 0), M.Wood, wood)
	end
	for _, x in { -2.5, 2.5 } do
		box("BenchLeg", Vector3.new(0.3, 1.45, 2), cframe * CFrame.new(x, 0.72, 0), M.Metal, Color3.fromRGB(50, 50, 54))
		deco("BenchBackPost", Vector3.new(0.25, 1.8, 0.25), cframe * CFrame.new(x, 2.4, 1.08) * CFrame.Angles(math.rad(-10), 0, 0), M.Metal, Color3.fromRGB(50, 50, 54))
	end
end

-- Papelera de acero inoxidable con tapa. zoneName: es de la mision Vaciar papeleras
-- (tag Wastebasket con esa zona, el ala de la galeria).
local function trashBin(cframe: CFrame, zoneName: string?)
	local bin = box("TrashBin", Vector3.new(2.6, 1.8, 1.8), cframe * CFrame.new(0, 1.3, 0) * CFrame.Angles(0, 0, math.rad(90)), M.Metal, STEEL, {
		Shape = Enum.PartType.Cylinder,
	})
	if zoneName then
		tag(bin, Tags.Wastebasket, { Zone = zoneName })
	end
	deco("TrashLid", Vector3.new(0.35, 2, 2), cframe * CFrame.new(0, 2.75, 0) * CFrame.Angles(0, 0, math.rad(90)), M.Metal, Color3.fromRGB(45, 45, 48), {
		Shape = Enum.PartType.Cylinder,
	})
	deco("TrashBase", Vector3.new(0.2, 1.9, 1.9), cframe * CFrame.new(0, 0.1, 0) * CFrame.Angles(0, 0, math.rad(90)), M.Metal, Color3.fromRGB(45, 45, 48), {
		Shape = Enum.PartType.Cylinder,
	})
end

-- Columna con base, capitel y anillo de acero.
local function column(x: number, z: number, height: number, width: number)
	box("Column", Vector3.new(width, height, width), at(x, height / 2, z), M.Marble, Color3.fromRGB(245, 243, 238))
	deco("ColumnBase", Vector3.new(width + 0.6, 1.2, width + 0.6), at(x, 0.6, z), M.Granite, Color3.fromRGB(70, 66, 64))
	deco("ColumnCap", Vector3.new(width + 0.8, 0.8, width + 0.8), at(x, height - 0.4, z), M.Plaster, WHITE)
	deco("ColumnBand", Vector3.new(width + 0.1, 0.35, width + 0.1), at(x, 9, z), M.Metal, STEEL)
end

-- Barandal de vidrio con pasamanos (con colision: no se cae nadie al atrio).
-- De p1 a p2 en el suelo de la planta actual.
local function railing(p1: Vector3, p2: Vector3)
	local a = Vector3.new(p1.X, Y0 + levelY, p1.Z)
	local b = Vector3.new(p2.X, Y0 + levelY, p2.Z)
	local length = (b - a).Magnitude
	if length < 0.1 then
		return
	end
	local mid = (a + b) / 2
	local cf = CFrame.lookAt(mid, mid + (b - a))
	-- Vidrio templado (colision) sobre perfil de aluminio, en paneles con juntas y pinzas,
	-- pasamanos redondo de acero sobre soportes y tira LED calida debajo
	box("RailingGlass", Vector3.new(0.15, 3.8, length), cf * CFrame.new(0, 1.9, 0), M.Glass, Color3.fromRGB(200, 225, 220), {
		Transparency = 0.75,
		Reflectance = 0.25,
		CastShadow = false,
		Variant = false,
	})
	deco("RailShoe", Vector3.new(0.5, 0.45, length), cf * CFrame.new(0, 0.22, 0), M.Metal, Color3.fromRGB(150, 154, 160), { Variant = false })
	deco("RailShoeCap", Vector3.new(0.56, 0.06, length), cf * CFrame.new(0, 0.47, 0), M.Metal, Color3.fromRGB(205, 208, 212), { Variant = false })
	deco("Handrail", Vector3.new(length, 0.32, 0.32), cf * CFrame.new(0, 4.25, 0) * CFrame.Angles(0, math.rad(90), 0), M.Metal, STEEL, {
		Shape = Enum.PartType.Cylinder,
	})
	deco("RailCap", Vector3.new(0.22, 0.14, length), cf * CFrame.new(0, 3.86, 0), M.Metal, STEEL)
	deco("RailLight", Vector3.new(0.05, 0.05, length), cf * CFrame.new(0, 4.06, 0), M.Neon, Color3.fromRGB(255, 225, 180), {
		CastShadow = false,
		Variant = false,
	})
	local panels = math.max(1, math.floor(length / 6))
	for i = 0, panels do
		local z = -length / 2 + i * (length / panels)
		-- Soporte del pasamanos y, entre paneles, la junta del vidrio con sus pinzas
		deco("RailBracket", Vector3.new(0.1, 0.4, 0.1), cf * CFrame.new(0, 4.03, z), M.Metal, STEEL)
		if i > 0 and i < panels then
			deco("GlassJoint", Vector3.new(0.17, 3.3, 0.04), cf * CFrame.new(0, 2.15, z), M.SmoothPlastic, Color3.fromRGB(60, 70, 72), {
				Transparency = 0.4,
				Variant = false,
			})
		end
		for _, y in { 0.9, 3.4 } do
			deco("GlassClamp", Vector3.new(0.3, 0.3, 0.45), cf * CFrame.new(0, y, z), M.Metal, STEEL)
		end
	end
end

----------------------------------------------------------------------
-- Maquina expendedora (tag VendingMachine)
----------------------------------------------------------------------
-- La parte con el tag es invisible (colision + ProximityPrompt). Lo visible es la
-- maquina: carcasa, vitrina iluminada con latas, panel con pantalla (OddsScreen: alli
-- dibuja VendingService las probabilidades), teclado, monedero y bandeja.
-- `cf` = centro de la maquina a 3.5 del suelo, frente (-Z) hacia los jugadores.

-- Productos de la vitrina: { cuerpo, franja de la etiqueta }
local CAN_FLAVORS = {
	{ Color3.fromRGB(196, 22, 34), Color3.fromRGB(245, 245, 245) }, -- cola
	{ Color3.fromRGB(28, 92, 200), Color3.fromRGB(200, 210, 225) }, -- azul
	{ Color3.fromRGB(70, 175, 60), Color3.fromRGB(250, 220, 60) }, -- lima
	{ Color3.fromRGB(240, 120, 25), Color3.fromRGB(255, 245, 230) }, -- naranja
	{ Color3.fromRGB(120, 50, 170), Color3.fromRGB(240, 240, 245) }, -- uva
	{ Color3.fromRGB(235, 235, 240), Color3.fromRGB(210, 30, 40) }, -- light
	{ Color3.fromRGB(25, 25, 30), Color3.fromRGB(80, 230, 120) }, -- energetica
}
local BOTTLE_FLAVORS = {
	{ Color3.fromRGB(150, 85, 25), Color3.fromRGB(245, 235, 210) }, -- ambar
	{ Color3.fromRGB(40, 140, 70), Color3.fromRGB(250, 250, 250) }, -- verde
	{ Color3.fromRGB(120, 190, 230), Color3.fromRGB(30, 60, 150) }, -- agua
	{ Color3.fromRGB(190, 40, 60), Color3.fromRGB(250, 215, 120) }, -- frutos rojos
	{ Color3.fromRGB(230, 200, 70), Color3.fromRGB(40, 40, 45) }, -- limonada
}

-- SurfaceGui en una cara. light = cuanto le afecta la luz de la escena (0 = brilla sola)
local function surface(part: BasePart, face: Enum.NormalId, ppS: number, light: number, brightness: number?): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = ppS
	gui.LightInfluence = light
	gui.Brightness = brightness or 1
	gui.Parent = part
	return gui
end

local function guiFrame(parent: Instance, props): Frame
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.Size = UDim2.fromScale(1, 1)
	for k, v in props do
		(f :: any)[k] = v
	end
	f.Parent = parent
	return f
end

local function guiText(parent: Instance, text: string, props): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBlack
	l.TextScaled = true
	l.TextColor3 = Color3.new(1, 1, 1)
	l.Text = text
	for k, v in props do
		(l :: any)[k] = v
	end
	l.Parent = parent
	return l
end

local function gradient(parent: Instance, a: Color3, b: Color3, rotation: number)
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(a, b)
	g.Rotation = rotation
	g.Parent = parent
	return g
end

-- Marco de 4 listones alrededor de un rectangulo (x, y centro; w, h interior) en z
local function trimFrame(cf: CFrame, name: string, x: number, y: number, w: number, h: number, z: number, t: number, depth: number, color: Color3, material)
	for _, bar in {
		{ Vector3.new(w + 2 * t, t, depth), Vector3.new(x, y + h / 2 + t / 2, z) },
		{ Vector3.new(w + 2 * t, t, depth), Vector3.new(x, y - h / 2 - t / 2, z) },
		{ Vector3.new(t, h, depth), Vector3.new(x - w / 2 - t / 2, y, z) },
		{ Vector3.new(t, h, depth), Vector3.new(x + w / 2 + t / 2, y, z) },
	} do
		deco(name, bar[1], cf * CFrame.new(bar[2]), material, color, { Reflectance = 0.25, CastShadow = false })
	end
end

local function vendingMachine(cf: CFrame, machineType: string, accent: Color3, title: string)
	local W, H, D = 4.4, 7, 3
	local premium = machineType == "Premium"
	local body = box("Vending_" .. machineType, Vector3.new(W, H, D), cf, M.SmoothPlastic, accent, { Transparency = 1, Variant = false })
	body:SetAttribute("MachineType", machineType)
	local dark = Color3.fromRGB(26, 26, 31)
	local black = Color3.fromRGB(12, 12, 15)
	-- Remates: cromo en las normales, dorado en la premium
	local trim = if premium then Color3.fromRGB(214, 172, 82) else Color3.fromRGB(205, 210, 218)
	local accentDark = accent:Lerp(Color3.new(0, 0, 0), 0.35)
	local accentLight = accent:Lerp(Color3.new(1, 1, 1), 0.25)
	local glossy = { Reflectance = 0.14, Variant = false }

	-- Carcasa con las esquinas verticales redondeadas (nucleo + laterales + 4 cilindros).
	-- Ocupa z de -1.2 (frente) a 1.5 (espalda).
	local shell = deco("VendingShell", Vector3.new(W - 0.3, H - 0.1, D - 0.3), cf * CFrame.new(0, -0.05, 0.15), M.SmoothPlastic, accent, glossy)
	local side = deco("VendingShellSide", Vector3.new(W, H - 0.1, D - 0.6), cf * CFrame.new(0, -0.05, 0.15), M.SmoothPlastic, accent, glossy)
	for _, sx in { -1, 1 } do
		for _, sz in { -1.05, 1.35 } do
			deco("VendingCorner", Vector3.new(H - 0.1, 0.3, 0.3), cf * CFrame.new(sx * (W / 2 - 0.15), -0.05, sz) * CFrame.Angles(0, 0, math.rad(90)), M.SmoothPlastic, accent, {
				Shape = Enum.PartType.Cylinder,
				Reflectance = 0.14,
				Variant = false,
			})
		end
	end
	-- Tapa de arriba y zocalo
	deco("VendingTop", Vector3.new(W - 0.2, 0.08, D - 0.4), cf * CFrame.new(0, H / 2 - 0.06, 0.15), M.Metal, trim, { Reflectance = 0.3, CastShadow = false })
	deco("VendingPlinth", Vector3.new(W - 0.5, 0.3, D - 0.6), cf * CFrame.new(0, -H / 2 + 0.05, 0.15), M.SmoothPlastic, black)
	deco("VendingKick", Vector3.new(W - 0.4, 0.32, 0.06), cf * CFrame.new(0, -H / 2 + 0.26, -1.23), M.SmoothPlastic, black, { Reflectance = 0.1, Variant = false })
	deco("VendingKickTrim", Vector3.new(W - 0.4, 0.04, 0.07), cf * CFrame.new(0, -H / 2 + 0.44, -1.235), M.Metal, trim, { Reflectance = 0.3, CastShadow = false })

	-- Laterales con grafica: degradado, franjas en diagonal y la marca en vertical
	-- (les afecta la luz de la escena: no brillan solos)
	for _, face in { Enum.NormalId.Left, Enum.NormalId.Right } do
		local gui = surface(side, face, 40, 1, 1)
		local bg = guiFrame(gui, { BackgroundColor3 = Color3.new(1, 1, 1), ClipsDescendants = true })
		gradient(bg, accentLight, accentDark, 90)
		for i, spec in { { 0.62, 0.11, 0.05 }, { 0.7, 0.035, 0.25 } } do
			local wave = guiFrame(bg, {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, spec[1]),
				Size = UDim2.fromScale(2.2, spec[2]),
				Rotation = if face == Enum.NormalId.Left then -22 else 22,
				BackgroundColor3 = if i == 1 then Color3.new(1, 1, 1) else trim,
				BackgroundTransparency = spec[3],
			})
			wave.ZIndex = 2
		end
		local brand = guiText(bg, title, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.4),
			Size = UDim2.fromScale(2.0, 0.32), -- (girado: el ancho pasa a ser el alto)
			Rotation = -90,
			TextTransparency = 0.05,
			ZIndex = 3,
		})
		local stroke = Instance.new("UIStroke")
		stroke.Color = accentDark
		stroke.Thickness = 2
		stroke.Parent = brand
		guiText(bg, if premium then "EDICIÓN ORO · BEBIDAS FRÍAS" else "BEBIDAS FRÍAS · 24 H", {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(0.5, 0.95),
			Size = UDim2.fromScale(0.85, 0.035),
			Font = Enum.Font.GothamBold,
			TextColor3 = Color3.fromRGB(255, 255, 255),
			TextTransparency = 0.15,
			ZIndex = 3,
		})
	end

	-- Puerta: placa algo mas oscura con un filo metalico alrededor
	deco("VendingDoor", Vector3.new(W - 0.34, H - 0.8, 0.06), cf * CFrame.new(0, -0.12, -1.23), M.SmoothPlastic, accent:Lerp(Color3.new(0, 0, 0), 0.15), glossy)
	trimFrame(cf, "VendingDoorTrim", 0, -0.12, W - 0.34, H - 0.8, -1.25, 0.04, 0.05, trim, M.Metal)

	-- Marquesina luminosa arriba (degradado, marca y subtitulo; se ve a oscuras)
	local logo = deco("VendingLogo", Vector3.new(W - 0.5, 0.8, 0.1), cf * CFrame.new(0, 3.0, -1.3), M.SmoothPlastic, accent, { Variant = false })
	do
		local gui = surface(logo, Enum.NormalId.Front, 60, 0, 1.6)
		local bg = guiFrame(gui, { BackgroundColor3 = Color3.new(1, 1, 1) })
		gradient(bg, accentLight, accentDark, 90)
		guiFrame(bg, { Size = UDim2.fromScale(1, 0.42), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.82 }) -- brillo
		local titleLabel = guiText(bg, title, {
			Position = UDim2.fromScale(0.05, 0.08),
			Size = UDim2.fromScale(0.9, 0.62),
			ZIndex = 2,
		})
		local stroke = Instance.new("UIStroke")
		stroke.Color = accentDark:Lerp(Color3.new(0, 0, 0), 0.4)
		stroke.Thickness = 3
		stroke.Parent = titleLabel
		guiText(bg, if premium then "★  SELECCIÓN DE LA CASA  ★" else "SIEMPRE FRÍAS", {
			Position = UDim2.fromScale(0.1, 0.7),
			Size = UDim2.fromScale(0.8, 0.22),
			Font = Enum.Font.GothamBold,
			TextColor3 = if premium then trim else Color3.fromRGB(255, 235, 235),
			ZIndex = 2,
		})
	end
	trimFrame(cf, "VendingLogoTrim", 0, 3.0, W - 0.5, 0.8, -1.32, 0.05, 0.08, trim, M.Metal)
	neonStrip(Vector3.new(W - 0.5, 0.05, 0.05), cf * CFrame.new(0, 2.555, -1.33), Color3.fromRGB(255, 255, 255), "Mall")

	-- Vitrina (vista de frente: vitrina a la izquierda, panel a la derecha = -X local).
	-- Mimic.luau usa estas medidas (WIN_X, WIN_W, WIN_H y el vidrio en z = -1.5).
	local winX, winY, winW, winH = 0.75, 0.05, 2.6, 4.7
	-- Fondo iluminado (degradado frio, brilla solo)
	-- (delante de la placa de la puerta, que acaba en z = -1.26)
	local back = deco("VendingBack", Vector3.new(winW - 0.1, winH - 0.1, 0.05), cf * CFrame.new(winX, winY, -1.29), M.SmoothPlastic, Color3.fromRGB(20, 20, 26), { Variant = false })
	do
		local gui = surface(back, Enum.NormalId.Front, 20, 0, 1)
		local bg = guiFrame(gui, { BackgroundColor3 = Color3.new(1, 1, 1) })
		gradient(bg, Color3.fromRGB(205, 225, 245), Color3.fromRGB(70, 85, 110), 90)
		-- Ilumina los productos desde el fondo (cerca del centro: el Mimico la hace parpadear)
		local backLight = Instance.new("SurfaceLight")
		backLight.Face = Enum.NormalId.Front
		backLight.Range = 3
		backLight.Brightness = 1.4
		backLight.Angle = 120
		backLight.Color = Color3.fromRGB(225, 238, 255)
		backLight.Parent = back
	end
	-- Tiras LED a los lados, por dentro del vidrio
	for _, sx in { -1, 1 } do
		deco("VendingLED", Vector3.new(0.05, winH - 0.25, 0.05), cf * CFrame.new(winX + sx * (winW / 2 - 0.08), winY, -1.42), M.Neon, Color3.fromRGB(225, 240, 255), { CastShadow = false })
	end
	local flavors = if premium then BOTTLE_FLAVORS else CAN_FLAVORS
	local rowLetters = { "E", "D", "C", "B", "A" }
	for row = 0, 4 do
		local y = -1.95 + row * 0.9
		deco("VendingShelf", Vector3.new(winW - 0.1, 0.05, 0.26), cf * CFrame.new(winX, y - 0.025, -1.33), M.Metal, STEEL, { CastShadow = false })
		-- Etiquetas del borde de la balda: codigo de cada hueco
		local strip = deco("VendingShelfLabel", Vector3.new(winW - 0.1, 0.12, 0.02), cf * CFrame.new(winX, y - 0.1, -1.465), M.SmoothPlastic, black, { CastShadow = false, Variant = false })
		do
			local gui = surface(strip, Enum.NormalId.Front, 80, 0.4, 1.2)
			local holder = guiFrame(gui, { BackgroundTransparency = 1 })
			local layout = Instance.new("UIListLayout")
			layout.FillDirection = Enum.FillDirection.Horizontal
			layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
			layout.Padding = UDim.new(0.02, 0)
			layout.Parent = holder
			for k = 1, 6 do
				local tagFrame = guiFrame(holder, {
					Size = UDim2.fromScale(0.14, 0.8),
					BackgroundColor3 = Color3.fromRGB(245, 245, 240),
					LayoutOrder = k,
				})
				guiText(tagFrame, rowLetters[row + 1] .. k, {
					Size = UDim2.fromScale(1, 1),
					Font = Enum.Font.GothamBold,
					TextColor3 = Color3.fromRGB(20, 20, 25),
				})
			end
		end
		for k = 0, 5 do
			-- Cada par de huecos lleva un producto distinto
			local flavor = flavors[(row * 3 + k // 2) % #flavors + 1]
			local x = winX - 1.1 + k * 0.44
			local upright = CFrame.Angles(0, 0, math.rad(90))
			if premium then
				-- Botella: cuerpo de vidrio de color, etiqueta y tapon dorado
				deco("Bottle", Vector3.new(0.5, 0.26, 0.26), cf * CFrame.new(x, y + 0.25, -1.32) * upright, M.SmoothPlastic, flavor[1], {
					Shape = Enum.PartType.Cylinder,
					Transparency = 0.12,
					Reflectance = 0.3,
					CastShadow = false,
					Variant = false,
				})
				deco("BottleLabel", Vector3.new(0.2, 0.27, 0.27), cf * CFrame.new(x, y + 0.22, -1.32) * upright, M.SmoothPlastic, flavor[2], {
					Shape = Enum.PartType.Cylinder,
					CastShadow = false,
					Variant = false,
				})
				deco("BottleCap", Vector3.new(0.16, 0.12, 0.12), cf * CFrame.new(x, y + 0.56, -1.32) * upright, M.Metal, trim, {
					Shape = Enum.PartType.Cylinder,
					Reflectance = 0.3,
					CastShadow = false,
				})
			else
				-- Lata: cuerpo brillante, franja de la etiqueta y tapa de aluminio
				deco("Can", Vector3.new(0.5, 0.3, 0.3), cf * CFrame.new(x, y + 0.25, -1.32) * upright, M.SmoothPlastic, flavor[1], {
					Shape = Enum.PartType.Cylinder,
					Reflectance = 0.22,
					CastShadow = false,
					Variant = false,
				})
				deco("CanBand", Vector3.new(0.14, 0.31, 0.31), cf * CFrame.new(x, y + 0.27, -1.32) * upright, M.SmoothPlastic, flavor[2], {
					Shape = Enum.PartType.Cylinder,
					Reflectance = 0.1,
					CastShadow = false,
					Variant = false,
				})
				deco("CanLid", Vector3.new(0.04, 0.27, 0.27), cf * CFrame.new(x, y + 0.51, -1.32) * upright, M.Metal, Color3.fromRGB(200, 204, 210), {
					Shape = Enum.PartType.Cylinder,
					Reflectance = 0.35,
					CastShadow = false,
				})
			end
		end
	end
	local innerLight = deco("VendingInnerLight", Vector3.new(winW - 0.2, 0.06, 0.08), cf * CFrame.new(winX, winY + winH / 2 - 0.12, -1.3), M.Neon, Color3.fromRGB(235, 245, 255))
	local inner = Instance.new("PointLight")
	inner.Range = 7
	inner.Brightness = 2.2
	inner.Color = Color3.fromRGB(235, 245, 255)
	inner.Parent = innerLight
	local glow = Instance.new("PointLight")
	glow.Range = 10
	glow.Brightness = 0.6
	glow.Color = accent:Lerp(Color3.new(1, 1, 1), 0.3)
	glow.Parent = shell
	-- Marco de la vitrina: perfil oscuro con un filo metalico por dentro
	trimFrame(cf, "VendingFrame", winX, winY, winW, winH, -1.36, 0.15, 0.32, dark, M.Metal)
	trimFrame(cf, "VendingFrameLip", winX, winY, winW - 0.02, winH - 0.02, -1.53, 0.035, 0.03, trim, M.Metal)
	-- (SmoothPlastic y no Glass: el material Glass no deja ver las SurfaceGui ni las
	-- piezas transparentes que tiene detras: el fondo iluminado, etiquetas y botellas)
	local glass = deco("VendingGlass", Vector3.new(winW, winH, 0.05), cf * CFrame.new(winX, winY, -1.5), M.SmoothPlastic, Color3.fromRGB(200, 220, 230), {
		Transparency = 0.88,
		Reflectance = 0.25,
		CastShadow = false,
		Variant = false,
	})
	-- Reflejos en diagonal sobre el vidrio
	do
		local gui = surface(glass, Enum.NormalId.Front, 20, 0.5, 1)
		local holder = guiFrame(gui, { BackgroundTransparency = 1, ClipsDescendants = true })
		for _, spec in { { 0.3, 0.16, 0.86 }, { 0.48, 0.05, 0.84 }, { 0.82, 0.08, 0.9 } } do
			guiFrame(holder, {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(spec[1], 0.45),
				Size = UDim2.fromScale(spec[2], 1.6),
				Rotation = 24,
				BackgroundColor3 = Color3.new(1, 1, 1),
				BackgroundTransparency = spec[3],
			})
		end
	end

	-- Panel derecho: pantalla (probabilidades), teclado, monedero, tarjeta y billetero
	local panelX = -1.45
	deco("VendingPanel", Vector3.new(1.3, 5.3, 0.08), cf * CFrame.new(panelX, -0.15, -1.27), M.SmoothPlastic, dark, { Reflectance = 0.08, Variant = false })
	deco("VendingScreenBezel", Vector3.new(1.42, 3.02, 0.04), cf * CFrame.new(panelX, 1, -1.3), M.Metal, trim, { Reflectance = 0.3, CastShadow = false })
	local screen = box("OddsScreen", Vector3.new(1.3, 2.9, 0.05), cf * CFrame.new(panelX, 1, -1.32), M.SmoothPlastic, Color3.fromRGB(8, 10, 14), {
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Variant = false,
	})
	screen.Parent = body
	-- Teclado: una placa con las teclas dibujadas (1-9, *, 0, #)
	local keypad = deco("VendingKeypad", Vector3.new(0.9, 0.95, 0.05), cf * CFrame.new(panelX, -0.95, -1.33), M.SmoothPlastic, Color3.fromRGB(40, 40, 46), { Variant = false })
	do
		local gui = surface(keypad, Enum.NormalId.Front, 100, 0.6, 1.3)
		local holder = guiFrame(gui, { BackgroundTransparency = 1 })
		local grid = Instance.new("UIGridLayout")
		grid.CellSize = UDim2.fromScale(0.28, 0.2)
		grid.CellPadding = UDim2.fromScale(0.05, 0.045)
		grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
		grid.VerticalAlignment = Enum.VerticalAlignment.Center
		grid.Parent = holder
		for i, key in { "1", "2", "3", "4", "5", "6", "7", "8", "9", "*", "0", "#" } do
			local k = guiFrame(holder, { BackgroundColor3 = Color3.fromRGB(215, 218, 224), LayoutOrder = i })
			local c = Instance.new("UICorner")
			c.CornerRadius = UDim.new(0.25, 0)
			c.Parent = k
			guiText(k, key, {
				Size = UDim2.fromScale(1, 1),
				Font = Enum.Font.GothamBold,
				TextColor3 = Color3.fromRGB(30, 30, 36),
			})
		end
	end
	-- Monedero (cromo con ranura) y lector de tarjetas (luz verde)
	deco("CoinSlot", Vector3.new(0.45, 0.55, 0.08), cf * CFrame.new(panelX + 0.3, -1.85, -1.33), M.Metal, trim, { Reflectance = 0.3 })
	deco("CoinSlotHole", Vector3.new(0.05, 0.3, 0.02), cf * CFrame.new(panelX + 0.3, -1.85, -1.375), M.SmoothPlastic, black)
	deco("CardReader", Vector3.new(0.45, 0.55, 0.12), cf * CFrame.new(panelX - 0.3, -1.85, -1.35), M.SmoothPlastic, black, { Reflectance = 0.1, Variant = false })
	neonStrip(Vector3.new(0.3, 0.035, 0.03), cf * CFrame.new(panelX - 0.3, -1.68, -1.415), Color3.fromRGB(80, 255, 120), "Mall")
	deco("BillSlot", Vector3.new(0.8, 0.2, 0.08), cf * CFrame.new(panelX, -2.35, -1.33), M.SmoothPlastic, black)
	neonStrip(Vector3.new(0.55, 0.04, 0.04), cf * CFrame.new(panelX, -2.35, -1.38), Color3.fromRGB(80, 255, 120), "Mall")
	-- Cajetin del cambio
	trimFrame(cf, "ChangeCupTrim", panelX, -2.62, 0.45, 0.25, -1.31, 0.04, 0.05, trim, M.Metal)
	deco("ChangeCup", Vector3.new(0.45, 0.25, 0.06), cf * CFrame.new(panelX, -2.62, -1.29), M.SmoothPlastic, black)

	-- Bandeja de salida: hueco oscuro con marco metalico y tapa ahumada "EMPUJAR"
	deco("VendingTray", Vector3.new(winW, 0.7, 0.1), cf * CFrame.new(winX, -2.95, -1.28), M.SmoothPlastic, black)
	trimFrame(cf, "VendingTrayTrim", winX, -2.95, winW, 0.7, -1.3, 0.05, 0.08, trim, M.Metal)
	local flap = deco("VendingFlap", Vector3.new(winW - 0.2, 0.5, 0.04), cf * CFrame.new(winX, -2.95, -1.34), M.SmoothPlastic, Color3.fromRGB(45, 45, 52), {
		Transparency = 0.15,
		Reflectance = 0.15,
		Variant = false,
	})
	do
		local gui = surface(flap, Enum.NormalId.Front, 60, 0.7, 1)
		guiText(gui, "EMPUJAR", {
			Position = UDim2.fromScale(0.3, 0.3),
			Size = UDim2.fromScale(0.4, 0.4),
			Font = Enum.Font.GothamBold,
			TextColor3 = Color3.fromRGB(200, 200, 210),
			TextTransparency = 0.3,
		})
	end

	tag(body, Tags.VendingMachine)

	-- Punto delante de la maquina (mision Rellenar maquina: alli se entrega la caja)
	local front = (cf * CFrame.new(0, -H / 2 + 0.1, -(D / 2 + 2.2))).Position
	local refill = box("Spot_RefillVending", Vector3.new(1, 0.2, 1), CFrame.new(front), M.SmoothPlastic, Color3.new(1, 1, 1), {
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Variant = false,
	})
	tag(refill, Tags.MissionSpot, { MissionType = "RefillVending" })
	return body
end

----------------------------------------------------------------------
-- Productos y muebles de tienda
----------------------------------------------------------------------

-- Variacion suave de un color (para que los productos no sean todos identicos).
local rng = Random.new(1234)
local function vary(color: Color3, amount: number?): Color3
	local h, s, v = color:ToHSV()
	local a = amount or 0.08
	return Color3.fromHSV(h, math.clamp(s + rng:NextNumber(-a, a), 0, 1), math.clamp(v + rng:NextNumber(-a, a), 0, 1))
end

-- Fila de productos sueltos (cajas de distintos tamaños) sobre una balda.
local function productRow(cf: CFrame, length: number, depth: number, color: Color3)
	local cursor = -length / 2 + 0.2
	while cursor < length / 2 - 0.6 do
		local w = rng:NextNumber(0.6, 1.3)
		local h = rng:NextNumber(0.5, 1)
		if cursor + w > length / 2 - 0.2 then
			break
		end
		deco("Product", Vector3.new(w - 0.08, h, depth), cf * CFrame.new(cursor + w / 2, h / 2, 0), M.SmoothPlastic, vary(color), { CastShadow = false })
		cursor += w
	end
end

-- En el marco de la tienda: x lateral, y altura sobre el suelo, d profundidad (0 = fachada).
local function L(base: CFrame, x: number, y: number, d: number): CFrame
	return base * CFrame.new(x, y, -d)
end

local OUT = CFrame.Angles(0, math.pi, 0) -- mirando hacia la galeria
local FACE_NEG_X = CFrame.Angles(0, math.rad(90), 0) -- mirando hacia -x local
local FACE_POS_X = CFrame.Angles(0, math.rad(-90), 0) -- mirando hacia +x local

-- Repite un modelo a lo largo de `length` (eje X de cf), segun el ancho real del modelo
-- (o `unit` si no se puede medir). Devuelve false si no existe.
local function propRow(name: string, cf: CFrame, length: number, unit: number, collide: boolean?): boolean
	local template = propFolder and propFolder:FindFirstChild(name)
	if not template or not template:IsA("Model") then
		return false
	end
	local width = template:GetExtentsSize().X
	if width > 0.5 then
		unit = width
	end
	local count = math.max(1, math.floor(length / unit + 0.5))
	local seg = length / count
	for k = 1, count do
		prop(name, cf * CFrame.new(-length / 2 + seg * (k - 0.5), 0, 0), collide)
	end
	return true
end

local function gondola(base: CFrame, x: number, d: number, length: number, colors: { Color3 }, alongDepth: boolean?, propName: string?)
	local rot = if alongDepth then CFrame.Angles(0, math.rad(90), 0) else CFrame.new()
	local cf = L(base, x, 0, d) * rot
	-- Colisionador invisible del tamaño de la gondola llena (bloquea el paso y la vision)
	box("GondolaCollider", Vector3.new(length, 5, 2.4), cf * CFrame.new(0, 2.5, 0), M.SmoothPlastic, Color3.new(1, 1, 1), {
		Transparency = 1,
		Variant = false,
	})
	-- Modelo 3D de estanteria llena de productos (si existe): los modelos solo tienen
	-- estantes por delante, asi que van dos espalda con espalda (gondola de doble cara)
	local name = propName or "GroceryShelf"
	if propFolder and propFolder:FindFirstChild(name) then
		propRow(name, cf * CFrame.new(0, 0, -0.6), length, 7.5, false)
		propRow(name, cf * CFrame.new(0, 0, 0.6) * CFrame.Angles(0, math.pi, 0), length, 7.5, false)
		return
	end
	box("Gondola", Vector3.new(length, 5, 0.5), cf * CFrame.new(0, 2.5, 0), M.Metal, Color3.fromRGB(215, 215, 218))
	deco("GondolaBase", Vector3.new(length, 0.6, 2.4), cf * CFrame.new(0, 0.3, 0), M.Metal, Color3.fromRGB(60, 60, 64))
	deco("GondolaTopper", Vector3.new(length, 0.8, 0.2), cf * CFrame.new(0, 5.4, 0), M.SmoothPlastic, colors[1]:Lerp(Color3.new(1, 1, 1), 0.3))
	for i, color in colors do
		local y = 0.6 + (i - 1) * 1.4
		for _, side in { -1, 1 } do
			deco("Shelf", Vector3.new(length, 0.1, 1), cf * CFrame.new(0, y, side * 0.7), M.Metal, Color3.fromRGB(215, 215, 218))
			deco("PriceStrip", Vector3.new(length, 0.18, 0.04), cf * CFrame.new(0, y - 0.05, side * 1.21), M.SmoothPlastic, Color3.fromRGB(245, 245, 240))
			productRow(cf * CFrame.new(0, y + 0.05, side * 0.75), length, 0.8, color)
		end
	end
end

-- Perchero con prendas colgadas (perchas, largos y tonos distintos).
local function clothesRack(base: CFrame, x: number, d: number, colors: { Color3 })
	local cf = L(base, x, 0, d)
	if prop("ClothingRack", cf) then
		return
	end
	box("RackRail", Vector3.new(8, 0.2, 0.2), cf * CFrame.new(0, 5, 0), M.Metal, STEEL)
	box("RackPost", Vector3.new(0.25, 5, 0.25), cf * CFrame.new(-3.8, 2.5, 0), M.Metal, STEEL)
	box("RackPost", Vector3.new(0.25, 5, 0.25), cf * CFrame.new(3.8, 2.5, 0), M.Metal, STEEL)
	for _, px in { -3.8, 3.8 } do
		deco("RackFoot", Vector3.new(0.25, 0.15, 2), cf * CFrame.new(px, 0.08, 0), M.Metal, STEEL)
	end
	local n = 12
	for i = 1, n do
		local color = vary(colors[(i - 1) % #colors + 1], 0.06)
		local px = -3.3 + (i - 1) * (6.6 / (n - 1))
		local len = rng:NextNumber(2.4, 3.4)
		local g = cf * CFrame.new(px, 0, 0) * CFrame.Angles(0, math.rad(90 + rng:NextNumber(-6, 6)), 0)
		deco("Hanger", Vector3.new(0.05, 0.4, 0.05), g * CFrame.new(0, 4.75, 0), M.Metal, STEEL)
		deco("Garment", Vector3.new(1.5, len, 0.22), g * CFrame.new(0, 4.55 - len / 2, 0), M.Fabric, color)
		deco("Shoulders", Vector3.new(1.6, 0.25, 0.3), g * CFrame.new(0, 4.5, 0), M.Fabric, color)
	end
end

-- Mesa con pilas de ropa doblada.
local function foldedTable(base: CFrame, x: number, d: number, colors: { Color3 })
	local cf = L(base, x, 0, d)
	if prop("FoldedClothesTable", cf * OUT) then
		return
	end
	box("DisplayTable", Vector3.new(6, 2.8, 3), cf * CFrame.new(0, 1.4, 0), M.Wood, Color3.fromRGB(225, 212, 195))
	for i = 0, 5 do
		local col = i % 3
		local row = math.floor(i / 3)
		local h = rng:NextNumber(0.5, 1.1)
		deco("FoldedStack", Vector3.new(1.5, h, 1.1), cf * CFrame.new(-1.9 + col * 1.9, 2.8 + h / 2, -0.65 + row * 1.3), M.Fabric, vary(colors[i % #colors + 1], 0.05))
	end
end

-- Maniqui de escaparate: EL MISMO modelo que el enemigo (EntityModels.mannequin). Uno de
-- ellos cobra vida cuando sale el Maniqui y vuelve a su peana al terminar la noche.
local function displayMannequin(cframe: CFrame)
	local model = EntityModels.mannequin()
	model.Name = "DisplayMannequin"
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanTouch = false
			d.CanCollide = d ~= model.PrimaryPart
		end
	end
	EntityModels.placeAt(model, cframe * CFrame.new(0, 0.2, 0), currentParent)
	tag(model, Tags.DisplayMannequin)
	deco("Stand", Vector3.new(2, 0.2, 2), cframe * CFrame.new(0, 0.1, 0), M.Metal, DARK)
end

local function glassCase(base: CFrame, x: number, d: number, colors: { Color3 })
	local cf = L(base, x, 0, d)
	box("CaseBase", Vector3.new(6, 2.6, 2.6), cf * CFrame.new(0, 1.3, 0), M.Wood, Color3.fromRGB(235, 230, 222))
	box("CaseGlass", Vector3.new(6, 1.6, 2.6), cf * CFrame.new(0, 3.4, 0), M.Glass, Color3.fromRGB(200, 225, 235), {
		Transparency = 0.6,
		Reflectance = 0.15,
		Variant = false,
	})
	deco("CaseVelvet", Vector3.new(5.6, 0.1, 2.2), cf * CFrame.new(0, 2.66, 0), M.Fabric, Color3.fromRGB(30, 30, 40))
	for i, color in colors do
		deco("Item", Vector3.new(0.5, 0.9, 0.5), cf * CFrame.new(-2 + (i - 1) * 2, 3.15, 0), M.Glass, color)
	end
	local glow = deco("CaseLight", Vector3.new(5.6, 0.08, 0.2), cf * CFrame.new(0, 4.15, 0), M.Neon, Color3.fromRGB(255, 245, 225))
	local light = Instance.new("PointLight")
	light.Range = 5
	light.Brightness = 0.5
	light.Color = Color3.fromRGB(255, 240, 220)
	light.Parent = glow
end

local function wallShelf(base: CFrame, side: number, d: number, length: number, colors: { Color3 }, propName: string?)
	-- side = -1 pared izquierda, 1 pared derecha
	local cf = L(base, side * 22.4, 0, d) * (if side > 0 then FACE_NEG_X else FACE_POS_X)
	box("ShelfCollider", Vector3.new(length, 8, 1.4), cf * CFrame.new(0, 4, -0.1), M.SmoothPlastic, Color3.new(1, 1, 1), {
		Transparency = 1,
		Variant = false,
	})
	-- Modelo 3D de estanteria con productos (si existe)
	if propRow(propName or "WallShelf", cf * CFrame.new(0, 0, 0.1), length, 7.5, false) then
		return
	end
	box("WallShelf", Vector3.new(length, 8, 0.4), cf * CFrame.new(0, 4, 0.4), M.Wood, Color3.fromRGB(150, 110, 75))
	for _, sx in { -length / 2, length / 2 } do
		deco("ShelfSide", Vector3.new(0.2, 8, 1.4), cf * CFrame.new(sx, 4, -0.1), M.Wood, Color3.fromRGB(130, 95, 65))
	end
	for i, color in colors do
		local y = 0.9 + (i - 1) * 1.8
		deco("Shelf", Vector3.new(length, 0.12, 1.3), cf * CFrame.new(0, y, -0.15), M.Wood, Color3.fromRGB(165, 125, 88))
		productRow(cf * CFrame.new(0, y + 0.06, -0.2), length - 0.4, 1, color)
	end
end

-- Espejo de pared (frente = -Z de `cf`).
local function mirror(cf: CFrame, width: number, height: number)
	deco("MirrorFrame", Vector3.new(width + 0.3, height + 0.3, 0.15), cf * CFrame.new(0, 0, 0.05), M.Metal, DARK)
	-- (Roblox solo refleja el cielo: de noche un espejo muy reflectante se ve negro)
	deco("Mirror", Vector3.new(width, height, 0.08), cf * CFrame.new(0, 0, -0.05), M.SmoothPlastic, Color3.fromRGB(170, 182, 190), {
		Reflectance = 0.3,
		Variant = false,
	})
end

-- Mesa redonda con sillas alrededor (cafeteria, patio de comidas).
local function roundTable(cf: CFrame, chairs: number, chairColor: Color3, radius: number?)
	box("TableTop", Vector3.new(0.25, 4, 4), cf * CFrame.new(0, 3, 0) * CFrame.Angles(0, 0, math.rad(90)), M.Wood, Color3.fromRGB(205, 175, 135), {
		Shape = Enum.PartType.Cylinder,
	})
	box("TableLeg", Vector3.new(0.45, 2.9, 0.45), cf * CFrame.new(0, 1.45, 0), M.Metal, STEEL)
	deco("TableFoot", Vector3.new(0.12, 2, 2), cf * CFrame.new(0, 0.06, 0) * CFrame.Angles(0, 0, math.rad(90)), M.Metal, STEEL, {
		Shape = Enum.PartType.Cylinder,
	})
	local r = radius or 2.9
	for k = 0, chairs - 1 do
		local a = math.rad(k * 360 / chairs + 45)
		local ccf = cf * CFrame.new(math.cos(a) * r, 0, math.sin(a) * r) * CFrame.Angles(0, -a + math.rad(90), 0)
		box("Seat", Vector3.new(1.7, 0.25, 1.7), ccf * CFrame.new(0, 1.8, 0), M.Plastic, chairColor)
		deco("SeatBack", Vector3.new(1.7, 1.6, 0.2), ccf * CFrame.new(0, 2.7, 0.8), M.Plastic, chairColor)
		deco("SeatPost", Vector3.new(0.25, 1.7, 0.25), ccf * CFrame.new(0, 0.85, 0), M.Metal, STEEL)
	end
end

-- Escritorio de oficina con monitor (version de piezas del modelo OfficeDesk).
local function deskFallback(cf: CFrame)
	box("Desk", Vector3.new(6, 0.25, 3), cf * CFrame.new(0, 2.9, 0), M.Wood, Color3.fromRGB(150, 120, 90))
	for _, x in { -2.8, 2.8 } do
		box("DeskSide", Vector3.new(0.25, 2.8, 2.8), cf * CFrame.new(x, 1.4, 0), M.Wood, Color3.fromRGB(150, 120, 90))
	end
	local monitor = deco("Monitor", Vector3.new(2.2, 1.4, 0.15), cf * CFrame.new(0, 4, 0.6), M.SmoothPlastic, DARK)
	glowScreen(monitor, Enum.NormalId.Front, Color3.fromRGB(20, 40, 70), Color3.fromRGB(10, 15, 25), nil)
	deco("Keyboard", Vector3.new(1.8, 0.1, 0.6), cf * CFrame.new(0, 3.08, -0.4), M.SmoothPlastic, DARK)
	box("ChairSeat", Vector3.new(2, 0.4, 2), cf * CFrame.new(0, 1.9, -2.6), M.Fabric, DARK)
	deco("ChairBack", Vector3.new(2, 2.4, 0.3), cf * CFrame.new(0, 3.2, -3.5), M.Fabric, DARK)
	deco("ChairPost", Vector3.new(0.3, 1.7, 0.3), cf * CFrame.new(0, 0.85, -2.6), M.Metal, METAL)
end

-- Estanteria metalica de almacen con cajas.
local function storageRack(cf: CFrame, length: number)
	box("Rack", Vector3.new(length, 9, 3), cf * CFrame.new(0, 4.5, 0), M.Metal, Color3.fromRGB(70, 90, 140), { Transparency = 0.999, Variant = false })
	for _, x in { -length / 2 + 0.2, length / 2 - 0.2 } do
		for _, z in { -1.3, 1.3 } do
			deco("RackUpright", Vector3.new(0.25, 9, 0.25), cf * CFrame.new(x, 4.5, z), M.Metal, Color3.fromRGB(40, 70, 150))
		end
	end
	for level = 0, 2 do
		deco("RackBeam", Vector3.new(length, 0.25, 3), cf * CFrame.new(0, 0.4 + level * 3, 0), M.Metal, Color3.fromRGB(230, 120, 30))
		local cursor = -length / 2 + 0.6
		while cursor < length / 2 - 2 do
			local w = rng:NextNumber(1.6, 2.6)
			local h = rng:NextNumber(1.2, 2.2)
			deco("Boxes", Vector3.new(w - 0.1, h, 2.4), cf * CFrame.new(cursor + w / 2, 0.55 + level * 3 + h / 2, 0), M.Cardboard, vary(Color3.fromRGB(175, 135, 90), 0.06))
			cursor += w
		end
	end
end

-- Tonos apagados de producto real (no colores primarios de juguete)
local PALETTE = {
	Color3.fromRGB(150, 52, 52), -- burdeos
	Color3.fromRGB(48, 66, 102), -- azul marino
	Color3.fromRGB(205, 180, 130), -- beige
	Color3.fromRGB(88, 104, 70), -- verde oliva
	Color3.fromRGB(225, 222, 214), -- crudo
	Color3.fromRGB(62, 62, 66), -- grafito
}
local function pick(n: number, offset: number): { Color3 }
	local list = {}
	for i = 1, n do
		table.insert(list, PALETTE[(i + offset - 1) % #PALETTE + 1])
	end
	return list
end

-- Tiendas: interiores, acabado comun y mobiliario extra. Van dentro de un bloque do (el
-- modulo no puede tener mas de 200 variables locales); fuera solo se ven estas:
local INTERIORS, FITOUT, storeCommon
local Kit = {} -- piezas reutilizadas fuera de las tiendas
do

----------------------------------------------------------------------
-- Acabado realista de las tiendas: piezas comunes
----------------------------------------------------------------------
-- Marco de la tienda: L(base, x, y, d). La cara interior de las paredes laterales esta en
-- x = ±23 y la del fondo en d = 49: lo que se cuelgue mas adentro queda tapado por el muro.

local SIDE_FACE = 23
local BACK_FACE = 49
local WHITE_WALL = Color3.fromRGB(236, 233, 226)
local LAMINATE = Color3.fromRGB(242, 240, 236)
local BLACK = Color3.fromRGB(22, 22, 25)
local CHROME_LIGHT = Color3.fromRGB(200, 202, 206)
local CYL = Enum.PartType.Cylinder
local BALL = Enum.PartType.Ball
local UPRIGHT = CFrame.Angles(0, 0, math.rad(90)) -- cilindro de pie (su eje X pasa a ser Y)

-- Colores vivos de producto (jugueteria, golosinas, packaging)
local BRIGHT = {
	Color3.fromRGB(220, 50, 50),
	Color3.fromRGB(40, 110, 215),
	Color3.fromRGB(250, 200, 40),
	Color3.fromRGB(60, 170, 80),
	Color3.fromRGB(240, 120, 30),
	Color3.fromRGB(150, 70, 190),
	Color3.fromRGB(30, 180, 190),
	Color3.fromRGB(235, 90, 150),
}

-- Punto de una pared lateral (side -1 izquierda / 1 derecha), frente (-Z) hacia la sala y
-- X a lo largo de la pared. inset = separacion de la pared.
local function sideWallCF(base: CFrame, side: number, d: number, y: number, inset: number?): CFrame
	return L(base, side * (SIDE_FACE - (inset or 0)), y, d) * (if side > 0 then FACE_NEG_X else FACE_POS_X)
end

-- Punto de la pared del fondo, mirando hacia la entrada.
local function backWallCF(base: CFrame, x: number, y: number, inset: number?): CFrame
	return L(base, x, y, BACK_FACE - (inset or 0)) * OUT
end

-- Texto impreso (le afecta la luz de la escena: no brilla).
local function printed(part: BasePart, text: string, color: Color3, font: Enum.Font, face: Enum.NormalId?): SurfaceGui
	local gui = sign(part, text, color, font, face)
	gui.LightInfluence = 1
	gui.Brightness = 1
	return gui
end

-- Panel ranurado de pared (slatwall): tablero con ranuras horizontales cada 0.5.
local function slatwall(cf: CFrame, w: number, h: number, color: Color3): Part
	local p = deco("Slatwall", Vector3.new(w, h, 0.12), cf, M.SmoothPlastic, color, { Variant = false, CastShadow = false })
	local gui = surface(p, Enum.NormalId.Front, 16, 1, 1)
	local holder = guiFrame(gui, { BackgroundTransparency = 1 })
	local groove = color:Lerp(Color3.new(0, 0, 0), 0.45)
	local n = math.max(2, math.floor(h / 0.5))
	for i = 1, n - 1 do
		guiFrame(holder, {
			Position = UDim2.fromScale(0, i / n),
			Size = UDim2.new(1, 0, 0, 2),
			BackgroundColor3 = groove,
			BackgroundTransparency = 0.3,
		})
	end
	return p
end

-- Fila de pilas de ropa doblada (o de toallas, platos...) sobre una balda.
local function stackRow(cf: CFrame, length: number, depth: number, colors: { Color3 }, maxH: number, unit: number?)
	local n = math.max(1, math.floor(length / (unit or 1.4)))
	local seg = length / n
	for k = 0, n - 1 do
		local h = rng:NextNumber(maxH * 0.45, maxH)
		deco("Stack", Vector3.new(seg - 0.22, h, depth), cf * CFrame.new(-length / 2 + seg * (k + 0.5), h / 2, 0), M.Fabric, vary(colors[k % #colors + 1], 0.05), {
			CastShadow = false,
		})
	end
end

-- Hilera de lomos de libros (una pieza con los lomos dibujados: muchos libros, pocas piezas).
local function bookRow(cf: CFrame, length: number, height: number)
	local row = deco("BookRow", Vector3.new(length, height, 0.9), cf * CFrame.new(0, height / 2, 0), M.SmoothPlastic, Color3.fromRGB(35, 30, 28), {
		Variant = false,
		CastShadow = false,
	})
	local gui = surface(row, Enum.NormalId.Front, 20, 1, 1)
	local holder = guiFrame(gui, { BackgroundTransparency = 1 })
	local x = 0
	while x < 0.97 do
		local w = rng:NextNumber(0.018, 0.034) * (10 / length)
		local hh = rng:NextNumber(0.72, 0.98)
		local spine = guiFrame(holder, {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(x, 1),
			Size = UDim2.fromScale(math.min(w, 1 - x) - 0.002, hh),
			BackgroundColor3 = vary(PALETTE[rng:NextInteger(1, #PALETTE)], 0.14),
		})
		-- Banda del titulo en algunos lomos
		if rng:NextNumber() < 0.6 then
			guiFrame(spine, {
				Position = UDim2.fromScale(0.15, rng:NextNumber(0.12, 0.3)),
				Size = UDim2.fromScale(0.7, 0.08),
				BackgroundColor3 = Color3.fromRGB(230, 215, 170),
				BackgroundTransparency = 0.2,
			})
		end
		x += w
	end
end

-- Mueble de pared sobre panel ranurado: montantes, colision, cartel de seccion y producto.
-- side -1/1, d = centro a lo largo de la pared. kind:
--   Hang (barras con prendas) · Shelves (baldas con pilas) · Cubby (casilleros) · Shoes
--   (baldas inclinadas con pares) · Peg (ganchos con blisters) · Bottles (vidrio iluminado con
--   frascos) · Frames (monturas de gafas) · Books (lomos) · Boxes (cajas) · Cases (vitrinas)
local function wallBay(base: CFrame, side: number, d: number, length: number, kind: string, colors: { Color3 }, title: string?, zoneName: string?, height: number?)
	local h = height or 8.4
	local cf = sideWallCF(base, side, d, 0)
	local function P(x: number, y: number, z: number): CFrame
		return cf * CFrame.new(x, y, -z) -- z = distancia desde la pared
	end
	local dark = kind == "Bottles" or kind == "Cases" or kind == "Frames"
	slatwall(P(0, 0.6 + h / 2, 0.06), length, h, if dark then Color3.fromRGB(46, 44, 48) else LAMINATE)
	box("BayCollider", Vector3.new(length, h, 1.4), P(0, h / 2, 0.75), M.SmoothPlastic, Color3.new(1, 1, 1), { Transparency = 1, Variant = false })
	for _, sx in { -1, 1 } do
		deco("BayUpright", Vector3.new(0.14, h + 0.6, 1.5), P(sx * (length / 2 + 0.07), (h + 0.6) / 2, 0.75), M.Metal, CHROME_LIGHT)
	end
	if kind ~= "Hang" then
		deco("BayPlinth", Vector3.new(length, 0.6, 1.4), P(0, 0.3, 0.7), M.SmoothPlastic, BLACK, { Variant = false })
	end
	if title then
		local fascia = deco("BayHeader", Vector3.new(length + 0.3, 0.9, 0.25), P(0, h + 1.1, 0.25), M.SmoothPlastic, Color3.fromRGB(30, 30, 34), { Variant = false })
		sign(fascia, title, Color3.fromRGB(245, 245, 240), Enum.Font.GothamBold, Enum.NormalId.Front)
	end
	local function shelf(y: number, depth: number, material, color: Color3, props)
		return deco("BayShelf", Vector3.new(length - 0.1, 0.1, depth), P(0, y, depth / 2 + 0.1), material, color, props)
	end

	if kind == "Hang" then
		-- Doble barra (camisas arriba, pantalones abajo) y balda con pilas encima
		for r, rail in { 3.9, 7.4 } do
			deco("HangRail", Vector3.new(length - 0.3, 0.14, 0.14), P(0, rail, 1.0), M.Metal, STEEL)
			for _, sx in { -1, 1 } do
				deco("RailBracket", Vector3.new(0.1, 0.1, 1.0), P(sx * (length / 2 - 0.4), rail, 0.5), M.Metal, STEEL)
			end
			local n = math.floor((length - 0.8) / 0.42)
			for k = 0, n - 1 do
				local len = if r == 1 then rng:NextNumber(2.4, 2.8) else rng:NextNumber(2.2, 2.7)
				local color = vary(colors[(k // 4 + r) % #colors + 1], 0.05)
				deco("Garment", Vector3.new(0.2, len, 1.45), P(-length / 2 + 0.6 + k * 0.42, rail - 0.2 - len / 2, 1.0), M.Fabric, color, { CastShadow = false })
			end
		end
		shelf(h - 0.2, 1.2, M.Wood, LAMINATE)
		stackRow(P(0, h - 0.15, 0.7), length - 0.4, 1.0, colors, 0.8)
	elseif kind == "Shelves" or kind == "Cubby" or kind == "Boxes" then
		local ys = { 1.5, 3.4, 5.3, 7.2 }
		for i, y in ys do
			shelf(y - 0.05, 1.25, M.Wood, LAMINATE)
			if kind == "Boxes" then
				productRow(P(0, y, 0.75), length - 0.3, 0.9, colors[(i - 1) % #colors + 1])
			else
				stackRow(P(0, y, 0.72), length - 0.3, 1.05, colors, 1.3, if kind == "Cubby" then 1.15 else 1.4)
			end
		end
		if kind == "Cubby" then
			local cols = math.max(2, math.floor(length / 2.4))
			for c = 1, cols - 1 do
				deco("CubbyDivider", Vector3.new(0.1, h - 0.4, 1.25), P(-length / 2 + c * length / cols, 0.6 + (h - 0.4) / 2, 0.72), M.Wood, LAMINATE)
			end
			shelf(h + 0.3, 1.25, M.Wood, LAMINATE)
		end
	elseif kind == "Shoes" then
		for i = 0, 4 do
			local y = 1.5 + i * 1.5
			local s = P(0, y, 0.75) * CFrame.Angles(math.rad(-12), 0, 0)
			deco("ShoeShelf", Vector3.new(length - 0.1, 0.08, 1.3), s, M.SmoothPlastic, Color3.fromRGB(235, 235, 235), { Transparency = 0.3, Variant = false })
			local n = math.floor((length - 0.4) / 1.3)
			for k = 0, n - 1 do
				local color = vary(colors[(k + i) % #colors + 1], 0.08)
				local px = -length / 2 + 0.85 + k * 1.3
				for _, ox in { -0.24, 0.24 } do
					deco("Shoe", Vector3.new(0.4, 0.42, 1.05), s * CFrame.new(px + ox, 0.25, 0), M.Leather, color, { CastShadow = false })
				end
				deco("ShoeSole", Vector3.new(0.92, 0.1, 1.08), s * CFrame.new(px, 0.09, 0), M.Rubber, Color3.fromRGB(240, 240, 236), { CastShadow = false })
			end
		end
	elseif kind == "Peg" then
		for row = 0, 4 do
			local y = 2.2 + row * 1.35
			local n = math.floor((length - 0.4) / 0.95)
			for k = 0, n - 1 do
				local x = -length / 2 + 0.7 + k * 0.95
				local color = vary(colors[(k + row) % #colors + 1], 0.06)
				deco("Blister", Vector3.new(0.72, 1.0, 0.08), P(x, y, 0.55), M.SmoothPlastic, color, { CastShadow = false, Variant = false })
				deco("BlisterBubble", Vector3.new(0.48, 0.55, 0.18), P(x, y - 0.12, 0.66), M.SmoothPlastic, Color3.fromRGB(230, 236, 240), {
					Transparency = 0.35,
					Reflectance = 0.2,
					CastShadow = false,
					Variant = false,
				})
				deco("PegHook", Vector3.new(0.05, 0.05, 0.7), P(x, y + 0.55, 0.4), M.Metal, STEEL, { CastShadow = false })
			end
		end
	elseif kind == "Bottles" then
		-- Fondo retroiluminado, baldas de vidrio con tira LED y frascos
		local back = deco("BayBacklight", Vector3.new(length - 0.2, h - 0.6, 0.05), P(0, 0.9 + (h - 0.6) / 2, 0.16), M.SmoothPlastic, Color3.fromRGB(250, 244, 236), { Variant = false })
		glowScreen(back, Enum.NormalId.Front, Color3.fromRGB(255, 250, 242), Color3.fromRGB(235, 222, 205), nil).Brightness = 0.7
		for i, y in { 2.2, 3.8, 5.4, 7.0 } do
			shelf(y - 0.05, 1.1, M.Glass, Color3.fromRGB(220, 235, 238), { Transparency = 0.5, Reflectance = 0.2, Variant = false })
			local led = deco("ShelfLED", Vector3.new(length - 0.2, 0.04, 0.04), P(0, y + 0.02, 1.18), M.Neon, Color3.fromRGB(255, 244, 225), { CastShadow = false })
			if zoneName then
				tag(led, Tags.Light, { Zone = zoneName })
			end
			local n = math.floor((length - 0.4) / 0.72)
			for k = 0, n - 1 do
				local x = -length / 2 + 0.55 + k * 0.72
				local color = colors[(k + i) % #colors + 1]
				local bh = rng:NextNumber(0.5, 0.85)
				deco("Flacon", Vector3.new(bh, 0.38, 0.38), P(x, y + bh / 2, 0.6) * UPRIGHT, M.SmoothPlastic, color, {
					Shape = CYL,
					Transparency = 0.18,
					Reflectance = 0.35,
					CastShadow = false,
					Variant = false,
				})
				deco("FlaconCap", Vector3.new(0.18, 0.2, 0.2), P(x, y + bh + 0.08, 0.6), M.Metal, Color3.fromRGB(214, 180, 110), { Reflectance = 0.3, CastShadow = false })
			end
		end
	elseif kind == "Frames" then
		for row = 0, 5 do
			local y = 2.3 + row * 1.05
			shelf(y - 0.05, 0.6, M.SmoothPlastic, Color3.fromRGB(230, 236, 240), { Transparency = 0.4, Variant = false })
			local n = math.floor((length - 0.4) / 1.12)
			for k = 0, n - 1 do
				local x = -length / 2 + 0.75 + k * 1.12
				local color = colors[(k + row) % #colors + 1]
				local frame = P(x, y + 0.22, 0.32) * CFrame.Angles(math.rad(10), 0, 0)
				for _, ox in { -0.24, 0.24 } do
					deco("Lens", Vector3.new(0.06, 0.4, 0.4), frame * CFrame.new(ox, 0, 0) * CFrame.Angles(0, math.rad(90), 0), M.SmoothPlastic, color, {
						Shape = CYL,
						Transparency = 0.25,
						Reflectance = 0.2,
						CastShadow = false,
						Variant = false,
					})
				end
				deco("Bridge", Vector3.new(0.12, 0.04, 0.04), frame * CFrame.new(0, 0.06, 0), M.Metal, color, { CastShadow = false })
			end
		end
	elseif kind == "Books" then
		for _, y in { 1.0, 2.75, 4.5, 6.25 } do
			shelf(y - 0.05, 1.2, M.Wood, Color3.fromRGB(150, 112, 78))
			bookRow(P(0, y, 0.65), length - 0.3, 1.45)
		end
		shelf(8.0, 1.2, M.Wood, Color3.fromRGB(150, 112, 78))
	elseif kind == "Cases" then
		-- Vitrinas de pared: armario abajo, caja de vidrio con terciopelo y piezas iluminadas
		local nCases = math.max(1, math.floor(length / 3.2))
		local seg = length / nCases
		for c = 0, nCases - 1 do
			local x = -length / 2 + seg * (c + 0.5)
			deco("CaseCabinet", Vector3.new(seg - 0.25, 2.6, 1.3), P(x, 1.9, 0.75), M.Wood, Color3.fromRGB(42, 36, 34))
			deco("CaseVelvet", Vector3.new(seg - 0.45, 3.6, 0.08), P(x, 5.1, 0.2), M.Fabric, Color3.fromRGB(28, 26, 40))
			deco("CaseFloor", Vector3.new(seg - 0.45, 0.08, 1.1), P(x, 3.25, 0.75), M.Fabric, Color3.fromRGB(28, 26, 40))
			deco("CaseGlass", Vector3.new(seg - 0.3, 3.7, 0.06), P(x, 5.1, 1.38), M.SmoothPlastic, Color3.fromRGB(215, 232, 238), {
				Transparency = 0.82,
				Reflectance = 0.25,
				CastShadow = false,
				Variant = false,
			})
			deco("CaseTop", Vector3.new(seg - 0.25, 0.25, 1.35), P(x, 7.05, 0.75), M.Wood, Color3.fromRGB(42, 36, 34))
			local led = deco("CaseLED", Vector3.new(seg - 0.6, 0.04, 0.06), P(x, 6.85, 1.15), M.Neon, Color3.fromRGB(255, 246, 230), { CastShadow = false })
			if zoneName then
				tag(led, Tags.Light, { Zone = zoneName })
			end
			for k = -1, 1 do
				deco("Bust", Vector3.new(0.35, 0.9, 0.3), P(x + k * 0.8, 3.75, 0.7), M.Fabric, Color3.fromRGB(235, 230, 222), { CastShadow = false })
				deco("Piece", Vector3.new(0.3, 0.3, 0.3), P(x + k * 0.8, 4.1, 0.86), M.Metal, colors[(c + k + 2) % #colors + 1], {
					Shape = BALL,
					Reflectance = 0.45,
					CastShadow = false,
				})
			end
		end
	end
end

-- Carril de focos en el techo (a lo largo de la profundidad, en x). Las lentes se apagan
-- con la zona (tag MallLight) cuando `zoneName` no es nil.
local function trackLights(base: CFrame, x: number, d1: number, d2: number, heads: number, zoneName: string?)
	local len = d2 - d1
	deco("TrackRail", Vector3.new(0.24, 0.14, len), L(base, x, STORE_H - 0.07, (d1 + d2) / 2), M.Metal, BLACK, { Variant = false, CastShadow = false })
	for i = 0, heads - 1 do
		local d = d1 + 1 + i * ((len - 2) / math.max(1, heads - 1))
		local mount = L(base, x, STORE_H - 0.14, d)
		deco("TrackAdapter", Vector3.new(0.3, 0.2, 0.5), mount * CFrame.new(0, -0.08, 0), M.Metal, BLACK, { CastShadow = false })
		local aim = if i % 2 == 0 then 1 else -1
		local head = mount * CFrame.new(0, -0.7, 0) * CFrame.Angles(math.rad(aim * 10), 0, math.rad(aim * 28))
		deco("TrackArm", Vector3.new(0.08, 0.6, 0.08), mount * CFrame.new(0, -0.38, 0), M.Metal, BLACK, { CastShadow = false })
		deco("TrackCan", Vector3.new(0.95, 0.52, 0.52), head * UPRIGHT, M.SmoothPlastic, BLACK, { Shape = CYL, Variant = false, CastShadow = false })
		local lens = deco("TrackLens", Vector3.new(0.05, 0.42, 0.42), head * CFrame.new(0, -0.48, 0) * UPRIGHT, if zoneName then M.Neon else M.SmoothPlastic, Color3.fromRGB(255, 240, 215), {
			Shape = CYL,
			CastShadow = false,
		})
		if zoneName then
			tag(lens, Tags.Light, { Zone = zoneName })
		end
	end
end

-- Detector de humo, altavoz y camara domo de techo (cf = punto del techo).
local function smokeDetector(cf: CFrame)
	deco("SmokeDetector", Vector3.new(0.22, 0.95, 0.95), cf * CFrame.new(0, -0.11, 0) * UPRIGHT, M.SmoothPlastic, Color3.fromRGB(240, 240, 236), { Shape = CYL, Variant = false, CastShadow = false })
	deco("SmokeLed", Vector3.new(0.07, 0.07, 0.07), cf * CFrame.new(0.28, -0.23, 0), M.Neon, Color3.fromRGB(255, 60, 40), { CastShadow = false })
end

local function ceilingSpeaker(cf: CFrame)
	deco("SpeakerRim", Vector3.new(0.06, 1.35, 1.35), cf * CFrame.new(0, -0.03, 0) * UPRIGHT, M.SmoothPlastic, Color3.fromRGB(238, 238, 235), { Shape = CYL, Variant = false, CastShadow = false })
	deco("SpeakerGrille", Vector3.new(0.07, 1.05, 1.05), cf * CFrame.new(0, -0.04, 0) * UPRIGHT, M.DiamondPlate, Color3.fromRGB(205, 205, 202), { Shape = CYL, CastShadow = false })
end

local function domeCamera(cf: CFrame)
	deco("DomeBase", Vector3.new(0.14, 1.4, 1.4), cf * CFrame.new(0, -0.07, 0) * UPRIGHT, M.SmoothPlastic, Color3.fromRGB(238, 238, 235), { Shape = CYL, Variant = false })
	deco("Dome", Vector3.new(1, 1, 1), cf * CFrame.new(0, -0.1, 0), M.SmoothPlastic, Color3.fromRGB(20, 22, 26), {
		Shape = BALL,
		Transparency = 0.2,
		Reflectance = 0.35,
		CastShadow = false,
		Variant = false,
	})
end

-- Antena antirrobo (EAS) de la entrada: panel acrilico sobre base, cf en el suelo.
local function securityGate(cf: CFrame)
	deco("EASBase", Vector3.new(0.55, 0.22, 1.9), cf * CFrame.new(0, 0.11, 0), M.Metal, Color3.fromRGB(70, 72, 78))
	deco("EASPanel", Vector3.new(0.16, 4.9, 1.45), cf * CFrame.new(0, 2.7, 0), M.SmoothPlastic, Color3.fromRGB(225, 236, 242), {
		Transparency = 0.55,
		Reflectance = 0.2,
		CastShadow = false,
		Variant = false,
	})
	for _, sz in { -0.78, 0.78 } do
		deco("EASEdge", Vector3.new(0.24, 5.0, 0.14), cf * CFrame.new(0, 2.72, sz), M.SmoothPlastic, Color3.fromRGB(235, 235, 232), { Variant = false })
	end
	deco("EASCap", Vector3.new(0.26, 0.22, 1.72), cf * CFrame.new(0, 5.3, 0), M.SmoothPlastic, Color3.fromRGB(235, 235, 232), { Variant = false })
	deco("EASLed", Vector3.new(0.27, 0.05, 1.0), cf * CFrame.new(0, 5.18, 0), M.Neon, Color3.fromRGB(80, 220, 120), { CastShadow = false })
end

-- Cartel colgado del techo con dos cables (texto por las dos caras). cf = centro del cartel;
-- drop = del borde superior del cartel al techo.
local function hangingSign(cf: CFrame, w: number, h: number, text: string, bg: Color3, fg: Color3, font: Enum.Font, drop: number): Part
	local board = deco("HangingSign", Vector3.new(w, h, 0.12), cf, M.SmoothPlastic, bg, { Variant = false })
	sign(board, text, fg, font, Enum.NormalId.Front)
	sign(board, text, fg, font, Enum.NormalId.Back)
	for _, sx in { -1, 1 } do
		deco("SignCable", Vector3.new(0.04, drop, 0.04), cf * CFrame.new(sx * (w / 2 - 0.4), h / 2 + drop / 2, 0), M.Metal, STEEL, { CastShadow = false })
	end
	return board
end

-- Puerta del almacen ("SOLO PERSONAL"): cf = pie de la pared, frente hacia la sala.
local function staffDoor(cf: CFrame)
	deco("StaffDoorFrame", Vector3.new(4.3, 8.25, 0.14), cf * CFrame.new(0, 4.12, -0.07), M.Metal, Color3.fromRGB(72, 74, 78))
	deco("StaffDoor", Vector3.new(3.7, 7.9, 0.12), cf * CFrame.new(0, 3.95, -0.18), M.SmoothPlastic, Color3.fromRGB(208, 206, 200), { Variant = false })
	deco("KickPlate", Vector3.new(3.5, 0.9, 0.03), cf * CFrame.new(0, 0.55, -0.26), M.Metal, STEEL)
	deco("PushPlate", Vector3.new(0.45, 1.5, 0.03), cf * CFrame.new(1.35, 3.9, -0.26), M.Metal, STEEL)
	deco("VisionPanel", Vector3.new(0.6, 1.7, 0.04), cf * CFrame.new(-1.0, 5.3, -0.25), M.SmoothPlastic, Color3.fromRGB(40, 48, 54), { Reflectance = 0.25, Variant = false })
	deco("DoorCloser", Vector3.new(1.4, 0.3, 0.3), cf * CFrame.new(0.7, 7.55, -0.34), M.Metal, Color3.fromRGB(150, 152, 156))
	deco("CloserArm", Vector3.new(1.3, 0.08, 0.08), cf * CFrame.new(-0.45, 7.5, -0.5) * CFrame.Angles(0, math.rad(-15), 0), M.Metal, Color3.fromRGB(150, 152, 156))
	local plate = deco("StaffSign", Vector3.new(2.4, 0.75, 0.03), cf * CFrame.new(0.4, 6.4, -0.26), M.SmoothPlastic, Color3.fromRGB(30, 30, 34), { Variant = false })
	printed(plate, "SOLO PERSONAL", Color3.fromRGB(250, 250, 245), Enum.Font.GothamBold, Enum.NormalId.Front)
end

-- Reloj de pared (cf = punto de la pared, frente hacia la sala).
local function wallClock(cf: CFrame, diameter: number?)
	local dia = diameter or 1.6
	deco("ClockRim", Vector3.new(0.18, dia, dia), cf * CFrame.new(0, 0, -0.09) * CFrame.Angles(0, math.rad(90), 0), M.SmoothPlastic, Color3.fromRGB(30, 30, 34), { Shape = CYL, Variant = false })
	local face = deco("ClockFace", Vector3.new(0.04, dia - 0.2, dia - 0.2), cf * CFrame.new(0, 0, -0.19) * CFrame.Angles(0, math.rad(90), 0), M.SmoothPlastic, Color3.fromRGB(245, 244, 238), { Shape = CYL, Variant = false })
	face.CastShadow = false
	deco("ClockHand", Vector3.new(0.06, dia * 0.3, 0.02), cf * CFrame.new(dia * 0.05, dia * 0.12, -0.22) * CFrame.Angles(0, 0, math.rad(-25)), M.SmoothPlastic, BLACK, { CastShadow = false })
	deco("ClockHand", Vector3.new(0.05, dia * 0.42, 0.02), cf * CFrame.new(-dia * 0.1, -dia * 0.12, -0.23) * CFrame.Angles(0, 0, math.rad(-140)), M.SmoothPlastic, BLACK, { CastShadow = false })
end

-- Poste separador de fila con cinta (de d1 a d2 en x).
local function stanchions(base: CFrame, x: number, d1: number, d2: number, beltColor: Color3)
	local n = 3
	for i = 0, n - 1 do
		local d = d1 + (d2 - d1) * i / (n - 1)
		local p = L(base, x, 0, d)
		deco("StanchionBase", Vector3.new(0.12, 1.1, 1.1), p * CFrame.new(0, 0.06, 0) * UPRIGHT, M.Metal, STEEL, { Shape = CYL })
		deco("StanchionPost", Vector3.new(3.1, 0.2, 0.2), p * CFrame.new(0, 1.65, 0) * UPRIGHT, M.Metal, STEEL, { Shape = CYL })
		deco("StanchionTop", Vector3.new(0.3, 0.34, 0.34), p * CFrame.new(0, 3.25, 0) * UPRIGHT, M.Metal, STEEL, { Shape = CYL })
		if i > 0 then
			local seg = (d2 - d1) / (n - 1)
			deco("Belt", Vector3.new(0.04, 0.25, seg - 0.2), L(base, x, 2.9, d - seg / 2), M.Fabric, beltColor, { CastShadow = false })
		end
	end
end

-- Datafono sobre un mostrador (cf = encimera, frente hacia el cliente).
local function cardTerminal(cf: CFrame)
	local t = cf * CFrame.new(0, 0.12, 0) * CFrame.Angles(math.rad(-18), 0, 0)
	deco("CardTerminal", Vector3.new(0.5, 0.16, 0.9), t, M.SmoothPlastic, Color3.fromRGB(30, 30, 34), { Variant = false })
	local screen = deco("TerminalScreen", Vector3.new(0.36, 0.02, 0.3), t * CFrame.new(0, 0.09, -0.22), M.SmoothPlastic, Color3.fromRGB(20, 40, 60), { CastShadow = false, Variant = false })
	glowScreen(screen, Enum.NormalId.Top, Color3.fromRGB(60, 140, 220), Color3.fromRGB(20, 60, 110), nil)
	deco("TerminalKeys", Vector3.new(0.34, 0.02, 0.36), t * CFrame.new(0, 0.09, 0.2), M.SmoothPlastic, Color3.fromRGB(170, 172, 176), { CastShadow = false, Variant = false })
end

-- Cuadro / cartel enmarcado (impreso: le afecta la luz). cf = punto de la pared.
local function framedPrint(cf: CFrame, w: number, h: number, a: Color3, b: Color3, text: string?)
	deco("PrintFrame", Vector3.new(w + 0.3, h + 0.3, 0.12), cf * CFrame.new(0, 0, -0.06), M.Wood, Color3.fromRGB(30, 28, 26))
	local art = deco("Print", Vector3.new(w, h, 0.04), cf * CFrame.new(0, 0, -0.14), M.SmoothPlastic, a, { Variant = false, CastShadow = false })
	local gui = glowScreen(art, Enum.NormalId.Front, a, b, text)
	gui.LightInfluence = 1
	gui.Brightness = 1
	return art
end

-- Mesa de exposicion (tablero con patas de acero). cf = centro en el suelo.
local function displayTable(cf: CFrame, w: number, dd: number, h: number, top: Color3): CFrame
	box("DisplayTable", Vector3.new(w, 0.2, dd), cf * CFrame.new(0, h - 0.1, 0), M.Wood, top)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			deco("TableLeg", Vector3.new(0.18, h - 0.2, 0.18), cf * CFrame.new(sx * (w / 2 - 0.3), (h - 0.2) / 2, sz * (dd / 2 - 0.3)), M.Metal, Color3.fromRGB(40, 40, 44))
		end
	end
	return cf * CFrame.new(0, h, 0) -- encimera
end

-- Silla sencilla (asiento, respaldo, 4 patas). cf en el suelo, frente -Z.
local function chair(cf: CFrame, color: Color3, seatH: number?)
	local sh = seatH or 1.8
	box("ChairSeat", Vector3.new(1.6, 0.2, 1.6), cf * CFrame.new(0, sh, 0), M.Fabric, color)
	deco("ChairBack", Vector3.new(1.6, 1.7, 0.18), cf * CFrame.new(0, sh + 0.95, 0.72), M.Fabric, color)
	for _, sx in { -0.65, 0.65 } do
		for _, sz in { -0.65, 0.65 } do
			deco("ChairLeg", Vector3.new(0.12, sh, 0.12), cf * CFrame.new(sx, sh / 2, sz), M.Metal, Color3.fromRGB(40, 40, 44))
		end
	end
end

-- Taburete alto (bar, mostrador).
local function stool(cf: CFrame, color: Color3, seatH: number?)
	local sh = seatH or 2.6
	box("StoolSeat", Vector3.new(0.3, 1.3, 1.3), cf * CFrame.new(0, sh, 0) * UPRIGHT, M.Leather, color, { Shape = CYL })
	deco("StoolPost", Vector3.new(sh, 0.2, 0.2), cf * CFrame.new(0, sh / 2, 0) * UPRIGHT, M.Metal, STEEL, { Shape = CYL })
	deco("StoolBase", Vector3.new(0.1, 1.2, 1.2), cf * CFrame.new(0, 0.05, 0) * UPRIGHT, M.Metal, STEEL, { Shape = CYL })
	deco("StoolRing", Vector3.new(0.08, 1.0, 1.0), cf * CFrame.new(0, sh * 0.35, 0) * UPRIGHT, M.Metal, STEEL, { Shape = CYL })
end

-- Lampara de pie con pantalla (la bombilla se apaga con la zona).
local function floorLamp(cf: CFrame, zoneName: string?)
	deco("LampBase", Vector3.new(0.15, 1.3, 1.3), cf * CFrame.new(0, 0.08, 0) * UPRIGHT, M.Metal, Color3.fromRGB(35, 35, 38), { Shape = CYL })
	box("LampPole", Vector3.new(5.4, 0.16, 0.16), cf * CFrame.new(0, 2.8, 0) * UPRIGHT, M.Metal, Color3.fromRGB(35, 35, 38), { Shape = CYL })
	deco("LampShade", Vector3.new(1.3, 1.6, 1.6), cf * CFrame.new(0, 5.8, 0) * UPRIGHT, M.Fabric, Color3.fromRGB(240, 230, 205), { Shape = CYL })
	local bulb = deco("LampBulb", Vector3.new(0.5, 0.5, 0.5), cf * CFrame.new(0, 5.4, 0), M.Neon, Color3.fromRGB(255, 225, 180), { Shape = BALL, CastShadow = false })
	if zoneName then
		local light = Instance.new("PointLight")
		light.Range = 9
		light.Brightness = 0.5
		light.Color = Color3.fromRGB(255, 220, 170)
		light.Parent = bulb
		tag(bulb, Tags.Light, { Zone = zoneName })
	end
end

-- Lampara colgante de la tienda (cable, pantalla y bombilla); cf = punto del techo.
local function storePendant(cf: CFrame, drop: number, shade: Color3, zoneName: string?)
	deco("PendantCable", Vector3.new(0.05, drop, 0.05), cf * CFrame.new(0, -drop / 2, 0), M.Metal, BLACK, { CastShadow = false })
	deco("PendantShade", Vector3.new(1.1, 1.7, 1.7), cf * CFrame.new(0, -drop - 0.45, 0) * UPRIGHT, M.Metal, shade, { Shape = CYL })
	local bulb = deco("PendantBulb", Vector3.new(0.6, 0.6, 0.6), cf * CFrame.new(0, -drop - 1.0, 0), M.Neon, Color3.fromRGB(255, 220, 170), { Shape = BALL, CastShadow = false })
	if zoneName then
		local light = Instance.new("SpotLight")
		light.Face = Enum.NormalId.Bottom
		light.Angle = 80
		light.Range = 12
		light.Brightness = 0.9
		light.Color = Color3.fromRGB(255, 220, 170)
		light.Parent = bulb
		tag(bulb, Tags.Light, { Zone = zoneName })
	end
end

-- Planta en maceta (modelo 3D pequeño o bola de hojas).
local function pottedPlant(cf: CFrame)
	deco("Pot", Vector3.new(1.6, 1.5, 1.5), cf * CFrame.new(0, 0.8, 0) * UPRIGHT, M.SmoothPlastic, Color3.fromRGB(235, 232, 225), { Shape = CYL, Variant = false })
	if not prop("FicusSmall", cf * CFrame.new(0, 1.55, 0), false) then
		deco("Leaves", Vector3.new(2.2, 2.6, 2.2), cf * CFrame.new(0, 3, 0), M.Grass, LEAF_COLORS[1], { Shape = BALL })
	end
end

----------------------------------------------------------------------
-- Interiores de las tiendas (base = marco de la tienda; devuelven true si ya
-- traen escondite). Zonas reservadas por buildStore: mostrador (x -20..-8, d 38..42),
-- pared izquierda (alarma d 6, estante de reponer d 24), derrame (6, 20),
-- tablero (10, d 48), armario (17, d 47).
----------------------------------------------------------------------

INTERIORS = {}

function INTERIORS.Clothes(base: CFrame, def)
	clothesRack(base, -12, 14, pick(4, 0))
	clothesRack(base, 12, 14, pick(4, 2))
	clothesRack(base, -12, 26, pick(4, 4))
	clothesRack(base, 12, 30, pick(4, 1))
	displayMannequin(L(base, -17, 0.6, 3.5) * OUT)
	displayMannequin(L(base, -13, 0.6, 4.5) * OUT * CFrame.Angles(0, math.rad(25), 0))
	displayMannequin(L(base, 15, 0.6, 4) * OUT * CFrame.Angles(0, math.rad(-15), 0))
	foldedTable(base, -2, 31, pick(3, 3))
	mirror(L(base, 22.85, 4.5, 24) * FACE_NEG_X, 3, 7)
	-- Probadores (escondites) en la pared derecha
	for _, d in { 33, 38 } do
		hidingSpot("Probador", L(base, 20.6, 4, d) * FACE_NEG_X, Vector3.new(4.4, 8, 4), M.Fabric, def.Accent:Lerp(Color3.new(0, 0, 0), 0.4))
	end
	return true
end

function INTERIORS.Tech(base: CFrame, def)
	for _, x in { -12, 12 } do
		propOr("LaptopTable", L(base, x, 0, 15) * OUT, function()
			box("DisplayTable", Vector3.new(8, 3, 4), L(base, x, 1.5, 15), M.Wood, Color3.fromRGB(235, 232, 226))
			for i = -1, 1 do
				local lid = deco("Laptop", Vector3.new(1.6, 1.1, 0.08), L(base, x + i * 2.5, 3.6, 15.3) * CFrame.Angles(math.rad(15), 0, 0) * OUT, M.SmoothPlastic, DARK)
				glowScreen(lid, Enum.NormalId.Front, def.Accent, Color3.fromRGB(10, 20, 40), nil)
				deco("LaptopBase", Vector3.new(1.6, 0.06, 1.1), L(base, x + i * 2.5, 3.03, 14.8), M.Metal, STEEL)
			end
		end)
	end
	-- Pared de televisores encendidos (con un brillo de pantalla en la pared)
	for _, d in { 12, 34 } do
		propOr("TVDisplay", L(base, -23, 6.2, d) * FACE_POS_X, function()
			local tv = box("TV", Vector3.new(0.3, 3.6, 6.4), L(base, -22.6, 8, d), M.SmoothPlastic, Color3.fromRGB(10, 10, 12))
			glowScreen(tv, Enum.NormalId.Right, Color3.fromRGB(40, 120, 220), Color3.fromRGB(230, 90, 160), "4K")
		end, false)
		local glow = deco("TVGlow", Vector3.new(0.2, 0.2, 0.2), L(base, -21.5, 8, d), M.SmoothPlastic, Color3.new(1, 1, 1), { Transparency = 1 })
		local light = Instance.new("PointLight")
		light.Range = 8
		light.Brightness = 0.5
		light.Color = Color3.fromRGB(140, 180, 255)
		light.Parent = glow
	end
	wallShelf(base, 1, 30, 14, pick(4, 1), "ElectronicsShelf")
	gondola(base, 2, 32, 9, pick(3, 2), false, "ElectronicsShelf")
end

function INTERIORS.Gamer(base: CFrame, def)
	INTERIORS.Tech(base, def)
	for _, d in { 9, 15 } do
		propOr("ArcadeCabinet", L(base, 20, 0, d) * FACE_NEG_X, function(cf)
			box("Arcade", Vector3.new(3, 6.4, 3), cf * CFrame.new(0, 3.2, 0), M.SmoothPlastic, def.Accent:Lerp(DARK, 0.5))
			local s = deco("ArcadeScreen", Vector3.new(2.4, 1.8, 0.1), cf * CFrame.new(0, 4.6, -1.55), M.SmoothPlastic, DARK)
			glowScreen(s, Enum.NormalId.Front, def.Accent, Color3.fromRGB(255, 200, 60), "PLAY")
		end)
	end
end

function INTERIORS.Toys(base: CFrame)
	gondola(base, -12, 14, 12, pick(3, 0), false, "ToyShelf")
	gondola(base, -12, 28, 12, pick(3, 3), false, "ToyShelf")
	gondola(base, 12, 28, 12, pick(3, 4), false, "ToyShelf")
	-- Oso gigante en el escaparate
	local cf = L(base, -16, 0.6, 5)
	if prop("TeddyBear", cf * OUT * CFrame.Angles(0, math.rad(20), 0)) then
		propOr("ClawMachine", L(base, 15, 0, 8) * OUT, function() end)
		return
	end
	box("Teddy", Vector3.new(4, 4, 3.4), cf * CFrame.new(0, 2, 0), M.Fabric, Color3.fromRGB(160, 110, 70), { Shape = Enum.PartType.Ball })
	box("Teddy", Vector3.new(2.6, 2.6, 2.6), cf * CFrame.new(0, 5, 0), M.Fabric, Color3.fromRGB(160, 110, 70), { Shape = Enum.PartType.Ball })
	for _, ox in { -1, 1 } do
		deco("TeddyEar", Vector3.new(0.9, 0.9, 0.5), cf * CFrame.new(ox, 6.2, 0), M.Fabric, Color3.fromRGB(140, 95, 60), { Shape = Enum.PartType.Ball })
		deco("TeddyEye", Vector3.new(0.25, 0.25, 0.25), cf * CFrame.new(ox * 0.45, 5.3, 1.25), M.SmoothPlastic, DARK, { Shape = Enum.PartType.Ball })
	end
	propOr("ClawMachine", L(base, 15, 0, 8) * OUT, function(c)
		box("ClawMachine", Vector3.new(4, 7, 4), c * CFrame.new(0, 3.5, 0), M.SmoothPlastic, Color3.fromRGB(200, 40, 50))
	end)
end

function INTERIORS.Sports(base: CFrame)
	clothesRack(base, -12, 14, pick(4, 3))
	clothesRack(base, -12, 26, pick(4, 1))
	local bin = L(base, 12, 0, 12)
	box("BallBin", Vector3.new(5, 2, 5), bin * CFrame.new(0, 1, 0), M.Metal, METAL)
	for i = 0, 5 do
		deco("Ball", Vector3.new(1.4, 1.4, 1.4), bin * CFrame.new(-1.6 + (i % 3) * 1.6, 2.6, -0.8 + math.floor(i / 3) * 1.6), M.Leather, PALETTE[i % #PALETTE + 1], {
			Shape = Enum.PartType.Ball,
		})
	end
	for _, d in { 25, 34 } do
		propOr("Treadmill", L(base, 13, 0, d) * OUT * FACE_POS_X, function(cf)
			box("Treadmill", Vector3.new(3, 1.2, 7), cf * CFrame.new(0, 0.6, 0), M.Rubber, DARK)
			box("TreadmillBar", Vector3.new(3, 3.6, 0.4), cf * CFrame.new(0, 2.4, -3.2), M.Metal, METAL)
		end)
	end
	wallShelf(base, 1, 12, 8, pick(3, 2))
end

function INTERIORS.Books(base: CFrame)
	for i, d in { 10, 18, 26, 34 } do
		propOr("Bookshelf", L(base, 22.6, 0, d) * FACE_NEG_X, function()
			wallShelf(base, 1, d, 7, pick(4, i))
		end)
	end
	for _, x in { -10, 4 } do
		box("BookTable", Vector3.new(6, 2.6, 3.4), L(base, x, 1.3, 28), M.Wood, Color3.fromRGB(120, 85, 55))
		for k = 0, 5 do
			local h = rng:NextNumber(0.4, 1)
			deco("BookStack", Vector3.new(1.3, h, 1), L(base, x - 2 + (k % 3) * 2, 2.6 + h / 2, 27.4 + math.floor(k / 3) * 1.4), M.SmoothPlastic, vary(PALETTE[k % #PALETTE + 1], 0.1))
		end
	end
	box("Armchair", Vector3.new(3.4, 1.6, 3.4), L(base, -14, 0.8, 32), M.Leather, Color3.fromRGB(110, 60, 40))
	box("ArmchairBack", Vector3.new(3.4, 2.6, 0.8), L(base, -14, 2.3, 33.4), M.Leather, Color3.fromRGB(110, 60, 40))
	deco("Rug", Vector3.new(8, 0.06, 6), L(base, -12, 0.03, 30), M.Carpet, Color3.fromRGB(150, 60, 50), { Variant = false })
end

function INTERIORS.Shoes(base: CFrame)
	wallShelf(base, 1, 14, 14, pick(4, 1), "ShoeWall")
	wallShelf(base, 1, 30, 10, pick(4, 4), "ShoeWall")
	for _, x in { -10, 10 } do
		box("Bench", Vector3.new(6, 1.4, 2), L(base, x, 0.7, 20), M.Leather, Color3.fromRGB(60, 45, 40))
	end
	-- Mesa central con zapatillas expuestas
	box("ShoeTable", Vector3.new(7, 2.4, 3), L(base, -6, 1.2, 30), M.Wood, Color3.fromRGB(235, 230, 222))
	for k = 0, 5 do
		local color = vary(PALETTE[k % #PALETTE + 1], 0.08)
		local cf = L(base, -8.6 + (k % 3) * 2.6, 2.6, 29.3 + math.floor(k / 3) * 1.4)
		deco("Shoe", Vector3.new(0.6, 0.45, 1.3), cf * CFrame.new(-0.35, 0, 0), M.Leather, color)
		deco("Shoe", Vector3.new(0.6, 0.45, 1.3), cf * CFrame.new(0.35, 0, 0.15), M.Leather, color)
	end
	for i = 0, 3 do
		box("ShoeBoxes", Vector3.new(2, 0.9 * (i + 1), 1.4), L(base, -16 + i * 2.2, 0.45 * (i + 1), 44), M.Cardboard, Color3.fromRGB(180, 140, 95))
	end
end

function INTERIORS.Perfume(base: CFrame)
	for i, p in { { -12, 14 }, { 12, 14 }, { -12, 26 }, { 12, 26 } } do
		propOr("PerfumeCounter", L(base, p[1], 0, p[2]) * OUT, function()
			glassCase(base, p[1], p[2], pick(3, i))
		end)
	end
	mirror(L(base, 22.85, 5, 20) * FACE_NEG_X, 8, 8)
	-- Columna-expositor iluminada en el centro
	box("DisplayColumn", Vector3.new(2.4, 6, 2.4), L(base, 0, 3, 32), M.Marble, Color3.fromRGB(240, 238, 235))
	local top = deco("ColumnGlow", Vector3.new(2.2, 0.1, 2.2), L(base, 0, 6.06, 32), M.Neon, Color3.fromRGB(255, 230, 255))
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(230, 190, 255)
	light.Range = 8
	light.Brightness = 0.6
	light.Parent = top
end

function INTERIORS.Optics(base: CFrame)
	glassCase(base, -12, 16, pick(3, 1))
	glassCase(base, 12, 16, pick(3, 4))
	local chart = box("EyeChart", Vector3.new(0.2, 7, 5), L(base, 22.8, 6, 28), M.SmoothPlastic, Color3.fromRGB(245, 245, 245))
	sign(chart, "E\nF P\nT O Z\nL P E D", DARK, Enum.Font.SourceSansBold, Enum.NormalId.Left)
	for _, x in { -6, 0, 6 } do
		box("Chair", Vector3.new(2, 1.6, 2), L(base, x, 0.8, 30), M.Fabric, Color3.fromRGB(70, 90, 140))
	end
	wallShelf(base, 1, 14, 10, pick(4, 5))
	mirror(L(base, 22.85, 4.5, 36) * FACE_NEG_X, 3, 5)
end

function INTERIORS.Home(base: CFrame)
	propOr("Sofa", L(base, -12, 0, 14) * OUT, function(cf)
		box("Sofa", Vector3.new(9, 1.8, 3.4), cf * CFrame.new(0, 0.9, 0), M.Fabric, Color3.fromRGB(120, 130, 150))
		box("SofaBack", Vector3.new(9, 2.4, 0.9), cf * CFrame.new(0, 2.6, -1.3), M.Fabric, Color3.fromRGB(120, 130, 150))
	end)
	box("CoffeeTable", Vector3.new(4, 1.4, 2.4), L(base, -12, 0.7, 9.5), M.Wood, Color3.fromRGB(120, 85, 55))
	deco("Rug", Vector3.new(10, 0.06, 8), L(base, -12, 0.03, 12), M.Carpet, Color3.fromRGB(200, 170, 120), { Variant = false })
	local bed = L(base, 12, 0, 28)
	propOr("Bed", bed * OUT, function()
		box("Bed", Vector3.new(7, 1.8, 10), bed * CFrame.new(0, 0.9, 0), M.Fabric, Color3.fromRGB(235, 235, 240))
		deco("Duvet", Vector3.new(7.2, 0.4, 6), bed * CFrame.new(0, 1.9, 1.5), M.Fabric, Color3.fromRGB(110, 125, 150))
		for _, ox in { -1.8, 1.8 } do
			deco("Pillow", Vector3.new(2.6, 0.6, 1.4), bed * CFrame.new(ox, 2.1, -4), M.Fabric, Color3.fromRGB(245, 245, 245))
		end
		box("Headboard", Vector3.new(7, 4, 0.6), bed * CFrame.new(0, 2, -5.2), M.Wood, Color3.fromRGB(120, 85, 55))
	end)
	box("Lamp", Vector3.new(0.4, 5, 0.4), L(base, -18, 2.5, 20), M.Metal, METAL)
	deco("LampShade", Vector3.new(1.8, 1.4, 1.8), L(base, -18, 5.4, 20), M.Fabric, Color3.fromRGB(240, 225, 190))
	wallShelf(base, 1, 14, 10, pick(4, 2))
end

function INTERIORS.Furniture(base: CFrame)
	for _, p in { { -12, 12 }, { 12, 12 }, { -4, 30 } } do
		propOr("Sofa", L(base, p[1], 0, p[2]) * OUT, function(cf)
			box("Sofa", Vector3.new(9, 1.8, 3.4), cf * CFrame.new(0, 0.9, 0), M.Fabric, Color3.fromRGB(150, 150, 155))
			box("SofaBack", Vector3.new(9, 2.4, 0.9), cf * CFrame.new(0, 2.6, -1.3), M.Fabric, Color3.fromRGB(150, 150, 155))
		end)
		deco("Rug", Vector3.new(10, 0.06, 7), L(base, p[1], 0.03, p[2] - 3), M.Carpet, vary(Color3.fromRGB(190, 170, 140), 0.1), { Variant = false })
		box("CoffeeTable", Vector3.new(4, 1.4, 2.2), L(base, p[1], 0.7, p[2] - 4.5), M.Wood, Color3.fromRGB(110, 80, 50))
	end
	for i, d in { 26, 34 } do
		propOr("Bookshelf", L(base, 22.6, 0, d) * FACE_NEG_X, function()
			wallShelf(base, 1, d, 7, pick(4, i + 2))
		end)
	end
	for _, x in { -18, 18 } do
		box("FloorLamp", Vector3.new(0.3, 6, 0.3), L(base, x, 3, 20), M.Metal, DARK)
		deco("FloorLampShade", Vector3.new(1.6, 1.3, 1.6), L(base, x, 6.2, 20), M.Fabric, Color3.fromRGB(240, 228, 200))
	end
end

function INTERIORS.Music(base: CFrame)
	propOr("Piano", L(base, -12, 0, 16) * OUT, function(cf)
		box("Piano", Vector3.new(7, 3.2, 3), cf * CFrame.new(0, 1.6, 0), M.SmoothPlastic, Color3.fromRGB(15, 15, 18), { Reflectance = 0.1 })
		deco("Keys", Vector3.new(6.4, 0.2, 1), cf * CFrame.new(0, 3.2, 1.4), M.SmoothPlastic, Color3.fromRGB(245, 245, 245))
	end)
	for i = 0, 3 do
		local g = L(base, 22.5, 0, 10 + i * 5) * FACE_NEG_X
		deco("GuitarHook", Vector3.new(0.2, 0.2, 0.6), g * CFrame.new(0, 9.4, 0.3), M.Metal, METAL)
		if not prop("ElectricGuitar", g * CFrame.new(0, 4.4, 0.4), false) then
			box("GuitarBody", Vector3.new(2, 2.6, 0.5), g * CFrame.new(0, 5, 0), M.Wood, PALETTE[i + 1])
			deco("GuitarNeck", Vector3.new(0.4, 3.4, 0.3), g * CFrame.new(0, 7.8, 0), M.Wood, Color3.fromRGB(90, 60, 35))
		end
	end
	for _, x in { -18, 18 } do
		propOr("Speaker", L(base, x, 0, 6) * OUT, function()
			box("Speaker", Vector3.new(2.6, 6, 2.6), L(base, x, 3, 6), M.Fabric, Color3.fromRGB(25, 25, 28))
			for k, y in { 1.5, 4.2 } do
				deco("Woofer", Vector3.new(0.1, 1.6 + k * 0.2, 1.6 + k * 0.2), L(base, x, y, 4.68) * CFrame.Angles(0, math.rad(90), 0), M.SmoothPlastic, Color3.fromRGB(50, 50, 55), {
					Shape = Enum.PartType.Cylinder,
				})
			end
		end)
	end
	-- Bateria
	local kit = L(base, 10, 0, 30)
	if prop("DrumKit", kit * OUT) then
		return
	end
	box("BassDrum", Vector3.new(2, 3, 3), kit * CFrame.new(0, 1.5, 0) * CFrame.Angles(0, math.rad(90), 0), M.Plastic, Color3.fromRGB(170, 30, 35), {
		Shape = Enum.PartType.Cylinder,
	})
	for _, p in { { -2, 2.4 }, { 2, 2.6 } } do
		deco("Tom", Vector3.new(1, 1.6, 1.6), kit * CFrame.new(p[1], p[2], -0.5) * CFrame.Angles(0, 0, math.rad(90)), M.Plastic, Color3.fromRGB(170, 30, 35), {
			Shape = Enum.PartType.Cylinder,
		})
		deco("Cymbal", Vector3.new(0.05, 2.2, 2.2), kit * CFrame.new(p[1] * 1.5, 4.6, 0.5) * CFrame.Angles(0, 0, math.rad(90)), M.Foil, Color3.fromRGB(210, 170, 70), {
			Shape = Enum.PartType.Cylinder,
		})
	end
end

function INTERIORS.Jewelry(base: CFrame, def)
	for _, p in { { -12, 14 }, { 12, 14 }, { -12, 27 }, { 12, 27 } } do
		propOr("JewelryCase", L(base, p[1], 0, p[2]) * OUT, function()
			glassCase(base, p[1], p[2], { def.Accent, Color3.fromRGB(230, 230, 240), Color3.fromRGB(200, 60, 80) })
		end)
	end
	mirror(L(base, 22.85, 5, 20) * FACE_NEG_X, 5, 7)
	deco("VelvetRug", Vector3.new(10, 0.06, 20), L(base, 0, 0.03, 20), M.Fabric, Color3.fromRGB(70, 20, 30))
	box("Safe", Vector3.new(3, 4, 3), L(base, 19, 2, 36), M.Metal, Color3.fromRGB(60, 62, 66))
	deco("SafeDial", Vector3.new(0.2, 0.9, 0.9), L(base, 19, 2.4, 34.4) * CFrame.Angles(0, math.rad(90), 0), M.Metal, STEEL, { Shape = Enum.PartType.Cylinder })
end

function INTERIORS.Pharmacy(base: CFrame, def)
	gondola(base, -11, 14, 10, pick(3, 4), false, "PharmacyShelf")
	gondola(base, -11, 26, 10, pick(3, 2), false, "PharmacyShelf")
	gondola(base, 12, 30, 10, pick(3, 0), false, "PharmacyShelf")
	wallShelf(base, 1, 14, 14, { Color3.fromRGB(235, 235, 240), def.Accent, Color3.fromRGB(240, 240, 245), Color3.fromRGB(90, 140, 220) })
	-- Cruz verde luminosa sobre el mostrador
	local crossCF = L(base, -14, 10.5, 48.8) * OUT
	neonStrip(Vector3.new(3.2, 1, 0.2), crossCF, def.Accent, def.Name, 0.6)
	neonStrip(Vector3.new(1, 3.2, 0.2), crossCF, def.Accent, def.Name)
	for i = 0, 2 do
		box("WaitingChair", Vector3.new(2, 1.6, 2), L(base, 4 + i * 2.4, 0.8, 44), M.Plastic, Color3.fromRGB(80, 160, 120))
	end
end

function INTERIORS.Gym(base: CFrame, def)
	for _, x in { -16, -10, -4 } do
		propOr("Treadmill", L(base, x, 0, 16) * OUT, function(cf)
			box("Treadmill", Vector3.new(3, 1.2, 7), cf * CFrame.new(0, 0.6, 0), M.Rubber, DARK)
			box("TreadmillBar", Vector3.new(3, 3.6, 0.4), cf * CFrame.new(0, 2.4, 3.2), M.Metal, METAL)
		end)
	end
	mirror(L(base, 22.85, 5, 25) * FACE_NEG_X, 28, 8)
	-- Rack de mancuernas y banco
	local rack = L(base, 16, 0, 32) * FACE_NEG_X
	if not propRow("DumbbellRack", rack, 8, 4) then
		box("DumbbellRack", Vector3.new(8, 2.6, 2), rack * CFrame.new(0, 1.3, 0), M.Metal, DARK)
		for k = 0, 7 do
			deco("Dumbbell", Vector3.new(0.9, 0.5, 0.5), rack * CFrame.new(-3.4 + k, 2.85, 0), M.Metal, Color3.fromRGB(40, 40, 44))
		end
	end
	box("WeightBench", Vector3.new(1.6, 1.6, 5), L(base, 4, 0.8, 32), M.Leather, def.Accent:Lerp(DARK, 0.4))
	deco("Barbell", Vector3.new(7, 0.2, 0.2), L(base, 4, 3.6, 30), M.Metal, STEEL)
	for _, ox in { -3.2, 3.2 } do
		deco("Plate", Vector3.new(0.3, 2, 2), L(base, 4 + ox, 3.6, 30) * CFrame.Angles(0, 0, 0), M.Metal, DARK, { Shape = Enum.PartType.Cylinder })
	end
	deco("RubberMat", Vector3.new(20, 0.08, 14), L(base, 4, 0.04, 32), M.Rubber, Color3.fromRGB(35, 35, 38), { Variant = false })
end

function INTERIORS.Cafe(base: CFrame, def)
	for i, p in { { -12, 12 }, { 12, 12 }, { -12, 26 }, { 12, 28 }, { 0, 32 } } do
		propOr("BistroTable", L(base, p[1], 0, p[2]) * CFrame.Angles(0, i * 0.7, 0), function(cf)
			roundTable(cf, 3, def.Accent:Lerp(DARK, 0.3))
		end)
	end
	glassCase(base, -2, 40, { Color3.fromRGB(210, 160, 100), Color3.fromRGB(240, 220, 180), Color3.fromRGB(120, 70, 40) })
	propOr("EspressoMachine", L(base, -18, 3.7, 40) * OUT, function()
		box("EspressoMachine", Vector3.new(2.4, 1.6, 1.6), L(base, -18, 4.4, 40), M.Metal, STEEL)
	end, false)
	lightbox(L(base, -14, 9.5, 48.75) * OUT, 10, 3, "MENÚ · CAFÉ · POSTRES", def.Accent, def.Name)
	deco("Rug", Vector3.new(12, 0.06, 10), L(base, 0, 0.03, 20), M.Carpet, Color3.fromRGB(120, 90, 70), { Variant = false })
end

function INTERIORS.Market(base: CFrame)
	for _, x in { -12, 0, 12 } do
		for _, d in { 15, 29 } do
			gondola(base, x, d, 8, pick(3, (x + d) % 6))
		end
	end
	-- Congeladores iluminados en la pared derecha
	for _, d in { 12, 22, 32 } do
		local cf = L(base, 22, 0, d) * FACE_NEG_X
		if not propRow("Freezer", cf * CFrame.new(0, 0, 0.2), 8, 4) then
			box("Freezer", Vector3.new(8, 7, 2.2), cf * CFrame.new(0, 3.5, 0.2), M.Metal, Color3.fromRGB(225, 228, 232))
			local doorGlass = deco("FreezerGlass", Vector3.new(7.4, 5.6, 0.08), cf * CFrame.new(0, 3.6, -0.95), M.SmoothPlastic, Color3.fromRGB(200, 230, 245), { Transparency = 0.4 })
			glowScreen(doorGlass, Enum.NormalId.Front, Color3.fromRGB(220, 240, 255), Color3.fromRGB(160, 200, 230), nil)
		end
		local cold = deco("FreezerLight", Vector3.new(0.2, 0.2, 0.2), cf * CFrame.new(0, 5, -1.6), M.SmoothPlastic, Color3.new(1, 1, 1), { Transparency = 1 })
		local light = Instance.new("PointLight")
		light.Range = 8
		light.Brightness = 0.6
		light.Color = Color3.fromRGB(200, 230, 255)
		light.Parent = cold
	end
	-- Cajas rapidas cerca de la entrada
	for _, x in { -14, -6 } do
		propOr("CheckoutCounter", L(base, x, 0, 9), function()
			box("Checkout", Vector3.new(2, 3, 6), L(base, x, 1.5, 9), M.Metal, Color3.fromRGB(90, 92, 98))
			propOr("CashRegister", L(base, x, 3, 7.5) * FACE_POS_X, function(cf)
				box("Register", Vector3.new(1.4, 1, 1.2), cf * CFrame.new(0, 0.5, 0), M.Metal, DARK)
			end, false)
		end)
	end
end

function INTERIORS.Salon(base: CFrame, def)
	for _, d in { 10, 18, 26, 34 } do
		local cf = L(base, 22.9, 0, d) * FACE_NEG_X
		mirror(cf * CFrame.new(0, 5, 0), 3.4, 4.5)
		for k = -1, 1, 2 do
			neonStrip(Vector3.new(0.2, 4.4, 0.2), cf * CFrame.new(k * 1.9, 5, -0.1), Color3.fromRGB(255, 240, 220), def.Name)
		end
		deco("Counter", Vector3.new(3.6, 0.2, 1.2), cf * CFrame.new(0, 3, -0.6), M.Marble, Color3.fromRGB(240, 238, 235))
		local chair = cf * CFrame.new(0, 0, -3.4)
		-- La silla mira al espejo (de espaldas a la sala)
		propOr("SalonChair", chair * CFrame.Angles(0, math.pi, 0), function()
			box("SalonChair", Vector3.new(2.2, 0.8, 2.2), chair * CFrame.new(0, 2.2, 0), M.Leather, DARK)
			deco("SalonChairBack", Vector3.new(2.2, 2.4, 0.4), chair * CFrame.new(0, 3.6, -1), M.Leather, DARK)
			deco("SalonChairBase", Vector3.new(0.3, 1.8, 1.8), chair * CFrame.new(0, 0.9, 0) * CFrame.Angles(0, 0, math.rad(90)), M.Metal, STEEL, {
				Shape = Enum.PartType.Cylinder,
			})
		end)
	end
	for _, d in { 14, 32 } do
		box("WashBasin", Vector3.new(2.6, 3, 2.6), L(base, -20, 1.5, d), M.SmoothPlastic, Color3.fromRGB(30, 30, 34))
		deco("Sink", Vector3.new(2, 0.6, 1.8), L(base, -20, 3.2, d), M.SmoothPlastic, Color3.fromRGB(245, 245, 245))
	end
	propOr("Sofa", L(base, -6, 0, 7) * OUT, function(cf)
		box("Sofa", Vector3.new(8, 1.8, 3), cf * CFrame.new(0, 0.9, 0), M.Leather, def.Accent:Lerp(DARK, 0.5))
	end)
end

----------------------------------------------------------------------
-- Mobiliario extra por tipo de tienda (se pone despues del interior).
-- Respeta las zonas reservadas de buildStore y lo que ya coloca cada interior.
----------------------------------------------------------------------

-- Punto del suelo de la tienda mirando hacia la entrada.
local function F(base: CFrame, x: number, d: number): CFrame
	return L(base, x, 0, d) * OUT
end

-- Mesas nido: una alta y dos bajas delante, con pilas de ropa doblada.
local function nestingTables(base: CFrame, x: number, d: number, colors: { Color3 })
	local top = displayTable(L(base, x, 0, d), 5, 2.6, 3.2, Color3.fromRGB(196, 160, 118))
	stackRow(top, 4.4, 1.2, colors, 0.75, 1.1)
	for _, sx in { -1, 1 } do
		local low = displayTable(L(base, x + sx * 1.7, 0, d - 2.6), 3, 2.0, 2.2, Color3.fromRGB(226, 222, 214))
		stackRow(low, 2.6, 1.1, colors, 0.6, 1.3)
	end
end

-- Mesa de dispositivos: moviles (o consolas) en peanas con cable antirrobo, por las dos caras.
local function deviceTable(base: CFrame, x: number, d: number, accent: Color3, gaming: boolean)
	local top = displayTable(L(base, x, 0, d), 8, 3.4, 3.1, Color3.fromRGB(214, 190, 150))
	for _, side in { -1, 1 } do
		for k = 0, 3 do
			local cf = top * CFrame.new(-3 + k * 2, 0, side * 0.95) * (if side > 0 then OUT else CFrame.new())
			if gaming then
				deco("Console", Vector3.new(1.2, 0.3, 0.9), cf * CFrame.new(0, 0.15, 0.1), M.SmoothPlastic, if k % 2 == 0 then BLACK else Color3.fromRGB(235, 235, 238), { Variant = false })
				deco("Controller", Vector3.new(0.8, 0.18, 0.5), cf * CFrame.new(0, 0.09, -0.6) * CFrame.Angles(0, math.rad(8 * (k - 1.5)), 0), M.SmoothPlastic, if k % 2 == 0 then Color3.fromRGB(40, 40, 46) else Color3.fromRGB(225, 225, 230), { Variant = false })
			else
				deco("DeviceStand", Vector3.new(0.55, 0.1, 0.55), cf * CFrame.new(0, 0.05, 0), M.Metal, STEEL)
				local dev = deco("Device", Vector3.new(0.46, 0.92, 0.06), cf * CFrame.new(0, 0.6, 0.05) * CFrame.Angles(math.rad(12), 0, 0), M.SmoothPlastic, BLACK, { Variant = false })
				glowScreen(dev, Enum.NormalId.Front, accent:Lerp(Color3.new(1, 1, 1), 0.2), Color3.fromRGB(15, 20, 40), nil)
				deco("SecurityCable", Vector3.new(0.05, 0.05, 0.6), cf * CFrame.new(0, 0.03, 0.45), M.Rubber, BLACK, { CastShadow = false })
			end
			local price = deco("PriceCard", Vector3.new(0.6, 0.02, 0.35), cf * CFrame.new(0, 0.02, -0.55), M.SmoothPlastic, Color3.fromRGB(250, 250, 248), { CastShadow = false, Variant = false })
			printed(price, string.format("%d,99 €", 99 + k * 100), BLACK, Enum.Font.GothamBold, Enum.NormalId.Top)
		end
	end
	if gaming then
		local mon = deco("DemoMonitor", Vector3.new(3.2, 1.9, 0.12), top * CFrame.new(0, 1.3, 0), M.SmoothPlastic, BLACK, { Variant = false })
		glowScreen(mon, Enum.NormalId.Front, accent, Color3.fromRGB(255, 80, 120), "DEMO")
		glowScreen(mon, Enum.NormalId.Back, accent, Color3.fromRGB(40, 200, 255), "JUEGA")
		deco("MonitorStand", Vector3.new(0.3, 0.6, 0.3), top * CFrame.new(0, 0.3, 0), M.Metal, BLACK)
	end
end

-- Expositor giratorio de complementos (gafas de sol, bisuteria, llaveros).
local function spinnerRack(cf: CFrame, colors: { Color3 })
	deco("SpinnerBase", Vector3.new(0.15, 1.6, 1.6), cf * CFrame.new(0, 0.08, 0) * UPRIGHT, M.Metal, Color3.fromRGB(40, 40, 44), { Shape = CYL })
	box("SpinnerPole", Vector3.new(6, 0.16, 0.16), cf * CFrame.new(0, 3, 0) * UPRIGHT, M.Metal, STEEL, { Shape = CYL })
	deco("SpinnerTopper", Vector3.new(1.4, 0.6, 1.4), cf * CFrame.new(0, 6.2, 0), M.SmoothPlastic, colors[1], { Variant = false })
	for tier = 0, 2 do
		for k = 0, 5 do
			local a = math.rad(k * 60 + tier * 20)
			local item = cf * CFrame.new(0, 2.4 + tier * 1.3, 0) * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -0.75)
			deco("SpinnerItem", Vector3.new(0.6, 0.8, 0.06), item, M.SmoothPlastic, vary(colors[(k + tier) % #colors + 1], 0.06), { CastShadow = false, Variant = false })
		end
	end
end

-- Mesita infantil con taburetes y piezas de construccion.
local function kidsTable(cf: CFrame)
	box("KidsTable", Vector3.new(0.2, 3.4, 3.4), cf * CFrame.new(0, 1.7, 0) * UPRIGHT, M.SmoothPlastic, Color3.fromRGB(250, 250, 245), { Shape = CYL, Variant = false })
	deco("KidsTableLeg", Vector3.new(1.6, 0.4, 0.4), cf * CFrame.new(0, 0.8, 0) * UPRIGHT, M.SmoothPlastic, Color3.fromRGB(80, 170, 230), { Shape = CYL, Variant = false })
	for k = 0, 3 do
		local a = math.rad(k * 90 + 45)
		deco("KidsStool", Vector3.new(1.1, 1.1, 1.1), cf * CFrame.new(math.cos(a) * 2.5, 0.55, math.sin(a) * 2.5) * UPRIGHT, M.SmoothPlastic, BRIGHT[k + 1], { Shape = CYL, Variant = false })
	end
	for k = 0, 6 do
		deco("Block", Vector3.new(0.4, 0.4, 0.8), cf * CFrame.new(-1 + (k % 4) * 0.6, 1.95 + (k // 4) * 0.4, -0.4 + (k % 3) * 0.4) * CFrame.Angles(0, math.rad(k * 23), 0), M.SmoothPlastic, BRIGHT[k % #BRIGHT + 1], { CastShadow = false, Variant = false })
	end
end

-- Coche correpasillos de juguete (frente -Z).
local function rideOnCar(cf: CFrame, color: Color3)
	box("ToyCarBody", Vector3.new(2.4, 1.1, 4), cf * CFrame.new(0, 1.05, 0), M.SmoothPlastic, color, { Variant = false, Reflectance = 0.1 })
	deco("ToyCarHood", Vector3.new(2.2, 0.5, 1.4), cf * CFrame.new(0, 1.8, -1.1), M.SmoothPlastic, color, { Variant = false, Reflectance = 0.1 })
	deco("ToyCarSeat", Vector3.new(1.6, 0.9, 0.4), cf * CFrame.new(0, 2.0, 1.1), M.SmoothPlastic, BLACK, { Variant = false })
	deco("ToyCarWheel", Vector3.new(0.2, 0.8, 0.2), cf * CFrame.new(0, 2.2, -0.3) * CFrame.Angles(math.rad(-30), 0, 0), M.Metal, BLACK)
	deco("ToyCarSteer", Vector3.new(0.12, 0.8, 0.8), cf * CFrame.new(0, 2.6, -0.1) * CFrame.Angles(math.rad(-30), math.rad(90), 0), M.SmoothPlastic, BLACK, { Shape = CYL })
	for _, sx in { -1.25, 1.25 } do
		for _, sz in { -1.3, 1.3 } do
			deco("ToyCarTyre", Vector3.new(0.4, 1.1, 1.1), cf * CFrame.new(sx, 0.55, sz), M.Rubber, BLACK, { Shape = CYL })
		end
	end
	for _, sx in { -0.7, 0.7 } do
		deco("ToyCarLight", Vector3.new(0.5, 0.3, 0.06), cf * CFrame.new(sx, 1.3, -2.02), M.SmoothPlastic, Color3.fromRGB(255, 250, 220), { Variant = false })
	end
end

-- Racimo de globos atados a una pesa.
local function balloons(cf: CFrame)
	deco("BalloonWeight", Vector3.new(0.5, 0.4, 0.5), cf * CFrame.new(0, 0.2, 0), M.SmoothPlastic, Color3.fromRGB(230, 60, 80), { Variant = false })
	for k = 0, 4 do
		local a = math.rad(k * 72)
		local top = Vector3.new(math.cos(a) * 0.9, 7 + (k % 2) * 0.8, math.sin(a) * 0.9)
		local bottom = Vector3.new(0, 0.4, 0)
		local mid = (top + bottom) / 2
		deco("BalloonString", Vector3.new(0.02, 0.02, (top - bottom).Magnitude), cf * CFrame.lookAt(mid, top), M.SmoothPlastic, Color3.fromRGB(240, 240, 240), { CastShadow = false })
		deco("Balloon", Vector3.new(1.3, 1.6, 1.3), cf * CFrame.new(top + Vector3.new(0, 0.75, 0)), M.SmoothPlastic, BRIGHT[k + 1], { Shape = BALL, Reflectance = 0.2, Variant = false })
	end
end

-- Bicicleta (cf = centro entre las ruedas a la altura del eje; plano de la bici = X-Y).
local function bike(cf: CFrame, color: Color3)
	for _, sx in { -1.7, 1.7 } do
		deco("BikeTyre", Vector3.new(0.18, 2.3, 2.3), cf * CFrame.new(sx, 0, 0) * CFrame.Angles(0, math.rad(90), 0), M.Rubber, BLACK, { Shape = CYL })
		deco("BikeRim", Vector3.new(0.2, 1.9, 1.9), cf * CFrame.new(sx, 0, 0) * CFrame.Angles(0, math.rad(90), 0), M.Metal, Color3.fromRGB(70, 72, 78), { Shape = CYL, Transparency = 0.3 })
		deco("BikeHub", Vector3.new(0.3, 0.3, 0.3), cf * CFrame.new(sx, 0, 0) * CFrame.Angles(0, math.rad(90), 0), M.Metal, STEEL, { Shape = CYL })
	end
	local function tube(a: Vector3, b: Vector3, thick: number?)
		local mid = (a + b) / 2
		deco("BikeTube", Vector3.new(thick or 0.16, thick or 0.16, (b - a).Magnitude), cf * CFrame.lookAt(mid, b), M.Metal, color, { Reflectance = 0.15 })
	end
	local bb, seat, head = Vector3.new(-0.2, -0.2, 0), Vector3.new(-0.6, 1.5, 0), Vector3.new(1.0, 1.5, 0)
	tube(bb, seat)
	tube(seat, head)
	tube(bb, head)
	tube(bb, Vector3.new(-1.7, 0, 0), 0.12)
	tube(seat, Vector3.new(-1.7, 0, 0), 0.12)
	tube(head, Vector3.new(1.7, 0, 0), 0.14)
	deco("BikeSaddle", Vector3.new(0.9, 0.16, 0.35), cf * CFrame.new(-0.7, 1.85, 0), M.Leather, BLACK)
	deco("BikeBars", Vector3.new(0.12, 0.12, 1.5), cf * CFrame.new(1.05, 1.9, 0), M.Metal, BLACK)
	deco("BikeCrank", Vector3.new(0.12, 0.7, 0.7), cf * CFrame.new(-0.2, -0.2, 0) * CFrame.Angles(0, math.rad(90), 0), M.Metal, STEEL, { Shape = CYL })
end

-- Cubo con esterillas enrolladas (deportes).
local function yogaBin(cf: CFrame)
	box("MatBin", Vector3.new(2.2, 2.2, 2.2), cf * CFrame.new(0, 1.1, 0) * UPRIGHT, M.Metal, Color3.fromRGB(60, 62, 68), { Shape = CYL })
	for k = 0, 5 do
		local a = math.rad(k * 60)
		local r = if k == 0 then 0 else 0.6
		deco("RolledMat", Vector3.new(3.0, 0.6, 0.6), cf * CFrame.new(math.cos(a) * r, 2.6, math.sin(a) * r) * UPRIGHT * CFrame.Angles(math.rad(k * 3), 0, 0), M.Rubber, BRIGHT[k + 2], { Shape = CYL, CastShadow = false })
	end
end

-- Estanteria baja de doble cara con libros (isla) y novedades de cara encima.
local function lowBookcase(cf: CFrame, len: number)
	box("LowBookcase", Vector3.new(len, 4.4, 2.4), cf * CFrame.new(0, 2.2, 0), M.Wood, Color3.fromRGB(150, 112, 78))
	for _, side in { -1, 1 } do
		local face = cf * CFrame.new(0, 0, side * 0.8) * (if side > 0 then OUT else CFrame.new())
		for _, y in { 0.35, 1.75, 3.0 } do
			bookRow(face * CFrame.new(0, y, 0.0), len - 0.4, 1.25)
		end
	end
	for k = 0, 3 do
		local book = deco("FaceOutBook", Vector3.new(1.4, 1.9, 0.18), cf * CFrame.new(-len / 2 + 1.2 + k * (len - 2.4) / 3, 5.3, 0) * CFrame.Angles(math.rad(-12), 0, 0), M.SmoothPlastic, vary(BRIGHT[k + 1], 0.1), { Variant = false })
		printed(book, ({ "LA NOCHE", "EL MALL", "SOMBRAS", "TURNO" })[k + 1], Color3.new(1, 1, 1), Enum.Font.Merriweather, Enum.NormalId.Front)
		printed(book, ({ "RELATOS", "CUENTOS", "MISTERIO", "POESÍA" })[k + 1], Color3.new(1, 1, 1), Enum.Font.Merriweather, Enum.NormalId.Back)
	end
end

-- Espejo de suelo inclinado (zapateria).
local function floorMirror(cf: CFrame)
	deco("FloorMirrorBack", Vector3.new(1.4, 2.6, 0.12), cf * CFrame.new(0, 1.3, 0.3) * CFrame.Angles(math.rad(-14), 0, 0), M.SmoothPlastic, BLACK, { Variant = false })
	deco("FloorMirror", Vector3.new(1.2, 2.4, 0.04), cf * CFrame.new(0, 1.3, 0.22) * CFrame.Angles(math.rad(-14), 0, 0), M.SmoothPlastic, Color3.fromRGB(170, 182, 190), { Reflectance = 0.3, Variant = false })
end

-- Tocador de maquillaje con bombillas (cf = pie de la pared lateral).
local function vanityStation(cf: CFrame, zoneName: string)
	box("VanityCounter", Vector3.new(4.4, 0.25, 1.6), cf * CFrame.new(0, 3.2, -0.8), M.Marble, Color3.fromRGB(245, 243, 238))
	deco("VanityCabinet", Vector3.new(4.2, 2.9, 1.4), cf * CFrame.new(0, 1.55, -0.72), M.SmoothPlastic, Color3.fromRGB(30, 28, 32), { Variant = false })
	deco("VanityMirrorFrame", Vector3.new(3.6, 3.8, 0.1), cf * CFrame.new(0, 5.6, -0.05), M.SmoothPlastic, Color3.fromRGB(250, 248, 244), { Variant = false })
	deco("VanityMirror", Vector3.new(3.0, 3.2, 0.06), cf * CFrame.new(0, 5.6, -0.12), M.SmoothPlastic, Color3.fromRGB(170, 182, 190), { Reflectance = 0.3, Variant = false })
	for k = 0, 3 do
		for _, sx in { -1.65, 1.65 } do
			local bulb = deco("VanityBulb", Vector3.new(0.3, 0.3, 0.3), cf * CFrame.new(sx, 4.1 + k * 1.0, -0.15), M.Neon, Color3.fromRGB(255, 240, 220), { Shape = BALL, CastShadow = false })
			tag(bulb, Tags.Light, { Zone = zoneName })
		end
	end
	for k = 0, 4 do
		deco("Lipstick", Vector3.new(0.4, 0.14, 0.14), cf * CFrame.new(-1.6 + k * 0.4, 3.53, -1.1) * UPRIGHT, M.SmoothPlastic, BRIGHT[k + 1], { Shape = CYL, CastShadow = false })
	end
	stool(cf * CFrame.new(0, 0, -2.6), Color3.fromRGB(30, 28, 32), 2.4)
end

-- Puesto de graduacion de la vista: sillon, foroptero en su brazo y mesita.
local function examStation(cf: CFrame)
	box("ExamSeat", Vector3.new(2.2, 0.6, 2.2), cf * CFrame.new(0, 1.9, 0), M.Leather, Color3.fromRGB(60, 70, 100))
	deco("ExamBack", Vector3.new(2.2, 2.8, 0.5), cf * CFrame.new(0, 3.5, 1.0) * CFrame.Angles(math.rad(-10), 0, 0), M.Leather, Color3.fromRGB(60, 70, 100))
	deco("ExamBase", Vector3.new(1.6, 1.6, 1.6), cf * CFrame.new(0, 0.8, 0.2), M.Metal, Color3.fromRGB(220, 220, 224))
	for _, sx in { -1.25, 1.25 } do
		deco("ExamArm", Vector3.new(0.35, 0.3, 1.8), cf * CFrame.new(sx, 2.5, 0.1), M.Leather, Color3.fromRGB(60, 70, 100))
	end
	deco("PhoropterPost", Vector3.new(0.3, 5.8, 0.3), cf * CFrame.new(1.9, 2.9, 0.6), M.Metal, Color3.fromRGB(220, 220, 224))
	deco("PhoropterArm", Vector3.new(1.9, 0.2, 0.2), cf * CFrame.new(1.0, 5.6, 0.2), M.Metal, Color3.fromRGB(220, 220, 224))
	deco("Phoropter", Vector3.new(1.6, 0.8, 0.5), cf * CFrame.new(0, 5.0, -0.2), M.SmoothPlastic, Color3.fromRGB(40, 42, 48), { Variant = false })
	for _, sx in { -0.4, 0.4 } do
		deco("PhoropterEye", Vector3.new(0.1, 0.4, 0.4), cf * CFrame.new(sx, 5.0, -0.48) * CFrame.Angles(0, math.rad(90), 0), M.SmoothPlastic, Color3.fromRGB(20, 20, 22), { Shape = CYL, Variant = false })
	end
	local top = displayTable(cf * CFrame.new(-2.6, 0, -0.5), 1.8, 1.6, 2.9, Color3.fromRGB(240, 240, 240))
	deco("Lensmeter", Vector3.new(0.8, 1.2, 0.8), top * CFrame.new(0, 0.6, 0), M.SmoothPlastic, Color3.fromRGB(230, 232, 236), { Variant = false })
end

-- Mesa de comedor con sillas (a lo largo de X).
local function diningSet(cf: CFrame, w: number, chairColor: Color3, wood: Color3)
	local top = displayTable(cf, w, 3.2, 3.0, wood)
	local n = math.max(1, math.floor(w / 2.4))
	for k = 0, n - 1 do
		local x = -w / 2 + w / n * (k + 0.5)
		chair(cf * CFrame.new(x, 0, -2.3) * CFrame.Angles(0, math.pi, 0), chairColor)
		chair(cf * CFrame.new(x, 0, 2.3), chairColor)
		deco("Placemat", Vector3.new(1.3, 0.02, 0.9), top * CFrame.new(x, 0.01, -0.9), M.Fabric, Color3.fromRGB(220, 210, 190), { CastShadow = false })
		deco("Placemat", Vector3.new(1.3, 0.02, 0.9), top * CFrame.new(x, 0.01, 0.9), M.Fabric, Color3.fromRGB(220, 210, 190), { CastShadow = false })
	end
	deco("Vase", Vector3.new(0.9, 0.5, 0.5), top * CFrame.new(0, 0.45, 0) * UPRIGHT, M.Glass, Color3.fromRGB(180, 210, 200), { Shape = CYL, Transparency = 0.3 })
end

-- Armario ropero de exposicion (frente -Z).
local function wardrobe(cf: CFrame, w: number, color: Color3)
	box("Wardrobe", Vector3.new(w, 8, 2.4), cf * CFrame.new(0, 4, 0), M.Wood, color)
	local doors = math.max(2, math.floor(w / 2))
	for k = 1, doors - 1 do
		deco("DoorGap", Vector3.new(0.05, 7.6, 0.04), cf * CFrame.new(-w / 2 + k * w / doors, 4, -1.21), M.SmoothPlastic, color:Lerp(BLACK, 0.5))
	end
	for k = 0, doors - 1 do
		local x = -w / 2 + (k + 0.5) * w / doors + (if k % 2 == 0 then 0.6 else -0.6)
		deco("WardrobeHandle", Vector3.new(0.08, 1.2, 0.1), cf * CFrame.new(x, 4.2, -1.25), M.Metal, STEEL)
	end
	deco("WardrobePlinth", Vector3.new(w, 0.3, 2.3), cf * CFrame.new(0, 0.15, 0.05), M.SmoothPlastic, BLACK, { Variant = false })
end

-- Cajones de vinilos (discos de canto) con cartel.
local function vinylBins(cf: CFrame, len: number)
	box("VinylCrate", Vector3.new(len, 2.6, 2.4), cf * CFrame.new(0, 1.3, 0), M.Wood, Color3.fromRGB(120, 86, 56))
	local n = math.floor((len - 0.6) / 0.16)
	for k = 0, n - 1 do
		local x = -len / 2 + 0.4 + k * 0.16
		deco("Record", Vector3.new(0.05, 2.1, 2.1), cf * CFrame.new(x, 3.0, 0) * CFrame.Angles(0, 0, math.rad(-12)), M.SmoothPlastic, vary(BRIGHT[(k // 3) % #BRIGHT + 1], 0.15), {
			CastShadow = false,
			Variant = false,
		})
	end
	local header = deco("VinylSign", Vector3.new(2.6, 0.9, 0.1), cf * CFrame.new(0, 4.9, -1.0), M.SmoothPlastic, Color3.fromRGB(20, 20, 22), { Variant = false })
	printed(header, "VINILOS", Color3.fromRGB(255, 220, 90), Enum.Font.Bangers, Enum.NormalId.Front)
	deco("VinylSignPost", Vector3.new(0.1, 1.2, 0.1), cf * CFrame.new(0, 3.9, -1.0), M.Metal, BLACK)
end

-- Auriculares (diadema + dos copas) colgados de un gancho; cf = gancho.
local function headphones(cf: CFrame, color: Color3)
	deco("HeadphoneBand", Vector3.new(0.9, 0.12, 0.2), cf * CFrame.new(0, -0.1, -0.3), M.SmoothPlastic, color, { CastShadow = false, Variant = false })
	for _, sx in { -0.45, 0.45 } do
		deco("HeadphoneCup", Vector3.new(0.22, 0.6, 0.6), cf * CFrame.new(sx, -0.6, -0.3) * CFrame.Angles(0, 0, 0), M.SmoothPlastic, color, { Shape = CYL, CastShadow = false, Variant = false })
	end
end

-- Puesto de escucha: balda con tabletas y auriculares colgados (cf = pie de la pared).
local function listeningStation(cf: CFrame, accent: Color3)
	box("ListenShelf", Vector3.new(7, 0.25, 1.5), cf * CFrame.new(0, 3.6, -0.75), M.Wood, Color3.fromRGB(60, 44, 34))
	for k = -1, 1 do
		local tablet = deco("ListenTablet", Vector3.new(1.3, 0.9, 0.06), cf * CFrame.new(k * 2.2, 4.35, -0.5) * CFrame.Angles(math.rad(15), 0, 0), M.SmoothPlastic, BLACK, { Variant = false })
		glowScreen(tablet, Enum.NormalId.Front, accent, Color3.fromRGB(20, 20, 30), "▶")
		headphones(cf * CFrame.new(k * 2.2, 6.2, 0), if k == 0 then accent else Color3.fromRGB(30, 30, 34))
	end
	local header = deco("ListenSign", Vector3.new(6, 0.9, 0.1), cf * CFrame.new(0, 7.9, -0.1), M.SmoothPlastic, Color3.fromRGB(20, 20, 22), { Variant = false })
	printed(header, "ESCUCHA ANTES DE COMPRAR", Color3.new(1, 1, 1), Enum.Font.GothamBold, Enum.NormalId.Front)
end

-- Bicicleta estatica (frente -Z).
local function exerciseBike(cf: CFrame, accent: Color3)
	box("SpinFrame", Vector3.new(0.5, 0.4, 4), cf * CFrame.new(0, 0.2, 0), M.Metal, Color3.fromRGB(40, 40, 44))
	deco("SpinFlywheel", Vector3.new(0.3, 1.8, 1.8), cf * CFrame.new(0, 1.3, -1.2), M.Metal, STEEL, { Shape = CYL })
	deco("SpinGuard", Vector3.new(0.4, 1.4, 1.2), cf * CFrame.new(0, 1.5, -0.8), M.SmoothPlastic, accent, { Variant = false })
	deco("SpinSeatPost", Vector3.new(0.25, 2.6, 0.25), cf * CFrame.new(0, 1.6, 0.9) * CFrame.Angles(math.rad(-12), 0, 0), M.Metal, Color3.fromRGB(40, 40, 44))
	deco("SpinSaddle", Vector3.new(0.7, 0.2, 1.1), cf * CFrame.new(0, 3.0, 1.15), M.Leather, BLACK)
	deco("SpinStem", Vector3.new(0.25, 2.8, 0.25), cf * CFrame.new(0, 2.2, -0.3) * CFrame.Angles(math.rad(14), 0, 0), M.Metal, Color3.fromRGB(40, 40, 44))
	deco("SpinBars", Vector3.new(1.6, 0.16, 0.6), cf * CFrame.new(0, 3.55, -0.65), M.Rubber, BLACK)
	local console = deco("SpinConsole", Vector3.new(0.8, 0.5, 0.1), cf * CFrame.new(0, 3.85, -0.6) * CFrame.Angles(math.rad(-30), 0, 0), M.SmoothPlastic, BLACK, { Variant = false })
	glowScreen(console, Enum.NormalId.Back, Color3.fromRGB(40, 60, 90), Color3.fromRGB(10, 20, 30), "120")
	for _, sz in { -1.8, 1.8 } do
		deco("SpinFoot", Vector3.new(2, 0.2, 0.4), cf * CFrame.new(0, 0.1, sz), M.Metal, Color3.fromRGB(40, 40, 44))
	end
end

-- Jaula de sentadillas con barra y discos (frente -Z).
local function powerRack(cf: CFrame, accent: Color3)
	for _, sx in { -2, 2 } do
		for _, sz in { -1.6, 1.6 } do
			box("RackPost", Vector3.new(0.3, 7.5, 0.3), cf * CFrame.new(sx, 3.75, sz), M.Metal, Color3.fromRGB(35, 35, 38))
		end
		deco("RackTop", Vector3.new(0.3, 0.3, 3.5), cf * CFrame.new(sx, 7.4, 0), M.Metal, Color3.fromRGB(35, 35, 38))
		deco("RackFoot", Vector3.new(0.4, 0.2, 3.8), cf * CFrame.new(sx, 0.1, 0), M.Metal, Color3.fromRGB(35, 35, 38))
	end
	deco("PullupBar", Vector3.new(4.3, 0.16, 0.16), cf * CFrame.new(0, 7.4, -1.6), M.Metal, STEEL)
	deco("RackBarbell", Vector3.new(7, 0.18, 0.18), cf * CFrame.new(0, 4.6, -1.2), M.Metal, STEEL)
	for _, sx in { -3.0, 3.0 } do
		deco("RackPlate", Vector3.new(0.3, 2.2, 2.2), cf * CFrame.new(sx, 4.6, -1.2), M.Rubber, BLACK, { Shape = CYL })
		deco("RackPlateRim", Vector3.new(0.32, 0.9, 0.9), cf * CFrame.new(sx, 4.6, -1.2), M.Rubber, accent, { Shape = CYL })
	end
	for _, sx in { -2, 2 } do
		deco("JHook", Vector3.new(0.2, 0.3, 0.5), cf * CFrame.new(sx, 4.4, -1.6), M.Metal, accent)
	end
end

-- Fila de pesas rusas en el suelo.
local function kettlebells(cf: CFrame, count: number, accent: Color3)
	for k = 0, count - 1 do
		local s = 0.8 + k * 0.1
		local p = cf * CFrame.new(-count / 2 * 1.3 + k * 1.3, s / 2, 0)
		deco("Kettlebell", Vector3.new(s, s, s), p, M.Metal, Color3.fromRGB(30, 30, 33), { Shape = BALL })
		deco("KettleHandle", Vector3.new(s * 0.7, 0.12, 0.12), p * CFrame.new(0, s * 0.55, 0), M.Metal, Color3.fromRGB(30, 30, 33))
		deco("KettleTag", Vector3.new(0.3, 0.2, 0.04), p * CFrame.new(0, 0, -s * 0.5), M.SmoothPlastic, accent, { CastShadow = false, Variant = false })
	end
end

-- Fuente de agua con garrafa.
local function waterCooler(cf: CFrame)
	box("CoolerBody", Vector3.new(1.4, 3.4, 1.3), cf * CFrame.new(0, 1.7, 0), M.SmoothPlastic, Color3.fromRGB(235, 235, 232), { Variant = false })
	deco("CoolerTap", Vector3.new(0.15, 0.25, 0.2), cf * CFrame.new(-0.3, 2.8, -0.7), M.SmoothPlastic, Color3.fromRGB(50, 110, 220))
	deco("CoolerTap", Vector3.new(0.15, 0.25, 0.2), cf * CFrame.new(0.3, 2.8, -0.7), M.SmoothPlastic, Color3.fromRGB(220, 50, 50))
	deco("CoolerBottle", Vector3.new(1.8, 1.2, 1.2), cf * CFrame.new(0, 4.3, 0) * UPRIGHT, M.Glass, Color3.fromRGB(120, 180, 230), { Shape = CYL, Transparency = 0.35 })
	deco("CoolerCups", Vector3.new(0.9, 0.3, 0.3), cf * CFrame.new(0.85, 2.7, 0) * UPRIGHT, M.SmoothPlastic, Color3.fromRGB(250, 250, 250), { Shape = CYL })
end

-- Pizarra de caballete (A) con texto por las dos caras. cf en el suelo.
local function aFrameBoard(cf: CFrame, text: string)
	for _, side in { -1, 1 } do
		local leaf = deco("AFrame", Vector3.new(2.2, 3.4, 0.12), cf * CFrame.new(0, 1.65, side * 0.5) * CFrame.Angles(math.rad(-side * 14), 0, 0), M.Wood, Color3.fromRGB(120, 86, 56))
		local board = deco("Chalkboard", Vector3.new(1.9, 2.8, 0.04), cf * CFrame.new(0, 1.7, side * 0.58) * CFrame.Angles(math.rad(-side * 14), 0, 0), M.Slate, Color3.fromRGB(32, 36, 34))
		printed(board, text, Color3.fromRGB(240, 240, 232), Enum.Font.PatrickHand, if side < 0 then Enum.NormalId.Front else Enum.NormalId.Back)
		leaf.CastShadow = true
	end
end

-- Puesto de fruta: cajas inclinadas con piezas de fruta (bolas).
local function produceStand(cf: CFrame)
	box("ProduceStand", Vector3.new(6.4, 2.4, 3.2), cf * CFrame.new(0, 1.2, 0), M.Wood, Color3.fromRGB(150, 110, 70))
	local fruits = {
		{ Color3.fromRGB(200, 30, 30), 0.55 }, -- manzana
		{ Color3.fromRGB(245, 150, 30), 0.6 }, -- naranja
		{ Color3.fromRGB(240, 220, 60), 0.5 }, -- limon
		{ Color3.fromRGB(90, 160, 50), 0.6 }, -- manzana verde
		{ Color3.fromRGB(110, 40, 90), 0.45 }, -- ciruela
		{ Color3.fromRGB(240, 200, 60), 0.5 }, -- pera
	}
	for c = 0, 5 do
		local col, row = c % 3, c // 3
		local crate = cf * CFrame.new(-2.1 + col * 2.1, 2.55, -0.75 + row * 1.5) * CFrame.Angles(math.rad(-10), 0, 0)
		deco("Crate", Vector3.new(2.0, 0.5, 1.4), crate, M.WoodPlanks, Color3.fromRGB(190, 150, 100))
		local fruit = fruits[c + 1]
		for k = 0, 8 do
			deco("Fruit", Vector3.new(fruit[2], fruit[2], fruit[2]), crate * CFrame.new(-0.65 + (k % 3) * 0.65, 0.4 + (k // 3 % 2) * 0.08, -0.4 + (k // 3) * 0.4), M.SmoothPlastic, vary(fruit[1], 0.06), {
				Shape = BALL,
				CastShadow = false,
				Variant = false,
			})
		end
		local price = deco("PriceTag", Vector3.new(0.9, 0.5, 0.04), crate * CFrame.new(0, 0.1, -0.72), M.SmoothPlastic, Color3.fromRGB(250, 250, 245), { CastShadow = false, Variant = false })
		printed(price, string.format("%d,%02d €/kg", 1 + c % 3, 19 + c * 10), BLACK, Enum.Font.GothamBold, Enum.NormalId.Front)
	end
	local header = deco("ProduceSign", Vector3.new(6, 1, 0.12), cf * CFrame.new(0, 4.6, 1.5), M.SmoothPlastic, Color3.fromRGB(40, 110, 50), { Variant = false })
	printed(header, "FRUTA FRESCA", Color3.new(1, 1, 1), Enum.Font.GothamBlack, Enum.NormalId.Front)
	for _, sx in { -2.9, 2.9 } do
		deco("ProduceSignPost", Vector3.new(0.12, 2.2, 0.12), cf * CFrame.new(sx, 3.5, 1.5), M.Metal, BLACK)
	end
end

-- Columna de cestas de la compra.
local function basketStack(cf: CFrame, color: Color3)
	for k = 0, 6 do
		deco("Basket", Vector3.new(1.8, 0.28, 1.3), cf * CFrame.new(0, 0.2 + k * 0.28, 0) * CFrame.Angles(0, math.rad((k % 2) * 3), 0), M.SmoothPlastic, color, { Variant = false })
	end
	deco("BasketHandle", Vector3.new(1.6, 0.6, 0.08), cf * CFrame.new(0, 2.4, 0), M.SmoothPlastic, BLACK, { Variant = false })
end

-- Carrito auxiliar de peluqueria con cajones y utensilios.
local function toolTrolley(cf: CFrame)
	box("Trolley", Vector3.new(1.3, 3.0, 1.3), cf * CFrame.new(0, 1.7, 0), M.SmoothPlastic, Color3.fromRGB(30, 30, 34), { Variant = false })
	for k = 0, 3 do
		deco("TrolleyDrawer", Vector3.new(1.1, 0.04, 0.04), cf * CFrame.new(0, 0.7 + k * 0.7, -0.67), M.Metal, STEEL)
	end
	deco("HairDryer", Vector3.new(0.9, 0.35, 0.35), cf * CFrame.new(0, 3.4, 0), M.SmoothPlastic, Color3.fromRGB(230, 230, 235), { Shape = CYL, Variant = false })
	deco("Brush", Vector3.new(0.12, 0.12, 0.9), cf * CFrame.new(0.4, 3.26, 0), M.SmoothPlastic, BLACK)
	deco("SprayBottle", Vector3.new(0.6, 0.3, 0.3), cf * CFrame.new(-0.4, 3.5, 0.3) * UPRIGHT, M.SmoothPlastic, Color3.fromRGB(200, 120, 200), { Shape = CYL, Variant = false })
	for _, sx in { -0.5, 0.5 } do
		for _, sz in { -0.5, 0.5 } do
			deco("Caster", Vector3.new(0.2, 0.3, 0.3), cf * CFrame.new(sx, 0.15, sz), M.Rubber, BLACK, { Shape = CYL })
		end
	end
end

-- Secador de casco con su sillon (frente -Z).
local function hoodDryer(cf: CFrame, color: Color3)
	box("DryerSeat", Vector3.new(2.4, 1.6, 2.2), cf * CFrame.new(0, 0.8, 0), M.Leather, color)
	deco("DryerBack", Vector3.new(2.4, 2.6, 0.5), cf * CFrame.new(0, 2.6, 0.9), M.Leather, color)
	deco("DryerPost", Vector3.new(0.2, 5.6, 0.2), cf * CFrame.new(0, 2.8, 1.5), M.Metal, STEEL)
	deco("DryerArm", Vector3.new(0.2, 0.2, 1.2), cf * CFrame.new(0, 5.4, 1.0), M.Metal, STEEL)
	deco("DryerHood", Vector3.new(1.9, 1.9, 1.9), cf * CFrame.new(0, 4.8, 0.4), M.SmoothPlastic, Color3.fromRGB(235, 235, 240), { Shape = BALL, Variant = false })
	deco("DryerVisor", Vector3.new(1.7, 0.6, 0.06), cf * CFrame.new(0, 4.3, -0.5), M.SmoothPlastic, Color3.fromRGB(80, 80, 90), { Transparency = 0.4, Variant = false })
end

-- Silla gaming (frente -Z).
local function gamingChair(cf: CFrame, accent: Color3)
	box("GChairSeat", Vector3.new(2, 0.5, 2), cf * CFrame.new(0, 2, 0), M.Leather, BLACK)
	deco("GChairBack", Vector3.new(2, 3.6, 0.5), cf * CFrame.new(0, 4.0, 0.9) * CFrame.Angles(math.rad(-8), 0, 0), M.Leather, BLACK)
	deco("GChairStripe", Vector3.new(0.5, 3.5, 0.52), cf * CFrame.new(0, 4.0, 0.89) * CFrame.Angles(math.rad(-8), 0, 0), M.Leather, accent)
	deco("GChairHead", Vector3.new(1.2, 0.6, 0.4), cf * CFrame.new(0, 5.6, 0.95), M.Fabric, accent)
	for _, sx in { -1.05, 1.05 } do
		deco("GChairArm", Vector3.new(0.3, 0.2, 1.4), cf * CFrame.new(sx, 3.0, 0.1), M.Plastic, BLACK)
		deco("GChairArmPost", Vector3.new(0.2, 0.8, 0.2), cf * CFrame.new(sx, 2.5, 0.3), M.Plastic, BLACK)
	end
	deco("GChairGas", Vector3.new(1.4, 0.3, 0.3), cf * CFrame.new(0, 1.1, 0) * UPRIGHT, M.Metal, STEEL, { Shape = CYL })
	for k = 0, 4 do
		local a = math.rad(k * 72)
		deco("GChairLeg", Vector3.new(0.2, 0.15, 1.3), cf * CFrame.new(math.cos(a) * 0.65, 0.35, math.sin(a) * 0.65) * CFrame.Angles(0, -a + math.rad(90), 0), M.Plastic, BLACK)
	end
end

-- Mesita de revistas (sala de espera).
local function magazineTable(cf: CFrame)
	local top = displayTable(cf, 2.6, 1.6, 1.6, Color3.fromRGB(240, 238, 235))
	for k = 0, 2 do
		deco("Magazine", Vector3.new(0.9, 0.04, 1.2), top * CFrame.new(-0.6 + k * 0.6, 0.03 + k * 0.04, 0) * CFrame.Angles(0, math.rad(k * 17 - 10), 0), M.SmoothPlastic, BRIGHT[k + 4], { CastShadow = false, Variant = false })
	end
end

-- Tensiometro de farmacia: maquina con manguito y asiento.
local function bloodPressureKiosk(cf: CFrame, accent: Color3)
	box("BPMachine", Vector3.new(2.2, 4.4, 1.6), cf * CFrame.new(0, 2.2, 0.6), M.SmoothPlastic, Color3.fromRGB(240, 240, 238), { Variant = false })
	deco("BPCuff", Vector3.new(0.9, 0.9, 1.0), cf * CFrame.new(0.4, 2.9, -0.4) * CFrame.Angles(0, math.rad(90), 0), M.Fabric, Color3.fromRGB(40, 60, 110), { Shape = CYL })
	local screen = deco("BPScreen", Vector3.new(1.4, 0.9, 0.05), cf * CFrame.new(0, 3.8, -0.22), M.SmoothPlastic, BLACK, { Variant = false })
	glowScreen(screen, Enum.NormalId.Front, accent, Color3.fromRGB(10, 40, 20), "120/80")
	local header = deco("BPSign", Vector3.new(2.2, 0.6, 0.05), cf * CFrame.new(0, 4.7, -0.22), M.SmoothPlastic, accent, { Variant = false })
	printed(header, "TENSIÓMETRO", Color3.new(1, 1, 1), Enum.Font.GothamBold, Enum.NormalId.Front)
	chair(cf * CFrame.new(-1.8, 0, -0.6) * CFrame.Angles(0, math.rad(-90), 0), Color3.fromRGB(80, 160, 120))
end

-- Mesa de atencion con dos sillas y espejo de sobremesa (joyeria).
local function consultDesk(cf: CFrame)
	local top = displayTable(cf, 5, 2.6, 3.0, Color3.fromRGB(45, 36, 34))
	deco("DeskVelvet", Vector3.new(2.2, 0.03, 1.4), top * CFrame.new(0, 0.02, 0), M.Fabric, Color3.fromRGB(28, 26, 40), { CastShadow = false })
	deco("DeskMirror", Vector3.new(0.9, 1.3, 0.06), top * CFrame.new(1.7, 0.75, 0.6) * CFrame.Angles(math.rad(10), math.rad(20), 0), M.SmoothPlastic, Color3.fromRGB(170, 182, 190), { Reflectance = 0.3, Variant = false })
	deco("DeskLamp", Vector3.new(0.12, 1.3, 0.12), top * CFrame.new(-2, 0.65, 0.8), M.Metal, Color3.fromRGB(200, 170, 100))
	for _, sx in { -1.2, 1.2 } do
		chair(cf * CFrame.new(sx, 0, -2.4) * CFrame.Angles(0, math.pi, 0), Color3.fromRGB(110, 30, 45))
	end
	chair(cf * CFrame.new(0, 0, 2.4), Color3.fromRGB(40, 40, 44))
end

-- Rueda de reloj de pared con hora distinta en cada uno (relojeria).
local function clockWall(cf: CFrame)
	for k = 0, 5 do
		wallClock(cf * CFrame.new(-3 + (k % 3) * 3, (k // 3) * 2.4, 0), 1.6 + (k % 2) * 0.4)
	end
end

FITOUT = {}

function FITOUT.Clothes(base: CFrame, def)
	wallBay(base, -1, 14, 10, "Hang", pick(4, 1), "NUEVA TEMPORADA")
	wallBay(base, -1, 32.5, 8, "Hang", pick(4, 3), "BÁSICOS")
	wallBay(base, 1, 13.5, 11, "Cubby", pick(5, 4), "DENIM · PUNTO")
	nestingTables(base, 0, 13, pick(3, 2))
	spinnerRack(F(base, 5, 26), { def.Accent, Color3.fromRGB(230, 200, 120), Color3.fromRGB(40, 40, 44) })
	hangingSign(F(base, 17, 30) * CFrame.new(0, 11, 0), 6, 1.2, "PROBADORES", Color3.fromRGB(28, 28, 32), Color3.new(1, 1, 1), Enum.Font.GothamBold, 4.4)
	stanchions(base, -6.5, 34, 37.5, def.Accent:Lerp(DARK, 0.3))
end

function FITOUT.Tech(base: CFrame, def)
	local gaming = def.Kind == "Gamer"
	deviceTable(base, 0, 23, def.Accent, gaming)
	if not gaming then
		wallBay(base, 1, 14.5, 12, "Peg", { Color3.fromRGB(30, 30, 34), Color3.fromRGB(235, 235, 238), def.Accent, Color3.fromRGB(60, 120, 200) }, "ACCESORIOS")
	else
		for i, x in { -12, -7.5 } do
			gamingChair(F(base, x, 26) * CFrame.Angles(0, math.rad(i * 12 - 18), 0), if i == 1 then def.Accent else Color3.fromRGB(230, 40, 60))
		end
		-- Tiras RGB bajo el falso techo
		for _, side in { -1, 1 } do
			neonStrip(Vector3.new(0.12, 0.12, 46), L(base, side * 20, STORE_H - 1.25, 25), def.Accent, def.Name)
		end
	end
	hangingSign(F(base, -12, 15) * CFrame.new(0, 11.2, 0), 6, 1.2, if gaming then "PC GAMING" else "PORTÁTILES", Color3.fromRGB(20, 20, 24), def.Accent, Enum.Font.GothamBold, 4.2)
	hangingSign(F(base, 12, 15) * CFrame.new(0, 11.2, 0), 6, 1.2, if gaming then "CONSOLAS" else "TABLETS", Color3.fromRGB(20, 20, 24), def.Accent, Enum.Font.GothamBold, 4.2)
	stanchions(base, -5, 33, 37, def.Accent:Lerp(DARK, 0.3))
end
FITOUT.Gamer = FITOUT.Tech

function FITOUT.Toys(base: CFrame, def)
	wallBay(base, 1, 18, 10, "Boxes", BRIGHT, "JUEGOS DE MESA")
	kidsTable(L(base, 0, 0, 12))
	rideOnCar(F(base, -3, 21) * CFrame.Angles(0, math.rad(25), 0), Color3.fromRGB(220, 40, 45))
	balloons(L(base, -9, 0, 7))
	hangingSign(F(base, -12, 21) * CFrame.new(0, 11.2, 0), 6, 1.2, "PELUCHES", Color3.fromRGB(255, 205, 50), Color3.fromRGB(40, 30, 20), Enum.Font.FredokaOne, 4.2)
	hangingSign(F(base, 12, 28) * CFrame.new(0, 11.2, 0), 6, 1.2, "CONSTRUCCIÓN", Color3.fromRGB(80, 170, 230), Color3.new(1, 1, 1), Enum.Font.FredokaOne, 4.2)
	stanchions(base, -5, 33, 37, def.Accent)
end

function FITOUT.Sports(base: CFrame, def)
	local cycling = string.find(def.Name, "Bici") ~= nil
	wallBay(base, -1, 14, 10, "Shoes", pick(4, 2), if cycling then "CASCOS · ZAPATILLAS" else "RUNNING")
	-- Bicis colgadas de la pared derecha (y en el suelo si es la tienda de bicis)
	for i, d in { 22, 28 } do
		local cf = sideWallCF(base, 1, d, 6.2, 0.6)
		bike(cf, if i == 1 then def.Accent else Color3.fromRGB(40, 110, 200))
		deco("BikeHook", Vector3.new(0.12, 0.12, 0.6), sideWallCF(base, 1, d, 7.4, 0.3), M.Metal, STEEL)
	end
	if cycling then
		for i, x in { -4, 2 } do
			bike(L(base, x, 1.25, 21) * CFrame.Angles(0, math.rad(90 + i * 10), 0), BRIGHT[i + 2])
			deco("BikeStand", Vector3.new(0.5, 0.4, 1.2), L(base, x, 0.2, 21), M.Metal, Color3.fromRGB(40, 40, 44))
		end
	else
		yogaBin(L(base, -2, 0, 18))
	end
	for i, d in { 30.5, 34.5 } do
		framedPrint(sideWallCF(base, -1, d, 6, 0), 2.8, 3.4, BRIGHT[i + 1], BRIGHT[i + 1]:Lerp(BLACK, 0.5), tostring(i * 7 + 3))
	end
	hangingSign(F(base, 12, 12) * CFrame.new(0, 11.2, 0), 6, 1.2, if cycling then "TALLER" else "BALONES", Color3.fromRGB(20, 20, 24), def.Accent, Enum.Font.Oswald, 4.2)
	stanchions(base, -5, 33, 37, def.Accent:Lerp(DARK, 0.3))
end

function FITOUT.Books(base: CFrame, def)
	wallBay(base, -1, 14, 10, "Books", PALETTE, "NOVEDADES")
	wallBay(base, -1, 32.5, 8, "Books", PALETTE, "INFANTIL")
	lowBookcase(L(base, 0, 0, 14), 8)
	floorLamp(L(base, -18.5, 0, 30), def.Name)
	hangingSign(F(base, 16, 18) * CFrame.new(0, 11.2, 0), 5, 1.1, "NOVELA", Color3.fromRGB(115, 40, 45), Color3.fromRGB(240, 220, 170), Enum.Font.Merriweather, 4.3)
	hangingSign(F(base, 16, 32) * CFrame.new(0, 11.2, 0), 5, 1.1, "ENSAYO", Color3.fromRGB(115, 40, 45), Color3.fromRGB(240, 220, 170), Enum.Font.Merriweather, 4.3)
	stanchions(base, -5, 33, 37, Color3.fromRGB(115, 40, 45))
end

function FITOUT.Shoes(base: CFrame, def)
	wallBay(base, -1, 14, 10, "Shoes", pick(5, 0), "MUJER")
	wallBay(base, -1, 32.5, 8, "Shoes", pick(5, 3), "NIÑOS")
	for _, x in { -10, 10 } do
		floorMirror(F(base, x, 23.2))
		deco("FootMeasure", Vector3.new(1, 0.12, 1.8), L(base, x + 2.4, 0.06, 22), M.Metal, Color3.fromRGB(60, 62, 70))
	end
	hangingSign(F(base, 17, 20) * CFrame.new(0, 11.2, 0), 5, 1.1, "HOMBRE", Color3.fromRGB(20, 20, 24), def.Accent, Enum.Font.GothamBlack, 4.3)
	stanchions(base, -5, 33, 37, def.Accent:Lerp(DARK, 0.3))
end

function FITOUT.Perfume(base: CFrame, def)
	local glassColors = { Color3.fromRGB(240, 200, 120), Color3.fromRGB(200, 160, 230), Color3.fromRGB(150, 200, 240), Color3.fromRGB(240, 170, 190), Color3.fromRGB(230, 230, 235) }
	wallBay(base, -1, 14, 10, "Bottles", glassColors, "FRAGANCIAS", def.Name)
	vanityStation(sideWallCF(base, 1, 32, 0), def.Name)
	hangingSign(F(base, 0, 20) * CFrame.new(0, 11.4, 0), 7, 1.2, "MAQUILLAJE · CUIDADO", Color3.fromRGB(20, 18, 24), def.Accent, Enum.Font.Fondamento, 4.0)
end

function FITOUT.Optics(base: CFrame, def)
	local frameColors = { Color3.fromRGB(25, 25, 28), Color3.fromRGB(110, 70, 40), Color3.fromRGB(200, 170, 110), Color3.fromRGB(150, 30, 40), Color3.fromRGB(40, 70, 130) }
	wallBay(base, -1, 14, 10, "Frames", frameColors, "GRADUADAS", def.Name)
	wallBay(base, -1, 32.5, 8, "Frames", frameColors, "GAFAS DE SOL", def.Name)
	examStation(L(base, 12, 0, 28) * CFrame.Angles(0, math.rad(-90), 0))
	for _, x in { -12, 12 } do
		deco("CounterMirror", Vector3.new(0.8, 1.2, 0.06), L(base, x + 2.2, 4.85, 15.2) * OUT * CFrame.Angles(math.rad(-10), 0, 0), M.SmoothPlastic, Color3.fromRGB(170, 182, 190), { Reflectance = 0.3, Variant = false })
	end
end

function FITOUT.Home(base: CFrame, def)
	wallBay(base, -1, 14, 10, "Shelves", { Color3.fromRGB(245, 245, 242), Color3.fromRGB(200, 220, 215), Color3.fromRGB(230, 205, 180), Color3.fromRGB(150, 175, 200) }, "COCINA · MESA")
	diningSet(L(base, -8, 0, 28), 5, Color3.fromRGB(200, 190, 170), Color3.fromRGB(170, 130, 90))
	for k = -1, 1 do
		framedPrint(sideWallCF(base, 1, 28 + k * 3.2, 7.6, 0), 2.4, 3, Color3.fromRGB(90, 205, 195):Lerp(BRIGHT[k + 3], 0.4), Color3.fromRGB(240, 235, 225), nil)
	end
	pottedPlant(L(base, -20, 0, 9))
end

function FITOUT.Furniture(base: CFrame, def)
	diningSet(L(base, 12, 0, 22), 6, Color3.fromRGB(60, 60, 64), Color3.fromRGB(190, 150, 100))
	wardrobe(sideWallCF(base, -1, 13, 0, 1.3), 6, Color3.fromRGB(225, 215, 198))
	for k = -1, 1, 2 do
		framedPrint(sideWallCF(base, -1, 31 + k * 2, 6.2, 0), 3, 3.6, Color3.fromRGB(200, 150, 100), Color3.fromRGB(60, 50, 40), nil)
	end
	pottedPlant(L(base, 4, 0, 8))
end

function FITOUT.Music(base: CFrame, def)
	vinylBins(F(base, -3, 26), 6)
	listeningStation(sideWallCF(base, -1, 13, 0), def.Accent)
	local posters = { { "ROCK", Color3.fromRGB(200, 40, 40) }, { "JAZZ", Color3.fromRGB(40, 90, 170) }, { "POP", Color3.fromRGB(230, 90, 170) } }
	for k, p in posters do
		framedPrint(sideWallCF(base, -1, 28 + k * 2.8, 6.4, 0), 2.2, 3.2, p[2], p[2]:Lerp(BLACK, 0.6), p[1])
	end
	for k = 0, 1 do
		box("Amp", Vector3.new(3, 2.4 - k * 0.6, 1.6), L(base, 16, (2.4 - k * 0.6) / 2 + k * 2.4, 36) * OUT, M.Leather, Color3.fromRGB(25, 25, 28))
		deco("AmpGrille", Vector3.new(2.6, 1.6 - k * 0.6, 0.05), L(base, 16, (2.4 - k * 0.6) / 2 + k * 2.4, 35.18) * OUT, M.Fabric, Color3.fromRGB(70, 66, 60))
	end
	stanchions(base, -5, 33, 37, def.Accent:Lerp(DARK, 0.3))
end

function FITOUT.Jewelry(base: CFrame, def)
	local metals = { Color3.fromRGB(230, 190, 90), Color3.fromRGB(220, 222, 228), Color3.fromRGB(200, 60, 80), Color3.fromRGB(80, 150, 220) }
	wallBay(base, -1, 14, 10, "Cases", metals, if string.find(def.Name, "Reloj") then "ALTA RELOJERÍA" else "ALTA JOYERÍA", def.Name, 7.6)
	consultDesk(F(base, 2, 34))
	if string.find(def.Name, "Reloj") then
		clockWall(sideWallCF(base, -1, 32.5, 6.4, 0))
	end
end

function FITOUT.Pharmacy(base: CFrame, def)
	wallBay(base, -1, 14, 10, "Shelves", { Color3.fromRGB(245, 245, 248), Color3.fromRGB(90, 150, 220), def.Accent, Color3.fromRGB(240, 240, 245) }, "DERMOCOSMÉTICA")
	bloodPressureKiosk(L(base, 18, 0, 22) * FACE_NEG_X, def.Accent)
	-- Cruz verde de farmacia colgada en el escaparate
	local crossCF = F(base, -15, 1.6) * CFrame.new(0, 9.2, 0)
	neonStrip(Vector3.new(2.6, 0.8, 0.25), crossCF, def.Accent, def.Name, 0.5)
	neonStrip(Vector3.new(0.8, 2.6, 0.25), crossCF, def.Accent, def.Name)
	for _, sx in { -0.9, 0.9 } do
		deco("CrossCable", Vector3.new(0.04, 5.4, 0.04), crossCF * CFrame.new(sx, 4.0, 0), M.Metal, STEEL, { CastShadow = false })
	end
end

function FITOUT.Gym(base: CFrame, def)
	for _, x in { -15, -10, -5 } do
		exerciseBike(F(base, x, 28), def.Accent)
	end
	powerRack(F(base, 17, 22), def.Accent)
	kettlebells(F(base, 12, 41), 6, def.Accent)
	waterCooler(L(base, -21, 0, 33) * FACE_POS_X)
	hangingSign(F(base, -10, 28) * CFrame.new(0, 11.4, 0), 6, 1.2, "CICLO INDOOR", Color3.fromRGB(20, 20, 24), def.Accent, Enum.Font.Oswald, 4.0)
end

function FITOUT.Cafe(base: CFrame, def)
	-- Barra junto a la pared derecha con taburetes
	local barCF = sideWallCF(base, 1, 14, 0)
	box("WindowBar", Vector3.new(12, 0.25, 1.6), barCF * CFrame.new(0, 3.6, -0.8), M.Wood, Color3.fromRGB(150, 110, 75))
	for k = -1, 1 do
		deco("BarBracket", Vector3.new(0.2, 1.2, 1.4), barCF * CFrame.new(k * 5.5, 2.9, -0.7), M.Metal, BLACK)
	end
	for k = 0, 3 do
		stool(barCF * CFrame.new(-4.5 + k * 3, 0, -2.4), Color3.fromRGB(60, 40, 30))
	end
	for _, p in { { -12, 12 }, { 12, 12 }, { -12, 26 }, { 12, 28 }, { 0, 32 } } do
		storePendant(L(base, p[1], STORE_H, p[2]), 4.5, Color3.fromRGB(35, 35, 38), def.Name)
	end
	aFrameBoard(F(base, 5, 3) * CFrame.Angles(0, math.rad(-20), 0), "CAFÉ DEL DÍA\n\nFlat white\n2,80 €")
	-- Barra de detras del mostrador: molinillo, torres de tazas y botes
	local counterTop = L(base, -14, 3.7, 40) * OUT
	deco("Grinder", Vector3.new(0.9, 1.6, 0.9), counterTop * CFrame.new(1.8, 0.8, 0.3), M.Metal, BLACK)
	deco("GrinderHopper", Vector3.new(0.9, 0.6, 0.6), counterTop * CFrame.new(1.8, 1.9, 0.3) * UPRIGHT, M.SmoothPlastic, Color3.fromRGB(120, 80, 50), { Shape = CYL, Transparency = 0.3 })
	for k = 0, 2 do
		deco("CupStack", Vector3.new(1.0, 0.5, 0.5), counterTop * CFrame.new(-4.6 + k * 0.6, 0.5, 0.5) * UPRIGHT, M.SmoothPlastic, Color3.fromRGB(245, 245, 240), { Shape = CYL })
	end
end

function FITOUT.Market(base: CFrame, def)
	produceStand(F(base, 12, 9.5))
	basketStack(L(base, 4, 0, 4), def.Accent)
	propOr("ShoppingCart", F(base, 2.5, 9) * CFrame.Angles(0, math.rad(15), 0), function() end, false)
	hangingSign(F(base, -6, 22) * CFrame.new(0, 11.2, 0), 5, 1.4, "1 · DESPENSA", Color3.fromRGB(240, 60, 60), Color3.new(1, 1, 1), Enum.Font.GothamBlack, 4.1)
	hangingSign(F(base, 6, 22) * CFrame.new(0, 11.2, 0), 5, 1.4, "2 · BEBIDAS", Color3.fromRGB(240, 60, 60), Color3.new(1, 1, 1), Enum.Font.GothamBlack, 4.1)
	hangingSign(F(base, 19, 22) * CFrame.new(0, 11.2, 0), 5, 1.4, "CONGELADOS", Color3.fromRGB(60, 140, 220), Color3.new(1, 1, 1), Enum.Font.GothamBlack, 4.1)
end

function FITOUT.Salon(base: CFrame, def)
	for _, d in { 10, 18, 26, 34 } do
		toolTrolley(L(base, 17.2, 0, d + 2.4) * FACE_NEG_X)
	end
	for _, x in { -12, -7.5 } do
		hoodDryer(F(base, x, 24), def.Accent:Lerp(DARK, 0.5))
	end
	magazineTable(L(base, 1.5, 0, 8))
	pottedPlant(L(base, -12, 0, 6))
end

-- Titulo del cartel de caja segun el tipo de tienda
local CHECKOUT_TITLE = {
	Cafe = "PIDE AQUÍ",
	Pharmacy = "DISPENSACIÓN",
	Gym = "RECEPCIÓN",
	Salon = "RECEPCIÓN",
	Optics = "ATENCIÓN AL CLIENTE",
}
-- Tiendas sin antenas antirrobo en la puerta
local NO_SECURITY_GATES = { Cafe = true, Gym = true, Salon = true }

-- Acabado comun de todas las tiendas: muro de marca con logo, rieles de focos,
-- instalaciones del techo, antenas antirrobo, vinilos del escaparate, felpudo, puerta
-- del almacen, reloj, datafono y cartel de caja. Las cerradas quedan apagadas.
function storeCommon(base: CFrame, def, hasBackDoor: boolean)
	local open = not def.Closed
	local zoneName = if open then def.Name else nil

	-- Muro de marca detras del mostrador (del lado izquierdo hasta x -6) con el logo
	local featureColor = def.Accent:Lerp(Color3.fromRGB(38, 36, 40), 0.5)
	deco("FeatureWall", Vector3.new(17, STORE_H - 1.2, 0.08), backWallCF(base, -14.5, (STORE_H - 1.2) / 2, 0.04), M.SmoothPlastic, featureColor, { Variant = false, CastShadow = false })
	deco("FeatureWallSide", Vector3.new(0.08, STORE_H - 1.2, 6), L(base, -SIDE_FACE + 0.04, (STORE_H - 1.2) / 2, BACK_FACE - 3), M.SmoothPlastic, featureColor, { Variant = false, CastShadow = false })
	local logo = deco("BrandLogo", Vector3.new(11, 2.0, 0.14), backWallCF(base, -14.5, 13.3, 0.15), M.SmoothPlastic, featureColor, { Variant = false })
	if open then
		litSign(logo, def.Name, def.Accent:Lerp(Color3.new(1, 1, 1), 0.35), def.Font, Enum.NormalId.Front)
		local halo = deco("BrandHalo", Vector3.new(10, 0.06, 0.06), backWallCF(base, -14.5, 12.15, 0.3), M.Neon, def.Accent, { CastShadow = false })
		tag(halo, Tags.Light, { Zone = def.Name })
	else
		sign(logo, def.Name, def.Accent:Lerp(DARK, 0.5), def.Font, Enum.NormalId.Front)
	end

	-- Rieles de focos y techo: detectores de humo, altavoces y camara domo sobre la caja
	for _, x in { -6, 6 } do
		trackLights(base, x, 5, 45, 5, zoneName)
	end
	smokeDetector(L(base, 6, STORE_H, 19))
	smokeDetector(L(base, -6, STORE_H, 33))
	ceilingSpeaker(L(base, 0, STORE_H, 20))
	ceilingSpeaker(L(base, 0, STORE_H, 40))
	domeCamera(L(base, -9, STORE_H, 34))

	-- Puerta del almacen (la fila sin salida trasera) y reloj de pared
	if not hasBackDoor then
		staffDoor(backWallCF(base, 3, 0))
	end
	wallClock(backWallCF(base, 6, 11.8))

	-- Escaparate: franja de seguridad en los vidrios y horario en el vinilo
	for _, side in { -1, 1 } do
		deco("GlassBand", Vector3.new(13.4, 0.3, 0.02), L(base, side * 15.2, 4.9, 0.22), M.SmoothPlastic, Color3.new(1, 1, 1), {
			Transparency = 0.5,
			CastShadow = false,
			Variant = false,
		})
	end
	local hours = deco("HoursVinyl", Vector3.new(2.6, 2.4, 0.02), L(base, -10.6, 6.8, 0.22) * OUT, M.SmoothPlastic, Color3.new(1, 1, 1), {
		Transparency = 1,
		CastShadow = false,
		Variant = false,
	})
	do
		local gui = surface(hours, Enum.NormalId.Front, 50, 0.4, 1.2)
		local holder = guiFrame(gui, { BackgroundTransparency = 1 })
		local layout = Instance.new("UIListLayout")
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		layout.Parent = holder
		local lines = if open
			then { { def.Name, 0.28, def.Font }, { "HORARIO", 0.14, Enum.Font.GothamBold }, { "LUN – SÁB   10:00 – 22:00", 0.12, Enum.Font.Gotham }, { "DOM Y FESTIVOS   11:00 – 21:00", 0.12, Enum.Font.Gotham }, { "Aceptamos tarjeta", 0.1, Enum.Font.Gotham } }
			else { { def.Name, 0.28, def.Font }, { "PRÓXIMA APERTURA", 0.16, Enum.Font.GothamBold }, { "Disculpen las molestias", 0.12, Enum.Font.Gotham } }
		for i, line in lines do
			guiText(holder, line[1], {
				Size = UDim2.fromScale(1, line[2]),
				Font = line[3],
				TextColor3 = Color3.fromRGB(250, 250, 248),
				TextTransparency = 0.05,
				LayoutOrder = i,
			})
		end
	end

	-- Felpudo de entrada con el logo
	-- (en la cara Top el texto corre a lo largo del eje Z de la pieza: el felpudo va girado)
	local mat = deco("EntryMat", Vector3.new(4.4, 0.06, 9), L(base, 0, 0.03, 3.4) * CFrame.Angles(0, math.rad(90), 0), M.Carpet, Color3.fromRGB(38, 38, 42), { Variant = false })
	do
		local gui = surface(mat, Enum.NormalId.Top, 20, 1, 1)
		guiText(guiFrame(gui, { BackgroundTransparency = 1 }), def.Name, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.8, 0.45),
			Font = def.Font,
			TextColor3 = def.Accent:Lerp(Color3.fromRGB(38, 38, 42), 0.35),
		})
	end

	-- Antenas antirrobo a los lados de la entrada
	if not NO_SECURITY_GATES[def.Kind] then
		for _, sx in { -7.2, 7.2 } do
			securityGate(L(base, sx, 0, 2.4))
		end
	end

	if not open then
		return
	end

	-- Caja: datafono, cartel colgado y pegatina de videovigilancia
	cardTerminal(L(base, -9.6, 3.72, 39.2) * OUT)
	hangingSign(L(base, -14, 9.6, 39.6) * OUT, 4.6, 1.1, CHECKOUT_TITLE[def.Kind] or "CAJA", def.Accent:Lerp(DARK, 0.65), Color3.new(1, 1, 1), Enum.Font.GothamBold, 5.85)
	local cctv = deco("CCTVSticker", Vector3.new(1.6, 1.1, 0.02), L(base, 12.8, 3.2, 0.22) * OUT, M.SmoothPlastic, Color3.fromRGB(250, 200, 30), { CastShadow = false, Variant = false })
	printed(cctv, "ZONA\nVIDEOVIGILADA", BLACK, Enum.Font.GothamBlack, Enum.NormalId.Front)
	-- Banderola de la promo colgada detras del escaparate (se ve desde la galeria)
	local promo = (def.Promo or "NUEVA TEMPORADA"):gsub("\n", " ")
	hangingSign(F(base, 0, 9) * CFrame.new(0, 11.1, 0), 8, 2.2, promo, def.Accent, Color3.new(1, 1, 1), Enum.Font.GothamBlack, 3.8)
end

-- Piezas que usan otras partes del mapa (tienda del conserje)
Kit.wallClock = wallClock
Kit.cardTerminal = cardTerminal
Kit.hangingSign = hangingSign
Kit.printed = printed
Kit.slatwall = slatwall
Kit.stool = stool
Kit.smokeDetector = smokeDetector
Kit.domeCamera = domeCamera
Kit.ceilingSpeaker = ceilingSpeaker
Kit.displayTable = displayTable
Kit.stackRow = stackRow
end -- (do: los helpers de arriba no cuentan para el limite de 200 locales del modulo)

local function buildStore(def, index: number, frontCenter: Vector3, inward: Vector3, wing: string, hasBackDoor: boolean)
	local storeFolder = Instance.new("Folder")
	storeFolder.Name = def.Name
	storeFolder.Parent = map
	currentParent = storeFolder

	local origin = Vector3.new(frontCenter.X, Y0 + levelY, frontCenter.Z)
	local base = CFrame.lookAt(origin, origin + inward)
	local W, D, H = STORE_W, STORE_D, STORE_H
	local half = W / 2
	local center = (base * CFrame.new(0, 0, -D / 2)).Position

	-- Suelo, techo y zona
	-- (Floor[3] = false: sin MaterialVariant; el porcelanico generado tira a marron)
	box("Floor", Vector3.new(W, 1, D), L(base, 0, -0.5, D / 2), def.Floor[1], def.Floor[2], if def.Floor[3] == false then { Variant = false } else nil)
	box("Ceiling", Vector3.new(W, 1, D), L(base, 0, H + 0.5, D / 2), M.Plaster, WHITE, { Variant = CEILING_VARIANT })
	-- Falso techo perimetral (bulkhead) con tira de luz indirecta
	for _, side in { -1, 1 } do
		deco("Bulkhead", Vector3.new(3, 1.2, D - 2), L(base, side * (half - 2.5), H - 0.6, D / 2), M.Plaster, WHITE)
	end
	deco("Threshold", Vector3.new(16, 0.06, 0.8), L(base, 0, 0.03, 0.4), M.Metal, STEEL)
	local zonePart = box("Zone_" .. def.Name, Vector3.new(W - 1, H, D - 1), L(base, 0, H / 2, D / 2), M.SmoothPlastic, Color3.new(1, 1, 1), {
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Variant = false,
	})
	tag(zonePart, Tags.Zone, { Zone = def.Name })

	-- Paredes laterales y trasera (con puerta de servicio en la fila norte): blanco roto con
	-- un toque del color de la marca (el color fuerte va en el muro de marca de storeCommon)
	local wallColor = def.Accent:Lerp(Color3.fromRGB(236, 233, 226), 0.92)
	for _, side in { -1, 1 } do
		box("SideWall", Vector3.new(1, H, D), L(base, side * (half - 0.5), H / 2, D / 2), M.Plaster, wallColor)
		deco("Baseboard", Vector3.new(0.24, 0.7, D), L(base, side * (half - 1.1), 0.35, D / 2), M.SmoothPlastic, TRIM)
	end
	local backA = (base * CFrame.new(-half, 0, -(D - 0.5))).Position
	local backB = (base * CFrame.new(half, 0, -(D - 0.5))).Position
	-- (wall() solo usa X/Z de los puntos y ya suma la altura de la planta actual)
	wall(backA, backB, H, {
		Color = wallColor,
		Openings = if hasBackDoor then { { From = half - 4, To = half + 4, Height = 9 } } else nil,
	})
	if hasBackDoor then
		exitSign(L(base, 0, 10, D - 1.2) * OUT)
		deco("BackDoorFrame", Vector3.new(8.6, 9.3, 1.2), L(base, 0, 4.65, D - 0.5), M.Metal, DARK, { Transparency = 0.999 })
	end

	-- Fachada: vitrinas de vidrio, entrada de 16, cabecera con el nombre
	for _, side in { -1, 1 } do
		local x = side * 15.2
		local glass = box("Glass", Vector3.new(13.6, 11.4, 0.3), L(base, x, 6.3, 0.4), M.Glass, GLASS, {
			Transparency = 0.65,
			Reflectance = 0.18,
			Variant = false,
		})
		tag(glass, Tags.ReflectiveSurface)
		box("KickPlate", Vector3.new(13.6, 0.6, 0.5), L(base, x, 0.3, 0.4), M.Metal, Color3.fromRGB(70, 72, 78))
		for _, mx in { 8.2, 15.2, 22.2 } do
			box("Mullion", Vector3.new(0.35, 12, 0.5), L(base, side * mx, 6, 0.4), M.Metal, Color3.fromRGB(70, 72, 78))
		end
		-- Podio del escaparate
		deco("WindowPodium", Vector3.new(11, 0.6, 4), L(base, side * 15, 0.3, 4), M.SmoothPlastic, Color3.fromRGB(235, 232, 226))
	end
	-- Pantalla publicitaria en el escaparate derecho (mision Apagar escaparates)
	-- (a un lado del podio: en medio puede haber un maniqui)
	deco("PromoStand", Vector3.new(0.3, 1.4, 0.3), L(base, 19, 1.3, 4.6), M.Metal, DARK)
	local displayColor = def.Accent:Lerp(DARK, 0.5)
	local display = box("PromoScreen", Vector3.new(3.6, 2.4, 0.3), L(base, 19, 3.2, 4.6) * OUT, M.SmoothPlastic, if def.Closed then DARK else displayColor, {
		CanCollide = false,
		Variant = false,
	})
	-- Tienda cerrada (def.Closed): pantalla apagada, sin luces y sin puntos de mision
	if not def.Closed then
		local screenGui = glowScreen(display, Enum.NormalId.Front, def.Accent, def.Accent:Lerp(DARK, 0.6), ((def.Promo or def.Name):gsub("\n", " ")))
		screenGui.Name = "Screen"
		local screenGlow = Instance.new("PointLight")
		screenGlow.Color = def.Accent
		screenGlow.Range = 9
		screenGlow.Brightness = 0.8
		screenGlow.Parent = display
		tag(display, Tags.StoreDisplay, { Wing = wing, OnColor = displayColor })
	end
	-- Cabecera (de 12 hasta el suelo de la planta de arriba / techo del pasillo)
	box("Header", Vector3.new(W, 5, 1), L(base, 0, 14.5, 0.5), M.Plaster, def.Accent:Lerp(DARK, 0.7))
	deco("HeaderTrim", Vector3.new(W, 0.25, 1.3), L(base, 0, 12.1, 0.5), M.Metal, STEEL)
	local signPart = box("StoreSign", Vector3.new(30, 2.8, 0.3), L(base, 0, 14.2, -0.15), M.SmoothPlastic, Color3.fromRGB(14, 14, 18), {
		CanCollide = false,
		Variant = false,
	})
	if def.Closed then
		sign(signPart, def.Name, def.Accent:Lerp(DARK, 0.55), def.Font, Enum.NormalId.Back) -- rotulo apagado
	else
		litSign(signPart, def.Name, def.Accent, def.Font, Enum.NormalId.Back)
	end
	-- Tira de luz del color de la tienda bajo la cabecera (se apaga con la zona)
	local strip = deco("AccentStrip", Vector3.new(W - 4, 0.12, 0.12), L(base, 0, 11.9, -0.25), M.Neon, def.Accent)
	tag(strip, Tags.Light, { Zone = def.Name })
	local signGlow = Instance.new("SurfaceLight")
	signGlow.Face = Enum.NormalId.Back
	signGlow.Range = 12
	signGlow.Angle = 70
	signGlow.Brightness = 0.5
	signGlow.Color = def.Accent
	signGlow.Parent = strip
	-- Vitrina: focos que iluminan el escaparate
	for _, side in { -1, 1 } do
		local spotPart = deco("WindowSpot", Vector3.new(0.8, 0.5, 0.8), L(base, side * 15, H - 0.3, 3), M.Metal, DARK)
		local spotLight = Instance.new("SpotLight")
		spotLight.Face = Enum.NormalId.Bottom
		spotLight.Angle = 60
		spotLight.Range = 18
		spotLight.Brightness = 1.6
		spotLight.Color = Color3.fromRGB(255, 238, 215)
		spotLight.Shadows = true
		spotLight.Parent = spotPart
		tag(spotPart, Tags.Light, { Zone = def.Name })
	end
	-- Pared sobre la cabecera hasta el techo del pasillo (planta alta: hasta GALLERY_TOP)
	box("UpperWall", Vector3.new(W, 1, 1), L(base, 0, H + 1.5, 0.5), M.Plaster, WALL)

	-- Persiana (mision Bajar persianas): control junto a la entrada, persiana hija
	local control = box("ShutterControl", Vector3.new(1, 1.4, 0.4), L(base, 10.2, 4.5, -0.3) * OUT, M.Metal, Color3.fromRGB(200, 170, 40))
	-- Botonera 3D de la persiana (PropTemplates.ShutterSwitch); la caja queda invisible
	if fitProp("ShutterSwitch", control.CFrame * CFrame.new(0, -0.75, 0), Vector3.new(1, 1.5, 0.5), false) then
		control.Transparency = 1
	end
	-- Pedestal de acero hasta el suelo (esta delante del escaparate: antes parecia flotar)
	local postH = 3.75 -- de la base de la botonera (4.5 - 0.75) al suelo
	deco("ShutterPost", Vector3.new(0.28, postH, 0.28), control.CFrame * CFrame.new(0, -0.75 - postH / 2, 0.05), M.Metal, Color3.fromRGB(60, 62, 68))
	deco("ShutterPostBase", Vector3.new(0.8, 0.1, 0.8), control.CFrame * CFrame.new(0, -4.45, 0.05), M.Metal, Color3.fromRGB(60, 62, 68))
	if not def.Closed then
		tag(control, Tags.ShutterControl, { Wing = wing })
	end
	local openCF, closedCF = L(base, 0, 11.6, 0.9), L(base, 0, 9, 0.9)
	local shutter = box("Shutter", Vector3.new(16, 0.8, 0.3), openCF, M.DiamondPlate, Color3.fromRGB(150, 152, 158), {
		CanCollide = false,
		CanQuery = false,
	})
	shutter:SetAttribute("OpenSize", Vector3.new(16, 0.8, 0.3))
	shutter:SetAttribute("OpenCFrame", openCF)
	shutter:SetAttribute("ClosedSize", Vector3.new(16, 6, 0.3))
	shutter:SetAttribute("ClosedCFrame", closedCF)
	shutter.Parent = control
	if def.Closed then
		-- Cerrada: persiana a media altura (se pasa agachado... o no) y cartel de cierre
		shutter.Size = Vector3.new(16, 6, 0.3)
		shutter.CFrame = closedCF
		shutter.Color = Color3.fromRGB(110, 110, 114)
		local notice = deco("ClosedNotice", Vector3.new(5, 2.2, 0.05), L(base, 3, 8.6, 0.72) * OUT, M.SmoothPlastic, Color3.fromRGB(235, 232, 220))
		sign(notice, "CERRADO\nPOR CIERRE", Color3.fromRGB(150, 25, 25), Enum.Font.GothamBlack, Enum.NormalId.Front)
	end

	-- Luces: paneles LED, rejillas de ventilacion y rociadores
	for _, x in { -12, 12 } do
		for _, d in { 14, 36 } do
			ceilingPanel(L(base, x, H, d), def.Name, Vector2.new(6, 2.4), 24, 1.6)
		end
		ceilingVent(L(base, x, H, 25))
	end
	for _, p in { { 0, 10 }, { 0, 30 }, { -18, 44 } } do
		deco("Sprinkler", Vector3.new(0.3, 0.3, 0.3), L(base, p[1], H - 0.15, p[2]), M.Metal, STEEL)
	end

	-- Mostrador con caja registradora, bolsas y cartel de la marca
	-- Mostrador 3D (PropTemplates.CheckoutCounter: frente blanco y encimera de madera) o el de piezas
	if not prop("CheckoutCounter", L(base, -14, 0, 40) * OUT) then
		box("Counter", Vector3.new(12, 3.5, 3), L(base, -14, 1.75, 40), M.Wood, def.Accent:Lerp(Color3.fromRGB(240, 235, 225), 0.6))
		deco("CounterTop", Vector3.new(12.4, 0.2, 3.4), L(base, -14, 3.6, 40), M.Marble, Color3.fromRGB(45, 44, 44))
	end
	local front = deco("CounterLogo", Vector3.new(6, 1.4, 0.06), L(base, -14, 2.2, 38.46) * OUT, M.SmoothPlastic, def.Accent:Lerp(DARK, 0.6))
	litSign(front, def.Name, def.Accent, def.Font, Enum.NormalId.Front)
	propOr("CashRegister", L(base, -12, 3.7, 40) * OUT, function(cf)
		box("Register", Vector3.new(1.6, 1, 1.2), cf * CFrame.new(0, 0.3, 0), M.Metal, DARK)
		local screen = deco("RegisterScreen", Vector3.new(1.3, 0.9, 0.08), cf * CFrame.new(0, 1.3, 0.3) * CFrame.Angles(math.rad(12), 0, 0), M.Glass, Color3.fromRGB(10, 14, 20))
		litSign(screen, "CERRADO", Color3.fromRGB(90, 170, 255), Enum.Font.Code, Enum.NormalId.Front)
	end, false)
	for k = 0, 2 do
		deco("ShoppingBag", Vector3.new(1.1, 1.3, 0.5), L(base, -18.8 + k * 0.4, 4.35, 40 + k * 0.3), M.Cardboard, vary(def.Accent, 0.1))
	end
	-- Caja registradora (mision Reiniciar cajas) y mostrador (mision Entrega de paquete):
	-- puntos invisibles sobre el mostrador
	local registerSpot = box("RegisterSpot", Vector3.new(2, 1.6, 1.6), L(base, -12, 4.4, 40), M.SmoothPlastic, Color3.new(1, 1, 1), {
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Variant = false,
	})
	if not def.Closed then
		tag(registerSpot, Tags.CashRegister, { Wing = wing })
	end
	local counterSpot = box("CounterSpot", Vector3.new(4, 1, 1.4), L(base, -16.5, 4.2, 39), M.SmoothPlastic, Color3.new(1, 1, 1), {
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Variant = false,
	})
	local backShelf = box("BackWallShelf", Vector3.new(14, 0.3, 1.2), L(base, -14, 6.5, D - 1.6), M.Wood, Color3.fromRGB(150, 110, 75))
	if not def.Closed then
		tag(counterSpot, Tags.StoreCounter, { Zone = def.Name })
		tag(backShelf, Tags.InventoryShelf, { Zone = def.Name }) -- (mision Inventario)
	end
	productRow(L(base, -14, 6.65, D - 1.6), 13, 0.9, def.Accent:Lerp(WHITE, 0.4))
	trashBin(L(base, -21, 0, 45), if def.Closed then nil else wing)
	-- Publicidad retroiluminada en la pared izquierda (por encima de los muebles)
	if not def.Closed then
		-- (x -22.75: antes quedaba dentro del muro y no se veia)
		lightbox(L(base, -22.75, 12, 34) * FACE_POS_X, 8, 3.2, def.Promo or "NUEVA TEMPORADA", def.Accent, def.Name)
	end

	-- Interior segun el tipo, acabado comun y mobiliario extra (las cerradas, sin extras)
	local hasHiding = INTERIORS[def.Kind](base, def)
	storeCommon(base, def, hasBackDoor)
	if not def.Closed and FITOUT[def.Kind] then
		FITOUT[def.Kind](base, def)
	end

	-- Escondite (armario del personal) si el interior no trae uno
	if not hasHiding then
		hidingSpot("Armario", L(base, 17, 3.75, D - 2.6) * OUT, Vector3.new(4, 7.5, 3), M.Metal, Color3.fromRGB(80, 95, 110))
	end

	-- Tienda cerrada: sabanas sobre el mobiliario, polvo y ningun punto de mision
	if def.Closed then
		for _, p in { { -12, 14 }, { 12, 14 }, { -12, 27 }, { 12, 30 }, { -2, 31 } } do
			deco("DustSheet", Vector3.new(8.6, 5.4, 3), L(base, p[1], 2.7, p[2]), M.Fabric, Color3.fromRGB(214, 212, 204), {
				CanCollide = false,
				CanQuery = false,
			})
		end
		for _, p in { { -6, 22 }, { 8, 40 }, { 16, 20 } } do
			deco("Dust", Vector3.new(6, 0.04, 4), L(base, p[1], 0.02, p[2]) * CFrame.Angles(0, math.rad(p[1] * 7), 0), M.Sand, Color3.fromRGB(120, 112, 100))
		end
		deco("FallenBox", Vector3.new(2.2, 1.6, 2.2), L(base, 4, 0.8, 12) * CFrame.Angles(0, math.rad(25), 0), M.Cardboard, Color3.fromRGB(170, 130, 85))
		currentParent = map
		return center
	end

	-- Puntos de mision
	electricPanel(L(base, 10, 4.5, D - 1.3) * OUT, def.Name)
	local alarm = box("AlarmPanel", Vector3.new(1, 1.4, 0.4), L(base, -22.6, 6, 6) * FACE_POS_X, M.SmoothPlastic, Color3.fromRGB(170, 35, 35))
	tag(alarm, Tags.MissionSpot, { MissionType = "SilenceAlarm", Zone = def.Name })
	local shelf = box("RestockShelf", Vector3.new(6, 0.4, 1.6), L(base, -22, 3, 24) * FACE_POS_X, M.Wood, Color3.fromRGB(170, 130, 90))
	tag(shelf, Tags.MissionSpot, { MissionType = "RestockStore", Zone = def.Name })
	local spillPos = L(base, 6, 0, 20).Position
	spot(spillPos.X, spillPos.Z, "CleanSpill", def.Name)
	local trashPos = L(base, -18, 0, 45).Position
	spot(trashPos.X, trashPos.Z, "TakeOutTrash", def.Name)
	if index % 2 == 0 then
		local lostPos = L(base, 6, 0, 44).Position
		spot(lostPos.X, lostPos.Z, "LostItem", def.Name)
	end
	-- Tiendas del sur (impares): aparecen enemigos al fondo
	if not hasBackDoor and index % 2 == 1 then
		local spawnPos = L(base, 18, 0, D - 6).Position
		enemySpawn(spawnPos.X, spawnPos.Z)
	end

	currentParent = map
	return center
end

----------------------------------------------------------------------
-- Tiendas (5 al norte y 5 al sur por planta; de oeste a este)
----------------------------------------------------------------------

local STORES_1 = {
	{ Name = "Moda Luna", Kind = "Clothes", Promo = "NUEVA\nCOLECCIÓN", Accent = Color3.fromRGB(235, 120, 170), Font = Enum.Font.Garamond, Floor = { M.WoodPlanks, Color3.fromRGB(240, 232, 220) } },
	{ Name = "TecnoMax", Kind = "Tech", Promo = "OFERTAS\n-30%", Accent = Color3.fromRGB(70, 195, 255), Font = Enum.Font.Michroma, Floor = { M.CeramicTiles, Color3.fromRGB(196, 198, 200), false } },
	{ Name = "Juguetería Pipo", Kind = "Toys", Promo = "¡A JUGAR!", Accent = Color3.fromRGB(255, 205, 50), Font = Enum.Font.FredokaOne, Floor = { M.CeramicTiles, Color3.fromRGB(150, 200, 235) } },
	{ Name = "Deportes Ríos", Kind = "Sports", Promo = "SUPERA\nTUS LÍMITES", Accent = Color3.fromRGB(70, 210, 100), Font = Enum.Font.Oswald, Floor = { M.Rubber, Color3.fromRGB(60, 62, 68) } },
	{ Name = "Librería Papel", Kind = "Books", Promo = "LOS MÁS\nLEÍDOS", Accent = Color3.fromRGB(240, 210, 150), Font = Enum.Font.Merriweather, Floor = { M.Carpet, Color3.fromRGB(115, 40, 45) } },
	{ Name = "Zapatería Paso", Kind = "Shoes", Promo = "2x1 EN\nZAPATILLAS", Accent = Color3.fromRGB(255, 145, 60), Font = Enum.Font.GothamBlack, Floor = { M.WoodPlanks, Color3.fromRGB(185, 160, 140) } },
	{ Name = "Perfumería Aroma", Kind = "Perfume", Promo = "ESENCIA\nDE NOCHE", Accent = Color3.fromRGB(190, 130, 255), Font = Enum.Font.Fondamento, Floor = { M.Marble, Color3.fromRGB(240, 238, 235) } },
	{ Name = "Óptica Visión", Kind = "Optics", Promo = "EXAMEN\nGRATIS", Accent = Color3.fromRGB(90, 140, 255), Font = Enum.Font.Gotham, Floor = { M.CeramicTiles, Color3.fromRGB(225, 228, 232) } },
	{ Name = "Hogar Nube", Kind = "Home", Promo = "TU CASA,\nTU NUBE", Accent = Color3.fromRGB(90, 205, 195), Font = Enum.Font.Nunito, Floor = { M.Carpet, Color3.fromRGB(190, 175, 150) } },
	{ Name = "Disco Sonar", Kind = "Music", Promo = "VINILOS\nY MÁS", Accent = Color3.fromRGB(235, 75, 75), Font = Enum.Font.Bangers, Floor = { M.WoodPlanks, Color3.fromRGB(140, 115, 100) } },
}

local STORES_2 = {
	{ Name = "Joyería Brillo", Kind = "Jewelry", Promo = "ORO Y\nDIAMANTES", Accent = Color3.fromRGB(240, 200, 90), Font = Enum.Font.Garamond, Floor = { M.Marble, Color3.fromRGB(60, 58, 60) } },
	{ Name = "Farmacia Salud", Kind = "Pharmacy", Promo = "ABIERTO\n24 HORAS", Accent = Color3.fromRGB(60, 200, 110), Font = Enum.Font.GothamBold, Floor = { M.CeramicTiles, Color3.fromRGB(235, 238, 240) } },
	{ Name = "Gimnasio Titán", Kind = "Gym", Promo = "SIN\nEXCUSAS", Accent = Color3.fromRGB(255, 90, 40), Font = Enum.Font.Oswald, Floor = { M.Rubber, Color3.fromRGB(45, 45, 50) } },
	{ Name = "Muebles Roble", Kind = "Furniture", Promo = "DISEÑO\nNÓRDICO", Accent = Color3.fromRGB(200, 150, 100), Font = Enum.Font.Merriweather, Floor = { M.WoodPlanks, Color3.fromRGB(225, 210, 190) } },
	{ Name = "Mundo Gamer", Kind = "Gamer", Promo = "NIVEL\nMÁXIMO", Accent = Color3.fromRGB(150, 90, 255), Font = Enum.Font.Michroma, Floor = { M.Carpet, Color3.fromRGB(40, 40, 52) } },
	{ Name = "Café Aroma", Kind = "Cafe", Promo = "CAFÉ\nDE ESPECIALIDAD", Accent = Color3.fromRGB(200, 140, 80), Font = Enum.Font.Fondamento, Floor = { M.WoodPlanks, Color3.fromRGB(170, 135, 110) } },
	{ Name = "Súper Express", Kind = "Market", Promo = "FRESCO\nCADA DÍA", Accent = Color3.fromRGB(240, 60, 60), Font = Enum.Font.GothamBlack, Floor = { M.CeramicTiles, Color3.fromRGB(225, 225, 220) } },
	{ Name = "Salón Glamour", Kind = "Salon", Promo = "LUCE\nINCREÍBLE", Accent = Color3.fromRGB(255, 120, 200), Font = Enum.Font.Fondamento, Floor = { M.Marble, Color3.fromRGB(240, 236, 232) } },
	{ Name = "Moda Peque", Kind = "Clothes", Promo = "VUELTA\nAL COLE", Accent = Color3.fromRGB(120, 200, 255), Font = Enum.Font.FredokaOne, Floor = { M.WoodPlanks, Color3.fromRGB(240, 232, 220) } },
	{ Name = "Electro Casa", Kind = "Tech", Promo = "TODO PARA\nTU HOGAR", Accent = Color3.fromRGB(90, 220, 200), Font = Enum.Font.Gotham, Floor = { M.CeramicTiles, Color3.fromRGB(204, 204, 202), false } },
}

-- Las tiendas del centro (columna 3, x -24..24) ya no estan en la galeria: alli se abren
-- los pasajes a las alas (norte y sur). Sus tiendas se mudaron al Ala Norte.
local WING_COLUMN = 3

local function buildStoreRow(defs, west: string, east: string)
	for i, def in defs do
		local north = i <= 5
		local col = if north then i else i - 5
		if col ~= WING_COLUMN then
			local x = -120 + STORE_W * (col - 1) + STORE_W / 2
			local front = Vector3.new(x, 0, if north then 20 else -20)
			local inward = if north then Vector3.new(0, 0, 1) else Vector3.new(0, 0, -1)
			buildStore(def, i, front, inward, if x <= 0 then west else east, north)
		end
	end
end

-- Ala Norte: 4 tiendas por planta a los lados del pasillo (x ±24), de sur a norte.
-- { def, lado (-1 oeste / 1 este), centro z }. Las de la columna 3 de la galeria se mudaron aqui.
local NORTH_STORES_1 = {
	STORES_1[3], -- Jugueteria Pipo
	STORES_1[8], -- Optica Vision
	{ Name = "Relojería Tic Tac", Kind = "Jewelry", Promo = "EL TIEMPO\nES ORO", Accent = Color3.fromRGB(210, 180, 120), Font = Enum.Font.Garamond, Floor = { M.Marble, Color3.fromRGB(70, 66, 64) } },
	{ Name = "Novias Azahar", Kind = "Clothes", Promo = "EL DÍA\nMÁS FELIZ", Accent = Color3.fromRGB(240, 225, 235), Font = Enum.Font.Fondamento, Floor = { M.Marble, Color3.fromRGB(236, 232, 228) }, Closed = true },
}
local NORTH_STORES_2 = {
	STORES_2[3], -- Gimnasio Titan
	STORES_2[8], -- Salon Glamour
	{ Name = "Bici Ruta", Kind = "Sports", Promo = "RUEDA\nSIN LÍMITES", Accent = Color3.fromRGB(255, 170, 40), Font = Enum.Font.Oswald, Floor = { M.Rubber, Color3.fromRGB(58, 60, 66) } },
	{ Name = "Disfraces Carnaval", Kind = "Clothes", Promo = "¿QUIÉN\nERES HOY?", Accent = Color3.fromRGB(200, 80, 230), Font = Enum.Font.Bangers, Floor = { M.WoodPlanks, Color3.fromRGB(120, 95, 80) }, Closed = true },
}
-- Posicion de cada tienda del ala (mismo orden que las listas): suroeste, noroeste, sureste, noreste
local NORTH_SLOTS = { { -1, 135 }, { -1, 183 }, { 1, 135 }, { 1, 183 } }

-- Ala Sur (en obras): 4 locales por planta y los grandes almacenes al fondo
local SOUTH_Z1 = -167 -- fondo del pasillo del Ala Sur (el pasillo empieza en z = -70)
local SOUTH_SLOTS = { { -1, -95 }, { -1, -143 }, { 1, -95 }, { 1, -143 } }
local ANCHOR = { X1 = -74, X2 = 74, Z1 = -227, Z2 = -167 } -- grandes almacenes (2 plantas)

local function buildWingStores(defs, wingName: string, floorOffset: number)
	for i, def in defs do
		local slot = NORTH_SLOTS[i]
		local side, zc = slot[1], slot[2]
		buildStore(def, floorOffset + i, Vector3.new(side * WING, 0, zc), Vector3.new(side, 0, 0), wingName, true)
	end
end

----------------------------------------------------------------------
-- Directorio (totem con el plano de las dos plantas)
----------------------------------------------------------------------

-- Areas comunes de cada planta: { texto, x1, x2, z1, z2, color }
local MAP_AREAS = {
	{
		{ "BODEGA", -180, -90, 70, 110, Color3.fromRGB(80, 82, 90) },
		{ "SERVICIO · BAÑOS", -90, 180, 70, 110, Color3.fromRGB(80, 82, 90) },
		{ "PATIO DE\nCOMIDAS", -180, -120, -70, 70, Color3.fromRGB(190, 120, 50) },
		{ "ENTRADA", 120, 180, -70, 70, Color3.fromRGB(70, 120, 170) },
		{ "GALERÍA", -120, 120, -20, 20, Color3.fromRGB(200, 196, 186) },
		{ "ALA NORTE", -24, 24, 20, 207, Color3.fromRGB(200, 196, 186) },
		{ "SERVICIO", -84, 84, 207, 222, Color3.fromRGB(80, 82, 90) },
		{ "", -84, -74, 111, 207, Color3.fromRGB(80, 82, 90) },
		{ "", 74, 84, 111, 207, Color3.fromRGB(80, 82, 90) },
		{ "ALA SUR\n(OBRAS)", -24, 24, -167, -20, Color3.fromRGB(150, 120, 60) },
		{ "ALMACENES\nESTRELLA\n(CERRADO)", -74, 74, -227, -167, Color3.fromRGB(70, 60, 60) },
	},
	{
		{ "ALMACÉN", -180, -90, 70, 110, Color3.fromRGB(80, 82, 90) },
		{ "OFICINAS", -90, 180, 70, 110, Color3.fromRGB(80, 82, 90) },
		{ "CINE", -180, -120, -70, 70, Color3.fromRGB(150, 35, 45) },
		{ "ZONA DE\nJUEGOS", 120, 180, -70, 70, Color3.fromRGB(110, 60, 190) },
		{ "ATRIO", -120, 120, -20, 20, Color3.fromRGB(200, 196, 186) },
		{ "ALA NORTE", -24, 24, 20, 207, Color3.fromRGB(200, 196, 186) },
		{ "SERVICIO", -84, 84, 207, 222, Color3.fromRGB(80, 82, 90) },
		{ "", -84, -74, 111, 207, Color3.fromRGB(80, 82, 90) },
		{ "", 74, 84, 111, 207, Color3.fromRGB(80, 82, 90) },
		{ "ALA SUR\n(OBRAS)", -24, 24, -167, -20, Color3.fromRGB(150, 120, 60) },
		{ "ALMACENES\nESTRELLA\n(CERRADO)", -74, 74, -227, -167, Color3.fromRGB(70, 60, 60) },
	},
}
-- Limites del plano (con las alas): x -180..180, z -228..223
local MAP_X1, MAP_X2, MAP_Z1, MAP_Z2 = -180, 180, -228, 223

-- Coordenadas del mundo -> posicion relativa en el plano (norte arriba)
local function mapPos(x: number, z: number): (number, number)
	return (x - MAP_X1) / (MAP_X2 - MAP_X1), (MAP_Z2 - z) / (MAP_Z2 - MAP_Z1)
end

-- Tiendas y locales de cada planta para el plano: { nombre, x1, x2, z1, z2, color }
local function mapStores(floorIndex: number)
	local list = {}
	local defs = if floorIndex == 2 then STORES_2 else STORES_1
	for i, def in defs do
		local north = i <= 5
		local col = if north then i else i - 5
		if col ~= WING_COLUMN then
			local x1 = -120 + STORE_W * (col - 1)
			table.insert(list, { def.Name, x1, x1 + STORE_W, if north then 20 else -70, if north then 70 else -20, def.Accent })
		end
	end
	for i, def in (if floorIndex == 2 then NORTH_STORES_2 else NORTH_STORES_1) do
		local slot = NORTH_SLOTS[i]
		local x1 = if slot[1] > 0 then WING else -(WING + STORE_D)
		table.insert(list, { def.Name, x1, x1 + STORE_D, slot[2] - STORE_W / 2, slot[2] + STORE_W / 2, if def.Closed then Color3.fromRGB(60, 60, 64) else def.Accent })
	end
	for _, slot in SOUTH_SLOTS do
		local x1 = if slot[1] > 0 then WING else -(WING + STORE_D)
		table.insert(list, { "OBRAS", x1, x1 + STORE_D, slot[2] - STORE_W / 2, slot[2] + STORE_W / 2, Color3.fromRGB(120, 100, 60) })
	end
	return list
end

local function mapRect(parent: Instance, text: string, x1, x2, z1, z2, color: Color3, textColor: Color3?)
	local u1, v1 = mapPos(x1, z2)
	local u2, v2 = mapPos(x2, z1)
	local f = Instance.new("Frame")
	f.Position = UDim2.fromScale(u1, v1)
	f.Size = UDim2.fromScale(u2 - u1, v2 - v1)
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(15, 15, 20)
	stroke.Thickness = 1
	stroke.Parent = f
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(0.9, 0.8)
	label.Position = UDim2.fromScale(0.05, 0.1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = textColor or Color3.new(1, 1, 1)
	label.Text = text
	label.Parent = f
	f.Parent = parent
	return f
end

local function floorMap(parent: Instance, floorIndex: number, order: number, here: Vector3?)
	local title = Instance.new("TextLabel")
	title.LayoutOrder = order
	title.Size = UDim2.new(1, 0, 0.05, 0)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.TextScaled = true
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = Color3.fromRGB(255, 210, 120)
	title.Text = if floorIndex == 2 then "PLANTA ALTA  ·  P2" else "PLANTA BAJA  ·  P1"
	title.Parent = parent

	local map = Instance.new("Frame")
	map.LayoutOrder = order + 1
	map.Size = UDim2.fromScale(1, 0.37)
	map.BackgroundColor3 = Color3.fromRGB(30, 32, 40)
	map.BorderSizePixel = 0
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = (MAP_X2 - MAP_X1) / (MAP_Z2 - MAP_Z1)
	aspect.Parent = map
	map.Parent = parent

	for _, a in MAP_AREAS[floorIndex] do
		local corridor = a[1] == "GALERÍA" or a[1] == "ATRIO" or a[1] == "ALA NORTE"
		mapRect(map, a[1], a[2], a[3], a[4], a[5], a[6], if corridor then Color3.fromRGB(40, 40, 46) else nil)
	end
	for _, s in mapStores(floorIndex) do
		mapRect(map, s[1], s[2], s[3], s[4], s[5], s[6]:Lerp(Color3.fromRGB(20, 20, 24), 0.45))
	end
	-- Escaleras mecanicas y de servicio
	for _, ex in { -76.5, 76.5 } do
		local f = mapRect(map, "⇅", ex - 15.5, ex + 15.5, -5, 5, Color3.fromRGB(60, 160, 230))
		f.ZIndex = 2
	end
	mapRect(map, "▤", 146, 172, 99, 107, Color3.fromRGB(240, 190, 30), Color3.fromRGB(20, 20, 20)).ZIndex = 2
	-- Usted esta aqui
	if here then
		local u, v = mapPos(here.X, here.Z)
		local dot = Instance.new("Frame")
		dot.AnchorPoint = Vector2.new(0.5, 0.5)
		dot.Position = UDim2.fromScale(u, v)
		dot.Size = UDim2.fromScale(0.06, 0.048)
		dot.BackgroundColor3 = Color3.fromRGB(255, 40, 40)
		dot.ZIndex = 3
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = dot
		local ring = Instance.new("UIStroke")
		ring.Color = Color3.new(1, 1, 1)
		ring.Thickness = 2
		ring.Parent = dot
		dot.Parent = map
	end
end

-- Pantalla del directorio en la cara Front de `part`. here = posicion del totem (su planta).
local function directoryScreen(part: BasePart, here: Vector3, floorIndex: number)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.LightInfluence = 0
	gui.Brightness = 1.3
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 120
	local root = Instance.new("Frame")
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundColor3 = Color3.fromRGB(14, 16, 22)
	root.BorderSizePixel = 0
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0.05, 0)
	padding.PaddingRight = UDim.new(0.05, 0)
	padding.PaddingTop = UDim.new(0.03, 0)
	padding.Parent = root
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0.01, 0)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = root

	local header = Instance.new("TextLabel")
	header.LayoutOrder = 0
	header.Size = UDim2.new(1, 0, 0.08, 0)
	header.BackgroundTransparency = 1
	header.Font = Enum.Font.Fondamento
	header.TextScaled = true
	header.TextColor3 = Color3.fromRGB(255, 215, 120)
	header.Text = "PLAZA LUNA · DIRECTORIO"
	header.Parent = root

	-- Primero la planta en la que esta el totem
	local first, second = floorIndex, if floorIndex == 1 then 2 else 1
	floorMap(root, first, 1, here)
	floorMap(root, second, 3, nil)

	local legend = Instance.new("TextLabel")
	legend.LayoutOrder = 10
	legend.Size = UDim2.new(1, 0, 0.1, 0)
	legend.BackgroundTransparency = 1
	legend.Font = Enum.Font.Gotham
	legend.TextScaled = true
	legend.TextColor3 = Color3.fromRGB(200, 205, 215)
	legend.Text = "●  Usted está aquí     ⇅  Escaleras mecánicas     ▤  Escalera de servicio"
	legend.Parent = root
	root.Parent = gui
	gui.Parent = part
end

-- Totem: base de granito, cuerpo de acero, pantalla con el plano e icono "i".
-- `cf` en el suelo, frente (-Z) hacia el publico. doubleSided = pantalla tambien detras.
local function directoryTotem(cf: CFrame, floorIndex: number, doubleSided: boolean?)
	deco("TotemPlinth", Vector3.new(3.4, 0.3, 1.4), cf * CFrame.new(0, 0.15, 0), M.Granite, Color3.fromRGB(50, 48, 46))
	box("DirectoryTotem", Vector3.new(3, 7.8, 0.9), cf * CFrame.new(0, 4.2, 0), M.Metal, Color3.fromRGB(70, 72, 80))
	deco("TotemCap", Vector3.new(3.2, 0.25, 1.1), cf * CFrame.new(0, 8.2, 0), M.Metal, STEEL)
	local here = (cf * CFrame.new(0, 0, -1)).Position
	for _, side in (if doubleSided then { 1, -1 } else { 1 }) do
		local face = cf * CFrame.Angles(0, if side > 0 then 0 else math.pi, 0)
		deco("TotemBezel", Vector3.new(2.8, 5.4, 0.06), face * CFrame.new(0, 4.4, -0.46), M.SmoothPlastic, Color3.fromRGB(15, 15, 18))
		local screen = deco("DirectoryScreen", Vector3.new(2.6, 5.2, 0.05), face * CFrame.new(0, 4.4, -0.5), M.SmoothPlastic, Color3.fromRGB(8, 10, 14), { Variant = false })
		directoryScreen(screen, here, floorIndex)
		local badge = deco("TotemBadge", Vector3.new(0.7, 0.7, 0.06), face * CFrame.new(0, 7.5, -0.47), M.Neon, Color3.fromRGB(40, 130, 230))
		litSign(badge, "i", Color3.new(1, 1, 1), Enum.Font.GothamBlack, Enum.NormalId.Front)
	end
	local glow = deco("TotemGlow", Vector3.new(0.2, 0.2, 0.2), cf * CFrame.new(0, 4.4, -1.2), M.SmoothPlastic, Color3.new(1, 1, 1), { Transparency = 1 })
	local light = Instance.new("PointLight")
	light.Range = 6
	light.Brightness = 0.5
	light.Color = Color3.fromRGB(150, 190, 255)
	light.Parent = glow
end

----------------------------------------------------------------------
-- Escaleras mecanicas
----------------------------------------------------------------------

-- Cuña maciza con la rampa arriba. La parte baja queda en lowX y la alta (a F2) en highX.
local function rampBody(name: string, lowX: number, highX: number, zc: number, width: number, material, color: Color3)
	local dirX = if highX > lowX then 1 else -1
	local run = math.abs(highX - lowX)
	local center = Vector3.new((lowX + highX) / 2, Y0 + F2 / 2, zc)
	-- WedgePart: alta en +Z local, baja en -Z local (su LookVector apunta al extremo bajo)
	return make("WedgePart", name, Vector3.new(width, F2, run), CFrame.lookAt(center, center + Vector3.new(-dirX, 0, 0)), material, color)
end

-- Escalera mecanica funcional: la rampa arrastra al jugador (AssemblyLinearVelocity) y
-- el cliente anima los escalones (EscalatorFX). Los enemigos la usan como rampa (pathfinding).
local function escalator(lowX: number, highX: number, zc: number, up: boolean)
	local model = Instance.new("Model")
	model.Name = if up then "EscalatorUp" else "EscalatorDown"
	model.Parent = currentParent
	local previous = currentParent
	currentParent = model

	local W = 4.2
	local dirX = if highX > lowX then 1 else -1
	local low = Vector3.new(lowX, Y0, zc)
	local high = Vector3.new(highX, Y0 + F2, zc)
	local length = (high - low).Magnitude
	local u = (high - low).Unit
	local mid = (low + high) / 2
	local surface = CFrame.lookAt(mid, mid + u) -- LookVector: rampa arriba; UpVector: normal

	-- Cuerpo (la rampa: colision y arrastre) revestido de acero cepillado
	local body = rampBody("EscalatorBody", lowX, highX, zc, W, M.SmoothPlastic, Color3.fromRGB(196, 200, 205))
	body.MaterialVariant = ""
	body.Reflectance = 0.12
	body.AssemblyLinearVelocity = u * ESC_SPEED * (if up then 1 else -1)
	-- Juntas de los paneles del revestimiento lateral (cada 3 studs, hasta la rampa)
	local runLength = math.abs(highX - lowX)
	for k = 1, math.floor(runLength / 3) do
		local t = k * 3 / runLength
		local x = lowX + (highX - lowX) * t
		local h = F2 * t
		if h > 0.6 then
			for _, side in { -1, 1 } do
				deco("CladSeam", Vector3.new(0.06, h - 0.3, 0.04), CFrame.new(x, Y0 + (h - 0.3) / 2, zc + side * (W / 2 + 0.02)), M.SmoothPlastic, Color3.fromRGB(120, 124, 130), {
					CastShadow = false,
					Variant = false,
				})
			end
		end
	end
	for _, side in { -1, 1 } do
		-- Zocalo oscuro a lo largo del suelo
		deco("CladPlinth", Vector3.new(runLength, 0.3, 0.06), CFrame.new((lowX + highX) / 2, Y0 + 0.15, zc + side * (W / 2 + 0.03)), M.SmoothPlastic, Color3.fromRGB(45, 46, 52), {
			Variant = false,
		})
	end

	-- Escalones (los mueve el cliente: EscalatorFX mueve la pieza "StepNN" por la rampa).
	-- Cada escalon es un soporte invisible con la huella horizontal, la contrahuella y las
	-- lineas amarillas soldadas: se ve como una escalera de verdad y se mueve entera.
	local stepsFolder = Instance.new("Folder")
	stepsFolder.Name = "Steps"
	stepsFolder.Parent = model
	local count = math.floor(length / 1.35)
	local spacing = length / count
	local slope = math.asin(F2 / length) -- inclinacion de la rampa
	local run = spacing * math.cos(slope) -- huella (horizontal)
	local rise = spacing * math.sin(slope) -- contrahuella
	local treadW = W - 0.5
	local treadColor = Color3.fromRGB(58, 60, 66)
	local yellow = Color3.fromRGB(245, 200, 30)
	for i = 1, count do
		local s = -length / 2 + (i - 1) * spacing
		local carrierCF = surface * CFrame.new(0, 0.1, -s)
		local step = deco(string.format("Step%02d", i), Vector3.new(treadW, 0.1, spacing - 0.1), carrierCF, M.SmoothPlastic, treadColor, {
			Transparency = 1,
			CastShadow = false,
			Variant = false,
		})
		step.Parent = stepsFolder
		-- Marco horizontal del escalon (-Z hacia lo alto de la rampa)
		local horiz = carrierCF * CFrame.Angles(-slope, 0, 0)
		local h = 0.12
		local pieces = {
			deco("StepTread", Vector3.new(treadW, 0.14, run), horiz * CFrame.new(0, h, 0), M.DiamondPlate, treadColor, { CastShadow = false }),
			deco("StepRiser", Vector3.new(treadW, rise, 0.1), horiz * CFrame.new(0, h - rise / 2, run / 2), M.Metal, Color3.fromRGB(40, 42, 46), { CastShadow = false }),
			deco("StepEdge", Vector3.new(treadW, 0.16, 0.16), horiz * CFrame.new(0, h + 0.01, run / 2 - 0.08), M.SmoothPlastic, yellow, { CastShadow = false, Variant = false }),
		}
		for _, sx in { -1, 1 } do
			table.insert(pieces, deco("StepSide", Vector3.new(0.14, 0.16, run), horiz * CFrame.new(sx * (treadW / 2 - 0.07), h + 0.01, 0), M.SmoothPlastic, yellow, {
				CastShadow = false,
				Variant = false,
			}))
		end
		for _, piece in pieces do
			piece.Anchored = false
			piece.Massless = true
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = step
			weld.Part1 = piece
			weld.Parent = piece
			piece.Parent = step
		end
	end

	-- Balaustradas de vidrio (con colision: nadie se cae por los lados), zocalo de acero con
	-- tira LED, cubierta interior y pasamanos de goma redondo que da la vuelta en los extremos
	local rubber = Color3.fromRGB(18, 18, 20)
	for _, side in { -1, 1 } do
		box("Balustrade", Vector3.new(0.2, 3.2, length), surface * CFrame.new(side * (W / 2 + 0.1), 1.75, 0), M.Glass, GLASS, {
			Transparency = 0.7,
			Reflectance = 0.25,
			CastShadow = false,
			Variant = false,
		})
		deco("Skirt", Vector3.new(0.3, 0.6, length), surface * CFrame.new(side * (W / 2 - 0.1), 0.35, 0), M.Metal, STEEL)
		deco("SkirtLight", Vector3.new(0.06, 0.06, length - 0.4), surface * CFrame.new(side * (W / 2 - 0.27), 0.62, 0), M.Neon, Color3.fromRGB(150, 210, 255), {
			CastShadow = false,
			Variant = false,
		})
		deco("Decking", Vector3.new(0.6, 0.12, length), surface * CFrame.new(side * (W / 2 + 0.05), 0.12, 0), M.Metal, Color3.fromRGB(150, 152, 158))
		-- Pinzas del vidrio
		local clamps = math.max(2, math.floor(length / 4))
		for k = 0, clamps do
			deco("GlassClamp", Vector3.new(0.34, 0.35, 0.3), surface * CFrame.new(side * (W / 2 + 0.1), 0.35, -length / 2 + k * (length / clamps)), M.Metal, STEEL)
		end
		-- Pasamanos (cilindro a lo largo de la rampa) y su perfil de apoyo
		deco("HandrailGuide", Vector3.new(0.16, 0.18, length), surface * CFrame.new(side * (W / 2 + 0.1), 3.32, 0), M.Metal, STEEL)
		deco("Handrail", Vector3.new(length, 0.38, 0.38), surface * CFrame.new(side * (W / 2 + 0.1), 3.5, 0) * CFrame.Angles(0, math.rad(90), 0), M.Rubber, rubber, {
			Shape = Enum.PartType.Cylinder,
			Variant = false,
		})
	end
	-- Extremos (cabeza de la balaustrada): tramo horizontal y la curva del pasamanos, en
	-- las dos plantas, con el peine amarillo y la placa de entrada
	for _, isTop in { false, true } do
		local endX = if isTop then highX else lowX
		local y = if isTop then Y0 + F2 else Y0
		local out = if isTop then dirX else -dirX -- hacia fuera de la escalera
		local NEWEL = 2.2 -- largo del tramo horizontal
		for _, side in { -1, 1 } do
			-- Donde acaba el pasamanos inclinado: de ahi sale el tramo horizontal
			local railEnd = (surface * CFrame.new(side * (W / 2 + 0.1), 3.5, if isTop then -length / 2 else length / 2)).Position
			local glassEnd = (surface * CFrame.new(side * (W / 2 + 0.1), 0, if isTop then -length / 2 else length / 2)).Position
			local railY = railEnd.Y
			local startX = railEnd.X
			local z = zc + side * (W / 2 + 0.1)
			local glassH = railY - y - 0.25
			deco("NewelGlass", Vector3.new(NEWEL + math.abs(startX - glassEnd.X), glassH, 0.2), CFrame.new((startX + out * NEWEL + glassEnd.X) / 2, y + glassH / 2, z), M.Glass, GLASS, {
				Transparency = 0.7,
				Reflectance = 0.25,
				CastShadow = false,
				Variant = false,
			})
			deco("NewelRail", Vector3.new(NEWEL, 0.38, 0.38), CFrame.new(startX + out * NEWEL / 2, railY, z), M.Rubber, rubber, {
				Shape = Enum.PartType.Cylinder,
				Variant = false,
			})
			-- Codo entre el tramo inclinado y el horizontal, y la curva del final (el
			-- pasamanos da la vuelta y vuelve por dentro)
			deco("NewelElbow", Vector3.new(0.4, 0.4, 0.4), CFrame.new(startX, railY, z), M.Rubber, rubber, { Shape = Enum.PartType.Ball, Variant = false })
			deco("NewelCurve", Vector3.new(0.38, 0.85, 0.85), CFrame.new(startX + out * NEWEL, railY - 0.24, z) * CFrame.Angles(0, math.rad(90), 0), M.Rubber, rubber, {
				Shape = Enum.PartType.Cylinder,
				Variant = false,
			})
			deco("NewelBase", Vector3.new(NEWEL + 0.4, 0.5, 0.6), CFrame.new(startX + out * NEWEL / 2, y + 0.25, z), M.Metal, STEEL)
		end
		deco("CombPlate", Vector3.new(0.35, 0.06, W - 0.4), CFrame.new(endX + out * 0.2, y + 0.06, zc), M.SmoothPlastic, Color3.fromRGB(245, 200, 30), { Variant = false })
		deco("LandingPlate", Vector3.new(2.5, 0.08, W), CFrame.new(endX + out * 1.25, y + 0.04, zc), M.DiamondPlate, STEEL)
	end
	local signCF = CFrame.lookAt(Vector3.new(lowX - dirX * 3.2, Y0 + 2.4, zc), Vector3.new(lowX - dirX * 10, Y0 + 2.4, zc))
	local post = deco("EscalatorSign", Vector3.new(1.6, 0.8, 0.1), signCF, M.SmoothPlastic, DARK)
	litSign(post, if up then "▲ SUBE" else "▼ BAJA", if up then Color3.fromRGB(90, 230, 120) else Color3.fromRGB(255, 150, 70), Enum.Font.GothamBold, Enum.NormalId.Front)
	deco("EscalatorSignPost", Vector3.new(0.15, 2, 0.15), signCF * CFrame.new(0, -1.3, 0), M.Metal, STEEL)

	currentParent = previous
	tag(model, Tags.Escalator, {
		Surface = surface,
		Length = length,
		Spacing = spacing,
		Speed = if up then ESC_SPEED else -ESC_SPEED,
	})
	tag(model, Tags.FloorConnector, { Low = low, High = high, Width = W })
	return model
end

----------------------------------------------------------------------
-- Fuente con agua real (agua de Terrain dentro de un vaso hueco)
----------------------------------------------------------------------

local WATER_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"
local MIST_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"

local WATER_VARIANT = "Mall_FountainWater2" -- material de agua generado (MaterialService)

-- Lamina de agua (disco). spin = rad/s de giro en el cliente (WaterFX).
local function waterSheet(cf: CFrame, diameter: number, transparency: number, spin: number)
	local sheet = deco("WaterSurface", Vector3.new(0.12, diameter, diameter), cf * CFrame.Angles(0, 0, math.rad(90)), M.Glacier, Color3.fromRGB(110, 195, 210), {
		Shape = Enum.PartType.Cylinder,
		Transparency = transparency,
		Reflectance = 0.25,
		CastShadow = false,
		Variant = WATER_VARIANT,
	})
	sheet:SetAttribute("Spin", spin)
	CollectionService:AddTag(sheet, Tags.FountainWater)
	return sheet
end

-- Cortina de agua que cae desde el borde de un plato (anillo de particulas con gravedad).
local function waterCurtain(cf: CFrame, radius: number, rate: number)
	local ring = deco("WaterRing", Vector3.new(0.1, radius * 2, radius * 2), cf * CFrame.Angles(0, 0, math.rad(90)), M.SmoothPlastic, Color3.new(1, 1, 1), {
		Shape = Enum.PartType.Cylinder,
		Transparency = 1,
	})
	local fall = Instance.new("ParticleEmitter")
	fall.Name = "WaterFall"
	fall.Texture = WATER_TEXTURE
	fall.Shape = Enum.ParticleEmitterShape.Disc
	fall.ShapePartial = 0.92 -- solo el borde del disco
	fall.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	fall.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
	fall.Color = ColorSequence.new(Color3.fromRGB(210, 235, 250))
	fall.LightEmission = 0.15
	fall.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.22), NumberSequenceKeypoint.new(1, 0.12) })
	fall.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 0.85) })
	fall.Lifetime = NumberRange.new(0.5, 0.75)
	fall.Rate = rate
	fall.Speed = NumberRange.new(0.6, 1.2)
	fall.Acceleration = Vector3.new(0, -32, 0)
	fall.Parent = ring
	return ring
end

-- cx, cz en el suelo de la planta actual. radius = radio exterior del vaso.
-- tiers = platos escalonados en el centro (1 o 2).
local function fountain(cx: number, cz: number, radius: number, tiers: number, zoneName: string, withStatue: boolean?)
	local stone = Color3.fromRGB(236, 233, 226)
	local granite = Color3.fromRGB(85, 80, 78)
	local R = radius

	-- Pared circular del vaso (segmentos) con borde de granito para sentarse
	local segments = math.max(16, math.floor(R * 4))
	for i = 0, segments - 1 do
		local a = (i + 0.5) / segments * math.pi * 2
		local cf = at(cx + math.cos(a) * (R - 0.5), 1.1, cz + math.sin(a) * (R - 0.5)) * CFrame.Angles(0, -a - math.pi / 2, 0)
		local len = 2 * math.pi * R / segments + 0.12
		box("FountainWall", Vector3.new(len, 2.2, 1), cf, M.Marble, stone)
		deco("FountainLip", Vector3.new(len + 0.15, 0.3, 1.5), cf * CFrame.new(0, 1.25, 0), M.Granite, granite)
	end
	-- Fondo de azulejo azul (se ve a traves del agua) y monedas
	deco("FountainFloor", Vector3.new(0.3, (R - 1) * 2 + 0.2, (R - 1) * 2 + 0.2), at(cx, 0.15, cz) * CFrame.Angles(0, 0, math.rad(90)), M.CeramicTiles, Color3.fromRGB(45, 110, 140), {
		Shape = Enum.PartType.Cylinder,
		Variant = false,
	})
	for _ = 1, math.floor(R * 2) do
		local a, r = rng:NextNumber(0, math.pi * 2), rng:NextNumber(1.5, R - 1.5)
		deco("Coin", Vector3.new(0.06, 0.45, 0.45), at(cx + math.cos(a) * r, 0.33, cz + math.sin(a) * r) * CFrame.Angles(0, 0, math.rad(90)), M.Foil, if rng:NextNumber() < 0.6 then Color3.fromRGB(215, 175, 70) else Color3.fromRGB(190, 190, 195), {
			Shape = Enum.PartType.Cylinder,
			CastShadow = false,
		})
	end

	-- Agua: dos laminas con material de agua (ondas y causticas) que giran en sentidos
	-- opuestos en el cliente (WaterFX). (El agua de Terrain apaga la iluminacion en interiores.)
	local waterD = (R - 1) * 2 + 0.1
	waterSheet(at(cx, 1.15, cz), waterD, 0.55, -0.05)
	waterSheet(at(cx, 1.7, cz), waterD, 0.3, 0.08)

	-- Pedestal y platos escalonados, con su cortina de agua cada uno
	local bowlY = { 4.2, 7.4 }
	local bowlD = { R * 0.85, R * 0.5 }
	local top = 2
	for t = 1, math.clamp(tiers, 1, 2) do
		local y, d = bowlY[t], bowlD[t]
		box("FountainColumn", Vector3.new(y - top + 0.4, 1.4 - t * 0.3, 1.4 - t * 0.3), at(cx, (top + y) / 2, cz) * CFrame.Angles(0, 0, math.rad(90)), M.Marble, stone, {
			Shape = Enum.PartType.Cylinder,
		})
		box("FountainBowl", Vector3.new(0.7, d, d), at(cx, y, cz) * CFrame.Angles(0, 0, math.rad(90)), M.Marble, stone, {
			Shape = Enum.PartType.Cylinder,
		})
		deco("FountainBowlUnder", Vector3.new(0.5, d * 0.7, d * 0.7), at(cx, y - 0.5, cz) * CFrame.Angles(0, 0, math.rad(90)), M.Marble, stone, {
			Shape = Enum.PartType.Cylinder,
		})
		waterSheet(at(cx, y + 0.33, cz), d - 0.5, 0.25, 0.15 * (if t == 1 then 1 else -1))
		waterCurtain(at(cx, y + 0.3, cz), d / 2 + 0.05, 140 - t * 40)
		top = y
	end
	-- Remate: la Estatua (la entidad es este mismo modelo) o una bola de marmol.
	-- Con estatua, el chorro sale de entre sus manos.
	local jetY = top + 1
	if withStatue then
		local statue = EntityModels.statue()
		statue.Name = "FountainStatue"
		EntityModels.placeAt(statue, at(cx, top + 0.35, cz) * CFrame.Angles(0, math.rad(90), 0), currentParent)
		tag(statue, Tags.FountainStatue)
		jetY = top + 0.35 + EntityModels.STATUE_HANDS_Y + 0.3
	else
		deco("FountainFinial", Vector3.new(0.7, 0.7, 0.7), at(cx, top + 0.7, cz), M.Marble, stone, { Shape = Enum.PartType.Ball })
	end

	-- Chorro central
	local jet = deco("FountainJet", Vector3.new(0.4, 0.4, 0.4), at(cx, jetY, cz), M.SmoothPlastic, Color3.new(1, 1, 1), { Transparency = 1 })
	local water = Instance.new("ParticleEmitter")
	water.Name = "Water"
	water.Texture = WATER_TEXTURE
	water.Color = ColorSequence.new(Color3.fromRGB(210, 232, 245))
	water.LightEmission = 0.1
	water.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 0.1) })
	water.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
	water.Lifetime = NumberRange.new(0.8, 1.1)
	water.Rate = 120
	water.Speed = NumberRange.new(6, 8)
	water.SpreadAngle = Vector2.new(10, 10)
	water.Acceleration = Vector3.new(0, -24, 0)
	water.EmissionDirection = Enum.NormalId.Top
	water.Parent = jet

	-- Bruma donde cae el agua y luces bajo el agua
	local mistPart = deco("FountainMist", Vector3.new(0.1, bowlD[1], bowlD[1]), at(cx, 1.8, cz) * CFrame.Angles(0, 0, math.rad(90)), M.SmoothPlastic, Color3.new(1, 1, 1), {
		Shape = Enum.PartType.Cylinder,
		Transparency = 1,
	})
	local mist = Instance.new("ParticleEmitter")
	mist.Texture = MIST_TEXTURE
	mist.Shape = Enum.ParticleEmitterShape.Disc
	mist.Color = ColorSequence.new(Color3.fromRGB(220, 235, 245))
	mist.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1.6) })
	mist.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.85), NumberSequenceKeypoint.new(1, 1) })
	mist.Lifetime = NumberRange.new(0.8, 1.4)
	mist.Rate = 25
	mist.Speed = NumberRange.new(0.3, 0.8)
	mist.EmissionDirection = Enum.NormalId.Top
	mist.Parent = mistPart
	-- Focos bajo el agua (solo uno emite luz real; los demas son el brillo del foco)
	local lightsCount = if R > 6 then 3 else 1
	for k = 0, 2 do
		local a = k * math.pi * 2 / 3
		local glowPart = deco("FountainGlow", Vector3.new(0.4, 0.2, 0.4), at(cx + math.cos(a) * (R - 2), 0.4, cz + math.sin(a) * (R - 2)), M.Neon, Color3.fromRGB(150, 210, 255), {
			CastShadow = false,
		})
		if k < lightsCount then
			local light = Instance.new("SpotLight")
			light.Face = Enum.NormalId.Top
			light.Angle = 70
			light.Range = 12
			light.Brightness = 1.2
			light.Color = Color3.fromRGB(110, 190, 255)
			light.Parent = glowPart
			-- Titila como la luz a traves del agua (WaterFX)
			glowPart:SetAttribute("Shimmer", true)
			CollectionService:AddTag(glowPart, Tags.FountainWater)
		end
		tag(glowPart, Tags.Light, { Zone = zoneName })
	end
end

----------------------------------------------------------------------
-- Galeria (atrio) - planta baja
----------------------------------------------------------------------

local function buildGallery()
	folder("Galeria")
	levelY = 0

	zone("Galería Oeste", -120, 0, -20, 20, F2 - 1)
	zone("Galería Este", 0, 120, -20, 20, F2 - 1)

	-- Suelo de marmol con franja central de granito
	slab("Floor", -120, 120, -20, 20, 0, M.Marble, Color3.fromRGB(232, 228, 220))
	deco("Runner", Vector3.new(240, 0.05, 6), at(0, 0.02, 0), M.Granite, Color3.fromRGB(95, 90, 88))
	for _, z in { -17.5, 17.5 } do
		deco("Border", Vector3.new(240, 0.05, 1.2), at(0, 0.02, z), M.Granite, Color3.fromRGB(95, 90, 88))
	end

	-- Columnas: entre tiendas (todo el alto) y en el borde del atrio (sostienen los pasillos)
	for x = -120, 120, 48 do
		for _, z in { -19, 19 } do
			column(x, z, GALLERY_TOP, 2.6)
		end
	end
	for _, x in { -108, -36, 36, 108 } do
		for _, z in { -VOID - 0.6, VOID + 0.6 } do
			column(x, z, F2 - 1, 2)
		end
	end

	-- Focos bajo los pasillos de la planta alta (iluminan las fachadas)
	for x = -108, 108, 24 do
		for _, z in { -16, -9.5, 9.5, 16 } do
			downlight(at(x, F2 - 1, z), if x < 0 then "Galería Oeste" else "Galería Este")
		end
	end
	-- Rejillas de ventilacion bajo los pasillos de arriba (el Ducto)
	for x = -96, 96, 48 do
		for _, z in { -16, 16 } do
			ceilingVent(at(x, F2 - 1, z))
		end
	end

	-- Fuente central con agua real y dos platos
	fountain(0, 0, 7.5, 2, "Galería Este", true)

	-- Escaleras mecanicas: un par en cada ala (sube por el sur del par, baja por el norte)
	escalator(-92, -61, -2.3, true)
	escalator(-92, -61, 2.3, false)
	escalator(92, 61, 2.3, true)
	escalator(92, 61, -2.3, false)

	-- Maceteros (mision Regar plantas: 3 por ala), bancas, papeleras
	for _, x in { -114, -44, -26 } do
		planter(x, 0, "Galería Oeste")
		planter(-x, 0, "Galería Este")
	end
	-- (lejos de las columnas del borde del atrio, en x = ±36 y ±108)
	for _, x in { -100, -44 } do
		bench(at(x, 0, -6.5))
		bench(at(x, 0, 6.5) * CFrame.Angles(0, math.pi, 0))
		bench(at(-x, 0, -6.5))
		bench(at(-x, 0, 6.5) * CFrame.Angles(0, math.pi, 0))
	end
	trashBin(at(-60, 0, -15), "Galería Oeste")
	trashBin(at(60, 0, 15), "Galería Este")

	-- Kioscos
	local kiosks = {
		{ X = -14, Z = -11, Name = "Helados Polar", Color = Color3.fromRGB(120, 200, 255) },
		{ X = 14, Z = 11, Name = "Fundas y Más", Color = Color3.fromRGB(255, 120, 80) },
	}
	for _, k in kiosks do
		local x, kz = k.X, k.Z
		box("Kiosk", Vector3.new(8, 3.6, 4), at(x, 1.8, kz), M.Wood, Color3.fromRGB(235, 230, 220))
		deco("KioskTop", Vector3.new(8.4, 0.2, 4.4), at(x, 3.7, kz), M.Marble, Color3.fromRGB(45, 44, 44))
		box("KioskRoof", Vector3.new(9, 0.4, 5), at(x, 8, kz), M.SmoothPlastic, k.Color)
		for _, ox in { -3.8, 3.8 } do
			box("KioskPost", Vector3.new(0.3, 4.4, 0.3), at(x + ox, 5.8, kz), M.Metal, METAL)
		end
		local kioskSign = box("KioskSign", Vector3.new(8, 1.4, 0.2), at(x, 9, kz), M.SmoothPlastic, DARK, { CanCollide = false })
		litSign(kioskSign, k.Name, k.Color, Enum.Font.FredokaOne, if kz < 0 then Enum.NormalId.Back else Enum.NormalId.Front)
	end

	wetFloorSign(at(-9, 0, 4) * CFrame.Angles(0, math.rad(30), 0))
	wetFloorSign(at(10, 0, -5) * CFrame.Angles(0, math.rad(-60), 0))
	directoryTotem(at(-100, 0, 11), 1, true)
	directoryTotem(at(100, 0, -11) * CFrame.Angles(0, math.pi, 0), 1, true)

	-- Puntos de mision
	electricPanel(at(-110, 3, 18.4), "Galería Oeste")
	electricPanel(at(110, 3, -18.4) * CFrame.Angles(0, math.pi, 0), "Galería Este")
	for _, p in { { -84, -10 }, { -40, 13 }, { 30, -13 }, { 100, 10 } } do
		spot(p[1], p[2], "CleanSpill", if p[1] < 0 then "Galería Oeste" else "Galería Este")
	end
	spot(-60, -13, "TakeOutTrash", "Galería Oeste")
	spot(60, 13, "TakeOutTrash", "Galería Este")
	spot(-84, -8.5, "LostItem", "Galería Oeste")
	spot(84, 8.5, "LostItem", "Galería Este")
	spot(-60, 8, "WaterPlants", "Galería Oeste")
	spot(60, -8, "WaterPlants", "Galería Este")
	spot(-20, 0, "LockDoors", "Galería Oeste")
	spot(20, 0, "LockDoors", "Galería Este")
	spot(-24, 3, "ResetRegisters", "Galería Oeste")
	spot(24, -3, "ResetRegisters", "Galería Este")
	spot(-24, -3, "TurnOffDisplays", "Galería Oeste")
	spot(24, 3, "TurnOffDisplays", "Galería Este")
	patrolClock(-75, 12, "Galería Oeste")
	patrolClock(75, -12, "Galería Este")
	spot(-28, 3, "EmptyBins", "Galería Oeste")
	spot(28, -3, "EmptyBins", "Galería Este")
	spot(-14, -15, "CheckExtinguishers", "Planta baja")
	-- Extintores y telefonos en las columnas de las fachadas (cara hacia el pasillo)
	wallExtinguisher(at(-72, 0, 17.7), "Planta baja")
	wallExtinguisher(at(72, 0, -17.7) * CFrame.Angles(0, math.pi, 0), "Planta baja")
	payPhone(at(-24, 0, -17.7) * CFrame.Angles(0, math.pi, 0), "Galería Oeste")
	payPhone(at(24, 0, 17.7), "Galería Este")

	-- Camaras bajo los pasillos altos
	camera(-118, 15.4, 18, -90, 0, -2)
	camera(-26, 15.4, -18, -54, 0, 2)
	camera(26, 15.4, 18, 54, 0, -2)
	camera(118, 15.4, -18, 90, 0, 2)

	currentParent = map
end

----------------------------------------------------------------------
-- Galeria - planta alta: pasillos, puentes, barandales, tragaluz
----------------------------------------------------------------------

local function buildUpperGallery()
	folder("GaleriaAlta")
	levelY = F2
	local W1, E1 = "Planta alta Oeste", "Planta alta Este"
	zone(W1, -120, 0, -20, 20, 18)
	zone(E1, 0, 120, -20, 20, 18)

	-- Pasillos (suelo) y puentes sobre el atrio
	for _, s in { -1, 1 } do
		local z1, z2 = math.min(s * VOID, s * 20), math.max(s * VOID, s * 20)
		slab("Walkway", -120, 120, z1, z2, 0, M.Marble, Color3.fromRGB(232, 228, 220))
		deco("WalkwayFascia", Vector3.new(240, 1.4, 0.4), at(0, -0.6, s * VOID), M.Plaster, Color3.fromRGB(240, 238, 232))
		deco("WalkwayBorder", Vector3.new(240, 0.05, 1), at(0, 0.02, s * (VOID + 1.2)), M.Granite, Color3.fromRGB(95, 90, 88))
		-- Techo de los pasillos (cara inferior a 18 sobre la planta alta)
		ceiling(-120, 120, z1, z2, 19)
		deco("CeilingCove", Vector3.new(240, 1.2, 0.6), at(0, 17.4, s * (VOID + 0.3)), M.Plaster, WHITE)
	end
	for _, bx in { -57, 57 } do
		slab("Bridge", bx - 4, bx + 4, -VOID, VOID, 0, M.Marble, Color3.fromRGB(232, 228, 220))
		for _, ex in { bx - 4, bx + 4 } do
			deco("BridgeFascia", Vector3.new(0.4, 1.4, VOID * 2), at(ex, -0.6, 0), M.Plaster, Color3.fromRGB(240, 238, 232))
		end
	end

	-- Barandales (con huecos donde estan los puentes y donde llegan las escaleras)
	for _, s in { -1, 1 } do
		local z = s * VOID
		railing(Vector3.new(-120, 0, z), Vector3.new(-61, 0, z))
		railing(Vector3.new(-53, 0, z), Vector3.new(53, 0, z))
		railing(Vector3.new(61, 0, z), Vector3.new(120, 0, z))
	end
	-- Puente oeste: lado del atrio central (x=-53) cerrado; lado de las escaleras (x=-61) abierto en el centro
	railing(Vector3.new(-53, 0, -VOID), Vector3.new(-53, 0, VOID))
	railing(Vector3.new(-61, 0, -VOID), Vector3.new(-61, 0, -5))
	railing(Vector3.new(-61, 0, 5), Vector3.new(-61, 0, VOID))
	railing(Vector3.new(53, 0, -VOID), Vector3.new(53, 0, VOID))
	railing(Vector3.new(61, 0, -VOID), Vector3.new(61, 0, -5))
	railing(Vector3.new(61, 0, 5), Vector3.new(61, 0, VOID))

	-- Tragaluz abovedado sobre el atrio
	local paneLen = VOID / math.cos(math.rad(25))
	local rise = VOID * math.tan(math.rad(25))
	for _, side in { -1, 1 } do
		box("Skylight", Vector3.new(240, 0.3, paneLen), at(0, 18 + rise / 2, side * VOID / 2) * CFrame.Angles(math.rad(side * 25), 0, 0), M.Glass, Color3.fromRGB(30, 42, 66), {
			Transparency = 0.5,
			Reflectance = 0.25,
			CastShadow = false,
			Variant = false,
		})
		for x = -114, 114, 12 do
			deco("SkylightRib", Vector3.new(0.4, 0.5, paneLen + 0.2), at(x, 18 + rise / 2 - 0.15, side * VOID / 2) * CFrame.Angles(math.rad(side * 25), 0, 0), M.Metal, Color3.fromRGB(235, 235, 235))
		end
	end
	deco("SkylightRidge", Vector3.new(240, 0.5, 0.6), at(0, 18 + rise, 0), M.Metal, Color3.fromRGB(235, 235, 235))

	-- Colgantes en el atrio (sobre la fuente y los puentes) y paneles en los pasillos
	local i = 0
	for x = -108, 108, 24 do
		i += 1
		pendant(x, if i % 2 == 0 then 2.5 else -2.5, 18.6, 9.5, if x < 0 then W1 else E1)
	end
	for x = -108, 108, 24 do
		for _, z in { -16, -9.5, 9.5, 16 } do
			ceilingPanel(at(x, 18, z), if x < 0 then W1 else E1, Vector2.new(5, 2.4), 22, 1.4)
		end
	end
	for x = -96, 96, 48 do
		for _, z in { -16, 16 } do
			ceilingVent(at(x, 18, z))
		end
	end
	for _, bx in { -57, 57 } do
		downlight(at(bx, 18, 0), if bx < 0 then W1 else E1, 24, 1.4)
	end

	-- Maceteros estrechos junto al barandal (3 por ala), papeleras y bancos
	for _, p in { { -110, 7.8 }, { -80, -7.8 }, { -30, 7.8 } } do
		planter(p[1], p[2], W1, true)
		planter(-p[1], -p[2], E1, true)
	end
	trashBin(at(-70, 0, -18), W1)
	trashBin(at(70, 0, 18), E1)
	-- Directorios de la planta alta (junto a las fachadas)
	directoryTotem(at(-114, 0, 18.4), 2)
	directoryTotem(at(114, 0, -18.4) * CFrame.Angles(0, math.pi, 0), 2)
	-- Bancos en el pasillo (los puentes ahora son cortos: alli llegan las escaleras)
	for _, x in { -84, 84 } do
		-- De espaldas a las tiendas, mirando al atrio
		bench(at(x, 0, 17.4))
		bench(at(-x, 0, -17.4) * CFrame.Angles(0, math.pi, 0))
	end

	-- Puntos de mision de la planta alta
	-- (en las fachadas, no en los extremos: alli estan las puertas del cine y de los juegos)
	electricPanel(at(-110, 3, 18.4), W1)
	electricPanel(at(110, 3, -18.4) * CFrame.Angles(0, math.pi, 0), E1)
	for _, p in { { -90, 16 }, { -30, -16 }, { 40, 16 }, { 100, -16 } } do
		spot(p[1], p[2], "CleanSpill", if p[1] < 0 then W1 else E1)
	end
	spot(-70, -16, "TakeOutTrash", W1)
	spot(70, 16, "TakeOutTrash", E1)
	spot(-100, -16, "LostItem", W1)
	spot(80, 16, "LostItem", E1)
	spot(-60, 16, "WaterPlants", W1)
	spot(60, -16, "WaterPlants", E1)
	spot(-20, 16, "LockDoors", W1)
	spot(20, -16, "LockDoors", E1)
	spot(-24, 17, "ResetRegisters", W1)
	spot(24, -17, "ResetRegisters", E1)
	spot(-16, 17, "TurnOffDisplays", W1)
	spot(16, -17, "TurnOffDisplays", E1)
	patrolClock(-45, 16.5, W1)
	patrolClock(45, -16.5, E1)
	spot(-28, 17, "EmptyBins", W1)
	spot(28, -17, "EmptyBins", E1)
	spot(-14, -16, "CheckExtinguishers", "Planta alta")
	wallExtinguisher(at(-72, 0, 17.7), "Planta alta")
	wallExtinguisher(at(72, 0, -17.7) * CFrame.Angles(0, math.pi, 0), "Planta alta")

	-- Camaras de la planta alta (miran a traves del atrio)
	camera(-118, 15.4, 18.6, -80, 0, -15)
	camera(-30, 15.4, -18.6, -60, 0, 15) -- (no en x = 0: alli se abren los pasajes de las alas)
	camera(30, 15.4, 18.6, 60, 0, -15)
	camera(118, 15.4, -18.6, 80, 0, 15)

	levelY = 0
	currentParent = map
end

----------------------------------------------------------------------
-- Envolvente exterior (las dos plantas)
----------------------------------------------------------------------

local function buildShell()
	folder("Fachada")
	levelY = 0
	local top = GALLERY_TOP + 4
	wall(Vector3.new(-180.5, 0, -71), Vector3.new(-180.5, 0, 111), top)
	wall(Vector3.new(180.5, 0, -71), Vector3.new(180.5, 0, 111), top, {
		Openings = { { From = 57, To = 85, Height = 14 } }, -- puertas de vidrio (z -14..14)
	})
	-- Muro sur: abierto en x -24..24 (pasillo del Ala Sur, las dos plantas)
	wall(Vector3.new(-180, 0, -70.5), Vector3.new(180, 0, -70.5), top, {
		Openings = { { From = 180 - WING, To = 180 + WING, Height = top } },
	})
	-- Muro norte: abierto en x -24..24 (pasillo del Ala Norte) y con las puertas de los
	-- pasillos de servicio del ala (planta baja: x -83..-75 al servicio, x 77..83 a seguridad)
	wall(Vector3.new(-180, 0, 110.5), Vector3.new(180, 0, 110.5), top, {
		Material = M.Concrete,
		Color = Color3.fromRGB(165, 165, 160),
		Openings = {
			{ From = 97, To = 105, Height = 9 },
			{ From = 180 - WING, To = 180 + WING, Height = top },
			{ From = 257, To = 263, Height = 9 },
		},
	})
	-- Revestimiento exterior de la fachada principal y franja de la planta alta
	deco("FacadeCladding", Vector3.new(0.4, top - 16, 182), at(181, 16 + (top - 16) / 2, 20), M.Concrete, Color3.fromRGB(70, 72, 78))
	deco("FacadeBand", Vector3.new(0.6, 1.2, 182), at(181.1, 16, 20), M.Metal, STEEL)
	currentParent = map
end

----------------------------------------------------------------------
-- Patio de comidas (planta baja, oeste)
----------------------------------------------------------------------

-- Tablero de menu iluminado: titulo y lista de platos con precio (cara `face` de part).
local function menuBoard(part: BasePart, face: Enum.NormalId, title: string, items: { { string } }, accent: Color3)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.LightInfluence = 0
	gui.Brightness = 1.6
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 60
	local root = Instance.new("Frame")
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundColor3 = Color3.fromRGB(18, 14, 12)
	root.BorderSizePixel = 0
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(150, 150, 150))
	grad.Rotation = 90
	grad.Parent = root
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0.03, 0)
	layout.Parent = root
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0.06, 0)
	padding.PaddingRight = UDim.new(0.06, 0)
	padding.PaddingTop = UDim.new(0.05, 0)
	padding.Parent = root
	local header = Instance.new("TextLabel")
	header.Size = UDim2.fromScale(1, 0.2)
	header.BackgroundTransparency = 1
	header.Font = Enum.Font.GothamBlack
	header.TextScaled = true
	header.TextColor3 = accent
	header.Text = title
	header.LayoutOrder = 0
	header.Parent = root
	for i, item in items do
		local row = Instance.new("Frame")
		row.Size = UDim2.fromScale(1, 0.15)
		row.BackgroundTransparency = 1
		row.LayoutOrder = i
		local itemName = Instance.new("TextLabel")
		itemName.Size = UDim2.fromScale(0.7, 1)
		itemName.BackgroundTransparency = 1
		itemName.Font = Enum.Font.GothamBold
		itemName.TextScaled = true
		itemName.TextXAlignment = Enum.TextXAlignment.Left
		itemName.TextColor3 = Color3.fromRGB(245, 240, 230)
		itemName.Text = item[1]
		itemName.Parent = row
		local price = Instance.new("TextLabel")
		price.Size = UDim2.fromScale(0.3, 1)
		price.Position = UDim2.fromScale(0.7, 0)
		price.BackgroundTransparency = 1
		price.Font = Enum.Font.GothamBlack
		price.TextScaled = true
		price.TextXAlignment = Enum.TextXAlignment.Right
		price.TextColor3 = accent
		price.Text = item[2]
		price.Parent = row
		row.Parent = root
	end
	root.Parent = gui
	gui.Parent = part
	return gui
end

-- Puesto de comida rapida contra la pared oeste (frente hacia +X, hacia las mesas).
-- s = { Z, Name, Color, Kitchen (modelo de cocina), Menus = { {titulo, {{plato, precio}...}}, x2 }, Promo }
local function foodStall(s, zoneName: string)
	local z0 = s.Z
	local color: Color3 = s.Color
	local dark = color:Lerp(Color3.fromRGB(15, 15, 18), 0.6)
	local FACE_X = CFrame.Angles(0, math.rad(-90), 0) -- frente (-Z) hacia +X

	-- Pared del fondo alicatada con franja de color, suelo de cocina y tabiques laterales
	box("StallBack", Vector3.new(0.5, 12, 18), at(-179.6, 6, z0), M.CeramicTiles, Color3.fromRGB(235, 235, 232), { Variant = false })
	deco("StallBackStripe", Vector3.new(0.55, 1.2, 18), at(-179.6, 4.6, z0), M.CeramicTiles, color, { Variant = false })
	deco("KitchenFloor", Vector3.new(10, 0.05, 17.5), at(-175, 0.03, z0), M.CeramicTiles, Color3.fromRGB(120, 45, 40), { Variant = false })
	for _, dz in { -9, 9 } do
		box("StallPartition", Vector3.new(11, 12, 0.6), at(-174.5, 6, z0 + dz), M.Plaster, dark)
		deco("StallPartitionEdge", Vector3.new(0.6, 12, 0.8), at(-169.1, 6, z0 + dz), M.Metal, STEEL)
	end

	-- Cocina (modelo 3D) o version de piezas
	local placed
	if s.Kitchen == "PizzaOven" then
		placed = prop("PizzaOven", at(-177.4, 0, z0 - 3.8) * FACE_X) ~= nil
		prop("KitchenLine", at(-178.2, 0, z0 + 4.4) * FACE_X)
	else
		placed = propRow("KitchenLine", at(-178.2, 0, z0) * FACE_X, 15, 7.5)
	end
	if not placed then
		box("StallKitchen", Vector3.new(3, 4, 14), at(-177.5, 2, z0), M.Metal, Color3.fromRGB(190, 192, 196))
		deco("Hood", Vector3.new(3.4, 1.4, 14), at(-177.6, 8.6, z0), M.Metal, Color3.fromRGB(200, 202, 206))
	end

	-- Mostrador: base del color de la marca con logo luminoso, encimera, mampara de vidrio
	box("StallCounter", Vector3.new(3, 3.6, 16), at(-172, 1.8, z0), M.SmoothPlastic, dark)
	deco("StallCounterTop", Vector3.new(3.4, 0.25, 16.4), at(-172, 3.72, z0), M.Granite, Color3.fromRGB(45, 43, 42))
	local logo = deco("CounterLogo", Vector3.new(6, 1.6, 0.06), at(-170.47, 2, z0) * FACE_X, M.SmoothPlastic, dark)
	litSign(logo, s.Name, color, Enum.Font.FredokaOne, Enum.NormalId.Front)
	deco("SneezeGuard", Vector3.new(0.08, 1.4, 14), at(-171.2, 4.75, z0), M.Glass, Color3.fromRGB(210, 230, 235), {
		Transparency = 0.7,
		Reflectance = 0.2,
		Variant = false,
	})
	for _, dz in { -7, 0, 7 } do
		deco("GuardPost", Vector3.new(0.12, 1.5, 0.12), at(-171.2, 4.6, z0 + dz), M.Metal, STEEL)
	end
	-- Sobre el mostrador: caja, maquina de refrescos, servilleteros, bandejas
	propOr("CashRegister", at(-172.4, 3.85, z0 + 5.5) * FACE_X, function(cf)
		box("Register", Vector3.new(1.4, 1, 1.2), cf * CFrame.new(0, 0.5, 0), M.Metal, DARK)
	end, false)
	propOr("SodaFountain", at(-172.6, 3.85, z0 - 5.5) * FACE_X, function(cf)
		box("SodaDispenser", Vector3.new(2, 2.4, 1.6), cf * CFrame.new(0, 1.2, 0), M.Metal, STEEL)
	end, false)
	for k = 0, 3 do
		deco("TrayStack", Vector3.new(1.4, 0.08, 2), at(-171.6, 3.88 + k * 0.09, z0 + 1.5), M.Plastic, color:Lerp(DARK, 0.3))
	end
	deco("NapkinHolder", Vector3.new(0.5, 0.6, 0.8), at(-171.5, 4.15, z0 - 1.6), M.Metal, STEEL)
	if s.Name == "Café Central" then
		propOr("EspressoMachine", at(-172.6, 3.85, z0 - 1.8) * FACE_X, function() end, false)
	end

	-- Fachada superior: rotulo luminoso, tira de neon y persiana enrollada (abierta)
	local fascia = box("StallFascia", Vector3.new(1, 2.8, 18), at(-169.6, 11.4, z0), M.SmoothPlastic, dark, { CanCollide = false })
	litSign(fascia, s.Name, color, Enum.Font.FredokaOne, Enum.NormalId.Right)
	neonStrip(Vector3.new(0.12, 0.12, 17.6), at(-169.05, 9.95, z0), color, zoneName)
	deco("ShutterBox", Vector3.new(0.9, 0.9, 16.4), at(-170.3, 9.4, z0), M.Metal, STEEL)

	-- Menus iluminados colgados sobre la cocina
	for i, m in s.Menus do
		local mz = z0 + (if i == 1 then -5 elseif i == 2 then 0 else 5)
		local board = deco("MenuBoard", Vector3.new(0.2, 2.8, 4.6), at(-173.8, 8, mz), M.SmoothPlastic, Color3.fromRGB(18, 14, 12))
		if m.Promo then
			glowScreen(board, Enum.NormalId.Right, color, color:Lerp(Color3.new(0, 0, 0), 0.7), m.Promo)
		else
			menuBoard(board, Enum.NormalId.Right, m[1], m[2], color)
		end
		deco("MenuHanger", Vector3.new(0.08, 2.6, 0.08), at(-173.8, 10.7, mz), M.Metal, DARK)
	end

	-- Tres lamparas colgantes sobre el mostrador
	for _, dz in { -5, 0, 5 } do
		local lx, lz = -171.6, z0 + dz
		deco("PendantCable", Vector3.new(0.08, 5.2, 0.08), at(lx, FOOD_H - 2.6, lz), M.Metal, DARK)
		deco("PendantShade", Vector3.new(1.1, 1.4, 1.4), at(lx, FOOD_H - 5.4, lz) * CFrame.Angles(0, 0, math.rad(90)), M.Metal, color, {
			Shape = Enum.PartType.Cylinder,
		})
		local bulb = deco("PendantBulb", Vector3.new(0.5, 0.5, 0.5), at(lx, FOOD_H - 6, lz), M.Neon, Color3.fromRGB(255, 230, 190), {
			Shape = Enum.PartType.Ball,
			CastShadow = false,
		})
		-- Solo el colgante central ilumina (demasiadas luces juntas hacen que Roblox descarte algunas)
		if dz == 0 then
			local light = Instance.new("SpotLight")
			light.Face = Enum.NormalId.Bottom
			light.Angle = 120
			light.Range = 14
			light.Brightness = 1.4
			light.Color = Color3.fromRGB(255, 225, 185)
			light.Parent = bulb
		end
		tag(bulb, Tags.Light, { Zone = zoneName })
	end
end

local function buildFoodCourt()
	folder("PatioDeComidas")
	levelY = 0
	local Z = "Patio de comidas"
	zone(Z, -180, -120, -70, 70, FOOD_H)

	slab("Floor", -180, -120, -70, 70, 0, M.CeramicTiles, Color3.fromRGB(215, 200, 175))
	ceiling(-180, -120, -70, 70, FOOD_H + 1)

	-- Pared norte con puerta a la bodega; este abierta a la galeria (hasta el suelo de arriba)
	wall(Vector3.new(-180, 0, 70.5), Vector3.new(-120, 0, 70.5), FOOD_H, {
		Openings = { { From = 6, To = 18, Height = 10 } },
	})
	wall(Vector3.new(-120.5, 0, -70), Vector3.new(-120.5, 0, 70), F2, {
		Openings = { { From = 50, To = 90, Height = FOOD_H } },
	})

	-- Puestos de comida en la pared oeste
	local stalls = {
		{
			Z = -50, Name = "Tacos del Barrio", Color = Color3.fromRGB(240, 140, 40), Kitchen = "KitchenLine",
			Menus = {
				{ "TACOS", { { "Al pastor", "$25" }, { "Suadero", "$25" }, { "Campechano", "$28" }, { "Gringa", "$40" } } },
				{ Promo = "¡3 TACOS\n+ REFRESCO\n$75!" },
				{ "ANTOJITOS", { { "Burrito", "$45" }, { "Nachos", "$35" }, { "Quesadilla", "$30" }, { "Agua fresca", "$20" } } },
			},
		},
		{
			Z = -20, Name = "Pizza Nonna", Color = Color3.fromRGB(210, 50, 50), Kitchen = "PizzaOven",
			Menus = {
				{ "PIZZAS", { { "Margarita", "$60" }, { "Pepperoni", "$70" }, { "4 Quesos", "$75" }, { "Hawaiana", "$70" } } },
				{ Promo = "HORNO\nDE LEÑA" },
				{ "ITALIANO", { { "Calzone", "$55" }, { "Lasaña", "$65" }, { "Tiramisú", "$40" }, { "Refresco", "$20" } } },
			},
		},
		{
			Z = 20, Name = "Wok Dragón", Color = Color3.fromRGB(230, 190, 40), Kitchen = "KitchenLine",
			Menus = {
				{ "WOK", { { "Arroz frito", "$50" }, { "Pollo agridulce", "$65" }, { "Fideos wok", "$55" }, { "Res con brócoli", "$70" } } },
				{ Promo = "COMBO\nDRAGÓN\n$99" },
				{ "EXTRAS", { { "Rollitos", "$30" }, { "Wantán", "$35" }, { "Té helado", "$20" }, { "Galleta suerte", "$5" } } },
			},
		},
		{
			Z = 50, Name = "Café Central", Color = Color3.fromRGB(170, 115, 75), Kitchen = "KitchenLine",
			Menus = {
				{ "CAFÉ", { { "Espresso", "$20" }, { "Capuchino", "$30" }, { "Latte", "$32" }, { "Chocolate", "$28" } } },
				{ Promo = "RECIÉN\nHORNEADO" },
				{ "POSTRES", { { "Croissant", "$25" }, { "Cheesecake", "$40" }, { "Brownie", "$30" }, { "Muffin", "$25" } } },
			},
		},
	}
	for _, s in stalls do
		foodStall(s, Z)
	end

	-- Fuente pequeña en el centro, mesas alrededor y estacion de basura/reciclaje
	fountain(-149, 0, 4.5, 1, Z)
	for _, x in { -158, -140 } do
		for _, z in { -54, -36, -18, 18, 36, 54 } do
			propOr("FoodCourtTable", at(x, 0, z) * CFrame.Angles(0, math.rad(45), 0), function(cf)
				roundTable(cf, 4, Color3.fromRGB(200, 70, 60), 3.3)
			end)
			-- Donde puede quedar una bandeja olvidada (mision Recoger bandejas; la mision la
			-- apoya sobre la mesa que haya debajo)
			local traySpot = box("TraySpot", Vector3.new(1, 0.2, 1), at(x + 0.6, 3.3, z), M.SmoothPlastic, Color3.new(1, 1, 1), {
				Transparency = 1,
				CanCollide = false,
				CanQuery = false,
				CanTouch = false,
				Variant = false,
			})
			tag(traySpot, Tags.TraySpot)
		end
	end
	for _, z in { -27, 27 } do
		propOr("TrashStation", at(-124, 0, z) * CFrame.Angles(0, math.rad(90), 0), function(cf)
			for k = -1, 1 do
				box("Bin", Vector3.new(1.8, 3.6, 1.8), cf * CFrame.new(k * 2, 1.8, 0), M.Metal, ({ Color3.fromRGB(60, 60, 64), Color3.fromRGB(40, 110, 200), Color3.fromRGB(60, 160, 70) })[k + 2])
			end
		end)
		local trayBin = box("TrayBin", Vector3.new(2.4, 3.6, 6.4), at(-124, 1.8, z), M.SmoothPlastic, Color3.new(1, 1, 1), {
			Transparency = 1,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			Variant = false,
		})
		tag(trayBin, Tags.TrayBin)
	end
	spot(-149, -10, "ClearTrays", Z)
	patrolClock(-126, 56, Z)
	wallExtinguisher(at(-121, 0, 50) * CFrame.Angles(0, math.rad(90), 0), "Planta baja")
	payPhone(at(-121, 0, -40) * CFrame.Angles(0, math.rad(90), 0), Z)
	-- Plantas que separan la zona de mesas del pasillo
	for _, z in { -64, 64 } do
		planter(-138, z, Z)
	end
	for _, x in { -165, -138 } do
		for _, z in { -45, 0, 45 } do
			ceilingPanel(at(x, FOOD_H, z), Z, Vector2.new(8, 2.4), 30, 1.6)
		end
		for _, z in { -22.5, 22.5 } do
			ceilingPanel(at(x, FOOD_H, z), Z, Vector2.new(2.4, 2.4), 20, 0.9)
		end
	end

	-- Maquina barata (entre los puestos) y escondite
	vendingMachine(CFrame.lookAt(Vector3.new(-178, Y0 + 3.5, 0), Vector3.new(-170, Y0 + 3.5, 0)), "Cheap", Color3.fromRGB(180, 30, 35), "REFRESCOS")
	hidingSpot("Armario de limpieza", at(-177.8, 3.75, -66) * CFrame.Angles(0, math.rad(-90), 0), Vector3.new(4, 7.5, 3), M.Metal, Color3.fromRGB(90, 110, 80))
	propOr("JanitorCart", at(-128, 0, -66) * CFrame.Angles(0, math.rad(-90), 0), function() end)

	electricPanel(at(-121.4, 3, -64) * CFrame.Angles(0, math.rad(90), 0), Z)
	for _, p in { { -150, -27 }, { -130, 0 }, { -150, 45 } } do
		spot(p[1], p[2], "CleanSpill", Z)
	end
	spot(-166, -35, "TakeOutTrash", Z)
	spot(-166, 35, "TakeOutTrash", Z)
	spot(-158, -46, "LostItem", Z)
	spot(-140, 44, "LostItem", Z)
	enemySpawn(-150, -66)
	camera(-122, 14, 68, -150, 0, 40)

	currentParent = map
end

----------------------------------------------------------------------
-- Cine (planta alta, oeste): vestibulo y 2 salas
----------------------------------------------------------------------

local function cinemaHall(name: string, z1: number, z2: number, screenSide: number)
	-- screenSide = 1: pantalla al norte (z2); -1: al sur (z1)
	zone(name, -180, -120, z1, z2, STORE_H)
	slab("HallFloor", -180, -120, z1, z2, 0.02, M.Carpet, Color3.fromRGB(60, 22, 28), { CanCollide = false, Variant = false })
	local s = screenSide
	local screenZ = if s > 0 then z2 - 1.2 else z1 + 1.2
	local facing = CFrame.Angles(0, if s > 0 then 0 else math.pi, 0) -- frente (-Z) hacia las butacas
	local screen = box("CinemaScreen", Vector3.new(40, 12.5, 0.3), at(-150, 9.2, screenZ) * facing, M.SmoothPlastic, Color3.fromRGB(200, 205, 210))
	glowScreen(screen, Enum.NormalId.Front, Color3.fromRGB(40, 50, 70), Color3.fromRGB(10, 12, 18), nil)
	deco("ScreenFrame", Vector3.new(42, 14, 0.2), at(-150, 9.2, screenZ + s * 0.2) * facing, M.Fabric, Color3.fromRGB(15, 15, 18))
	-- Escenario bajo la pantalla
	box("Stage", Vector3.new(44, 1.2, 3), at(-150, 0.6, screenZ - s * 1.6), M.Wood, Color3.fromRGB(40, 22, 20))
	for _, sx in { -173, -127 } do
		deco("Curtain", Vector3.new(5, 15, 0.6), at(sx, 7.5, screenZ - screenSide * 0.4), M.Fabric, Color3.fromRGB(120, 20, 30))
	end
	-- Escondite: cortina lateral junto a la pantalla
	hidingSpot("Cortina", at(-176, 3.75, screenZ - screenSide * 2.6) * facing, Vector3.new(4, 7.5, 3), M.Fabric, Color3.fromRGB(110, 18, 28))

	-- Graderio (stadium seating): 5 filas, cada una 1.1 mas alta que la anterior.
	--   * Escalera central (x -153..-147) con peldaños de 0.55 (dos por fila).
	--   * Pasillos laterales a nivel del suelo (x -180..-176 y -124..-120) que unen la
	--     puerta del fondo con la zona de la pantalla.
	--   * Antepechos a los lados de las gradas y detras de la ultima fila.
	local ROWS, ROW_DEPTH, RISE = 5, 4.5, 1.1
	local carpet = Color3.fromRGB(70, 24, 30)
	local seatFacing = if s > 0 then CFrame.Angles(0, math.pi, 0) else CFrame.new()
	local function rowZ(k: number): number
		return screenZ - s * (14 + k * ROW_DEPTH)
	end
	for k = 0, ROWS - 1 do
		local z, h = rowZ(k), k * RISE
		if k > 0 then
			-- Plataforma de la fila (izquierda y derecha de la escalera)
			for _, side in { { -176, -153 }, { -147, -124 } } do
				local w = side[2] - side[1]
				local cx = (side[1] + side[2]) / 2
				box("Tier", Vector3.new(w, h, ROW_DEPTH), at(cx, h / 2, z), M.Carpet, carpet, { Variant = false })
				-- Tira de luz en el canto del escalon (hacia la pantalla)
				neonStrip(Vector3.new(w, 0.06, 0.08), at(cx, h - 0.08, z + s * (ROW_DEPTH / 2 + 0.03)), Color3.fromRGB(70, 120, 255), name)
			end
			-- Antepechos laterales (hacia los pasillos de los lados)
			for _, px in { -176.2, -123.8 } do
				box("TierParapet", Vector3.new(0.4, h + 3, ROW_DEPTH), at(px, (h + 3) / 2, z), M.Plaster, Color3.fromRGB(55, 28, 32))
			end
			-- Escalera central: dos peldaños por fila
			for half = 0, 1 do
				local stepH = h - RISE / 2 + half * RISE / 2
				local stepZ = z + s * (ROW_DEPTH / 4) - s * half * (ROW_DEPTH / 2)
				box("AisleStep", Vector3.new(6, stepH, ROW_DEPTH / 2), at(-150, stepH / 2, stepZ), M.Carpet, carpet, { Variant = false })
				neonStrip(Vector3.new(6, 0.06, 0.1), at(-150, stepH - 0.06, stepZ + s * (ROW_DEPTH / 4 - 0.05)), Color3.fromRGB(70, 120, 255), name)
			end
		end
		-- Butacas (3 bloques por lado, mirando a la pantalla)
		for _, x in { -172.4, -165.8, -159.2, -140.8, -134.2, -127.6 } do
			propOr("CinemaSeats", at(x, h, z - s * 0.4) * seatFacing, function(cf)
				for j = -1, 1 do
					box("CinemaSeat", Vector3.new(2, 1.6, 2), cf * CFrame.new(j * 2.1, 0.8, 0), M.Fabric, Color3.fromRGB(140, 20, 30))
					deco("CinemaSeatBack", Vector3.new(2, 2.6, 0.5), cf * CFrame.new(j * 2.1, 2.4, 1), M.Fabric, Color3.fromRGB(140, 20, 30))
				end
			end)
		end
	end
	-- Antepecho detras de la ultima fila (da al pasillo del fondo, a nivel del suelo)
	local topH = (ROWS - 1) * RISE
	local backEdge = rowZ(ROWS - 1) - s * (ROW_DEPTH / 2 + 0.2)
	box("BackParapet", Vector3.new(52, topH + 3, 0.4), at(-150, (topH + 3) / 2, backEdge), M.Plaster, Color3.fromRGB(55, 28, 32))
	deco("BackParapetRail", Vector3.new(52, 0.25, 0.6), at(-150, topH + 3.1, backEdge), M.Metal, STEEL)
	-- Luces de los pasillos laterales (en el suelo)
	for k = 0, ROWS - 1 do
		for _, x in { -178, -122 } do
			neonStrip(Vector3.new(0.6, 0.08, 0.3), at(x, 0.08, rowZ(k)), Color3.fromRGB(90, 150, 255), name)
		end
	end
	-- Apliques de pared (luz tenue de sala) y luz del proyector
	for _, z in { z1 + 12, (z1 + z2) / 2, z2 - 12 } do
		for _, x in { -179.3, -120.7 } do
			local sconce = deco("Sconce", Vector3.new(0.4, 1.2, 1.2), at(x, 9, z), M.Neon, Color3.fromRGB(255, 200, 150))
			local light = Instance.new("SpotLight")
			light.Face = Enum.NormalId.Top
			light.Range = 12
			light.Angle = 90
			light.Brightness = 0.8
			light.Color = Color3.fromRGB(255, 190, 140)
			light.Parent = sconce
			tag(sconce, Tags.Light, { Zone = name })
		end
	end
	-- Luces de limpieza (tenues): de noche la sala no esta del todo a oscuras
	for _, z in { z1 + 10, (z1 + z2) / 2, z2 - 10 } do
		for _, x in { -165, -135 } do
			ceilingPanel(at(x, STORE_H, z), name, Vector2.new(3, 3), 24, 0.9)
		end
	end
	local projector = deco("Projector", Vector3.new(1.4, 1, 1.4), at(-150, 14, screenZ - s * 37.4), M.Neon, Color3.fromRGB(200, 220, 255))
	CollectionService:AddTag(projector, Tags.Projector) -- (mision Apagar proyector; atributo Zone lo pone tag() abajo)
	-- Panel de la cabina, al fondo de la sala a nivel del suelo (mision Apagar proyector)
	local projectorPanel = box("ProjectorControl", Vector3.new(1.4, 1.8, 0.5), at(-179.4, 3.6, backEdge - s * 3) * CFrame.Angles(0, math.rad(-90), 0), M.Metal, Color3.fromRGB(50, 52, 58), {
		Variant = false,
	})
	local panelSign = deco("ProjectorSign", Vector3.new(1.6, 0.5, 0.06), at(-179.15, 5, backEdge - s * 3) * CFrame.Angles(0, math.rad(-90), 0), M.SmoothPlastic, DARK)
	litSign(panelSign, "PROYECTOR", Color3.fromRGB(200, 220, 255), Enum.Font.Code, Enum.NormalId.Front)
	tag(projectorPanel, Tags.MissionSpot, { MissionType = "TurnOffProjector", Zone = name })
	deco("ProjectionWindow", Vector3.new(3, 2, 0.1), at(-150, 14, screenZ - s * 38), M.Glass, Color3.fromRGB(30, 40, 60), { Transparency = 0.5 })
	local beam = Instance.new("SpotLight")
	beam.Face = if s > 0 then Enum.NormalId.Back else Enum.NormalId.Front
	beam.Range = 45
	beam.Angle = 30
	beam.Brightness = 1.2
	beam.Color = Color3.fromRGB(200, 220, 255)
	beam.Parent = projector
	tag(projector, Tags.Light, { Zone = name })

	-- Puntos de mision en zonas a nivel del suelo: delante de la pantalla, pasillo lateral
	-- y pasillo del fondo (las gradas quedan para esconderse y observar)
	electricPanel(at(-179.4, 3, screenZ - s * 8) * CFrame.Angles(0, math.rad(-90), 0), name)
	spot(-150, screenZ - s * 8, "CleanSpill", name)
	spot(-168, screenZ - s * 9, "LostItem", name)
	spot(-135, screenZ - s * 36.5, "TakeOutTrash", name)
	spot(-122, (rowZ(1) + rowZ(3)) / 2, "CleanSpill", name)
	enemySpawn(-150, screenZ - s * 7) -- delante de la pantalla
end

local function buildCinema()
	folder("Cine")
	levelY = F2
	local Z = "Cine"
	zone(Z, -180, -120, -30, 30, STORE_H)
	slab("Floor", -180, -120, -70, 70, 0, M.Carpet, Color3.fromRGB(70, 28, 34))
	ceiling(-180, -120, -70, 70, STORE_H + 1)

	-- Pared hacia el atrio (con entradas desde los pasillos altos) y separaciones de las salas
	wall(Vector3.new(-120.5, 0, -70), Vector3.new(-120.5, 0, 70), 18, {
		Openings = { { From = 50, To = 58, Height = 9 }, { From = 82, To = 90, Height = 9 } },
	})
	for _, z in { -30.5, 30.5 } do
		wall(Vector3.new(-180, 0, z), Vector3.new(-120, 0, z), STORE_H, {
			Openings = { { From = 44, To = 52, Height = 9 } },
			Color = Color3.fromRGB(60, 30, 36),
		})
		local doorSign = deco("SalaSign", Vector3.new(6, 1.2, 0.2), at(-132, 10.4, z + (if z < 0 then 0.65 else -0.65)), M.SmoothPlastic, DARK)
		litSign(doorSign, if z > 0 then "SALA 1" else "SALA 2", Color3.fromRGB(255, 210, 120), Enum.Font.GothamBlack, if z > 0 then Enum.NormalId.Front else Enum.NormalId.Back)
	end
	wall(Vector3.new(-180, 0, 70.5), Vector3.new(-120, 0, 70.5), STORE_H, {
		Openings = { { From = 30, To = 38, Height = 9 } }, -- salida de emergencia al almacen alto
	})
	exitSign(at(-146, 10.2, 69.8))

	-- Cartel grande hacia el atrio
	local atriumSign = deco("CinemaSign", Vector3.new(0.4, 4, 22), at(-119.8, 11, 0), M.SmoothPlastic, Color3.fromRGB(20, 10, 14))
	litSign(atriumSign, "CINE LUNA", Color3.fromRGB(255, 200, 90), Enum.Font.Fondamento, Enum.NormalId.Right)
	neonStrip(Vector3.new(0.2, 0.2, 22), at(-119.5, 8.8, 0), Color3.fromRGB(255, 180, 60), Z)
	neonStrip(Vector3.new(0.2, 0.2, 22), at(-119.5, 13.2, 0), Color3.fromRGB(255, 180, 60), Z)

	-- Vestibulo: taquilla, dulceria con palomitas, carteleras luminosas
	box("ConcessionCounter", Vector3.new(4, 3.6, 30), at(-170, 1.8, 0), M.Wood, Color3.fromRGB(90, 30, 35))
	deco("ConcessionTop", Vector3.new(4.4, 0.2, 30.4), at(-170, 3.7, 0), M.Marble, Color3.fromRGB(40, 38, 38))
	for _, z in { -8, 8 } do
		propOr("PopcornMachine", at(-170, 3.8, z) * CFrame.Angles(0, math.rad(-90), 0), function(cf)
			box("Popcorn", Vector3.new(2.4, 3, 2), cf * CFrame.new(0, 1.5, 0), M.Glass, Color3.fromRGB(255, 220, 120), { Transparency = 0.3 })
		end, false)
	end
	local menu = deco("ConcessionMenu", Vector3.new(0.3, 4, 24), at(-179.3, 9, 0), M.SmoothPlastic, DARK)
	glowScreen(menu, Enum.NormalId.Right, Color3.fromRGB(150, 30, 40), Color3.fromRGB(40, 10, 15), "PALOMITAS · REFRESCOS · NACHOS")
	for i, z in { -26, -6, 6, 26 } do
		lightbox(at(-121.2, 6, z) * CFrame.Angles(0, math.rad(90), 0), 5, 7, ({ "ESTRENO", "TERROR\nEN EL MALL", "PRÓXIMAMENTE", "3D" })[i], Color3.fromRGB(200, 60, 60):Lerp(Color3.fromRGB(60, 90, 200), (i - 1) / 3), Z)
	end
	-- Postes con cordon
	for k = 0, 4 do
		local z = -12 + k * 6
		box("Stanchion", Vector3.new(0.3, 3, 0.3), at(-150, 1.5, z), M.Metal, Color3.fromRGB(200, 170, 80))
		if k < 4 then
			deco("Rope", Vector3.new(0.2, 0.2, 6), at(-150, 2.7, z + 3), M.Fabric, Color3.fromRGB(130, 20, 30))
		end
	end
	for _, z in { -20, 0, 20 } do
		for _, x in { -158, -136 } do
			ceilingPanel(at(x, STORE_H, z), Z, Vector2.new(4, 4), 26, 1.3)
		end
	end
	vendingMachine(CFrame.lookAt(Vector3.new(-178, Y0 + F2 + 3.5, -24), Vector3.new(-170, Y0 + F2 + 3.5, -24)), "Cheap", Color3.fromRGB(180, 30, 35), "REFRESCOS")
	electricPanel(at(-121.4, 3, -21) * CFrame.Angles(0, math.rad(90), 0), Z)
	spot(-145, 6, "CleanSpill", Z)
	spot(-160, -20, "TakeOutTrash", Z)
	spot(-140, 24, "LostItem", Z)
	camera(-178, 14, -28, -150, 0, 0)

	cinemaHall("Sala 1", 30, 70, 1)
	cinemaHall("Sala 2", -70, -30, -1)

	levelY = 0
	currentParent = map
end

----------------------------------------------------------------------
-- Entrada (planta baja, este)
----------------------------------------------------------------------

local function buildEntrance()
	folder("Entrada")
	levelY = 0
	local Z = "Entrada"
	zone(Z, 120, 180, -70, 70, ENTRY_H)

	slab("Floor", 120, 180, -70, 70, 0, M.Marble, Color3.fromRGB(225, 220, 212))
	deco("Inlay", Vector3.new(0.05, 16, 16), at(150, 0.02, 0) * CFrame.Angles(0, 0, math.rad(90)), M.Granite, Color3.fromRGB(80, 75, 72), {
		Shape = Enum.PartType.Cylinder,
	})
	ceiling(120, 180, -70, 70, ENTRY_H + 1)

	wall(Vector3.new(120.5, 0, -70), Vector3.new(120.5, 0, 70), F2, {
		Openings = { { From = 50, To = 90, Height = ENTRY_H } },
	})
	wall(Vector3.new(120, 0, 70.5), Vector3.new(180, 0, 70.5), ENTRY_H, {
		Openings = { { From = 4, To = 16, Height = 10 } }, -- puerta a servicio (x 124..136)
	})
	-- Puertas de vidrio automaticas, ABIERTAS: se sale al estacionamiento (buildParking).
	-- Las hojas quedan recogidas a los lados del hueco (z -14..14), por dentro del muro.
	for _, s in { -1, 1 } do
		for k, x in { 179.6, 179.1 } do
			local z = s * (14 + 3.3 + (k - 1) * 0.4)
			box("EntranceDoor", Vector3.new(0.4, 13.4, 6.6), at(x, 6.8, z), M.Glass, Color3.fromRGB(150, 180, 200), {
				Transparency = 0.6,
				Reflectance = 0.2,
				Variant = false,
			})
		end
		box("DoorFrame", Vector3.new(0.6, 13.6, 0.4), at(180.5, 6.8, s * 14), M.Metal, DARK)
	end
	box("DoorHeader", Vector3.new(0.8, 0.6, 28), at(180.5, 13.8, 0), M.Metal, DARK)
	local mallSign = box("MallSign", Vector3.new(0.4, 5, 30), at(181.4, 22, 0), M.SmoothPlastic, Color3.fromRGB(20, 20, 26), { CanCollide = false })
	litSign(mallSign, "PLAZA LUNA", Color3.fromRGB(255, 215, 120), Enum.Font.Fondamento, Enum.NormalId.Right)
	deco("EntryMat", Vector3.new(10, 0.06, 26), at(174, 0.03, 0), M.Carpet, Color3.fromRGB(40, 40, 44), { Variant = false })
	exitSign(at(179.7, 15.2, 22) * CFrame.Angles(0, math.rad(90), 0))

	-- (El estacionamiento, afuera, lo construye buildParking)

	-- Alfombra de bienvenida (aparecen los jugadores)
	local pad = box("PlayerSpawn", Vector3.new(12, 0.2, 12), at(158, 0.1, 0), M.Carpet, Color3.fromRGB(150, 30, 40), { CanCollide = false, Variant = false })
	tag(pad, Tags.PlayerSpawn)

	-- Informacion / objetos perdidos
	local desk = box("InfoDesk", Vector3.new(4, 3.6, 12), at(136, 1.8, -36), M.Wood, Color3.fromRGB(235, 230, 220))
	tag(desk, Tags.LostAndFound)
	deco("InfoTop", Vector3.new(4.6, 0.3, 12.6), at(136, 3.75, -36), M.Marble, Color3.fromRGB(60, 58, 56))
	local infoSign = box("InfoSign", Vector3.new(0.3, 2, 10), at(136, 9, -36), M.SmoothPlastic, DARK, { CanCollide = false })
	litSign(infoSign, "INFORMACIÓN · OBJETOS PERDIDOS", Color3.fromRGB(120, 200, 255), Enum.Font.GothamBold, Enum.NormalId.Right)
	deco("InfoSignHanger", Vector3.new(0.1, 5, 0.1), at(136, 12.5, -36), M.Metal, DARK)

	-- Tienda del conserje (la tienda del mall): local de suministros encajado contra el muro
	-- norte (x 144..168, z 58..70): tabiques, cabecera con rotulo, persiana enrollada,
	-- mostrador con caja (tag ShopCounter), vitrina "bajo llave", estanterias de fondo con
	-- lo que se vende en la tienda (limpieza, linternas y pilas, primeros auxilios),
	-- panel de herramientas, fregonas y el rincon del personal.
	do
		local SX1, SX2, SZ1, SZ2 = 144, 168, 58, 70
		local CX, CZ = (SX1 + SX2) / 2, (SZ1 + SZ2) / 2
		local NAVY = Color3.fromRGB(24, 40, 64)
		local YELLOW = Color3.fromRGB(250, 196, 30)
		local RED = Color3.fromRGB(200, 30, 30)
		local SHELF_GREY = Color3.fromRGB(150, 154, 160)
		local INK = Color3.fromRGB(22, 22, 25)
		local CYL, BALL = Enum.PartType.Cylinder, Enum.PartType.Ball
		local UP = CFrame.Angles(0, 0, math.rad(90)) -- cilindro de pie

		-- Franja de seguridad amarilla y negra (dibujada) en la cara `face` de una pieza
		local function hazard(part: BasePart, face: Enum.NormalId)
			local gui = Instance.new("SurfaceGui")
			gui.Face = face
			gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			gui.PixelsPerStud = 20
			gui.LightInfluence = 1
			local holder = Instance.new("Frame")
			holder.Size = UDim2.fromScale(1, 1)
			holder.BackgroundColor3 = YELLOW
			holder.BorderSizePixel = 0
			holder.ClipsDescendants = true
			holder.Parent = gui
			for i = -2, 40 do
				local bar = Instance.new("Frame")
				bar.AnchorPoint = Vector2.new(0.5, 0.5)
				bar.Position = UDim2.new(0, i * 24, 0.5, 0)
				bar.Size = UDim2.new(0, 10, 3, 0)
				bar.Rotation = 40
				bar.BackgroundColor3 = INK
				bar.BorderSizePixel = 0
				bar.Parent = holder
			end
			gui.Parent = part
		end

		-- Suelo de vinilo gris con franja de seguridad en el borde del local
		deco("ShopFloor", Vector3.new(SX2 - SX1, 0.06, SZ2 - SZ1), at(CX, 0.03, CZ), M.SmoothPlastic, Color3.fromRGB(118, 122, 126), { Variant = false })
		hazard(deco("ShopEdge", Vector3.new(SX2 - SX1, 0.07, 0.5), at(CX, 0.035, SZ1 + 0.25), M.SmoothPlastic, YELLOW, { Variant = false }), Enum.NormalId.Top)

		-- Tabiques laterales con canto de aluminio, cabecera azul con el rotulo luminoso
		for _, x in { SX1, SX2 } do
			box("ShopPartition", Vector3.new(0.6, ENTRY_H, SZ2 - SZ1), at(x, ENTRY_H / 2, CZ), M.Plaster, Color3.fromRGB(226, 224, 218))
			deco("PartitionEdge", Vector3.new(0.8, ENTRY_H, 0.3), at(x, ENTRY_H / 2, SZ1 - 0.1), M.Metal, STEEL)
		end
		box("ShopFascia", Vector3.new(SX2 - SX1 + 0.8, 4.6, 0.8), at(CX, ENTRY_H - 2.3, SZ1), M.SmoothPlastic, NAVY, { Variant = false })
		deco("FasciaTrim", Vector3.new(SX2 - SX1 + 0.8, 0.2, 1.0), at(CX, ENTRY_H - 4.6, SZ1), M.Metal, STEEL)
		local shopSign = deco("ShopSign", Vector3.new(20, 2.3, 0.2), at(CX, 14.35, SZ1 - 0.5), M.SmoothPlastic, NAVY, { Variant = false })
		litSign(shopSign, "TIENDA DEL CONSERJE", Color3.fromRGB(255, 214, 90), Enum.Font.GothamBlack, Enum.NormalId.Front)
		local subSign = deco("ShopSubSign", Vector3.new(15, 0.9, 0.2), at(CX, 12.4, SZ1 - 0.5), M.SmoothPlastic, NAVY, { Variant = false })
		litSign(subSign, "SUMINISTROS · LIMPIEZA · SEGURIDAD", Color3.fromRGB(200, 225, 255), Enum.Font.GothamBold, Enum.NormalId.Front)
		local signLine = deco("ShopSignNeon", Vector3.new(SX2 - SX1, 0.12, 0.12), at(CX, 11.7, SZ1 - 0.45), M.Neon, YELLOW, { CastShadow = false })
		tag(signLine, Tags.Light, { Zone = Z })
		-- Persiana metalica enrollada (cajon) con sus guias
		deco("GrilleBox", Vector3.new(SX2 - SX1 - 0.6, 0.9, 0.9), at(CX, 10.95, SZ1 + 0.4), M.Metal, Color3.fromRGB(170, 172, 176))
		for _, x in { SX1 + 0.55, SX2 - 0.55 } do
			deco("GrilleGuide", Vector3.new(0.3, 10.5, 0.4), at(x, 5.25, SZ1 + 0.4), M.Metal, Color3.fromRGB(150, 152, 158))
		end

		-- Techo del local: fluorescentes, detector, altavoz y camara domo
		for _, x in { 150, 162 } do
			ceilingPanel(at(x, ENTRY_H, 64.5), Z, Vector2.new(7, 1.4), 22, 1.3, true)
		end
		Kit.smokeDetector(at(156, ENTRY_H, 61))
		Kit.ceilingSpeaker(at(146.5, ENTRY_H, 61))
		Kit.domeCamera(at(165, ENTRY_H, 61))

		-- Mostrador: frente con el logo y zocalo de seguridad, encimera de acero (tag ShopCounter)
		local counter = box("ShopCounter", Vector3.new(14.6, 3.5, 2.6), at(153.3, 1.75, 60.8), M.SmoothPlastic, Color3.fromRGB(52, 60, 72), { Variant = false })
		tag(counter, Tags.ShopCounter)
		deco("CounterTop", Vector3.new(15.2, 0.2, 3.1), at(153.3, 3.6, 60.85), M.Metal, STEEL, { Reflectance = 0.15 })
		local front = deco("CounterFront", Vector3.new(13.8, 2.0, 0.06), at(153.3, 2.1, 59.47), M.SmoothPlastic, NAVY, { Variant = false })
		Kit.printed(front, "TIENDA DEL CONSERJE", Color3.fromRGB(255, 214, 90), Enum.Font.GothamBlack, Enum.NormalId.Front)
		hazard(deco("CounterKick", Vector3.new(14.6, 0.55, 0.06), at(153.3, 0.3, 59.47), M.SmoothPlastic, YELLOW, { Variant = false }), Enum.NormalId.Front)
		local cardSticker = deco("CardSticker", Vector3.new(1.6, 0.8, 0.04), at(158.6, 2.7, 59.43), M.SmoothPlastic, Color3.fromRGB(245, 245, 240), { Variant = false })
		Kit.printed(cardSticker, "PAGO CON\nTARJETA", Color3.fromRGB(30, 60, 140), Enum.Font.GothamBold, Enum.NormalId.Front)
		-- Encima: caja registradora, datafono, timbre, expositor de pilas, radios y portapapeles
		propOr("CashRegister", at(156.5, 3.7, 61.1), function(cf)
			box("Register", Vector3.new(1.6, 1, 1.2), cf * CFrame.new(0, 0.5, 0), M.Metal, INK)
		end, false)
		Kit.cardTerminal(at(153.6, 3.72, 60.0))
		deco("BellBase", Vector3.new(0.1, 0.6, 0.6), at(151.3, 3.75, 60.1) * UP, M.Metal, INK, { Shape = CYL })
		deco("Bell", Vector3.new(0.5, 0.5, 0.5), at(151.3, 3.85, 60.1), M.Metal, Color3.fromRGB(215, 190, 120), { Shape = BALL, Reflectance = 0.4 })
		local caddy = deco("BatteryCaddy", Vector3.new(1.6, 0.5, 1.0), at(148.6, 3.95, 60.4), M.Cardboard, Color3.fromRGB(230, 60, 40))
		Kit.printed(caddy, "PILAS 2x1", Color3.new(1, 1, 1), Enum.Font.GothamBlack, Enum.NormalId.Front)
		for k = 0, 3 do
			deco("BatteryCard", Vector3.new(0.34, 0.75, 0.05), at(148.0 + k * 0.4, 4.4, 60.5 + (k % 2) * 0.2), M.SmoothPlastic, if k % 2 == 0 then Color3.fromRGB(30, 30, 34) else Color3.fromRGB(230, 120, 20), { Variant = false })
		end
		deco("RadioDock", Vector3.new(1.4, 0.3, 0.7), at(146.9, 3.85, 61.6), M.SmoothPlastic, INK, { Variant = false })
		for k = 0, 1 do
			deco("Walkie", Vector3.new(0.45, 1.1, 0.3), at(146.6 + k * 0.6, 4.5, 61.6), M.SmoothPlastic, Color3.fromRGB(40, 42, 46), { Variant = false })
			deco("WalkieAntenna", Vector3.new(0.08, 0.6, 0.08), at(146.45 + k * 0.6, 5.3, 61.6), M.Rubber, INK)
			deco("WalkieLed", Vector3.new(0.08, 0.08, 0.04), at(146.75 + k * 0.6, 4.95, 61.44), M.Neon, Color3.fromRGB(60, 255, 90), { CastShadow = false })
		end
		deco("Clipboard", Vector3.new(0.9, 0.05, 1.3), at(158.9, 3.72, 61.4) * CFrame.Angles(0, math.rad(12), 0), M.Wood, Color3.fromRGB(160, 120, 80))
		deco("ClipboardSheet", Vector3.new(0.8, 0.02, 1.1), at(158.9, 3.76, 61.45) * CFrame.Angles(0, math.rad(12), 0), M.SmoothPlastic, Color3.fromRGB(245, 245, 240), { Variant = false })

		-- Vitrina "bajo llave" (taser, machete y pistola) a la derecha del paso del personal
		local VX = 165
		box("LockedCase", Vector3.new(4.8, 2.6, 2.4), at(VX, 1.3, 60.8), M.SmoothPlastic, Color3.fromRGB(42, 46, 52), { Variant = false })
		deco("LockedCaseFloor", Vector3.new(4.6, 0.06, 2.2), at(VX, 2.63, 60.8), M.Fabric, Color3.fromRGB(25, 28, 34))
		deco("LockedCaseGlass", Vector3.new(4.8, 1.2, 2.4), at(VX, 3.2, 60.8), M.SmoothPlastic, Color3.fromRGB(215, 232, 238), {
			Transparency = 0.82,
			Reflectance = 0.25,
			CastShadow = false,
			Variant = false,
		})
		deco("LockedCaseTop", Vector3.new(4.9, 0.12, 2.5), at(VX, 3.86, 60.8), M.Metal, STEEL)
		local caseLed = deco("LockedCaseLED", Vector3.new(4.4, 0.04, 0.06), at(VX, 3.75, 59.9), M.Neon, Color3.fromRGB(235, 245, 255), { CastShadow = false })
		tag(caseLed, Tags.Light, { Zone = Z })
		deco("Lock", Vector3.new(0.3, 0.35, 0.08), at(VX + 1.6, 2.2, 59.58), M.Metal, Color3.fromRGB(210, 180, 90))
		-- Machete
		deco("MacheteBlade", Vector3.new(2.2, 0.06, 0.45), at(VX - 0.6, 2.7, 60.4) * CFrame.Angles(0, math.rad(8), 0), M.Metal, Color3.fromRGB(190, 194, 200), { Reflectance = 0.3 })
		deco("MacheteGrip", Vector3.new(0.8, 0.14, 0.25), at(VX + 0.9, 2.72, 60.6) * CFrame.Angles(0, math.rad(8), 0), M.Wood, Color3.fromRGB(70, 45, 30))
		-- Taser
		deco("TaserBody", Vector3.new(0.9, 0.3, 0.45), at(VX - 1.2, 2.82, 61.4), M.SmoothPlastic, Color3.fromRGB(250, 200, 30), { Variant = false })
		deco("TaserTip", Vector3.new(0.3, 0.25, 0.35), at(VX - 1.75, 2.8, 61.4), M.SmoothPlastic, INK, { Variant = false })
		-- Pistola (silueta)
		deco("PistolSlide", Vector3.new(1.1, 0.22, 0.25), at(VX + 0.8, 2.8, 61.4), M.Metal, Color3.fromRGB(35, 35, 38))
		deco("PistolGrip", Vector3.new(0.3, 0.12, 0.6), at(VX + 1.15, 2.74, 61.75) * CFrame.Angles(0, math.rad(-15), 0), M.SmoothPlastic, Color3.fromRGB(35, 35, 38), { Variant = false })
		local caseTag = deco("LockedSign", Vector3.new(2.2, 0.5, 0.04), at(VX, 2.15, 59.58), M.SmoothPlastic, RED, { Variant = false })
		Kit.printed(caseTag, "BAJO LLAVE · PIDE AL CONSERJE", Color3.new(1, 1, 1), Enum.Font.GothamBold, Enum.NormalId.Front)

		-- Estanteria del fondo: 3 modulos (z 67.4..70) con baldas, precios y cartel por modulo
		local RZ = 68.7
		box("BackShelving", Vector3.new(21.8, 9.2, 2.6), at(CX, 4.6, RZ), M.SmoothPlastic, Color3.new(1, 1, 1), { Transparency = 1, Variant = false })
		for _, x in { 145.1, 152.4, 159.6, 166.9 } do
			for _, z in { 67.55, 69.8 } do
				deco("ShelfUpright", Vector3.new(0.25, 9.6, 0.25), at(x, 4.8, z), M.Metal, Color3.fromRGB(70, 74, 82))
			end
		end
		deco("ShelfBackPanel", Vector3.new(21.8, 9.2, 0.08), at(CX, 4.8, 69.92), M.Metal, Color3.fromRGB(200, 202, 206))
		local shelfYs = { 0.45, 2.35, 4.25, 6.15, 8.05 }
		for i, y in shelfYs do
			deco("Shelf", Vector3.new(21.6, 0.12, 2.4), at(CX, y, RZ), M.Metal, SHELF_GREY)
			local strip = deco("PriceStrip", Vector3.new(21.6, 0.3, 0.05), at(CX, y - 0.05, 67.48), M.SmoothPlastic, Color3.fromRGB(245, 245, 240), { Variant = false })
			local gui = Instance.new("SurfaceGui")
			gui.Face = Enum.NormalId.Front
			gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			gui.PixelsPerStud = 30
			gui.LightInfluence = 1
			local row = Instance.new("Frame")
			row.Size = UDim2.fromScale(1, 1)
			row.BackgroundTransparency = 1
			row.Parent = gui
			local layout = Instance.new("UIListLayout")
			layout.FillDirection = Enum.FillDirection.Horizontal
			layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
			layout.Padding = UDim.new(0.03, 0)
			layout.Parent = row
			for k = 1, 9 do
				local label = Instance.new("TextLabel")
				label.Size = UDim2.fromScale(0.08, 1)
				label.BackgroundColor3 = if (k + i) % 4 == 0 then YELLOW else Color3.fromRGB(245, 245, 240)
				label.BorderSizePixel = 0
				label.Font = Enum.Font.GothamBold
				label.TextScaled = true
				label.TextColor3 = INK
				label.Text = string.format("%d,%02d €", 1 + (k * 7 + i * 3) % 19, (k * 37 + i * 11) % 100)
				label.LayoutOrder = k
				label.Parent = row
			end
			gui.Parent = strip
		end
		for k, title in { "LIMPIEZA", "LINTERNAS · PILAS", "PRIMEROS AUXILIOS" } do
			local header = deco("BayHeader", Vector3.new(6.8, 0.9, 0.2), at(148.75 + (k - 1) * 7.25, 9.75, 67.5), M.SmoothPlastic, NAVY, { Variant = false })
			Kit.printed(header, title, Color3.fromRGB(255, 214, 90), Enum.Font.GothamBold, Enum.NormalId.Front)
		end
		local function onShelf(i: number, x: number, z: number?): CFrame
			return at(x, shelfYs[i] + 0.06, z or 68.4)
		end

		-- Modulo 1: LIMPIEZA (x 145.4..152.1)
		for k = 0, 2 do
			local p = onShelf(1, 146.6 + k * 2.2)
			deco("Bucket", Vector3.new(1.3, 1.3, 1.3), p * CFrame.new(0, 0.65, 0) * UP, M.SmoothPlastic, YELLOW, { Shape = CYL, Variant = false })
			deco("BucketRim", Vector3.new(0.1, 1.42, 1.42), p * CFrame.new(0, 1.3, 0) * UP, M.SmoothPlastic, Color3.fromRGB(230, 170, 20), { Shape = CYL, Variant = false })
		end
		for k = 0, 4 do
			local p = onShelf(2, 146.0 + k * 1.3)
			local color = ({ Color3.fromRGB(40, 110, 200), Color3.fromRGB(60, 170, 80), Color3.fromRGB(240, 120, 30), Color3.fromRGB(40, 110, 200), Color3.fromRGB(230, 230, 235) })[k + 1]
			deco("Jug", Vector3.new(0.9, 1.3, 0.6), p * CFrame.new(0, 0.65, 0), M.SmoothPlastic, color, { Variant = false })
			deco("JugCap", Vector3.new(0.2, 0.3, 0.3), p * CFrame.new(-0.2, 1.4, 0) * UP, M.SmoothPlastic, Color3.fromRGB(240, 240, 240), { Shape = CYL, Variant = false })
			deco("JugLabel", Vector3.new(0.7, 0.5, 0.02), p * CFrame.new(0, 0.6, -0.31), M.SmoothPlastic, Color3.fromRGB(250, 250, 245), { Variant = false, CastShadow = false })
		end
		for k = 0, 7 do
			local p = onShelf(3, 145.9 + k * 0.82)
			local color = ({ Color3.fromRGB(80, 170, 230), Color3.fromRGB(240, 90, 150), Color3.fromRGB(120, 200, 90), Color3.fromRGB(250, 200, 40) })[k % 4 + 1]
			deco("SprayBody", Vector3.new(0.5, 1.0, 0.32), p * CFrame.new(0, 0.5, 0), M.SmoothPlastic, color, { Transparency = 0.1, Variant = false })
			deco("SprayNeck", Vector3.new(0.14, 0.25, 0.14), p * CFrame.new(0, 1.12, 0), M.SmoothPlastic, Color3.fromRGB(240, 240, 240), { Variant = false })
			deco("SprayHead", Vector3.new(0.18, 0.22, 0.45), p * CFrame.new(0, 1.3, -0.1), M.SmoothPlastic, Color3.fromRGB(240, 240, 240), { Variant = false })
		end
		for k = 0, 5 do
			local p = onShelf(4, 146.0 + k * 1.15)
			deco("TowelRoll", Vector3.new(1.3, 0.95, 0.95), p * CFrame.new(0, 0.65, 0) * UP, M.Fabric, Color3.fromRGB(248, 248, 244), { Shape = CYL })
		end
		productRow(onShelf(5, 148.75), 6.2, 1.8, Color3.fromRGB(185, 145, 95))

		-- Modulo 2: LINTERNAS · PILAS (x 152.6..159.4)
		for k = 0, 3 do
			local p = onShelf(1, 153.6 + k * 1.65)
			local boxPart = deco("LanternBox", Vector3.new(1.4, 1.5, 1.2), p * CFrame.new(0, 0.75, 0), M.Cardboard, Color3.fromRGB(235, 225, 205))
			Kit.printed(boxPart, "LINTERNA\nLED", INK, Enum.Font.GothamBlack, Enum.NormalId.Front)
		end
		for k = 0, 5 do
			local p = onShelf(2, 153.3 + k * 1.1, 67.95) * CFrame.Angles(0, math.rad(90), 0)
			local color = if k % 2 == 0 then INK else YELLOW
			deco("FlashlightBody", Vector3.new(1.2, 0.32, 0.32), p * CFrame.new(0, 0.18, 0), M.SmoothPlastic, color, { Shape = CYL, Variant = false })
			deco("FlashlightHead", Vector3.new(0.35, 0.48, 0.48), p * CFrame.new(-0.7, 0.26, 0), M.SmoothPlastic, color, { Shape = CYL, Variant = false })
			deco("FlashlightLens", Vector3.new(0.04, 0.4, 0.4), p * CFrame.new(-0.88, 0.26, 0), M.SmoothPlastic, Color3.fromRGB(230, 240, 250), { Shape = CYL, Reflectance = 0.4, Variant = false })
		end
		for k = 0, 7 do
			local p = onShelf(3, 153.2 + k * 0.82, 67.9)
			deco("BatteryPack", Vector3.new(0.62, 1.05, 0.08), p * CFrame.new(0, 0.53, 0), M.SmoothPlastic, if k % 2 == 0 then Color3.fromRGB(30, 30, 34) else Color3.fromRGB(230, 120, 20), { Variant = false })
			for b = 0, 1 do
				deco("Battery", Vector3.new(0.6, 0.18, 0.18), p * CFrame.new(-0.1 + b * 0.2, 0.45, -0.1) * UP, M.Metal, Color3.fromRGB(220, 180, 60), { Shape = CYL })
			end
		end
		for k = 0, 2 do
			local p = onShelf(4, 153.7 + k * 2.2)
			deco("FlareBox", Vector3.new(1.8, 0.5, 1.2), p * CFrame.new(0, 0.25, 0), M.Cardboard, Color3.fromRGB(200, 60, 40))
			for s = 0, 3 do
				deco("Flare", Vector3.new(1.4, 0.18, 0.18), p * CFrame.new(-0.6 + s * 0.4, 0.62, 0) * CFrame.Angles(0, math.rad(90), 0) * CFrame.Angles(0, 0, math.rad(8)), M.SmoothPlastic, Color3.fromRGB(220, 30, 30), { Shape = CYL, Variant = false })
			end
		end
		for k = 0, 3 do
			local p = onShelf(5, 153.5 + k * 1.6) * CFrame.Angles(0, math.rad(90), 0)
			deco("UVFlashlight", Vector3.new(1.1, 0.34, 0.34), p * CFrame.new(0, 0.2, 0), M.SmoothPlastic, Color3.fromRGB(110, 50, 170), { Shape = CYL, Variant = false })
			deco("UVLens", Vector3.new(0.05, 0.36, 0.36), p * CFrame.new(-0.57, 0.2, 0), M.Neon, Color3.fromRGB(150, 80, 255), { Shape = CYL, CastShadow = false })
		end

		-- Modulo 3: PRIMEROS AUXILIOS (x 159.9..166.6)
		for k = 0, 2 do
			local p = onShelf(1, 161.0 + k * 2.1)
			deco("Extinguisher", Vector3.new(1.7, 0.75, 0.75), p * CFrame.new(0, 0.85, 0) * UP, M.SmoothPlastic, RED, { Shape = CYL, Reflectance = 0.1, Variant = false })
			deco("ExtinguisherHead", Vector3.new(0.35, 0.4, 0.5), p * CFrame.new(0, 1.85, 0), M.Metal, INK)
			deco("ExtinguisherLabel", Vector3.new(0.6, 0.6, 0.02), p * CFrame.new(0, 0.9, -0.38), M.SmoothPlastic, Color3.fromRGB(245, 245, 240), { Variant = false, CastShadow = false })
		end
		for k = 0, 2 do
			local p = onShelf(2, 161.1 + k * 2.1)
			local bag = deco("FirstAidBag", Vector3.new(1.8, 1.2, 1.1), p * CFrame.new(0, 0.6, 0), M.Fabric, Color3.fromRGB(40, 130, 70))
			Kit.printed(bag, "✚", Color3.new(1, 1, 1), Enum.Font.GothamBlack, Enum.NormalId.Front)
		end
		for k = 0, 4 do
			local p = onShelf(3, 160.7 + k * 1.3)
			local kit = deco("FirstAidKit", Vector3.new(1.1, 0.8, 0.5), p * CFrame.new(0, 0.4, -0.2), M.SmoothPlastic, Color3.fromRGB(245, 245, 242), { Variant = false })
			Kit.printed(kit, "✚", RED, Enum.Font.GothamBlack, Enum.NormalId.Front)
		end
		Kit.stackRow(onShelf(4, 162.0), 3.6, 1.6, { Color3.fromRGB(220, 255, 40), Color3.fromRGB(255, 140, 30) }, 0.8, 1.2)
		for k = 0, 1 do
			deco("HardHat", Vector3.new(1.1, 1.1, 1.1), onShelf(4, 164.9 + k * 1.2) * CFrame.new(0, 0.05, 0), M.SmoothPlastic, YELLOW, { Shape = BALL, Variant = false })
		end
		productRow(onShelf(5, 163.25), 6.2, 1.8, Color3.fromRGB(185, 145, 95))

		-- Tabique izquierdo: panel perforado con herramientas y fregonas/escobas apoyadas
		local pegX = SX1 + 0.36
		local board = deco("Pegboard", Vector3.new(0.08, 4.6, 5), at(pegX, 6.1, 64.5), M.Wood, Color3.fromRGB(175, 135, 90))
		do
			local gui = Instance.new("SurfaceGui")
			gui.Face = Enum.NormalId.Right
			gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			gui.PixelsPerStud = 20
			gui.LightInfluence = 1
			local grid = Instance.new("Frame")
			grid.Size = UDim2.fromScale(1, 1)
			grid.BackgroundTransparency = 1
			grid.Parent = gui
			local layout = Instance.new("UIGridLayout")
			layout.CellSize = UDim2.fromOffset(3, 3)
			layout.CellPadding = UDim2.fromOffset(7, 7)
			layout.Parent = grid
			for _ = 1, 230 do
				local hole = Instance.new("Frame")
				hole.BackgroundColor3 = Color3.fromRGB(70, 50, 30)
				hole.BorderSizePixel = 0
				hole.Parent = grid
			end
			gui.Parent = board
		end
		local function tool(name: string, size: Vector3, y: number, z: number, color: Color3, rot: number?)
			deco(name, size, at(pegX + 0.15, y, z) * CFrame.Angles(math.rad(rot or 0), 0, 0), M.Metal, color)
		end
		tool("Hammer", Vector3.new(0.12, 1.6, 0.18), 6.6, 62.6, Color3.fromRGB(120, 80, 50))
		tool("HammerHead", Vector3.new(0.18, 0.3, 0.8), 7.4, 62.6, Color3.fromRGB(60, 62, 66))
		tool("Wrench", Vector3.new(0.08, 1.5, 0.2), 6.5, 63.6, STEEL, 10)
		tool("Wrench", Vector3.new(0.08, 1.2, 0.18), 6.6, 64.2, STEEL, -10)
		tool("Screwdriver", Vector3.new(0.12, 1.3, 0.12), 6.4, 64.9, Color3.fromRGB(220, 50, 40))
		tool("Screwdriver", Vector3.new(0.12, 1.3, 0.12), 6.4, 65.3, Color3.fromRGB(250, 200, 30))
		tool("Pliers", Vector3.new(0.1, 1.2, 0.35), 6.5, 66.0, Color3.fromRGB(220, 50, 40), 6)
		for k = 0, 2 do
			deco("TapeRoll", Vector3.new(0.35, 0.8, 0.8), at(pegX + 0.25, 4.5, 63 + k * 1.1) * CFrame.Angles(0, 0, 0), M.SmoothPlastic, ({ Color3.fromRGB(170, 170, 175), YELLOW, RED })[k + 1], { Shape = CYL, Variant = false })
		end
		deco("TapeMeasure", Vector3.new(0.4, 0.7, 0.7), at(pegX + 0.25, 4.5, 66.4), M.SmoothPlastic, YELLOW, { Variant = false })
		for k = 0, 3 do
			local base = at(SX1 + 0.9, 0, 59.4 + k * 0.75) * CFrame.Angles(math.rad(-4 + k * 2), 0, math.rad(-8))
			deco("MopHandle", Vector3.new(0.14, 5.6, 0.14), base * CFrame.new(0, 2.9, 0), M.Wood, if k % 2 == 0 then Color3.fromRGB(40, 110, 200) else Color3.fromRGB(200, 60, 40))
			if k % 2 == 0 then
				deco("MopHead", Vector3.new(0.7, 0.6, 0.7), base * CFrame.new(0, 0.3, 0), M.Fabric, Color3.fromRGB(235, 232, 220))
			else
				deco("BroomHead", Vector3.new(0.4, 0.5, 1.4), base * CFrame.new(0, 0.25, 0), M.Plastic, Color3.fromRGB(60, 60, 64))
			end
		end

		-- Tabique derecho: armario de llaves, tablon de avisos, reloj de fichar y reloj
		local wx = SX2 - 0.32
		deco("KeyCabinet", Vector3.new(0.4, 2.2, 1.8), at(wx - 0.2, 5.8, 61.2), M.Metal, Color3.fromRGB(200, 200, 196))
		deco("KeyCabinetDoor", Vector3.new(0.05, 1.9, 1.5), at(wx - 0.42, 5.8, 61.2), M.SmoothPlastic, Color3.fromRGB(215, 232, 238), { Transparency = 0.6, Variant = false })
		for k = 0, 5 do
			deco("Key", Vector3.new(0.04, 0.3, 0.12), at(wx - 0.35, 6.2 - (k // 3) * 0.6, 60.7 + (k % 3) * 0.5), M.Metal, Color3.fromRGB(210, 180, 90))
		end
		deco("CorkBoard", Vector3.new(0.12, 2.6, 3.4), at(wx - 0.06, 6.0, 64.4), M.Wood, Color3.fromRGB(180, 140, 95))
		for k = 0, 4 do
			local note = deco("Notice", Vector3.new(0.03, 0.9, 0.7), at(wx - 0.14, 5.4 + (k % 2) * 1.1, 63.2 + k * 0.55) * CFrame.Angles(math.rad((k * 7) % 11 - 5), 0, 0), M.SmoothPlastic, if k == 2 then YELLOW else Color3.fromRGB(245, 245, 240), { Variant = false, CastShadow = false })
			if k == 0 then
				Kit.printed(note, "TURNO\nNOCHE", INK, Enum.Font.GothamBold, Enum.NormalId.Left)
			end
		end
		deco("TimeClock", Vector3.new(0.5, 1.3, 1.0), at(wx - 0.25, 5.2, 66.6), M.SmoothPlastic, Color3.fromRGB(60, 64, 72), { Variant = false })
		deco("TimeClockScreen", Vector3.new(0.04, 0.35, 0.6), at(wx - 0.51, 5.5, 66.6), M.Neon, Color3.fromRGB(120, 220, 140), { CastShadow = false })
		deco("CardRack", Vector3.new(0.2, 1.6, 0.9), at(wx - 0.1, 3.4, 66.6), M.Metal, Color3.fromRGB(170, 172, 176))
		Kit.wallClock(at(CX, 11.0, 69.92), 1.4)

		-- Rincon del personal detras del mostrador: taburete, cajas de reposicion y carretilla
		Kit.stool(at(156.5, 0, 63.6), INK)
		for k = 0, 1 do
			deco("StockBox", Vector3.new(2, 1.5, 1.6), at(147.2, 0.75 + k * 1.5, 65.6) * CFrame.Angles(0, math.rad(k * 9), 0), M.Cardboard, Color3.fromRGB(185, 145, 95))
		end
		deco("HandTruckPlate", Vector3.new(1.6, 0.12, 0.9), at(162.4, 0.06, 65.6), M.Metal, Color3.fromRGB(60, 62, 68))
		for _, sx in { -0.6, 0.6 } do
			deco("HandTruckRail", Vector3.new(0.12, 4.4, 0.12), at(162.4 + sx, 2.2, 66.1) * CFrame.Angles(math.rad(-6), 0, 0), M.Metal, Color3.fromRGB(200, 60, 40))
			deco("HandTruckWheel", Vector3.new(0.3, 0.9, 0.9), at(162.4 + sx * 1.3, 0.45, 66.2), M.Rubber, INK, { Shape = CYL })
		end

		-- Fuera del local: el carro del conserje y la señal de piso mojado
		propOr("JanitorCart", at(140.5, 0, 63) * CFrame.Angles(0, math.rad(-90), 0), function() end)
		wetFloorSign(at(141.5, 0, 56) * CFrame.Angles(0, math.rad(20), 0))
	end

	-- Maquina premium
	vendingMachine(CFrame.lookAt(Vector3.new(178, Y0 + 3.5, -44), Vector3.new(170, Y0 + 3.5, -44)), "Premium", Color3.fromRGB(25, 45, 140), "PREMIUM")

	planter(172, 58, Z)
	planter(172, 30, Z)
	planter(140, -60, Z)
	bench(at(150, 0, 30) * CFrame.Angles(0, math.rad(90), 0))
	bench(at(150, 0, -30) * CFrame.Angles(0, math.rad(90), 0))
	directoryTotem(at(140, 0, 12) * CFrame.Angles(0, math.rad(-90), 0), 1)

	for _, x in { 134, 166 } do
		for _, z in { -45, 0, 45 } do
			ceilingPanel(at(x, ENTRY_H, z), Z, Vector2.new(6, 6), 30, 1.5, false, true)
		end
	end
	for _, c in { { 128, -45 }, { 128, 45 } } do
		column(c[1], c[2], ENTRY_H, 3)
	end

	hidingSpot("Armario", at(122.6, 3.75, 64) * CFrame.Angles(0, math.rad(-90), 0), Vector3.new(4, 7.5, 3), M.Metal, Color3.fromRGB(80, 95, 110))
	electricPanel(at(121.4, 3, -64) * CFrame.Angles(0, math.rad(-90), 0), Z)
	spot(140, -10, "CleanSpill", Z)
	spot(165, 20, "CleanSpill", Z)
	spot(156, -62, "WaterPlants", Z)
	spot(140, -36, "SecurityRound", Z)
	spot(150, 30, "PayPhone", "Sigue el timbre")
	patrolClock(124, 32, Z)
	wallExtinguisher(at(121, 0, -50) * CFrame.Angles(0, math.rad(-90), 0), "Planta baja")
	payPhone(at(121, 0, -30) * CFrame.Angles(0, math.rad(-90), 0), Z)
	camera(178, 14, 68, 150, 0, 30)

	currentParent = map
end

----------------------------------------------------------------------
-- Estacionamiento (planta baja, afuera de la Entrada)
----------------------------------------------------------------------
-- Vallado, con farolas (luces de la zona: se apagan y se reparan), coches (dos con la
-- puerta abierta: escondites), corral de carritos y carritos abandonados (mision Juntar
-- carritos), contenedor de basura y puntos de mision.

local PARK = { X1 = 181, X2 = 260, Z1 = -90, Z2 = 90 }

-- Valla de obra: zocalo de hormigon, malla metalica y postes (no se salta).
local function fence(p1: Vector3, p2: Vector3)
	local a = Vector3.new(p1.X, Y0 + levelY, p1.Z)
	local b = Vector3.new(p2.X, Y0 + levelY, p2.Z)
	local length = (b - a).Magnitude
	local mid = (a + b) / 2
	local cf = CFrame.lookAt(mid, mid + (b - a))
	box("FenceBase", Vector3.new(0.8, 1.2, length), cf * CFrame.new(0, 0.6, 0), M.Concrete, Color3.fromRGB(120, 120, 116))
	box("FenceMesh", Vector3.new(0.2, 10, length), cf * CFrame.new(0, 6.2, 0), M.DiamondPlate, Color3.fromRGB(110, 115, 120), {
		Transparency = 0.55,
		CastShadow = false,
		Variant = false,
	})
	deco("FenceRail", Vector3.new(0.3, 0.3, length), cf * CFrame.new(0, 11.2, 0), M.Metal, METAL)
	local posts = math.max(1, math.floor(length / 10))
	for i = 0, posts do
		deco("FencePost", Vector3.new(0.4, 11.4, 0.4), cf * CFrame.new(0, 5.7, -length / 2 + i * (length / posts)), M.Metal, METAL)
	end
end

-- Farola con foco hacia abajo (luz de la zona: el Apagon la apaga, Reparar luces la arregla).
local function lightPole(x: number, z: number, zoneName: string)
	box("LightPole", Vector3.new(0.7, 22, 0.7), at(x, 11, z), M.Metal, Color3.fromRGB(60, 62, 66))
	deco("PoleBase", Vector3.new(1.6, 1, 1.6), at(x, 0.5, z), M.Concrete, Color3.fromRGB(130, 130, 126))
	local head = deco("PoleLamp", Vector3.new(3, 0.5, 1.4), at(x, 22, z), M.Neon, Color3.fromRGB(255, 205, 140), { CastShadow = false })
	local lot = Instance.new("SpotLight")
	lot.Face = Enum.NormalId.Bottom
	lot.Angle = 120
	lot.Range = 50
	lot.Brightness = 2.2
	lot.Color = Color3.fromRGB(255, 190, 120)
	lot.Shadows = true
	lot.Parent = head
	tag(head, Tags.Light, { Zone = zoneName })
end

-- Coche aparcado de piezas. `cf` = centro en el suelo; el morro mira a -Z.
-- hide = puerta del conductor (lado -X) abierta: es un escondite.
local function parkedCar(cf: CFrame, color: Color3, hide: boolean?, modelName: string?)
	-- Modelo 3D (PropTemplates.CarSedan / CarHatch / CarSUV): los blancos se tiñen con `color`
	local car = prop(modelName or "CarSedan", cf)
	if car then
		tintModel(car, color)
		if hide then
			local hideSpot = box("Coche", Vector3.new(3, 4, 3), cf * CFrame.new(-1.2, 3, 0.3) * CFrame.Angles(0, math.rad(90), 0), M.SmoothPlastic, Color3.new(1, 1, 1), {
				Transparency = 1,
				CanCollide = false,
				CanQuery = false,
				Variant = false,
			})
			hideSpot:SetAttribute("DisplayName", "Coche")
			tag(hideSpot, Tags.HidingSpot)
		end
		return
	end
	local glass = Color3.fromRGB(18, 22, 28)
	box("CarBody", Vector3.new(6, 2.4, 13), cf * CFrame.new(0, 2, 0), M.SmoothPlastic, color, { Variant = false })
	box("CarCabin", Vector3.new(5.6, 2.2, 6.4), cf * CFrame.new(0, 4.3, 0.6), M.SmoothPlastic, color:Lerp(Color3.new(0, 0, 0), 0.15), { Variant = false })
	deco("CarWindshield", Vector3.new(5.2, 1.8, 0.1), cf * CFrame.new(0, 4.3, -2.66), M.Glass, glass, { Transparency = 0.25, Variant = false })
	deco("CarRearWindow", Vector3.new(5.2, 1.8, 0.1), cf * CFrame.new(0, 4.3, 3.86), M.Glass, glass, { Transparency = 0.25, Variant = false })
	for _, s in { -1, 1 } do
		deco("CarSideWindow", Vector3.new(0.1, 1.6, 5.6), cf * CFrame.new(s * 2.86, 4.4, 0.6), M.Glass, glass, { Transparency = 0.25, Variant = false })
		for _, wz in { -4.2, 4.2 } do
			deco("CarWheel", Vector3.new(0.9, 2.4, 2.4), cf * CFrame.new(s * 2.8, 1.2, wz), M.Rubber, Color3.fromRGB(25, 25, 27), {
				Shape = Enum.PartType.Cylinder,
			})
		end
		deco("Headlight", Vector3.new(1.2, 0.5, 0.1), cf * CFrame.new(s * 2, 2.5, -6.55), M.SmoothPlastic, Color3.fromRGB(235, 230, 200))
		deco("Taillight", Vector3.new(1.2, 0.4, 0.1), cf * CFrame.new(s * 2, 2.6, 6.55), M.SmoothPlastic, Color3.fromRGB(150, 20, 20))
	end
	if hide then
		-- Puerta abierta (girada sobre la bisagra delantera)
		local hinge = cf * CFrame.new(-3, 3.2, -1.6) * CFrame.Angles(0, math.rad(-55), 0)
		deco("CarDoorOpen", Vector3.new(0.2, 2.6, 3.4), hinge * CFrame.new(0, 0, 1.7), M.SmoothPlastic, color, { Variant = false })
		-- Escondite invisible dentro del coche; su cara Front mira hacia la puerta (-X)
		local hideSpot = box("Coche", Vector3.new(3, 4, 3), cf * CFrame.new(-1.2, 3, 0.3) * CFrame.Angles(0, math.rad(90), 0), M.SmoothPlastic, Color3.new(1, 1, 1), {
			Transparency = 1,
			CanCollide = false,
			CanQuery = false,
			Variant = false,
		})
		hideSpot:SetAttribute("DisplayName", "Coche")
		tag(hideSpot, Tags.HidingSpot)
	end
end

-- Punto invisible del suelo con un tag (plazas de carritos).
local function floorMark(name: string, x: number, z: number, tagName: string)
	local p = box(name, Vector3.new(1, 0.2, 1), at(x, 0.1, z), M.SmoothPlastic, Color3.new(1, 1, 1), {
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Variant = false,
	})
	tag(p, tagName)
	return p
end

local function buildParking()
	folder("Estacionamiento")
	levelY = 0
	local Z = "Estacionamiento"
	zone(Z, PARK.X1, PARK.X2, PARK.Z1, PARK.Z2, 30)

	slab("Parking", PARK.X1, PARK.X2, PARK.Z1, PARK.Z2, 0, M.Asphalt, Color3.fromRGB(42, 42, 45), { Variant = false })
	deco("Sidewalk", Vector3.new(14, 0.6, 180), at(188, 0.3, 0), M.Concrete, Color3.fromRGB(150, 148, 142))
	box("Canopy", Vector3.new(12, 0.8, 34), at(187, 15, 0), M.Metal, Color3.fromRGB(45, 45, 50))
	for _, z in { -16, 16 } do
		box("CanopyPost", Vector3.new(0.8, 15, 0.8), at(192.5, 7.5, z), M.Metal, Color3.fromRGB(45, 45, 50))
	end
	-- Paso de peatones hasta las plazas
	for k = 0, 5 do
		deco("Crosswalk", Vector3.new(6, 0.04, 1.6), at(198, 0.02, -5 + k * 2), M.SmoothPlastic, Color3.fromRGB(225, 225, 215), { Variant = false })
	end
	for x = 205, 253, 12 do
		for _, z in { -40, 40 } do
			deco("ParkingLine", Vector3.new(0.4, 0.04, 16), at(x, 0.02, z), M.SmoothPlastic, Color3.fromRGB(220, 220, 215), { Variant = false })
		end
	end

	-- Valla: este, sur, norte y el trozo entre la valla sur y la fachada (z -90..-71)
	fence(Vector3.new(PARK.X2, 0, PARK.Z1), Vector3.new(PARK.X2, 0, PARK.Z2))
	fence(Vector3.new(PARK.X1 - 0.5, 0, PARK.Z1), Vector3.new(PARK.X2, 0, PARK.Z1))
	fence(Vector3.new(PARK.X1 - 0.5, 0, PARK.Z2), Vector3.new(PARK.X2, 0, PARK.Z2))
	fence(Vector3.new(PARK.X1 - 0.5, 0, PARK.Z1), Vector3.new(PARK.X1 - 0.5, 0, -71))

	-- Farolas
	for _, p in { { 200, -60 }, { 200, 60 }, { 225, 0 }, { 250, -60 }, { 250, 60 }, { 250, 0 } } do
		lightPole(p[1], p[2], Z)
	end

	-- Coches (8 plazas: z = +-40; x = 211, 223, 235, 247). Dos son escondites.
	parkedCar(CFrame.new(211, Y0, 40), Color3.fromRGB(165, 30, 35), false, "CarSedan")
	parkedCar(CFrame.new(235, Y0, 40), Color3.fromRGB(60, 95, 170), true, "CarHatch")
	parkedCar(CFrame.new(247, Y0, 40), Color3.fromRGB(240, 240, 236), false, "CarSedan")
	parkedCar(CFrame.new(211, Y0, -40) * CFrame.Angles(0, math.pi, 0), Color3.fromRGB(62, 64, 70), true, "CarSedan")
	parkedCar(CFrame.new(223, Y0, -40) * CFrame.Angles(0, math.pi, 0), Color3.fromRGB(185, 188, 192), false, "CarHatch")
	parkedCar(CFrame.new(247, Y0, -40) * CFrame.Angles(0, math.pi, 0), Color3.fromRGB(45, 95, 60), false, "CarSUV")

	-- Corral de carritos (mision Juntar carritos) con un par de carritos dentro
	local corralCF = at(210, 0, -20)
	-- Barandas de tubo (se ven los carritos); la colision es una placa invisible
	local tube = Color3.fromRGB(150, 155, 162)
	for _, s in { -1, 1 } do
		box("CorralRail", Vector3.new(0.3, 3.4, 12), corralCF * CFrame.new(s * 2.4, 1.7, 0), M.Metal, METAL, { Transparency = 1, Variant = false })
		for _, y in { 1.4, 3.3 } do
			deco("CorralBar", Vector3.new(12, 0.22, 0.22), corralCF * CFrame.new(s * 2.4, y, 0) * CFrame.Angles(0, math.rad(90), 0), M.Metal, tube, { Shape = Enum.PartType.Cylinder })
		end
		for _, z in { -5.9, 0, 5.9 } do
			deco("CorralPost", Vector3.new(3.4, 0.26, 0.26), corralCF * CFrame.new(s * 2.4, 1.7, z) * CFrame.Angles(0, 0, math.rad(90)), M.Metal, tube, { Shape = Enum.PartType.Cylinder })
		end
	end
	box("CorralBack", Vector3.new(5, 3.4, 0.3), corralCF * CFrame.new(0, 1.7, 6), M.Metal, METAL, { Transparency = 1, Variant = false })
	for _, y in { 1.4, 3.3 } do
		deco("CorralBar", Vector3.new(4.8, 0.22, 0.22), corralCF * CFrame.new(0, y, 5.9), M.Metal, tube, { Shape = Enum.PartType.Cylinder })
	end
	local corralSign = box("CorralSign", Vector3.new(4.6, 1.4, 0.2), corralCF * CFrame.new(0, 4.4, 6), M.SmoothPlastic, Color3.fromRGB(20, 60, 140), { CanCollide = false })
	sign(corralSign, "CARRITOS", Color3.new(1, 1, 1), Enum.Font.GothamBlack, Enum.NormalId.Front)
	-- Carritos encajados unos en otros (modelo 3D; si falta, las cajas de antes)
	for k = 0, 2 do
		propOr("ShoppingCart", corralCF * CFrame.new(0, 0, 3.2 - k * 1.1), function(c)
			if k < 2 then
				deco("CorralCart", Vector3.new(2.3, 1.8, 3.2), c * CFrame.new(0, 2.6, 0), M.DiamondPlate, STEEL, { Transparency = 0.35 })
			end
		end, false)
	end
	local corral = box("CartCorral", Vector3.new(4, 3, 10), corralCF * CFrame.new(0, 1.5, 0), M.SmoothPlastic, Color3.new(1, 1, 1), {
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Variant = false,
	})
	tag(corral, Tags.CartCorral)
	-- Plazas donde pueden quedar carritos abandonados
	for _, p in { { 230, -70 }, { 215, 70 }, { 240, 20 }, { 255, -15 }, { 205, 82 }, { 240, 75 }, { 222, -58 }, { 238, -22 } } do
		floorMark("CartSpot", p[1], p[2], Tags.CartSpot)
	end

	-- Contenedor de basura (tambien vale para Sacar la basura)
	-- (contra la valla este: las tapas miran al estacionamiento, -X)
	tag(dumpster(at(255, 0, 30) * CFrame.Angles(0, math.rad(90), 0)), Tags.TrashDropoff)

	-- Puntos de mision, escondites, camara y aparicion de enemigos
	electricPanel(at(181.4, 3, -40) * CFrame.Angles(0, math.rad(-90), 0), Z)
	spot(215, 2, "CleanSpill", Z)
	spot(240, -52, "CleanSpill", Z)
	spot(190, 60, "TakeOutTrash", Z)
	spot(230, 55, "LostItem", Z)
	spot(200, -30, "CollectCarts", Z)
	patrolClock(193, 45, Z)
	wallExtinguisher(at(181, 0, 40) * CFrame.Angles(0, math.rad(-90), 0), "Planta baja")
	payPhone(at(181, 0, -55) * CFrame.Angles(0, math.rad(-90), 0), Z)
	enemySpawn(255, 80)
	enemySpawn(255, -80)
	camera(181.8, 13, 60, 225, 0, 20)

	currentParent = map
end

----------------------------------------------------------------------
-- Zona de juegos (planta alta, este)
----------------------------------------------------------------------

local function buildArcade()
	folder("ZonaDeJuegos")
	levelY = F2
	local Z = "Zona de juegos"
	zone(Z, 120, 180, -70, 70, STORE_H)
	slab("Floor", 120, 180, -70, 70, 0, M.Carpet, Color3.fromRGB(28, 22, 48))
	ceiling(120, 180, -70, 70, STORE_H + 1)
	-- Moqueta con dibujos de neon (franjas) tipica de arcade
	for k = -6, 6 do
		deco("CarpetPattern", Vector3.new(58, 0.03, 0.4), at(150, 0.02, k * 10 + 3), M.SmoothPlastic, if k % 2 == 0 then Color3.fromRGB(70, 40, 120) else Color3.fromRGB(30, 90, 120), {
			Variant = false,
		})
	end

	wall(Vector3.new(120.5, 0, -70), Vector3.new(120.5, 0, 70), 18, {
		Openings = { { From = 50, To = 58, Height = 9 }, { From = 82, To = 90, Height = 9 } },
		Color = Color3.fromRGB(40, 30, 60),
	})
	wall(Vector3.new(120, 0, 70.5), Vector3.new(180, 0, 70.5), STORE_H, {
		Openings = { { From = 20, To = 28, Height = 9 } }, -- a las oficinas
		Color = Color3.fromRGB(40, 30, 60),
	})
	exitSign(at(144, 10.2, 69.8))
	local atriumSign = deco("ArcadeSign", Vector3.new(0.4, 4, 26), at(119.8, 11, 0), M.SmoothPlastic, Color3.fromRGB(14, 10, 24))
	litSign(atriumSign, "ZONA DE JUEGOS", Color3.fromRGB(120, 230, 255), Enum.Font.Bangers, Enum.NormalId.Left)
	neonStrip(Vector3.new(0.2, 0.2, 26), at(119.5, 8.8, 0), Color3.fromRGB(255, 60, 200), Z)
	neonStrip(Vector3.new(0.2, 0.2, 26), at(119.5, 13.2, 0), Color3.fromRGB(60, 220, 255), Z)

	-- Filas de maquinas (espalda con espalda)
	local accents = { Color3.fromRGB(255, 60, 200), Color3.fromRGB(60, 220, 255), Color3.fromRGB(255, 200, 40), Color3.fromRGB(120, 255, 120) }
	for row, z in { -48, -34, 34, 48 } do
		for col = 0, 4 do
			local x = 134 + col * 8
			for _, face in { -1, 1 } do
				local cf = at(x, 0, z + face * 1.8) * CFrame.Angles(0, if face > 0 then math.pi else 0, 0)
				local accent = accents[(row + col) % #accents + 1]
				propOr("ArcadeCabinet", cf, function(c)
					box("Arcade", Vector3.new(3, 6.4, 3), c * CFrame.new(0, 3.2, 0), M.SmoothPlastic, accent:Lerp(DARK, 0.55))
					local s = deco("ArcadeScreen", Vector3.new(2.4, 1.8, 0.1), c * CFrame.new(0, 4.6, -1.55), M.SmoothPlastic, DARK)
					glowScreen(s, Enum.NormalId.Front, accent, Color3.fromRGB(20, 10, 40), "PLAY")
					deco("ArcadeMarquee", Vector3.new(2.8, 0.7, 0.2), c * CFrame.new(0, 6.1, -1.4), M.Neon, accent)
				end)
				-- Punto de la mision Reiniciar recreativas (delante de la pantalla)
				local arcadeSpot = box("ArcadeSpot", Vector3.new(2.4, 2.4, 0.4), cf * CFrame.new(0, 4.4, -1.8), M.SmoothPlastic, Color3.new(1, 1, 1), {
					Transparency = 1,
					CanCollide = false,
					CanQuery = false,
					CanTouch = false,
					Variant = false,
				})
				tag(arcadeSpot, Tags.ArcadeMachine, { Zone = Z })
			end
		end
		neonStrip(Vector3.new(40, 0.15, 0.15), at(150, 7.2, z), accents[row], Z, 0.5)
	end
	-- Maquinas de gancho y mesas de hockey de aire
	for i, z in { -14, -4, 6, 16 } do
		propOr("ClawMachine", at(176, 0, z) * CFrame.Angles(0, math.rad(90), 0), function(cf)
			box("ClawMachine", Vector3.new(4, 7, 4), cf * CFrame.new(0, 3.5, 0), M.SmoothPlastic, accents[i])
			deco("ClawGlass", Vector3.new(3.6, 3, 3.6), cf * CFrame.new(0, 5, 0), M.Glass, GLASS, { Transparency = 0.6 })
		end)
	end
	-- Mesas de hockey de aire (modelo 3D con su marcador; los marcadores hacia fuera)
	for _, z in { -12, 12 } do
		local cf = at(150, 0, z) * (if z < 0 then CFrame.Angles(0, math.pi, 0) else CFrame.identity)
		if fitProp("AirHockey", cf, Vector3.new(5, 9, 8.5)) then
			-- El modelo trae el marcador y el tablero sin luz (se veia apagada): marcador
			-- encendido, tablero iluminado con sus lineas, LED en las bandas, disco y mazos.
			-- Medidas del modelo escalado: tablero a 4.83 (x ±2.2, z -4..2.2), marcador en +Z.
			local blue = Color3.fromRGB(40, 140, 255)
			local red = Color3.fromRGB(230, 40, 50)
			local board = deco("ScoreScreen", Vector3.new(3.2, 1.7, 0.08), cf * CFrame.new(0, 7.45, 2.88), M.SmoothPlastic, Color3.fromRGB(10, 10, 16), {
				CastShadow = false,
				Variant = false,
			})
			do
				local gui = surface(board, Enum.NormalId.Front, 40, 0, 1.4)
				local bg = guiFrame(gui, { BackgroundColor3 = Color3.fromRGB(8, 8, 14) })
				guiText(bg, "AIR HOCKEY", { Size = UDim2.fromScale(1, 0.28), Position = UDim2.fromScale(0, 0.04), TextColor3 = Color3.fromRGB(255, 220, 90), Font = Enum.Font.Bangers })
				guiText(bg, if z < 0 then "07" else "03", { Size = UDim2.fromScale(0.42, 0.6), Position = UDim2.fromScale(0.04, 0.34), TextColor3 = red, Font = Enum.Font.Code })
				guiText(bg, ":", { Size = UDim2.fromScale(0.1, 0.5), Position = UDim2.fromScale(0.45, 0.36), TextColor3 = Color3.fromRGB(230, 230, 240), Font = Enum.Font.Code })
				guiText(bg, if z < 0 then "05" else "06", { Size = UDim2.fromScale(0.42, 0.6), Position = UDim2.fromScale(0.54, 0.34), TextColor3 = blue, Font = Enum.Font.Code })
			end
			tag(board, Tags.Light, { Zone = Z })
			-- Tablero iluminado (cara de arriba) con linea central, circulo y porterias
			local field = deco("AirField", Vector3.new(4.0, 0.04, 6.0), cf * CFrame.new(0, 4.86, -0.9), M.SmoothPlastic, Color3.fromRGB(225, 238, 255), {
				CastShadow = false,
				Variant = false,
			})
			do
				local gui = surface(field, Enum.NormalId.Top, 30, 0, 1.1)
				local bg = guiFrame(gui, { BackgroundColor3 = Color3.new(1, 1, 1) })
				gradient(bg, Color3.fromRGB(235, 245, 255), Color3.fromRGB(190, 215, 250), 90)
				-- (en la cara Top el lienzo va a lo largo del eje Z de la pieza: X = largo)
				guiFrame(bg, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.new(0, 3, 1, 0), BackgroundColor3 = red })
				local ring = guiFrame(bg, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.22, 0.33), BackgroundTransparency = 1 })
				local stroke = Instance.new("UIStroke")
				stroke.Color = red
				stroke.Thickness = 3
				stroke.Parent = ring
				local corner = Instance.new("UICorner")
				corner.CornerRadius = UDim.new(0.5, 0)
				corner.Parent = ring
				for _, gx in { 0, 1 } do
					guiFrame(bg, { AnchorPoint = Vector2.new(gx, 0.5), Position = UDim2.fromScale(gx, 0.5), Size = UDim2.fromScale(0.04, 0.4), BackgroundColor3 = blue })
				end
			end
			local fieldLight = Instance.new("SurfaceLight")
			fieldLight.Face = Enum.NormalId.Top
			fieldLight.Range = 6
			fieldLight.Brightness = 0.6
			fieldLight.Color = Color3.fromRGB(190, 220, 255)
			fieldLight.Parent = field
			tag(field, Tags.Light, { Zone = Z })
			-- Tiras LED en las dos bandas
			for _, sx in { -2.15, 2.15 } do
				neonStrip(Vector3.new(0.08, 0.08, 6.2), cf * CFrame.new(sx, 4.95, -0.9), blue, Z)
			end
			-- Disco y dos mazos (rojo y azul)
			deco("Puck", Vector3.new(0.12, 0.6, 0.6), cf * CFrame.new(0.5, 4.94, -0.4) * CFrame.Angles(0, 0, math.rad(90)), M.SmoothPlastic, Color3.fromRGB(20, 20, 24), {
				Shape = Enum.PartType.Cylinder,
				Variant = false,
			})
			for k, mallet in { { -3.0, red }, { 1.3, blue } } do
				local base = cf * CFrame.new(if k == 1 then -0.6 else 0.7, 4.88, mallet[1])
				deco("Mallet", Vector3.new(0.3, 0.95, 0.95), base * CFrame.new(0, 0.15, 0) * CFrame.Angles(0, 0, math.rad(90)), M.SmoothPlastic, mallet[2], {
					Shape = Enum.PartType.Cylinder,
					Variant = false,
				})
				deco("MalletKnob", Vector3.new(0.45, 0.4, 0.4), base * CFrame.new(0, 0.5, 0) * CFrame.Angles(0, 0, math.rad(90)), M.SmoothPlastic, mallet[2], {
					Shape = Enum.PartType.Cylinder,
					Variant = false,
				})
			end
		else
			box("AirHockey", Vector3.new(5, 2.8, 9), cf * CFrame.new(0, 1.4, 0), M.SmoothPlastic, Color3.fromRGB(30, 30, 36))
			local top = deco("AirHockeyTop", Vector3.new(4.6, 0.1, 8.6), cf * CFrame.new(0, 2.85, 0), M.SmoothPlastic, Color3.fromRGB(230, 235, 240))
			glowScreen(top, Enum.NormalId.Top, Color3.fromRGB(200, 230, 255), Color3.fromRGB(140, 180, 255), nil)
		end
	end

	-- Zona de premios: mostrador de canje con vitrina de cristal llena de premios, maquina
	-- de tickets, vitrinas de premios contra la pared, peluches y cartel luminoso
	local gold = Color3.fromRGB(235, 185, 60)
	local counterCF = at(172.5, 0, 30)
	box("PrizeCounter", Vector3.new(2.6, 2.6, 16), counterCF * CFrame.new(0, 1.3, 0), M.SmoothPlastic, Color3.fromRGB(70, 40, 110))
	deco("PrizeCounterKick", Vector3.new(2.7, 0.3, 16.1), counterCF * CFrame.new(0, 0.15, 0), M.SmoothPlastic, Color3.fromRGB(30, 18, 50))
	-- Base de terciopelo de la vitrina, cristal y canto dorado arriba y abajo
	deco("PrizeCounterTrim", Vector3.new(2.8, 0.15, 16.2), counterCF * CFrame.new(0, 2.65, 0), M.Fabric, Color3.fromRGB(45, 20, 70))
	deco("PrizeGlass", Vector3.new(2.5, 1.1, 15.9), counterCF * CFrame.new(0, 3.28, 0), M.Glass, Color3.fromRGB(210, 230, 255), { Transparency = 0.8 })
	deco("PrizeGlassTop", Vector3.new(2.6, 0.06, 16), counterCF * CFrame.new(0, 3.86, 0), M.Glass, Color3.fromRGB(220, 235, 255), { Transparency = 0.6 })
	for _, side in { -1, 1 } do
		deco("PrizeEdge", Vector3.new(0.1, 0.1, 16.1), counterCF * CFrame.new(side * 1.3, 3.88, 0), M.Metal, gold)
		deco("PrizeEdge", Vector3.new(0.1, 0.1, 16.1), counterCF * CFrame.new(side * 1.3, 2.72, 0), M.Metal, gold)
	end
	neonStrip(Vector3.new(0.12, 0.12, 15.8), counterCF * CFrame.new(-1.32, 2.4, 0), Color3.fromRGB(255, 60, 200), Z, 0.4)
	-- Premios pequeños dentro de la vitrina (pelotas, cajitas, peluchitos)
	local prizeColors = { Color3.fromRGB(255, 90, 160), Color3.fromRGB(90, 200, 255), Color3.fromRGB(255, 220, 70), Color3.fromRGB(120, 230, 120), Color3.fromRGB(200, 120, 255) }
	for i = 0, 17 do
		local z = -7.4 + i * 0.87
		local color = prizeColors[i % #prizeColors + 1]
		local x = if i % 2 == 0 then -0.5 else 0.5
		if i % 3 == 0 then
			deco("Prize", Vector3.new(0.55, 0.55, 0.55), counterCF * CFrame.new(x, 3.0, z), M.SmoothPlastic, color, { Shape = Enum.PartType.Ball })
		else
			deco("Prize", Vector3.new(0.5, 0.65, 0.4), counterCF * CFrame.new(x, 3.05, z) * CFrame.Angles(0, math.rad(i * 23), 0), M.SmoothPlastic, color)
		end
	end
	-- Maquina contadora de tickets sobre el mostrador
	local ticketMachine = deco("TicketMachine", Vector3.new(1.1, 1.4, 1.1), counterCF * CFrame.new(0, 4.6, -6.2), M.SmoothPlastic, Color3.fromRGB(28, 28, 36))
	litSign(ticketMachine, "TICKETS", gold, Enum.Font.Bangers, Enum.NormalId.Left)
	deco("TicketSlot", Vector3.new(0.05, 0.12, 0.7), counterCF * CFrame.new(-0.57, 4.1, -6.2), M.Neon, Color3.fromRGB(255, 80, 80))
	for k = 0, 4 do
		deco("TicketStrip", Vector3.new(0.02, 0.5, 0.35), counterCF * CFrame.new(-0.3 + k * 0.12, 3.92, -4.8 + k * 0.15) * CFrame.Angles(0, 0, math.rad(80)), M.SmoothPlastic, Color3.fromRGB(240, 120, 150))
	end
	-- Vitrinas de premios contra la pared (modelo 3D) con peluches encima
	for i = 0, 4 do
		local z = 22.6 + i * 3.7
		local cab = fitProp("PrizeCabinet", at(178.3, 0, z) * CFrame.Angles(0, math.rad(90), 0), Vector3.new(3.4, 5.4, 2.6))
		if cab and i % 2 == 0 then
			fitProp("TeddyBear", at(178.3, 5.4, z) * CFrame.Angles(0, math.rad(90), 0), Vector3.new(1.6, 1.9, 1.6), false)
		end
	end
	-- Cartel luminoso
	local prizeSign = deco("PrizeSign", Vector3.new(0.3, 2.2, 18), at(179.6, 9.2, 30), M.SmoothPlastic, Color3.fromRGB(30, 15, 50))
	litSign(prizeSign, "★ PREMIOS ★", gold, Enum.Font.Bangers, Enum.NormalId.Left)
	neonStrip(Vector3.new(0.2, 0.2, 18.4), at(179.4, 10.5, 30), Color3.fromRGB(255, 60, 200), Z)
	neonStrip(Vector3.new(0.2, 0.2, 18.4), at(179.4, 7.9, 30), Color3.fromRGB(60, 220, 255), Z)
	-- Fotomaton (escondite)
	hidingSpot("Fotomatón", at(124, 3.75, -62) * CFrame.Angles(0, math.rad(-90), 0), Vector3.new(4, 7.5, 4), M.SmoothPlastic, Color3.fromRGB(200, 40, 120))
	hidingSpot("Armario", at(176.8, 3.75, -64) * CFrame.Angles(0, math.rad(90), 0), Vector3.new(4, 7.5, 3), M.Metal, Color3.fromRGB(80, 95, 110))
	vendingMachine(CFrame.lookAt(Vector3.new(178, Y0 + F2 + 3.5, 52), Vector3.new(170, Y0 + F2 + 3.5, 52)), "Cheap", Color3.fromRGB(180, 30, 35), "REFRESCOS")

	for _, x in { 134, 166 } do
		for _, z in { -55, -20, 20, 55 } do
			ceilingPanel(at(x, STORE_H, z), Z, Vector2.new(4, 4), 22, 0.9)
		end
	end

	electricPanel(at(121.4, 3, 64) * CFrame.Angles(0, math.rad(-90), 0), Z)
	spot(140, -24, "CleanSpill", Z)
	spot(160, 26, "CleanSpill", Z)
	spot(130, 60, "TakeOutTrash", Z)
	spot(165, -60, "LostItem", Z)
	spot(150, 0, "ResetArcade", Z)
	wallExtinguisher(at(121, 0, -40) * CFrame.Angles(0, math.rad(-90), 0), "Planta alta")
	payPhone(at(121, 0, 40) * CFrame.Angles(0, math.rad(-90), 0), Z)
	enemySpawn(172, -66)
	camera(178, 14, -68, 150, 0, -30)

	levelY = 0
	currentParent = map
end

----------------------------------------------------------------------
-- Servicio (planta baja, norte): bodega, generador, baños, seguridad, escalera
----------------------------------------------------------------------

-- Hueco de la escalera de servicio (planta baja -> oficinas)
local STAIR = { X1 = 146, X2 = 172, Z1 = 100, Z2 = 106 }
local STAIR_HOLE = { STAIR.X1, STAIR.X2, STAIR.Z1 - 1, STAIR.Z2 + 1 }

local function serviceStairs()
	local W = STAIR.Z2 - STAIR.Z1
	local zc = (STAIR.Z1 + STAIR.Z2) / 2
	local ramp = rampBody("ServiceStairs", STAIR.X1, STAIR.X2, zc, W, M.Concrete, Color3.fromRGB(150, 150, 146))
	tag(ramp, Tags.FloorConnector, {
		Low = Vector3.new(STAIR.X1, Y0, zc),
		High = Vector3.new(STAIR.X2, Y0 + F2, zc),
		Width = W,
	})
	-- Peldaños (visuales) sobre la rampa
	local steps = 16
	for i = 0, steps - 1 do
		local x = STAIR.X1 + (i + 0.5) * (STAIR.X2 - STAIR.X1) / steps
		local y = (i + 1) * F2 / steps
		deco("StairTread", Vector3.new((STAIR.X2 - STAIR.X1) / steps + 0.05, 0.3, W), at(x, y - 0.15, zc), M.Concrete, Color3.fromRGB(165, 165, 160))
		deco("StairNosing", Vector3.new(0.25, 0.32, W), at(x - (STAIR.X2 - STAIR.X1) / steps / 2, y - 0.15, zc), M.SmoothPlastic, Color3.fromRGB(240, 190, 20), {
			Variant = false,
		})
	end
	-- Barandillas a los lados
	local low = Vector3.new(STAIR.X1, Y0, zc)
	local high = Vector3.new(STAIR.X2, Y0 + F2, zc)
	local mid = (low + high) / 2
	local slope = CFrame.lookAt(mid, high)
	for _, side in { -1, 1 } do
		box("StairRail", Vector3.new(0.2, 3.4, (high - low).Magnitude), slope * CFrame.new(side * (W / 2 + 0.1), 1.7, 0), M.Metal, Color3.fromRGB(240, 190, 20), {
			Transparency = 0.999,
			Variant = false,
		})
		deco("StairHandrail", Vector3.new(0.25, 0.25, (high - low).Magnitude), slope * CFrame.new(side * (W / 2 + 0.1), 3.2, 0), M.Metal, Color3.fromRGB(240, 190, 20))
	end
end

----------------------------------------------------------------------
-- Baños: inodoros, cubiculos, urinarios y lavabos hechos con piezas
----------------------------------------------------------------------
-- Convencion: `cf` es un punto del SUELO pegado a la cara interior de la pared, mirando
-- hacia la sala (LookVector = hacia fuera de la pared). Todo se coloca en local con z < 0.

local PORCELAIN = Color3.fromRGB(240, 240, 236)
local CHROME = Color3.fromRGB(205, 208, 212)
local PARTITION = Color3.fromRGB(92, 116, 132)

-- Cilindro vertical (los cilindros de Roblox van a lo largo de X)
local function vcyl(name: string, height: number, diameter: number, cf: CFrame, material, color: Color3, props): Part
	local all = { Shape = Enum.PartType.Cylinder }
	for k, v in props or {} do
		all[k] = v
	end
	return deco(name, Vector3.new(height, diameter, diameter), cf * CFrame.Angles(0, 0, math.rad(90)), material, color, all)
end

-- Inodoro con tanque, taza, agua y tapa levantada. Si `zoneName` viene, la base es el
-- punto de la mision Desatascar (su LookVector mira a la sala: el charco sale delante).
local function toilet(cf: CFrame, zoneName: string?)
	local base = box("Toilet", Vector3.new(1.2, 1.3, 1.7), cf * CFrame.new(0, 0.65, -1.6), M.SmoothPlastic, PORCELAIN, { Variant = false })
	if zoneName then
		tag(base, Tags.MissionSpot, { MissionType = "UnclogToilet", Zone = zoneName })
	end
	vcyl("ToiletBowl", 0.75, 2, cf * CFrame.new(0, 1.55, -2), M.SmoothPlastic, PORCELAIN, { CanCollide = true })
	deco("ToiletNeck", Vector3.new(1.5, 0.75, 1.1), cf * CFrame.new(0, 1.55, -1.05), M.SmoothPlastic, PORCELAIN)
	vcyl("ToiletWater", 0.04, 1.45, cf * CFrame.new(0, 1.94, -2.05), M.Glass, Color3.fromRGB(150, 165, 150), { Transparency = 0.15, CastShadow = false })
	box("ToiletTank", Vector3.new(2, 1.7, 0.8), cf * CFrame.new(0, 3, -0.45), M.SmoothPlastic, PORCELAIN, { Variant = false })
	deco("TankLid", Vector3.new(2.15, 0.16, 0.95), cf * CFrame.new(0, 3.93, -0.45), M.SmoothPlastic, PORCELAIN)
	deco("FlushHandle", Vector3.new(0.45, 0.1, 0.12), cf * CFrame.new(-0.7, 3.55, -0.9), M.Metal, CHROME, { Reflectance = 0.3 })
	-- Tapa y asiento levantados, apoyados en el tanque
	deco("ToiletLid", Vector3.new(1.9, 1.9, 0.14), cf * CFrame.new(0, 2.9, -0.98) * CFrame.Angles(math.rad(-6), 0, 0), M.SmoothPlastic, PORCELAIN)
	-- Toma de agua cromada
	vcyl("SupplyPipe", 1.6, 0.18, cf * CFrame.new(-0.75, 1.2, -0.15), M.Metal, CHROME, { Reflectance = 0.3 })
	deco("SupplyValve", Vector3.new(0.3, 0.3, 0.3), cf * CFrame.new(-0.75, 0.5, -0.25), M.Metal, CHROME)
end

-- Fila de cubiculos contra la pared del fondo. `xs` = centro de cada cubiculo (mundo),
-- `zWall` = cara interior de la pared (la sala queda hacia -Z). `skipX` = linderos que
-- coinciden con una pared (no se pone mampara). `closed` = indice del cubiculo cerrado
-- "fuera de servicio" (no tiene mision y algo se ve bajo la puerta...).
local function stallRow(xs: { number }, zWall: number, zoneName: string, opts)
	opts = opts or {}
	local W, D = opts.Width or 5.5, opts.Depth or 6.5
	local zf = zWall - D -- frente de los cubiculos
	local doorAngles = { 78, 64, 85, 70 }
	local function partition(b: number)
		for _, s in opts.SkipX or {} do
			if math.abs(b - s) < 0.3 then
				return
			end
		end
		box("StallWall", Vector3.new(0.15, 6.4, D), at(b, 4, zWall - D / 2), M.SmoothPlastic, PARTITION, { Variant = false })
		deco("StallFoot", Vector3.new(0.25, 0.8, 0.25), at(b, 0.4, zf + 0.35), M.Metal, CHROME)
	end
	partition(xs[1] - W / 2)
	for i, x in xs do
		partition(x + W / 2)
		local isClosed = opts.Closed == i
		toilet(at(x, 0, zWall), if isClosed then nil else zoneName)
		-- Frente: dos pilastras y la puerta (abatida hacia dentro)
		for _, side in { -1, 1 } do
			local x0, x1 = x + side * 1.3, x + side * W / 2
			box("StallFront", Vector3.new(math.abs(x1 - x0), 6.4, 0.15), at((x0 + x1) / 2, 4, zf), M.SmoothPlastic, PARTITION, { Variant = false })
		end
		local hinge = at(x + 1.3, 3.8, zf)
		local angle = if isClosed then 0 else doorAngles[(i - 1) % #doorAngles + 1]
		local doorCF = hinge * CFrame.Angles(0, math.rad(angle), 0) * CFrame.new(-1.25, 0, 0)
		local door = make("Part", "StallDoor", Vector3.new(2.5, 6, 0.12), doorCF, M.SmoothPlastic, PARTITION, {
			CanCollide = isClosed,
			CanQuery = isClosed,
			Variant = false,
		})
		deco("DoorLatch", Vector3.new(0.35, 0.2, 0.25), doorCF * CFrame.new(-1.05, 0, 0), M.Metal, CHROME, { Reflectance = 0.3 })
		deco("CoatHook", Vector3.new(0.12, 0.3, 0.3), doorCF * CFrame.new(0, 2.3, 0.2), M.Metal, CHROME)
		-- Portarrollos en la mampara derecha
		deco("PaperHolder", Vector3.new(0.18, 0.5, 0.75), at(x + W / 2 - 0.17, 2.7, zWall - 2.3), M.Metal, CHROME, { Reflectance = 0.25 })
		deco("PaperRoll", Vector3.new(0.6, 0.55, 0.55), at(x + W / 2 - 0.5, 2.5, zWall - 2.3) * CFrame.Angles(0, math.rad(90), 0), M.Fabric, Color3.fromRGB(245, 244, 238), {
			Shape = Enum.PartType.Cylinder,
		})
		if isClosed then
			local plate = deco("OutOfOrder", Vector3.new(2, 0.9, 0.05), doorCF * CFrame.new(0, 0.8, -0.09), M.SmoothPlastic, Color3.fromRGB(240, 200, 40))
			sign(plate, "FUERA DE SERVICIO", Color3.fromRGB(30, 30, 30), Enum.Font.GothamBlack, Enum.NormalId.Front)
			-- Unos zapatos se ven por debajo de la puerta cerrada
			for _, sx in { -0.35, 0.35 } do
				deco("Shoe", Vector3.new(0.4, 0.35, 0.95), at(x + sx, 0.18, zWall - 3.3), M.Leather, Color3.fromRGB(28, 24, 22))
			end
		end
	end
	-- Barra superior de los cubiculos
	local left, right = xs[1] - W / 2, xs[#xs] + W / 2
	deco("StallRail", Vector3.new(right - left, 0.15, 0.15), at((left + right) / 2, 7.3, zf), M.Metal, CHROME, { Reflectance = 0.3 })
end

-- Urinario de pared con tuberia de descarga
local function urinal(cf: CFrame)
	box("Urinal", Vector3.new(1.5, 2.6, 1.1), cf * CFrame.new(0, 3.3, -0.55), M.SmoothPlastic, PORCELAIN, { Variant = false })
	deco("UrinalBasin", Vector3.new(1.1, 1.8, 0.05), cf * CFrame.new(0, 3.4, -1.12), M.SmoothPlastic, Color3.fromRGB(222, 226, 226))
	deco("UrinalLip", Vector3.new(1.6, 0.25, 1.35), cf * CFrame.new(0, 2.05, -0.65), M.SmoothPlastic, PORCELAIN)
	vcyl("FlushPipe", 1.4, 0.18, cf * CFrame.new(0, 5.3, -0.25), M.Metal, CHROME, { Reflectance = 0.3 })
	deco("FlushValve", Vector3.new(0.5, 0.4, 0.45), cf * CFrame.new(0, 6, -0.3), M.Metal, CHROME, { Reflectance = 0.3 })
	deco("UrinalCake", Vector3.new(0.5, 0.08, 0.4), cf * CFrame.new(0, 2.25, -0.75), M.SmoothPlastic, Color3.fromRGB(120, 200, 210))
end

-- Encimera con `n` lavabos, grifos, jaboneras y espejo. `cracked` = espejo roto.
-- faucetZone: los caños son grifos de la mision Cerrar grifos (tag Faucet con esa zona).
local function vanity(cf: CFrame, n: number, spacing: number, cracked: boolean?, faucetZone: string?)
	local len = n * spacing + 1
	box("Counter", Vector3.new(len, 0.35, 2.2), cf * CFrame.new(0, 3, -1.1), M.Marble, Color3.fromRGB(70, 72, 76))
	deco("CounterSkirt", Vector3.new(len, 0.8, 0.1), cf * CFrame.new(0, 2.45, -2.15), M.Marble, Color3.fromRGB(60, 62, 66))
	for i = 1, n do
		local lx = (i - (n + 1) / 2) * spacing
		vcyl("Basin", 0.06, 1.5, cf * CFrame.new(lx, 3.19, -1.1), M.SmoothPlastic, PORCELAIN)
		vcyl("Drain", 0.07, 0.25, cf * CFrame.new(lx, 3.2, -1.1), M.Metal, Color3.fromRGB(60, 60, 62))
		vcyl("Faucet", 0.7, 0.2, cf * CFrame.new(lx, 3.5, -0.35), M.Metal, CHROME, { Reflectance = 0.35 })
		local spout = deco("Spout", Vector3.new(0.14, 0.14, 0.55), cf * CFrame.new(lx, 3.8, -0.6), M.Metal, CHROME, { Reflectance = 0.35 })
		if faucetZone then
			tag(spout, Tags.Faucet, { Zone = faucetZone })
		end
		vcyl("Trap", 0.9, 0.2, cf * CFrame.new(lx, 2.35, -0.9), M.Metal, CHROME)
		if i < n then
			-- Jabonera de bomba sobre la encimera, entre dos lavabos
			vcyl("SoapBottle", 0.6, 0.4, cf * CFrame.new(lx + spacing / 2, 3.48, -0.45), M.SmoothPlastic, Color3.fromRGB(235, 235, 232))
			deco("SoapPump", Vector3.new(0.12, 0.25, 0.3), cf * CFrame.new(lx + spacing / 2, 3.9, -0.5), M.Metal, CHROME)
		end
	end
	local mirror = deco("Mirror", Vector3.new(len - 0.4, 3.4, 0.08), cf * CFrame.new(0, 6, -0.06), M.Glass, Color3.fromRGB(205, 215, 220), { Reflectance = 0.55 })
	tag(mirror, Tags.ReflectiveSurface)
	for _, y in { 4.25, 7.75 } do
		deco("MirrorTrim", Vector3.new(len - 0.3, 0.12, 0.14), cf * CFrame.new(0, y, -0.08), M.Metal, CHROME)
	end
	if cracked then
		-- Grietas que salen de un golpe en el espejo
		local hitX = -spacing / 2
		for k, a in { 20, 75, 140, 200, 290, 330 } do
			local length = 0.8 + (k % 3) * 0.5
			deco("MirrorCrack", Vector3.new(length, 0.05, 0.02), cf * CFrame.new(hitX, 6.2, -0.11) * CFrame.Angles(0, 0, math.rad(a)) * CFrame.new(length / 2, 0, 0), M.SmoothPlastic, Color3.fromRGB(35, 38, 40), { CastShadow = false })
		end
	end
end

-- Detalles de ambiente: secamanos, papelera, desague, tubo fluorescente muerto, cubo con fregona
local function handDryer(cf: CFrame)
	deco("HandDryer", Vector3.new(1.3, 1.5, 0.8), cf * CFrame.new(0, 4.6, -0.4), M.SmoothPlastic, Color3.fromRGB(225, 226, 228), { Variant = false })
	deco("DryerNozzle", Vector3.new(0.4, 0.3, 0.4), cf * CFrame.new(0, 3.75, -0.55), M.SmoothPlastic, Color3.fromRGB(150, 152, 156), { Variant = false })
	deco("DryerLabel", Vector3.new(0.8, 0.25, 0.05), cf * CFrame.new(0, 4.9, -0.82), M.SmoothPlastic, Color3.fromRGB(60, 62, 66))
end

local function bathDetails(center: CFrame, binCF: CFrame, bucketCF: CFrame)
	deco("FloorDrain", Vector3.new(0.9, 0.04, 0.9), center * CFrame.new(0, 0.07, 0), M.DiamondPlate, Color3.fromRGB(135, 136, 138))
	-- Manchas y un charco
	deco("FloorStain", Vector3.new(3, 0.02, 1.8), center * CFrame.new(-4, 0.07, 4) * CFrame.Angles(0, 0.6, 0), M.SmoothPlastic, Color3.fromRGB(120, 105, 70), { Transparency = 0.55, CastShadow = false })
	deco("FloorPuddle", Vector3.new(2.4, 0.02, 1.5), center * CFrame.new(3, 0.07, -2) * CFrame.Angles(0, -0.3, 0), M.Glass, Color3.fromRGB(170, 185, 190), { Transparency = 0.4, Reflectance = 0.3, CastShadow = false })
	vcyl("TrashBin", 2.2, 1.4, binCF * CFrame.new(0, 1.1, 0), M.Metal, Color3.fromRGB(150, 152, 156), { CanCollide = true })
	vcyl("TrashPaper", 0.3, 1.1, binCF * CFrame.new(0, 2.3, 0), M.Fabric, Color3.fromRGB(235, 232, 225))
	-- Cubo amarillo con fregona apoyada
	vcyl("MopBucket", 1.4, 1.6, bucketCF * CFrame.new(0, 0.7, 0), M.Plastic, Color3.fromRGB(240, 195, 30), { CanCollide = true })
	deco("MopHandle", Vector3.new(0.15, 5.2, 0.15), bucketCF * CFrame.new(0.2, 2.9, 0) * CFrame.Angles(0, 0, math.rad(-14)), M.Wood, Color3.fromRGB(150, 120, 80))
	-- Fluorescente fundido (sin luz) colgando de una cadena
	local tubeCF = center * CFrame.new(0, 13.5, 0)
	deco("DeadFixture", Vector3.new(1.2, 0.3, 8), tubeCF, M.Metal, Color3.fromRGB(200, 200, 198))
	deco("DeadTube", Vector3.new(0.3, 0.3, 7.6), tubeCF * CFrame.new(0, -0.25, 0), M.SmoothPlastic, Color3.fromRGB(150, 150, 145))
end

local function buildService()
	folder("Servicio")
	levelY = 0
	zone("Bodega", -180, -90, 70, 110, SERVICE_H)
	-- (el pasaje al Ala Norte, x -24..24, parte el servicio en dos)
	zone("Servicio Oeste", -90, -WING, 70, 110, SERVICE_H)
	zone("Servicio", WING, 180, 70, 110, SERVICE_H)

	slab("Floor", -180, -WING, 70, 110, 0, M.Concrete, Color3.fromRGB(125, 125, 122))
	slab("Floor", WING, 180, 70, 110, 0, M.Concrete, Color3.fromRGB(125, 125, 122))
	slab("Ceiling", -180, -WING, 70, 110, SERVICE_H + 1, M.Concrete, Color3.fromRGB(95, 95, 98))
	slabWithHole("Ceiling", WING, 180, 70, 110, SERVICE_H + 1, STAIR_HOLE, M.Concrete, Color3.fromRGB(95, 95, 98))
	local grey = Color3.fromRGB(165, 165, 160)
	-- Separacion bodega / pasillo, con puerta
	wall(Vector3.new(-90, 0, 70), Vector3.new(-90, 0, 110), SERVICE_H, {
		Material = M.Concrete,
		Color = grey,
		Openings = { { From = 10, To = 24, Height = 10 } },
	})

	-- Bodega: estanterias con cajas, palets (reponer), contenedor (basura)
	for _, z in { 80, 96 } do
		for _, x in { -160, -130 } do
			storageRack(at(x, 0, z), 18)
		end
	end
	for _, x in { -112, -100 } do
		local pallet = box("Pallet", Vector3.new(5, 0.6, 5), at(x, 0.3, 102), M.WoodPlanks, Color3.fromRGB(160, 125, 80))
		tag(pallet, Tags.StockPickup)
		palletBoxes(x, 103.4)
	end
	tag(dumpster(at(-150, 0, 107)), Tags.TrashDropoff)
	box("LoadingDoor", Vector3.new(16, 10, 0.4), at(-130, 5, 110), M.DiamondPlate, Color3.fromRGB(150, 150, 150))
	deco("LoadingStripes", Vector3.new(16, 0.5, 0.45), at(-130, 10.3, 110), M.SmoothPlastic, Color3.fromRGB(240, 190, 20), { Variant = false })
	hidingSpot("Casillero", at(-178.4, 3.75, 80) * CFrame.Angles(0, math.rad(-90), 0), Vector3.new(4, 7.5, 3), M.Metal, Color3.fromRGB(70, 90, 110))
	hidingSpot("Casillero", at(-178.4, 3.75, 86) * CFrame.Angles(0, math.rad(-90), 0), Vector3.new(4, 7.5, 3), M.Metal, Color3.fromRGB(70, 90, 110))
	-- Bodega a oscuras: solo luces de emergencia
	for _, x in { -160, -115 } do
		emergencyLight(at(x, SERVICE_H, 88))
	end
	propOr("JanitorCart", at(-96, 0, 74) * CFrame.Angles(0, math.rad(-90), 0), function() end)
	enemySpawn(-120, 90)
	-- Puntos de las misiones de entrega (paquetes en los palets) y ronda de seguridad
	spot(-106, 92, "Delivery", "Bodega")
	patrolClock(-94, 104, "Bodega")
	patrolClock(100, 74, "Servicio")
	-- Pasillo de servicio: extintor y telefono en la pared de las tiendas; valvulas de la
	-- caldera en la pared norte
	wallExtinguisher(at(30, 0, 70) * CFrame.Angles(0, math.pi, 0), "Planta baja")
	payPhone(at(-30, 0, 70) * CFrame.Angles(0, math.pi, 0), "Servicio Oeste")
	boilerValve(at(-87, 0, 110), "Servicio Oeste")
	boilerValve(at(110, 0, 110), "Servicio")

	-- Generador (mision Reiniciar generador: deja sin luz Servicio y Bodega)
	local genPanel = generatorSet(-70, 105)
	box("GeneratorPipe", Vector3.new(1.2, 8, 1.2), at(-74, 10, 107), M.Metal, METAL)
	tag(genPanel, Tags.MissionSpot, { MissionType = "RestartGenerator", Zone = "Servicio Oeste", PowersZones = "Patio de comidas,Entrada" })

	-- Baños (al oeste del pasaje al Ala Norte: x -64.5..-24.5; la pared este es la del pasaje)
	local BX = -44.5
	wall(Vector3.new(BX - 20, 0, 88), Vector3.new(BX + 20, 0, 88), SERVICE_H, {
		Material = M.CeramicTiles,
		Color = Color3.fromRGB(220, 225, 228),
		Openings = { { From = 16, To = 24, Height = 9 } },
	})
	wall(Vector3.new(BX - 20, 0, 88), Vector3.new(BX - 20, 0, 110), SERVICE_H, { Material = M.CeramicTiles, Color = Color3.fromRGB(220, 225, 228) })
	deco("BathWallTile", Vector3.new(0.08, SERVICE_H, 21), at(BX + 19.46, SERVICE_H / 2, 99), M.CeramicTiles, Color3.fromRGB(220, 225, 228))
	deco("BathFloor", Vector3.new(40, 0.05, 22), at(BX, 0.03, 99), M.CeramicTiles, Color3.fromRGB(235, 238, 240))
	local bathSign = box("BathSign", Vector3.new(6, 1.2, 0.2), at(BX, 10, 87.4), M.SmoothPlastic, Color3.fromRGB(30, 60, 120), { CanCollide = false })
	litSign(bathSign, "BAÑOS", Color3.new(1, 1, 1), Enum.Font.GothamBold, Enum.NormalId.Back)
	-- 4 cubiculos al fondo (el ultimo cerrado, "fuera de servicio"), 3 urinarios,
	-- lavabos con espejo en la pared este (uno roto), secamanos, papelera y fregona
	stallRow({ BX - 16.75, BX - 11.25, BX - 5.75, BX - 0.25 }, 109.5, "Servicio Oeste", { SkipX = { BX - 19.5 }, Closed = 4 })
	for i, x in { 6, 9.5, 13 } do
		urinal(at(BX + x, 0, 109.5))
		if i < 3 then
			deco("UrinalScreen", Vector3.new(0.12, 3.2, 1.8), at(BX + x + 1.75, 4, 108.6), M.SmoothPlastic, PARTITION)
		end
	end
	local eastWall = CFrame.Angles(0, math.rad(90), 0) -- mirando a -X
	vanity(at(BX + 19.5, 0, 96) * eastWall, 3, 3, true, "Baños")
	spot(BX, 95, "CloseFaucets", "Baños")
	handDryer(at(BX + 19.5, 0, 103) * eastWall)
	handDryer(at(BX - 19.5, 0, 96) * CFrame.Angles(0, math.rad(-90), 0))
	bathDetails(at(BX, 0, 97), at(BX + 18, 0, 89.8), at(BX - 17.5, 0, 91))

	-- Oficina de seguridad (mision Revisar camaras) con taquillas
	wall(Vector3.new(60, 0, 88), Vector3.new(92, 0, 88), SERVICE_H, {
		Material = M.Plaster,
		Color = Color3.fromRGB(190, 195, 200),
		Openings = { { From = 10, To = 18, Height = 9 } },
	})
	for _, x in { 60, 92 } do
		wall(Vector3.new(x, 0, 88), Vector3.new(x, 0, 110), SERVICE_H, { Material = M.Plaster, Color = Color3.fromRGB(190, 195, 200) })
	end
	local secSign = box("SecuritySign", Vector3.new(8, 1.2, 0.2), at(74, 10, 87.4), M.SmoothPlastic, Color3.fromRGB(20, 20, 24), { CanCollide = false })
	litSign(secSign, "SEGURIDAD", Color3.fromRGB(255, 80, 80), Enum.Font.GothamBold, Enum.NormalId.Back)
	-- (mesa y monitores hacia el oeste: en x 77..83 esta la puerta trasera al pasillo de servicio del Ala Norte)
	box("SecurityDesk", Vector3.new(12, 3, 3), at(70, 1.5, 104), M.Wood, Color3.fromRGB(110, 85, 60))
	-- Pared de 6 monitores con imagen de camaras; la pieza "Monitors" (invisible) es el
	-- punto de la mision Revisar camaras y hace de colision
	local monitors = box("Monitors", Vector3.new(10, 3.2, 0.6), at(70, 5, 105.2), M.Glass, Color3.fromRGB(20, 40, 60), {
		Transparency = 1,
		Variant = false,
	})
	tag(monitors, Tags.MissionSpot, { MissionType = "CheckCameras", Zone = "Servicio" })
	local screenGlow = Instance.new("PointLight")
	screenGlow.Color = Color3.fromRGB(150, 210, 170)
	screenGlow.Range = 10
	screenGlow.Brightness = 0.6
	screenGlow.Parent = monitors
	monitorWall(at(70, 5, 105.1), {
		{ "CAM 01", "GALERIA P1" },
		{ "CAM 02", "ENTRADA" },
		{ "CAM 03", "PATIO COMIDAS" },
		{ "CAM 04", "ESTACIONAM." },
		{ "CAM 05", "BODEGA", "Figure" },
		{ "CAM 06", "ALA SUR", "NoSignal" },
	})
	securityDeskTop(at(70, 3, 103.3))
	officeChair(at(70, 0, 100.4) * CFrame.Angles(0, math.pi, 0))
	hidingSpot("Taquilla", at(89.6, 3.75, 94) * CFrame.Angles(0, math.rad(90), 0), Vector3.new(4, 7.5, 3), M.Metal, Color3.fromRGB(70, 90, 110))
	hidingSpot("Taquilla", at(89.6, 3.75, 99) * CFrame.Angles(0, math.rad(90), 0), Vector3.new(4, 7.5, 3), M.Metal, Color3.fromRGB(70, 90, 110))

	-- Escalera a las oficinas (planta alta)
	serviceStairs()
	local stairSign = deco("StairSign", Vector3.new(5, 1, 0.2), at(140, 9, 99.4), M.SmoothPlastic, DARK)
	litSign(stairSign, "▲ OFICINAS P2", Color3.fromRGB(240, 200, 40), Enum.Font.GothamBold, Enum.NormalId.Front)

	-- Instalaciones vistas: tuberia, bandeja de cables, conductos y franjas de seguridad
	-- (cortadas donde pasa el pasaje al Ala Norte)
	-- Tuberia redonda con manguitos cada 8 studs, conducto de chapa con bridas cada 6 y
	-- colgadores al techo; bandeja de cables lisa.
	local function run(name: string, x1: number, x2: number, y: number, z: number, size: Vector2, material, color: Color3)
		for _, seg in { { x1, -WING - 0.5 }, { WING + 0.5, x2 } } do
			local length = seg[2] - seg[1]
			if length > 1 then
				local mid = at((seg[1] + seg[2]) / 2, y, z)
				if name == "Pipe" then
					deco(name, Vector3.new(length, size.X, size.Y), mid, material, color, { Shape = Enum.PartType.Cylinder })
				else
					deco(name, Vector3.new(length, size.X, size.Y), mid, material, color)
				end
				local step = if name == "Pipe" then 8 elseif name == "AirDuct" then 6 else 0
				if step > 0 then
					local k = 0
					local x = seg[1] + step / 2
					while x < seg[2] - 0.5 do
						if name == "Pipe" then
							deco("PipeCoupling", Vector3.new(0.4, size.X + 0.2, size.Y + 0.2), at(x, y, z), M.Metal, Color3.fromRGB(95, 98, 104), { Shape = Enum.PartType.Cylinder })
						else
							deco("DuctFlange", Vector3.new(0.22, size.X + 0.16, size.Y + 0.16), at(x, y, z), M.Metal, color:Lerp(Color3.new(0, 0, 0), 0.12))
						end
						-- Colgador: varilla roscada hasta el techo y abrazadera
						if k % 2 == 0 then
							local top = SERVICE_H
							local bottom = y + size.X / 2
							if top - bottom > 0.1 then
								deco("Hanger", Vector3.new(0.08, top - bottom, 0.08), at(x + 0.6, (top + bottom) / 2, z), M.Metal, Color3.fromRGB(70, 72, 76))
							end
							deco("HangerClamp", Vector3.new(0.12, size.X + 0.12, size.Y + 0.12), at(x + 0.6, y, z), M.Metal, Color3.fromRGB(70, 72, 76))
						end
						k += 1
						x += step
					end
				end
			end
		end
	end
	run("Pipe", -90, 180, SERVICE_H - 1.5, 109, Vector2.new(1, 1), M.Metal, METAL)
	run("CableTray", -175, 175, SERVICE_H - 0.9, 73, Vector2.new(0.3, 1.6), M.Metal, Color3.fromRGB(150, 150, 150))
	run("AirDuct", -180, 140, SERVICE_H - 0.8, 104, Vector2.new(1.6, 2.4), M.Metal, Color3.fromRGB(185, 188, 190))
	for x = -170, 170, 40 do
		if math.abs(x) > 22 and (x < 58 or x > 94) then
			deco("HazardStripe", Vector3.new(4, 0.04, 0.5), at(x, 0.02, 71.4), M.SmoothPlastic, Color3.fromRGB(240, 190, 20), { Variant = false })
		end
	end
	for x = -75, 165, 30 do
		if math.abs(x) > 22 and (x < 58 or x > 94) then
			if (x + 75) % 60 == 0 then
				emergencyLight(at(x, SERVICE_H, 78), x % 2 == 0)
			end
		end
	end
	emergencyLight(at(BX, SERVICE_H, 99))
	emergencyLight(at(150, SERVICE_H, 96), true)
	for _, x in { -60, 30, 120 } do
		exitSign(at(x, SERVICE_H - 2.4, 71.2) * CFrame.Angles(0, math.pi, 0))
	end
	-- Salidas al pasillo de servicio del Ala Norte (puertas en el muro norte)
	exitSign(at(-79, 10.4, 109.2))
	exitSign(at(80, 10.4, 109.2))
	spot(-40, 80, "CleanSpill", "Servicio Oeste")
	spot(130, 82, "CleanSpill", "Servicio")
	enemySpawn(40, 100)
	enemySpawn(120, 92)
	enemySpawn(-55, 80)
	camera(-30, 12, 72, 10, 0, 90)
	camera(150, 12, 74, 115, 0, 82)

	currentParent = map
end

----------------------------------------------------------------------
-- Oficinas (planta alta, norte)
----------------------------------------------------------------------

local function buildOffices()
	folder("Oficinas")
	levelY = F2
	local OFF = "Oficinas"
	-- (el pasaje al Ala Norte, x -24..24, cruza las oficinas: salas reorganizadas a los lados)
	zone("Almacén alto", -180, -90, 70, 110, STORE_H)
	zone("Oficinas Oeste", -90, -WING, 70, 82, STORE_H)
	zone(OFF, WING, 130, 70, 82, STORE_H)
	zone("Escalera de servicio", 130, 180, 70, 110, STORE_H)
	zone("Administración", -90, -64, 82, 110, STORE_H)
	zone("Sala de descanso", -64, -WING, 82, 110, STORE_H)
	zone("Baños P2", WING, 54.5, 82, 110, STORE_H)
	zone("Archivo", 54.5, 80, 82, 110, STORE_H)
	zone("Sala de máquinas", 80, 130, 82, 110, STORE_H)

	slab("Floor", -180, -WING, 70, 110, 0, M.Concrete, Color3.fromRGB(150, 150, 146))
	slabWithHole("Floor", WING, 180, 70, 110, 0, STAIR_HOLE, M.Concrete, Color3.fromRGB(150, 150, 146))
	deco("CorridorVinyl", Vector3.new(66, 0.04, 12), at(-57, 0.02, 76), M.SmoothPlastic, Color3.fromRGB(190, 192, 188), { Variant = false })
	deco("CorridorVinyl", Vector3.new(106, 0.04, 12), at(77, 0.02, 76), M.SmoothPlastic, Color3.fromRGB(190, 192, 188), { Variant = false })
	ceiling(-180, -WING, 70, 110, STORE_H + 1)
	ceiling(WING, 180, 70, 110, STORE_H + 1)

	local officeWall = Color3.fromRGB(205, 205, 200)
	wall(Vector3.new(-90, 0, 70), Vector3.new(-90, 0, 110), STORE_H, {
		Color = officeWall,
		Openings = { { From = 2, To = 10, Height = 9 } },
	})
	-- Pasillo / habitaciones (puerta de cada sala), a cada lado del pasaje
	wall(Vector3.new(-90, 0, 82), Vector3.new(-WING - 0.5, 0, 82), STORE_H, {
		Color = officeWall,
		Openings = {
			{ From = 10, To = 18, Height = 9 }, -- administracion
			{ From = 42, To = 50, Height = 9 }, -- descanso
		},
	})
	wall(Vector3.new(WING + 0.5, 0, 82), Vector3.new(130, 0, 82), STORE_H, {
		Color = officeWall,
		Openings = {
			{ From = 11, To = 19, Height = 9 }, -- baños
			{ From = 38.5, To = 46.5, Height = 9 }, -- archivo
			{ From = 76.5, To = 84.5, Height = 9 }, -- maquinas
		},
	})
	for _, x in { -64, 54.5, 80, 130 } do
		wall(Vector3.new(x, 0, 82), Vector3.new(x, 0, 110), STORE_H, { Color = officeWall })
	end
	-- Rotulos de las puertas
	for _, r in { { -76, "ADMINISTRACIÓN" }, { -44, "DESCANSO" }, { 39.5, "BAÑOS" }, { 67, "ARCHIVO" }, { 105, "MÁQUINAS" } } do
		local plate = deco("DoorPlate", Vector3.new(5, 0.9, 0.12), at(r[1], 10, 81.4), M.SmoothPlastic, Color3.fromRGB(40, 44, 52))
		litSign(plate, r[2], Color3.fromRGB(220, 220, 220), Enum.Font.GothamBold, Enum.NormalId.Front)
	end

	-- Barandilla alrededor del hueco de la escalera (el lado de llegada, x=172, queda abierto)
	railing(Vector3.new(STAIR_HOLE[1], 0, STAIR_HOLE[3]), Vector3.new(STAIR_HOLE[2], 0, STAIR_HOLE[3]))
	railing(Vector3.new(STAIR_HOLE[1], 0, STAIR_HOLE[4]), Vector3.new(STAIR_HOLE[2], 0, STAIR_HOLE[4]))
	railing(Vector3.new(STAIR_HOLE[1], 0, STAIR_HOLE[3]), Vector3.new(STAIR_HOLE[1], 0, STAIR_HOLE[4]))
	local stairSign = deco("StairSign", Vector3.new(5, 1, 0.2), at(176, 9, 99.4), M.SmoothPlastic, DARK)
	litSign(stairSign, "▼ PLANTA BAJA", Color3.fromRGB(240, 200, 40), Enum.Font.GothamBold, Enum.NormalId.Front)

	-- Luces (fluorescentes frios)
	-- Zona de oficinas a oscuras: luces de emergencia espaciadas en el pasillo y una por sala
	for x = -160, 170, 55 do
		if math.abs(x) > WING + 2 then
			emergencyLight(at(x, STORE_H, 76), x % 2 == 0)
		end
	end
	for _, rx in { -77, -44, 39.5, 67, 105, 155 } do
		emergencyLight(at(rx, STORE_H, 98))
	end
	emergencyLight(at(-140, STORE_H, 95))

	-- Almacen alto: estanterias, palets (reponer en la planta alta) y casillero
	for _, x in { -165, -135 } do
		storageRack(at(x, 0, 92) , 18)
	end
	for _, x in { -112, -100 } do
		local pallet = box("Pallet", Vector3.new(5, 0.6, 5), at(x, 0.3, 102), M.WoodPlanks, Color3.fromRGB(160, 125, 80))
		tag(pallet, Tags.StockPickup)
		palletBoxes(x, 103.4)
	end
	hidingSpot("Casillero", at(-178.4, 3.75, 104) * CFrame.Angles(0, math.rad(-90), 0), Vector3.new(4, 7.5, 3), M.Metal, Color3.fromRGB(70, 90, 110))
	enemySpawn(-150, 106)

	-- Administracion (x -90..-64): escritorios y monitores de camaras
	for _, p in { { -84, 92 }, { -72, 92 }, { -84, 101 }, { -72, 101 } } do
		propOr("OfficeDesk", at(p[1], 0, p[2]) * CFrame.Angles(0, math.pi, 0), deskFallback)
	end
	local monitors = box("Monitors", Vector3.new(10, 3, 0.6), at(-77, 5, 109.2), M.Glass, Color3.fromRGB(20, 40, 60), {
		Transparency = 1,
		Variant = false,
	})
	tag(monitors, Tags.MissionSpot, { MissionType = "CheckCameras", Zone = "Administración" })
	monitorWall(at(-77, 5, 109.1), {
		{ "CAM 07", "CINE" },
		{ "CAM 08", "ZONA JUEGOS" },
		{ "CAM 09", "GALERIA P2" },
		{ "CAM 10", "OFICINAS" },
		{ "CAM 11", "SALA MAQUINAS" },
		{ "CAM 12", "ALA NORTE", "Figure" },
	})
	box("MonitorDesk", Vector3.new(10, 3, 2.6), at(-77, 1.5, 107.4), M.Wood, Color3.fromRGB(110, 85, 60))
	securityDeskTop(at(-79, 3, 107.4), true)
	-- Bandeja de albaranes (mision Entrega de paquete: se firma aqui)
	local deliveryTray = box("DeliveryTray", Vector3.new(1.6, 0.3, 1.2), at(-73.5, 3.15, 107.4), M.Plastic, Color3.fromRGB(40, 40, 44), { Variant = false })
	deco("Paperwork", Vector3.new(1.3, 0.1, 0.9), at(-73.5, 3.35, 107.4), M.SmoothPlastic, Color3.fromRGB(240, 238, 230))
	tag(deliveryTray, Tags.DeliveryDesk, { Zone = "Administración" })
	hidingSpot("Armario", at(-66.4, 3.75, 104) * CFrame.Angles(0, math.rad(90), 0), Vector3.new(4, 7.5, 3), M.Metal, Color3.fromRGB(80, 95, 110))

	-- Sala de descanso (x -64..-24.5)
	local DX = -24
	propOr("Sofa", at(DX - 20, 0, 107), function(cf)
		box("Sofa", Vector3.new(8, 1.8, 3), cf * CFrame.new(0, 0.9, 0), M.Fabric, Color3.fromRGB(90, 100, 120))
	end)
	roundTable(at(DX - 20, 0, 95), 4, Color3.fromRGB(70, 120, 160))
	box("Fridge", Vector3.new(3, 7, 3), at(DX - 37, 3.5, 106), M.Metal, Color3.fromRGB(230, 230, 230))
	box("Kitchenette", Vector3.new(8, 3.4, 2.6), at(DX - 34, 1.7, 87), M.Wood, Color3.fromRGB(200, 190, 170))
	deco("Microwave", Vector3.new(2, 1.2, 1.4), at(DX - 36, 4, 87), M.Metal, DARK)
	for _, z in { 95, 99 } do
		hidingSpot("Taquilla", at(-26.1, 3.75, z) * CFrame.Angles(0, math.rad(90), 0), Vector3.new(4, 7.5, 3), M.Metal, Color3.fromRGB(70, 90, 110))
	end
	vendingMachine(CFrame.lookAt(Vector3.new(DX - 7, Y0 + F2 + 3.5, 107.5), Vector3.new(DX - 7, Y0 + F2 + 3.5, 100)), "Cheap", Color3.fromRGB(180, 30, 35), "REFRESCOS")

	-- Baños P2 (x 25..54: la pared oeste es la del pasaje)
	local PX = 24.5
	deco("BathFloor", Vector3.new(30, 0.05, 28), at(PX + 15, 0.03, 96), M.CeramicTiles, Color3.fromRGB(235, 238, 240))
	stallRow({ PX + 3.25, PX + 8.75, PX + 14.25 }, 109.5, "Baños P2", { SkipX = { PX + 0.5 }, Closed = 3 })
	urinal(at(PX + 21, 0, 109.5))
	urinal(at(PX + 24.5, 0, 109.5))
	deco("UrinalScreen", Vector3.new(0.12, 3.2, 1.8), at(PX + 22.75, 4, 108.6), M.SmoothPlastic, PARTITION)
	local eastWallP2 = CFrame.Angles(0, math.rad(90), 0)
	vanity(at(PX + 29.5, 0, 90) * eastWallP2, 3, 3, false, "Baños P2")
	spot(PX + 15, 92, "CloseFaucets", "Baños P2")
	handDryer(at(PX + 29.5, 0, 99) * eastWallP2)
	bathDetails(at(PX + 15, 0, 95), at(PX + 28.2, 0, 96.8), at(PX + 1.8, 0, 85))
	-- Azulejo hasta 8 studs en las paredes interiores (las de oficina son de yeso)
	local tileColor = Color3.fromRGB(215, 222, 226)
	local TILE_H = 8
	deco("WallTile", Vector3.new(0.08, TILE_H, 27), at(PX + 0.55, TILE_H / 2, 96), M.CeramicTiles, tileColor)
	deco("WallTile", Vector3.new(0.08, TILE_H, 27), at(PX + 29.45, TILE_H / 2, 96), M.CeramicTiles, tileColor)
	deco("WallTile", Vector3.new(29, TILE_H, 0.08), at(PX + 15, TILE_H / 2, 109.45), M.CeramicTiles, tileColor)
	for _, seg in { { 0.5, 11 }, { 19, 29.5 } } do -- pared de la puerta (hueco x 11..19)
		deco("WallTile", Vector3.new(seg[2] - seg[1], TILE_H, 0.08), at(PX + (seg[1] + seg[2]) / 2, TILE_H / 2, 82.55), M.CeramicTiles, tileColor)
		deco("TileTrim", Vector3.new(seg[2] - seg[1], 0.25, 0.12), at(PX + (seg[1] + seg[2]) / 2, TILE_H, 82.6), M.SmoothPlastic, Color3.fromRGB(70, 95, 110))
	end
	deco("TileTrim", Vector3.new(29, 0.25, 0.12), at(PX + 15, TILE_H, 109.4), M.SmoothPlastic, Color3.fromRGB(70, 95, 110))
	for _, x in { 0.6, 29.4 } do
		deco("TileTrim", Vector3.new(0.12, 0.25, 27), at(PX + x, TILE_H, 96), M.SmoothPlastic, Color3.fromRGB(70, 95, 110))
	end

	-- Archivo (x 54.5..80)
	-- (estanterias de x 62.5 a 79: pasillo libre de x 54.5 a 62.5, frente a la puerta x 55..63,
	-- para llegar al fondo de la sala)
	for _, z in { 90, 100 } do
		storageRack(at(70.75, 0, z), 16.5)
	end
	propOr("OfficeDesk", at(60, 0, 106) * CFrame.Angles(0, math.rad(-90), 0), deskFallback)
	spot(72, 106, "LostItem", "Archivo")

	-- Sala de maquinas: segundo generador (deja sin luz las oficinas) y caldera
	local genPanel2 = generatorSet(105, 105)
	-- Caldera: modelo 3D (PropTemplates.Boiler) o el bloque de antes
	propOr("Boiler", at(88, 0, 104), function(c)
		box("Boiler", Vector3.new(5, 9, 5), c * CFrame.new(0, 4.5, 0), M.Metal, Color3.fromRGB(170, 70, 50))
	end)
	for k = 0, 3 do
		deco("PipeRun", Vector3.new(0.8, 0.8, 26), at(84 + k * 1.6, 13.5, 96), M.Metal, METAL)
	end
	tag(genPanel2, Tags.MissionSpot, {
		MissionType = "RestartGenerator",
		Zone = "Sala de máquinas",
		PowersZones = "Cine,Zona de juegos",
	})
	-- Caldera (mision Purgar la caldera): panel en su frente y valvulas en las paredes
	local boilerPanel = box("BoilerControl", Vector3.new(2.4, 2, 0.5), at(88, 3.5, 101.2), M.Metal, Color3.fromRGB(60, 62, 66), { Variant = false })
	local boilerSign = deco("BoilerSign", Vector3.new(2.2, 0.5, 0.06), at(88, 4.8, 100.92), M.SmoothPlastic, DARK)
	litSign(boilerSign, "CALDERA", Color3.fromRGB(255, 150, 80), Enum.Font.Code, Enum.NormalId.Front)
	tag(boilerPanel, Tags.BoilerControl)
	boilerValve(at(80.5, 0, 92) * CFrame.Angles(0, math.rad(-90), 0), "Sala de máquinas")
	boilerValve(at(125, 0, 110), "Sala de máquinas")
	boilerValve(at(180, 0, 85) * CFrame.Angles(0, math.rad(90), 0), "Escalera de servicio")
	spot(105, 92, "PurgeBoiler", "Sala de máquinas")

	-- Pasillo: carrito del conserje, puntos y camaras
	propOr("JanitorCart", at(-70, 0, 79) * CFrame.Angles(0, math.rad(90), 0), function() end)
	spot(-34, 76, "CleanSpill", "Oficinas Oeste")
	spot(90, 76, "CleanSpill", OFF)
	spot(-106, 92, "Delivery", "Almacén alto")
	spot(-60, 76, "SecurityRound", "Oficinas Oeste")
	spot(-70, 96, "Inventory", "Administración")
	patrolClock(40, 79, OFF)
	-- Extintores y telefono en la pared del pasillo (cara hacia el pasillo)
	wallExtinguisher(at(-56, 0, 81.5), "Planta alta")
	wallExtinguisher(at(85, 0, 81.5), "Planta alta")
	payPhone(at(-34, 0, 81.5), "Oficinas Oeste")
	spot(150, 84, "CleanSpill", "Escalera de servicio")
	enemySpawn(60, 76)
	camera(-88, 12, 72, -40, 0, 78)
	camera(128, 12, 72, 80, 0, 78)

	levelY = 0
	currentParent = map
end

----------------------------------------------------------------------
-- Alas nuevas (2026-11-25)
--   * Pasajes desde el centro de la galeria (donde estaban las tiendas de la columna 3).
--   * ALA NORTE (z 110..207, cruza el servicio y las oficinas): 4 tiendas por planta (una
--     cerrada y a oscuras en cada planta), pasillo de servicio oscuro detras que da la
--     vuelta, y escalera entre plantas al fondo.
--   * ALA SUR (z -167..-70): toda en obras y a oscuras, 4 locales en obras por planta y
--     los grandes almacenes cerrados al fondo (z -227..-167) con escaleras mecanicas paradas.
----------------------------------------------------------------------

local MARBLE = Color3.fromRGB(232, 228, 220)
local GRANITE = Color3.fromRGB(95, 90, 88)
local PLYWOOD = Color3.fromRGB(196, 160, 112)
local CAUTION = Color3.fromRGB(240, 190, 20)
local SHEET = Color3.fromRGB(214, 212, 204)
local NORTH_END = 207 -- fondo del pasillo del Ala Norte (pared con puerta al pasillo de servicio)
local NORTH_BACK = 222 -- muro norte del pasillo de servicio
local BACK_X1, BACK_X2 = 74, 84 -- pasillos de servicio detras de las tiendas del Ala Norte (|x|)
local NSTAIR = { X1 = 30, X2 = 56, Z1 = 215, Z2 = 221 } -- escalera del pasillo de servicio norte
local NSTAIR_HOLE = { NSTAIR.X1, NSTAIR.X2, NSTAIR.Z1 - 1, NSTAIR.Z2 + 1 }
local ESC_HOLE = { -20, 15, -206, -194 } -- hueco de las escaleras paradas de los grandes almacenes
local SOUTH_BRANDS = { "Burger Luna", "Sushi Kame", "Mascotas Peludas", "Tatuajes Tinta", "Heladería Nube", "Bazar Oriental", "Escape Room", "Cine 4D" }

-- Pasillo de un ala (|x| < WING): suelo de marmol con franja de granito (como la galeria).
local function corridorFloor(z1: number, z2: number)
	slab("Floor", -WING, WING, z1, z2, 0, M.Marble, MARBLE)
	local len, zc = z2 - z1, (z1 + z2) / 2
	deco("Runner", Vector3.new(6, 0.05, len), at(0, 0.02, zc), M.Granite, GRANITE)
	for _, x in { -WING + 2.5, WING - 2.5 } do
		deco("Border", Vector3.new(1.2, 0.05, len), at(x, 0.02, zc), M.Granite, GRANITE)
	end
end

-- Cabecera con el nombre del ala sobre la entrada del pasaje (vista desde la galeria).
-- dir = 1: el pasaje va al norte (entrada en z = 20); -1: al sur (z = -20).
local function passageEntrance(zFront: number, dir: number, text: string, accent: Color3)
	local face = if dir > 0 then CFrame.new() else CFrame.Angles(0, math.pi, 0)
	local h = if levelY == 0 then 5 else 6
	local top = if levelY == 0 then F2 - 1 else 18
	box("PassageHeader", Vector3.new(2 * WING, h, 1), at(0, top - h / 2, zFront + dir * 0.5), M.Plaster, accent:Lerp(DARK, 0.75))
	deco("HeaderTrim", Vector3.new(2 * WING, 0.25, 1.3), at(0, top - h + 0.1, zFront + dir * 0.5), M.Metal, STEEL)
	local signPart = box("PassageSign", Vector3.new(34, 2.8, 0.3), at(0, top - h / 2, zFront - dir * 0.15) * face, M.SmoothPlastic, Color3.fromRGB(14, 14, 18), {
		CanCollide = false,
		Variant = false,
	})
	litSign(signPart, text, accent, Enum.Font.GothamBlack, Enum.NormalId.Front)
end

-- Escalera de servicio entre plantas a lo largo de x (rampa, peldaños y barandillas).
-- Se llama con levelY = 0: sube de x1 (planta baja) a x2 (planta alta).
local function stairs(x1: number, x2: number, z1: number, z2: number)
	local W = z2 - z1
	local zc = (z1 + z2) / 2
	local ramp = rampBody("Stairs", x1, x2, zc, W, M.Concrete, Color3.fromRGB(150, 150, 146))
	tag(ramp, Tags.FloorConnector, { Low = Vector3.new(x1, Y0, zc), High = Vector3.new(x2, Y0 + F2, zc), Width = W })
	local steps = 16
	for i = 0, steps - 1 do
		local x = x1 + (i + 0.5) * (x2 - x1) / steps
		local y = (i + 1) * F2 / steps
		deco("StairTread", Vector3.new((x2 - x1) / steps + 0.05, 0.3, W), at(x, y - 0.15, zc), M.Concrete, Color3.fromRGB(165, 165, 160))
		deco("StairNosing", Vector3.new(0.25, 0.32, W), at(x - (x2 - x1) / steps / 2, y - 0.15, zc), M.SmoothPlastic, CAUTION, { Variant = false })
	end
	local low = Vector3.new(x1, Y0, zc)
	local high = Vector3.new(x2, Y0 + F2, zc)
	local slope = CFrame.lookAt((low + high) / 2, high)
	for _, side in { -1, 1 } do
		box("StairRail", Vector3.new(0.2, 3.4, (high - low).Magnitude), slope * CFrame.new(side * (W / 2 + 0.1), 1.7, 0), M.Metal, CAUTION, {
			Transparency = 0.999,
			Variant = false,
		})
		deco("StairHandrail", Vector3.new(0.25, 0.25, (high - low).Magnitude), slope * CFrame.new(side * (W / 2 + 0.1), 3.2, 0), M.Metal, CAUTION)
	end
end

-- Cartel de pared "SOLO PERSONAL" (frente -Z de cf).
local function staffSign(cf: CFrame)
	local plate = deco("StaffPlate", Vector3.new(4.4, 0.9, 0.12), cf, M.SmoothPlastic, Color3.fromRGB(40, 44, 52))
	litSign(plate, "SOLO PERSONAL", Color3.fromRGB(230, 230, 230), Enum.Font.GothamBold, Enum.NormalId.Front)
end

-- Luz de emergencia SIN bateria en una pared (mision Luces de emergencia). cf = punto de la
-- pared a 7 de altura, frente (-Z) hacia el pasillo. La lente apagada es su hijo "Lens".
local function deadEmergencyLight(cf: CFrame, missionZone: string)
	local body = box("EmergencyBox", Vector3.new(1.8, 0.7, 0.7), cf * CFrame.new(0, 0, -0.35), M.SmoothPlastic, Color3.fromRGB(225, 225, 220), {
		CanCollide = false,
		Variant = false,
	})
	local lens = deco("Lens", Vector3.new(1.4, 0.16, 0.5), cf * CFrame.new(0, -0.42, -0.4), M.SmoothPlastic, Color3.fromRGB(60, 40, 30), { CastShadow = false })
	lens.Parent = body
	deco("BatteryLabel", Vector3.new(0.6, 0.25, 0.05), cf * CFrame.new(0.4, 0.15, -0.72), M.SmoothPlastic, CAUTION)
	tag(body, Tags.EmergencyBox, { Zone = missionZone })
end

-- Montones de cajas de carton (con colision) a ras de suelo.
local function boxPile(cf: CFrame, count: number)
	for i = 0, count - 1 do
		local w, h = rng:NextNumber(1.8, 2.8), rng:NextNumber(1.4, 2.2)
		-- Modelo 3D de caja (PropTemplates.StockBox) si esta
		if prop("StockBox", cf * CFrame.new((i % 2) * 1.7, math.floor(i / 2) * 2.08, 0) * CFrame.Angles(0, math.rad(rng:NextNumber(-12, 12)), 0)) then
			continue
		end
		box("BoxPile", Vector3.new(w, h, w), cf * CFrame.new((i % 2) * 2.4, h / 2 + math.floor(i / 2) * 1.6, 0) * CFrame.Angles(0, math.rad(rng:NextNumber(-12, 12)), 0), M.Cardboard, vary(Color3.fromRGB(175, 135, 90), 0.06))
	end
end

----------------------------------------------------------------------
-- Atrezo de obra
----------------------------------------------------------------------

local function scaffold(cf: CFrame, w: number, d: number, h: number)
	local tube = Color3.fromRGB(150, 155, 160)
	for _, px in { -w / 2, w / 2 } do
		for _, pz in { -d / 2, d / 2 } do
			box("ScaffoldPost", Vector3.new(0.3, h, 0.3), cf * CFrame.new(px, h / 2, pz), M.Metal, tube)
		end
	end
	for y = 2, h - 1, 4 do
		for _, pz in { -d / 2, d / 2 } do
			deco("ScaffoldTube", Vector3.new(w, 0.2, 0.2), cf * CFrame.new(0, y, pz), M.Metal, tube)
		end
		for _, px in { -w / 2, w / 2 } do
			deco("ScaffoldTube", Vector3.new(0.2, 0.2, d), cf * CFrame.new(px, y, 0), M.Metal, tube)
		end
	end
	box("ScaffoldDeck", Vector3.new(w, 0.25, d), cf * CFrame.new(0, h - 2.5, 0), M.WoodPlanks, Color3.fromRGB(170, 130, 85))
	deco("ScaffoldToeBoard", Vector3.new(w, 0.6, 0.1), cf * CFrame.new(0, h - 2.1, -d / 2), M.Wood, CAUTION)
end

local function paintBuckets(cf: CFrame)
	local colors = { Color3.fromRGB(235, 235, 230), Color3.fromRGB(70, 130, 200), Color3.fromRGB(200, 80, 60) }
	for i, off in { Vector2.new(0, 0), Vector2.new(1.3, 0.4), Vector2.new(0.5, -1.2) } do
		deco("PaintBucket", Vector3.new(1.2, 1, 1), cf * CFrame.new(off.X, 0.6, off.Y) * CFrame.Angles(0, 0, math.rad(90)), M.Plastic, colors[i], {
			Shape = Enum.PartType.Cylinder,
		})
	end
	deco("PaintSpill", Vector3.new(2.4, 0.04, 1.6), cf * CFrame.new(-1.2, 0.02, 1) * CFrame.Angles(0, math.rad(30), 0), M.SmoothPlastic, colors[2]:Lerp(DARK, 0.3))
end

local function cementBags(cf: CFrame)
	for i = 0, 4 do
		box("CementBag", Vector3.new(2.2, 0.6, 1.3), cf * CFrame.new((i % 2) * 0.3, 0.3 + i * 0.6, 0) * CFrame.Angles(0, math.rad(i * 9), 0), M.Fabric, Color3.fromRGB(205, 195, 170))
	end
end

local function drywallStack(cf: CFrame)
	box("DrywallStack", Vector3.new(8, 0.9, 4), cf * CFrame.new(0, 0.45, 0), M.Plaster, Color3.fromRGB(225, 222, 214), { Variant = false })
	for i = 0, 2 do
		deco("DrywallSheet", Vector3.new(4, 8, 0.2), cf * CFrame.new(-2 + i * 2, 4, 2.6 + i * 0.25) * CFrame.Angles(math.rad(-12), 0, 0), M.Plaster, Color3.fromRGB(228, 226, 218), { Variant = false })
	end
end

local function ladder(cf: CFrame, h: number)
	local lean = cf * CFrame.Angles(math.rad(-15), 0, 0)
	for _, x in { -0.8, 0.8 } do
		deco("LadderRail", Vector3.new(0.2, h, 0.25), lean * CFrame.new(x, h / 2, 0), M.Metal, Color3.fromRGB(205, 205, 200))
	end
	for y = 1, h - 0.5, 1 do
		deco("LadderRung", Vector3.new(1.6, 0.15, 0.15), lean * CFrame.new(0, y, 0), M.Metal, Color3.fromRGB(205, 205, 200))
	end
end

-- Foco de obra apagado (tripode con cabeza de lampara).
local function workLamp(cf: CFrame)
	for k = 0, 2 do
		local a = math.rad(k * 120)
		deco("TripodLeg", Vector3.new(0.15, 4.4, 0.15), cf * CFrame.new(math.cos(a) * 0.8, 2.1, math.sin(a) * 0.8) * CFrame.Angles(math.sin(a) * 0.2, 0, -math.cos(a) * 0.2), M.Metal, DARK)
	end
	deco("LampHead", Vector3.new(1.4, 1.1, 0.7), cf * CFrame.new(0, 4.6, 0) * CFrame.Angles(math.rad(-20), 0, 0), M.Metal, CAUTION)
	deco("LampGlass", Vector3.new(1.1, 0.8, 0.05), cf * CFrame.new(0, 4.6, -0.38) * CFrame.Angles(math.rad(-20), 0, 0), M.Glass, Color3.fromRGB(60, 60, 55))
end

-- Lamina de plastico colgada del techo (tapa la vista; los enemigos ven a traves).
local function plasticSheet(cf: CFrame, w: number, h: number)
	deco("PlasticSheet", Vector3.new(w, h, 0.05), cf, M.SmoothPlastic, Color3.fromRGB(232, 236, 238), {
		Transparency = 0.4,
		CastShadow = false,
		Variant = false,
	})
end

-- Cinta de "precaucion" entre dos puntos (sin colision).
local function cautionTape(p1: Vector3, p2: Vector3)
	local a = Vector3.new(p1.X, Y0 + levelY + p1.Y, p1.Z)
	local b = Vector3.new(p2.X, Y0 + levelY + p2.Y, p2.Z)
	deco("CautionTape", Vector3.new(0.05, 0.3, (b - a).Magnitude), CFrame.lookAt((a + b) / 2, b), M.SmoothPlastic, CAUTION, { CastShadow = false })
end

-- Herramienta electrica de la obra (mision Desenchufar herramientas). Solo la pieza
-- principal lleva el tag PowerTool.
local function powerTool(kind: string, cf: CFrame, missionZone: string)
	local main: BasePart
	if kind == "Mixer" then
		deco("MixerFrame", Vector3.new(2.8, 2, 1.8), cf * CFrame.new(0, 1, 0), M.Metal, Color3.fromRGB(70, 72, 76))
		for _, x in { -1.2, 1.2 } do
			deco("MixerWheel", Vector3.new(0.4, 1.2, 1.2), cf * CFrame.new(x, 0.6, 1.1), M.Rubber, DARK, { Shape = Enum.PartType.Cylinder })
		end
		main = box("Mixer", Vector3.new(3.2, 2.8, 2.8), cf * CFrame.new(0, 3.3, 0) * CFrame.Angles(0, 0, math.rad(-35)), M.Metal, Color3.fromRGB(230, 130, 30), {
			Shape = Enum.PartType.Cylinder,
		})
	elseif kind == "Saw" then
		for _, x in { -2.2, 2.2 } do
			for _, z in { -0.6, 0.6 } do
				deco("SawhorseLeg", Vector3.new(0.25, 3, 0.25), cf * CFrame.new(x, 1.5, z) * CFrame.Angles(math.rad(z * 18), 0, 0), M.Wood, PLYWOOD)
			end
		end
		box("SawPlank", Vector3.new(6, 0.3, 2.4), cf * CFrame.new(0, 3, 0), M.Wood, PLYWOOD)
		main = box("CircularSaw", Vector3.new(1.6, 0.9, 1.2), cf * CFrame.new(0.6, 3.6, 0), M.SmoothPlastic, Color3.fromRGB(40, 110, 200))
		deco("SawBlade", Vector3.new(0.08, 1.4, 1.4), cf * CFrame.new(1.45, 3.5, 0) * CFrame.Angles(0, math.rad(90), 0), M.Metal, STEEL, {
			Shape = Enum.PartType.Cylinder,
		})
	elseif kind == "Compressor" then
		main = box("Compressor", Vector3.new(3, 2, 1.8), cf * CFrame.new(0, 1.4, 0), M.Metal, Color3.fromRGB(190, 40, 35))
		deco("CompressorTank", Vector3.new(3.4, 1.4, 1.4), cf * CFrame.new(0, 0.7, 0), M.Metal, Color3.fromRGB(170, 35, 30), { Shape = Enum.PartType.Cylinder })
		deco("Hose", Vector3.new(0.2, 0.2, 4), cf * CFrame.new(1.8, 0.1, -2), M.Rubber, DARK)
	else -- "Generator"
		main = box("PortableGenerator", Vector3.new(3, 2.2, 2), cf * CFrame.new(0, 1.3, 0), M.Metal, CAUTION)
		deco("GenFrame", Vector3.new(3.3, 2.6, 2.3), cf * CFrame.new(0, 1.3, 0), M.Metal, DARK, { Transparency = 0.6 })
		deco("ExtensionCord", Vector3.new(0.2, 0.15, 6), cf * CFrame.new(0, 0.08, -4), M.Rubber, Color3.fromRGB(230, 120, 20))
	end
	tag(main, Tags.PowerTool, { Zone = missionZone })
	return main
end

-- Maniqui destapado sobre una peana (mision Tapar maniquies). El maniqui (Model) es hijo de
-- la peana, que lleva el tag. No es un DisplayMannequin: el enemigo Maniqui no lo usa.
local function sheetMannequin(cf: CFrame, missionZone: string)
	local stand = box("MannequinStand", Vector3.new(2.4, 0.4, 2.4), cf * CFrame.new(0, 0.2, 0), M.Metal, DARK)
	local model = EntityModels.mannequin()
	model.Name = "Mannequin"
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanTouch = false
			d.CanCollide = d == model.PrimaryPart
		end
	end
	EntityModels.placeAt(model, cf * CFrame.new(0, 0.4, 0), stand)
	stand:SetAttribute("HomeCFrame", model:GetPivot())
	tag(stand, Tags.SheetMannequin, { Zone = missionZone })
end

-- Maniqui tapado con una sabana (decoracion).
local function coveredMannequin(cf: CFrame)
	deco("Stand", Vector3.new(2, 0.2, 2), cf * CFrame.new(0, 0.1, 0), M.Metal, DARK)
	box("CoveredFigure", Vector3.new(2.6, 5.6, 1.8), cf * CFrame.new(0, 3, 0), M.Fabric, SHEET)
	deco("CoveredHead", Vector3.new(1.6, 1.6, 1.6), cf * CFrame.new(0, 6.2, 0), M.Fabric, SHEET, { Shape = Enum.PartType.Ball })
end

-- Mueble tapado con sabana (sofa, cama, perchero...).
local function coveredFurniture(cf: CFrame, size: Vector3)
	box("CoveredFurniture", size, cf * CFrame.new(0, size.Y / 2, 0), M.Fabric, SHEET)
	deco("SheetDrape", Vector3.new(size.X + 0.6, 0.12, size.Z + 0.6), cf * CFrame.new(0, 0.06, 0), M.Fabric, SHEET:Lerp(DARK, 0.15))
end

-- Escalera mecanica parada: sin velocidad, sin animacion y cartel de "FUERA DE SERVICIO".
local function stoppedEscalator(lowX: number, highX: number, zc: number)
	local model = escalator(lowX, highX, zc, true)
	CollectionService:RemoveTag(model, Tags.Escalator)
	local body = model:FindFirstChild("EscalatorBody")
	if body and body:IsA("BasePart") then
		body.AssemblyLinearVelocity = Vector3.zero
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Name == "SkirtLight" then
			d.Material = M.SmoothPlastic
			d.Color = Color3.fromRGB(40, 44, 50)
		end
	end
	local signPart = model:FindFirstChild("EscalatorSign")
	local label = signPart and signPart:FindFirstChildWhichIsA("TextLabel", true)
	if label then
		label.Text = "FUERA DE SERVICIO"
		label.TextColor3 = Color3.fromRGB(255, 70, 60)
	end
end

----------------------------------------------------------------------
-- Ala Norte
----------------------------------------------------------------------

local function buildNorthWing()
	local wingFolder = folder("AlaNorte")
	levelY = 0
	local top = GALLERY_TOP + 4
	-- Muros exteriores del ala (las dos plantas): lados de los pasillos de servicio y fondo
	wall(Vector3.new(-(BACK_X2 + 0.5), 0, 111), Vector3.new(-(BACK_X2 + 0.5), 0, NORTH_BACK + 1), top)
	wall(Vector3.new(BACK_X2 + 0.5, 0, 111), Vector3.new(BACK_X2 + 0.5, 0, NORTH_BACK + 1), top)
	wall(Vector3.new(-(BACK_X2 + 1), 0, NORTH_BACK + 0.5), Vector3.new(BACK_X2 + 1, 0, NORTH_BACK + 0.5), top, {
		Material = M.Concrete,
		Color = Color3.fromRGB(150, 150, 146),
	})
	-- Escalera del pasillo de servicio norte (planta baja -> alta)
	stairs(NSTAIR.X1, NSTAIR.X2, NSTAIR.Z1, NSTAIR.Z2)

	for floorIndex, ly in { 0, F2 } do
		levelY = ly
		currentParent = wingFolder
		local upper = ly > 0
		local P2 = if upper then " P2" else ""
		local wingName = "Ala Norte" .. P2
		local passageZone = "Pasaje Norte" .. P2
		local floorName = if upper then "Planta alta" else "Planta baja"

		-- Pasaje desde la galeria (z 20..110) y pasillo del ala (z 110..207)
		zone(passageZone, -WING, WING, 20, 110, 16)
		zone(wingName, -WING, WING, 110, NORTH_END, 16)
		corridorFloor(20, NORTH_END)
		ceiling(-WING, WING, 20, NORTH_END, STORE_H + 1)
		passageEntrance(20, 1, if upper then "ALA NORTE  ·  P2" else "ALA NORTE", Color3.fromRGB(130, 205, 255))
		-- Cruce del servicio / oficinas (z 70..110): puertas de personal a cada lado
		for _, s in { -1, 1 } do
			wall(Vector3.new(s * (WING + 0.5), 0, 70), Vector3.new(s * (WING + 0.5), 0, 110), STORE_H, {
				Color = Color3.fromRGB(205, 205, 200),
				Openings = { { From = 3, To = 11, Height = 9 } },
			})
			staffSign(at(s * (WING - 0.1), 10, 77) * CFrame.Angles(0, if s > 0 then math.rad(90) else math.rad(-90), 0))
		end

		-- Luces
		for z = 32, 104, 24 do
			for _, x in { -12, 12 } do
				ceilingPanel(at(x, STORE_H, z), passageZone, Vector2.new(6, 2.4), 24, 1.5)
			end
		end
		for z = 122, 194, 24 do
			for _, x in { -12, 12 } do
				ceilingPanel(at(x, STORE_H, z), wingName, Vector2.new(6, 2.4), 24, 1.5)
			end
		end
		for z = 44, 188, 48 do
			ceilingVent(at(0, STORE_H, z))
		end

		-- Pasaje: directorio, macetero y banco
		directoryTotem(at(-15, 0, 30), floorIndex, true)
		planter(15, 44, passageZone)
		bench(at(15, 0, 50))

		-- Tiendas del ala (puerta trasera al pasillo de servicio)
		buildWingStores(if upper then NORTH_STORES_2 else NORTH_STORES_1, wingName, if upper then 20 else 10)
		currentParent = wingFolder

		-- Fondo del pasillo: pared con puerta al pasillo de servicio (x -4..4)
		wall(Vector3.new(-(WING + STORE_D), 0, NORTH_END + 0.5), Vector3.new(WING + STORE_D, 0, NORTH_END + 0.5), F2, {
			Openings = { { From = WING + STORE_D - 4, To = WING + STORE_D + 4, Height = 9 } },
		})
		exitSign(at(0, 10.5, NORTH_END - 0.2))
		staffSign(at(7.5, 7.5, NORTH_END - 0.1))

		-- Mobiliario y puntos de mision del pasillo
		for _, z in { 128, 160, 192 } do
			planter(0, z, wingName)
		end
		for _, z in { 128, 192 } do
			bench(at(-7.5, 0, z) * CFrame.Angles(0, math.rad(90), 0))
			bench(at(7.5, 0, z) * CFrame.Angles(0, math.rad(-90), 0))
		end
		trashBin(at(-20, 0, 122), wingName)
		trashBin(at(20, 0, 150), wingName)
		trashBin(at(-20, 0, 178), wingName)
		directoryTotem(at(15, 0, 116), floorIndex, true)
		electricPanel(at(16, 3, NORTH_END - 0.3), wingName)
		wallExtinguisher(at(-14, 0, NORTH_END), floorName)
		payPhone(at(-20, 0, NORTH_END), wingName)
		spot(-10, 140, "CleanSpill", wingName)
		spot(12, 186, "CleanSpill", wingName)
		spot(-14, 170, "TakeOutTrash", wingName)
		spot(10, 120, "LostItem", wingName)
		spot(6, 160, "WaterPlants", wingName)
		spot(-6, 150, "LockDoors", wingName)
		spot(6, 140, "ResetRegisters", wingName)
		spot(-6, 176, "TurnOffDisplays", wingName)
		spot(0, 202, "EmptyBins", wingName)
		patrolClock(-20, 200, wingName)
		camera(-22, 14, 112, 0, 0, 170)
		camera(22, 14, 205, 0, 0, 150)
		enemySpawn(0, 204)

		-- Pasillos de servicio (a oscuras): detras de las tiendas y al fondo
		local backZone = "Pasillo de servicio" .. P2
		local concrete = Color3.fromRGB(118, 118, 114)
		for _, s in { -1, 1 } do
			local x1, x2 = if s > 0 then BACK_X1 else -BACK_X2, if s > 0 then BACK_X2 else -BACK_X1
			zone("Pasillo de servicio " .. (if s > 0 then "Este" else "Oeste") .. P2, x1, x2, 111, NORTH_END, STORE_H)
			slab("Floor", x1, x2, 111, NORTH_END, 0, M.Concrete, concrete)
			slab("Ceiling", x1, x2, 111, NORTH_END, STORE_H + 1, M.Concrete, Color3.fromRGB(90, 90, 94))
		end
		zone("Pasillo de servicio Norte" .. P2, -BACK_X2, BACK_X2, NORTH_END, NORTH_BACK, STORE_H)
		if upper then
			slabWithHole("Floor", -BACK_X2, BACK_X2, NORTH_END, NORTH_BACK + 1, 0, NSTAIR_HOLE, M.Concrete, concrete)
			slab("Ceiling", -BACK_X2, BACK_X2, NORTH_END, NORTH_BACK + 1, STORE_H + 1, M.Concrete, Color3.fromRGB(90, 90, 94))
			-- Barandilla del hueco de la escalera (la llegada, x = 56, queda abierta)
			railing(Vector3.new(NSTAIR_HOLE[1], 0, NSTAIR_HOLE[3]), Vector3.new(NSTAIR_HOLE[2], 0, NSTAIR_HOLE[3]))
			railing(Vector3.new(NSTAIR_HOLE[1], 0, NSTAIR_HOLE[3]), Vector3.new(NSTAIR_HOLE[1], 0, NORTH_BACK))
		else
			slab("Floor", -BACK_X2, BACK_X2, NORTH_END, NORTH_BACK + 1, 0, M.Concrete, concrete)
			slabWithHole("Ceiling", -BACK_X2, BACK_X2, NORTH_END, NORTH_BACK + 1, STORE_H + 1, NSTAIR_HOLE, M.Concrete, Color3.fromRGB(90, 90, 94))
		end
		-- Solo luces de emergencia tenues... y las que no tienen bateria (mision)
		for _, p in { { 79, 140 }, { -79, 170 }, { -60, 214 }, { 70, 212 } } do
			emergencyLight(at(p[1], STORE_H, p[2]), p[1] > 0)
		end
		deadEmergencyLight(at(BACK_X2, 7, 128) * FACE_NEG_X, backZone)
		deadEmergencyLight(at(BACK_X2, 7, 190) * FACE_NEG_X, backZone)
		deadEmergencyLight(at(-BACK_X2, 7, 150) * FACE_POS_X, backZone)
		deadEmergencyLight(at(-BACK_X2, 7, 198) * FACE_POS_X, backZone)
		deadEmergencyLight(at(-20, 7, NORTH_BACK), backZone)
		deadEmergencyLight(at(-70, 7, NORTH_BACK), backZone)
		spot(0, 214, "RestoreEmergencyLights", backZone)
		-- Tuberias, cajas, casilleros y salidas
		for _, s in { -1, 1 } do
			deco("BackPipe", Vector3.new(0.8, 0.8, NORTH_END - 111), at(s * (BACK_X2 - 1), STORE_H - 1.2, (111 + NORTH_END) / 2), M.Metal, METAL)
			boxPile(at(s * 82, 0, 150 + s * 10), 4)
			hidingSpot("Casillero", at(s * 82.5, 3.75, 120 + (s + 1) * 25) * (if s > 0 then FACE_NEG_X else FACE_POS_X), Vector3.new(4, 7.5, 3), M.Metal, Color3.fromRGB(70, 90, 110))
		end
		deco("BackPipe", Vector3.new(2 * BACK_X2, 0.8, 0.8), at(0, STORE_H - 1.2, NORTH_BACK - 1), M.Metal, METAL)
		propOr("JanitorCart", at(-40, 0, 211) * CFrame.Angles(0, math.rad(90), 0), function() end)
		boxPile(at(-78, 0, 216), 3)
		exitSign(at(0, 10.5, NORTH_END + 1.2) * CFrame.Angles(0, math.pi, 0))
		if not upper then
			for _, x in { -79, 80 } do
				exitSign(at(x, 10.4, 111.8) * CFrame.Angles(0, math.pi, 0))
			end
		end
		spot(79, 160, "CleanSpill", "Pasillo de servicio Este" .. P2)
		spot(-79, 130, "CleanSpill", "Pasillo de servicio Oeste" .. P2)
		patrolClock(-79, 186, "Pasillo de servicio Oeste" .. P2)
		enemySpawn(79, 196)
		enemySpawn(-79, 140)
		enemySpawn(-60, 216)
		camera(-82, 13, 220, -40, 0, 212)
	end

	levelY = 0
	currentParent = map
end

----------------------------------------------------------------------
-- Ala Sur (en obras) y grandes almacenes cerrados
----------------------------------------------------------------------

-- Local en obras: x de side*24 a side*74, z = zc ± 24. Valla de tablero con puerta,
-- interior a medio hacer y sin luz (zona oscura "Local en obras N").
local function constructionUnit(n: number, side: number, zc: number, toolZone: string, withTool: string?)
	local unitFolder = Instance.new("Folder")
	unitFolder.Name = "LocalObras" .. n
	unitFolder.Parent = map
	local previous = currentParent
	currentParent = unitFolder

	local zoneName = "Local en obras " .. n
	local xIn, xOut = side * WING, side * (WING + STORE_D)
	local x1, x2 = math.min(xIn, xOut), math.max(xIn, xOut)
	local z1, z2 = zc - STORE_W / 2, zc + STORE_W / 2
	local origin = Vector3.new(xIn, Y0 + levelY, zc)
	local base = CFrame.lookAt(origin, origin + Vector3.new(side, 0, 0))
	local faceCorridor = if side > 0 then FACE_NEG_X else FACE_POS_X

	zone(zoneName, x1, x2, z1, z2, STORE_H)
	slab("Floor", x1, x2, z1, z2, 0, M.Concrete, Color3.fromRGB(122, 120, 116))
	slab("Ceiling", x1, x2, z1, z2, STORE_H + 1, M.Concrete, Color3.fromRGB(88, 88, 92))
	local drywall = Color3.fromRGB(196, 192, 184)
	for _, z in { z1 + 0.5, z2 - 0.5 } do
		wall(Vector3.new(x1, 0, z), Vector3.new(x2, 0, z), STORE_H, { Color = drywall, Baseboard = false })
	end
	wall(Vector3.new(xOut - side * 0.5, 0, z1), Vector3.new(xOut - side * 0.5, 0, z2), STORE_H, { Material = M.Concrete, Color = Color3.fromRGB(150, 150, 146), Baseboard = false })
	-- Valla de obra (tablero) con puerta en el centro
	wall(Vector3.new(xIn + side * 0.5, 0, z1), Vector3.new(xIn + side * 0.5, 0, z2), STORE_H, {
		Material = M.Wood,
		Color = PLYWOOD,
		Baseboard = false,
		Openings = { { From = STORE_W / 2 - 4, To = STORE_W / 2 + 4, Height = 9 } },
	})
	local banner = deco("HoardingBanner", Vector3.new(22, 4.4, 0.1), at(side * (WING - 0.1), 12, zc) * faceCorridor, M.SmoothPlastic, Color3.fromRGB(30, 32, 40))
	sign(banner, "PRÓXIMA APERTURA\n" .. string.upper(SOUTH_BRANDS[(n - 1) % #SOUTH_BRANDS + 1]), Color3.fromRGB(235, 200, 90), Enum.Font.GothamBlack, Enum.NormalId.Front)
	for _, dz in { -4.3, 4.3 } do
		deco("DoorStripe", Vector3.new(0.3, 9, 0.6), at(side * (WING - 0.05), 4.5, zc + dz), M.SmoothPlastic, CAUTION)
	end
	cautionTape(Vector3.new(side * (WING - 0.3), 3.2, zc - 4), Vector3.new(side * (WING - 0.3), 3.6, zc + 4))

	-- Montantes de pladur a la vista en una pared lateral
	for d = 6, 46, 2.5 do
		deco("Stud", Vector3.new(0.3, STORE_H, 0.6), L(base, -STORE_W / 2 + 1.3, STORE_H / 2, d), M.Metal, Color3.fromRGB(170, 172, 176))
	end
	-- Atrezo segun el local
	local variant = n % 4
	if variant == 1 then
		scaffold(L(base, 10, 0, 30), 8, 4, 12)
		drywallStack(L(base, -12, 0, 16))
		paintBuckets(L(base, 4, 0, 12))
		ladder(L(base, 18, 0, 44), 10)
	elseif variant == 2 then
		cementBags(L(base, 14, 0, 14))
		cementBags(L(base, 16, 0, 17))
		workLamp(L(base, -6, 0, 22) * CFrame.Angles(0, math.rad(150), 0))
		plasticSheet(L(base, 0, 7, 30), 30, 13)
		boxPile(L(base, -16, 0, 40), 5)
	elseif variant == 3 then
		scaffold(L(base, -12, 0, 24), 8, 4, 12)
		scaffold(L(base, 8, 0, 38), 8, 4, 12)
		paintBuckets(L(base, 14, 0, 12))
		ladder(L(base, -2, 0, 12), 9)
	else
		drywallStack(L(base, 10, 0, 18))
		workLamp(L(base, -10, 0, 30))
		plasticSheet(L(base, 4, 7, 26), 24, 13)
		cementBags(L(base, -16, 0, 44))
	end
	if withTool then
		powerTool(withTool, L(base, 0, 0, 34), toolZone)
	end
	-- Escondite: baño portatil (impares) o armario de herramientas (pares)
	if n % 2 == 1 then
		hidingSpot("Baño portátil", L(base, 19, 4, 44) * OUT, Vector3.new(4.4, 8, 4.4), M.Plastic, Color3.fromRGB(40, 95, 170))
	else
		hidingSpot("Armario de obra", L(base, -19, 3.75, 46.6) * OUT, Vector3.new(4, 7.5, 3), M.Metal, Color3.fromRGB(120, 90, 40))
	end
	emergencyLight(L(base, 0, STORE_H, 40), n % 2 == 0)
	-- Puntos de mision y enemigos
	local spill = L(base, -8, 0, 28).Position
	spot(spill.X, spill.Z, "CleanSpill", zoneName)
	if n % 2 == 0 then
		local lost = L(base, 8, 0, 44).Position
		spot(lost.X, lost.Z, "LostItem", zoneName)
	end
	local spawnPos = L(base, 0, 0, 44).Position
	enemySpawn(spawnPos.X, spawnPos.Z)

	currentParent = previous
end

local function buildAnchorStore(upper: boolean)
	local P2 = if upper then " P2" else ""
	local zoneName = "Almacenes Estrella" .. P2
	local A = ANCHOR
	zone(zoneName, A.X1, A.X2, A.Z1, A.Z2, STORE_H)
	if upper then
		slabWithHole("Floor", A.X1, A.X2, A.Z1, A.Z2 - 1, 0, ESC_HOLE, M.Marble, Color3.fromRGB(205, 198, 186))
		slab("Ceiling", A.X1, A.X2, A.Z1, A.Z2 - 1, STORE_H + 1, M.Plaster, WHITE)
	else
		slab("Floor", A.X1, A.X2, A.Z1, A.Z2 - 1, 0, M.Marble, Color3.fromRGB(205, 198, 186))
		slabWithHole("Ceiling", A.X1, A.X2, A.Z1, A.Z2 - 1, STORE_H + 1, ESC_HOLE, M.Plaster, WHITE)
	end
	-- Fachada hacia el pasillo del ala: abertura x -16..16 con la persiana a medio bajar
	wall(Vector3.new(A.X1, 0, A.Z2 - 0.5), Vector3.new(A.X2, 0, A.Z2 - 0.5), F2, {
		Color = Color3.fromRGB(70, 66, 64),
		Openings = { { From = 58, To = 90, Height = 12 } },
	})
	box("RollingGate", Vector3.new(32, 4, 0.3), at(0, 10, A.Z2 - 0.1), M.DiamondPlate, Color3.fromRGB(110, 110, 114), { CanCollide = false })
	local storeSign = deco("AnchorSign", Vector3.new(40, 3, 0.2), at(0, 14.2, A.Z2 + 0.05) * CFrame.Angles(0, math.pi, 0), M.SmoothPlastic, Color3.fromRGB(20, 20, 24))
	sign(storeSign, if upper then "ALMACENES ESTRELLA · HOGAR" else "★ ALMACENES ESTRELLA ★", Color3.fromRGB(150, 130, 70), Enum.Font.Garamond, Enum.NormalId.Front)
	local notice = deco("ClosingNotice", Vector3.new(6, 3, 0.05), at(-20, 5, A.Z2 + 0.06) * CFrame.Angles(0, math.pi, 0), M.SmoothPlastic, Color3.fromRGB(235, 232, 220))
	sign(notice, "CERRADO\nDEFINITIVAMENTE\nGracias por 30 años", Color3.fromRGB(140, 25, 25), Enum.Font.GothamBold, Enum.NormalId.Front)

	-- Columnas
	for _, x in { -40, 40 } do
		for _, z in { -185, -210 } do
			box("Column", Vector3.new(2.4, STORE_H, 2.4), at(x, STORE_H / 2, z), M.Plaster, Color3.fromRGB(220, 214, 204))
		end
	end
	-- Pancarta de liquidacion colgando torcida
	local banner = deco("SaleBanner", Vector3.new(22, 3, 0.1), at(0, 12.5, -180) * CFrame.Angles(0, 0, math.rad(7)), M.SmoothPlastic, Color3.fromRGB(170, 30, 30))
	sign(banner, "LIQUIDACIÓN TOTAL  -70%", Color3.fromRGB(255, 235, 200), Enum.Font.GothamBlack, Enum.NormalId.Front)
	sign(banner, "LIQUIDACIÓN TOTAL  -70%", Color3.fromRGB(255, 235, 200), Enum.Font.GothamBlack, Enum.NormalId.Back)

	if upper then
		-- Planta de hogar: sofas y camas tapados, armarios de exposicion (escondites)
		for _, p in { { -56, -182 }, { -56, -202 }, { 56, -182 }, { 56, -202 } } do
			coveredFurniture(at(p[1], 0, p[2]), Vector3.new(9, 3.2, 4.5))
		end
		for _, x in { -40, 40 } do
			coveredFurniture(at(x, 0, -220), Vector3.new(8, 2.4, 10))
		end
		coveredMannequin(at(-24, 0, -178))
		coveredMannequin(at(66, 0, -214))
		hidingSpot("Armario", at(72.4, 3.75, -190) * FACE_NEG_X, Vector3.new(4, 7.5, 3), M.Wood, Color3.fromRGB(150, 115, 80))
		hidingSpot("Armario", at(-72.4, 3.75, -214) * FACE_POS_X, Vector3.new(4, 7.5, 3), M.Wood, Color3.fromRGB(150, 115, 80))
		for _, p in { { -34, -190 }, { 34, -186 }, { -60, -216 }, { 60, -220 } } do
			sheetMannequin(at(p[1], 0, p[2]) * CFrame.Angles(0, math.rad(rng:NextNumber(0, 360)), 0), zoneName)
		end
		-- Barandilla del hueco de las escaleras (la llegada, x = 15, entre las dos queda abierta)
		local h = ESC_HOLE
		railing(Vector3.new(h[1], 0, h[3]), Vector3.new(h[2], 0, h[3]))
		railing(Vector3.new(h[1], 0, h[4]), Vector3.new(h[2], 0, h[4]))
		railing(Vector3.new(h[1], 0, h[3]), Vector3.new(h[1], 0, h[4]))
		railing(Vector3.new(h[2], 0, h[3]), Vector3.new(h[2], 0, -204.4))
		railing(Vector3.new(h[2], 0, -195.6), Vector3.new(h[2], 0, h[4]))
		enemySpawn(60, -190)
	else
		-- Planta baja: moda. Percheros tapados, mostradores, maniquies (algunos tapados)
		for _, p in { { -58, -182 }, { -58, -198 }, { -58, -214 }, { 58, -182 }, { 58, -198 }, { 58, -214 } } do
			clothesRack(CFrame.new(p[1], Y0 + levelY, p[2]), 0, 0, pick(4, math.abs(p[2]) % 6))
			deco("DustSheet", Vector3.new(8.6, 5.4, 3), at(p[1], 2.7, p[2]), M.Fabric, SHEET)
		end
		for _, x in { -36, 36 } do
			box("Counter", Vector3.new(10, 3.5, 3), at(x, 1.75, -184), M.Wood, Color3.fromRGB(200, 190, 175))
			deco("CounterTop", Vector3.new(10.4, 0.2, 3.4), at(x, 3.6, -184), M.Marble, Color3.fromRGB(45, 44, 44))
		end
		box("CashDesk", Vector3.new(10, 3.5, 3), at(-56, 1.75, -172), M.Wood, Color3.fromRGB(110, 85, 60))
		for _, x in { -26, 26 } do
			displayMannequin(at(x, 0.6, -176) * CFrame.Angles(0, math.pi, 0))
		end
		coveredMannequin(at(-26, 0, -222))
		coveredMannequin(at(26, 0, -222))
		coveredMannequin(at(66, 0, -200))
		for _, p in { { -44, -196 }, { 44, -208 }, { -40, -216 }, { 30, -196 } } do
			sheetMannequin(at(p[1], 0, p[2]) * CFrame.Angles(0, math.rad(rng:NextNumber(0, 360)), 0), zoneName)
		end
		for _, z in { -192, -198 } do
			hidingSpot("Probador", at(-71.9, 4, z) * FACE_POS_X, Vector3.new(4.4, 8, 4), M.Fabric, Color3.fromRGB(90, 40, 50))
		end
		for k = 0, 1 do
			propOr("ShoppingCart", at(8 + k * 2.6, 0, -178 - k) * CFrame.Angles(0, math.rad(8 - k * 20), 0), function(c)
				box("ShoppingCart", Vector3.new(2.2, 2.4, 3.4), c * CFrame.new(0, 1.2, 0), M.Metal, STEEL, { Transparency = 0.3 })
			end)
		end
		-- Escaleras mecanicas paradas (unen las dos plantas)
		stoppedEscalator(-16, 15, -198)
		stoppedEscalator(-16, 15, -202)
		enemySpawn(-60, -224)
	end
	for _, p in { { -40, -200 }, { 40, -200 }, { 0, -222 }, { 0, -176 } } do
		emergencyLight(at(p[1], STORE_H, p[2]), p[1] == 0)
	end
	spot(0, -186, "CoverMannequins", zoneName)
	spot(-20, -212, "CleanSpill", zoneName)
	spot(50, -224, "LostItem", zoneName)
	patrolClock(-66, -172, zoneName)
	enemySpawn(60, -224)
	camera(-70, 13, -170, -20, 0, -200)
end

local function buildSouthWing()
	local wingFolder = folder("AlaSur")
	levelY = 0
	local top = GALLERY_TOP + 4
	-- Muros exteriores: lados (x ±74.5) y fondo de los grandes almacenes
	for _, s in { -1, 1 } do
		wall(Vector3.new(s * (ANCHOR.X2 + 0.5), 0, -71), Vector3.new(s * (ANCHOR.X2 + 0.5), 0, ANCHOR.Z1 - 1), top)
	end
	wall(Vector3.new(-(ANCHOR.X2 + 1), 0, ANCHOR.Z1 - 0.5), Vector3.new(ANCHOR.X2 + 1, 0, ANCHOR.Z1 - 0.5), top)
	-- Contenedor de escombros (vale para Sacar la basura y Vaciar papeleras)
	local skip = box("DebrisSkip", Vector3.new(10, 4.5, 5), at(-16, 2.25, -160), M.Metal, Color3.fromRGB(200, 120, 30))
	tag(skip, Tags.TrashDropoff)
	deco("Rubble", Vector3.new(9, 1.4, 4), at(-16, 4.6, -160) * CFrame.Angles(math.rad(4), 0, math.rad(-3)), M.Slate, Color3.fromRGB(120, 116, 110))

	for floorIndex, ly in { 0, F2 } do
		levelY = ly
		currentParent = wingFolder
		local upper = ly > 0
		local P2 = if upper then " P2" else ""
		local wingName = "Ala Sur" .. P2
		local accessName = "Acceso Ala Sur" .. P2
		local floorName = if upper then "Planta alta" else "Planta baja"

		zone(accessName, -WING, WING, -70, -20, 16)
		zone(wingName, -WING, WING, SOUTH_Z1, -70, 16)
		corridorFloor(SOUTH_Z1, -20)
		ceiling(-WING, WING, SOUTH_Z1, -20, STORE_H + 1)
		passageEntrance(-20, -1, if upper then "ALA SUR  ·  P2  ·  EN OBRAS" else "ALA SUR  ·  EN REMODELACIÓN", CAUTION)
		-- Valla de obra a la entrada del pasaje (paso de 10 en el centro) con avisos
		wall(Vector3.new(-WING, 0, -22.5), Vector3.new(WING, 0, -22.5), 11, {
			Material = M.Wood,
			Color = PLYWOOD,
			Baseboard = false,
			Openings = { { From = WING - 5, To = WING + 5, Height = 9 } },
		})
		for _, x in { -14.5, 14.5 } do
			local panel = deco("HoardingPrint", Vector3.new(16, 6, 0.1), at(x, 5, -21.9) * CFrame.Angles(0, math.pi, 0), M.SmoothPlastic, Color3.fromRGB(28, 30, 38))
			sign(panel, if x < 0 then "DISCULPEN LAS\nMOLESTIAS" else "ESTAMOS MEJORANDO\nPARA USTED", Color3.fromRGB(235, 200, 90), Enum.Font.GothamBlack, Enum.NormalId.Front)
		end
		cautionTape(Vector3.new(-5, 3.4, -22.4), Vector3.new(5, 3.9, -22.4))
		cautionTape(Vector3.new(-5, 5.6, -22.4), Vector3.new(5, 5.1, -22.4))

		-- Suelo levantado: parches de cemento sobre el marmol
		for _, p in { { -10, -40, 12, 9 }, { 8, -88, 16, 12 }, { -6, -122, 20, 10 }, { 12, -150, 10, 14 } } do
			deco("ConcretePatch", Vector3.new(p[3], 0.06, p[4]), at(p[1], 0.03, p[2]) * CFrame.Angles(0, math.rad(p[1]), 0), M.Concrete, Color3.fromRGB(128, 126, 120))
		end
		-- Laminas de plastico colgando en el pasillo (no dejan ver lo que hay detras)
		for _, z in { -64, -112, -152 } do
			for _, x in { -14, -4, 9 } do
				plasticSheet(at(x + rng:NextNumber(-1.5, 1.5), 8, z + rng:NextNumber(-1, 1)) * CFrame.Angles(0, math.rad(rng:NextNumber(-8, 8)), 0), 9, 15.6)
			end
		end
		-- Andamios, escaleras, material
		scaffold(at(-19, 0, -84), 8, 4, 14)
		scaffold(at(19, 0, -132), 8, 4, 14)
		ladder(at(18, 0, -98) * CFrame.Angles(0, math.rad(-90), 0), 12)
		cementBags(at(-19, 0, -120))
		paintBuckets(at(17, 0, -78))
		drywallStack(at(-14, 0, -146) * CFrame.Angles(0, math.rad(90), 0))
		workLamp(at(0, 0, -96))
		workLamp(at(-6, 0, -158))
		-- Cables colgando del techo
		for _, p in { { -8, -52 }, { 6, -100 }, { -2, -138 } } do
			deco("HangingCable", Vector3.new(0.12, 5, 0.12), at(p[1], STORE_H - 2.5, p[2]) * CFrame.Angles(math.rad(8), 0, math.rad(6)), M.Rubber, DARK)
		end
		for z = -60, -160, -50 do
			emergencyLight(at(0, STORE_H, z), z % 100 == 0)
		end

		-- Locales en obras (4 por planta) y herramientas de la mision (4 por planta)
		local base = if upper then 4 else 0
		local tools = { "Compressor", nil, nil, "Generator" }
		for i, slot in SOUTH_SLOTS do
			constructionUnit(base + i, slot[1], slot[2], wingName, tools[i])
		end
		currentParent = wingFolder
		powerTool("Mixer", at(14, 0, -114) * CFrame.Angles(0, math.rad(20), 0), wingName)
		powerTool("Saw", at(-13, 0, -100) * CFrame.Angles(0, math.rad(90), 0), wingName)

		-- Puntos de mision del pasillo
		spot(0, -120, "UnplugTools", wingName)
		spot(-8, -104, "CleanSpill", wingName)
		spot(10, -150, "CleanSpill", wingName)
		spot(6, -140, "LostItem", wingName)
		spot(-8, -88, "TakeOutTrash", wingName)
		patrolClock(20, -76, wingName)
		wallExtinguisher(at(-20, 0, SOUTH_Z1) * CFrame.Angles(0, math.pi, 0), floorName)
		if upper then
			hidingSpot("Baño portátil", at(19, 4, -160), Vector3.new(4.4, 8, 4.4), M.Plastic, Color3.fromRGB(40, 95, 170))
		end
		camera(22, 13, -72, 0, 0, -120)
		enemySpawn(0, -160)
		enemySpawn(-14, -74)

		-- Grandes almacenes del fondo
		buildAnchorStore(upper)
	end

	levelY = 0
	currentParent = map
end

----------------------------------------------------------------------
-- Arranque
----------------------------------------------------------------------

function MallBuilder.BuildIfNeeded()
	if not Config.Debug.BuildTestMap then
		return
	end
	if Workspace:FindFirstChild("Mall") or #CollectionService:GetTagged(Tags.Zone) > 0 then
		return
	end

	loadVariants()
	propFolder = ServerStorage:FindFirstChild("PropTemplates")
	map = Instance.new("Model")
	map.Name = "Mall"
	currentParent = map
	levelY = 0

	buildShell()
	buildGallery()
	levelY = 0
	buildStoreRow(STORES_1, "Galería Oeste", "Galería Este")
	buildFoodCourt()
	buildEntrance()
	buildParking()
	buildService()

	buildUpperGallery()
	levelY = F2
	buildStoreRow(STORES_2, "Planta alta Oeste", "Planta alta Este")
	levelY = 0
	buildCinema()
	buildArcade()
	buildOffices()
	-- Alas nuevas (2026-11-25): Ala Norte (tiendas + pasillo de servicio) y Ala Sur (obras)
	buildNorthWing()
	buildSouthWing()

	-- Atenuar todas las luces (ambiente de terror). Config.MallLightScale = 1 para el brillo original.
	local scale = Config.MallLightScale or 1
	if scale ~= 1 then
		for _, d in map:GetDescendants() do
			if d:IsA("Light") then
				d.Brightness *= scale
			end
		end
	end

	map.Parent = Workspace
	print("[MallBuilder] Centro comercial (2 plantas) construido (desactivar en Config.Debug.BuildTestMap)")
end

return MallBuilder
