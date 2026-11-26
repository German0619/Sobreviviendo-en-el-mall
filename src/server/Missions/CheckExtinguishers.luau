-- Mision: Revisar extintores.
-- Revisa 3 extintores de pared de una planta (tag Extinguisher, atributo Floor = "Planta
-- baja" / "Planta alta"). Si llevas el extintor (arma), al revisar uno se recarga.

local ServerScriptService = game:GetService("ServerScriptService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Tags = require(Shared.Tags)
local Remotes = require(Shared.Remotes)
local Multi = require(script.Parent.Multi)

return Multi.new({
	Type = "CheckExtinguishers",
	TargetTag = Tags.Extinguisher,
	TargetAttribute = "Floor",
	ActionText = "Revisar",
	ObjectText = "Extintor",
	OnStep = function(_part, player: Player)
		-- (se carga aqui para no crear un ciclo de require al arrancar)
		local WeaponService = require(ServerScriptService:WaitForChild("Server"):WaitForChild("WeaponService")) :: any
		if WeaponService.Refill(player, "Extinguisher") then
			Remotes.event("Notify"):FireClient(player, "Tu extintor está recargado.", "good")
		end
	end,
})
