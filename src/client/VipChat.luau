-- VipChat (lobby y mall): etiqueta [VIP] dorada delante del nombre en el chat
-- para los jugadores con el pase VIP (atributo Pass_VIP, lo pone PassService).

local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")

local VipChat = {}

local TAG = '<font color="#FFC83C"><b>[VIP]</b></font> '

function VipChat.Start()
	TextChatService.OnIncomingMessage = function(message: TextChatMessage)
		local properties = Instance.new("TextChatMessageProperties")
		local source = message.TextSource
		local sender = source and Players:GetPlayerByUserId(source.UserId)
		if sender and sender:GetAttribute("Pass_VIP") == true then
			properties.PrefixText = TAG .. message.PrefixText
		end
		return properties
	end
end

return VipChat
