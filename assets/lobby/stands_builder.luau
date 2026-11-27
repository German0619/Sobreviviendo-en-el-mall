-- Puestos de la plaza del lobby: acabado realista (place del lobby, Workspace.Lobby.Stands).
--
-- El lobby esta modelado en Studio (no lo construye ningun script del juego). Este script se
-- pega en la barra de comandos de Studio (o se ejecuta por MCP) con el place del lobby
-- abierto, y despues se guarda el place. Se puede ejecutar varias veces: borra lo que puso
-- la vez anterior (carpeta Detail de cada kiosco) antes de volver a construir.
--
-- Conserva lo que usa el juego: el modelo del puesto con sus atributos (Stand, ObjectText,
-- ActionText), PromptPart y FloorGlow, y la estructura del kiosco (zocalo, marquesina,
-- postes, cartel delantero, caja de luz trasera, mostrador y laterales). Quita los bloques
-- de producto de antes y pone, segun el puesto:
--   TAQUILLA (Locker)    banco de taquillas metalicas con numeros, una abierta con
--                        consumibles; en la vitrina pilas, botiquines, bengalas y latas.
--   SKINS (Cosmetics)    baldas de vidrio con linternas de cada skin sobre peanas, muestrario
--                        de acabados, peana giratoria con una linterna iluminada y espejo.
--   MEJORAS (Upgrades)   kits de mejora (vida, estamina, bateria, velocidad) en cajas
--                        rotuladas, pantalla con barras de nivel y folletos.
-- Y en todos: frente del mostrador con paneles y moldura, logo, TPV con datafono e
-- impresora de tickets, cartel de pago con diamantes, taburete y alfombrilla del
-- dependiente, pantallas colgadas de la marquesina y focos redondos.
--
-- Copia de seguridad de los puestos originales: ServerStorage.StandsBackup_2026_11_27.

local ServerStorage = game:GetService("ServerStorage")

local stands = workspace:FindFirstChild("Lobby") and workspace.Lobby:FindFirstChild("Stands")
assert(stands, "Abre el place del lobby (falta Workspace.Lobby.Stands)")

if not ServerStorage:FindFirstChild("StandsBackup_2026_11_27") then
	local backup = stands:Clone()
	backup.Name = "StandsBackup_2026_11_27"
	backup.Parent = ServerStorage
end

local M = Enum.Material
local CYL, BALL = Enum.PartType.Cylinder, Enum.PartType.Ball
local UP = CFrame.Angles(0, 0, math.rad(90)) -- cilindro de pie
local BLACK = Color3.fromRGB(22, 22, 25)
local STEEL = Color3.fromRGB(178, 182, 188)
local BRASS = Color3.fromRGB(214, 172, 82)
local WHITE = Color3.fromRGB(245, 245, 240)

local STANDS = {
	Locker = { Title = "TAQUILLA", Screens = { "BATERÍAS · BOTIQUINES", "BENGALAS · PETARDOS" } },
	Cosmetics = { Title = "SKINS", Screens = { "LINTERNAS", "ARMAS" } },
	Upgrades = { Title = "MEJORAS", Screens = { "VIDA · ESTAMINA", "BATERÍA · VELOCIDAD" } },
}

-- Colores aproximados de las skins (para el muestrario y las linternas del puesto SKINS)
local SKIN_COLORS = {
	{ "Camo", Color3.fromRGB(90, 105, 60) },
	{ "Crimson", Color3.fromRGB(170, 20, 35) },
	{ "Diamond", Color3.fromRGB(170, 230, 245) },
	{ "Galaxy", Color3.fromRGB(70, 40, 140) },
	{ "Gold", Color3.fromRGB(230, 185, 70) },
	{ "Ice", Color3.fromRGB(190, 230, 255) },
	{ "Inferno", Color3.fromRGB(240, 90, 20) },
	{ "Luna", Color3.fromRGB(220, 220, 240) },
	{ "Neon", Color3.fromRGB(60, 255, 140) },
	{ "Phoenix", Color3.fromRGB(255, 120, 40) },
	{ "Plasma", Color3.fromRGB(150, 70, 255) },
	{ "Prism", Color3.fromRGB(255, 120, 200) },
	{ "Rust", Color3.fromRGB(150, 80, 40) },
	{ "Storm", Color3.fromRGB(70, 90, 120) },
	{ "Toxic", Color3.fromRGB(150, 220, 30) },
}

