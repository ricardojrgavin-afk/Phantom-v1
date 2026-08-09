local Framework = {}
Framework.__index = Framework

local DEFAULT_ROOT = "Phantom"
local FRAMEWORK_ROOT = "src/framework"
local function normalizePath(path)
	path = tostring(path or "")
	path = path:gsub("\\", "/")
	path = path:gsub("^%./", "")
	path = path:gsub("^/+", "")
	path = path:gsub("/+", "/")
	path = path:gsub("/$", "")
	return path
end

local function ensureLuaPath(path)
	local normalized = normalizePath(path)
	if normalized == "" then
		return "init.lua"
	end
	if normalized:match("%.lua$") then
		return normalized
	end
	return normalized .. ".lua"
end

function Framework.new(rootName, logger)
	return setmetatable({
		rootName = rootName or DEFAULT_ROOT,
		logger = logger,
		cache = {},
	}, Framework)
end

function Framework:SetLogger(logger)
	self.logger = logger
	return logger
end

function Framework:GetFrameworkRoot()
	return FRAMEWORK_ROOT
end

function Framework:Resolve(path)
	local relative = ensureLuaPath(path)
	return string.format("%s/%s/%s", self.rootName, FRAMEWORK_ROOT, relative)
end

function Framework:Load(path, ...)
	local relative = ensureLuaPath(path)
	local cached = self.cache[relative]
	if cached ~= nil then
		return cached
	end

	local fullPath = self:Resolve(relative)
	if not isfile(fullPath) then
		error("[phantom] missing framework file: " .. fullPath)
	end

	local source = readfile(fullPath)
	local chunk, compileError = loadstring(source, "@" .. fullPath)
	if not chunk then
		error("[phantom] failed to compile framework module " .. relative .. ": " .. tostring(compileError))
	end

	local ok, result = pcall(chunk, ...)
	if not ok then
		error("[phantom] failed to execute framework module " .. relative .. ": " .. tostring(result))
	end

	self.cache[relative] = result
	return result
end

function Framework:LoadCore(name)
	return self:Load("core/" .. tostring(name))
end

function Framework:LoadNet(name)
	return self:Load("net/" .. tostring(name))
end

function Framework:LoadRenderer(name)
	return self:Load("render/" .. tostring(name))
end

function Framework:LoadSystem(name)
	return self:Load("systems/" .. tostring(name))
end

function Framework:LoadUtility(name)
	return self:Load("utils/" .. tostring(name))
end

return Framework
