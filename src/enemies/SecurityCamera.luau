-- SecurityCamera: camaras del mall (tag SecurityCamera) que trabajan para el Vigilante.
--
-- Solo se activan las noches en que hay Vigilante (EnemyService las crea).
-- Barren de lado a lado con un haz rojo visible. Si ven a un jugador un
-- momento (Config.SecurityCameras.DetectSeconds), avisan al Vigilante de donde esta.
-- Ven en la oscuridad (infrarrojo), pero no dentro de los escondites.
--
-- Contramedidas: esquivar el haz; el destello [G] las ciega
-- Config.SecurityCameras.DisabledSeconds segundos.
--
-- EnemyService las trata como un enemigo mas (Update / OnFlash / Destroy), asi
-- el destello de DefenseService las alcanza. Model es la parte de la camara.

local ServerScriptService = game:GetService("ServerScriptService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Signal = require(Shared.Signal)

local Server = ServerScriptService:WaitForChild("Server")
local DefenseService = require(Server:WaitForChild("DefenseService"))
local PlayerStats = require(Server:WaitForChild("PlayerStats"))

local Common = require(script.Parent.Common)

local CamConfig = Config.SecurityCameras
local SCAN_INTERVAL = 0.1
local BEAM_COLOR = Color3.fromRGB(255, 40, 40)

local SecurityCamera = {}
SecurityCamera.__index = SecurityCamera

----------------------------------------------------------------------
-- Avistamientos (los lee el Vigilante)
----------------------------------------------------------------------

type Sighting = { Position: Vector3, Time: number, Player: Player }

local lastSighting: Sighting? = nil
local lastWarned: { [Player]: number } = {}

function SecurityCamera.GetSighting(): Sighting?
	return lastSighting
end

function SecurityCamera.ClearSighting()
	lastSighting = nil
end

-- (player, position) una camara vio a alguien. Lo usa la Central (jefe de la noche 20).
SecurityCamera.Spotted = Signal.new()
-- Aviso al jugador visto (la Central lo cambia por el suyo; "" = sin aviso)
SecurityCamera.ReportMessage = nil :: string?

local function report(player: Player, position: Vector3)
	local now = os.clock()
	lastSighting = { Position = position, Time = now, Player = player }
	if not lastWarned[player] or now - lastWarned[player] > 8 then
		lastWarned[player] = now
		-- Las camaras son los ojos del Vigilante (con la Central, ReportMessage, son suyas)
		if SecurityCamera.ReportMessage == nil then
			Common.discover(player, "Watcher")
		end
		local message = SecurityCamera.ReportMessage or "¡Una cámara te vio! El Vigilante viene hacia aquí."
		if message ~= "" then
			Remotes.event("Notify"):FireClient(player, message, "bad")
		end
		SecurityCamera.Spotted:Fire(player, position)
	end
end

----------------------------------------------------------------------
-- Camara
----------------------------------------------------------------------

function SecurityCamera.new(part: BasePart, _ctx)
	local self = setmetatable({}, SecurityCamera)
	self.Model = part
	self.BaseCFrame = part.CFrame
	self.StartTime = os.clock() + math.random() * CamConfig.SweepSeconds -- desfasadas entre si
	self.Accumulator = 0
	self.Level = {} :: { [Player]: number }
	self.CosHalf = math.cos(math.rad(CamConfig.HalfAngle))
	self.Disabled = false

	local beam = Instance.new("SpotLight")
	beam.Name = "CameraBeam"
	beam.Face = Enum.NormalId.Front
	beam.Color = BEAM_COLOR
	beam.Range = CamConfig.Range
	beam.Angle = CamConfig.HalfAngle * 2
	beam.Brightness = 3
	beam.Shadows = true
	beam.Parent = part
	self.Beam = beam

	-- Piloto rojo
	local led = Instance.new("PointLight")
	led.Name = "CameraLed"
	led.Color = BEAM_COLOR
	led.Range = 4
	led.Brightness = 2
	led.Parent = part
	self.Led = led
	return self
end

-- Punto que tiene que alumbrar el destello (justo delante del lente, para que
-- el rayo de vision no choque con la propia camara).
function SecurityCamera:GetFlashPoint(): Vector3
	return self.Model.Position + self.Model.CFrame.LookVector * 1.5
end

function SecurityCamera:SetDisabled(disabled: boolean)
	if self.Disabled == disabled then
		return
	end
	self.Disabled = disabled
	self.Beam.Enabled = not disabled
	self.Led.Enabled = not disabled
	if disabled then
		self.Level = {}
	end
end

function SecurityCamera:Sees(root: BasePart, head: BasePart): boolean
	local origin = self:GetFlashPoint()
	local toHead = head.Position - origin
	local dist = toHead.Magnitude
	if dist > CamConfig.Range or dist < 0.1 then
		return false
	end
	if self.Model.CFrame.LookVector:Dot(toHead.Unit) < self.CosHalf then
		return false
	end
	return Common.lineOfSight(origin, head.Position) or Common.lineOfSight(origin, root.Position)
end

function SecurityCamera:Update(dt: number)
	local part = self.Model
	if not part.Parent then
		return
	end

	self:SetDisabled(DefenseService.IsStunned(part :: any))
	if self.Disabled then
		return
	end

	-- Barrido de lado a lado (alrededor del eje vertical)
	local t = os.clock() - self.StartTime
	local yaw = math.sin(t * 2 * math.pi / CamConfig.SweepSeconds) * math.rad(CamConfig.SweepDegrees / 2)
	part.CFrame = CFrame.new(self.BaseCFrame.Position)
		* CFrame.fromAxisAngle(Vector3.yAxis, yaw)
		* self.BaseCFrame.Rotation

	-- Deteccion (10 veces por segundo)
	self.Accumulator += dt
	if self.Accumulator < SCAN_INTERVAL then
		return
	end
	local step = self.Accumulator
	self.Accumulator = 0

	local seeing = false
	for _, player in Common.getAlivePlayers() do
		local character = player.Character
		local root = Common.getRoot(player)
		local head = character and character:FindFirstChild("Head")
		if root and head and head:IsA("BasePart") and not DefenseService.IsHidden(player) and self:Sees(root, head) then
			seeing = true
			local delay = PlayerStats.GetPerk(player, "DetectionDelay") or 1
			local level = (self.Level[player] or 0) + step / (CamConfig.DetectSeconds * delay)
			self.Level[player] = math.min(level, 1)
			if level >= 1 then
				report(player, root.Position)
			end
		else
			self.Level[player] = math.max(0, (self.Level[player] or 0) - step)
		end
	end
	-- El haz se intensifica mientras ve a alguien
	self.Beam.Brightness = if seeing then 6 else 3
end

-- Destello: queda ciega un rato.
function SecurityCamera:OnFlash(player: Player)
	if self.Disabled then
		return
	end
	DefenseService.Stun(self.Model :: any, CamConfig.DisabledSeconds)
	self:SetDisabled(true)
	Remotes.event("Notify"):FireClient(player, string.format("Cámara cegada %d s.", CamConfig.DisabledSeconds), "good")
end

-- El porrazo no le hace nada (esta en lo alto de la pared).
function SecurityCamera:OnShove(_player: Player, _direction: Vector3) end

function SecurityCamera:Destroy()
	-- La camara es parte del mapa: solo se deja como estaba
	if self.Model.Parent then
		self.Model.CFrame = self.BaseCFrame
		self.Model:SetAttribute("StunnedUntil", nil)
		local highlight = self.Model:FindFirstChild("StunHighlight")
		if highlight then
			highlight:Destroy()
		end
	end
	self.Beam:Destroy()
	self.Led:Destroy()
	lastSighting = nil
	lastWarned = {}
end

return SecurityCamera
