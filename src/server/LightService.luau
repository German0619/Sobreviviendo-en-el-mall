-- LightService: zonas del mall y sus luces.
--
-- Una zona esta a oscuras si tiene al menos un "motivo" activo
-- (luces rotas por una mision, el Apagon, etc). Asi varios sistemas pueden
-- apagar la misma zona sin pisarse.

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Tags = require(Shared.Tags)
local GameState = require(Shared.GameState)
local Util = require(Shared.Util)

local OFF_COLOR = Color3.fromRGB(40, 40, 40)

local LightService = {}

local lightsByZone = {} -- [zone] = { entry }
local zoneParts = {} -- [zone] = BasePart
local reasons = {} -- [zone] = { [reason] = true }
local flickering = {} -- [zone] = true

local function zoneOf(inst: Instance): string
	local z = inst:GetAttribute("Zone")
	return if type(z) == "string" and z ~= "" then z else "Mall"
end

local function applyEntry(entry, on: boolean)
	for _, light in entry.Lights do
		light.Enabled = on
	end
	if entry.Part.Parent then
		entry.Part.Material = if on then entry.Material else Enum.Material.SmoothPlastic
		entry.Part.Color = if on then entry.Color else OFF_COLOR
	end
end

local function applyZone(zone: string)
	if flickering[zone] then
		return -- el parpadeo aplicara el estado final al terminar
	end
	local on = not LightService.IsZoneDark(zone)
	for _, entry in lightsByZone[zone] or {} do
		applyEntry(entry, on)
	end
	-- El HUD lo usa para avisar "zona sin luz"
	GameState.Folder:SetAttribute("Dark_" .. Util.attributeKey(zone), not on)
end

local function registerLight(inst: Instance)
	if not inst:IsA("BasePart") then
		return
	end
	local entry = {
		Part = inst,
		Lights = {},
		Material = inst.Material,
		Color = inst.Color,
	}
	for _, d in inst:GetDescendants() do
		if d:IsA("Light") then
			table.insert(entry.Lights, d)
		end
	end
	local zone = zoneOf(inst)
	lightsByZone[zone] = lightsByZone[zone] or {}
	table.insert(lightsByZone[zone], entry)
	applyEntry(entry, not LightService.IsZoneDark(zone))
end

local function unregisterLight(inst: Instance)
	for _, list in lightsByZone do
		for i, entry in list do
			if entry.Part == inst then
				table.remove(list, i)
				return
			end
		end
	end
end

local function registerZone(inst: Instance)
	if not inst:IsA("BasePart") then
		return
	end
	-- Los volumenes de zona no deben bloquear rayos, toques ni colisiones.
	inst.CanCollide = false
	inst.CanQuery = false
	inst.CanTouch = false
	inst.Transparency = 1
	zoneParts[zoneOf(inst)] = inst
end

----------------------------------------------------------------------
-- API
----------------------------------------------------------------------

function LightService.IsZoneDark(zone: string): boolean
	local r = reasons[zone]
	return r ~= nil and next(r) ~= nil
end

function LightService.HasReason(zone: string, reason: string): boolean
	local r = reasons[zone]
	return r ~= nil and r[reason] == true
end

function LightService.SetReason(zone: string, reason: string, active: boolean)
	local wasDark = LightService.IsZoneDark(zone)
	reasons[zone] = reasons[zone] or {}
	reasons[zone][reason] = if active then true else nil
	if wasDark ~= LightService.IsZoneDark(zone) then
		applyZone(zone)
	end
end

-- Parpadeo de terror; al terminar aplica el estado real de la zona.
function LightService.Flicker(zone: string, duration: number)
	if flickering[zone] then
		return
	end
	flickering[zone] = true
	task.spawn(function()
		local endAt = os.clock() + duration
		local on = true
		while os.clock() < endAt do
			on = not on
			for _, entry in lightsByZone[zone] or {} do
				applyEntry(entry, on)
			end
			task.wait(math.random(4, 18) / 100)
		end
		flickering[zone] = nil
		applyZone(zone)
	end)
end

-- Zonas siempre oscuras (Config.DarkZones): razon permanente "Ambient".
local AMBIENT = "Ambient"
local function applyAmbientDark()
	for _, zone in Config.DarkZones or {} do
		reasons[zone] = reasons[zone] or {}
		reasons[zone][AMBIENT] = true
		GameState.Folder:SetAttribute("Ambient_" .. Util.attributeKey(zone), true)
	end
end

-- true si la zona es oscura por diseño (no por un apagon o luces rotas).
function LightService.IsAmbientDark(zone: string): boolean
	return LightService.HasReason(zone, AMBIENT)
end

function LightService.ResetAll()
	reasons = {}
	applyAmbientDark()
	for zone in lightsByZone do
		applyZone(zone)
	end
	for zone in zoneParts do
		applyZone(zone)
	end
end

