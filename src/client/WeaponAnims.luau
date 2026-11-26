-- WeaponAnims (mall): animaciones de las armas al usarlas (hechas por codigo, sin assets).
--   * Tu arma en primera persona (client/ViewModel.Play).
--   * El brazo derecho de los DEMAS jugadores (su hombro, solo en este cliente): asi se
--     ve el tajo, el disparo, la estocada... desde fuera.
-- El servidor marca cada uso confirmado con el atributo WeaponAnim = "<arma>|<hora>"
-- (WeaponService.Use). La Linterna UV no se anima (solo se enciende y apaga).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local ViewModel = require(script.Parent.ViewModel)

local player = Players.LocalPlayer

local WeaponAnims = {}

local I = CFrame.identity
local rad = math.rad

local function smooth(a: number): number
	return a * a * (3 - 2 * a)
end

-- Fotogramas clave { { t, CFrame }, ... } (t de 0 a 1) -> funcion alpha -> CFrame
local function keys(list: { { any } }): (number) -> CFrame
	return function(a: number): CFrame
		for i = 1, #list - 1 do
			local k0, k1 = list[i], list[i + 1]
			if a <= k1[1] then
				local span = k1[1] - k0[1]
				local t = if span > 0 then (a - k0[1]) / span else 1
				return (k0[2] :: CFrame):Lerp(k1[2], smooth(math.clamp(t, 0, 1)))
			end
		end
		return list[#list][2]
	end
end

-- View: el arma delante de la camara (relativo a su posicion de reposo; -Z = delante).
-- Arm: el hombro derecho de otros jugadores (relativo a su C0).
local ANIMS = {
	-- Tajo: sube el machete y lo baja en diagonal
	Machete = {
		Duration = 0.38,
		View = keys({
			{ 0, I },
			{ 0.3, CFrame.new(0.25, 0.45, 0.25) * CFrame.Angles(rad(55), rad(-10), rad(-35)) },
			{ 0.62, CFrame.new(-0.55, -0.45, -0.35) * CFrame.Angles(rad(-60), rad(25), rad(45)) },
			{ 1, I },
		}),
		Arm = keys({
			{ 0, I },
			{ 0.3, CFrame.Angles(rad(60), 0, rad(25)) },
			{ 0.62, CFrame.Angles(rad(-35), 0, rad(-30)) },
			{ 1, I },
		}),
	},
	-- Retroceso: el cañon salta arriba y atras
	Pistol = {
		Duration = 0.2,
		View = keys({
			{ 0, I },
			{ 0.18, CFrame.new(0, 0.06, 0.28) * CFrame.Angles(rad(16), 0, rad(-3)) },
			{ 1, I },
		}),
		Arm = keys({
			{ 0, I },
			{ 0.2, CFrame.Angles(rad(18), 0, 0) },
			{ 1, I },
		}),
	},
	-- Estocada con chispazo: adelante y una sacudida
	Taser = {
		Duration = 0.3,
		View = keys({
			{ 0, I },
			{ 0.3, CFrame.new(0, 0, -0.5) },
			{ 0.5, CFrame.new(0.04, 0.02, -0.45) * CFrame.Angles(0, 0, rad(7)) },
			{ 0.7, CFrame.new(-0.04, -0.02, -0.45) * CFrame.Angles(0, 0, rad(-7)) },
			{ 1, I },
		}),
		Arm = keys({
			{ 0, I },
			{ 0.3, CFrame.new(0, 0, -0.45) },
			{ 1, I },
		}),
	},
	-- Empujon: coge impulso hacia atras y empuja
	Mop = {
		Duration = 0.42,
		View = keys({
			{ 0, I },
			{ 0.3, CFrame.new(0, 0.12, 0.35) * CFrame.Angles(rad(8), 0, 0) },
			{ 0.55, CFrame.new(0, -0.15, -0.9) * CFrame.Angles(rad(-12), 0, 0) },
			{ 1, I },
		}),
		Arm = keys({
			{ 0, I },
			{ 0.3, CFrame.new(0, 0, 0.3) },
			{ 0.55, CFrame.new(0, 0, -0.7) * CFrame.Angles(rad(-15), 0, 0) },
			{ 1, I },
		}),
	},
	-- Rociar: el extintor tiembla mientras sale el chorro
	Extinguisher = {
		Duration = 0.6,
		View = function(a: number): CFrame
			local fade = 1 - a
			return CFrame.new(math.sin(a * 70) * 0.035 * fade, math.cos(a * 63) * 0.03 * fade, 0.12 * fade)
				* CFrame.Angles(rad(6 * fade), 0, 0)
		end,
		Arm = function(a: number): CFrame
			local fade = 1 - a
			return CFrame.Angles(rad(math.sin(a * 70) * 4 * fade), 0, rad(math.cos(a * 63) * 4 * fade))
		end,
	},
	-- Poner el cartel: bajarlo al suelo y volver
	WetFloorSign = {
		Duration = 0.55,
		View = keys({
			{ 0, I },
			{ 0.45, CFrame.new(0, -0.95, -0.55) * CFrame.Angles(rad(-35), 0, 0) },
			{ 1, I },
		}),
		Arm = keys({
			{ 0, I },
			{ 0.45, CFrame.Angles(rad(-40), 0, 0) },
			{ 1, I },
		}),
	},
}

----------------------------------------------------------------------
-- Brazo de los demas jugadores (hombro derecho, solo en este cliente)
----------------------------------------------------------------------

type ArmAnim = { Motor: Motor6D, Base: CFrame, Fn: (number) -> CFrame, Start: number, Duration: number }
local armAnims: { [Motor6D]: ArmAnim } = {}

local function rightShoulder(character: Model): Motor6D?
	local upper = character:FindFirstChild("RightUpperArm")
	local m = upper and upper:FindFirstChild("RightShoulder")
	if m and m:IsA("Motor6D") then
		return m
	end
	local torso = character:FindFirstChild("Torso")
	local r6 = torso and torso:FindFirstChild("Right Shoulder")
	return if r6 and r6:IsA("Motor6D") then r6 else nil
end

local function playArm(character: Model, def)
	local motor = rightShoulder(character)
	if not motor then
		return
	end
	local current = armAnims[motor]
	local base = if current then current.Base else motor.C0
	armAnims[motor] = { Motor = motor, Base = base, Fn = def.Arm, Start = os.clock(), Duration = def.Duration }
end

local function stepArms()
	local now = os.clock()
	for motor, a in armAnims do
		local alpha = (now - a.Start) / a.Duration
		if alpha >= 1 or not motor.Parent then
			if motor.Parent then
				motor.C0 = a.Base
			end
			armAnims[motor] = nil
		else
			motor.C0 = a.Base * a.Fn(math.clamp(alpha, 0, 1))
		end
	end
end

----------------------------------------------------------------------
-- Arranque
----------------------------------------------------------------------

local function onAnim(who: Player)
	local value = who:GetAttribute("WeaponAnim")
	if type(value) ~= "string" then
		return
	end
	local weaponId = string.match(value, "^([^|]+)")
	local def = weaponId and ANIMS[weaponId]
	if not def then
		return
	end
	if who == player then
		ViewModel.Play(def.View, def.Duration) -- tu, en primera persona
	elseif who.Character then
		playArm(who.Character, def)
	end
end

local function watch(who: Player)
	who:GetAttributeChangedSignal("WeaponAnim"):Connect(function()
		onAnim(who)
	end)
end

function WeaponAnims.Start()
	for _, p in Players:GetPlayers() do
		watch(p)
	end
	Players.PlayerAdded:Connect(watch)
	RunService.RenderStepped:Connect(stepArms)
end

return WeaponAnims
