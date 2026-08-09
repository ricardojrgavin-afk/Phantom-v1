local getcustomasset = getcustomasset or function(location)
    return
end
local request = syn and syn.request or http and http.request or http_request or request or function() end
local queueteleport = queue_for_teleport or queue_on_teleport or queueonteleport

local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Teams = game:GetService("Teams")
local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")

local lplr = Players.LocalPlayer
local Camera = workspace.CurrentCamera

local UI, ops = phantom.UI, phantom.ops
local GuiLibrary, funcs = UI, ops
local Runtime = funcs.runtime
local RunLoops = Runtime.RunLoops
local runcode = Runtime.run
local createNotification = GuiLibrary.toast

local Prediction = phantom.module:Load("prediction") or loadstring(readfile("Phantom/lib/Prediction.lua"))()
local DrawLibrary = phantom.module:Load("fly") or loadstring(readfile("Phantom/lib/fly.lua"))()

local PlayerUtility = {connections = {}, localConnections = {}, lplrIsAlive = false}

local entities = {"entity", "GolemBoss"}
local entityBlacklist = {"BarrelEntity"}
local newData

local chr
local humanoid
local root
local died
local team
local disconnect = function(con)
    if type(con) == "function" then
        con()
    elseif con then
        if con.Disconnect then
            con:Disconnect()
        elseif con.disconnect then
            con:disconnect()
        elseif con.Destroy then
            con:Destroy()
        elseif con.destroy then
            con:destroy()
        elseif con.DoCleaning then
            con:DoCleaning()
        end
    end
end

local disconnectAll = function(bucket)
    for i = #bucket, 1, -1 do
        disconnect(bucket[i])
        bucket[i] = nil
    end
end

local connect = function(signal, func, bucket)
    local connector = signal and (signal.Connect or signal.connect)
    if not connector then return end
    local connection = connector(signal, func)
    table.insert(bucket or PlayerUtility.connections, connection)
    return connection
end

local resetlplrentity = function()
    disconnectAll(PlayerUtility.localConnections)
    chr = nil
    humanoid = nil
    root = nil
    died = false
    team = nil
    PlayerUtility.lplrIsAlive = false
    PlayerUtility.character = nil
    PlayerUtility.humanoid = nil
    PlayerUtility.rootPart = nil
    PlayerUtility.team = nil
end

local updatelplrentity = function(v : Model)
    resetlplrentity()
    if not v then return end

    chr = v
    humanoid = v:WaitForChild("Humanoid")
    root = v:WaitForChild("HumanoidRootPart")
    team = v:GetAttribute("Team")
    PlayerUtility.lplrIsAlive = true
    PlayerUtility.character = chr
    PlayerUtility.humanoid = humanoid
    PlayerUtility.rootPart = root
    PlayerUtility.team = team

    connect(humanoid.Died, function()
        PlayerUtility.lplrIsAlive = false
        died = true
    end, PlayerUtility.localConnections)
    connect(v:GetAttributeChangedSignal("Team"), function()
        team = v:GetAttribute("Team")
        PlayerUtility.team = team
    end, PlayerUtility.localConnections)
end

task.spawn(function()
    updatelplrentity(lplr.Character or lplr.CharacterAdded:Wait())
end)

connect(lplr.CharacterAdded, updatelplrentity)
connect(lplr.CharacterRemoving, resetlplrentity)
-- task.spawn(function()
--     repeat
--         task.wait()
--     until lplr.Character
--     updatelplrentity(lplr.Character)
-- end)
-- lplr.CharacterRemoving:Connect(function()
--     chr = nil
--     humanoid = nil
--     root = nil
--     died = false
-- end)

local entityCache = {}
local newData = {
    statistics = {
        Reported = {},
        ReportedCount = 0,
    },
    queueType = "",
    matchState = 0,
    customMatch = false,
    Attacking = false,
    attackingEntity = nil,
    blocks = {},
    blockRaycast = RaycastParams.new(),
    clientStore = {},
    queueInfo = {},
    zephyrOrb = 0,
    speedMultiplier = 0,
    hookEvents = {
        damageHooks = {},
        deathHooks = {}
    },
}

local findEntity = function(entity)
    return entityCache[entity] or (entity:IsA("Player") and entity.Character and entityCache[entity.Character]) or nil
end

local hookEntity = function(entity)
    if table.find(entityBlacklist, entity.Name) or findEntity(entity) then return end

    local data = {
        entity = nil,
        humanoid = nil,
        health = nil,
        isGhost = nil,
        forcefield = nil,
        team = nil
    }

    if entity:IsA("Player") then
        if not entity.Character then return end
        data.entity = entity.Character

        data.humanoid = data.entity:WaitForChild("Humanoid", 1)
        if not data.humanoid then return end

        data.health = data.humanoid.Health or 100
        connect(data.humanoid.HealthChanged, function(health)
            data.health = health
        end)

        data.forcefield = data.entity:FindFirstChildOfClass("ForceField") or data.forcefield
        connect(data.entity.ChildAdded, function(c)
            if c.ClassName == "ForceField" then
                data.forcefield = c
            end
        end)
        connect(data.entity.ChildRemoved, function(c)
            if c == data.forcefield then
                data.forcefield = nil
            end
        end)

        data.team = entity:GetAttribute("Team") or data.team
        connect(data.entity:GetAttributeChangedSignal("Team"), function()
            data.team = entity:GetAttribute("Team") or data.team
        end)
    else
        data.entity = entity
        data.health = entity:GetAttribute("Health") or 0
        data.team = entity:GetAttribute("Team") or data.team

        connect(data.entity:GetAttributeChangedSignal("Health"), function()
            data.health = entity:GetAttribute("Health") or data.health
        end)
        connect(data.entity:GetAttributeChangedSignal("Team"), function()
            data.team = entity:GetAttribute("Team") or data.team
        end)

        connect(entity.AncestryChanged, function(_, parent)
            if not parent then
                entityCache[entity] = nil
            end
        end)
    end

    if entity:IsA("Player") then
        entityCache[entity] = data
    end
    entityCache[data.entity] = data
    return data
end

local watchPlayer = function(player)
    if player == lplr then return end
    connect(player.CharacterAdded, function()
        entityCache[player] = nil
        hookEntity(player)
    end)
    connect(player.CharacterRemoving, function(character)
        entityCache[player] = nil
        entityCache[character] = nil
    end)
    if player.Character then
        hookEntity(player)
    end
end

task.spawn(function()
    for _, v in Players:GetPlayers() do
        watchPlayer(v)
    end
end)
connect(Players.PlayerAdded, watchPlayer)
connect(Players.PlayerRemoving, function(player)
    entityCache[player] = nil
    if player.Character then
        entityCache[player.Character] = nil
    end
end)

PlayerUtility.IsAlive = function(entity, healthCheck, forcefieldCheck)
    entity = entity or lplr
    local shouldCheckHealth = healthCheck ~= true

    if entity == lplr then
        return chr and root and humanoid and ((shouldCheckHealth and not died) or not shouldCheckHealth)
    else
        local cEntity = findEntity(entity)
        if not cEntity then
            cEntity = hookEntity(entity)
        end

        if not cEntity then return nil end
        if forcefieldCheck and cEntity.forcefield then return false end
        return ((cEntity.humanoid and cEntity.humanoid.Health > 0) or (cEntity.health and cEntity.health > 0)) or nil
    end

    -- if entity.ClassName == "Player" then
    --     local humanoid = entity.Character and entity.Character:FindFirstChild("Humanoid")
    --     return humanoid and humanoid.Health > 0 and humanoid:GetState() ~= Enum.HumanoidStateType.Dead
    -- else
    --     local health = entity:GetAttribute("Health") or nil
    --     return health and health > 0
    -- end
end

PlayerUtility.isTargetable = function(entity)
    return PlayerUtility.IsAlive(entity, false, true)
end

PlayerUtility.EntityVisible = function(startPos, targetPos)
    return not workspace:Raycast(startPos, (targetPos - startPos).Unit * (targetPos - startPos).Magnitude, newData.blockRaycast)
end

task.spawn(function()
    for _, type in entities do
        for _, entity in CollectionService:GetTagged(type) do
            hookEntity(entity)
        end
        connect(CollectionService:GetInstanceAddedSignal(type), function(entity)
            hookEntity(entity)
        end)
    end
end)

-- entity:GetAttribute("GhostForm")
PlayerUtility.getNearestEntities = function(maxDist, findNearestHealthEntity, teamCheck, sortFunction, raycheck)
    if not PlayerUtility.IsAlive() then return end

    local selfPos = lplr.Character.PrimaryPart.Position
    if not selfPos then return end

    local filteredEntities = {}
    local seenEntities = {}

    for _, entity in entityCache do
        if entity.entity and not seenEntities[entity.entity] and PlayerUtility.isTargetable(entity.entity) then
            seenEntities[entity.entity] = true
            local EntityRootPart = entity.entity.PrimaryPart
            if EntityRootPart then
                local mag = (EntityRootPart.Position - selfPos).Magnitude
                local wallcheck = raycheck and PlayerUtility.EntityVisible(selfPos, EntityRootPart.Position) or true
                if wallcheck and mag <= maxDist and (not teamCheck or entity.team ~= team) then
                    table.insert(filteredEntities, {
                        entity = entity.entity,
                        distance = mag,
                        health = entity.health,
                    })
                end
            end
        end
    end
    
    local sortFunction = sortFunction or (findNearestHealthEntity == "Health" and function(a, b)
        return a.health < b.health
    end) or (findNearestHealthEntity == "Distance" and function(a, b)
        return a.distance < b.distance
    end)
    table.sort(filteredEntities, sortFunction)

    return filteredEntities
end

PlayerUtility.EnemyToMouse = function(fov, teamCheck)
    local closestEnemy = nil
    local closestDistance = fov
    local mousePosition = UserInputService:GetMouseLocation()

    for _, v in pairs(Players:GetPlayers()) do
        if v ~= lplr and v.Team ~= lplr.Team and v.Character and v.Character:FindFirstChild("HumanoidRootPart") then
            local rootPart = v.Character.HumanoidRootPart
            local screenPoint = Camera:WorldToViewportPoint(rootPart.Position)
            local distanceFromMouse = (Vector2.new(screenPoint.X, screenPoint.Y) - mousePosition).Magnitude

            if distanceFromMouse < closestDistance and (not teamCheck or v:GetAttribute("Team") ~= team) then
                closestDistance = distanceFromMouse
                closestEnemy = v
            end
        end
    end

    return closestEnemy
end

PlayerUtility.getNearestEntity = function(maxDist, findNearestHealthEntity, teamCheck, sortFunction)
    local entities = PlayerUtility.getNearestEntities(maxDist, findNearestHealthEntity or "Distance", teamCheck, sortFunction)
    return entities and entities[1] and entities[1].entity or nil
end

PlayerUtility.GetEntityNearMouse = PlayerUtility.EnemyToMouse
PlayerUtility.GetNearestEntities = PlayerUtility.getNearestEntities
PlayerUtility.GetNearestEntity = PlayerUtility.getNearestEntity

PlayerUtility.clones = {}
PlayerUtility.createClone = function(mirrorMovement, allowCollision)
    chr.Archivable = true
    local clone = chr:Clone()

    for _, v in clone:GetDescendants() do
        if v:IsA("BasePart") then
            if allowCollision then
                v.CollisionGroup = "Default"
            end
            v.Massless = true
        end
        if v:IsA("LocalScript") then
            v:Destroy()
        end
    end

    local cons = {}
    if mirrorMovement then
        table.insert(cons, chr.Humanoid:GetPropertyChangedSignal("MoveDirection"):Connect(function()
            clone.Humanoid:Move(chr.Humanoid.MoveDirection)
        end))
        table.insert(cons, chr.Humanoid.StateChanged:Connect(function(_, new)
            clone.Humanoid:ChangeState(new)
        end))
        clone.Humanoid:ChangeState(chr.Humanoid:GetState())
        clone.Humanoid:Move(chr.Humanoid.MoveDirection)
    end

    chr:FindFirstChild("Animate"):Clone().Parent = clone
    clone.Parent = chr
    clone.Humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None

    PlayerUtility.clones[clone] = cons
    return clone
end

PlayerUtility.destroyClone = function(clone)
    if PlayerUtility.clones[clone] then
        clone:Destroy()

        for _, v in PlayerUtility.clones[clone] do
            v:Disconnect()
        end
        PlayerUtility.clones[clone] = nil
    end
end

PlayerUtility.cleanupClones = function()
    for v, _ in PlayerUtility.clones do
        v:Destroy()
    end
    PlayerUtility.clones = {}
end

newData.blockRaycast.FilterType = Enum.RaycastFilterType.Include

newData.blocks = CollectionService:GetTagged("block")
newData.blockRaycast.FilterDescendantsInstances = newData.blocks

task.spawn(function()
    table.insert(newData.blocks, workspace:WaitForChild("SpectatorPlatform"))
    newData.blockRaycast.FilterDescendantsInstances = newData.blocks
end)

task.spawn(function()
    table.insert(newData.blocks, workspace:WaitForChild("Lobby"))
    newData.blockRaycast.FilterDescendantsInstances = newData.blocks
end)

task.spawn(function()
    table.insert(newData.blocks, workspace:WaitForChild("Terrain"))
    newData.blockRaycast.FilterDescendantsInstances = newData.blocks
end)

local KnitClient = require(ReplicatedStorage.rbxts_include.node_modules["@easy-games"].knit.src.Knit.KnitClient)
local knit = KnitClient
local Client = require(ReplicatedStorage.TS.remotes).default.Client
local Flamework = require(ReplicatedStorage["rbxts_include"]["node_modules"]["@flamework"].core.out).Flamework
local InventoryUtil = require(ReplicatedStorage.TS.inventory["inventory-util"]).InventoryUtil
local ItemTable = require(game:GetService("ReplicatedStorage").TS.item["item-meta"]).items
repeat task.wait() until Flamework.isInitialized

repeat
    task.wait()
until lplr:GetAttribute("LobbyConnected") and lplr.Character

funcs:onExit("clones", PlayerUtility.cleanupClones)
-- pcall(function() -- force fuck around with simradius
--     if hookmetamethod then
--         local hook
--         hook = hookmetamethod(game, "__index", function(self, index, ...)
--             if not checkcaller() then
--                 if self == lplr and string.lower(index) == "simulationradius" then
--                     return math.huge
--                 end
--             end

--             return hook(self, index, ...)
--         end)
        
--         funcs:onExit("simradius", function()
--             hookmetamethod(game, "__index", hook)
--         end)
--     end
--     lplr.SimulationRadius = math.huge -- trigger change
-- end)

local blockAdded = CollectionService:GetInstanceAddedSignal("block"):Connect(function(block)
    table.insert(newData.blocks, block)
    newData.blockRaycast.FilterDescendantsInstances = newData.blocks
end)

local blockRemoved = CollectionService:GetInstanceRemovedSignal("block"):Connect(function(block)
    local blockIndex = table.find(newData.blocks, block)
    if blockIndex then
        table.remove(newData.blocks, blockIndex)
        newData.blockRaycast.FilterDescendantsInstances = newData.blocks
    end
end)

funcs:onExit("pUtil", function()
    disconnectAll(PlayerUtility.localConnections)
    disconnectAll(PlayerUtility.connections)
end)
funcs:onExit("blockAdded", function()
    blockAdded:Disconnect()
end)
funcs:onExit("blockRemoved", function()
    blockRemoved:Disconnect()
end)

local runcode = function(func) -- stays like this because stuff needs to load properly
    return func()
end

for _, v in ipairs({
    "AntiAFK", "Antideath", "Gravity", "FovChanger", "ESP",
    "Cape", "AimAssist", "AntiFall", "Speed", "Fly", "NoClip",
    "AutoClicker", "FastStop", "FPSBooster", "AnimationPlayer", "BreadCrumbs"
}) do
    UI.kit:deregister(v .. "Module")
end

local function getremote(t)
    for i, v in pairs(t) do
        if v == "Client" then
            local tab = t[i + 1]
            return tab
        end
    end
    return ""
end

local playerScripts = lplr:WaitForChild("PlayerScripts")
local function getcont(name, meta)
    local controller = KnitClient.Controllers[name] or knit.Controllers[name]
    if controller and meta then
        return getmetatable(controller) or controller
    end
    return controller
end

local function resolveDependency(path)
    local ok, result = pcall(Flamework.resolveDependency, path)
    return ok and result or nil
end

local controllers = {
    ItemDropController = getcont("ItemDropController"),
    SprintController = getcont("SprintController"),
    SwordController = getcont("SwordController"),
    ViewmodelController = getcont("ViewmodelController"),
    QueueController = getcont("QueueController"),
    LockerController = getcont("LockerController"),
    WindWalkerController = getcont("WindWalkerController"),
    JumpHeightController = getcont("JumpHeightController"),
    DamageIndicatorController = getcont("DamageIndicatorController", true),
    EmeraldSwordController = getcont("EmeraldSwordController", true),
    BatteryEffectsController = getcont("BatteryEffectsController", true),
    ProjectileControllerObject = getcont("ProjectileController"),
    ProjectileController = getcont("ProjectileController", true),
}

local bedwars = setmetatable({
    Controllers = controllers,
    ItemTable = ItemTable,
    KnockbackUtil = require(ReplicatedStorage.TS.damage["knockback-util"]).KnockbackUtil,
    DropItem = controllers.ItemDropController and controllers.ItemDropController.dropItemInHand,
    AnimationType = require(ReplicatedStorage.TS.animation["animation-type"]).AnimationType,
    SoundList = require(ReplicatedStorage.TS.sound["game-sound"]).GameSound,
    AbilityController = resolveDependency("@easy-games/game-core:client/controllers/ability/ability-controller@AbilityController"),
    ClientHandlerStore = require(playerScripts.TS.ui.store).ClientStore,
    CombatConstant = require(ReplicatedStorage.TS.combat["combat-constant"]).CombatConstant,
    BlockController = require(ReplicatedStorage["rbxts_include"]["node_modules"]["@easy-games"]["block-engine"].out).BlockEngine,
    PartyController = require(ReplicatedStorage.rbxts_include.node_modules["@easy-games"].lobby.out.client.controllers["party-controller"]).PartyController,
    CombatController = require(playerScripts.TS.controllers.game.combat["combat-controller"]).CombatController,
    KillEffectMeta = require(ReplicatedStorage.TS.locker["kill-effect"]["kill-effect-meta"]).KillEffectMeta,
    InteractionRegistryController = require(playerScripts.TS.controllers.global.interaction["interaction-registry-controller"]).InteractionRegistryController,
    SoundManager = require(ReplicatedStorage["rbxts_include"]["node_modules"]["@easy-games"]["game-core"].out).SoundManager,
    InventoryEntity = require(ReplicatedStorage.TS.entity.entities["inventory-entity"]).InventoryEntity,
    ShopItems = require(ReplicatedStorage.TS.games.bedwars.shop["bedwars-shop"]).BedwarsShop.ShopItems,
    SprintController = controllers.SprintController,
    SwordController = controllers.SwordController,
    ViewmodelController = controllers.ViewmodelController,
    QueueController = controllers.QueueController,
    LockerController = controllers.LockerController,
    WindWalkerController = controllers.WindWalkerController,
    JumpHeightController = controllers.JumpHeightController,
    ProjectileControllerObject = controllers.ProjectileControllerObject,
    DamageIndicatorController = controllers.DamageIndicatorController,
    EmeraldSwordController = controllers.EmeraldSwordController,
    BatteryEffectsController = controllers.BatteryEffectsController,
    BowConstantsTable = KnitClient.Controllers.ProjectileController and debug.getupvalue(KnitClient.Controllers.ProjectileController.enableBeam, 8),
    ProjectileController = controllers.ProjectileController,
    blockBreaker = require(ReplicatedStorage["rbxts_include"]["node_modules"]["@easy-games"]["block-engine"].out.shared.remotes).BlockEngineRemotes.Client,
    EmoteMeta = require(ReplicatedStorage.TS.locker.emote["emote-meta"]).EmoteMeta,
    TitleMeta = require(ReplicatedStorage.TS.locker.title["title-meta"]).TitleMeta,
    WinEffectMeta = require(ReplicatedStorage.TS.locker["win-effect"]["win-effect-meta"]).WinEffectMeta,
    LobbyGadgetMeta = require(ReplicatedStorage.TS.locker["lobby-gadget"]["lobby-gadget-meta"]).LobbyGadgetMeta,
    ZapNetworking = require(playerScripts.TS.lib.network),
    ProjectileMeta = require(ReplicatedStorage.TS.projectile['projectile-meta']).ProjectileMeta,
    TSremotes = require(ReplicatedStorage.TS.remotes).default,
    remotes = {
        PickupRemote = ReplicatedStorage["rbxts_include"]["node_modules"]["@rbxts"].net.out["_NetManaged"].PickupItemDrop,
        ConsumeItem = ReplicatedStorage.rbxts_include.node_modules["@rbxts"].net.out._NetManaged.ConsumeItem,
        PlaceBlock = ReplicatedStorage.rbxts_include.node_modules["@easy-games"]["block-engine"].node_modules["@rbxts"].net.out._NetManaged.PlaceBlock,
        TeamRemote = ReplicatedStorage.rbxts_include.node_modules["@rbxts"].net.out._NetManaged["CustomMatches/SelectTeam"],
        AttackRemote = controllers.SwordController and getremote(debug.getconstants(controllers.SwordController.sendServerRequest)) or "",
        ProjectileFire = ReplicatedStorage.rbxts_include.node_modules["@rbxts"].net.out._NetManaged.ProjectileFire,
        SetObservedChest = Client:GetNamespace("Inventory"):Get("SetObservedChest"),
        AckKnockback = ReplicatedStorage.rbxts_include.node_modules["@rbxts"].net.out._NetManaged.AckKnockback,
        ChestGetItem = ReplicatedStorage:WaitForChild("rbxts_include"):WaitForChild("node_modules"):FindFirstChild("@rbxts").net.out._NetManaged:FindFirstChild("Inventory/ChestGetItem"),
        EntityDamageEvent = Client:Get("EntityDamageEvent"),
        EntityDeathEvent = Client:Get("EntityDeathEvent")
    },
}, {
    __index = function(_, index)
        return controllers[index] or KnitClient.Controllers[index] or knit.Controllers[index]
    end
})

bedwars.inventory = nil
bedwars.inventoryFolder = nil
bedwars.inventoryIndex = nil
bedwars.Inventory = function()
    return InventoryUtil.getInventory(lplr)
end

bedwars.getIcon = function(item, showinv)
    return (ItemTable[item.itemType] and ItemTable[item.itemType].image)
end

local inventoryStorage = ReplicatedStorage.Inventories

local chrCFrame
do
    local primPart

    RunLoops:BindToHeartbeat("chrCFrame", function()
        if PlayerUtility.lplrIsAlive then
            primPart = (lplr.Character and lplr.Character.PrimaryPart) or nil
            if not primPart then return end

            chrCFrame = primPart.CFrame or chrCFrame
        end
    end)
end

local updateInventory = function()
    if bedwars.inventory and bedwars.inventory.Parent == inventoryStorage then return end
    local inv

    repeat
        task.wait()
    until PlayerUtility.lplrIsAlive
    
    repeat
        inv = lplr.Character and lplr.Character:WaitForChild("InventoryFolder", 1)
        task.wait()
    until inv and inv.Value

    bedwars.inventoryFolder = inv.Value
    bedwars.inventory = bedwars.inventoryFolder
    bedwars.inventoryIndex = bedwars.inventory:GetChildren()
    local cons = {}
    table.insert(cons, bedwars.inventory.ChildAdded:Connect(function(v)
        table.insert(bedwars.inventoryIndex, v)
    end))
    table.insert(cons, bedwars.inventory.ChildRemoved:Connect(function(v)
        local tbl = table.find(bedwars.inventoryIndex, v)
        if tbl then
            table.remove(bedwars.inventoryIndex, tbl)
        end
    end))
    funcs:onExit("inventoryIndexUpdate", function()
        for _, v in cons do
            v:Disconnect()
        end
    end)
end

local revert
local unlockAll = {}
local cosmeticData = {
    emotes = bedwars.EmoteMeta,
    titles = bedwars.TitleMeta,
    killEffects = bedwars.KillEffectMeta,
    lobbyGadgets = bedwars.LobbyGadgetMeta,
    winEffects = bedwars.WinEffectMeta,
    --breakBedEffect = bedwars.BreakBedEffectMeta
}
local cosmeticConfig = (isfile("Phantom/storage/cache/lockerConfig.json") and HttpService:JSONDecode(readfile("Phantom/storage/cache/lockerConfig.json"))) or {
    Attributes = {},
    Selected = {
        selectedEmotes = {}
    }
}

for i, v in cosmeticData do
    local tbl = {}
    for i, _ in v do
        table.insert(tbl, i)
    end
    cosmeticData[i] = tbl
end

local updateStore
do
    local ogFunc = bedwars.ClientHandlerStore.getState
    local storeConnection
    local applyStoreState = function(store)
        if unlockAll.Enabled and not revert then
            revert = {}
            for i, v in cosmeticData do
                revert[i] = store.Locker[i]
                store.Locker[i] = v
            end
            for i, v in cosmeticConfig.Selected do
                if i ~= cosmeticConfig.Selected.selectedEmotes or cosmeticConfig.Selected.selectedEmotes > 0 then
                    store.Locker[i] = v
                end
            end
        end
        if not unlockAll.Enabled and revert then
            for i, v in revert do
                store.Locker[i] = v
            end
            revert = nil
        end

        newData.clientStore = store
        newData.matchState = store.Game.matchState
        newData.queueType = store.Game.queueType or "bedwars_test"
        newData.customMatch = store.Game.customMatch
        getgenv().phantomBedwarsNewData = store
        return store
    end

    bedwars.ClientHandlerStore.getState = function(...)
        return applyStoreState(ogFunc(...))
    end
    updateStore = function()
        return applyStoreState(ogFunc(bedwars.ClientHandlerStore))
    end

    if bedwars.ClientHandlerStore.subscribe then
        local ok, result = pcall(function()
            return bedwars.ClientHandlerStore:subscribe(updateStore)
        end)
        if ok then
            storeConnection = result
        end
    elseif bedwars.ClientHandlerStore.changed then
        storeConnection = connect(bedwars.ClientHandlerStore.changed, updateStore)
    end
    funcs:onExit("clientHandlerStoreUnHook", function()
        bedwars.ClientHandlerStore.getState = ogFunc or bedwars.ClientHandlerStore.getState
        disconnect(storeConnection)
    end)
end

task.spawn(function()
    updateStore()
end)

-- KnitClient.Controllers.PermissionController.permissions = {
--     "anticheat_mod",
--     "all_kit_skins",
--     "all_kits"
-- }


local function getPlacedBlock(pos)
	local roundedPosition = bedwars.BlockController:getBlockPosition(pos)
	return bedwars.BlockController:getStore():getBlockAt(roundedPosition), roundedPosition
end

-- RunLoops:BindToHeartbeat("inventory", function()
--     if PlayerUtility.lplrIsAlive and lplr.Character:FindFirstChild("InventoryFolder") then
--         if not bedwars.inventoryFolder then
--             bedwars.inventoryFolder = lplr.Character.InventoryFolder
--             local newInventory = lplr.Character.InventoryFolder.Value
--             if newInventory ~= bedwars.inventory then
--                 bedwars.inventory = newInventory
--             end
--             bedwars.inventoryFolder:GetPropertyChangedSignal("Value"):Connect(function()
--                 if newInventory ~= bedwars.inventory then
--                     bedwars.inventory = newInventory
--                 end
--             end)
--         end
--     else
--         bedwars.inventoryFolder = nil
--     end
-- end)

local swords = {}
local consumables = {}

for i, v in bedwars.ItemTable do
    if v.sword then
        swords[i] = v
    end
    if v.consumable then
        consumables[i] = v
    end
end
table.remove(consumables, table.find(consumables, "diamond"))

local findItemInventory = function(scan, sword)
    for i, v in scan do
        if v.itemType == sword.Name then
            return v
        end
    end
end

local lastSword
local updateSword = function()
    local bestSword, bestSwordDamage = nil, 0
    for _, item in bedwars.inventoryIndex do
        local swordMeta = swords[item.Name]
        if swordMeta then
            swordMeta = swordMeta.sword
            local swordDamage = swordMeta.damage or 0
            if swordDamage > bestSwordDamage then
                bestSword, bestSwordDamage = item, swordDamage
            end
        end
    end
    lastSword = bestSword and findItemInventory(bedwars.Inventory(lplr).items, bestSword) or lastSword
end

local function getSword()
    if not lastSword or not lastSword.tool or lastSword.tool.Parent ~= bedwars.inventory then
        updateSword()
    end
    return lastSword
end

local function getserverpos(Position)
    local x = math.round(Position.X/3)
    local y = math.round(Position.Y/3)
    local z = math.round(Position.Z/3)
    return Vector3.new(x,y,z)
