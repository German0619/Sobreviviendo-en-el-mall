--!strict
-- RouletteBuilder (lobby): construye una ruleta fisica de feria para la plaza.
--
--   * Rueda vertical con un sector por premio (color, nombre y %), separadores
--     dorados, clavijas en el borde y una lengueta roja arriba que marca el premio.
--   * Aro dorado fijo con bombillas, marquesina con el titulo, patas de acero y
--     zocalo de granito.
--   * Consola delante con el boton [E] (girar, gasta diamantes) y su pantalla.
--   * Cartel de probabilidades a un lado con [F] (abre el panel del puesto).
--
-- Las piezas que giran van en la carpeta Rotor; cada una guarda su posicion respecto
-- al eje con la rueda en 0 grados (atributo RotorOffset). La rueda la mueve el cliente
-- (client/LobbyRoulettes) durante el giro y el servidor la deja en su angulo final.
--
-- Marco local de la rueda (atributo WheelFrame del modelo): origen en el eje,
-- X = derecha de quien la mira, Y = arriba, Z = hacia quien la mira.
-- Angulos en grados en el sentido de las agujas del reloj desde arriba.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Tags = require(Shared.Tags)

local RouletteBuilder = {}

export type Sector = {
	Key: string, -- clase o skin
	Text: string,
	Sub: string,
	Color: Color3,
	TextColor: Color3,
	Material: Enum.Material?,
}

local RC = Config.LobbyRoulettes
local GOLD = Color3.fromRGB(214, 172, 82)
local STEEL = Color3.fromRGB(120, 124, 132)
local DARK = Color3.fromRGB(18, 19, 30)
local BULB = Color3.fromRGB(255, 226, 160)
local POINTER = Color3.fromRGB(215, 30, 40)
local ROTOR_T = 0.4 -- grosor de la rueda

----------------------------------------------------------------------
-- Utilidades
----------------------------------------------------------------------

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, props: { [string]: any }?): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CastShadow = true
	if props then
		for k, v in props do
			(p :: any)[k] = v
		end
	end
	p.Parent = parent
	return p
end

local function cylinder(parent: Instance, name: string, diameter: number, length: number, cf: CFrame, color: Color3, material: Enum.Material?, props: { [string]: any }?): BasePart
	-- El eje del cilindro es su X: `cf` ya debe tener la X a lo largo del eje.
	local p = part(parent, name, Vector3.new(length, diameter, diameter), cf, color, material, props) :: Part
	p.Shape = Enum.PartType.Cylinder
	return p
end

-- Punto del plano de la rueda a `radius` y `angle` grados (horario desde arriba).
local function polar(angle: number, radius: number, z: number?): Vector3
	local a = math.rad(angle)
	return Vector3.new(math.sin(a) * radius, math.cos(a) * radius, z or 0)
end

-- Giro en el plano de la rueda: la Y local apunta hacia `angle`.
local function spin(angle: number): CFrame
	return CFrame.Angles(0, 0, -math.rad(angle))
end

-- Eje del cilindro (X) a lo largo de la Z de la rueda / de la Y del mundo.
local AXIS_Z = CFrame.Angles(0, math.pi / 2, 0)
local AXIS_Y = CFrame.Angles(0, 0, math.pi / 2)

local function wedge(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material): WedgePart
	local w = Instance.new("WedgePart")
	w.Name = name
	w.Anchored = true
	w.Size = size
	w.CFrame = cf
	w.Color = color
	w.Material = material
	w.TopSurface = Enum.SurfaceType.Smooth
	w.BottomSurface = Enum.SurfaceType.Smooth
	w.Parent = parent
	return w
end

