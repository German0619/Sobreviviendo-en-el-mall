-- DefenseService: formas activas de defenderse de las entidades (Fase 5).
-- Defenderse cuesta recursos y es temporal: sigue siendo un juego de terror.
--
--   * [G] Destello de linterna: gasta bateria de golpe y afecta a los enemigos del
--     cono (cada enemigo decide en OnFlash; por defecto queda aturdido).
--   * [Q] Porrazo (clase Guardia): empuja y aturde a los enemigos de enfrente (OnShove).
--   * Bengala (tienda): zona iluminada temporal. La consultan los enemigos.
--   * Petardo (tienda): tras la mecha atrae a los enemigos cercanos.
--   * Escondites (tag HidingSpot): rompen la persecucion si el enemigo no te vio entrar.
--   * Zonas de las armas (WeaponService): nube del extintor (IsInSmoke: ciega) y
--     piso mojado (GetSpeedFactor: ralentiza). Empujon con fuerza variable (Push).
--
-- Los enemigos consultan este servicio (IsStunned, IsInFlare, GetLure, IsHidden...);
-- este servicio NO requiere los modulos de enemigos (EnemyService le pasa la lista).
--
-- Atributos del Player: FlashReadyAt, AbilityReadyAt, HideReadyAt, HiddenUntil
--   (tiempos de Workspace:GetServerTimeNow()) y Hidden (true mientras esta escondido).
-- Atributos del modelo enemigo: StunnedUntil (os.clock del servidor).
-- Atributo del escondite: Occupied.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Tags = require(Shared.Tags)
local Remotes = require(Shared.Remotes)
local Signal = require(Shared.Signal)

local FlashlightService = require(script.Parent.FlashlightService)
local PlayerStats = require(script.Parent.PlayerStats)

local DefenseService = {}

-- (player) se acaba de esconder. Common lo usa para decidir que enemigos lo vieron entrar.
DefenseService.PlayerHid = Signal.new()

local Def = Config.Defense

type Flare = { Position: Vector3, ExpiresAt: number, Part: BasePart }
type Lure = { Position: Vector3, ActiveFrom: number, ExpiresAt: number, Part: BasePart?, Radius: number? }
type HideEntry = { Spot: BasePart, Character: Model, Until: number }
type Zone = { Position: Vector3, Radius: number, ExpiresAt: number, Part: BasePart?, Multiplier: number? }

local flares: { Flare } = {}
local lures: { Lure } = {}
local smokes: { Zone } = {}
local slowZones: { Zone } = {}
local hiding: { [Player]: HideEntry } = {}
local occupants: { [BasePart]: Player } = {}

local enemyProvider: () -> { any } = function()
	return {}
end

----------------------------------------------------------------------
-- Utilidades
----------------------------------------------------------------------

local function notify(player: Player, message: string, kind: string?)
	Remotes.event("Notify"):FireClient(player, message, kind or "info")
end

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

