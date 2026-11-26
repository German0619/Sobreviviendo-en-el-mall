-- Mision progresiva: Purgar la caldera.
--   1-3. Abrir 3 valvulas EN ORDEN (tag BoilerValve, atributo Zone), al menos una en cada
--        planta (servicio de abajo y sala de maquinas / escalera de arriba).
--   4.   Reiniciar la caldera manteniendo E en su panel (tag BoilerControl).
-- Mientras dura, la caldera suelta vapor y silba. La rueda de cada valvula gira al abrirla
-- y vuelve a su sitio la noche siguiente.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Tags = require(Shared.Tags)
local Sequence = require(script.Parent.Sequence)
local Common = require(script.Parent.Common)

local busy: { [Instance]: boolean } = {}

local function turnWheel(valve: BasePart, open: boolean)
	local wheel = valve:FindFirstChild("Wheel")
	if not wheel or not wheel:IsA("BasePart") then
		return
	end
	local home = wheel:GetAttribute("HomeCFrame")
	if typeof(home) ~= "CFrame" then
		wheel:SetAttribute("HomeCFrame", wheel.CFrame)
		home = wheel.CFrame
	end
	-- (la rueda es un cilindro: su eje es X)
	wheel.CFrame = if open then (home :: CFrame) * CFrame.Angles(math.rad(90), 0, 0) else home :: CFrame
	wheel.Color = if open then Color3.fromRGB(60, 170, 80) else Color3.fromRGB(190, 40, 35)
end

-- n valvulas, mezclando plantas si se puede.
local function pick(n: number): { BasePart }
	local pool = Sequence.pickRandom(Sequence.tagged(Tags.BoilerValve, busy), math.huge)
	local chosen = {}
	for i = 1, math.min(n, #pool) do
		chosen[i] = pool[i]
	end
	if #chosen >= 2 then
		local floor1 = Config.getFloor(chosen[1].Position.Y)
		local mixed = false
		for _, valve in chosen do
			if Config.getFloor(valve.Position.Y) ~= floor1 then
				mixed = true
			end
		end
		if not mixed then
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

local function startSteam(control: BasePart): () -> ()
	local steam = Instance.new("ParticleEmitter")
	steam.Name = "BoilerSteam"
	steam.Texture = "rbxasset://textures/particles/smoke_main.dds"
	steam.Color = ColorSequence.new(Color3.fromRGB(230, 235, 240))
	steam.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 4) })
	steam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1) })
	steam.Lifetime = NumberRange.new(1.2, 2)
	steam.Rate = 30
	steam.Speed = NumberRange.new(4, 7)
	steam.SpreadAngle = Vector2.new(25, 25)
	steam.EmissionDirection = Enum.NormalId.Top
	steam.Parent = control
	local sound = Common.loopSound(control, "Steam", 60)
	return function()
		steam:Destroy()
		if sound then
			sound:Destroy()
		end
	end
end

return Sequence.new({
	Type = "PurgeBoiler",
	CanStart = function(): boolean
		return #Sequence.tagged(Tags.BoilerValve, busy) >= 3 and #Sequence.tagged(Tags.BoilerControl, busy) > 0
	end,
	Plan = function(_mission)
		local valves = pick(Config.Missions.PurgeBoiler.Count or 3)
		local controls = Sequence.tagged(Tags.BoilerControl, busy)
		if #valves < 2 or #controls == 0 then
			return nil
		end
		local control = controls[math.random(1, #controls)]
		busy[control] = true
		local stopSteam = startSteam(control)
		local stages = {}
		for _, valve in valves do
			busy[valve] = true
			table.insert(stages, {
				Targets = {
					{
						Part = valve,
						Action = "Abrir",
						Object = "Válvula de purga",
						OnDone = function()
							turnWheel(valve, true)
						end,
					},
				},
			})
		end
		table.insert(stages, {
			Targets = {
				{
					Part = control,
					Action = "Reiniciar",
					Object = "Caldera",
					Duration = Config.MissionDetails.PurgeBoiler.FinalHold,
				},
			},
		})
		return {
			Stages = stages,
			Cleanup = function()
				stopSteam()
				busy[control] = nil
				for _, valve in valves do
					busy[valve] = nil
				end
			end,
		}
	end,
	ResetNight = function()
		for _, valve in Sequence.tagged(Tags.BoilerValve) do
			turnWheel(valve, false)
		end
	end,
})
