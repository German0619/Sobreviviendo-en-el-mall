-- TestMapBuilder: construye un mall de prueba (4 zonas) si el lugar no tiene
-- un mapa propio. Sirve para jugar mientras modelas el mall de verdad y de
-- ejemplo de como poner los tags/atributos.
--
-- Se salta si existe Workspace.Mall o cualquier parte con tag MallZone.
-- Desactivar: Config.Debug.BuildTestMap = false
--
--   +----------------+----------------+
--   |  Comida (NW)   |  Tiendas (NE)  |      puertas en el centro
--   +------  --------+-------  -------+      de cada pared interior
--   |  Bodega (SW)   |  Atrio (SE)    |
--   +----------------+----------------+      (los jugadores aparecen en el Atrio)

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Tags = require(Shared.Tags)

local TestMapBuilder = {}

local HALF = 80 -- medio ancho del mall (160 x 160 studs)
local WALL_H = 20
local DOOR_W = 12
local FLOOR_Y = 0.05 -- cara superior del suelo

local function part(props, parent: Instance): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props do
		p[k] = v
	end
	p.Parent = parent
	return p
end

local function tag(inst: Instance, tagName: string, attributes)
	for k, v in attributes or {} do
		inst:SetAttribute(k, v)
	end
	CollectionService:AddTag(inst, tagName)
end

local function wall(parent, center: Vector3, size: Vector3)
	part({
		Name = "Wall",
		Size = size,
		Position = center,
		Material = Enum.Material.Concrete,
		Color = Color3.fromRGB(150, 145, 138),
	}, parent)
end

-- Pared a lo largo de un eje con dos huecos de puerta en +-HALF/2.
local function wallWithDoors(parent, axis: "X" | "Z")
	local door = HALF / 2
	local segments = {
		{ -HALF, -door - DOOR_W / 2 },
		{ -door + DOOR_W / 2, door - DOOR_W / 2 },
		{ door + DOOR_W / 2, HALF },
	}
	for _, seg in segments do
		local a, b = seg[1], seg[2]
		local mid, len = (a + b) / 2, b - a
		if axis == "Z" then
			wall(parent, Vector3.new(0, WALL_H / 2, mid), Vector3.new(2, WALL_H, len))
		else
			wall(parent, Vector3.new(mid, WALL_H / 2, 0), Vector3.new(len, WALL_H, 2))
		end
	end
end

local function spot(parent, position: Vector3, missionType: string, zone: string)
	local p = part({
		Name = "Spot_" .. missionType,
		Size = Vector3.new(1, 0.2, 1),
		Position = Vector3.new(position.X, FLOOR_Y + 0.1, position.Z),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
	}, parent)
	tag(p, Tags.MissionSpot, { MissionType = missionType, Zone = zone })
	return p
end

local ROOMS = {
	{ Name = "Atrio", X = 40, Z = -40, Floor = Color3.fromRGB(190, 185, 175) },
	{ Name = "Tiendas", X = 40, Z = 40, Floor = Color3.fromRGB(170, 160, 150) },
	{ Name = "Comida", X = -40, Z = 40, Floor = Color3.fromRGB(160, 120, 100) },
	{ Name = "Bodega", X = -40, Z = -40, Floor = Color3.fromRGB(110, 110, 110) },
}

