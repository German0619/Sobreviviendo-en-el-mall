-- El Gerente (jefe de la noche 10): un hombre de traje con un walkie. Patrulla y, si ve
-- a alguien, lo MARCA (contorno rojo y aviso) y lo persigue. Lo que hace con el walkie
-- (pedir refuerzos, cerrar persianas) y como se le vence (destruir sus radios) lo lleva
-- su modulo de jefe (server/Bosses/Manager); aqui solo esta su cuerpo.
--
-- Contramedidas: esconderse; el destello, el taser y los empujones lo frenan un momento.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local ServerScriptService = game:GetService("ServerScriptService")

local Server = ServerScriptService:WaitForChild("Server")
local DefenseService = require(Server:WaitForChild("DefenseService"))

local Common = require(script.Parent.Common)

local HEIGHT = 6.6
local SUIT = Color3.fromRGB(38, 40, 48)
local SHIRT = Color3.fromRGB(230, 230, 228)
local SKIN = Color3.fromRGB(205, 175, 150)
local MARK = Color3.fromRGB(255, 60, 50)

local Manager = {}
Manager.__index = Manager

local function buildModel(): Model
	local model, _root = Common.newModel("Manager", HEIGHT)
	local function add(name, size, cf: CFrame, color: Color3, material, shape)
		local p = Common.part({
			Name = name,
			Size = size,
			CFrame = cf,
			Color = color,
			Material = material or Enum.Material.Fabric,
		})
		if shape then
			p.Shape = shape
		end
		p.Parent = model
		return p
	end
	add("LeftLeg", Vector3.new(0.8, 2.8, 0.8), CFrame.new(-0.45, -1.9, 0), SUIT)
	add("RightLeg", Vector3.new(0.8, 2.8, 0.8), CFrame.new(0.45, -1.9, 0), SUIT)
	add("Shoes", Vector3.new(1.9, 0.3, 1.1), CFrame.new(0, -3.15, -0.1), Color3.fromRGB(20, 18, 16), Enum.Material.Leather)
	add("Jacket", Vector3.new(2.1, 2.6, 1.05), CFrame.new(0, 0.8, 0), SUIT)
	add("Shirt", Vector3.new(0.6, 2.2, 0.05), CFrame.new(0, 1, -0.53), SHIRT, Enum.Material.SmoothPlastic)
	add("Tie", Vector3.new(0.25, 1.8, 0.06), CFrame.new(0, 0.95, -0.56), Color3.fromRGB(170, 20, 25), Enum.Material.SmoothPlastic)
	add("LeftArm", Vector3.new(0.65, 2.5, 0.65), CFrame.new(-1.4, 0.6, 0), SUIT)
	-- Brazo derecho doblado: el walkie junto a la cara
	add("RightArm", Vector3.new(0.65, 2.3, 0.65), CFrame.new(1.25, 1.3, -0.4) * CFrame.Angles(math.rad(-50), 0, math.rad(15)), SUIT)
	add("Head", Vector3.new(1.1, 1.25, 1.1), CFrame.new(0, 2.75, 0), SKIN, Enum.Material.SmoothPlastic)
	add("Hair", Vector3.new(1.15, 0.35, 1.15), CFrame.new(0, 3.3, 0.05), Color3.fromRGB(30, 25, 22), Enum.Material.SmoothPlastic)
	for _, x in { -0.22, 0.22 } do
		add("Eye", Vector3.new(0.18, 0.08, 0.05), CFrame.new(x, 2.85, -0.56), Color3.fromRGB(255, 230, 200), Enum.Material.Neon)
	end
	add("Walkie", Vector3.new(0.35, 0.8, 0.25), CFrame.new(0.85, 2.6, -0.55), Color3.fromRGB(25, 25, 25), Enum.Material.SmoothPlastic)
	local led = add("WalkieLed", Vector3.new(0.12, 0.12, 0.12), CFrame.new(0.85, 3.05, -0.55), Color3.fromRGB(255, 40, 30), Enum.Material.Neon)
	local light = Instance.new("PointLight")
	light.Name = "WalkieLight"
	light.Color = Color3.fromRGB(255, 50, 40)
	light.Range = 6
	light.Brightness = 0.8
	light.Parent = led
	return model
end

