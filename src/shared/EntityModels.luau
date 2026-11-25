-- EntityModels: modelos de las entidades que tambien son decoracion del mapa.
--
-- La Estatua de la fuente y los maniquies de escaparate estan SIEMPRE en el mapa
-- (mall y lobby). Cuando aparece la entidad, es ese mismo modelo el que cobra vida,
-- y al terminar la noche vuelve a su sitio. Por eso el mapa (MallBuilder, la plaza
-- del lobby) y los enemigos sacan el modelo de aqui.
--
-- Convencion (igual que los enemigos): Model con una parte raiz invisible "Root"
-- (PrimaryPart) del alto total del modelo; el pivote esta en su centro y los pies
-- en el fondo de la raiz. El frente es -Z.
--
-- Plantillas propias: si existe ServerStorage.EnemyTemplates.<Nombre> (Model con
-- PrimaryPart) se usa en vez del modelo de piezas. Solo funciona en el servidor.

local RunService = game:GetService("RunService")

local EntityModels = {}

local SKIN = Color3.fromRGB(226, 216, 200)

local function part(props): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props do
		(p :: any)[k] = v
	end
	return p
end

local function newModel(name: string, height: number): (Model, Part)
	local model = Instance.new("Model")
	model.Name = name
	local root = part({
		Name = "Root",
		Size = Vector3.new(2, height, 2),
		Transparency = 1,
		CanQuery = false,
		CFrame = CFrame.new(),
	})
	root.Parent = model
	model.PrimaryPart = root
	return model, root
end

local function template(name: string): Model?
	if not RunService:IsServer() then
		return nil
	end
	local folder = game:GetService("ServerStorage"):FindFirstChild("EnemyTemplates")
	local found = folder and folder:FindFirstChild(name)
	if found and found:IsA("Model") and found.PrimaryPart then
		return found:Clone()
	end
	return nil
end

----------------------------------------------------------------------
-- Estatua de la fuente
----------------------------------------------------------------------
-- Un guerrero de piedra (un golem) con casco y un hacha doble levantada delante, las
-- manos sobre el pomo. En el mall el chorro de agua sale del pomo del hacha; en el lobby
-- la luna flota sobre el casco. Los ojos y las runas del pecho se encienden al despertar
-- (piezas "Eye" o con el atributo Glow, transparentes mientras duerme). Despierto camina
-- con sus piernas de piedra (EnemyAnimator, estilo Golem); el resto del cuerpo es rigido.

EntityModels.STATUE_HEIGHT = 9.1
-- Pomo del hacha, entre las manos (desde los pies): de ahi sale el chorro de la fuente
EntityModels.STATUE_HANDS_Y = 6.05
-- Sobre el casco (desde los pies): ahi flota la luna del lobby
EntityModels.STATUE_TOP_Y = 8.7
-- Eje de los hombros (desde los pies): ahi gira el hachazo
EntityModels.STATUE_SHOULDER_Y = 5.75

local STATUE_STONE = Color3.fromRGB(122, 128, 140)
local STATUE_DARK = Color3.fromRGB(88, 93, 106)
local STATUE_SHADOW = Color3.fromRGB(40, 42, 50)
local STATUE_MOSS = Color3.fromRGB(80, 120, 65)
local STATUE_GLOW = Color3.fromRGB(255, 140, 40)