local function getRoot(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function isAlive(player: Player): boolean
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0 and player:GetAttribute("Alive") ~= false
end

-- Puede usar una defensa: vivo y no escondido.
local function canAct(player: Player): boolean
	return isAlive(player) and hiding[player] == nil
end

local function flatLook(root: BasePart): Vector3?
	local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	return if look.Magnitude > 0.01 then look.Unit else nil
end

local function flatDistance(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

local function getPropsFolder(): Folder
	local folder = Workspace:FindFirstChild("DefenseProps")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "DefenseProps"
		folder.Parent = Workspace
	end
	return folder :: Folder
end

local function throwParams(): RaycastParams
	local exclude: { Instance } = { getPropsFolder() }
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(exclude, p.Character)
		end
	end
	for _, name in { "Enemies", "MissionProps" } do
		local folder = Workspace:FindFirstChild(name)
		if folder then
			table.insert(exclude, folder)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclude
	return params
end

-- Lanza hacia delante: devuelve (punto de salida, punto del suelo donde cae).
local function throwTarget(player: Player, range: number): (Vector3?, Vector3?)
	local root = getRoot(player)
	if not root then
		return nil, nil
	end
	local look = flatLook(root) or Vector3.new(0, 0, -1)
	local origin = root.Position + Vector3.new(0, 1.5, 0)
	local params = throwParams()
	local hit = Workspace:Raycast(origin, look * range, params)
	local landing = if hit then hit.Position - look * 1.5 else origin + look * range
	local down = Workspace:Raycast(landing + Vector3.new(0, 1, 0), Vector3.new(0, -60, 0), params)
	local ground = if down then down.Position else Vector3.new(landing.X, root.Position.Y - 3, landing.Z)
	return origin, ground
end

local function prop(props): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false -- no bloquea rayos de vision ni de linterna
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props do
		(p :: any)[k] = v
	end
	return p
end

-- Arco simple del objeto lanzado hasta el suelo. rest: como queda apoyado (rotacion
-- y altura del centro sobre el suelo).
local function flyTo(part: BasePart, from: Vector3, to: Vector3, duration: number, rest: CFrame)
	local apex = (from + to) / 2 + Vector3.new(0, math.min(6, (to - from).Magnitude * 0.25), 0)
	local start = os.clock()
	while true do
		local t = math.min((os.clock() - start) / duration, 1)
		-- Bezier cuadratica
		local a = from:Lerp(apex, t)
		local b = apex:Lerp(to, t)
		part.CFrame = CFrame.new(a:Lerp(b, t)) * CFrame.Angles(t * 8, t * 5, 0)
		if t >= 1 then
			break
		end
		RunService.Heartbeat:Wait()
	end
	part.CFrame = CFrame.new(to) * rest
end

local function removeFrom<T>(list: { T }, item: T)
	local i = table.find(list, item)
	if i then
		table.remove(list, i)
	end
end

----------------------------------------------------------------------
-- Aturdimiento (lo leen los enemigos)
----------------------------------------------------------------------

function DefenseService.Stun(model: Model, seconds: number)
	local untilTime = math.max(model:GetAttribute("StunnedUntil") or 0, os.clock() + seconds)
	model:SetAttribute("StunnedUntil", untilTime)

	-- Contorno blanco mientras dura (se ve desde todos los clientes)
	local highlight = model:FindFirstChild("StunHighlight") :: Highlight?
	if not highlight then
		local h = Instance.new("Highlight")
		h.Name = "StunHighlight"
		h.FillColor = Color3.new(1, 1, 1)
		h.FillTransparency = 0.85
		h.OutlineColor = Color3.new(1, 1, 1)
		h.OutlineTransparency = 0
		h.DepthMode = Enum.HighlightDepthMode.Occluded
		h.Parent = model
		highlight = h
	end
	task.delay(seconds, function()
		if model.Parent and highlight and highlight.Parent and os.clock() >= (model:GetAttribute("StunnedUntil") or 0) - 0.05 then
			highlight:Destroy()
		end
	end)
end

function DefenseService.IsStunned(model: Model): boolean
	return (model:GetAttribute("StunnedUntil") or 0) > os.clock()
end

-- EnemyService pasa una funcion que devuelve los enemigos activos.
function DefenseService.SetEnemyProvider(fn: () -> { any })
	enemyProvider = fn
end

-- Enemigos activos (para las armas).
function DefenseService.GetEnemies(): { any }
	return enemyProvider()
end

----------------------------------------------------------------------
-- Zonas de las armas: nube (ciega) y piso mojado (ralentiza)
----------------------------------------------------------------------

local function activeZones(list: { Zone }): { Zone }
	local now = os.clock()
	for i = #list, 1, -1 do
		local zone = list[i]
		if now >= zone.ExpiresAt then
			if zone.Part then
				zone.Part:Destroy()
			end
			table.remove(list, i)
		end
	end
	return list
end

-- Nube que ciega: los enemigos dentro no ven, y nadie ve a quien esta dentro.
function DefenseService.AddSmoke(position: Vector3, radius: number, duration: number, part: BasePart?)
	table.insert(smokes, { Position = position, Radius = radius, ExpiresAt = os.clock() + duration, Part = part })
end

function DefenseService.IsInSmoke(position: Vector3): boolean
	for _, zone in activeZones(smokes) do
		if (position - zone.Position).Magnitude <= zone.Radius then
			return true
		end
	end
	return false
end

-- Zona que ralentiza a los enemigos (multiplicador de velocidad < 1).
function DefenseService.AddSlowZone(position: Vector3, radius: number, multiplier: number, duration: number, part: BasePart?)
	table.insert(slowZones, {
		Position = position,
		Radius = radius,
		ExpiresAt = os.clock() + duration,
		Part = part,
		Multiplier = multiplier,
	})
end

-- Multiplicador de velocidad de un enemigo en `position` (1 = normal).
function DefenseService.GetSpeedFactor(position: Vector3): number
	local factor = 1
	for _, zone in activeZones(slowZones) do
		if flatDistance(position, zone.Position) <= zone.Radius and math.abs(position.Y - zone.Position.Y) < 8 then
			factor = math.min(factor, zone.Multiplier or 1)
		end
	end
	return factor
end

----------------------------------------------------------------------
-- [G] Destello de linterna
----------------------------------------------------------------------

function DefenseService.Flash(player: Player)
	if not canAct(player) then
		return
	end
	local now = serverNow()
	if (player:GetAttribute("FlashReadyAt") or 0) > now then
		return
	end
	local cost = Def.Flash.BatteryCost * (PlayerStats.GetPerk(player, "FlashCostMultiplier") or 1)
	if not FlashlightService.TrySpendBattery(player, cost) then
		notify(player, string.format("El destello necesita %d de batería.", math.ceil(cost)), "bad")
		return
	end
	local cooldown = Def.Flash.Cooldown * (PlayerStats.GetPerk(player, "FlashCooldownMultiplier") or 1)
	player:SetAttribute("FlashReadyAt", now + cooldown)
	FlashlightService.Burst(player, 0.25)

	local range = Config.Flashlight.Range * Def.Flash.RangeMultiplier
	for _, enemy in enemyProvider() do
		local model = enemy.Model
		if model and model.Parent then
			-- GetFlashPoint: punto a alumbrar si no es el centro (p. ej. el lente de una camara)
			local position = if enemy.GetFlashPoint then enemy:GetFlashPoint() else model:GetPivot().Position
			if FlashlightService.InCone(player, position, range, Def.Flash.ExtraHalfAngle) then
				if enemy.OnFlash then
					local ok, err = pcall(enemy.OnFlash, enemy, player)
					if not ok then
						warn("[DefenseService] OnFlash:", err)
					end
				else
					DefenseService.Stun(model, Def.Flash.StunSeconds)
				end
			end
		end
	end
end

----------------------------------------------------------------------
-- [Q] Habilidad de clase: Porrazo del Guardia
----------------------------------------------------------------------

local function shockwave(position: Vector3, look: Vector3)
	local ring = prop({
		Name = "Shove",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.2, 2, 2),
		CFrame = CFrame.new(position + look * 2) * CFrame.Angles(0, 0, math.rad(90)),
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(120, 170, 255),
		Transparency = 0.3,
	})
	ring.Parent = getPropsFolder()
	local info = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(ring, info, { Size = Vector3.new(0.2, Def.Shove.Range * 1.6, Def.Shove.Range * 1.6), Transparency = 1 })
		:Play()
	task.delay(0.35, function()
		ring:Destroy()
	end)
end

-- Empuja y aturde a los enemigos de enfrente. strength = { StunSeconds, Distance }
-- (el Porrazo usa Config.Defense.Shove; el Trapeador, uno mas debil). Devuelve los golpeados.
function DefenseService.Push(player: Player, range: number, strength: { StunSeconds: number, Distance: number }): number
	local root = getRoot(player)
	local look = root and flatLook(root)
	if not root or not look then
		return 0
	end
	shockwave(root.Position, look)
	local hits = 0
	for _, enemy in enemyProvider() do
		local model = enemy.Model
		if model and model.Parent then
			local offset = model:GetPivot().Position - root.Position
			local flat = Vector3.new(offset.X, 0, offset.Z)
			local dist = flat.Magnitude
			-- Delante del jugador (o pegado a el)
			if dist <= range and (dist < 2 or look:Dot(flat.Unit) >= 0.2) then
				hits += 1
				local direction = if dist > 0.01 then flat.Unit else look
				if enemy.OnShove then
					local ok, err = pcall(enemy.OnShove, enemy, player, direction, strength)
					if not ok then
						warn("[DefenseService] OnShove:", err)
					end
				else
					DefenseService.Stun(model, strength.StunSeconds)
				end
			end
		end
	end
	return hits
end

function DefenseService.UseClassAbility(player: Player)
	if not PlayerStats.GetPerk(player, "Shove") or not canAct(player) then
		return
	end
	local now = serverNow()
	if (player:GetAttribute("AbilityReadyAt") or 0) > now then
		return
	end
	if not getRoot(player) then
		return
	end
	player:SetAttribute("AbilityReadyAt", now + Def.Shove.Cooldown)
	if DefenseService.Push(player, Def.Shove.Range, Def.Shove) == 0 then
		notify(player, "El porrazo no alcanzó a nadie.")
	end
end

-- Para las armas: puede actuar (vivo y no escondido).
function DefenseService.CanAct(player: Player): boolean
	return canAct(player)
end

----------------------------------------------------------------------
-- Bengala
----------------------------------------------------------------------

function DefenseService.ThrowFlare(player: Player): boolean
	if not canAct(player) then
		return false
	end
	local origin, ground = throwTarget(player, Def.Flare.ThrowRange)
	if not origin or not ground then
		return false
	end

	local part = prop({
		Name = "Flare",
		Size = Vector3.new(0.4, 1.4, 0.4),
		CFrame = CFrame.new(origin),
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(255, 60, 40),
	})
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 90, 60)
	light.Range = Def.Flare.Radius + 6
	light.Brightness = 2.5
	light.Shadows = true
	light.Parent = part
	local sparks = Instance.new("ParticleEmitter")
	sparks.Color = ColorSequence.new(Color3.fromRGB(255, 120, 60), Color3.fromRGB(255, 220, 120))
	sparks.LightEmission = 1
	sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 0) })
	sparks.Lifetime = NumberRange.new(0.3, 0.7)
	sparks.Rate = 40
	sparks.Speed = NumberRange.new(3, 6)
	sparks.SpreadAngle = Vector2.new(40, 40)
	sparks.Acceleration = Vector3.new(0, -12, 0)
	sparks.Parent = part
	local smoke = Instance.new("ParticleEmitter")
	smoke.Color = ColorSequence.new(Color3.fromRGB(255, 120, 110))
	smoke.LightEmission = 0.3
	smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 4) })
	smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1) })
	smoke.Lifetime = NumberRange.new(2, 3)
	smoke.Rate = 6
	smoke.Speed = NumberRange.new(1, 2)
	smoke.Acceleration = Vector3.new(0, 1.5, 0)
	smoke.Parent = part
	part.Parent = getPropsFolder()

	task.spawn(function()
		-- Tumbada en el suelo (su eje largo es Y)
		flyTo(part, origin, ground, 0.45, CFrame.new(0, 0.2, 0) * CFrame.Angles(0, 0, math.rad(90)))
		if not part.Parent then
			return
		end
		local flare: Flare = { Position = ground, ExpiresAt = os.clock() + Def.Flare.Duration, Part = part }
		table.insert(flares, flare)

		-- Parpadeo suave y apagado gradual en los ultimos 2 segundos
		while part.Parent and os.clock() < flare.ExpiresAt do
			local remaining = flare.ExpiresAt - os.clock()
			local fade = math.clamp(remaining / 2, 0, 1)
			light.Brightness = (2.2 + math.random() * 0.8) * fade
			task.wait(0.08)
		end
		removeFrom(flares, flare)
		part:Destroy()
	end)
	return true
