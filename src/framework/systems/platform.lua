local function loadFrameworkModule(relativePath)
	local fullPath = "Phantom/src/framework/" .. tostring(relativePath)
	local source = readfile(fullPath)
	local chunk, err = loadstring(source, "@" .. fullPath)
	if not chunk then
		error("[phantom] failed to compile " .. tostring(relativePath) .. ": " .. tostring(err))
	end

	local ok, result = pcall(chunk)
	if not ok then
		error("[phantom] failed to execute " .. tostring(relativePath) .. ": " .. tostring(result))
	end

	return result
end

local File = loadFrameworkModule("utils/file.lua")
local Http = loadFrameworkModule("net/http.lua")
local Config = loadFrameworkModule("core/config.lua")
local Discord = loadFrameworkModule("net/discord.lua")

local Platform = {}
Platform.__index = Platform

function Platform.new(rootName, logger)
	local file = File.new(rootName, logger)
	local http = Http.new(logger)
	local config = Config.new(file, logger)

	return setmetatable({
		logger = logger,
		file = file,
		http = http,
		config = config,
	}, Platform)
end

function Platform:SetLogger(logger)
	self.logger = logger
	if self.file then
		self.file.logger = logger
	end
	if self.http then
		self.http.logger = logger
	end
	if self.config then
		self.config.logger = logger
	end
	return logger
end

function Platform:CreateDiscord(options)
	options = options or {}
	options.file = options.file or self.file
	options.http = options.http or self.http
	options.logger = options.logger or self.logger
	return Discord.new(options)
end

Platform.File = File
Platform.Http = Http
Platform.Config = Config
Platform.Discord = Discord

return Platform
