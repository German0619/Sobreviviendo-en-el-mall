-- EnemyAnimator: animaciones de movimiento de los enemigos hechos con piezas.
--
-- Los enemigos son modelos ANCLADOS que el servidor mueve con PivotTo, asi que la
-- animacion tambien se hace en el servidor: despues de que el enemigo se mueve
-- (EnemyService, tras Update), cada extremidad se coloca respecto a la raiz a partir de
-- su pose de reposo, girada sobre su articulacion (cadera, hombro, eje de la rueda).
--
-- * Las extremidades se reconocen por el NOMBRE de la pieza (LeftLeg, Arm, Wheel...) y
--   el lado por su posicion; lo que llevan (zapatos, guantes, linterna, walkie) sigue a
--   la extremidad mas cercana.
-- * Los detalles (atributos Detail / Follow: botones, dedos, tapacubos...) no se tocan:
--   Common.prepareModel los suelda sin anclar a su pieza y se mueven con ella.
-- * El paso va con lo que el enemigo avanza de verdad: quieto, se queda quieto (da mas
--   miedo, y el Maniqui y la Estatua dependen de eso).
-- * Estilos por tipo de enemigo en Config.EnemyAnimation:
--     Biped     piernas y brazos alternados
--     Stiff     igual, pero rigido y a tirones (el Maniqui)
--     ArmsOnly  solo los brazos (el Coleccionista: el abrigo tapa las piernas)
--     Quadruped cuatro patas en diagonal (el Rastro)
--     Crawler   patas de araña por turnos (el Ducto)
--     Wheels    ruedas que giran (el Carrito)
-- * Modelos de una sola pieza (plantillas con MeshPart, maniquies del mapa): el cuerpo
--   entero se balancea sobre los pies (RockAngle).

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local EnemyAnimator = {}

-- Piezas que siguen a la extremidad mas cercana
local LEG_FOLLOWERS = { Shoe = true, Shoes = true, Foot = true, LowerLeg = true }
local ARM_FOLLOWERS = {
	Hand = true,
	Glove = true,
	Lantern = true,
	Walkie = true,
	WalkieLed = true,
	Case = true,
	CaseFrame = true,
	Figurine = true,
}

-- RockAngle: si el modelo es de UNA pieza (los maniquies del mapa y las plantillas de
-- ServerStorage.EnemyTemplates hechas con un MeshPart), todo el cuerpo se balancea de lado
-- sobre los pies al andar (a tirones con Snap).
-- Attack: animacion al golpear (Common.playAttack pone el atributo AttackAt en el modelo):
--   Swipe  zarpazo: levanta los brazos y los baja de golpe (uno tras otro)
--   Grab   agarre rigido: los brazos saltan al frente y se quedan un momento
--   Pounce salto: patas delanteras arriba y adelante, las de atras empujan
--   Raise  patas delanteras arriba y clavadas (el Ducto)
local STYLES = {
	Biped = { LegAngle = 32, ArmAngle = 26, Stride = 2.4, Smooth = 10, RockAngle = 5, Attack = "Swipe" },
	Stiff = { LegAngle = 22, ArmAngle = 12, Stride = 3.2, Smooth = 10, Snap = true, RockAngle = 7, Attack = "Grab" },
	ArmsOnly = { LegAngle = 0, ArmAngle = 18, Stride = 2.6, Smooth = 8, RockAngle = 4, Attack = "Swipe" },
	Quadruped = { LegAngle = 34, ArmAngle = 0, Stride = 2.0, Smooth = 12, RockAngle = 5, Attack = "Pounce" },
	Crawler = { LegAngle = 28, ArmAngle = 0, Stride = 1.6, Smooth = 12, Sideways = true, Attack = "Raise" },
	Wheels = { Smooth = 10 },
	-- La Estatua (golem de piedra): pasos cortos y pesados; los brazos no se mueven
	Golem = { LegAngle = 18, ArmAngle = 0, Stride = 3.6, Smooth = 8 },
	-- Fantasmas que flotan (el Apagon): SIEMPRE se mecen arriba y abajo, los brazos
	-- cuelgan y se balancean despacio, y al desplazarse se inclinan hacia delante.
	Float = {
		LegAngle = 6,
		ArmAngle = 12,
		Smooth = 4,
		Float = true,
		BobHeight = 0.3, -- studs
		BobSpeed = 1.7, -- rad/s
		SwaySpeed = 1.2,
		Lean = 10, -- grados al desplazarse
		Attack = "Swipe", -- y se abalanza hacia delante
	},
}

-- Duracion de la animacion de ataque (s)
local ATTACK_TIME = 0.45

