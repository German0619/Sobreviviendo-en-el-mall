--!strict
-- LobbyRoulettes (solo en el lobby): anima las ruletas fisicas de la plaza
-- (server/RouletteService, server/RouletteBuilder).
--
--   * [E] en la consola: pide el giro (RequestWheelSpin). Si tu clase equipada es
--     Epica o superior, la primera pulsacion pide confirmar (como en el panel).
--   * La rueda gira con la hora del servidor: todos la ven igual, tambien quien
--     entra a mitad de un giro. Clic y lengueta por cada clavija que pasa.
--   * Bombillas: parpadeo suave en reposo, persecucion durante el giro y destello
--     del color de la rareza al terminar; cartel con el premio y confeti.
--   * La pantalla de la consola y el [E] muestran tu precio (VIP con descuento).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Tags = require(Shared.Tags)

local LobbyPanels = require(script.Parent.LobbyPanels)

local LobbyRoulettes = {}

local player = Players.LocalPlayer
local RC = Config.LobbyRoulettes
local DIAMOND = "💎"

local BULB_ON = Color3.fromRGB(255, 226, 160)
local BULB_OFF = Color3.fromRGB(95, 70, 40)

type Wheel = {
	model: Model,
	kind: string,
	frame: CFrame,
	sectorAngle: number,
	parts: { BasePart },
	offsets: { CFrame },
	cframes: { CFrame },
	flapper: BasePart?,
	pivot: CFrame?,
	flapOffset: CFrame?,
	flap: number,
	bulbs: { BasePart },
	labels: { [number]: SurfaceGui },
	prompt: ProximityPrompt?,
	screen: { [string]: TextLabel },
	tick: Sound,
	win: Sound,
	spinning: boolean,
	handledSpin: number,
	flashing: boolean,
	confirmUntil: number,
}

local wheels: { [Model]: Wheel } = {}

local function now(): number
	return Workspace:GetServerTimeNow()
end

----------------------------------------------------------------------
-- Precio y textos
----------------------------------------------------------------------

local function costOf(kind: string): number
	if kind == "Classes" then
		return Config.getSpinCost(player:GetAttribute("Pass_VIP") == true)
	end
	return Config.Cosmetics.SpinCost
end

local function refreshTexts(w: Wheel)
	local cost = costOf(w.kind)
	local s = w.screen
	if w.spinning then
		local who = w.model:GetAttribute("Spinner")
		if s.Action then
			s.Action.Text = "GIRANDO…"
		end
		if s.Price then
			s.Price.Text = if type(who) == "string" then who else ""
		end
		if s.Hint then
			s.Hint.Text = "Espera tu turno"
		end
		return
	end
	if s.Action then
		s.Action.Text = "GIRAR"
	end
	if s.Price then
		s.Price.Text = DIAMOND .. " " .. cost
	end
	if s.Hint then
		s.Hint.Text = if w.kind == "Classes" then "Reemplaza tu slot equipado" else "Repetida = +" .. Config.Cosmetics.DuplicateRefund .. " " .. DIAMOND
	end
	local prompt = w.prompt
	if prompt and os.clock() > w.confirmUntil then
		prompt.ActionText = "Girar"
		prompt.ObjectText = DIAMOND .. " " .. cost
	end
end

----------------------------------------------------------------------
-- Rueda
----------------------------------------------------------------------

local function placeRotor(w: Wheel, angle: number)
	local at = w.frame * CFrame.Angles(0, 0, -math.rad(angle))
	for i, offset in w.offsets do
		w.cframes[i] = at * offset
	end
	Workspace:BulkMoveTo(w.parts, w.cframes, Enum.BulkMoveMode.FireCFrameChanged)
end

local function placeFlapper(w: Wheel)
	if w.flapper and w.pivot and w.flapOffset then
		w.flapper.CFrame = w.pivot * CFrame.Angles(0, 0, math.rad(w.flap)) * w.flapOffset
	end
end

local function setBulbs(w: Wheel, fn: (index: number) -> boolean, onColor: Color3?)
	for _, b in w.bulbs do
		local on = fn((b:GetAttribute("Index") :: number?) or 0)
		b.Color = if on then (onColor or BULB_ON) else BULB_OFF
	end