end

local function getItem(itm, path)
    if PlayerUtility.lplrIsAlive then
        for _, v in bedwars.inventoryIndex do
            if v.Name == itm then
                return v
            end
        end
    end
end

local switchtool
local switchItem
local handInvItem
local setupHandInvItem
local fakeHandInvItem
local updateSpeedMultiplier

updateInventory()
do
    local con
    con = inventoryStorage.ChildAdded:Connect(updateInventory)
    funcs:onExit("inventoryBind", function()
        con:Disconnect()
    end)
end

--credit tos vape veryyyy sorryy my got patched :(
do
    local con

    con = bedwars.ZapNetworking.EntityDamageEventZap.On(function(...)
        local args = {
            entityInstance = ...,
            damage = select(2, ...),
            damageType = select(3, ...),
            fromPosition = select(4, ...),
            fromEntity = select(5, ...),
            knockbackMultiplier = select(6, ...),
            knockbackId = select(7, ...),
            disableDamageHighlight = select(13, ...)
        }

        if args.fromEntity and args.fromEntity == lplr.Character then
            for _, v in newData.hookEvents.damageHooks do
                task.spawn(v, args)
            end
        end
    end)

    funcs:onExit("entityDamageEventBind", function()
        if con then
            con:Disconnect()
            con = nil
        end
    end)
end

-- setupHandInvItem = function()
--     repeat
--         task.wait()
--     until PlayerUtility.lplrIsAlive

--     repeat
--         handInvItem = lplr.Character and lplr.Character:FindFirstChild("HandInvItem")
--         task.wait()
--     until handInvItem

--     local mt = {
--         HandInvItem = fakeHandInvItem
--     }

--     function mt:FindFirstChild(...)
--         return lplr.Character:FindFirstChild(...)
--     end

--     local construct = setmetatable(mt, {
--         __index = function(_, i)
--             local val = (i and lplr.Character[i]) or lplr.Character
            
--             if type(val) == "function" then
--                 return loadstring("return game.Players.LocalPlayer.Character:" .. i .. "()")
--             end
    
--             return val
--         end
--     })
--     print(construct.Parent[lplr.Character.Name].HandInvItem:GetFullName())

--     bedwars.InventoryEntity.equipItem = function(...)
--         local args = {...}
--         args[1].instance = (args[1].player == lplr and construct.Parent[lplr.Character.Name]) or args[1].instance
--         return ogFunc(unpack(args))
--     end

--     funcs:onExit("handInvItemOgFunc", function()
--         bedwars.InventoryEntity.equipItem = ogFunc or bedwars.InventoryEntity.equipItem
--     end)
-- end

setupHandInvItem = function()
    repeat
        task.wait()
    until PlayerUtility.lplrIsAlive
    handInvItem = lplr.Character:FindFirstChild("realHandInvItem") or lplr.Character:WaitForChild("HandInvItem")

    handInvItem.Name = "realHandInvItem"
    fakeHandInvItem = lplr.Character:FindFirstChild("HandInvItem") or Instance.new("ObjectValue", lplr.Character)
    fakeHandInvItem.Name = "HandInvItem"
end

switchItem = function(name)
    if not handInvItem.Parent then
        setupHandInvItem()
    end
    
    bedwars.InventoryEntity.player = lplr
    bedwars.InventoryEntity.instance = lplr.Character
    if name then
        if handInvItem and handInvItem.Value and handInvItem.Value.Name == name then
            return
        end
        local hasItem = bedwars.inventory:FindFirstChild(name)
        if hasItem then
            bedwars.InventoryEntity:equipItem(hasItem)
            -- local timeout = tick()
            repeat
                task.wait()
            until (handInvItem.Value and handInvItem.Value.Name == name)
        end
    else
        local viewmodelItem = Camera:FindFirstChild("Viewmodel") and Camera.Viewmodel:FindFirstChildWhichIsA("Accessory")
        local hasItem = viewmodelItem and bedwars.inventory and bedwars.inventory:FindFirstChild(viewmodelItem.Name)
        if hasItem then
            bedwars.InventoryEntity:equipItem(hasItem)
        end
    end
end
switchtool = switchItem

task.spawn(function()
    setupHandInvItem()
end)
-- switchItem()

local speedBoostValues = {
    GrimReaperChannel = 18,
    BatteryOverload = 18,
    SpeedPieBuff = 5.5
}

local speedState = {
    boost = 0,
    expiresAt = 0
}

updateSpeedMultiplier = function()
    if not chr then
        newData.speedMultiplier = 0
        return 0
    end

    local baseMultiplier = 0
    local characterAttributes = chr:GetAttributes()

    if typeof(characterAttributes.SpeedBoost) == "number" then
        local speedBoostMultiplier = characterAttributes.SpeedBoost
        baseMultiplier = baseMultiplier + (speedBoostMultiplier * 7.8)
    end

    for i, v in characterAttributes do
        if v then
            baseMultiplier = baseMultiplier + (speedBoostValues[i] or 0)
        end
    end

    if newData.zephyrOrb ~= 0 then
        baseMultiplier = baseMultiplier + 18
    end

    if characterAttributes.Kitbeast and lplr:FindFirstChild("leaderstats") and lplr.leaderstats:FindFirstChild("Bed") and lplr.leaderstats.Bed.Value ~= "✅" and lplr.Character:FindFirstChild("ExtraCharacterParts") and lplr.Character.ExtraCharacterParts:FindFirstChild("BeastActivated") then
        baseMultiplier = 40
    end

    if chr:FindFirstChild("speed_boots_left") and chr:FindFirstChild("speed_boots_right") then
        baseMultiplier = baseMultiplier + 12
    end

    if tick() <= speedState.expiresAt then
        baseMultiplier = baseMultiplier + speedState.boost
    end

    newData.speedMultiplier = baseMultiplier
    return baseMultiplier
end

local function setSpeedBoost(value, duration)
    speedState.boost = value or 0
    speedState.expiresAt = duration and (tick() + duration) or 0
    return updateSpeedMultiplier()
end

local function clearSpeedBoost()
    speedState.boost = 0
    speedState.expiresAt = 0
    return updateSpeedMultiplier()
end

local function SpeedMultiplier()
    return newData.speedMultiplier or 0
end

do
    RunLoops:BindToHeartbeat("speedMultiplier", updateSpeedMultiplier)
    funcs:onExit("speedMultiplier", function()
        RunLoops:UnbindFromHeartbeat("speedMultiplier")
    end)
end

if bedwars.WindWalkerController then
    local oldZephyrUpdate = bedwars.WindWalkerController.updateJump
    bedwars.WindWalkerController.updateJump = function(self, orb, ...)
        newData.zephyrOrb = PlayerUtility.lplrIsAlive and orb or 0
        updateSpeedMultiplier()
        return oldZephyrUpdate(self, orb, ...)
    end
    funcs:onExit("windWalkerController", function()
        bedwars.WindWalkerController.updateJump = oldZephyrUpdate or bedwars.WindWalkerController.updateJump
    end)
end

local AttackAnim = {}
local Swing = {}
local NoBob = {}
local oldViewmodelAnimation
local scaleFactor = 0
local viewmodelCheck = function(Self, id, ...)
    local id = id
    if Swing.Enabled and AttackAnim.Enabled and id == 15 and newData.Attacking and newData.attackingEntity then
        return
    end
    if NoBob.Enabled and id == 19 then
        id = 11
    end
    return id
end

-- #FUCKTHEINTERP KILLAURA
local reachDistance = {}
local nearestEntities = {}
local Distance = {["Value"] = 21}
local clone
local LongFly = {}
local LongFlyItemSwitch
local ProjItemSwitch
local SpeedSlider = {}
runcode(function()
    local Killaura = {}
    local Angle = {}
    local AnimationDropdown = {}
    local playerAdornments = {}
    local lazer = {}
    local AuraSort = {}
    local Indicator = {}
    local Raycast = {}
    local FacePlayer = {}
    local ShowTarget = {}
    local VMAnimActive = false
    local adornments = {}
    local Animations = {
        Tick = {
            {CFrame = CFrame.new(0.69, -0.71, 0.6) * CFrame.Angles(math.rad(200), math.rad(60), math.rad(1)), Time = 0.2},
            {CFrame = CFrame.new(0, 0, 0) * CFrame.Angles(math.rad(0), math.rad(0), math.rad(0)), Time = 0.25}
        },
        Slow = {
            {CFrame = CFrame.new(0.69, -0.7, 0.6) * CFrame.Angles(math.rad(295), math.rad(55), math.rad(290)), Time = 0.15},
            {CFrame = CFrame.new(0.69, -0.71, 0.6) * CFrame.Angles(math.rad(200), math.rad(60), math.rad(1)), Time = 0.15}
        },
        Wood = {
            {CFrame = CFrame.new(.5, -1, 0) * CFrame.Angles(math.rad(295), math.rad(55), math.rad(290)), Time = 0.15},
            {CFrame = CFrame.new(.5, -1, 0) * CFrame.Angles(math.rad(200), math.rad(60), math.rad(1)), Time = 0.1}
        },
        Latest = {
            {CFrame = CFrame.new(0.69, -0.7, 0.1) * CFrame.Angles(math.rad(-65), math.rad(55), math.rad(-51)), Time = 0.1},
            {CFrame = CFrame.new(0.16, -1.16, 0.5) * CFrame.Angles(math.rad(-179), math.rad(54), math.rad(33)), Time = 0.1}
        }
    }
    local EndAnimation = {
        {CFrame = CFrame.new(), Time = .1}
    }

    local auraAnimations = {}
    for v, _ in Animations do
        table.insert(auraAnimations, v)
    end

    local origC0 = ReplicatedStorage.Assets.Viewmodel.RightHand.RightWrist.C0
    local killauradelay = 0
    local attackRemote
    local serverTime
    local lastPos
    local lastServerTime
    local lastPlayerPos
    local lastDamage = 0
    local attackspeed = 0
    local inventoryCon
    local sword
    local swordmeta
    local spoofedSwordCont
    local lastEffect = 0
    -- local part = Instance.new("Part", workspace)
    -- part.Anchored = true
    -- part.Material = Enum.Material.Neon
    -- part.Color = Color3.fromRGB(0, 0, 255)
    -- part.CanCollide = false

    -- local mPart = part:Clone()
    -- mPart.Parent = workspace
    -- mPart.Color = Color3.new(1, 0, 0)
    -- local indicatorHook
    -- local lastEntityHit

    local updateSwordInventory = function()
        if not inventoryCon then
            -- if inventoryCon then
            --     funcs:unbindFromUninject("inventoryCon")
            --     inventoryCon:Disconnect()
            --     inventoryCon = nil
            -- end
            lastSword = nil
            inventoryCon = bedwars.inventory.ChildAdded:Connect(function(item)
                if lastSword and lastSword.tool and lastSword.tool.Name == item.Name then return end
                if swords[item.Name] then
                    updateSword()
                end
            end)
            funcs:onExit("inventoryCon", function()
                if inventoryCon then
                    inventoryCon:Disconnect()
                    inventoryCon = nil
                end
            end)
            updateSword()
        end
    end

    local passObject = function(obj)
        return function()
            return obj
        end
    end

    local clear = function()
        if not adornments or #adornments == 0 then return end
        for _, v in ipairs(adornments) do
            v.Adornee = nil
        end
    end

    local RightWrist
    Killaura = GuiLibrary.Registry.combatPanel.API.CreateOptionsButton({
        Name = "Killaura",
        Function = function(callback)
            if callback then
                updateSwordInventory()

                attackRemote = Client:Get(bedwars.remotes.AttackRemote).instance
                RightWrist = Camera.Viewmodel.RightHand.RightWrist
                if not oldViewmodelAnimation then
                    oldViewmodelAnimation = bedwars.ViewmodelController.playAnimation
                end
                bedwars.ViewmodelController.playAnimation = function(Self, id, ...)
                    local id = viewmodelCheck(Self, id, ...)
                    if not id then return end
                    return oldViewmodelAnimation(Self, id, ...)
                end
                lastPlayerPos = Vector3.zero
                lastPos = Vector3.zero
                lastServerTime = 0
                if not spoofedSwordCont then
                    spoofedSwordCont = {}
                    for i, v in bedwars.SwordController do
                        spoofedSwordCont[i] = v
                    end
                    spoofedSwordCont.getHandItem = function()
                        return sword
                    end
                end

                task.spawn(function()
                    repeat
                        if AttackAnim.Enabled and newData.Attacking and not VMAnimActive then
                            VMAnimActive = true
                            local selectedAnimation = Animations[AnimationDropdown.Value]
                            if selectedAnimation then
                                repeat
                                    for _, anim in ipairs(selectedAnimation) do
                                        if not VMAnimActive then return end
                                        local auratween = TweenService:Create(RightWrist, TweenInfo.new(anim.Time, Enum.EasingStyle.Circular, Enum.EasingDirection.InOut), {C0 = origC0 * anim.CFrame})
                                        auratween:Play()
                                        auratween.Completed:Wait()
                                    end
                                until not newData.Attacking or not VMAnimActive

                                if VMAnimActive then
                                    for _, v in ipairs(EndAnimation) do
                                        local endTween = TweenService:Create(RightWrist, TweenInfo.new(v.Time, Enum.EasingStyle.Circular, Enum.EasingDirection.InOut), {C0 = origC0 * v.CFrame})
                                        endTween:Play()
                                    end
                                end
                            end
                            VMAnimActive = false
                        end
                        task.wait(0.01)
                    until not Killaura.Enabled
                end)

                RunLoops:BindToHeartbeat("Killaura", function()
                    if newData.matchState == 0 or not PlayerUtility.lplrIsAlive then return end

                    local nearestEntities = PlayerUtility.getNearestEntities(Distance["Value"], AuraSort.Value, true)
                    if #nearestEntities == 0 then
                        if newData.Attacking then
                            switchtool()
                        end
                        newData.Attacking, newData.attackingEntity = false, nil
                        clear()
                        return
                    end

                    sword = getSword()
                    if not sword then updateSword() return end

                    local entity = nearestEntities[1].entity
                    local root = entity:FindFirstChild("HumanoidRootPart") or entity.PrimaryPart
                    if Raycast.Enabled and not bedwars.SwordController:canSee({getInstance = passObject(entity)}) then return end

                    local angle = Angle.Value < 360 and math.acos(lplr.Character.HumanoidRootPart.CFrame.LookVector:Dot((root.Position - lplr.Character.HumanoidRootPart.Position).unit))
                    if angle and angle > math.rad(Angle.Value) then return end

                    newData.Attacking, newData.attackingEntity = true, entity
                    swordmeta = sword and sword.tool and bedwars.ItemTable[sword.tool.Name]

                    serverTime = workspace:GetServerTimeNow()
                    lastDamage = entity:GetAttribute("LastDamageTakenTime") or bedwars.SwordController.lastAttack
                    if lastDamage and serverTime - lastDamage >= .1 then
                        bedwars.SwordController.lastAttack = serverTime
                        local offset = (serverTime - lastServerTime) * ((Distance.Value + SpeedMultiplier()) * 15.2)
                        local targetPos = root.Position + (root.Position - lastPos) * offset
                        local selfPos = lplr.Character.HumanoidRootPart.Position + (lplr.Character.HumanoidRootPart.Position - lastPlayerPos) * offset + ((targetPos - lplr.Character.HumanoidRootPart.Position) / 2)

                        if LongFlyItemSwitch or ProjItemSwitch then return end
                        switchtool(sword.tool.Name)

                        -- lol bedwars really try to change smth targetPosition woah
                        attackRemote:FireServer({
                            weapon = sword.tool,
                            entityInstance = entity,
                            validate = {
                                raycast = {},
                                targetPosition = { value = targetPos },
                                selfPosition = { value = selfPos }
                            },
                            chargedAttack = { chargeRatio = 0 }
                        })

                        lastPos, lastPlayerPos, lastServerTime = root.Position, lplr.Character.HumanoidRootPart.Position, serverTime
                        for i, v in ipairs(adornments) do
                            v.Adornee = ShowTarget.Enabled and nearestEntities[i] and nearestEntities[i].entity.PrimaryPart or nil
                        end
                        if FacePlayer.Enabled and not LongFly.Enabled then
                            lplr.Character.PrimaryPart.CFrame = CFrame.lookAt(lplr.Character.HumanoidRootPart.Position, Vector3.new(root.Position.X, lplr.Character.HumanoidRootPart.Position.Y, root.Position.Z))
                        end
                        if Swing.Enabled and tick() >= attackspeed then
                            bedwars.SwordController.playSwordEffect(spoofedSwordCont, sword, false)
                            attackspeed = tick() + ((swordmeta.sword.respectAttackSpeedForEffects and swordmeta.sword.attackSpeed) or 0.24)
                        end
                    end
                end)
            else
                bedwars.ViewmodelController.playAnimation = oldViewmodelAnimation
                RunLoops:UnbindFromHeartbeat("Killaura")
                if inventoryCon then
                    inventoryCon:Disconnect()
                    inventoryCon = nil
                end
                if AttackAnim.Enabled then
                    for _, v in ipairs(EndAnimation) do
                        local endTween = TweenService:Create(RightWrist, TweenInfo.new(v.Time, Enum.EasingStyle.Circular, Enum.EasingDirection.InOut), {C0 = origC0 * v.CFrame})
                        endTween:Play()
                    end
                end
                clear()
                VMAnimActive = false
                oldViewmodelAnimation = nil
                newData.Attacking = false
            end
        end
    })
    Distance = Killaura.CreateSlider({
        Name = "value",
        Min = 0,
        Max = 23,
        Default = 23,
        Round = 1,
        Function = function() end
    }) 
    Angle = Killaura.CreateSlider({
        Name = "Angle",
        Min = 0,
        Max = 360,
        Default = 360,
        Round = 1,
        Function = function() end
    }) 
    ShowTarget = Killaura.CreateToggle({
        Name = "Show Target",
        Default = true,
        Function = function(callback)
            if callback then
                GuiLibrary.ColorUpdate:Connect(function() 
                    local newColor = GuiLibrary.kit:activeColor()
                    for _, adornment in ipairs(adornments) do
                        adornment.Color3 = newColor
                    end
                end)
                for i = 1, 10 do
                    local boxHandleAdornment = Instance.new("BoxHandleAdornment")
                    boxHandleAdornment.Size = Vector3.new(4, 6, 4)
                    boxHandleAdornment.Color3 = Color3.new(1, 0, 0)
                    boxHandleAdornment.Transparency = 0.6
                    boxHandleAdornment.AlwaysOnTop = true
                    boxHandleAdornment.ZIndex = 10
                    boxHandleAdornment.Parent = workspace
                    adornments[i] = boxHandleAdornment
                end
            end
        end,
    })    
    AttackAnim = Killaura.CreateToggle({
        Name = "Animations",
        Default = true, 
    })
    Swing = Killaura.CreateToggle({
        Name = "Swing",
        Default = true,
    })
    FacePlayer = Killaura.CreateToggle({
        Name = "Face Player",
        Default = true,
    })
    Raycast = Killaura.CreateToggle({
        Name = "Raycast",
        Default = false
    })
    Indicator = Killaura.CreateToggle({
        Name = "Indicator",
        Default = true,
    })
    AuraSort = Killaura.CreateDropdown({
        Name = "AuraSort",
        Default = "Distance",
        List = {"Distance", "Health"},
    })
    AnimationDropdown = Killaura.CreateDropdown({
        Name = "AnimationDropdown",
        Default = "Tick",
        List = auraAnimations,
    })
end)

runcode(function()
    local oldClicking
    local NoClickDelay = {}; NoClickDelay = GuiLibrary.Registry.combatPanel.API.CreateOptionsButton({
        Name = "NoClickDelay",
        Function = function(callback)
            if callback then
                oldClicking = bedwars.SwordController.isClickingTooFast
                bedwars.SwordController.isClickingTooFast = function(self)
                    self.lastSwing = 0
                    return
                end
            else
                bedwars.SwordController.isClickingTooFast = oldClicking or bedwars.SwordController.isClickingTooFast
                bedwars.SwordController.lastSwing = 0
            end
        end
    })
end)

runcode(function()
    local oldRaycastDistance, oldRegionDistance
    local Reach = {}; Reach = GuiLibrary.Registry.combatPanel.API.CreateOptionsButton({
        Name = "Reach",
        Function = function(callback)
            if callback then
                oldRaycastDistance = bedwars.CombatConstant.RAYCAST_SWORD_CHARACTER_DISTANCE
                oldRegionDistance = bedwars.CombatConstant.REGION_SWORD_CHARACTER_DISTANCE
                bedwars.CombatConstant.RAYCAST_SWORD_CHARACTER_DISTANCE = reachDistance.Value
                bedwars.CombatConstant.REGION_SWORD_CHARACTER_DISTANCE = reachDistance.Value
            else
                bedwars.CombatConstant.RAYCAST_SWORD_CHARACTER_DISTANCE = oldRaycastDistance
                bedwars.CombatConstant.REGION_SWORD_CHARACTER_DISTANCE = oldRegionDistance
            end
        end
    })
    reachDistance = Reach.CreateSlider({
        Name = "reach distance",
        Min = 1,
        Max = 21,
        Default = 21,
        Round = 1,
    })
end)

--[[runcode(function()
    local AutoTrap = {}
    local trappedPlayers = {}
    local trapSetupTime = 0.95
    local TrapDistance = {}
    
    local function IsTrapPlaceable(position, targetPosition)
        local direction = (targetPosition - position).unit
        local ray = Ray.new(position, direction * 5)
        local hitPart, hitPosition = game.Workspace:FindPartOnRay(ray, nil, false, true)
        if hitPart and (hitPart.CanCollide or hitPosition.Y > position.Y) then
            return false
        end
        local region = Region3.new(position - Vector3.new(0.5, 1, 0.5), position + Vector3.new(0.5, 0, 0.5))
        local parts = game.Workspace:FindPartsInRegion3(region, nil, math.huge)
        return #parts == 0
    end

    local function RoundVector(vec)
        return Vector3.new(math.round(vec.X), math.round(vec.Y), math.round(vec.Z))
    end

    local previousVelocities = {}
    AutoTrap = GuiLibrary.Registry.worldPanel.API.CreateOptionsButton({
        Name = "AutoTrap",
        Function = function(callback)
            if callback then
               repeat
                    if getItem("snap_trap") and PlayerUtility.lplrIsAlive then
                        local nearestPlayer = PlayerUtility.getNearestEntity(TrapDistance.Value, "Distance", true)
                        if nearestPlayer and not nearestPlayer:FindFirstChild("BillboardGui") then
                            local distance = (nearestPlayer.HumanoidRootPart.Position - lplr.Character.HumanoidRootPart.Position).Magnitude
                            if distance <= 18 then
                                local velocity = nearestPlayer.HumanoidRootPart.Velocity
                                local acceleration = (velocity - (previousVelocities[nearestPlayer] or velocity))
                                local predictedPosition = nearestPlayer.HumanoidRootPart.Position + velocity * trapSetupTime + 0.5 * acceleration * trapSetupTime ^ 2
                                previousVelocities[nearestPlayer] = velocity

                                if nearestPlayer.Humanoid:GetState() == Enum.HumanoidStateType.Jumping or nearestPlayer.Humanoid:GetState() == Enum.HumanoidStateType.Freefall then
                                    local timeToLand = math.sqrt((2 * predictedPosition.Y) / 196.2)
                                    predictedPosition = predictedPosition + nearestPlayer.HumanoidRootPart.Velocity * timeToLand
                                end

                                local trapPosition = RoundVector(predictedPosition) + Vector3.new(0, -1, 0)
                                if IsTrapPlaceable(trapPosition, nearestPlayer.HumanoidRootPart.Position) and not newData.Attacking and not LongFlyItemSwitch then
                                    switchItem("snap_trap")
                                    bedwars.remotes.PlaceBlock:InvokeServer({
                                        blockType = "snap_trap",
                                        blockData = 0,
                                        position = getserverpos(trapPosition)
                                    })               
                                end
                            end
                        end
                    end
                task.wait(0.01)       
               until not AutoTrap.Enabled
            else
                RunLoops:UnbindFromHeartbeat("AutoTrap")
                previousVelocities = {}
            end
        end
    })
    TrapDistance = AutoTrap.CreateSlider({
        Name = "Distance",
        Min = 0,
        Max = 21,
        Default = 21,
        Round = 1
    })
end)--]]

--[[
runcode(function()
    local ogFunc
    local KeepSprint = {}; KeepSprint = GuiLibrary.Registry.blatantPanel.API.CreateOptionsButton({
        Name = "KeepSprint",
        Function = function(callback)
            if callback then
                ogFunc = bedwars.SprintController.startSprinting
                bedwars.SprintController.startSprinting = function(...)
                    local args = {...}
                    args[1].sprinting = true
                    args[1].attemptingSprint = true
                    lplr:SetAttribute("Sprinting", true)
                    args[1]:setSpeed(20)
                end
            else
                bedwars.SprintController.startSprinting = ogFunc or bedwars.SprintController.startSprinting
            end
        end
    })
end)
]]

local Fly = {}
local Speed = {}

local bodyVel
local createBodyVel = function()
    if PlayerUtility.lplrIsAlive and ((bodyVel and not bodyVel.Parent.Parent) or not bodyVel) then
        bodyVel = Instance.new("BodyVelocity", lplr.Character.HumanoidRootPart)
        bodyVel.P = math.huge
        bodyVel.MaxForce = Vector3.new(bodyVel.P, bodyVel.P, bodyVel.P)
        bodyVel.Velocity = Vector3.zero

        funcs:onExit("bodyVelHook", function()
            if bodyVel then
                bodyVel:Destroy()
            end
        end)
    end
end

runcode(function()
    local AutoJump = {}
    local Mode = {}
    local SpeedSlider = {}
    local damageBoost = {
        [0] = { speedBoost = 20, speedTimer = .35 },
        [5] = { speedBoost = 20, speedTimer = .5 },
    }
    newData.hookEvents.damageHooks.Speed = function(...)
        if DamageBoost and DamageBoost.Enabled then
            local args = {...}
            if not LongFly.Enabled and args[1] and args[1].entityInstance and args[1].entityInstance == lplr.Character then
                local damageValues = damageBoost[args.damageType]
                if damageValues then
                    setSpeedBoost(damageValues.speedBoost, damageValues.speedTimer)
                end
            end
        end
    end
    Speed = GuiLibrary.Registry.blatantPanel.API.CreateOptionsButton({
        Name = "Speedv2",
        ExtraText = "CFrame",
        Function = function(callback)
            if callback then
                RunLoops:BindToHeartbeat("Speed", function(dt)
                    if Fly.Enabled then return end
                    local char = lplr.Character
                    local hum = char and char:FindFirstChildOfClass("Humanoid")
                    local root = char and char:FindFirstChild("HumanoidRootPart")
                    if PlayerUtility.lplrIsAlive and hum and root and hum.MoveDirection.Magnitude > 0 then
                        local moveDirection = hum.MoveDirection

                        if Mode.Value == "Velocity" then
                            root.AssemblyLinearVelocity = (moveDirection * (SpeedSlider.Value + SpeedMultiplier())) + Vector3.new(0, root.AssemblyLinearVelocity.Y, 0)
                        end

                        if not Fly.Enabled and AutoJump.Enabled and newData.Attacking and hum.FloorMaterial ~= Enum.Material.Air then
                            hum:ChangeState(Enum.HumanoidStateType.Jumping)
                        end
                    end
                end)
            else
                newData.hookEvents.damageHooks.Speed = nil
                if bodyVel then
                    bodyVel:Destroy()
                    bodyVel = nil
                end
                RunLoops:UnbindFromHeartbeat("Speed")
            end
        end
    })
    SpeedSlider = Speed.CreateSlider({
        Name = "Value",
        Min = 0,
        Max = 23,
        Default = 23,
        Round = 1,
    })
    Mode = Speed.CreateDropdown({
        Name = "Mode",
        List = {"Velocity"},
        Default = "Velocity",
    })
    AutoJump = Speed.CreateToggle({
        Name = "AutoJump",
        Default = true,
    })
    DamageBoost = Speed.CreateToggle({
        Name = "Damage Boost",
        Default = true,
    })
end)

runcode(function()
    local old
    local playerHook

    local blacklistedStates = {
        Enum.HumanoidStateType.FallingDown,
        Enum.HumanoidStateType.Physics,
        Enum.HumanoidStateType.Ragdoll,
        Enum.HumanoidStateType.PlatformStanding
    }

    local disableStates = function(hum)
        for _, v in next, blacklistedStates do
            hum:SetStateEnabled(v, false)
        end
    end
    
    local Strength = {}
    local Velocity = {}; Velocity = GuiLibrary.Registry.combatPanel.API.CreateOptionsButton({
        Name = "Velocity",
        Function = function(callback)
            if callback then
                old = bedwars.KnockbackUtil.applyKnockback
                bedwars.KnockbackUtil.applyKnockback = function(...)
                    -- local pos = PlayerUtility.getNearestEntities(Distance["Value"] * 1.5, "Distance", true)
                    -- if pos and pos[1] then
                    --     if LongFly.Enabled then
                    --         -- LongFly.Toggle()
                    --         return
                    --     end
                    --     pos = pos[1].entity:GetPivot()
                    --     lplr.Character:PivotTo(pos * CFrame.new(0, 0, (Distance["Value"] / 2)))
                    --     -- TweenService:Create(lplr.Character.HumanoidRootPart, TweenInfo.new((lplr.Character:GetPivot().Position - pos.Position).Magnitude / (maxDist * 2), Enum.EasingStyle.Linear), {CFrame = pos}):Play()
                    -- end
                    if Strength.Value <= 0 then return end
                    local args = {...}
                    local power = Strength.Value / 100
                    args[2] = args[2] * power
                    return old(unpack(args))
                end
                disableStates(lplr.Character.Humanoid)
                playerHook = lplr.CharacterAdded:Connect(function(chr)
                    disableStates(chr:WaitForChild("Humanoid"))
                end)
            else
                if playerHook then
                    playerHook:Disconnect()
                    playerHook = nil
                end
                bedwars.KnockbackUtil.applyKnockback = old or bedwars.KnockbackUtil.applyKnockback
            end
        end
    })
    Strength = Velocity.CreateSlider({
        Name = "Strength",
        Min = 0,
        Max = 100,
        Default = 0
    })
end)

runcode(function()
    local originalSetSpeed = bedwars.SprintController.setSpeed
    local NoSlowdown = {}

    NoSlowdown = GuiLibrary.Registry.combatPanel.API.CreateOptionsButton({
        Name = "NoSlowdown",
        Function = function(callback)
            if callback then
                bedwars.SprintController.setSpeed = function(controller, speed)
                    if PlayerUtility.lplrIsAlive then
                        lplr.Character.Humanoid.WalkSpeed = speed * controller.moveSpeedMultiplier
                    end
                end
            else
                bedwars.SprintController.setSpeed = originalSetSpeed
            end
        end
    })
end)

runcode(function()
    local old
    local Sprint = {} Sprint = GuiLibrary.Registry.combatPanel.API.CreateOptionsButton({
        Name = "Sprint",
        Function = function(callback)
            if callback then
                old = bedwars.SprintController.stopSprinting
                bedwars.SprintController.stopSprinting = function() return end
                task.spawn(function()
                    bedwars.SprintController:startSprinting()
                end)
            else
                bedwars.SprintController.stopSprinting = old or bedwars.SprintController.stopSprinting
                bedwars.SprintController:stopSprinting()
            end
        end
    })
end)

runcode(function()
    local Gravity = {}
    local originalGravity
    local gravity = {Value = 192.2}
    
    Gravity = GuiLibrary.Registry.blatantPanel.API.CreateOptionsButton({
        Name = "Gravity",
        Function = function(callback)
            if callback then
                originalGravity = workspace.Gravity
                RunLoops:BindToHeartbeat("GravityLoop", function()
                    workspace.Gravity = gravity.Value
                end)
            else
                RunLoops:UnbindFromHeartbeat("GravityLoop")
                workspace.Gravity = originalGravity or workspace.Gravity
            end
        end
    })
    gravity = Gravity.CreateSlider({
        Name = "Gravity Slider",
		Min = 0,
		Max = 196.2,
		Default = 196.2,
		Round = 1,
		Function = function() end
    })
end)

local height = lplr.Character.HumanoidRootPart.Size.Y * 1.5
runcode(function()
	local ScreenGui = DrawLibrary.CreateBar(game.CoreGui)

	local FlyValue = {}
	local FlyVerticalValue = {}
	local ProgressBar = {}
	local extendedFly = {}
    local ExtendMode = {}
	local bypass = {}

	local TweenFrame = ScreenGui.Bar
	local SecondLeft = ScreenGui.SecondLeft

	local extPhase = "none"
	local extTimer = 0
	local lastExtendTime = 0

	Fly = GuiLibrary.Registry.blatantPanel.API.CreateOptionsButton({
		Name = "Fly",
		Function = function(callback)

			local lastTick = os.clock()
			local airTimer = 0
			local i = 0
			local verticalVelocity = 0

			local descendState = false
			local ascendState = false
			local targetY = 0
			local originalY = 0

			local char = lplr.Character
			local root = char and char:FindFirstChild("HumanoidRootPart")
			local humanoid = char and char:FindFirstChildOfClass("Humanoid")

			local groundParams = RaycastParams.new()
			groundParams.FilterType = Enum.RaycastFilterType.Blacklist
			groundParams.FilterDescendantsInstances = { char }
			groundParams.IgnoreWater = true

			local isOverVoid = false
			local voidCheckTimer = 0
			local voidGrace = 0
            local VOID_GRACE_TIME = 0.4
            local MAX_AIR_TIME = ExtendMode.Value == "TweenDown" and 2.3 or 2.5

            extPhase = "none"
            extTimer = 0

            if callback then
                TweenFrame.Size = UDim2.new(0, 0, 1, 0)
                TweenFrame.Position = UDim2.new(0, 0, 0, 0)
                ScreenGui.ScreenGui.Enabled = true

				RunLoops:BindToHeartbeat("Fly", function(dt)

					local currentTick = os.clock()
					local deltaTime = math.min(currentTick - lastTick, 0.1)
					lastTick = currentTick

					if not root or not root.Parent then
						char = lplr.Character
						root = char and char:FindFirstChild("HumanoidRootPart")
						humanoid = char and char:FindFirstChildOfClass("Humanoid")
						if char then groundParams.FilterDescendantsInstances = { char } end
						return
					end

                    voidCheckTimer = voidCheckTimer + deltaTime
					if voidCheckTimer >= 0.1 then
						voidCheckTimer = 0
						local voidRay = workspace:Raycast(root.Position, Vector3.new(0, -1000, 0), groundParams)
						if voidRay then
							isOverVoid = false
							voidGrace = VOID_GRACE_TIME
						else
                            voidGrace = voidGrace - deltaTime
							if voidGrace <= 0 then isOverVoid = true end
						end
					end

					local moveDirection = (humanoid and humanoid.MoveDirection) or Vector3.zero
					local dir = moveDirection.Magnitude > 0.1 and moveDirection.Unit or root.CFrame.LookVector
                    i = i + deltaTime

                    root.CFrame = root.CFrame + moveDirection * (FlyValue.Value + SpeedMultiplier()) / (1 / dt)

					createBodyVel()
					bodyVel.MaxForce = Vector3.one * bodyVel.P

					local ray = workspace:Raycast(root.Position, Vector3.new(0, -math.clamp(1000 + math.abs(root.AssemblyLinearVelocity.Y) * 8, 1000, 2500), 0), groundParams)
					local onGround = ray and ray.Distance <= height + 0.3

					if onGround then
						if extPhase == "descending" then
							extPhase = "none"
							extTimer = 0
							bodyVel.MaxForce = Vector3.zero
							if Fly.Enabled then Fly.Toggle() end
							return
						end
						airTimer = 0
						isOverVoid = false
					end

					if bypass.Enabled then airTimer = math.huge end

					if ProgressBar.Enabled then
						ScreenGui.ScreenGui.Enabled = true
						TweenFrame.Visible = true
					else
						ScreenGui.ScreenGui.Enabled = false
						TweenFrame.Visible = false
					end

                    if extendedFly.Enabled and not bypass.Enabled and ExtendMode.Value == "TweenDown" then
						if extPhase ~= "none" then extPhase = "none"; extTimer = 0 end
                        if not bypass.Enabled then airTimer = airTimer + deltaTime end

						local remainingTime = math.max(MAX_AIR_TIME - airTimer, 0)
						remainingTime = math.round(remainingTime * 10) / 10

						if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
							verticalVelocity = FlyVerticalValue.Value
						elseif UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then
							verticalVelocity = -FlyVerticalValue.Value
						else
							verticalVelocity = math.sin(i * math.pi) * 0.01
						end

						if descendState then
							local check = workspace:Raycast(root.Position, Vector3.new(0, -100, 0), groundParams)
							if not check then
								descendState = false
							else
                                bodyVel.Velocity = Vector3.new(0, -math.clamp((root.Position.Y - targetY) * 4, 100, 250), 0)
								if humanoid.FloorMaterial ~= Enum.Material.Air then
									airTimer = 0
									descendState = false
									ascendState = true
								end
							end
						elseif ascendState then
							bodyVel.Velocity = Vector3.new(0, math.clamp((originalY - root.Position.Y) * 2, 15, 60), 0)
							if originalY - root.Position.Y <= 0.3 then
								ascendState = false
								airTimer = 0
							end
						else
							bodyVel.Velocity = Vector3.new(0, verticalVelocity, 0)
						end

						if not descendState and not ascendState and not isOverVoid then
							local vel = root.AssemblyLinearVelocity
							local horizontalSpeed = math.max(Vector3.new(vel.X, 0, vel.Z).Magnitude, FlyValue.Value + SpeedMultiplier())
							local scanStep = math.clamp(horizontalSpeed * 0.25, 4, 10)
							local maxScan = math.clamp(horizontalSpeed * 10, 60, 150)
							local closestBlock, closestDist = nil, math.huge

							for dist = 2, maxScan, scanStep do
								local origin = root.Position + dir * dist + Vector3.new(0, 6, 0)
								local forwardRay = workspace:Raycast(origin, Vector3.new(0, -60, 0), groundParams)
								if forwardRay then
									local hDist = (Vector3.new(forwardRay.Position.X, 0, forwardRay.Position.Z) - Vector3.new(root.Position.X, 0, root.Position.Z)).Magnitude
									if math.abs(forwardRay.Position.Y - root.Position.Y) < 50 and hDist < closestDist then
										closestDist = hDist
										closestBlock = forwardRay.Position
									end
								end
							end

							if closestBlock then
								local horizontalDist = (Vector3.new(closestBlock.X, 0, closestBlock.Z) - Vector3.new(root.Position.X, 0, root.Position.Z)).Magnitude
								if horizontalDist <= 35 then
									local safetyRay = workspace:Raycast(Vector3.new(closestBlock.X, closestBlock.Y + 5, closestBlock.Z), Vector3.new(0, -100, 0), groundParams)
									if safetyRay then
										local landingY = closestBlock.Y + height
                                        local dropHeight = root.Position.Y - landingY
                                        local descentSpeed = math.clamp(dropHeight * 4, 100, 250)
                                        local timeToDescend = dropHeight / descentSpeed
										local timeToReach = closestDist / math.max(horizontalSpeed, FlyValue.Value)
										if remainingTime <= timeToReach + timeToDescend and airTimer > 0.25 then
											if landingY < root.Position.Y then
												local landingCheck = workspace:Raycast(Vector3.new(closestBlock.X, closestBlock.Y + 5, closestBlock.Z), Vector3.new(0, -500, 0), groundParams)
												if landingCheck and (os.clock() - lastExtendTime) > 0.7 then
													lastExtendTime = os.clock()
													airTimer = 0
													originalY = root.Position.Y
													targetY = landingY
													descendState = true
													createNotification("Fly", "Extended time by " .. remainingTime .. "s", 4)
												end
											end
										end
									end
								end
							end
						end
					else
						if extPhase ~= "none" then extPhase = "none"; extTimer = 0 end
                        if not bypass.Enabled then airTimer = airTimer + deltaTime end

						if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
							verticalVelocity = FlyVerticalValue.Value
						elseif UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then
							verticalVelocity = -FlyVerticalValue.Value
						else
							verticalVelocity = math.sin(i * math.pi) * 0.01
						end
						bodyVel.Velocity = Vector3.new(0, verticalVelocity, 0)
					end

					local remainingTime = bypass.Enabled and math.huge or math.max(MAX_AIR_TIME - airTimer, 0)
					remainingTime = math.round(remainingTime * 10) / 10
					SecondLeft.Text = remainingTime .. "s"

					if ScreenGui.ScreenGui.Enabled then
						local barFill = extPhase == "ascending" and 1 or (bypass.Enabled and 1 or math.max(1 - (airTimer / MAX_AIR_TIME), 0))
						TweenFrame:TweenSize(UDim2.new(barFill, 0, 1, 0), Enum.EasingDirection.InOut, Enum.EasingStyle.Linear, 0.1, true)
					end

					if airTimer >= MAX_AIR_TIME and extPhase == "none" and not bypass.Enabled then
						bodyVel.MaxForce = Vector3.zero
						if Fly.Enabled then Fly.Toggle() end
					end
				end)
			else
				if bodyVel then bodyVel.MaxForce = Vector3.zero end
				extPhase = "none"
				extTimer = 0
				descendState = false
				ascendState = false
                MAX_AIR_TIME = 2.5
				TweenFrame:TweenSize(UDim2.new(0, 0, 1, 0), Enum.EasingDirection.InOut, Enum.EasingStyle.Linear, 0.1, true)
				ScreenGui.ScreenGui.Enabled = false
				RunLoops:UnbindFromHeartbeat("Fly")
			end
		end
	})
	FlyValue = Fly.CreateSlider({
		Name = "value",
		Min = 0,
		Max = 23,
		Default = 23,
		Round = 1
	})
	FlyVerticalValue = Fly.CreateSlider({
		Name = "vertical value",
		Min = 0,
		Max = 100,
		Default = 49,
		Round = 1
	})
	ProgressBar = Fly.CreateToggle({
		Name = "ProgressBar",
		Default = true
	})
	extendedFly = Fly.CreateToggle({
		Name = "ExtendedFly",
		Default = true
	})
	ExtendMode = Fly.CreateDropdown({
		Name = "Extend Mode",
        List = {"TweenDown"},
        Default = "TweenDown",
	})
	extendedFly:AddDependent(ExtendMode)
    -- AscendDescend removed; only TweenDown supported
	bypass = Fly.CreateToggle({
		Name = "bypassTimer",
		Default = false
	})
end)

runcode(function()
    local ProjectileAimbot = {}
    local BowAura = {}
    local AimMode = {}
    local AimRange = {}
    local AimFOV = {}
    local AimWallcheck = {}
    local AimPart = {}
    local AimTargetHud = {}
    local AimProjectiles = {}
    local AuraMode = {}
    local AuraSort = {}
    local AuraPart = {}
    local AuraRange = {}
    local AuraFOV = {}
    local AuraDelay = {}
    local AuraWallcheck = {}
    local LocalProjectile = {}
    local AutoSwap = {}
    local AuraHeld = {}
    local AuraCharge = {}
    local AuraChargeTime = {Value = 1}
    local AuraTargetHud = {}
    local AuraProjectiles = {}
    local oldCalculateAim
    local fireDelays = {}
    local lastAuraTick = 0
    local defaultAimProjectiles = {"arrow", "snowball", "fireball", "telepearl"}
    local defaultAuraProjectiles = {"arrow", "snowball", "fireball"}
    local projectileController = bedwars.ProjectileControllerObject

    local function Projectiletype(projectile, ammo, itemType)
        local lowered = string.lower(projectile or itemType or ammo or "")
        if lowered == "telepearl" or itemType == "telepearl" then
            return "telepearl"
        end
        if lowered == "fireball" or itemType == "fireball" then
            return "fireball"
        end
        if lowered:find("snowball") or ammo == "snowball" then
            return "snowball"
        end
        if lowered:find("arrow") or ammo == "arrow" then
            return "arrow"
        end
        return lowered
    end

    local function projectileEnabled(listObject, defaults, projectile, ammo, itemType)
        local values = listObject and listObject.Values
        local category = Projectiletype(projectile, ammo, itemType)
        if not values or next(values) == nil then
            return table.find(defaults, category) ~= nil
        end
        return table.find(values, category) ~= nil or table.find(values, projectile) ~= nil or table.find(values, itemType) ~= nil
    end

    local function getProjectileAmmo(source)
        local inventory = bedwars.Inventory(lplr)
        if not inventory then return end
        for _, item in inventory.items do
            if source.ammoItemTypes and table.find(source.ammoItemTypes, item.itemType) then
                return item.itemType
            end
        end
    end

    local function getGravity(character)
        local gravity = workspace.Gravity
        local balloons = character and character:GetAttribute("InflatedBalloons")
        if type(balloons) == "number" and balloons > 0 then
            gravity = workspace.Gravity * (1 - (balloons >= 4 and 1.2 or balloons >= 3 and 1 or 0.975))
        end
        if character and character.PrimaryPart and character.PrimaryPart:FindFirstChild("rbxassetid://8200754399") then
            gravity = 6
        end
        return gravity
    end

    local function getAimPosition(character, targetPart)
        local part = (targetPart == "Head" and character:FindFirstChild("Head")) or (targetPart == "UpperTorso" and (character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso"))) or character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart
        return part and part.Position or nil
    end

    local function getTarget(mode, range, fov, wallcheck, sortMode, targetPart)
        if not PlayerUtility.lplrIsAlive or not root then return end
        if mode == "Mouse" then
            local target = PlayerUtility.EnemyToMouse(fov, true)
            local character = target and target.Character
            local targetRoot = character and (character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart)
            local targetPosition = character and getAimPosition(character, targetPart)
            if targetRoot and targetPosition and (not wallcheck or PlayerUtility.EntityVisible(root.Position, targetPosition)) then
                return character
            end
            return
        end
        local entities = PlayerUtility.GetNearestEntities(range, sortMode or "Distance", true, nil, wallcheck)
        return entities and entities[1] and entities[1].entity or nil
    end

    local function calcTrajectory(positionFrom, projectile, projectileMeta, gravityMultiplier, velocityMultiplier, drawDuration, targetCharacter, wallcheck, usePredictionLifetime, targetPart)
        local targetRoot = targetCharacter and (targetCharacter:FindFirstChild("HumanoidRootPart") or targetCharacter.PrimaryPart)
        local targetHumanoid = targetCharacter and targetCharacter:FindFirstChildOfClass("Humanoid")
        local targetPosition = targetCharacter and getAimPosition(targetCharacter, targetPart)
        if not targetRoot or not targetPosition or not projectileMeta then return end

        local launchVelocity = (projectileMeta.launchVelocity or 100) * (velocityMultiplier or 1)
        local gravity = (projectileMeta.gravitationalAcceleration or 196.2) * (gravityMultiplier or 1)
        local lifetime = (usePredictionLifetime and projectileMeta.predictionLifetimeSec) or projectileMeta.lifetimeSec or 3
        local calc = Prediction.SolveTrajectory(positionFrom, launchVelocity, gravity, targetPosition, (projectile == "telepearl" and Vector3.zero or targetRoot.Velocity), getGravity(targetCharacter), targetHumanoid and targetHumanoid.HipHeight or 2, targetHumanoid and targetHumanoid:GetState() == Enum.HumanoidStateType.Jumping and 42.6 or nil, wallcheck and newData.blockRaycast or nil)

        if not calc then return end
        return {initialVelocity = CFrame.new(positionFrom, calc).LookVector * launchVelocity, positionFrom = positionFrom, deltaT = lifetime, gravitationalAcceleration = gravity, drawDurationSeconds = drawDuration or 1}
    end

    local function getProjectileLoadout(listObject, defaults, heldOnly)
        local inventory = bedwars.Inventory(lplr)
        local loadout = {}
        local heldTool = handInvItem and handInvItem.Value
        if not inventory then return loadout end

        for _, item in inventory.items do
            local itemMeta = bedwars.ItemTable[item.itemType]
            local source = itemMeta and itemMeta.projectileSource
            if source then
                local ammo = getProjectileAmmo(source)
                local projectile = (type(source.projectileType) == "function" and source.projectileType(ammo) or source.projectileType)
                local matchesHeld = not heldOnly or (heldTool and ((item.tool and item.tool == heldTool) or heldTool.Name == item.itemType or (item.tool and heldTool.Name == item.tool.Name)))
                if matchesHeld and projectile and projectileEnabled(listObject, defaults, projectile, ammo, item.itemType) and (ammo or projectile == "telepearl" or projectile == "fireball") then
                    table.insert(loadout, {
                        item = item,
                        ammo = ammo,
                        projectile = projectile,
                        source = source,
                    })
                end
            end
        end

        table.sort(loadout, function(a, b)
            local heldName = heldTool and heldTool.Name
            local aHeld = heldName and ((a.item.tool and a.item.tool.Name == heldName) or a.item.itemType == heldName) or false
            local bHeld = heldName and ((b.item.tool and b.item.tool.Name == heldName) or b.item.itemType == heldName) or false
            if aHeld ~= bHeld then
                return aHeld
            end
            return (bedwars.ProjectileMeta[a.projectile] and bedwars.ProjectileMeta[a.projectile].launchVelocity or 0) > (bedwars.ProjectileMeta[b.projectile] and bedwars.ProjectileMeta[b.projectile].launchVelocity or 0)
        end)

        return loadout
    end

    local function resolveProjectileTool(item)
        if item.tool and item.tool.Parent then
            return item.tool
        end
        if bedwars.inventory then
            return bedwars.inventory:FindFirstChild(item.itemType) or (item.tool and bedwars.inventory:FindFirstChild(item.tool.Name))
        end
        return item.tool
    end

    ProjectileAimbot = GuiLibrary.Registry.blatantPanel.API.CreateOptionsButton({
        Name = "ProjectileAimbot",
        ExtraText = "Predict",
        Function = function(callback)
            if callback then
                if not bedwars.ProjectileController or not bedwars.ProjectileController.calculateImportantLaunchValues then return end
                oldCalculateAim = oldCalculateAim or bedwars.ProjectileController.calculateImportantLaunchValues
                bedwars.ProjectileController.calculateImportantLaunchValues = function(self, source, usePredictionLifetime, shootPart, launchOrigin)
                    local projectile = source and source.projectile
                    if not projectileEnabled(AimProjectiles, defaultAimProjectiles, projectile, nil, projectile) then
                        return oldCalculateAim(self, source, usePredictionLifetime, shootPart, launchOrigin)
                    end

                    local targetCharacter = getTarget(AimMode.Value, AimRange.Value, AimFOV.Value, AimWallcheck.Enabled, AimMode.Value, AimPart.Value)
                    local position = launchOrigin or self:getLaunchPosition(shootPart)
                    if not targetCharacter or not position or not source or not source.getProjectileMeta then
                        return oldCalculateAim(self, source, usePredictionLifetime, shootPart, launchOrigin)
                    end

                    local launchValues = calcTrajectory(position + (projectile == "owl_projectile" and Vector3.zero or (source.fromPositionOffset or Vector3.zero)), projectile, source:getProjectileMeta(), source.gravityMultiplier, source.velocityMultiplier, source.drawDurationSeconds or 1, targetCharacter, AimWallcheck.Enabled, usePredictionLifetime, AimPart.Value)

                    return launchValues or oldCalculateAim(self, source, usePredictionLifetime, shootPart, launchOrigin)
                end
            else
                bedwars.ProjectileController.calculateImportantLaunchValues = oldCalculateAim or bedwars.ProjectileController.calculateImportantLaunchValues
            end
        end
    })
    AimMode = ProjectileAimbot.CreateDropdown({
        Name = "Mode",
        Default = "Mouse",
        List = {"Mouse", "Distance", "Health"},
    })
    AimPart = ProjectileAimbot.CreateDropdown({
        Name = "Aim Part",
        Default = "RootPart",
        List = {"RootPart", "Head", "UpperTorso"},
    })
    AimRange = ProjectileAimbot.CreateSlider({
        Name = "Range",
        Min = 10,
        Max = 80,
        Default = 50,
        Round = 1,
    })
    AimFOV = ProjectileAimbot.CreateSlider({
        Name = "FOV",
        Min = 20,
        Max = 250,
        Default = 160,
        Round = 1,
    })
    AimWallcheck = ProjectileAimbot.CreateToggle({
        Name = "Wallcheck",
        Default = true,
    })
    AimTargetHud = ProjectileAimbot.CreateToggle({
        Name = "TargetHud",
        Default = false,
    })
    AimProjectiles = ProjectileAimbot.CreateTextlist({
        Name = "Projectiles",
    })

    BowAura = GuiLibrary.Registry.blatantPanel.API.CreateOptionsButton({
        Name = "BowAura",
        ExtraText = "Predict",
        Function = function(callback)
            if callback then
                fireDelays = {}
                lastAuraTick = 0
                RunLoops:BindToHeartbeat("BowAura", function()
                    if not PlayerUtility.lplrIsAlive or not root or newData.Attacking or LongFlyItemSwitch then return end
                    if tick() < lastAuraTick + AuraDelay.Value then return end

                    local targetCharacter = getTarget(AuraMode.Value, AuraRange.Value, AuraFOV.Value, AuraWallcheck.Enabled, AuraSort.Value, AuraPart.Value)
                    if not targetCharacter then return end

                    for _, data in getProjectileLoadout(AuraProjectiles, defaultAuraProjectiles, AuraHeld.Enabled) do
                        local cooldown = fireDelays[data.item.itemType] or 0
                        if cooldown <= tick() then
                            local position = projectileController and projectileController:getLaunchPosition()
                            local chargeTime = AuraCharge and AuraCharge.Enabled and math.min(AuraChargeTime.Value, data.source.maxStrengthChargeSec or (data.source.drawDurationSeconds or data.source.maxStrengthChargeSec or 1)) or (data.source.drawDurationSeconds or data.source.maxStrengthChargeSec or 1)
                            local launchValues = position and calcTrajectory(position + (data.projectile == "owl_projectile" and Vector3.zero or (data.source.fromPositionOffset or Vector3.zero)), data.projectile, bedwars.ProjectileMeta[data.projectile], data.source.gravityMultiplier, data.source.velocityMultiplier, chargeTime, targetCharacter, AuraWallcheck.Enabled, true, AuraPart.Value)

                            if launchValues then
                                lastAuraTick = tick()
                                fireDelays[data.item.itemType] = tick() + math.max(data.source.fireDelaySec or 0.1, AuraDelay.Value)
                                task.spawn(function()
                                    local heldItem = handInvItem and handInvItem.Value and handInvItem.Value.Name
                                    local toolName = data.item.tool and data.item.tool.Name or data.item.itemType
                                    local success

                                    ProjItemSwitch = true
                                    if AutoSwap.Enabled and heldItem and heldItem ~= toolName then
                                        switchtool(data.item.tool.Name)
                                    end

                                    local ok, err = pcall(function()
                                        local tool = resolveProjectileTool(data.item)
                                        if tool then
                                            success = bedwars.remotes.ProjectileFire:InvokeServer(
                                                tool,
                                                data.ammo,
                                                data.projectile,
                                                launchValues.positionFrom,
                                                root.Position,
                                                launchValues.initialVelocity,
                                                HttpService:GenerateGUID(true),
                                                {
                                                    drawDurationSec = chargeTime,
                                                    shotId = HttpService:GenerateGUID(false)
                                                },
                                                workspace:GetServerTimeNow() - 0.045
                                            )
                                        end
                                    end)

                                    ProjItemSwitch = false

                                    if success then
                                        if LocalProjectile.Enabled and projectileController then
                                            projectileController:createLocalProjectile(
                                                data.source,
                                                data.ammo,
                                                data.projectile,
                                                launchValues.positionFrom,
                                                HttpService:GenerateGUID(true),
                                                launchValues.initialVelocity,
                                                {
                                                    drawDurationSec = chargeTime,
                                                    shotId = HttpService:GenerateGUID(false)
                                                }
                                            )
                                        end
                                    else
                                        fireDelays[data.item.itemType] = tick() + 0.1
                                    end
                                end)

                                break
                            end
                        end
                    end
                end)
            else
                RunLoops:UnbindFromHeartbeat("BowAura")
                fireDelays = {}
            end
        end
    })
    AuraMode = BowAura.CreateDropdown({
        Name = "Mode",
        Default = "Distance",
        List = {"Distance", "Health", "Mouse"},
    })
    AuraSort = BowAura.CreateDropdown({
        Name = "Sort",
        Default = "Distance",
        List = {"Distance", "Health"},
    })
    AuraPart = BowAura.CreateDropdown({
        Name = "Aim Part",
        Default = "RootPart",
        List = {"RootPart", "Head", "UpperTorso"},
    })
    AuraRange = BowAura.CreateSlider({
        Name = "Range",
        Min = 5,
        Max = 80,
        Default = 45,
        Round = 1,
    })
    AuraFOV = BowAura.CreateSlider({
        Name = "FOV",
        Min = 20,
        Max = 250,
        Default = 160,
        Round = 1,
    })
    AuraDelay = BowAura.CreateSlider({
        Name = "Delay",
        Min = 0.05,
        Max = 0.5,
        Default = 0.1,
        Round = 2,
    })
    AuraWallcheck = BowAura.CreateToggle({
        Name = "Wallcheck",
        Default = true,
    })
    LocalProjectile = BowAura.CreateToggle({
        Name = "LocalProjectile",
        Default = true,
    })
    AutoSwap = BowAura.CreateToggle({
        Name = "AutoSwap",
        Default = true,
    })
    AuraHeld = BowAura.CreateToggle({
        Name = "HeldOnly",
        Default = false,
    })
    AuraCharge = BowAura.CreateToggle({
        Name = "CustomCharge",
        Default = false,
    })
    AuraChargeTime = BowAura.CreateSlider({
        Name = "Charge",
        Min = 0.1,
        Max = 3,
        Default = 1,
        Round = 2,
    })
    AuraTargetHud = BowAura.CreateToggle({
        Name = "TargetHud",
        Default = false,
    })
    AuraProjectiles = BowAura.CreateTextlist({
        Name = "Projectiles",
    })--]]

    funcs:onExit("projectileAimbot", function()
        restoreProjectileAimbot()
        updateProjectileTargetHud(nil, false)
    end)
    funcs:onExit("bowAura", function()
        RunLoops:UnbindFromHeartbeat("BowAura")
        updateProjectileTargetHud(nil, false)
    end)
end)

-- so simga Scaffold 
--[[runcode(function()
    local Scaffold = {}
    local scaffoldY
    local primpart = lplr.Character.PrimaryPart

    local function getWool()
        for _, v in pairs(bedwars.inventoryIndex) do
            if string.lower(v.Name):find("wool") then
                return {Obj = v,Amount = v:GetAttribute("Amount")}
            end
        end
        return nil
    end

    local function getpos()
        local humanoid = lplr.Character:FindFirstChildOfClass("Humanoid")
        local moveDirection = humanoid.MoveDirection
        local angle = math.atan2(moveDirection.Z, moveDirection.X)
        if moveDirection ~= Vector3.zero then
            local x = math.round(primpart.Position.X + math.cos(angle) * 1.5) / 3
            local z = math.round(primpart.Position.Z + math.sin(angle) * 1.5) / 3
            return Vector3.new(math.floor(x), math.floor(scaffoldY), math.floor(z))
        end
    end

    Scaffold = GuiLibrary.Registry.blatantPanel.API.CreateOptionsButton({
        Name = "Scaffold",
        Function = function(callback)
            if callback then
                scaffoldY = nil
                RunLoops:BindToHeartbeat("Scaffold", function()
                    if PlayerUtility.lplrIsAlive then
                        local block
                        local wool = getWool()
                        if wool then
                            block = wool.Obj.Name
                        end
                        
                        if not scaffoldY then
                            scaffoldY = lplr.Character.HumanoidRootPart.Position.Y / 3
                        end

                        if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
                            scaffoldY = lplr.Character.HumanoidRootPart.Position.Y / 3 - 1.5
                        elseif UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then
                            scaffoldY = lplr.Character.HumanoidRootPart.Position.Y / 3 - 2
                        end
                        
                        local pos = getpos()

                        bedwars.remotes.PlaceBlock:InvokeServer({
                            position = pos,
                            blockType = block
                        })
                    end
                end)
            else
                RunLoops:UnbindFromHeartbeat("Scaffold")
                scaffoldY = nil
            end
        end
    })
end)--]]

runcode(function()
    local lastDamageTick

    local function blockBelowPlayer()
        local raycastResult = workspace:Raycast(lplr.Character.HumanoidRootPart.Position, Vector3.new(0, -30), newData.blockRaycast)
        return raycastResult and raycastResult.Instance ~= nil
    end

    local methods = { -- top = highest priority
        ["jade_hammer"] = {
            check = function()
                return bedwars.AbilityController:canUseAbility("jade_hammer_jump")
            end,
            timer = 1.9,
            speedVal = 90,
            func = function(v)
                bedwars.AbilityController:useAbility("jade_hammer_jump")
                setSpeedBoost(v.speedVal, v.timer)
            end
        },
        ["fireball"] = {
            check = function()
                return blockBelowPlayer()
            end,
            timer = 1.5,
            speedVal = 45,
            func = function(v)
                local characterPosition = chrCFrame.Position
                
                lastDamageTick = nil
                LongFlyItemSwitch = true
                switchItem("fireball")
                
                bedwars.remotes.ProjectileFire:InvokeServer(
                    bedwars.inventory.fireball, 
                    "fireball", 
                    "fireball", 
                    characterPosition, 
                    characterPosition + lplr.Character.Humanoid.MoveDirection - Vector3.new(0, height, 0), 
                    (lplr.Character.Humanoid.MoveDirection * 1.5) + Vector3.new(0, -60), 
                    HttpService:GenerateGUID(true), 
                    {drawDurationSeconds = 0, shotId = HttpService:GenerateGUID(false)}, 
                    workspace:GetServerTimeNow()
                )
                
                LongFlyItemSwitch = false
                switchItem()

                repeat
                    task.wait()
                until lastDamageTick or not LongFly.Enabled
                
                if not LongFly.Enabled then return end

                setSpeedBoost(v.speedVal, v.timer)
            end
        },
        ["void_axe"] = {
            check = function() 
                return bedwars.AbilityController:canUseAbility("void_axe_jump")
            end,
            timer = 1.75,
            speedVal = 70,
            func = function(v)
                bedwars.AbilityController:useAbility("void_axe_jump")
                setSpeedBoost(v.speedVal, v.timer)
            end
        },
    }

    newData.hookEvents.damageHooks.LongFly = function(...)
        local args = {...}
        if args[1] and args[1].fromEntity and args[1].fromEntity == lplr.Character then
            lastDamageTick = tick()
        end
    end
    
    LongFly = GuiLibrary.Registry.blatantPanel.API.CreateOptionsButton({
        Name = "LongFly",
        Function = function(callback)
            if callback then
                if newData.matchState == 0 or not PlayerUtility.lplrIsAlive or
                   (GuiLibrary.Registry.flyOptionsButton and GuiLibrary.Registry.flyOptionsButton.API.Enabled) then
                    if LongFly.Enabled then
                        LongFly.Toggle()
                    end
                    return
                end

                for i, v in pairs(methods) do
                    if getItem(i) and v.check() then
                        task.spawn(function()
                            v.func(v)
                        end)

                        task.spawn(function()
                            local rayResult = workspace:Raycast( lplr.Character.HumanoidRootPart.Position, Vector3.new(0, -1000), newData.blockRaycast)
                            
                            local args = {lplr.Character.HumanoidRootPart.CFrame:GetComponents()}
                            args[2] = (rayResult and (rayResult.Position.Y + height)) or args[2]
                            lplr.Character.HumanoidRootPart.CFrame = CFrame.new(unpack(args))
                            
                            if not Fly.Enabled then
                                Fly.Toggle()
                            end
                        end)
                        return
                    end
                end
                
                if LongFly.Enabled then
                    LongFly.Toggle()
                end
            else
                if Fly.Enabled then
                    Fly.Toggle()
                end
                clearSpeedBoost()
            end
        end
    })
    for i, v in methods do
        LongFly.CreateSlider({
            Name = i .. " speed",
            Min = 0,
            Max = v.speedVal,
            Default = v.speedVal,
            Round = 1,
            Function = function(val)
                v.speedVal = val
            end
        })
    end
end)

--[[runcode(function()
    local Nofall = {}
    Nofall = GuiLibrary.Registry.blatantPanel.API.CreateOptionsButton({
        Name = "Nofall",
        Function = function(callback)
            if callback then
                RunLoops:BindToHeartbeat("Nofall", function()
                    if PlayerUtility.lplrIsAlive then
                        local root = lplr.Character and lplr.Character:FindFirstChild("HumanoidRootPart")
                        if root and root.Velocity.Y < 0 then
                            local v = root.Velocity
                            root.Velocity = Vector3.new(v.X, v.Y * 0.4, v.Z)
                        end
                    end
                end)
            else
                RunLoops:UnbindFromHeartbeat("Nofall")
            end
        end
    })
end)--]]

do
    local KillEffect = {}
    local ogValue
    local dropdown = {}
    local cEffects = {}
    local randomize = {}
    local entityDeath

    -- local customEffects = {
    --     ["ragdoll"] = function()
    --         local sound = Instance.new("Sound", workspace)
    --         sound.SoundId = nil
    --     end
    -- }

    local dropdownOptions = {}
    for i, v in bedwars.KillEffectMeta do
        table.insert(dropdownOptions, i)
    end

    local applyKillEffect = function()
        newData.hookEvents.deathHooks.KillEffect = nil
        if not KillEffect.Enabled then return end
        if randomize.Enabled then
            newData.hookEvents.deathHooks.KillEffect = function(eventData)
                if eventData.fromEntity == lplr.Character then
                    lplr:SetAttribute("KillEffectType", dropdownOptions[math.random(1, #dropdownOptions)])
                end
            end
            lplr:SetAttribute("KillEffectType", dropdownOptions[math.random(1, #dropdownOptions)])
            return
        end
        lplr:SetAttribute("KillEffectType", dropdown.Value)
    end

    KillEffect = GuiLibrary.Registry.renderPanel.API.CreateOptionsButton({
        Name = "KillEffect",
        Function = function(callback)
            if callback then
                ogValue = ogValue or lplr:GetAttribute("KillEffectType")
                applyKillEffect()
            else
                newData.hookEvents.deathHooks.KillEffect = nil
                lplr:SetAttribute("KillEffectType", ogValue or "none")
            end
        end
    })
    dropdown = KillEffect.CreateDropdown({
        Name = "Effect",
        Default = "",
        Function = function()
            if KillEffect.Enabled then
                applyKillEffect()
            end
        end,
        List = dropdownOptions,
    })
    randomize = KillEffect.CreateToggle({
        Name = "Randomize",
        Function = function()
            if KillEffect.Enabled then
                applyKillEffect()
            end
        end
    })
end

runcode(function()
    local lockerCont = getmetatable(bedwars.LockerController)
    local funcs = {
        setEmote = function(...)
            local args = {...}
            task.spawn(function()
                bedwars.ClientHandlerStore:dispatch({
                    type = "LockerSetEmote",
                    emote = args[2],
                    slot = args[3]
                })
            end)
            cosmeticConfig.Attributes["EmoteTypeSlot" .. args[3]] = args[2]
            cosmeticConfig.Selected.selectedEmotes[args[3]] = args[2]
            lplr:SetAttribute("EmoteTypeSlot" .. args[3], args[2])
            writefile("Phantom/storage/cache/lockerConfig.json", HttpService:JSONEncode(cosmeticConfig))
        end,
        setKillEffect = function(...)
            local args = {...}
            task.spawn(function()
                bedwars.ClientHandlerStore:dispatch({
                    type = "LockerSetKillEffect",
                    killEffect = args[2],
                })
            end)
            cosmeticConfig.Attributes["KillEffectType"] = args[2]
            cosmeticConfig.Selected.selectedKillEffect = args[2]
            lplr:SetAttribute("KillEffectType", args[2])
            writefile("Phantom/storage/cache/lockerConfig.json", HttpService:JSONEncode(cosmeticConfig))
        end,
        setTitle = function(...)
            local args = {...}
            task.spawn(function()
                bedwars.ClientHandlerStore:dispatch({
                    type = "LockerSetTitle",
                    title = args[2],
                })
            end)
            cosmeticConfig.Attributes["TitleType"] = args[2]
            cosmeticConfig.Selected.selectedTitle = args[2]
            lplr:SetAttribute("TitleType", args[2])
            writefile("Phantom/storage/cache/lockerConfig.json", HttpService:JSONEncode(cosmeticConfig))
        end,
        setLobbyGadget = function(...)
            local args = {...}
            task.spawn(function()
                bedwars.ClientHandlerStore:dispatch({
                    type = "LockerSetLobbyGadget",
                    lobbyGadget = args[2],
                })
            end)
            cosmeticConfig.Attributes["LobbyGadgetType"] = args[2]
            cosmeticConfig.Selected.selectedLobbyGadget = args[2]
            lplr:SetAttribute("LobbyGadgetType", args[2])
            writefile("Phantom/storage/cache/lockerConfig.json", HttpService:JSONEncode(cosmeticConfig))
        end,
        setWinEffect = function(...)
            local args = {...}
            task.spawn(function()
                bedwars.ClientHandlerStore:dispatch({
                    type = "LockerSetWinEffect",
                    winEffect = args[2],
                })
            end)
            cosmeticConfig.Attributes["WinEffectType"] = args[2]
            cosmeticConfig.Selected.selectedWinEffect = args[2]
            lplr:SetAttribute("WinEffectType", args[2])
            writefile("Phantom/storage/cache/lockerConfig.json", HttpService:JSONEncode(cosmeticConfig))
        end,
        setBreakBedEffect = function(...)
            local args = {...}
            task.spawn(function()
                bedwars.ClientHandlerStore:dispatch({
                    type = "LockerSetBreakBedEffect",
                    breakBedEffect = args[2],
                })
            end)
            cosmeticConfig.Attributes["BreakBedEffectType"] = args[2]
            cosmeticConfig.Selected.selectedBreakBedEffect = args[2]
            lplr:SetAttribute("BreakBedEffectType", args[2])
            writefile("Phantom/storage/cache/lockerConfig.json", HttpService:JSONEncode(cosmeticConfig))
        end,
    }
    local revertFuncs
    unlockAll = GuiLibrary.Registry.inventoryPanel.API.CreateOptionsButton({
        Name = "LockerExploit",
        Function = function(callback)
            if callback then
                for i, v in cosmeticConfig.Attributes do
                    lplr:SetAttribute(i, v)
                end
                revertFuncs = {}
                for i, v in funcs do
                    revertFuncs[i] = lockerCont[i]
                    lockerCont[i] = v
                end
            elseif revertFuncs then
                for i, v in revertFuncs do
                    lockerCont[i] = v
                end
                revertFuncs = nil
            end
            task.spawn(function()
                updateStore()
            end)
        end
    })
end)

--[[do
    local SoundReplace = {}
    -- local listSounds = {
    --     "1.mp3",
    --     "2.mp3",
    --     "3.mp3",
    --     "4.mp3",
    --     "5.mp3"
    -- }
    -- local listSounds = {"rbxassetid://15090512951"}
    local listSounds = {
       getcustomasset("phantom/nigger.mp3")
    }

    -- for i, v in listSounds do
    --     listSounds[i] = (string.split(v, ".")[2] and getcustomasset("Phantom/storage/cache/" .. v)) or v
    -- end

    SoundReplace = GuiLibrary.Registry.renderPanel.API.CreateOptionsButton({
        Name = "KillSoundReplace",
        Function = function(callback)
            if callback then
                getmetatable(bedwars.CombatController).setKillSounds = function() end
                bedwars.CombatController.killSounds = listSounds
                bedwars.CombatController.multiKillLoops = {}
            end
        end
    })
end--]]

runcode(function()
    local ThemeDropdown = {}
    local GameThemes = {}
    local LIGHT_TAG = "NightTheme_Light"
    local LIGHT_HOLDER_FOLDER = "NightTheme_LightHolders"
    local nightConnections = {}
    local timeCycleConn = nil
    local audioState = {folder=nil,rainInside=nil,rainOutside=nil,thunderLoop=nil,thunderToken=0,roofHeartbeat=nil,flashToken=0,flashGui=nil,flashFrame=nil}

    local cleanupSnow = function()
        local e = workspace:FindFirstChild("Snowfall_Client"); if e then e:Destroy() end
    end
    local cleanupNight = function()
        if timeCycleConn then timeCycleConn:Disconnect(); timeCycleConn = nil end
        for _, c in ipairs(nightConnections) do c:Disconnect() end
        nightConnections = {}
        local hf = workspace:FindFirstChild(LIGHT_HOLDER_FOLDER); if hf then hf:Destroy() end
        for _, d in ipairs(workspace:GetDescendants()) do
            local l1 = d:FindFirstChild(LIGHT_TAG.."_Spot"); if l1 then l1:Destroy() end
            local l2 = d:FindFirstChild(LIGHT_TAG.."_Point"); if l2 then l2:Destroy() end
        end
    end
    local cleanupAudio = function()
        audioState.thunderToken += 1; audioState.flashToken += 1
        if audioState.roofHeartbeat then audioState.roofHeartbeat:Disconnect(); audioState.roofHeartbeat = nil end
        if audioState.flashGui then audioState.flashGui:Destroy() end
        if audioState.folder then audioState.folder:Destroy() end
        audioState.folder=nil; audioState.rainInside=nil; audioState.rainOutside=nil
        audioState.thunderLoop=nil; audioState.flashGui=nil; audioState.flashFrame=nil
    end
    local cleanupAll = function() cleanupSnow(); cleanupNight(); cleanupAudio() end

    local applyLighting = function(code) loadstring(code)() end

    local tweenVolume = function(sound, target, step)
        if not sound then return end
        sound.Volume = sound.Volume + (target - sound.Volume) * math.clamp(step, 0, 1)
        if math.abs(sound.Volume - target) < 0.003 then sound.Volume = target end
    end

    local ROOF_OFFSETS = {Vector3.new(0,0,0),Vector3.new(7,0,0),Vector3.new(-7,0,0),Vector3.new(0,0,7),Vector3.new(0,0,-9),Vector3.new(9,0,9),Vector3.new(-9,0,9),Vector3.new(9,0,-9),Vector3.new(-9,0,-9)}
    local getRoofAudioBlend = function(hrp, rayParams)
        if not hrp then return 0, false end
        local offsets = ROOF_OFFSETS
        local coveredWeight, totalWeight, centerCovered = 0, 0, false
        for idx, offset in ipairs(offsets) do
            local result = workspace:Raycast(hrp.Position + offset, Vector3.new(0,80,0), rayParams)
            local weight = idx == 1 and 2.35 or 1
            totalWeight += weight
            if result then
                local strength = 0.45 + (1 - math.clamp((result.Position.Y - hrp.Position.Y - 6) / 22, 0, 1)) * 0.55
                coveredWeight += weight * strength
                if idx == 1 then centerCovered = true end
            end
        end
        local blend = totalWeight > 0 and math.clamp(coveredWeight / totalWeight, 0, 1) or 0
        if blend > 0 and blend < 1 then blend = math.clamp(blend * 0.82 + 0.09, 0, 1) end
        return blend, centerCovered
    end

    local ensureLightningFlash = function()
        if audioState.flashGui and audioState.flashFrame and audioState.flashGui.Parent then return audioState.flashFrame end
        local pgui = lplr:FindFirstChildOfClass("PlayerGui"); if not pgui then return nil end
        local gui = Instance.new("ScreenGui"); gui.Name="WeatherLightningFlash"; gui.IgnoreGuiInset=true; gui.ResetOnSpawn=false; gui.DisplayOrder=999999; gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling; gui.Parent=pgui
        local frame = Instance.new("Frame"); frame.Name="Flash"; frame.BackgroundColor3=Color3.new(1,1,1); frame.BorderSizePixel=0; frame.Size=UDim2.fromScale(1,1); frame.Position=UDim2.fromScale(0,0); frame.BackgroundTransparency=1; frame.Parent=gui
        audioState.flashGui=gui; audioState.flashFrame=frame; return frame
    end

    local playLightningFlash = function(power)
        local frame = ensureLightningFlash()
        audioState.flashToken += 1; local token = audioState.flashToken
        power = math.clamp(power or 0.5, 0.08, 1)
        local char = lplr.Character; local hrp = char and char:FindFirstChild("HumanoidRootPart")
        local lightPart, worldLight
        if hrp then
            lightPart = Instance.new("Part"); lightPart.Name="LightningFlashHolder"; lightPart.Anchored=true; lightPart.CanCollide=false; lightPart.CanQuery=false; lightPart.CanTouch=false; lightPart.Transparency=1; lightPart.Size=Vector3.new(1,1,1); lightPart.CFrame=hrp.CFrame; lightPart.Parent=workspace
            worldLight = Instance.new("PointLight"); worldLight.Name="LightningFlashLight"; worldLight.Color=Color3.fromRGB(220,235,255); worldLight.Brightness=0; worldLight.Range=0; worldLight.Shadows=true; worldLight.Parent=lightPart
        end
        task.spawn(function()
            local steps = {{1-(power*0.34),1.7*power,40+(26*power),0.025},{1-(power*0.16),0.8*power,30+(18*power),0.035},{1-(power*0.48),2.5*power,52+(34*power),0.030},{1-(power*0.10),0.55*power,24+(14*power),0.060},{1,0,0,0.080}}
            for _, s in ipairs(steps) do
                if audioState.flashToken ~= token then break end
                local chr = lplr.Character; local h = chr and chr:FindFirstChild("HumanoidRootPart")
                if lightPart and lightPart.Parent and h then lightPart.CFrame = h.CFrame end
                if frame and frame.Parent then frame.BackgroundTransparency = s[1] end
                if worldLight and worldLight.Parent then worldLight.Brightness=s[2]; worldLight.Range=s[3] end
                task.wait(s[4])
            end
            if frame and frame.Parent and audioState.flashToken == token then frame.BackgroundTransparency = 1 end
            if lightPart then lightPart:Destroy() end
        end)
    end

    local ensureGameAudio = function()
        cleanupAudio()
        local gameAudio = Instance.new("Folder"); gameAudio.Name="GameAudio"; gameAudio.Parent=workspace
        local thunderSounds = Instance.new("Folder"); thunderSounds.Name="ThunderSounds"; thunderSounds.Parent=gameAudio
        local closeFolder = Instance.new("Folder"); closeFolder.Name="Close"; closeFolder.Parent=thunderSounds
        local farFolder = Instance.new("Folder"); farFolder.Name="Far"; farFolder.Parent=thunderSounds
        local brewingFolder = Instance.new("Folder"); brewingFolder.Name="Brewing"; brewingFolder.Parent=thunderSounds
        local rainFolder = Instance.new("Folder"); rainFolder.Name="Rain"; rainFolder.Parent=gameAudio
        local makeSound = function(p,n,id,vol,looped,spd) local s=Instance.new("Sound"); s.Name=n; s.SoundId=id; s.Volume=vol; s.Looped=looped or false; s.RollOffMode=Enum.RollOffMode.Inverse; s.RollOffMinDistance=35; s.RollOffMaxDistance=100000; s.EmitterSize=80; s.PlaybackSpeed=spd or 1; s.Parent=p; return s end
        local makeMuffler = function(s) local eq=Instance.new("EqualizerSoundEffect"); eq.Name="AudioMuffler"; eq.Enabled=true; eq.HighGain=0; eq.MidGain=0; eq.LowGain=0; eq.Parent=s; return eq end
        local makeLayer = function(p,n,id,vol,spd) local s=makeSound(p,n,id,0,true,spd); s:SetAttribute("OriginalVolume",vol); return s end
        local t1=makeSound(closeFolder,"Thunder1","rbxassetid://131300621",1.15,false,1); makeMuffler(t1)
        local t2=makeSound(closeFolder,"Thunder2","rbxassetid://5246104843",1.1,false,1); makeMuffler(t2)
        local t3=makeSound(closeFolder,"Thunder3","rbxassetid://6734470366",1.2,false,0.8); makeMuffler(t3)
        local r1=makeSound(farFolder,"Rumble1","rbxassetid://7742650861",0.9,false,1); makeMuffler(r1)
        local r2=makeSound(farFolder,"Rumble2","rbxassetid://4961240438",0.82,false,1); makeMuffler(r2)
        local r3=makeSound(farFolder,"Rumble3","rbxassetid://9120016241",0.82,false,1); makeMuffler(r3)
        local b1=makeSound(brewingFolder,"Rumble1","rbxassetid://4961240438",0.55,false,0.7); makeMuffler(b1)
        local b2=makeSound(brewingFolder,"Rumble2","rbxassetid://83308742405412",0.9,false,1); makeMuffler(b2)
        local hri=makeLayer(rainFolder,"HeavyRainInside","rbxassetid://97388832021513",0.42,1)
        local hro=makeLayer(rainFolder,"HeavyRainOutside","rbxassetid://9120551859",0.16,1)
        local lri=makeLayer(rainFolder,"LightRainInside","c",0.24,1.05)
        local lro=makeLayer(rainFolder,"LightRainOutside","rbxassetid://9120551859",0.10,1.08)
        local bw=makeLayer(rainFolder,"BlizzardWind","rbxassetid://4175285709",0.22,0.72)
        audioState.folder=gameAudio
        audioState.soundSets={
            LightRain={inside=lri,outside=lro,insideTarget=0.24,outsideTarget=0.10,thunderChance=0.62,minDelay=10,maxDelay=20},
            HeavyRain={inside=hri,outside=hro,insideTarget=0.42,outsideTarget=0.16,thunderChance=0.82,minDelay=6,maxDelay=14},
            Blizzard={inside=nil,outside=bw,insideTarget=0,outsideTarget=0.22,thunderChance=0,minDelay=999,maxDelay=999},
        }
        return gameAudio
    end

    local setMuffled = function(sound, muffled)
        if not sound then return end
        local eq = sound:FindFirstChild("AudioMuffler"); if not eq then return end
        if muffled then eq.LowGain=-2; eq.MidGain=-6; eq.HighGain=-18
        else eq.LowGain=0; eq.MidGain=0; eq.HighGain=0 end
    end

    local startWeatherAudio = function(mode)
        ensureGameAudio()
        local cfg = audioState.soundSets and audioState.soundSets[mode]; if not cfg then return end
        audioState.rainInside=cfg.inside; audioState.rainOutside=cfg.outside
        for _, s in ipairs({cfg.inside, cfg.outside}) do
            if s then s.Volume=0; s.TimePosition=0; if s.IsPlaying then s:Stop() end; s:Play() end
        end
        local rayParams = RaycastParams.new(); rayParams.FilterType=Enum.RaycastFilterType.Exclude
        audioState.roofHeartbeat = RunService.Heartbeat:Connect(function(dt)
            local char=lplr.Character; local hrp=char and char:FindFirstChild("HumanoidRootPart")
            if not hrp then
                if cfg.inside then tweenVolume(cfg.inside,0,0.12) end
                if cfg.outside then tweenVolume(cfg.outside,0,0.12) end; return
            end
            rayParams.FilterDescendantsInstances={char,audioState.folder}
            local blend, centerCovered = getRoofAudioBlend(hrp, rayParams)
            local outsideBlend = 1 - blend
            local insideTarget = cfg.insideTarget * (centerCovered and math.max(blend,0.7) or blend)
            local outsideTarget = centerCovered and cfg.outsideTarget*(0.08+outsideBlend*0.55) or cfg.outsideTarget*math.clamp(0.42+outsideBlend*0.58,0,1)
            local step = math.clamp((dt or 0.016)*5.6,0.05,0.16)
            if cfg.inside then tweenVolume(cfg.inside,insideTarget,step) end
            if cfg.outside then tweenVolume(cfg.outside,outsideTarget,step) end
        end)
        if cfg.thunderChance > 0 then
            local token = audioState.thunderToken + 1; audioState.thunderToken = token
            task.spawn(function()
                while audioState.thunderToken == token do
                    task.wait(math.random(cfg.minDelay*100, cfg.maxDelay*100)/100)
                    if audioState.thunderToken ~= token then break end
                    if math.random() > cfg.thunderChance then continue end
                    local tSounds=audioState.folder and audioState.folder:FindFirstChild("ThunderSounds")
                    local cf=tSounds and tSounds:FindFirstChild("Close"); local ff=tSounds and tSounds:FindFirstChild("Far"); local bf=tSounds and tSounds:FindFirstChild("Brewing")
                    local char=lplr.Character; local hrp=char and char:FindFirstChild("HumanoidRootPart")
                    local insideBlend,underRoof=0,false
                    if hrp then local tr=RaycastParams.new(); tr.FilterType=Enum.RaycastFilterType.Exclude; tr.FilterDescendantsInstances={char,audioState.folder}; insideBlend,underRoof=getRoofAudioBlend(hrp,tr) end
                    local forcedClose=false
                    if bf and math.random()<0.55 then
                        local brewing=bf:GetChildren()
                        if #brewing>0 then
                            local brew=brewing[math.random(1,#brewing)]; setMuffled(brew,underRoof or insideBlend>0.45); brew.TimePosition=0; brew:Play()
                            if math.random()<0.35 then task.wait(math.random(20,55)/100); if audioState.thunderToken~=token then break end; playLightningFlash(0.14) end
                            task.wait(math.random(140,320)/100); if audioState.thunderToken~=token then break end; forcedClose=true
                        end
                    else task.wait(math.random(10,45)/100); if audioState.thunderToken~=token then break end end
                    local useClose=forcedClose or (math.random()<(mode=="HeavyRain" and 0.45 or 0.20))
                    local src=useClose and cf or ff
                    if src then
                        local list=src:GetChildren()
                        if #list>0 then
                            local snd=list[math.random(1,#list)]; setMuffled(snd,underRoof or insideBlend>0.45); snd.TimePosition=0
                            playLightningFlash(useClose and math.random(75,100)/100 or math.random(28,50)/100); snd:Play()
                        end
                    end
                end
            end)
        end
    end

    local isCharacterPart = function(part) local m=part:FindFirstAncestorOfClass("Model"); return m and m:FindFirstChildOfClass("Humanoid") end
    local getLightHolderFolder = function() local f=workspace:FindFirstChild(LIGHT_HOLDER_FOLDER); if not f then f=Instance.new("Folder"); f.Name=LIGHT_HOLDER_FOLDER; f.Parent=workspace end; return f end
    local addSpotLight = function(part)
        if not part:IsA("BasePart") or not isCharacterPart(part) then return end
        local hf=getLightHolderFolder(); local hn=LIGHT_TAG.."_Holder_"..tostring(part:GetDebugId()); if hf:FindFirstChild(hn) then return end
        local holder=Instance.new("Part"); holder.Name=hn; holder.Anchored=true; holder.CanCollide=false; holder.CanQuery=false; holder.CanTouch=false; holder.Transparency=1; holder.Size=Vector3.new(0.2,0.2,0.2); holder.CFrame=part.CFrame; holder.Parent=hf
        local sl=Instance.new("SpotLight"); sl.Name=LIGHT_TAG.."_Spot"; sl.Brightness=0.1; sl.Range=35; sl.Angle=55; sl.Color=Color3.fromRGB(255,180,89); sl.Shadows=true; sl.Face=Enum.NormalId.Front; sl.Parent=holder
        table.insert(nightConnections, RunService.Heartbeat:Connect(function() if not holder.Parent then return end; if not part.Parent then holder:Destroy(); return end; holder.CFrame=part.CFrame end))
    end
    local addPointLight = function(part)
        if not part:IsA("BasePart") or part:FindFirstChild(LIGHT_TAG.."_Point") or isCharacterPart(part) or part.Size.Magnitude<6 then return end
        local pl=Instance.new("PointLight"); pl.Name=LIGHT_TAG.."_Point"; pl.Brightness=0.2; pl.Range=12; pl.Color=Color3.fromRGB(254,243,187); pl.Parent=part
    end
    local lightFolders = function()
        for _,child in ipairs(workspace:GetChildren()) do if child:IsA("Folder") then for _,d in ipairs(child:GetDescendants()) do addSpotLight(d); addPointLight(d) end end end
        for _,p in ipairs(Players:GetPlayers()) do local char=p.Character; if char then for _,part in ipairs(char:GetDescendants()) do addSpotLight(part) end end end
    end

    local buildRainScene = function(lplr, cam, folder, rainRate, dropletRate, mistRate, mistTransMin, mistTransMax)
        local conns = {}
        local makeWeatherPart = function(name, size, offset)
            local p=Instance.new("Part",folder); p.Name=name; p.Anchored=true; p.CanCollide=false; p.Transparency=1; p.Color=Color3.fromRGB(255,0,0); p.Size=size; p.CFrame=CFrame.new(0,0,0)
            local rain=Instance.new("ParticleEmitter",p); rain.Name="Rain"; rain.Texture="rbxassetid://1822883048"; rain.Rate=rainRate; rain.Lifetime=NumberRange.new(3,3); rain.Speed=NumberRange.new(100,100); rain.Drag=0; rain.Rotation=NumberRange.new(0,0); rain.RotSpeed=NumberRange.new(0,0); rain.VelocitySpread=2; rain.SpreadAngle=Vector2.new(2,2); rain.LightInfluence=0.38; rain.LightEmission=0.5; rain.ZOffset=0; rain.Acceleration=Vector3.new(0,0,0); rain.EmissionDirection=Enum.NormalId.Bottom; rain.Orientation=Enum.ParticleOrientation.FacingCameraWorldUp; rain.Shape=Enum.ParticleEmitterShape.Box; rain.ShapeStyle=Enum.ParticleEmitterShapeStyle.Volume; rain.ShapeInOut=Enum.ParticleEmitterShapeInOut.Outward; rain.Enabled=true
            rain.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.new(0.760784,0.823529,1)),ColorSequenceKeypoint.new(1,Color3.new(0.760784,0.823529,1))})
            rain.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,11),NumberSequenceKeypoint.new(1,11)})
            rain.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,0.85),NumberSequenceKeypoint.new(0.367,0.894),NumberSequenceKeypoint.new(0.395,1),NumberSequenceKeypoint.new(1,1)})
            table.insert(conns, RunService.Heartbeat:Connect(function() p.CFrame=cam.CFrame*CFrame.new(offset) end))
            p.AncestryChanged:Connect(function() if not p.Parent then for _,c in ipairs(conns) do c:Disconnect() end end end)
            return p, rain
        end
        local droplets=Instance.new("Part",folder); droplets.Name="Droplets"; droplets.Anchored=true; droplets.CanCollide=false; droplets.Transparency=1; droplets.Size=Vector3.new(50,1,50); droplets.CFrame=CFrame.new(0,0,0)
        local de=Instance.new("ParticleEmitter",droplets); de.Name="Emitter"; de.Texture="rbxassetid://241576804"; de.Rate=dropletRate; de.Lifetime=NumberRange.new(0.5,0.5); de.Speed=NumberRange.new(3,3); de.Drag=0; de.Rotation=NumberRange.new(-20,-20); de.RotSpeed=NumberRange.new(0,0); de.VelocitySpread=0; de.SpreadAngle=Vector2.new(0,0); de.LightInfluence=0; de.LightEmission=0.5; de.ZOffset=0; de.Acceleration=Vector3.new(0,-30,0); de.EmissionDirection=Enum.NormalId.Top; de.Orientation=Enum.ParticleOrientation.FacingCamera; de.Shape=Enum.ParticleEmitterShape.Box; de.ShapeStyle=Enum.ParticleEmitterShapeStyle.Volume; de.ShapeInOut=Enum.ParticleEmitterShapeInOut.Outward; de.Enabled=false
        de.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.new(1,1,1)),ColorSequenceKeypoint.new(1,Color3.new(1,1,1))})
        de.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,0),NumberSequenceKeypoint.new(1,1.0625)})
        de.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,1),NumberSequenceKeypoint.new(0.1,0),NumberSequenceKeypoint.new(0.55,0.75),NumberSequenceKeypoint.new(1,1)})
        local mistPart=Instance.new("Part",folder); mistPart.Name="MistPart"; mistPart.Anchored=true; mistPart.CanCollide=false; mistPart.Transparency=1; mistPart.Size=Vector3.new(100,1,100); mistPart.CFrame=CFrame.new(0,0,0)
        local mist=Instance.new("ParticleEmitter",mistPart); mist.Name="Mist"; mist.Texture="rbxassetid://135522315481814"; mist.Rate=mistRate; mist.Lifetime=NumberRange.new(6,10); mist.Speed=NumberRange.new(1,4); mist.Drag=0.8; mist.Rotation=NumberRange.new(0,360); mist.RotSpeed=NumberRange.new(-10,10); mist.VelocitySpread=360; mist.SpreadAngle=Vector2.new(20,20); mist.LightInfluence=1; mist.LightEmission=0; mist.ZOffset=0; mist.Acceleration=Vector3.new(-0.1,0,0); mist.EmissionDirection=Enum.NormalId.Top; mist.Orientation=Enum.ParticleOrientation.FacingCamera; mist.Shape=Enum.ParticleEmitterShape.Box; mist.ShapeStyle=Enum.ParticleEmitterShapeStyle.Volume; mist.ShapeInOut=Enum.ParticleEmitterShapeInOut.Outward; mist.Enabled=true
        mist.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.new(0.78,0.81,0.85)),ColorSequenceKeypoint.new(1,Color3.new(0.78,0.81,0.85))})
        mist.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,4),NumberSequenceKeypoint.new(0.4,8),NumberSequenceKeypoint.new(1,3)})
        mist.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,1),NumberSequenceKeypoint.new(0.1,mistTransMin),NumberSequenceKeypoint.new(0.9,mistTransMax),NumberSequenceKeypoint.new(1,1)})
        local _,r1=makeWeatherPart("PrimaryWeatherPart",Vector3.new(100,1,100),Vector3.new(0,37,0))
        local _,r2=makeWeatherPart("WeatherPart",Vector3.new(100,1,100),Vector3.new(0,-10,0))
        local _,r3=makeWeatherPart("WeatherPart",Vector3.new(100,1,100),Vector3.new(30,5,-30))
        local _,r4=makeWeatherPart("WeatherPart",Vector3.new(100,1,100),Vector3.new(-30,5,30))
        local rainEmitters={r1,r2,r3,r4}
        local edgeFolder=Instance.new("Folder",folder); edgeFolder.Name="EdgeRain"
        local edgeOffsets={Vector3.new(8,0,0),Vector3.new(-8,0,0),Vector3.new(0,0,8),Vector3.new(0,0,-8),Vector3.new(6,0,6),Vector3.new(-6,0,6),Vector3.new(6,0,-6),Vector3.new(-6,0,-6)}
        local edgeEmitters={}
        for _,offset in ipairs(edgeOffsets) do
            local ep=Instance.new("Part",edgeFolder); ep.Name="EdgePart"; ep.Anchored=true; ep.CanCollide=false; ep.Transparency=1; ep.Size=Vector3.new(6,1,6); ep.CFrame=CFrame.new(0,0,0)
            local ee=Instance.new("ParticleEmitter",ep); ee.Name="EdgeRain"; ee.Texture="rbxassetid://1822883048"; ee.Rate=rainRate*0.35; ee.Lifetime=NumberRange.new(2,3); ee.Speed=NumberRange.new(80,100); ee.Drag=0; ee.Rotation=NumberRange.new(0,0); ee.RotSpeed=NumberRange.new(0,0); ee.VelocitySpread=3; ee.SpreadAngle=Vector2.new(3,3); ee.LightInfluence=0.38; ee.LightEmission=0.5; ee.ZOffset=0; ee.Acceleration=Vector3.new(0,0,0); ee.EmissionDirection=Enum.NormalId.Bottom; ee.Orientation=Enum.ParticleOrientation.FacingCameraWorldUp; ee.Shape=Enum.ParticleEmitterShape.Box; ee.ShapeStyle=Enum.ParticleEmitterShapeStyle.Volume; ee.ShapeInOut=Enum.ParticleEmitterShapeInOut.Outward; ee.Enabled=false
            ee.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.new(0.760784,0.823529,1)),ColorSequenceKeypoint.new(1,Color3.new(0.760784,0.823529,1))})
            ee.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,8),NumberSequenceKeypoint.new(1,8)})
            ee.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,0.85),NumberSequenceKeypoint.new(0.367,0.894),NumberSequenceKeypoint.new(0.395,1),NumberSequenceKeypoint.new(1,1)})
            table.insert(edgeEmitters,{part=ep,emitter=ee,offset=offset})
        end
        local rayParams=RaycastParams.new(); rayParams.FilterType=Enum.RaycastFilterType.Exclude
        table.insert(conns, RunService.Heartbeat:Connect(function()
            local char=lplr.Character; local hrp=char and char:FindFirstChild("HumanoidRootPart")
            if not hrp then de.Enabled=false; mist.Enabled=false; for _,e in ipairs(rainEmitters) do e.Enabled=true end; for _,d in ipairs(edgeEmitters) do d.emitter.Enabled=false end; return end
            rayParams.FilterDescendantsInstances={char,folder,audioState.folder}
            local roofResult=workspace:Raycast(hrp.Position,Vector3.new(0,80,0),rayParams); local underRoof=roofResult~=nil
            for _,e in ipairs(rainEmitters) do e.Enabled=not underRoof end
            de.Enabled=false; mist.Enabled=false
            if underRoof then
                for _,d in ipairs(edgeEmitters) do
                    local ewp=hrp.Position+d.offset
                    d.emitter.Enabled=(workspace:Raycast(ewp,Vector3.new(0,80,0),rayParams)==nil)
                    d.part.CFrame=CFrame.new(ewp.X,hrp.Position.Y+18,ewp.Z)
                end
            else
                for _,d in ipairs(edgeEmitters) do d.emitter.Enabled=false end
                local floorResult=workspace:Raycast(hrp.Position+Vector3.new(0,5,0),Vector3.new(0,-60,0),rayParams)
                if floorResult and floorResult.Normal.Y>0.7 and floorResult.Position.Y<=hrp.Position.Y then
                    droplets.CFrame=CFrame.new(hrp.Position.X,floorResult.Position.Y,hrp.Position.Z)
                    mistPart.CFrame=CFrame.new(hrp.Position.X,floorResult.Position.Y+1,hrp.Position.Z)
                    de.Enabled=true; mist.Enabled=true
                end
            end
        end))
    end

    local makeSnowPart = function(name, rate, lifetime, speed, sizeKF, transKF, accel, folder, trackCam)
        local part=Instance.new("Part",folder); part.Name=name; part.Anchored=true; part.CanCollide=false; part.Transparency=1
        local e=Instance.new("ParticleEmitter",part); e.Name="Particle"; e.Texture="rbxassetid://127302768524882"; e.Rate=rate; e.Lifetime=lifetime; e.Speed=speed; e.Drag=0; e.VelocitySpread=trackCam and 5 or 18; e.SpreadAngle=trackCam and Vector2.new(5,5) or Vector2.new(12,12); e.LightInfluence=1; e.LightEmission=0; e.ZOffset=0; e.Acceleration=accel; e.EmissionDirection=Enum.NormalId.Front; e.Orientation=Enum.ParticleOrientation.FacingCamera; e.Shape=Enum.ParticleEmitterShape.Box; e.ShapeStyle=Enum.ParticleEmitterShapeStyle.Volume; e.ShapeInOut=Enum.ParticleEmitterShapeInOut.Outward; e.Enabled=true
        e.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.new(1,1,1)),ColorSequenceKeypoint.new(1,Color3.new(1,1,1))})
        e.Size=NumberSequence.new(sizeKF); e.Transparency=NumberSequence.new(transKF)
        if trackCam then
            part.Size=Vector3.new(100,80,1)
            local conn=RunService.Heartbeat:Connect(function() local hrp=lplr.Character and lplr.Character:FindFirstChild("HumanoidRootPart"); if hrp then part.CFrame=CFrame.new(hrp.Position+Vector3.new(0,0,50)) end end)
            part.AncestryChanged:Connect(function() if not part.Parent then conn:Disconnect() end end)
        else
            part.Size=Vector3.new(90,55,1)
            local OFFSET_Z,OFFSET_Y,zSign=10,5,1
            local conn=RunService.Heartbeat:Connect(function()
                local hrp=lplr.Character and lplr.Character:FindFirstChild("HumanoidRootPart"); if not hrp then return end
                local flatLook=Vector3.new(hrp.CFrame.LookVector.X,0,hrp.CFrame.LookVector.Z).Unit
                local toPart=Vector3.new(part.Position.X-hrp.Position.X,0,part.Position.Z-hrp.Position.Z)
                if toPart.Magnitude>0.01 and flatLook:Dot(toPart/toPart.Magnitude)<-0.85 then zSign=-zSign end
                part.CFrame=CFrame.lookAt(hrp.Position+Vector3.new(0,OFFSET_Y,OFFSET_Z*zSign),hrp.Position)
            end)
            part.AncestryChanged:Connect(function() if not part.Parent then conn:Disconnect() end end)
        end
        return part, e
    end

    local setupNightLights = function()
        lightFolders()
        table.insert(nightConnections,workspace.DescendantAdded:Connect(function(d) task.defer(function() addSpotLight(d); addPointLight(d) end) end))
        local watchChar = function(p) table.insert(nightConnections,p.CharacterAdded:Connect(function(char) task.defer(function() for _,part in ipairs(char:GetDescendants()) do addSpotLight(part) end end) end)) end
        for _,p in ipairs(Players:GetPlayers()) do watchChar(p) end
        table.insert(nightConnections,Players.PlayerAdded:Connect(watchChar))
        local last=0; table.insert(nightConnections,RunService.Heartbeat:Connect(function() if tick()-last<5 then return end; last=tick(); lightFolders() end))
    end

    local themes = {
        Default = function()
            cleanupAll()
            applyLighting([[local L=game:GetService('Lighting');L:ClearAllChildren();task.wait(0.3);L.Ambient=Color3.new(0.576471,0.67451,0.784314);L.Brightness=3;L.ColorShift_Bottom=Color3.new(0.294118,0.235294,0.192157);L.ColorShift_Top=Color3.new(0,0,0);L.OutdoorAmbient=Color3.new(0.576471,0.67451,0.784314);L.FogColor=Color3.new(0.752941,0.752941,0.752941);L.FogEnd=100000;L.FogStart=0;L.GlobalShadows=true;L.GeographicLatitude=45;L.ExposureCompensation=0;L.EnvironmentDiffuseScale=1;L.EnvironmentSpecularScale=1;L.ClockTime=14.5;L.TimeOfDay='14:30:00';L.ShadowSoftness=0.1;L.Technology=Enum.Technology.ShadowMap;local blo=Instance.new('BloomEffect',L);blo.Name='Bloom';blo.Enabled=true;blo.Intensity=1;blo.Size=10;blo.Threshold=2;local col=Instance.new('ColorCorrectionEffect',L);col.Name='DeathBarrierEffect';col.Enabled=false;col.Brightness=0;col.Contrast=0;col.Saturation=0;col.TintColor=Color3.new(0.858824,0.627451,1);local col2=Instance.new('ColorCorrectionEffect',L);col2.Name='ColorCorrection';col2.Enabled=true;col2.Brightness=0;col2.Contrast=0.05;col2.Saturation=0.05;col2.TintColor=Color3.new(1,1,1);local sky=Instance.new('Sky',L);sky.Name='Sky';sky.CelestialBodiesShown=true;sky.SunAngularSize=21;sky.MoonAngularSize=11;sky.SkyboxBk='rbxassetid://93968881652239';sky.SkyboxDn='rbxassetid://102254730940508';sky.SkyboxFt='rbxassetid://93968881652239';sky.SkyboxLf='rbxassetid://93968881652239';sky.SkyboxRt='rbxassetid://93968881652239';sky.SkyboxUp='rbxassetid://112261788034018';sky.StarCount=3000;sky.SunTextureId='';sky.MoonTextureId='';local col3=Instance.new('ColorCorrectionEffect',L);col3.Name='SmokeColorCorrection';col3.Enabled=false;col3.Brightness=0;col3.Contrast=0;col3.Saturation=-0.5;col3.TintColor=Color3.new(0.588235,0.588235,0.588235)]])
        end,
        Morning = function()
            cleanupAll()
            applyLighting([[local L=game:GetService('Lighting');L:ClearAllChildren();task.wait(0.3);L.Ambient=Color3.new(0,0,0);L.Brightness=3;L.ColorShift_Bottom=Color3.new(1,1,1);L.ColorShift_Top=Color3.new(0.972549,0.537255,0.152941);L.OutdoorAmbient=Color3.new(0,0,0);L.FogColor=Color3.new(0.752941,0.752941,0.752941);L.FogEnd=100000;L.FogStart=0;L.GlobalShadows=true;L.GeographicLatitude=40;L.ExposureCompensation=0.7;L.EnvironmentDiffuseScale=1;L.EnvironmentSpecularScale=1;L.ClockTime=7;L.TimeOfDay='07:00:00';L.ShadowSoftness=0.03;L.Technology=Enum.Technology.Future;local sky=Instance.new('Sky',L);sky.Name='60';sky.CelestialBodiesShown=true;sky.SunAngularSize=5;sky.MoonAngularSize=1.5;sky.SkyboxBk='rbxassetid://6973550206';sky.SkyboxDn='rbxassetid://6973550815';sky.SkyboxFt='rbxassetid://6973549125';sky.SkyboxLf='rbxassetid://6973549670';sky.SkyboxRt='rbxassetid://9089057892';sky.SkyboxUp='rbxassetid://6973551204';sky.StarCount=5000;sky.SunTextureId='rbxassetid://1084351190';sky.MoonTextureId='rbxassetid://1075087760';local atm=Instance.new('Atmosphere',L);atm.Name='Atmosphere';atm.Density=0.325;atm.Offset=1;atm.Color=Color3.new(0,0,0);atm.Decay=Color3.new(0,0,0);atm.Glare=0;atm.Haze=0.05;local blo=Instance.new('BloomEffect',L);blo.Name='Bloom';blo.Enabled=true;blo.Intensity=1;blo.Size=56;blo.Threshold=2.9;local blu=Instance.new('BlurEffect',L);blu.Name='Blur';blu.Enabled=false;blu.Size=3;local col=Instance.new('ColorCorrectionEffect',L);col.Name='ColorCorrection';col.Enabled=true;col.Brightness=0;col.Contrast=0.1;col.Saturation=0.2;col.TintColor=Color3.new(1,1,1);local sun=Instance.new('SunRaysEffect',L);sun.Name='SunRays';sun.Enabled=true;sun.Intensity=0.004;sun.Spread=0.04]])
        end,
        Sunset = function()
            cleanupAll()
            applyLighting([[local L=game:GetService('Lighting');L:ClearAllChildren();task.wait(0.3);L.Ambient=Color3.new(0,0,0);L.Brightness=1.5;L.ColorShift_Bottom=Color3.new(0,0,0);L.ColorShift_Top=Color3.new(0.666667,0.533333,0.321569);L.OutdoorAmbient=Color3.new(0,0,0);L.FogColor=Color3.new(0.752941,0.752941,0.752941);L.FogEnd=100000;L.FogStart=0;L.GlobalShadows=true;L.GeographicLatitude=40;L.ExposureCompensation=0.5;L.EnvironmentDiffuseScale=1;L.EnvironmentSpecularScale=1;L.ClockTime=17.6;L.TimeOfDay='17:36:00';L.ShadowSoftness=0.03;L.Technology=Enum.Technology.Future;local sky=Instance.new('Sky',L);sky.Name='60';sky.CelestialBodiesShown=true;sky.SunAngularSize=5;sky.MoonAngularSize=1.5;sky.SkyboxBk='rbxassetid://6973550206';sky.SkyboxDn='rbxassetid://6973550815';sky.SkyboxFt='rbxassetid://6973549125';sky.SkyboxLf='rbxassetid://6973549670';sky.SkyboxRt='rbxassetid://9089057892';sky.SkyboxUp='rbxassetid://6973551204';sky.StarCount=5000;sky.SunTextureId='rbxassetid://1084351190';sky.MoonTextureId='rbxassetid://1075087760';local atm=Instance.new('Atmosphere',L);atm.Name='Atmosphere';atm.Density=0.35;atm.Offset=1;atm.Color=Color3.new(0.490196,0.247059,0.45098);atm.Decay=Color3.new(0.411765,0.643137,0.705882);atm.Glare=0;atm.Haze=0.05;local blo=Instance.new('BloomEffect',L);blo.Name='Bloom';blo.Enabled=true;blo.Intensity=1;blo.Size=56;blo.Threshold=2.9;local blu=Instance.new('BlurEffect',L);blu.Name='Blur';blu.Enabled=false;blu.Size=3;local col=Instance.new('ColorCorrectionEffect',L);col.Name='ColorCorrection';col.Enabled=true;col.Brightness=0;col.Contrast=0.05;col.Saturation=0.1;col.TintColor=Color3.new(1,0.921569,0.796078);local sun=Instance.new('SunRaysEffect',L);sun.Name='SunRays';sun.Enabled=true;sun.Intensity=0.004;sun.Spread=0.04]])
        end,
        Blizzard = function()
            cleanupAll()
            applyLighting([[local L=game:GetService('Lighting');L:ClearAllChildren();task.wait(0.3);L.Ambient=Color3.new(0,0,0);L.Brightness=1;L.ColorShift_Bottom=Color3.new(0,0,0);L.ColorShift_Top=Color3.new(0,0,0);L.OutdoorAmbient=Color3.new(0.576471,0.6,0.760784);L.FogColor=Color3.new(0.576471,0.6,0.760784);L.FogEnd=300;L.FogStart=15;L.GlobalShadows=true;L.GeographicLatitude=23.5;L.ExposureCompensation=0;L.EnvironmentDiffuseScale=0.4;L.EnvironmentSpecularScale=0.6;L.ClockTime=12;L.TimeOfDay='12:00:00';L.ShadowSoftness=0.07;L.Technology=Enum.Technology.Future;local sky=Instance.new('Sky',L);sky.Name='Sky';sky.CelestialBodiesShown=false;sky.SkyboxBk='http://www.roblox.com/asset/?id=4514139911';sky.SkyboxDn='http://www.roblox.com/asset/?id=4514139911';sky.SkyboxFt='http://www.roblox.com/asset/?id=4514139911';sky.SkyboxLf='http://www.roblox.com/asset/?id=4514139911';sky.SkyboxRt='http://www.roblox.com/asset/?id=4514139911';sky.SkyboxUp='http://www.roblox.com/asset/?id=4514139911';sky.StarCount=3000;local atm=Instance.new('Atmosphere',L);atm.Name='Blizzard_Atmosphere';atm.Density=0.531;atm.Offset=0.281;atm.Color=Color3.new(0.686275,0.733333,0.780392);atm.Decay=Color3.new(0.619608,0.666667,0.784314);atm.Glare=2.69;atm.Haze=10]])
            local folder=Instance.new("Folder",workspace); folder.Name="Snowfall_Client"
            makeSnowPart("Blizzard",5000,NumberRange.new(6,8),NumberRange.new(20,50),
                {NumberSequenceKeypoint.new(0,1.875),NumberSequenceKeypoint.new(0.374999,1.25),NumberSequenceKeypoint.new(1,0)},
                {NumberSequenceKeypoint.new(0,1),NumberSequenceKeypoint.new(0.501247,0.4375),NumberSequenceKeypoint.new(1,0)},
                Vector3.new(0,-0.4,0),folder,true)
            startWeatherAudio("Blizzard")
        end,
        LightSnow = function()
            cleanupAll()
            applyLighting([[local L=game:GetService('Lighting');L:ClearAllChildren();task.wait(0.3);L.Ambient=Color3.new(0.15,0.15,0.15);L.Brightness=1.7;L.ColorShift_Bottom=Color3.new(0,0,0);L.ColorShift_Top=Color3.new(0,0,0);L.OutdoorAmbient=Color3.new(0.68,0.72,0.78);L.FogColor=Color3.new(0.76,0.8,0.86);L.FogEnd=850;L.FogStart=35;L.GlobalShadows=true;L.GeographicLatitude=23.5;L.ExposureCompensation=0;L.EnvironmentDiffuseScale=0.5;L.EnvironmentSpecularScale=0.65;L.ClockTime=12.3;L.TimeOfDay='12:18:00';L.ShadowSoftness=0.05;L.Technology=Enum.Technology.Future;local sky=Instance.new('Sky',L);sky.Name='Sky';sky.CelestialBodiesShown=false;sky.SkyboxBk='http://www.roblox.com/asset/?id=4514139911';sky.SkyboxDn='http://www.roblox.com/asset/?id=4514139911';sky.SkyboxFt='http://www.roblox.com/asset/?id=4514139911';sky.SkyboxLf='http://www.roblox.com/asset/?id=4514139911';sky.SkyboxRt='http://www.roblox.com/asset/?id=4514139911';sky.SkyboxUp='http://www.roblox.com/asset/?id=4514139911';sky.StarCount=3000;local atm=Instance.new('Atmosphere',L);atm.Name='LightSnow_Atmosphere';atm.Density=0.4;atm.Offset=0.12;atm.Color=Color3.new(0.8,0.84,0.89);atm.Decay=Color3.new(0.7,0.74,0.81);atm.Glare=0.7;atm.Haze=2.4;local col=Instance.new('ColorCorrectionEffect',L);col.Name='ColorCorrection';col.Enabled=true;col.Brightness=-0.01;col.Contrast=0.04;col.Saturation=-0.1;col.TintColor=Color3.new(0.96,0.98,1)]])
            local folder=Instance.new("Folder",workspace); folder.Name="Snowfall_Client"
            makeSnowPart("LightSnow",450,NumberRange.new(7,10),NumberRange.new(6,14),
                {NumberSequenceKeypoint.new(0,0.45),NumberSequenceKeypoint.new(0.7,0.32),NumberSequenceKeypoint.new(1,0.18)},
                {NumberSequenceKeypoint.new(0,0.35),NumberSequenceKeypoint.new(0.8,0.5),NumberSequenceKeypoint.new(1,1)},
                Vector3.new(0,-1.2,0),folder,false)
        end,
        ChillMorning = function()
            cleanupAll()
            applyLighting([[local L=game:GetService('Lighting');L:ClearAllChildren();task.wait(0.3);L.Ambient=Color3.new(0,0,0);L.Brightness=2.2;L.ColorShift_Bottom=Color3.new(0.9,0.95,1);L.ColorShift_Top=Color3.new(0.972549,0.537255,0.152941);L.OutdoorAmbient=Color3.new(0.62,0.66,0.74);L.FogColor=Color3.new(0.82,0.87,0.93);L.FogEnd=680;L.FogStart=30;L.GlobalShadows=true;L.GeographicLatitude=40;L.ExposureCompensation=0.55;L.EnvironmentDiffuseScale=0.6;L.EnvironmentSpecularScale=0.75;L.ClockTime=7.2;L.TimeOfDay='07:12:00';L.ShadowSoftness=0.04;L.Technology=Enum.Technology.Future;local sky=Instance.new('Sky',L);sky.Name='ChillMorningSky';sky.CelestialBodiesShown=true;sky.SunAngularSize=5;sky.MoonAngularSize=1.5;sky.SkyboxBk='rbxassetid://6973550206';sky.SkyboxDn='rbxassetid://6973550815';sky.SkyboxFt='rbxassetid://6973549125';sky.SkyboxLf='rbxassetid://6973549670';sky.SkyboxRt='rbxassetid://9089057892';sky.SkyboxUp='rbxassetid://6973551204';sky.StarCount=2000;sky.SunTextureId='rbxassetid://1084351190';sky.MoonTextureId='rbxassetid://1075087760';local atm=Instance.new('Atmosphere',L);atm.Name='ChillMorning_Atmosphere';atm.Density=0.38;atm.Offset=0.18;atm.Color=Color3.new(0.78,0.82,0.88);atm.Decay=Color3.new(0.68,0.72,0.80);atm.Glare=0.9;atm.Haze=2.0;local blo=Instance.new('BloomEffect',L);blo.Name='Bloom';blo.Enabled=true;blo.Intensity=0.85;blo.Size=48;blo.Threshold=2.7;local col=Instance.new('ColorCorrectionEffect',L);col.Name='ColorCorrection';col.Enabled=true;col.Brightness=0.02;col.Contrast=0.08;col.Saturation=0.05;col.TintColor=Color3.new(0.96,0.98,1);local sun=Instance.new('SunRaysEffect',L);sun.Name='SunRays';sun.Enabled=true;sun.Intensity=0.003;sun.Spread=0.035]])
            local folder=Instance.new("Folder",workspace); folder.Name="Snowfall_Client"
            makeSnowPart("ChillMorning",320,NumberRange.new(8,12),NumberRange.new(4,10),
                {NumberSequenceKeypoint.new(0,0.40),NumberSequenceKeypoint.new(0.7,0.28),NumberSequenceKeypoint.new(1,0.14)},
                {NumberSequenceKeypoint.new(0,0.28),NumberSequenceKeypoint.new(0.8,0.48),NumberSequenceKeypoint.new(1,1)},
                Vector3.new(0,-0.9,0),folder,false)
        end,
        LightRain = function()
            cleanupAll()
            applyLighting([[local L=game:GetService('Lighting');L:ClearAllChildren();task.wait(0.3);L.Ambient=Color3.new(0,0,0);L.Brightness=1.4;L.ColorShift_Bottom=Color3.new(0,0,0);L.ColorShift_Top=Color3.new(0.6,0.6,0.6);L.OutdoorAmbient=Color3.new(0.3,0.32,0.36);L.FogColor=Color3.new(0.72,0.74,0.78);L.FogEnd=800;L.FogStart=40;L.GlobalShadows=true;L.GeographicLatitude=40;L.ExposureCompensation=0;L.EnvironmentDiffuseScale=0.8;L.EnvironmentSpecularScale=0.6;L.ClockTime=13;L.TimeOfDay='15:00:00';L.ShadowSoftness=0.05;L.Technology=Enum.Technology.Future;local sky=Instance.new('Sky',L);sky.Name='Sky';sky.CelestialBodiesShown=false;sky.SkyboxBk='http://www.roblox.com/asset/?id=4514139911';sky.SkyboxDn='http://www.roblox.com/asset/?id=4514139911';sky.SkyboxFt='http://www.roblox.com/asset/?id=4514139911';sky.SkyboxLf='http://www.roblox.com/asset/?id=4514139911';sky.SkyboxRt='http://www.roblox.com/asset/?id=4514139911';sky.SkyboxUp='http://www.roblox.com/asset/?id=4514139911';sky.StarCount=0;local atm=Instance.new('Atmosphere',L);atm.Name='LightRain_Atmosphere';atm.Density=0.38;atm.Offset=0.08;atm.Color=Color3.new(0.74,0.76,0.80);atm.Decay=Color3.new(0.60,0.62,0.66);atm.Glare=0.3;atm.Haze=1.8;local col=Instance.new('ColorCorrectionEffect',L);col.Name='ColorCorrection';col.Enabled=true;col.Brightness=-0.02;col.Contrast=0.03;col.Saturation=-0.15;col.TintColor=Color3.new(0.94,0.96,1)]])
            local folder=Instance.new("Folder",workspace); folder.Name="Snowfall_Client"
            buildRainScene(lplr,workspace.CurrentCamera,folder,28,38,6,0.94,0.97)
            startWeatherAudio("LightRain")
        end,
        HeavyRain = function()
            cleanupAll()
            applyLighting([[local L=game:GetService('Lighting');L:ClearAllChildren();task.wait(0.3);L.Ambient=Color3.new(0.168627,0.168627,0.168627);L.Brightness=1;L.ColorShift_Bottom=Color3.new(0,0,0);L.ColorShift_Top=Color3.new(0,0,0);L.OutdoorAmbient=Color3.new(0.168627,0.168627,0.168627);L.FogColor=Color3.new(0.752941,0.752941,0.752941);L.FogEnd=100000;L.FogStart=0;L.GlobalShadows=true;L.GeographicLatitude=0;L.ExposureCompensation=0;L.EnvironmentDiffuseScale=1;L.EnvironmentSpecularScale=1;L.ClockTime=0;L.TimeOfDay='2:00:00';L.ShadowSoftness=0.2;L.Technology=Enum.Technology.ShadowMap;local atm=Instance.new('Atmosphere',L);atm.Name='Atmosphere';atm.Density=0.6;atm.Offset=0;atm.Color=Color3.new(0.780392,0.780392,0.780392);atm.Decay=Color3.new(0.415686,0.439216,0.490196);atm.Glare=0;atm.Haze=0;local col=Instance.new('ColorCorrectionEffect',L);col.Name='ColorCorrection';col.Enabled=true;col.Brightness=0;col.Contrast=0;col.Saturation=0.5;col.TintColor=Color3.new(1,1,1);local sky=Instance.new('Sky',L);sky.Name='Sky';sky.CelestialBodiesShown=true;sky.SunAngularSize=11;sky.MoonAngularSize=11;sky.SkyboxBk='rbxassetid://6444884337';sky.SkyboxDn='rbxassetid://6444884785';sky.SkyboxFt='rbxassetid://6444884337';sky.SkyboxLf='rbxassetid://6444884337';sky.SkyboxRt='rbxassetid://6444884337';sky.SkyboxUp='rbxassetid://6412503613';sky.StarCount=3000;sky.SunTextureId='rbxassetid://6196665106';sky.MoonTextureId='rbxassetid://5076043799';local dep=Instance.new('DepthOfFieldEffect',L);dep.Name='DepthOfField';dep.Enabled=true;dep.FarIntensity=0.75;dep.FocusDistance=0.05;dep.InFocusRadius=75;dep.NearIntensity=0]])
            local folder=Instance.new("Folder",workspace); folder.Name="Snowfall_Client"
            buildRainScene(lplr,workspace.CurrentCamera,folder,82,50,18,0.88,0.93)
            startWeatherAudio("HeavyRain"); lightFolders()
        end,
        BloodMoon = function()
            cleanupAll()
            applyLighting([[local L=game:GetService('Lighting');L:ClearAllChildren();task.wait(0.3);L.Ambient=Color3.new(0.0784314,0.0784314,0.0784314);L.Brightness=0.5;L.ColorShift_Bottom=Color3.new(0,0,0);L.ColorShift_Top=Color3.new(0,0,0);L.OutdoorAmbient=Color3.new(0.423529,0.160784,0.164706);L.FogColor=Color3.new(0,0,0);L.FogEnd=300;L.FogStart=15;L.GlobalShadows=true;L.GeographicLatitude=23.5;L.ExposureCompensation=0;L.EnvironmentDiffuseScale=0.4;L.EnvironmentSpecularScale=0.6;L.ClockTime=0;L.TimeOfDay='00:00:00';L.ShadowSoftness=0.07;L.Technology=Enum.Technology.Future;local blu=Instance.new('BlurEffect',L);blu.Name='Blur';blu.Enabled=true;blu.Size=1;local blo=Instance.new('BloomEffect',L);blo.Name='DefaultBloom';blo.Enabled=true;blo.Intensity=0.2;blo.Size=100;blo.Threshold=0.8;local col2=Instance.new('ColorCorrectionEffect',L);col2.Name='Saturation';col2.Enabled=true;col2.Brightness=0;col2.Contrast=0;col2.Saturation=0.4;col2.TintColor=Color3.new(1,1,1);local sky=Instance.new('Sky',L);sky.Name='Sky';sky.CelestialBodiesShown=false;sky.SkyboxBk='http://www.roblox.com/asset/?id=4514139911';sky.SkyboxDn='http://www.roblox.com/asset/?id=4514139911';sky.SkyboxFt='http://www.roblox.com/asset/?id=4514139911';sky.SkyboxLf='http://www.roblox.com/asset/?id=4514139911';sky.SkyboxRt='http://www.roblox.com/asset/?id=4514139911';sky.SkyboxUp='http://www.roblox.com/asset/?id=4514139911';sky.StarCount=3000;local atm=Instance.new('Atmosphere',L);atm.Name='BloodNight_Atmosphere';atm.Density=0.58;atm.Offset=0;atm.Color=Color3.new(0.254902,0.14902,0.152941);atm.Decay=Color3.new(0.27451,0.0431373,0.0509804);atm.Glare=0;atm.Haze=4.47]])
        end,
        Nighttime = function()
            cleanupAll()
            applyLighting([[local L=game:GetService('Lighting');L:ClearAllChildren();task.wait(0.3);L.Ambient=Color3.new(0.168627,0.168627,0.168627);L.Brightness=1;L.ColorShift_Bottom=Color3.new(0,0,0);L.ColorShift_Top=Color3.new(0,0,0);L.OutdoorAmbient=Color3.new(0.168627,0.168627,0.168627);L.FogColor=Color3.new(0.752941,0.752941,0.752941);L.FogEnd=100000;L.FogStart=0;L.GlobalShadows=true;L.GeographicLatitude=0;L.ExposureCompensation=0;L.EnvironmentDiffuseScale=1;L.EnvironmentSpecularScale=1;L.ClockTime=0;L.TimeOfDay='00:00:00';L.ShadowSoftness=0.2;L.Technology=Enum.Technology.Future;local sky=Instance.new('Sky',L);sky.Name='Sky';sky.CelestialBodiesShown=true;sky.SunAngularSize=11;sky.MoonAngularSize=11;sky.SkyboxBk='rbxassetid://6444884337';sky.SkyboxDn='rbxassetid://6444884785';sky.SkyboxFt='rbxassetid://6444884337';sky.SkyboxLf='rbxassetid://6444884337';sky.SkyboxRt='rbxassetid://6444884337';sky.SkyboxUp='rbxassetid://6412503613';sky.StarCount=3000;sky.SunTextureId='rbxassetid://6196665106';sky.MoonTextureId='rbxassetid://5076043799';local dep=Instance.new('DepthOfFieldEffect',L);dep.Name='DepthOfField';dep.Enabled=false;dep.FarIntensity=0;dep.FocusDistance=0.05;dep.InFocusRadius=30;dep.NearIntensity=0;local col=Instance.new('ColorCorrectionEffect',L);col.Name='ColorCorrection';col.Enabled=true;col.Brightness=0;col.Contrast=0;col.Saturation=0;col.TintColor=Color3.new(1,1,1);local atm=Instance.new('Atmosphere',L);atm.Name='Atmosphere';atm.Density=0.6;atm.Offset=0;atm.Color=Color3.new(0.780392,0.780392,0.780392);atm.Decay=Color3.new(0.415686,0.439216,0.490196);atm.Glare=0;atm.Haze=0]])
            setupNightLights()
            local gameAudio=Instance.new("Folder"); gameAudio.Name="GameAudio"; gameAudio.Parent=workspace; audioState.folder=gameAudio
            local bgSound=Instance.new("Sound"); bgSound.Name="OutsideNightAmbient"; bgSound.SoundId="rbxassetid://9112764891"; bgSound.Looped=true; bgSound.Volume=0.1; bgSound.RollOffMode=Enum.RollOffMode.Inverse; bgSound.RollOffMinDistance=35; bgSound.RollOffMaxDistance=100000; bgSound.EmitterSize=80; bgSound.Parent=gameAudio; bgSound:Play()
        end,
        Foggy = function()
            cleanupAll()
            applyLighting([[local L=game:GetService('Lighting');L:ClearAllChildren();task.wait(0.3);L.Ambient=Color3.new(0,0,0);L.Brightness=1;L.ColorShift_Bottom=Color3.new(0,0,0);L.ColorShift_Top=Color3.new(0,0,0);L.OutdoorAmbient=Color3.new(0.431373,0.431373,0.431373);L.FogColor=Color3.new(0.521569,0.521569,0.521569);L.FogEnd=300;L.FogStart=15;L.GlobalShadows=true;L.GeographicLatitude=23.5;L.ExposureCompensation=0;L.EnvironmentDiffuseScale=0.4;L.EnvironmentSpecularScale=0.6;L.ClockTime=12;L.TimeOfDay='12:00:00';L.ShadowSoftness=0.07;L.Technology=Enum.Technology.Future;local blu=Instance.new('BlurEffect',L);blu.Name='Blur';blu.Enabled=true;blu.Size=1;local blo=Instance.new('BloomEffect',L);blo.Name='DefaultBloom';blo.Enabled=true;blo.Intensity=0.2;blo.Size=100;blo.Threshold=0.8;local col2=Instance.new('ColorCorrectionEffect',L);col2.Name='Saturation';col2.Enabled=true;col2.Brightness=0;col2.Contrast=0;col2.Saturation=0.4;col2.TintColor=Color3.new(1,1,1);local sky=Instance.new('Sky',L);sky.Name='Sky';sky.CelestialBodiesShown=false;sky.SkyboxBk='http://www.roblox.com/asset/?id=4514139911';sky.SkyboxDn='http://www.roblox.com/asset/?id=4514139911';sky.SkyboxFt='http://www.roblox.com/asset/?id=4514139911';sky.SkyboxLf='http://www.roblox.com/asset/?id=4514139911';sky.SkyboxRt='http://www.roblox.com/asset/?id=4514139911';sky.SkyboxUp='http://www.roblox.com/asset/?id=4514139911';sky.StarCount=3000;local atm=Instance.new('Atmosphere',L);atm.Name='FoggyDay_Atmosphere';atm.Density=0.675;atm.Offset=0;atm.Color=Color3.new(0.780392,0.780392,0.780392);atm.Decay=Color3.new(0.454902,0.454902,0.454902);atm.Glare=4.95;atm.Haze=2.62]])
        end,
        WasteLand = function()
            cleanupAll()
            applyLighting([[local L=game:GetService('Lighting');L:ClearAllChildren();task.wait(0.3);L.Ambient=Color3.new(0,0,0);L.Brightness=3.5;L.ColorShift_Bottom=Color3.new(0,0,0);L.ColorShift_Top=Color3.new(1,0.752941,0.572549);L.OutdoorAmbient=Color3.new(0.254902,0.282353,0.207843);L.FogColor=Color3.new(0.752941,0.752941,0.752941);L.FogEnd=100000;L.FogStart=0;L.GlobalShadows=true;L.GeographicLatitude=53;L.ExposureCompensation=0;L.EnvironmentDiffuseScale=0.222;L.EnvironmentSpecularScale=1;L.ClockTime=7.8;L.TimeOfDay='07:48:00';L.ShadowSoftness=0.15;L.Technology=Enum.Technology.Voxel;local blo=Instance.new('BloomEffect',L);blo.Name='Bloom';blo.Enabled=true;blo.Intensity=0.15;blo.Size=20;blo.Threshold=2;local blu=Instance.new('BlurEffect',L);blu.Name='Blur';blu.Enabled=true;blu.Size=1;local col=Instance.new('ColorCorrectionEffect',L);col.Name='ColorCorrection';col.Enabled=true;col.Brightness=0.1;col.Contrast=0.2;col.Saturation=0;col.TintColor=Color3.new(0.803922,0.890196,1);local sun=Instance.new('SunRaysEffect',L);sun.Name='SunRays';sun.Enabled=true;sun.Intensity=-0.01;sun.Spread=1;local sky=Instance.new('Sky',L);sky.Name='Clouded Sky';sky.CelestialBodiesShown=true;sky.SunAngularSize=11;sky.MoonAngularSize=11;sky.SkyboxBk='http://www.roblox.com/asset/?id=252760981';sky.SkyboxDn='http://www.roblox.com/asset/?id=252763035';sky.SkyboxFt='http://www.roblox.com/asset/?id=252761439';sky.SkyboxLf='http://www.roblox.com/asset/?id=252760980';sky.SkyboxRt='http://www.roblox.com/asset/?id=252760986';sky.SkyboxUp='http://www.roblox.com/asset/?id=252762652';sky.StarCount=3000;sky.SunTextureId='rbxassetid://1345009717';sky.MoonTextureId='rbxasset://sky/moon.jpg';local atm=Instance.new('Atmosphere',L);atm.Name='Atmosphere';atm.Density=0.125;atm.Offset=0;atm.Color=Color3.new(0.45098,0.623529,0.65098);atm.Decay=Color3.new(0.160784,0.239216,0.247059);atm.Glare=0.5;atm.Haze=2.1]])
        end,
        Haze = function()
            cleanupAll()
            applyLighting([[local L=game:GetService('Lighting');L:ClearAllChildren();task.wait(0.3);L.Ambient=Color3.new(0.211765,0.219608,0.231373);L.Brightness=2.1;L.ColorShift_Bottom=Color3.new(0.713726,0.713726,0.713726);L.ColorShift_Top=Color3.new(0.956863,0.952941,0.886275);L.OutdoorAmbient=Color3.new(0.490196,0.482353,0.458824);L.FogColor=Color3.new(0.752941,0.752941,0.752941);L.FogEnd=100000;L.FogStart=0;L.GlobalShadows=true;L.GeographicLatitude=55;L.ExposureCompensation=0.6;L.EnvironmentDiffuseScale=0.5;L.EnvironmentSpecularScale=0.75;L.ClockTime=7.6;L.TimeOfDay='07:36:00';L.ShadowSoftness=0.1;L.Technology=Enum.Technology.Future;local atm=Instance.new('Atmosphere',L);atm.Name='Atmosphere';atm.Density=0.3;atm.Offset=0;atm.Color=Color3.new(1,0.964706,0.827451);atm.Decay=Color3.new(0.654902,0.627451,0.576471);atm.Glare=0.25;atm.Haze=0.15;local blo=Instance.new('BloomEffect',L);blo.Name='Bloom';blo.Enabled=true;blo.Intensity=0.05;blo.Size=38;blo.Threshold=2;local col=Instance.new('ColorCorrectionEffect',L);col.Name='Default';col.Enabled=true;col.Brightness=-0.06;col.Contrast=0.33;col.Saturation=0.1;col.TintColor=Color3.new(1,0.941176,0.878431);local dep=Instance.new('DepthOfFieldEffect',L);dep.Name='DepthOfField';dep.Enabled=true;dep.FarIntensity=0.1;dep.FocusDistance=100;dep.InFocusRadius=50;dep.NearIntensity=0;local sun=Instance.new('SunRaysEffect',L);sun.Name='Rays';sun.Enabled=true;sun.Intensity=0.022;sun.Spread=0.4;local sky=Instance.new('Sky',L);sky.Name='Sky';sky.CelestialBodiesShown=true;sky.SunAngularSize=11;sky.MoonAngularSize=11;sky.SkyboxBk='http://www.roblox.com/asset/?id=252760981';sky.SkyboxDn='http://www.roblox.com/asset/?id=252763035';sky.SkyboxFt='http://www.roblox.com/asset/?id=252761439';sky.SkyboxLf='http://www.roblox.com/asset/?id=252760980';sky.SkyboxRt='http://www.roblox.com/asset/?id=252760986';sky.SkyboxUp='http://www.roblox.com/asset/?id=252762652';sky.StarCount=3000;sky.SunTextureId='rbxassetid://1345009717';sky.MoonTextureId='rbxasset://sky/moon.jpg']])
        end,
        CherryBlossom = function()
            cleanupAll()
            applyLighting([[local L=game:GetService('Lighting');L:ClearAllChildren();task.wait(0.3);L.Ambient=Color3.new(0.627451,0.580392,0.631373);L.Brightness=8;L.ColorShift_Bottom=Color3.new(0.713726,0.713726,0.713726);L.ColorShift_Top=Color3.new(0.956863,0.952941,0.886275);L.OutdoorAmbient=Color3.new(0.552941,0.529412,0.576471);L.FogColor=Color3.new(0.752941,0.752941,0.752941);L.FogEnd=100000;L.FogStart=0;L.GlobalShadows=true;L.GeographicLatitude=25;L.ExposureCompensation=0.1;L.EnvironmentDiffuseScale=0;L.EnvironmentSpecularScale=0.75;L.ClockTime=16.7;L.TimeOfDay='16:42:00';L.ShadowSoftness=0.1;L.Technology=Enum.Technology.Future;local atm=Instance.new('Atmosphere',L);atm.Name='Atmosphere';atm.Density=0.33;atm.Offset=0;atm.Color=Color3.new(0.580392,0.462745,0.552941);atm.Decay=Color3.new(0.866667,0.768627,0.909804);atm.Glare=0.2;atm.Haze=0;local blo=Instance.new('BloomEffect',L);blo.Name='Bloom';blo.Enabled=true;blo.Intensity=0.05;blo.Size=38;blo.Threshold=2;local col=Instance.new('ColorCorrectionEffect',L);col.Name='Default';col.Enabled=true;col.Brightness=-0.04;col.Contrast=0.3;col.Saturation=0.1;col.TintColor=Color3.new(1,0.937255,1);local dep=Instance.new('DepthOfFieldEffect',L);dep.Name='DepthOfField';dep.Enabled=true;dep.FarIntensity=0.1;dep.FocusDistance=100;dep.InFocusRadius=50;dep.NearIntensity=0;local sun=Instance.new('SunRaysEffect',L);sun.Name='Rays';sun.Enabled=true;sun.Intensity=0.022;sun.Spread=0.4;local sky=Instance.new('Sky',L);sky.Name='Sky';sky.CelestialBodiesShown=true;sky.SunAngularSize=21;sky.MoonAngularSize=11;sky.SkyboxBk='rbxassetid://11555017034';sky.SkyboxDn='rbxassetid://11555013415';sky.SkyboxFt='rbxassetid://11555010145';sky.SkyboxLf='rbxassetid://11555006545';sky.SkyboxRt='rbxassetid://11555000712';sky.SkyboxUp='rbxassetid://11554996247';sky.StarCount=3000]])
        end,
        GoldenHour = function()
            cleanupAll()
            applyLighting([[local L=game:GetService('Lighting');L:ClearAllChildren();task.wait(0.3);L.Ambient=Color3.new(0.133333,0.137255,0.145098);L.Brightness=2.2;L.ColorShift_Bottom=Color3.new(0.713726,0.713726,0.713726);L.ColorShift_Top=Color3.new(0.956863,0.952941,0.886275);L.OutdoorAmbient=Color3.new(0.4,0.34902,0.321569);L.FogColor=Color3.new(0.752941,0.752941,0.752941);L.FogEnd=100000;L.FogStart=0;L.GlobalShadows=true;L.GeographicLatitude=55;L.ExposureCompensation=0.6;L.EnvironmentDiffuseScale=0.5;L.EnvironmentSpecularScale=0.75;L.ClockTime=16.65;L.TimeOfDay='16:39:00';L.ShadowSoftness=0.1;L.Technology=Enum.Technology.Future;local atm=Instance.new('Atmosphere',L);atm.Name='Atmosphere';atm.Density=0.33;atm.Offset=0;atm.Color=Color3.new(0.7843,0.6667,0.4235);atm.Decay=Color3.new(0.3608,0.2353,0.0549);atm.Glare=0;atm.Haze=0;local blo=Instance.new('BloomEffect',L);blo.Name='Bloom';blo.Enabled=true;blo.Intensity=0.05;blo.Size=38;blo.Threshold=2;local col=Instance.new('ColorCorrectionEffect',L);col.Name='Default';col.Enabled=true;col.Brightness=-0.04;col.Contrast=0.4;col.Saturation=0.1;col.TintColor=Color3.new(1,0.941176,0.878431);local dep=Instance.new('DepthOfFieldEffect',L);dep.Name='DepthOfField';dep.Enabled=true;dep.FarIntensity=0.1;dep.FocusDistance=100;dep.InFocusRadius=50;dep.NearIntensity=0;local sun=Instance.new('SunRaysEffect',L);sun.Name='Rays';sun.Enabled=true;sun.Intensity=0.022;sun.Spread=0.4;local sky=Instance.new('Sky',L);sky.Name='Sky';sky.CelestialBodiesShown=false;sky.SunAngularSize=21;sky.MoonAngularSize=11;sky.SkyboxBk='rbxassetid://600830446';sky.SkyboxDn='rbxassetid://600831635';sky.SkyboxFt='rbxassetid://600832720';sky.SkyboxLf='rbxassetid://600886090';sky.SkyboxRt='rbxassetid://600833862';sky.SkyboxUp='rbxassetid://600835177';sky.StarCount=3000]])
        end,
        Void = function()
            cleanupAll()
            applyLighting([[local L=game:GetService('Lighting');L:ClearAllChildren();task.wait(0.3);L.Ambient=Color3.new(0.784314,0.784314,0.784314);L.Brightness=1;L.ColorShift_Bottom=Color3.new(0,0,0);L.ColorShift_Top=Color3.new(0,0,0);L.OutdoorAmbient=Color3.new(0.588235,0.588235,0.588235);L.FogColor=Color3.new(0.431373,0.258824,0.666667);L.FogEnd=2000;L.FogStart=0;L.GlobalShadows=true;L.GeographicLatitude=41.7333;L.ExposureCompensation=0;L.EnvironmentDiffuseScale=0;L.EnvironmentSpecularScale=0;L.ClockTime=14;L.TimeOfDay='14:00:00';L.ShadowSoftness=0.5;L.Technology=Enum.Technology.ShadowMap;local sun=Instance.new('SunRaysEffect',L);sun.Name='SunRays';sun.Enabled=true;sun.Intensity=0;sun.Spread=1;local col=Instance.new('ColorCorrectionEffect',L);col.Name='ColorCorrection';col.Enabled=true;col.Brightness=0;col.Contrast=0.35;col.Saturation=0;col.TintColor=Color3.new(1,1,1);local blo=Instance.new('BloomEffect',L);blo.Name='Bloom';blo.Enabled=true;blo.Intensity=1;blo.Size=13;blo.Threshold=2;local sky=Instance.new('Sky',L);sky.Name='Sky';sky.CelestialBodiesShown=false;sky.SunAngularSize=21;sky.MoonAngularSize=11;sky.SkyboxBk='http://www.roblox.com/asset/?id=296908715';sky.SkyboxDn='http://www.roblox.com/asset/?id=296908724';sky.SkyboxFt='http://www.roblox.com/asset/?id=296908740';sky.SkyboxLf='http://www.roblox.com/asset/?id=296908755';sky.SkyboxRt='http://www.roblox.com/asset/?id=296908764';sky.SkyboxUp='http://www.roblox.com/asset/?id=296908769';sky.StarCount=0]])
        end,
        TimeCycle = function()
            cleanupAll()
            local L=game:GetService("Lighting"); L:ClearAllChildren(); L.Technology=Enum.Technology.Future; L.GlobalShadows=true; L.GeographicLatitude=40; L.ShadowSoftness=0.25; L.FogEnd=100000; L.FogStart=0; L.EnvironmentDiffuseScale=1; L.EnvironmentSpecularScale=1
            local sky=Instance.new("Sky",L); sky.Name="60"; sky.CelestialBodiesShown=true; sky.SunAngularSize=5; sky.MoonAngularSize=1.5; sky.SkyboxBk="rbxassetid://6973550206"; sky.SkyboxDn="rbxassetid://6973550815"; sky.SkyboxFt="rbxassetid://6973549125"; sky.SkyboxLf="rbxassetid://6973549670"; sky.SkyboxRt="rbxassetid://9089057892"; sky.SkyboxUp="rbxassetid://6973551204"; sky.StarCount=5000; sky.SunTextureId="rbxassetid://1084351190"; sky.MoonTextureId="rbxassetid://1075087760"
            local atm=Instance.new("Atmosphere",L)
            local bloom=Instance.new("BloomEffect",L); bloom.Name="Bloom"; bloom.Enabled=true
            local cc=Instance.new("ColorCorrectionEffect",L); cc.Name="ColorCorrection"; cc.Enabled=true
            local sun=Instance.new("SunRaysEffect",L); sun.Name="SunRays"; sun.Enabled=true; sun.Intensity=0.004; sun.Spread=0.04
            local KF={
                {clock=7,   brightness=3,   exposure=0.7, shadowSoftness=0.25, csTop=Color3.new(0.972549,0.537255,0.152941), csBot=Color3.new(1,1,1),               ambient=Color3.new(0,0,0),             outdoorAmbient=Color3.new(0,0,0),             atmDensity=0.325,atmOffset=1,   atmColor=Color3.new(0,0,0),             atmDecay=Color3.new(0,0,0),             atmGlare=0,atmHaze=0.05, bloomI=1,bloomS=56,bloomT=2.9,ccContrast=0.1, ccSat=0.2, ccTint=Color3.new(1,1,1)},
                {clock=14,  brightness=3,   exposure=0.4, shadowSoftness=0.15, csTop=Color3.new(1,0.941176,0.803922),         csBot=Color3.new(1,1,1),               ambient=Color3.new(0,0,0),             outdoorAmbient=Color3.new(0,0,0),             atmDensity=0.3,  atmOffset=0.9,  atmColor=Color3.new(0.101961,0.109804,0.152941),atmDecay=Color3.new(0.101961,0.109804,0.152941),atmGlare=0,atmHaze=0,    bloomI=1,bloomS=56,bloomT=2.9,ccContrast=0.05,ccSat=0.1, ccTint=Color3.new(1,1,1)},
                {clock=17.6,brightness=1.5, exposure=0.5, shadowSoftness=0.25, csTop=Color3.new(0.666667,0.533333,0.321569),  csBot=Color3.new(0,0,0),               ambient=Color3.new(0,0,0),             outdoorAmbient=Color3.new(0,0,0),             atmDensity=0.35, atmOffset=1,    atmColor=Color3.new(0.490196,0.247059,0.45098), atmDecay=Color3.new(0.411765,0.643137,0.705882),atmGlare=0,atmHaze=0.05, bloomI=1,bloomS=56,bloomT=2.9,ccContrast=0.05,ccSat=0.1, ccTint=Color3.new(1,0.921569,0.796078)},
                {clock=27,  brightness=1,   exposure=2.1, shadowSoftness=0.35, csTop=Color3.new(1,1,1),                        csBot=Color3.new(0,0,0),               ambient=Color3.new(0.098,0.098,0.098),outdoorAmbient=Color3.new(0.098,0.098,0.098),atmDensity=0.35, atmOffset=0.93, atmColor=Color3.new(0.133333,0.0901961,0.152941),atmDecay=Color3.new(0.133333,0.0901961,0.152941),atmGlare=0,atmHaze=0.05, bloomI=1,bloomS=56,bloomT=2.9,ccContrast=0.05,ccSat=-0.1,ccTint=Color3.new(1,1,1)},
            }
            local SEG_W={7/24,3.6/24,9.4/24,4/24}; local SEG_S={0}; for i=1,3 do SEG_S[i+1]=SEG_S[i]+SEG_W[i] end
            local CYCLE_DURATION=300; local cycleStart=tick()
            timeCycleConn=RunService.Heartbeat:Connect(function()
                local t=(tick()-cycleStart)%CYCLE_DURATION/CYCLE_DURATION
                local seg=4; for i=3,1,-1 do if t<SEG_S[i+1] then seg=i end end
                local a=KF[seg]; local b=KF[seg%4+1]; local st=math.clamp((t-SEG_S[seg])/SEG_W[seg],0,1)
                local lerp = function(x,y) return x+(y-x)*st end
                local clockB=(seg==4) and (KF[1].clock+24) or b.clock
                L.ClockTime=(a.clock+(clockB-a.clock)*st)%24; L.Brightness=lerp(a.brightness,b.brightness); L.ExposureCompensation=lerp(a.exposure,b.exposure)
                L.ColorShift_Top=a.csTop:Lerp(b.csTop,st); L.ColorShift_Bottom=a.csBot:Lerp(b.csBot,st); L.Ambient=a.ambient:Lerp(b.ambient,st); L.OutdoorAmbient=a.outdoorAmbient:Lerp(b.outdoorAmbient,st)
                atm.Density=lerp(a.atmDensity,b.atmDensity); atm.Offset=lerp(a.atmOffset,b.atmOffset); atm.Color=a.atmColor:Lerp(b.atmColor,st); atm.Decay=a.atmDecay:Lerp(b.atmDecay,st); atm.Glare=lerp(a.atmGlare,b.atmGlare); atm.Haze=lerp(a.atmHaze,b.atmHaze)
                bloom.Intensity=lerp(a.bloomI,b.bloomI); bloom.Size=lerp(a.bloomS,b.bloomS); bloom.Threshold=lerp(a.bloomT,b.bloomT)
                cc.Contrast=lerp(a.ccContrast,b.ccContrast); cc.Saturation=lerp(a.ccSat,b.ccSat); cc.TintColor=a.ccTint:Lerp(b.ccTint,st); L.ShadowSoftness=lerp(a.shadowSoftness,b.shadowSoftness)
            end)
        end,
    }

    GameThemes = GuiLibrary.Registry.renderPanel.API.CreateOptionsButton({
        Name = "GameThemes",
        Function = function(callback)
            if callback then themes[ThemeDropdown.Value]()
            else cleanupAll(); themes.Default() end
        end
    })
    ThemeDropdown = GameThemes.CreateDropdown({
        Name = "theme",
        List = {"Default","Morning","Sunset","LightSnow","ChillMorning","Blizzard","LightRain","HeavyRain","BloodMoon","Nighttime","Foggy","WasteLand","TimeCycle","GoldenHour","CherryBlossom","Haze","Void"},
        Default = "Default",
        Function = function(callback)
            if GameThemes.Enabled and themes[callback] then themes[callback]() end
        end
    })
