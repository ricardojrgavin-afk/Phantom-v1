local Manager = {}
Manager.__index = Manager

local function cleanupValue(value)
	if value == nil then
		return
	end

	local valueType = typeof(value)
	if valueType == "RBXScriptConnection" then
		if value.Connected then
			value:Disconnect()
		end
		return
	end

	if valueType == "Instance" then
		value:Destroy()
		return
	end

	if valueType == "function" then
		value()
		return
	end

	if valueType == "table" then
		if type(value.Cleanup) == "function" then
			value:Cleanup()
			return
		end

		if type(value.Destroy) == "function" then
			value:Destroy()
			return
		end

		if type(value.Disconnect) == "function" then
			value:Disconnect()
			return
		end
	end
end

function Manager.new(label)
	return setmetatable({
		label = label or "manager",
		_items = {},
	}, Manager)
end

function Manager:Add(value)
	self._items[#self._items + 1] = value
	return value
end

function Manager:AddInstance(instance)
	return self:Add(instance)
end

function Manager:AddConnection(connection)
	return self:Add(connection)
end

function Manager:AddTask(callback)
	return self:Add(callback)
end

function Manager:CreateScope(label)
	local scope = Manager.new(label)
	self:AddTask(function()
		scope:Cleanup()
	end)
	return scope
end

function Manager:Cleanup()
	for index = #self._items, 1, -1 do
		cleanupValue(self._items[index])
		self._items[index] = nil
	end
end

return Manager