local function buildRoom(map: Model, room)
	local folder = Instance.new("Folder")
	folder.Name = room.Name
	folder.Parent = map
	local cx, cz = room.X, room.Z
	local sx, sz = math.sign(cx), math.sign(cz)

	-- Suelo de la zona
	part({
		Name = "Floor",
		Size = Vector3.new(HALF, 1, HALF),
		Position = Vector3.new(cx, FLOOR_Y - 0.5, cz),
		Material = if room.Name == "Bodega" then Enum.Material.Concrete else Enum.Material.Marble,
		Color = room.Floor,
	}, folder)

	-- Volumen de zona
	local zonePart = part({
		Name = "Zone_" .. room.Name,
		Size = Vector3.new(HALF - 1, WALL_H, HALF - 1),
		Position = Vector3.new(cx, WALL_H / 2, cz),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
	}, folder)
	tag(zonePart, Tags.Zone, { Zone = room.Name })

	-- Lamparas del techo
	for _, ox in { -20, 20 } do
		for _, oz in { -20, 20 } do
			local lamp = part({
				Name = "Lamp",
				Size = Vector3.new(6, 0.4, 2),
				Position = Vector3.new(cx + ox, WALL_H - 0.3, cz + oz),
				Material = Enum.Material.Neon,
				Color = Color3.fromRGB(255, 244, 225),
				CanCollide = false,
			}, folder)
			local light = Instance.new("PointLight")
			light.Range = 30
			light.Brightness = 1.4
			light.Color = Color3.fromRGB(255, 238, 215)
			light.Shadows = true
			light.Parent = lamp
			tag(lamp, Tags.Light, { Zone = room.Name })
		end
	end

	-- Tablero electrico (mision Reparar luces) en la pared exterior
	local panel = part({
		Name = "ElectricPanel",
		Size = Vector3.new(3, 4, 0.6),
		Position = Vector3.new(cx, FLOOR_Y + 4, sz * (HALF - 0.4)),
		Material = Enum.Material.DiamondPlate,
		Color = Color3.fromRGB(90, 95, 100),
	}, folder)
	tag(panel, Tags.MissionSpot, { MissionType = "FixLights", Zone = room.Name })

	-- Derrames
	spot(folder, Vector3.new(cx - 15 * sx, 0, cz + 10 * sz), "CleanSpill", room.Name)
	spot(folder, Vector3.new(cx + 12 * sx, 0, cz - 14 * sz), "CleanSpill", room.Name)

	-- Basura (no en la bodega, ahi esta el contenedor)
	if room.Name ~= "Bodega" then
		spot(folder, Vector3.new(cx + 25 * sx, 0, cz + 25 * sz), "TakeOutTrash", room.Name)
	end

	-- Aparicion de enemigos (no en el Atrio, donde aparecen los jugadores)
	if room.Name ~= "Atrio" then
		local enemySpawn = part({
			Name = "EnemySpawn",
			Size = Vector3.new(2, 0.2, 2),
			Position = Vector3.new(cx + 30 * sx, FLOOR_Y + 0.1, cz + 30 * sz),
			Transparency = 1,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
		}, folder)
		tag(enemySpawn, Tags.EnemySpawn)
	end

	return folder
end

local function buildProps(map: Model)
	local props = Instance.new("Folder")
	props.Name = "Props"
	props.Parent = map

	-- Tiendas: estanterias
	for _, x in { 20, 35, 50, 65 } do
		part({
			Name = "Shelf",
			Size = Vector3.new(2, 6, 14),
			Position = Vector3.new(x, FLOOR_Y + 3, 55),
			Material = Enum.Material.Wood,
			Color = Color3.fromRGB(120, 90, 60),
		}, props)
	end
	-- Comida: mesas
	for _, pos in { Vector2.new(-60, 60), Vector2.new(-45, 64), Vector2.new(-28, 62), Vector2.new(-62, 22) } do
		part({
			Name = "Table",
			Size = Vector3.new(5, 3, 5),
			Position = Vector3.new(pos.X, FLOOR_Y + 1.5, pos.Y),
			Material = Enum.Material.SmoothPlastic,
			Color = Color3.fromRGB(200, 200, 205),
		}, props)
	end
	-- Bodega: estanterias metalicas y contenedor de basura
	for _, z in { -15, -45 } do
		part({
			Name = "Rack",
			Size = Vector3.new(16, 8, 2),
			Position = Vector3.new(-40, FLOOR_Y + 4, z),
			Material = Enum.Material.Metal,
			Color = Color3.fromRGB(80, 85, 90),
		}, props)
	end
	local dumpster = part({
		Name = "Dumpster",
		Size = Vector3.new(8, 5, 4),
		Position = Vector3.new(-70, FLOOR_Y + 2.5, -62),
		Material = Enum.Material.Metal,
		Color = Color3.fromRGB(40, 80, 45),
	}, props)
	tag(dumpster, Tags.TrashDropoff)
	-- Atrio: bancas
	for _, x in { 25, 55 } do
		part({
			Name = "Bench",
			Size = Vector3.new(6, 1.5, 2),
			Position = Vector3.new(x, FLOOR_Y + 0.75, -64),
			Material = Enum.Material.Wood,
			Color = Color3.fromRGB(110, 80, 50),
		}, props)
	end

	-- Atrio: tienda del mall (mostrador contra la pared sur, mirando al norte)
	local counterPos = Vector3.new(62, FLOOR_Y + 1.75, -73)
	local counter = part({
		Name = "ShopCounter",
		Size = Vector3.new(12, 3.5, 3),
		CFrame = CFrame.lookAt(counterPos, counterPos + Vector3.new(0, 0, 1)),
		Material = Enum.Material.Wood,
		Color = Color3.fromRGB(150, 110, 70),
	}, props)
	tag(counter, Tags.ShopCounter)
	local sign = part({
		Name = "ShopSign",
		Size = Vector3.new(14, 3, 0.5),
		CFrame = CFrame.lookAt(Vector3.new(62, FLOOR_Y + 9, -79.6), Vector3.new(62, FLOOR_Y + 9, 0)),
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(40, 120, 200),
		CanCollide = false,
	}, props)
	local signGui = Instance.new("SurfaceGui")
	signGui.Face = Enum.NormalId.Front
	signGui.LightInfluence = 0
	local signText = Instance.new("TextLabel")
	signText.Size = UDim2.fromScale(1, 1)
	signText.BackgroundTransparency = 1
	signText.Font = Enum.Font.GothamBlack
	signText.TextScaled = true
	signText.TextColor3 = Color3.new(1, 1, 1)
	signText.Text = "TIENDA"
	signText.Parent = signGui
	signGui.Parent = sign
	local signLight = Instance.new("PointLight")
	signLight.Range = 14
	signLight.Brightness = 0.8
	signLight.Color = Color3.fromRGB(120, 180, 255)
	signLight.Parent = sign

	-- Maquinas expendedoras (la cara Front mira hacia dentro de la sala)
	local function vending(position: Vector3, facing: Vector3, machineType: string, color: Color3)
		local machine = part({
			Name = "Vending_" .. machineType,
			Size = Vector3.new(4, 7, 3),
			CFrame = CFrame.lookAt(position, position + facing),
			Material = Enum.Material.SmoothPlastic,
			Color = color,
		}, props)
		machine:SetAttribute("MachineType", machineType)
		tag(machine, Tags.VendingMachine)
		local glow = Instance.new("PointLight")
		glow.Range = 10
		glow.Brightness = 0.7
		glow.Color = color
		glow.Parent = machine
	end
	vending(Vector3.new(-77, FLOOR_Y + 3.5, 45), Vector3.new(1, 0, 0), "Cheap", Color3.fromRGB(180, 40, 40))
	vending(Vector3.new(77, FLOOR_Y + 3.5, -30), Vector3.new(-1, 0, 0), "Premium", Color3.fromRGB(40, 60, 170))