end)

runcode(function()
    local ViewModel, Connection, Size = {}, nil, {Value = 5}
    local nobobhorizontal = {}
    local nobobdepth = {}
    local SwordSize = {}
    local yup = {}
    local FOV, FOVValue, OldFOV, FOVConnection = {Enabled = false}, {Value = 90}, nil, nil

    local function handleSize(v : Accessory)
        if v.ClassName == "Accessory" then
            scaleFactor = (Size.Value / 5) + 0.2
            local handle = v:FindFirstChild("Handle")
            if not handle then return end
            handle.Size *= scaleFactor
            -- handle.CFrame = CFrame.new(handle.Position)

            for _, child in handle:GetChildren() do
                if child:IsA("BasePart") then
                    for _, v in child:GetChildren() do
                        if v:IsA("WeldConstraint") then
                            v:Destroy()
                        end
                    end
                    child.Size *= scaleFactor

                    child.CFrame = handle.CFrame * CFrame.new((child.Position - handle.Position) * scaleFactor)
                    local weld = Instance.new("WeldConstraint", child)
                    weld.Part0 = child
                    weld.Part1 = handle
                end
            end
        end
    end

    ViewModel = GuiLibrary.Registry.renderPanel.API.CreateOptionsButton({
        Name = "ViewModel",
        Function = function(callback)
            if callback then
                if NoBob.Enabled then
                    if not oldViewmodelAnimation then
                        oldViewmodelAnimation = bedwars.ViewmodelController.playAnimation
                    end
                    bedwars.ViewmodelController.playAnimation = function(Self, id, ...)
                        local id = viewmodelCheck(Self, id, ...)
                        if not id then return end
                        return oldViewmodelAnimation(Self, id, ...)
                    end
                end
            else
                if Connection then Connection:Disconnect() end
                Connection = nil
                bedwars.ViewmodelController.playAnimation = oldViewmodelAnimation or bedwars.ViewmodelController.playAnimation
                lplr.PlayerScripts.TS.controllers.global.viewmodel["viewmodel-controller"]:SetAttribute("ConstantManager_DEPTH_OFFSET", 0)
                lplr.PlayerScripts.TS.controllers.global.viewmodel["viewmodel-controller"]:SetAttribute("ConstantManager_HORIZONTAL_OFFSET", 0)
            end
        end
    })
    Size = ViewModel.CreateSlider({
        Name = "Sword Size",
        Min = 0,
        Max = 10,
        Default = 1,
        Round = 1,
    })
    nobobdepth = ViewModel.CreateSlider({
        Name = "nobobdepth",
        Min = 0,
        Max = 24,
        Default = 5,
        Round = 1,
        Function = function(v)
            if ViewModel.Enabled and yup.Enabled then
                lplr.PlayerScripts.TS.controllers.global.viewmodel["viewmodel-controller"]:SetAttribute("ConstantManager_DEPTH_OFFSET", -(v / 10))
            end
        end
    })
    nobobhorizontal = ViewModel.CreateSlider({
        Name = "nobobdepth",
        Min = 0,
        Max = 24,
        Default = 5,
        Round = 1,
        Function = function(v)
            if ViewModel.Enabled and yup.Enabled then
                lplr.PlayerScripts.TS.controllers.global.viewmodel["viewmodel-controller"]:SetAttribute("ConstantManager_HORIZONTAL_OFFSET", (v/ 10))
            end
        end
    })
    NoBob = ViewModel.CreateToggle({
        Name = "NoBob",
        Default = true,
    })
    yup = ViewModel.CreateToggle({
        Name = "Horizontal, Depth",
        Default = true,
    })
    SwordSize = ViewModel.CreateToggle({
        Name = "SwordSize",
        Default = true,
        Function = function(callback)
            if callback and ViewModel.Enabled then
                Connection = Camera:WaitForChild("Viewmodel").ChildAdded:Connect(handleSize)
                for _, v in Camera.Viewmodel:GetChildren() do
                    handleSize(v)
                end
            end
        end
    })
    FOV = ViewModel.CreateToggle({
        Name = "FOV",
        Default = true,
        Function = function(callback)
            FOV.Enabled = callback
            if callback then
                OldFOV = OldFOV or workspace.CurrentCamera.FieldOfView
                if FOV.Enabled then
                    workspace.CurrentCamera.FieldOfView = FOVValue.Value
                end
                FOVConnection = workspace.CurrentCamera:GetPropertyChangedSignal("FieldOfView"):Connect(function() 
                    if workspace.CurrentCamera.FieldOfView ~= FOVValue.Value then 
                        workspace.CurrentCamera.FieldOfView = FOVValue.Value
                    end
                end)
            else
                if FOVConnection then FOVConnection:Disconnect() end
                if OldFOV then
                    workspace.CurrentCamera.FieldOfView = OldFOV
                    OldFOV = nil
                end
            end
        end
    })
    FOVValue = ViewModel.CreateSlider({
        Name = "Field of view",
        Min = 10,
        Max = 120,
        Round = 0,
        Default = 90,
        Function = function()
            if FOV.Enabled then
                workspace.CurrentCamera.FieldOfView = FOVValue.Value
            end
        end
    })
end)

