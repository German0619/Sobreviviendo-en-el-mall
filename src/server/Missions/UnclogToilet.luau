-- Mision: Desatascar bano.
-- Un inodoro se desborda y deja un charco (es un derrame: lo huele el Rastro).
-- Si no se arregla, el charco se queda hasta la siguiente noche.

local Config = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Config)
local Common = require(script.Parent.Common)
local Hold = require(script.Parent.Hold)

local leftovers = {}

return Hold.new({
	Type = "UnclogToilet",
	ActionText = "Desatascar",
	ObjectText = "Inodoro",
	OnBegin = function(mission)
		local spot = mission.Spot
		-- Delante del inodoro (su cara Front)
		local floor = Common.floorPosition(spot) + spot.CFrame.LookVector * 2.5
		return Common.makePuddle(floor, Config.MissionDetails.UnclogToilet.PuddleSize, Color3.fromRGB(150, 180, 190))
	end,
	OnEnd = function(_mission, success, puddle)
		if success then
			puddle:Destroy()
		else
			table.insert(leftovers, puddle)
		end
	end,
	ResetNight = function()
		for _, puddle in leftovers do
			puddle:Destroy()
		end
		leftovers = {}
	end,
})
