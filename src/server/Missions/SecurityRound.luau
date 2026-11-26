-- Mision progresiva: Ronda de seguridad.
-- Fichar, EN ORDEN, en 3 relojes de control (tag PatrolClock, atributo Zone) de zonas
-- distintas y, si se puede, de las dos plantas. Solo se ve el siguiente reloj.
-- Al fichar, el piloto del reloj se pone verde (vuelve a rojo la noche siguiente).

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Tags = require(Shared.Tags)
local Sequence = require(script.Parent.Sequence)

local RED = Color3.fromRGB(220, 40, 40)
local GREEN = Color3.fromRGB(60, 230, 90)

local busy: { [Instance]: boolean } = {}

local function setLed(clock: BasePart, color: Color3)
	local led = clock:FindFirstChild("Led")
	if led and led:IsA("BasePart") then
		led.Color = color
	end
end

-- Relojes libres, uno por zona como mucho.
local function freeByZone(): { BasePart }
	local seen, list = {}, {}
	for _, clock in Sequence.pickRandom(Sequence.tagged(Tags.PatrolClock, busy), math.huge) do
		local zone = clock:GetAttribute("Zone")
		if not seen[zone] then
			seen[zone] = true
			table.insert(list, clock)
		end
	end
	return list
end

-- n relojes de zonas distintas; si todos caen en la misma planta, cambia uno por otro
-- de la otra planta (para obligar a subir o bajar).
local function pick(n: number): { BasePart }
	local pool = freeByZone()
	local chosen = {}
	for i = 1, math.min(n, #pool) do
		chosen[i] = pool[i]
	end
	if #chosen >= 2 then
		local floor1 = Config.getFloor(chosen[1].Position.Y)
		local allSame = true
		for _, clock in chosen do
			if Config.getFloor(clock.Position.Y) ~= floor1 then
				allSame = false
			end
		end
		if allSame then
			for i = #chosen + 1, #pool do
				if Config.getFloor(pool[i].Position.Y) ~= floor1 then
					chosen[#chosen] = pool[i]
					break
				end
			end
		end
	end
	return chosen
end

return Sequence.new({
	Type = "SecurityRound",
	CanStart = function(): boolean
		return #freeByZone() >= 3
	end,
	Plan = function(_mission)
		local clocks = pick(Config.Missions.SecurityRound.Count or 3)
		if #clocks < 2 then
			return nil
		end
		local stages = {}
		for _, clock in clocks do
			busy[clock] = true
			table.insert(stages, {
				Targets = {
					{
						Part = clock,
						Action = "Fichar",
						Object = "Reloj de control",
						OnDone = function()
							setLed(clock, GREEN)
						end,
					},
				},
			})
		end
		return {
			Stages = stages,
			Cleanup = function()
				for _, clock in clocks do
					busy[clock] = nil
				end
			end,
		}
	end,
	ResetNight = function()
		for _, clock in Sequence.tagged(Tags.PatrolClock) do
			setLed(clock, RED)
		end
	end,
})
