-- Eco: un fantasma que se hace pasar por un companero.
--
-- Lleva el nombre de otro jugador encima, una "linterna" y suena a pasos. Te
-- oye a traves de las paredes (Config SenseRange), se acerca despacio y, si
-- nadie lo alumbra, se lanza contra ti al estar cerca. Tras golpear, se esfuma.
--
-- Contramedidas: alumbrarlo con la linterna (o tenerlo dentro de una bengala)
-- lo revela y lo hace desaparecer; el destello y el porrazo, al instante; los
-- petardos lo distraen; esconderse rompe la persecucion. El Medium lo ve a
-- traves de las paredes (es un fantasma).
--
-- Estados: Stalk (acecha) <-> Vanished (desaparecido unos segundos)

local ServerScriptService = game:GetService("ServerScriptService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)

local Server = ServerScriptService:WaitForChild("Server")
local FlashlightService = require(Server:WaitForChild("FlashlightService"))
local DefenseService = require(Server:WaitForChild("DefenseService"))

local Common = require(script.Parent.Common)

local HEIGHT = 5.5
local HIDDEN_CFRAME = CFrame.new(0, -500, 0) -- donde espera mientras esta desaparecido
local FOOTSTEPS = "rbxasset://sounds/action_footsteps_plastic.mp3" -- sonido incluido en Roblox

local DISGUISE_COLOR = Color3.fromRGB(60, 75, 95) -- uniforme de conserje
local SKIN_COLOR = Color3.fromRGB(190, 160, 130)
local REVEALED_COLOR = Color3.fromRGB(8, 8, 10)

local Echo = {}
Echo.__index = Echo

local function buildModel(): Model
	local model, _root = Common.newModel("Echo", HEIGHT)
	local function add(name, size, offset, color, shape)
		local p = Common.part({
			Name = name,
			Size = size,
			CFrame = CFrame.new(offset),
			Color = color,
			Material = Enum.Material.SmoothPlastic,
		})
		if shape then
			p.Shape = shape
		end
		p:SetAttribute("DisguiseColor", color)
		p.Parent = model
		return p
	end
	add("LeftLeg", Vector3.new(0.8, 2, 0.8), Vector3.new(-0.45, -1.75, 0), DISGUISE_COLOR)
	add("RightLeg", Vector3.new(0.8, 2, 0.8), Vector3.new(0.45, -1.75, 0), DISGUISE_COLOR)
	add("Torso", Vector3.new(1.8, 2, 0.9), Vector3.new(0, 0.25, 0), DISGUISE_COLOR)
	add("LeftArm", Vector3.new(0.7, 2, 0.7), Vector3.new(-1.25, 0.25, 0), DISGUISE_COLOR)
	add("RightArm", Vector3.new(0.7, 2, 0.7), Vector3.new(1.25, 0.25, 0), DISGUISE_COLOR)
	local head = add("Head", Vector3.new(1.1, 1.1, 1.1), Vector3.new(0, 1.85, 0), SKIN_COLOR)

	-- Ojos: solo se ven cuando lo alumbran
	for _, x in { -0.25, 0.25 } do
		local eye = Common.part({
			Name = "Eye",
			Size = Vector3.new(0.2, 0.12, 0.05),
			CFrame = CFrame.new(x, 1.95, -0.56),
			Color = Color3.fromRGB(255, 255, 255),
			Material = Enum.Material.Neon,
			Transparency = 1,
		})
		eye.Parent = model
	end

	-- Linterna falsa (como la de un companero)
	local light = Instance.new("SpotLight")
	light.Name = "FakeFlashlight"
	light.Face = Enum.NormalId.Front
	light.Range = 30
	light.Angle = 50
	light.Brightness = 2
	light.Color = Color3.fromRGB(255, 244, 214)
	light.Parent = head

	-- Nombre falso sobre la cabeza (imita la etiqueta de un jugador)
	local tag = Instance.new("BillboardGui")
	tag.Name = "NameTag"
	tag.Size = UDim2.fromOffset(200, 24)
	tag.StudsOffsetWorldSpace = Vector3.new(0, 1.6, 0)
	tag.MaxDistance = 70
	tag.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamMedium
	label.TextSize = 18
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.5
	label.Text = ""
	label.Parent = tag
	tag.Parent = head

	return model
end

function Echo.new(spawnPosition: Vector3, ctx)
	local def = Config.Enemies.Echo
	local model = Common.getTemplate("Echo") or buildModel()
	local height = Common.getHeight(model)
	Common.prepareModel(model)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false -- atraviesa paredes
		end
	end
	model:SetAttribute("Ghost", true) -- el Medium lo ve a traves de las paredes

	local hoverY = spawnPosition.Y + height / 2
	model:PivotTo(CFrame.new(Vector3.new(spawnPosition.X, hoverY, spawnPosition.Z)))
	model.Parent = ctx.Container

	local root = model.PrimaryPart :: BasePart
	local steps = Instance.new("Sound")
	steps.Name = "Footsteps"
	steps.SoundId = FOOTSTEPS
	steps.Looped = true
	steps.Volume = 0.9
	steps.PlaybackSpeed = 1.1
	steps.RollOffMaxDistance = 70
	steps.RollOffMinDistance = 8
	steps.Parent = root

	local self = setmetatable({}, Echo)
	self.Def = def
	self.Ctx = ctx
	self.Model = model
	self.Height = height
	self.Steps = steps
	self.Mover = Common.newMover(model, { Speed = def.Speed, Height = height, Ghost = true, HoverY = hoverY })
	self.Awareness = Common.newAwareness(ctx)
	self.State = "Stalk"
	self.ReappearAt = 0
	self.Exposure = 0
	self.Revealed = false
	self.LastAttack = 0
	self.PatrolPoint = nil :: Vector3?
	self.NextDisguise = 0
	self:SetDisguiseName(nil)
	return self
end

function Echo:GetSpeedMultiplier(): number
	local threatBonus = 1 + Config.Threat.SpeedPerFailedMission * self.Ctx.GetTotalThreat()
	return self.Ctx.Difficulty.SpeedMultiplier * threatBonus
end

-- Nombre de otro jugador vivo (no el de su presa). Jugando solo: "???".
function Echo:SetDisguiseName(target: Player?)
	local candidates = {}
	for _, player in Common.getAlivePlayers() do
		if player ~= target then
			table.insert(candidates, player)
		end
	end
	local label = self.Model:FindFirstChild("Label", true)
	if label and label:IsA("TextLabel") then
		label.Text = if #candidates > 0 then candidates[math.random(1, #candidates)].DisplayName else "???"
	end
end

-- Al alumbrarlo se ve lo que es: negro, ojos brillantes, sin linterna ni nombre.
function Echo:SetRevealed(revealed: boolean)
	if self.Revealed == revealed then
		return
	end
	self.Revealed = revealed
	for _, d in self.Model:GetDescendants() do
		if d:IsA("BasePart") then
			if d.Name == "Eye" then
				d.Transparency = if revealed then 0 else 1
			elseif d:GetAttribute("DisguiseColor") then
				d.Color = if revealed then REVEALED_COLOR else d:GetAttribute("DisguiseColor")
				-- Plantilla con malla texturizada (ServerStorage.EnemyTemplates.Echo):
				-- sin textura queda la silueta negra.
				local texture = d:GetAttribute("DisguiseTexture")
				if d:IsA("MeshPart") and type(texture) == "string" then
					d.TextureID = if revealed then "" else texture
				end
			end
		elseif d:IsA("SpotLight") then
			d.Enabled = not revealed
		elseif d:IsA("BillboardGui") then
			d.Enabled = not revealed
		end
	end
end

function Echo:Vanish()
	self.State = "Vanished"
	self.ReappearAt = os.clock() + self.Def.VanishSeconds
	self.Exposure = 0
	self.Mover:Clear()
	self.Steps:Stop()
	self.Model:PivotTo(HIDDEN_CFRAME)
	self:SetRevealed(false)
end

-- Vuelve en un punto lejos de los jugadores.
function Echo:Reappear(): boolean
	local best = nil
	for _ = 1, 8 do
		local point = Common.randomPatrolPoint()
		if point then
			local _, _, dist = Common.nearestAlive(point)
			if dist >= self.Def.ReappearMinDistance then
				best = point
				break
			end
			best = best or point
		end
	end
	if not best then
		return false
	end
	local y = best.Y + self.Height / 2
	self.Mover.HoverY = y
	self.Model:PivotTo(CFrame.new(best.X, y, best.Z))
	self.State = "Stalk"
	self.PatrolPoint = nil
	return true
end

-- Avanza con el sonido de pasos.
function Echo:Walk(dt: number, target: Vector3, speed: number, groundY: number)
	self.Mover.HoverY = groundY + self.Height / 2
	self.Mover.Speed = speed
	self.Mover:MoveTowards(target)
	if self.Mover:Step(dt) then
		if not self.Steps.IsPlaying then
			self.Steps:Play()
		end
	elseif self.Steps.IsPlaying then
		self.Steps:Stop()
	end
end

function Echo:Update(dt: number)
	local now = os.clock()

	if self.State == "Vanished" then
		if now >= self.ReappearAt and not self:Reappear() then
			self.ReappearAt = now + 2
		end
		return
	end

	if Common.isStunned(self.Model) then
		self.Steps:Stop()
		return
	end

	local position = self.Model:GetPivot().Position

	-- 1) Alumbrado: se queda quieto, se revela y desaparece
	local chest = position + Vector3.new(0, self.Height * 0.15, 0)
	local lit = #FlashlightService.GetLightingPlayers(chest) > 0 or DefenseService.IsInFlare(position)
	if lit then
		self:SetRevealed(true)
		self.Steps:Stop()
		self.Exposure += dt
		if self.Exposure >= self.Def.ExposureToVanish then
			self:Vanish()
		end
		return
	end
	self.Exposure = math.max(0, self.Exposure - dt)
	self:SetRevealed(false)

	local groundY = position.Y - self.Height / 2
	local multiplier = self:GetSpeedMultiplier()

	-- 2) Un petardo lo distrae
	local lure = DefenseService.GetLure(position)
	if lure then
		self:Walk(dt, lure, self.Def.LungeSpeed * multiplier, lure.Y)
		return
	end

	-- 3) Te oye aunque haya paredes
	local target, root, dist, targetPos = self.Awareness:Update(dt, position, function(_player, r)
		return (r.Position - position).Magnitude <= self.Def.SenseRange
	end)

	if not target or not root or not targetPos then
		-- Merodea entre zonas
		local flat = self.PatrolPoint
			and Vector3.new(self.PatrolPoint.X - position.X, 0, self.PatrolPoint.Z - position.Z).Magnitude
		if not self.PatrolPoint or (flat and flat < 4) then
			self.PatrolPoint = Common.randomPatrolPoint()
		end
		if self.PatrolPoint then
			self:Walk(dt, self.PatrolPoint, self.Def.Speed * multiplier, self.PatrolPoint.Y)
		end
		return
	end

	-- Cambia de disfraz de vez en cuando (imita a otro companero)
	if now >= self.NextDisguise then
		self.NextDisguise = now + 20
		self:SetDisguiseName(target)
	end

	local speed = if dist <= self.Def.LungeDistance then self.Def.LungeSpeed else self.Def.Speed
	self:Walk(dt, targetPos, speed * multiplier, targetPos.Y - 3)

	if dist <= self.Def.AttackRange + 1 and now - self.LastAttack >= self.Def.AttackCooldown then
		self.LastAttack = now
		Common.damage(target, self.Def.Damage)
		self:Vanish() -- golpea y se esfuma
	end
end

-- Destello o porrazo: desaparece al instante.
function Echo:OnFlash(_player: Player)
	if self.State ~= "Vanished" then
		self:Vanish()
	end
end

function Echo:OnShove(player: Player, _direction: Vector3)
	self:OnFlash(player)
end

function Echo:Destroy()
	self.Mover:Destroy()
	self.Model:Destroy()
end

return Echo
