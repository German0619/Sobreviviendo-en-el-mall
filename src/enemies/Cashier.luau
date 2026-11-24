-- Cajero: un cajero automatico con patas. No hace dano: huele los billetes.
-- Persigue al jugador que ve con dinero, le roba una parte al tocarlo y huye.
-- Si nadie lo detiene en FleeSeconds, se queda el dinero.
--
-- Contramedidas: gastar antes los billetes (tienda, mejoras); aturdirlo mientras huye
-- (destello, porrazo, trapeador, taser) devuelve lo robado a su dueno. Los petardos
-- lo distraen y los escondites rompen la persecucion.
--
-- Estados: Prowl (busca) -> Flee (huye con el dinero) -> Prowl

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Util = require(Shared.Util)
local ServerScriptService = game:GetService("ServerScriptService")

local Server = ServerScriptService:WaitForChild("Server")
local DefenseService = require(Server:WaitForChild("DefenseService"))
local RunState = require(Server:WaitForChild("RunState"))

local Common = require(script.Parent.Common)

local HEIGHT = 6
local BODY_COLOR = Color3.fromRGB(120, 126, 134)
local SCREEN_COLOR = Color3.fromRGB(60, 230, 110)
local GREED_COLOR = Color3.fromRGB(255, 70, 60)

local Cashier = {}
Cashier.__index = Cashier

local function buildModel(): Model
	local model, _root = Common.newModel("Cashier", HEIGHT)
	local function add(name, size, cf: CFrame, color: Color3, material, props)
		local p = Common.part({
			Name = name,
			Size = size,
			CFrame = cf,
			Color = color,
			Material = material or Enum.Material.Metal,
		})
		for k, v in props or {} do
			p[k] = v
		end
		p.Parent = model
		return p
	end
	-- Cuerpo del cajero (frente = -Z)
	add("Body", Vector3.new(2.6, 3.4, 1.8), CFrame.new(0, 0.9, 0), BODY_COLOR, Enum.Material.Metal, { CanQuery = true })
	add("Top", Vector3.new(2.8, 0.5, 2), CFrame.new(0, 2.85, -0.05), Color3.fromRGB(40, 90, 160), Enum.Material.SmoothPlastic)
	local screen = add("Screen", Vector3.new(1.6, 1, 0.08), CFrame.new(0, 1.7, -0.92), SCREEN_COLOR, Enum.Material.Neon)
	add("Keypad", Vector3.new(1.2, 0.5, 0.35), CFrame.new(0, 0.85, -1) * CFrame.Angles(math.rad(-25), 0, 0), Color3.fromRGB(50, 52, 56))
	-- Ranura de billetes: su "boca"
	add("Slot", Vector3.new(1.4, 0.15, 0.1), CFrame.new(0, 0.2, -0.92), Color3.fromRGB(15, 15, 15), Enum.Material.SmoothPlastic)
	-- Patas largas y delgadas
	for _, x in { -0.8, 0.8 } do
		add("Leg", Vector3.new(0.35, 2.6, 0.35), CFrame.new(x, -1.7, 0), Color3.fromRGB(60, 62, 66))
		add("Foot", Vector3.new(0.6, 0.2, 0.9), CFrame.new(x, -2.9, -0.15), Color3.fromRGB(40, 40, 42))
	end
	-- Pantalla con el simbolo de dinero
	local gui = Instance.new("SurfaceGui")
	gui.Name = "ScreenGui"
	gui.Face = Enum.NormalId.Front
	gui.CanvasSize = Vector2.new(160, 100)
	gui.LightInfluence = 0
	gui.Parent = screen
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(10, 40, 15)
	label.Text = "$"
	label.Parent = gui
	local glow = Instance.new("PointLight")
	glow.Name = "ScreenGlow"
	glow.Color = SCREEN_COLOR
	glow.Range = 8
	glow.Brightness = 0.8
	glow.Parent = screen
	return model
end

function Cashier.new(spawnPosition: Vector3, ctx)
	local def = Config.Enemies.Cashier
	local model = Common.getTemplate("Cashier") or buildModel()
	local height = Common.getHeight(model)
	Common.prepareModel(model)
	model:PivotTo(CFrame.new(spawnPosition + Vector3.new(0, height / 2, 0)))
	model.Parent = ctx.Container

	local self = setmetatable({}, Cashier)
	self.Def = def
	self.Ctx = ctx
	self.Model = model
	self.Height = height
	self.Mover = Common.newMover(model, { Speed = def.Speed, Height = height })
	self.Awareness = Common.newAwareness(ctx)
	self.State = "Prowl" -- Prowl | Flee
	self.Loot = {} :: { [Player]: number } -- lo robado en esta huida
	self.FleeUntil = 0
	self.FleePoint = nil :: Vector3?
	self.NextStealAt = 0
	self.PatrolPoint = nil
	self.NextRetarget = 0
	self.Screen = model:FindFirstChild("Screen", true) :: BasePart?
	self.Label = model:FindFirstChild("Label", true) :: TextLabel?
	return self
end

function Cashier:SpeedMultiplier(): number
	return self.Ctx.Difficulty.SpeedMultiplier * (1 + Config.Threat.SpeedPerFailedMission * self.Ctx.GetTotalThreat())
end

local function notify(player: Player, message: string, kind: string)
	Remotes.event("Notify"):FireClient(player, message, kind)
end

-- Pantalla: verde buscando, roja huyendo con el dinero.
function Cashier:SetGreedy(greedy: boolean)
	local color = if greedy then GREED_COLOR else SCREEN_COLOR
	if self.Screen then
		self.Screen.Color = color
		local glow = self.Screen:FindFirstChildOfClass("PointLight")
		if glow then
			glow.Color = color
			glow.Brightness = if greedy then 1.6 else 0.8
		end
	end
	if self.Label then
		self.Label.Text = if greedy then "$$$" else "$"
	end