-- Pose de ataque de una extremidad en el instante t (s desde el golpe): (giro, peso).
-- peso: cuanto sustituye a la pose de andar (1 = del todo).
local function attackPose(kind: string?, limb, t: number): (CFrame?, number)
	local joint = limb.Joint.Position
	local fade = math.clamp((ATTACK_TIME - t) / 0.12, 0, 1)
	if kind == "Swipe" or kind == "Grab" then
		if limb.Kind ~= "Arm" then
			return nil, 0
		end
		-- (solo brazos que cuelgan: el brazo doblado del Gerente sigue con su walkie)
		if math.abs(limb.Rest.UpVector.Y) < 0.8 then
			return nil, 0
		end
		local k = math.max(0, t - (if joint.X < 0 then 0.05 else 0)) -- uno tras otro
		local angle
		if kind == "Grab" then
			angle = if k < 0.07 then 95 * k / 0.07 elseif k < 0.32 then 95 else 95 * math.max(0, 1 - (k - 0.32) / 0.1)
		elseif k < 0.12 then
			angle = 115 * math.sin(k / 0.12 * math.pi / 2) -- arriba
		elseif k < 0.22 then
			angle = 115 - 105 * ((k - 0.12) / 0.1) ^ 2 -- zarpazo hacia abajo
		else
			angle = 10 * math.max(0, 1 - (k - 0.22) / 0.2)
		end
		return CFrame.Angles(math.rad(angle), 0, 0), fade
	elseif kind == "Pounce" then
		if limb.Kind ~= "Leg" then
			return nil, 0
		end
		local amount = if t < 0.15 then t / 0.15 elseif t < 0.3 then 1 else math.max(0, 1 - (t - 0.3) / 0.15)
		return CFrame.Angles(math.rad((if joint.Z < 0 then 60 else -18) * amount), 0, 0), 1
	elseif kind == "Raise" then
		if limb.Kind ~= "Leg" or joint.Z >= 0 then
			return nil, 0
		end
		local side = if joint.X < 0 then -1 else 1
		local angle = if t < 0.15 then 50 * t / 0.15 elseif t < 0.25 then 50 - 65 * (t - 0.15) / 0.1 else -15 * math.max(0, 1 - (t - 0.25) / 0.2)
		return CFrame.Angles(0, 0, math.rad(side * angle)), 1
	end
	return nil, 0
end

type Limb = {
	Part: BasePart,
	Rest: CFrame, -- respecto a la raiz
	Joint: CFrame, -- articulacion respecto a la raiz (orientacion de la raiz)
	Phase: number, -- 0 o math.pi (alternas)
	Kind: string, -- "Leg" | "Arm" | "Wheel" | "Rock" (cuerpo entero de una pieza)
	Radius: number?, -- ruedas
	Followers: { { Part: BasePart, Rest: CFrame } },
}

local Rig = {}
Rig.__index = Rig

-- Piernas: LeftLeg, Leg, UpperLeg, FrontLeftLeg... (LowerLeg es la mitad de abajo: sigue)
local function isLeg(name: string): boolean
	return string.find(name, "Leg") ~= nil and name ~= "LowerLeg"
end

-- Brazos: LeftArm, RightArm, Arm...
local function isArm(name: string): boolean
	return string.find(name, "Arm") ~= nil
end