runcode(function()
    local AutoConsume = {}
    -- local Consumablesa = {}
    local statusEffects = {
        ["speed_potion"] = "StatusEffect_speed",
        ["apple"] = "requiresMissingHealth"
    }

    local con
    local health
    local maxHealth
    local items = {}
    
    local consumeItem = function(item)
        task.spawn(function()
            bedwars.remotes.ConsumeItem:InvokeServer({
                item = item
            })
        end)
    end
    
    local updateConsumable = function(data, item)
        local statusCheck = statusEffects[item.Name]
        if data.consumable.requiresMissingHealth or data.consumable.potion or statusCheck then
            table.insert(items, {
                instance = item,
                data = data,
                statusCheck = statusCheck
            })
            return
        end

        consumeItem(item)
    end

    local checkConsumable = function(item : Accessory)
        local data = consumables[item.Name]
        if data then
            local amount = item:GetAttribute("Amount")
            local con
            con = item.AttributeChanged:Connect(function()
                local attr = item:GetAttribute("Amount")
                if attr > amount then
                    amount = attr
                    updateConsumable(data, item)
                end
            end)
            funcs:onExit("autoConsume_" .. item.Name, function()
                if con and item then
                    con:Disconnect()
                    con = nil
                end
            end)
            updateConsumable(data, item)
        end
    end

    AutoConsume = GuiLibrary.Registry.inventoryPanel.API.CreateOptionsButton({
        Name = "AutoConsume",
        Function = function(callback)
            if callback then
                for _, v in bedwars.inventoryIndex do
                    checkConsumable(v)
                end
                con = bedwars.inventory.ChildAdded:Connect(checkConsumable)

                repeat
                    if #items > 0 and PlayerUtility.lplrIsAlive then
                        health = lplr.Character:GetAttribute("Health")
                        maxHealth = lplr.Character:GetAttribute("MaxHealth")
                        for i, item in items do
                            local data = item.data
                            local statusCheck = item.statusCheck
                            local item = item.instance
                            if not item then table.remove(items, i) break end
                            if data.consumable.requiresMissingHealth then
                                if health < maxHealth then
                                    local amount = item:GetAttribute("Amount")
                                    consumeItem(item)
                                    --print((amount - 1))
                                    if amount and (amount - 1) <= 0 then
                                        table.remove(items, i)
                                    end
                                    break
                                end
                            end
                            if statusCheck and not lplr.Character:GetAttribute(statusCheck) then
                                local amount = item:GetAttribute("Amount")
                                consumeItem(item)
                                if amount and (amount - 1) <= 0 then
                                    table.remove(items, i)
                                end
                                break
                            end
                            if not statusCheck and data.consumable.potion then
                                local amount = item:GetAttribute("Amount")
                                consumeItem(item)
                                if amount and (amount - 1) <= 0 then
                                    table.remove(items, i)
                                end
                                break
                            end
                        end
                    end
                    task.wait()
                until not AutoConsume.Enabled
            else
                if con then
                    con:Disconnect()
                    con = nil
                end
            end
        end
    })
end)