end

function Cashier:Walk(dt: number, target: Vector3, speed: number, retarget: number)
	local now = os.clock()
	if now >= self.NextRetarget or not self.Mover:HasPath() then
		self.Mover:MoveTowards(target)
		self.NextRetarget = now + retarget
	end
	self.Mover.Speed = speed
	self.Mover:Step(dt)
end

-- Punto de huida: el mas lejano de la victima entre unos cuantos al azar.
function Cashier:PickFleePoint(from: Vector3): Vector3?
	local best, bestDist = nil, -1
	for _ = 1, 8 do
		local point = Common.randomPatrolPoint()
		if point then
			local d = (point - from).Magnitude
			if d > bestDist then
				best, bestDist = point, d
			end
		end
	end
	return best
end

function Cashier:Steal(player: Player)
	local cash = RunState.GetCash(player)
	local amount = math.min(cash, math.max(self.Def.StealMin, math.floor(cash * self.Def.StealFraction)))
	if amount <= 0 or not RunState.TrySpend(player, amount) then
		return
	end
	self.Loot[player] = (self.Loot[player] or 0) + amount
	notify(player, string.format("¡El Cajero te robó %s! Atúrdelo antes de que escape.", Util.formatMoney(amount)), "bad")
	self.State = "Flee"
	self.FleeUntil = os.clock() + self.Def.FleeSeconds
	self.FleePoint = self:PickFleePoint(self.Model:GetPivot().Position)
	self.Mover:Clear()
	self:SetGreedy(true)
end

-- Aturdido con el botin: lo suelta y vuelve a sus duenos.
function Cashier:DropLoot()
	if next(self.Loot) == nil then
		return
	end
	for player, amount in self.Loot do
		if player.Parent then
			RunState.AddCash(player, amount)
			notify(player, string.format("Recuperaste %s del Cajero.", Util.formatMoney(amount)), "good")
		end
	end
	self.Loot = {}
	self.State = "Prowl"
	self.NextStealAt = os.clock() + self.Def.StealCooldown * 0.5
	self:SetGreedy(false)
end

-- Escapo: el dinero se pierde.
function Cashier:KeepLoot()
	for player, amount in self.Loot do
		if player.Parent then
			notify(player, string.format("El Cajero escapó con tus %s.", Util.formatMoney(amount)), "bad")
		end
	end
	self.Loot = {}
	self.State = "Prowl"
	self.NextStealAt = os.clock() + self.Def.StealCooldown
	self:SetGreedy(false)
end

function Cashier:Update(dt: number)
	local now = os.clock()
	if Common.isStunned(self.Model) then
		self.Mover:Clear()
		return
	end
	local pos = self.Model:GetPivot().Position
	local mul = self:SpeedMultiplier()

	if self.State == "Flee" then
		local arrived = self.FleePoint
			and Vector3.new(self.FleePoint.X - pos.X, 0, self.FleePoint.Z - pos.Z).Magnitude < 4
		if now >= self.FleeUntil then
			self:KeepLoot()
			return
		end
		if arrived or not self.FleePoint then
			self.FleePoint = self:PickFleePoint(pos) -- sigue corriendo hasta que se acabe el tiempo
		end
		if self.FleePoint then
			self:Walk(dt, self.FleePoint, self.Def.FleeSpeed * mul, 0.6)
		end
		return
	end

	-- Solo le interesan los que llevan billetes (y los que puede robar ya)
	local canSteal = now >= self.NextStealAt
	local target, _root, dist, targetPos = self.Awareness:Update(dt, pos, function(player, r)
		return canSteal and RunState.GetCash(player) >= self.Def.MinCash and Common.canSee(pos, r)
	end)

	local lure = DefenseService.GetLure(pos)
	if lure and (not target or dist > Config.Defense.Firecracker.IgnoreIfTargetWithin) then
		self:Walk(dt, lure, self.Def.ChaseSpeed * mul, 0.5)
		return
	end

	if target and targetPos and canSteal then
		self.PatrolPoint = nil
		self:Walk(dt, targetPos, self.Def.ChaseSpeed * mul, 0.4)
		if dist <= self.Def.AttackRange and not DefenseService.IsHidden(target) then
			self:Steal(target)
		end
		return
	end

	if not self.PatrolPoint or Vector3.new(self.PatrolPoint.X - pos.X, 0, self.PatrolPoint.Z - pos.Z).Magnitude < 4 then
		self.PatrolPoint = Common.randomPatrolPoint()
	end
	if self.PatrolPoint then
		self:Walk(dt, self.PatrolPoint, self.Def.Speed * mul, 1)
	end
end

function Cashier:Stunned(seconds: number)
	self.Mover:Clear()
	DefenseService.Stun(self.Model, seconds)
	self:DropLoot()
end

function Cashier:OnFlash(_player: Player)
	self:Stunned(Config.Defense.Flash.StunSeconds)
end

function Cashier:OnShove(_player: Player, direction: Vector3, strength: { StunSeconds: number, Distance: number }?)
	local s = strength or Config.Defense.Shove
	self:Stunned(s.StunSeconds)
	Common.knockback(self.Model, direction, s.Distance)
end

function Cashier:OnTaser(_player: Player)
	self:Stunned(Config.Weapons.Taser.StunSeconds)
end

function Cashier:Destroy()
	-- Fin de la noche con el botin encima: se pierde (como si hubiera escapado)
	self.Loot = {}
	self.Mover:Destroy()
	self.Model:Destroy()
end

return Cashier
