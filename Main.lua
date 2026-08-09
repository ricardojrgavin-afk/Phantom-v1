repeat task.wait() until game:IsLoaded()
local environment = getfenv and getfenv() or {}

local executorGetEnv = environment.getgenv
local executorCloneRef = environment.cloneref or function(value)
	return value
end
local executorIsFile = environment.isfile
local executorReadFile = environment.readfile
local executorGetCustomAsset = environment.getcustomasset
local _genv = (executorGetEnv and executorGetEnv()) or {}
local executorQueueForTeleport = environment.queue_for_teleport or _genv.queue_for_teleport
local executorQueueOnTeleport = environment.queue_on_teleport or _genv.queue_on_teleport
local executorQueueOnTeleportLegacy = environment.queueonteleport or _genv.queueonteleport
local customSignal
do
	local ok, ev = pcall(function() return Instance.new("BindableEvent") end)
	if ok and ev then
		customSignal = ev
	else
		customSignal = {
			Event = { Connect = function(_, fn) return { Disconnect = function() end } end },
			Fire = function() end,
			Destroy = function() end,
			Parent = nil,
		}
	end
end

if not executorGetEnv or not executorIsFile or not executorReadFile then
	cloneref(game:GetService("Players")).LocalPlayer:Kick("unsupported executor")
	return nil
end

local ROOT = "Phantom"
local function service(name)
	local instance = game:GetService(name)
	if executorCloneRef then
		local ok, cloned = pcall(executorCloneRef, instance)
		if ok and cloned then
			return cloned
		end
	end
	return instance
end

local function runtimePath(path)
	return ROOT .. "/" .. path
end

local function readRuntimeFile(path)
	local fullPath = runtimePath(path)
	if not executorIsFile(fullPath) then
		error("[phantom] missing runtime file: " .. fullPath)
	end
	return executorReadFile(fullPath), fullPath
end

local function loadRuntimeModule(path)
	local source, fullPath = readRuntimeFile(path)
	local chunk, err = loadstring(source, "@" .. fullPath)
	if not chunk then
		error("[phantom] failed to compile " .. path .. ": " .. tostring(err))
	end

	local ok, result = pcall(chunk)
	if not ok then
		error("[phantom] failed to execute " .. path .. ": " .. tostring(result))
	end

	return result
end

local env = executorGetEnv()
env.phantomInstances = type(env.phantomInstances) == "table" and env.phantomInstances or {}

