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
local TweenService = game:GetService("TweenService")

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
		-- Detalles soldados (Common.prepareModel); el cuerpo, las patas y los pies se mueven solos
		if name ~= "Body" and name ~= "Leg" and name ~= "Foot" and p:GetAttribute("Follow") == nil then
			p:SetAttribute("Detail", true)
		end
		p.Parent = model
		return p
	end
	local function text(part: BasePart, face: Enum.NormalId, canvas: Vector2, str: string, color: Color3, font: Enum.Font?)
		local gui = Instance.new("SurfaceGui")
		gui.Name = "SignGui"
		gui.Face = face
		gui.CanvasSize = canvas
		gui.LightInfluence = 0.6
		gui.Parent = part
		local t = Instance.new("TextLabel")
		t.Name = "SignText"
		t.Size = UDim2.fromScale(1, 1)
		t.BackgroundTransparency = 1
		t.Font = font or Enum.Font.GothamBlack
		t.TextScaled = true
		t.TextColor3 = color
		t.Text = str
		t.Parent = gui
	end
	local DARK = Color3.fromRGB(32, 34, 38)
	local STEEL = Color3.fromRGB(175, 180, 188)
	local BLUE = Color3.fromRGB(40, 90, 160)

	-- Cuerpo del cajero (frente = -Z) con cantos oscuros
	add("Body", Vector3.new(2.6, 3.4, 1.8), CFrame.new(0, 0.9, 0), BODY_COLOR, Enum.Material.Metal, { CanQuery = true })
	for _, x in { -1.27, 1.27 } do
		add("Trim", Vector3.new(0.12, 3.4, 0.12), CFrame.new(x, 0.9, -0.9), DARK)
		add("Trim", Vector3.new(0.12, 3.4, 0.12), CFrame.new(x, 0.9, 0.9), DARK)
	end
	add("Plinth", Vector3.new(2.7, 0.25, 1.9), CFrame.new(0, -0.7, 0), DARK)
	-- Letrero luminoso de arriba
	local top = add("Top", Vector3.new(2.8, 0.4, 2), CFrame.new(0, 2.8, -0.05), BLUE, Enum.Material.SmoothPlastic)
	text(top, Enum.NormalId.Front, Vector2.new(280, 40), "CAJERO 24H", Color3.fromRGB(255, 255, 255))
	add("TopStripe", Vector3.new(2.82, 0.06, 2.02), CFrame.new(0, 2.62, -0.05), Color3.fromRGB(240, 190, 40), Enum.Material.SmoothPlastic)
	-- Pantalla con marco y visera
	local screen = add("Screen", Vector3.new(1.6, 1, 0.08), CFrame.new(0, 1.7, -0.92), SCREEN_COLOR, Enum.Material.Neon)
	add("Bezel", Vector3.new(1.85, 1.25, 0.05), CFrame.new(0, 1.7, -0.9), DARK, Enum.Material.SmoothPlastic)
	add("Hood", Vector3.new(2.0, 0.08, 0.45), CFrame.new(0, 2.36, -1.12), DARK)
	for _, x in { -0.97, 0.97 } do
		add("Hood", Vector3.new(0.08, 1.3, 0.45), CFrame.new(x, 1.72, -1.12), DARK)
	end
	-- Camara espia sobre la pantalla (un ojo que te sigue)
	add("Lens", Vector3.new(0.22, 0.22, 0.22), CFrame.new(0, 2.5, -0.93), Color3.fromRGB(10, 10, 12), Enum.Material.Glass, { Shape = Enum.PartType.Ball, Reflectance = 0.4 })
	add("LensLed", Vector3.new(0.06, 0.06, 0.04), CFrame.new(0.22, 2.5, -0.92), GREED_COLOR, Enum.Material.Neon)
	-- Teclado inclinado con sus botones (la ultima columna: rojo, amarillo y verde)
	local keypadCF = CFrame.new(0, 0.85, -1) * CFrame.Angles(math.rad(-25), 0, 0)
	add("Keypad", Vector3.new(1.2, 0.5, 0.35), keypadCF, Color3.fromRGB(50, 52, 56))
	local keyColors = { Color3.fromRGB(220, 50, 50), Color3.fromRGB(240, 200, 50), Color3.fromRGB(60, 190, 80) }
	for col = 0, 3 do
		for row = 0, 2 do
			local color = if col == 3 then keyColors[row + 1] else Color3.fromRGB(200, 200, 205)
			add("Key", Vector3.new(0.2, 0.05, 0.08), keypadCF * CFrame.new(-0.42 + col * 0.28, 0.26, -0.11 + row * 0.11), color, Enum.Material.SmoothPlastic)
		end
	end
	-- Ranuras: tarjeta (con su luz) y recibo
	add("CardSlot", Vector3.new(0.42, 0.12, 0.06), CFrame.new(0.75, 1.15, -0.92), Color3.fromRGB(12, 12, 12), Enum.Material.SmoothPlastic)
	add("CardLed", Vector3.new(0.08, 0.08, 0.04), CFrame.new(0.75, 1.27, -0.92), SCREEN_COLOR, Enum.Material.Neon)
	add("ReceiptSlot", Vector3.new(0.45, 0.06, 0.06), CFrame.new(-0.75, 1.15, -0.92), Color3.fromRGB(12, 12, 12), Enum.Material.SmoothPlastic)
	add("Receipt", Vector3.new(0.35, 0.02, 0.5), CFrame.new(-0.75, 1.05, -1.1) * CFrame.Angles(math.rad(-60), 0, 0), Color3.fromRGB(245, 245, 235), Enum.Material.SmoothPlastic)
	-- Ranura de billetes: su "boca", con dientes de metal y billetes asomando
	add("Slot", Vector3.new(1.4, 0.15, 0.1), CFrame.new(0, 0.2, -0.92), Color3.fromRGB(15, 15, 15), Enum.Material.SmoothPlastic)
	add("SlotFrame", Vector3.new(1.6, 0.4, 0.05), CFrame.new(0, 0.2, -0.9), STEEL)
	for i = 0, 5 do
		local x = -0.6 + i * 0.24
		-- (cuña girada: el triangulo se ve de frente; arriba apuntan hacia abajo)
		local sideways = CFrame.Angles(0, math.rad(90), 0)
		add("Tooth", Vector3.new(0.05, 0.16, 0.14), CFrame.new(x, 0.33, -0.97) * sideways * CFrame.Angles(math.rad(180), 0, 0), Color3.fromRGB(230, 225, 210), Enum.Material.SmoothPlastic, { Shape = Enum.PartType.Wedge })
		add("Tooth", Vector3.new(0.05, 0.13, 0.14), CFrame.new(x + 0.12, 0.08, -0.97) * sideways, Color3.fromRGB(230, 225, 210), Enum.Material.SmoothPlastic, { Shape = Enum.PartType.Wedge })
	end
	local BILL = Color3.fromRGB(120, 190, 110)
	add("Bill", Vector3.new(0.55, 0.02, 0.45), CFrame.new(-0.25, 0.17, -1.12) * CFrame.Angles(math.rad(-10), math.rad(8), 0), BILL, Enum.Material.SmoothPlastic)
	add("Bill", Vector3.new(0.55, 0.02, 0.35), CFrame.new(0.3, 0.2, -1.08) * CFrame.Angles(math.rad(12), math.rad(-15), 0), BILL, Enum.Material.SmoothPlastic)
	-- Rejillas de ventilacion a los lados
	for _, x in { -1.31, 1.31 } do
		for i = 0, 4 do
			add("Vent", Vector3.new(0.04, 0.07, 1.1), CFrame.new(x, -0.1 + i * 0.16, 0.1), DARK)
		end
	end
	-- Pegatina vieja de "FUERA DE SERVICIO" (torcida)
	local sticker = add("Sticker", Vector3.new(0.75, 0.38, 0.02), CFrame.new(-0.8, -0.3, -0.91) * CFrame.Angles(0, 0, math.rad(9)), Color3.fromRGB(250, 220, 60), Enum.Material.SmoothPlastic)
	text(sticker, Enum.NormalId.Front, Vector2.new(150, 76), "FUERA DE\nSERVICIO", Color3.fromRGB(30, 30, 30), Enum.Font.GothamBold)
	-- Caderas, patas largas con rodilla y piston, y pies con garras
	for _, x in { -0.8, 0.8 } do
		add("Hip", Vector3.new(0.65, 0.35, 0.65), CFrame.new(x, -0.82, 0), DARK)
		add("Leg", Vector3.new(0.35, 2.6, 0.35), CFrame.new(x, -1.7, 0), Color3.fromRGB(60, 62, 66))
		local knee = add("Knee", Vector3.new(0.5, 0.5, 0.5), CFrame.new(x, -1.75, 0), DARK, Enum.Material.Metal, { Shape = Enum.PartType.Ball })
		knee:SetAttribute("Follow", "Leg")
		local piston = add("Piston", Vector3.new(0.12, 1.3, 0.12), CFrame.new(x, -1.2, 0.24), STEEL)
		piston:SetAttribute("Follow", "Leg")
		add("Foot", Vector3.new(0.6, 0.2, 0.9), CFrame.new(x, -2.9, -0.15), Color3.fromRGB(40, 40, 42))
		for _, toe in { -0.18, 0.18 } do
			local claw = add("Claw", Vector3.new(0.14, 0.14, 0.3), CFrame.new(x + toe, -2.93, -0.7), STEEL, Enum.Material.Metal, { Shape = Enum.PartType.Wedge })
			claw:SetAttribute("Follow", "Leg")
		end
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

