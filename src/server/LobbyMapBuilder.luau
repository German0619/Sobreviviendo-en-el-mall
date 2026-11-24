-- LobbyMapBuilder: construye un lobby de prueba (la sala de descanso de los
-- conserjes) si el place del lobby no tiene uno propio.
-- Se salta si existe Workspace.Lobby. Desactivar: Config.Debug.BuildTestMap = false
--
-- Todo el lobby se maneja desde la interfaz (LobbyUI); el mapa es decoracion.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)

local LobbyMapBuilder = {}

local W, D, H = 70, 50, 14 -- ancho (X), fondo (Z) y alto de la sala

local function part(props, parent: Instance): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props do
		(p :: any)[k] = v
	end
	p.Parent = parent
	return p
end

local function sign(parent: Instance, cframe: CFrame, size: Vector3, text: string, color: Color3)
	local board = part({
		Name = "Sign",
		Size = size,
		CFrame = cframe,
		Material = Enum.Material.SmoothPlastic,
		Color = Color3.fromRGB(20, 22, 26),
		CanCollide = false,
	}, parent)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.LightInfluence = 0
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextWrapped = true
	label.TextColor3 = color
	label.Text = text
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0.05, 0)
	padding.PaddingRight = UDim.new(0.05, 0)
	padding.PaddingTop = UDim.new(0.08, 0)
	padding.PaddingBottom = UDim.new(0.08, 0)
	padding.Parent = label
	label.Parent = gui
	gui.Parent = board
end

local function setupLighting()
	-- Noche fuera, pero la sala esta iluminada: aqui no hay peligro.
	Lighting.ClockTime = 0
	Lighting.Brightness = 1
	Lighting.Ambient = Color3.fromRGB(55, 55, 65)
	Lighting.OutdoorAmbient = Color3.fromRGB(40, 40, 50)
	Lighting.EnvironmentDiffuseScale = 0.3
	Lighting.EnvironmentSpecularScale = 0.3
end

function LobbyMapBuilder.BuildIfNeeded()
	setupLighting()
	if not Config.Debug.BuildTestMap or Workspace:FindFirstChild("Lobby") then
		return
	end

	local map = Instance.new("Model")
	map.Name = "Lobby"

	-- Suelo, techo y paredes
	part({
		Name = "Floor",
		Size = Vector3.new(W, 1, D),
		Position = Vector3.new(0, -0.5, 0),
		Material = Enum.Material.Slate,
		Color = Color3.fromRGB(95, 92, 88),
	}, map)
	part({
		Name = "Ceiling",
		Size = Vector3.new(W, 1, D),
		Position = Vector3.new(0, H + 0.5, 0),
		Material = Enum.Material.Concrete,
		Color = Color3.fromRGB(70, 70, 72),
	}, map)
	local wallColor = Color3.fromRGB(160, 150, 130)
	for _, wall in {
		{ Vector3.new(0, H / 2, D / 2 + 0.5), Vector3.new(W + 2, H, 1) },
		{ Vector3.new(0, H / 2, -D / 2 - 0.5), Vector3.new(W + 2, H, 1) },
		{ Vector3.new(W / 2 + 0.5, H / 2, 0), Vector3.new(1, H, D) },
		{ Vector3.new(-W / 2 - 0.5, H / 2, 0), Vector3.new(1, H, D) },
	} do
		part({
			Name = "Wall",
			Size = wall[2],
			Position = wall[1],
			Material = Enum.Material.Plaster,
			Color = wallColor,
		}, map)
	end

	-- Lamparas
	for _, x in { -20, 0, 20 } do
		for _, z in { -12, 12 } do
			local lamp = part({
				Name = "Lamp",
				Size = Vector3.new(6, 0.3, 1.5),
				Position = Vector3.new(x, H - 0.2, z),
				Material = Enum.Material.Neon,
				Color = Color3.fromRGB(255, 240, 215),
				CanCollide = false,
			}, map)
			local light = Instance.new("PointLight")
			light.Range = 26
			light.Brightness = 1.3
			light.Color = Color3.fromRGB(255, 235, 205)
			light.Parent = lamp
		end
	end

	-- Aparicion
	local spawnLocation = Instance.new("SpawnLocation")
	spawnLocation.Name = "LobbySpawn"
	spawnLocation.Anchored = true
	spawnLocation.Size = Vector3.new(8, 0.2, 8)
	spawnLocation.Position = Vector3.new(0, 0.1, 6)
	spawnLocation.Material = Enum.Material.SmoothPlastic
	spawnLocation.Color = Color3.fromRGB(60, 120, 200)
	spawnLocation.Duration = 0
	spawnLocation.Neutral = true
	spawnLocation.CanCollide = false
	spawnLocation.Parent = map

	-- Casilleros (pared oeste)
	for i = 0, 5 do
		part({
			Name = "Locker",
			Size = Vector3.new(3, 7.5, 3.6),
			Position = Vector3.new(-W / 2 + 1.8, 3.75, -12 + i * 3.7),
			Material = Enum.Material.Metal,
			Color = Color3.fromRGB(70, 90, 110),
		}, map)
	end
	-- Mesa y bancas
	part({
		Name = "Table",
		Size = Vector3.new(12, 0.6, 4),
		Position = Vector3.new(14, 3, -6),
		Material = Enum.Material.Wood,
		Color = Color3.fromRGB(130, 95, 60),
	}, map)
	for _, z in { -9, -3 } do
		part({
			Name = "Bench",
			Size = Vector3.new(12, 1.6, 1.6),
			Position = Vector3.new(14, 0.8, z),
			Material = Enum.Material.Wood,
			Color = Color3.fromRGB(110, 80, 50),
		}, map)
	end
	-- Maquina de cafe y reloj de fichar (decoracion)
	part({
		Name = "CoffeeMachine",
		Size = Vector3.new(3, 6, 2.5),
		Position = Vector3.new(W / 2 - 2, 3, 12),
		Material = Enum.Material.SmoothPlastic,
		Color = Color3.fromRGB(150, 40, 40),
	}, map)
	part({
		Name = "TimeClock",
		Size = Vector3.new(2, 2.5, 1),
		Position = Vector3.new(-6, 5, -D / 2 + 0.5),
		Material = Enum.Material.Metal,
		Color = Color3.fromRGB(180, 180, 175),
	}, map)

	-- Carteles (pared norte, mirando hacia dentro)
	local north = -D / 2 + 0.1
	sign(
		map,
		CFrame.lookAt(Vector3.new(10, 8, north), Vector3.new(10, 8, 0)),
		Vector3.new(22, 6, 0.2),
		"TURNO DE NOCHE\nElige tu clase y crea una sala (hasta 5)",
		Color3.fromRGB(255, 200, 80)
	)
	sign(
		map,
		CFrame.lookAt(Vector3.new(-18, 8, north), Vector3.new(-18, 8, 0)),
		Vector3.new(10, 4, 0.2),
		"MALL  →",
		Color3.fromRGB(230, 80, 80)
	)

	map.Parent = Workspace
	print("[LobbyMapBuilder] Lobby de prueba construido (desactivar en Config.Debug.BuildTestMap)")
end

return LobbyMapBuilder
