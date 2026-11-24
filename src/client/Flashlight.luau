-- Flashlight: camara en primera persona y linterna con F (o boton en movil).
-- El servidor decide si se enciende y gasta la bateria; aqui solo pedimos
-- el cambio y apuntamos la luz hacia donde mira la camara.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)

local BASE_BRIGHTNESS = Config.Flashlight.Brightness
local updateHitGlow -- (se define mas abajo)

local player = Players.LocalPlayer

local Flashlight = {}

local ATTACHMENT_NAME = "FlashlightAttachment"
-- Posicion de la linterna: delante del pecho (en horizontal), a la derecha y un poco abajo
local HOLD_FORWARD, HOLD_RIGHT, HOLD_DOWN = 1.3, 0.5, 0.6

local lastToggle = 0

-- Circulo de luz del haz (solo en este cliente). Con la calidad grafica baja/automatica,
-- Roblox calcula la luz en bloques de ~4 studs: el foco de la linterna apenas ilumina y
-- una luz con alcance pequeño DESAPARECE (al mirar al suelo o acercarte a algo, el
-- circulo bajaba a 2-4 studs de alcance y no se veia nada). Esta luz va un poco
-- separada de la superficie donde choca el haz, sigue el tamaño del circulo del cono
-- pero nunca baja de MIN_RANGE, para que siempre se vea en cualquier calidad grafica.
local HIT_GLOW_RANGE = 45 -- igual que el alcance de la linterna
local MIN_RANGE = 8 -- por debajo, con calidad baja la luz deja de verse
local MIN_OFFSET = 2 -- separacion minima de la superficie
local hitGlow: { Part: BasePart, Light: PointLight }? = nil
local hitParams = RaycastParams.new()
hitParams.FilterType = Enum.RaycastFilterType.Exclude

-- Raycast que atraviesa partes invisibles (puntos de mision, barandillas transparentes,
-- volumenes...): el circulo debe quedar en lo que ves, no en algo invisible.
local function raycastVisible(from: Vector3, dir: Vector3, ignore: { Instance }): RaycastResult?
	local list = table.clone(ignore)
	for _ = 1, 6 do
		hitParams.FilterDescendantsInstances = list
		local hit = Workspace:Raycast(from, dir, hitParams)
		if not hit or hit.Instance.Transparency < 0.9 then
			return hit
		end
		table.insert(list, hit.Instance)
	end
	return nil
end

local function getHitGlow()
	if hitGlow and hitGlow.Part.Parent then
		return hitGlow
	end
	local part = Instance.new("Part")
	part.Name = "FlashlightHitGlow"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.new(0.2, 0.2, 0.2)
	local light = Instance.new("PointLight")
	light.Shadows = false
	light.Enabled = false
	light.Parent = part
	part.Parent = Workspace.CurrentCamera -- local: no se replica
	hitGlow = { Part = part, Light = light }
	return hitGlow
end

-- `eye` = posicion de la camara: el rayo sale de tus ojos hacia donde miras (si saliera
-- del foco y estuvieras pegado a una pared, empezaria dentro de ella y la atravesaria).
function updateHitGlow(character: Model, att: Attachment, eye: Vector3, direction: Vector3)
	local glow = getHitGlow()
	local spot = att:FindFirstChildOfClass("SpotLight")
	if not spot or not spot.Enabled or player:GetAttribute("FlashlightOn") ~= true then
		glow.Light.Enabled = false
		return
	end
	local hit = raycastVisible(eye, direction * HIT_GLOW_RANGE, { character, Workspace.CurrentCamera })
	if not hit then
		glow.Light.Enabled = false
		return
	end
	local dist = hit.Distance
	-- Mismo circulo que el haz principal: radio = distancia * tan(mitad del cono)
	local radius = dist * math.tan(math.rad(spot.Angle / 2))
	-- El destello sube el brillo y abre el cono: el circulo lo acompaña
	local boost = spot.Brightness / math.max(BASE_BRIGHTNESS, 0.1)
	-- Separada de la superficie, pero nunca detras de tus ojos
	local offset = math.min(math.max(MIN_OFFSET, radius * 0.45), math.max(dist - 0.3, 0.3))
	glow.Part.Position = hit.Position + hit.Normal * offset
	glow.Light.Color = spot.Color
	glow.Light.Range = math.max(MIN_RANGE, radius * 1.4 + 1.5)
	-- Lejos, el circulo es mas grande y mas tenue
	glow.Light.Brightness = 2 * math.clamp(1 - dist / 70, 0.35, 1) * boost
	glow.Light.Enabled = true