end

-- Bengala activa cuyo radio (+ margen) incluye `position` (distancia horizontal).
function DefenseService.GetFlareNear(position: Vector3, margin: number?): Vector3?
	local best, bestDist = nil, math.huge
	for _, flare in flares do
		local d = flatDistance(position, flare.Position)
		if d <= Def.Flare.Radius + (margin or 0) and math.abs(position.Y - flare.Position.Y) < 20 and d < bestDist then
			best, bestDist = flare.Position, d
		end
	end
	return best
end

-- Apaga las bengalas cuya posicion cumpla `filter` (evento Alarma de incendio). Devuelve cuantas.
function DefenseService.ExtinguishFlares(filter: (Vector3) -> boolean): number
	local count = 0
	for i = #flares, 1, -1 do
		local flare = flares[i]
		if filter(flare.Position) then
			table.remove(flares, i)
			flare.Part:Destroy() -- su bucle de parpadeo termina al no tener padre
			count += 1
		end
	end
	return count
end

function DefenseService.IsInFlare(position: Vector3): boolean
	return DefenseService.GetFlareNear(position) ~= nil
end

----------------------------------------------------------------------
-- Petardo
----------------------------------------------------------------------

function DefenseService.ThrowFirecracker(player: Player): boolean
	if not canAct(player) then
		return false
	end
	local origin, ground = throwTarget(player, Def.Firecracker.ThrowRange)
	if not origin or not ground then
		return false
	end

	local part = prop({
		Name = "Firecracker",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1, 0.4, 0.4),
		CFrame = CFrame.new(origin),
		Material = Enum.Material.SmoothPlastic,
		Color = Color3.fromRGB(200, 30, 30),
	})
	local fuse = Instance.new("ParticleEmitter")
	fuse.Color = ColorSequence.new(Color3.fromRGB(255, 200, 80))
	fuse.LightEmission = 1
	fuse.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 0) })
	fuse.Lifetime = NumberRange.new(0.2, 0.4)
	fuse.Rate = 30
	fuse.Speed = NumberRange.new(2, 4)
	fuse.SpreadAngle = Vector2.new(60, 60)
	fuse.Parent = part
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 210, 120)
	light.Range = 4
	light.Brightness = 1
	light.Parent = part
	part.Parent = getPropsFolder()

	task.spawn(function()
		flyTo(part, origin, ground, 0.5, CFrame.new(0, 0.2, 0))
		if not part.Parent then
			return
		end
		local now = os.clock()
		local lure: Lure = {
			Position = ground,
			ActiveFrom = now + Def.Firecracker.Fuse,
			ExpiresAt = now + Def.Firecracker.Fuse + Def.Firecracker.Duration,
			Part = part,
		}
		table.insert(lures, lure)

		task.wait(Def.Firecracker.Fuse)
		-- Traqueteo: destellos y chispas hasta que se acaba
		fuse.Rate = 0
		local burst = Instance.new("ParticleEmitter")
		burst.Color = ColorSequence.new(Color3.fromRGB(255, 230, 150), Color3.fromRGB(255, 120, 40))
		burst.LightEmission = 1
		burst.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
		burst.Lifetime = NumberRange.new(0.2, 0.5)
		burst.Rate = 0
		burst.Speed = NumberRange.new(8, 16)
		burst.SpreadAngle = Vector2.new(180, 180)
		burst.Parent = part
		while part.Parent and os.clock() < lure.ExpiresAt do
			burst:Emit(math.random(6, 14))
			light.Range = 14
			light.Brightness = 3
			task.wait(0.06)
			light.Brightness = 0.2
			task.wait(math.random(10, 35) / 100)
		end
		removeFrom(lures, lure)
		part:Destroy()
	end)
	return true