local UPGRADES = {
	{ "VIDA", Color3.fromRGB(220, 50, 60), "♥" },
	{ "ESTAMINA", Color3.fromRGB(60, 190, 90), "💪" },
	{ "BATERÍA", Color3.fromRGB(245, 200, 40), "🔋" },
	{ "VELOCIDAD", Color3.fromRGB(60, 140, 240), "💨" },
}

-- (Marco local K sin girar: el frente del kiosco es +Z, asi que los carteles y pantallas
-- que miran al cliente van en la cara Back de cada pieza.)
local function build(stand: Model)
	local id = stand:GetAttribute("Stand")
	local spec = STANDS[id]
	local kiosk = stand:FindFirstChild("Kiosk")
	if not spec or not kiosk then
		return
	end
	local cf0 = kiosk:GetBoundingBox()
	local K = CFrame.new(cf0.Position.X, 0, cf0.Position.Z) -- frente del kiosco = +Z
	local accent = (kiosk:FindFirstChild("CanopyEdge") :: BasePart).Color

	-- Limpieza: lo de la vez anterior y los bloques de producto originales
	local old = kiosk:FindFirstChild("Detail")
	if old then
		old:Destroy()
	end
	for _, p in kiosk:GetChildren() do
		if p.Name == "Product" or p.Name == "Display" or p.Name == "Shelf" or p.Name == "ShelfLED" then
			p:Destroy()
		end
	end
	local detail = Instance.new("Folder")
	detail.Name = "Detail"

	local function part(name: string, size: Vector3, cf: CFrame, material, color: Color3, props): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.CanCollide = false
		p.CanTouch = false
		p.CanQuery = false
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Size = size
		p.CFrame = K * cf
		p.Material = material
		p.Color = color
		for k, v in props or {} do
			(p :: any)[k] = v
		end
		p.Parent = detail
		return p
	end
	local function at(x: number, y: number, z: number): CFrame
		return CFrame.new(x, y, z)
	end
	local function text(p: BasePart, str: string, color: Color3, font: Enum.Font, face: Enum.NormalId?, lit: boolean?, bg: Color3?)
		local gui = Instance.new("SurfaceGui")
		gui.Face = face or Enum.NormalId.Back
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 50
		gui.LightInfluence = if lit then 0 else 1
		gui.Brightness = if lit then 1.6 else 1
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = if bg then 0 else 1
		label.BackgroundColor3 = bg or Color3.new()
		label.BorderSizePixel = 0
		label.Font = font
		label.TextScaled = true
		label.TextColor3 = color
		label.Text = str
		local pad = Instance.new("UIPadding")
		pad.PaddingTop = UDim.new(0.1, 0)
		pad.PaddingBottom = UDim.new(0.1, 0)
		pad.PaddingLeft = UDim.new(0.05, 0)
		pad.PaddingRight = UDim.new(0.05, 0)
		pad.Parent = label
		label.Parent = gui
		gui.Parent = p
		return gui
	end
	local function screen(p: BasePart, a: Color3, b: Color3, str: string?)
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Back
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 40
		gui.LightInfluence = 0
		gui.Brightness = 1.3
		local f = Instance.new("Frame")
		f.Size = UDim2.fromScale(1, 1)
		f.BorderSizePixel = 0
		f.BackgroundColor3 = Color3.new(1, 1, 1)
		local g = Instance.new("UIGradient")
		g.Color = ColorSequence.new(a, b)
		g.Rotation = 90
		g.Parent = f
		if str then
			local l = Instance.new("TextLabel")
			l.Size = UDim2.fromScale(0.9, 0.7)
			l.Position = UDim2.fromScale(0.05, 0.15)
			l.BackgroundTransparency = 1
			l.Font = Enum.Font.GothamBlack
			l.TextScaled = true
			l.TextColor3 = Color3.new(1, 1, 1)
			l.Text = str
			l.Parent = f
		end
		f.Parent = gui
		gui.Parent = p
		return gui
	end

	-- Mostrador: frente con tres paneles enmarcados, moldura de laton y placa con el logo
	local counter = kiosk:FindFirstChild("Counter") :: BasePart?
	if counter then
		counter.Material = M.Wood
		counter.Color = Color3.fromRGB(70, 44, 32)
	end
	for _, sx in { -4.3, 0, 4.3 } do
		for _, bar in {
			{ Vector3.new(3.9, 0.12, 0.08), at(sx, 2.55, 4.03) },
			{ Vector3.new(3.9, 0.12, 0.08), at(sx, 1.0, 4.03) },
			{ Vector3.new(0.12, 1.55, 0.08), at(sx - 1.95, 1.78, 4.03) },
			{ Vector3.new(0.12, 1.55, 0.08), at(sx + 1.95, 1.78, 4.03) },
		} do
			part("PanelMoulding", bar[1], bar[2], M.Wood, Color3.fromRGB(95, 62, 44))
		end
	end
	part("BrassRail", Vector3.new(13.1, 0.1, 0.1), at(0, 2.92, 4.04), M.Metal, BRASS, { Reflectance = 0.3 })
	local logo = part("CounterLogo", Vector3.new(3.4, 1.0, 0.06), at(0, 1.78, 4.09), M.SmoothPlastic, BLACK)
	text(logo, spec.Title, accent, Enum.Font.GothamBlack, Enum.NormalId.Back, true)
	for _, sx in { -1.82, 1.82 } do
		part("LogoBolt", Vector3.new(0.1, 0.1, 0.05), at(sx, 1.78, 4.12), M.Metal, BRASS)
	end
	-- Laterales: zocalo de acero y moldura
	for _, sx in { -7.4, 7.4 } do
		part("SideKick", Vector3.new(2.25, 0.35, 5.55), at(sx, 0.52, 0.6), M.Metal, STEEL)
		part("SideBrass", Vector3.new(2.25, 0.08, 5.55), at(sx, 3.85, 0.6), M.Metal, BRASS, { Reflectance = 0.3 })
	end

	-- Interior: alfombrilla, taburete del dependiente, papelera y balda bajo el mostrador
	part("StaffMat", Vector3.new(10, 0.05, 3.6), at(0, 0.375, -1.3), M.Rubber, Color3.fromRGB(35, 35, 38))
	part("StoolSeat", Vector3.new(0.3, 1.3, 1.3), at(-2.2, 2.75, -1.6) * UP, M.Leather, BLACK, { Shape = CYL })
	part("StoolPost", Vector3.new(2.4, 0.2, 0.2), at(-2.2, 1.55, -1.6) * UP, M.Metal, STEEL, { Shape = CYL })
	part("StoolBase", Vector3.new(0.1, 1.2, 1.2), at(-2.2, 0.42, -1.6) * UP, M.Metal, STEEL, { Shape = CYL })
	part("StoolRing", Vector3.new(0.08, 1.0, 1.0), at(-2.2, 1.3, -1.6) * UP, M.Metal, STEEL, { Shape = CYL })
	part("Bin", Vector3.new(1.4, 1.0, 1.0), at(5.6, 1.05, -2.4) * UP, M.Metal, STEEL, { Shape = CYL })
	part("UnderShelf", Vector3.new(12.4, 0.12, 1.2), at(0, 1.6, 1.4), M.Wood, Color3.fromRGB(60, 40, 30))
	for k = 0, 3 do
		part("StockBox", Vector3.new(1.6, 0.9, 1.0), at(-4.5 + k * 2.6, 2.13, 1.4) * CFrame.Angles(0, math.rad((k * 13) % 9 - 4), 0), M.Cardboard, Color3.fromRGB(185, 145, 95))
	end

	-- TPV en el lateral derecho: tablet en su peana, datafono, impresora de tickets
	part("PosStand", Vector3.new(0.4, 0.8, 0.4), at(7.4, 4.53, 0.2), M.Metal, STEEL)
	local tablet = part("PosTablet", Vector3.new(1.7, 1.15, 0.08), at(7.4, 5.2, 0.35) * CFrame.Angles(math.rad(-15), 0, 0), M.SmoothPlastic, BLACK)
	screen(tablet, accent, Color3.fromRGB(20, 20, 30), "💎")
	local reader = part("CardReader", Vector3.new(0.5, 0.15, 0.85), at(7.0, 4.22, 2.4) * CFrame.Angles(math.rad(-15), 0, 0), M.SmoothPlastic, BLACK)
	screen(part("ReaderScreen", Vector3.new(0.36, 0.3, 0.02), at(7.0, 4.32, 2.15) * CFrame.Angles(math.rad(-105), 0, 0), M.SmoothPlastic, BLACK), Color3.fromRGB(60, 150, 230), Color3.fromRGB(20, 60, 110))
	reader.Reflectance = 0.1
	part("ReceiptPrinter", Vector3.new(0.9, 0.6, 0.9), at(7.6, 4.43, -1.4), M.SmoothPlastic, Color3.fromRGB(235, 235, 232))
	part("Receipt", Vector3.new(0.6, 0.02, 0.5), at(7.6, 4.74, -0.85) * CFrame.Angles(math.rad(25), 0, 0), M.SmoothPlastic, WHITE)
	-- Cartel de pago con diamantes en el mostrador
	part("SignHolder", Vector3.new(1.8, 0.12, 0.5), at(-4.6, 4.2, 3.4), M.SmoothPlastic, Color3.fromRGB(230, 236, 240), { Transparency = 0.4 })
	local paySign = part("PaySign", Vector3.new(1.7, 1.1, 0.04), at(-4.6, 4.8, 3.4) * CFrame.Angles(math.rad(-8), 0, 0), M.SmoothPlastic, WHITE)
	text(paySign, "PAGO CON\n💎 DIAMANTES", BLACK, Enum.Font.GothamBold, Enum.NormalId.Back, false)

	-- Marquesina: focos redondos y dos pantallas colgadas con lo que se vende
	for _, dl in kiosk:GetChildren() do
		if dl.Name == "Downlight" and dl:IsA("BasePart") then
			dl.Transparency = 1
		end
	end
	for _, x in { -6, -2, 2, 6 } do
		for _, z in { -2.2, 2.4 } do
			part("CanRim", Vector3.new(0.08, 1.0, 1.0), at(x, 11.5, z) * UP, M.Metal, STEEL, { Shape = CYL })
			part("CanLens", Vector3.new(0.06, 0.7, 0.7), at(x, 11.48, z) * UP, M.Neon, Color3.fromRGB(255, 238, 210), { Shape = CYL, CastShadow = false })
		end
	end
	for i, sx in { -5.2, 5.2 } do
		for _, cx in { -1.2, 1.2 } do
			part("ScreenCable", Vector3.new(0.04, 0.9, 0.04), at(sx + cx, 11.05, 5.0), M.Metal, STEEL)
		end
		local s = part("MenuScreen", Vector3.new(3.4, 1.3, 0.12), at(sx, 9.95, 5.0), M.SmoothPlastic, BLACK)
		screen(s, accent:Lerp(Color3.new(0, 0, 0), 0.25), Color3.fromRGB(15, 15, 22), spec.Screens[i])
	end

	-- Producto segun el puesto -------------------------------------------------------------
	-- Vitrina del mostrador: interior x ±6.2, suelo y 2.97, z 1.9..3.9
	part("CaseVelvet", Vector3.new(12.6, 0.04, 2.0), at(0, 2.97, 2.9), M.Fabric, Color3.fromRGB(26, 26, 34))
	local backFace = -4.18 -- cara delantera del mueble del fondo

	if id == "Locker" then
		-- Banco de taquillas metalicas (2 filas x 7) bajo la caja de luz
		local cabinet = kiosk:FindFirstChild("Cabinet") :: BasePart?
		if cabinet then
			cabinet.Material = M.Metal
			cabinet.Color = Color3.fromRGB(70, 78, 90)
		end
		local cols, w = 7, 2.1
		for row = 0, 1 do
			for c = 0, cols - 1 do
				local x = -((cols - 1) / 2) * w + c * w
				local y = 1.5 + row * 2.05
				local n = row * cols + c + 1
				if n == 10 then
					-- Taquilla abierta: puerta girada y consumibles dentro
					part("LockerInside", Vector3.new(w - 0.2, 1.85, 0.05), at(x, y, backFace + 0.03), M.Metal, Color3.fromRGB(40, 44, 50))
					-- (bisagra a la izquierda: la puerta gira hacia fuera, +Z)
					part("LockerDoor", Vector3.new(w - 0.15, 1.9, 0.08), at(x - w / 2 + 0.05, y, backFace + 0.08) * CFrame.Angles(0, math.rad(-80), 0) * CFrame.new((w - 0.15) / 2, 0, 0), M.Metal, Color3.fromRGB(120, 135, 155))
					part("KitBox", Vector3.new(0.9, 0.6, 0.6), at(x - 0.3, y - 0.6, backFace + 0.35), M.SmoothPlastic, WHITE)
					part("Can", Vector3.new(0.6, 0.3, 0.3), at(x + 0.5, y - 0.6, backFace + 0.35) * UP, M.Metal, Color3.fromRGB(40, 180, 90), { Shape = CYL })
				else
					local door = part("LockerDoor", Vector3.new(w - 0.15, 1.9, 0.08), at(x, y, backFace + 0.04), M.Metal, Color3.fromRGB(120, 135, 155))
					door.Reflectance = 0.05
					for v = 0, 3 do
						part("LockerVent", Vector3.new(0.9, 0.06, 0.03), at(x, y + 0.65 - v * 0.14, backFace + 0.09), M.Metal, Color3.fromRGB(45, 50, 58))
					end
					part("LockerHandle", Vector3.new(0.1, 0.5, 0.1), at(x + w / 2 - 0.4, y - 0.1, backFace + 0.12), M.Metal, STEEL)
					local plate = part("LockerNumber", Vector3.new(0.5, 0.3, 0.02), at(x, y - 0.45, backFace + 0.09), M.SmoothPlastic, BRASS)
					text(plate, tostring(n), BLACK, Enum.Font.GothamBold, Enum.NormalId.Back, false)
				end
			end
		end
		-- Vitrina: pilas, botiquines, bengalas y latas
		for k = 0, 3 do
			part("Battery", Vector3.new(0.9, 0.3, 0.3), at(-5.6 + k * 0.4, 3.15, 2.9) * CFrame.Angles(0, math.rad(90), 0), M.Metal, if k % 2 == 0 then Color3.fromRGB(30, 30, 34) else Color3.fromRGB(230, 130, 30), { Shape = CYL })
		end
		for k = 0, 2 do
			local kit = part("MedKit", Vector3.new(1.1, 0.6, 0.8), at(-2.6 + k * 1.3, 3.27, 2.9), M.SmoothPlastic, WHITE)
			text(kit, "✚", Color3.fromRGB(210, 30, 40), Enum.Font.GothamBlack, Enum.NormalId.Back, false)
		end
		for k = 0, 3 do
			part("Flare", Vector3.new(1.3, 0.2, 0.2), at(1.8 + k * 0.35, 3.1, 2.9) * CFrame.Angles(0, math.rad(80), 0), M.SmoothPlastic, Color3.fromRGB(220, 30, 30), { Shape = CYL })
		end
		for k = 0, 2 do
			part("EnergyCan", Vector3.new(0.75, 0.38, 0.38), at(4.4 + k * 0.6, 3.36, 2.9) * UP, M.Metal, Color3.fromRGB(30, 30, 34), { Shape = CYL, Reflectance = 0.2 })
			part("CanBand", Vector3.new(0.2, 0.39, 0.39), at(4.4 + k * 0.6, 3.4, 2.9) * UP, M.SmoothPlastic, Color3.fromRGB(80, 230, 120), { Shape = CYL })
		end
		-- Lateral izquierdo: cesta con linternas
		part("Basket", Vector3.new(1.8, 0.7, 1.4), at(-7.4, 4.5, 0.6), M.SmoothPlastic, Color3.fromRGB(200, 40, 40))
		for k = 0, 2 do
			part("Flashlight", Vector3.new(1.2, 0.32, 0.32), at(-7.4, 4.95, 0.2 + k * 0.4) * CFrame.Angles(0, 0, math.rad(15)), M.SmoothPlastic, if k == 1 then Color3.fromRGB(250, 200, 30) else BLACK, { Shape = CYL })
		end
	elseif id == "Cosmetics" then
		-- Mueble del fondo lacado en negro con dos baldas de vidrio iluminadas
		local cabinet = kiosk:FindFirstChild("Cabinet") :: BasePart?
		if cabinet then
			cabinet.Material = M.SmoothPlastic
			cabinet.Color = Color3.fromRGB(28, 26, 32)
		end
		for r, y in { 1.9, 3.7 } do
			part("GlassShelf", Vector3.new(15, 0.08, 1.2), at(0, y, backFace + 0.65), M.Glass, Color3.fromRGB(220, 235, 240), { Transparency = 0.5 })
			part("ShelfLED", Vector3.new(14.8, 0.04, 0.05), at(0, y + 0.02, backFace + 1.24), M.Neon, Color3.fromRGB(255, 240, 225), { CastShadow = false })
			for k = 0, 6 do
				local skin = SKIN_COLORS[(r - 1) * 7 + k + 1]
				local x = -6.3 + k * 2.1
				part("Riser", Vector3.new(1.0, 0.25, 0.7), at(x, y + 0.17, backFace + 0.6), M.SmoothPlastic, Color3.fromRGB(230, 236, 240), { Transparency = 0.3 })
				local body = at(x, y + 0.5, backFace + 0.6) * CFrame.Angles(0, 0, math.rad(8))
				part("SkinFlashlight", Vector3.new(1.3, 0.34, 0.34), body, M.SmoothPlastic, skin[2], { Shape = CYL, Reflectance = 0.25 })
				part("SkinHead", Vector3.new(0.38, 0.5, 0.5), body * CFrame.new(-0.75, 0, 0), M.SmoothPlastic, skin[2]:Lerp(BLACK, 0.3), { Shape = CYL, Reflectance = 0.25 })
				local tagPart = part("SkinTag", Vector3.new(1.0, 0.28, 0.03), at(x, y - 0.12, backFace + 1.27), M.SmoothPlastic, WHITE)
				text(tagPart, skin[1], BLACK, Enum.Font.GothamBold, Enum.NormalId.Back, false)
			end
		end
		-- Vitrina: muestrario de acabados (fichas de color)
		for k = 1, 15 do
			local skin = SKIN_COLORS[k]
			local x = -6.0 + ((k - 1) % 8) * 1.7
			local z = 2.5 + ((k - 1) // 8) * 0.8
			part("Swatch", Vector3.new(1.2, 0.05, 0.6), at(x, 3.02, z) * CFrame.Angles(math.rad(-6), 0, 0), M.SmoothPlastic, skin[2], { Reflectance = 0.2 })
		end
		-- Lateral izquierdo: peana giratoria con una linterna iluminada y espejo
		part("Turntable", Vector3.new(0.2, 1.8, 1.8), at(-7.4, 4.23, 0.6) * UP, M.SmoothPlastic, BLACK, { Shape = CYL })
		local hero = at(-7.4, 5.1, 0.6) * CFrame.Angles(0, math.rad(30), math.rad(20))
		part("HeroFlashlight", Vector3.new(1.6, 0.42, 0.42), hero, M.SmoothPlastic, Color3.fromRGB(150, 70, 255), { Shape = CYL, Reflectance = 0.3 })
		local lens = part("HeroLens", Vector3.new(0.05, 0.5, 0.5), hero * CFrame.new(-0.82, 0, 0), M.Neon, Color3.fromRGB(230, 210, 255), { Shape = CYL })
		local glow = Instance.new("PointLight")
		glow.Range = 6
		glow.Brightness = 0.8
		glow.Color = Color3.fromRGB(190, 140, 255)
		glow.Parent = lens
		part("MirrorFrame", Vector3.new(0.12, 2.6, 1.5), at(-8.35, 5.4, -1.2), M.Metal, BRASS)
		part("Mirror", Vector3.new(0.06, 2.4, 1.3), at(-8.27, 5.4, -1.2), M.SmoothPlastic, Color3.fromRGB(170, 182, 190), { Reflectance = 0.35 })
	elseif id == "Upgrades" then
		-- Mueble del fondo: baldas con los kits de mejora rotulados
		for r, y in { 1.85, 3.6 } do
			part("KitShelf", Vector3.new(15, 0.12, 1.2), at(0, y, backFace + 0.65), M.Wood, Color3.fromRGB(60, 40, 30))
			part("ShelfLED", Vector3.new(14.8, 0.04, 0.05), at(0, y - 0.07, backFace + 1.24), M.Neon, Color3.fromRGB(255, 236, 200), { CastShadow = false })
			for k = 0, 7 do
				local up = UPGRADES[(k + r) % #UPGRADES + 1]
				local box = part("UpgradeKit", Vector3.new(1.4, 1.3, 0.9), at(-6.3 + k * 1.8, y + 0.71, backFace + 0.6), M.SmoothPlastic, up[2]:Lerp(BLACK, 0.15))
				text(box, up[3] .. "\n" .. up[1], Color3.new(1, 1, 1), Enum.Font.GothamBlack, Enum.NormalId.Back, false)
			end
		end
		-- Vitrina: insignias (una por mejora) con su nivel
		for k, up in UPGRADES do
			local x = -5.4 + (k - 1) * 3.6
			part("BadgeStand", Vector3.new(1.4, 0.2, 0.8), at(x, 3.07, 2.9), M.SmoothPlastic, Color3.fromRGB(230, 236, 240), { Transparency = 0.3 })
			part("Badge", Vector3.new(0.12, 0.75, 0.75), at(x, 3.55, 2.9) * CFrame.Angles(0, math.rad(90), 0), M.Metal, up[2], { Shape = CYL, Reflectance = 0.3 })
			part("BadgeRim", Vector3.new(0.1, 0.85, 0.85), at(x, 3.55, 2.86) * CFrame.Angles(0, math.rad(90), 0), M.Metal, BRASS, { Shape = CYL, Reflectance = 0.3 })
		end
		-- Lateral izquierdo: pantalla con las barras de nivel y folletos
		local stats = part("StatsScreen", Vector3.new(1.9, 1.4, 0.08), at(-7.4, 5.1, 0.6) * CFrame.Angles(math.rad(-12), 0, 0), M.SmoothPlastic, BLACK)
		do
			local gui = Instance.new("SurfaceGui")
			gui.Face = Enum.NormalId.Back
			gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			gui.PixelsPerStud = 60
			gui.LightInfluence = 0
			gui.Brightness = 1.3
			local bg = Instance.new("Frame")
			bg.Size = UDim2.fromScale(1, 1)
			bg.BackgroundColor3 = Color3.fromRGB(14, 16, 24)
			bg.BorderSizePixel = 0
			bg.Parent = gui
			for k, up in UPGRADES do
				local bar = Instance.new("Frame")
				bar.Position = UDim2.fromScale(0.08, 0.1 + (k - 1) * 0.22)
				bar.Size = UDim2.fromScale(0.25 + k * 0.15, 0.14)
				bar.BackgroundColor3 = up[2]
				bar.BorderSizePixel = 0
				bar.Parent = bg
			end
			gui.Parent = stats
		end
		part("StatsStand", Vector3.new(0.3, 0.8, 0.3), at(-7.4, 4.5, 0.5), M.Metal, STEEL)
		for k = 0, 2 do
			part("Brochure", Vector3.new(0.7, 1.0, 0.04), at(-7.9 + k * 0.5, 4.65, 2.6) * CFrame.Angles(math.rad(-12), 0, 0), M.SmoothPlastic, UPGRADES[k + 1][2])
		end
		part("BrochureHolder", Vector3.new(1.7, 0.6, 0.5), at(-7.4, 4.4, 2.75), M.SmoothPlastic, Color3.fromRGB(230, 236, 240), { Transparency = 0.4 })
	end

	detail.Parent = kiosk
end

for _, stand in stands:GetChildren() do
	if stand:IsA("Model") then
		build(stand)
	end
end
print("[Stands] Puestos del lobby actualizados")
