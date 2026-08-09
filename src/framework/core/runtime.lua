local RunService = game:GetService("RunService")

local Runtime = {}
Runtime.__index = Runtime

local function resolveSignal(primary, secondary, fallback)
	return RunService[primary] or RunService[secondary] or RunService[fallback]
end

function Runtime.new(logger)
	local self = setmetatable({
		logger = logger,
		_exitHooks = {},
		_loops = {
			Heartbeat = {
				handlers = {},
				signal = resolveSignal("Heartbeat", "Heartbeat", "Heartbeat"),
				connection = nil,
			},
			RenderStepped = {
				handlers = {},
				signal = resolveSignal("RenderStepped", "PreRender", "Heartbeat"),
				connection = nil,
			},
			Stepped = {
				handlers = {},
				signal = resolveSignal("PreSimulation", "Stepped", "Heartbeat"),
				connection = nil,
			},
		},
	}, Runtime)

	self.runtime = {
		run = function(code)
			return self:Run(code)
		end,
		RunLoops = {
			BindToHeartbeat = function(_, id, callback, interval)
				self:Bind("Heartbeat", id, callback, interval)
			end,
			UnbindFromHeartbeat = function(_, id)
				self:Unbind("Heartbeat", id)
			end,
			BindToRenderStepped = function(_, id, callback, interval)
				self:Bind("RenderStepped", id, callback, interval)
			end,
			UnbindFromRenderStepped = function(_, id)
				self:Unbind("RenderStepped", id)
			end,
			BindToStepped = function(_, id, callback, interval)
				self:Bind("Stepped", id, callback, interval)
			end,
			UnbindFromStepped = function(_, id)
				self:Unbind("Stepped", id)
			end,
		},
	}

	return self
end

function Runtime:_dispatch(loopName, ...)
	local loop = self._loops[loopName]
	local now = tick()
	for id, handlerData in pairs(loop.handlers) do
		if handlerData.interval <= 0 or now - handlerData.lastRun >= handlerData.interval then
			handlerData.lastRun = now
			local ok, err = pcall(handlerData.callback, ...)
			if not ok and self.logger then
				self.logger:Warn("loop failure", loopName, id, err)
			end
		end
	end
end

function Runtime:_ensureConnection(loopName)
	local loop = self._loops[loopName]
	if loop.connection or not loop.signal then
		return
	end

	loop.connection = loop.signal:Connect(function(...)
		self:_dispatch(loopName, ...)
	end)
end

function Runtime:Bind(loopName, id, callback, interval)
	local loop = self._loops[loopName]
	if not loop or type(callback) ~= "function" then
		return
	end

	loop.handlers[id] = {
		callback = callback,
		interval = tonumber(interval) or 0,
		lastRun = 0,
	}

	self:_ensureConnection(loopName)
end

function Runtime:Unbind(loopName, id)
	local loop = self._loops[loopName]
	if not loop then
		return
	end

	loop.handlers[id] = nil
	if not next(loop.handlers) and loop.connection then
		loop.connection:Disconnect()
		loop.connection = nil
	end
end

function Runtime:ClearLoops()
	for _, loop in pairs(self._loops) do
		for id in pairs(loop.handlers) do
			loop.handlers[id] = nil
		end
		if loop.connection then
			loop.connection:Disconnect()
			loop.connection = nil
		end
	end
end

function Runtime:OnExit(id, callback)
	if type(callback) == "function" then
		self._exitHooks[id] = callback
	end
end

function Runtime:OffExit(id)
	self._exitHooks[id] = nil
end

function Runtime:RunExitHooks()
	local hooks = self._exitHooks
	self._exitHooks = {}

	for id, callback in pairs(hooks) do
		local ok, err = pcall(callback)
		if not ok and self.logger then
			self.logger:Warn("exit hook failure", id, err)
		end
	end
end

function Runtime:Run(code)
	if type(code) == "function" then
		return code()
	end

	if type(code) ~= "string" or code == "" then
		return nil, "runtime expects string or function"
	end

	local compiled, err = loadstring(code)
	if not compiled then
		if self.logger then
			self.logger:Warn("compile failure", err)
		end
		return nil, err
	end

	local ok, result = pcall(compiled)
	if not ok then
		if self.logger then
			self.logger:Warn("runtime execution failure", result)
		end
		return nil, result
	end

	return result
end

function Runtime:Cleanup()
	self:ClearLoops()
	self:RunExitHooks()
end

return Runtime
