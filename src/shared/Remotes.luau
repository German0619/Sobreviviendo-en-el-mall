--!strict
-- Registro central de RemoteEvents / RemoteFunctions.
-- El servidor los crea; el cliente espera a que existan.
--
-- Uso:
--   local Remotes = require(ReplicatedStorage.Shared.Remotes)
--   Remotes.event("Notify"):FireClient(player, ...)
--   Remotes.func("RequestUpgrade"):InvokeServer("Health")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "Remotes"

-- Agregar aqui cada remote nuevo.
local EVENTS = {
	"Notify", -- servidor -> cliente: (texto, tipo "info"|"good"|"bad")
	"NightResults", -- servidor -> cliente: desglose del pago de la noche
	"ToggleFlashlight", -- cliente -> servidor: (encender: boolean)
	"OpenShop", -- servidor -> cliente: (posicion del mostrador)
	"UseItem", -- cliente -> servidor: (itemId)
	"RequestSelfRevive", -- cliente -> servidor: revivirse (ficha o Robux)
	"RequestBuyProduct", -- cliente -> servidor: ("ClassSlot" | "Diamonds", indice del paquete)
	"UseFlash", -- cliente -> servidor: destello de linterna [G]
	"UseClassAbility", -- cliente -> servidor: habilidad activa de la clase [Q] (Porrazo del Guardia)
	"RequestUnhide", -- cliente -> servidor: salir del escondite
	"RequestReturnToLobby", -- cliente -> servidor (mall): volver al lobby
	"RequestStartGame", -- cliente -> servidor (mall, solo Studio/servidor no reservado): iniciar con [P]
	"PartyState", -- servidor -> cliente (lobby): estado de tu sala, o nil si no estas en ninguna
	"RequestBuyPass", -- cliente -> servidor: (nombre del pase en Config.GamePasses)
	"OpenSodaPicker", -- servidor -> cliente (mall): abrir el selector de soda a eleccion
	"RequestChoiceSoda", -- cliente -> servidor (mall): (efecto) usar ficha o comprar con Robux
	"PadPrompt", -- servidor -> cliente (lobby): (padId) elegir sala publica / solo amigos, o (nil) cerrar
	"SpinResult", -- servidor -> cliente (lobby): (clase, mensaje) resultado de un tiro afortunado (Robux)
	"RequestLeavePad", -- cliente -> servidor (lobby): salto dentro de un cuadro = salir de la sala y del cuadro
	"UseWeapon", -- cliente -> servidor (mall): usar el arma equipada [R]
	"RequestEquipSkin", -- cliente -> servidor (lobby): (objeto, skin | nil) equipar o quitar una skin
	"CosmeticResult", -- servidor -> cliente (lobby): (objeto, skin, repetida) resultado de un giro con Robux
}

local FUNCTIONS = {
	"RequestUpgrade", -- cliente -> servidor: (statName) -> (ok, mensaje)
	"RequestPurchase", -- cliente -> servidor: (itemId) -> (ok, mensaje)
	"RequestSpin", -- cliente -> servidor: () -> (ok, mensaje, className). Reemplaza la clase equipada.
	"RequestEquipSlot", -- cliente -> servidor: (slot) -> (ok, mensaje)
	-- Lobby. Las salas se crean y se unen SOLO subiendose a un cuadro (PadService);
	-- List/Create/Join/JoinByCode/Leave ya no se atienden (quedan del lobby de prueba).
	"RequestRoomList", -- () -> { salas publicas }
	"RequestCreateRoom", -- (esPublica, nombre) -> (ok, mensaje). Crea la sala y te mete en ella
	"RequestJoinRoom", -- (idSala) -> (ok, mensaje)
	"RequestJoinByCode", -- (codigo) -> (ok, mensaje)
	"RequestLeaveRoom", -- () -> (ok, mensaje)
	"RequestStartRoom", -- () -> (ok, mensaje). Solo el anfitrion: todos viajan al mall
	"RequestPadCreate", -- (esPublica) -> (ok, mensaje). Quien eligio en su cuadro libre
	"RequestClaimAchievement", -- (idLogro) -> (ok, mensaje). Da los diamantes de un logro desbloqueado
	"RequestClaimVipDaily", -- () -> (ok, mensaje). Bono diario VIP
	"RequestCosmeticSpin", -- () -> (ok, mensaje, objeto, skin, repetida). Caja de cosmeticos con diamantes
	"RequestBuySkin", -- (objeto, skin) -> (ok, mensaje). Compra directa con diamantes
	"RequestBuyPermanent", -- (mejora) -> (ok, mensaje). Siguiente nivel de una mejora permanente (lobby)
	"RequestBuyLocker", -- (objeto) -> (ok, mensaje). Guarda un consumible en la taquilla del conserje (lobby)
}

local IS_SERVER = RunService:IsServer()

local folder: Folder
if IS_SERVER then
	local existing = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if existing then
		folder = existing :: Folder
	else
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = ReplicatedStorage
	end
	for _, name in EVENTS do
		if not folder:FindFirstChild(name) then
			local r = Instance.new("RemoteEvent")
			r.Name = name
			r.Parent = folder
		end
	end
	for _, name in FUNCTIONS do
		if not folder:FindFirstChild(name) then
			local r = Instance.new("RemoteFunction")
			r.Name = name
			r.Parent = folder
		end
	end
else
	folder = ReplicatedStorage:WaitForChild(FOLDER_NAME) :: Folder
end

local Remotes = {}

function Remotes.event(name: string): RemoteEvent
	assert(table.find(EVENTS, name), "RemoteEvent no registrado: " .. name)
	return folder:WaitForChild(name) :: RemoteEvent
end

function Remotes.func(name: string): RemoteFunction
	assert(table.find(FUNCTIONS, name), "RemoteFunction no registrada: " .. name)
	return folder:WaitForChild(name) :: RemoteFunction
end

return Remotes
