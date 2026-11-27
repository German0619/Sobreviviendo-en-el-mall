-- WeaponService: armas del mall (Config.Weapons). Defensas temporales: aturden o
-- apartan a los enemigos, no los matan.
--
-- * Se pueden llevar TODAS (una de cada tipo), cada una en su casilla de la mochila
--   (BackpackService). Usar su herramienta la usa; [R] (UseWeapon) usa el arma ACTIVA:
--   la que tienes en la mano o la ultima que tuviste (SetActive). Se compran con
--   billetes en la tienda del mall (ShopService llama a Equip); comprar una que ya
--   llevas recarga sus usos (el taser no: se vuelve a comprar cuando se le acaban, cada
--   vez mas caro, ver Config.getShopPrice). Se pierden al morir (ShopService llama a
--   Clear), salvo al revivir pagando (Snapshot / Restore).
-- * Taser: aturde al enemigo mas cercano de enfrente (nivel 3: casi nada).
-- * Extintor: nube que ciega (DefenseService.AddSmoke) y tapa el olor del Rastro.
-- * Cartel de piso mojado: trampa que ralentiza (DefenseService.AddSlowZone).
-- * Linterna UV: [R] la enciende/apaga; revela de lejos a los enemigos con OnUV
--   (el Eco) y gasta mas bateria (FlashlightService).
-- * Trapeador: empujon corto (DefenseService.Push con menos fuerza que el Porrazo).
--
-- Atributos del Player:
--   WeaponUses_<id> (nil = no la llevas; -1 = infinitos) y WeaponReadyAt_<id>, por arma;
--   Weapon (arma activa o nil) y WeaponUses / WeaponReadyAt (copia de los de la activa,
--   los usan el HUD, la tienda y la recarga de taser); Weapons ("Taser,Mop": las que
--   llevas, en orden de compra); TaserBuys (compras del taser en la partida); UVOn.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local GameState = require(Shared.GameState)
local HeldModels = require(Shared.HeldModels)

local DefenseService = require(script.Parent.DefenseService)
local FlashlightService = require(script.Parent.FlashlightService)
local SfxService = require(script.Parent.SfxService)

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

-- Armas que lleva cada jugador: [id] = { Uses = n (-1 = infinitos), ReadyAt = t }
type Owned = { Uses: number, ReadyAt: number }
local owned: { [Player]: { [string]: Owned } } = {}
local order: { [Player]: { string } } = {} -- en orden de compra (casillas de la mochila)

local function ownedOf(player: Player): { [string]: Owned }
	local list = owned[player]
	if not list then
		list = {}
		owned[player] = list
		order[player] = {}
	end
	return list
end

-- Arma activa ([R]): la de la mano o la ultima que tuvo.
function WeaponService.Get(player: Player): string?
	local id = player:GetAttribute("Weapon")
	return if type(id) == "string" and W[id] and ownedOf(player)[id] then id else nil
end

function WeaponService.Has(player: Player, weaponId: string): boolean
	return ownedOf(player)[weaponId] ~= nil
end

-- Las que lleva, en orden de compra.
function WeaponService.List(player: Player): { string }
	ownedOf(player)
	return table.clone(order[player])
end

-- Publica los atributos de un arma y, si es la activa, sus copias generales.
local function publish(player: Player, weaponId: string)
	local entry = ownedOf(player)[weaponId]
	player:SetAttribute("WeaponUses_" .. weaponId, if entry then entry.Uses else nil)
	player:SetAttribute("WeaponReadyAt_" .. weaponId, if entry then entry.ReadyAt else nil)
	if player:GetAttribute("Weapon") == weaponId then
		player:SetAttribute("WeaponUses", if entry then entry.Uses else nil)
		player:SetAttribute("WeaponReadyAt", if entry then entry.ReadyAt else nil)
	end
end