-- Triangulo plano (a, b, c en coordenadas locales) con dos cunas.
local function triangle(parent: Instance, frame: CFrame, a: Vector3, b: Vector3, c: Vector3, thickness: number, color: Color3, material: Enum.Material)
	local ab, ac, bc = b - a, c - a, c - b
	local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
	if abd > acd and abd > bcd then
		c, a = a, c
	elseif acd > bcd and acd > abd then
		a, b = b, a
	end
	ab, ac, bc = b - a, c - a, c - b
	local right = ac:Cross(ab).Unit
	local up = bc:Cross(right).Unit
	local back = bc.Unit
	local height = math.abs(ab:Dot(up))
	wedge(parent, "Slice", Vector3.new(thickness, height, math.abs(ab:Dot(back))), frame * CFrame.fromMatrix((a + b) / 2, right, up, back), color, material)
	wedge(parent, "Slice", Vector3.new(thickness, height, math.abs(ac:Dot(back))), frame * CFrame.fromMatrix((a + c) / 2, -right, up, -back), color, material)
end

local function surfaceText(p: BasePart, face: Enum.NormalId, ppsd: number): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = ppsd
	gui.LightInfluence = 0
	gui.MaxDistance = 140
	gui.Parent = p
	return gui
end

local function text(parent: Instance, name: string, value: string, size: UDim2, pos: UDim2, color: Color3, font: Enum.Font?): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Size = size
	l.Position = pos
	l.Font = font or Enum.Font.GothamBlack
	l.TextScaled = true
	l.TextWrapped = true
	l.TextColor3 = color
	l.TextStrokeTransparency = 0.35
	l.Text = value
	l.Parent = parent
	return l
end

local function shade(c: Color3, k: number): Color3
	return Color3.new(math.clamp(c.R * k, 0, 1), math.clamp(c.G * k, 0, 1), math.clamp(c.B * k, 0, 1))
end

local function formatPercent(p: number): string
	local decimals = 2
	if p > 0 and p < 1 then
		decimals = math.max(2, -math.floor(math.log10(p)) + 1)
	end
	local s = string.format("%." .. decimals .. "f", p)
	s = string.gsub(s, "0+$", "")
	s = string.gsub(s, "%.$", "")
	return s .. "%"
end
RouletteBuilder.formatPercent = formatPercent

----------------------------------------------------------------------
-- Sectores de cada ruleta
----------------------------------------------------------------------

function RouletteBuilder.Sectors(kind: string): { Sector }
	local list: { Sector } = {}
	if kind == "Classes" then
		local odds = {}
		for _, entry in Config.getRouletteOdds(false) do
			odds[entry.Class] = entry.Percent
		end
		for i, className in Config.ClassOrder do
			local class = Config.Classes[className]
			local rarity = Config.Rarities[class.Rarity]
			-- Las vecinas de la misma rareza se alternan en tono para distinguirlas
			local color = if i % 2 == 0 then shade(rarity.Color, 0.78) else rarity.Color
			table.insert(list, {
				Key = className,
				Text = class.DisplayName,
				Sub = formatPercent(odds[className] or 0),
				Color = color,
				TextColor = Color3.new(1, 1, 1),
			})
		end
	else
		local def = RC.Wheels[kind]
		for _ = 1, (def and def.Repeat) or 1 do
			for _, skinId in Config.SkinOrder do
				local skin = Config.Skins[skinId]
				local body = skin.Body
				local material = body.Material
				if material ~= Enum.Material.Metal and material ~= Enum.Material.Foil and material ~= Enum.Material.Fabric then
					material = Enum.Material.SmoothPlastic
				end
				local textColor = if skin.Glow then skin.Glow.Color elseif skin.Accent then skin.Accent.Color else Color3.new(1, 1, 1)
				if skinId == "Gold" or skinId == "Camo" then
					textColor = Color3.new(1, 1, 1)
				end
				table.insert(list, {
					Key = skinId,
					Text = skin.DisplayName,
					Sub = Config.Rarities[skin.Rarity].DisplayName,
					Color = body.Color,
					TextColor = textColor,
					Material = material,
				})
			end
		end
	end
	return list
end

----------------------------------------------------------------------
-- Construccion
----------------------------------------------------------------------

