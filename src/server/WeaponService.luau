-- WeaponService: armas del mall (Config.Weapons). Defensas temporales: aturden o
-- apartan a los enemigos, no los matan.
--
-- * Una equipada a la vez, se usa con [R] (UseWeapon). Se compran con billetes en
--   la tienda del mall (ShopService llama a Equip); comprar otra reemplaza a la
--   actual y comprar la misma recarga sus usos. Se pierden al morir (ShopService
--   llama a Clear junto con el inventario).
-- * Taser: aturde al enemigo mas cercano de enfrente (nivel 3: casi nada).
-- * Extintor: nube que ciega (DefenseService.AddSmoke) y tapa el olor del Rastro.
-- * Cartel de piso mojado: trampa que ralentiza (DefenseService.AddSlowZone).
-- * Linterna UV: [R] la enciende/apaga; revela de lejos a los enemigos con OnUV
--   (el Eco) y gasta mas bateria (FlashlightService).
-- * Trapeador: empujon corto (DefenseService.Push con menos fuerza que el Porrazo).
--
-- Atributos del Player: Weapon (id o nil), WeaponUses (-1 = infinitos),
-- WeaponReadyAt (Workspace:GetServerTimeNow()) y UVOn.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)

local DefenseService = require(script.Parent.DefenseService)
local FlashlightService = require(script.Parent.FlashlightService)

local WeaponService = {}

local W = Config.Weapons
local lastUse: { [Player]: number } = {}

local function notify(player: Player, message: string, kind: string?)
	Remotes.event("Notify"):FireClient(player, message, kind or "info")
end

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