end

-- Senuelo generico (p. ej. una alarma de la mision SilenceAlarm). Devuelve una funcion
-- para quitarlo antes de tiempo.
function DefenseService.AddLure(position: Vector3, seconds: number, radius: number?): () -> ()
	local now = os.clock()
	local lure: Lure = { Position = position, ActiveFrom = now, ExpiresAt = now + seconds, Radius = radius }
	table.insert(lures, lure)
	return function()
		removeFrom(lures, lure)
	end
end

-- Senuelo activo (petardo, alarma...) mas cercano dentro de su radio, o nil.
function DefenseService.GetLure(position: Vector3): Vector3?
	local now = os.clock()
	local best, bestDist = nil, math.huge
	for _, lure in lures do
		if now >= lure.ActiveFrom and now < lure.ExpiresAt then
			local d = (position - lure.Position).Magnitude
			if d <= (lure.Radius or Def.Firecracker.Radius) and d < bestDist then
				best, bestDist = lure.Position, d
			end
		end
	end
	return best
end

----------------------------------------------------------------------
-- Escondites
----------------------------------------------------------------------

-- Donde queda el jugador al salir (delante de la cara Front del escondite).
local function exitCFrame(spot: BasePart): CFrame
	return spot.CFrame * CFrame.new(0, -spot.Size.Y / 2 + 3, -(spot.Size.Z / 2 + 2.5))