-- Crea el esqueleto de un enemigo (o nil si su tipo no se anima o no tiene extremidades).
function EnemyAnimator.attach(model: Model, enemyType: string)
	local styleName = Config.EnemyAnimation and Config.EnemyAnimation[enemyType]
	local style = styleName and STYLES[styleName]
	local root = model.PrimaryPart
	if not style or not root then
		return nil
	end
	local rootCF = root.CFrame
	local limbs: { Limb } = {}
	local followers: { BasePart } = {}
	local floating: { BasePart } = {} -- Float: piezas que no son extremidades (torso, ojos...)

	for _, d in model:GetDescendants() do
		-- (solo piezas ancladas: los detalles soldados van con su pieza)
		if d:IsA("BasePart") and d ~= root and d.Anchored then
			local rest = rootCF:ToObjectSpace(d.CFrame)
			local kind = nil
			if styleName == "Wheels" then
				kind = if d.Name == "Wheel" then "Wheel" else nil
			elseif isLeg(d.Name) and style.LegAngle > 0 then
				kind = "Leg"
			elseif isArm(d.Name) and style.ArmAngle > 0 then
				kind = "Arm"
			elseif LEG_FOLLOWERS[d.Name] or ARM_FOLLOWERS[d.Name] then
				table.insert(followers, d)
			elseif style.Float then
				table.insert(floating, d) -- (el resto del cuerpo tambien flota)
			end
			if kind then
				-- Articulacion: arriba de la pieza (cadera u hombro); la rueda, en su centro
				local jointPos = if kind == "Wheel" then rest.Position else (rest * CFrame.new(0, d.Size.Y / 2, 0)).Position
				table.insert(limbs, {
					Part = d,
					Rest = rest,
					Joint = CFrame.new(jointPos),
					Phase = 0,
					Kind = kind,
					Radius = if kind == "Wheel" then math.max(d.Size.Y, d.Size.Z) / 2 else nil,
					Followers = {},
				})
			end
		end
	end
	-- Float: el resto del cuerpo es una "extremidad" fija que solo sube, baja y se inclina
	if style.Float and #floating > 0 then
		local body: Limb = {
			Part = floating[1],
			Rest = rootCF:ToObjectSpace(floating[1].CFrame),
			Joint = CFrame.new(),
			Phase = 0,
			Kind = "Body",
			Followers = {},
		}
		for i = 2, #floating do
			table.insert(body.Followers, { Part = floating[i], Rest = rootCF:ToObjectSpace(floating[i].CFrame) })
		end
		table.insert(limbs, body)
	end

	-- Sin extremidades sueltas (modelo de una pieza) y con RockAngle: todo el cuerpo es
	-- una sola "extremidad" que se balancea de lado sobre los pies
	if #limbs == 0 and style.RockAngle then
		local body: BasePart? = nil
		local others = {}
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") and d ~= root and d.Anchored then
				if not body or d.Size.Magnitude > body.Size.Magnitude then
					if body then
						table.insert(others, body)
					end
					body = d
				else
					table.insert(others, d)
				end
			end
		end
		if body then
			local rock: Limb = {
				Part = body,
				Rest = rootCF:ToObjectSpace(body.CFrame),
				Joint = CFrame.new(0, -root.Size.Y / 2, 0), -- los pies
				Phase = 0,
				Kind = "Rock",
				Followers = {},
			}
			for _, part in others do
				table.insert(rock.Followers, { Part = part, Rest = rootCF:ToObjectSpace(part.CFrame) })
			end
			table.insert(limbs, rock)
		end
	end
	if #limbs == 0 then
		return nil
	end

	-- Fases: lado izquierdo y derecho alternos; brazos al reves que las piernas del mismo
	-- lado; a cuatro patas, en diagonal; el reptante, por turnos a lo largo del cuerpo.
	for _, limb in limbs do
		local p = limb.Joint.Position
		local side = if p.X < 0 then 0 else 1
		local phase = side * math.pi
		if limb.Kind == "Arm" then
			phase += math.pi
		end
		if styleName == "Quadruped" or styleName == "Crawler" then
			local front = if p.Z < 0 then 0 else 1
			phase = ((side + front) % 2) * math.pi
			if styleName == "Crawler" then
				phase += p.Z * 0.9 -- onda a lo largo del cuerpo
			end
		end
		limb.Phase = phase
	end

	-- Lo que llevan sigue a la extremidad mas cercana del tipo que le toca
	for _, part in followers do
		local rest = rootCF:ToObjectSpace(part.CFrame)
		local wanted = if LEG_FOLLOWERS[part.Name] then "Leg" else "Arm"
		local best, bestDist = nil, math.huge
		for _, limb in limbs do
			if limb.Kind == wanted then
				local dist = (limb.Rest.Position - rest.Position).Magnitude
				if dist < bestDist then
					best, bestDist = limb, dist
				end
			end
		end
		if best and bestDist < 6 then
			table.insert(best.Followers, { Part = part, Rest = rest })
		end
	end

	local self = setmetatable({}, Rig)
	self.Model = model
	self.Root = root
	self.Style = style
	-- Float: altura a la que flota sobre el suelo (Config.Enemies.<tipo>.FloatLift)
	local enemyDef = Config.Enemies[enemyType]
	self.Lift = if enemyDef and type(enemyDef.FloatLift) == "number" then enemyDef.FloatLift else (style.BaseLift or 0)
	self.Limbs = limbs
	self.Phase = 0 -- avance del paso (radianes)
	self.Amount = 0 -- 0 quieto .. 1 andando (suavizado)
	self.Spin = 0 -- giro de las ruedas
	self.Snapped = 0 -- Stiff: angulo "a tirones" actual
	self.LastPos = root.Position
	return self
end

