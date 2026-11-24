-- Cazador: una figura alta con sombrero y un farol rojo. Cada cierto tiempo MARCA al
-- jugador mas solo (el mas lejos del resto; jugando solo, a ti) y lo persigue sabiendo
-- siempre donde esta, a traves de las paredes. A los demas los ignora.
--
-- La marca se ve: contorno rojo en el marcado (lo ven todos) y un aviso.
-- Se rompe si el marcado se reune con otro jugador unos segundos, si se esconde con el
-- Cazador lejos, o al cabo de MarkSeconds. Tras golpear desaparece y vuelve lejos.
--
-- Contramedidas: ir en grupo; esconderse a tiempo; correr (es algo mas rapido que caminar);
-- el destello y el porrazo lo frenan un instante (es de nivel 3: casi no le afectan).

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local ServerScriptService = game:GetService("ServerScriptService")

local Server = ServerScriptService:WaitForChild("Server")
local DefenseService = require(Server:WaitForChild("DefenseService"))

local Common = require(script.Parent.Common)

local HEIGHT = 7.5
local COAT = Color3.fromRGB(28, 24, 22)
local LANTERN = Color3.fromRGB(255, 50, 30)

local Hunter = {}
Hunter.__index = Hunter

local function buildModel(): Model
	local model, _root = Common.newModel("Hunter", HEIGHT)
	local function add(name, size, cf: CFrame, color: Color3?, material, shape)
		local p = Common.part({
			Name = name,
			Size = size,
			CFrame = cf,
			Color = color or COAT,
			Material = material or Enum.Material.Fabric,
		})
		if shape then
			p.Shape = shape
		end
		p.Parent = model
		return p
	end
	-- Abrigo largo, piernas flacas, brazos largos
	add("LeftLeg", Vector3.new(0.5, 2.6, 0.5), CFrame.new(-0.4, -2.45, 0))
	add("RightLeg", Vector3.new(0.5, 2.6, 0.5), CFrame.new(0.4, -2.45, 0))
	add("Coat", Vector3.new(1.8, 3.6, 1), CFrame.new(0, 0.2, 0))
	add("CoatTail", Vector3.new(1.9, 1.4, 1.05), CFrame.new(0, -1.9, 0.05))
	add("LeftArm", Vector3.new(0.45, 3.1, 0.45), CFrame.new(-1.15, -0.2, 0))
	add("RightArm", Vector3.new(0.45, 3.1, 0.45), CFrame.new(1.15, -0.2, -0.3) * CFrame.Angles(math.rad(20), 0, 0))
	add("Head", Vector3.new(0.9, 1.1, 0.9), CFrame.new(0, 2.6, 0), Color3.fromRGB(40, 36, 34), Enum.Material.SmoothPlastic)
	-- Sombrero de ala ancha
	add("HatBrim", Vector3.new(0.15, 2.4, 2.4), CFrame.new(0, 3.1, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(18, 16, 15), Enum.Material.Fabric, Enum.PartType.Cylinder)
	add("HatTop", Vector3.new(0.8, 1.2, 1.2), CFrame.new(0, 3.55, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(18, 16, 15), Enum.Material.Fabric, Enum.PartType.Cylinder)
	for _, x in { -0.2, 0.2 } do
		add("Eye", Vector3.new(0.16, 0.08, 0.05), CFrame.new(x, 2.65, -0.46), LANTERN, Enum.Material.Neon)
	end
	-- Farol rojo en la mano derecha: se le ve venir de lejos
	local lantern = add("Lantern", Vector3.new(0.5, 0.7, 0.5), CFrame.new(1.15, -2.0, -0.85), LANTERN, Enum.Material.Neon)
	local light = Instance.new("PointLight")
	light.Name = "LanternLight"
	light.Color = LANTERN
	light.Range = 14
	light.Brightness = 1.4
	light.Shadows = true
	light.Parent = lantern
	return model
end

function Hunter.new(spawnPosition: Vector3, ctx)
	local def = Config.Enemies.Hunter
	local model = Common.getTemplate("Hunter") or buildModel()
	local height = Common.getHeight(model)
	Common.prepareModel(model)
	model:PivotTo(CFrame.new(spawnPosition + Vector3.new(0, height / 2, 0)))
	model.Parent = ctx.Container

	local self = setmetatable({}, Hunter)
	self.Def = def
	self.Ctx = ctx
	self.Model = model
	self.Height = height
	self.Mover = Common.newMover(model, { Speed = def.Speed, Height = height, AgentHeight = 6 })
	self.Marked = nil :: Player?
	self.MarkUntil = 0
	self.NextMarkAt = os.clock() + 4
	self.GroupedFor = 0
	self.LastAttack = 0
	self.Gone = false
	self.ReturnAt = 0
	self.PatrolPoint = nil
	self.NextRetarget = 0
	return self
end

function Hunter:SpeedMultiplier(): number
	return self.Ctx.Difficulty.SpeedMultiplier * (1 + Config.Threat.SpeedPerFailedMission * self.Ctx.GetTotalThreat())
end

-- Distancia de un jugador al companero vivo mas cercano (math.huge si esta solo).
local function isolation(player: Player): number
	local root = Common.getRoot(player)
	if not root then
		return 0
	end
	local best = math.huge
	for _, other in Common.getAlivePlayers() do
		local r = other ~= player and Common.getRoot(other)
		if r then
			best = math.min(best, (r.Position - root.Position).Magnitude)
		end
	end
	return best
end

local function setHighlight(player: Player, on: boolean)
	local character = player.Character
	if not character then
		return
	end
	local mark = character:FindFirstChild("HunterMark")
	if on and not mark then
		local h = Instance.new("Highlight")
		h.Name = "HunterMark"
		h.FillTransparency = 1
		h.OutlineColor = LANTERN
		h.OutlineTransparency = 0.2
		h.DepthMode = Enum.HighlightDepthMode.Occluded
		h.Parent = character
	elseif not on and mark then
		mark:Destroy()
	end
end

function Hunter:Mark(player: Player)
	self.Marked = player
	self.MarkUntil = os.clock() + self.Def.MarkSeconds
	self.GroupedFor = 0
	player:SetAttribute("HunterMarked", true)
	setHighlight(player, true)
	local solo = #Common.getAlivePlayers() <= 1
	Remotes.event("Notify"):FireClient(
		player,
		if solo
			then "El Cazador te ha marcado. ¡Corre o escóndete lejos de él!"
			else "El Cazador te ha marcado por ir solo. ¡Reúnete con tu equipo!",
		"bad"
	)
end

function Hunter:Unmark(reason: string?)
	local player = self.Marked
	self.Marked = nil
	self.NextMarkAt = os.clock() + self.Def.MarkCooldown
	if player then
		player:SetAttribute("HunterMarked", nil)
		setHighlight(player, false)
		if reason and player.Parent then
			Remotes.event("Notify"):FireClient(player, reason, "good")
		end
	end
end

-- El jugador mas solo (si lo esta lo bastante).
function Hunter:PickPrey(): Player?
	local best, bestIso = nil, -1
	local alive = Common.getAlivePlayers()
	for _, player in alive do
		if not DefenseService.IsHidden(player) then
			local iso = isolation(player)
			if iso > bestIso then
				best, bestIso = player, iso
			end
		end
	end
	if best and (#alive <= 1 or bestIso >= self.Def.LonelyDistance) then
		return best
	end
	return nil
end

-- Tras golpear desaparece un rato y vuelve lejos de todos.
function Hunter:Retreat()
	self.Gone = true
	self.ReturnAt = os.clock() + self.Def.RetreatSeconds
	self.Mover:Clear()
	self.Model.Parent = nil
end

function Hunter:TryReturn(): boolean
	for _ = 1, 8 do
		local point = Common.randomPatrolPoint()
		if point then
			local _, _, d = Common.nearestAlive(point)
			if d >= 50 then
				self.Model:PivotTo(CFrame.new(point + Vector3.new(0, self.Height / 2, 0)))
				self.Model.Parent = self.Ctx.Container
				self.Gone = false
				self.Mover:Clear()
				return true
			end
		end
	end
	return false
end

function Hunter:Walk(dt: number, goal: Vector3, speed: number, retarget: number)
	local now = os.clock()
	if now >= self.NextRetarget or not self.Mover:HasPath() then
		self.Mover:MoveTowards(goal)
		self.NextRetarget = now + retarget
	end
	self.Mover.Speed = speed
	self.Mover:Step(dt)
end

function Hunter:Update(dt: number)
	local now = os.clock()
	if self.Gone then
		if now >= self.ReturnAt and not self:TryReturn() then
			self.ReturnAt = now + 2
		end
		return
	end
	if Common.isStunned(self.Model) then
		self.Mover:Clear()
		return
	end
	local pos = self.Model:GetPivot().Position
	local mul = self:SpeedMultiplier()

	-- La marca: se rompe si ya no esta solo, si se esconde lejos o se acaba el tiempo
	local prey = self.Marked
	if prey then
		local root = Common.getRoot(prey)
		if not Common.isAlive(prey) or not root then
			self:Unmark(nil)
			prey = nil
		elseif now >= self.MarkUntil then
			self:Unmark("El Cazador pierde tu rastro... por ahora.")
			prey = nil
		elseif DefenseService.IsHidden(prey) and (root.Position - pos).Magnitude > self.Def.HideEscapeDistance then
			self:Unmark("Te escondiste a tiempo: el Cazador pierde tu rastro.")
			prey = nil
		else
			if isolation(prey) <= self.Def.GroupDistance then
				self.GroupedFor += dt
				if self.GroupedFor >= self.Def.GroupSeconds then
					self:Unmark("Ya no estás solo: el Cazador te deja.")
					prey = nil
				end
			else
				self.GroupedFor = 0
			end
		end
	elseif now >= self.NextMarkAt then
		local pick = self:PickPrey()
		if pick then
			self:Mark(pick)
			prey = pick
		else
			self.NextMarkAt = now + 3
		end
	end

	if prey then
		-- Sabe donde esta (si esta escondido, va a la puerta del escondite)
		local root = Common.getRoot(prey) :: BasePart
		local goal = Common.targetPosition(prey, root)
		self.PatrolPoint = nil
		self:Walk(dt, goal, self.Def.ChaseSpeed * mul, 0.3)
		if (goal - pos).Magnitude <= self.Def.AttackRange + 1 and now - self.LastAttack >= self.Def.AttackCooldown then
			self.LastAttack = now
			Common.damage(prey, self.Def.Damage)
			self:Unmark(nil)
			self:Retreat()
		end
		return
	end

	-- Sin presa: merodea despacio
	if not self.PatrolPoint or Vector3.new(self.PatrolPoint.X - pos.X, 0, self.PatrolPoint.Z - pos.Z).Magnitude < 4 then
		self.PatrolPoint = Common.randomPatrolPoint()
	end
	if self.PatrolPoint then
		self:Walk(dt, self.PatrolPoint, self.Def.Speed * mul, 1)
	end
end

-- Nivel 3: el destello y los empujones apenas lo frenan.
function Hunter:OnFlash(_player: Player)
	self.Mover:Clear()
	DefenseService.Stun(self.Model, 1)
end

function Hunter:OnShove(_player: Player, direction: Vector3, strength: { StunSeconds: number, Distance: number }?)
	local s = strength or Config.Defense.Shove
	self.Mover:Clear()
	DefenseService.Stun(self.Model, math.min(s.StunSeconds, 1))
	Common.knockback(self.Model, direction, s.Distance * 0.4)
end

function Hunter:Destroy()
	self:Unmark(nil)
	self.Mover:Destroy()
	self.Model:Destroy()
end

return Hunter
