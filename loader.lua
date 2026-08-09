
repeat task.wait() until game:IsLoaded()

local environment = getgenv() or getfenv() or {}

local getgenv = environment.getgenv or getgenv or getfenv
local isfile = environment.isfile or isfile
local isfolder = environment.isfolder or isfolder
local makefolder = environment.makefolder or makefolder
local readfile = environment.readfile or readfile
local writefile = environment.writefile or writefile
local request = environment.request or request
local http_request = environment.http_request or http_request
local gethui = environment.gethui or gethui
local get_hidden_gui = environment.get_hidden_gui or get_hidden_gui

if not getgenv then
	return warn("[phantom] unsupported executor.")
end

local HttpService = game:GetService("HttpService")
local ROOT = "Phantom"
local REPO_OWNER = "XzynAstralz"
local REPO_NAME = "Phantom"
local LOADER_PLACE_ID = tostring(game.PlaceId)
local LOADER_GAME_ID = tonumber(game.GameId) and tostring(game.GameId) or ""
local LOADER_DISPLAY_ID = LOADER_GAME_ID ~= "" and LOADER_GAME_ID or LOADER_PLACE_ID

local function parseBooleanText(value)
	local normalized = string.lower(tostring(value or ""))
	normalized = normalized:gsub("%s+", "")
	return normalized == "true" or normalized == "1" or normalized == "yes" or normalized == "on"
end

local function readDeveloperFlag()
	if not isfile or not readfile or not isfile("debug.dev/checkdev.txt") then
		return false
	end

	local ok, contents = pcall(readfile, "debug.dev/checkdev.txt")
	if ok then
		return parseBooleanText(contents)
	end

	return false
end

local function normalize(path)
	path = tostring(path or "")
	path = path:gsub("\\", "/")
	path = path:gsub("^%./", "")
	path = path:gsub("^/+", "")
	path = path:gsub("/+", "/")
	path = path:gsub("/$", "")
	return path
end

local function mapToStorage(path)
	path = normalize(path)
	if path == "assets" or path:match("^assets/") or
		path == "config" or path:match("^config/") or
		path == "configs" or path:match("^configs/") or
		path == "cache" or path:match("^cache/") then
		return "storage/" .. path
	end
	return path
end