end

local function toggle()
	if os.clock() - lastToggle < 0.2 then
		return
	end
	lastToggle = os.clock()
	local wantOn = player:GetAttribute("FlashlightOn") ~= true
	if wantOn and (player:GetAttribute("Battery") or 0) <= 0 then
		return
	end
	Remotes.event("ToggleFlashlight"):FireServer(wantOn)
end

-- En primera persona tu cuerpo es invisible para ti, pero seguia proyectando sombra:
-- al mirar hacia abajo la linterna (que tiene sombras) chocaba con tu torso y piernas
-- y el suelo se veia negro. Solo en este cliente: tu personaje no proyecta sombra.
local function disableOwnShadows(character: Model)
	local function apply(inst: Instance)
		if inst:IsA("BasePart") then
			inst.CastShadow = false
		end
	end
	for _, d in character:GetDescendants() do
		apply(d)
	end
	character.DescendantAdded:Connect(apply) -- accesorios que llegan despues
end

function Flashlight.Start()
	player.CameraMode = Enum.CameraMode.LockFirstPerson
	if player.Character then
		disableOwnShadows(player.Character)
	end
	player.CharacterAdded:Connect(disableOwnShadows)

	ContextActionService:BindAction("Flashlight", function(_, state)
		if state == Enum.UserInputState.Begin then
			toggle()
		end
		return Enum.ContextActionResult.Pass
	end, true, Enum.KeyCode.F, Enum.KeyCode.ButtonR1)
	ContextActionService:SetTitle("Flashlight", "Luz")
	ContextActionService:SetPosition("Flashlight", UDim2.new(1, -170, 1, -160))

	-- Apuntar la linterna con la camara (incluida la inclinacion arriba/abajo).
	-- Es solo visual en este cliente; el servidor usa la direccion del personaje.
	-- El foco se coloca delante del pecho con un desplazamiento HORIZONTAL: antes el
	-- desplazamiento seguia a la camara y al mirar hacia abajo el foco quedaba dentro
	-- del torso, asi que solo iluminaba tu propio cuerpo y el suelo se veia negro.
	RunService.RenderStepped:Connect(function()
		local character = player.Character
		local head = character and character:FindFirstChild("Head")
		local att = head and head:FindFirstChild(ATTACHMENT_NAME)
		local camera = Workspace.CurrentCamera
		if att and camera then
			local camCF = camera.CFrame
			local flat = Vector3.new(camCF.LookVector.X, 0, camCF.LookVector.Z)
			flat = if flat.Magnitude > 0.05 then flat.Unit else Vector3.new(camCF.UpVector.X, 0, camCF.UpVector.Z).Unit
			local right = Vector3.new(camCF.RightVector.X, 0, camCF.RightVector.Z)
			right = if right.Magnitude > 0.05 then right.Unit else Vector3.new(-flat.Z, 0, flat.X)
			local eye = camCF.Position
			local hold = flat * HOLD_FORWARD + right * HOLD_RIGHT - Vector3.new(0, HOLD_DOWN, 0)
			-- Pegado a una pared: el foco no debe quedar dentro de ella (no alumbraria nada)
			hitParams.FilterDescendantsInstances = { character, camera }
			local block = Workspace:Raycast(eye, hold, hitParams)
			local origin = if block then eye + hold.Unit * math.max(block.Distance - 0.3, 0) else eye + hold
			att.WorldCFrame = CFrame.lookAt(origin, origin + camCF.LookVector)
			updateHitGlow(character, att, eye, camCF.LookVector)
		elseif hitGlow then
			hitGlow.Light.Enabled = false
		end
	end)
end

return Flashlight