end

function DefenseService.IsHidden(player: Player): boolean
	return hiding[player] ~= nil
end

-- Hacia donde van los enemigos para alcanzar a un jugador (si esta escondido: a la puerta).
function DefenseService.GetTargetPosition(player: Player, root: BasePart): Vector3
	local entry = hiding[player]
	if entry then
		return exitCFrame(entry.Spot).Position
	end
	return root.Position
end

function DefenseService.Unhide(player: Player, message: string?, kind: string?)
	local entry = hiding[player]
	if not entry then
		return
	end
	hiding[player] = nil
	if occupants[entry.Spot] == player then
		occupants[entry.Spot] = nil
		entry.Spot:SetAttribute("Occupied", nil)
	end
	player:SetAttribute("Hidden", nil)
	player:SetAttribute("HiddenUntil", nil)
	player:SetAttribute("HideReadyAt", serverNow() + Def.Hiding.Cooldown)

	local character = entry.Character
	local root = character.Parent and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		root.Anchored = false
		if entry.Spot.Parent then
			character:PivotTo(exitCFrame(entry.Spot))
		end
	end
	if message then
		notify(player, message, kind)
	end
end

-- Un enemigo te alcanzo dentro del escondite: te saca a la fuerza.
function DefenseService.ForceOut(player: Player)
	DefenseService.Unhide(player, "¡Te encontraron!", "bad")