function Rig:Step(dt: number)
	local root = self.Root
	if not root.Parent then
		return
	end
	local style = self.Style
	local pos = root.Position
	local moved = Vector3.new(pos.X - self.LastPos.X, 0, pos.Z - self.LastPos.Z).Magnitude
	self.LastPos = pos
	if moved > 6 then
		moved = 0 -- teletransporte (aparecer, cambiar de escondite): no cuenta como paso
	end
	local speed = moved / math.max(dt, 1e-3)

	-- Cuanto anda (suavizado): quieto vuelve a la pose de reposo
	local target = if speed > 0.6 then 1 else 0
	self.Amount += (target - self.Amount) * math.min(1, dt * (style.Smooth or 10))
	-- Golpe en curso (Common.playAttack): segundos desde el golpe, o nil
	local now = os.clock()
	local attackAt = self.Model:GetAttribute("AttackAt")
	local attackT = if style.Attack and type(attackAt) == "number" and now - attackAt >= 0 and now - attackAt < ATTACK_TIME
		then now - attackAt
		else nil
	-- Quieto y ya en reposo: no tocar las piezas (PivotTo conserva la pose).
	-- (Los que flotan no paran nunca; tampoco mientras golpea.)
	if style.Float or attackT then
		self.Settled = false
	elseif target == 0 and self.Amount < 0.01 then
		if self.Settled then
			return
		end
		self.Amount = 0
		self.Settled = true
	else
		self.Settled = false
	end

	local parts: { BasePart } = {}
	local cframes: { CFrame } = {}
	local rootCF = root.CFrame

	if style.Stride then
		self.Phase += moved / style.Stride * math.pi
	end
	self.Spin += moved

	-- Rigido a tirones: el angulo salta entre dos poses en vez de oscilar
	local snapTarget = if math.sin(self.Phase) >= 0 then 1 else -1
	if style.Snap then
		self.Snapped += (snapTarget - self.Snapped) * math.min(1, dt * 25)
	end

	-- Flotar: todo el cuerpo sube y baja y, al desplazarse, se inclina hacia delante
	-- (al golpear se abalanza: adelante e inclinado)
	local floatCF = CFrame.identity
	if style.Float then
		local lunge = if attackT then math.sin(math.min(attackT / 0.3, 1) * math.pi) else 0
		-- (sobre FloatLift; el balanceo nunca lo hunde en el suelo)
		floatCF = CFrame.new(0, self.Lift + style.BobHeight + math.sin(now * style.BobSpeed) * style.BobHeight, -0.9 * lunge)
			* CFrame.Angles(-math.rad(style.Lean * self.Amount + 25 * lunge), 0, 0)
	end

	for _, limb in self.Limbs do
		local offset: CFrame
		if limb.Kind == "Body" then
			offset = CFrame.identity
		elseif style.Float then
			-- Brazos y piernas colgando que se balancean despacio (cada uno a su ritmo)
			local maxAngle = if limb.Kind == "Leg" then style.LegAngle else style.ArmAngle
			offset = CFrame.Angles(math.rad(maxAngle) * math.sin(now * style.SwaySpeed + limb.Phase), 0, 0)
		elseif limb.Kind == "Wheel" then
			offset = CFrame.Angles(-self.Spin / (limb.Radius or 1), 0, 0)
		elseif limb.Kind == "Rock" then
			-- De lado a lado, a tirones (Snap) o suave
			local wave = if style.Snap then self.Snapped else math.sin(self.Phase)
			offset = CFrame.Angles(0, 0, math.rad(style.RockAngle) * wave * self.Amount)
		else
			local maxAngle = if limb.Kind == "Leg" then style.LegAngle else style.ArmAngle
			local wave
			if style.Snap then
				wave = self.Snapped * (if limb.Phase % (2 * math.pi) < 0.1 then 1 else -1)
			else
				wave = math.sin(self.Phase + limb.Phase)
			end
			local angle = math.rad(maxAngle) * wave * self.Amount
			-- El reptante mueve las patas hacia los lados; los demas, adelante y atras
			offset = if style.Sideways then CFrame.Angles(0, angle, 0) else CFrame.Angles(angle, 0, 0)
		end
		-- Golpe: la pose de ataque sustituye (del todo o en parte) a la de andar
		if attackT and limb.Kind ~= "Body" then
			local pose, weight = attackPose(style.Attack, limb, attackT)
			if pose then
				offset = offset:Lerp(pose, weight)
			end
		end
		local transform = floatCF * limb.Joint * offset * limb.Joint:Inverse()
		table.insert(parts, limb.Part)
		table.insert(cframes, rootCF * transform * limb.Rest)
		for _, follower in limb.Followers do
			table.insert(parts, follower.Part)
			table.insert(cframes, rootCF * transform * follower.Rest)
		end
	end
	Workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
end

-- Todo a la pose de reposo (antes de devolver un modelo del mapa a su sitio).
function Rig:Reset()
	local root = self.Root
	if not root.Parent then
		return
	end
	local rootCF = root.CFrame
	local parts: { BasePart } = {}
	local cframes: { CFrame } = {}
	for _, limb in self.Limbs do
		table.insert(parts, limb.Part)
		table.insert(cframes, rootCF * limb.Rest)
		for _, follower in limb.Followers do
			table.insert(parts, follower.Part)
			table.insert(cframes, rootCF * follower.Rest)
		end
	end
	Workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	self.Amount = 0
	self.Settled = true
end

return EnemyAnimator
