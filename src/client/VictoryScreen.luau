-- VictoryScreen (mall): celebracion al ganar la noche (las 6 AM).
--   Destello dorado de pantalla, rayos de luz que giran, confeti, "¡SOBREVIVISTE!"
--   enorme que entra de golpe, la noche superada y el pago con el total contando.
--   Dura Config.Night.VictorySeconds al empezar la preparacion de la siguiente noche
--   (despues se abre sola la ventana de mejoras: UpgradeUI). No bloquea los clics.
-- El fin de partida (cae todo el equipo) lo sigue mostrando el panel del HUD.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local Remotes = require(Shared.Remotes)
local GameState = require(Shared.GameState)
local UIKit = require(script.Parent.UIKit)

local player = Players.LocalPlayer
local C = UIKit.COLORS
local make = UIKit.make

local VictoryScreen = {}

local GOLD = Color3.fromRGB(255, 210, 80)
local GOLD_DEEP = Color3.fromRGB(255, 150, 40)
local CONFETTI_COLORS = {
	GOLD,
	Color3.fromRGB(255, 245, 200),
	Color3.fromRGB(100, 220, 130),
	Color3.fromRGB(110, 180, 255),
	Color3.fromRGB(255, 120, 150),
	GOLD_DEEP,
}
local RAY_COUNT = 8 -- franjas que cruzan el centro (= 16 rayos)
local GLOW_SIZE = 0.75 -- diametro del resplandor (fraccion del ancho de pantalla)

local fxGui: ScreenGui -- capas a pantalla completa (sin margenes ni escala)
local gui: ScreenGui -- textos y tarjeta del pago (escalados)
local flash, dim, rays, glow, confettiLayer
local edges, glowParts = {}, {}
local hiding = false
local content, contentScale, tagLabel, titleLabel, nightLabel, card, cardScale, linesLabel, totalLabel
local rayConnection: RBXScriptConnection? = nil
local token = 0
local rng = Random.new()

----------------------------------------------------------------------
-- Construccion
----------------------------------------------------------------------