end

function DefenseService.Hide(player: Player, spot: BasePart)
	if hiding[player] or not isAlive(player) then
		return
	end
	if (player:GetAttribute("HideReadyAt") or 0) > serverNow() then
		notify(player, "Espera un momento antes de volver a esconderte.")
		return
	end
	if occupants[spot] then
		notify(player, "Ya hay alguien escondido ahí.")
		return
	end
	local character = player.Character
	local root = getRoot(player)
	if not character or not root or (root.Position - spot.Position).Magnitude > Def.Hiding.PromptDistance + spot.Size.Magnitude / 2 + 4 then
		return
	end

	hiding[player] = { Spot = spot, Character = character, Until = os.clock() + Def.Hiding.MaxSeconds }
	occupants[spot] = player
	spot:SetAttribute("Occupied", true)

	FlashlightService.SetOn(player, false)
	root.AssemblyLinearVelocity = Vector3.zero
	root.Anchored = true
	character:PivotTo(spot.CFrame * CFrame.new(0, -spot.Size.Y / 2 + 3, 0))
	player:SetAttribute("Hidden", true)
	player:SetAttribute("HiddenUntil", serverNow() + Def.Hiding.MaxSeconds)

	DefenseService.PlayerHid:Fire(player)
end

local function setupSpot(spot: Instance)
	if not spot:IsA("BasePart") or spot:FindFirstChild("HidePrompt") then
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "HidePrompt"
	prompt.ActionText = "Esconderse"
	prompt.ObjectText = spot:GetAttribute("DisplayName") or "Escondite"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = Def.Hiding.PromptDistance
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.Parent = spot
	prompt.Triggered:Connect(function(player)
		local entry = hiding[player]
		if entry then
			if entry.Spot == spot then
				DefenseService.Unhide(player)
			end
			return
		end
		DefenseService.Hide(player, spot)
	end)
end

----------------------------------------------------------------------
-- Limpieza y arranque
----------------------------------------------------------------------

-- Fin de la noche: quitar bengalas, petardos, nubes y carteles.
function DefenseService.ClearAll()
	for _, flare in flares do
		flare.Part:Destroy()
	end
	for _, lure in lures do
		if lure.Part then
			lure.Part:Destroy()
		end
	end
	flares = {}
	lures = {}
	-- Nubes y carteles de piso mojado
	for _, list in { smokes, slowZones } do
		for _, zone in list do
			if zone.Part then
				zone.Part:Destroy()
			end
		end
		table.clear(list)
	end
end

function DefenseService.Start()
	for _, spot in CollectionService:GetTagged(Tags.HidingSpot) do
		setupSpot(spot)
	end
	CollectionService:GetInstanceAddedSignal(Tags.HidingSpot):Connect(setupSpot)

	Remotes.event("UseFlash").OnServerEvent:Connect(DefenseService.Flash)
	Remotes.event("UseClassAbility").OnServerEvent:Connect(DefenseService.UseClassAbility)
	Remotes.event("RequestUnhide").OnServerEvent:Connect(function(player: Player)
		DefenseService.Unhide(player)
	end)

	local function setup(player: Player)
		player.CharacterAdded:Connect(function(character)
			local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
			if humanoid then
				-- Si caes escondido, el cuerpo queda delante del escondite (para que te revivan)
				humanoid.Died:Connect(function()
					DefenseService.Unhide(player)
				end)
			end
		end)
		player.CharacterRemoving:Connect(function()
			DefenseService.Unhide(player)
		end)
	end
	Players.PlayerAdded:Connect(setup)
	for _, player in Players:GetPlayers() do
		setup(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		DefenseService.Unhide(player)
	end)

	-- Tiempo maximo escondido
	task.spawn(function()
		while true do
			task.wait(0.5)
			local now = os.clock()
			for player, entry in hiding do
				if now >= entry.Until then
					DefenseService.Unhide(player, "Te falta el aire: sales del escondite.", "bad")
				end
			end
		end
	end)
end

return DefenseService
