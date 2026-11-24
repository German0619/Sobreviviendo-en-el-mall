-- NativeUI: piezas de interfaz del lobby (paneles de clases, tienda...).
--
-- Todo se dimensiona en Scale con limites (UITextSizeConstraint,
-- UISizeConstraint), asi que los paneles se ven proporcionados igual en PC,
-- telefono, tableta y consola. No tiene Start: lo usan otros modulos.

local NativeUI = {}

NativeUI.COLORS = {
	Window = Color3.fromRGB(16, 17, 28),
	Panel = Color3.fromRGB(28, 30, 46),
	Row = Color3.fromRGB(34, 36, 54),
	RowSelected = Color3.fromRGB(58, 60, 92),
	Text = Color3.fromRGB(255, 255, 255),
	Dim = Color3.fromRGB(170, 174, 200),
	Good = Color3.fromRGB(110, 230, 140),
	Bad = Color3.fromRGB(255, 120, 120),
	Buy = Color3.fromRGB(60, 170, 90),
	Off = Color3.fromRGB(70, 72, 90),
	Gold = Color3.fromRGB(255, 205, 80),
	Diamond = Color3.fromRGB(120, 220, 255),
}
local COLORS = NativeUI.COLORS

function NativeUI.corner(parent: Instance, scale: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(scale, 0)
	c.Parent = parent
end

function NativeUI.stroke(parent: Instance, color: Color3, transparency: number, thickness: number): UIStroke
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Transparency = transparency
	s.Thickness = thickness
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

-- Texto escalado con tope de tamano. props: propiedades extra del TextLabel.
function NativeUI.label(parent: Instance, name: string, size: UDim2, position: UDim2, maxSize: number, props: { [string]: any }?): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Size = size
	l.Position = position
	l.Font = Enum.Font.GothamBold
	l.TextColor3 = COLORS.Text
	l.TextScaled = true
	l.Text = ""
	for k, v in props or {} do
		(l :: any)[k] = v
	end
	l.Parent = parent
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = maxSize
	limit.MinTextSize = 8
	limit.Parent = l
	return l
end

function NativeUI.button(parent: Instance, name: string, size: UDim2, position: UDim2, color: Color3, maxSize: number): TextButton
	local b = Instance.new("TextButton")
	b.Name = name
	b.Size = size
	b.Position = position
	b.BackgroundColor3 = color
	b.AutoButtonColor = true
	b.Font = Enum.Font.GothamBlack
	b.TextColor3 = COLORS.Text
	b.TextScaled = true
	b.Text = ""
	b.Parent = parent
	NativeUI.corner(b, 0.22)
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = maxSize
	limit.MinTextSize = 8
	limit.Parent = b
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0.16, 0)
	padding.PaddingBottom = UDim.new(0.16, 0)
	padding.PaddingLeft = UDim.new(0.04, 0)
	padding.PaddingRight = UDim.new(0.04, 0)
	padding.Parent = b
	return b
end

-- Frame transparente, o con fondo si se pasa color.
function NativeUI.frame(parent: Instance, name: string, size: UDim2, position: UDim2, color: Color3?): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.Size = size
	f.Position = position
	f.BackgroundColor3 = color or COLORS.Panel
	f.BackgroundTransparency = if color then 0 else 1
	f.BorderSizePixel = 0
	f.Parent = parent
	return f
end

-- Ventana centrada (oculta) con cabecera: titulo, diamantes y X.
-- Devuelve window, diamondsLabel, closeButton, plusButton.
function NativeUI.window(gui: ScreenGui, title: string, accent: Color3)
	local window = Instance.new("Frame")
	window.Name = "Window"
	window.AnchorPoint = Vector2.new(0.5, 0.5)
	window.Position = UDim2.fromScale(0.5, 0.5)
	window.Size = UDim2.fromScale(0.96, 0.92)
	window.BackgroundColor3 = COLORS.Window
	window.BackgroundTransparency = 0.05
	window.Visible = false
	window.Active = true
	window.Parent = gui
	NativeUI.corner(window, 0.03)
	NativeUI.stroke(window, accent, 0.3, 2)
	local limits = Instance.new("UISizeConstraint")
	limits.MaxSize = Vector2.new(980, 600)
	limits.Parent = window
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0.025, 0)
	padding.PaddingBottom = UDim.new(0.025, 0)
	padding.PaddingLeft = UDim.new(0.018, 0)
	padding.PaddingRight = UDim.new(0.018, 0)
	padding.Parent = window

	local header = NativeUI.frame(window, "Header", UDim2.fromScale(1, 0.09), UDim2.fromScale(0, 0))
	NativeUI.label(header, "Title", UDim2.fromScale(0.5, 1), UDim2.fromScale(0, 0), 30, {
		Text = title,
		Font = Enum.Font.GothamBlack,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local diamonds = NativeUI.label(header, "Diamonds", UDim2.fromScale(0.25, 0.8), UDim2.fromScale(0.55, 0.1), 26, {
		TextColor3 = COLORS.Diamond,
		TextXAlignment = Enum.TextXAlignment.Right,
	})
	local plus = NativeUI.button(header, "Plus", UDim2.fromScale(0.05, 0.8), UDim2.fromScale(0.815, 0.1), COLORS.Buy, 24)
	plus.Text = "+"
	local plusAspect = Instance.new("UIAspectRatioConstraint")
	plusAspect.AspectRatio = 1
	plusAspect.Parent = plus
	local close = NativeUI.button(header, "Close", UDim2.fromScale(0.07, 1), UDim2.fromScale(1, 0), COLORS.Off, 26)
	close.AnchorPoint = Vector2.new(1, 0)
	close.Text = "X"
	local closeAspect = Instance.new("UIAspectRatioConstraint")
	closeAspect.AspectRatio = 1
	closeAspect.Parent = close
	return window, diamonds, close, plus
end

return NativeUI
