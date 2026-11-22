-- UIKit: helpers para construir interfaces por codigo con el mismo estilo.

local UIKit = {}

UIKit.COLORS = {
	Panel = Color3.fromRGB(12, 12, 16),
	Row = Color3.fromRGB(26, 26, 32),
	Text = Color3.fromRGB(235, 235, 235),
	Dim = Color3.fromRGB(150, 150, 160),
	Good = Color3.fromRGB(90, 210, 120),
	Bad = Color3.fromRGB(230, 80, 80),
	Accent = Color3.fromRGB(255, 200, 80),
	Button = Color3.fromRGB(60, 140, 80),
	ButtonOff = Color3.fromRGB(60, 60, 68),
}

UIKit.FONT = Enum.Font.GothamBold
UIKit.FONT_LIGHT = Enum.Font.Gotham

function UIKit.make(className: string, props, children)
	local inst = Instance.new(className)
	for k, v in props do
		if k ~= "Parent" then
			inst[k] = v
		end
	end
	for _, child in children or {} do
		child.Parent = inst
	end
	if props.Parent then
		inst.Parent = props.Parent
	end
	return inst
end

function UIKit.corner(radius: number?)
	return UIKit.make("UICorner", { CornerRadius = UDim.new(0, radius or 8) })
end

function UIKit.text(props)
	local base = {
		BackgroundTransparency = 1,
		Font = UIKit.FONT,
		TextColor3 = UIKit.COLORS.Text,
		TextSize = 18,
	}
	for k, v in props do
		base[k] = v
	end
	return UIKit.make("TextLabel", base)
end

function UIKit.button(props, onClick: () -> ())
	local base = {
		BackgroundColor3 = UIKit.COLORS.Button,
		Font = UIKit.FONT,
		TextColor3 = UIKit.COLORS.Text,
		TextSize = 16,
		AutoButtonColor = true,
	}
	for k, v in props do
		base[k] = v
	end
	local button = UIKit.make("TextButton", base, { UIKit.corner(6) })
	button.Activated:Connect(onClick)
	return button
end

-- Ventana centrada con titulo y boton de cerrar.
-- El boton de cerrar tiene Modal = true: libera el raton en primera persona
-- mientras la ventana esta visible.
function UIKit.window(parent: Instance, title: string, size: Vector2, onClose: () -> ())
	local frame = UIKit.make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(size.X, size.Y),
		BackgroundColor3 = UIKit.COLORS.Panel,
		BackgroundTransparency = 0.05,
		Visible = false,
		ZIndex = 20,
		Parent = parent,
	}, {
		UIKit.corner(12),
		UIKit.make("UIStroke", { Color = UIKit.COLORS.Accent, Thickness = 1.5, Transparency = 0.4 }),
		UIKit.make("UISizeConstraint", { MaxSize = Vector2.new(size.X, size.Y) }),
	})
	UIKit.text({
		Position = UDim2.fromOffset(20, 12),
		Size = UDim2.new(1, -80, 0, 30),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 24,
		Text = title,
		ZIndex = 21,
		Parent = frame,
	})
	UIKit.button({
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 12),
		Size = UDim2.fromOffset(32, 32),
		BackgroundColor3 = UIKit.COLORS.ButtonOff,
		Text = "X",
		Modal = true,
		ZIndex = 21,
		Parent = frame,
	}, onClose)
	local content = UIKit.make("Frame", {
		Name = "Content",
		Position = UDim2.fromOffset(16, 54),
		Size = UDim2.new(1, -32, 1, -70),
		BackgroundTransparency = 1,
		ZIndex = 21,
		Parent = frame,
	})
	return frame, content
end

return UIKit
