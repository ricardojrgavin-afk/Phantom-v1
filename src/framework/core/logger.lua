local Logger = {}
Logger.__index = Logger

local function join(...)
	local parts = {}
	for index = 1, select("#", ...) do
		parts[#parts + 1] = tostring(select(index, ...))
	end
	return table.concat(parts, " ")
end

local function emit(kind, prefix, ...)
	local message = prefix .. " " .. kind .. " " .. join(...)
	if kind == "[WARN]" or kind == "[ERROR]" then
		warn(message)
	end
end

function Logger.new(prefix, debugEnabled)
	return setmetatable({
		prefix = prefix or "[phantom]",
		debugEnabled = debugEnabled == true,
	}, Logger)
end

function Logger:SetDebug(enabled)
	self.debugEnabled = enabled == true
end

function Logger:Info(...)
	emit("[INFO]", self.prefix, ...)
end

function Logger:Debug(...)
	if not self.debugEnabled then
		return
	end
	emit("[DEBUG]", self.prefix, ...)
end

function Logger:Warn(...)
	emit("[WARN]", self.prefix, ...)
end

function Logger:Error(...)
	emit("[ERROR]", self.prefix, ...)
end

return Logger
