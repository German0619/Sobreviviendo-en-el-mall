--!strict
-- Registro de paneles del lobby. Cada fase registra el suyo y los botones del
-- HUD / los puestos de la plaza solo piden abrirlo por su id:
--   "Shop"         boton TIENDA          (Fase 4)
--   "Achievements" boton LOGROS          (Fase 5)
--   "Classes"      puesto CLASES         (Fase 3)
--   "Upgrades"     puesto MEJORAS        (por decidir)
-- Mientras un panel no exista se muestra un aviso nativo de "Proximamente".

local StarterGui = game:GetService("StarterGui")

local LobbyPanels = {}

local openers: { [string]: () -> () } = {}

local TITLES = {
	Shop = "Tienda",
	Achievements = "Logros",
	Rooms = "Salas",
	Classes = "Clases y ruleta",
	Upgrades = "Mejoras",
}

-- Aviso nativo de Roblox (esquina inferior derecha en todos los dispositivos).
function LobbyPanels.notify(title: string, text: string, duration: number?)
	for _ = 1, 10 do
		local ok = pcall(function()
			StarterGui:SetCore("SendNotification", {
				Title = title,
				Text = text,
				Duration = duration or 4,
			})
		end)
		if ok then
			return
		end
		task.wait(0.5) -- el CoreGui puede no estar listo al entrar
	end
end

function LobbyPanels.register(id: string, open: () -> ())
	openers[id] = open
end

function LobbyPanels.open(id: string)
	local open = openers[id]
	if open then
		open()
	else
		LobbyPanels.notify(TITLES[id] or id, "Próximamente.", 3)
	end
end

return LobbyPanels