do
	local shutdownQueue = {}
	local seen = {}

	if type(env.phantom) == "table" then
		shutdownQueue[#shutdownQueue + 1] = env.phantom
	end

	for _, instance in ipairs(env.phantomInstances) do
		shutdownQueue[#shutdownQueue + 1] = instance
	end

	for _, instance in ipairs(shutdownQueue) do
		if type(instance) == "table" and not seen[instance] then
			seen[instance] = true
			if type(instance.Shutdown) == "function" then
				pcall(instance.Shutdown, "hot-reload")
			end
		end
	end
end

local Framework = loadRuntimeModule("src/framework/init.lua")
local framework = Framework.new(ROOT)

local Logger = framework:Load("core/logger.lua")
local File = framework:Load("utils/file.lua")
local Http = framework:Load("net/http.lua")
local Manager = framework:Load("systems/manager.lua")
local Runtime = framework:Load("core/runtime.lua")
local Config = framework:Load("core/config.lua")
local Developer = framework:Load("core/developer.lua")
local Discord = framework:Load("net/discord.lua")
local Module = framework:Load("systems/module.lua")
local Version = framework:Load("core/version.lua")
local Updater = framework:Load("systems/updater.lua")
local GameLoader = framework:Load("systems/game_loader.lua")

local bootstrapLogger = Logger.new("[phantom]", false)
framework:SetLogger(bootstrapLogger)
local fileApi = File.new(ROOT, bootstrapLogger)
fileApi:EnsureRuntimeFolders()

local http = Http.new(bootstrapLogger)
local config = Config.new(fileApi, bootstrapLogger)
local developer = Developer.new({
	logger = bootstrapLogger,
})
local updater = Updater.new({
	file = fileApi,
	http = http,
	config = config,
	logger = bootstrapLogger,
	developer = developer,
	repo = {
		owner = "XzynAstralz",
		name = "Phantom",
	},
})
local settings = updater:GetSettings()
local developerState = developer:Sync(settings.developerMode)
local effectiveDeveloperMode = developerState.enabled == true

local logger = Logger.new("[phantom]", settings.debugLogs or effectiveDeveloperMode)
framework:SetLogger(logger)
fileApi.logger = logger
http.logger = logger
config.logger = logger
developer:SetLogger(logger)
updater.logger = logger

local discord = Discord.new({
	file = fileApi,
	http = http,
	logger = logger,
	statePath = "configs/discord.json",
	invite = "bvKBeKQsRY",
})

local versionData = Version.Read(fileApi)
local rootManager = Manager.new("phantom")
local runtime = Runtime.new(logger)
local moduleLoader = Module.new(fileApi, logger)
moduleLoader:SetDeveloperMode(effectiveDeveloperMode)
local gameLoader = GameLoader.new({
	file = fileApi,
	module = moduleLoader,
	http = http,
	logger = logger,
	updater = updater,
	developer = developer,
	repo = {
		owner = "XzynAstralz",
		name = "Phantom",
	},
})

local Services = {
	Players = service("Players"),
	UserInputService = service("UserInputService"),
	TeleportService = service("TeleportService"),
	RunService = service("RunService"),
	Lighting = service("Lighting"),
	HttpService = service("HttpService"),
	StarterGui = service("StarterGui"),
}
local LocalPlayer = Services.Players.LocalPlayer
local queueTeleport = executorQueueForTeleport or executorQueueOnTeleport or executorQueueOnTeleportLegacy
local placeId = tostring(game.PlaceId)
local gameId = tonumber(game.GameId) and tostring(game.GameId) or ""
local creatorId = tonumber(game.CreatorId) and tostring(game.CreatorId) or ""
local profileSlot = "default"
local overlayStatePath = "config/overlay.cfg.json"
local overlayState = fileApi:ReadJson(overlayStatePath, {})
local hudEditor
local configBar
local arrayListWidget
local watermarkWindow
local sessionInfoWindow

local uiFullyReady = false

local function readOverlayToggleState(key, defaultValue)
	if type(overlayState) ~= "table" then
		return defaultValue == true
	end
	local value = overlayState[key]
	if type(value) == "boolean" then
		return value
	end
	return defaultValue == true
end

local function setHideBadExecutorModules(enabled)
	local state = enabled == true
	env.phantomHideBadExecutorModules = state
	env.phantomExecutor = type(env.phantomExecutor) == "table" and env.phantomExecutor or {}
	env.phantomExecutor.hideUnsupportedModules = state
end

local function shouldAutoEnableHideBadExecutorModules()
	if env.phantomIsBadExecutor ~= true then
		return false
	end
	if type(env.phantomMissingMainFunctions) ~= "table" then
		return true
	end
	return next(env.phantomMissingMainFunctions) ~= nil
end

local function syncExecutorContextFromEnv()
	env.phantomExecutor = type(env.phantomExecutor) == "table" and env.phantomExecutor or {}
	
	local executor = env.phantomExecutor
	if type(env.phantomExecutorInfo) == "table" then
		executor.info = env.phantomExecutorInfo
	end
	if type(env.phantomMissingMainFunctions) == "table" then
		executor.missingMainLookup = env.phantomMissingMainFunctions
	end
	if env.phantomIsBadExecutor ~= nil then
		executor.isBad = env.phantomIsBadExecutor == true
	end
	
	executor.hideUnsupportedModules = executor.hideUnsupportedModules == true
end

setHideBadExecutorModules(readOverlayToggleState("hide bad executor modules", false))
if shouldAutoEnableHideBadExecutorModules() then
	setHideBadExecutorModules(true)
end
syncExecutorContextFromEnv()

local gameContext = {
	placeId = placeId,
	gameId = gameId,
	creatorId = creatorId,
}
local gameScripts = gameLoader:Resolve(gameContext)

local function placeScriptExists()
	return type(gameScripts) == "table" and type(gameScripts.place) == "table" and gameScripts.place.exists == true
end

local function creatorScriptExists()
	return type(gameScripts) == "table" and type(gameScripts.creator) == "table" and gameScripts.creator.exists == true
end

local function gameScriptExists()
	return type(gameScripts) == "table" and type(gameScripts.game) == "table" and gameScripts.game.exists == true
end

local function activeGameKey()
	return gameLoader:GetActiveKey(gameScripts, gameContext)
end

local function activeModuleLabel()
	return gameLoader:GetActiveLabel(gameScripts, gameContext)
end

if type(overlayState) == "table" and overlayState.__preload == true then
	local preloadSlot = overlayState.__preloadCfg
	if type(preloadSlot) == "string" and preloadSlot ~= "" then
		profileSlot = preloadSlot
	end
end

local function getIcon(name)
	local path = "assets/icons/" .. tostring(name) .. ".png"
	local fullPath = fileApi:Resolve(path)
	if not executorIsFile(fullPath) or not executorGetCustomAsset then
		return nil
	end
	local ok, asset = pcall(executorGetCustomAsset, fullPath)
	if ok then
		return asset
	end
	return nil
end

local uiExport = loadRuntimeModule("GuiLibrary.lua")
local UI = type(uiExport) == "function" and uiExport() or uiExport
if not UI then
	error("[phantom] failed to initialize GuiLibrary")
end

if config and type(config.SetPromptFunction) == "function" then
	config:SetPromptFunction(function(opts)
		local ok, parent = pcall(function()
			local guiParent = nil
			if environment and environment.get_hidden_gui then
				local suc, p = pcall(environment.get_hidden_gui)
				if suc and p then guiParent = p end
			end
			if not guiParent and environment and environment.gethui then
				local suc, p = pcall(environment.gethui)
				if suc and p then guiParent = p end
			end
			return guiParent or game.CoreGui
		end)
		parent = (ok and parent) and parent or game.CoreGui

		local success, promptGui = pcall(function()
			local gui = Instance.new("ScreenGui")
			gui.Name = "PhantomConfigPrompt"
			gui.ResetOnSpawn = false
			gui.Parent = parent

			local frame = Instance.new("Frame")
			frame.Size = UDim2.new(0, 420, 0, 152)
			frame.AnchorPoint = Vector2.new(0.5, 0.5)
			frame.Position = UDim2.fromScale(0.5, 0.5)
			frame.BackgroundColor3 = Color3.fromRGB(10, 14, 21)
			frame.BorderSizePixel = 0
			frame.Parent = gui

			local title = Instance.new("TextLabel")
			title.Parent = frame
			title.BackgroundTransparency = 1
			title.Position = UDim2.new(0, 12, 0, 8)
			title.Size = UDim2.new(1, -24, 0, 26)
			title.Font = Enum.Font.GothamBold
			title.Text = tostring(opts.title or "Confirm")
			title.TextColor3 = Color3.fromRGB(241, 235, 226)
			title.TextSize = 18

			local body = Instance.new("TextLabel")
			body.Parent = frame
			body.BackgroundTransparency = 1
			body.Position = UDim2.new(0, 12, 0, 40)
			body.Size = UDim2.new(1, -24, 0, 64)
			body.Font = Enum.Font.Gotham
			body.Text = tostring(opts.message or "Are you sure?")
			body.TextColor3 = Color3.fromRGB(165, 174, 190)
			body.TextSize = 14
			body.TextWrapped = true

			local btnConfirm = Instance.new("TextButton")
			btnConfirm.Parent = frame
			btnConfirm.Position = UDim2.new(0, 24, 1, -46)
			btnConfirm.Size = UDim2.new(0, 160, 0, 32)
			btnConfirm.Font = Enum.Font.GothamBold
			btnConfirm.Text = "Overwrite"
			btnConfirm.TextSize = 14
			btnConfirm.TextColor3 = Color3.fromRGB(17, 18, 22)
			btnConfirm.BackgroundColor3 = Color3.fromRGB(239, 155, 73)

			local btnCancel = Instance.new("TextButton")
			btnCancel.Parent = frame
			btnCancel.Position = UDim2.new(1, -184, 1, -46)
			btnCancel.Size = UDim2.new(0, 160, 0, 32)
			btnCancel.Font = Enum.Font.Gotham
			btnCancel.Text = "Cancel"
			btnCancel.TextSize = 14
			btnCancel.TextColor3 = Color3.fromRGB(241, 235, 226)
			btnCancel.BackgroundColor3 = Color3.fromRGB(33, 40, 54)

			btnConfirm.MouseButton1Click:Connect(function()
				pcall(function()
					if type(opts.onConfirm) == "function" then
						opts.onConfirm()
					end
				end)
				if gui and gui.Parent then gui:Destroy() end
			end)
			btnCancel.MouseButton1Click:Connect(function()
				pcall(function()
					if type(opts.onCancel) == "function" then
						opts.onCancel()
					end
				end)
				if gui and gui.Parent then gui:Destroy() end
			end)

			return gui
		end)

		if not success then
			if type(opts.onConfirm) == "function" then
				pcall(opts.onConfirm)
			end
		end
	end)
end

local function readGuiTheme()
	local defaults = {
		H = 0.73,
		S = 0.77,
		V = 0.59,
		RainbowMode = false,
		RainbowSpeed = 1750,
		AnimationSpeed = 1,
		GlowSpeed = 1.5,
		SecondaryColor = { R = 30, G = 8, B = 52 },
		FontColor = { R = 238, G = 238, B = 243 },
	}
	if UI.GetThemeState then
		local state = UI.GetThemeState() or {}
		local palette = state.Palette or {}
		return {
			H = palette.H or defaults.H,
			S = palette.S or defaults.S,
			V = palette.V or defaults.V,
			RainbowMode = state.RainbowMode == true,
			RainbowSpeed = state.RainbowSpeed or defaults.RainbowSpeed,
			AnimationSpeed = state.AnimationSpeed or defaults.AnimationSpeed,
			GlowSpeed = state.GlowSpeed or defaults.GlowSpeed,
			SecondaryColor = state.SecondaryColor or defaults.SecondaryColor,
			FontColor = state.FontColor or defaults.FontColor,
		}
	end
	return defaults
end

local function setGuiPalette(palette)
	if UI.SetPalette then
		UI.SetPalette(palette)
	elseif UI.kit and UI.kit.writePalette then
		UI.kit:writePalette(palette)
	end
end

local function forceUiRedraw()
    for _, object in pairs(UI.Registry or {}) do
        if object.Instance then
            if object.UpdateColor then
                pcall(object.UpdateColor)
            end

            local color = UI.kit:activeColor()
            if object.Instance:IsA("Frame") or object.Instance:IsA("TextButton") then
                object.Instance.BackgroundColor3 = color
            elseif object.Instance:IsA("TextLabel") then
                object.Instance.TextColor3 = color
            end

            if object.Options and type(object.Options) == "table" then
                for _, option in pairs(object.Options) do
                    if option.Background then
                        option.Background.BackgroundColor3 = color
                    end
                    if option.TextLabel then
                        option.TextLabel.TextColor3 = color
                    end
                end
            end
        end
    end
end

local function updateGuiPalette(key, value)
    local theme = readGuiTheme()
    theme[key] = value
    setGuiPalette({ H = theme.H, S = theme.S, V = theme.V })

    if UI.PaletteSync then
        UI.PaletteSync:Emit()
    end
    forceUiRedraw()
end

local lastNonRainbowPalette = nil
local function saveCurrentPaletteAsNormal()
    if UI.GetThemeState then
        local state = UI.GetThemeState() or {}
        local palette = state.Palette or {}
        lastNonRainbowPalette = {H = palette.H or 0.73, S = palette.S or 0.77, V = palette.V or 0.59,}
    end
end

local function setGuiRainbowMode(enabled)
    enabled = enabled == true

    if UI.SetRainbowMode then
        UI.SetRainbowMode(enabled)
        
        if not enabled and lastNonRainbowPalette then
            setGuiPalette(lastNonRainbowPalette)
        end
        return
    end

    UI.RainbowMode = enabled

    if not enabled and lastNonRainbowPalette then
        setGuiPalette(lastNonRainbowPalette)
    end

    if UI.PaletteSync then
        UI.PaletteSync:Emit()
    end
end

local function setGuiRainbowSpeed(speed)
	local value = math.max(250, math.floor(tonumber(speed) or 1750))
	if UI.SetRainbowSpeed then
		UI.SetRainbowSpeed(value)
		return
	end
	UI.RainbowSpeed = value
	if UI.PaletteSync then
		UI.PaletteSync:Emit()
	end
end

local function setGuiSecondaryColor(color)
	if UI.SetSecondaryColor then
		UI.SetSecondaryColor(color)
	end
end

local function setGuiFontColor(color)
	if UI.SetFontColor then
		UI.SetFontColor(color)
	end
end

local function setGuiAnimationSpeed(speed)
	if UI.SetAnimationSpeed then
		UI.SetAnimationSpeed(speed)
	end
end

local function setGuiGlowSpeed(speed)
	if UI.SetGlowSpeed then
		UI.SetGlowSpeed(speed)
	end
end

local function bindGuiTheme(callback)
	task.spawn(function()
		local deadline = os.clock() + 5
		while not uiFullyReady and os.clock() < deadline do
			task.wait(0.05)
		end
		if not uiFullyReady then
			logger:Warn("bindGuiTheme: timed out waiting for uiFullyReady; proceeding")
			uiFullyReady = true
		end
		local ok, err = pcall(callback)
		if not ok then
			logger:Warn("bindGuiTheme: callback error", err)
		end
		if UI.PaletteSync then
			rootManager:AddConnection(UI.PaletteSync:Bind(callback))
		end
	end)
end

local categoryIconMap = {
	internal = "other",
	movement = "blatant",
	network = "misc",
	inventory = "inventory",
	combat = "combat",
	build = "world",
	utility = "utillity",
	visuals = "render",
}

local tabs = UI.CreateDefaultTabs({
	ShowIcons = false,
	IconResolver = function(name)
		return getIcon(categoryIconMap[name] or name)
	end,
	Order = {
		{ Name = "internal", Title = "Internal", Aliases = { "other", "settings", "config" } },
		{ Name = "combat", Title = "Combat" },
		{ Name = "movement", Title = "Movement", Aliases = { "blatant" } },
		{ Name = "visuals", Title = "Visuals", Aliases = { "render" } },
		{ Name = "utility", Title = "Utility", Aliases = { "utillity" } },
		{ Name = "build", Title = "Build", Aliases = { "world" } },
		{ Name = "network", Title = "Network", Aliases = { "misc" } },
		{ Name = "inventory", Title = "Inventory" },
	},
})

if UI.CreateArrayListWidget then
	arrayListWidget = UI.CreateArrayListWidget({
		Name = "array list",
		Scale = tonumber(overlayState["arraylist scale"]) or 1,
		WatermarkVisible = readOverlayToggleState("arraylist watermark", true),
		LinesVisible = readOverlayToggleState("arraylist lines", true),
	})
	if arrayListWidget.SetVisible then
		arrayListWidget.SetVisible(readOverlayToggleState("show arraylist", false))
	end
end

if UI.CreateHudConfig then
	hudEditor = UI.CreateHudConfig({
		Name = "settings hub",
		StateFile = fileApi:Resolve(overlayStatePath),
	})
	if hudEditor and hudEditor.CaptureDefaultPosition then
		hudEditor.CaptureDefaultPosition()
	end
	if hudEditor.AddSectionHeader then
		hudEditor.AddSectionHeader("Gui Colors")
	end
	if hudEditor.AddToggleRow then
		hudEditor.AddToggleRow("rainbow gui", false, function(on)
			if on then
				saveCurrentPaletteAsNormal()
			end
			setGuiRainbowMode(on)
		end)
	end
	if hudEditor.AddSliderRow then
		hudEditor.AddSliderRow("rainbow speed", 250, 4000, 1750, 0, function(value)
			setGuiRainbowSpeed(value)
		end)
		hudEditor.AddSliderRow("gui hue", 0, 360, 216, 0, function(value)
			updateGuiPalette("H", math.clamp(value / 360, 0, 1))
		end)
		hudEditor.AddSliderRow("gui saturation", 0, 100, 79, 0, function(value)
			updateGuiPalette("S", math.clamp(value / 100, 0, 1))
		end)
		hudEditor.AddSliderRow("gui brightness", 0, 100, 91, 0, function(value)
			updateGuiPalette("V", math.clamp(value / 100, 0, 1))
		end)
	end
	if hudEditor.AddSectionHeader then
		hudEditor.AddSectionHeader("Visibility")
	end
	if hudEditor.AddSectionHeader then
		hudEditor.AddSectionHeader("HUD")
	end
	if arrayListWidget and hudEditor.AddSectionHeader then
		hudEditor.AddSectionHeader("Overlay")
	end
	if UI.IsMobile and hudEditor.AddSectionHeader then
		hudEditor.AddSectionHeader("Mobile Buttons")
	end
	if UI.IsMobile and hudEditor.AddToggleRow then
		local mobileButtonStyle = UI.GetMobileButtonStyle and UI.GetMobileButtonStyle() or {
			Circle = false,
			Outline = true,
		}
		hudEditor.AddToggleRow("mobile button circle", mobileButtonStyle.Circle == true, function(on)
			if UI.SetMobileButtonStyle then
				UI.SetMobileButtonStyle({ Circle = on })
			end
		end)
		hudEditor.AddToggleRow("mobile button outline", mobileButtonStyle.Outline ~= false, function(on)
			if UI.SetMobileButtonStyle then
				UI.SetMobileButtonStyle({ Outline = on })
			end
		end)
	end
	if arrayListWidget and hudEditor.AddToggleRow then
		hudEditor.AddToggleRow("show arraylist", false, function(on)
			if arrayListWidget.SetVisible then
				arrayListWidget.SetVisible(on)
			end
		end)
	end
	if arrayListWidget and arrayListWidget.SetScale and hudEditor.AddSliderRow then
		hudEditor.AddSliderRow("arraylist scale", 0.5, 2, 1, 1, function(value)
			arrayListWidget.SetScale(value)
		end)
	end
	if arrayListWidget and arrayListWidget.SetWatermarkVisible and hudEditor.AddToggleRow then
		hudEditor.AddToggleRow("arraylist watermark", true, function(on)
			arrayListWidget.SetWatermarkVisible(on)
		end)
	end
	if arrayListWidget and arrayListWidget.SetLinesVisible and hudEditor.AddToggleRow then
		hudEditor.AddToggleRow("arraylist lines", true, function(on)
			arrayListWidget.SetLinesVisible(on)
		end)
	end
end

if UI.CreateConfigBar and hudEditor then
	configBar = UI.CreateConfigBar(hudEditor)
	if configBar and configBar.CaptureDefaultPosition then
		configBar.CaptureDefaultPosition()
	end
	if configBar and configBar.SetVisible then
		configBar.SetVisible(readOverlayToggleState("show preset bar", false))
	elseif configBar and configBar.Instance then
		local ok = pcall(function()
			configBar.Instance.Visible = readOverlayToggleState("show preset bar", false)
		end)
		if not ok then
			logger:Warn("configBar.Instance.Visible could not be set during init")
		end
	end
end

if UI.CreateCustomWindow then
	watermarkWindow = UI.CreateCustomWindow({ Name = "watermark" })
	sessionInfoWindow = UI.CreateCustomWindow({ Name = "session info" })
	watermarkWindow.SetVisible(readOverlayToggleState("watermark", false))
	sessionInfoWindow.SetVisible(readOverlayToggleState("session info", false))

	task.defer(function()
		local cam = workspace.CurrentCamera
		local vp  = cam and cam.ViewportSize or Vector2.new(1920, 1080)
		local padX = math.max(10, math.floor(vp.X * 0.012))
		local padY = math.max(8,  math.floor(vp.Y * 0.012))
		local gap  = math.max(20, math.floor(vp.Y * 0.1))
		local storedFloatingLayout = UI.FloatingLayout or {}
		if watermarkWindow.Instance and not storedFloatingLayout["watermarkFloater"] then
			watermarkWindow.Instance.AnchorPoint = Vector2.new(0, 0)
			watermarkWindow.Instance.Position    = UDim2.new(0, padX, 0, padY)
			if watermarkWindow.CaptureDefaultPosition then
				watermarkWindow.CaptureDefaultPosition()
			end
		end
		if sessionInfoWindow.Instance and not storedFloatingLayout["session infoFloater"] then
			sessionInfoWindow.Instance.AnchorPoint = Vector2.new(0, 0)
			sessionInfoWindow.Instance.Position    = UDim2.new(0, padX, 0, padY + gap)
			if sessionInfoWindow.CaptureDefaultPosition then
				sessionInfoWindow.CaptureDefaultPosition()
			end
		end
	end)

	do
		local frame = watermarkWindow.new("Frame")
		frame.BackgroundColor3 = Color3.fromRGB(17, 17, 19)
		frame.BorderSizePixel = 0
		frame.Size = UDim2.new(0, 168, 0, 24)
		frame.ZIndex = 10

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 12)
		corner.Parent = frame

		local stroke = Instance.new("UIStroke")
		stroke.Transparency = 0.55
		stroke.Thickness = 1
		stroke.Parent = frame

		local accent = Instance.new("Frame")
		accent.Parent = frame
		accent.BackgroundColor3 = UI.kit:activeColor()
		accent.BorderSizePixel = 0
		accent.Position = UDim2.new(0, 8, 0.5, -6)
		accent.Size = UDim2.new(0, 3, 0, 12)
		local accentCorner = Instance.new("UICorner")
		accentCorner.CornerRadius = UDim.new(1, 0)
		accentCorner.Parent = accent

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Parent = frame
		nameLabel.BackgroundTransparency = 1
		nameLabel.Position = UDim2.new(0, 18, 0.5, -7)
		nameLabel.Size = UDim2.new(0, 62, 0, 14)
		nameLabel.Font = Enum.Font.GothamBold
		nameLabel.Text = tostring(versionData.name or "Phantom")
		nameLabel.TextColor3 = Color3.fromRGB(190, 190, 205)
		nameLabel.TextSize = 11
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left

		local versionLabel = Instance.new("TextLabel")
		versionLabel.Parent = frame
		versionLabel.BackgroundTransparency = 1
		versionLabel.Position = UDim2.new(0, 76, 0.5, -7)
		versionLabel.Size = UDim2.new(0, 38, 0, 14)
		versionLabel.Font = Enum.Font.Gotham
		versionLabel.Text = tostring(versionData.base)
		versionLabel.TextColor3 = Color3.fromRGB(95, 95, 140)
		versionLabel.TextSize = 11
		versionLabel.TextXAlignment = Enum.TextXAlignment.Left

		local badge = Instance.new("Frame")
		badge.Parent = frame
		badge.BackgroundColor3 = UI.kit:activeColor()
		badge.BackgroundTransparency = 0.85
		badge.BorderSizePixel = 0
		badge.Position = UDim2.new(0, 116, 0.5, -7)
		badge.Size = UDim2.new(0, 44, 0, 14)
		badge.ZIndex = 11

		local badgeCorner = Instance.new("UICorner")
		badgeCorner.CornerRadius = UDim.new(0, 3)
		badgeCorner.Parent = badge

		local badgeStroke = Instance.new("UIStroke")
		badgeStroke.Transparency = 0.7
		badgeStroke.Thickness = 1
		badgeStroke.Parent = badge

		local releaseLabel = Instance.new("TextLabel")
		releaseLabel.Parent = badge
		releaseLabel.BackgroundTransparency = 1
		releaseLabel.Size = UDim2.new(1, 0, 1, 0)
		releaseLabel.Font = Enum.Font.Gotham
		releaseLabel.Text = "v" .. (tostring(versionData.releaseTag or ""):match("build(%d+)") or "0")
		releaseLabel.TextColor3 = Color3.fromRGB(170, 150, 255)
		releaseLabel.TextSize = 9
		releaseLabel.ZIndex = 12

		bindGuiTheme(function()
			local color = UI.kit:activeColor()
			stroke.Color = color
			badgeStroke.Color = color
			accent.BackgroundColor3 = color
			badge.BackgroundColor3 = color
		end)
	end

	do
		local frame = sessionInfoWindow.new("Frame")
		frame.BackgroundColor3 = Color3.fromRGB(17, 17, 19)
		frame.BorderSizePixel = 0
		frame.Size = UDim2.new(0, 180, 0, 92)

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 10)
		corner.Parent = frame

		local stroke = Instance.new("UIStroke")
		stroke.Transparency = 0.55
		stroke.Thickness = 1
		stroke.Parent = frame

		local title = Instance.new("TextLabel")
		title.Parent = frame
		title.BackgroundTransparency = 1
		title.Position = UDim2.new(0, 10, 0, 6)
		title.Size = UDim2.new(1, -20, 0, 14)
		title.Font = Enum.Font.GothamBold
		title.Text = "Session Info"
		title.TextColor3 = Color3.fromRGB(200, 200, 215)
		title.TextSize = 11
		title.TextXAlignment = Enum.TextXAlignment.Left

		local divider = Instance.new("Frame")
		divider.Parent = frame
		divider.BackgroundColor3 = Color3.fromRGB(40, 42, 58)
		divider.BorderSizePixel = 0
		divider.Position = UDim2.new(0, 10, 0, 24)
		divider.Size = UDim2.new(1, -20, 0, 1)

		local function makeRow(index, name)
			local label = Instance.new("TextLabel")
			label.Parent = frame
			label.BackgroundTransparency = 1
			label.Position = UDim2.new(0, 10, 0, 28 + ((index - 1) * 15))
			label.Size = UDim2.new(0, 70, 0, 14)
			label.Font = Enum.Font.GothamSemibold
			label.Text = name
			label.TextColor3 = Color3.fromRGB(132, 136, 154)
			label.TextSize = 10
			label.TextXAlignment = Enum.TextXAlignment.Left

			local value = Instance.new("TextLabel")
			value.Parent = frame
			value.BackgroundTransparency = 1
			value.Position = UDim2.new(0, 82, 0, 28 + ((index - 1) * 15))
			value.Size = UDim2.new(1, -92, 0, 14)
			value.Font = Enum.Font.Gotham
			value.Text = "-"
			value.TextColor3 = Color3.fromRGB(205, 208, 220)
			value.TextSize = 10
			value.TextXAlignment = Enum.TextXAlignment.Right
			return value
		end

		local uptimeValue = makeRow(1, "Session")
		local pingValue = makeRow(2, "Ping")
		local fpsValue = makeRow(3, "FPS")
		local moduleValue = makeRow(4, "Module")

		bindGuiTheme(function()
			local color = UI.kit:activeColor()
			stroke.Color = color
			divider.BackgroundColor3 = color:Lerp(Color3.fromRGB(17, 17, 19), 0.7)
			moduleValue.TextColor3 = color:Lerp(Color3.fromRGB(255, 255, 255), 0.2)
		end)

		local sessionStarted = os.clock()
		local fpsEstimate = 60
		local fpsSamples = 0
		local elapsed = 0

		local function formatDuration(totalSeconds)
			totalSeconds = math.max(0, math.floor(totalSeconds))
			local hours = math.floor(totalSeconds / 3600)
			local minutes = math.floor((totalSeconds % 3600) / 60)
			local seconds = totalSeconds % 60
			return string.format("%02d:%02d:%02d", hours, minutes, seconds)
		end

		rootManager:AddConnection(Services.RunService.RenderStepped:Connect(function(dt)
			if dt > 0 then
				local instant = 1 / dt
				fpsSamples = math.min(fpsSamples + 1, 30)
				fpsEstimate = fpsEstimate + ((instant - fpsEstimate) / fpsSamples)
			end
		end))

		rootManager:AddConnection(Services.RunService.Heartbeat:Connect(function(dt)
			elapsed = elapsed + dt
			if elapsed < 0.25 then
				return
			end
			elapsed = 0

			local ping = 0
			pcall(function()
				ping = math.floor((LocalPlayer:GetNetworkPing() * 1000) + 0.5)
			end)

			uptimeValue.Text = formatDuration(os.clock() - sessionStarted)
			pingValue.Text = tostring(ping) .. " ms"
			fpsValue.Text = tostring(math.floor(fpsEstimate + 0.5))
			moduleValue.Text = activeModuleLabel()
		end))
	end

	if hudEditor and hudEditor.AddToggleRow then
		hudEditor.AddToggleRow("watermark", false, function(on)
			watermarkWindow.SetVisible(on)
		end)
		hudEditor.AddToggleRow("session info", false, function(on)
			sessionInfoWindow.SetVisible(on)
		end)
	end
