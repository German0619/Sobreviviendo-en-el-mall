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
	ShopPanel = true, -- tienda con Robux (boton TIENDA)
	AchievementsPanel = true, -- logros y bono diario VIP (boton LOGROS)
	CosmeticsPanel = true, -- skins: caja, compra y equipar (puesto COSMETICOS)
	PermanentPanel = true, -- mejoras permanentes (puesto MEJORAS)
	LockerPanel = true, -- taquilla del conserje (puesto TAQUILLA)
	VipChat = true, -- [VIP] en el chat (tambien en el mall)
	Movement = true,
	TouchButtons = true, -- botones tactiles en arco junto al de saltar (tambien en el mall)
}

-- StoreUI, LobbyUI y ClassUI (ruleta vieja) son del lobby de prueba y ya no arrancan:
-- las clases solo se cambian en el lobby (ClassPanel).
local LOBBY_ONLY = {
	ClassUI = true,
	LobbyHUD = true,
	LobbyPanels = true,
	PadUI = true,
	ClassPanel = true,
	ShopPanel = true,
	AchievementsPanel = true,
	CosmeticsPanel = true,
	PermanentPanel = true,
	LockerPanel = true,
	LobbyUI = true,
	StoreUI = true,
}

-- Solo horizontal (gira entre los dos horizontales): toda la UI esta pensada para
-- pantalla ancha. Se fija aqui y no en StarterGui para que valga en los dos places.
-- Roblox la vuelve a copiar de StarterGui al aparecer el personaje: se reaplica.
do
	local localPlayer = game:GetService("Players").LocalPlayer
	local function landscape()
		local playerGui = localPlayer:FindFirstChildOfClass("PlayerGui")
		if playerGui then
			playerGui.ScreenOrientation = Enum.ScreenOrientation.LandscapeSensor
		end
	end
	localPlayer:WaitForChild("PlayerGui")
	landscape()
	localPlayer.CharacterAdded:Connect(function()
		task.defer(landscape)
	end)
end

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
