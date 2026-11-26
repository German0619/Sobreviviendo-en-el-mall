-- Pantalla de carga (ReplicatedFirst: corre antes que todo lo demas, en el lobby y en el mall).
--   * Quita la pantalla de Roblox y pone la nuestra: fondo del mall de noche, "PLAZA LUNA" con
--     una luna creciente que parpadea como un fluorescente, barra de progreso con el paso
--     actual y un consejo al azar que va cambiando.
--   * Espera a que el juego cargue, a que exista el mapa (Workspace.Mall o Workspace.Lobby) y
--     tu personaje, y a que bajen las descargas pendientes; luego se desvanece.
--   * La misma pantalla se usa en los viajes entre places (TeleportService:SetTeleportGui):
--     al llegar se reemplaza por esta sin que se vea negro.
-- Es autonoma (no usa modulos de ReplicatedStorage: aun no han llegado cuando arranca).

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

local GOLD = Color3.fromRGB(240, 205, 120)
local DIM = Color3.fromRGB(150, 150, 165)
local MIN_SECONDS = 2.5 -- se ve al menos esto (no parpadea si todo carga al instante)
local MAX_SECONDS = 45 -- por si algo no llega nunca

local TIPS = {
	"El Maniquí solo se mueve cuando no lo miras.",
	"Si un compañero se te acerca raro, alúmbralo: el Eco copia caras.",
	"Limpia los derrames: el Rastro los huele y te sigue.",
	"Cada tarea que caduca hace más rápidos a todos los enemigos.",
	"Si dejáis caducar 3 tareas, La Garra atrapa a quien menos haya hecho.",
	"La Estatua solo se detiene con la luz de una bengala.",
	"Probadores, casilleros y armarios: escóndete y aguanta la respiración.",
	"El Ala Sur está en obras y a oscuras. Lleva batería de sobra.",
	"No mires fijamente el Globo: su estallido atrae a los enemigos.",
	"Las Polillas se comen la batería de tu linterna. Apágala.",
	"Si una tarea no está en tu lista, es la Megafonía mintiendo.",
	"Las tareas completadas acercan el reloj a las 6 AM.",
	"Cada 5 noches llega un jefe. Desde la 25, de dos en dos.",
	"El Cazador va a por el que está más solo. No te separes.",
	"Si oyes ruido en las rejillas del techo, camina: no corras.",
	"El Cajero roba billetes. Atúrdelo antes de que escape.",
}

local STEPS = {
	"Abriendo las puertas de Plaza Luna...",
	"Encendiendo las luces de emergencia...",
	"Despertando a los maniquíes...",
	"Buscando tu tarjeta de empleado...",
	"Casi listo. No te separes del grupo.",
}

----------------------------------------------------------------------
-- Interfaz (la misma para la carga y para el viaje entre places)
----------------------------------------------------------------------

local function make(className: string, props, parent: Instance?)
	local inst = Instance.new(className)
	for k, v in props do
		(inst :: any)[k] = v
	end
	inst.Parent = parent
	return inst
end

local function text(props, parent: Instance)
	local label = make("TextLabel", {
		BackgroundTransparency = 1,
		TextScaled = true,
		Font = Enum.Font.GothamMedium,
		TextColor3 = DIM,
	}, parent)
	for k, v in props do
		(label :: any)[k] = v
	end
	return label
end