local function buildRotor(model: Model, frame: CFrame, sectors: { Sector })
	local rotor = Instance.new("Folder")
	rotor.Name = "Rotor"
	local R = RC.Radius
	local n = #sectors
	local SA = 360 / n
	local SUB = math.max(1, math.ceil(36 / n)) -- triangulos por sector (borde casi redondo)

	for i, sector in sectors do
		local center = (i - 1) * SA
		local material = sector.Material or Enum.Material.SmoothPlastic
		for k = 0, SUB - 1 do
			local a0 = center - SA / 2 + SA * k / SUB
			local a1 = a0 + SA / SUB
			triangle(rotor, frame, Vector3.zero, polar(a0, R), polar(a1, R), ROTOR_T, sector.Color, material)
		end
		-- Banda interior mas oscura (le da profundidad, como las ruedas pintadas)
		for k = 0, SUB - 1 do
			local a0 = center - SA / 2 + SA * k / SUB
			local a1 = a0 + SA / SUB
			triangle(rotor, frame, polar(a0, R * 0.36, 0.02), polar(a0, R * 0.3, 0.02), polar(a1, R * 0.36, 0.02), ROTOR_T, shade(sector.Color, 0.6), material)
			triangle(rotor, frame, polar(a1, R * 0.36, 0.02), polar(a0, R * 0.3, 0.02), polar(a1, R * 0.3, 0.02), ROTOR_T, shade(sector.Color, 0.6), material)
		end

		-- Nombre y % del sector (se lee desde el centro hacia el borde)
		local rIn, rOut = R * 0.38, R - 0.55
		local rc = (rIn + rOut) / 2
		local dir = polar(center, 1)
		local height = 2 * rc * math.sin(math.rad(SA / 2)) * 0.86
		local labelPart = part(rotor, "Label", Vector3.new(rOut - rIn, height, 0.05),
			frame * CFrame.fromMatrix(dir * rc + Vector3.new(0, 0, ROTOR_T / 2 + 0.04), -dir, Vector3.new(-dir.Y, dir.X, 0)),
			Color3.new(1, 1, 1), Enum.Material.SmoothPlastic, { Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false })
		labelPart:SetAttribute("Sector", i)
		local gui = surfaceText(labelPart, Enum.NormalId.Front, 60)
		local nameLabel = text(gui, "Name", string.upper(sector.Text), UDim2.fromScale(0.97, 0.62), UDim2.fromScale(0.03, 0.04), sector.TextColor)
		nameLabel.TextXAlignment = Enum.TextXAlignment.Right
		local sub = text(gui, "Sub", sector.Sub, UDim2.fromScale(0.97, 0.3), UDim2.fromScale(0.03, 0.66), sector.TextColor, Enum.Font.GothamBold)
		sub.TextXAlignment = Enum.TextXAlignment.Right
		sub.TextTransparency = 0.1

		-- Separador dorado y clavija del borde (a la izquierda del sector)
		local b = center - SA / 2
		local bdir = polar(b, 1)
		part(rotor, "Divider", Vector3.new(0.12, R - 1.4, 0.1), frame * CFrame.new(bdir * ((R + 1.4) / 2) + Vector3.new(0, 0, ROTOR_T / 2 + 0.04)) * spin(b),
			GOLD, Enum.Material.Metal, { CanCollide = false, CanQuery = false, Reflectance = 0.15 })
		cylinder(rotor, "Peg", 0.24, 0.7, frame * CFrame.new(polar(b, R - 0.28, ROTOR_T / 2 + 0.35)) * AXIS_Z,
			Color3.fromRGB(225, 225, 232), Enum.Material.Metal, { CanCollide = false, CanQuery = false, Reflectance = 0.3 })
	end

	-- Buje dorado
	cylinder(rotor, "Hub", 2.4, 0.5, frame * CFrame.new(0, 0, ROTOR_T / 2 + 0.25) * AXIS_Z, GOLD, Enum.Material.Metal, { CanCollide = false, Reflectance = 0.2 })
	cylinder(rotor, "HubRing", 2.9, 0.3, frame * CFrame.new(0, 0, ROTOR_T / 2 + 0.12) * AXIS_Z, DARK, Enum.Material.SmoothPlastic, { CanCollide = false })

	for _, p in rotor:GetChildren() do
		if p:IsA("BasePart") then
			p.CanCollide = false
			p.CanTouch = false
			p:SetAttribute("RotorOffset", frame:ToObjectSpace(p.CFrame))
		end
	end
	rotor.Parent = model
