--!strict
-- Punto de entrada del cliente. Arranca cada ModuleScript hijo que tenga Start(),
-- segun el place (ver shared/Place):
--   * Lobby: solo los modulos de LOBBY_MODULES.
--   * Mall:  todos menos los de LOBBY_ONLY.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Place = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Place"))

-- LobbyUI (ventana de salas del lobby de prueba) ya no se usa: las salas se
-- arman subiendose a los cuadros de la plaza (PadUI / PadService).
local LOBBY_MODULES = {
	LobbyHUD = true, -- diamantes, botones laterales y paneles de los puestos
	PadUI = true, -- cuadros de sala
	ClassPanel = true, -- clases y ruleta (puesto CLASES)
	StoreUI = true,
	Movement = true,
}

-- ClassUI (ruleta vieja) solo se usa en el mall dentro de Studio, para probar.
local LOBBY_ONLY = {
	LobbyHUD = true,
	LobbyPanels = true,
	PadUI = true,
	ClassPanel = true,
	LobbyUI = true,
	StoreUI = true,
}

local function shouldStart(name: string): boolean
	if Place.IsLobby then
		return LOBBY_MODULES[name] == true
	end
	return not LOBBY_ONLY[name]
end

for _, child in script:GetChildren() do
	if child:IsA("ModuleScript") and shouldStart(child.Name) then
		local ok, mod = pcall(require, child)
		if ok and type(mod) == "table" and type(mod.Start) == "function" then
			task.spawn(mod.Start)
		elseif not ok then
			warn("[Client] Error cargando", child.Name, mod)
		end
	end
end

print(string.format("[Client] Sobreviviendo en el Mall: cliente iniciado (%s)", Place.Role))
