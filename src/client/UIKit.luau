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

-- Hace que un ScreenGui hecho en pixeles se vea igual en cualquier pantalla:
--   * respeta el notch y la barra superior de Roblox (ScreenInsets);
--   * escala todo con un UIScale segun el tamano de la pantalla
--     (diseno base 1280x720; entre MIN_SCALE y MAX_SCALE);
--   * en consola (tele, se juega desde el sofa) todo un CONSOLE_BOOST mas grande.
-- Devuelve el UIScale (su Scale cambia si cambia la pantalla, p. ej. al girar).
local BASE = Vector2.new(1280, 720)
local MIN_SCALE, MAX_SCALE = 0.6, 1.25
local CONSOLE_BOOST, CONSOLE_MAX = 1.3, 1.7
local MIN_TOUCH_TEXT = 10 -- px reales minimos de un texto en tactil

local GuiService = game:GetService("GuiService")
local TextService = game:GetService("TextService")
local UserInputService = game:GetService("UserInputService")
local textFits: (obj: any, size: number) -> boolean

local function isConsole(): boolean
	local ok, tenFoot = pcall(function()
		return GuiService:IsTenFootInterface()
	end)
	return ok and tenFoot == true
end

-- Escala real de un objeto: producto de los UIScale de sus antepasados.
local function effectiveScale(obj: Instance): number
	local s = 1
	local node: Instance? = obj
	while node do
		local uiScale = node:FindFirstChildOfClass("UIScale")
		if uiScale then
			s *= uiScale.Scale
		end
		node = node.Parent
	end
	return s
end

-- ¿Cabe el texto de `obj` con tamano `size` en su caja? (ancho; alto si hace salto de linea)
textFits = function(obj: any, size: number): boolean
	local text = obj.Text
	if obj.RichText then
		text = string.gsub(text, "<[^>]->", "")
	end
	if text == "" then
		return true
	end
	local s = effectiveScale(obj)
	local box = obj.AbsoluteSize / s -- en pixeles de diseno
	if box.X <= 0 then
		return true
	end
	local ok, bounds = pcall(function()
		return TextService:GetTextSize(text, size, obj.Font, Vector2.new(if obj.TextWrapped then box.X else 100000, 100000))
	end)
	if not ok then
		return true
	end
	if obj.TextWrapped then
		return bounds.Y <= box.Y + 2
	end
	-- Una linea: que quepa a lo ancho y no se pase mucho de alto (taparia lo de abajo)
	return bounds.X <= box.X + 1 and bounds.Y <= box.Y * 1.25 + 1
end

function UIKit.adapt(gui: ScreenGui): UIScale
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	local scale = gui:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	scale.Parent = gui
	local function refresh()
		local camera = workspace.CurrentCamera
		if not camera then
			return
		end
		local size = camera.ViewportSize
		local s = math.min(size.X / BASE.X, size.Y / BASE.Y)
		if isConsole() then
			scale.Scale = math.clamp(s * CONSOLE_BOOST, MIN_SCALE, CONSOLE_MAX)
		else
			scale.Scale = math.clamp(s, MIN_SCALE, MAX_SCALE)
		end
	end
	refresh()

	-- Texto minimo legible en tactil: con la escala de un telefono pequeno (0.6) un
	-- texto de 13 px se queda en 8 px reales. Los textos fijos (no TextScaled) se
	-- agrandan hacia MIN_TOUCH_TEXT px reales, pero solo hasta donde quepan en su caja
	-- (si no, se quedan en su tamano). El tamano original queda en BaseTextSize.
	local watched: { [Instance]: boolean } = {}
	local function fixText(obj: Instance)
		if not (obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox")) or obj.TextScaled then
			return
		end
		local base = obj:GetAttribute("BaseTextSize")
		if type(base) ~= "number" then
			base = obj.TextSize
			obj:SetAttribute("BaseTextSize", base)
		end
		local size = math.max(base, math.ceil(MIN_TOUCH_TEXT / scale.Scale))
		while size > base and not textFits(obj, size) do
			size -= 1
		end
		obj.TextSize = size
		if not watched[obj] then
			watched[obj] = true
			-- El texto cambia durante la partida: volver a ajustarlo
			obj:GetPropertyChangedSignal("Text"):Connect(function()
				fixText(obj)
			end)
			obj.Destroying:Connect(function()
				watched[obj] = nil
			end)
		end
	end
	local function fixAll()
		for _, obj in gui:GetDescendants() do
			fixText(obj)
		end
	end
	if UserInputService.TouchEnabled then
		task.defer(fixAll) -- despues de que el modulo termine de construir su UI
		gui.DescendantAdded:Connect(function(obj)
			task.defer(fixText, obj)
		end)
		scale:GetPropertyChangedSignal("Scale"):Connect(fixAll)
	end

	local function watch(camera: Camera?)
		if camera then
			camera:GetPropertyChangedSignal("ViewportSize"):Connect(refresh)
			refresh()
		end
	end
	watch(workspace.CurrentCamera)
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		watch(workspace.CurrentCamera)
	end)
	return scale
