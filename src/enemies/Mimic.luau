-- Mimico: una de las maquinas expendedoras que YA estan en el mall (tag VendingMachine)
-- esta viva. No aparece ninguna maquina nueva ni se mueve: espera quieta.
--
-- Muerde (mucho dano) a quien intenta comprar en ella o se queda delante unos segundos.
-- Despues se esconde en OTRA maquina, lejos de los jugadores.
--
-- Pistas: si hay alguien cerca, de vez en cuando sus luces parpadean y gotea por la
-- bandeja. La linterna UV le ve los dientes; el destello (y el taser o un empujon)
-- le hace ensenar los dientes y lo deja un momento sin poder morder.
--
-- El "modelo" son los dientes y los ojos, ocultos dentro del frente de la maquina.

local CollectionService = game:GetService("CollectionService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Tags = require(Shared.Tags)
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local TweenService = game:GetService("TweenService")

local Server = ServerScriptService:WaitForChild("Server")
local DefenseService = require(Server:WaitForChild("DefenseService"))
local LightService = require(Server:WaitForChild("LightService"))
local VendingService = require(Server:WaitForChild("VendingService"))

local Common = require(script.Parent.Common)

local TOOTH_COLOR = Color3.fromRGB(240, 236, 220)
local EYE_COLOR = Color3.fromRGB(255, 210, 40)
local DROOL_COLOR = Color3.fromRGB(170, 210, 120)
-- Medidas del frente de la maquina (MallBuilder.vendingMachine): vitrina a la izquierda
local WIN_X, WIN_W, WIN_H = 0.75, 2.6, 4.7
local FRONT_Z = -1.56
local PIVOT_Z = -2.4

local Mimic = {}
Mimic.__index = Mimic

local function buildModel(): Model
	local model, root = Common.newModel("Mimic", 7)
	root.CanQuery = false
	-- El pivote queda delante del frente: el destello, la UV y el taser apuntan ahi
	-- (el centro de la maquina esta tapado por su propia caja de colision)
	root.PivotOffset = CFrame.new(0, 0, PIVOT_Z)
	-- Pieza oculta que aparece al enseñar los dientes. row: se cierra con esa fila al morder.
	local function hidden(name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, row: number?)
		local p = Common.part({
			Name = name,
			Size = size,
			CFrame = cf,
			Color = color,
			Material = material or Enum.Material.SmoothPlastic,
			Transparency = 1,
		})
		if row then
			p:SetAttribute("Row", row)
		else
			p:SetAttribute("Reveal", true)
		end
		p.Parent = model
		return p
	end
	-- Dientes arriba y abajo de la vitrina (cuñas que apuntan hacia dentro), de tamaños
	-- distintos y con dos colmillos largos en cada fila, sobre una encia oscura
	local count = 9
	local GUM = Color3.fromRGB(110, 25, 35)
	for row = 0, 1 do
		local edge = if row == 0 then WIN_H / 2 else -WIN_H / 2
		local inward = if row == 0 then -1 else 1
		hidden("Gum", Vector3.new(WIN_W, 0.3, 0.1), CFrame.new(WIN_X, edge + inward * 0.1, FRONT_Z + 0.04), GUM, nil, row)
		for i = 0, count - 1 do
			local x = WIN_X - WIN_W / 2 + (i + 0.5) * WIN_W / count
			local fang = i == 1 or i == count - 2
			local length = if fang then 0.85 else 0.4 + ((i * 7) % 3) * 0.08
			local tooth = hidden("Tooth", Vector3.new(0.24, length, 0.12), CFrame.new(x, edge + inward * (0.2 + length / 2), FRONT_Z) * CFrame.Angles(0, 0, if row == 0 then math.rad(180) else 0), TOOTH_COLOR, nil, row)
			tooth.Color = if fang then Color3.fromRGB(250, 248, 235) else TOOTH_COLOR:Lerp(Color3.fromRGB(200, 180, 120), ((i * 5) % 4) / 10)
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.Wedge
			mesh.Parent = tooth
		end
	end
	-- Lengua que cuelga por la bandeja
	hidden("Tongue", Vector3.new(0.9, 0.12, 1.0), CFrame.new(WIN_X, -WIN_H / 2 + 0.15, FRONT_Z - 0.4) * CFrame.Angles(math.rad(-35), 0, 0), Color3.fromRGB(200, 80, 100))
	hidden("TongueTip", Vector3.new(0.6, 0.12, 0.4), CFrame.new(WIN_X, -WIN_H / 2 - 0.25, FRONT_Z - 0.95) * CFrame.Angles(math.rad(-65), 0, 0), Color3.fromRGB(200, 80, 100))
	-- Ojos detras del vidrio, con pupila rasgada
	for _, x in { WIN_X - 0.6, WIN_X + 0.6 } do
		local eye = Common.part({
			Name = "Eye",
			Size = Vector3.new(0.4, 0.22, 0.05),
			CFrame = CFrame.new(x, 1.3, FRONT_Z + 0.08),
			Color = EYE_COLOR,
			Material = Enum.Material.Neon,
			Transparency = 1,
		})
		eye.Parent = model
		hidden("Pupil", Vector3.new(0.06, 0.2, 0.02), CFrame.new(x, 1.3, FRONT_Z + 0.04), Color3.fromRGB(10, 5, 5))
	end
	-- Babas por la bandeja
	local drool = Instance.new("ParticleEmitter")
	drool.Name = "Drool"
	drool.Color = ColorSequence.new(DROOL_COLOR)
	drool.LightEmission = 0.2
	drool.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.18), NumberSequenceKeypoint.new(1, 0.08) })
	drool.Transparency = NumberSequence.new(0.2)
	drool.Lifetime = NumberRange.new(0.6, 0.9)
	drool.Rate = 0
	drool.Speed = NumberRange.new(0.2, 0.6)
	drool.Acceleration = Vector3.new(0, -18, 0)
	drool.EmissionDirection = Enum.NormalId.Bottom
	local droolPart = Common.part({
		Name = "DroolPoint",
		Size = Vector3.new(0.2, 0.2, 0.2),
		CFrame = CFrame.new(WIN_X, -2.75, FRONT_Z),
		Transparency = 1,
		CanQuery = false,
	})
	drool.Parent = droolPart
	droolPart.Parent = model
	local glow = Instance.new("PointLight")
	glow.Name = "Glow"
	glow.Color = Color3.fromRGB(255, 60, 40)
	glow.Range = 10
	glow.Brightness = 0
	glow.Parent = root
	return model