end

local entity = {
	player = LocalPlayer,
	character = LocalPlayer.Character,
}

rootManager:AddConnection(LocalPlayer.CharacterAdded:Connect(function(character)
	entity.character = character
end))

rootManager:AddConnection(LocalPlayer.CharacterRemoving:Connect(function(character)
	if entity.character == character then
		entity.character = nil
	end
end))

local render = {}

function render:Toggle(forceState)
	if not UI or not UI.Root then
		return false
	end
	if forceState == nil then
		UI.toggle()
	else
		UI.Root.Visible = forceState == true
	end
	return UI.Root.Visible
end

function render:Toast(options)
	options = options or {}
	if UI and UI.toast then
		return UI.toast(options.title, options.text, options.duration, options.highlight)
	end
end

function render:Add(definition)
	definition = definition or {}
	local panel = tabs[definition.panel or "other"] or tabs.other
	if not panel or not panel.AddNew then
		error("[phantom] invalid render panel: " .. tostring(definition.panel))
	end

	if definition.type == "toggle" then
		local module = panel.AddNew({
			Name = definition.name,
			Beta = definition.beta,
			New = definition.new,
			Bind = definition.bind,
			Function = definition.callback,
		})
		if definition.default and module.SetEnabled then
			module.SetEnabled(true, true, true)
		end
		return module
	end

	if definition.type == "button" then
		local action
		action = panel.AddNew({
			Name = definition.name,
			Beta = definition.beta,
			New = definition.new,
			Bind = definition.bind,
			Function = function(enabled)
				if not enabled then
					return
				end
				if type(definition.callback) == "function" then
					definition.callback()
				end
				if action and action.SetEnabled then
					action.SetEnabled(false, true, true)
				end
			end,
		})
		return action
	end

	if definition.parent and definition.type == "slider" and definition.parent.CreateSlider then
		return definition.parent.CreateSlider({
			Name = definition.name,
			Min = definition.min,
			Max = definition.max,
			Default = definition.default,
			Round = definition.round,
			Function = definition.callback,
		})
	end

	if definition.parent and definition.type == "dropdown" and definition.parent.CreateDropdown then
		return definition.parent.CreateDropdown({
			Name = definition.name,
			List = definition.list,
			Default = definition.default,
			Function = definition.callback,
		})
	end

	error("[phantom] legacy render facade requires a parent for " .. tostring(definition.type))