local function getRoot(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function displayName(weaponId: string): string
	local item = Config.ShopItems[weaponId]
	return if item then item.DisplayName else weaponId
end

local function propsFolder(): Folder
	local folder = Workspace:FindFirstChild("DefenseProps")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "DefenseProps"
		folder.Parent = Workspace
	end
	return folder :: Folder
end

local function rayParams(player: Player): RaycastParams
	local exclude: { Instance } = { propsFolder() }
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(exclude, p.Character)
		end
	end
	local enemies = Workspace:FindFirstChild("Enemies")
	if enemies then
		table.insert(exclude, enemies)
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclude
	return params
end

local function part(props): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props do
		(p :: any)[k] = v
	end
	return p
end

----------------------------------------------------------------------
-- Equipar / quitar
----------------------------------------------------------------------

function WeaponService.Get(player: Player): string?
	local id = player:GetAttribute("Weapon")
	return if type(id) == "string" and W[id] then id else nil
end

-- Se puede comprar? (no si ya la llevas y no hay nada que recargar)
function WeaponService.CanEquip(player: Player, weaponId: string): (boolean, string?)
	local def = W[weaponId]
	if not def then
		return false, "Arma inválida"
	end
	if WeaponService.Get(player) == weaponId then
		if not def.Uses then
			return false, "Ya la llevas"
		end
		if (player:GetAttribute("WeaponUses") or 0) >= def.Uses then
			return false, "Ya la tienes cargada"
		end
	end
	return true, nil
end

function WeaponService.Equip(player: Player, weaponId: string)
	local def = W[weaponId]
	if not def then
		return
	end
	local previous = WeaponService.Get(player)
	if previous == "UVFlashlight" and weaponId ~= "UVFlashlight" then
		WeaponService.SetUV(player, false)
	end
	player:SetAttribute("Weapon", weaponId)
	player:SetAttribute("WeaponUses", def.Uses or -1)
	player:SetAttribute("WeaponReadyAt", 0)
	if previous and previous ~= weaponId then
		notify(player, string.format("Dejaste %s y equipaste %s [R].", displayName(previous), displayName(weaponId)))
	end
end

function WeaponService.Clear(player: Player)
	if WeaponService.Get(player) == "UVFlashlight" then
		WeaponService.SetUV(player, false)
	end
	player:SetAttribute("Weapon", nil)
	player:SetAttribute("WeaponUses", nil)
	player:SetAttribute("WeaponReadyAt", nil)
end

-- Gasta un uso (si tiene limite). Sin usos: se pierde el arma.
local function consume(player: Player, weaponId: string)
	local def = W[weaponId]
	player:SetAttribute("WeaponReadyAt", serverNow() + (def.Cooldown or 0))
	if def.Uses then
		local left = (player:GetAttribute("WeaponUses") or 0) - 1
		player:SetAttribute("WeaponUses", left)
		if left <= 0 then
			WeaponService.Clear(player)
			notify(player, string.format("%s se quedó sin usos.", displayName(weaponId)), "bad")
		end
	end
end

----------------------------------------------------------------------
-- Taser
----------------------------------------------------------------------

local function taserBolt(from: Vector3, to: Vector3)
	local length = (to - from).Magnitude
	local bolt = part({
		Name = "TaserBolt",
		Size = Vector3.new(0.15, 0.15, length),
		CFrame = CFrame.lookAt((from + to) / 2, to),
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(120, 200, 255),
	})
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(120, 200, 255)
	light.Range = 10
	light.Brightness = 3
	light.Parent = bolt
	bolt.Parent = propsFolder()
	TweenService:Create(bolt, TweenInfo.new(0.2), { Transparency = 1 }):Play()
	task.delay(0.25, function()
		bolt:Destroy()
	end)
end

local function useTaser(player: Player): boolean
	local def = W.Taser
	local root = getRoot(player)
	if not root then
		return false
	end
	local origin = root.Position + Vector3.new(0, 1, 0)
	local look = root.CFrame.LookVector
	local cosHalf = math.cos(math.rad(def.HalfAngle))
	local params = rayParams(player)

	local best, bestDist = nil, math.huge
	for _, enemy in DefenseService.GetEnemies() do
		local model = enemy.Model
		if enemy.EnemyType and model and model.Parent then
			local pos = model:GetPivot().Position
			local offset = pos - origin
			local dist = offset.Magnitude
			if dist <= def.Range and dist < bestDist and (dist < 2 or look:Dot(offset.Unit) >= cosHalf) then
				-- Sin paredes de por medio
				local hit = Workspace:Raycast(origin, offset, params)
				if not hit or (hit.Position - origin).Magnitude >= dist - 2 then
					best, bestDist = enemy, dist
				end
			end
		end
	end
	if not best then
		notify(player, "El taser no alcanza a ningún enemigo delante.")
		return false
	end

	local model = best.Model
	taserBolt(origin, model:GetPivot().Position)
	local enemyDef = Config.Enemies[best.EnemyType]
	if enemyDef and enemyDef.TaserImmune then
		notify(player, "¡No le hace nada!", "bad")
		return true
	end
	if best.OnTaser then
		local ok, err = pcall(best.OnTaser, best, player)
		if not ok then
			warn("[WeaponService] OnTaser:", err)
		end
	else
		local tier = enemyDef and enemyDef.Tier or 1
		local seconds = if tier >= 3 then def.Tier3StunSeconds else def.StunSeconds
		DefenseService.Stun(model, seconds)
		if tier >= 3 then
			notify(player, "Apenas lo aturdiste: es demasiado fuerte.", "bad")
		end
	end
	return true
end

----------------------------------------------------------------------
-- Extintor
----------------------------------------------------------------------

local function useExtinguisher(player: Player): boolean
	local def = W.Extinguisher
	local root = getRoot(player)
	if not root then
		return false
	end
	local origin = root.Position + Vector3.new(0, 1, 0)
	local look = root.CFrame.LookVector
	look = Vector3.new(look.X, 0, look.Z)
	look = if look.Magnitude > 0.01 then look.Unit else Vector3.new(0, 0, -1)
	local hit = Workspace:Raycast(origin, look * def.Range, rayParams(player))
	local center = if hit then hit.Position - look * 2 else origin + look * def.Range

	local cloud = part({
		Name = "ExtinguisherCloud",
		Size = Vector3.new(1, 1, 1),
		CFrame = CFrame.new(center),
		Transparency = 1,
	})
	local smoke = Instance.new("ParticleEmitter")
	smoke.Color = ColorSequence.new(Color3.fromRGB(235, 238, 245))
	smoke.LightInfluence = 1
	smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 4), NumberSequenceKeypoint.new(1, def.Radius * 0.9) })
	smoke.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(0.7, 0.35),
		NumberSequenceKeypoint.new(1, 1),
	})
	smoke.Lifetime = NumberRange.new(2.5, 3.5)
	smoke.Rate = 25
	smoke.Speed = NumberRange.new(2, 5)
	smoke.SpreadAngle = Vector2.new(180, 180)
	smoke.Drag = 2
	smoke.Parent = cloud
	cloud.Parent = propsFolder()
	-- Chorro desde el jugador hasta la nube
	local spray = part({
		Name = "Spray",
		Size = Vector3.new(0.6, 0.6, (center - origin).Magnitude),
		CFrame = CFrame.lookAt((origin + center) / 2, center),
		Material = Enum.Material.SmoothPlastic,
		Color = Color3.new(1, 1, 1),
		Transparency = 0.5,
	})
	spray.Parent = propsFolder()
	TweenService:Create(spray, TweenInfo.new(0.4), { Transparency = 1 }):Play()
	task.delay(0.45, function()
		spray:Destroy()
	end)

	DefenseService.AddSmoke(center, def.Radius, def.Duration, cloud)
	task.delay(def.Duration, function()
		smoke.Enabled = false -- las particulas que quedan se desvanecen
	end)
	task.delay(def.Duration + 4, function()
		cloud:Destroy()
	end)
	return true