-- Evento Neblina. La bruma de la Atmosphere casi no se ve en un mall a oscuras (no hay
-- luz que la ilumine), asi que se usa la niebla clasica de Lighting (FogEnd), que tapa de
-- verdad lo que esta a mas de FOG_END studs. La niebla clasica solo funciona sin
-- Atmosphere: mientras dura, la Atmosphere se guarda fuera de Lighting.
local FOG_NORMAL = { Density = 0.14, Haze = 0.7, Color = Color3.fromRGB(15, 15, 20) } -- Atmosphere normal
local FOG_END = 38 -- con niebla, no se ve nada a mas de esto
local FOG_CLEAR = 1500 -- "sin niebla" para la transicion
local FOG_COLOR = Color3.fromRGB(48, 50, 56)
local storedAtmosphere: Atmosphere? = nil
local fogToken = 0
function LightService.SetFog(on: boolean, seconds: number)
	fogToken += 1
	local token = fogToken
	local info = TweenInfo.new(math.max(seconds, 0.01), Enum.EasingStyle.Sine)
	if on then
		local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
		if atmosphere then
			storedAtmosphere = atmosphere
			atmosphere.Parent = nil
		end
		Lighting.FogColor = FOG_COLOR
		Lighting.FogStart = 0
		Lighting.FogEnd = FOG_CLEAR
		TweenService:Create(Lighting, info, { FogEnd = FOG_END }):Play()
	else
		TweenService:Create(Lighting, info, { FogEnd = FOG_CLEAR }):Play()
		task.delay(seconds, function()
			if fogToken ~= token then
				return -- volvio a empezar otra niebla
			end
			Lighting.FogEnd = 100000
			if storedAtmosphere then
				storedAtmosphere.Parent = Lighting
				storedAtmosphere = nil
			end
		end)
	end
end

function LightService.GetZones(): { string }
	local list = {}
	for zone in zoneParts do
		table.insert(list, zone)
	end
	if #list == 0 then
		for zone in lightsByZone do
			table.insert(list, zone)
		end
	end
	return list
end

function LightService.GetZonePart(zone: string): BasePart?
	return zoneParts[zone]
end

function LightService.GetZoneCenter(zone: string): Vector3?
	local part = zoneParts[zone]
	if part then
		return part.Position
	end
	local lights = lightsByZone[zone]
	if lights and #lights > 0 then
		local sum = Vector3.zero
		for _, entry in lights do
			sum += entry.Part.Position
		end
		return sum / #lights
	end
	return nil
end

-- Zona en la que esta un punto (nil si fuera de todas).
function LightService.GetZoneAt(position: Vector3): string?
	for zone, part in zoneParts do
		local rel = part.CFrame:PointToObjectSpace(position)
		local half = part.Size / 2
		if math.abs(rel.X) <= half.X and math.abs(rel.Y) <= half.Y and math.abs(rel.Z) <= half.Z then
			return zone
		end
	end
	return nil
end

function LightService.IsDarkAt(position: Vector3): boolean
	local zone = LightService.GetZoneAt(position)
	return zone ~= nil and LightService.IsZoneDark(zone)
end

----------------------------------------------------------------------
-- Arranque
----------------------------------------------------------------------

local function setupAmbience()
	-- Noche cerrada: casi toda la luz viene de las lamparas del mall y las linternas.
	-- (Recomendado en Studio: Lighting.Technology = Future para sombras de luces.)
	Lighting.ClockTime = 0
	Lighting.Brightness = 0
	Lighting.Ambient = Color3.fromRGB(6, 6, 10)
	Lighting.OutdoorAmbient = Color3.fromRGB(4, 4, 8)
	Lighting.EnvironmentDiffuseScale = 0
	Lighting.EnvironmentSpecularScale = 0
	Lighting.GlobalShadows = true
	Lighting.ExposureCompensation = 0
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere then
		-- Bruma ligera: oscurece lo lejano sin tapar el interior (con 0.35 se veia todo negro)
		-- (los mismos valores que FOG_NORMAL: la Neblina vuelve a ellos)
		atmosphere.Density = FOG_NORMAL.Density
		atmosphere.Offset = 0
		atmosphere.Color = FOG_NORMAL.Color
		atmosphere.Decay = Color3.fromRGB(5, 5, 8)
		atmosphere.Glare = 0
		atmosphere.Haze = FOG_NORMAL.Haze
	end

	-- Postprocesado "realista": un poco de contraste, tono frio de noche y un bloom
	-- suave que solo afecta a las lamparas (Threshold alto) y no a las paredes.
	local function effect(className: string, name: string): Instance
		local e = Lighting:FindFirstChild(name)
		if not e then
			e = Instance.new(className)
			e.Name = name
			e.Parent = Lighting
		end
		return e
	end
	local grade = effect("ColorCorrectionEffect", "MallGrade") :: ColorCorrectionEffect
	grade.Brightness = 0.02
	grade.Contrast = 0.12
	grade.Saturation = -0.12
	grade.TintColor = Color3.fromRGB(238, 242, 255)
	local bloom = Lighting:FindFirstChildOfClass("BloomEffect") or effect("BloomEffect", "Bloom")
	local b = bloom :: BloomEffect
	b.Intensity = 0.55
	b.Size = 28
	b.Threshold = 1.4
	-- Los rayos de sol y la profundidad de campo no pintan nada dentro de un mall de noche
	for _, e in Lighting:GetChildren() do
		if e:IsA("SunRaysEffect") or e:IsA("DepthOfFieldEffect") then
			e.Enabled = false
		end
	end
end

function LightService.Start()
	setupAmbience()
	applyAmbientDark()

	for _, inst in CollectionService:GetTagged(Tags.Zone) do
		registerZone(inst)
	end
	CollectionService:GetInstanceAddedSignal(Tags.Zone):Connect(registerZone)

	for _, inst in CollectionService:GetTagged(Tags.Light) do
		registerLight(inst)
	end
	CollectionService:GetInstanceAddedSignal(Tags.Light):Connect(registerLight)
	CollectionService:GetInstanceRemovedSignal(Tags.Light):Connect(unregisterLight)
	for _, zone in Config.DarkZones or {} do
		applyZone(zone)
	end
end

return LightService
