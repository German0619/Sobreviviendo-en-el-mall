-- TouchButtons: coloca los botones tactiles de ContextActionService en dos arcos
-- alrededor del boton de saltar, sin taparse y sin salirse de la pantalla.
--
-- Roblox los coloca en posiciones fijas que en un telefono pequeno (Galaxy A06,
-- 705x338) quedan debajo del boton de saltar o fuera de pantalla. Aqui se calculan
-- a partir del tamano real del boton de saltar y de los botones.
--   Arco interior (lo mas usado): Correr, Linterna, Destello.
--   Arco exterior: habilidad de clase / salir del escondite, Mejoras, Lobby.
-- Solo se colocan las acciones que tienen boton (las demas dejan su hueco a la
-- siguiente). Se revisa cada medio segundo: las acciones se enlazan y se quitan
-- durante la partida (habilidad, escondite) y la pantalla puede girar.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local TouchButtons = {}

local player = Players.LocalPlayer

-- Orden de prioridad: las primeras quedan mas cerca del pulgar.
local ORDER = { "Sprint", "Flashlight", "Flash", "ClassAbility", "ExitHiding", "Upgrades", "ReturnToLobby" }
-- Angulos de cada hueco (grados; 180 = a la izquierda del salto, 90 = encima)
local INNER = { 180, 135, 90 }
local OUTER = { 180, 150, 120, 90 }
local GAP = 8
local SIZE_OF_JUMP = 0.55 -- los botones miden al menos esta fraccion del boton de saltar

local placed: { [string]: Vector2 } = {}

local function layout()
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	local touchGui = playerGui and playerGui:FindFirstChild("TouchGui")
	local jump = touchGui and touchGui:FindFirstChild("JumpButton", true) :: GuiObject?
	local actionGui = playerGui and playerGui:FindFirstChild("ContextActionGui")
	local frame = actionGui and actionGui:FindFirstChild("ContextButtonFrame") :: GuiObject?
	if not jump or not frame or not jump.Visible or jump.AbsoluteSize.X <= 0 then
		return
	end

	local center = jump.AbsolutePosition + jump.AbsoluteSize / 2
	local jumpRadius = jump.AbsoluteSize.X / 2
	-- (GetButton avisa en la consola si la accion no esta enlazada: se mira antes)
	local bound = ContextActionService:GetAllBoundActionInfo()
	local slot = 0
	for _, action in ORDER do
		local button = if bound[action] then ContextActionService:GetButton(action) else nil
		if button then
			slot += 1
			-- Tamano: el de Roblox (45 px), pero al menos SIZE_OF_JUMP del boton de saltar
			-- (en tablet el de saltar mide 120 y los de 45 se quedaban pequenos)
			local baseSize = button:GetAttribute("BaseSize")
			if type(baseSize) ~= "number" then
				baseSize = button.AbsoluteSize.X
				button:SetAttribute("BaseSize", baseSize)
			end
			local size = math.max(baseSize, math.floor(jump.AbsoluteSize.X * SIZE_OF_JUMP))
			if button.AbsoluteSize.X ~= size then
				button.Size = UDim2.fromOffset(size, size)
				local title = button:FindFirstChild("ActionTitle")
				if title and title:IsA("TextLabel") then
					local baseText = title:GetAttribute("BaseTextSize")
					if type(baseText) ~= "number" then
						baseText = title.TextSize
						title:SetAttribute("BaseTextSize", baseText)
					end
					title.TextSize = math.floor(baseText * size / baseSize)
				end
			end
			local radius, angle
			if slot <= #INNER then
				radius = jumpRadius + size / 2 + GAP
				angle = INNER[slot]
			else
				radius = jumpRadius + size * 1.5 + GAP * 2
				angle = OUTER[math.min(slot - #INNER, #OUTER)]
			end
			local a = math.rad(angle)
			local buttonCenter = center + Vector2.new(math.cos(a), -math.sin(a)) * radius
			local topLeft = buttonCenter - Vector2.new(size, size) / 2 - frame.AbsolutePosition
			local rounded = Vector2.new(math.floor(topLeft.X + 0.5), math.floor(topLeft.Y + 0.5))
			-- Solo si cambio (o si el juego de Roblox la movio)
			local current = button.AbsolutePosition - frame.AbsolutePosition
			if placed[action] ~= rounded or (current - rounded).Magnitude > 1 then
				ContextActionService:SetPosition(action, UDim2.fromOffset(rounded.X, rounded.Y))
				placed[action] = rounded
			end
		else
			placed[action] = nil
		end
	end
end

function TouchButtons.Start()
	task.spawn(function()
		while true do
			if UserInputService.TouchEnabled then
				pcall(layout)
			end
			task.wait(0.5)
		end
	end)
end

return TouchButtons
