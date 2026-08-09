local Module = {}
Module.__index = Module

function Module.new(fileApi, logger)
	return setmetatable({
		file = fileApi,
		logger = logger,
		registry = {},
		developerMode = false,
	}, Module)
end

function Module:SetDeveloperMode(enabled)
	self.developerMode = enabled == true
end

function Module:Register(name, spec)
	self.registry[name] = spec
	return spec
end

function Module:RegisterPath(name, path, options)
	options = options or {}
	options.path = path
	if options.cache == nil then
		options.cache = true
	end
	self.registry[name] = options
	return options
end

function Module:_compile(path)
	local source = self.file:Read(path)
	if not source then
		return nil, "missing file"
	end

	return loadstring(source, "@" .. self.file:Resolve(path))
end

function Module:Load(name, ...)
	local spec = self.registry[name]
	if not spec then
		if self.file:Exists(name) then
			spec = self:RegisterPath("__path__:" .. name, name, { cache = true })
			name = "__path__:" .. name
		else
			return nil, "unknown module: " .. tostring(name)
		end
	end

	local useCache = spec.cache ~= false and not (self.developerMode and spec.hotReload)
	if useCache and spec.loaded then
		return spec.value
	end

	spec.loading = true
	local ok, result

	if type(spec.loader) == "function" then
		ok, result = pcall(spec.loader, ...)
	elseif spec.path then
		local compiled, err = self:_compile(spec.path)
		if not compiled then
			spec.loading = false
			if self.logger then
				self.logger:Warn("failed to compile module", name, err)
			end
			return nil, err
		end
		ok, result = pcall(compiled, ...)
	else
		spec.loading = false
		return nil, "invalid module spec"
	end

	spec.loading = false
	if not ok then
		if self.logger then
			self.logger:Warn("failed to load module", name, result)
		end
		return nil, result
	end

	spec.loaded = true
	spec.value = result
	self.registry[name] = spec

	return result
end

function Module:LoadPath(path, ...)
	local key = "__path__:" .. tostring(path)
	if not self.registry[key] then
		self:RegisterPath(key, path, { cache = true })
	end
	return self:Load(key, ...)
end

function Module:Get(name)
	local spec = self.registry[name]
	return spec and spec.value or nil
end

function Module:Reload(name, ...)
	local spec = self.registry[name]
	if spec then
		spec.loaded = false
		spec.value = nil
		self.registry[name] = spec
	end
	return self:Load(name, ...)
end

return Module