runcode(function()
    local AutoQueue = {}
    local queueAttempted = false
    AutoQueue = GuiLibrary.Registry.utillityPanel.API.CreateOptionsButton({
        Name = "AutoQueue",
        Function = function(callback)
            if callback then
                newData.hookEvents.deathHooks.AutoQueue = function(eventData)
                    if eventData.finalKill and eventData.entityInstance == lplr.Character and not queueAttempted then
                        if newData.matchState == 2 then return end
                        bedwars.QueueController:joinQueue(newData.queueType)
                        queueAttempted = true
                    end
                end

                repeat task.wait() until newData.matchState == 2 or not AutoQueue.Enabled

                if not AutoQueue.Enabled then return end

                if not queueAttempted then
                    bedwars.QueueController:joinQueue(newData.queueType)
                    queueAttempted = true
                end
            else
                newData.hookEvents.deathHooks.AutoQueue = nil
                queueAttempted = false
            end
        end
    })
end)

runcode(function()
    local AntiAfk = {}; AntiAfk = GuiLibrary.Registry.worldPanel.API.CreateOptionsButton({
        Name = "AntiAFK",
        Function = function(callback)
            if callback then
                repeat
                    task.wait()
                until newData.matchState == 1

                local oldPos = chrCFrame.Position
                repeat
                    task.wait()
                until (oldPos - chrCFrame.Position).Magnitude > 10

                Client:Get("AfkInfo"):SendToServer({
                    afk = false
                })
            end
        end
    })
end)