local function buildGui(): ScreenGui
	local gui = make("ScreenGui", {
		Name = "PlazaLunaLoading",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		DisplayOrder = 1000,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	})
	local root = make("Frame", {
		Name = "Root",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(8, 9, 16),
		BorderSizePixel = 0,
	}, gui)
	make("UIGradient", {
		Color = ColorSequence.new(Color3.fromRGB(26, 30, 52), Color3.fromRGB(4, 4, 8)),
		Rotation = 90,
	}, root)

	-- Luna creciente (dos circulos) y nombre
	local logo = make("Frame", {
		Name = "Logo",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.4),
		Size = UDim2.fromScale(0.8, 0.34),
		BackgroundTransparency = 1,
	}, root)
	local moon = make("Frame", {
		Name = "Moon",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.18),
		Size = UDim2.fromScale(0.36, 0.36),
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		BackgroundColor3 = GOLD,
		BorderSizePixel = 0,
	}, logo)
	make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, moon)
	local bite = make("Frame", {
		Name = "Bite",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.72, 0.38),
		Size = UDim2.fromScale(0.9, 0.9),
		BackgroundColor3 = Color3.fromRGB(22, 25, 44),
		BorderSizePixel = 0,
	}, moon)
	make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, bite)
	local title = text({
		Name = "Title",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.4),
		Size = UDim2.fromScale(1, 0.38),
		Font = Enum.Font.Fondamento,
		TextColor3 = GOLD,
		Text = "PLAZA LUNA",
	}, logo)
	make("UIStroke", { Color = Color3.fromRGB(80, 50, 10), Thickness = 1.5, Transparency = 0.3 }, title)
	text({
		Name = "Subtitle",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.8),
		Size = UDim2.fromScale(0.9, 0.14),
		Font = Enum.Font.GothamBold,
		TextColor3 = Color3.fromRGB(200, 200, 212),
		Text = "SOBREVIVIENDO EN EL CENTRO COMERCIAL",
	}, logo)

	-- Consejo
	local tipBox = make("Frame", {
		Name = "TipBox",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.66),
		Size = UDim2.fromScale(0.7, 0.11),
		BackgroundTransparency = 1,
	}, root)
	text({ Name = "TipTitle", Size = UDim2.fromScale(1, 0.32), Font = Enum.Font.GothamBlack, TextColor3 = GOLD, Text = "CONSEJO" }, tipBox)
	text({ Name = "Tip", Position = UDim2.fromScale(0, 0.38), Size = UDim2.fromScale(1, 0.55), TextColor3 = Color3.fromRGB(215, 215, 225), Text = TIPS[1] }, tipBox)

	-- Barra de progreso y paso actual
	local bar = make("Frame", {
		Name = "Bar",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.86),
		Size = UDim2.fromScale(0.5, 0.008),
		BackgroundColor3 = Color3.fromRGB(45, 46, 60),
		BorderSizePixel = 0,
	}, root)
	make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, bar)
	local fill = make("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0.04, 1),
		BackgroundColor3 = GOLD,
		BorderSizePixel = 0,
	}, bar)
	make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, fill)
	text({
		Name = "Step",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.88),
		Size = UDim2.fromScale(0.6, 0.03),
		Text = STEPS[1],
	}, root)
	return gui
end

----------------------------------------------------------------------
-- Arranque
----------------------------------------------------------------------

local playerGui = player:WaitForChild("PlayerGui")
local gui = buildGui()
gui.Parent = playerGui
ReplicatedFirst:RemoveDefaultLoadingScreen()
-- Si venimos de un viaje, quitar la copia que trajo el teletransporte (esta es identica)
local arriving = TeleportService:GetArrivingTeleportGui()
if arriving then
	arriving:Destroy()
end

local screen = gui:WaitForChild("Root") :: Frame
local logo = screen:WaitForChild("Logo") :: Frame
local title = logo:WaitForChild("Title") :: TextLabel
local moon = logo:WaitForChild("Moon") :: Frame
local tipLabel = screen:WaitForChild("TipBox"):WaitForChild("Tip") :: TextLabel
local fill = screen:WaitForChild("Bar"):WaitForChild("Fill") :: Frame
local stepLabel = screen:WaitForChild("Step") :: TextLabel

local startedAt = os.clock()
local progress = 0.04 -- objetivo de la barra (0..1); se anima hacia el
local shown = 0.04
local done = false

-- El nombre y la luna parpadean de vez en cuando, como un fluorescente que falla
task.spawn(function()
	while not done do
		task.wait(math.random(15, 45) / 10)
		for _ = 1, math.random(2, 4) do
			title.TextTransparency = 0.7
			moon.BackgroundTransparency = 0.6
			task.wait(math.random(3, 9) / 100)
			title.TextTransparency = 0
			moon.BackgroundTransparency = 0
			task.wait(math.random(4, 12) / 100)
		end
	end
end)

