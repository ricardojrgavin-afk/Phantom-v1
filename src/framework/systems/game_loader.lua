local HttpService = game:GetService("HttpService")

local GameLoader = {}
GameLoader.__index = GameLoader

local function normalizeId(value)
	local id = tostring(value or "")
	if id == "0" then
		return ""
	end
	return id
end

local function endsWith(value, suffix)
	if suffix == "" then
		return true
	end
	return value:sub(-#suffix) == suffix
end

local function decodeJson(body)
	if type(body) ~= "string" or body == "" then
		return nil
	end

	local ok, decoded = pcall(function()
		return HttpService:JSONDecode(body)
	end)
	if ok then
		return decoded
	end
	return nil
end

local function sanitizeKey(value)
	return tostring(value or "script"):gsub("[^%w_%-]", "_")
end

function GameLoader.new(options)
	options = options or {}
	return setmetatable({
		file = options.file,
		module = options.module,
		http = options.http,
		logger = options.logger,
		updater = options.updater,
		developer = options.developer,
		repo = options.repo or {
			owner = "XzynAstralz",
			name = "Phantom",
		},
	}, GameLoader)
end

function GameLoader:_developerState()
	if self.developer and type(self.developer.Sync) == "function" then
		return self.developer:Sync()
	end

	return {
		enabled = false,
		overrideEnabled = false,
		externalEnabled = false,
		source = "disabled",
	}
end

function GameLoader:_preferredRef()
	if self.updater and type(self.updater.GetPreferredRef) == "function" then
		return self.updater:GetPreferredRef()
	end
	return "main"
end

function GameLoader:_rawBaseUrl(ref)
	return string.format("https://raw.githubusercontent.com/%s/%s/%s/", self.repo.owner, self.repo.name, ref)
end

function GameLoader:_contentsUrl(folderPath, ref)
	return string.format(
		"https://api.github.com/repos/%s/%s/contents/%s?ref=%s",
		self.repo.owner,
		self.repo.name,
		folderPath,
		HttpService:UrlEncode(ref)
	)
end

function GameLoader:_buildDescriptor(id, label)
	local normalized = normalizeId(id)
	return {
		id = normalized,
		label = label,
		displayLabel = normalized ~= "" and (label .. " " .. normalized) or label,
		folderPath = normalized ~= "" and ("games/" .. normalized) or nil,
		legacyPath = normalized ~= "" and ("games/" .. normalized .. ".lua") or nil,
		paths = {},
		exists = false,
		source = "missing",
	}
end

function GameLoader:_resolveUniversal()
	local descriptor = {
		id = "universal",
		label = "universal",
		displayLabel = "universal",
		folderPath = "games/universal",
		legacyPath = "games/universal.lua",
		paths = {},
		exists = false,
		source = "missing",
	}

	local folderPaths = self.file:ListLuaFiles(descriptor.folderPath)
	if #folderPaths > 0 then
		descriptor.paths = folderPaths
		descriptor.exists = true
		descriptor.source = "folder"
		return descriptor
	end

	if self.file:IsFile(descriptor.legacyPath) then
		descriptor.paths = { descriptor.legacyPath }
		descriptor.exists = true
		descriptor.source = "legacy-file"
	end

	return descriptor
end

function GameLoader:_resolveLocalTarget(id, label)
	local descriptor = self:_buildDescriptor(id, label)
	if descriptor.id == "" then
		return descriptor
	end

	local folderPaths = self.file:ListLuaFiles(descriptor.folderPath)
	if #folderPaths > 0 then
		descriptor.paths = folderPaths
		descriptor.exists = true
		descriptor.source = "folder"
		return descriptor
	end

	if self.file:IsFile(descriptor.legacyPath) then
		descriptor.paths = { descriptor.legacyPath }
		descriptor.exists = true
		descriptor.source = "legacy-file"
	end

	return descriptor
end

function GameLoader:_downloadRemoteFolder(descriptor)
	local developerState = self:_developerState()
	if developerState.enabled then
		return false, "developer mode enabled"
	end

	if not self.http or not descriptor or descriptor.id == "" then
		return false, "remote loader unavailable"
	end

	local ref = self:_preferredRef()
	local ok, body, response = self.http:Request({
		url = self:_contentsUrl(descriptor.folderPath, ref),
		method = "GET",
		headers = {
			Accept = "application/vnd.github+json",
		},
	})

	local decoded = decodeJson(body)
	if ok and type(decoded) == "table" then
		local scripts = {}
		for _, entry in ipairs(decoded) do
			local entryName = string.lower(tostring(entry.name or ""))
			if entry.type == "file" and endsWith(entryName, ".lua") then
				scripts[#scripts + 1] = entry
			end
		end

		table.sort(scripts, function(left, right)
			return string.lower(tostring(left.name or "")) < string.lower(tostring(right.name or ""))
		end)

		if #scripts > 0 then
			self.file:MakeFolder(descriptor.folderPath)
			local downloadedPaths = {}

			for _, entry in ipairs(scripts) do
				local downloadUrl = entry.download_url
				if not downloadUrl or downloadUrl == "" then
					downloadUrl = self:_rawBaseUrl(ref) .. descriptor.folderPath .. "/" .. tostring(entry.name)
				end

				local downloadOk, source = self.http:Get(downloadUrl, {
					Accept = "text/plain",
				})
				if not downloadOk then
					return false, source
				end

				local localPath = descriptor.folderPath .. "/" .. tostring(entry.name)
				local writeOk, writeErr = self.file:Write(localPath, source, { force = true })
				if not writeOk then
					return false, writeErr
				end

				downloadedPaths[#downloadedPaths + 1] = localPath
			end

			descriptor.paths = downloadedPaths
			descriptor.exists = #downloadedPaths > 0
			descriptor.source = "remote-folder"
			descriptor.ref = ref
			return descriptor.exists, descriptor
		end
	end

	local legacyUrl = self:_rawBaseUrl(ref) .. "games/" .. descriptor.id .. ".lua"
	local legacyOk, legacyBody = self.http:Get(legacyUrl, {
		Accept = "text/plain",
	})
	if legacyOk then
		self.file:MakeFolder(descriptor.folderPath)
		local fallbackPath = descriptor.folderPath .. "/main.lua"
		local writeOk, writeErr = self.file:Write(fallbackPath, legacyBody, { force = true })
		if not writeOk then
			return false, writeErr
		end

		descriptor.paths = { fallbackPath }
		descriptor.exists = true
		descriptor.source = "remote-legacy"
		descriptor.ref = ref
		return true, descriptor
	end

	if self.logger then
		local statusCode = response and response.StatusCode or "?"
		self.logger:Warn("game folder download failed", descriptor.folderPath, statusCode, decoded and decoded.message or body)
	end

	return false, decoded and decoded.message or legacyBody or body or "missing remote game folder"
end

function GameLoader:Resolve(context)
	context = context or {}

	local creator = self:_resolveLocalTarget(context.creatorId, "creator")
	local game = self:_resolveLocalTarget(context.gameId, "game")
	if not game.exists and game.id ~= "" then
		local downloaded, remoteResult = self:_downloadRemoteFolder(game)
		if downloaded and type(remoteResult) == "table" then
			game = remoteResult
		elseif not downloaded and self.logger and remoteResult and remoteResult ~= "developer mode enabled" then
			self.logger:Debug("remote game folder unavailable", game.id, remoteResult)
		end
	end

	local place = self:_resolveLocalTarget(context.placeId, "place")
	local universal = self:_resolveUniversal()
	local primary = game.exists and game or place.exists and place or game.id ~= "" and game or place
	local active = creator.exists and creator or primary

	return {
		universal = universal,
		creator = creator,
		game = game,
		place = place,
		primary = primary,
		active = active,
	}
end

function GameLoader:GetPrimaryPath(bundle)
	if type(bundle) ~= "table" then
		return nil
	end
	return bundle.paths and bundle.paths[1] or bundle.legacyPath or bundle.folderPath
end

function GameLoader:GetActiveKey(resolved, context)
	local active = resolved and resolved.active
	if active and active.exists and active.id ~= "" then
		return active.id
	end

	local gameId = normalizeId(context and context.gameId)
	local placeId = normalizeId(context and context.placeId)
	return gameId ~= "" and gameId or placeId
end

function GameLoader:GetActiveLabel(resolved, context)
	local active = resolved and resolved.active
	if active and active.exists then
		return active.displayLabel
	end

	local gameId = normalizeId(context and context.gameId)
	local placeId = normalizeId(context and context.placeId)
	return "game " .. (gameId ~= "" and gameId or placeId)
end

function GameLoader:ReadBundle(bundle)
	if type(bundle) ~= "table" or not bundle.exists then
		return ""
	end

	local parts = {}
	for _, path in ipairs(bundle.paths or {}) do
		local source = self.file:Read(path, "")
		if source ~= "" then
			parts[#parts + 1] = "-- " .. tostring(path)
			parts[#parts + 1] = source
		end
	end
	return table.concat(parts, "\n\n")
end

function GameLoader:LoadBundle(namespace, bundle)
	if type(bundle) ~= "table" or not bundle.exists then
		return true
	end

	local failures = {}
	for index, path in ipairs(bundle.paths or {}) do
		local basename = path:match("([^/]+)%.lua$") or ("script_" .. tostring(index))
		local key = string.format("%s/%02d_%s", tostring(namespace), index, sanitizeKey(basename))
		self.module:RegisterPath(key, path, {
			cache = false,
			hotReload = true,
		})

		local _, err = self.module:Reload(key)
		if err then
			failures[#failures + 1] = {
				path = path,
				error = err,
			}
			if self.logger then
				self.logger:Warn("failed to load game script", path, err)
			end
		end
	end

	return #failures == 0, failures
end

return GameLoader
