-- Utilidades compartidas por todos los enemigos.
--
-- Los enemigos son modelos anclados que se mueven con PivotTo (cinematicos):
-- no se atascan con la fisica y su comportamiento es 100% del servidor.
--
-- Plantillas propias: si existe ServerStorage.EnemyTemplates.<Nombre> (un
-- Model con PrimaryPart), se usa en vez del modelo de prueba hecho con bloques.

local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Config = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Config)
local PlayerStats = require(ServerScriptService:WaitForChild("Server"):WaitForChild("PlayerStats"))
local LightService = require(ServerScriptService:WaitForChild("Server"):WaitForChild("LightService"))
local DefenseService = require(ServerScriptService:WaitForChild("Server"):WaitForChild("DefenseService"))

local Common = {}

----------------------------------------------------------------------
-- Jugadores
----------------------------------------------------------------------

function Common.isAlive(player: Player): boolean
	if player:GetAttribute("Alive") ~= true then
		return false
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0 and character:FindFirstChild("HumanoidRootPart") ~= nil
end

function Common.getAlivePlayers(): { Player }
	local list = {}
	for _, player in Players:GetPlayers() do
		if Common.isAlive(player) then
			table.insert(list, player)
		end
	end
	return list
end

function Common.getRoot(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

-- Jugador vivo mas cercano (opcionalmente filtrado). Devuelve (player, root, distancia).
function Common.nearestAlive(position: Vector3, filter: ((Player, BasePart) -> boolean)?)
	local best, bestRoot, bestDist = nil, nil, math.huge
	for _, player in Common.getAlivePlayers() do
		local root = Common.getRoot(player)
		if root and (not filter or filter(player, root)) then
			local d = (root.Position - position).Magnitude
			if d < bestDist then
				best, bestRoot, bestDist = player, root, d
			end
		end
	end
	return best, bestRoot, bestDist
end

function Common.damage(player: Player, amount: number)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		-- Si estaba escondido (y el enemigo lo vio entrar), lo saca a la fuerza
		if DefenseService.IsHidden(player) then
			DefenseService.ForceOut(player)
		end
		humanoid:TakeDamage(amount)
	end
end

-- Hacia donde ir para alcanzar a un jugador (si esta escondido: a la puerta del escondite).
function Common.targetPosition(player: Player, root: BasePart): Vector3
	return DefenseService.GetTargetPosition(player, root)
end

----------------------------------------------------------------------
-- Defensas de los jugadores (DefenseService)
----------------------------------------------------------------------

function Common.isStunned(model: Model): boolean
	return DefenseService.IsStunned(model)
end

-- Empuja al enemigo `distance` studs en horizontal sin atravesar paredes
-- (deslizamiento corto). Lo usa el Porrazo del Guardia.
function Common.knockback(model: Model, direction: Vector3, distance: number)
	local flat = Vector3.new(direction.X, 0, direction.Z)
	if flat.Magnitude < 0.01 then
		return
	end
	flat = flat.Unit
	local from = model:GetPivot().Position
	local hit = Workspace:Raycast(from, flat * distance, Common.raycastParams())
	local travel = if hit then math.max(0, (hit.Position - from).Magnitude - 1.5) else distance
	local to = from + flat * travel
	task.spawn(function()
		local duration = 0.2
		local start = os.clock()
		while model.Parent do
			local t = math.min((os.clock() - start) / duration, 1)
			local pos = from:Lerp(to, 1 - (1 - t) ^ 2)
			model:PivotTo(CFrame.lookAt(pos, pos - flat)) -- mirando hacia quien lo empujo
			if t >= 1 then
				break
			end
			RunService.Heartbeat:Wait()
		end
	end)
end

----------------------------------------------------------------------
-- Rayos
----------------------------------------------------------------------

function Common.getEnemiesFolder(): Folder
	local folder = Workspace:FindFirstChild("Enemies")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Enemies"
		folder.Parent = Workspace
	end
	return folder
end

-- Parametros que ignoran personajes, enemigos y objetos de mision.
function Common.raycastParams(): RaycastParams
	local exclude = { Common.getEnemiesFolder() }
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(exclude, player.Character)
		end
	end
	local props = Workspace:FindFirstChild("MissionProps")
	if props then
		table.insert(exclude, props)
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclude
	params.IgnoreWater = true -- el agua de las fuentes no tapa la vision ni es "suelo"
	return params
end

function Common.lineOfSight(from: Vector3, to: Vector3): boolean
	return Workspace:Raycast(from, to - from, Common.raycastParams()) == nil
end

----------------------------------------------------------------------
-- Modelos
----------------------------------------------------------------------

function Common.part(props): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props do
		p[k] = v
	end
	return p
end

-- Crea un Model vacio con una parte raiz invisible del alto indicado.
-- El pivote del modelo queda en el centro de esa raiz.
function Common.newModel(name: string, height: number): (Model, Part)
	local model = Instance.new("Model")
	model.Name = name
	local root = Common.part({
		Name = "Root",
		Size = Vector3.new(2, height, 2),
		Transparency = 1,
		CanQuery = false,
		CFrame = CFrame.new(),
	})
	root.Parent = model
	model.PrimaryPart = root
	return model, root
end

-- Ancla y prepara todas las partes; los caminantes no bloquean su propio pathfinding.
function Common.prepareModel(model: Model)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanTouch = false
			local modifier = Instance.new("PathfindingModifier")
			modifier.PassThrough = true
			modifier.Parent = d
		end
	end
end

function Common.getTemplate(name: string): Model?
	local folder = ServerStorage:FindFirstChild("EnemyTemplates")
	local template = folder and folder:FindFirstChild(name)
	if template and template:IsA("Model") and template.PrimaryPart then
		return template:Clone()
	end
	return nil
end

function Common.getHeight(model: Model): number
	local _, size = model:GetBoundingBox()
	return size.Y
end

----------------------------------------------------------------------
-- Movimiento
----------------------------------------------------------------------

local Mover = {}
Mover.__index = Mover

-- Diferencia de altura (studs) a partir de la cual el objetivo esta en otro piso.
local OTHER_FLOOR = 8
-- Caida maxima que un caminante acepta al avanzar (evita tirarse por el atrio).
local MAX_DROP = 4
-- Velocidad vertical de los fantasmas al cambiar de piso (studs/s).
local GHOST_CLIMB_SPEED = 7

-- Altura del suelo bajo un punto (o nil).
function Common.floorBelow(position: Vector3, maxDistance: number?): number?
	local hit = Workspace:Raycast(position + Vector3.new(0, 1, 0), Vector3.new(0, -(maxDistance or 40), 0), Common.raycastParams())
	return hit and hit.Position.Y
end

-- opts: { Speed, Height, Ghost (atraviesa paredes, flota a HoverY), HoverY,
--         HoverOffset (fantasmas: altura sobre el suelo del destino; asi cambian de piso) }
function Common.newMover(model: Model, opts)
	local self = setmetatable({}, Mover)
	self.Model = model
	self.Speed = opts.Speed
	self.Height = opts.Height
	self.Ghost = opts.Ghost == true
	self.HoverY = opts.HoverY
	self.HoverOffset = opts.HoverOffset
	self.ForcePath = false
	self.Waypoints = {}
	self.Index = 1
	self.Computing = false
	self.LastCompute = 0
	self.Destroyed = false
	if not self.Ghost then
		self.Path = PathfindingService:CreatePath({
			AgentRadius = 1.5, -- cabe por las escaleras mecanicas (4.2 de ancho)
			AgentHeight = math.max(self.Height, 5),
			AgentCanJump = false,
			AgentCanClimb = false,
		})
	end
	return self
end

function Mover:GetPosition(): Vector3
	return self.Model:GetPivot().Position
end

function Mover:Clear()
	self.Waypoints = {}
	self.Index = 1
end

function Mover:HasPath(): boolean
	return self.Waypoints[self.Index] ~= nil
end

-- Fija el destino. Si hay linea directa va recto; si no, calcula una ruta.
function Mover:MoveTowards(target: Vector3)
	if self.Ghost then
		self.Waypoints = { target }
		self.Index = 1
		-- Atraviesa suelos: se coloca a su altura sobre el piso del destino
		if self.HoverOffset then
			local floorY = Common.floorBelow(target + Vector3.new(0, 2, 0))
			if floorY then
				self.HoverY = floorY + self.HoverOffset
			end
		end
		return
	end

	local from = self:GetPosition()
	local feetY = from.Y - self.Height / 2
	-- Mismo piso y a la vista: recto. Otro piso (o venia de un borde): ruta con escaleras.
	local sameFloor = math.abs(target.Y - feetY) < OTHER_FLOOR
	if sameFloor and not self.ForcePath and Common.lineOfSight(from, Vector3.new(target.X, from.Y, target.Z)) then
		self.Waypoints = { target }
		self.Index = 1
		return
	end

	if self.Computing or os.clock() - self.LastCompute < 0.75 then
		return
	end
	self.Computing = true
	self.LastCompute = os.clock()
	task.spawn(function()
		local groundFrom = from - Vector3.new(0, self.Height / 2 - 0.5, 0)
		local ok = pcall(function()
			self.Path:ComputeAsync(groundFrom, target)
		end)
		self.Computing = false
		if self.Destroyed then
			return
		end
		if ok and self.Path.Status == Enum.PathStatus.Success then
			local list = {}
			for i, wp in self.Path:GetWaypoints() do
				if i > 1 then
					table.insert(list, wp.Position)
				end
			end
			self.Waypoints = list
			self.Index = 1
			self.ForcePath = false
			self.FailCount = 0
		else
			-- Sin ruta (p. ej. aparecio dentro de un mueble): tras 2 fallos da unos pasos
			-- en una direccion al azar para salir y vuelve a intentarlo
			self.FailCount = (self.FailCount or 0) + 1
			if self.FailCount >= 2 then
				self.FailCount = 0
				local angle = math.random() * math.pi * 2
				self.Waypoints = { from + Vector3.new(math.cos(angle), 0, math.sin(angle)) * 5 }
				self.Index = 1
			end
		end
	end)
end

-- Avanza hacia el siguiente punto. Devuelve true si se movio.
function Mover:Step(dt: number): boolean
	local wp = self.Waypoints[self.Index]
	if not wp then
		-- Fantasma ya en su X/Z pero aun no a la altura de su piso: termina de subir/bajar
		if self.Ghost and self.HoverY then
			local pos = self:GetPosition()
			local diff = self.HoverY - pos.Y
			if math.abs(diff) > 0.05 then
				local maxStep = GHOST_CLIMB_SPEED * dt
				self.Model:PivotTo(self.Model:GetPivot() + Vector3.new(0, math.clamp(diff, -maxStep, maxStep), 0))
				return true
			end
		end
		return false
	end

	local pos = self:GetPosition()
	local flat = Vector3.new(wp.X - pos.X, 0, wp.Z - pos.Z)
	local dist = flat.Magnitude
	if dist < 0.6 then
		self.Index += 1
		return self:Step(dt)
	end

	local dir = flat / dist
	-- Cartel de piso mojado: mas lento dentro de su radio
	local speed = self.Speed * DefenseService.GetSpeedFactor(pos)
	local newPos = pos + dir * math.min(dist, speed * dt)

	local y
	if self.Ghost then
		-- Sube o baja suavemente hasta su altura (cambia de piso atravesando el suelo)
		local goal = self.HoverY or pos.Y
		local maxStep = GHOST_CLIMB_SPEED * dt
		y = pos.Y + math.clamp(goal - pos.Y, -maxStep, maxStep)
	else
		local params = Common.raycastParams()
		local feetY = pos.Y - self.Height / 2
		local function ground(p: Vector3): RaycastResult?
			return Workspace:Raycast(p + Vector3.new(0, 1, 0), Vector3.new(0, -(self.Height + 6), 0), params)
		end
		local function safe(h: RaycastResult?): boolean
			return h ~= nil and feetY - h.Position.Y <= MAX_DROP
		end
		local hit = ground(newPos)
		if not safe(hit) then
			-- Delante hay un vacio (el atrio, el borde de una escalera): probar a deslizarse
			-- por un solo eje (las rutas rozan los extremos de los barandales)
			local slid = false
			for _, alt in { Vector3.new(newPos.X, pos.Y, pos.Z), Vector3.new(pos.X, pos.Y, newPos.Z) } do
				if (alt - pos).Magnitude > 0.01 then
					local h2 = ground(alt)
					if safe(h2) then
						newPos, hit, slid = alt, h2, true
						break
					end
				end
			end
			if not slid then
				-- Retrocede a un punto seguro reciente y recalcula la ruta desde alli
				self:Clear()
				self.ForcePath = true
				local back = self.SafePrev or self.SafePos
				if back and (back - pos).Magnitude > 0.5 then
					self.Waypoints = { back }
				end
				return false
			end
		end
		y = (hit :: RaycastResult).Position.Y + self.Height / 2
		-- Historial de posiciones seguras (para poder retroceder)
		local now = os.clock()
		if now - (self.SafeAt or 0) > 0.4 then
			self.SafePrev = self.SafePos
			self.SafePos = pos
			self.SafeAt = now
		end
	end

	newPos = Vector3.new(newPos.X, y, newPos.Z)
	self.Model:PivotTo(CFrame.lookAt(newPos, newPos + dir))
	return true
end

function Mover:Destroy()
	self.Destroyed = true
end

----------------------------------------------------------------------
-- Deteccion
----------------------------------------------------------------------
-- Cada enemigo tiene que "notar" a un jugador durante un tiempo antes de
-- perseguirlo, y lo recuerda unos segundos tras perderlo de vista.
-- La clase Sombra (Perk DetectionDelay) tarda mas en ser detectada.

-- Escondites: si un enemigo te estaba persiguiendo y te percibia justo al entrar,
-- sabe donde estas (Watched) e ira a sacarte. Si no, te pierde por completo.

local Awareness = {}
Awareness.__index = Awareness

local awarenessRegistry = setmetatable({}, { __mode = "k" })

function Common.newAwareness(ctx)
	local self = setmetatable({ Ctx = ctx, Level = {}, KnownAt = {}, LastSensed = {}, Watched = {} }, Awareness)
	awarenessRegistry[self] = true
	return self
end

DefenseService.PlayerHid:Connect(function(player: Player)
	local now = os.clock()
	for awareness in awarenessRegistry do
		local sensed = awareness.LastSensed[player]
		local known = awareness.KnownAt[player]
		if sensed and known and now - sensed <= Config.Defense.Hiding.SeenEnteringWindow
			and now - known <= Config.Detection.Memory then
			awareness.Watched[player] = true
		else
			awareness.Watched[player] = nil
			awareness.Level[player] = 0
			awareness.KnownAt[player] = nil
		end
	end
end)

function Awareness:DetectTime(player: Player): number
	local delay = PlayerStats.GetPerk(player, "DetectionDelay") or 1
	return Config.Detection.BaseTime * delay / self.Ctx.Difficulty.DetectionMultiplier
end

-- senses(player, root) -> boolean: si el enemigo percibe al jugador ahora mismo.
-- Devuelve (player, root, distancia, posicion objetivo) del objetivo detectado mas
-- cercano, o nil. Hay que moverse hacia la posicion objetivo (no hacia root):
-- si el jugador esta escondido es la puerta del escondite.
function Awareness:Update(dt: number, position: Vector3, senses: (Player, BasePart) -> boolean)
	local now = os.clock()
	local best, bestRoot, bestDist, bestPos = nil, nil, math.huge, nil
	for _, player in Common.getAlivePlayers() do
		local root = Common.getRoot(player)
		if root then
			if DefenseService.IsHidden(player) then
				if self.Watched[player] then
					self.KnownAt[player] = now -- te vio entrar: sabe donde estas
				else
					self.Level[player] = 0
					self.KnownAt[player] = nil
				end
			else
				self.Watched[player] = nil
				-- Nube del extintor: no ve desde dentro ni a quien esta dentro
				local blinded = DefenseService.IsInSmoke(position) or DefenseService.IsInSmoke(root.Position)
				if not blinded and senses(player, root) then
					self.LastSensed[player] = now
					local level = (self.Level[player] or 0) + dt / self:DetectTime(player)
					self.Level[player] = math.min(level, 1)
					if level >= 1 then
						self.KnownAt[player] = now
					end
				else
					self.Level[player] = math.max(0, (self.Level[player] or 0) - dt * 0.5)
				end
			end
			local knownAt = self.KnownAt[player]
			if knownAt and now - knownAt <= Config.Detection.Memory then
				local targetPos = Common.targetPosition(player, root)
				local d = (targetPos - position).Magnitude
				if d < bestDist then
					best, bestRoot, bestDist, bestPos = player, root, d, targetPos
				end
			end
		end
	end
	return best, bestRoot, bestDist, bestPos
end

-- Sentido estandar: te ve si hay linea de vision a menos de SenseRange,
-- o te siente si estas muy cerca.
function Common.canSee(eye: Vector3, root: BasePart): boolean
	local d = (root.Position - eye).Magnitude
	if d <= Config.Detection.CloseRange then
		return true
	end
	return d <= Config.Detection.SenseRange and Common.lineOfSight(eye, root.Position)
end

-- Punto al azar para patrullar: un punto libre del suelo de una zona al azar.
-- (El centro exacto puede caer sobre un mueble y entonces no hay ruta; con 2 plantas
-- tambien hay que bajar hasta el suelo de esa zona, no hasta el de otra planta.)
function Common.randomPatrolPoint(): Vector3?
	local zones = LightService.GetZones()
	if #zones == 0 then
		return nil
	end
	local zoneName = zones[math.random(1, #zones)]
	local part = LightService.GetZonePart(zoneName)
	if part then
		local params = Common.raycastParams()
		local floorY = part.Position.Y - part.Size.Y / 2
		for _ = 1, 6 do
			local rel = Vector3.new((math.random() - 0.5) * part.Size.X * 0.8, 0, (math.random() - 0.5) * part.Size.Z * 0.8)
			local top = (part.CFrame * CFrame.new(rel)).Position + Vector3.new(0, part.Size.Y / 2 - 1, 0)
			local hit = Workspace:Raycast(top, Vector3.new(0, -(part.Size.Y + 2), 0), params)
			-- Vale si cae en el suelo de la zona (no encima de una mesa, estanteria...)
			if hit and math.abs(hit.Position.Y - floorY) < 1.5 then
				return hit.Position
			end
		end
	end
	local center = LightService.GetZoneCenter(zoneName)
	if not center then
		return nil
	end
	local hit = Workspace:Raycast(center, Vector3.new(0, -100, 0), Common.raycastParams())
	return if hit then hit.Position else center
end

return Common