end

function render:Destroy()
	if UI and UI.Screen then
		UI.Screen:Destroy()
	end
end

local phantom = {
	version = versionData,
	services = Services,
	logger = logger,
	file = fileApi,
	manager = rootManager,
	module = moduleLoader,
	config = config,
	discord = discord,
	updater = updater,
	render = render,
	runtime = runtime.runtime,
	UI = UI,
	developerMode = effectiveDeveloperMode,
	entity = entity,
	loader = {
		ReadScript = function(_, path)
			return fileApi:Read(path)
		end,
		GetIcon = function(_, name)
			return getIcon(name)
		end,
	},
	executor = env.phantomExecutor,
}

local ops = { runtime = runtime.runtime }

function ops:placeKey()
	return activeGameKey()
end

function ops:exec(code)
	return runtime:Run(code)
end

function ops:placeScript()
	if creatorScriptExists() then
		return gameLoader:ReadBundle(gameScripts and gameScripts.creator)
	end
	return gameLoader:ReadBundle(gameScripts and gameScripts.primary)
end

function ops:creatorScript()
	return gameLoader:ReadBundle(gameScripts and gameScripts.creator)
end

function ops:universalScript()
	return gameLoader:ReadBundle(gameScripts and gameScripts.universal)
end

function ops:onExit(id, callback)
	runtime:OnExit(id, callback)
end

function ops:offExit(id)
	runtime:OffExit(id)
end

function ops:track(value)
	return rootManager:Add(value)
end

function ops:lookup(name, prop, value)
	for key, object in next, UI.Registry do
		if key == name and object[prop] == value then
			return object
		end
	end
end

local function safeGet(object, key)
	if type(object) ~= "table" then return nil end
	local ok, val = pcall(function() return object[key] end)
	return ok and val or nil
end

local function safeCall(object, method, ...)
	if type(object) ~= "table" then return end
	local fn = object[method]
	if type(fn) ~= "function" then return end
	local ok, err = pcall(fn, object, ...)
	if not ok then
		logger:Warn("safeCall", method, err)
	end
end

local function safeSetVisible(instance, state)
	if typeof(instance) ~= "Instance" then return end
	pcall(function()
		if instance.Parent ~= nil then
			instance.Visible = state == true
		end
	end)
end

local function copyWithoutRuntimeValues(value)
	if type(value) ~= "table" then
		return value
	end
	local clone = {}
	for key, child in pairs(value) do
		local childType = typeof(child)
		if childType ~= "Instance" and childType ~= "RBXScriptConnection" then
			clone[key] = copyWithoutRuntimeValues(child)
		end
	end
	return clone
end

local function packUDim2(position)
	if typeof(position) ~= "UDim2" then
		return nil
	end

	return {
		X = {
			Scale = position.X.Scale,
			Offset = position.X.Offset,
		},
		Y = {
			Scale = position.Y.Scale,
			Offset = position.Y.Offset,
		},
	}
end

local function unpackUDim2(position)
	if type(position) ~= "table" then
		return nil
	end

	local x = position.X
	local y = position.Y
	if type(x) ~= "table" or type(y) ~= "table" then
		return nil
	end

	return UDim2.new(
		tonumber(x.Scale) or 0,
		tonumber(x.Offset) or 0,
		tonumber(y.Scale) or 0,
		tonumber(y.Offset) or 0
	)
end

local function getConfigBaseFolder()
	return activeGameKey()
end

if hudEditor.SetDir then
	hudEditor.SetDir(fileApi:Resolve("configs/" .. getConfigBaseFolder()))
end

local function statePath(slot)
	local base = getConfigBaseFolder()
	return string.format("configs/%s/%s.json", base, slot or "default")
end

local function setProfileSlot(slot)
	profileSlot = tostring(slot or "default")
	if configBar and configBar.SetName then
		configBar.SetName(profileSlot)
	end
	return profileSlot
end

local function shouldPersistObject(object)
	return not (object and object.args and object.args.NoSave == true)
end

local function saveProfile(slot)
	slot = setProfileSlot(slot or profileSlot)
	if UI.saveTabPositions then
		UI.saveTabPositions()
	end
	local data = {}

	for name, object in next, UI.Registry do
		if shouldPersistObject(object) and object.Type == "OptionsButton" then
			local api = safeGet(object, "API")
			if api then
				data[name] = {
					Enabled = safeGet(api, "Enabled"),
					Bind = safeGet(api, "Bind"),
					Type = object.Type,
					Window = object.Window,
				}
			end
		elseif shouldPersistObject(object) and object.Type == "Toggle" then
			local api = safeGet(object, "API")
			if api then
				data[name] = {
					Enabled = safeGet(api, "Enabled"),
					Type = object.Type,
					OptionsButton = object.OptionsButton,
					CustomWindow = object.CustomWindow,
				}
			end
		elseif shouldPersistObject(object) and object.Type == "Slider" then
			local api = safeGet(object, "API")
			if api then
				data[name] = {
					Value = safeGet(api, "Value"),
					Type = object.Type,
					OptionsButton = object.OptionsButton,
					CustomWindow = object.CustomWindow,
				}
			end
		elseif shouldPersistObject(object) and object.Type == "Dropdown" then
			local api = safeGet(object, "API")
			if api then
				data[name] = {
					Value = safeGet(api, "Value"),
					Type = object.Type,
					OptionsButton = object.OptionsButton,
					CustomWindow = object.CustomWindow,
				}
			end
		elseif shouldPersistObject(object) and object.Type == "Textbox" then
			local api = safeGet(object, "API")
			if api then
				data[name] = {
					Value = safeGet(api, "Value"),
					Type = object.Type,
					OptionsButton = object.OptionsButton,
					CustomWindow = object.CustomWindow,
				}
			end
		elseif shouldPersistObject(object) and object.Type == "MultiDropdown" then
			local api = safeGet(object, "API")
			if api then
				data[name] = {
					Values = copyWithoutRuntimeValues(safeGet(api, "Values")),
					Type = object.Type,
					OptionsButton = object.OptionsButton,
					CustomWindow = object.CustomWindow,
				}
			end
		elseif shouldPersistObject(object) and object.Type == "Textlist" then
			local api = safeGet(object, "API")
			if api then
				data[name] = {
					Values = copyWithoutRuntimeValues(safeGet(api, "Values")),
					Type = object.Type,
					OptionsButton = object.OptionsButton,
					CustomWindow = object.CustomWindow,
				}
			end
		elseif shouldPersistObject(object) and object.Type == "CustomWindow" and object.Instance then
			local packed = packUDim2(object.Instance.Position)
			if packed then
				data[name] = {
					Type = object.Type,
					Position = packed,
				}
			end
		end
	end

	local existing = fileApi:ReadJson(statePath(slot), {})
	for k, v in pairs(data) do
		existing[k] = v
	end
	local ok, err = fileApi:WriteJson(statePath(slot), existing, { force = true })
	if not ok then
		logger:Warn("failed to save profile", slot, err)
	end
	return existing
end

