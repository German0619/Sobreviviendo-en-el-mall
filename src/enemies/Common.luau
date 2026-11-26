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
local BestiaryService = require(ServerScriptService:WaitForChild("Server"):WaitForChild("BestiaryService"))

local Common = {}

-- Dificultad de la noche actual (Config.getDifficulty; la pone EnemyService.StartNight).
-- Aqui se usan DamageMultiplier (Common.damage) y SenseMultiplier (Common.canSee).
local difficulty = { DamageMultiplier = 1, SenseMultiplier = 1 }

function Common.SetDifficulty(d: { DamageMultiplier: number?, SenseMultiplier: number? })
	difficulty = {
		DamageMultiplier = d.DamageMultiplier or 1,
		SenseMultiplier = d.SenseMultiplier or 1,
	}
end

----------------------------------------------------------------------
-- Jugadores
----------------------------------------------------------------------

-- Para los enemigos: vivo y no protegido. Quien acaba de revivir pagando (ReviveService,
-- atributo ProtectedUntil) no existe para ellos durante unos segundos.
function Common.isAlive(player: Player): boolean
	if player:GetAttribute("Alive") ~= true then
		return false
	end
	local protectedUntil = player:GetAttribute("ProtectedUntil")
	if type(protectedUntil) == "number" and protectedUntil > Workspace:GetServerTimeNow() then
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
		-- Maldito por el maletin perdido (atributo Cursed): recibe mas dano (Config.Curse)
		local curse = if player:GetAttribute("Cursed") == true then Config.Curse.DamageMultiplier else 1
		humanoid:TakeDamage(amount * difficulty.DamageMultiplier * curse)
	end
end

-- El jugador se topo con esta entidad: entrada del bestiario (Config.Bestiary). Las que
-- tienen cuerpo ya se descubren solas al verlas; esto es para las que se disfrazan o no
-- tienen cuerpo (Eco, Mimico, Megafonia), al sufrirlas.
function Common.discover(player: Player, entityId: string)
	BestiaryService.Discover(player, entityId)
end

-- Animacion de ataque del enemigo (EnemyAnimator la lee del atributo AttackAt: zarpazo,
-- agarre, salto... segun su estilo en Config.EnemyAnimation). Llamarla al golpear.
function Common.playAttack(model: Model)
	model:SetAttribute("AttackAt", os.clock())
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

-- Pieza a la que se suelda un detalle con Follow = `wanted`: la mas cercana con ese
-- nombre, o del tipo "Arm" / "Leg" (como las reconoce EnemyAnimator).
local function followTarget(parts: { BasePart }, detail: BasePart, wanted: string): BasePart?
	local best, bestDist = nil, math.huge
	for _, p in parts do
		local name = p.Name
		local matches = name == wanted
			or (wanted == "Arm" and string.find(name, "Arm") ~= nil)
			or (wanted == "Leg" and string.find(name, "Leg") ~= nil and name ~= "LowerLeg")
		if matches then
			local d = (p.Position - detail.Position).Magnitude
			if d < bestDist then
				best, bestDist = p, d
			end
		end
	end
	return best
end

-- Ancla y prepara todas las partes; los caminantes no bloquean su propio pathfinding.
--
-- Detalles (botones, dedos, costuras...): las piezas con el atributo Detail = true o
-- Follow = "<pieza>" | "Arm" | "Leg" NO se anclan: se sueldan a la raiz (Detail) o a esa
-- pieza (Follow) y se mueven con ella. Asi el servidor solo mueve (y la red solo envia)
-- las piezas principales, aunque el modelo tenga muchos detalles.
function Common.prepareModel(model: Model)
	local main: { BasePart } = {}
	local details: { BasePart } = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanTouch = false
			if d:GetAttribute("Detail") == true or type(d:GetAttribute("Follow")) == "string" then
				table.insert(details, d)
			else
				d.Anchored = true
				table.insert(main, d)
			end
			if not d:FindFirstChildOfClass("PathfindingModifier") then
				local modifier = Instance.new("PathfindingModifier")
				modifier.PassThrough = true
				modifier.Parent = d
			end
		end
	end
	local root = model.PrimaryPart
	for _, d in details do
		if d:FindFirstChild("DetailWeld") then
			continue -- ya soldado (un modelo del mapa que vuelve a cobrar vida)
		end
		local follow = d:GetAttribute("Follow")
		local target = if type(follow) == "string" then followTarget(main, d, follow) else root
		target = target or root
		if target then
			d.Anchored = false
			d.Massless = true
			d.CanCollide = false
			local weld = Instance.new("WeldConstraint")
			weld.Name = "DetailWeld"
			weld.Part0 = target
			weld.Part1 = d
			weld.Parent = d
		else
			d.Anchored = true
		end
	end
end

-- Modelos del mapa que cobran vida (la Estatua de la fuente, los maniquies de escaparate):
-- el enemigo "toma" el modelo del mapa y, al terminar la noche, vuelve a su sitio
-- (atributo HomeCFrame) con su padre y colisiones originales.
export type MapHome = { Parent: Instance?, CFrame: CFrame, Collide: { [BasePart]: boolean } }

-- Modelo libre (no tomado por otro enemigo) con ese tag; si hay `score`, el de mayor puntuacion.
function Common.findMapModel(tagName: string, score: ((Model) -> number)?): Model?
	local CollectionService = game:GetService("CollectionService")
	local best, bestScore = nil, -math.huge
	for _, inst in CollectionService:GetTagged(tagName) do
		if inst:IsA("Model") and inst.PrimaryPart and inst:GetAttribute("Claimed") ~= true and inst:IsDescendantOf(Workspace) then
			local s = if score then score(inst) else 0
			if s > bestScore then
				best, bestScore = inst, s
			end
		end
	end
	return best
