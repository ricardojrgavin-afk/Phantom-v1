local cloneref = cloneref or function(value)
    return value
end

local Players = cloneref(game:GetService("Players"))
local Workspace = cloneref(game:GetService("Workspace"))
local ReplicatedStorage= cloneref(game:GetService("ReplicatedStorage"))
local Lighting = cloneref(game:GetService("Lighting"))
local CollectionService= cloneref(game:GetService("CollectionService"))
local RunService = cloneref(game:GetService("RunService"))
local CoreGui = cloneref(game:GetService("CoreGui"))
local UserInputService = cloneref(game:GetService("UserInputService"))

local lplr = Players.LocalPlayer
local PlayerGui = lplr:FindFirstChildOfClass("PlayerGui") or lplr:WaitForChild("PlayerGui", 10)

local lib, ops  = phantom.UI, phantom.ops
local Runtime = ops.runtime
local RunLoops = Runtime.RunLoops
local runcode = Runtime.run
local notification = lib.toast

local hiddenUi = (gethui or get_hidden_gui or function() return CoreGui end)()
local overlayParent = (typeof(hiddenUi) == "Instance" and not hiddenUi:IsA("ScreenGui")) and hiddenUi or CoreGui

for _, v in ipairs({
    "AntiAFK", "Antideath", "Gravity", "FovChanger", "ESP",
    "Cape", "AimAssist", "AntiFall", "Speed", "Fly", "NoClip",
    "AutoClicker", "FastStop", "FPSBooster", "AnimationPlayer", "BreadCrumbs"
}) do
    lib.kit:deregister(v .. "Module")
end

local overlayName = "Overlay"
local highlightName = "Highlights"
do
    local old  = CoreGui:FindFirstChild(overlayName)
    if old  then old:Destroy()  end
    local oldH = CoreGui:FindFirstChild(highlightName)
    if oldH then oldH:Destroy() end
end

local OverlayGui = Instance.new("ScreenGui")
OverlayGui.Name = overlayName
OverlayGui.IgnoreGuiInset = true
OverlayGui.ResetOnSpawn = false
OverlayGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
OverlayGui.Parent = overlayParent

local HighlightFolder = Instance.new("Folder")
HighlightFolder.Name   = highlightName
HighlightFolder.Parent = CoreGui

local RuntimeState = {
    Character = nil,
    Humanoid = nil,
    RootPart = nil,
    Tool = nil,
    Blocking = false,
    StunState = false,
    LastAction = {},
    HudLabel = nil,
}

local SavedStates = {
    Fullbright = nil,
    ScreenEffects = {},
    CharacterCollision= {},
    TrapParts = {},
    SpeedBoost = { WalkSpeed = nil, RunSpeed = nil },
    PlayerAttributes  = {
        CameraShake = lplr:GetAttribute("CameraShake"),
        ShowHitboxes = lplr:GetAttribute("ShowHitboxes"),
        ShowBarriers = lplr:GetAttribute("ShowBarriers"),
    },
}

local ESPCache  = {
    Survivor = {}, Killer = {}, Generator = {},
    FuseBox = {}, Battery = {}, Door = {},
    Exit = {}, Beartrap = {}, Springtrap = {}, EnnardMinion = {}, Objective = {},
}

local ESPColors = {
    Survivor = Color3.fromRGB(120, 255, 120),
    Killer = Color3.fromRGB(255, 90,  90 ),
    Generator = Color3.fromRGB(255, 215, 90 ),
    FuseBox = Color3.fromRGB(95,  225, 255),
    Battery = Color3.fromRGB(255, 170, 70 ),
    Door = Color3.fromRGB(120, 180, 255),
    Exit = Color3.fromRGB(255, 255, 255),
    Beartrap = Color3.fromRGB(255, 120, 120),
    Springtrap = Color3.fromRGB(255, 165, 90),
    EnnardMinion = Color3.fromRGB(190, 140, 255),
    Objective = Color3.fromRGB(255, 235, 140),
}

local Connections = {}
local ScreenEffectConnections  = nil
local EMOTES = {"wave", "dance", "cheer", "laugh", "point"}
local PromptCache = { Map = nil, Entries = {}, Lookup = {} }
local PromptKeywords = {
    Recovery = {"shake", "wiggle", "struggle", "free", "escape", "help"},
    Pickup = {"pickup", "take", "grab", "collect", "battery", "fuse"},
    Insert = {"insert", "place", "install", "battery", "fuse"},
    Barricade = {"barricade"},
    Exit = {"exit", "escape", "open"},
    Repair = {"wire", "switch", "lever", "repair"},
}
local ESPColorNames = {"Default", "Red", "Orange", "Yellow", "Green", "Cyan", "Blue", "Purple", "White", "Pink"}
local ESPColorPresets = {
    Red = Color3.fromRGB(255, 105, 105),
    Orange = Color3.fromRGB(255, 170, 85),
    Yellow = Color3.fromRGB(255, 225, 90),
    Green = Color3.fromRGB(120, 255, 120),
    Cyan = Color3.fromRGB(95, 225, 255),
    Blue = Color3.fromRGB(120, 180, 255),
    Purple = Color3.fromRGB(190, 140, 255),
    White = Color3.fromRGB(255, 255, 255),
    Pink = Color3.fromRGB(255, 150, 210),
}
local AutoSwingSettings = {
    Range = 11,
    Delay = 0.18,
    FaceTarget = true,
    QueueSlash = true,
}

local GeneratorSolverPayloads = {
    {Wires = true, Switches = true, Lever = true},
    {Wires = true, Switches = true, Levers = true},
    {Wire  = true, Switch  = true,  Lever  = true},
    {Action = "Wires"}, {Action = "Switches"}, {Action = "Lever"},
}

local PlayerUtility = phantom.module:Load("utility") or loadstring(readfile("Phantom/lib/Utility.lua"))()

local modulesFolder = ReplicatedStorage:FindFirstChild("Modules")

local toLower = function(v) return string.lower(tostring(v or "")) end
local notify = function(text) pcall(notification, text) end
local getDesc = function(instance)
    if not instance then return {} end
    local ok, r = pcall(function() return instance:GetDescendants() end)
    return ok and r or {}
end

local disconnect = function(key)
    local c = Connections[key]; if c then c:Disconnect(); Connections[key] = nil end
end

local setAttr = function(instance, attr, value)
    if not instance then return false end
    return pcall(function() instance:SetAttribute(attr, value) end)
end

local getAttr = function(instance, attr, fallback)
    if not instance then return fallback end
    local ok, r = pcall(function() return instance:GetAttribute(attr) end)
    return (ok and r ~= nil) and r or fallback
end

local hasTag = function(instance, tagName)
    if not instance then return false end
    local ok, r = pcall(function() return instance:HasTag(tagName) end)
    if ok then return r end
    local ok2, r2 = pcall(function() return CollectionService:HasTag(instance, tagName) end)
    return ok2 and r2 or false
end

local removeTag = function(instance, tagName)
    if not instance then return end
    if not pcall(function() instance:RemoveTag(tagName) end) then
        pcall(function() CollectionService:RemoveTag(instance, tagName) end)
    end
end

local getPart
getPart = function(instance)
    if not instance then return nil end
    if instance:IsA("ProximityPrompt") then return getPart(instance.Parent) end
    if instance:IsA("BasePart") or instance:IsA("MeshPart") then return instance end
    if instance:IsA("Attachment") then
        return (instance.Parent and instance.Parent:IsA("BasePart")) and instance.Parent or nil
    end
    if instance:IsA("Model") then
        return instance.PrimaryPart or instance:FindFirstChild("Root") or instance:FindFirstChild("HumanoidRootPart") or instance:FindFirstChildWhichIsA("BasePart", true)
    end
    return nil
end

local createEntryState = function() return { Entries = {}, Lookup = {} } end
local clearEntryState = function(state) table.clear(state.Entries); table.clear(state.Lookup) end

