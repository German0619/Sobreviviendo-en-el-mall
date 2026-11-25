-- Mercader nocturno: un vendedor encapuchado aparece un minuto en una planta, con una
-- manta y OffersShown ofertas raras delante: armas (algunas con mas usos que en la
-- tienda) y objetos exclusivos (MerchantOnly: Botiquin grande, Bengala de magnesio). Cada oferta es un objeto en la manta con su
-- propio boton (ProximityPrompt nativo: teclado, tactil y mando). Cada jugador puede
-- comprar cada oferta una vez. Se le ve de lejos por su marca "$".

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Util = require(Shared.Util)

local Server = script.Parent.Parent
local LightService = require(Server.LightService)
local RunState = require(Server.RunState)
local ShopService = require(Server.ShopService)
local SfxService = require(Server.SfxService)
local FlashlightService = require(Server.FlashlightService)
local WeaponService = require(Server.WeaponService)
local MissionsCommon = require(Server.Missions.Common)
local EventUtil = require(script.Parent.EventUtil)

local ROBE = Color3.fromRGB(55, 30, 70)
local GOLD = Color3.fromRGB(255, 200, 80)

local function part(model: Model, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	if shape then
		p.Shape = shape
	end
	p.Parent = model
	return p
end

local function notify(player: Player, message: string, kind: string)
	Remotes.event("Notify"):FireClient(player, message, kind)
end

-- Cuantos caben (respetando el maximo que se puede llevar).
local function room(player: Player, itemId: string): number
	local item = Config.ShopItems[itemId]
	local owned = ShopService.GetCount(player, itemId)
	if itemId == "FlashlightPro" and player:GetAttribute("Pass_PremiumFlashlight") == true then
		return 0
	end
	local max = item.MaxStack or (if item.Unique then 1 else math.huge)
	return math.max(0, max - owned)
end

return {
	CanStart = function(ctx)
		return EventUtil.pointOnFloor(ctx.Floor, 20, 70) ~= nil
	end,
	Start = function(ctx)
		local def = ctx.Def
		local point = EventUtil.pointOnFloor(ctx.Floor, 20, 70)
		if not point then
			ctx.Finish()
			return nil
		end
		-- Mira hacia el jugador mas cercano
		local root, nearestDist = nil, math.huge
		for _, player in EventUtil.alivePlayers() do
			local r = EventUtil.rootOf(player)
			if r and (r.Position - point).Magnitude < nearestDist then
				root, nearestDist = r, (r.Position - point).Magnitude
			end
		end
		local facing = if root then Vector3.new(root.Position.X, point.Y, root.Position.Z) else point + Vector3.new(0, 0, -1)
		if (facing - point).Magnitude < 0.5 then
			facing = point + Vector3.new(0, 0, -1)
		end
		local base = CFrame.lookAt(point, facing) -- en el suelo, mirando a los jugadores

		local model = Instance.new("Model")
		model.Name = "NightMerchant"
		-- Mercader: tunica, capucha, cara en sombra con ojos dorados y farol
		part(model, "Robe", Vector3.new(2.4, 4.4, 1.6), base * CFrame.new(0, 2.2, 0.8), ROBE, Enum.Material.Fabric)
		part(model, "Hood", Vector3.new(1.6, 1.6, 1.6), base * CFrame.new(0, 5.1, 0.8), ROBE, Enum.Material.Fabric, Enum.PartType.Ball)
		part(model, "Face", Vector3.new(1, 0.9, 0.2), base * CFrame.new(0, 5, 0.05), Color3.fromRGB(10, 8, 12))
		for _, x in { -0.22, 0.22 } do
			part(model, "Eye", Vector3.new(0.15, 0.08, 0.05), base * CFrame.new(x, 5.1, -0.06), GOLD, Enum.Material.Neon)
		end
		local lantern = part(model, "Lantern", Vector3.new(0.5, 0.7, 0.5), base * CFrame.new(1.5, 2.6, 0.4), GOLD, Enum.Material.Neon)
		local light = Instance.new("PointLight")
		light.Color = GOLD
		light.Range = 14
		light.Brightness = 1.5
		light.Shadows = true
		light.Parent = lantern
		-- Manta con las ofertas
		part(model, "Rug", Vector3.new(2.2 * def.OffersShown + 1, 0.1, 3), base * CFrame.new(0, 0.05, -1.6), Color3.fromRGB(120, 30, 40), Enum.Material.Fabric)
		-- Marca "$" visible de lejos
		local marker = MissionsCommon.makeMarker(lantern, "$", GOLD)
		marker.MaxDistance = 250
		marker.StudsOffsetWorldSpace = Vector3.new(-1.5, 4, 0)

		-- Ofertas al azar
		local pool = table.clone(def.Offers)
		for i = #pool, 2, -1 do
			local j = math.random(1, i)
			pool[i], pool[j] = pool[j], pool[i]
		end
		local bought: { [Player]: { [number]: boolean } } = {}
		local count = math.min(def.OffersShown, #pool)
		for i = 1, count do
			local offer = pool[i]
			local isWeapon = offer.Weapon ~= nil
			local itemId = offer.Weapon or offer.Item
			local item = Config.ShopItems[itemId]
			local title = offer.Label or (if isWeapon then item.DisplayName else string.format("%s x%d", item.DisplayName, offer.Amount))
			local x = (i - (count + 1) / 2) * 2.2
			local stand = part(model, "Offer", Vector3.new(1, 1, 1), base * CFrame.new(x, 0.6, -1.6), GOLD, Enum.Material.Foil)
			stand.CanQuery = true
			local tag = Instance.new("BillboardGui")
			tag.Size = UDim2.fromOffset(150, 40)
			tag.StudsOffsetWorldSpace = Vector3.new(0, 1.5, 0)
			tag.MaxDistance = 25
			tag.LightInfluence = 0
			tag.Parent = stand
			local label = Instance.new("TextLabel")
			label.Size = UDim2.fromScale(1, 1)
			label.BackgroundTransparency = 1
			label.Font = Enum.Font.GothamBold
			label.TextScaled = true
			label.TextColor3 = Color3.new(1, 1, 1)
			label.TextStrokeTransparency = 0.3
			label.Text = string.format("%s\n%s", title, Util.formatMoney(offer.Price))
			label.Parent = tag

			local prompt = MissionsCommon.makePrompt(stand, "Comprar (" .. Util.formatMoney(offer.Price) .. ")", title, 0.3)
			prompt.MaxActivationDistance = 5
			prompt.Triggered:Connect(function(player: Player)
				if ctx.Ended or player:GetAttribute("Alive") ~= true then
					return
				end
				local mine = bought[player] or {}
				bought[player] = mine
				if mine[i] then
					notify(player, "Ya compraste esta oferta.", "info")
					return
				end
				if isWeapon then
					-- Arma: va a su casilla; si ya la llevas, se recarga hasta los usos de la oferta
					local weaponDef = Config.Weapons[itemId]
					local uses = offer.Uses or (weaponDef and weaponDef.Uses)
					local current = player:GetAttribute("WeaponUses_" .. itemId)
					if type(current) == "number" and (not uses or current < 0 or current >= uses) then
						notify(player, "Ya llevas esa arma cargada.", "info")
						return
					end
				elseif room(player, itemId) < offer.Amount then
					notify(player, "No te cabe: llevas demasiados " .. item.DisplayName .. ".", "bad")
					return
				end
				if not RunState.TrySpend(player, offer.Price) then
					notify(player, "Billetes insuficientes.", "bad")
					return
				end
				mine[i] = true
				if isWeapon then
					WeaponService.Equip(player, itemId, offer.Uses)
				else
					ShopService.GiveItem(player, itemId, offer.Amount)
					SfxService.PlayFor(player, "Buy")
					if itemId == "FlashlightPro" then
						FlashlightService.Refresh(player)
					end
				end
				notify(player, string.format("Compraste %s al mercader.", title), "good")
			end)
		end
		model.Parent = MissionsCommon.getPropsFolder()

		local zone = LightService.GetZoneAt(point + Vector3.new(0, 3, 0))
		Remotes.event("Notify"):FireAllClients("El mercader está en " .. (zone or "el mall") .. ". Se irá en un minuto.", "good")

		return function()
			model:Destroy()
			Remotes.event("Notify"):FireAllClients("El mercader se ha ido.", "info")
		end
	end,
}
