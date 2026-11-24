-- Rastro: una bestia que sigue el olor de los derrames.
--
-- Si un jugador pisa un derrame (tag DirtyArea, lo crea la mision "Limpiar
-- derrame"), queda marcado Config MarkSeconds segundos: deja huellas y el
-- Rastro sabe donde esta en todo momento, incluso escondido (lo saca a la fuerza).
-- Sin olor, patrulla cerca de los derrames y persigue a quien vea.
-- Cada derrame sin limpiar (mision fallada) lo hace mas rapido.
--
-- Contramedidas: limpiar los derrames y no pisarlos; esperar a que se vaya el
-- olor; el destello (aturdido) y el porrazo (empujado). Los petardos solo lo
-- distraen si no esta siguiendo un olor.
--
-- Atributo del Player: ScentUntil (Workspace:GetServerTimeNow() en que se va el olor).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Tags = require(Shared.Tags)
local Remotes = require(Shared.Remotes)

local Server = ServerScriptService:WaitForChild("Server")
local DefenseService = require(Server:WaitForChild("DefenseService"))

local Common = require(script.Parent.Common)

local HEIGHT = 3.6
local FOOTPRINT_SPACING = 3
local FOOTPRINT_SECONDS = 10

local Tracker = {}
Tracker.__index = Tracker

----------------------------------------------------------------------
-- Olor (compartido por todos los Rastros)
----------------------------------------------------------------------

local scent: { [Player]: number } = {} -- [Player] = os.clock() en que se va
local lastPrint: { [Player]: Vector3 } = {}
local lastScentUpdate = 0

local function getFootprintsFolder(): Folder
	local folder = Workspace:FindFirstChild("Footprints")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Footprints"
		folder.Parent = Workspace
	end
	return folder :: Folder
end

local function footprint(root: BasePart)
	local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	if look.Magnitude < 0.01 then
		look = Vector3.new(0, 0, -1)
	end
	local hit = Workspace:Raycast(root.Position, Vector3.new(0, -8, 0), Common.raycastParams())
	if not hit then
		return
	end
	local pos = hit.Position + Vector3.new(0, 0.03, 0)
	local mark = Instance.new("Part")
	mark.Name = "Footprint"
	mark.Anchored = true
	mark.CanCollide = false
	mark.CanQuery = false
	mark.CanTouch = false
	mark.Size = Vector3.new(0.7, 0.05, 1.1)
	mark.CFrame = CFrame.lookAt(pos, pos + look.Unit)
	mark.Material = Enum.Material.SmoothPlastic
	mark.Color = Color3.fromRGB(80, 85, 30)
	mark.Transparency = 0.25
	mark.Parent = getFootprintsFolder()
	task.delay(FOOTPRINT_SECONDS, function()
		mark:Destroy()
	end)
end

local function isOnDirt(position: Vector3): boolean
	for _, puddle in CollectionService:GetTagged(Tags.DirtyArea) do
		if puddle:IsA("BasePart") and puddle.Parent then
			local radius = math.max(puddle.Size.X, puddle.Size.Y, puddle.Size.Z) / 2
			local offset = position - puddle.Position
			if Vector3.new(offset.X, 0, offset.Z).Magnitude <= radius and math.abs(offset.Y) < 5 then
				return true
			end
		end
	end
	return false
end

-- Marca a quien pisa un derrame, deja huellas y quita el olor caducado.
-- La llama cada Rastro en su Update; solo trabaja una vez cada 0.1 s.
local function updateScent()
	local now = os.clock()
	if now - lastScentUpdate < 0.1 then
		return
	end
	lastScentUpdate = now
	local def = Config.Enemies.Tracker

	for _, player in Common.getAlivePlayers() do
		local root = Common.getRoot(player)
		if root then
			if isOnDirt(root.Position) then
				if not scent[player] then
					Remotes.event("Notify"):FireClient(
						player,
						string.format("Pisaste un derrame: el Rastro sigue tu olor (%d s).", def.MarkSeconds),
						"bad"
					)
				end
				scent[player] = now + def.MarkSeconds
				player:SetAttribute("ScentUntil", Workspace:GetServerTimeNow() + def.MarkSeconds)
			elseif scent[player] and DefenseService.IsInSmoke(root.Position) then
				-- La espuma del extintor tapa el olor
				scent[player] = now
				Remotes.event("Notify"):FireClient(player, "La espuma del extintor tapó tu olor.", "good")
			end
			if scent[player] and not DefenseService.IsHidden(player) then
				local last = lastPrint[player]
				local flat = last and Vector3.new(root.Position.X - last.X, 0, root.Position.Z - last.Z).Magnitude
				if not last or (flat and flat >= FOOTPRINT_SPACING) then
					lastPrint[player] = root.Position
					footprint(root)
				end
			end
		end
	end

	for player, expiresAt in scent do
		if now >= expiresAt or not player.Parent or not Common.isAlive(player) then
			scent[player] = nil
			lastPrint[player] = nil
			if player.Parent then
				player:SetAttribute("ScentUntil", nil)
			end
		end
	end
end

local function clearScent()
	for player in scent do
		if player.Parent then
			player:SetAttribute("ScentUntil", nil)
		end
	end
	scent = {}
	lastPrint = {}
	local folder = Workspace:FindFirstChild("Footprints")
	if folder then
		folder:ClearAllChildren()
	end
end

----------------------------------------------------------------------
-- Modelo
----------------------------------------------------------------------

local function buildModel(): Model
	local model, _root = Common.newModel("Tracker", HEIGHT)
	local fur = Color3.fromRGB(45, 35, 28)
	local function add(name, size, offset, color, material)
		local p = Common.part({
			Name = name,
			Size = size,
			CFrame = CFrame.new(offset),
			Color = color or fur,
			Material = material or Enum.Material.Fabric,
			CanCollide = true,
		})
		p.Parent = model
		return p
	end
	add("Body", Vector3.new(2.2, 1.6, 4.2), Vector3.new(0, 0.3, 0))
	add("Head", Vector3.new(1.6, 1.3, 1.6), Vector3.new(0, 0.75, -2.6))
	add("Snout", Vector3.new(0.9, 0.6, 0.9), Vector3.new(0, 0.45, -3.6), Color3.fromRGB(30, 22, 18))
	for _, x in { -0.8, 0.8 } do
		for _, z in { -1.5, 1.5 } do
			add("Leg", Vector3.new(0.5, 1.4, 0.5), Vector3.new(x, -1.1, z))
		end
	end
	for _, x in { -0.4, 0.4 } do
		local eye = add("Eye", Vector3.new(0.25, 0.18, 0.05), Vector3.new(x, 0.95, -3.41), Color3.fromRGB(255, 210, 40), Enum.Material.Neon)
		eye.CanCollide = false
	end
	return model
end

function Tracker.new(spawnPosition: Vector3, ctx)
	local def = Config.Enemies.Tracker
	local model = Common.getTemplate("Tracker") or buildModel()
	local height = Common.getHeight(model)
	Common.prepareModel(model)
	model:PivotTo(CFrame.new(spawnPosition + Vector3.new(0, height / 2, 0)))
	model.Parent = ctx.Container

	local self = setmetatable({}, Tracker)
	self.Def = def
	self.Ctx = ctx
	self.Model = model
	self.Height = height
	self.Mover = Common.newMover(model, { Speed = def.Speed, Height = height })
	self.Awareness = Common.newAwareness(ctx)
	self.PatrolPoint = nil :: Vector3?
	self.LastAttack = 0
	self.NextRetarget = 0
	return self
end

function Tracker:GetSpeed(base: number): number
	local threatBonus = 1 + Config.Threat.SpeedPerFailedMission * self.Ctx.GetTotalThreat()
	local dirtBonus = 1 + self.Def.SpeedPerDirtySpill * self.Ctx.GetThreat("CleanSpill")
	return base * self.Ctx.Difficulty.SpeedMultiplier * threatBonus * dirtBonus
end

-- Jugador con olor mas cercano: (player, root, distancia, posicion objetivo).
function Tracker:FindScent(position: Vector3)
	local best, bestRoot, bestDist, bestPos = nil, nil, math.huge, nil
	for player in scent do
		if Common.isAlive(player) then
			local root = Common.getRoot(player)
			if root then
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

-- Sin presa: ronda los derrames (o una zona al azar si no hay).
function Tracker:PickPatrolPoint(): Vector3?
	local puddles = {}
	for _, puddle in CollectionService:GetTagged(Tags.DirtyArea) do
		if puddle:IsA("BasePart") and puddle.Parent then
			table.insert(puddles, puddle)
		end
	end
	if #puddles > 0 and math.random() < 0.7 then
		local puddle = puddles[math.random(1, #puddles)]
		local angle = math.random() * math.pi * 2
		return puddle.Position + Vector3.new(math.cos(angle) * 6, 0, math.sin(angle) * 6)
	end
	return Common.randomPatrolPoint()
end

function Tracker:Chase(dt: number, target: Player, targetPos: Vector3, dist: number, speed: number)
	local now = os.clock()
	self.PatrolPoint = nil
	if now >= self.NextRetarget or not self.Mover:HasPath() then
		self.Mover:MoveTowards(targetPos)
		self.NextRetarget = now + 0.3
	end
	self.Mover.Speed = speed
	self.Mover:Step(dt)
	if dist <= self.Def.AttackRange + 1 and now - self.LastAttack >= self.Def.AttackCooldown then
		self.LastAttack = now
		Common.damage(target, self.Def.Damage)
	end
end

function Tracker:Update(dt: number)
	updateScent()
	if Common.isStunned(self.Model) then
		self.Mover:Clear()
		return
	end

	local position = self.Model:GetPivot().Position
	local now = os.clock()

	-- 1) Olor: sabe donde estas (aunque estes escondido)
	local scented, _, scentDist, scentPos = self:FindScent(position)
	if scented and scentPos then
		self:Chase(dt, scented, scentPos, scentDist, self:GetSpeed(self.Def.TrackSpeed))
		return
	end

	-- 2) Un petardo lo distrae
	local lure = DefenseService.GetLure(position)
	if lure then
		self.PatrolPoint = nil
		if now >= self.NextRetarget or not self.Mover:HasPath() then
			self.Mover:MoveTowards(lure)
			self.NextRetarget = now + 0.5
		end
		self.Mover.Speed = self:GetSpeed(self.Def.ChaseSpeed)
		self.Mover:Step(dt)
		return
	end

	-- 3) Vista normal
	local eye = position + Vector3.new(0, self.Height * 0.3, 0)
	local target, root, dist, targetPos = self.Awareness:Update(dt, position, function(_player, r)
		return Common.canSee(eye, r)
	end)
	if target and root and targetPos then
		self:Chase(dt, target, targetPos, dist, self:GetSpeed(self.Def.ChaseSpeed))
		return
	end

	-- 4) Rondar los derrames
	local point = self.PatrolPoint
	if not point or Vector3.new(point.X - position.X, 0, point.Z - position.Z).Magnitude < 4 then
		point = self:PickPatrolPoint()
		self.PatrolPoint = point
	end
	if point then
		if now >= self.NextRetarget or not self.Mover:HasPath() then
			self.Mover:MoveTowards(point)
			self.NextRetarget = now + 1
		end
		self.Mover.Speed = self:GetSpeed(self.Def.Speed) * 0.6
		self.Mover:Step(dt)
	end
end

-- Destello: aturdido (lo por defecto, pero tambien pierde la ruta).
function Tracker:OnFlash(_player: Player)
	self.Mover:Clear()
	DefenseService.Stun(self.Model, Config.Defense.Flash.StunSeconds)
end

-- Porrazo: sale despedido y queda aturdido.
-- strength: { StunSeconds, Distance } (Porrazo por defecto; el Trapeador es mas debil)
function Tracker:OnShove(_player: Player, direction: Vector3, strength: { StunSeconds: number, Distance: number }?)
	local s = strength or Config.Defense.Shove
	self.Mover:Clear()
	DefenseService.Stun(self.Model, s.StunSeconds)
	Common.knockback(self.Model, direction, s.Distance)
end

function Tracker:Destroy()
	self.Mover:Destroy()
	self.Model:Destroy()
	clearScent()
end

Players.PlayerRemoving:Connect(function(player)
	scent[player] = nil
	lastPrint[player] = nil
end)

return Tracker
