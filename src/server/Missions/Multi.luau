-- Fabrica de misiones de varios puntos (p. ej. regar 3 plantas, bajar 3 persianas).
--
-- El MissionSpot de la mision solo indica la zona; los puntos reales son las
-- partes con TargetTag cuyo atributo (TargetAttribute) coincide con esa zona.
-- Se completa al terminar todos (el ultimo jugador se lleva el credito).
-- El progreso se publica en el atributo Progress de la mision ("1/3").
--
--   Multi.new({
--     Type = "WaterPlants", TargetTag = Tags.Planter, TargetAttribute = "Zone",
--     ActionText = "Regar", ObjectText = "Planta",
--     OnStep = function(part, player)?, ResetNight = function()?,
--     OnActivate = function(part) -> (() -> ())?,  -- efecto mientras el punto esta pendiente
--                                                  -- (agua, musica...); devuelve como pararlo
--     OnFail = function(mission, pending: { BasePart })?,  -- si caduca (charco, etc.)
--   })

local CollectionService = game:GetService("CollectionService")
local Config = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Config)
local Common = require(script.Parent.Common)

local Multi = {}

function Multi.new(opts)
	local busy: { [BasePart]: boolean } = {}

	local function freeTargets(zone: string): { BasePart }
		local list = {}
		for _, part in CollectionService:GetTagged(opts.TargetTag) do
			if part:IsA("BasePart") and part:GetAttribute(opts.TargetAttribute) == zone and not busy[part] then
				table.insert(list, part)
			end
		end
		return list
	end

	local module = { ResetNight = opts.ResetNight }

	function module.CanStart(_spot: BasePart, zone: string): boolean
		local count = Config.Missions[opts.Type].Count or 3
		return #freeTargets(zone) >= math.min(count, 2)
	end

	function module.Begin(mission, complete)
		local def = Config.Missions[opts.Type]
		local pool = freeTargets(mission.Zone)
		local targets = {}
		for _ = 1, math.min(def.Count or 3, #pool) do
			table.insert(targets, table.remove(pool, math.random(1, #pool)))
		end
		if #targets == 0 then
			error("no hay puntos libres para " .. opts.Type .. " en " .. mission.Zone)
		end

		local total = #targets
		local doneCount = 0
		local pending: { [BasePart]: { Prompt: ProximityPrompt, Marker: BillboardGui, Stop: (() -> ())? } } = {}
		mission.Value:SetAttribute("Progress", string.format("0/%d", total))

		for _, part in targets do
			busy[part] = true
			local prompt = Common.makePrompt(part, opts.ActionText, opts.ObjectText, def.Duration)
			if opts.RepairTask then
				prompt:SetAttribute("RepairTask", true)
			end
			local marker = Common.makeMarker(part)
			local stop = if opts.OnActivate then opts.OnActivate(part) else nil
			pending[part] = { Prompt = prompt, Marker = marker, Stop = stop }

			prompt.Triggered:Connect(function(player: Player)
				local entry = pending[part]
				if not entry or player:GetAttribute("Alive") ~= true then
					return
				end
				pending[part] = nil
				busy[part] = nil
				prompt:Destroy()
				marker:Destroy()
				if entry.Stop then
					entry.Stop()
				end
				doneCount += 1
				if opts.OnStep then
					opts.OnStep(part, player)
				end
				if mission.Value.Parent then
					mission.Value:SetAttribute("Progress", string.format("%d/%d", doneCount, total))
				end
				if doneCount >= total then
					complete(player)
				end
			end)
		end

		return {
			Cleanup = function(success: boolean, silent: boolean?)
				local left = {}
				for part, entry in pending do
					entry.Prompt:Destroy()
					entry.Marker:Destroy()
					if entry.Stop then
						entry.Stop()
					end
					busy[part] = nil
					table.insert(left, part)
				end
				pending = {}
				if not success and not silent and opts.OnFail and #left > 0 then
					opts.OnFail(mission, left)
				end
			end,
		}
	end

	return module
end

return Multi