end

function TestMapBuilder.BuildIfNeeded()
	if not Config.Debug.BuildTestMap then
		return
	end
	if Workspace:FindFirstChild("Mall") or #CollectionService:GetTagged(Tags.Zone) > 0 then
		return
	end

	local map = Instance.new("Model")
	map.Name = "Mall"

	-- Paredes exteriores
	local outer = HALF + 1
	wall(map, Vector3.new(0, WALL_H / 2, outer), Vector3.new(HALF * 2 + 4, WALL_H, 2))
	wall(map, Vector3.new(0, WALL_H / 2, -outer), Vector3.new(HALF * 2 + 4, WALL_H, 2))
	wall(map, Vector3.new(outer, WALL_H / 2, 0), Vector3.new(2, WALL_H, HALF * 2 + 4))
	wall(map, Vector3.new(-outer, WALL_H / 2, 0), Vector3.new(2, WALL_H, HALF * 2 + 4))

	-- Paredes interiores con puertas
	wallWithDoors(map, "Z")
	wallWithDoors(map, "X")

	-- Techo
	part({
		Name = "Ceiling",
		Size = Vector3.new(HALF * 2 + 4, 1, HALF * 2 + 4),
		Position = Vector3.new(0, WALL_H + 0.5, 0),
		Material = Enum.Material.Concrete,
		Color = Color3.fromRGB(60, 60, 62),
	}, map)

	for _, room in ROOMS do
		buildRoom(map, room)
	end
	buildProps(map)

	-- Punto de aparicion de jugadores en el Atrio
	local spawnPad = part({
		Name = "PlayerSpawn",
		Size = Vector3.new(8, 0.2, 8),
		Position = Vector3.new(40, FLOOR_Y + 0.1, -40),
		Material = Enum.Material.SmoothPlastic,
		Color = Color3.fromRGB(60, 120, 200),
		CanCollide = false,
	}, map)
	tag(spawnPad, Tags.PlayerSpawn)

	map.Parent = Workspace

	-- Las SpawnLocation de la plantilla (p. ej. la del Baseplate, en el centro)
	-- quedarian dentro de las paredes: el juego mueve a los jugadores al PlayerSpawn.
	print("[TestMapBuilder] Mall de prueba construido (desactivar en Config.Debug.BuildTestMap)")
end

return TestMapBuilder