end

local function buildFrame(model: Model, frame: CFrame, def: any)
	local R = RC.Radius
	local H = RC.HubHeight
	local accent: Color3 = def.Accent
	local static = Instance.new("Folder")
	static.Name = "Frame"

	-- Disco trasero, aro dorado y bombillas
	cylinder(static, "BackDisc", 2 * R + 1.6, 0.5, frame * CFrame.new(0, 0, -0.5) * AXIS_Z, Color3.fromRGB(24, 26, 44), Enum.Material.SmoothPlastic)
	local SEG = 48
	for i = 0, SEG - 1 do
		local a = i * 360 / SEG
		local r = R + 0.4
		part(static, "Rim", Vector3.new(2 * r * math.sin(math.pi / SEG) * 1.08, 0.75, 1.0), frame * CFrame.new(polar(a, r, 0.05)) * spin(a),
			GOLD, Enum.Material.Metal, { Reflectance = 0.2 })
	end
	local bulbs = Instance.new("Folder")
	bulbs.Name = "Bulbs"
	bulbs.Parent = static
	local BULBS = 24
	for i = 0, BULBS - 1 do
		local a = (i + 0.5) * 360 / BULBS
		local b = part(bulbs, "Bulb", Vector3.new(0.42, 0.42, 0.42), frame * CFrame.new(polar(a, R + 0.4, 0.6)), BULB, Enum.Material.Neon, {
			Shape = Enum.PartType.Ball,
			CanCollide = false,
			CastShadow = false,
		})
		b:SetAttribute("Index", i)
	end

	-- Tapa del buje con la luna (fija: la luna siempre derecha)
	local cap = part(static, "HubCap", Vector3.new(1.5, 1.5, 0.05), frame * CFrame.new(0, 0, ROTOR_T / 2 + 0.53) * CFrame.Angles(0, math.pi, 0),
		Color3.new(1, 1, 1), Enum.Material.SmoothPlastic, { Transparency = 1, CanCollide = false, CanQuery = false, CastShadow = false })
	text(surfaceText(cap, Enum.NormalId.Front, 60), "Moon", "🌙", UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), Color3.fromRGB(70, 50, 20), Enum.Font.GothamBlack).TextStrokeTransparency = 1

	-- Lengueta (puntero) arriba: soporte dorado y la lengueta roja que choca con las clavijas
	part(static, "PointerMount", Vector3.new(1.1, 0.9, 1.3), frame * CFrame.new(0, R + 1.05, 0.45), GOLD, Enum.Material.Metal, { Reflectance = 0.2 })
	local pivot = frame * CFrame.new(0, R + 0.7, ROTOR_T / 2 + 0.75)
	local flapper = part(static, "Flapper", Vector3.new(0.34, 1.7, 0.22), pivot * CFrame.new(0, -0.85, 0), POINTER, Enum.Material.SmoothPlastic, {
		CanCollide = false,
		Reflectance = 0.1,
	})
	flapper:SetAttribute("Pivot", pivot)
	flapper:SetAttribute("PivotOffset", pivot:ToObjectSpace(flapper.CFrame))

	-- Patas de acero en A, eje y zocalo
	local floorY = -H
	for _, side in { -1, 1 } do
		local foot = Vector3.new(side * 3.6, floorY + 1.1, -1.3)
		local top = Vector3.new(side * 0.5, 0.3, -1.3)
		local mid = (foot + top) / 2
		part(static, "Leg", Vector3.new(0.55, 0.55, (top - foot).Magnitude), frame * CFrame.lookAt(mid, top), STEEL, Enum.Material.Metal, {
			MaterialVariant = "LobbyBrushedSteel1",
		})
	end
	cylinder(static, "Axle", 1.0, 1.2, frame * CFrame.new(0, 0, -1.2) * AXIS_Z, STEEL, Enum.Material.Metal, { MaterialVariant = "LobbyBrushedSteel1" })
	part(static, "Plinth", Vector3.new(10, 1.1, 4.6), frame * CFrame.new(0, floorY + 0.55, -0.9), Color3.fromRGB(40, 38, 44), Enum.Material.Granite, {
		MaterialVariant = "LobbyGranite1",
	})
	part(static, "PlinthTrim", Vector3.new(10.2, 0.14, 4.8), frame * CFrame.new(0, floorY + 1.15, -0.9), GOLD, Enum.Material.Metal, { Reflectance = 0.2 })

	-- Marquesina con el titulo, bombillas y dos varillas que la sujetan
	local marqueeY = R + 2.75
	local marquee = part(static, "Marquee", Vector3.new(11.5, 2.1, 0.7), frame * CFrame.new(0, marqueeY, -0.4) * CFrame.Angles(0, math.pi, 0), DARK)
	local mg = surfaceText(marquee, Enum.NormalId.Front, 40)
	local title = text(mg, "Title", def.Title, UDim2.fromScale(0.92, 0.72), UDim2.fromScale(0.04, 0.14), accent)
	title.TextStrokeColor3 = shade(accent, 0.3)
	title.TextStrokeTransparency = 0
	part(static, "MarqueeTrim", Vector3.new(11.9, 2.5, 0.5), frame * CFrame.new(0, marqueeY, -0.55), GOLD, Enum.Material.Metal, { Reflectance = 0.2 })
	for i = 0, 13 do
		local x = -5.6 + i * (11.2 / 13)
		for _, y in { marqueeY + 1.15, marqueeY - 1.15 } do
			local b = part(bulbs, "Bulb", Vector3.new(0.3, 0.3, 0.3), frame * CFrame.new(x, y, -0.15), BULB, Enum.Material.Neon, {
				Shape = Enum.PartType.Ball,
				CanCollide = false,
				CastShadow = false,
			})
			b:SetAttribute("Index", 100 + i)
		end
	end
	for _, side in { -1, 1 } do
		part(static, "MarqueeRod", Vector3.new(0.25, marqueeY - 1.2, 0.25), frame * CFrame.new(side * 4.6, (marqueeY - 1.2) / 2 + 0.2, -0.8), STEEL, Enum.Material.Metal)
	end

	-- Luz: foco desde delante y un brillo del color de la ruleta
	local spotPart = part(static, "Spot", Vector3.new(0.6, 0.6, 0.6), frame * CFrame.lookAt(Vector3.new(0, R + 4.5, 7), Vector3.new(0, 0, 0)), DARK, Enum.Material.Metal, {
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
	})
	local spot = Instance.new("SpotLight")
	spot.Face = Enum.NormalId.Front
	spot.Angle = 70
	spot.Range = 20
	spot.Brightness = 1.4
	spot.Color = Color3.fromRGB(255, 236, 205)
	spot.Shadows = true
	spot.Parent = spotPart
	local glow = Instance.new("PointLight")
	glow.Name = "Glow"
	glow.Range = 14
	glow.Brightness = 0.6
	glow.Color = accent
	glow.Parent = part(static, "GlowPoint", Vector3.new(0.2, 0.2, 0.2), frame * CFrame.new(0, 0, 3), DARK, nil, {
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
	})

	-- Alfombra redonda con aro de laton delante de la rueda
	local rugCenter = Vector3.new(0, floorY + 0.03, RC.ConsoleDistance - 1)
	cylinder(static, "Rug", 11, 0.06, frame * CFrame.new(rugCenter) * AXIS_Y, shade(accent, 0.28), Enum.Material.Fabric, { CanCollide = false })
	cylinder(static, "RugRing", 11.6, 0.04, frame * CFrame.new(rugCenter - Vector3.new(0, 0.01, 0)) * AXIS_Y, GOLD, Enum.Material.Metal, { CanCollide = false })

	-- Ancla del cartel del resultado y del confeti
	local result = part(static, "ResultAnchor", Vector3.new(1, 1, 1), frame * CFrame.new(0, R + 5.2, 1), DARK, nil, {
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
	})
	local confetti = Instance.new("ParticleEmitter")
	confetti.Name = "Confetti"
	confetti.Enabled = false
	confetti.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	confetti.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 120)),
		ColorSequenceKeypoint.new(0.33, Color3.fromRGB(255, 215, 80)),
		ColorSequenceKeypoint.new(0.66, Color3.fromRGB(90, 200, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(170, 90, 255)),
	})
	confetti.Size = NumberSequence.new(0.35, 0.15)
	confetti.Lifetime = NumberRange.new(1.4, 2.2)
	confetti.Speed = NumberRange.new(10, 16)
	confetti.SpreadAngle = Vector2.new(60, 60)
	confetti.Acceleration = Vector3.new(0, -18, 0)
	confetti.Rotation = NumberRange.new(0, 360)
	confetti.RotSpeed = NumberRange.new(-200, 200)
	confetti.LightEmission = 0.4
	confetti.EmissionDirection = Enum.NormalId.Top
	confetti.Parent = result

	static.Parent = model
