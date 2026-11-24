-- Persianas cerradas: varias tiendas de una planta se sellan (la persiana baja hasta el
-- suelo, con colision). Cada una se abre con una mision de evento en su persiana, que se
-- puede hacer desde fuera o desde dentro. Si caduca, sale otra. Al acabar el tiempo
-- maximo se abren solas.

local Remotes = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Remotes)

local Server = script.Parent.Parent
local LightService = require(Server.LightService)
local MissionService = require(Server.MissionService)
local EventUtil = require(script.Parent.EventUtil)

return {
	CanStart = function(ctx)
		return #EventUtil.getStores(ctx.Floor) > 0
	end,
	Start = function(ctx)
		local def = ctx.Def
		local stores = EventUtil.getStores(ctx.Floor)
		-- Las mas cercanas a los jugadores primero (con algo de azar)
		local scored = {}
		for _, store in stores do
			table.insert(scored, { Store = store, Score = EventUtil.nearestPlayerDistance(store.Shutter.Position) + math.random() * 40 })
		end
		table.sort(scored, function(a, b)
			return a.Score < b.Score
		end)

		local open = {} -- [store] = funcion que la abre
		local missions = {}
		local pending = 0

		local function offer(store)
			local handle
			handle = MissionService.StartEventMission({
				DisplayName = "Abrir la persiana de " .. store.Zone,
				Spot = store.Shutter,
				ActionText = "Abrir persiana",
				ObjectText = store.Zone,
				HoldSeconds = def.HoldSeconds,
				TimeLimit = def.MissionSeconds,
				OnComplete = function()
					missions[handle] = nil
					local restore = open[store]
					open[store] = nil
					if restore then
						restore()
					end
					pending -= 1
					if pending <= 0 then
						ctx.Finish()
					end
				end,
				OnExpire = function()
					missions[handle] = nil
					if not ctx.Ended and open[store] then
						offer(store)
					end
				end,
			})
			missions[handle] = true
		end

		local names = {}
		for i = 1, math.min(def.Stores, #scored) do
			local store = scored[i].Store
			open[store] = EventUtil.sealShutter(store, 1.5)
			pending += 1
			table.insert(names, store.Zone)
			offer(store)
			-- Quien se quede dentro, que lo sepa
			for _, player in EventUtil.alivePlayers() do
				local root = EventUtil.rootOf(player)
				if root and LightService.GetZoneAt(root.Position) == store.Zone then
					Remotes.event("Notify"):FireClient(player, "¡Te quedaste encerrado en " .. store.Zone .. "! Abre la persiana desde dentro.", "bad")
				end
			end
		end
		Remotes.event("Notify"):FireAllClients("Tiendas selladas: " .. table.concat(names, ", ") .. ".", "bad")

		ctx.SetEndsAt(def.MaxSeconds)
		task.delay(def.MaxSeconds, ctx.Finish)

		return function()
			for handle in missions do
				handle.Cancel()
			end
			for _, restore in open do
				restore()
			end
		end
	end,
}