end

function Common.claimMapModel(model: Model, container: Instance): MapHome
	local homeCFrame = model:GetAttribute("HomeCFrame")
	local home: MapHome = {
		Parent = model.Parent,
		CFrame = if typeof(homeCFrame) == "CFrame" then homeCFrame else model:GetPivot(),
		Collide = {},
	}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			home.Collide[d] = d.CanCollide
		end
	end
	model:SetAttribute("Claimed", true)
	model.Parent = container
	return home
end

function Common.releaseMapModel(model: Model, home: MapHome)
	local parent = home.Parent
	if not parent or not parent:IsDescendantOf(game) then
		model:Destroy()
		return
	end
	model:PivotTo(home.CFrame)
	for part, collide in home.Collide do
		part.CanCollide = collide
	end
	model:SetAttribute("Claimed", nil)
	model:SetAttribute("EnemyType", nil)
	model.Parent = parent
end

function Common.getTemplate(name: string): Model?
	local folder = ServerStorage:FindFirstChild("EnemyTemplates")
	local template = folder and folder:FindFirstChild(name)
	if template and template:IsA("Model") and template.PrimaryPart then
		return template:Clone()
	end
	return nil
end

-- "Alto" para el Mover: el doble de la distancia del pivote a lo mas bajo del modelo
-- (el Mover pone el pivote a Height/2 sobre el suelo). Asi lo que sobresale por arriba
-- (un sombrero, una antena) no hace flotar al enemigo.
function Common.getHeight(model: Model): number
	local cf, size = model:GetBoundingBox()
	local bottom = cf.Position.Y - size.Y / 2
	return 2 * (model:GetPivot().Position.Y - bottom)
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
-- Subida maxima de un paso (los escalones miden ~1.1). Mas alto es un obstaculo: sin esto,
-- los altos (la Estatua) "pisaban" el techo de un puesto bajo al pasar por encima y se
-- quedaban arriba sin poder bajar.
local MAX_STEP = 1.8
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
			-- AgentHeight: los altos (la Estatua, brazos en alto) pasan agachados por las puertas
			AgentHeight = opts.AgentHeight or math.max(self.Height, 5),
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
			return h ~= nil and feetY - h.Position.Y <= MAX_DROP and h.Position.Y - feetY <= MAX_STEP
		end
		local hit = ground(newPos)
		if not safe(hit) then
			-- Delante hay un vacio (el atrio, el borde de una escalera) o algo demasiado alto para
			-- subirlo de un paso (un puesto, un mostrador): probar a deslizarse por un solo eje
			-- (las rutas rozan los extremos de los barandales); si no, ruta para rodearlo
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

-- Persecuciones: tras Config.Detection.GiveUpSeconds persiguiendo a alguien, o si este le saca
-- GiveUpDistance, el enemigo lo suelta y lo ignora IgnoreSeconds.
-- options.NoGiveUp = true: nunca suelta (la Estatua).
function Common.newAwareness(ctx, options: { NoGiveUp: boolean? }?)
	local self = setmetatable({
		Ctx = ctx,
		Level = {},
		KnownAt = {},
		LastSensed = {},
		Watched = {},
		ChaseStart = {},
		Closest = {},
		IgnoreUntil = {},
		NoGiveUp = options ~= nil and options.NoGiveUp == true,
	}, Awareness)
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
			awareness.ChaseStart[player] = nil
			awareness.Closest[player] = nil
		end
	end
end)

-- d = distancia del enemigo a su objetivo. Devuelve el motivo si debe soltarlo.
function Awareness:ShouldGiveUp(player: Player, d: number, now: number): string?
	if self.NoGiveUp then
		return nil
	end
	local start = self.ChaseStart[player]
	if not start then
		self.ChaseStart[player] = now
		self.Closest[player] = d
		return nil
	end
	local closest = math.min(self.Closest[player] or d, d)
	self.Closest[player] = closest
	local det = Config.Detection
	if now - start >= det.GiveUpSeconds then
		return "tiempo"
	end
	if d > det.GiveUpDistance and d > closest + det.GiveUpGap then
		return "distancia"
	end
	return nil
end

function Awareness:GiveUp(player: Player, now: number, reason: string)
	self.KnownAt[player] = nil
	self.Level[player] = 0
	self.Watched[player] = nil
	self.ChaseStart[player] = nil
	self.Closest[player] = nil
	self.IgnoreUntil[player] = now + Config.Detection.IgnoreSeconds
	if RunService:IsStudio() then
		print(string.format("[Persecucion] Un enemigo dejo de seguir a %s (%s)", player.Name, reason))
	end
end

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
				-- Recien soltado: lo ignora un rato
				local ignored = (self.IgnoreUntil[player] or 0) > now
				if not ignored and not blinded and senses(player, root) then
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
				local reason = self:ShouldGiveUp(player, d, now)
				if reason then
					self:GiveUp(player, now, reason)
				elseif d < bestDist then
					best, bestRoot, bestDist, bestPos = player, root, d, targetPos
				end
			else
				self.ChaseStart[player] = nil
				self.Closest[player] = nil
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
	return d <= Config.Detection.SenseRange * difficulty.SenseMultiplier and Common.lineOfSight(eye, root.Position)
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