local function build()
	local playerGui = player:WaitForChild("PlayerGui")
	fxGui = make("ScreenGui", {
		Name = "VictoryFX",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ScreenInsets = Enum.ScreenInsets.None,
		DisplayOrder = 3, -- encima del HUD; los textos (4) encima; las ventanas (5) encima de todo
		Enabled = false,
		Parent = playerGui,
	})
	gui = make("ScreenGui", {
		Name = "Victory",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 4,
		Enabled = false,
		Parent = playerGui,
	})
	UIKit.adapt(gui)

	-- Oscurece un poco el mall para que resalte el oro
	dim = make("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = fxGui,
	})

	-- Resplandor detras del titulo: dos circulos con degradado cruzado (horizontal y
	-- vertical), que juntos dejan el centro brillante y se apagan hacia fuera
	glow = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.36),
		Size = UDim2.fromScale(GLOW_SIZE, GLOW_SIZE),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = fxGui,
	}, { make("UIAspectRatioConstraint", { AspectRatio = 1 }) })
	for _, rotation in { 0, 90 } do
		table.insert(glowParts, make("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = GOLD,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = 2,
			Parent = glow,
		}, {
			make("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
			make("UIGradient", {
				Rotation = rotation,
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 1),
					NumberSequenceKeypoint.new(0.5, 0.25),
					NumberSequenceKeypoint.new(1, 1),
				}),
			}),
		}))
	end

	rays = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.36),
		Size = UDim2.fromScale(1.6, 1.6),
		BackgroundTransparency = 1,
		ZIndex = 3,
		Parent = fxGui,
	}, { make("UIAspectRatioConstraint", { AspectRatio = 1 }) })
	for i = 1, RAY_COUNT do
		make("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(0.07, 0, 1, 0),
			Rotation = (i - 1) * (180 / RAY_COUNT),
			BackgroundColor3 = Color3.fromRGB(255, 230, 150),
			BackgroundTransparency = 0,
			BorderSizePixel = 0,
			ZIndex = 3,
			Parent = rays,
		}, {
			make("UIGradient", {
				Rotation = 90,
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 1),
					NumberSequenceKeypoint.new(0.5, 0.55),
					NumberSequenceKeypoint.new(1, 1),
				}),
			}),
		})
	end

	-- Bordes de pantalla dorados
	for _, spec in {
		{ UDim2.fromScale(0, 0), UDim2.fromScale(1, 0.16), 90 },
		{ UDim2.fromScale(0, 0.84), UDim2.fromScale(1, 0.16), -90 },
		{ UDim2.fromScale(0, 0), UDim2.fromScale(0.1, 1), 0 },
		{ UDim2.fromScale(0.9, 0), UDim2.fromScale(0.1, 1), 180 },
	} do
		table.insert(edges, make("Frame", {
			Position = spec[1],
			Size = spec[2],
			BackgroundColor3 = GOLD,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = 4,
			Parent = fxGui,
		}, {
			make("UIGradient", { Rotation = spec[3], Transparency = NumberSequence.new(0, 1) }),
		}))
	end

	confettiLayer = make("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 6,
		Parent = fxGui,
	})

	-- Destello blanco-dorado del primer instante
	flash = make("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(255, 240, 200),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 10,
		Parent = fxGui,
	})

	-- Textos
	content = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.36),
		Size = UDim2.fromOffset(820, 190),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	contentScale = make("UIScale", { Parent = content })
	tagLabel = UIKit.text({
		Size = UDim2.new(1, 0, 0, 30),
		Font = UIKit.FONT_BLACK,
		TextSize = 24,
		TextColor3 = GOLD,
		Text = "☀  6:00 AM  ☀",
		Parent = content,
	})
	make("UIStroke", { Color = Color3.fromRGB(60, 35, 0), Thickness = 2, Transparency = 0.2, Parent = tagLabel })
	titleLabel = UIKit.text({
		Position = UDim2.fromOffset(0, 32),
		Size = UDim2.new(1, 0, 0, 100),
		Font = UIKit.FONT_BLACK,
		TextScaled = true,
		TextColor3 = Color3.new(1, 1, 1),
		Text = "¡SOBREVIVISTE!",
		Parent = content,
	})
	make("UITextSizeConstraint", { MaxTextSize = 96, MinTextSize = 30, Parent = titleLabel })
	make("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 250, 215)),
			ColorSequenceKeypoint.new(0.45, GOLD),
			ColorSequenceKeypoint.new(1, GOLD_DEEP),
		}),
		Parent = titleLabel,
	})
	make("UIStroke", {
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		Color = Color3.fromRGB(70, 35, 0),
		Thickness = 5,
		Parent = titleLabel,
	})
	nightLabel = UIKit.text({
		Position = UDim2.fromOffset(0, 136),
		Size = UDim2.new(1, 0, 0, 40),
		Font = UIKit.FONT_BLACK,
		TextSize = 30,
		TextColor3 = Color3.new(1, 1, 1),
		Text = "",
		Parent = content,
	})
	make("UIStroke", { Color = Color3.fromRGB(0, 0, 0), Thickness = 2.5, Transparency = 0.15, Parent = nightLabel })

	-- Tarjeta del pago
	card = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.58),
		Size = UDim2.fromOffset(400, 180),
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.12,
		Parent = gui,
	}, {
		UIKit.corner(14),
		make("UIPadding", {
			PaddingTop = UDim.new(0, 12),
			PaddingBottom = UDim.new(0, 12),
			PaddingLeft = UDim.new(0, 20),
			PaddingRight = UDim.new(0, 20),
		}),
	})
	UIKit.stroke(card, GOLD, 2, 0.15)
	cardScale = make("UIScale", { Parent = card })
	linesLabel = UIKit.text({
		Size = UDim2.new(1, 0, 1, -48),
		Font = UIKit.FONT_LIGHT,
		TextSize = 16,
		RichText = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		LineHeight = 1.2,
		Text = "",
		Parent = card,
	})
	totalLabel = UIKit.text({
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 44),
		Font = UIKit.FONT_BLACK,
		TextSize = 34,
		TextColor3 = GOLD,
		Text = "",
		Parent = card,
	})
	make("UIStroke", { Color = Color3.fromRGB(60, 35, 0), Thickness = 2, Transparency = 0.3, Parent = totalLabel })