end

local function buildConsole(model: Model, frame: CFrame, kind: string, def: any)
	local H = RC.HubHeight
	local z = RC.ConsoleDistance
	local console = Instance.new("Model")
	console.Name = "Console"
	local floorY = -H
	local accent: Color3 = def.Accent

	part(console, "Pedestal", Vector3.new(2.8, 3.2, 1.8), frame * CFrame.new(0, floorY + 1.6, z), Color3.fromRGB(36, 34, 40), Enum.Material.Granite, {
		MaterialVariant = "LobbyGranite1",
	})
	part(console, "Top", Vector3.new(3.0, 0.2, 2.0), frame * CFrame.new(0, floorY + 3.3, z), GOLD, Enum.Material.Metal, { Reflectance = 0.2 })
	part(console, "Stripe", Vector3.new(2.82, 0.18, 1.82), frame * CFrame.new(0, floorY + 0.5, z), accent, Enum.Material.Neon, { CastShadow = false })

	-- Boton rojo grande (aqui sale el [E])
	cylinder(console, "ButtonRing", 1.5, 0.16, frame * CFrame.new(0, floorY + 3.48, z) * AXIS_Y, Color3.fromRGB(30, 30, 34), Enum.Material.Metal)
	local button = cylinder(console, "Button", 1.15, 0.32, frame * CFrame.new(0, floorY + 3.6, z) * AXIS_Y, Color3.fromRGB(225, 35, 45), Enum.Material.SmoothPlastic, {
		Reflectance = 0.15,
	})
	local buttonLight = Instance.new("PointLight")
	buttonLight.Range = 5
	buttonLight.Brightness = 0.8
	buttonLight.Color = Color3.fromRGB(255, 70, 70)
	buttonLight.Parent = button

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "SpinPrompt"
	prompt.ActionText = "Girar"
	prompt.ObjectText = def.Title
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 9
	prompt.RequiresLineOfSight = false
	prompt.Exclusivity = Enum.ProximityPromptExclusivity.AlwaysShow
	prompt.UIOffset = Vector2.new(0, 0)
	prompt:SetAttribute("Roulette", kind)
	prompt.Parent = button

	-- Pantalla del precio, en la cara de la consola que mira al jugador
	local screen = part(console, "Screen", Vector3.new(2.4, 1.5, 0.08), frame * CFrame.new(0, floorY + 2.25, z + 0.93) * CFrame.Angles(0, math.pi, 0),
		Color3.fromRGB(8, 10, 16), Enum.Material.Glass, { CanCollide = false, Reflectance = 0.1 })
	local sg = surfaceText(screen, Enum.NormalId.Front, 80)
	sg.Name = "ScreenGui"
	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.fromRGB(10, 12, 22)
	bg.BorderSizePixel = 0
	bg.Parent = sg
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new(shade(accent, 0.35), Color3.fromRGB(10, 12, 22))
	grad.Rotation = 90
	grad.Parent = bg
	text(bg, "Action", "GIRAR", UDim2.fromScale(0.9, 0.34), UDim2.fromScale(0.05, 0.08), Color3.new(1, 1, 1))
	text(bg, "Price", "", UDim2.fromScale(0.9, 0.3), UDim2.fromScale(0.05, 0.44), Color3.fromRGB(130, 225, 255))
	text(bg, "Hint", "", UDim2.fromScale(0.9, 0.16), UDim2.fromScale(0.05, 0.78), Color3.fromRGB(190, 192, 210), Enum.Font.GothamBold)

	console.Parent = model