end

function Mimic.new(spawnPosition: Vector3, ctx)
	local def = Config.Enemies.Mimic
	local model = buildModel()
	Common.prepareModel(model)

	local self = setmetatable({}, Mimic)
	self.Def = def
	self.Ctx = ctx
	self.Model = model
	self.Floor = Config.getFloor(spawnPosition.Y)
	self.Machine = nil :: BasePart?
	self.Lights = {} :: { Light }
	self.Linger = {} :: { [Player]: number }
	self.NextTell = os.clock() + 5
	self.CalmUntil = 0 -- aturdido / recien destellado: no muerde
	self.RevealUntil = 0
	self.RelocateAt = 0
	self.Warned = false
	self.Teeth, self.Eyes = {}, {}
	-- Teeth: se ven y se cierran al morder (dientes y encias, atributo Row).
	-- Eyes: solo se ven (ojos, pupilas, lengua: atributo Reveal).
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			if d:GetAttribute("Row") ~= nil then
				table.insert(self.Teeth, d)
			elseif d.Name == "Eye" or d:GetAttribute("Reveal") then
				table.insert(self.Eyes, d)
			end
		end
	end
	self.Drool = model:FindFirstChild("Drool", true) :: ParticleEmitter?
	self.Glow = model:FindFirstChild("Glow", true) :: PointLight?
	self.Conn = VendingService.MimicTriggered:Connect(function(player: Player, machine: BasePart)
		if machine == self.Machine then
			self:Bite(player)
		end
	end)
	self:Possess(false)
	return self
end

