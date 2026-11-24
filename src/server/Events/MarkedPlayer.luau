-- Jugador marcado: un jugador al azar atrae a los enemigos (un senuelo que le sigue).
-- Se anula quedandose junto a un companero unos segundos. Jugando solo, dura lo que dure.

local Players = game:GetService("Players")
local Remotes = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Remotes)
local DefenseService = require(script.Parent.Parent.DefenseService)

local MARK_COLOR = Color3.fromRGB(255, 210, 40)

local function alivePlayers(): { Player }
	local list = {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if player:GetAttribute("Alive") == true and humanoid and humanoid.Health > 0 then
			table.insert(list, player)
		end
	end
	return list
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

return {
	CanStart = function(_ctx)
		return #alivePlayers() > 0
	end,
	Start = function(ctx)
		local def = ctx.Def
		local list = alivePlayers()
		local target = list[math.random(1, #list)]
		local highlight = Instance.new("Highlight")
		highlight.Name = "EventMark"
		highlight.FillTransparency = 1
		highlight.OutlineColor = MARK_COLOR
		highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		highlight.Parent = target.Character

		Remotes.event("Notify"):FireClient(target, "¡Estás marcado! Los enemigos van a por ti. Ponte junto a un compañero.", "bad")
		for _, other in list do
			if other ~= target then
				Remotes.event("Notify"):FireClient(other, target.DisplayName .. " está marcado: acércate a él para anularlo.", "bad")
			end
		end

		task.spawn(function()
			local together = 0
			while not ctx.Ended do
				local root = rootOf(target)
				if target:GetAttribute("Alive") ~= true or not root then
					ctx.Finish()
					return
				end
				DefenseService.AddLure(root.Position, 0.8, def.LureRadius)
				-- Junto a un companero: se anula
				local near = false
				for _, other in alivePlayers() do
					local r = other ~= target and rootOf(other)
					if r and (r.Position - root.Position).Magnitude <= def.ClearDistance then
						near = true
						break
					end
				end
				together = if near then together + 0.5 else 0
				if together >= def.ClearSeconds then
					Remotes.event("Notify"):FireAllClients("La marca se anuló: ya nadie atrae a los enemigos.", "good")
					ctx.Finish()
					return
				end
				task.wait(0.5)
			end
		end)

		return function()
			highlight:Destroy()
		end
	end,
}
