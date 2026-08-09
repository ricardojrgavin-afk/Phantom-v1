local HttpService = game:GetService("HttpService")

local Config = {}
Config.__index = Config

local function deepCopy(value)
	if type(value) ~= "table" then
		return value
	end

	local clone = {}
	for key, child in pairs(value) do
		clone[key] = deepCopy(child)
	end
	return clone
end

local function merge(defaults, overrides)
	if type(defaults) ~= "table" then
		return overrides == nil and defaults or overrides
	end

	local result = deepCopy(defaults)
	if type(overrides) ~= "table" then
		return result
	end

	for key, value in pairs(overrides) do
		if type(value) == "table" and type(result[key]) == "table" then
			result[key] = merge(result[key], value)
		else
			result[key] = deepCopy(value)
		end
	end

	return result
end

function Config.new(fileApi, logger)
	return setmetatable({
		file = fileApi,
		logger = logger,
		stores = {},
		saveTokens = {},
		profileTokens = {},
	}, Config)
end

function Config:Load(name, defaults)
	local loaded = self.file:ReadJson("config/" .. name .. ".json", {})
	local store = merge(defaults or {}, loaded)
	self.stores[name] = store
	return store
end

function Config:Get(name)
	return self.stores[name]
end

function Config:Save(name, data)
	local store = data or self.stores[name] or {}
	local ok, err = self.file:WriteJson("config/" .. name .. ".json", store, { force = true })
	if not ok and self.logger then
		self.logger:Warn("failed to save config", name, err)
	end
	return ok, err
end

function Config:ScheduleSave(name, data, delaySeconds)
	self.saveTokens[name] = (self.saveTokens[name] or 0) + 1
	local token = self.saveTokens[name]

	task.delay(delaySeconds or 0.2, function()
		if self.saveTokens[name] ~= token then
			return
		end
		self:Save(name, data)
	end)
end

function Config:LoadProfile(placeId, slot, defaults)
	local profile = self.file:ReadJson(string.format("configs/%s/%s.json", tostring(placeId), slot or "default"), {})
	return merge(defaults or {}, profile)
end

function Config:SaveProfile(placeId, slot, data)
	local ok, err = self.file:WriteJson(string.format("configs/%s/%s.json", tostring(placeId), slot or "default"), data or {}, { force = true })
	if not ok and self.logger then
		self.logger:Warn("failed to save profile", placeId, slot, err)
	end
	return ok, err
end

function Config:ScheduleProfileSave(placeId, slot, data, delaySeconds)
	local key = tostring(placeId) .. ":" .. tostring(slot or "default")
	self.profileTokens[key] = (self.profileTokens[key] or 0) + 1
	local token = self.profileTokens[key]

	task.delay(delaySeconds or 0.3, function()
		if self.profileTokens[key] ~= token then
			return
		end
		self:SaveProfile(placeId, slot, data)
	end)
end

function Config:ExportProfile(placeId, slot)
	local path = string.format("configs/%s/%s.json", tostring(placeId), slot or "default")
	local contents = self.file:Read(path, nil)
	if not contents then
		return nil, "profile not found"
	end
	return contents
end

function Config:ImportProfile(placeId, slot, jsonString, options)
	options = options or {}
	local path = string.format("configs/%s/%s.json", tostring(placeId), slot or "default")

	local ok, parsed = pcall(function()
		return HttpService:JSONDecode(jsonString or "")
	end)
	if not ok then
		return false, "invalid json"
	end

	if not options.force and self.file:IsFile(path) then
		if type(self.prompt) == "function" then
			self.prompt({
				title = "Import Profile",
				message = string.format("A profile already exists for %s/%s. Overwrite?", tostring(placeId), tostring(slot or "default")),
				onConfirm = function()
					self.file:WriteJson(path, parsed, { force = true })
				end,
				onCancel = function() end,
			})
			return "pending"
		end
		return false, "exists"
	end

	local ok2, err = self.file:WriteJson(path, parsed, { force = true })
	if not ok2 then
		return false, err
	end
	return true
end

function Config:SetPromptFunction(fn)
	self.prompt = fn
end

function Config:ListProfiles(base)
	local prefix = string.format("configs/%s", tostring(base))
	local items = self.file:ListFiles(prefix)
	local result = {}
	for _, path in ipairs(items) do
		local name = path:match("([^/]+)%.json$")
		if name and not name:match("^Players") and not path:match("temp_ref_") then
			result[#result + 1] = name
		end
	end
	return result
end

return Config