local function resolve(path)
	path = normalize(path)
	if path == "" then
		return ROOT
	end

	local lowerPath = path:lower()
	local rootPrefix = ROOT:lower() .. "/"
	if lowerPath:sub(1, #rootPrefix) == rootPrefix then
		local inner = path:sub(#rootPrefix + 1)
		local mapped = mapToStorage(inner)
		if mapped == inner then
			return path
		end
		return ROOT .. "/" .. mapped
	end

	local mapped = mapToStorage(path)
	return ROOT .. "/" .. mapped
end

local function ensureFolder(path)
	local relative = normalize(path)
	local current = ROOT

	if not isfolder(current) then
		pcall(makefolder, current)
	end

	if relative == "" then
		return
	end

	for segment in relative:gmatch("[^/]+") do
		current = current .. "/" .. segment
		if not isfolder(current) then
			pcall(makefolder, current)
		end
	end
end

local function ensureParent(path)
	local relative = normalize(path)
	local parent = relative:match("^(.*)/[^/]+$")
	if parent and parent ~= "" then
		ensureFolder(mapToStorage(parent))
	else
		ensureFolder("")
	end
end

local function readFile(path)
	local fullPath = resolve(path)
	if not isfile(fullPath) then
		return nil
	end
	local ok, contents = pcall(readfile, fullPath)
	if ok then
		return contents
	end
	return nil
end

local function readJson(path, defaultValue)
	local contents = readFile(path)
	if not contents or contents == "" then
		return defaultValue
	end
	local ok, decoded = pcall(function()
		return HttpService:JSONDecode(contents)
	end)
	if ok then
		return decoded
	end
	return defaultValue
end

local function requestFunction()
	return environment.request or environment.http_request or (environment.syn and environment.syn.request) or (environment.http and environment.http.request) or (environment.fluxus and environment.fluxus.request)
end

local function httpGet(url, headers)
	local request = requestFunction()
	if not request then
		return false, "No request function available", { StatusCode = 0 }
	end

	local ok, response = pcall(request, {
		Url = url,
		Method = "GET",
		Headers = headers or {},
	})

	if ok and response and tonumber(response.StatusCode) then
		if response.StatusCode >= 200 and response.StatusCode < 300 then
			return true, response.Body, response
		else
			return false, response.Body, response
		end
	end

	return false, response, { StatusCode = 0 }
end

local function httpGetJson(url, headers)
	local ok, body, response = httpGet(url, headers)
	if not ok then
		return false, body, response
	end
	local success, decoded = pcall(function()
		return HttpService:JSONDecode(body)
	end)
	if success then
		return true, decoded, response
	end
	return false, decoded, response
end

local function encodePath(path)
	return tostring(path):gsub(" ", "%%20")
end

local function buildRawBase(ref)
	return string.format("https://raw.githubusercontent.com/%s/%s/%s/", REPO_OWNER, REPO_NAME, ref)
end

local function fetchLatestManifest()
	local ok, release = httpGetJson(string.format("https://api.github.com/repos/%s/%s/releases/latest", REPO_OWNER, REPO_NAME), {
		Accept = "application/vnd.github+json",
	})
	if not ok or type(release) ~= "table" then
		return nil, release
	end

	for _, asset in ipairs(release.assets or {}) do
		if asset.name == "release-manifest.json" and asset.browser_download_url then
			local assetOk, manifest = httpGetJson(asset.browser_download_url, {
				Accept = "application/json",
			})
			if assetOk and type(manifest) == "table" then
				manifest.releaseTag = manifest.releaseTag or release.tag_name or "main"
				manifest.version = manifest.version or manifest.releaseTag
				manifest.rawBaseUrl = manifest.rawBaseUrl or buildRawBase(manifest.releaseTag)
				manifest.files = manifest.files or {}
				return manifest, release
			end
		end
	end

	local rawOk, manifest = httpGetJson(buildRawBase(release.tag_name or "main") .. "release-manifest.json")
	if rawOk and type(manifest) == "table" then
		manifest.releaseTag = manifest.releaseTag or release.tag_name or "main"
		manifest.version = manifest.version or manifest.releaseTag
		manifest.rawBaseUrl = manifest.rawBaseUrl or buildRawBase(manifest.releaseTag)
		manifest.files = manifest.files or {}
		return manifest, release
	end

	return nil, "release manifest missing"
end

local function replacePlain(source, target, replacement, limit)
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

local function applyPatch(entry)
	local source = readFile(entry.path)
	if not source then
		return false, "missing local file for patch"
	end

	for _, patch in ipairs(entry.patches or {}) do
		local updated, replacements
		if patch.plain == false then
			updated, replacements = source:gsub(patch.find or "", patch.replace or "", patch.count or 1)
		else
			updated, replacements = replacePlain(source, patch.find or "", patch.replace or "", patch.count)
		end
		if replacements == 0 and not patch.optional then
			return false, "patch target not found"
		end
		source = updated
	end

	ensureParent(entry.path)
	return pcall(writefile, resolve(entry.path), source)
end

local function isPreserved(path)
	path = normalize(path)
	return path:sub(1, 7) == "config/" or path:sub(1, 8) == "configs/" or path:sub(1, 6) == "cache/"
end

local function isDeveloperProtected(path)
	return tostring(path):match("%.lua$") ~= nil
end

local function getSettings()
	local settings = readJson("config/loader.json", {
		autoUpdate = true,
		developerMode = false,
		debugLogs = false,
		allowPatching = true,
		releaseChannel = "stable",
	})
	settings.autoUpdate = settings.autoUpdate ~= false
	settings.developerMode = settings.developerMode == true
	settings.debugLogs = settings.debugLogs == true
	settings.allowPatching = settings.allowPatching ~= false
	return settings
end

local function createLoaderUi()
	local noop = {
		SetStatus = function() end,
		SetProgress = function() end,
		Destroy = function() end,
	}

	local ok, result = pcall(function()
		local parent = (get_hidden_gui and get_hidden_gui()) or (gethui and gethui()) or game.CoreGui

		local gui = Instance.new("ScreenGui")
		gui.Name = "PhantomLoader"
		gui.ResetOnSpawn = false
		gui.IgnoreGuiInset = true
		gui.DisplayOrder = 999998
		gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		gui.Parent = parent

		local root = Instance.new("Frame")
		root.Parent = gui
		root.AnchorPoint = Vector2.new(0.5, 0.5)
		root.Position = UDim2.fromScale(0.5, 0.5)
		root.Size = UDim2.new(0, 420, 0, 166)
		root.BackgroundColor3 = Color3.fromRGB(10, 14, 21)
		root.BorderSizePixel = 0

		local rootCorner = Instance.new("UICorner")
		rootCorner.CornerRadius = UDim.new(0, 18)
		rootCorner.Parent = root

		local rootStroke = Instance.new("UIStroke")
		rootStroke.Color = Color3.fromRGB(67, 78, 96)
		rootStroke.Transparency = 0.2
		rootStroke.Parent = root

		local title = Instance.new("TextLabel")
		title.Parent = root
		title.BackgroundTransparency = 1
		title.Position = UDim2.new(0, 18, 0, 16)
		title.Size = UDim2.new(1, -36, 0, 24)
		title.Font = Enum.Font.GothamBold
		title.Text = "Phantom Loader"
		title.TextColor3 = Color3.fromRGB(241, 235, 226)
		title.TextSize = 20
		title.TextXAlignment = Enum.TextXAlignment.Left

		local subtitle = Instance.new("TextLabel")
		subtitle.Parent = root
		subtitle.BackgroundTransparency = 1
		subtitle.Position = UDim2.new(0, 18, 0, 44)
		subtitle.Size = UDim2.new(1, -36, 0, 16)
		subtitle.Font = Enum.Font.Gotham
		subtitle.Text = LOADER_GAME_ID ~= ""
			and string.format("GameID %s  PlaceID %s", LOADER_GAME_ID, LOADER_PLACE_ID)
			or ("PlaceID " .. LOADER_PLACE_ID)
		subtitle.TextColor3 = Color3.fromRGB(165, 174, 190)
		subtitle.TextSize = 12
		subtitle.TextXAlignment = Enum.TextXAlignment.Left

		local status = Instance.new("TextLabel")
		status.Parent = root
		status.BackgroundTransparency = 1
		status.Position = UDim2.new(0, 18, 0, 74)
		status.Size = UDim2.new(1, -36, 0, 20)
		status.Font = Enum.Font.GothamMedium
		status.Text = "Checking for updates..."
		status.TextColor3 = Color3.fromRGB(239, 155, 73)
		status.TextSize = 14
		status.TextXAlignment = Enum.TextXAlignment.Left

		local detail = Instance.new("TextLabel")
		detail.Parent = root
		detail.BackgroundTransparency = 1
		detail.Position = UDim2.new(0, 18, 0, 96)
		detail.Size = UDim2.new(1, -36, 0, 16)
		detail.Font = Enum.Font.Gotham
		detail.Text = "0/0"
		detail.TextColor3 = Color3.fromRGB(165, 174, 190)
		detail.TextSize = 12
		detail.TextXAlignment = Enum.TextXAlignment.Left

		local track = Instance.new("Frame")
		track.Parent = root
		track.BackgroundColor3 = Color3.fromRGB(24, 31, 45)
		track.BorderSizePixel = 0
		track.Position = UDim2.new(0, 18, 1, -34)
		track.Size = UDim2.new(1, -36, 0, 12)

		local trackCorner = Instance.new("UICorner")
		trackCorner.CornerRadius = UDim.new(0, 6)
		trackCorner.Parent = track

		local fill = Instance.new("Frame")
		fill.Parent = track
		fill.BackgroundColor3 = Color3.fromRGB(239, 155, 73)
		fill.BorderSizePixel = 0
		fill.Size = UDim2.new(0, 0, 1, 0)

		local fillCorner = Instance.new("UICorner")
		fillCorner.CornerRadius = UDim.new(0, 6)
		fillCorner.Parent = fill

		return {
			SetStatus = function(_, text)
				pcall(function()
					if status and status.Parent then
						status.Text = tostring(text)
					end
				end)
			end,
			SetProgress = function(_, complete, total, current)
				pcall(function()
					local ratio = total > 0 and math.clamp(complete / total, 0, 1) or 0
					fill.Size = UDim2.new(ratio, 0, 1, 0)
					detail.Text = string.format("%d/%d  %s", complete, total, tostring(current or LOADER_DISPLAY_ID))
				end)
			end,
			Destroy = function()
				pcall(function()
					if gui and gui.Parent then
						gui:Destroy()
					end
				end)
			end,
		}
	end)

	if ok and type(result) == "table" then
		return result
	end

	warn("[phantom] UI unavailable: " .. tostring(result))
	return noop
end

ensureFolder("")
ensureFolder("storage")
ensureFolder("storage/assets")
ensureFolder("storage/assets/icons")
ensureFolder("storage/cache")
ensureFolder("storage/config")
ensureFolder("storage/configs")
ensureFolder("games")
ensureFolder("lib")
ensureFolder("src/framework/core")
ensureFolder("src/framework/net")
ensureFolder("src/framework/render")
ensureFolder("src/framework/systems")
ensureFolder("src/framework/utils")


local settings = getSettings()
local developerFlagEnabled = readDeveloperFlag()
local developerModeEnabled = settings.developerMode or developerFlagEnabled
local ui = createLoaderUi()
local localManifest = readJson("cache/release-manifest.json", nil)
local remoteManifest, releaseOrError
if not developerModeEnabled then
	remoteManifest, releaseOrError = fetchLatestManifest()
end
local forceBootstrap = not isfile(resolve("Main.lua")) or not isfile(resolve("src/framework/init.lua")) or not isfile(resolve("src/framework/render/renderer.lua"))

local function manifestHasPath(manifest, wantedPath)
	for _, entry in ipairs(manifest.files or {}) do
		if tostring(entry.path or "") == wantedPath then
			return true
		end
	end
	return false
end

local function isRemoteCompatible(manifest)
	if not isfile(resolve("src/framework/init.lua")) then
		return true
	end
	return manifestHasPath(manifest, "src/framework/init.lua")
end

local function downloadUrl(manifest, entry)
	if entry.url then
		return entry.url
	end
	return (manifest.rawBaseUrl or buildRawBase(manifest.releaseTag or "main")) .. encodePath(entry.path)
end

local function buildPlan(manifest)
	local localFiles = {}
	if localManifest and type(localManifest.files) == "table" then
		for _, entry in ipairs(localManifest.files) do
			if entry.path then
				localFiles[entry.path] = entry
			end
		end
	end

	local plan = { toDownload = {}, skipped = {} }
	for _, entry in ipairs(manifest.files or {}) do
		local path = normalize(entry.path)
		local localEntry = localFiles[path]
		local exists = isfile(resolve(path))
		local sameHash = localEntry and entry.sha256 and localEntry.sha256 == entry.sha256 and exists

		if sameHash then
		elseif isPreserved(path) then
			plan.skipped[#plan.skipped + 1] = { path = path, reason = "preserved" }
		elseif developerModeEnabled and not forceBootstrap and isDeveloperProtected(path) and exists then
			plan.skipped[#plan.skipped + 1] = { path = path, reason = "developer-mode" }
		else
			entry.path = path
			plan.toDownload[#plan.toDownload + 1] = entry
		end
	end
	return plan
end

local function applyUpdatePlan(manifest, plan)
	local failures = {}
	local total = #plan.toDownload

	for index, entry in ipairs(plan.toDownload) do
		ui:SetStatus("Updating " .. entry.path)
		ui:SetProgress(index - 1, total, entry.path)

		local ok, result = false, ""
		if entry.mode == "patch" and settings.allowPatching then
			ok, result = applyPatch(entry)
		end
		if not ok then
			local downloaded, body = httpGet(downloadUrl(manifest, entry))
			if downloaded then
				ensureParent(entry.path)
				ok, result = pcall(writefile, resolve(entry.path), body)
			else
				ok, result = false, body
			end
		end

		if not ok then
			failures[#failures + 1] = { path = entry.path, error = result }
			warn("[phantom] update failed", entry.path, result)
		end
	end

	ui:SetProgress(total, total, LOADER_DISPLAY_ID)
	return failures
end

local updateStatus = "offline-local"
if developerModeEnabled then
	updateStatus = "developer-mode"
	ui:SetStatus("Developer mode enabled. Using local files.")
	ui:SetProgress(0, 0, LOADER_DISPLAY_ID)
	ui:Destroy()
	if forceBootstrap then
		return warn("[phantom] developer mode blocks GitHub bootstrap and the local runtime is incomplete.")
	end
elseif remoteManifest and not isRemoteCompatible(remoteManifest) then
	updateStatus = "incompatible-remote"
	ui:SetStatus("Remote build is older than local framework. Using local files.")
	ui:SetProgress(0, 0, LOADER_DISPLAY_ID)
	ui:Destroy()
	if forceBootstrap then
		return warn("[phantom] unable to bootstrap runtime: remote build is missing the new framework structure.")
	end
elseif remoteManifest then
	local plan = buildPlan(remoteManifest)
	if (not settings.autoUpdate and not forceBootstrap) then
		updateStatus = "disabled"
		ui:SetStatus("Auto updater disabled.")
		ui:Destroy()
	elseif #plan.toDownload == 0 then
		updateStatus = "up-to-date"
		local ok, encoded = pcall(HttpService.JSONEncode, HttpService, remoteManifest)
		if ok then
			ensureParent("cache/release-manifest.json")
			pcall(writefile, resolve("cache/release-manifest.json"), encoded)
		end
		ui:SetStatus("Up to date")
		ui:SetProgress(1, 1, LOADER_DISPLAY_ID)
		ui:Destroy()
	else
		updateStatus = "updated"
		local failures = applyUpdatePlan(remoteManifest, plan)
		if #failures == 0 then
			local ok, encoded = pcall(HttpService.JSONEncode, HttpService, remoteManifest)
			if ok then
				ensureParent("cache/release-manifest.json")
				pcall(writefile, resolve("cache/release-manifest.json"), encoded)
			end
			ui:SetStatus("Update complete")
			ui:Destroy()
		else
			updateStatus = "partial"
			ui:SetStatus("Update finished with warnings")
			ui:Destroy()
		end
	end
else
	ui:SetStatus("GitHub unavailable. Using local files.")
	ui:SetProgress(0, 0, LOADER_DISPLAY_ID)
	ui:Destroy()
	if forceBootstrap then
		return warn("[phantom] unable to bootstrap runtime: " .. tostring(releaseOrError))
	end
end

local patcherSource = readFile("lib/patcher.lua")
if patcherSource then
	local patcherChunk = loadstring(patcherSource, "@" .. resolve("lib/patcher.lua"))
	if patcherChunk then
		local ok, patcherResult = pcall(patcherChunk)
		if ok and type(patcherResult) == "table" and type(getgenv) == "function" then
			local env = getgenv()
			env.phantomExecutorInfo = patcherResult
			env.phantomMissingMainFunctions = patcherResult.missingMainLookup or {}
			env.phantomIsBadExecutor = patcherResult.executorLevel ~= "HIGH"
			env.phantomExecutor = type(env.phantomExecutor) == "table" and env.phantomExecutor or {}
			env.phantomExecutor.info = patcherResult
			env.phantomExecutor.missingMainLookup = env.phantomMissingMainFunctions
			env.phantomExecutor.isBad = env.phantomIsBadExecutor
		end
	end
end

local mainSource = readFile("Main.lua")
if not mainSource then
	ui:Destroy()
	return warn("[phantom] Main.lua missing after loader update.")
end

ui:SetStatus("Launching Phantom...")
task.delay(updateStatus == "up-to-date" and 0.15 or 0.45, function()
	ui:Destroy()
end)

local mainChunk, compileError = loadstring(mainSource, "@" .. resolve("Main.lua"))
if not mainChunk then
	return warn("[phantom] failed to compile Main.lua: " .. tostring(compileError))
end

local ok, runtimeError = pcall(mainChunk)
if not ok then
	return warn("[phantom] runtime error: " .. tostring(runtimeError))
end