-- Consejos: uno al azar cada 5 s, con fundido
task.spawn(function()
	local i = math.random(1, #TIPS)
	tipLabel.Text = TIPS[i]
	while not done do
		task.wait(5)
		if done then
			break
		end
		TweenService:Create(tipLabel, TweenInfo.new(0.35), { TextTransparency = 1 }):Play()
		task.wait(0.35)
		i = i % #TIPS + 1
		tipLabel.Text = TIPS[i]
		TweenService:Create(tipLabel, TweenInfo.new(0.35), { TextTransparency = 0 }):Play()
	end
end)

-- Barra suave
local barConn = RunService.RenderStepped:Connect(function(dt)
	shown += (progress - shown) * math.min(1, dt * 4)
	fill.Size = UDim2.fromScale(math.clamp(shown, 0.02, 1), 1)
end)

local function step(index: number, value: number)
	progress = math.max(progress, value)
	stepLabel.Text = STEPS[index]
end

local function timedOut(): boolean
	return os.clock() - startedAt > MAX_SECONDS
end

-- 1) El juego (lo que Roblox manda al entrar)
if not game:IsLoaded() then
	game.Loaded:Wait()
end
step(2, 0.35)

-- 2) El mapa: el mall lo construye el servidor al arrancar; el lobby ya viene en el place
while not (Workspace:FindFirstChild("Mall") or Workspace:FindFirstChild("Lobby")) and not timedOut() do
	task.wait(0.2)
end
step(3, 0.6)

-- 3) Tu personaje (y el suelo bajo sus pies)
local character = player.Character
while not (character and character:FindFirstChild("HumanoidRootPart")) and not timedOut() do
	task.wait(0.2)
	character = player.Character
end
step(4, 0.7)

-- 3b) El mapa ALREDEDOR del personaje (StreamingEnabled): el modelo del mapa existe
-- enseguida, pero sus piezas llegan poco a poco; si se quita la pantalla antes, se ve
-- negro unos segundos. Se espera a que haya suelo bajo los pies y a que el numero de
-- piezas cercanas deje de crecer.
local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
if root then
	pcall(function()
		player:RequestStreamAroundAsync(root.Position, 10)
	end)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = { character }
	local streamUntil = os.clock() + 20
	local lastCount, stableFor = -1, 0
	while os.clock() < streamUntil and not timedOut() and root.Parent do
		local ground = Workspace:Raycast(root.Position, Vector3.new(0, -12, 0), params)
		local count = #Workspace:GetPartBoundsInRadius(root.Position, 60, overlap)
		-- "estable": casi no llegan piezas nuevas en el ultimo cuarto de segundo
		if ground and count >= 25 and lastCount >= 0 and count - lastCount <= math.max(2, lastCount * 0.02) then
			stableFor += 0.25
		else
			stableFor = 0
		end
		lastCount = count
		progress = math.max(progress, 0.7 + 0.1 * math.clamp(count / 400, 0, 1))
		if stableFor >= 1.5 then
			break
		end
		task.wait(0.25)
	end
end
step(4, 0.8)

-- 4) Descargas pendientes (texturas, sonidos, modelos): hasta que casi no quede nada
local queueStart = math.max(ContentProvider.RequestQueueSize, 1)
local settleUntil = os.clock() + 8
while ContentProvider.RequestQueueSize > 5 and os.clock() < settleUntil and not timedOut() do
	local left = ContentProvider.RequestQueueSize / queueStart
	progress = math.max(progress, 0.8 + 0.18 * (1 - math.clamp(left, 0, 1)))
	task.wait(0.2)
end
step(5, 1)

-- Lista para el proximo viaje (lobby -> mall o vuelta al lobby): la misma pantalla
pcall(function()
	TeleportService:SetTeleportGui(buildGui())
end)

-- 5) Fundido
local remaining = MIN_SECONDS - (os.clock() - startedAt)
if remaining > 0 then
	task.wait(remaining)
end
task.wait(0.4)
done = true
local fade = TweenInfo.new(0.9, Enum.EasingStyle.Sine)
for _, d in gui:GetDescendants() do
	if d:IsA("TextLabel") then
		TweenService:Create(d, fade, { TextTransparency = 1 }):Play()
	elseif d:IsA("UIStroke") then
		TweenService:Create(d, fade, { Transparency = 1 }):Play()
	elseif d:IsA("Frame") and d ~= screen then
		TweenService:Create(d, fade, { BackgroundTransparency = 1 }):Play()
	end
end
TweenService:Create(screen, TweenInfo.new(1.4, Enum.EasingStyle.Sine), { BackgroundTransparency = 1 }):Play()
task.wait(1.5)
barConn:Disconnect()
gui:Destroy()