local addEntry = function(state, instance)
    if not instance then return false end
    local count = state.Lookup[instance] or 0
    state.Lookup[instance] = count + 1
    if count == 0 then state.Entries[#state.Entries + 1] = instance; return true end
    return false
end

local removeEntry = function(state, instance)
    local count = state.Lookup[instance]
    if not count then return false end
    if count > 1 then state.Lookup[instance] = count - 1; return false end
    state.Lookup[instance] = nil
    for i = #state.Entries, 1, -1 do
        if state.Entries[i] == instance then table.remove(state.Entries, i); break end
    end
    return true
end

local disconnectConnections = function(connectionTable)
    for key, connection in pairs(connectionTable) do
        if connection then connection:Disconnect() end
        connectionTable[key] = nil
    end
end

local compactLower = function(value) return (toLower(value):gsub("%s+", "")) end
local getNameBlob = function(instance, stopAt)
    local parts, current = {}, instance
    while current and current ~= stopAt do
        parts[#parts + 1] = current.Name
        current = current.Parent
    end
    return toLower(table.concat(parts, " "))
end

local nameHasKeyword = function(name, keywords)
    for _, kw in ipairs(keywords or {}) do if name:find(kw, 1, true) then return true end end
    return false
end

local matchesClasses = function(instance, classNames)
    if not classNames then return true end
    for _, cn in ipairs(classNames) do if instance:IsA(cn) then return true end end
    return false
end

local createContainerMatcher = function(tokens, exactMatch, classNames)
    local compactTokens = {}
    for _, token in ipairs(tokens or {}) do compactTokens[#compactTokens+1] = compactLower(token) end
    return function(instance)
        if not matchesClasses(instance, classNames or {"Folder","Model"}) then return false end
        local name = compactLower(instance.Name)
        for _, token in ipairs(compactTokens) do
            if exactMatch then if name == token then return true end
            elseif name:find(token, 1, true) then return true end
        end
        return false
    end
end

local createFallbackMatcher = function(keywords, classNames, validator)
    return function(instance)
        if not matchesClasses(instance, classNames or {"Model","BasePart","Folder"}) then return false end
        local name = toLower(instance.Name)
        if not nameHasKeyword(name, keywords) then return false end
        return not validator or validator(instance, name)
    end
end

local createTrackedGroup = function(containerMatcher, fallbackMatcher)
    return {
        ContainerMatcher = containerMatcher,
        FallbackMatcher  = fallbackMatcher,
        Containers = {},
        Primary  = createEntryState(),
        Fallback = createEntryState(),
    }
end

local CharacterPartCache  = createEntryState()
local CharacterConnections = {}
local PlayerFolderCache   = {
    Root = nil, RootConnections = {},
    Survivor = createEntryState(),
    Killer = createEntryState(),
    RefreshQueued = false,
}
PlayerFolderCache.Survivor.Folder = nil; PlayerFolderCache.Survivor.Connections = {}
PlayerFolderCache.Killer.Folder = nil; PlayerFolderCache.Killer.Connections   = {}

local MapCache = {
    Root = nil, MapsFolder = nil,
    Connections = {}, RootConnections = {},
    RefreshQueued = false,
    Groups = {
        Generators = createTrackedGroup(createContainerMatcher({"Generators"})),
        FuseBoxes = createTrackedGroup(createContainerMatcher({"FuseBoxes","Fuse Boxes"})),
        Batteries = createTrackedGroup(createContainerMatcher({"Batteries"})),
        Exits = createTrackedGroup(createContainerMatcher({"Escapes"})),
        Objectives = createTrackedGroup(createContainerMatcher({"Points","GenPoints","FusePoints","AnnouncementPoints"}, true, {"Folder"}), nil),
        Beartrap = createTrackedGroup(nil, createFallbackMatcher({"beartrap","bear trap"}, {"Model","BasePart"}, function(_, name) return not name:find("spring",1,true) end)),
        Springtrap = createTrackedGroup(nil, createFallbackMatcher({"springtrap","spring trap"}, {"Model","BasePart"}, function(instance) return getPart(instance) ~= nil end)),
        EnnardMinion= createTrackedGroup(nil, createFallbackMatcher({"minion","ennard"}, {"Model"}, function(instance, name) return name:find("minion",1,true) or (name:find("ennard",1,true) and not instance:FindFirstChildOfClass("Humanoid")) end)),
        Doors = createTrackedGroup(
            createContainerMatcher({"Doors","Door"}, false, {"Folder","Model"}),
            createFallbackMatcher({"door"}, {"Model","BasePart","Folder"}, function(instance, name) return not name:find("locked",1,true) and name ~= "lockeddoors" and getPart(instance) ~= nil end)
        ),
    },
}

local IgnoreCache = {
    Root = nil, RootConnections = {},
    TrapFolder = nil, TrapConnections = {},
    Beartraps = createEntryState(), Springtraps = createEntryState(), Minions = createEntryState(),
    RefreshQueued = false,
}

local refreshPlayerFolderCache, refreshMapTracker, refreshIgnoreTracker
local queuePlayerFolderRefresh, queueMapRefresh, queueIgnoreRefresh
local bindRuntimeCharacter

local bindTrackedFolder = function(state, folder)
    if state.Folder == folder then return end
    disconnectConnections(state.Connections)
    state.Folder = folder
    clearEntryState(state)
    if not folder then return end
    for _, child in ipairs(folder:GetChildren()) do addEntry(state, child) end
    state.Connections.ChildAdded = folder.ChildAdded:Connect(function(child) addEntry(state, child) end)
    state.Connections.ChildRemoved = folder.ChildRemoved:Connect(function(child) removeEntry(state, child) end)
    state.Connections.AncestryChanged = folder.AncestryChanged:Connect(function(_, parent)
        if not parent or folder.Parent ~= PlayerFolderCache.Root then queuePlayerFolderRefresh() end
    end)
end

queuePlayerFolderRefresh = function()
    if PlayerFolderCache.RefreshQueued then return end
    PlayerFolderCache.RefreshQueued = true
    task.defer(function() PlayerFolderCache.RefreshQueued = false; refreshPlayerFolderCache(true) end)
end

refreshPlayerFolderCache = function(force)
    local root = Workspace:FindFirstChild("PLAYERS")
    if force or PlayerFolderCache.Root ~= root then
        disconnectConnections(PlayerFolderCache.RootConnections)
        PlayerFolderCache.Root = root
        if root then
            PlayerFolderCache.RootConnections.ChildAdded = root.ChildAdded:Connect(function(child)
                if child.Name == "ALIVE" or child.Name == "KILLER" then queuePlayerFolderRefresh() end
            end)
            PlayerFolderCache.RootConnections.ChildRemoved = root.ChildRemoved:Connect(function(child)
                if child.Name == "ALIVE" or child.Name == "KILLER" then queuePlayerFolderRefresh() end
            end)
            PlayerFolderCache.RootConnections.AncestryChanged = root.AncestryChanged:Connect(function(_, parent)
                if not parent then queuePlayerFolderRefresh() end
            end)
        end
    end
    bindTrackedFolder(PlayerFolderCache.Survivor, root and root:FindFirstChild("ALIVE") or nil)
    bindTrackedFolder(PlayerFolderCache.Killer,   root and root:FindFirstChild("KILLER") or nil)
    return root
end

local resolveMapRoot = function()
    local mapsFolder = Workspace:FindFirstChild("MAPS")
    if mapsFolder then
        local gameMap = mapsFolder:FindFirstChild("GAME MAP")
        if gameMap then return gameMap, mapsFolder end
    end
    for _, child in ipairs(Workspace:GetChildren()) do
        if child:IsA("Model") and (child.Name:find("MAP",1,true) or child.Name:find("Game",1,true)) then
            return child, mapsFolder
        end
    end
    return nil, mapsFolder
end

local detachGroupContainer, attachGroupContainer
local clearTrackedGroup = function(group)
    local containers = {}
    for container in pairs(group.Containers) do containers[#containers+1] = container end
    for _, container in ipairs(containers) do detachGroupContainer(group, container) end
    clearEntryState(group.Primary); clearEntryState(group.Fallback)
end

detachGroupContainer = function(group, container)
    local state = group.Containers[container]; if not state then return end
    group.Containers[container] = nil
    disconnectConnections(state.Connections)
    for child in pairs(state.Children) do removeEntry(group.Primary, child); state.Children[child] = nil end
end

attachGroupContainer = function(group, container)
    if group.Containers[container] then return end
    local state = { Connections = {}, Children = {} }
    group.Containers[container] = state
    local trackChild   = function(child) if state.Children[child] then return end; state.Children[child] = true;  addEntry(group.Primary, child) end
    local untrackChild = function(child) if not state.Children[child] then return end; state.Children[child] = nil; removeEntry(group.Primary, child) end
    for _, child in ipairs(container:GetChildren()) do trackChild(child) end
    state.Connections.ChildAdded   = container.ChildAdded:Connect(trackChild)
    state.Connections.ChildRemoved = container.ChildRemoved:Connect(untrackChild)
    state.Connections.AncestryChanged = container.AncestryChanged:Connect(function(_, parent)
        if not parent then detachGroupContainer(group, container) end
    end)
end

local handleMapDescendantAdded = function(descendant)
    if descendant:IsA("ProximityPrompt") then addEntry(PromptCache, descendant) end
    for _, group in pairs(MapCache.Groups) do
        if group.ContainerMatcher and group.ContainerMatcher(descendant) then
            attachGroupContainer(group, descendant)
        elseif group.FallbackMatcher and group.FallbackMatcher(descendant) then
            addEntry(group.Fallback, descendant)
        end
    end
end

local handleMapDescendantRemoving = function(descendant)
    if descendant:IsA("ProximityPrompt") then removeEntry(PromptCache, descendant) end
    for _, group in pairs(MapCache.Groups) do
        if group.Containers[descendant] then detachGroupContainer(group, descendant)
        elseif group.Fallback.Lookup[descendant] then removeEntry(group.Fallback, descendant) end
    end
end

local bindMapsFolderTracker = function(folder)
    if MapCache.MapsFolder == folder then return end
    disconnectConnections(MapCache.RootConnections)
    MapCache.MapsFolder = folder
    if not folder then return end
    MapCache.RootConnections.ChildAdded = folder.ChildAdded:Connect(function() queueMapRefresh() end)
    MapCache.RootConnections.ChildRemoved = folder.ChildRemoved:Connect(function() queueMapRefresh() end)
    MapCache.RootConnections.AncestryChanged = folder.AncestryChanged:Connect(function(_, parent) if not parent then queueMapRefresh() end end)
end

queueMapRefresh = function()
    if MapCache.RefreshQueued then return end
    MapCache.RefreshQueued = true
    task.defer(function() MapCache.RefreshQueued = false; refreshMapTracker(true) end)
end

refreshMapTracker = function(force)
    local map, mapsFolder = resolveMapRoot()
    bindMapsFolderTracker(mapsFolder)
    if force or MapCache.Root ~= map then
        disconnectConnections(MapCache.Connections)
        MapCache.Root = map; PromptCache.Map = map
        clearEntryState(PromptCache)
        for _, group in pairs(MapCache.Groups) do clearTrackedGroup(group) end
        if map then
            for _, d in ipairs(map:GetDescendants()) do handleMapDescendantAdded(d) end
            MapCache.Connections.DescendantAdded = map.DescendantAdded:Connect(handleMapDescendantAdded)
            MapCache.Connections.DescendantRemoving = map.DescendantRemoving:Connect(handleMapDescendantRemoving)
            MapCache.Connections.AncestryChanged = map.AncestryChanged:Connect(function(_, parent) if not parent then queueMapRefresh() end end)
        end
    end
    return map
end

local isBeartrapName = function(name) return name:find("bear",1,true) and not name:find("spring",1,true) end
local isSpringtrapName = function(name) return name:find("spring",1,true) ~= nil end
local resolveTrapTarget = function(instance, trapFolder)
    local current = instance
    while current and current ~= trapFolder do
        if current:IsA("Model") or current:IsA("Folder") or current:IsA("BasePart") or current:IsA("MeshPart") then
            local blob = getNameBlob(current, trapFolder)
            if isBeartrapName(blob) or isSpringtrapName(blob) then
                if current:IsA("BasePart") or current:IsA("MeshPart") then
                    local parentModel = current.Parent
                    if parentModel and parentModel ~= trapFolder and parentModel:IsA("Model") then
                        return parentModel
                    end
                end
                return current
            end
        end
        current = current.Parent
    end
    return nil
end

local bindTrapFolder = function(folder)
    if IgnoreCache.TrapFolder == folder then return end
    disconnectConnections(IgnoreCache.TrapConnections)
    IgnoreCache.TrapFolder = folder
    clearEntryState(IgnoreCache.Beartraps); clearEntryState(IgnoreCache.Springtraps)
    if not folder then return end
    local classifyTrap = function(instance, present)
        local target = resolveTrapTarget(instance, folder)
        if not target then return end
        local name = getNameBlob(target, folder)
        if isBeartrapName(name)  then if present then addEntry(IgnoreCache.Beartraps,  target) else removeEntry(IgnoreCache.Beartraps,  target) end end
        if isSpringtrapName(name) then if present then addEntry(IgnoreCache.Springtraps,target) else removeEntry(IgnoreCache.Springtraps,target) end end
    end
    classifyTrap(folder, true)
    for _, child in ipairs(folder:GetDescendants()) do classifyTrap(child, true) end
    IgnoreCache.TrapConnections.DescendantAdded = folder.DescendantAdded:Connect(function(child) classifyTrap(child, true) end)
    IgnoreCache.TrapConnections.DescendantRemoving = folder.DescendantRemoving:Connect(function(child) classifyTrap(child, false) end)
    IgnoreCache.TrapConnections.AncestryChanged = folder.AncestryChanged:Connect(function(_, parent)
        if not parent or folder.Parent ~= IgnoreCache.Root then queueIgnoreRefresh() end
    end)
end

queueIgnoreRefresh = function()
    if IgnoreCache.RefreshQueued then return end
    IgnoreCache.RefreshQueued = true
    task.defer(function() IgnoreCache.RefreshQueued = false; refreshIgnoreTracker(true) end)
end

refreshIgnoreTracker = function(force)
    local root = Workspace:FindFirstChild("IGNORE")
    if force or IgnoreCache.Root ~= root then
        disconnectConnections(IgnoreCache.RootConnections)
        IgnoreCache.Root = root
        clearEntryState(IgnoreCache.Minions)
        if root then
            for _, d in ipairs(root:GetDescendants()) do
                if d:IsA("Model") then
                    local name = toLower(d.Name)
                    if name:find("minion",1,true) or (name:find("ennard",1,true) and not d:FindFirstChildOfClass("Humanoid")) then
                        addEntry(IgnoreCache.Minions, d)
                    end
                end
            end
            IgnoreCache.RootConnections.ChildAdded = root.ChildAdded:Connect(function(child)
                if child.Name == "Trap" then bindTrapFolder(root:FindFirstChild("Trap")) end
            end)
            IgnoreCache.RootConnections.ChildRemoved = root.ChildRemoved:Connect(function(child)
                if child.Name == "Trap" then bindTrapFolder(root:FindFirstChild("Trap")) end
            end)
            IgnoreCache.RootConnections.DescendantAdded = root.DescendantAdded:Connect(function(d)
                if d:IsA("Model") then
                    local name = toLower(d.Name)
                    if name:find("minion",1,true) or (name:find("ennard",1,true) and not d:FindFirstChildOfClass("Humanoid")) then
                        addEntry(IgnoreCache.Minions, d)
                    end
                end
            end)
            IgnoreCache.RootConnections.DescendantRemoving = root.DescendantRemoving:Connect(function(d)
                if d:IsA("Model") then removeEntry(IgnoreCache.Minions, d) end
            end)
            IgnoreCache.RootConnections.AncestryChanged = root.AncestryChanged:Connect(function(_, parent)
                if not parent then queueIgnoreRefresh() end
            end)
        end
    end
    bindTrapFolder(root and root:FindFirstChild("Trap") or nil)
    return root
end

bindRuntimeCharacter = function(character, useFallback)
    disconnectConnections(CharacterConnections)
    clearEntryState(CharacterPartCache)

    RuntimeState.Character = character
    if not RuntimeState.Character and useFallback ~= false then
        RuntimeState.Character = lplr.Character or PlayerUtility.lplrCharacter
    end

    RuntimeState.Humanoid = nil; RuntimeState.RootPart = nil; RuntimeState.Tool = nil

    local activeCharacter = RuntimeState.Character
    if not activeCharacter then return end

    RuntimeState.Humanoid = activeCharacter:FindFirstChildOfClass("Humanoid") or PlayerUtility.lplrHumanoid
    RuntimeState.RootPart = activeCharacter:FindFirstChild("HumanoidRootPart") or activeCharacter:FindFirstChild("Root") or activeCharacter:FindFirstChildWhichIsA("BasePart", true) or PlayerUtility.lplrRoot
    RuntimeState.Tool = activeCharacter:FindFirstChildOfClass("Tool")

    for _, d in ipairs(activeCharacter:GetDescendants()) do
        if d:IsA("BasePart") then addEntry(CharacterPartCache, d) end
    end

    CharacterConnections.ChildAdded = activeCharacter.ChildAdded:Connect(function(child)
        if child:IsA("Humanoid") then RuntimeState.Humanoid = child
        elseif child:IsA("Tool") then RuntimeState.Tool = child end
    end)
    CharacterConnections.ChildRemoved = activeCharacter.ChildRemoved:Connect(function(child)
        if child == RuntimeState.Humanoid then
            RuntimeState.Humanoid = activeCharacter:FindFirstChildOfClass("Humanoid") or PlayerUtility.lplrHumanoid
        elseif child == RuntimeState.Tool then
            RuntimeState.Tool = activeCharacter:FindFirstChildOfClass("Tool")
        end
    end)
    CharacterConnections.DescendantAdded = activeCharacter.DescendantAdded:Connect(function(d)
        if d:IsA("BasePart") then
            addEntry(CharacterPartCache, d)
            if d.Name == "HumanoidRootPart" or d.Name == "Root" or not RuntimeState.RootPart then
                RuntimeState.RootPart = d
            end
        end
    end)
    CharacterConnections.DescendantRemoving = activeCharacter.DescendantRemoving:Connect(function(d)
        if d:IsA("BasePart") then
            removeEntry(CharacterPartCache, d)
            if d == RuntimeState.RootPart then
                RuntimeState.RootPart = activeCharacter:FindFirstChild("HumanoidRootPart") or activeCharacter:FindFirstChild("Root") or activeCharacter:FindFirstChildWhichIsA("BasePart", true) or PlayerUtility.lplrRoot
            end
        end
    end)
    CharacterConnections.AncestryChanged = activeCharacter.AncestryChanged:Connect(function(_, parent)
        if not parent then bindRuntimeCharacter(nil, false) end
    end)
end

Connections.WorkspaceChildAdded = Workspace.ChildAdded:Connect(function(child)
    if child.Name == "PLAYERS" then queuePlayerFolderRefresh()
    elseif child.Name == "MAPS" or (child:IsA("Model") and (child.Name:find("MAP",1,true) or child.Name:find("Game",1,true))) then queueMapRefresh()
    elseif child.Name == "IGNORE" then queueIgnoreRefresh() end
end)

Connections.WorkspaceChildRemoved = Workspace.ChildRemoved:Connect(function(child)
    if child.Name == "PLAYERS" then queuePlayerFolderRefresh()
    elseif child.Name == "MAPS" or (child:IsA("Model") and (child.Name:find("MAP",1,true) or child.Name:find("Game",1,true))) then queueMapRefresh()
    elseif child.Name == "IGNORE" then queueIgnoreRefresh() end
end)

Connections.CharacterAdded = lplr.CharacterAdded:Connect(function(character) bindRuntimeCharacter(character) end)
Connections.CharacterRemoving = lplr.CharacterRemoving:Connect(function(character)
    if RuntimeState.Character == character then bindRuntimeCharacter(nil, false) end
end)

bindRuntimeCharacter(lplr.Character or PlayerUtility.lplrCharacter)
refreshPlayerFolderCache(true)
refreshMapTracker(true)
refreshIgnoreTracker(true)

local distTo = function(instance)
    local root = RuntimeState.RootPart or PlayerUtility.lplrRoot
    local target = getPart(instance)
    if not (root and target) then return math.huge end
    return (root.Position - target.Position).Magnitude
end

local getMap = function() return MapCache.Root or refreshMapTracker() end

local getTaskList = function(folderName, keywords)
    local group = MapCache.Groups[folderName]
    if group then
        if #group.Primary.Entries > 0 then return group.Primary.Entries end
        return group.Fallback.Entries
    end
    local map = getMap(); if not map then return {} end
    local results, seen = {}, {}
    local addIfNew = function(obj) if obj and not seen[obj] then seen[obj] = true; results[#results+1] = obj end end
    local folder = map:FindFirstChild(folderName)
    if folder then
        for _, child in ipairs(folder:GetChildren()) do addIfNew(child) end
        if #results > 0 then return results end
    end
    for _, desc in ipairs(map:GetDescendants()) do
        if (desc:IsA("Folder") or desc:IsA("Model")) and string.find(string.lower(desc.Name), string.lower(folderName), 1, true) then
            for _, child in ipairs(desc:GetChildren()) do addIfNew(child) end
        end
    end
    if #results > 0 then return results end
    if keywords then
        for _, desc in ipairs(map:GetDescendants()) do
            if desc:IsA("Model") or desc:IsA("BasePart") or desc:IsA("Folder") then
                local n = string.lower(desc.Name)
                for _, kw in ipairs(keywords) do if string.find(n, kw, 1, true) then addIfNew(desc); break end end
            end
        end
    end
    return results
end

local getMapPrompts = function()
    local map = getMap()
    if not map then PromptCache.Map = nil; clearEntryState(PromptCache); return {} end
    if PromptCache.Map ~= map then refreshMapTracker(true) end
    return PromptCache.Entries
end

local getDoors = function()
    local source = getTaskList("Doors", {"door"})
    local results, seen = {}, {}
    local addDoor = function(obj)
        if not obj or seen[obj] then return end
        local n = string.lower(obj.Name)
        if n:find("locked") or n == "lockeddoors" then return end
        seen[obj] = true; results[#results+1] = obj
    end
    for _, door in ipairs(source) do addDoor(door) end
    local map = getMap()
    if map then
        local doorsFolder = map:FindFirstChild("Doors")
        if doorsFolder then
            for _, door in ipairs(doorsFolder:GetChildren()) do addDoor(door) end
            local dd = doorsFolder:FindFirstChild("Double Doors")
            if dd then for _, d in ipairs(dd:GetChildren()) do addDoor(d) end end
        end
        local doubleDoors = map:FindFirstChild("Double Doors")
        if doubleDoors then
            for _, d in ipairs(doubleDoors:GetChildren()) do
                local tf = d:FindFirstChild("Types")
                if tf then
                    local sub = tf:FindFirstChild("1")
                    if sub then addDoor(sub:FindFirstChild("Door1")); addDoor(sub:FindFirstChild("Door2")) end
                end
            end
        end
    end
    return results
end

local getBatteries = function()
    local group = MapCache.Groups.Batteries
    local primary = group and group.Primary.Entries  or {}
    local fallback = group and group.Fallback.Entries or {}
    local results, seen = {}, {}
    local addBattery = function(obj) if not obj or seen[obj] then return end; seen[obj] = true; results[#results+1] = obj end
    for _, b in ipairs(primary)  do addBattery(b) end
    for _, b in ipairs(fallback) do addBattery(b) end
    for _, b in ipairs(getTaskList("Batteries", {"battery"})) do addBattery(b) end
    local ignoreFolder = Workspace:FindFirstChild("IGNORE")
    if ignoreFolder then
        for _, obj in ipairs(ignoreFolder:GetDescendants()) do
            local cls = obj.ClassName
            if cls == "Model" or cls == "BasePart" or cls == "MeshPart" then
                if string.lower(obj.Name):find("battery",1,true) then addBattery(obj) end
            end
        end
    end
    return results
end

local getGenerators = function() return getTaskList("Generators", {"generator","gen"})  end
local getFuseBoxes  = function() return getTaskList("FuseBoxes",  {"fuse","fusebox"})   end

local mapObjects = function(keywords, validator)
    local map = getMap(); if not map then return {} end
    local results, seen = {}, {}
    for _, d in ipairs(map:GetDescendants()) do
        if d:IsA("Model") or d:IsA("BasePart") then
            local target = d:IsA("BasePart") and (d.Parent:IsA("Model") and d.Parent or d) or d
            if not seen[target] then
                local n = string.lower(target.Name)
                for _, kw in ipairs(keywords) do
                    if n:find(kw, 1, true) then
                        if not validator or validator(target) then seen[target] = true; results[#results+1] = target end
                        break
                    end
                end
            end
        end
    end
    return results
end

local mergeLists = function(...)
    local merged, seen = {}, {}
    for _, list in ipairs({...}) do
        for _, entry in ipairs(list) do
            if entry and not seen[entry] then seen[entry] = true; merged[#merged+1] = entry end
        end
    end
    return merged
end

local getObjectives = function() if not getMap() then return {} end; return MapCache.Groups.Objectives.Primary.Entries end
local getExits = function() return getTaskList("Exits", {"exit","escape"}) end
local getBeartraps = function()
    return mergeLists(
        IgnoreCache.Beartraps.Entries,
        MapCache.Groups.Beartrap.Primary.Entries,
        MapCache.Groups.Beartrap.Fallback.Entries
    )
end
local getSpringtrapTraps = function()
    return mergeLists(
        IgnoreCache.Springtraps.Entries,
        MapCache.Groups.Springtrap.Primary.Entries,
        MapCache.Groups.Springtrap.Fallback.Entries
    )
end
local getEnnardMinions  = function() return #IgnoreCache.Minions.Entries > 0 and IgnoreCache.Minions.Entries or MapCache.Groups.EnnardMinion.Fallback.Entries end

local getPlayerFolders = function()
    if not PlayerFolderCache.Root and Workspace:FindFirstChild("PLAYERS") then refreshPlayerFolderCache(true) end
    return PlayerFolderCache.Survivor.Folder, PlayerFolderCache.Killer.Folder
end

local getSurvivorCharacters = function()
    local aliveFolder = getPlayerFolders()
    local out = {}
    if not aliveFolder then return out end
    for _, c in ipairs(PlayerFolderCache.Survivor.Entries) do
        if c ~= RuntimeState.Character and c.Parent == aliveFolder and PlayerUtility.IsAlive(Players:GetPlayerFromCharacter(c)) then
            out[#out+1] = c
        end
    end
    return out
end

local getKillerCharacters = function()
    local _, killerFolder = getPlayerFolders()
    local out = {}
    if not killerFolder then return out end
    for _, c in ipairs(PlayerFolderCache.Killer.Entries) do
        if c ~= RuntimeState.Character and c.Parent == killerFolder and PlayerUtility.IsAlive(Players:GetPlayerFromCharacter(c)) then
            out[#out+1] = c
        end
    end
    return out
end

local lkillr = function()
    local _, kf = getPlayerFolders()
    return RuntimeState.Character ~= nil and kf ~= nil and RuntimeState.Character.Parent == kf
end

local closestChar = function(characters, maxDistance, ignoreUndetectable)
    local best, bestDist = nil, maxDistance or math.huge
    for _, c in ipairs(characters) do
        local root = getPart(c)
        if root then
            local ok = not ignoreUndetectable or (not hasTag(c, "UNDETECTABLE") and not hasTag(c, "Imitation"))
            if ok then
                local d = distTo(root)
                if d < bestDist then best = c; bestDist = d end
            end
        end
    end
    return best, bestDist
end

local closestTarget = function(maxDist)
    local targets = lkillr() and getSurvivorCharacters() or getKillerCharacters()
    return closestChar(targets, maxDist, true)
end

local closestKiller = function(maxDist) return closestChar(getKillerCharacters(), maxDist, true) end

local closestIn = function(list, maxDist, validator)
    local best, bestDist = nil, maxDist or math.huge
    for _, item in ipairs(list) do
        local part = getPart(item)
        if part and (not validator or validator(item)) then
            local d = distTo(part); if d < bestDist then best = item; bestDist = d end
        end
    end
    return best, bestDist
end

local promptOk = function(prompt, keywords)
    if not prompt or not prompt:IsA("ProximityPrompt") or not prompt.Enabled then return false end
    if not keywords or #keywords == 0 then return true end
    local blob = getNameBlob(prompt.Parent, nil) .. " " .. toLower(prompt.Name .. " " .. prompt.ActionText .. " " .. prompt.ObjectText)
    for _, kw in ipairs(keywords) do if blob:find(kw, 1, true) then return true end end
    return false
end

local getPromptBlob = function(prompt)
    if not prompt then return "" end
    local parentBlob = prompt.Parent and getNameBlob(prompt.Parent, nil) or ""
    return toLower(table.concat({prompt.Name, prompt.ActionText, prompt.ObjectText, parentBlob}, " "))
end

local closestPrompt = function(keywords, maxDist, validator)
    local bestPrompt, bestDist = nil, maxDist or math.huge
    for _, prompt in ipairs(getMapPrompts()) do
        if prompt:IsA("ProximityPrompt") and promptOk(prompt, keywords) and (not validator or validator(prompt)) then
            local dist = distTo(prompt.Parent or prompt)
            if dist < bestDist then
                bestPrompt, bestDist = prompt, dist
            end
        end
    end
    return bestPrompt, bestDist
end

local UIS = UserInputService
local touchHeld = false
local connectiontouch1, connectiontouch2
do
    connectiontouch1 = UIS.TouchStarted:Connect(function(input, processed)
        if not processed then
            touchHeld = true
        end
    end)

    connectiontouch2 = UIS.TouchEnded:Connect(function()
        touchHeld = false
    end)
end

local isPromptInputHeld = function(prompt)
    if not prompt or not prompt.Enabled then
        return false 
    end

    local held = false
    pcall(function()
        local keyCode = prompt.KeyboardKeyCode
        if keyCode and keyCode ~= Enum.KeyCode.Unknown then
            held = UIS:IsKeyDown(keyCode)
        end
    end)

    if held then 
        return true 
    end
    if prompt.ClickablePrompt or UIS.TouchEnabled then
        pcall(function()
            if UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
                held = true
            end
        end)
        if held then
            return true
        end
        if touchHeld then
            return true
        end
    end

    return false
end

local isRecoveryPrompt = function(prompt)
    if not prompt or not prompt.Enabled then return false end
    local character = RuntimeState.Character
    local parent = prompt.Parent
    if character and parent and parent:IsDescendantOf(character) then return true end
    return distTo(parent or prompt) <= 18 and nameHasKeyword(getPromptBlob(prompt), PromptKeywords.Recovery)
end

local findPrompt
findPrompt = function(instance, keywords)
    if not instance then return nil end
    if instance:IsA("ProximityPrompt") and promptOk(instance, keywords) then return instance end
    for _, d in ipairs(instance:GetDescendants()) do
        if d:IsA("ProximityPrompt") and promptOk(d, keywords) then return d end
    end
    return nil
end

local findMapPrompt = function(keywords, maxDist, validator)
    return closestPrompt(keywords, maxDist, validator)
end

local firePrompt = function(prompt)
    if not prompt or not prompt.Enabled then return false end
    local holdDuration = math.max(prompt.HoldDuration or 0, 0.02)
    if fireproximityprompt then
        if pcall(function() fireproximityprompt(prompt, holdDuration + 0.02) end) then return true end
    end
    return pcall(function()
        prompt:InputHoldBegin(); task.wait(holdDuration); prompt:InputHoldEnd()
    end)
end

local moveTo = function(instance, yOffset)
    local root = RuntimeState.RootPart or PlayerUtility.lplrRoot
    if not (root and instance) then return false end
    local part = getPart(instance); if not part then return false end
    root.CFrame = CFrame.lookAt(part.Position + Vector3.new(0, yOffset or 2.5, 0), part.Position)
    return true
end

local throttle = function(key, delay)
    local now = tick(); local prev = RuntimeState.LastAction[key] or 0
    if now - prev >= delay then RuntimeState.LastAction[key] = now; return true end
    return false
end

local canAct = function()
    local character = RuntimeState.Character
    if not PlayerUtility.lplrIsAlive or not character or not RuntimeState.RootPart then return false end
    if getAttr(character, "Stun", false) or getAttr(character, "Ragdoll", false) then return false end
    if hasTag(character, "CantMove") or hasTag(character, "StopAnim") or hasTag(character, "KillAnims") then return false end
    return true
end

local hasBatteryItem = function(character)
    character = character or RuntimeState.Character
    return character and (hasTag(character, "Battery") or character:FindFirstChild("Battery") ~= nil) or false
end

local getTool = function()
    local character = RuntimeState.Character or lplr.Character or PlayerUtility.lplrCharacter
    RuntimeState.Tool = nil
    if not character then return nil end
    for _, child in ipairs(character:GetChildren()) do
        if child.ClassName == "Tool" then
            RuntimeState.Tool = child
            return child
        end
    end
    local axe = character:FindFirstChild("Axe")
    if axe then
        RuntimeState.Tool = axe
        return axe
    end
    return nil
end

local fireChannels = function(root, keywords, ...)
    if not root then return false end
    local args = table.pack(...)
    for _, d in ipairs(root:GetDescendants()) do
        local n     = toLower(d.Name); local match = false
        for _, kw in ipairs(keywords) do if n:find(kw, 1, true) then match = true; break end end
        if match then
            local ok = false
            if     d:IsA("RemoteEvent")      then ok = pcall(d.FireServer,   d, table.unpack(args, 1, args.n))
            elseif d:IsA("BindableEvent")    then ok = pcall(d.Fire,         d, table.unpack(args, 1, args.n))
            elseif d:IsA("RemoteFunction")   then ok = pcall(d.InvokeServer, d, table.unpack(args, 1, args.n))
            elseif d:IsA("BindableFunction") then ok = pcall(d.Invoke,       d, table.unpack(args, 1, args.n)) end
            if ok then return true end
        end
    end
    return false
end

local setBlock = function(holding)
    if RuntimeState.Blocking == holding then return end
    RuntimeState.Blocking = holding
    local tool = getTool()
    if tool then
        fireChannels(tool, {"block","guard","parry"}, holding)
    end
    if holding then if mouse2press   then pcall(mouse2press)   end
    else            if mouse2release then pcall(mouse2release) end end
end

local queueToolAnim = function(tool, value)
    if not tool or AutoSwingSettings.QueueSlash ~= true then return false end
    local toolAnim = tool:FindFirstChild("toolanim")
    if not toolAnim or toolAnim.ClassName ~= "StringValue" then
        toolAnim = Instance.new("StringValue")
        toolAnim.Name = "toolanim"
        toolAnim.Parent = tool
    end
    toolAnim.Value = value or "Slash"
    return true
end

local firePrimaryInput = function()
    if mouse1click then
        return pcall(mouse1click)
    elseif mouse1press and mouse1release then
        local ok = pcall(mouse1press)
        task.delay(0.03, function() pcall(mouse1release) end)
        return ok
    end
    return false
end

local faceTargetFlat = function(target)
    local root = RuntimeState.RootPart
    local targetPart = getPart(target)
    if not (root and targetPart) then return false end
    local source = root.Position
    local goal = Vector3.new(targetPart.Position.X, source.Y, targetPart.Position.Z)
    if (goal - source).Magnitude <= 0.01 then return false end
    root.CFrame = CFrame.lookAt(source, goal)
    return true
end

local swing = function(target)
    if not canAct() or hasBatteryItem() then return false end
    local tool = getTool()
    if AutoSwingSettings.FaceTarget then
        faceTargetFlat(target)
    end
    if tool then
        queueToolAnim(tool, "Slash")
        pcall(function() tool:Activate() end)
    end
    if tool or lkillr() then
        return firePrimaryInput() or tool ~= nil
    end
    return false
end

local isDone = function(instance)
    for _, flag in ipairs({"Done","Completed","Fixed","Repaired","Powered","Opened","Open","Finished"}) do
        if getAttr(instance, flag, nil) == true then return true end
    end
    local p = getAttr(instance, "Progress") or getAttr(instance, "Completion") or getAttr(instance, "Percent")
    return type(p) == "number" and p >= 100
end

local closestInteract = function(instances, keywords, maxDist)
    local best, bestPrompt, bestDist = nil, nil, maxDist or math.huge
    for _, instance in ipairs(instances or {}) do
        if instance and instance.Parent and not isDone(instance) then
            local prompt = findPrompt(instance, keywords) or findPrompt(instance)
            if prompt and prompt.Enabled then
                local dist = distTo(prompt.Parent or instance)
                if dist < bestDist then
                    best, bestPrompt, bestDist = instance, prompt, dist
                end
            end
        end
    end
    return best, bestPrompt, bestDist
end

local interact = function(target, keywords, promptOverride)
    local prompt = promptOverride or findPrompt(target, keywords) or findPrompt(target)
    if not prompt or isDone(target) then return false end
    local maxActivationDistance = math.max((prompt.MaxActivationDistance or 0) + 1.5, 8)
    local activationTarget = prompt.Parent or target
    if distTo(activationTarget) > maxActivationDistance then
        moveTo(activationTarget, 2.5); task.delay(0.05, function() firePrompt(prompt) end); return true
    end
    return firePrompt(prompt)
end

local isPostEffect = function(i)
    return i:IsA("BlurEffect") or i:IsA("ColorCorrectionEffect") or i:IsA("BloomEffect")
        or i:IsA("SunRaysEffect") or i:IsA("DepthOfFieldEffect")
end

local shouldHideGuiEffect = function(i)
    local n = toLower(i.Name)
    return n:find("static",1,true) or n:find("vignette",1,true) or n:find("blur",1,true) or n:find("blood",1,true) or n:find("noise",1,true) or n:find("flash",1,true)
end

local applyFB = function()
    if not SavedStates.Fullbright then
        SavedStates.Fullbright = {
            Brightness = Lighting.Brightness, Ambient = Lighting.Ambient,
            OutdoorAmbient = Lighting.OutdoorAmbient, ClockTime = Lighting.ClockTime,
            FogEnd = Lighting.FogEnd, GlobalShadows = Lighting.GlobalShadows,
        }
    end
    Lighting.Brightness = 2.5; Lighting.Ambient = Color3.fromRGB(175,175,175)
    Lighting.OutdoorAmbient = Color3.fromRGB(175,175,175); Lighting.ClockTime = 14
    Lighting.FogEnd = 100000; Lighting.GlobalShadows = false
end

local restoreFB = function()
    if not SavedStates.Fullbright then return end
    local fb = SavedStates.Fullbright
    Lighting.Brightness = fb.Brightness; Lighting.Ambient = fb.Ambient
    Lighting.OutdoorAmbient = fb.OutdoorAmbient; Lighting.ClockTime = fb.ClockTime
    Lighting.FogEnd = fb.FogEnd; Lighting.GlobalShadows = fb.GlobalShadows
    SavedStates.Fullbright = nil
end

local restoreCollision = function()
    for part, prev in pairs(SavedStates.CharacterCollision) do
        if typeof(part) == "Instance" and part.Parent and part:IsA("BasePart") then part.CanCollide = prev end
    end
    table.clear(SavedStates.CharacterCollision)
end

local noCollide = function()
    for _, d in ipairs(CharacterPartCache.Entries) do
        if d:IsA("BasePart") then
            if SavedStates.CharacterCollision[d] == nil then SavedStates.CharacterCollision[d] = d.CanCollide end
            d.CanCollide = false
        end
    end
end

local restoreTraps = function()
    for part, state in pairs(SavedStates.TrapParts) do
        if typeof(part) == "Instance" and part.Parent and part:IsA("BasePart") then
            part.CanCollide = state.CanCollide; part.Transparency = state.Transparency
            pcall(function() part.CanTouch = state.CanTouch end)
        end
    end
    table.clear(SavedStates.TrapParts)
end

local defusePart = function(part)
    if not part or not part:IsA("BasePart") then return end
    if SavedStates.TrapParts[part] == nil then
        SavedStates.TrapParts[part] = { CanCollide = part.CanCollide, CanTouch = part.CanTouch, Transparency = part.Transparency }
    end
    part.CanCollide = false; part.Transparency = math.max(part.Transparency, 0.55)
    pcall(function() part.CanTouch = false end)
end

local getHud = function()
    if RuntimeState.HudLabel and RuntimeState.HudLabel.Parent then return RuntimeState.HudLabel end
    local label = Instance.new("TextLabel")
    label.Name = "KillerDistanceHUD"; label.AnchorPoint = Vector2.new(0.5, 0)
    label.Position = UDim2.new(0.5, 0, 0, 20); label.Size = UDim2.new(0, 280, 0, 38)
    label.BackgroundColor3 = Color3.fromRGB(15,15,15); label.BackgroundTransparency = 0.25
    label.BorderSizePixel = 0; label.Font = Enum.Font.GothamBold
    label.TextColor3 = Color3.fromRGB(255,255,255); label.TextSize = 16
    label.TextStrokeTransparency = 0; label.Text = "Killer Distance: waiting..."
    label.Parent = OverlayGui; RuntimeState.HudLabel = label; return label
end

local removeHud = function()
    if RuntimeState.HudLabel then RuntimeState.HudLabel:Destroy(); RuntimeState.HudLabel = nil end
end

local removeESP = function(entry)
    if entry.Highlight then entry.Highlight:Destroy() end
    if entry.Billboard then entry.Billboard:Destroy() end
end

local clearESP = function(name)
    for inst, entry in pairs(ESPCache[name]) do removeESP(entry); ESPCache[name][inst] = nil end
end
local clearAllESP = function() for name in pairs(ESPCache) do clearESP(name) end end

local ESP_CONFIG = {
    Survivor = { MaxDist = 1000, ColorName = "Default", ShowHighlight = true, ShowLabel = true, VisibleOnly = false },
    Killer = { MaxDist = 1000, ColorName = "Default", ShowHighlight = true, ShowLabel = true, VisibleOnly = false },
    Generator = { MaxDist = 1000, ColorName = "Default", ShowHighlight = true, ShowLabel = true, VisibleOnly = false },
    FuseBox = { MaxDist = 1000, ColorName = "Default", ShowHighlight = true, ShowLabel = true, VisibleOnly = false },
    Battery = { MaxDist = 1000, ColorName = "Default", ShowHighlight = true, ShowLabel = true, VisibleOnly = false },
    Door = { MaxDist = 1000, ColorName = "Default", ShowHighlight = true, ShowLabel = true, VisibleOnly = false },
    Exit = { MaxDist = 1000, ColorName = "Default", ShowHighlight = true, ShowLabel = true, VisibleOnly = false },
    Beartrap = { MaxDist = 1000, ColorName = "Default", ShowHighlight = true, ShowLabel = true, VisibleOnly = false },
    Springtrap = { MaxDist = 1000, ColorName = "Default", ShowHighlight = true, ShowLabel = true, VisibleOnly = false },
    EnnardMinion = { MaxDist = 1000, ColorName = "Default", ShowHighlight = true, ShowLabel = true, VisibleOnly = false },
    Objective = { MaxDist = 1000, ColorName = "Default", ShowHighlight = true, ShowLabel = true, VisibleOnly = false },
}

local WallCheckEnabled = false
local DistanceESPEnabled = true
local resolveESPColor = function(bucketName)
    local cfg = ESP_CONFIG[bucketName]
    if cfg and cfg.ColorName and cfg.ColorName ~= "Default" then
        return ESPColorPresets[cfg.ColorName] or ESPColors[bucketName] or Color3.fromRGB(255, 255, 255)
    end
    return ESPColors[bucketName] or Color3.fromRGB(255, 255, 255)
end
local isVisible = function(targetPart)
    if not targetPart then return false end
    local camera = Workspace.CurrentCamera; if not camera then return true end
    local origin = camera.CFrame.Position; local direction = targetPart.Position - origin
    local params = RaycastParams.new(); params.FilterType = Enum.RaycastFilterType.Exclude
    local filtered = { camera }
    local char = RuntimeState.Character; if char then filtered[#filtered+1] = char end
    local ignF = Workspace:FindFirstChild("IGNORE"); local plyF = Workspace:FindFirstChild("PLAYERS")
    if ignF then filtered[#filtered+1] = ignF end; if plyF then filtered[#filtered+1] = plyF end
    params.FilterDescendantsInstances = filtered
    local result = Workspace:Raycast(origin, direction, params); if not result then return true end
    local hitInst = result.Instance
    return hitInst and (hitInst == targetPart or hitInst:IsDescendantOf(targetPart) or (targetPart.Parent and hitInst:IsDescendantOf(targetPart.Parent)))
end

local upsertESP = function(bucketName, instance, text, color)
    local part = getPart(instance); if not part then return end
    ESPCache[bucketName] = ESPCache[bucketName] or {}
    local cfg = ESP_CONFIG[bucketName] or {}
    local entry = ESPCache[bucketName][instance]
    if not entry then
        local hl = Instance.new("Highlight"); hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        hl.FillTransparency = 0.45; hl.OutlineTransparency = 0; hl.Parent = HighlightFolder
        local bb = Instance.new("BillboardGui"); bb.Name = bucketName .. "_ESP"
        bb.AlwaysOnTop = true; bb.Size = UDim2.new(0,160,0,44); bb.StudsOffset = Vector3.new(0,3.5,0)
        bb.MaxDistance = 1350; bb.Parent = OverlayGui
        local bg = Instance.new("Frame"); bg.Size = UDim2.new(1,0,1,0)
        bg.BackgroundColor3 = Color3.fromRGB(10,10,10); bg.BackgroundTransparency = 0.35
        bg.BorderSizePixel = 0; bg.Parent = bb
        local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0,6); corner.Parent = bg
        local pad = Instance.new("UIPadding"); pad.PaddingLeft = UDim.new(0,5); pad.PaddingRight = UDim.new(0,5); pad.Parent = bg
        local lbl = Instance.new("TextLabel"); lbl.BackgroundTransparency = 1
        lbl.Size = UDim2.new(1,0,1,0); lbl.Font = Enum.Font.GothamBold; lbl.TextSize = 12
        lbl.TextWrapped = true; lbl.TextStrokeTransparency = 0.5; lbl.RichText = false; lbl.Parent = bg
        entry = { Highlight = hl, Billboard = bb, Label = lbl }; ESPCache[bucketName][instance] = entry
    end
    local adornee = instance:IsA("Model") and instance or part
    if entry.Highlight.Adornee ~= adornee then entry.Highlight.Adornee = adornee end
    entry.Highlight.Enabled = cfg.ShowHighlight ~= false
    entry.Highlight.FillColor = color; entry.Highlight.OutlineColor = color
    if entry.Billboard.Adornee ~= part then entry.Billboard.Adornee = part end
    entry.Billboard.Enabled = cfg.ShowLabel ~= false
    entry.Billboard.MaxDistance = math.max((cfg.MaxDist or 500) + 50, 50)
    if entry.Label.Text ~= text then entry.Label.Text = text end
    if entry.Label.TextColor3 ~= color then entry.Label.TextColor3 = color end
end

local function updateESP(name, instances, textFn, color)
    ESPCache[name] = ESPCache[name] or {}
    local cache = ESPCache[name]
    local cfg = ESP_CONFIG[name] or { MaxDist = 500 }
    local maxD = cfg.MaxDist or 500
    local shouldWallCheck = WallCheckEnabled or cfg.VisibleOnly == true
    color = color or resolveESPColor(name)
    local candidates = {}
    for _, inst in ipairs(instances or {}) do
        if inst and inst.Parent then
            local part = getPart(inst)
            if part then
                local d = distTo(inst)
                if d <= maxD and (not shouldWallCheck or isVisible(part)) then
                    candidates[#candidates+1] = { inst = inst, dist = d }
                end
            end
        end
    end
    local seen = {}
    for _, c in ipairs(candidates) do
        local inst = c.inst
        local success, text = pcall(textFn, inst)
        if success and text and text ~= "" then
            seen[inst] = true; upsertESP(name, inst, text, color)
        end
    end
    for inst, entry in pairs(cache) do
        if not seen[inst] or not (inst and inst.Parent) then removeESP(entry); cache[inst] = nil end
    end
end

local function formatDist(instance)
    local d = distTo(instance); return d == math.huge and "?" or tostring(math.floor(d))
end

local function worldESP(prefix, instance)
    local progress = getAttr(instance,"Progress") or getAttr(instance,"Completion") or getAttr(instance,"Percent")
    local status = ""
    if type(progress) == "number" then status = string.format(" (%d%%)", math.floor(progress))
    elseif isDone(instance) then status = " [DONE]" end
    if DistanceESPEnabled then
        return string.format("%s%s\n[%s studs]", prefix, status, formatDist(instance))
    end
    return string.format("%s%s", prefix, status)
end

local function playerESP(character, showRole, role, showHealth, showStamina)
    local plr = Players:GetPlayerFromCharacter(character)
    local dispName = plr and plr.DisplayName or character.Name
    local lines = {}
    table.insert(lines, showRole and (role .. ": " .. dispName) or dispName)
    if showHealth then
        local hum = character:FindFirstChildOfClass("Humanoid")
        table.insert(lines, "HP: " .. tostring(math.floor(hum and hum.Health or 0)))
    end
    if showStamina then
        table.insert(lines, "STA: " .. tostring(math.floor(getAttr(character, "Stamina", 0) or 0)))
    end
    if DistanceESPEnabled then
        table.insert(lines, formatDist(character) .. " studs")
    end
    return table.concat(lines, "\n")
end

local function clickGui(keywords)
    local pg = PlayerGui or lplr:FindFirstChildOfClass("PlayerGui"); if not pg then return false end
    for _, d in ipairs(pg:GetDescendants()) do
        if d:IsA("GuiButton") then
            local cur, visible = d, true
            while cur and cur ~= pg do
                if cur:IsA("GuiObject") and not cur.Visible then visible = false; break end
                if cur:IsA("ScreenGui") and not cur.Enabled then visible = false; break end
                cur = cur.Parent
            end
            if visible then
                local blob = toLower(d.Name) .. (d:IsA("TextButton") and (" " .. toLower(d.Text)) or "")
                for _, kw in ipairs(keywords) do
                    if blob:find(kw, 1, true) then
                        if pcall(function() d:Activate() end) then return true end
                        if firesignal and pcall(function() firesignal(d.MouseButton1Click) end) then return true end
                    end
                end
            end
        end
    end
    return false
end

local function guiVisible(instance)
    local current = instance
    while current do
        if current:IsA("GuiObject") and not current.Visible then return false end
        if current:IsA("LayerCollector") and current.Enabled == false then return false end
        current = current.Parent
    end
    return instance ~= nil and instance.Parent ~= nil
end

local function clickGuiIn(root, keywords)
    if not root then return false end
    for _, d in ipairs(getDesc(root)) do
        if d:IsA("GuiButton") and guiVisible(d) then
            local blob = toLower(d.Name) .. (d:IsA("TextButton") and (" " .. toLower(d.Text)) or "")
            for _, kw in ipairs(keywords or {}) do
                if blob:find(kw, 1, true) then
                    if pcall(function() d:Activate() end) then return true end
                    if firesignal and pcall(function() firesignal(d.MouseButton1Click) end) then return true end
                end
            end
        end
    end
    return false
end

local function fireChannel(channel, ...)
    if not channel then return false end
    local args = table.pack(...)
    if     channel:IsA("RemoteEvent")      then return pcall(channel.FireServer,   channel, table.unpack(args, 1, args.n))
    elseif channel:IsA("BindableEvent")    then return pcall(channel.Fire,         channel, table.unpack(args, 1, args.n))
    elseif channel:IsA("RemoteFunction")   then return pcall(channel.InvokeServer, channel, table.unpack(args, 1, args.n))
    elseif channel:IsA("BindableFunction") then return pcall(channel.Invoke,       channel, table.unpack(args, 1, args.n)) end
    return false
end

local function getGeneratorPanel()
    local gui = PlayerGui or lplr:FindFirstChildOfClass("PlayerGui"); if not gui then return nil, nil, nil end
    local gen = gui:FindFirstChild("Gen")
    local generatorMain = gen and gen:FindFirstChild("GeneratorMain")
    local event = generatorMain and generatorMain:FindFirstChild("Event")
    return gen, generatorMain, event
end

local function solveGeneratorPanel(generatorMain, event)
    if generatorMain and guiVisible(generatorMain) then
        if clickGuiIn(generatorMain, PromptKeywords.Repair) then return true end
    end
    if event then
        for _, payload in ipairs(GeneratorSolverPayloads) do if fireChannel(event, payload) then return true end end
    end
    return false
end

local function getStaminaMax(character, fallback)
    return getAttr(character,"MaxStamina",nil) or getAttr(character,"StaminaMax",nil) or getAttr(character,"MaxSprint",nil)  or fallback or 100
end

local function refillStamina(character, fallback)
    if not character then return nil end
    local max = getStaminaMax(character, fallback) or 100
    local cur = getAttr(character, "Stamina", nil)
    if cur ~= max then setAttr(character, "Stamina", max) end
    return max
end

local function randEmote()
    local humanoid = RuntimeState.Humanoid or PlayerUtility.lplrHumanoid
    if not humanoid then return false end
    local emote = EMOTES[math.random(1, #EMOTES)]
    if pcall(function() humanoid:PlayEmote(emote) end) then return true end
    local pg = lplr:FindFirstChildOfClass("PlayerGui"); if not pg then return false end
    for _, d in ipairs(pg:GetDescendants()) do
        if d.Name == "PlayEmote" then
            if d:IsA("BindableFunction") then if pcall(function() d:Invoke(emote) end) then return true end
            elseif d:IsA("BindableEvent") then if pcall(function() d:Fire(emote) end) then return true end end
        end
    end
    return false
end

local ClickGUI = lib.ClickGUI
local Root = ClickGUI

local function IsMouseOverGUI()
    if not Root or not Root.Visible then
        return false
    end

    local mousePos = UserInputService:GetMouseLocation()
    
    for _, obj in ipairs(Root:GetDescendants()) do
        if obj:IsA("GuiObject") and obj.Visible then
            local pos = obj.AbsolutePosition
            local size = obj.AbsoluteSize
            
            if mousePos.X >= pos.X and mousePos.X <= pos.X + size.X and
               mousePos.Y >= pos.Y and mousePos.Y <= pos.Y + size.Y then
                return true
            end
        end
    end
    
    return false
end

ops:onExit("70845479499574_cleanup", function()
    for _, key in ipairs({
        "AutoBlock", "AutoSwing", "AntiConfusion", "AutoUnstun", "AntiRagdoll",
        "HideBlockAnim", "BlockCameraShake", "BlockKillerInvis", "BlockScreenEffects",
        "InfiniteStamina",                          -- FIX: was "Infinite Stamina" (mismatch)
        "NoClip", "AntiSlide", "AutoBarricade", "AutoEscape",
        "Fullbright", "AutoShake", "FastItemPickup", "AutoRepairGenerators",
        "AntiSpringtrapTraps", "KillerDistanceHUD", "AutoEmotePlayer",
        "SpeedBoost", "NoSlowdown",
        "SurvivorESP", "KillerESP", "GeneratorESP", "FuseBoxESP", "BatteryESP",
        "ExitESP", "BeartrapESP", "SpringtrapESP", "EnnardMinionsESP", "ObjectiveESP",
        "AutoDeliverBattery", "AntiBeartrapAura",
    }) do
        RunLoops:UnbindFromHeartbeat(key)
    end

    setBlock(false); restoreCollision(); restoreTraps(); restoreFB()
    clearAllESP(); removeHud()

    if ScreenEffectConnections then
        for _, connection in ipairs(ScreenEffectConnections) do connection:Disconnect() end
        ScreenEffectConnections = nil
    end

    connectiontouch1:Disconnect(); connectiontouch1 = nil
    connectiontouch2:Disconnect(); connectiontouch2 = nil

    setAttr(lplr, "ShowHitboxes", SavedStates.PlayerAttributes.ShowHitboxes ~= nil and SavedStates.PlayerAttributes.ShowHitboxes or false)
    setAttr(lplr, "ShowBarriers", SavedStates.PlayerAttributes.ShowBarriers ~= nil and SavedStates.PlayerAttributes.ShowBarriers or false)
    if SavedStates.PlayerAttributes.CameraShake ~= nil then setAttr(lplr, "CameraShake", SavedStates.PlayerAttributes.CameraShake) end

    disconnect("StunAlert"); disconnect("WorkspaceChildAdded"); disconnect("WorkspaceChildRemoved")
    disconnect("CharacterAdded"); disconnect("CharacterRemoving")
    disconnectConnections(CharacterConnections); clearEntryState(CharacterPartCache)
    disconnectConnections(PlayerFolderCache.RootConnections)
    disconnectConnections(PlayerFolderCache.Survivor.Connections)
    disconnectConnections(PlayerFolderCache.Killer.Connections)
    disconnectConnections(MapCache.Connections); disconnectConnections(MapCache.RootConnections)
    disconnectConnections(IgnoreCache.RootConnections); disconnectConnections(IgnoreCache.TrapConnections)
    for _, group in pairs(MapCache.Groups) do clearTrackedGroup(group) end

    if PlayerUtility.lplrHumanoid then
        pcall(function()
            PlayerUtility.lplrHumanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, true)
            PlayerUtility.lplrHumanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, true)
        end)
    end

    if OverlayGui then OverlayGui:Destroy() end
    if HighlightFolder then HighlightFolder:Destroy() end
end)

local function restoreScreenEffects()
    if not SavedStates or not SavedStates.ScreenEffects then return end
    for instance, prev in pairs(SavedStates.ScreenEffects) do
        if typeof(instance) == "Instance" and instance.Parent then
            if isPostEffect(instance) then instance.Enabled = prev
            elseif instance:IsA("GuiObject") then instance.Visible = prev end
        end
    end
    table.clear(SavedStates.ScreenEffects)
end

runcode(function()
    local CombatPanel = lib.Registry.combatPanel.API

    --[[CombatPanel.CreateOptionsButton({
        Name = "Auto Block",
        Function = function(callback)
            if callback then
                RunLoops:BindToHeartbeat("AutoBlock", function()
                    local tool = getTool()
                    if not tool then setBlock(false); return end
                    print("gfsgfsDgsdf")
                    if IsMouseOverGUI() then setBlock(false); return end
                    if not PlayerUtility.lplrIsAlive or not RuntimeState.RootPart then setBlock(false); return end
                    local target, distance = closestTarget(18)
                    local targetRoot = getPart(target)
                    if targetRoot then
                        local dir = (RuntimeState.RootPart.Position - targetRoot.Position)
                        local dot = dir.Magnitude > 0 and targetRoot.CFrame.LookVector:Dot(dir.Unit) or -1
                        setBlock(distance <= 9 or dot > 0.1)
                    else
                        setBlock(false)
                    end
                end)
            else
                RunLoops:UnbindFromHeartbeat("AutoBlock"); setBlock(false)
            end
        end
    })--]]
    local AutoSwing = CombatPanel.CreateOptionsButton({
        Name = "Auto Swing",
        Tooltip = "Automatically swings using the equipped tool flow and the game's normal primary input path.",
        Function = function(callback)
            if callback then
                RunLoops:BindToHeartbeat("AutoSwing", function()
                    if IsMouseOverGUI() then return end
                    if not canAct() or hasBatteryItem() then return end
                    local target, distance = closestTarget(AutoSwingSettings.Range)
                    if target and distance <= AutoSwingSettings.Range and throttle("AutoSwing", AutoSwingSettings.Delay) then
                        swing(target)
                    end
                end)
            else
                RunLoops:UnbindFromHeartbeat("AutoSwing")
            end
        end
    })
    AutoSwing.CreateSlider({
        Name = "Range",
        Min = 1,
        Max = 20,
        Default = AutoSwingSettings.Range,
        Round = 1,
        Function = function(value) AutoSwingSettings.Range = value end
    })
    AutoSwing.CreateSlider({
        Name = "Delay",
        Min = 0.05,
        Max = 0.5,
        Default = AutoSwingSettings.Delay,
        Round = 0.01,
        Function = function(value) AutoSwingSettings.Delay = value end
    })
    AutoSwing.CreateToggle({
        Name = "Face Target",
        Default = AutoSwingSettings.FaceTarget,
        Function = function(value) AutoSwingSettings.FaceTarget = value == true end
    })
    AutoSwing.CreateToggle({
        Name = "Queue Slash Anim",
        Default = AutoSwingSettings.QueueSlash,
        Function = function(value) AutoSwingSettings.QueueSlash = value == true end
    })
    CombatPanel.CreateOptionsButton({
        Name = "Anti Confusion",
        Function = function(callback)
            if callback then
                RunLoops:BindToHeartbeat("AntiConfusion", function()
                    if not PlayerUtility.lplrIsAlive then return end
                    removeTag(RuntimeState.Character, "Confusion")
                end)
            else
                RunLoops:UnbindFromHeartbeat("AntiConfusion")
            end
        end
    })
    CombatPanel.CreateOptionsButton({
        Name = "Auto Unstun",
        Function = function(callback)
            if callback then
                RunLoops:BindToHeartbeat("AutoUnstun", function()
                    if not PlayerUtility.lplrIsAlive or not RuntimeState.Character or not RuntimeState.Humanoid then return end
                    setAttr(RuntimeState.Character, "Stun", false)
                    removeTag(RuntimeState.Character, "CantMove")
                    removeTag(RuntimeState.Character, "StopAnim")
                    removeTag(RuntimeState.Character, "KillAnims")
                    RuntimeState.Humanoid.PlatformStand = false
                end)
            else
                RunLoops:UnbindFromHeartbeat("AutoUnstun")
            end
        end
    })
    CombatPanel.CreateOptionsButton({
        Name = "Stun Alert",
        Function = function(callback)
            if callback then
                disconnect("StunAlert"); RuntimeState.StunState = false
                if lplr.Character then
                    Connections.StunAlert = lplr.Character:GetAttributeChangedSignal("Stun"):Connect(function()
                        local stunned = lplr.Character and getAttr(lplr.Character, "Stun", false) or false
                        if stunned and not RuntimeState.StunState then notify("Stun Alert: you are stunned") end
                        RuntimeState.StunState = not not stunned
                    end)
                end
            else
                disconnect("StunAlert"); RuntimeState.StunState = false
            end
        end
    })
    CombatPanel.CreateOptionsButton({
        Name = "Anti Ragdoll",
        Function = function(callback)
            if callback then
                RunLoops:BindToHeartbeat("AntiRagdoll", function()
                    if not PlayerUtility.lplrIsAlive or not RuntimeState.Character or not RuntimeState.Humanoid then return end
                    setAttr(RuntimeState.Character, "Ragdoll", false)
                    removeTag(RuntimeState.Character, "Ragdoll")
                    pcall(function()
                        RuntimeState.Humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
                        RuntimeState.Humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
                    end)
                    RuntimeState.Humanoid.PlatformStand = false
                    local state = RuntimeState.Humanoid:GetState()
                    if state == Enum.HumanoidStateType.Ragdoll or state == Enum.HumanoidStateType.FallingDown or state == Enum.HumanoidStateType.PlatformStanding then
                        RuntimeState.Humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
                    end
                end)
            else
                RunLoops:UnbindFromHeartbeat("AntiRagdoll")
                local hum = RuntimeState.Humanoid or PlayerUtility.lplrHumanoid
                if hum then
                    pcall(function()
                        hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, true)
                        hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, true)
                    end)
                end
            end
        end
    })
    CombatPanel.CreateOptionsButton({
        Name = "Hide Block Animation",
        Function = function(callback)
            if callback then
                RunLoops:BindToHeartbeat("HideBlockAnim", function()
                    if not PlayerUtility.lplrIsAlive or not PlayerUtility.lplrHumanoid then return end
                    for _, track in ipairs(PlayerUtility.lplrHumanoid:GetPlayingAnimationTracks()) do
                        local n = toLower(track.Name .. " " .. (track.Animation and track.Animation.Name or ""))
                        if n:find("block",1,true) or n:find("guard",1,true) or n:find("parry",1,true) then
                            pcall(function() track:Stop(0) end)
                        end
                    end
                end)
            else
                RunLoops:UnbindFromHeartbeat("HideBlockAnim")
            end
        end
    })

    CombatPanel.CreateOptionsButton({
        Name = "Block Camera Shake",
        Function = function(callback)
            if callback then
                RunLoops:BindToHeartbeat("BlockCameraShake", function()
                    setAttr(lplr, "CameraShake", false)
                end)
            else
                RunLoops:UnbindFromHeartbeat("BlockCameraShake")
                if SavedStates.PlayerAttributes.CameraShake ~= nil then
                    setAttr(lplr, "CameraShake", SavedStates.PlayerAttributes.CameraShake)
                end
            end
        end
    })

    CombatPanel.CreateOptionsButton({
        Name = "Block Killer Invisibility",
        Function = function(enabled)
            if enabled then
                local cachedParts = {}
                local function cacheKiller(killer)
                    if cachedParts[killer] then return end
                    cachedParts[killer] = {}
                    for _, d in ipairs(killer:GetDescendants()) do
                        if d:IsA("BasePart") then table.insert(cachedParts[killer], d) end
                    end
                end
                RunLoops:BindToHeartbeat("BlockKillerInvis", function()
                    for _, killer in ipairs(getKillerCharacters()) do
                        cacheKiller(killer)
                        removeTag(killer, "UNDETECTABLE"); removeTag(killer, "INVIS")
                        for _, part in ipairs(cachedParts[killer]) do
                            if part then
                                local orig = part:GetAttribute("OGTransparency")
                                if orig ~= nil then part.Transparency = orig end
                                part.LocalTransparencyModifier = 0
                                removeTag(part, "UNDETECTABLE"); removeTag(part, "INVIS")
                            end
                        end
                    end
                end)
            else
                RunLoops:UnbindFromHeartbeat("BlockKillerInvis")
            end
        end
    })

    local handleInstance = function(i)
        if isPostEffect(i) then
            if SavedStates.ScreenEffects[i] == nil then SavedStates.ScreenEffects[i] = i.Enabled end
            i.Enabled = false
        elseif i:IsA("GuiObject") and shouldHideGuiEffect(i) then
            if SavedStates.ScreenEffects[i] == nil then SavedStates.ScreenEffects[i] = i.Visible end
            i.Visible = false
        end
    end

    CombatPanel.CreateOptionsButton({
        Name = "Block Screen Effects",
        Function = function(enabled)
            if enabled then
                SavedStates.ScreenEffects = SavedStates.ScreenEffects or {}
                for _, i in ipairs(Lighting:GetChildren()) do handleInstance(i) end
                local pg = lplr:FindFirstChildOfClass("PlayerGui")
                if pg then for _, i in ipairs(pg:GetDescendants()) do handleInstance(i) end end
                ScreenEffectConnections = {}
                table.insert(ScreenEffectConnections, Lighting.ChildAdded:Connect(handleInstance))
                if pg then table.insert(ScreenEffectConnections, pg.DescendantAdded:Connect(handleInstance)) end
            else
                if ScreenEffectConnections then
                    for _, c in ipairs(ScreenEffectConnections) do c:Disconnect() end
                    ScreenEffectConnections = nil
                end
                restoreScreenEffects()
            end
        end
    })
end)

runcode(function()
    local MovementPanel = lib.Registry.blatantPanel.API

    MovementPanel.CreateOptionsButton({
        Name = "Speed Boost",
        Function = function(callback)
            if callback then
                local char = RuntimeState.Character or PlayerUtility.lplrCharacter
                if char then
                    SavedStates.SpeedBoost.WalkSpeed = getAttr(char, "WalkSpeed", nil)
                    SavedStates.SpeedBoost.RunSpeed = getAttr(char, "RunSpeed",  nil)
                end
                RunLoops:BindToHeartbeat("InfiniteStamina", function()
                    local character = RuntimeState.Character
                    if not character or not PlayerUtility.lplrIsAlive then return end

                    local max = getStaminaMax(character, 100)
                    setAttr(character, "Stamina", max)

                    setAttr(character, "CanRun", true)

                    removeTag(character, "Battery")
                    removeTag(character, "SlowStop")
                    removeTag(character, "CantMove")

                    local curWalk = getAttr(character, "WalkSpeed", 0)
                    local curRun = getAttr(character, "RunSpeed",  0)
                    if type(curWalk) == "number" and curWalk < 16 then setAttr(character, "WalkSpeed", 30) end
                    if type(curRun) == "number" and curRun < 24 then setAttr(character, "RunSpeed", 30) end
                end)
            else
                RunLoops:UnbindFromHeartbeat("InfiniteStamina")
                local char = RuntimeState.Character or PlayerUtility.lplrCharacter
                if char then
                    if SavedStates.SpeedBoost.WalkSpeed ~= nil then setAttr(char, "WalkSpeed", SavedStates.SpeedBoost.WalkSpeed) end
                    if SavedStates.SpeedBoost.RunSpeed  ~= nil then setAttr(char, "RunSpeed",  SavedStates.SpeedBoost.RunSpeed)  end
                end
                SavedStates.SpeedBoost.WalkSpeed = nil; SavedStates.SpeedBoost.RunSpeed = nil
            end
        end
    })

    MovementPanel.CreateOptionsButton({
        Name = "Anti Slide After Stop",
        Function = function(callback)
            if callback then
                RunLoops:BindToHeartbeat("AntiSlide", function()
                    if not PlayerUtility.lplrIsAlive or not RuntimeState.Character or not RuntimeState.Humanoid or not RuntimeState.RootPart then return end
                    removeTag(RuntimeState.Character, "SlowStop")
                    if RuntimeState.Humanoid.MoveDirection.Magnitude <= 0.05 then
                        RuntimeState.RootPart.AssemblyLinearVelocity = Vector3.new(0, RuntimeState.RootPart.AssemblyLinearVelocity.Y, 0)
                    end
                end)
            else
                RunLoops:UnbindFromHeartbeat("AntiSlide")
            end
        end
    })

    MovementPanel.CreateOptionsButton({
        Name = "No Slowdown",
        Function = function(callback)
            if callback then
                RunLoops:BindToHeartbeat("NoSlowdown", function()
                    local character = RuntimeState.Character
                    if not character or not PlayerUtility.lplrIsAlive then return end
                    removeTag(character, "SlowStop"); removeTag(character, "CantMove"); removeTag(character, "Confusion")
                    local customSpd = getAttr(character, "CustomSpeed", nil)
                    if type(customSpd) == "number" and customSpd < 14 then setAttr(character, "CustomSpeed", nil) end
                end)
            else
                RunLoops:UnbindFromHeartbeat("NoSlowdown")
            end
        end
    })

    MovementPanel.CreateOptionsButton({
        Name = "Anti Beartrap Aura",
        Function = function(callback)
            if callback then
                RunLoops:BindToHeartbeat("AntiBeartrapAura", function()
                    if not PlayerUtility.lplrIsAlive or lkillr() then return end
                    if not throttle("AntiBeartrapAura", 0.08) then return end
                    for _, trap in ipairs(getBeartraps()) do
                        local part = getPart(trap)
                        if part and distTo(part) <= 25 then
                            local defuseTarget = trap:IsA("Model") and trap or (trap.Parent and trap.Parent:IsA("Model") and trap.Parent or nil)
                            if defuseTarget then
                                for _, d in ipairs(defuseTarget:GetDescendants()) do
                                    if d:IsA("BasePart") then defusePart(d) end
                                end
                            else
                                defusePart(part)
                            end
                            if distTo(part) <= 4 and RuntimeState.RootPart then
                                RuntimeState.RootPart.CFrame = RuntimeState.RootPart.CFrame + Vector3.new(0, 5, 0)
                            end
                        end
                    end
                end)
            else
                RunLoops:UnbindFromHeartbeat("AntiBeartrapAura"); restoreTraps()
            end
        end
    })
end)

runcode(function()
    local RenderPanel = lib.Registry.renderPanel.API
    local HealthESP = false
    local StaminaESP = false
    RenderPanel.CreateOptionsButton({ Name = "Wall Check", Function = function(cb) WallCheckEnabled = cb == true; clearAllESP() end })
    RenderPanel.CreateOptionsButton({ Name = "Health ESP", Function = function(cb) HealthESP = cb == true; clearESP("Survivor"); clearESP("Killer") end })
    RenderPanel.CreateOptionsButton({ Name = "Stamina ESP", Function = function(cb) StaminaESP = cb == true; clearESP("Survivor"); clearESP("Killer") end })
    RenderPanel.CreateOptionsButton({ Name = "Distance ESP", Function = function(cb) DistanceESPEnabled = cb == true; clearAllESP() end })

    local makeESPButton = function(name, bucketName, instanceFn, textFn)
        local loopKey = name:gsub("%s", "")
        local cfg = ESP_CONFIG[bucketName] or {}
        local handle = RenderPanel.CreateOptionsButton({
            Name = name,
            Function = function(callback)
                if callback then
                    RunLoops:BindToHeartbeat(loopKey, function()
                        if not throttle(loopKey .. "Tick", 0.15) then return end
                        pcall(function() updateESP(bucketName, instanceFn(), textFn, resolveESPColor(bucketName)) end)
                    end)
                else
                    RunLoops:UnbindFromHeartbeat(loopKey); clearESP(bucketName)
                end
            end
        })
        handle.CreateSlider({
            Name = "Max Dist",
            Min = 10,
            Max = 1000,
            Default = cfg.MaxDist or 150,
            Round = 5,
            Function = function(value) cfg.MaxDist = value; clearESP(bucketName) end
        })
        handle.CreateDropdown({
            Name = "Color",
            List = ESPColorNames,
            Default = cfg.ColorName or "Default",
            Function = function(value) cfg.ColorName = value; clearESP(bucketName) end
        })
        handle.CreateToggle({
            Name = "Highlight",
            Default = cfg.ShowHighlight ~= false,
            Function = function(value) cfg.ShowHighlight = value == true; clearESP(bucketName) end
        })
        handle.CreateToggle({
            Name = "Label",
            Default = cfg.ShowLabel ~= false,
            Function = function(value) cfg.ShowLabel = value == true; clearESP(bucketName) end
        })
        handle.CreateToggle({
            Name = "Visible Only",
            Default = cfg.VisibleOnly == true,
            Function = function(value) cfg.VisibleOnly = value == true; clearESP(bucketName) end
        })
        return handle
    end

    makeESPButton("Survivor ESP", "Survivor", getSurvivorCharacters, function(c) return playerESP(c, true, "Survivor", HealthESP, StaminaESP) end)
    makeESPButton("Killer ESP", "Killer", getKillerCharacters, function(c) return playerESP(c, true, "Killer", HealthESP, StaminaESP) end)
    makeESPButton("Generator ESP", "Generator", getGenerators, function(i) return worldESP("Generator", i) end)
    makeESPButton("FuseBox ESP", "FuseBox", getFuseBoxes, function(i) return worldESP("Fuse Box", i) end)
    makeESPButton("Battery ESP", "Battery", getBatteries, function(i) return worldESP("Battery", i) end)
    --makeESPButton("Door ESP", "Door", getDoors, function(i) return worldESP("Door", i) end)
    makeESPButton("Exit ESP", "Exit", getExits, function(i) return worldESP("Exit", i) end)
    makeESPButton("Beartrap ESP", "Beartrap", getBeartraps, function(i) return worldESP("Beartrap", i) end)
    makeESPButton("Springtrap ESP", "Springtrap", getSpringtrapTraps, function(i) return worldESP("Springtrap Trap", i) end)
    makeESPButton("Ennard Minions ESP", "EnnardMinion", getEnnardMinions, function(i) return worldESP("Ennard Minion", i) end)
    makeESPButton("Objective ESP", "Objective", getObjectives, function(i) return worldESP("Objective", i) end)

    RenderPanel.CreateOptionsButton({
        Name = "Hitbox Viewer",
        Function = function(callback)
            setAttr(lplr, "ShowHitboxes", callback and true or (SavedStates.PlayerAttributes.ShowHitboxes ~= nil and SavedStates.PlayerAttributes.ShowHitboxes or false))
        end
    })
    RenderPanel.CreateOptionsButton({
        Name = "Barrier Viewer",
        Function = function(callback)
            setAttr(lplr, "ShowBarriers", callback and true or (SavedStates.PlayerAttributes.ShowBarriers ~= nil and SavedStates.PlayerAttributes.ShowBarriers or false))
        end
    })
end)

runcode(function()
    local MovementPanel = lib.Registry.utillityPanel.API
    MovementPanel.CreateOptionsButton({
        Name = "Auto Escape",
        Function = function(callback)
            if callback then
                RunLoops:BindToHeartbeat("AutoEscape", function()
                    if not PlayerUtility.lplrIsAlive or lkillr() then return end
                    if not throttle("AutoEscape", 0.45) then return end

                    local char = lplr.Character
                    if not char then return end

                    local gameObj = workspace:FindFirstChild("GAME")
                    if gameObj and gameObj:FindFirstChild("CAN_ESCAPE") then
                        if not gameObj.CAN_ESCAPE.Value then return end
                    end

                    local playersFolder = workspace:FindFirstChild("PLAYERS")
                    if not playersFolder or char.Parent ~= playersFolder:FindFirstChild("ALIVE") then return end

                    local mapsFolder = workspace:FindFirstChild("MAPS")
                    local gameMap = mapsFolder and mapsFolder:FindFirstChild("GAME MAP")
                    local escapes = gameMap and gameMap:FindFirstChild("Escapes")
                    if not escapes then return end

                    local teleported = false

                    for _, part in pairs(escapes:GetChildren()) do
                        if part:IsA("BasePart") and part:GetAttribute("Enabled") then
                            local highlight = part:FindFirstChildOfClass("Highlight")
                            if highlight and highlight.Enabled then
                                local root = char:FindFirstChild("HumanoidRootPart")
                                if root and not teleported then
                                    teleported = true
                                    root.Anchored = true
                                    root.CFrame = part.CFrame
                                    task.delay(1.5, function()
                                        if root then root.Anchored = false end
                                    end)
                                    task.delay(10, function()
                                        teleported = false
                                    end)
                                end
                            end
                        end
                    end

                    if not teleported then
                        local exitTarget = closestIn(getExits(), 250)
                        if exitTarget then
                            interact(exitTarget, {"escape","exit","open","leave"})
                        else
                            local exitPrompt = findMapPrompt({"escape","exit","leave"}, 250)
                            if exitPrompt then
                                interact(exitPrompt, {"escape","exit","leave"})
                            end
                        end
                    end
                end)
            else
                RunLoops:UnbindFromHeartbeat("AutoEscape")
            end
        end
    })
    MovementPanel.CreateOptionsButton({
        Name = "NoClip",
        Function = function(callback)
            if callback then
                RunLoops:BindToHeartbeat("NoClip", function()
                    if not PlayerUtility.lplrIsAlive or not RuntimeState.Character then return end
                    noCollide()
                end)
            else
                RunLoops:UnbindFromHeartbeat("NoClip"); restoreCollision()
            end
        end
    })

    MovementPanel.CreateOptionsButton({
        Name = "Auto Barricade",
        Function = function(callback)
            if callback then
                RunLoops:BindToHeartbeat("AutoBarricade", function()
                    if not PlayerUtility.lplrIsAlive or lkillr() then return end
                    if not throttle("AutoBarricade", 0.5) then return end
                    local door = closestIn(getDoors(), 60, function(instance) return not getAttr(instance, "HOLD", false) end)
                    if door then interact(door, {"barricade"}) end
                end)
            else
                RunLoops:UnbindFromHeartbeat("AutoBarricade")
            end
        end
    })
    MovementPanel.CreateOptionsButton({
        Name = "Fullbright",
        Function = function(callback)
            if callback then RunLoops:BindToHeartbeat("Fullbright", function() applyFB() end)
            else RunLoops:UnbindFromHeartbeat("Fullbright"); restoreFB() end
        end
    })
end)

runcode(function()
    local AutoPanel = lib.Registry.worldPanel.API

    AutoPanel.CreateOptionsButton({
        Name = "Auto Shake",
        Function = function(callback)
            if callback then
                RunLoops:BindToHeartbeat("AutoShake", function()
                    if not PlayerUtility.lplrIsAlive then return end
                    if not throttle("AutoShake", 0.08) then return end
                    if not clickGui(PromptKeywords.Recovery) then
                        local prompt = findPrompt(RuntimeState.Character, PromptKeywords.Recovery) or findMapPrompt(PromptKeywords.Recovery, 20, isRecoveryPrompt)
                        if prompt then firePrompt(prompt) end
                    end
                end)
            else
                RunLoops:UnbindFromHeartbeat("AutoShake")
            end
        end
    })

    AutoPanel.CreateOptionsButton({
        Name = "Instant interaction",
        Tooltip = "Instantly interacts with nearby objects.",
        Function = function(callback)
            if callback then
                RunLoops:BindToHeartbeat("FastItemPickup", function()
                    if not PlayerUtility.lplrIsAlive or lkillr() then return end
                    if not throttle("FastItemPickup", 0.12) then return end
                    local RANGE = 10
                    for _, entry in ipairs({
                        { Objects = getBatteries(), Keywords = PromptKeywords.Pickup },
                        { Objects = getFuseBoxes(), Keywords = PromptKeywords.Insert },
                        { Objects = getDoors(), Keywords = PromptKeywords.Barricade },
                        { Objects = getExits(), Keywords = PromptKeywords.Exit },
                    }) do
                        local target, prompt, dist = closestInteract(entry.Objects, entry.Keywords, RANGE)
                        if target and prompt and dist <= RANGE and isPromptInputHeld(prompt) then
                            interact(target, entry.Keywords, prompt)
                            return
                        end
                    end
                    local prompt, dist = findMapPrompt(nil, RANGE, function(candidate)
                        return not isRecoveryPrompt(candidate) and isPromptInputHeld(candidate)
                    end)
                    if prompt and dist <= RANGE then firePrompt(prompt) end
                end)
            else
                RunLoops:UnbindFromHeartbeat("FastItemPickup")
            end
        end
    })

    AutoPanel.CreateOptionsButton({
        Name = "Auto Repair Generators",
        Function = function(enabled)
            if enabled then
                RunLoops:BindToHeartbeat("AutoRepairGenerators", function()
                    if not PlayerUtility.lplrIsAlive or lkillr() then return end
                    local _, generatorMain, event = getGeneratorPanel()
                    if not (generatorMain and guiVisible(generatorMain)) then return end
                    if not throttle("AutoRepairGeneratorsSolve", 0.05) then return end
                    solveGeneratorPanel(generatorMain, event)
                end)
            else
                RunLoops:UnbindFromHeartbeat("AutoRepairGenerators")
            end
        end
    })

    AutoPanel.CreateOptionsButton({
        Name = "Anti Springtrap Traps",
        Function = function(callback)
            if callback then
                RunLoops:BindToHeartbeat("AntiSpringtrapTraps", function()
                    if not PlayerUtility.lplrIsAlive or lkillr() then return end
                    if not throttle("AntiSpringtrapTraps", 0.1) then return end
                    local closestTrap, closestDist = closestIn(getSpringtrapTraps(), 20)
                    if closestTrap then
                        local defuseTarget = closestTrap:IsA("Model") and closestTrap or (closestTrap.Parent and closestTrap.Parent:IsA("Model") and closestTrap.Parent or nil)
                        if defuseTarget then
                            for _, d in ipairs(defuseTarget:GetDescendants()) do
                                if d:IsA("BasePart") then defusePart(d) end
                            end
                        else
                            local part = getPart(closestTrap)
                            if part then defusePart(part) end
                        end
                        if closestDist <= 6 and RuntimeState.RootPart then
                            RuntimeState.RootPart.CFrame = RuntimeState.RootPart.CFrame + Vector3.new(0, 4, 0)
                        end
                    end
                end)
            else
                RunLoops:UnbindFromHeartbeat("AntiSpringtrapTraps"); restoreTraps()
            end
        end
    })


    -- working on this sorry lol
    --[[AutoPanel.CreateOptionsButton({
        Name = "Auto Deliver Battery",
        Function = function(callback)
            if callback then
                RunLoops:BindToHeartbeat("AutoDeliverBattery", function()
                    if not PlayerUtility.lplrIsAlive or lkillr() then return end
                    if not throttle("AutoDeliverBattery", 0.4) then return end

                    local char = RuntimeState.Character; if not char then return end
                    local hasBattery = hasBatteryItem(char)

                    if hasBattery then
                        local fuseBox, prompt = closestInteract(getFuseBoxes(), PromptKeywords.Insert, 300)
                        if fuseBox then
                            interact(fuseBox, PromptKeywords.Insert, prompt)
                        end
                    else
                        local battery, prompt = closestInteract(getBatteries(), PromptKeywords.Pickup, 200)
                        if battery then
                            interact(battery, PromptKeywords.Pickup, prompt)
                        end
                    end
                end)
            else
                RunLoops:UnbindFromHeartbeat("AutoDeliverBattery")
            end
        end
    })--]]
end)

runcode(function()
    local MiscPanel = lib.Registry.miscPanel.API
    local CreditsButton

    MiscPanel.CreateOptionsButton({
        Name = "Killer Distance HUD",
        Function = function(callback)
            if callback then
                RunLoops:BindToHeartbeat("KillerDistanceHUD", function()
                    pcall(function()
                        local label = getHud(); if not label then return end
                        local killer, distance = closestKiller(250)
                        if killer and distance and distance < math.huge then
                            label.Text = "Killer Distance: " .. math.floor(distance) .. " studs"
                            label.TextColor3 = distance <= 20 and Color3.fromRGB(255,90,90) or Color3.fromRGB(255,255,255)
                        else
                            label.Text = "Killer Distance: none"
                            label.TextColor3 = Color3.fromRGB(255,255,255)
                        end
                    end)
                end)
            else
                RunLoops:UnbindFromHeartbeat("KillerDistanceHUD"); pcall(removeHud)
            end
        end
    })

    MiscPanel.CreateOptionsButton({
        Name = "Auto Emote Player",
        Function = function(callback)
            if callback then
                RunLoops:BindToHeartbeat("AutoEmotePlayer", function()
                    pcall(function()
                        if not throttle("AutoEmotePlayer", 10) then return end
                        if PlayerUtility.lplrIsAlive and RuntimeState.RootPart and RuntimeState.RootPart.AssemblyLinearVelocity and RuntimeState.RootPart.AssemblyLinearVelocity.Magnitude <= 2 and not getAttr(RuntimeState.Character, "Stun", false) then
                            randEmote()
                        end
                    end)
                end)
            else
                RunLoops:UnbindFromHeartbeat("AutoEmotePlayer")
            end
        end
    })

    local roleHud = nil
    MiscPanel.CreateOptionsButton({
        Name = "Role Indicator",
        Function = function(callback)
            if callback then
                if not roleHud or not roleHud.Parent then
                    local lbl = Instance.new("TextLabel")
                    lbl.Name = "RoleIndicator"; lbl.AnchorPoint = Vector2.new(1, 0)
                    lbl.Position = UDim2.new(1, -8, 0, 8); lbl.Size = UDim2.new(0, 120, 0, 30)
                    lbl.BackgroundColor3 = Color3.fromRGB(10,10,10); lbl.BackgroundTransparency = 0.35
                    lbl.BorderSizePixel = 0; lbl.Font = Enum.Font.GothamBold
                    lbl.TextSize = 14; lbl.TextStrokeTransparency = 0; lbl.Parent = OverlayGui
                    Instance.new("UICorner", lbl).CornerRadius = UDim.new(0, 6)
                    roleHud = lbl
                end
                RunLoops:BindToHeartbeat("RoleIndicator", function()
                    if not roleHud or not roleHud.Parent then return end
                    if not throttle("RoleIndicatorTick", 0.5) then return end
                    if lkillr() then
                        roleHud.Text = "KILLER"
                        roleHud.TextColor3 = Color3.fromRGB(255, 90, 90)
                    elseif PlayerUtility.lplrIsAlive then
                        roleHud.Text = "SURVIVOR"
                        roleHud.TextColor3 = Color3.fromRGB(120, 255, 120)
                    else
                        roleHud.Text = "SPECTATOR"
                        roleHud.TextColor3 = Color3.fromRGB(200, 200, 200)
                    end
                end)
            else
                RunLoops:UnbindFromHeartbeat("RoleIndicator")
                if roleHud then roleHud:Destroy(); roleHud = nil end
            end
        end
    })

    local survivorCountHud = nil
    MiscPanel.CreateOptionsButton({
        Name = "Survivor Count",
        Function = function(callback)
            if callback then
                if not survivorCountHud or not survivorCountHud.Parent then
                    local lbl = Instance.new("TextLabel")
                    lbl.Name = "SurvivorCount"; lbl.AnchorPoint = Vector2.new(0.5, 0)
                    lbl.Position = UDim2.new(0.5, 0, 0, 65); lbl.Size = UDim2.new(0, 230, 0, 30)
                    lbl.BackgroundColor3 = Color3.fromRGB(10,10,10); lbl.BackgroundTransparency = 0.35
                    lbl.BorderSizePixel = 0; lbl.Font = Enum.Font.GothamBold
                    lbl.TextColor3 = Color3.fromRGB(120, 255, 120); lbl.TextSize = 14
                    lbl.TextStrokeTransparency = 0; lbl.Parent = OverlayGui
                    Instance.new("UICorner", lbl).CornerRadius = UDim.new(0, 6)
                    survivorCountHud = lbl
                end
                RunLoops:BindToHeartbeat("SurvivorCount", function()
                    if not survivorCountHud or not survivorCountHud.Parent then return end
                    if not throttle("SurvivorCountTick", 1.0) then return end
                    local count = #getSurvivorCharacters()
                    survivorCountHud.Text = "Survivors Alive: " .. count
                    survivorCountHud.TextColor3 = count <= 1 and Color3.fromRGB(255, 90, 90) or  Color3.fromRGB(120, 255, 120)
                end)
            else
                RunLoops:UnbindFromHeartbeat("SurvivorCount")
                if survivorCountHud then survivorCountHud:Destroy(); survivorCountHud = nil end
            end
        end
    })
end)
