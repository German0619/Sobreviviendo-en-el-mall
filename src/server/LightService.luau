-- LightService: zonas del mall y sus luces.
--
-- Una zona esta a oscuras si tiene al menos un "motivo" activo
-- (luces rotas por una mision, el Apagon, etc). Asi varios sistemas pueden
-- apagar la misma zona sin pisarse.

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Tags = require(Shared.Tags)
local GameState = require(Shared.GameState)
local Util = require(Shared.Util)

local SfxService = require(script.Parent.SfxService)

local OFF_COLOR = Color3.fromRGB(40, 40, 40)

local LightService = {}

local tintEntry -- (definida mas abajo: luz enfermiza)
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
		-- (un tubo muerto sigue apagado; uno que parpadea termina su parpadeo)
		if not entry.Flickering then
			applyEntry(entry, on and not entry.Dead)
		end
	end
	-- El HUD lo usa para avisar "zona sin luz"
	GameState.Folder:SetAttribute("Dark_" .. Util.attributeKey(zone), not on)
end

----------------------------------------------------------------------
-- Luz enfermiza: crece de la noche 1 a Config.Lighting.FullFromNight
----------------------------------------------------------------------

local lookAmount = 0 -- 0 = luz normal (noche 1) .. 1 = enfermiza del todo
local gradeEffect: ColorCorrectionEffect? = nil

local function lookForNight(night: number): number
	local L = Config.Lighting
	local full = (L and L.FullFromNight) or 1
	if full <= 1 then
		return 1
	end
	return math.clamp((night - 1) / (full - 1), 0, 1)
end

-- Color del tubo y de su luz, y brillo, segun lookAmount (sobre los originales).
function tintEntry(entry)
	local L = Config.Lighting
	if not L then
		return
	end
	local k = L.TintAmount * lookAmount
	entry.Color = entry.BaseColor:Lerp(L.LampColor, k)
	local brightness = 1 + (L.LampBrightness - 1) * lookAmount
	for light, base in entry.LightBase do
		light.Color = base.Color:Lerp(L.LightColor, k)
		light.Brightness = base.Brightness * brightness
	end
end

local function applyGrade()
	local L = Config.Lighting
	local grade = gradeEffect
	if not L or not grade or not L.BaseGrade or not L.Grade then
		return
	end
	local a, b, t = L.BaseGrade, L.Grade, lookAmount
	grade.Brightness = a.Brightness + (b.Brightness - a.Brightness) * t
	grade.Contrast = a.Contrast + (b.Contrast - a.Contrast) * t
	grade.Saturation = a.Saturation + (b.Saturation - a.Saturation) * t
	grade.TintColor = a.Tint:Lerp(b.Tint, t)
end

local function registerLight(inst: Instance)
	if not inst:IsA("BasePart") then
		return
	end
	-- (Color y brillo originales: la luz enfermiza se aplica sobre ellos segun la noche)
	local entry = {
		Part = inst,
		Lights = {},
		LightBase = {},
		Material = inst.Material,
		Color = inst.Color,
		BaseColor = inst.Color,
	}
	for _, d in inst:GetDescendants() do
		if d:IsA("Light") then
			table.insert(entry.Lights, d)
			entry.LightBase[d] = { Color = d.Color, Brightness = d.Brightness }
		end
	end
	tintEntry(entry)
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
				applyEntry(entry, on and not entry.Dead)
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
-- Tubos que fallan (de noche): unas pocas lamparas muertas toda la noche y, cada pocos
-- segundos, una lampara cerca de algun jugador parpadea con un chispazo (y a veces se
-- muere). Config.Lighting.
----------------------------------------------------------------------

local rng = Random.new()
local failToken = 0

local function nearPlayer(position: Vector3, range: number): boolean
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root and (root.Position - position).Magnitude <= range then
			return true
		end
	end
	return false
end

-- Una lampara sola parpadea; al acabar vuelve a su estado real (o se queda muerta).
local function flickerEntry(zone: string, entry, duration: number)
	local L = Config.Lighting
	entry.Flickering = true
	SfxService.PlayAt("TubeFlicker", entry.Part)
	task.spawn(function()
		local endAt = os.clock() + duration
		local on = true
		while os.clock() < endAt and entry.Part.Parent do
			on = not on
			applyEntry(entry, on)
			task.wait(rng:NextNumber(0.03, if on then 0.25 else 0.12))
		end
		entry.Flickering = nil
		if rng:NextNumber() < L.FlickerDieChance then
			entry.Dead = true
		end
		if not flickering[zone] and entry.Part.Parent then
			applyEntry(entry, not LightService.IsZoneDark(zone) and not entry.Dead)
		end
	end)
end

local function startFailingTubes()
	local L = Config.Lighting
	if not L then
		return
	end
	failToken += 1
	local token = failToken
	-- Lamparas muertas esta noche (en proporcion a la noche: en la 1, ninguna)
	for zone, list in lightsByZone do
		for _, entry in list do
			entry.Dead = rng:NextNumber() < L.DeadFraction * lookAmount or nil
		end
		applyZone(zone)
	end
	task.spawn(function()
		while failToken == token do
			task.wait(rng:NextNumber(L.FlickerEvery[1], L.FlickerEvery[2]))
			if failToken ~= token then
				break
			end
			-- (en las primeras noches casi nunca: un parpadeo solo con probabilidad lookAmount)
			if rng:NextNumber() >= lookAmount then
				continue
			end
			-- Una lampara encendida cerca de alguien (si no, nadie lo veria)
			local candidates = {}
			for zone, list in lightsByZone do
				if not flickering[zone] and not LightService.IsZoneDark(zone) then
					for _, entry in list do
						if not entry.Dead and not entry.Flickering and entry.Part.Parent
							and nearPlayer(entry.Part.Position, L.FlickerNearPlayers) then
							table.insert(candidates, { Zone = zone, Entry = entry })
						end
					end
				end
			end
			if #candidates > 0 then
				local pick = candidates[rng:NextInteger(1, #candidates)]
				flickerEntry(pick.Zone, pick.Entry, rng:NextNumber(L.FlickerSeconds[1], L.FlickerSeconds[2]))
			end
		end
	end)
end

local function stopFailingTubes()
	failToken += 1
	for zone, list in lightsByZone do
		for _, entry in list do
			entry.Dead = nil
		end
		applyZone(zone)
	end
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
	-- (Config.Lighting: de BaseGrade en la noche 1 a Grade, mas contraste y menos color)
	local grade = effect("ColorCorrectionEffect", "MallGrade") :: ColorCorrectionEffect
	grade.Brightness = 0.02
	grade.Contrast = 0.12
	grade.Saturation = -0.12
	grade.TintColor = Color3.fromRGB(238, 242, 255)
	gradeEffect = grade
	applyGrade()
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

	-- Luz enfermiza segun la noche (de la 1 a Config.Lighting.FullFromNight)
	local function onNight()
		local night = GameState.Folder:GetAttribute("Night")
		lookAmount = lookForNight(if type(night) == "number" then night else 1)
		for zone, list in lightsByZone do
			for _, entry in list do
				tintEntry(entry)
			end
			applyZone(zone)
		end
		applyGrade()
	end
	GameState.Folder:GetAttributeChangedSignal("Night"):Connect(onNight)
	onNight()

	-- Tubos que fallan: solo durante la noche
	local function onPhase()
		if GameState.Folder:GetAttribute("Phase") == "Night" then
			startFailingTubes()
		else
			stopFailingTubes()
		end
	end
	GameState.Folder:GetAttributeChangedSignal("Phase"):Connect(onPhase)
end

return LightService
