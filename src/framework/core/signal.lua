local Signal = {}
Signal.__index = Signal

function Signal.new()
	return setmetatable({
		_nextId = 0,
		_handlers = {},
	}, Signal)
end

function Signal:Connect(handler)
	assert(type(handler) == "function", "Signal:Connect expects a function")

	self._nextId = self._nextId + 1
	local id = self._nextId
	self._handlers[id] = handler

	local signal = self
	local connection = { Connected = true }

	function connection:Disconnect()
		if not self.Connected then
			return
		end

		self.Connected = false
		signal._handlers[id] = nil
	end

	connection.Destroy = connection.Disconnect

	return connection
end

function Signal:Once(handler)
	local connection
	connection = self:Connect(function(...)
		if connection then
			connection:Disconnect()
		end
		handler(...)
	end)

	return connection
end

function Signal:Fire(...)
	for _, handler in pairs(self._handlers) do
		local ok, err = pcall(handler, ...)
		if not ok then
			warn("[phantom] [signal]", err)
		end
	end
end

function Signal:Destroy()
	for id in pairs(self._handlers) do
		self._handlers[id] = nil
	end
end

return Signal
