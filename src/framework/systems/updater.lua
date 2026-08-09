local Updater = {}
Updater.__index = Updater

local function startsWith(value, prefix)
	return value:sub(1, #prefix) == prefix
end

local function encodePath(path)
	return tostring(path):gsub(" ", "%%20")
end

function Updater.new(options)
	options = options or {}
	return setmetatable({
		file = options.file,
		http = options.http,
		config = options.config,
		logger = options.logger,
		developer = options.developer,
		repo = options.repo or {
			owner = "XzynAstralz",
			name = "Phantom",
		},
		cachePath = options.cachePath or "cache/release-manifest.json",
		settings = nil,
	}, Updater)
end

function Updater:GetDefaults()
	return {
		autoUpdate = true,
		developerMode = false,
		debugLogs = false,
		allowPatching = true,
		releaseChannel = "stable",
	}
end

function Updater:_syncDeveloperState()
	local settings = self.settings or self:GetDefaults()
	if self.developer and type(self.developer.Sync) == "function" then
		return self.developer:Sync(settings.developerMode)
	end

	return {
		enabled = settings.developerMode == true,
		overrideEnabled = settings.developerMode == true,
		externalEnabled = false,
		source = settings.developerMode and "ui" or "disabled",
	}
end

function Updater:LoadSettings()
	self.settings = self.config:Load("loader", self:GetDefaults())
	self.settings.autoUpdate = self.settings.autoUpdate ~= false
	self.settings.developerMode = self.settings.developerMode == true
	self.settings.debugLogs = self.settings.debugLogs == true
	self.settings.allowPatching = self.settings.allowPatching ~= false

	local developerState = self:_syncDeveloperState()
	if self.logger then
		self.logger:SetDebug(self.settings.debugLogs or developerState.enabled)
	end
	return self.settings
end

function Updater:GetSettings()
	if not self.settings then
		return self:LoadSettings()
	end
	return self.settings
end

function Updater:GetDeveloperState()
	self:GetSettings()
	return self:_syncDeveloperState()
end

function Updater:IsDeveloperModeEnabled()
	return self:GetDeveloperState().enabled == true
end

function Updater:SetSetting(key, value, persist)
	local settings = self:GetSettings()
	settings[key] = value

	local developerState = self:_syncDeveloperState()
	if self.logger and (key == "debugLogs" or key == "developerMode") then
		self.logger:SetDebug(settings.debugLogs or developerState.enabled)
	end
	if persist ~= false then
		self.config:ScheduleSave("loader", settings, 0.05)
	end
	return settings
end

function Updater:GetLocalManifest()
	return self.file:ReadJson(self.cachePath, nil)
end

function Updater:SaveLocalManifest(manifest)
	return self.file:WriteJson(self.cachePath, manifest, { force = true })
end

function Updater:GetPreferredRef()
	local manifest = self:GetLocalManifest()
	if manifest and manifest.releaseTag then
		return manifest.releaseTag
	end
	return "main"
end

function Updater:_releaseApiUrl()
	return string.format("https://api.github.com/repos/%s/%s/releases/latest", self.repo.owner, self.repo.name)
end

function Updater:_rawBaseUrl(ref)
	return string.format("https://raw.githubusercontent.com/%s/%s/%s/", self.repo.owner, self.repo.name, ref)
end

function Updater:_fetchManifestFromRelease(release)
	for _, asset in ipairs(release.assets or {}) do
		if asset.name == "release-manifest.json" and asset.browser_download_url then
			local ok, manifest = self.http:GetJson(asset.browser_download_url, {
				Accept = "application/json",
			})
			if ok and type(manifest) == "table" then
				return manifest
			end
		end
	end

	local tagName = release.tag_name or "main"
	local ok, manifest = self.http:GetJson(self:_rawBaseUrl(tagName) .. "release-manifest.json")
	if ok and type(manifest) == "table" then
		return manifest
	end

	return nil
end

function Updater:FetchLatestManifest()
	local ok, release = self.http:GetJson(self:_releaseApiUrl(), {
		Accept = "application/vnd.github+json",
	})
	if not ok or type(release) ~= "table" then
		return nil, release
	end

	local manifest = self:_fetchManifestFromRelease(release)
	if not manifest then
		return nil, "release manifest missing"
	end

	manifest.releaseTag = manifest.releaseTag or release.tag_name or "main"
	manifest.version = manifest.version or manifest.releaseTag
	manifest.rawBaseUrl = manifest.rawBaseUrl or self:_rawBaseUrl(manifest.releaseTag)
	manifest.files = manifest.files or {}

	return manifest, release
end

function Updater:_buildFileMap(manifest)
	local map = {}
	if not manifest or type(manifest.files) ~= "table" then
		return map
	end
	for _, entry in ipairs(manifest.files) do
		if entry.path then
			map[entry.path] = entry
		end
	end
	return map
end

function Updater:_isPreserved(path)
	return startsWith(path, "config/") or startsWith(path, "configs/") or startsWith(path, "cache/")
end

function Updater:_downloadUrl(manifest, entry)
	if entry.url then
		return entry.url
	end
	return (manifest.rawBaseUrl or self:_rawBaseUrl(manifest.releaseTag or "main")) .. encodePath(entry.path)
end

function Updater:_manifestHasPath(manifest, wantedPath)
	for _, entry in ipairs(manifest.files or {}) do
		if tostring(entry.path or "") == wantedPath then
			return true
		end
	end
	return false
end

function Updater:IsRemoteCompatible(manifest)
	if not self.file:Exists("src/framework/init.lua") then
		return true
	end
	return self:_manifestHasPath(manifest, "src/framework/init.lua")
end

function Updater:BuildPlan(remoteManifest, localManifest, options)
	options = options or {}
	local localFiles = self:_buildFileMap(localManifest)
	local toDownload = {}
	local skipped = {}

	for _, entry in ipairs(remoteManifest.files or {}) do
		local path = tostring(entry.path or "")
		if path ~= "" then
			local localEntry = localFiles[path]
			local exists = self.file:Exists(path)
			local sameHash = not options.force and localEntry and entry.sha256 and localEntry.sha256 == entry.sha256 and exists

			if sameHash then
			elseif self:_isPreserved(path) then
				skipped[#skipped + 1] = { path = path, reason = "preserved" }
			else
				toDownload[#toDownload + 1] = entry
			end
		end
	end

	return {
		toDownload = toDownload,
		skipped = skipped,
	}
end

function Updater:_replacePlain(source, target, replacement, limit)
	if target == "" then
		return source, 0
	end

	local count = 0
	local result = {}
	local cursor = 1

	while true do
		local first, last = string.find(source, target, cursor, true)
		if not first or (limit and count >= limit) then
			result[#result + 1] = source:sub(cursor)
			break
		end

		result[#result + 1] = source:sub(cursor, first - 1)
		result[#result + 1] = replacement
		count = count + 1
		cursor = last + 1
	end

	if count == 0 then
		return source, 0
	end

	return table.concat(result), count
end

function Updater:ApplyPatch(entry)
	local source = self.file:Read(entry.path)
	if not source then
		return false, "missing local file for patch"
	end

	for _, patch in ipairs(entry.patches or {}) do
		local updatedSource, replacements
		if patch.plain == false then
			updatedSource, replacements = source:gsub(patch.find or "", patch.replace or "", patch.count or 1)
		else
			updatedSource, replacements = self:_replacePlain(source, patch.find or "", patch.replace or "", patch.count)
		end

		if replacements == 0 and not patch.optional then
			return false, "patch target not found"
		end

		source = updatedSource
	end

	return self.file:Write(entry.path, source, { force = true })
end

function Updater:DownloadEntry(entry, manifest)
	local ok, body = self.http:Get(self:_downloadUrl(manifest, entry))
	if not ok then
		return false, body
	end
	return self.file:Write(entry.path, body, { force = true })
end

function Updater:Check(ui)
	return self:Run(ui, { apply = false })
end

function Updater:Apply(ui, options)
	options = options or {}
	options.apply = true
	return self:Run(ui, options)
end

function Updater:Run(ui, options)
	options = options or {}
	local applyChanges = options.apply ~= false
	local settings = self:GetSettings()
	local developerState = self:GetDeveloperState()
	local forceBootstrap = options.forceBootstrap == true
		or not self.file:Exists("Main.lua")
		or not self.file:Exists("src/framework/init.lua")
		or not self.file:Exists("src/framework/render/renderer.lua")

	if developerState.enabled then
		if ui and ui.SetStatus then
			ui:SetStatus("Developer mode enabled. Using local files.")
		end
		return {
			status = self.file:Exists("Main.lua") and "developer-mode" or "blocked-developer",
			developer = developerState,
		}
	end

	if ui and ui.SetStatus then
		ui:SetStatus("Checking for updates...")
	end

	local remoteManifest, releaseOrError = self:FetchLatestManifest()
	if not remoteManifest then
		if ui and ui.SetStatus then
			ui:SetStatus("GitHub unavailable. Using local files.")
		end
		if self.file:Exists("Main.lua") then
			return { status = "offline-local", release = releaseOrError }
		end
		return { status = "error", error = releaseOrError }
	end

	if not self:IsRemoteCompatible(remoteManifest) then
		if ui and ui.SetStatus then
			ui:SetStatus("Remote build is older than local framework.")
		end
		return {
			status = "incompatible-remote",
			manifest = remoteManifest,
			release = releaseOrError,
		}
	end

	local localManifest = self:GetLocalManifest()
	local plan = self:BuildPlan(remoteManifest, localManifest, {
		force = options.force == true,
	})

	if not applyChanges then
		return {
			status = #plan.toDownload == 0 and "up-to-date" or "outdated",
			manifest = remoteManifest,
			plan = plan,
		}
	end

	if not settings.autoUpdate and not forceBootstrap and not options.force then
		if ui and ui.SetStatus then
			ui:SetStatus("Auto updater disabled.")
		end
		return {
			status = "disabled",
			manifest = remoteManifest,
			plan = plan,
		}
	end

	if #plan.toDownload == 0 then
		self:SaveLocalManifest(remoteManifest)
		if ui and ui.SetStatus then
			ui:SetStatus("Up to date")
		end
		return {
			status = "up-to-date",
			manifest = remoteManifest,
			plan = plan,
		}
	end

	local updated = {}
	local failures = {}
	local total = #plan.toDownload

	for index, entry in ipairs(plan.toDownload) do
		if ui and ui.SetStatus then
			ui:SetStatus(string.format("Updating %s", entry.path))
		end
		if ui and ui.SetProgress then
			ui:SetProgress(index - 1, total, entry.path)
		end

		local ok, err = false, ""
		if entry.mode == "patch" and settings.allowPatching then
			ok, err = self:ApplyPatch(entry)
		end
		if not ok then
			ok, err = self:DownloadEntry(entry, remoteManifest)
		end

		if ok then
			updated[#updated + 1] = entry.path
		else
			failures[#failures + 1] = {
				path = entry.path,
				error = err,
			}
			if self.logger then
				self.logger:Warn("update failed", entry.path, err)
			end
		end
	end

	if ui and ui.SetProgress then
		ui:SetProgress(total, total, tostring(game.PlaceId))
	end

	if #failures == 0 then
		self:SaveLocalManifest(remoteManifest)
	end

	if ui and ui.SetStatus then
		ui:SetStatus(#failures == 0 and "Update complete" or "Update finished with warnings")
	end

	return {
		status = #failures == 0 and "updated" or "partial",
		manifest = remoteManifest,
		plan = plan,
		updated = updated,
		failures = failures,
	}
end

return Updater