function EntityModels.statue(): Model
	local custom = template("Statue")
	if custom then
		return custom
	end
	local H = EntityModels.STATUE_HEIGHT
	local model = newModel("Statue", H)
	local FEET = Vector3.new(0, H / 2, 0)
	local function at(x: number, yFromFeet: number, z: number): CFrame
		return CFrame.new(x, yFromFeet - H / 2, z)
	end
	-- Piezas principales (chocan como decoracion; las piernas y los pies andan)
	local function stone(name: string, size: Vector3, cf: CFrame, color: Color3?)
		local p = part({
			Name = name,
			Size = size,
			CFrame = cf,
			Color = color or STATUE_STONE,
			Material = Enum.Material.Slate,
			CanCollide = true,
		})
		p:SetAttribute("Stone", true)
		p.Parent = model
		return p
	end
	-- Detalles: soldados a la raiz al despertar (Common.prepareModel) o, con `follow`, a esa pierna
	local function carve(name: string, size: Vector3, cf: CFrame, color: Color3?, follow: string?, material: Enum.Material?)
		local p = part({
			Name = name,
			Size = size,
			CFrame = cf,
			Color = color or STATUE_STONE,
			Material = material or Enum.Material.Slate,
		})
		p:SetAttribute("Stone", true)
		if follow then
			p:SetAttribute("Follow", follow)
		else
			p:SetAttribute("Detail", true)
		end
		p.Parent = model
		return p
	end
	-- Bloque de a hasta b (puntos desde los pies)
	local function beam(name: string, a: Vector3, b: Vector3, thickness: number, color: Color3?, follow: string?)
		return carve(name, Vector3.new(thickness, thickness, (b - a).Magnitude), CFrame.lookAt((a + b) / 2 - FEET, b - FEET), color, follow)
	end
	-- Lo que brilla al despertar (ojos y runas): apagado mientras es piedra
	local function glow(name: string, size: Vector3, cf: CFrame)
		local p = part({
			Name = name,
			Size = size,
			CFrame = cf,
			Color = STATUE_GLOW,
			Material = Enum.Material.Neon,
			Transparency = 1,
		})
		p:SetAttribute("Glow", true)
		p:SetAttribute("Detail", true)
		p.Parent = model
		return p
	end

	-- Piernas de columna con pies grandes, rodilleras y grebas
	for _, side in { -1, 1 } do
		local legName = if side < 0 then "LeftLeg" else "RightLeg"
		local x = side * 0.75
		stone(legName, Vector3.new(1.1, 2.6, 1.15), at(x, 1.85, 0))
		stone("Foot", Vector3.new(1.35, 0.55, 1.7), at(x, 0.275, -0.2), STATUE_DARK)
		carve("KneeGuard", Vector3.new(1.25, 0.6, 0.35), at(x, 2.05, -0.6), STATUE_DARK, legName)
		carve("Greave", Vector3.new(0.85, 1.0, 0.15), at(x, 1.15, -0.62), STATUE_STONE, legName)
		carve("Vine", Vector3.new(0.12, 1.7, 0.06), at(x + side * 0.3, 1.55, -0.62), STATUE_MOSS, legName, Enum.Material.Grass)
	end
	-- Cadera con faldon de placas, cinturon y hebilla con una runa
	stone("Hips", Vector3.new(2.7, 0.9, 1.6), at(0, 3.45, 0), STATUE_DARK)
	for _, x in { -0.95, 0, 0.95 } do
		carve("Tasset", Vector3.new(0.8, 1.0, 0.2), at(x, 2.95, -0.86) * CFrame.Angles(math.rad(-14), 0, 0), STATUE_STONE)
	end
	carve("Belt", Vector3.new(2.8, 0.32, 1.7), at(0, 3.9, 0), STATUE_SHADOW)
	carve("Buckle", Vector3.new(0.65, 0.5, 0.12), at(0, 3.9, -0.88), STATUE_STONE)
	glow("Rune", Vector3.new(0.25, 0.25, 0.05), at(0, 3.9, -0.95) * CFrame.Angles(0, 0, math.rad(45)))
	-- Torso con peto agrietado (las grietas son runas que se encienden)
	stone("Torso", Vector3.new(2.7, 2.4, 1.7), at(0, 5.2, 0))
	carve("ChestPlate", Vector3.new(2.1, 1.6, 0.2), at(0, 5.45, -0.9), STATUE_DARK)
	glow("Rune", Vector3.new(0.09, 0.9, 0.05), at(-0.3, 5.45, -1.02) * CFrame.Angles(0, 0, math.rad(20)))
	glow("Rune", Vector3.new(0.09, 0.6, 0.05), at(0.2, 5.25, -1.02) * CFrame.Angles(0, 0, math.rad(-30)))
	glow("Rune", Vector3.new(0.09, 0.5, 0.05), at(0.0, 5.85, -1.02) * CFrame.Angles(0, 0, math.rad(75)))
	carve("Vine", Vector3.new(0.12, 2.1, 0.06), at(1.05, 5.0, -0.88), STATUE_MOSS, nil, Enum.Material.Grass)
	for _, y in { 4.4, 5.1, 5.7 } do
		carve("Leaf", Vector3.new(0.28, 0.14, 0.08), at(1.18, y, -0.9) * CFrame.Angles(0, 0, math.rad(30)), STATUE_MOSS, nil, Enum.Material.Grass)
	end
	-- Capa de piedra raida a la espalda
	carve("Cape", Vector3.new(2.5, 3.5, 0.25), at(0, 4.45, 1.0) * CFrame.Angles(math.rad(6), 0, 0), STATUE_DARK)
	for i, x in { -0.85, 0, 0.85 } do
		carve("CapeTatter", Vector3.new(0.75, 0.3 + (i % 2) * 0.3, 0.24), at(x, 2.55 - (i % 2) * 0.15, 1.12) * CFrame.Angles(math.rad(6), 0, 0), STATUE_DARK)
	end
	-- Gola, casco con cresta, visera con los ojos, protector de cara con rendijas
	stone("Gorget", Vector3.new(1.8, 0.45, 1.5), at(0, 6.55, 0), STATUE_DARK)
	stone("Head", Vector3.new(1.35, 1.4, 1.35), at(0, 7.45, 0))
	carve("Brow", Vector3.new(1.45, 0.3, 0.25), at(0, 7.75, -0.62), STATUE_DARK)
	carve("Socket", Vector3.new(1.2, 0.26, 0.05), at(0, 7.45, -0.68), STATUE_SHADOW)
	carve("FaceGuard", Vector3.new(1.2, 0.55, 0.2), at(0, 7.03, -0.68), STATUE_DARK)
	for i = -1, 1 do
		carve("Slit", Vector3.new(0.07, 0.4, 0.05), at(i * 0.25, 7.0, -0.79), STATUE_SHADOW)
	end
	for _, side in { -1, 1 } do
		carve("CheekGuard", Vector3.new(0.15, 0.9, 0.95), at(side * 0.72, 7.2, -0.12), STATUE_DARK)
		glow("Eye", Vector3.new(0.3, 0.14, 0.06), at(side * 0.28, 7.45, -0.72))
	end
	carve("Crest", Vector3.new(0.3, 0.45, 1.5), at(0, 8.35, 0), STATUE_DARK)
	-- Lleva tanto tiempo quieta que le ha brotado una planta en el casco
	carve("Moss", Vector3.new(0.55, 0.15, 0.5), at(0.42, 8.2, 0.35), STATUE_MOSS, nil, Enum.Material.Grass)
	carve("Sprout", Vector3.new(0.08, 0.45, 0.08), at(0.45, 8.5, 0.35), STATUE_MOSS, nil, Enum.Material.Grass)
	carve("Leaf", Vector3.new(0.3, 0.06, 0.16), at(0.6, 8.7, 0.35) * CFrame.Angles(0, 0, math.rad(25)), STATUE_MOSS, nil, Enum.Material.Grass)
	carve("Leaf", Vector3.new(0.3, 0.06, 0.16), at(0.3, 8.65, 0.35) * CFrame.Angles(0, 0, math.rad(-25)), STATUE_MOSS, nil, Enum.Material.Grass)
	-- Eje de los hombros (invisible): los brazos y el hacha van soldados a el, asi el
	-- hachazo es girarlo (Statue.luau, EntityModels.setStatueSwing)
	local rig = part({
		Name = "AxeRig",
		Size = Vector3.new(0.4, 0.4, 0.4),
		CFrame = at(0, EntityModels.STATUE_SHOULDER_Y, 0),
		Transparency = 1,
		CanQuery = false,
	})
	rig.Parent = model
	local ARMS = "AxeRig"
	-- Hombreras con pinchos y musgo; brazos doblados con las manos sobre el pomo del hacha
	-- (no se llaman Arm: no se balancean al andar, sostienen el hacha)
	local fistZ = -1.38
	for _, side in { -1, 1 } do
		stone("Pauldron", Vector3.new(1.3, 1.0, 1.75), at(side * 1.75, 6.25, 0), STATUE_DARK)
		carve("PauldronRim", Vector3.new(1.36, 0.2, 1.8), at(side * 1.75, 5.8, 0), STATUE_STONE)
		carve("Spike", Vector3.new(0.35, 0.55, 0.35), at(side * 2.0, 6.95, 0) * CFrame.Angles(0, math.rad(45), 0), STATUE_STONE)
		carve("Moss", Vector3.new(0.7, 0.15, 0.6), at(side * 1.55, 6.8, 0.35), STATUE_MOSS, nil, Enum.Material.Grass)
		local shoulder = Vector3.new(side * 1.75, 5.75, 0)
		local elbow = Vector3.new(side * 1.85, 4.45, -0.35)
		local fist = Vector3.new(side * 0.42, 4.95, fistZ)
		beam("UpperLimb", shoulder, elbow, 0.9, nil, ARMS)
		carve("Elbow", Vector3.new(1.0, 1.0, 1.0), at(elbow.X, elbow.Y, elbow.Z), STATUE_DARK, ARMS)
		beam("Forelimb", elbow, fist, 0.8, nil, ARMS)
		beam("Bracer", elbow:Lerp(fist, 0.4), elbow:Lerp(fist, 0.78), 0.92, STATUE_DARK, ARMS)
		carve("Fist", Vector3.new(0.85, 0.85, 0.95), at(fist.X, fist.Y, fist.Z), STATUE_STONE, ARMS)
	end
	-- Hacha doble: mango con empuñaduras, pomo (de ahi sale el chorro) y dos hojas
	-- escalonadas con el filo claro (por encima de los pies: no las pisa al andar)
	local axeZ = fistZ - 0.02
	carve("AxeHandle", Vector3.new(0.32, 4.6, 0.32), at(0, 3.55, axeZ), STATUE_DARK, ARMS)
	for _, y in { 2.9, 3.25, 3.6 } do
		carve("Grip", Vector3.new(0.4, 0.14, 0.4), at(0, y, axeZ), STATUE_SHADOW, ARMS)
	end
	carve("Pommel", Vector3.new(0.5, 0.35, 0.5), at(0, 5.88, axeZ), STATUE_STONE, ARMS)
	carve("AxeCore", Vector3.new(0.6, 1.2, 0.5), at(0, 2.3, axeZ), STATUE_DARK, ARMS)
	carve("AxeSpike", Vector3.new(0.25, 0.5, 0.25), at(0, 1.45, axeZ), STATUE_DARK, ARMS)
	-- (piedra mas clara que el cuerpo: el hacha se distingue de las piernas)
	local BLADE = Color3.fromRGB(175, 182, 195)
	for _, side in { -1, 1 } do
		carve("AxeBlade", Vector3.new(0.7, 1.3, 0.26), at(side * 0.62, 2.3, axeZ), BLADE, ARMS)
		carve("AxeBlade", Vector3.new(0.45, 1.9, 0.26), at(side * 1.18, 2.3, axeZ), BLADE, ARMS)
		carve("AxeBlade", Vector3.new(0.3, 2.4, 0.26), at(side * 1.53, 2.3, axeZ), BLADE, ARMS)
		carve("AxeEdge", Vector3.new(0.14, 2.4, 0.28), at(side * 1.74, 2.3, axeZ), Color3.fromRGB(225, 230, 238), ARMS)
		carve("AxeEdge", Vector3.new(0.1, 0.3, 0.27), at(side * 1.0, 2.3, axeZ), STATUE_DARK, ARMS) -- muesca
	end
	glow("Rune", Vector3.new(0.2, 0.2, 0.05), at(0, 2.3, axeZ - 0.27) * CFrame.Angles(0, 0, math.rad(45))):SetAttribute("Follow", ARMS)
	-- Grietas
	carve("Crack", Vector3.new(0.05, 0.8, 0.04), at(-0.85, 4.6, -0.86) * CFrame.Angles(0, 0, math.rad(-25)), STATUE_SHADOW)
	carve("Crack", Vector3.new(0.05, 0.5, 0.04), at(0.4, 7.6, -0.68) * CFrame.Angles(0, 0, math.rad(15)), STATUE_SHADOW)
	return model