local function loadProfile(slot, silent)
	if not env.phantom then
		return {}
	end

	if not uiFullyReady then
		logger:Warn("loadProfile called before UI was fully ready – skipping")
		return {}
	end

	slot = setProfileSlot(slot or profileSlot)
	env.configloaded = false

	local data = fileApi:ReadJson(statePath(slot), nil)
	if type(data) ~= "table" then
		env.configloaded = true
		return {}
	end

	local staleKeys = {}
	local customWindowLayoutChanged = false

	for name, state in next, data do
		if type(state) ~= "table" then
			staleKeys[#staleKeys + 1] = name
			continue
		end

		local prop = state.Type == "OptionsButton" and "Window" or (state.CustomWindow and "CustomWindow" or "OptionsButton")

		local object = ops:lookup(name, prop, state[prop])

		if not object then
			continue
		end

		if not shouldPersistObject(object) then
			staleKeys[#staleKeys + 1] = name
			continue
		end

		local api = safeGet(object, "API")
		if not api then
			continue
		end

		local ok, err = pcall(function()
			if state.Type == "OptionsButton" then
				if state.Bind and state.Bind ~= "" then
					if type(api.SetBind) == "function" then
						api.SetBind(state.Bind)
					end
				end
				local currentEnabled = safeGet(api, "Enabled")
				if state.Enabled ~= nil and state.Enabled ~= currentEnabled then
					if type(api.Toggle) == "function" then
						api.Toggle()
					end
				end

			elseif state.Type == "Toggle" then
				local currentEnabled = safeGet(api, "Enabled")
				if state.Enabled ~= nil and state.Enabled ~= currentEnabled then
					if type(api.Toggle) == "function" then
						api.Toggle(true)
					end
				end

			elseif state.Type == "Slider" then
				if state.Value ~= nil and type(api.Set) == "function" then
					api.Set(state.Value, true)
				end

			elseif state.Type == "Dropdown" then
				if state.Value ~= nil and type(api.SetValue) == "function" then
					api.SetValue(state.Value)
				end

			elseif state.Type == "Textbox" then
				if state.Value ~= nil and type(api.Set) == "function" then
					api.Set(state.Value)
				end

			elseif state.Type == "MultiDropdown" then
				if type(state.Values) == "table" and type(api.ToggleValue) == "function" then
					for _, valueState in next, state.Values do
						if type(valueState) == "table" and valueState.Enabled then
							api.ToggleValue(valueState.Value)
						end
					end
				end

			elseif state.Type == "Textlist" then
				if type(state.Values) == "table" and type(api.Add) == "function" then
					for _, value in next, state.Values do
						api.Add(value)
					end
				end

			elseif state.Type == "CustomWindow" then
				local position = unpackUDim2(state.Position)
				if position and object.Instance then
					object.Instance.Position = position
					if type(api.NormalizePosition) == "function" then
						api.NormalizePosition()
					end
					customWindowLayoutChanged = true
				else
					staleKeys[#staleKeys + 1] = name
				end
			end
		end)

		if not ok then
			logger:Warn("loadProfile: error restoring", name, err)
		end
	end

	if #staleKeys > 0 then
		for _, key in ipairs(staleKeys) do
			data[key] = nil
		end
		local ok, err = fileApi:WriteJson(statePath(slot), data, { force = true })
		if not ok then
			logger:Warn("failed to clean profile", slot, err)
		end
	end

	if customWindowLayoutChanged and UI.SaveLayout then
		UI.SaveLayout()
	end

	env.configloaded = true

	if not silent then
		render:Toast({
			title = "Profile",
			text = "Loaded " .. slot .. ".json for " .. placeId,
			duration = 3,
		})
	end
	return data
end

local function scheduleLoadProfile(slot, silent)
	task.spawn(function()
		local deadline = os.clock() + 10
		while not uiFullyReady and os.clock() < deadline do
			task.wait(0.05)
		end
		if not uiFullyReady then
			logger:Warn("scheduleLoadProfile: timed out waiting for uiFullyReady; loading anyway")
			uiFullyReady = true
		end
		loadProfile(slot, silent)
	end)
end

function ops:saveConfig(slot)
	return saveProfile(slot)
end

function ops:loadConfig(slot)
	return loadProfile(slot)
end

phantom.ops = ops
phantom.funcs = ops
env.phantom = phantom
env.phantomInstances = env.phantomInstances or {}
table.insert(env.phantomInstances, phantom)
env.configloaded = false

rootManager:AddConnection(Services.Players.PlayerRemoving:Connect(function(player)
	if player == LocalPlayer then
		pcall(saveProfile, profileSlot)
	end
end))

moduleLoader:RegisterPath("prediction", "lib/Prediction.lua", { cache = true })
moduleLoader:RegisterPath("fly", "lib/fly.lua", { cache = true })
moduleLoader:RegisterPath("patcher", "lib/patcher.lua", { cache = false, hotReload = true })
moduleLoader:RegisterPath("utility", "src/framework/utils/utility.lua", { cache = true })

rootManager:AddConnection(customSignal.Event:Connect(function()
	if queueTeleport and not env.phantomTeleportQueued then
		env.phantomTeleportQueued = true
		
		local teleportPayload = [[
			local TARGET_GAME_ID = "]] .. gameId .. [["
			
			repeat task.wait() until game:IsLoaded()

			local currentId = tostring(game.GameId)

			if currentId == TARGET_GAME_ID then
				if isfile and isfile("Phantom/loader.lua") then
					loadstring(readfile("Phantom/loader.lua"))()
				end
			end
		]]

		pcall(queueTeleport, teleportPayload)
	end
end))

customSignal:Fire()

local patcherInfo
pcall(function()
	patcherInfo = moduleLoader:Load("patcher")
end)

if type(patcherInfo) == "table" then
	env.phantomExecutorInfo = patcherInfo
	env.phantomMissingMainFunctions = patcherInfo.missingMainLookup or {}
	env.phantomIsBadExecutor = patcherInfo.executorLevel ~= "HIGH"
end

if shouldAutoEnableHideBadExecutorModules() then
	setHideBadExecutorModules(true)
end
syncExecutorContextFromEnv()

local shuttingDown = false
local hotReloadQueued = false
local relaunchNonce = 0

local function shutdown(reason, options)
	options = options or {}
	if options.preserveRelaunch ~= true then
		relaunchNonce = relaunchNonce + 1
	end
	if shuttingDown then
		return
	end
	shuttingDown = true

	pcall(saveProfile, profileSlot)
	pcall(function()
		runtime:Cleanup()
	end)
	pcall(function()
		for _, object in next, UI.Registry do
			local api = safeGet(object, "API")
			if api then
				local objType = safeGet(object, "Type")
				if (objType == "OptionsButton" or objType == "Toggle")
					and safeGet(api, "Enabled")
					and type(safeGet(api, "Function")) == "function" then
					api.Enabled = false
					api.Value = false
					task.spawn(api.Function)
				end
			end
		end
	end)
	pcall(function()
		for _, tracked in pairs(UI.Tracked or UI.Connections or {}) do
			local disconnect = tracked and (tracked.Disconnect or tracked.Unbind)
			if disconnect then
				disconnect(tracked)
			end
		end
	end)
	pcall(function()
		if UI.Screen then
			UI.Screen:Destroy()
		end
	end)
	pcall(function()
		if customSignal and customSignal.Parent then
			customSignal:Destroy()
		end
	end)
	pcall(function()
		rootManager:Cleanup()
	end)

	local isCurrentInstance = env.phantom == phantom
	local instances = env.phantomInstances
	if type(instances) == "table" then
		for index = #instances, 1, -1 do
			if instances[index] == phantom then
				table.remove(instances, index)
			end
		end
		if #instances == 0 then
			env.phantomInstances = nil
		end
	end

	logger:Info("shutdown", reason or "manual")
	if isCurrentInstance then
		env.phantom = nil
		env.configloaded = nil
	end
end

phantom.Shutdown = shutdown

local function relaunchMain()
	local source = fileApi:Read("Main.lua")
	if not source or source == "" then
		logger:Error("Main.lua missing for reload")
		return false
	end
	local chunk, err = loadstring(source, "@Phantom/Main.lua")
	if not chunk then
		logger:Error("failed to compile Main.lua", err)
		return false
	end
	local ok, runtimeError = pcall(chunk)
	if not ok then
		logger:Error("runtime error during reload", runtimeError)
		return false
	end
	return true
end

phantom.HotReload = function()
	if shuttingDown or hotReloadQueued then
		return false
	end
	hotReloadQueued = true
	relaunchNonce = relaunchNonce + 1
	local expectedRelaunchNonce = relaunchNonce
	shutdown("hot-reload", { preserveRelaunch = true })
	task.defer(function()
		if relaunchNonce ~= expectedRelaunchNonce then
			return
		end
		relaunchMain()
	end)
	return true
end

local function formatUpdateResult(result)
	if not result then
		return "Unknown updater result."
	end
	if result.status == "up-to-date" then
		return "Already running " .. tostring(result.manifest and result.manifest.version or versionData.full) .. "."
	end
	if result.status == "outdated" then
		return string.format("%d file(s) need refresh.", #(result.plan and result.plan.toDownload or {}))
	end
	if result.status == "updated" then
		return string.format("Updated %d file(s). Reload to apply.", #(result.updated or {}))
	end
	if result.status == "partial" then
		return string.format("Updated %d file(s), %d failed.", #(result.updated or {}), #(result.failures or {}))
	end
	if result.status == "disabled" then
		return "Auto updater is disabled."
	end
	if result.status == "developer-mode" then
		return "Developer mode is enabled. GitHub updates are blocked."
	end
	if result.status == "blocked-developer" then
		return "Developer mode is enabled and the local runtime is incomplete."
	end
	if result.status == "offline-local" then
		return "GitHub unavailable. Using local runtime."
	end
	if result.status == "incompatible-remote" then
		return "Remote GitHub build is older than the local framework. Using local runtime."
	end
	return tostring(result.error or result.status)
end

local loaderSettings
do
	local function fixMouse()
		if Services.UserInputService.MouseBehavior ~= Enum.MouseBehavior.Default then
			Services.UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		end
	end

	local previousGuiController = env.phantomGuiFallbackController
	if type(previousGuiController) == "table" and type(previousGuiController.Cleanup) == "function" then
		pcall(previousGuiController.Cleanup)
	end

	local guiController = {
		desiredVisible = UI and UI.Root and UI.Root.Visible == true,
		applying = false,
		connections = {},
	}

	local function trackGuiController(connection)
		if not connection then
			return nil
		end
		guiController.connections[#guiController.connections + 1] = connection
		rootManager:AddConnection(connection)
		return connection
	end

	function guiController.Cleanup()
		for index = #guiController.connections, 1, -1 do
			local connection = guiController.connections[index]
			if connection and connection.Disconnect then
				pcall(function() connection:Disconnect() end)
			elseif connection and connection.Unbind then
				pcall(function() connection:Unbind() end)
			end
			guiController.connections[index] = nil
		end
	end

	env.phantomGuiFallbackController = guiController

	local function syncGuiControllerState()
		if loaderSettings and loaderSettings.SetEnabled and hudEditor and hudEditor.Instance then
			local vis = false
			pcall(function() vis = hudEditor.Instance.Visible == true end)
			loaderSettings.SetEnabled(vis, true, true)
		end
	end

	local function setGuiVisible(visible)
		guiController.desiredVisible = visible == true

		local function attemptApply()
			if not UI or not UI.Root then
				return false
			end
			local currentVisible = UI.Root.Visible == true
			if currentVisible == guiController.desiredVisible then
				syncGuiControllerState()
				return true
			end
			if guiController.applying then
				return false
			end
			guiController.applying = true
			if guiController.desiredVisible then
				fixMouse()
			end
			local ok = pcall(function()
				if UI.SetVisible then
					UI.SetVisible(guiController.desiredVisible)
				elseif UI.Root.Visible ~= guiController.desiredVisible and UI.toggle then
					UI.toggle()
				end
			end)
			guiController.applying = false
			if ok and UI.Root then
				guiController.desiredVisible = UI.Root.Visible == true
			end
			syncGuiControllerState()
			return ok and UI.Root and UI.Root.Visible == visible
		end

		if attemptApply() then
			return true
		end
		task.defer(function()
			attemptApply()
			task.delay(0.1, attemptApply)
		end)
		return false
	end

	local function toggleLegacyGui()
		local currentlyVisible = UI and UI.Root and UI.Root.Visible == true
		return setGuiVisible(not currentlyVisible)
	end

	local function setCoreGuiVisible(coreGuiType, enabled)
		if not Services.StarterGui or not Services.StarterGui.SetCoreGuiEnabled then
			return false
		end
		local ok = pcall(function()
			Services.StarterGui:SetCoreGuiEnabled(coreGuiType, enabled == true)
		end)
		return ok
	end

	local function syncTeamAwareControls(enabled)
		for _, object in next, UI.Objects or {} do
			if object.Type == "Toggle" then
				local api = safeGet(object, "API")
				if api and type(api.SetEnabled) == "function" then
					local name = string.lower(tostring(safeGet(object, "Name") or ""))
					if name:find("team") or name:find("friendmode") or name:find("friend") then
						api.SetEnabled(enabled == true, true)
					end
				end
			end
		end
		
		for _, object in next, UI.Registry or {} do
			local api = safeGet(object, "API")
			if api and type(api.SetEnabled) == "function" then
				local name = string.lower(tostring(safeGet(object, "Name") or ""))
				if name:find("team") or name:find("friendmode") or name:find("friend") then
					pcall(api.SetEnabled, enabled == true, true)
				end
			end
		end
		
		if type(env.phantomTeamSyncEnabled) ~= "boolean" then
			env.phantomTeamSyncEnabled = enabled == true
		end
	end

	local primaryPresets = {
		Violet  = Color3.fromRGB(86, 34, 150),
		Cobalt  = Color3.fromRGB(54, 92, 176),
		Crimson = Color3.fromRGB(155, 42, 68),
		Emerald = Color3.fromRGB(44, 126, 96),
		Amber   = Color3.fromRGB(171, 104, 36),
	}
	local secondaryPresets = {
		Night  = Color3.fromRGB(30, 8, 52),
		Ink    = Color3.fromRGB(16, 8, 28),
		Ruby   = Color3.fromRGB(64, 14, 30),
		Forest = Color3.fromRGB(20, 42, 31),
		Steel  = Color3.fromRGB(24, 28, 40),
	}
	local fontPresets = {
		Silver = Color3.fromRGB(238, 238, 243),
		Ice    = Color3.fromRGB(214, 226, 255),
		Sand   = Color3.fromRGB(242, 227, 204),
		Mint   = Color3.fromRGB(214, 244, 228),
	}

	local keybindWindow
	local keybindList

	local function refreshKeybindWindow()
		if not keybindList then
			return
		end
		for _, child in ipairs(keybindList:GetChildren()) do
			if not child:IsA("UIListLayout") then
				child:Destroy()
			end
		end

		local bindings = {}
		for _, object in next, UI.Registry do
			local api = safeGet(object, "API")
			if object.Type == "OptionsButton" and api then
				local bind = safeGet(api, "Bind")
				local args = safeGet(object, "args") or {}
				if bind and bind ~= "" and not (args.HideInUI == true) then
					bindings[#bindings + 1] = {
						Name = tostring(args.Name or object.Name or "module"),
						Bind = tostring(bind),
					}
				end
			end
		end

		table.sort(bindings, function(a, b)
			if a.Bind == b.Bind then return a.Name < b.Name end
			return a.Bind < b.Bind
		end)

		if #bindings == 0 then
			local empty = Instance.new("TextLabel")
			empty.Parent = keybindList
			empty.BackgroundTransparency = 1
			empty.Size = UDim2.new(1, 0, 0, 16)
			empty.Font = Enum.Font.Gotham
			empty.Text = "No binds assigned"
			empty.TextColor3 = Color3.fromRGB(150, 150, 164)
			empty.TextSize = 10
			empty.TextXAlignment = Enum.TextXAlignment.Left
			return
		end

		for _, binding in ipairs(bindings) do
			local row = Instance.new("Frame")
			row.Parent = keybindList
			row.BackgroundColor3 = Color3.fromRGB(9, 9, 10)
			row.BorderSizePixel = 0
			row.Size = UDim2.new(1, 0, 0, 18)

			local accent = Instance.new("Frame")
			accent.Parent = row
			accent.BackgroundColor3 = UI.kit:activeColor()
			accent.BorderSizePixel = 0
			accent.Position = UDim2.new(0, 0, 0.5, -5)
			accent.Size = UDim2.new(0, 2, 0, 10)

			local bindLabel = Instance.new("TextLabel")
			bindLabel.Parent = row
			bindLabel.BackgroundTransparency = 1
			bindLabel.Position = UDim2.new(0, 8, 0, 0)
			bindLabel.Size = UDim2.new(0, 52, 1, 0)
			bindLabel.Font = Enum.Font.GothamBold
			bindLabel.Text = "[" .. string.upper(binding.Bind) .. "]"
			bindLabel.TextColor3 = Color3.fromRGB(236, 236, 243)
			bindLabel.TextSize = 10
			bindLabel.TextXAlignment = Enum.TextXAlignment.Left

			local nameLabel = Instance.new("TextLabel")
			nameLabel.Parent = row
			nameLabel.BackgroundTransparency = 1
			nameLabel.Position = UDim2.new(0, 62, 0, 0)
			nameLabel.Size = UDim2.new(1, -62, 1, 0)
			nameLabel.Font = Enum.Font.Gotham
			nameLabel.Text = binding.Name
			nameLabel.TextColor3 = Color3.fromRGB(168, 168, 180)
			nameLabel.TextSize = 10
			nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		end
	end

	trackGuiController(Services.UserInputService:GetPropertyChangedSignal("MouseBehavior"):Connect(function()
		if UI.Root and UI.Root.Visible then
			fixMouse()
		end
	end))
	if UI and UI.Root then
		trackGuiController(UI.Root:GetPropertyChangedSignal("Visible"):Connect(function()
			guiController.desiredVisible = UI.Root.Visible == true
			if UI.Root.Visible then
				fixMouse()
			end
			syncGuiControllerState()
		end))
	end

	if UI.CreateCustomWindow then
		keybindWindow = UI.CreateCustomWindow({ Name = "keybinds" })
		keybindWindow.SetVisible(false)
		local storedFloatingLayout = UI.FloatingLayout or {}
		if keybindWindow.Instance and not storedFloatingLayout["keybindsFloater"] then
			keybindWindow.Instance.AnchorPoint = Vector2.new(0, 0)
			keybindWindow.Instance.Position = UDim2.new(0, 22, 0, 140)
		end
		if keybindWindow.CaptureDefaultPosition and not storedFloatingLayout["keybindsFloater"] then
			keybindWindow.CaptureDefaultPosition()
		end

		local frame = keybindWindow.new("Frame")
		frame.BackgroundColor3 = Color3.fromRGB(6, 6, 8)
		frame.BorderSizePixel = 0
		frame.Size = UDim2.new(0, 186, 0, 180)

		local stroke = Instance.new("UIStroke")
		stroke.Parent = frame
		stroke.Transparency = 0.18
		stroke.Thickness = 1

		local headerGlow = Instance.new("Frame")
		headerGlow.Parent = frame
		headerGlow.BackgroundColor3 = UI.kit:activeColor()
		headerGlow.BackgroundTransparency = 0.86
		headerGlow.BorderSizePixel = 0
		headerGlow.Size = UDim2.new(1, 0, 0, 42)
		local headerGlowFade = Instance.new("UIGradient")
		headerGlowFade.Parent = headerGlow
		headerGlowFade.Rotation = 90
		headerGlowFade.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.1),
			NumberSequenceKeypoint.new(1, 1),
		})

		local title = Instance.new("TextLabel")
		title.Parent = frame
		title.BackgroundTransparency = 1
		title.Position = UDim2.new(0, 10, 0, 8)
		title.Size = UDim2.new(1, -20, 0, 14)
		title.Font = Enum.Font.GothamBold
		title.Text = "Keybinds"
		title.TextColor3 = Color3.fromRGB(236, 236, 243)
		title.TextSize = 11
		title.TextXAlignment = Enum.TextXAlignment.Left

		local subtitle = Instance.new("TextLabel")
		subtitle.Parent = frame
		subtitle.BackgroundTransparency = 1
		subtitle.Position = UDim2.new(0, 10, 0, 22)
		subtitle.Size = UDim2.new(1, -20, 0, 12)
		subtitle.Font = Enum.Font.Gotham
		subtitle.Text = "Current module shortcuts"
		subtitle.TextColor3 = Color3.fromRGB(124, 124, 138)
		subtitle.TextSize = 9
		subtitle.TextXAlignment = Enum.TextXAlignment.Left

		local divider = Instance.new("Frame")
		divider.Parent = frame
		divider.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
		divider.BorderSizePixel = 0
		divider.Position = UDim2.new(0, 10, 0, 42)
		divider.Size = UDim2.new(1, -20, 0, 1)

		local scroll = Instance.new("ScrollingFrame")
		scroll.Parent = frame
		scroll.BackgroundTransparency = 1
		scroll.BorderSizePixel = 0
		scroll.Position = UDim2.new(0, 10, 0, 48)
		scroll.Size = UDim2.new(1, -20, 1, -58)
		scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
		scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
		scroll.ScrollBarThickness = 1
		scroll.ScrollBarImageColor3 = Color3.fromRGB(96, 96, 114)

		keybindList = Instance.new("Frame")
		keybindList.Parent = scroll
		keybindList.BackgroundTransparency = 1
		keybindList.Size = UDim2.new(1, 0, 1, 0)

		local keybindLayout = Instance.new("UIListLayout")
		keybindLayout.Parent = keybindList
		keybindLayout.SortOrder = Enum.SortOrder.LayoutOrder
		keybindLayout.Padding = UDim.new(0, 4)

		bindGuiTheme(function()
			local accent = UI.kit:activeColor()
			stroke.Color = accent
			headerGlow.BackgroundColor3 = accent
		end)

		refreshKeybindWindow()
	end

	if UI.BindSync then
		rootManager:AddConnection(UI.BindSync:Bind(function()
			refreshKeybindWindow()
		end))
	end

	local internalPanel = tabs.internal or tabs.other

	local function createInternalAction(name, callback, tooltip)
		local action
		action = internalPanel.AddNew({
			Name = name,
			NoSave = true,
			Function = function(enabled)
				if not enabled then return end
				local ok, err = pcall(callback)
				if not ok then
					logger:Warn(name, err)
					render:Toast({ title = name, text = tostring(err), duration = 3 })
				end
				if action and action.SetEnabled then
					action.SetEnabled(false, true, true)
				end
			end,
			Tooltip = tooltip,
		})
		return action
	end

	local function setSettingsHubVisible(on)
		if hudEditor and hudEditor.Show and hudEditor.Hide then
			if on == true then hudEditor.Show() else hudEditor.Hide() end
		elseif hudEditor and hudEditor.Instance then
			pcall(function() hudEditor.Instance.Visible = on == true end)
		end
	end

	local function setPresetBarVisible(on)
		if configBar and configBar.SetVisible then
			configBar.SetVisible(on)
		elseif configBar and configBar.Instance then
			pcall(function() configBar.Instance.Visible = on == true end)
		end
	end

	local keybindsModule = internalPanel.AddNew({
		Name = "Keybind List",
		NoSave = true,
		Function = function(on)
			if keybindWindow then
				if on then refreshKeybindWindow() end
				keybindWindow.SetVisible(on)
			end
		end,
		Tooltip = "Show the active module shortcuts in a floating panel.",
	})

	trackGuiController(Services.UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end
		if UI and UI.IsRecording then return end
		if Services.UserInputService:GetFocusedTextBox() then return end
		if input.KeyCode == Enum.KeyCode.RightShift or input.KeyCode == Enum.KeyCode.LeftAlt then
			toggleLegacyGui()
		end
	end))

	internalPanel.AddNew({
		Name = "Hide Scoreboard",
		NoSave = true,
		Function = function(on)
			setCoreGuiVisible(Enum.CoreGuiType.PlayerList, not on)
		end,
		Tooltip = "Hide the default Roblox player list.",
	})

	local altLoginAction
	altLoginAction = internalPanel.AddNew({
		Name = "Alt Login",
		NoSave = true,
		Function = function(enabled)
			if not enabled then return end
			render:Toast({
				title = "Alt Login",
				text = "Alt login is not available in this legacy runtime build.",
				duration = 3,
			})
			if altLoginAction and altLoginAction.SetEnabled then
				altLoginAction.SetEnabled(false, true, true)
			end
		end,
		Tooltip = "Reserved for multi-account workflows in newer builds.",
	})

	loaderSettings = internalPanel.AddNew({
		Name = "Config Panel",
		NoSave = true,
		NoSearch = true,
		Bind = "Insert",
		ExtraText = function()
			local bind = loaderSettings and loaderSettings.Bind
			local text = (bind and bind ~= "") and string.upper(bind) or "NONE"
			return "[" .. text .. "]"
		end,
		Function = function(on)
			setSettingsHubVisible(on)
		end,
		Tooltip = "Open the main settings, profiles, layout, and UI management controls.",
	})

	if hudEditor and hudEditor.Instance and loaderSettings and loaderSettings.SetEnabled then
		rootManager:AddConnection(hudEditor.Instance:GetPropertyChangedSignal("Visible"):Connect(function()
			local vis = false
			pcall(function() vis = hudEditor.Instance.Visible == true end)
			loaderSettings.SetEnabled(vis, true, true)
		end))
	end

	internalPanel.AddNew({
		Name = "Friend Mode",
		NoSave = true,
		Function = function(on)
			env.phantomFriendPreference = on
		end,
		Tooltip = "Store a friend-safe targeting preference for supported modules.",
	})

	internalPanel.AddNew({
		Name = "Team Sync",
		NoSave = true,
		Function = function(on)
			syncTeamAwareControls(on)
		end,
		Tooltip = "Sync team-aware combat and ESP controls together.",
	})
	createInternalAction("Uninject client", function()
		render:Toast({ title = "Phantom", text = "Uninjecting the current runtime.", duration = 2 })
		shutdown("user")
	end, "Safely rebuild the full UI without leaving the server.")
	createInternalAction("Reinject client", function()
		render:Toast({ title = "Phantom", text = "Reloading the interface runtime...", duration = 2 })
		phantom.HotReload()
	end, "Safely rebuild the full UI without leaving the server.")

	createInternalAction("Reset UI Layout", function()
		if UI.ResetLayout then UI.ResetLayout() end
		render:Toast({ title = "Layout", text = "Restored the default interface layout.", duration = 2 })
	end, "Restore every draggable window to the default layout.")

	local hudModule = internalPanel.AddNew({
		Name = "UI Theme",
		NoSave = true,
		Function = function() end,
		Tooltip = "Open the HUD customization controls.",
	})

	local function applyModuleSearch(searchText)
		local query = string.lower(tostring(searchText or "")):gsub("^%s+", ""):gsub("%s+$", "")
		for _, object in next, UI.Registry do
			local api = safeGet(object, "API")
			if object.Type == "OptionsButton" and api and type(api.SetSearchVisible) == "function" then
				local args = safeGet(object, "args") or {}
				if args.NoSearch ~= true then
					local label = string.lower(tostring(args.Name or object.Name or ""))
					local visible = query == "" or string.find(label, query, 1, true) ~= nil
					api.SetSearchVisible(visible)
				end
			end
		end
	end

	local layoutPresetMap = {
		["Default Layout"]  = "default",
		["Compact Layout"]  = "compact",
	}

	local function currentLayoutPresetLabel()
		local current = UI.GetLayoutPreset and UI.GetLayoutPreset() or "default"
		for label, key in pairs(layoutPresetMap) do
			if key == current then return label end
		end
		return "Default Layout"
	end

	local function applyLayoutPreset(label)
		local presetKey = layoutPresetMap[label] or "default"
		if UI.ApplyLayoutPreset then
			UI.ApplyLayoutPreset(presetKey)
		end
		local camera = workspace.CurrentCamera
		local viewport = camera and camera.ViewportSize or Vector2.new(1920, 1080)
		local padX = math.max(18, math.floor(viewport.X * 0.018))
		local padY = math.max(14, math.floor(viewport.Y * 0.018))
		local stackGap = math.max(26, math.floor(viewport.Y * 0.095))

		local function applyWindowPreset(windowApi, position)
			if not (windowApi and windowApi.Instance and position) then return end
			windowApi.Instance.Position = position
			if windowApi.CaptureDefaultPosition then windowApi.CaptureDefaultPosition() end
			if windowApi.SavePosition then windowApi.SavePosition() end
		end

		local overlayPositions = {
			default  = UDim2.new(0.5, 0, 0.5, 0),
			compact  = UDim2.new(0.68, 0, 0.42, 0),
		}
		local presetBarPositions = {
			default  = UDim2.new(0.5, 0, 0, padY),
			compact  = UDim2.new(0.34, 0, 0, padY),
		}
		local keybindPositions = {
			default  = UDim2.new(0, padX, 0, padY + 132),
			compact  = UDim2.new(0, padX, 0, padY + 106),
		}

		if hudEditor and hudEditor.Instance then
			hudEditor.Instance.Position = overlayPositions[presetKey] or overlayPositions.default
			if hudEditor.CaptureDefaultPosition then hudEditor.CaptureDefaultPosition() end
			if hudEditor.SavePosition then hudEditor.SavePosition() end
		end
		if configBar and configBar.SetDefaultPosition then
			configBar.Instance.Position = presetBarPositions[presetKey] or presetBarPositions.default
			configBar.SetDefaultPosition(configBar.Instance.Position)
			if configBar.Instance.Visible and configBar.SetVisible then
				configBar.SetVisible(true)
			end
		end
		if watermarkWindow then applyWindowPreset(watermarkWindow, UDim2.new(0, padX, 0, padY)) end
		if sessionInfoWindow then applyWindowPreset(sessionInfoWindow, UDim2.new(0, padX, 0, padY + stackGap)) end
		if keybindWindow then
			applyWindowPreset(keybindWindow, keybindPositions[presetKey] or keybindPositions.default)
		end
		if UI.SaveLayout then UI.SaveLayout() end
		render:Toast({ title = "Layout", text = "Applied " .. label .. ".", duration = 2 })
	end

	local function clearOverlayState()
		overlayState = {}
		fileApi:WriteJson(overlayStatePath, overlayState, { force = true })
	end

	if configBar and loaderSettings.CreateToggle then
		loaderSettings.CreateToggle({
			Name = "show preset bar",
			Default = readOverlayToggleState("show preset bar", false),
			Function = function(on) setPresetBarVisible(on) end,
			Tooltip = "Display the small preset bar at the top of the screen.",
		})
	end

	if UI.SetDraggingLocked and loaderSettings.CreateToggle then
		loaderSettings.CreateToggle({
			Name = "lock window dragging",
			Default = false,
			Function = function(on)
				UI.SetDraggingLocked(on)
				render:Toast({
					title = "Layout",
					text = on and "Window dragging locked." or "Window dragging unlocked.",
					duration = 2,
				})
			end,
			Tooltip = "Prevent accidental dragging while you use the menu.",
		})
	end

	if UI.ApplyLayoutPreset and loaderSettings.CreateDropdown then
		loaderSettings.CreateDropdown({
			Name = "layout preset",
			List = { "Default Layout", "Compact Layout"},
			Default = currentLayoutPresetLabel(),
			Function = function(value) applyLayoutPreset(value) end,
			Tooltip = "Instantly reflow the full window layout without touching your module states.",
		})
	end

	if UI.SetScaleMultiplier and loaderSettings.CreateSlider then
		loaderSettings.CreateSlider({
			Name = "ui scale",
			Min = 0.7,
			Max = 1.4,
			Default = UI.GetScaleMultiplier and UI.GetScaleMultiplier() or 1,
			Round = 1,
			Function = function(value) UI.SetScaleMultiplier(value) end,
			Tooltip = "Scale the interface responsively across laptop, desktop, and high-DPI viewports.",
		})
	end

	local moduleSearchBox
	if loaderSettings.CreateTextbox then
		moduleSearchBox = loaderSettings.CreateTextbox({
			Name = "module search",
			Default = "",
			Function = function(value) applyModuleSearch(value) end,
			Tooltip = "Filter visible modules across every category window.",
		})
	end

	if loaderSettings.CreateButton then
		loaderSettings.CreateButton({
			Name = "clear search",
			Function = function()
				if moduleSearchBox and moduleSearchBox.Set then
					moduleSearchBox.Set("")
				end
				applyModuleSearch("")
			end,
			Tooltip = "Clear the current module filter and restore every module row.",
		})
	end

	local developerModeToggle

	loaderSettings.CreateToggle({
		Name = "Auto Update",
		Default = settings.autoUpdate,
		Function = function(on)
			settings.autoUpdate = on
			updater:SetSetting("autoUpdate", on)
		end,
	})

	developerModeToggle = loaderSettings.CreateToggle({
		Name = "Developer Mode",
		Default = effectiveDeveloperMode,
		Function = function(on)
			settings.developerMode = on == true
			local state = developer:Sync(settings.developerMode)
			local enabled = state.enabled == true
			phantom.developerMode = enabled
			moduleLoader:SetDeveloperMode(enabled)
			updater:SetSetting("developerMode", settings.developerMode)
			logger:SetDebug(settings.debugLogs or enabled)
			if developerModeToggle and developerModeToggle.SetEnabled and enabled ~= on then
				developerModeToggle:SetEnabled(enabled, true)
			end
			if state.externalEnabled and not settings.developerMode then
				render:Toast({
					title = "Developer Mode",
					text = "checkdev.txt is still forcing local-only mode, so GitHub downloads remain blocked.",
					duration = 4,
				})
			end
		end,
		Tooltip = "Use local files only and block GitHub updates.",
	})

	loaderSettings.CreateToggle({
		Name = "Debug Logs",
		Default = settings.debugLogs,
		Function = function(on)
			settings.debugLogs = on
			updater:SetSetting("debugLogs", on)
			logger:SetDebug(on or developer:Sync(settings.developerMode).enabled)
		end,
	})

	if loaderSettings.CreateButton then
		loaderSettings.CreateButton({
			Name = "save current config",
			Function = function()
				saveProfile(profileSlot)
				render:Toast({
					title = "Profile",
					text = "Saved " .. profileSlot .. ".json for " .. placeId,
					duration = 2,
				})
			end,
			Tooltip = "Save the active profile without opening the settings window.",
		})

		loaderSettings.CreateButton({
			Name = "load current config",
			Function = function()
				loadProfile(profileSlot, false)
			end,
			Tooltip = "Reload the active profile immediately.",
		})

		if UI.ResetPositions then
			loaderSettings.CreateButton({
				Name = "reset positions only",
				Function = function()
					UI.ResetPositions()
					render:Toast({ title = "Layout", text = "Reset all window positions.", duration = 2 })
				end,
				Tooltip = "Keep the current scale and theme, but move windows back to their preset anchors.",
			})
		end

		if UI.ResetScale then
			loaderSettings.CreateButton({
				Name = "reset scale only",
				Function = function()
					UI.ResetScale()
					render:Toast({ title = "Layout", text = "Reset UI scaling to the default value.", duration = 2 })
				end,
				Tooltip = "Restore the responsive scaler without changing saved positions or toggles.",
			})
		end

		if UI.ResetLayout then
			loaderSettings.CreateButton({
				Name = "restore default layout",
				Function = function()
					UI.ResetLayout()
					render:Toast({ title = "Layout", text = "Restored the default UI layout.", duration = 2 })
				end,
				Tooltip = "Move every draggable UI window back to its original position.",
			})
		end

		if UI.FactoryResetUI then
			loaderSettings.CreateButton({
				Name = "full factory reset",
				BackgroundColor = Color3.fromRGB(58, 20, 20),
				Function = function()
					clearOverlayState()
					UI.FactoryResetUI()
					render:Toast({
						title = "Layout",
						text = "Factory reset applied. Reloading the UI...",
						duration = 2,
					})
					phantom.HotReload()
				end,
				Tooltip = "Reset theme, scaling, overlay settings, and layout state back to a clean factory baseline.",
			})
		end
	end

	local themeState = readGuiTheme()
	task.defer(function()
		task.wait(0.5)
		saveCurrentPaletteAsNormal()
	end)
	hudModule.CreateDropdown({
		Name = "Primary color",
		List = { "Violet", "Cobalt", "Crimson", "Emerald", "Amber" },
		Default = "Violet",
		Function = function(value)
			repeat task.wait(0.1) until env.configloaded
			local color = primaryPresets[value]
			if color then
				setGuiPalette(color)
			end
		end,
		Tooltip = "Swap the main accent used across active rows and highlights.",
	})

	hudModule.CreateDropdown({
		Name = "Secondary color",
		List = { "Night", "Ink", "Ruby", "Forest", "Steel" },
		Default = "Night",
		Function = function(value)
			local color = secondaryPresets[value]
			if color then setGuiSecondaryColor(color) end
		end,
		Tooltip = "Adjust the darker accent used behind active rows and panel glows.",
	})

	hudModule.CreateDropdown({
		Name = "Font color",
		List = { "Silver", "Ice", "Sand", "Mint" },
		Default = "Silver",
		Function = function(value)
			local color = fontPresets[value]
			if color then setGuiFontColor(color) end
		end,
		Tooltip = "Shift the UI text color without changing the accent color.",
	})

	hudModule.CreateSlider({
		Name = "Animation speed",
		Min = 0.5, Max = 2,
		Default = themeState.AnimationSpeed,
		Round = 1,
		Function = function(value) setGuiAnimationSpeed(value) end,
		Tooltip = "Scale the panel open, hover, and expand animation speed.",
	})

	hudModule.CreateSlider({
		Name = "Glow speed",
		Min = 0.5, Max = 3,
		Default = themeState.GlowSpeed,
		Round = 1,
		Function = function(value) setGuiGlowSpeed(value) end,
		Tooltip = "Adjust how quickly the active-row glow pulses.",
	})

	hudModule.CreateToggle({
		Name = "Panel bend",
		Default = true,
		Function = function(on) env.phantomBendEffect = on end,
		Tooltip = "Store the animated panel-bend preference for the legacy HUD.",
	})

	hudModule.CreateToggle({
		Name = "Watermark",
		Default = readOverlayToggleState("watermark", false),
		Function = function(on)
			if watermarkWindow then watermarkWindow.SetVisible(on) end
		end,
		Tooltip = "Show or hide the compact Phantom watermark window.",
	})

	hudModule.CreateToggle({
		Name = "Gesture mode",
		Default = false,
		Function = function(on) env.phantomGestures = on end,
		Tooltip = "Store the gesture preference for touch-first UI interactions.",
	})

	hudModule.CreateToggle({
		Name = "Fast search",
		Default = false,
		Function = function(on) env.phantomDirectSearch = on end,
		Tooltip = "Store the direct-search preference for future internal tooling.",
	})

	if hudModule.SetEnabled then
		hudModule.SetEnabled(true, true, true)
	end

	if keybindsModule and keybindsModule.SetEnabled then
		keybindsModule.SetEnabled(false, true, true)
	end

	setGuiVisible(false)
end

local function createAction(name, callback, options)
	options = options or {}
	local action
	action = tabs.other.AddNew({
		Name = name,
		NoSave = true,
		HideInUI = options.HideInUI == true,
		Function = function(enabled)
			if not enabled then return end
			local ok, err = pcall(callback)
			if not ok then
				logger:Warn(name, err)
				render:Toast({ title = name, text = tostring(err), duration = 3 })
			end
			if action and action.SetEnabled and env.phantom then
				action.SetEnabled(false, true, true)
			end
		end,
	})
	return action
end

if hudEditor then
	rootManager:AddConnection(Services.RunService.Heartbeat:Connect(function()
		local saveRequest = hudEditor.SaveRequest
		if saveRequest then
			hudEditor.SaveRequest = nil
			saveProfile(saveRequest)
			if hudEditor.RefreshConfigs then hudEditor.RefreshConfigs() end
		end

		local loadRequest = hudEditor.LoadRequest
		if loadRequest then
			hudEditor.LoadRequest = nil
			scheduleLoadProfile(loadRequest, false)
		end

		local deleteRequest = hudEditor.DeleteRequest
		if deleteRequest then
			hudEditor.DeleteRequest = nil
			local targetSlot = tostring(deleteRequest)
			local ok, err = fileApi:Delete(statePath(targetSlot))
			if not ok then
				logger:Warn("failed to delete profile", targetSlot, err)
				render:Toast({ title = "Profile", text = "Failed to delete " .. targetSlot, duration = 3 })
			else
				if targetSlot == profileSlot then
					setProfileSlot("default")
					scheduleLoadProfile(profileSlot, true)
				end
				if hudEditor.RefreshConfigs then hudEditor.RefreshConfigs() end
			end
		end
	end))
end

createAction("Check Updates", function()
	local result = updater:Check()
	render:Toast({ title = "Updater", text = formatUpdateResult(result), duration = 3 })
end, { HideInUI = false })

createAction("Apply Update", function()
	local result = updater:Apply(nil)
	render:Toast({ title = "Updater", text = formatUpdateResult(result), duration = 4 })
end, { HideInUI = false })

createAction("Save Profile", function()
	saveProfile(profileSlot)
	render:Toast({ title = "Profile", text = "Saved " .. profileSlot .. ".json for " .. placeId, duration = 3 })
end, { HideInUI = true })

createAction("Load Profile", function()
	scheduleLoadProfile(profileSlot, false)
end, { HideInUI = false })

local function loadGameScript(name, bundle)
	local ok = gameLoader:LoadBundle(name, bundle)
	return ok
end

local universalLoaded = loadGameScript("game.universal", gameScripts and gameScripts.universal)
local creatorLoaded = true
if creatorScriptExists() and gameScripts.creator ~= gameScripts.primary then
	creatorLoaded = loadGameScript("game.creator", gameScripts.creator)
end
local placeLoaded = loadGameScript("game.place", gameScripts and gameScripts.primary)

setProfileSlot(profileSlot)

task.defer(function()
	task.wait()
	uiFullyReady = true
	scheduleLoadProfile(profileSlot, true)
end)

task.defer(function()
	local ok, err = pcall(function()
		discord:EnsureInvite()
	end)
	if not ok then
		logger:Warn("discord bootstrap failed", err)
	end
end)

if not universalLoaded or not creatorLoaded or not placeLoaded then
	render:Toast({
		title = "Runtime",
		text = "One or more game scripts failed to load. Check warnings for details.",
		duration = 4,
	})
end

render:Toast({
	title = "Phantom",
	text = string.format( "Loaded %s for %s. Press RightShift or LeftAlt to toggle the UI.",versionData.full, placeId),
	duration = 3,
})

print("gsfgfgfs")
phantom.ready = true
return phantom

