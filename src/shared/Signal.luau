-- Signal minimo en Lua puro (para eventos entre modulos del mismo lado).

local Signal = {}
Signal.__index = Signal

export type Connection = {
	Disconnect: () -> (),
}

function Signal.new()
	return setmetatable({ _handlers = {} }, Signal)
end

function Signal:Connect(fn: (...any) -> ()): Connection
	local handlers = self._handlers
	local key = {}
	handlers[key] = fn
	return {
		Disconnect = function()
			handlers[key] = nil
		end,
	}
end

function Signal:Fire(...: any)
	-- Copiamos para que conectar/desconectar durante el Fire sea seguro.
	local snapshot = {}
	for _, fn in self._handlers do
		table.insert(snapshot, fn)
	end
	for _, fn in snapshot do
		task.spawn(fn, ...)
	end
end

function Signal:Wait(): ...any
	local thread = coroutine.running()
	local conn
	conn = self:Connect(function(...)
		conn.Disconnect()
		task.spawn(thread, ...)
	end)
	return coroutine.yield()
end

return Signal
