-- Megafonia: una voz en los altavoces del mall, sin cuerpo. Cada cierto tiempo pone una
-- TAREA FALSA: su marca "!" (igual que la de una tarea de verdad, visible en todo el mapa)
-- en una zona lejos de los jugadores. (Ni las reales ni las falsas tienen aviso.) Si alguien se acerca a la marca, salta una alarma que
-- atrae a todos los enemigos cercanos (un petardo enorme).
--
-- Contramedidas: las tareas falsas NO salen en la lista de tareas del HUD; el
-- destello sobre la marca la borra; la linterna UV la delata (se pone morada y dice
-- FALSA para todos).
--
-- El "modelo" es la propia marca: solo esta en el mapa mientras hay una tarea falsa.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local TweenService = game:GetService("TweenService")

local Server = ServerScriptService:WaitForChild("Server")
local DefenseService = require(Server:WaitForChild("DefenseService"))
local LightService = require(Server:WaitForChild("LightService"))

local Common = require(script.Parent.Common)

local MARKER_COLOR = Color3.fromRGB(255, 200, 60) -- igual que las marcas de MissionService
local FAKE_COLOR = Color3.fromRGB(190, 90, 255)
local ALARM_COLOR = Color3.fromRGB(255, 40, 40)

local Intercom = {}
Intercom.__index = Intercom

local function buildModel(): (Model, BasePart, TextLabel)
	local model, root = Common.newModel("Intercom", 2)
	root.CanQuery = false
	-- Misma marca que una tarea real (MissionService.addMarker)
	local gui = Instance.new("BillboardGui")
	gui.Name = "MissionMarker"
	gui.Size = UDim2.fromOffset(36, 36)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 3, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = math.huge -- como las reales: se ve desde cualquier punto del mapa
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = "!"
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = MARKER_COLOR
	label.TextStrokeTransparency = 0.3
	label.Parent = gui
	gui.Parent = root
	return model, root, label
end

-- Nombre de una tarea real al azar (para que el anuncio sea creible).
local function randomMissionName(): string
	local names = {}
	for _, def in Config.Missions do
		if type(def) == "table" and def.DisplayName then
			table.insert(names, def.DisplayName)
		end
	end
	return if #names > 0 then names[math.random(1, #names)] else "Revisar la zona"
end

function Intercom.new(spawnPosition: Vector3, ctx)
	local def = Config.Enemies.Intercom
	local model, root, label = buildModel()
	Common.prepareModel(model)

	local self = setmetatable({}, Intercom)
	self.Def = def
	self.Ctx = ctx
	self.Model = model
	self.Root = root
	self.Label = label
	self.Floor = Config.getFloor(spawnPosition.Y)
	self.Active = false
	self.NextAnnounce = os.clock() + def.FirstDelay
	self.ExpiresAt = 0
	self.Revealed = false
	return self
end

-- Punto para la tarea falsa: en su planta, ni muy cerca ni muy lejos de los jugadores.
function Intercom:PickPoint(): Vector3?
	local fallback = nil
	for _ = 1, 12 do
		local point = Common.randomPatrolPoint()
		if point and Config.getFloor(point.Y) == self.Floor then
			local _, _, d = Common.nearestAlive(point)
			if d >= self.Def.MinDistance and d <= self.Def.MaxDistance then
				return point
			end
			fallback = fallback or (if d >= self.Def.MinDistance * 0.5 then point else nil)
		end
	end
	return fallback
end

function Intercom:Announce(): boolean
	local point = self:PickPoint()
	if not point then
		return false
	end
	local zone = LightService.GetZoneAt(point) or "Mall"
	self.Root.CFrame = CFrame.new(point + Vector3.new(0, 1, 0))
	self.Label.Text = "!"
	self.Label.TextColor3 = MARKER_COLOR
	;(self.Label.Parent :: BillboardGui).Size = UDim2.fromOffset(36, 36)
	self.Revealed = false
	self.Model.Parent = self.Ctx.Container
	self.Active = true
	self.ExpiresAt = os.clock() + self.Def.FakeLifetime
	-- (Sin aviso, como las tareas de verdad: solo la marca)
	local name = randomMissionName()
	if RunService:IsStudio() then
		print(string.format("[Megafonía] Tarea FALSA: %s (%s) en %s", name, zone, tostring(point)))
	end
	return true
end

function Intercom:Clear()
	self.Active = false
	self.Model.Parent = nil
	self.NextAnnounce = os.clock() + self.Def.Interval[1] + math.random() * (self.Def.Interval[2] - self.Def.Interval[1])
end

-- Alguien llego a la marca: alarma que atrae a los enemigos.
function Intercom:Trigger()
	local position = self.Root.Position
	DefenseService.AddLure(position, self.Def.LureSeconds, self.Def.LureRadius)

	local fx = Common.part({
		Name = "IntercomAlarm",
		Size = Vector3.new(0.2, 0.2, 0.2),
		Transparency = 1,
		CFrame = CFrame.new(position + Vector3.new(0, 3, 0)),
		CanQuery = false,
	})
	local light = Instance.new("PointLight")
	light.Color = ALARM_COLOR
	light.Range = 30
	light.Brightness = 4
	light.Parent = fx
	fx.Parent = self.Ctx.Container
	task.spawn(function()
		-- Parpadeo rojo de alarma
		for i = 1, 10 do
			if not fx.Parent then
				return
			end
			light.Enabled = i % 2 == 1
			task.wait(0.25)
		end
		TweenService:Create(light, TweenInfo.new(0.5), { Brightness = 0 }):Play()
		task.wait(0.5)
		fx:Destroy()
	end)

	for _, player in Common.getAlivePlayers() do
		local root = Common.getRoot(player)
		if root and (root.Position - position).Magnitude <= self.Def.LureRadius then
			Common.discover(player, "Intercom")
			Remotes.event("Notify"):FireClient(player, "¡Era una tarea falsa de la Megafonía! Los enemigos vienen hacia aquí.", "bad")
		end
	end
	self:Clear()
end

function Intercom:Update(_dt: number)
	local now = os.clock()
	if not self.Active then
		if now >= self.NextAnnounce and not self:Announce() then
			self.NextAnnounce = now + 5
		end
		return
	end
	if now >= self.ExpiresAt then
		self:Clear()
		return
	end
	local position = self.Root.Position
	for _, player in Common.getAlivePlayers() do
		local root = Common.getRoot(player)
		if root and not DefenseService.IsHidden(player) then
			local offset = root.Position - position
			if Vector3.new(offset.X, 0, offset.Z).Magnitude <= self.Def.TriggerRange and math.abs(offset.Y) < 6 then
				self:Trigger()
				return
			end
		end
	end
end

-- Destello sobre la marca: la borra.
function Intercom:OnFlash(player: Player)
	if self.Active then
		Remotes.event("Notify"):FireClient(player, "La tarea era falsa: la marca desapareció.", "good")
		self:Clear()
	end
end

-- Linterna UV: la delata (para todos).
function Intercom:OnUV(_player: Player, _seconds: number)
	if self.Active and not self.Revealed then
		self.Revealed = true
		self.Label.Text = "FALSA"
		self.Label.TextColor3 = FAKE_COLOR
		local gui = self.Label.Parent :: BillboardGui
		gui.Size = UDim2.fromOffset(90, 30)
	end
end

function Intercom:OnShove() end -- no tiene cuerpo
function Intercom:OnTaser() end

function Intercom:Destroy()
	self.Model:Destroy()
end

return Intercom
