-- Utilidades compartidas por todos los enemigos.
--
-- Los enemigos son modelos anclados que se mueven con PivotTo (cinematicos):
-- no se atascan con la fisica y su comportamiento es 100% del servidor.
--
-- Plantillas propias: si existe ServerStorage.EnemyTemplates.<Nombre> (un
-- Model con PrimaryPart), se usa en vez del modelo de prueba hecho con bloques.

local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

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
		humanoid:TakeDamage(amount)
	end
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

-- opts: { Speed, Height, Ghost (atraviesa paredes, flota a HoverY), HoverY }
function Common.newMover(model: Model, opts)
	local self = setmetatable({}, Mover)
	self.Model = model
	self.Speed = opts.Speed
	self.Height = opts.Height
	self.Ghost = opts.Ghost == true
	self.HoverY = opts.HoverY
	self.Waypoints = {}
	self.Index = 1
	self.Computing = false
	self.LastCompute = 0
	self.Destroyed = false
	if not self.Ghost then
		self.Path = PathfindingService:CreatePath({
			AgentRadius = 2,
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
		return
	end

	local from = self:GetPosition()
	if Common.lineOfSight(from, Vector3.new(target.X, from.Y, target.Z)) then
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
		end
	end)
end

-- Avanza hacia el siguiente punto. Devuelve true si se movio.
function Mover:Step(dt: number): boolean
	local wp = self.Waypoints[self.Index]
	if not wp then
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
	local newPos = pos + dir * math.min(dist, self.Speed * dt)

	local y
	if self.Ghost then
		y = self.HoverY or pos.Y
	else
		local hit = Workspace:Raycast(
			newPos + Vector3.new(0, 1, 0),
			Vector3.new(0, -(self.Height + 6), 0),
			Common.raycastParams()
		)
		y = if hit then hit.Position.Y + self.Height / 2 else pos.Y
	end

	newPos = Vector3.new(newPos.X, y, newPos.Z)
	self.Model:PivotTo(CFrame.lookAt(newPos, newPos + dir))
	return true
end

function Mover:Destroy()
	self.Destroyed = true
end

return Common
