-- Items: usar objetos del inventario con su tecla (1 = bateria, 2 = botiquin...).
-- El servidor valida que lo tengas y aplica el efecto.

local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)

local Items = {}

local KEYCODES = {
	[1] = Enum.KeyCode.One,
	[2] = Enum.KeyCode.Two,
	[3] = Enum.KeyCode.Three,
	[4] = Enum.KeyCode.Four,
}

function Items.Start()
	local slot = 0
	for _, itemId in Config.ShopOrder do
		local item = Config.ShopItems[itemId]
		local keyCode = item.Hotkey and KEYCODES[item.Hotkey]
		if keyCode and item.Use then
			local actionName = "UseItem_" .. itemId
			ContextActionService:BindAction(actionName, function(_, state)
				if state == Enum.UserInputState.Begin then
					Remotes.event("UseItem"):FireServer(itemId)
				end
				return Enum.ContextActionResult.Pass
			end, true, keyCode)
			ContextActionService:SetTitle(actionName, item.DisplayName)
			ContextActionService:SetPosition(actionName, UDim2.new(1, -240, 1, -90 - slot * 70))
			slot += 1
		end
	end
end

return Items