--[[runcode(function()
    local KillList = {}
    local DisplayNames = {}
    local LowercaseMessage = {}
    local messagedPlayers = {}
    local entityDeath

    local function GetRandomValue(x)
        local values = {}
        for _, value in next, x do 
            values[#values + 1] = value 
        end
        return values[math.random(1, #values)] or ""
    end

    local AutoToxic = {}
    local hook
    AutoToxic = GuiLibrary.Registry.utillityPanel.API.CreateOptionsButton({
        Name = "AutoToxic",
        Function = function(callback)
            if callback then
                hook = newData.hookEvents.deathHooks.AutoToxic
                newData.hookEvents.deathHooks.AutoToxic = function(eventData)
                    local killer = Players:GetPlayerFromCharacter(eventData.fromEntity)
                    local victim = Players:GetPlayerFromCharacter(eventData.entityInstance)
    
                    if killer == lplr and victim and victim ~= lplr and not messagedPlayers[victim.UserId] then
                        local randomResponse
                        for i, v in pairs(KillList.Values) do
                            if v and v ~= "" then
                                randomResponse = GetRandomValue(KillList.Values):gsub("<plr>", victim.Name)
                                break
                            else
                                randomResponse = ""
                            end
                        end
                        randomResponse = ((not randomResponse or randomResponse == "") and "you suck <plr>" or randomResponse):gsub("<plr>", DisplayNames.Enabled and victim.DisplayName or victim.Name)
                        randomResponse = LowercaseMessage.Enabled and randomResponse:lower() or randomResponse
                        if randomResponse ~= "" then
                            ReplicatedStorage.DefaultChatSystemChatEvents.SayMessageRequest:FireServer(randomResponse, "All")
                            messagedPlayers[victim.UserId] = true
                            task.delay(5, function()
                                messagedPlayers[victim.UserId] = nil
                            end)
                        end
                    end
                end
            else
                newData.hookEvents.deathHooks.AutoToxic = hook
                hook = nil
            end
        end
    })
    KillList = AutoToxic.CreateTextlist({
        Name = "Kill <plr>",
    })
    DisplayNames = AutoToxic.CreateToggle({
        Name = "Display Names",
        Default = true 
    })
    LowercaseMessage = AutoToxic.CreateToggle({
        Name = "Lowercase Message",
        Default = false
    })
end)--]]

runcode(function()
    local health
    local maxHealth
    local playGuitar = ReplicatedStorage["rbxts_include"]["node_modules"]["@rbxts"].net.out["_NetManaged"].PlayGuitar
    local AutoHeal = {}
    
    AutoHeal = GuiLibrary.Registry.inventoryPanel.API.CreateOptionsButton({
        Name = "AutoHeal",
        Function = function(callback)
            if callback then
                repeat
                    if getItem("guitar") and PlayerUtility.lplrIsAlive then
                        health = lplr.Character:GetAttribute("Health")
                        maxHealth = lplr.Character:GetAttribute("MaxHealth")
                        if health < maxHealth then
                            playGuitar:FireServer({
                                healTarget = lplr
                            })
                        end
                    end
                    task.wait(0.01)
                until not AutoHeal.Enabled
            else
                RunLoops:UnbindFromHeartbeat("Autoheal")
            end
        end
    })
end)

runcode(function()
    local ChestStealer = {Enabled = false}
    local Range = {}
 
    local setObserve = bedwars.remotes.SetObservedChest
    local getItem = bedwars.remotes.ChestGetItem
 
    local chests = {}
    local cons = {}
    local chestCon = nil
    local observed = nil
 
    local stealTimer = 0
    local blacklist = {personal_chest = true}

    local function scanChest(folder)
        local loot = {}
        if not folder then return loot end
        for _, v in folder:GetChildren() do
            if v.ClassName == "Accessory" then
                loot[#loot + 1] = v
            end
        end
        return loot
    end
 
    local function indexChest(model)
        if blacklist[model.Name] then return end
 
        local folderValue = model:FindFirstChild("ChestFolderValue") or model:FindFirstChildOfClass("ObjectValue")
        if not folderValue then return end
 
        local inv = folderValue.Value
        if not inv then return end
        if chests[inv] then return end
 
        local entry = { chest = model, chestInv = inv, scan = scanChest(inv) }
        chests[inv] = entry
 
        local con = inv.ChildAdded:Connect(function()
            entry.scan = scanChest(inv)
        end)
        table.insert(cons, con)
    end
  
    ChestStealer = GuiLibrary.Registry.inventoryPanel.API.CreateOptionsButton({
        Name = "ChestStealer",
        Function = function(callback)
            if callback then
                local tagged = CollectionService:GetTagged("chest")
                if #tagged == 0 then
                    createNotification("ChestStealer", "no chests found")
                    return
                end
 
                for _, v in tagged do
                    task.spawn(indexChest, v)
                end
 
                chestCon = CollectionService:GetInstanceAddedSignal("chest"):Connect(function(v)
                    task.spawn(indexChest, v)
                end)
 
                RunLoops:BindToHeartbeat("ChestStealer", function(dt)
                    if not PlayerUtility.lplrIsAlive then return end
 
                    stealTimer -= dt
                    local range = Range.Value
                    local chrPos = chrCFrame.Position
 
                    local bestInv = nil
                    local bestDist = math.huge
 
                    for inv, entry in chests do
                        if #entry.scan == 0 then
                            chests[inv] = nil
                        else
                            local dist = (entry.chest.Position - chrPos).Magnitude
                            if dist <= range and dist < bestDist then
                                bestDist = dist
                                bestInv  = inv
                            end
                        end
                    end
 
                    if bestInv and stealTimer <= 0 then
                        stealTimer = 0.15
                        local entry = chests[bestInv]
                        if not entry then return end
 
                        if observed ~= bestInv then
                            observed = bestInv
                            task.spawn(function()
                                setObserve:SendToServer(bestInv)
                            end)
                        end
 
                        for i = #entry.scan, 1, -1 do
                            local item = entry.scan[i]
                            if item and item.Parent == bestInv then
                                local capturedItem = item
                                task.spawn(function()
                                    getItem:InvokeServer(bestInv, capturedItem)
                                end)
                            else
                                table.remove(entry.scan, i)
                            end
                        end
                    end
                end)
            else
                chests = {}
                observed = nil
                if chestCon then
                    chestCon:Disconnect()
                    chestCon = nil
                end
                RunLoops:UnbindFromHeartbeat("ChestStealer")
                for _, c in cons do c:Disconnect() end
                cons = {}
                task.spawn(function()
                    setObserve:SendToServer(nil)
                end)
            end
        end,
    })
    Range = ChestStealer.CreateSlider({
        Name = "Range",
        Min = 10,
        Max = 30,
        Default = 22,
    })
end)

--[[runcode(function()
    local ChatSpammer = {}
    local lastSentTime = 0
    local messageCount = 0

    local inviteLinks = {
        "F94NvExk2U",
        "Vaj5AU84sU",
        "UCtAuXa8d2",
        "BXj364yj4K"
    }
    
    local endsent = {
        "lh boosting(ranked)",
        "lè cheap / boosting(ranked)",
        "là Check out our boosts(ranked)!",
        "ljóin us for great deals(ranked)!",
        "hàh Don't miss out on our offers(ranked)!",
        "h hn Boosting services àvailable(ranked)!"
    }    

    local function obfuscateMessage(message)
        local replacements = {
            ["à"] = "a",
            ["é"] = "e",
            ["í"] = "i",
            ["ó"] = "o",
            ["ù"] = "u"
        }

        for original, replacement in pairs(replacements) do
            message = message:gsub(original, replacement)
        end
        
        return message
    end

    ChatSpammer = GuiLibrary.Registry.utillityPanel.API.CreateOptionsButton({
        Name = "ChatSpammer",
        Function = function(callback)
            if callback then
                repeat task.wait() until newData.matchState == 1 or not ChatSpammer.Enabled
                if not ChatSpammer.Enabled then return end
                if GuiLibrary.Registry.AutoToxicOptionsButton.API.Enabled then return end
                RunLoops:BindToHeartbeat("ChatSpammer", function()
                    if ReplicatedStorage:FindFirstChild('DefaultChatSystemChatEvents') then
                        if tick() - lastSentTime >= 3 then
                            local baseInvite = "Join gǵ /"

                            local randomInviteIndex
                            repeat
                                randomInviteIndex = math.random(1, #inviteLinks)
                            until randomInviteIndex ~= baseInvite

                            local randomInvite = inviteLinks[randomInviteIndex]

                            messageCount = messageCount + 1
                            local randomEnd = endsent[(messageCount - 1) % #endsent + 1]

                            local message = baseInvite .. " " .. randomInvite .. " " .. randomEnd
                            message = obfuscateMessage(message)

                            ReplicatedStorage.DefaultChatSystemChatEvents.SayMessageRequest:FireServer(message, "All")
                            lastSentTime = tick()
                        end
                    end
                end)
            else
                RunLoops:UnbindFromHeartbeat("ChatSpammer")
            end
        end
    })
end)--]]

runcode(function()
    local chestEsp = {}
    local trackItemList = {}

    local connections = {}
    local tracked = {}

    local connect = function(con, func)
        local id = HttpService:GenerateGUID(false)
        connections[id] = con:Connect(func)
        return connections[id]
    end

    local scaleBillboard = function(board)
        local itemCount = #board.Frame.Frame:GetChildren()
        board.Frame.Size = UDim2.new(itemCount, 0, 1)

        local imgCount = 0
        for _, v in board.Frame.Frame:GetChildren() do
            if v:IsA("ImageLabel") then
                imgCount += 1
                v.Size = UDim2.new(1 / itemCount, 0, 1)
                v.Position = UDim2.new((1 / itemCount) * imgCount, 0)
            end
        end
    end

    local addItem = function(board, item)
        local image = Instance.new("ImageLabel", board.Frame.Frame)
        image.BackgroundTransparency = 1
        image.AnchorPoint = Vector2.new(1, 0)

        image.Image = bedwars.getIcon({
            itemType = item.Name
        }, true)

        scaleBillboard(board)

        return image
    end

    local createBillboard = function(chest)
        local billboard = Instance.new("BillboardGui", CoreGui)
        billboard.Adornee = chest
        billboard.AlwaysOnTop = true
        billboard.MaxDistance = 9e9
        billboard.Size = UDim2.new(5, 0, 5)

        local frame = Instance.new("Frame", billboard)
        frame.BackgroundColor3 = Color3.new()
        frame.BackgroundTransparency = .5
        frame.Size = UDim2.new(1, 0, 1)
        frame.AnchorPoint = Vector2.new(.5, .5)
        frame.Position = UDim2.new(.5, 0, .5)

        local uiCorner = Instance.new("UICorner", frame)
        uiCorner.CornerRadius = UDim.new(.1, 0)

        local padding = Instance.new("Frame", frame)
        padding.BackgroundTransparency = 1
        padding.Size = UDim2.new(.8, 0, .8)
        padding.AnchorPoint = Vector2.new(.5, .5)
        padding.Position = UDim2.new(.5, 0, .5)

        -- local uiList = Instance.new("UIListLayout", padding)
        -- uiList.FillDirection = Enum.FillDirection.Horizontal
        -- uiList.Padding = UDim.new()

        return billboard
    end

    local checkChest = function(data, item)
        for _, prefix in pairs(trackItemList.Values) do
            if item.Name:lower():sub(1, #prefix:lower()) == prefix:lower() then
                tracked[data.folder] = tracked[data.folder] or {}
                tracked[data.folder].instance = tracked[data.folder].instance or createBillboard(data.chest)
                tracked[data.folder][item] = addItem(tracked[data.folder].instance, item)
                break
            end
        end
    end

    local countTable = function(tbl)
        local count = 0
        for _, v in tbl do
            count += 1
        end
        return count
    end

    local hookChest = function(v : Folder)
        local chestFolder = v:WaitForChild("ChestFolderValue").Value
        
        for _, item in chestFolder:GetChildren() do
            checkChest({
                chest = v,
                folder = chestFolder
            }, item)
        end
        connect(chestFolder.ChildAdded, function(item)
            checkChest({
                chest = v,
                folder = chestFolder
            }, item)
        end)
        connect(chestFolder.ChildRemoved, function(item)
            if tracked[chestFolder] and tracked[chestFolder][item] then
                if countTable(tracked[chestFolder]) > 2 then
                    tracked[chestFolder][item]:Destroy()
                    tracked[chestFolder][item] = nil
                    scaleBillboard(tracked[chestFolder].instance)
                else
                    tracked[chestFolder].instance:Destroy()
                    tracked[chestFolder] = nil
                end
            end
        end)
    end

    local chestEspCallback = function(callback)
        if callback then
            repeat
                task.wait()
            until trackItemList.Values ~= {}

            for _, v in CollectionService:GetTagged("chest") do
                hookChest(v)
            end
            connect(CollectionService:GetInstanceAddedSignal("chest"), hookChest)
        else
            for _, v in connections do
                v:Disconnect()
            end
            for _, v in tracked do
                v.instance:Destroy()
            end
            tracked = {}
        end
    end

    chestEsp = GuiLibrary.Registry.utillityPanel.API.CreateOptionsButton({
        Name = "ChestESP",
        Function = chestEspCallback
    })

    trackItemList = chestEsp.CreateTextlist({
        Name = "Items",
        -- Function = function()
        --     chestEspCallback(false)
        --     chestEspCallback(true)
        -- end
    })
end)

runcode(function()
    local oldItems = {}
    local oldItems2 = {}
    local CleanUp = {}
    local OldLeaderBoard = {}
    local blacklistedSounds = {
        "WIND_AMBIENCE",
        "AMBIENCE_SNOW",
        "CAVE_AMBIENCE",
        "FOREST_AMBIENCE",
        -- "LOBBY_MUSIC_SUMMER",
        -- "HALLOWEEN_2022_LOBBY_MUSIC",
        -- "LOBBY_MUSIC_FOREST",
        -- "LOBBY_MUSIC_DRUMS",
        -- "LOBBY_MUSIC_CRYSTALMOUNT",
        -- "LOBBY_MUSIC",
        -- "LOBBY_MUSIC_HEAVEN"
    }

    local ogSoundIds = {}

    for i, v in pairs(bedwars.ShopItems) do
        if type(v) == "table" then
            oldItems[v.itemType] = v.tiered
        end
        if v.tiered then
            oldItems2[v.itemType] = v.nextTier
        end
    end

    local soundFolders = {Lighting, workspace}
    CleanUp = GuiLibrary.Registry.utillityPanel.API.CreateOptionsButton({
        Name = "CleanUp",
        Function = function(callback)
            if callback then
                for i, v in pairs(bedwars.ShopItems) do
                    if type(v) == "table" then
                        v.tiered = nil
                        v.nextTier = nil
                    end
                end

                for _, fold in soundFolders do
                    for _, v in fold:GetDescendants() do
                        if v.ClassName == "Sound" then
                            for _, soundType in blacklistedSounds do
                                if v.SoundId == bedwars.SoundList[soundType] then
                                    v.Playing = false
                                end
                            end
                        end
                    end
                end
                for _, v in blacklistedSounds do
                    ogSoundIds[v] = bedwars.SoundList[v]
                    bedwars.SoundList[v] = "rbxassetid://0"
                end
                -- task.spawn(function()
                --     for _, v in workspace:WaitForChild("SpectatorPlatform"):GetChildren() do
                --         if v.ClassName == "Folder" then
                --             v:Destroy()
                --         end
                --     end
                -- end)
                lplr:SetAttribute("HideLobbyContentForBeginner", false)
            else
                for i, v in pairs(bedwars.ShopItems) do
                    if oldItems[v.itemType] then
                        v.tiered = oldItems[v.itemType]
                    end
                    if oldItems2[v.itemType] then
                        v.nextTier = oldItems2[v.itemType]
                    end
                end
                for i, v in ogSoundIds do
                    bedwars.SoundList[i] = v
                end
            end
        end
    })
    OldLeaderBoard = CleanUp.CreateToggle({
        Name = "OldLeaderBoard",
        Function = function(callback)
            if callback then
                if not StarterGui:GetCoreGuiEnabled(Enum.CoreGuiType.PlayerList) then
                    StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, true)
                end
            else
                StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
            end
        end
    })
end)

--[[runcode(function()
    local pickupRange = {}
    local visualizeSound = {}
    local pt
    local con

    local picking = {}
    local hookObj = function(obj : BasePart)
        if obj:IsA("BasePart") and not picking[obj] then
            picking[obj] = tick()
        end
    end

    pickupRange = GuiLibrary.Registry.utillityPanel.API.CreateOptionsButton({
        Name = "PickupRange",
        Function = function(callback)
            if callback then
                for _, v in workspace.ItemDrops:GetChildren() do
                    hookObj(v)
                end
                con = workspace.ItemDrops.ChildAdded:Connect(hookObj)
                RunLoops:BindToHeartbeat("PickupRange", function()
                    if PlayerUtility.lplrIsAlive then
                        local timer = tick()
                        for obj, lastPickup in picking do
                            if not obj or obj.Parent ~= workspace.ItemDrops then
                                picking[obj] = nil
                            elseif (timer - lastPickup) >= .1 and (lplr.Character.HumanoidRootPart.Position - obj.Position).Magnitude <= 10 then
                                picking[obj] = timer
                                bedwars.TSremotes.Client:Get("PickupItemDrop"):CallServerAsync({
                                    itemDrop = obj
                                })
                                if visualizeSound.Enabled and timer - (pt or 0) >= 0.5 then
                                    bedwars.SoundManager:playSound(bedwars.SoundList.PICKUP_ITEM_DROP)
                                    pt = timer
                                end
                            end

                            if isnetworkowner(obj) then
                                obj.CFrame = chrCFrame
                            end
                        end
                    end
                end)
            else
                if con then
                    con:Disconnect()
                    con = nil
                end
                RunLoops:UnbindFromHeartbeat("PickupRange")
                picking = {}
            end
        end
    })
    visualizeSound = pickupRange.CreateToggle({
        Name = "Visualize Sound"
    })
end)--]]


-- credit vape
runcode(function()
    local StaffDetector = {Enabled = false}
    local DetectClans = {Enabled = true}

    newData.staffData = {
        bad_clan = {'gs', 'g2', 'DV', 'IPS', 'DV2', 'gg'},
        connections = {},
        attrs = {
            Team = false,
            Spectator = true,
            PlayerConnected = true,
        },
        blacklistedusers = {},
        joined = {}
    }

    local connect = function(con, func)
        local id = HttpService:GenerateGUID(false)
        newData.staffData.connections[id] = con:Connect(func)
        return newData.staffData.connections[id]
    end

    local function getRole(plr, id)
        return plr:GetRankInGroup(id)
    end

    local function checkFriends(table)
        for _, v in pairs(table) do
            if table[v] then
                return newData.staffData.joined[v]
            end
        end
        return nil
    end

    newData.staffData.notify = function(player, type, time)
        createNotification("Staff Detected", '(' .. type .. '): ' .. player.Name, time, type)
    end

    newData.staffData.loadBlacklist = function(path)
        local content = path or readfile("Phantom/storage/cache/blacklistedusers.txt")
        for i, v in string.split(content, "\n") do
            local userid, clantag = unpack(string.split(v, ":"))
            if userid and clantag then
                newData.staffData.blacklistedusers[tonumber(userid)] = clantag ~= "" and clantag or nil
            end
        end
        -- print("worked")
    end
        
    newData.staffData.saveBlacklist = function(path)
        path = path or "Phantom/storage/cache/blacklistedusers.txt"
        local lines = {}
        for i, v in pairs(newData.staffData.blacklistedusers) do
            if v then
                table.insert(lines, i .. ":" .. v)
            else
                table.insert(lines, tostring(i))
            end
        end
        writefile(path, table.concat(lines, "\n"))
    end
    
    local function checkJoin(plr, connection)
        for i, v in pairs(newData.staffData.attrs) do
            if plr:GetAttribute(i) ~= v then return end
        end

        connection:Disconnect()

        local friendIds = {}
        local pages = Players:GetFriendsAsync(plr.UserId)
        repeat
            for _, friend in pairs(pages:GetCurrentPage()) do
                table.insert(friendIds, friend.Id)
            end
            pages:AdvanceToNextPageAsync()
        until pages.IsFinished

        local friendMatch = checkFriends(friendIds)

        if not friendMatch then
            local clantag = plr:GetAttribute('ClanTag')

            newData.staffData.notify(plr, 'Impossible Join', 60)
            newData.staffData.blacklistedusers[plr.UserId] = clantag ~= "None" and clantag  or ""
            newData.staffData.saveBlacklist()
        else
            newData.staffData.notify(plr, "Spectator Join", 20)
            createNotification("Spectator Join", string.format('Spectator %s joined from %s', plr.Name, friendMatch), 20, "Spectator")
        end
    end
    
    local function playerAdded(plr)
        newData.staffData.joined[plr.UserId] = plr.Name
        if plr == Players.LocalPlayer then return end
    
        if newData.staffData.blacklistedusers[plr.UserId] then
            newData.staffData.notify(plr, "blacklisted_user", 60)
            return
        end
    
        local clanTag = plr:GetAttribute('ClanTag')
        if DetectClans.Enabled and clanTag and table.find(newData.staffData.bad_clan, clanTag) then
            newData.staffData.notify(plr, "blacklisted_clan", 60)
            newData.staffData.blacklistedusers[plr.UserId] = clanTag
            newData.staffData.saveBlacklist()
            return
        end

        local rank = getRole(plr, 5774246)
        if rank >= 200 then
            newData.staffData.notify(plr, "staff_role", 60)
            newData.staffData.blacklistedusers[plr.UserId] = clanTag ~= "None" and clanTag or nil
            newData.staffData.saveBlacklist()
            return
        end
    
        connect(plr:GetAttributeChangedSignal('Spectator'), function()
            checkJoin(plr)
        end)
    
        connect(plr:GetAttributeChangedSignal('ClanTag'), function()
            local newClanTag = plr:GetAttribute('ClanTag')
            if DetectClans.Enabled and newClanTag and table.find(newData.staffData.bad_clan, newClanTag) then
                newData.staffData.blacklistedusers[plr.UserId] = newClanTag
                newData.staffData.notify(plr, "blacklisted_clan", 60)
                newData.staffData.saveBlacklist()
            end
        end)
    end
    
    StaffDetector = GuiLibrary.Registry.utillityPanel.API.CreateOptionsButton({
        Name = "StaffDetector",
        Function = function(callback)
            if callback then
                if newData.customMatch then return end
                newData.staffData.saveBlacklist()

                task.spawn(newData.staffData.loadBlacklist)

                for _, player in pairs(Players:GetPlayers()) do
                    task.spawn(playerAdded, player)
                end
    
                connect(Players.PlayerAdded, playerAdded)
            else
                for _, con in pairs(newData.staffData.connections) do
                    con:Disconnect()
                end
            end
        end
    })
    DetectClans = StaffDetector.CreateToggle({
        Name = "DetectClans",
        Default = false
    })
end)

runcode(function()
    local TrapDisabler = {}
    local remote = ReplicatedStorage.rbxts_include.node_modules["@rbxts"].net.out._NetManaged:FindFirstChild("StepOnSnapTrap")
    TrapDisabler = GuiLibrary.Registry.utillityPanel.API.CreateOptionsButton({
        Name = "TrapDisabler",
        Function = function(callback)
            if callback and remote then
                remote:Destroy()
            end
        end
    })
end)

--[[runcode(function()
    local AutoVoidDrop = {}
    local YLimt = {}

    AutoVoidDrop = GuiLibrary.Registry.utillityPanel.API.CreateOptionsButton({
        Name = "AutoVoidDrop",
        Function = function(callback)
            if callback then
                RunLoops:BindToHeartbeat("AutoVoidDrop", function()
                    if PlayerUtility.lplrIsAlive then
                        if lplr.Character.HumanoidRootPart.Position.Y < -YLimt.Value then
                            for _, v in pairs(bedwars.inventoryIndex) do
                                if v.Name then
                                    local ohTable1 = {
                                        ["item"] = ,
                                        ["amount"] = math.huge
                                    }
                                    ReplicatedStorage.rbxts_include.node_modules["@rbxts"].net.out._NetManaged.DropItem:InvokeServer(ohTable1)
                                end
                            end
                        end
                    end
                end)
            else
                RunLoops:UnbindFromHeartbeat("AutoVoidDrop")
            end
        end
    })

    YLimt = AutoVoidDrop.CreateSlider({
        Name = "Y Offset",
        Min = 0,
        Max = 95,
        Default = 0
    })
end)--]]

-- runcode(function()
--     local PickUpRange = {Enabled = false}
--     local priorityList = {"emerald", "speed", "bow", "diamond", "telepearl", "arrow"}
--     local pickedup = {}
--     local priorityMap = {}
    
--     for index, name in ipairs(priorityList) do
--         priorityMap[name] = index
--     end

--     PickUpRange = GuiLibrary.Registry.utillityPanel.API.CreateOptionsButton({
--         Name = "PickUpRange",
--         Function = function(callback)
--             if callback then
--                 RunLoops:BindToHeartbeat("PickUpRange", function()
--                     if PlayerUtility.lplrIsAlive then
--                         local hrp = lplr.Character.HumanoidRootPart
--                         if hrp then
--                             local itemDrops = workspace.ItemDrops:GetChildren()
--                             local itemsToPickup = {}
--                             local prioritizedItems = {}
--                             for _, v in pairs(itemDrops) do
--                                 if v:IsA("BasePart") and isnetworkowner(v) then
--                                     if not pickedup[v] or pickedup[v] <= tick() then
--                                         pickedup[v] = tick() + .2
--                                         local itemName = string.lower(v.Name)
--                                         local priority = priorityMap[itemName] or (#priorityList + 1)
--                                         table.insert(prioritizedItems, {item = v, priority = priority})
--                                     end
--                                 end
--                             end

--                             table.sort(prioritizedItems, function(a, b) return a.priority < b.priority end)

--                             for _, itemData in ipairs(prioritizedItems) do
--                                 table.insert(itemsToPickup, itemData.item)
--                             end

--                             if #itemsToPickup > 0 then
--                                 for _, v in pairs(itemsToPickup) do
--                                     v.CFrame = hrp.CFrame
--                                     bedwars.PickupRemote:InvokeServer({
--                                         itemDrop = v
--                                     })
--                                 end
--                             end
--                         end
--                     end
--                 end)
--             else
--                 RunLoops:UnbindFromHeartbeat("PickUpRange")
--             end
--         end
--     })
-- end)

runcode(function()
    local keyDown = false
    local FastDrop = {}; FastDrop = GuiLibrary.Registry.inventoryPanel.API.CreateOptionsButton({
        Name = "FastDrop",
        Function = function(callback)
            if callback then
                RunLoops:BindToHeartbeat("FastDrop", function()
                    if keyDown and PlayerUtility.lplrIsAlive then
                        task.spawn(bedwars.DropItem)
                    end
                    task.wait(.01)
                end)

                UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
                    if input.KeyCode == Enum.KeyCode.Q and not gameProcessedEvent and not keyDown then
                        keyDown = true
                    end
                end)

                UserInputService.InputEnded:Connect(function(input, gameProcessedEvent)
                    if input.KeyCode == Enum.KeyCode.Q and not gameProcessedEvent then
                        keyDown = false
                    end
                end)
            else
                RunLoops:UnbindFromHeartbeat("FastDrop")
                keyDown = false
            end
        end
    })
end)

--[[runcode(function()
    local AutoWin = {}

    local function getClosestBed()
        local closestBed = nil
        local closestDistance = math.huge
        local lplrPosition = lplr.Character.PrimaryPart.Position or Vector3.new(0, 0, 0)

        for _, part in pairs(CollectionService:GetTagged("bed")) do
            if part:IsA("BasePart") then
                local bedModel = part:FindFirstChild("Bed")
                if bedModel and part.Bed.BrickColor ~= lplr.TeamColor then
                    local distance = (lplrPosition - part.Position).Magnitude
                    if distance < closestDistance then
                        closestDistance = distance
                        closestBed = part
                    end
                end
            end
        end

        return closestBed
    end

    local function updateGameInfo(queueType)
        if string.find(queueType, "bedwars_duels") then
            newData.queueInfo = {closestBed = getClosestBed()}
        end
    end

    -- local speed = 23
    local games = {
        duels = {
            queueType = "bedwars_duels",
            Function = function()
                local bed = newData.queueInfo.closestBed
                if bed then
                    if not InfiniteFly.Enabled then
                        InfiniteFly.Toggle()
                    end
                    --autowinEnabled = true

                    local FlyRoot = lplr.Character.HumanoidRootPart
                    local tweenInfo = TweenInfo.new((FlyRoot.Position - bed.Position).Magnitude / SpeedSlider.Value, Enum.EasingStyle.Linear)
                    local tween = TweenService:Create(FlyRoot, tweenInfo, {CFrame = CFrame.new(bed.Position + Vector3.new(0, height * 4))})
                    
                    tween:Play()
                    
                    local timer = tick() + tweenInfo.Time
                    -- autowinEnabled = false
                    repeat
                        task.wait()
                    until tick() >= timer or not AutoWin.Enabled or not InfiniteFly.Enabled
                    if not AutoWin.Enabled then return end

                    if InfiniteFly.Enabled then
                        InfiniteFly.Toggle()
                    end
                end
            end
        }
    }
    
    AutoWin = GuiLibrary.Registry.miscPanel.API.CreateOptionsButton({
        Name = "AutoWin",
        Function = function(callback)
            if callback then
                if newData.matchState == 1 then return end
                repeat
                    task.wait()
                until newData.matchState == 1 and PlayerUtility.lplrIsAlive
                for i, v in pairs(games) do
                    if string.find(string.lower(newData.queueType), string.lower(v.queueType)) then
                        updateGameInfo(v.queueType)
                        v.Function()
                    end
                end
            end
        end
    })
end)--]]

runcode(function()
    local AutoInteract = {}
    local Cobalt = {}
    local ogFunc
    local promptOgFunc
    local interactReg = getmetatable(bedwars.InteractionRegistryController)
    local promptCont = getmetatable(knit.Controllers.ProximityPromptController)
    local prompt = Instance.new("ProximityPrompt")
    local emptyFunc = function() end
    local fakePrompt = {
        PromptButtonHoldEnded = {
            Connect = function(...)
                local args = {...}
                args[2]()
            end
        },
        Enabled = true,
        Destroy = emptyFunc
    }

    AutoInteract = GuiLibrary.Registry.worldPanel.API.CreateOptionsButton({
        Name = "AutoInteract",
        Function = function(callback)
            if callback then
                repeat
                    task.wait()
                until newData.matchState == 1 or not AutoInteract.Enabled
                if not AutoInteract.Enabled then return end

                ogFunc = interactReg.givePartProximityPrompt
                promptOgFunc = promptCont.createProximityPrompt
                interactReg.givePartProximityPrompt = function(...)
                    local args = {...}
                    args[3].onInteracted(lplr, args[2], prompt, emptyFunc)
                end
                promptCont.createProximityPrompt = function(...)
                    return fakePrompt
                end
            else
                promptCont.createProximityPrompt = promptOgFunc or promptCont.createProximityPrompt
                interactReg.givePartProximityPrompt = ogFunc or interactReg.givePartProximityPrompt
            end
        end
    })

    local cobaltCont = bedwars.BatteryEffectsController
    local ogFunc
    local cobaltRemote
    Cobalt = AutoInteract.CreateToggle({
        Name = "Cobalt",
        Function = function(callback)
            if not cobaltCont or not AutoInteract.Enabled then return end
            if callback then
                cobaltRemote = Client:Get("ConsumeBattery").instance

                ogFunc = cobaltCont.registerBattery
                cobaltCont.registerBattery = function(...)
                    local args = {...}
                    cobaltRemote:FireServer({
                        batteryId = args[3]
                    })
                end
            else
                cobaltCont.registerBattery = ogFunc or cobaltCont.registerBattery
            end
        end,
        Default = true
    })
end)

runcode(function()
    local AntiVoid = {}
    local addTp = {}
    local YOffset = {}
    local lowestBlock
    local lastGround
    local cooldown = 0

    AntiVoid = GuiLibrary.Registry.worldPanel.API.CreateOptionsButton({
        Name = "AntiVoid",
        Function = function(callback)
            if callback then
                repeat
                    task.wait()
                until PlayerUtility.lplrIsAlive and workspace:FindFirstChild("Map") and newData.matchState == 1

                if not lowestBlock then
                    local lowestY = 9e9
                    for _, v in workspace.Map:GetDescendants() do
                        if v:IsA("BasePart") and lowestY > v.Position.Y then
                            lowestY = v.Position.Y
                            lowestBlock = v
                        end
                    end
                end

               repeat
                    if not PlayerUtility.lplrIsAlive then return end

                    local ray = workspace:Raycast(lplr.Character.HumanoidRootPart.Position, Vector3.new(0, -1000), newData.blockRaycast)
                    lastGround = ray and ray.Position or lastGround

                    if not ray and lplr.Character.HumanoidRootPart.Position.Y < (lowestBlock.Position.Y - YOffset.Value) then
                        if addTp.Enabled and lastGround then
                            local isSafe = workspace:Raycast(Vector3.new(lplr.Character.HumanoidRootPart.Position.X, lastGround.Y, lplr.Character.HumanoidRootPart.Position.Z), Vector3.zero, newData.blockRaycast)
                            local args = {lplr.Character.HumanoidRootPart.CFrame:GetComponents()}
                            args[2] = (not isSafe and lastGround and lastGround.Y) + height or args[2]
    
                            lplr.Character.HumanoidRootPart.CFrame = CFrame.new(unpack(args))
                        elseif cooldown >= tick() then
                            return
                        end
                        
                        cooldown = tick() + .1
                        lplr.Character.HumanoidRootPart.Velocity = Vector3.new(lplr.Character.HumanoidRootPart.Velocity.X, -lplr.Character.HumanoidRootPart.Velocity.Y, lplr.Character.HumanoidRootPart.Velocity.Z)
                    end
                    task.wait(.01)
                until not AntiVoid.Enabled
            else
                RunLoops:UnbindFromHeartbeat("AntiVoid")
            end
        end
    })
    addTp = AntiVoid.CreateToggle({
        Name = "addTp",
        Default = true
    })
    YOffset = AntiVoid.CreateSlider({
        Name = "Y Offset",
        Min = 0,
        Max = 100,
        Default = 0
    })
end)

--[[runcode(function()
    local running = false
    local ClientCrasher = {}
    ClientCrasher = GuiLibrary.Registry.miscPanel.API.CreateOptionsButton({
        Name = "ClientCrasher",
        Function = function(callback)
            if callback then
                running = true
                repeat task.wait() until newData.matchState ~= 0 
                local humanoidRoot = lplr.Character and lplr.Character:FindFirstChild("HumanoidRootPart")
                if humanoidRoot then lplr:Move(humanoidRoot.CFrame:VectorToWorldSpace(Vector3.new(0.4, 0, 0)), false) end
                task.wait(0.3)
                local mt = getrawmetatable(game)
                setreadonly(mt, false)
                local originalNamecall = mt.__namecall
                mt.__namecall = newcclosure(function(self, ...)
                    local args = {...}
                    local method = getnamecallmethod()
                    local instanceName = tostring(self)
                    if method == "FireServer" and instanceName:find("BHHiderSnapToGrid") then
                        return
                    end
                    return originalNamecall(self, unpack(args))
                end)
                bedwars.blockDisguiseController.disguisedPlayerMap = function() return {} end
                local startTime = tick()
                while running do
                    local currentTime = tick()
                    local elapsedTime = currentTime - startTime
                    if elapsedTime >= 20 then
                        task.wait(4)
                        startTime = tick()
                    else
                        for i = 1, 20 do
                            if not running then break end
                            ReplicatedStorage.rbxts_include.node_modules["@rbxts"].net.out._NetManaged.BHHiderDisguiseBlock:FireServer({
                                ["data"] = {
                                    ["blockType"] = "new_years_lucky_block_2024"
                                }
                            })
                        end
                        task.wait(0.05)
                    end
                end
            else
                running = false
            end
        end
    })
end)--]]

--[[runcode(function()
    local MatchStartAbuse = {}; MatchStartAbuse = GuiLibrary.Registry.miscPanel.API.CreateOptionsButton({
        Name = "MatchStartAbuse",
        Function = function(callback)
            if callback then
                if newData.matchState == 1 or not lplr:GetAttribute("PlayerConnected") then return end

                repeat
                    task.wait()
                until newData.matchState == 0 and PlayerUtility.lplrIsAlive

                if not InfiniteFly.Enabled then
                    InfiniteFly.Toggle()
                end
                createNotification("MatchStartAbuse", "turned on infinite fly for matchstartabuse", 10)

                local tpPos
                if #CollectionService:GetTagged("bed") > 0 and newData.queueType ~= "battle_royale" then
                    for _, v in CollectionService:GetTagged("bed") do
                        if tpPos then break end
                        if v:FindFirstChild("Bed") and v.Bed.BrickColor ~= lplr.TeamColor then
                            tpPos = v.CFrame
                        end
                    end
                else
                    local bestChest, bestSwordDamage = nil, 0
                    for _, v in CollectionService:GetTagged("chest") do
                        local chestInv = v:FindFirstChild("ChestFolderValue")
                        if chestInv then
                            chestInv = chestInv.Value
                            for _, item in chestInv:GetChildren() do
                                local swordMeta = swords[item.Name]
                                if swordMeta then
                                    swordMeta = swordMeta.sword
                                    local swordDamage = swordMeta.damage or 0
                                    if swordDamage > bestSwordDamage then
                                        bestChest, bestSwordDamage = v, swordDamage
                                    end
                                end
                            end
                        end
                    end
                    if bestChest then
                        tpPos = bestChest.CFrame
                    end
                end
                if not tpPos then createNotification("MatchStartAbuse", "no tppos", 10) return end
                
                local speed = SpeedSlider.Value / 1.5

                repeat
                    task.wait()
                until FlyRoot or not MatchStartAbuse.Enabled or not InfiniteFly.Enabled
                if not MatchStartAbuse.Enabled or not InfiniteFly.Enabled then return end

                FlyRoot.CFrame = tpPos + Vector3.new(0, height)

                local positionReached
                repeat
                    -- local args = {lplr.Character.PrimaryPart.CFrame:GetComponents()}
                    
                    -- local xCalc = tpPos.X - args[1]
                    -- local zCalc = tpPos.Z - args[3]
                    -- args[1] = args[1] + math.clamp(xCalc, -speed, speed)
                    -- args[3] = args[3] + math.clamp(zCalc, -speed, speed)

                    -- positionReached = CFrame.new(unpack(args))
                    -- lplr.Character.PrimaryPart.CFrame = positionReached

                    -- lplr.Character.Humanoid:MoveTo(tpPos.Position)
                    -- positionReached = lplr.Character.PrimaryPart.CFrame

                    local xCalc = tpPos.X - lplr.Character.PrimaryPart.Position.X
                    local zCalc = tpPos.Z - lplr.Character.PrimaryPart.Position.Z
                    lplr.Character.PrimaryPart.Velocity = Vector3.new(math.clamp(xCalc, -speed, speed), lplr.Character.PrimaryPart.Velocity.Y, math.clamp(zCalc, -speed, speed))
                    positionReached = lplr.Character.PrimaryPart.CFrame
                    task.wait()
                until newData.matchState == 1 or not MatchStartAbuse.Enabled or not InfiniteFly.Enabled
                if not MatchStartAbuse.Enabled or not InfiniteFly.Enabled then return end
                
                -- repeat
                --     task.wait()
                -- until (oldPos.Position - chrCFrame.Position).Magnitude > 10

                -- repeat
                --     task.wait()
                -- until FlyRoot

                if InfiniteFly.Enabled then
                    InfiniteFly.Toggle()
                end

                local timer = tick() + 2
                repeat
                    lplr.Character.PrimaryPart.CFrame = positionReached
                    task.wait()
                until tick() >= timer

                -- lplr.Character.HumanoidRootPart.Velocity -= Vector3.new(0, 2000)
                -- lplr.Character.PrimaryPart.CFrame = tpPos + Vector3.new(0, 200000)
                -- repeat
                --     -- lplr.Character:PivotTo(tpPos + Vector3.new(0, 200000))
                --     task.wait()
                -- until tick() >= timer
                -- lplr.Character.PrimaryPart.CFrame = tpPos + Vector3.new(0, height)
                -- lplr.Character.HumanoidRootPart.Velocity = Vector3.zero
            end
        end
    })
end)--]]

--[[runcode(function()
    local teamList = {}
    local TeamSwitch = {}
    local Dropdown = {}
    local TeamDropdown = {Value = "Red"}

    for _, team in pairs(Teams:GetTeams()) do
        table.insert(teamList, team.Name)
    end

    TeamSwitch = GuiLibrary.Registry.miscPanel.API.CreateOptionsButton({
        Name = "TeamSwitch",
        Function = function(callback)
            if callback then
                bedwars.remotes.TeamRemote:FireServer(game.JobId, { TeamDropdown.Value })
                TeamSwitch.Toggle()
            end
        end
    })
    Dropdown = TeamSwitch.CreateDropdown({
        Name = "Select Team",
        List = teamList,
        Default = "Red",
        Function = function(selectedTeam)
            TeamDropdown.Value = selectedTeam
        end
    })
end)--]]

-- runcode(function()
--     local KrystalDisabler = {}
--     KrystalDisabler = GuiLibrary.Registry.blatantPanel.API.CreateOptionsButton({
--         Name = "KrystalDisabler",
--         Function = function(callback)
--             if callback then
--                 RunLoops:BindToHeartbeat("KrystalDisabler", function()
--                     bedwars.TSremotes.Client:Get("MomentumUpdate"):SendToServer({
--                         momentumValue = math.huge
--                     })
--                 end)
--             else
--                 RunLoops:UnbindFromHeartbeat("KrystalDisabler")
--             end
--         end
--     })
-- end)

-- runcode(function()
--     local Spider = {}
--     local Extend = {}

--     Spider = GuiLibrary.Registry.worldPanel.API.CreateOptionsButton({
--         Name = "Spider",
--         Function = function(callback)
--             if callback then
--                 RunLoops:BindToHeartbeat("Spider", function()
--                     if PlayerUtility.lplrIsAlive then
--                         local ray = workspace:Raycast(lplr.Character:GetPivot().Position, lplr.Character.Humanoid.MoveDirection * Extend.Value, newData.blockRaycast)
--                         if ray and ray.Instance then
--                             local pos = lplr.Character:GetPivot()
--                             local args = {pos:GetComponents()}

--                             local blockUpTp
--                             args[2] = 

--                             lplr.Character:PivotTo(CFrame.new(unpack(args)))
--                         end
--                     end
--                 end)
--             else
--                 RunLoops:UnbindFromHeartbeat("Spider")
--             end
--         end
--     })

--     Extend = Spider.CreateSlider({
--         Name = "Extend",
--         Min = 1,
--         Max = 10,
--         Default = 1
--     })
-- end)
