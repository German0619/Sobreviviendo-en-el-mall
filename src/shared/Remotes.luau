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
}

local FUNCTIONS = {
	"RequestUpgrade", -- cliente -> servidor: (statName) -> (ok, mensaje)
	"RequestPurchase", -- cliente -> servidor: (itemId) -> (ok, mensaje)
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