end

-- Telefono: tactil con poca altura de pantalla (en tablet el area util pasa de 700 px).
function UIKit.isPhone(gui: ScreenGui): boolean
	return UserInputService.TouchEnabled and gui.AbsoluteSize.Y > 0 and gui.AbsoluteSize.Y < 500
end

-- Cambia el tamano de un texto desde el codigo. Si UIKit.adapt lo agranda en tactil
-- (texto minimo), parte de este tamano y no del original.
function UIKit.setTextSize(label: TextLabel | TextButton, size: number)
	label:SetAttribute("BaseTextSize", size)
	label.TextSize = size
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
-- Se ajusta a la pantalla (telefonos pequenos):
--   * por defecto se encoge entera (UIScale "Fit") hasta caber;
--   * con scroll = true (su contenido tiene ScrollingFrame) baja de alto en vez de
--     encogerse, para que el texto no se haga mas pequeno.
--   * en tactil el boton de cerrar mide al menos 44 px reales.
function UIKit.window(parent: Instance, title: string, size: Vector2, onClose: () -> (), scroll: boolean?)
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
	local titleLabel = UIKit.text({
		Position = UDim2.fromOffset(20, 12),
		Size = UDim2.new(1, -80, 0, 30),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 24,
		TextScaled = true,
		Text = title,
		ZIndex = 21,
		Parent = frame,
	})
	UIKit.make("UITextSizeConstraint", { MaxTextSize = 24, MinTextSize = 10, Parent = titleLabel })
	local closeButton = UIKit.button({
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

	-- Ajuste a la pantalla
	local fit = UIKit.make("UIScale", { Name = "Fit", Parent = frame })
	local constraint = frame:FindFirstChildOfClass("UISizeConstraint") :: UISizeConstraint
	local gui = if parent:IsA("ScreenGui") then parent else parent:FindFirstAncestorOfClass("ScreenGui")
	local function refit()
		if not gui then
			return
		end
		local guiScaleObject = gui:FindFirstChildOfClass("UIScale")
		local guiScale = if guiScaleObject then guiScaleObject.Scale else 1
		local available = gui.AbsoluteSize
		if available.X <= 0 or available.Y <= 0 then
			return
		end
		local maxWidth = available.X * 0.96 / guiScale
		local maxHeight = available.Y * 0.94 / guiScale
		local height = size.Y
		local s
		if scroll then
			height = math.min(size.Y, maxHeight)
			s = math.min(1, maxWidth / size.X)
		else
			s = math.min(1, maxWidth / size.X, maxHeight / size.Y)
		end
		frame.Size = UDim2.fromOffset(size.X, height)
		constraint.MaxSize = Vector2.new(size.X, size.Y)
		fit.Scale = s
		-- Boton de cerrar: al menos 44 px reales en tactil
		local effective = guiScale * s
		local closeSize = if UserInputService.TouchEnabled then math.max(32, math.ceil(44 / effective)) else 32
		closeButton.Size = UDim2.fromOffset(closeSize, closeSize)
		titleLabel.Size = UDim2.new(1, -(closeSize + 36), 0, 30)
	end
	refit()
	if gui then
		gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(refit)
		local guiScaleObject = gui:FindFirstChildOfClass("UIScale")
		if guiScaleObject then
			guiScaleObject:GetPropertyChangedSignal("Scale"):Connect(refit)
		end
	end
	return frame, content
end

return UIKit