end

local function rarityColor(rarity: any): Color3
	local r = if type(rarity) == "string" then Config.Rarities[rarity] else nil
	return if r then r.Color else Color3.new(1, 1, 1)
end

local function showResult(w: Wheel)
	local model = w.model
	local anchor = model:FindFirstChild("ResultAnchor", true) :: BasePart?
	local rarity = model:GetAttribute("ResultRarity")
	local color = rarityColor(rarity)
	local order = if type(rarity) == "string" and Config.Rarities[rarity] then Config.Rarities[rarity].Order else 1
	local mine = model:GetAttribute("SpinnerId") == player.UserId

	-- Sonido y confeti
	w.win.PlaybackSpeed = 0.85 + order * 0.08
	w.win.Volume = if mine then 0.9 else 0.5
	w.win:Play()
	if anchor then
		local confetti = anchor:FindFirstChild("Confetti") :: ParticleEmitter?
		if confetti then
			confetti:Emit(if order >= 3 then 140 else 45)
		end
		-- Cartel con el premio
		local bb = Instance.new("BillboardGui")
		bb.Name = "ResultBillboard"
		bb.Size = UDim2.fromScale(12, 3.4)
		bb.LightInfluence = 0
		bb.MaxDistance = 120
		bb.AlwaysOnTop = false
		bb.Adornee = anchor
		local who = Instance.new("TextLabel")
		who.BackgroundTransparency = 1
		who.Size = UDim2.fromScale(1, 0.32)
		who.Font = Enum.Font.GothamBold
		who.TextScaled = true
		who.TextColor3 = Color3.new(1, 1, 1)
		who.TextStrokeTransparency = 0.3
		local spinner = model:GetAttribute("Spinner")
		who.Text = (if type(spinner) == "string" then spinner else "") .. " consiguió"
		who.Parent = bb
		local prize = Instance.new("TextLabel")
		prize.BackgroundTransparency = 1
		prize.Position = UDim2.fromScale(0, 0.32)
		prize.Size = UDim2.fromScale(1, 0.68)
		prize.Font = Enum.Font.GothamBlack
		prize.TextScaled = true
		prize.TextColor3 = color
		prize.TextStrokeTransparency = 0
		prize.TextStrokeColor3 = Color3.new(0, 0, 0)
		local result = model:GetAttribute("Result")
		prize.Text = if type(result) == "string" then string.upper(result) else ""
		prize.Parent = bb
		local scale = Instance.new("UIScale")
		scale.Scale = 0.2
		scale.Parent = bb
		bb.Parent = anchor
		TweenService:Create(scale, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		task.delay(RC.ResultSeconds, function()
			if bb.Parent then
				TweenService:Create(scale, TweenInfo.new(0.3), { Scale = 0 }):Play()
				task.wait(0.3)
				bb:Destroy()
			end
		end)
	end

	-- El nombre del sector ganador parpadea y las bombillas destellan del color de la rareza
	local sector = model:GetAttribute("ResultSector")
	local gui = if type(sector) == "number" then w.labels[sector] else nil
	w.flashing = true
	task.spawn(function()
		local labels = {}
		if gui then
			for _, l in gui:GetChildren() do
				if l:IsA("TextLabel") then
					table.insert(labels, { l, l.TextColor3 })
				end
			end
		end
		for i = 1, 8 do
			local on = i % 2 == 1
			setBulbs(w, function()
				return on
			end, color)
			for _, entry in labels do
				entry[1].TextColor3 = if on then Color3.fromRGB(255, 225, 90) else entry[2]
			end
			task.wait(0.18)
		end
		for _, entry in labels do
			entry[1].TextColor3 = entry[2]
		end
		w.flashing = false
	end)
end

-- Anima el giro publicado en los atributos del modelo (si no esta ya animado).
local function runSpin(w: Wheel)
	local model = w.model
	local id = (model:GetAttribute("SpinId") :: number?) or 0
	if id == w.handledSpin then
		return
	end
	w.handledSpin = id
	local from = (model:GetAttribute("SpinFrom") :: number?) or 0
	local to = (model:GetAttribute("SpinTo") :: number?) or 0
	local start = (model:GetAttribute("SpinStart") :: number?) or 0
	local duration = (model:GetAttribute("SpinDuration") :: number?) or RC.SpinSeconds
	if now() >= start + duration then
		placeRotor(w, (model:GetAttribute("Angle") :: number?) or to % 360)
		return
	end

	w.spinning = true
	refreshTexts(w)
	local sa = w.sectorAngle
	local function pegIndex(angle: number): number
		return math.floor((angle - sa / 2) / sa)
	end
	local lastPeg = pegIndex(from)
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function(dt)
		local t = math.clamp((now() - start) / duration, 0, 1)
		-- Frena como una rueda de verdad (rapida al principio, lenta al final)
		local eased = 1 - (1 - t) ^ 4
		local angle = from + (to - from) * eased
		placeRotor(w, angle)

		local peg = pegIndex(angle)
		if peg ~= lastPeg then
			lastPeg = peg
			w.flap = 30
			w.tick.PlaybackSpeed = 0.95 + math.random() * 0.15
			w.tick.TimePosition = 0
			w.tick:Play()
		end
		w.flap = math.max(0, w.flap - dt * 220)
		placeFlapper(w)

		-- Bombillas en persecucion (mas lenta al frenar)
		if not w.flashing then
			local step = math.floor(angle / 9)
			setBulbs(w, function(index)
				return (index + step) % 3 == 0
			end)
		end

		if t >= 1 then
			conn:Disconnect()
			placeRotor(w, to)
			w.flap = 0
			placeFlapper(w)
			w.spinning = false
			refreshTexts(w)
			showResult(w)
		end
	end)