end

local function buildOddsBoard(model: Model, frame: CFrame, kind: string, def: any, sectors: { Sector })
	local H = RC.HubHeight
	local R = RC.Radius
	local side: number = def.Side or 1
	local board = Instance.new("Model")
	board.Name = "OddsBoard"
	local accent: Color3 = def.Accent
	local floorY = -H
	-- Un poco girado hacia la plaza
	local base = frame * CFrame.new(side * (R + 3.4), floorY, 2.2) * CFrame.Angles(0, math.rad(-side * 22), 0)

	part(board, "Foot", Vector3.new(3.2, 0.4, 1.4), base * CFrame.new(0, 0.2, 0), Color3.fromRGB(36, 34, 40), Enum.Material.Granite, { MaterialVariant = "LobbyGranite1" })
	part(board, "Post", Vector3.new(0.4, 1.6, 0.4), base * CFrame.new(0, 1.2, 0), STEEL, Enum.Material.Metal)
	part(board, "Bezel", Vector3.new(4.2, 6.6, 0.35), base * CFrame.new(0, 5.2, 0), GOLD, Enum.Material.Metal, { Reflectance = 0.15 })
	local panel = part(board, "Board", Vector3.new(3.9, 6.3, 0.1), base * CFrame.new(0, 5.2, 0.2) * CFrame.Angles(0, math.pi, 0), Color3.fromRGB(10, 11, 20), Enum.Material.SmoothPlastic)
	local sg = surfaceText(panel, Enum.NormalId.Front, 60)
	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.fromRGB(12, 13, 24)
	bg.BorderSizePixel = 0
	bg.Parent = sg
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0.07, 0)
	pad.PaddingRight = UDim.new(0.07, 0)
	pad.PaddingTop = UDim.new(0.03, 0)
	pad.PaddingBottom = UDim.new(0.03, 0)
	pad.Parent = bg
	text(bg, "Title", "PROBABILIDADES", UDim2.fromScale(1, 0.07), UDim2.fromScale(0, 0), accent)

	local rows: { { left: string, right: string, color: Color3 } } = {}
	if kind == "Classes" then
		for _, s in sectors do
			local class = Config.Classes[s.Key]
			table.insert(rows, { left = s.Text, right = s.Sub, color = Config.Rarities[class.Rarity].Color })
		end
	else
		local bySkin, byRarity = Config.getSkinOdds()
		local rarities = {}
		for rarity in byRarity do
			table.insert(rarities, rarity)
		end
		table.sort(rarities, function(a, b)
			return Config.Rarities[a].Order < Config.Rarities[b].Order
		end)
		for _, rarity in rarities do
			table.insert(rows, { left = string.upper(Config.Rarities[rarity].DisplayName), right = formatPercent(byRarity[rarity]), color = Config.Rarities[rarity].Color })
			-- (las de una rareza, en una fila: cada una tiene la misma probabilidad)
			local names, each = {}, 0
			for _, skinId in Config.SkinOrder do
				if Config.Skins[skinId].Rarity == rarity then
					table.insert(names, Config.Skins[skinId].DisplayName)
					each = bySkin[skinId]
				end
			end
			table.insert(rows, { left = "   " .. table.concat(names, " · "), right = formatPercent(each) .. " c/u", color = Color3.fromRGB(220, 222, 235) })
		end
		table.insert(rows, { left = "Objeto al azar entre 6", right = "", color = Color3.fromRGB(160, 162, 185) })
	end
	local top, bottom = 0.1, 0.86
	local h = (bottom - top) / #rows
	for i, row in rows do
		local y = top + (i - 1) * h
		local l = text(bg, "Row" .. i, row.left, UDim2.fromScale(0.72, h * 0.8), UDim2.fromScale(0, y), row.color, Enum.Font.GothamBold)
		l.TextXAlignment = Enum.TextXAlignment.Left
		local r = text(bg, "Pct" .. i, row.right, UDim2.fromScale(0.28, h * 0.8), UDim2.fromScale(0.72, y), Color3.new(1, 1, 1), Enum.Font.GothamBold)
		r.TextXAlignment = Enum.TextXAlignment.Right
	end
	local hint = text(bg, "Hint", "[F] " .. def.InfoText, UDim2.fromScale(1, 0.06), UDim2.fromScale(0, 0.91), Color3.fromRGB(190, 192, 210), Enum.Font.GothamBold)
	hint.TextStrokeTransparency = 1

	local info = Instance.new("ProximityPrompt")
	info.Name = "InfoPrompt"
	info.ActionText = def.InfoText
	info.ObjectText = "Probabilidades"
	info.KeyboardKeyCode = Enum.KeyCode.F
	info.GamepadKeyCode = Enum.KeyCode.ButtonY
	info.HoldDuration = 0
	info.MaxActivationDistance = 9
	info.RequiresLineOfSight = false
	info.Exclusivity = Enum.ProximityPromptExclusivity.AlwaysShow
	info:SetAttribute("Stand", def.InfoStand)
	info.Parent = panel

	board.Parent = model
