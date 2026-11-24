--!strict
-- Punto de entrada del cliente. Arranca cada ModuleScript hijo que tenga Start(),
-- segun el place (ver shared/Place):
--   * Lobby: solo los modulos de LOBBY_MODULES.
--   * Mall:  todos menos los de LOBBY_ONLY.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Place = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Place"))

local LOBBY_MODULES = {
	LobbyHUD = true, -- diamantes, botones laterales y paneles de los puestos
	ClassUI = true,
	LobbyUI = true,
	StoreUI = true,
	Movement = true,
}

local LOBBY_ONLY = {
	LobbyHUD = true,
	LobbyPanels = true,
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