end

----------------------------------------------------------------------
-- Registro de cada rueda
----------------------------------------------------------------------

local function sound(parent: Instance, id: string, volume: number): Sound
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = 10
	s.RollOffMaxDistance = 70
	s.Parent = parent
	return s
end

local function setup(model: Instance)
	if not model:IsA("Model") or wheels[model] then
		return
	end
	local kind = model:GetAttribute("Roulette")
	local frame = model:GetAttribute("WheelFrame")
	local sectors = model:GetAttribute("Sectors")
	local rotor = model:WaitForChild("Rotor", 10)
	if type(kind) ~= "string" or typeof(frame) ~= "CFrame" or type(sectors) ~= "number" or not rotor then
		return
	end

	local parts, offsets, labels = {}, {}, {}
	for _, p in rotor:GetChildren() do
		local offset = p:GetAttribute("RotorOffset")
		if p:IsA("BasePart") and typeof(offset) == "CFrame" then
			table.insert(parts, p)
			table.insert(offsets, offset)
			local sector = p:GetAttribute("Sector")
			local gui = p:FindFirstChildOfClass("SurfaceGui")
			if type(sector) == "number" and gui then
				labels[sector] = gui
			end
		end
	end
	local bulbs = {}
	local bulbFolder = model:FindFirstChild("Bulbs", true)
	if bulbFolder then
		for _, b in bulbFolder:GetChildren() do
			if b:IsA("BasePart") then
				table.insert(bulbs, b)
			end
		end
	end
	local flapper = model:FindFirstChild("Flapper", true) :: BasePart?
	local pivot = flapper and flapper:GetAttribute("Pivot")
	local flapOffset = flapper and flapper:GetAttribute("PivotOffset")
	local screen = {}
	local screenPart = model:FindFirstChild("Screen", true)
	local screenGui = screenPart and screenPart:FindFirstChild("ScreenGui")
	if screenGui then
		for _, l in screenGui:GetDescendants() do
			if l:IsA("TextLabel") then
				screen[l.Name] = l
			end
		end
	end
	local pointerPart = model:FindFirstChild("PointerMount", true) or model.PrimaryPart or model

	local w: Wheel = {
		model = model,
		kind = kind,
		frame = frame,
		sectorAngle = 360 / sectors,
		parts = parts,
		offsets = offsets,
		cframes = table.create(#parts),
		flapper = flapper,
		pivot = if typeof(pivot) == "CFrame" then pivot else nil,
		flapOffset = if typeof(flapOffset) == "CFrame" then flapOffset else nil,
		flap = 0,
		bulbs = bulbs,
		labels = labels,
		prompt = model:FindFirstChild("SpinPrompt", true) :: ProximityPrompt?,
		screen = screen,
		tick = sound(pointerPart, "rbxasset://sounds/clickfast.wav", 0.6),
		win = sound(pointerPart, "rbxasset://sounds/electronicpingshort.wav", 0.8),
		spinning = false,
		handledSpin = -1,
		flashing = false,
		confirmUntil = 0,
	}
	wheels[model] = w

	-- Estado inicial (o giro en curso al entrar)
	local current = (model:GetAttribute("SpinId") :: number?) or 0
	local start = (model:GetAttribute("SpinStart") :: number?) or 0
	local duration = (model:GetAttribute("SpinDuration") :: number?) or 0
	if current > 0 and now() < start + duration then
		runSpin(w)
	else
		w.handledSpin = current
		placeRotor(w, (model:GetAttribute("Angle") :: number?) or 0)
	end
	refreshTexts(w)
	model:GetAttributeChangedSignal("SpinId"):Connect(function()
		runSpin(w)
	end)
	model.Destroying:Connect(function()
		wheels[model] = nil
	end)
end

----------------------------------------------------------------------
-- [E] en la consola
----------------------------------------------------------------------

local requesting = false

local function onSpinPrompt(prompt: ProximityPrompt, kind: string)
	if requesting then
		return
	end
	local w: Wheel? = nil
	for _, wheel in wheels do
		if wheel.prompt == prompt then
			w = wheel
		end
	end
	local title = if kind == "Classes" then "Ruleta de clases" else "Ruleta de skins"

	-- Proteger las clases Epicas o mejores: la primera pulsacion pide confirmar
	if kind == "Classes" and w then
		local equipped = player:GetAttribute("EquippedClass")
		local class = if type(equipped) == "string" then Config.Classes[equipped] else nil
		local rarity = class and Config.Rarities[class.Rarity]
		if class and rarity and rarity.Order >= 3 and os.clock() > w.confirmUntil then
			w.confirmUntil = os.clock() + 4
			prompt.ActionText = "Confirmar giro"
			prompt.ObjectText = "Reemplaza a " .. class.DisplayName
			LobbyPanels.notify(
				title,
				string.format("Tienes %s (%s) en el slot equipado. Pulsa otra vez para girar y reemplazarla.", class.DisplayName, rarity.DisplayName),
				4
			)
			local wheel = w
			task.delay(4.05, function()
				refreshTexts(wheel)
			end)
			return
		end
		w.confirmUntil = 0
	end

	requesting = true
	local ok, message = Remotes.func("RequestWheelSpin"):InvokeServer(kind)
	requesting = false
	if w then
		refreshTexts(w)
	end
	if not ok then
		LobbyPanels.notify(title, if type(message) == "string" then message else "No se pudo girar.", 4)
	end
end

function LobbyRoulettes.Start()
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
		local kind = prompt:GetAttribute("Roulette")
		if type(kind) == "string" then
			task.spawn(onSpinPrompt, prompt, kind)
		end
	end)

	for _, model in CollectionService:GetTagged(Tags.LobbyRoulette) do
		task.spawn(setup, model)
	end
	CollectionService:GetInstanceAddedSignal(Tags.LobbyRoulette):Connect(function(model)
		task.spawn(setup, model)
	end)

	-- El precio cambia con el pase VIP
	player:GetAttributeChangedSignal("Pass_VIP"):Connect(function()
		for _, w in wheels do
			refreshTexts(w)
		end
	end)

	-- Bombillas en reposo: parpadeo suave alterno
	task.spawn(function()
		local phase = 0
		while true do
			task.wait(0.6)
			phase += 1
			for _, w in wheels do
				if not w.spinning and not w.flashing then
					setBulbs(w, function(index)
						return (index + phase) % 2 == 0
					end)
				end
			end
		end
	end)
end

return LobbyRoulettes