local function getMachines(): { BasePart }
	local list = {}
	for _, inst in CollectionService:GetTagged(Tags.VendingMachine) do
		if inst:IsA("BasePart") and inst:IsDescendantOf(workspace) then
			table.insert(list, inst)
		end
	end
	return list
end

-- Luces de la maquina (vitrina y brillo de la carcasa): piezas junto a la parte con el tag.
local function machineLights(machine: BasePart): { Light }
	local lights = {}
	local parent = machine.Parent
	if not parent then
		return lights
	end
	for _, child in parent:GetChildren() do
		if child:IsA("BasePart") and (child.Position - machine.Position).Magnitude < 3.8 then
			for _, light in child:GetChildren() do
				if light:IsA("Light") then
					table.insert(lights, light)
				end
			end
		end
	end
	return lights
end

-- Se mete en una maquina libre: en su planta y sin jugadores cerca (si se puede).
-- awayFromPlayers: al cambiar de maquina tras morder.
function Mimic:Possess(awayFromPlayers: boolean): boolean
	local best, bestScore = nil, -math.huge
	for _, machine in getMachines() do
		if machine:GetAttribute("Mimic") ~= true then
			local _, _, d = Common.nearestAlive(machine.Position)
			local score = math.random() * 10
			if Config.getFloor(machine.Position.Y) == self.Floor then
				score += 50
			end
			if d < 30 then
				score -= if awayFromPlayers then 1000 else 40
			end
			if score > bestScore then
				best, bestScore = machine, score
			end
		end
	end
	if not best then
		if not self.Warned then
			self.Warned = true
			warn("[Mimic] No hay maquinas expendedoras libres (tag VendingMachine): el Mimico espera")
		end
		return false
	end
	self.Machine = best
	best:SetAttribute("Mimic", true)
	self.Lights = machineLights(best)
	self.Linger = {}
	self.Model:PivotTo(best.CFrame * CFrame.new(0, 0, PIVOT_Z))
	self.Model.Parent = self.Ctx.Container
	self:SetRevealed(false)
	if RunService:IsStudio() then
		local zone = LightService.GetZoneAt(best.Position) or "?"
		print(string.format("[Mímico] Escondido en la máquina %s (%s, planta %d) en %s", best.Name, zone, Config.getFloor(best.Position.Y), tostring(best.Position)))
	end
	return true
end

function Mimic:Release()
	if self.Machine then
		self.Machine:SetAttribute("Mimic", nil)
	end
	for _, light in self.Lights do
		light.Enabled = true
	end
	self.Machine = nil
	self.Lights = {}
	self.Model.Parent = nil
end

function Mimic:SetRevealed(revealed: boolean)
	for _, p in self.Teeth do
		p.Transparency = if revealed then 0 else 1
	end
	for _, p in self.Eyes do
		p.Transparency = if revealed then 0 else 1
	end
	if self.Glow then
		self.Glow.Brightness = if revealed then 1.2 else 0
	end
end

-- Pista: parpadeo de luces y unas gotas por la bandeja.
function Mimic:Tell()
	if self.Drool then
		self.Drool:Emit(math.random(4, 8))
	end
	local lights = self.Lights
	task.spawn(function()
		for i = 1, 4 do
			for _, light in lights do
				light.Enabled = i % 2 == 0
			end
			task.wait(0.08 + math.random() * 0.08)
		end
		for _, light in lights do
			light.Enabled = true
		end
	end)
end

