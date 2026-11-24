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

local STONE = Color3.fromRGB(208, 203, 194)
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
-- Una dama de marmol con tunica y los brazos en alto (sostiene el chorro de agua
-- en el mall y la luna en el lobby). Ojos de piedra que se encienden en rojo al
-- despertar (partes "Eye", transparentes mientras duerme).

EntityModels.STATUE_HEIGHT = 9.1
-- Punto entre las manos, sobre la cabeza (desde los pies): ahi va lo que sostiene
EntityModels.STATUE_HANDS_Y = 8.85

function EntityModels.statue(): Model
	local custom = template("Statue")
	if custom then
		return custom
	end
	local H = EntityModels.STATUE_HEIGHT
	local model = newModel("Statue", H)
	local function at(x: number, yFromFeet: number, z: number): CFrame
		return CFrame.new(x, yFromFeet - H / 2, z)
	end
	local function stone(name: string, size: Vector3, cf: CFrame, shape: Enum.PartType?)
		local p = part({
			Name = name,
			Size = size,
			CFrame = cf,
			Color = STONE,
			Material = Enum.Material.Marble,
			CanCollide = true,
		})
		if shape then
			p.Shape = shape
		end
		p:SetAttribute("Stone", true)
		p.Parent = model
		return p
	end
	-- Tunica hasta los pies, con el bajo mas ancho y pliegues
	stone("Hem", Vector3.new(2.6, 0.5, 1.9), at(0, 0.25, 0))
	stone("Robe", Vector3.new(2.2, 3.4, 1.6), at(0, 2.05, 0))
	for _, x in { -0.75, 0, 0.75 } do
		stone("Fold", Vector3.new(0.18, 3.2, 0.15), at(x, 1.9, -0.82))
	end
	stone("Sash", Vector3.new(2.25, 0.3, 1.65), at(0, 3.65, 0))
	-- Torso, cuello y cabeza con mono
	stone("Torso", Vector3.new(1.8, 2, 0.95), at(0, 4.6, 0))
	stone("Neck", Vector3.new(0.5, 0.45, 0.5), at(0, 5.8, 0))
	stone("Head", Vector3.new(1.15, 1.15, 1.15), at(0, 6.45, 0), Enum.PartType.Ball)
	stone("Bun", Vector3.new(0.6, 0.6, 0.6), at(0, 6.75, 0.48), Enum.PartType.Ball)
	-- Brazos en alto: brazo hacia fuera y antebrazo hacia dentro (las manos sobre la cabeza)
	for _, side in { -1, 1 } do
		local shoulder = Vector3.new(side * 1.05, 5.4, 0)
		local upperDir = Vector3.new(side * math.sin(math.rad(20)), math.cos(math.rad(20)), 0)
		local elbow = shoulder + upperDir * 2
		local foreDir = Vector3.new(-side * math.sin(math.rad(15)), math.cos(math.rad(15)), 0)
		local hand = elbow + foreDir * 1.5
		local mid1 = shoulder + upperDir
		local mid2 = elbow + foreDir * 0.75
		stone("Shoulder", Vector3.new(0.55, 0.55, 0.55), at(shoulder.X, shoulder.Y, 0), Enum.PartType.Ball)
		stone("UpperArm", Vector3.new(0.45, 2, 0.45), at(mid1.X, mid1.Y, 0) * CFrame.Angles(0, 0, -side * math.rad(20)))
		stone("Elbow", Vector3.new(0.42, 0.42, 0.42), at(elbow.X, elbow.Y, 0), Enum.PartType.Ball)
		stone("Forearm", Vector3.new(0.4, 1.5, 0.4), at(mid2.X, mid2.Y, 0) * CFrame.Angles(0, 0, side * math.rad(15)))
		stone("Hand", Vector3.new(0.5, 0.5, 0.5), at(hand.X, hand.Y + 0.1, 0), Enum.PartType.Ball)
	end
	-- Ojos (solo se ven cuando despierta)
	for _, x in { -0.22, 0.22 } do
		local eye = part({
			Name = "Eye",
			Size = Vector3.new(0.2, 0.1, 0.05),
			CFrame = at(x, 6.55, -0.56),
			Color = Color3.fromRGB(255, 40, 30),
			Material = Enum.Material.Neon,
			Transparency = 1,
		})
		eye.Parent = model
	end
	return model
end

-- Despierta (ojos rojos) o vuelve a ser piedra.
function EntityModels.setStatueAwake(model: Model, awake: boolean)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Name == "Eye" then
			d.Transparency = if awake then 0 else 1
		end
	end
	model:SetAttribute("Awake", awake)
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