end

----------------------------------------------------------------------
-- Cartel de piso mojado
----------------------------------------------------------------------

local function buildSign(ground: Vector3, facing: Vector3): Model
	local model = Instance.new("Model")
	model.Name = "WetFloorSign"
	local base = CFrame.lookAt(ground, ground + facing)
	local yellow = Color3.fromRGB(255, 210, 40)
	for _, side in { -1, 1 } do
		local panel = part({
			Name = "Panel",
			Size = Vector3.new(1.6, 2.6, 0.12),
			CFrame = base * CFrame.new(0, 1.25, side * 0.45) * CFrame.Angles(math.rad(side * 12), 0, 0),
			Material = Enum.Material.SmoothPlastic,
			Color = yellow,
			CanCollide = false,
		})
		local gui = Instance.new("SurfaceGui")
		gui.Face = if side < 0 then Enum.NormalId.Front else Enum.NormalId.Back
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 40
		gui.LightInfluence = 1
		gui.Parent = panel
		local text = Instance.new("TextLabel")
		text.Size = UDim2.fromScale(1, 0.6)
		text.Position = UDim2.fromScale(0, 0.2)
		text.BackgroundTransparency = 1
		text.Font = Enum.Font.GothamBlack
		text.TextScaled = true
		text.TextColor3 = Color3.fromRGB(20, 20, 20)
		text.Text = "¡PISO\nMOJADO!"
		text.Parent = gui
		panel.Parent = model
	end
	local puddle = part({
		Name = "Puddle",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.06, W.WetFloorSign.Radius * 2, W.WetFloorSign.Radius * 2),
		CFrame = CFrame.new(ground + Vector3.new(0, 0.04, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Material = Enum.Material.Glass,
		Color = Color3.fromRGB(120, 170, 220),
		Transparency = 0.55,
	})
	puddle.Parent = model
	model.PrimaryPart = puddle
	model.Parent = propsFolder()
	return model
end

local function useWetFloorSign(player: Player): boolean
	local def = W.WetFloorSign
	local root = getRoot(player)
	if not root then
		return false
	end
	local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	look = if look.Magnitude > 0.01 then look.Unit else Vector3.new(0, 0, -1)
	local params = rayParams(player)
	local spot = root.Position + look * 3
	local down = Workspace:Raycast(spot + Vector3.new(0, 1, 0), Vector3.new(0, -12, 0), params)
	if not down then
		notify(player, "Aquí no se puede poner el cartel.")
		return false
	end
	local model = buildSign(down.Position, look)
	DefenseService.AddSlowZone(down.Position, def.Radius, def.SpeedMultiplier, def.Duration)
	task.delay(def.Duration, function()
		model:Destroy()
	end)
	return true
end

----------------------------------------------------------------------
-- Linterna UV
----------------------------------------------------------------------

function WeaponService.SetUV(player: Player, on: boolean)
	player:SetAttribute("UVOn", if on then true else nil)
	if on and not FlashlightService.IsOn(player) then
		FlashlightService.SetOn(player, true)
	end
	FlashlightService.Refresh(player)
end

local function useUV(player: Player): boolean
	local on = player:GetAttribute("UVOn") ~= true
	if on and (player:GetAttribute("Battery") or 0) <= 0 then
		notify(player, "La linterna no tiene batería.", "bad")
		return false
	end
	WeaponService.SetUV(player, on)
	return true
end

-- Revela a los enemigos del cono de la luz UV (lo llama un bucle).
local function updateUV()
	local def = W.UVFlashlight
	for _, player in Players:GetPlayers() do
		if player:GetAttribute("UVOn") == true and FlashlightService.IsOn(player) then
			for _, enemy in DefenseService.GetEnemies() do
				local model = enemy.Model
				if enemy.OnUV and model and model.Parent then
					local pos = model:GetPivot().Position
					if FlashlightService.InCone(player, pos, def.Range) then
						local ok, err = pcall(enemy.OnUV, enemy, player, def.RevealSeconds)
						if not ok then
							warn("[WeaponService] OnUV:", err)
						end
					end
				end
			end
		end
	end
end

----------------------------------------------------------------------
-- Trapeador
----------------------------------------------------------------------

local function useMop(player: Player): boolean
	local def = W.Mop
	if DefenseService.Push(player, def.Range, { StunSeconds = def.StunSeconds, Distance = def.Distance }) == 0 then
		notify(player, "El trapeador no alcanzó a nadie.")
	end
	return true -- gasta el enfriamiento aunque no acierte
end

----------------------------------------------------------------------
-- Uso
----------------------------------------------------------------------

local USES = {
	Taser = useTaser,
	Extinguisher = useExtinguisher,
	WetFloorSign = useWetFloorSign,
	UVFlashlight = useUV,
	Mop = useMop,
}

function WeaponService.Use(player: Player)
	local weaponId = WeaponService.Get(player)
	if not weaponId then
		notify(player, "No llevas ningún arma. Cómprala en la tienda del mall.")
		return
	end
	if not DefenseService.CanAct(player) then
		return
	end
	if (player:GetAttribute("WeaponReadyAt") or 0) > serverNow() then
		return
	end
	local fn = USES[weaponId]
	local ok, used = pcall(fn, player)
	if not ok then
		warn("[WeaponService] Error usando", weaponId, used)
		return
	end
	if used then
		consume(player, weaponId)
	end
end

function WeaponService.Start()
	Remotes.event("UseWeapon").OnServerEvent:Connect(function(player: Player)
		local now = os.clock()
		if lastUse[player] and now - lastUse[player] < 0.2 then
			return
		end
		lastUse[player] = now
		WeaponService.Use(player)
	end)

	-- La UV se apaga si se apaga la linterna (sin bateria, escondido...)
	local function setup(player: Player)
		player:GetAttributeChangedSignal("FlashlightOn"):Connect(function()
			if player:GetAttribute("FlashlightOn") ~= true and player:GetAttribute("UVOn") == true then
				WeaponService.SetUV(player, false)
			end
		end)
	end
	Players.PlayerAdded:Connect(setup)
	for _, player in Players:GetPlayers() do
		setup(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		lastUse[player] = nil
	end)

	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator >= 0.25 then
			accumulator = 0
			updateUV()
		end
	end)
end

return WeaponService
