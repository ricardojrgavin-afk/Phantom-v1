local Developer = {}
Developer.__index = Developer

local DEFAULT_FLAG_PATH = "debug.dev/checkdev.txt"

local function readRawFile(path)
	if not path or path == "" or not isfile or not readfile then
		return nil
	end
	if not isfile(path) then
		return nil
	end

	local ok, contents = pcall(readfile, path)
	if ok then
		return contents
	end

	return nil
end

local function parseBooleanText(value)
	local normalized = string.lower(tostring(value or ""))
	normalized = normalized:gsub("%s+", "")
	return normalized == "true" or normalized == "1" or normalized == "yes" or normalized == "on"
end

function Developer.new(options)
	options = options or {}
	return setmetatable({
		logger = options.logger,
		flagPath = options.flagPath or DEFAULT_FLAG_PATH,
		overrideEnabled = options.overrideEnabled == true,
		externalEnabled = false,
	}, Developer)
end

function Developer:SetLogger(logger)
	self.logger = logger
	return logger
end

function Developer:SetOverride(enabled)
	self.overrideEnabled = enabled == true
	return self.overrideEnabled
end

function Developer:GetFlagPath()
	return self.flagPath
end

function Developer:Refresh()
	self.externalEnabled = parseBooleanText(readRawFile(self.flagPath))
	return self.externalEnabled
end

function Developer:Sync(overrideEnabled)
	if overrideEnabled ~= nil then
		self:SetOverride(overrideEnabled)
	end
	self:Refresh()
	return self:GetState()
end

function Developer:IsExternalEnabled()
	return self.externalEnabled == true
end

function Developer:IsEnabled()
	return self.overrideEnabled == true or self.externalEnabled == true
end

function Developer:GetState()
	local source = "disabled"
	if self:IsExternalEnabled() and self.overrideEnabled then
		source = "file+ui"
	elseif self:IsExternalEnabled() then
		source = "file"
	elseif self.overrideEnabled then
		source = "ui"
	end

	return {
		flagPath = self.flagPath,
		overrideEnabled = self.overrideEnabled == true,
		externalEnabled = self.externalEnabled == true,
		enabled = self:IsEnabled(),
		source = source,
	}
end

return Developer
