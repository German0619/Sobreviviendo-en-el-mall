-- InputHints: pistas de control segun el dispositivo con el que se juega.
--
-- Los textos de la interfaz NO escriben teclas a mano ("[F]"): piden la pista
-- de la accion y se muestra lo que corresponde:
--   teclado y raton  -> "[F]"
--   mando            -> "(R1)"   (si la accion tiene boton de mando)
--   tactil           -> ""       (las acciones tienen su boton en pantalla)
-- Usa UserInputService.PreferredInput, que cambia si el jugador conecta o empieza
-- a usar otro control a mitad de partida (Changed avisa a la interfaz).

local UserInputService = game:GetService("UserInputService")

local InputHints = {}

-- Teclas de cada accion (las mismas que registra cada modulo con ContextActionService).
local ACTIONS = {
	Flashlight = { Key = "F", Pad = "R1" },
	Flash = { Key = "G", Pad = "X" },
	Ability = { Key = "Q", Pad = "Y" },
	Sprint = { Key = "Shift", Pad = "L3" },
	Upgrades = { Key = "U" },
	Unhide = { Key = "Espacio", Pad = "A" },
	Lobby = { Key = "L" },
	Start = { Key = "P", Pad = "Select" },
}

InputHints.Changed = Instance.new("BindableEvent")

-- "Keyboard" | "Gamepad" | "Touch"
function InputHints.Kind(): string
	local ok, preferred = pcall(function()
		return UserInputService.PreferredInput
	end)
	if ok and preferred then
		if preferred == Enum.PreferredInput.Touch then
			return "Touch"
		elseif preferred == Enum.PreferredInput.Gamepad then
			return "Gamepad"
		end
		return "Keyboard"
	end
	-- Por si la propiedad no existe en esta version del motor
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return "Touch"
	end
	if UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then
		return "Gamepad"
	end
	return "Keyboard"
end

function InputHints.IsTouch(): boolean
	return InputHints.Kind() == "Touch"
end

-- Pista de la accion para el control actual ("[F]", "(R1)" o "").
function InputHints.Tag(action: string): string
	local def = ACTIONS[action]
	if not def then
		return ""
	end
	local kind = InputHints.Kind()
	if kind == "Keyboard" then
		return "[" .. def.Key .. "]"
	elseif kind == "Gamepad" and def.Pad then
		return "(" .. def.Pad .. ")"
	end
	return ""
end

-- "Destello" -> "[G] Destello" (o solo "Destello" en tactil).
function InputHints.Label(action: string, text: string): string
	local tag = InputHints.Tag(action)
	return if tag == "" then text else tag .. " " .. text
end

local lastKind = InputHints.Kind()
local function check()
	local kind = InputHints.Kind()
	if kind ~= lastKind then
		lastKind = kind
		InputHints.Changed:Fire(kind)
	end
end
pcall(function()
	UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(check)
end)
UserInputService.LastInputTypeChanged:Connect(check)

return InputHints