end

----------------------------------------------------------------------
-- Efectos
----------------------------------------------------------------------

local function confettiBurst(count: number)
	for _ = 1, count do
		local w = rng:NextInteger(7, 12)
		local piece = make("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(rng:NextNumber(0.02, 0.98), rng:NextNumber(-0.25, -0.02)),
			Size = UDim2.fromOffset(w, math.floor(w * rng:NextNumber(1.4, 2.2))),
			Rotation = rng:NextNumber(0, 360),
			BackgroundColor3 = CONFETTI_COLORS[rng:NextInteger(1, #CONFETTI_COLORS)],
			BorderSizePixel = 0,
			ZIndex = 6,
			Parent = confettiLayer,
		})
		local fall = rng:NextNumber(2.6, 4.4)
		local drift = rng:NextNumber(-0.12, 0.12)
		local goal = UDim2.fromScale(piece.Position.X.Scale + drift, 1.08)
		UIKit.tween(piece, fall, { Position = goal, Rotation = piece.Rotation + rng:NextNumber(-720, 720) }, Enum.EasingStyle.Sine, Enum.EasingDirection.In)
		task.delay(fall * 0.7, function()
			UIKit.tween(piece, fall * 0.3, { BackgroundTransparency = 1 })
		end)
		task.delay(fall + 0.1, function()
			piece:Destroy()
		end)
	end
end

local function setEdges(transparency: number, seconds: number)
	for _, edge in edges do
		UIKit.tween(edge, seconds, { BackgroundTransparency = transparency }, Enum.EasingStyle.Sine)
	end
end

local function buildLines(data): string
	local lines = {
		string.format("Pago base  <b>%s</b>", Util.formatMoney(data.Base or 0)),
		string.format(
			'Tareas  <b>%s</b>  <font color="#9696A0">(tu parte de %s entre %d)</font>',
			Util.formatMoney(data.Missions or 0),
			Util.formatMoney(data.MissionsPool or data.Missions or 0),
			data.TeamSize or 1
		),
		string.format("Noche completada  <b>%s</b>", Util.formatMoney(data.Survival or 0)),
	}
	if (data.Bonus or 0) > 0 then
		table.insert(lines, string.format("Bonus de clase  <b>%s</b>", Util.formatMoney(data.Bonus)))
	end
	if (data.PassBonus or 0) > 0 then
		table.insert(lines, string.format('<font color="#FFC850">Pase x2 Billetes  <b>%s</b></font>', Util.formatMoney(data.PassBonus)))
	end
	return table.concat(lines, "\n")
end

local function hide(myToken: number)
	if token ~= myToken or hiding then
		return
	end
	hiding = true
	UIKit.fade(content, 1, 0.6)
	UIKit.fade(card, 1, 0.6)
	UIKit.tween(contentScale, 0.6, { Scale = 0.9 })
	UIKit.tween(dim, 0.8, { BackgroundTransparency = 1 })
	for _, part in glowParts do
		UIKit.tween(part, 0.8, { BackgroundTransparency = 1 })
	end
	for _, ray in rays:GetChildren() do
		if ray:IsA("Frame") then
			UIKit.tween(ray, 0.8, { BackgroundTransparency = 1 })
		end
	end
	setEdges(1, 0.8)
	task.delay(0.85, function()
		if token ~= myToken then
			return
		end
		gui.Enabled = false
		fxGui.Enabled = false
		if rayConnection then
			rayConnection:Disconnect()
			rayConnection = nil
		end
	end)
end

local function show(data)
	token += 1
	hiding = false
	local myToken = token
	local seconds = Config.Night.VictorySeconds

	nightLabel.Text = string.format("NOCHE %d SUPERADA", data.Night or 1)
	linesLabel.Text = buildLines(data)
	local lineCount = #string.split(linesLabel.Text, "\n")
	card.Size = UDim2.fromOffset(400, 24 + lineCount * 20 + 52)
	totalLabel.Text = "+" .. Util.formatMoney(0)

	gui.Enabled = true
	fxGui.Enabled = true

	-- Estado inicial (UIKit.fade guarda las transparencias "visibles" la primera vez)
	UIKit.fade(content, 0, 0)
	UIKit.fade(card, 1, 0)
	for _, ray in rays:GetChildren() do
		if ray:IsA("Frame") then
			ray.BackgroundTransparency = 1
			UIKit.tween(ray, 0.6, { BackgroundTransparency = 0 })
		end
	end
	flash.BackgroundTransparency = 0.15
	UIKit.tween(flash, 0.9, { BackgroundTransparency = 1 })
	dim.BackgroundTransparency = 1
	UIKit.tween(dim, 0.5, { BackgroundTransparency = 0.5 })
	for _, part in glowParts do
		part.BackgroundTransparency = 1
		UIKit.tween(part, 0.5, { BackgroundTransparency = 0.45 })
	end
	for _, edge in edges do
		edge.BackgroundTransparency = 1
	end
	setEdges(0.25, 0.4)

	-- Rayos girando y bordes que laten
	rays.Rotation = 0
	if rayConnection then
		rayConnection:Disconnect()
	end
	local started = os.clock()
	rayConnection = RunService.RenderStepped:Connect(function()
		local t = os.clock() - started
		rays.Rotation = t * 14
		local pulse = GLOW_SIZE + 0.05 * math.sin(t * 3)
		glow.Size = UDim2.fromScale(pulse, pulse)
		-- el titulo "respira" un poco despues de entrar (hasta que empieza a irse)
		if t > 0.6 and not hiding then
			contentScale.Scale = 1 + 0.025 * math.sin((t - 0.6) * 4)
		end
	end)

	-- Titulo: entra enorme y cae a su sitio con rebote
	contentScale.Scale = 2.4
	UIKit.tween(contentScale, 0.55, { Scale = 1 }, Enum.EasingStyle.Back)
	titleLabel.Rotation = -6
	UIKit.tween(titleLabel, 0.55, { Rotation = 0 }, Enum.EasingStyle.Back)

	confettiBurst(70)
	task.delay(0.9, function()
		if token == myToken then
			confettiBurst(45)
		end
	end)

	-- Tarjeta del pago y total contando
	task.delay(0.7, function()
		if token ~= myToken then
			return
		end
		UIKit.fade(card, 0, 0.3)
		cardScale.Scale = 0.8
		UIKit.tween(cardScale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
		local counter = Instance.new("NumberValue")
		counter.Value = 0
		counter.Changed:Connect(function(v)
			if token == myToken then
				totalLabel.Text = "+" .. Util.formatMoney(math.floor(v + 0.5))
			end
		end)
		local tween = UIKit.tween(counter, 1.3, { Value = data.Total or 0 }, Enum.EasingStyle.Quart)
		tween.Completed:Once(function()
			counter:Destroy()
			if token ~= myToken then
				return
			end
			totalLabel.Text = "+" .. Util.formatMoney(data.Total or 0)
			-- golpe final en el total
			local s = totalLabel:FindFirstChildOfClass("UIScale") or make("UIScale", { Parent = totalLabel })
			s.Scale = 1.35
			UIKit.tween(s, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
		end)
	end)

	task.delay(seconds, hide, myToken)
end

function VictoryScreen.Start()
	build()
	Remotes.event("NightResults").OnClientEvent:Connect(function(data)
		if type(data) == "table" and data.Survived and not data.GameOver then
			show(data)
		end
	end)
	-- Si empezara la noche con la pantalla aun puesta, quitarla ya
	GameState.Folder:GetAttributeChangedSignal("Phase"):Connect(function()
		if GameState.Folder:GetAttribute("Phase") == "Night" and gui.Enabled then
			hide(token)
		end
	end)
end

return VictoryScreen