-- Muerde: dientes que se cierran, dano y aviso. Luego se esconde en otra maquina.
function Mimic:Bite(player: Player)
	local machine = self.Machine
	if not machine or os.clock() < self.CalmUntil or not Common.isAlive(player) then
		return
	end
	self.CalmUntil = os.clock() + 999 -- no muerde dos veces
	self:SetRevealed(true)
	-- Dientes: se cierran hacia el centro de la vitrina
	local base = self.Model:GetPivot()
	for _, tooth in self.Teeth do
		local row = tooth:GetAttribute("Row")
		local offset = if row == 0 then -1.6 else 1.6
		local cf = tooth.CFrame
		local tween = TweenService:Create(tooth, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			CFrame = cf + base.UpVector * offset,
		})
		tween:Play()
		task.delay(0.35, function()
			if tooth.Parent then
				TweenService:Create(tooth, TweenInfo.new(0.3), { CFrame = cf }):Play()
			end
		end)
	end
	Common.damage(player, self.Def.Damage)
	Common.discover(player, "Mimic")
	Remotes.event("Notify"):FireClient(player, "¡La máquina te mordió! Era un Mímico.", "bad")
	for _, other in Common.getAlivePlayers() do
		local root = Common.getRoot(other)
		if other ~= player and root and (root.Position - machine.Position).Magnitude < 40 then
			Common.discover(other, "Mimic")
			Remotes.event("Notify"):FireClient(other, "¡Una máquina expendedora era un Mímico!", "bad")
		end
	end
	-- Se queda enseñando los dientes un momento y se va a otra maquina
	task.delay(2.5, function()
		if self.Machine == machine then
			self:Release()
			self.RelocateAt = os.clock() + self.Def.RelocateSeconds
			self.CalmUntil = 0
		end
	end)
end

function Mimic:Update(dt: number)
	local now = os.clock()
	if not self.Machine then
		if now >= self.RelocateAt and not self:Possess(true) then
			self.RelocateAt = now + 5
		end
		return
	end
	local machine = self.Machine :: BasePart
	if not machine:IsDescendantOf(workspace) then
		self:Release()
		return
	end

	-- Revelado por la UV / el destello
	if self.RevealUntil > 0 and now >= self.RevealUntil and self.CalmUntil < now + 900 then
		self.RevealUntil = 0
		self:SetRevealed(false)
	end

	-- Pistas si hay alguien cerca
	local _, _, nearest = Common.nearestAlive(machine.Position)
	if nearest <= self.Def.TellRange and now >= self.NextTell then
		local range = self.Def.TellInterval
		self.NextTell = now + range[1] + math.random() * (range[2] - range[1])
		self:Tell()
	end

	if now < self.CalmUntil then
		return
	end
	-- Quedarse delante mucho rato tambien lo hace morder
	local front = machine.CFrame.LookVector -- el frente de la maquina es -Z (LookVector)
	for _, player in Common.getAlivePlayers() do
		local root = Common.getRoot(player)
		local inFront = false
		if root and not DefenseService.IsHidden(player) then
			local offset = root.Position - machine.Position
			local flat = Vector3.new(offset.X, 0, offset.Z)
			inFront = flat.Magnitude <= self.Def.BiteRange and math.abs(offset.Y) < 6 and flat:Dot(front) > 0
		end
		if inFront then
			self.Linger[player] = (self.Linger[player] or 0) + dt
			if self.Linger[player] >= self.Def.LingerSeconds then
				self:Bite(player)
				return
			end
		else
			self.Linger[player] = nil
		end
	end
end

-- Se delata (ensena los dientes) y queda un momento sin poder morder.
function Mimic:Expose(seconds: number, calmSeconds: number?)
	if not self.Machine then
		return
	end
	self.RevealUntil = os.clock() + seconds
	self:SetRevealed(true)
	if calmSeconds then
		self.CalmUntil = math.max(self.CalmUntil, os.clock() + calmSeconds)
	end
end

-- (La UV y el destello le hacen enseñar los dientes: quien lo hizo ve lo que es)
function Mimic:OnUV(player: Player, seconds: number)
	self:Expose(math.max(seconds, 1))
	Common.discover(player, "Mimic")
end

function Mimic:OnFlash(player: Player)
	self:Expose(self.Def.RevealSeconds, 3)
	Common.discover(player, "Mimic")
end

function Mimic:OnTaser(_player: Player)
	self:Expose(self.Def.RevealSeconds, Config.Weapons.Taser.Tier3StunSeconds + 1)
end

function Mimic:OnShove(_player: Player, _direction: Vector3, _strength: any)
	self:Expose(self.Def.RevealSeconds, 1)
end

function Mimic:Destroy()
	if self.Conn then
		self.Conn.Disconnect()
	end
	self:Release()
	self.Model:Destroy()
end

return Mimic