function Manager.new(spawnPosition: Vector3, ctx)
	local def = Config.Enemies.Manager
	local model = Common.getTemplate("Manager") or buildModel()
	local height = Common.getHeight(model)
	Common.prepareModel(model)
	model:PivotTo(CFrame.new(spawnPosition + Vector3.new(0, height / 2, 0)))
	model.Parent = ctx.Container

	local self = setmetatable({}, Manager)
	self.Def = def
	self.Ctx = ctx
	self.Model = model
	self.Height = height
	self.Mover = Common.newMover(model, { Speed = def.Speed, Height = height, AgentHeight = 6 })
	self.Awareness = Common.newAwareness(ctx)
	self.Marked = nil :: Player?
	self.LastAttack = 0
	self.PatrolPoint = nil
	self.NextRetarget = 0
	self.Led = model:FindFirstChild("WalkieLed", true) :: BasePart?
	return self
end

function Manager:SpeedMultiplier(): number
	return self.Ctx.Difficulty.SpeedMultiplier * (1 + Config.Threat.SpeedPerFailedMission * self.Ctx.GetTotalThreat())
end

-- Habla por el walkie (lo usa su modulo de jefe): el led parpadea.
function Manager:Radio(seconds: number)
	local led = self.Led
	if not led then
		return
	end
	task.spawn(function()
		local untilAt = os.clock() + seconds
		while os.clock() < untilAt and led.Parent do
			led.Transparency = if led.Transparency == 0 then 0.8 else 0
			task.wait(0.15)
		end
		if led.Parent then
			led.Transparency = 0
		end
	end)
end

local function setMark(player: Player, on: boolean)
	local character = player.Character
	local mark = character and character:FindFirstChild("ManagerMark")
	if on and character and not mark then
		local h = Instance.new("Highlight")
		h.Name = "ManagerMark"
		h.FillTransparency = 1
		h.OutlineColor = MARK
		h.OutlineTransparency = 0.2
		h.DepthMode = Enum.HighlightDepthMode.Occluded
		h.Parent = character
	elseif not on and mark then
		mark:Destroy()
	end
end

function Manager:SetMarked(player: Player?)
	if self.Marked == player then
		return
	end
	if self.Marked then
		setMark(self.Marked, false)
	end
	self.Marked = player
	if player then
		setMark(player, true)
		Remotes.event("Notify"):FireClient(player, "¡El Gerente te ha visto! Te persigue: escóndete o despístalo.", "bad")
	end
end

function Manager:Walk(dt: number, goal: Vector3, speed: number, retarget: number)
	local now = os.clock()
	if now >= self.NextRetarget or not self.Mover:HasPath() then
		self.Mover:MoveTowards(goal)
		self.NextRetarget = now + retarget
	end
	self.Mover.Speed = speed
	self.Mover:Step(dt)
end

function Manager:Update(dt: number)
	local now = os.clock()
	if Common.isStunned(self.Model) then
		self.Mover:Clear()
		return
	end
	local pos = self.Model:GetPivot().Position
	local eye = pos + Vector3.new(0, self.Height * 0.35, 0)
	local target, _root, dist, targetPos = self.Awareness:Update(dt, pos, function(_player, r)
		return Common.canSee(eye, r)
	end)
	local mul = self:SpeedMultiplier()

	if target and targetPos then
		self:SetMarked(target)
		self.PatrolPoint = nil
		self:Walk(dt, targetPos, self.Def.ChaseSpeed * mul, 0.3)
		if dist <= self.Def.AttackRange + 1 and now - self.LastAttack >= self.Def.AttackCooldown then
			self.LastAttack = now
			Common.damage(target, self.Def.Damage)
		end
		return
	end
	self:SetMarked(nil)

	-- Un petardo lo distrae
	local lure = DefenseService.GetLure(pos)
	if lure then
		self:Walk(dt, lure, self.Def.Speed * mul, 0.5)
		return
	end
	if not self.PatrolPoint or Vector3.new(self.PatrolPoint.X - pos.X, 0, self.PatrolPoint.Z - pos.Z).Magnitude < 4 then
		self.PatrolPoint = Common.randomPatrolPoint()
	end
	if self.PatrolPoint then
		self:Walk(dt, self.PatrolPoint, self.Def.Speed * mul, 1)
	end
end

function Manager:Stun(seconds: number)
	self.Mover:Clear()
	DefenseService.Stun(self.Model, seconds)
end

function Manager:OnFlash(_player: Player)
	self:Stun(self.Def.StunSeconds)
end

function Manager:OnTaser(_player: Player)
	self:Stun(self.Def.StunSeconds)
end

function Manager:OnShove(_player: Player, direction: Vector3, strength: { StunSeconds: number, Distance: number }?)
	local s = strength or Config.Defense.Shove
	self:Stun(math.min(s.StunSeconds, self.Def.StunSeconds))
	Common.knockback(self.Model, direction, s.Distance * 0.5)
end

function Manager:Destroy()
	self:SetMarked(nil)
	self.Mover:Destroy()
	self.Model:Destroy()
end

return Manager