end

-- Construye la ruleta `kind` (Config.LobbyRoulettes.Wheels[kind]) en `parent`.
function RouletteBuilder.Build(kind: string, parent: Instance): Model?
	local def = RC.Wheels[kind]
	if not def then
		return nil
	end
	local sectors = RouletteBuilder.Sectors(kind)
	local hub = def.Position + Vector3.new(0, RC.HubHeight, 0)
	local facing = Vector3.new(def.Facing.X, 0, def.Facing.Z).Unit
	-- Marco local: Z hacia quien mira la rueda
	local frame = CFrame.lookAt(hub, hub - facing)

	local model = Instance.new("Model")
	model.Name = "Roulette_" .. kind
	model:SetAttribute("Roulette", kind)
	model:SetAttribute("Sectors", #sectors)
	model:SetAttribute("WheelFrame", frame)
	model:SetAttribute("Angle", 0)
	model:SetAttribute("SpinId", 0)
	local keys = {}
	for i, s in sectors do
		keys[i] = s.Key
	end
	model:SetAttribute("SectorKeys", table.concat(keys, ","))

	buildFrame(model, frame, def)
	buildRotor(model, frame, sectors)
	buildConsole(model, frame, kind, def)
	buildOddsBoard(model, frame, kind, def, sectors)

	model.PrimaryPart = (model :: any).Frame:FindFirstChild("BackDisc") :: BasePart
	-- Siempre cargada en el cliente (con streaming): la anima entera
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	CollectionService:AddTag(model, Tags.LobbyRoulette)
	model.Parent = parent
	return model
end

-- Coloca las piezas del rotor con la rueda girada `angle` grados (horario).
function RouletteBuilder.SetAngle(model: Model, angle: number)
	local frame = model:GetAttribute("WheelFrame") :: CFrame
	local rotor = model:FindFirstChild("Rotor")
	if not frame or not rotor then
		return
	end
	local at = frame * spin(angle)
	local parts, cframes = {}, {}
	for _, p in rotor:GetChildren() do
		local offset = p:GetAttribute("RotorOffset")
		if p:IsA("BasePart") and typeof(offset) == "CFrame" then
			table.insert(parts, p)
			table.insert(cframes, at * offset)
		end
	end
	workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
end

return RouletteBuilder