end

-- Despierta (ojos y runas encendidos) o vuelve a ser piedra.
function EntityModels.setStatueAwake(model: Model, awake: boolean)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and (d.Name == "Eye" or d:GetAttribute("Glow")) then
			d.Transparency = if awake then 0 else 1
		end
	end
	model:SetAttribute("Awake", awake)
end

-- Pose del hachazo: brazos y hacha girados `angle` grados sobre los hombros (0 = en
-- reposo, delante; positivo = hacia arriba por delante; 150 = sobre la cabeza).
-- (Solo con la estatua despierta: Common.prepareModel suelda los brazos al eje.)
function EntityModels.setStatueSwing(model: Model, angle: number)
	local root = model.PrimaryPart
	local rig = model:FindFirstChild("AxeRig") :: BasePart?
	if root and rig then
		local rest = CFrame.new(0, EntityModels.STATUE_SHOULDER_Y - root.Size.Y / 2, 0)
		rig.CFrame = root.CFrame * rest * CFrame.Angles(math.rad(angle), 0, 0)
	end
end

----------------------------------------------------------------------
-- Maniqui
----------------------------------------------------------------------

function EntityModels.mannequin(): Model
	local custom = template("Mannequin")
	if custom then
		return custom
	end
	local model = newModel("Mannequin", 6)
	local function add(name, size, offset, shape)
		local p = part({
			Name = name,
			Size = size,
			CFrame = CFrame.new(offset),
			Color = SKIN,
			Material = Enum.Material.SmoothPlastic,
			CanCollide = true,
		})
		if shape then
			p.Shape = shape
		end
		p.Parent = model
		return p
	end
	add("LeftLeg", Vector3.new(0.9, 2.6, 0.9), Vector3.new(-0.5, -1.7, 0))
	add("RightLeg", Vector3.new(0.9, 2.6, 0.9), Vector3.new(0.5, -1.7, 0))
	add("Torso", Vector3.new(2, 2.4, 1), Vector3.new(0, 0.8, 0))
	add("LeftArm", Vector3.new(0.7, 2.5, 0.7), Vector3.new(-1.4, 0.75, 0))
	add("RightArm", Vector3.new(0.7, 2.5, 0.7), Vector3.new(1.4, 0.75, 0))
	add("Head", Vector3.new(1.3, 1.3, 1.3), Vector3.new(0, 2.4, 0), Enum.PartType.Ball)
	return model
end

----------------------------------------------------------------------
-- Colocar como decoracion
----------------------------------------------------------------------

-- Alto del modelo (de los pies a lo mas alto).
function EntityModels.height(model: Model): number
	local _, size = model:GetBoundingBox()
	return size.Y
end

-- Coloca el modelo de pie sobre `feet` (CFrame en el suelo, mirando hacia -Z local).
-- Guarda su sitio (HomeCFrame) para que la entidad pueda volver al terminar la noche.
function EntityModels.placeAt(model: Model, feet: CFrame, parent: Instance)
	local root = model.PrimaryPart :: BasePart
	local height = root.Size.Y
	local cf = feet * CFrame.new(0, height / 2, 0)
	model:PivotTo(cf)
	model:SetAttribute("HomeCFrame", cf)
	model.Parent = parent
end

return EntityModels