local function publishList(player: Player)
	ownedOf(player)
	player:SetAttribute("Weapons", if #order[player] > 0 then table.concat(order[player], ",") else nil)
end

-- Cambia el arma activa (la que usa [R]): al sacar su herramienta (BackpackService).
function WeaponService.SetActive(player: Player, weaponId: string?)
	if weaponId and not ownedOf(player)[weaponId] then
		return
	end
	player:SetAttribute("Weapon", weaponId)
	local entry = weaponId and ownedOf(player)[weaponId]
	player:SetAttribute("WeaponUses", if entry then entry.Uses else nil)
	player:SetAttribute("WeaponReadyAt", if entry then entry.ReadyAt else nil)
end

-- Pase Taser infinito: el taser no gasta usos.
local function hasInfiniteTaser(player: Player): boolean
	return player:GetAttribute("Pass_InfiniteTaser") == true
end

-- Se puede comprar? (no si ya la llevas y no hay nada que recargar)
function WeaponService.CanEquip(player: Player, weaponId: string): (boolean, string?)
	local def = W[weaponId]
	if not def then
		return false, "Arma inválida"
	end
	local entry = ownedOf(player)[weaponId]
	if entry then
		if not def.Uses or entry.Uses < 0 then
			return false, "Ya la llevas"
		end
		if weaponId == "Taser" then
			return false, "Ya llevas un taser: podrás comprar otro cuando se le acaben los usos"
		end
		if entry.Uses >= def.Uses then
			return false, "Ya la tienes cargada"
		end
	end
	return true, nil
end

-- Da un arma (o recarga la que ya lleva) y la deja activa.
-- uses: usos de esta version (el Mercader vende armas con mas usos); por defecto, los de Config.
function WeaponService.Equip(player: Player, weaponId: string, uses: number?)
	local def = W[weaponId]
	if not def then
		return
	end
	local list = ownedOf(player)
	local infinite = not def.Uses or (weaponId == "Taser" and hasInfiniteTaser(player))
	local entry = list[weaponId]
	if entry then
		entry.Uses = if infinite then -1 else math.max(entry.Uses, uses or def.Uses)
	else
		list[weaponId] = { Uses = if infinite then -1 else (uses or def.Uses), ReadyAt = 0 }
		table.insert(order[player], weaponId)
		publishList(player)
	end
	WeaponService.SetActive(player, weaponId)
	publish(player, weaponId)
end

-- Recarga un arma que ya llevas a sus usos completos, sin cambiar la de la mano
-- (mision Revisar extintores). Devuelve true si la recargo.
function WeaponService.Refill(player: Player, weaponId: string): boolean
	local def = W[weaponId]
	local entry = ownedOf(player)[weaponId]
	if not def or not entry or not def.Uses or entry.Uses < 0 or entry.Uses >= def.Uses then
		return false
	end
	entry.Uses = def.Uses
	publish(player, weaponId)
	return true
end

-- Producto Recarga de taser: +uses al taser que llevas. Sin taser (lo perdio entre la
-- compra y la entrega), le da uno con esos usos para no perder la compra.
function WeaponService.AddTaserUses(player: Player, uses: number)
	local entry = ownedOf(player).Taser
	if entry then
		if entry.Uses >= 0 then
			entry.Uses += uses
			publish(player, "Taser")
		end
	else
		WeaponService.Equip(player, "Taser", uses)
	end
	notify(player, string.format("Taser recargado: +%d usos.", uses), "good")
end

-- Quita un arma (sin usos). Si era la activa, pasa a la ultima comprada que quede.
function WeaponService.Remove(player: Player, weaponId: string)
	local list = ownedOf(player)
	if not list[weaponId] then
		return
	end
	if weaponId == "UVFlashlight" then
		WeaponService.SetUV(player, false)
	end
	list[weaponId] = nil
	local index = table.find(order[player], weaponId)
	if index then
		table.remove(order[player], index)
	end
	publish(player, weaponId)
	publishList(player)
	if player:GetAttribute("Weapon") == weaponId then
		WeaponService.SetActive(player, order[player][#order[player]])
	end
end

-- Quita todas (al morir, al salir, al empezar otra partida).
function WeaponService.Clear(player: Player)
	for _, weaponId in WeaponService.List(player) do
		WeaponService.Remove(player, weaponId)
	end
	WeaponService.SetActive(player, nil)
end

-- Copia de las armas que lleva (para devolverlas al revivir pagando).
function WeaponService.Snapshot(player: Player): { { Id: string, Uses: number } }
	local copy = {}
	for _, weaponId in WeaponService.List(player) do
		table.insert(copy, { Id = weaponId, Uses = ownedOf(player)[weaponId].Uses })
	end
	return copy
end

function WeaponService.Restore(player: Player, snapshot: { { Id: string, Uses: number } })
	for _, entry in snapshot do
		WeaponService.Equip(player, entry.Id, if entry.Uses >= 0 then entry.Uses else nil)
	end
end

-- Gasta un uso (si tiene limite). Sin usos: se pierde el arma.
local function consume(player: Player, weaponId: string)
	local def = W[weaponId]
	local entry = ownedOf(player)[weaponId]
	if not entry then
		return
	end
	entry.ReadyAt = serverNow() + (def.Cooldown or 0)
	-- Uses < 0: sin limite (armas sin usos o pase Taser infinito)
	if def.Uses and entry.Uses >= 0 then
		entry.Uses -= 1
		if entry.Uses <= 0 then
			WeaponService.Remove(player, weaponId)
			local more = if weaponId == "Taser" then " Puedes comprar otro en la tienda." else ""
			notify(player, string.format("%s se quedó sin usos.%s", displayName(weaponId), more), "bad")
			return
		end
	end
	publish(player, weaponId)
end

----------------------------------------------------------------------
-- Taser
----------------------------------------------------------------------

-- color: el de la skin del taser (Config.Skins[...].Effect) o el azul electrico normal.
local function taserBolt(from: Vector3, to: Vector3, color: Color3?)
	local boltColor = color or Color3.fromRGB(120, 200, 255)
	local length = (to - from).Magnitude
	local bolt = part({
		Name = "TaserBolt",
		Size = Vector3.new(0.15, 0.15, length),
		CFrame = CFrame.lookAt((from + to) / 2, to),
		Material = Enum.Material.Neon,
		Color = boltColor,
	})
	local light = Instance.new("PointLight")
	light.Color = boltColor
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
	taserBolt(origin, model:GetPivot().Position, Config.getSkinEffect(player, "Taser"))
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
	-- Skin del extintor: la nube y el chorro se tinen de su color (siguen siendo humo claro)
	local skinColor = Config.getSkinEffect(player, "Extinguisher")
	local smokeColor = Color3.fromRGB(235, 238, 245)
	local sprayColor = Color3.new(1, 1, 1)
	if skinColor then
		smokeColor = smokeColor:Lerp(skinColor, Config.SkinEffects.SmokeTint)
		sprayColor = sprayColor:Lerp(skinColor, Config.SkinEffects.SmokeTint)
	end

	local cloud = part({
		Name = "ExtinguisherCloud",
		Size = Vector3.new(1, 1, 1),
		CFrame = CFrame.new(center),
		Transparency = 1,
	})
	local smoke = Instance.new("ParticleEmitter")
	smoke.Color = ColorSequence.new(smokeColor)
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
		Color = sprayColor,
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

-- skinId: skin del cartel del jugador (los paneles toman su color y material; el charco
-- se tine de su color de efecto).
local function buildSign(ground: Vector3, facing: Vector3, skinId: string?): Model
	local model = Instance.new("Model")
	model.Name = "WetFloorSign"
	local base = CFrame.lookAt(ground, ground + facing)
	local skin = if skinId then Config.Skins[skinId] else nil
	local panelColor = if skin then skin.Body.Color else Color3.fromRGB(255, 210, 40)
	local panelMaterial = if skin then skin.Body.Material else Enum.Material.SmoothPlastic
	local puddleColor = Color3.fromRGB(120, 170, 220)
	if skin and skin.Effect then
		puddleColor = puddleColor:Lerp(skin.Effect, Config.SkinEffects.PuddleTint)
	end
	-- Texto legible sobre paneles oscuros (Neón, Luna...)
	local _, _, brightness = panelColor:ToHSV()
	local textColor = if brightness < 0.45 then Color3.fromRGB(240, 240, 240) else Color3.fromRGB(20, 20, 20)
	for _, side in { -1, 1 } do
		local panel = part({
			Name = "Panel",
			Size = Vector3.new(1.6, 2.6, 0.12),
			-- Caballete en A: los dos paneles se juntan arriba y se abren abajo
			CFrame = base * CFrame.new(0, 1.25, side * 0.3) * CFrame.Angles(math.rad(-side * 12), 0, 0),
			Material = panelMaterial,
			Color = panelColor,
			CanCollide = false,
		})
		if skin and skin.Texture then
			HeldModels.applyTexture(panel, { Id = skin.Texture.Id, Tile = (skin.Texture.Tile or 1.2) * 1.6 })
		end
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
		text.TextColor3 = textColor
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
		Color = puddleColor,
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
	local skinId = player:GetAttribute("Skin_WetFloorSign")
	local model = buildSign(down.Position, look, if type(skinId) == "string" then skinId else nil)
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
	-- (la onda del empujon toma el color de la skin del trapeador)
	local strength = { StunSeconds = def.StunSeconds, Distance = def.Distance }
	if DefenseService.Push(player, def.Range, strength, Config.getSkinEffect(player, "Mop")) == 0 then
		notify(player, "El trapeador no alcanzó a nadie.")
	end
	return true -- gasta el enfriamiento aunque no acierte
end

----------------------------------------------------------------------
-- Armas con dano (Fase 16): machete y pistola
----------------------------------------------------------------------

-- (EnemyService se carga al usarlas: cargarlo arriba haria un ciclo de requires,
-- EnemyService -> MissionService -> Missions/CheckExtinguishers -> WeaponService)
local function enemyService()
	return require(script.Parent.EnemyService) :: any
end

-- Machete: tajo al enemigo mas cercano de enfrente. Se desgasta con cada tajo.
local function useMachete(player: Player): boolean
	local def = W.Machete
	local root = getRoot(player)
	if not root then
		return false
	end
	local origin = root.Position + Vector3.new(0, 1, 0)
	local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	look = if look.Magnitude > 0.01 then look.Unit else Vector3.new(0, 0, -1)
	local cosHalf = math.cos(math.rad(def.HalfAngle))
	local params = rayParams(player)
	local enemies = enemyService()
	local best, bestDist = nil, math.huge
	for _, enemy in DefenseService.GetEnemies() do
		if enemies.CanBeDamaged(enemy) then
			local pos = enemy.Model:GetPivot().Position
			local offset = pos - origin
			local flat = Vector3.new(offset.X, 0, offset.Z)
			local dist = flat.Magnitude
			if dist <= def.Range and dist < bestDist and math.abs(offset.Y) < 8 and (dist < 2 or look:Dot(flat.Unit) >= cosHalf) then
				local hit = Workspace:Raycast(origin, offset, params)
				if not hit or (hit.Position - origin).Magnitude >= offset.Magnitude - 2 then
					best, bestDist = enemy, dist
				end
			end
		end
	end
	-- Estela del tajo delante del jugador
	local slash = part({
		Name = "MacheteSlash",
		Size = Vector3.new(4, 0.1, 1.6),
		CFrame = CFrame.lookAt(origin + look * 2.5, origin + look * 5) * CFrame.Angles(0, 0, math.rad(-25)),
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(230, 230, 240),
		Transparency = 0.4,
	})
	slash.Parent = propsFolder()
	TweenService:Create(slash, TweenInfo.new(0.18), { Transparency = 1, Size = Vector3.new(5, 0.05, 2) }):Play()
	task.delay(0.2, function()
		slash:Destroy()
	end)
	if best then
		local _, killed = enemies.Damage(best, "Machete", player)
		if not killed and best.Model and best.Model.Parent then
			DefenseService.Stun(best.Model, def.HitStunSeconds)
		end
	end
	return true -- se desgasta con cada tajo (acierte o no)
end

-- Distancia de un punto a un rayo (y cuanto avanza el rayo hasta el).
local function rayDistance(origin: Vector3, dir: Vector3, point: Vector3): (number, number)
	local t = (point - origin):Dot(dir)
	local closest = origin + dir * math.max(t, 0)
	return (point - closest).Magnitude, t
end

-- Pistola: disparo hacia la mirilla (aim = direccion de la camara del cliente).
local function usePistol(player: Player, aim: Vector3?): boolean
	local def = W.Pistol
	local character = player.Character
	local root = getRoot(player)
	local head = character and character:FindFirstChild("Head") :: BasePart?
	if not root then
		return false
	end
	local origin = if head then head.Position else root.Position + Vector3.new(0, 1.5, 0)
	-- Direccion: la de la mirilla si es valida (no mas de MaxAimAngle respecto a donde
	-- mira el personaje), si no hacia delante
	local forward = root.CFrame.LookVector
	local dir = forward
	if typeof(aim) == "Vector3" and aim.Magnitude > 0.5 then
		local unit = aim.Unit
		local flatAim = Vector3.new(unit.X, 0, unit.Z)
		local flatFwd = Vector3.new(forward.X, 0, forward.Z)
		if flatAim.Magnitude < 0.05 or flatFwd.Magnitude < 0.05 or flatAim.Unit:Dot(flatFwd.Unit) >= math.cos(math.rad(def.MaxAimAngle)) then
			dir = unit
		end
	end

	-- Hasta donde llega la bala (pared)
	local params = rayParams(player)
	local wall = Workspace:Raycast(origin, dir * def.Range, params)
	local maxT = if wall then (wall.Position - origin).Magnitude else def.Range

	-- Enemigo alcanzado: el mas cercano a lo largo del disparo cuyo cuerpo pase cerca
	local enemies = enemyService()
	local best, bestT = nil, math.huge
	for _, enemy in DefenseService.GetEnemies() do
		if enemies.CanBeDamaged(enemy) then
			local model = enemy.Model :: Model
			local pivot = model:GetPivot().Position
			local height = enemy.Height or 6
			for _, dy in { -height * 0.3, 0, height * 0.3 } do
				local point = pivot + Vector3.new(0, dy, 0)
				local d, t = rayDistance(origin, dir, point)
				local radius = def.HitRadius + def.HitRadiusPerStud * t
				if t > 0 and t <= maxT + 1 and d <= radius and t < bestT then
					best, bestT = enemy, t
				end
			end
		end
	end

	-- Trazo de la bala y fogonazo
	local endPoint = origin + dir * (if best then bestT else maxT)
	local muzzle = origin + dir * 1.5
	local tracer = part({
		Name = "Tracer",
		Size = Vector3.new(0.08, 0.08, math.max((endPoint - muzzle).Magnitude, 0.1)),
		CFrame = CFrame.lookAt((muzzle + endPoint) / 2, endPoint),
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(255, 225, 140),
		Transparency = 0.2,
	})
	local flash = Instance.new("PointLight")
	flash.Color = Color3.fromRGB(255, 200, 120)
	flash.Range = 16
	flash.Brightness = 4
	flash.Parent = tracer
	tracer.Parent = propsFolder()
	TweenService:Create(tracer, TweenInfo.new(0.12), { Transparency = 1 }):Play()
	task.delay(0.15, function()
		tracer:Destroy()
	end)

	if best then
		local _, killed = enemies.Damage(best, "Pistol", player)
		if not killed and best.Model and best.Model.Parent then
			DefenseService.Stun(best.Model, def.HitStunSeconds)
		end
	end
	return true -- gasta la bala acierte o no
end

-- Pase Pistola: 12 balas al empezar cada noche (recarga la que lleve o le da una).
function WeaponService.GivePassPistol(player: Player)
	if player:GetAttribute("Pass_Pistol") ~= true then
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	local entry = ownedOf(player).Pistol
	if entry then
		entry.Uses = W.Pistol.Uses
		publish(player, "Pistol")
	else
		local previous = WeaponService.Get(player)
		WeaponService.Equip(player, "Pistol")
		-- (no le cambia el arma activa que ya tenia)
		if previous then
			WeaponService.SetActive(player, previous)
		end
	end
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
	Machete = useMachete,
	Pistol = usePistol,
}

-- Sonido de cada arma al usarla (Config.Sounds.Sfx), en 3D desde quien la usa
local USE_SOUNDS = {
	Taser = "Taser",
	Extinguisher = "Extinguisher",
	WetFloorSign = "WetFloorSign",
	UVFlashlight = "UV",
	Mop = "Mop",
	Machete = "Machete",
	Pistol = "Pistol",
}

-- weaponId: la de la herramienta que se uso; nil = la activa ([R]).
-- aim: direccion de la mirilla (camara del cliente), solo para la pistola.
function WeaponService.Use(player: Player, weaponId: string?, aim: Vector3?)
	weaponId = weaponId or WeaponService.Get(player)
	local entry = weaponId and ownedOf(player)[weaponId]
	if not weaponId or not entry then
		notify(player, "No llevas ningún arma. Cómprala en la tienda del mall.")
		return
	end
	if player:GetAttribute("Weapon") ~= weaponId then
		WeaponService.SetActive(player, weaponId)
	end
	if not DefenseService.CanAct(player) then
		return
	end
	if entry.ReadyAt > serverNow() then
		return
	end
	local fn = USES[weaponId]
	local ok, used = pcall(fn, player, aim)
	if not ok then
		warn("[WeaponService] Error usando", weaponId, used)
		return
	end
	-- (la UV suena tambien al apagarla)
	local root = getRoot(player)
	if root and USE_SOUNDS[weaponId] and (used or weaponId == "UVFlashlight") then
		SfxService.PlayAt(USE_SOUNDS[weaponId], root)
	end
	if used then
		-- Animacion del arma (client/WeaponAnims: primera persona y el brazo para los demas).
		-- La UV solo se enciende y apaga: no se anima.
		if weaponId ~= "UVFlashlight" then
			player:SetAttribute("WeaponAnim", string.format("%s|%.3f", weaponId, serverNow()))
		end
		consume(player, weaponId)
	end
end

function WeaponService.Start()
	-- (weaponId, aim): el cliente manda el arma de la herramienta (o nil = la activa) y la
	-- direccion de su camara (la usa la pistola para apuntar con la mirilla)
	Remotes.event("UseWeapon").OnServerEvent:Connect(function(player: Player, weaponId: any, aim: any)
		local now = os.clock()
		if lastUse[player] and now - lastUse[player] < 0.2 then
			return
		end
		lastUse[player] = now
		local id = if type(weaponId) == "string" and W[weaponId] then weaponId else nil
		WeaponService.Use(player, id, if typeof(aim) == "Vector3" then aim else nil)
	end)

	-- Pase Pistola: balas al empezar cada noche (y si lo compra a mitad de noche)
	GameState.Folder:GetAttributeChangedSignal("Phase"):Connect(function()
		if GameState.Folder:GetAttribute("Phase") == "Night" then
			for _, player in Players:GetPlayers() do
				WeaponService.GivePassPistol(player)
			end
		end
	end)

	-- La UV se apaga si se apaga la linterna (sin bateria, escondido...)
	local function setup(player: Player)
		player:GetAttributeChangedSignal("FlashlightOn"):Connect(function()
			if player:GetAttribute("FlashlightOn") ~= true and player:GetAttribute("UVOn") == true then
				WeaponService.SetUV(player, false)
			end
		end)
		player:GetAttributeChangedSignal("Pass_Pistol"):Connect(function()
			if GameState.Folder:GetAttribute("Phase") == "Night" then
				WeaponService.GivePassPistol(player)
			end
		end)
		-- Pase Taser infinito comprado durante la partida: el taser que lleva pasa a infinito
		player:GetAttributeChangedSignal("Pass_InfiniteTaser"):Connect(function()
			local entry = ownedOf(player).Taser
			if hasInfiniteTaser(player) and entry then
				entry.Uses = -1
				publish(player, "Taser")
			end
		end)
	end
	Players.PlayerAdded:Connect(setup)
	for _, player in Players:GetPlayers() do
		setup(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		lastUse[player] = nil
		owned[player] = nil
		order[player] = nil
	end)

	-- Partida nueva: el taser vuelve a su precio normal
	local RunState = require(script.Parent.RunState) :: any
	RunState.Reset:Connect(function(player: Player)
		player:SetAttribute("TaserBuys", nil)
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