-- Animacion del robo: tus billetes salen volando y se meten por su ranura (con un "ding").
function Cashier:PlayStealEffect(player: Player)
	local root = Common.getRoot(player)
	local slot = self.Model:FindFirstChild("Slot", true) :: BasePart?
	if not root or not slot then
		return
	end
	local ding = Instance.new("Sound")
	ding.SoundId = "rbxasset://sounds/electronicpingshort.wav"
	ding.Volume = 1.5
	ding.RollOffMaxDistance = 60
	ding.Parent = slot
	ding:Play()
	task.delay(2, function()
		ding:Destroy()
	end)
	for i = 1, 6 do
		local bill = Common.part({
			Name = "FlyingBill",
			Size = Vector3.new(0.55, 0.03, 0.3),
			CFrame = root.CFrame
				* CFrame.new((math.random() - 0.5) * 1.6, (math.random() - 0.5) * 1.4, -0.4)
				* CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6),
			Color = Color3.fromRGB(120, 190, 110),
			Material = Enum.Material.SmoothPlastic,
			CanQuery = false,
		})
		bill.Parent = self.Ctx.Container
		task.delay((i - 1) * 0.05, function()
			local tween = TweenService:Create(bill, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				CFrame = slot.CFrame,
				Size = Vector3.new(0.3, 0.02, 0.15),
			})
			tween:Play()
			tween.Completed:Wait()
			bill:Destroy()
		end)
	end
end

function Cashier:Steal(player: Player)
	local cash = RunState.GetCash(player)
	local amount = math.min(cash, math.max(self.Def.StealMin, math.floor(cash * self.Def.StealFraction)))
	if amount <= 0 or not RunState.TrySpend(player, amount) then
		return
	end
	self.Loot[player] = (self.Loot[player] or 0) + amount
	self:PlayStealEffect(player)
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
