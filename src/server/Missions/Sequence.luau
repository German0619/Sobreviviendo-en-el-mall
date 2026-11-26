-- Fabrica de misiones POR ETAPAS: hay que ir a varios lugares, en orden.
-- (Ronda de seguridad, Entrega de paquete, Recoger bandejas, Juntar carritos.)
--
--   Sequence.new({
--     Type = "SecurityRound",
--     CanStart = function(spot, zone) -> boolean,   (opcional)
--     Plan = function(mission) -> plan?,            (nil = no hay puntos libres)
--     ResetNight = function()?,
--   })
--
--   plan = {
--     Stages = {
--       { Targets = { target, ... }, Any = boolean? },  -- Any: basta con UNO de sus puntos
--       ...
--     },
--     Cleanup = function()?,   -- al terminar la tarea (bien o mal): borrar objetos, liberar puntos
--   }
--   target = { Part = BasePart, Action = string, Object = string?, Duration = number?,
--              Zone = string?, OnDone = (player) -> ()? }
--
-- Solo la etapa actual tiene ProximityPrompt y marcador. El progreso va en el atributo
-- Progress de la tarea ("1/4"; una etapa Any cuenta como un paso) y la zona de la tarea
-- pasa a ser la del siguiente punto, asi la lista dice a donde ir.

local Config = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Config)
local LightService = require(script.Parent.Parent.LightService)
local Common = require(script.Parent.Common)

local Sequence = {}

local STEP_COLOR = Color3.fromRGB(255, 200, 60) -- "!" de un punto pendiente
local END_COLOR = Color3.fromRGB(120, 220, 140) -- "▼" de un destino (etapa Any)

local function zoneOf(target, fallback: string): string
	if target.Zone then
		return target.Zone
	end
	local attr = target.Part:GetAttribute("Zone")
	if type(attr) == "string" and attr ~= "" then
		return attr
	end
	return LightService.GetZoneAt(target.Part.Position) or fallback
end

function Sequence.new(opts)
	local module = { ResetNight = opts.ResetNight, CanStart = opts.CanStart }

	function module.Begin(mission, complete)
		local def = Config.Missions[opts.Type]
		local plan = opts.Plan(mission)
		if not plan or #plan.Stages == 0 then
			error("no hay puntos libres para " .. opts.Type)
		end

		local total = 0
		for _, stage in plan.Stages do
			total += if stage.Any then 1 else #stage.Targets
		end
		local done = 0
		local finished = false
		local live: { [any]: { Prompt: ProximityPrompt, Marker: BillboardGui } } = {}

		local function setAttr(name: string, value: any)
			if mission.Value and mission.Value.Parent then
				mission.Value:SetAttribute(name, value)
			end
		end

		local function clearLive()
			for _, entry in live do
				entry.Prompt:Destroy()
				entry.Marker:Destroy()
			end
			table.clear(live)
		end

		-- La lista de tareas muestra la zona del siguiente punto pendiente
		local function updateZone()
			for target in live do
				setAttr("Zone", zoneOf(target, mission.Zone))
				return
			end
		end

		local function startStage(index: number)
			clearLive()
			local stage = plan.Stages[index]
			local remaining = #stage.Targets
			for _, target in stage.Targets do
				local prompt = Common.makePrompt(target.Part, target.Action, target.Object, target.Duration or def.Duration)
				local marker = if stage.Any
					then Common.makeMarker(target.Part, "▼", END_COLOR)
					else Common.makeMarker(target.Part, "!", STEP_COLOR)
				live[target] = { Prompt = prompt, Marker = marker }

				prompt.Triggered:Connect(function(player: Player)
					local entry = live[target]
					if finished or not entry or player:GetAttribute("Alive") ~= true then
						return
					end
					entry.Prompt:Destroy()
					entry.Marker:Destroy()
					live[target] = nil
					if target.OnDone then
						local ok, err = pcall(target.OnDone, player)
						if not ok then
							warn("[Sequence]", opts.Type, err)
						end
					end
					done += 1
					remaining = if stage.Any then 0 else remaining - 1
					setAttr("Progress", string.format("%d/%d", done, total))
					if remaining > 0 then
						updateZone()
					elseif index < #plan.Stages then
						startStage(index + 1)
					else
						finished = true
						clearLive()
						complete(player)
					end
				end)
			end
			updateZone()
		end

		setAttr("Progress", string.format("0/%d", total))
		startStage(1)

		return {
			Cleanup = function(_success: boolean)
				finished = true
				clearLive()
				if plan.Cleanup then
					plan.Cleanup()
				end
			end,
		}
	end

	return module
end

-- Utilidades para los modulos de mision por etapas

-- Partes con un tag (opcionalmente sin las ocupadas).
function Sequence.tagged(tag: string, busy: { [Instance]: boolean }?): { BasePart }
	local list = {}
	for _, part in game:GetService("CollectionService"):GetTagged(tag) do
		if part:IsA("BasePart") and not (busy and busy[part]) then
			table.insert(list, part)
		end
	end
	return list
end

-- n elementos al azar de una lista (sin repetir).
function Sequence.pickRandom<T>(list: { T }, n: number): { T }
	local pool = table.clone(list)
	local result = {}
	for _ = 1, math.min(n, #pool) do
		table.insert(result, table.remove(pool, math.random(1, #pool)))
	end
	return result
end

return Sequence
