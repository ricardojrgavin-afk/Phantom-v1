--!nonstrict

local HttpService = game:GetService("HttpService")
local Players = cloneref(game:GetService("Players"))
local Workspace = cloneref(game:GetService("Workspace"))
local ReplicatedStorage = cloneref(game:GetService("ReplicatedStorage"))
local Lighting = cloneref(game:GetService("Lighting"))
local CollectionService = cloneref(game:GetService("CollectionService"))
local RunService = cloneref(game:GetService("RunService"))
local CoreGui = cloneref(game:GetService("CoreGui"))
local SoundService = cloneref(game:GetService("SoundService"))
local Camera = Workspace.CurrentCamera
local lplr = Players.LocalPlayer

local UI = phantom.UI
local GuiLibrary = UI
local funcs = phantom.ops
local Runtime = phantom.ops.runtime
local RunLoops = Runtime.RunLoops
local runcode = Runtime.run
local PlayerUtility = phantom.module:Load("utility") or error("Failed to load utility module")
local modLoaded 

local function safeNew(className)
    local ok, inst = pcall(function() return Instance.new(className) end)
    if not ok or not inst then
        return nil
    end
    return inst
end

for _, v in ipairs({ "Antideath","Gravity","ESP","AntiFall","TriggerBot","AimAssist","BreadCrumbs","AutoClicker","ServerHop","NoClip","FPSBooster","FovChanger","AnimationPlayer","AntiAFK","Speed","FastStop","Rejoin" }) do
    UI.kit:deregister(v .. "Module")
end

local Controllers = { fighter = nil, duel = nil, spectate = nil, queuePad = nil, matchmaking = nil }

local STATUS = {NOT_IN_MATCH = 0, STARTED = 1, IN_PROGRESS = 2, ENDED = 3}
local newData = {
    changed = nil,
    connections = {},
    data = {
        matchStatus = STATUS.NOT_IN_MATCH,
        gameMode = "Lobby",
        envId = nil,
        matchId = nil,
        team = nil,
        allies = {},
        map = "Lobby",
        queue = nil,
        inQueue = false,
        duel = nil,
        queuePad = nil,
        mapObject = nil,
        fighter = nil,
    }
}

local gamefunction = {}
do
    function gamefunction:update()
        local d = newData.data
        local duel

        if Controllers.spectate and Controllers.spectate.CurrentDuelSubject then
            duel = Controllers.spectate.CurrentDuelSubject
        elseif Controllers.duel and Controllers.duel.GetDuel then
            local ok, v = pcall(Controllers.duel.GetDuel, Controllers.duel, lplr)
            if ok then duel = v end
        end

        local fighter = Controllers.fighter and Controllers.fighter.LocalFighter or nil

        local queuePad
        if Controllers.queuePad and Controllers.queuePad.GetQueuePad then
            local ok, v = pcall(Controllers.queuePad.GetQueuePad, Controllers.queuePad, lplr)
            if ok then queuePad = v end
        end

        local queueName
        if queuePad then
            local ok, v = pcall(function()
                return queuePad.GetActualQueueName and queuePad:GetActualQueueName() or queuePad:Get("QueueName")
            end)
            if ok then queueName = v end
        end

        local mmStatus = Workspace:GetAttribute("MatchmadeStatus")
        local playerEnvId = lplr:GetAttribute("EnvironmentID")
        local wsEnvId = Workspace:GetAttribute("EnvironmentID")
        local wsMatchId = Workspace:GetAttribute("MatchID")
        local matchmadeGameOver = Workspace:GetAttribute("MatchmadeGameOver")

        local State = {
            duel = duel,
            queuePad = queuePad,
            fighter = fighter,
            mapObject = duel and duel.Map or nil,
        }

        if not fighter or not fighter.Get or not fighter:Get("IsInDuel") then
            State.matchStatus = STATUS.NOT_IN_MATCH
        else
            local s = duel and duel.Get and duel:Get("Status")
            if matchmadeGameOver or s == "RoundFinished" then
                State.matchStatus = STATUS.ENDED
            elseif s == "Countdown" or s == "RoundStarting" or s == "WaitingForPlayers" then
                State.matchStatus = STATUS.STARTED
            else
                State.matchStatus = STATUS.IN_PROGRESS
            end
        end

        State.gameMode = (duel and duel.Get and (duel:Get("QueueName") or duel.Name)) or (type(mmStatus) == "string" and mmStatus ~= "" and mmStatus) or "Lobby"

        if playerEnvId ~= nil then
            State.envId = playerEnvId
        elseif duel and duel.Get then
            local ok, v = pcall(duel.Get, duel, "EnvironmentID")
            State.envId = (ok and v) or wsEnvId
        else
            State.envId = wsEnvId
        end

        if duel and duel.Get then
            local ok, v = pcall(duel.Get, duel, "ObjectID")
            State.matchId = (ok and v) or wsMatchId or playerEnvId
        else
            State.matchId = wsMatchId or playerEnvId
        end

        State.allies = {}
        State.team = nil

        if duel and duel.GetDueler then
            local localDueler = duel:GetDueler(lplr)
            State.team = localDueler and localDueler.Get and localDueler:Get("TeamID") or nil

            for _, dueler in ipairs(duel.Duelers or {}) do
                local player = rawget(dueler, "Player")
                if player and player ~= lplr then
                    State.allies[player.UserId] = State.team ~= nil and dueler.Get and dueler:Get("TeamID") == State.team or false
                end
            end
        end

        State.map = State.mapObject and State.mapObject.Name or "Lobby"
        State.queue = queueName
        State.inQueue = queueName ~= nil or (type(mmStatus) == "string" and mmStatus ~= "" and mmStatus ~= "Idle" and mmStatus ~= "None")

        local changed = d.matchStatus ~= State.matchStatus or d.gameMode ~= State.gameMode or d.envId ~= State.envId or d.matchId ~= State.matchId or d.team ~= State.team or d.map ~= State.map or d.queue ~= State.queue or d.inQueue ~= State.inQueue or d.duel ~= State.duel or d.queuePad ~= State.queuePad or d.mapObject ~= State.mapObject or d.fighter ~= State.fighter

        if not changed then
            for k, v in pairs(State.allies) do
                if d.allies[k] ~= v then changed = true break end
            end
            if not changed then
                for k in pairs(d.allies) do
                    if State.allies[k] == nil then changed = true break end
                end
            end
        end

        newData.data = State

        if changed and newData.changed and newData.changed.Fire then
            newData.changed:Fire()
        end
    end
    function gamefunction:hookgame()
        local function bind(signal)
            if signal and signal.Connect then
                table.insert(newData.connections, signal:Connect(self.update))
            end
        end

        bind(Workspace.ChildAdded)
        bind(Workspace.ChildRemoved)
        bind(Workspace.DescendantAdded)

        for _, attr in ipairs({ "MatchmadeStatus", "MatchmadeGameOver", "EnvironmentID", "MatchID" }) do
            bind(Workspace:GetAttributeChangedSignal(attr))
        end

        bind(lplr:GetAttributeChangedSignal("EnvironmentID"))
        bind(lplr:GetAttributeChangedSignal("Level"))

        if Controllers.spectate then
            bind(Controllers.spectate.DuelSubjectChanged)
            bind(Controllers.spectate.DuelSubjectEnvironmentIDChanged)
            bind(Controllers.spectate.DuelSubjectStatusChanged)
        end

        if Controllers.duel then
            bind(Controllers.duel.LocalPlayerJoinedOrLeftDuel)
            bind(Controllers.duel.ObjectAdded)
            bind(Controllers.duel.ObjectRemoved)
        end

        task.spawn(function()
            local fc = Controllers.fighter
            if fc and fc.WaitForLocalFighter then
                local ok, fighter = pcall(fc.WaitForLocalFighter, fc)
                if ok and fighter then
                    bind(fighter:GetDataChangedSignal("IsInDuel"))
                    bind(fighter:GetDataChangedSignal("IsInShootingRange"))
                    bind(fighter:GetDataChangedSignal("EquippedItem"))
                end
            end
        end)

        self:update()
    end
end

--// Credit: Original concept by the community

for _, con in getconnections(game:GetService("LogService").MessageOut) do
    if con.Function and islclosure(con.Function) then
        con:Disconnect()
    end
end

local names = {"LocalScript3", "MiscellaneousController", "AnalyticsPipeline"}
local function is_ac_calling()
    for i = 2, 15 do
        local _, src = pcall(debug.info, i, "s")
        for _, n in names do if src and src:find(n) then return true end end
    end
end
local old_debug_info; old_debug_info = hookfunction(debug.info, newcclosure(function(f, l, ...)
    local res = { old_debug_info(f, l, ...) }
    if type(l) == "string" and l:find("s") and res[1] then
        if res[1]:find("Ghost") or not res[1]:find(".lua") then
            return "CommonLib.lua"
        end
    end
    return unpack(res)
end))

local old_debug_traceback; old_debug_traceback = hookfunction(debug.traceback, newcclosure(function(...)
    local trace = old_debug_traceback(...)
    if is_ac_calling() then
        return trace:gsub("Ghost.-\n", "")
    end
    return trace
end))

local old_kick = lplr.Kick
local old_setmetatable; old_setmetatable = hookfunction(getrenv().setmetatable, newcclosure(function(t, mt)
    if mt and type(mt) == "table" and rawget(mt, "__mode") then
        local mode = rawget(mt, "__mode")
        
        if mode == "kv" or mode == "v" or mode == "k" then
            local stack = debug.traceback()
            
            if stack:find("MiscellaneousController") or stack:find("LocalScript3") or stack:find("CameraSecurity") or stack:find("AnalyticsPipelineController") then
                return old_setmetatable({1, 2, 3}, {})
            end
        end
    end
    
    return old_setmetatable(t, mt)
end))

local oldgc = getgc; getgc = function(...)
    local gc = oldgc(...)
    local filtered = {}
    for _, v in ipairs(gc) do
        if typeof(v) == "function" then
            local src = debug.info(v, "s")
            if not (src and (src:find("LocalScript3") or src:find("MiscellaneousController"))) then
                table.insert(filtered, v)
            end
        else
            table.insert(filtered, v)
        end
    end
    return filtered
end

hookfunction(old_kick, newcclosure(function(self, ...)
    if self == lplr then
        return nil
    end
    
    return old_kick(self, ...)
end))

repeat
    modLoaded = game:IsLoaded() and table.find(table.create(#getloadedmodules(), nil), true)

    for _, v in getloadedmodules() do
        if v.Name == "EntityController" then
            modLoaded = true
            break
        end
    end
    if not modLoaded then task.wait() end
until modLoaded

do
    local ps = lplr.PlayerScripts
    local ControllersFolder = ps.Controllers
    local Modules = ps.Modules
    local ReplicatedModules = ReplicatedStorage:WaitForChild("Modules")

    --// Main Controllers
    Controllers.fighter = require(ControllersFolder:WaitForChild("FighterController"))
    Controllers.duel = require(ControllersFolder:WaitForChild("DuelController"))
    Controllers.spectate = require(ControllersFolder:WaitForChild("SpectateController"))
    Controllers.queuePad = require(ControllersFolder:WaitForChild("QueuePadController"))
    Controllers.matchmaking = require(ControllersFolder:WaitForChild("MatchmakingController"))

    --// Modules
    Controllers.pData = require(ControllersFolder:WaitForChild("PlayerDataController"))
    Controllers.rep = require(ReplicatedModules:WaitForChild("ReplicatedClass"))
    Controllers.cam = require(ControllersFolder:WaitForChild("CameraController"))
    Controllers.kat = require(Modules.ViewModels:WaitForChild("Katana"))
    Controllers.fbMod = require(Modules.Items:WaitForChild("Flashbang"))
    Controllers.util = require(ReplicatedModules:WaitForChild("Utility"))
    Controllers.okat = require(Modules.Items:WaitForChild("Katana"))
    Controllers.mc = require(ControllersFolder:WaitForChild("MechanicsController"))
    Controllers.cli = require(Modules.ClientReplicatedClasses.ClientFighter.ClientItem)
    Controllers.cvm = require(Modules.ClientReplicatedClasses.ClientFighter.ClientItem:WaitForChild("ClientViewModel"))
    Controllers.GunItem = require(Modules.ItemTypes:WaitForChild("Gun"))
    Controllers.GameplayUtility = require(ReplicatedModules:WaitForChild("GameplayUtility"))
    Controllers.ItemLibrary = require(ReplicatedModules:WaitForChild("ItemLibrary"))
    Controllers.cosLib = require(ReplicatedModules:WaitForChild("CosmeticLibrary"))
end

--// Other

local hookmuzzle = function()
    local char = PlayerUtility.GetCharacter()
    if not char then return Camera.CFrame.Position end
    local weapon = char:FindFirstChild("Weapon") or char:FindFirstChild("Tool")
    if weapon then
        local muzzle = weapon:FindFirstChild("Muzzle") or weapon:FindFirstChild("Handle")
        if muzzle then
            return muzzle.Position
        end
    end
    local rightHand = char:FindFirstChild("RightHand")
    if rightHand then return rightHand.Position end
    return Camera.CFrame.Position
end

local function getweapon()
    local path = workspace:FindFirstChild("ViewModels"):FindFirstChild("FirstPerson")
    for _, v in ipairs(path:GetChildren()) do
        if v:IsA("Model") and string.find(v.Name, lplr.Name) then
            return v
        end
    end
    return nil
end

--// Custom entity handler
do
    local function getRandomPart(model)
        local parts = {}
        for _, part in ipairs(model:GetDescendants()) do
            if part:IsA("BasePart") then
                table.insert(parts, part)
            end
        end
        return #parts > 0 and parts[math.random(1, #parts)] or nil
    end

    local function isVisible(localChar, targetPart)
        local params = RaycastParams.new()
        params.FilterDescendantsInstances = {localChar}
        params.FilterType = Enum.RaycastFilterType.Exclude

        local direction = targetPart.Position - Camera.CFrame.Position
        local ray = workspace:Raycast(Camera.CFrame.Position, direction, params)

        return ray == nil or ray.Instance:IsDescendantOf(targetPart.Parent)
    end

    PlayerUtility.NewGetNearestEntity = function(args)
        local char = PlayerUtility.GetCharacter()
        local root = PlayerUtility.lplrRoot
        if not root then return nil end

        local center = Camera.ViewportSize / 2
        local selectionMode = args.selectionMode or args.mode or "Mouse"
        local priorityMode = args.priorityMode or args.priority or "Closest"
        local maxDist = args.maxDist or math.huge
        local fov = args.fov or math.huge
        local targetPart = args.targetPart or "HumanoidRootPart"

        local results = {}

        for _, entity in ipairs(CollectionService:GetTagged("Entity")) do
            if entity == char or not entity:IsA("Model") then continue end

            local hum = entity:FindFirstChildOfClass("Humanoid")
            local hrp = entity:FindFirstChild("HumanoidRootPart")
            if not (hum and hrp and hum.Health > 0) then continue end

            if args.teamCheck ~= false and hrp:FindFirstChild("TeammateLabel") then continue end

            local target = targetPart == "Random" and getRandomPart(entity) or entity:FindFirstChild(targetPart)
            if not target then continue end

            if args.wallCheck ~= false and not isVisible(char, target) then continue end

            local screenPos, onScreen = Camera:WorldToViewportPoint(target.Position)
            if not onScreen then continue end

            local distance = (root.Position - hrp.Position).Magnitude
            local mouseDist = (Vector2.new(screenPos.X, screenPos.Y) - center).Magnitude

            if selectionMode == "Distance" then
                if distance > maxDist then continue end
            elseif mouseDist > fov then
                continue
            end

            table.insert(results, {
                entity = entity,
                part = target,
                distance = distance,
                mouseDist = mouseDist,
                health = hum.Health
            })
        end

        if #results == 0 then return nil end

        table.sort(results, function(a, b)
            if priorityMode == "Lowest Health" then
                return a.health < b.health
            elseif selectionMode == "Distance" then
                return a.distance < b.distance
            end
            return a.mouseDist < b.mouseDist
        end)

        return results[1].part, results[1].entity
    end
    PlayerUtility.predictPosition = function(target, projectileSpeed, shooterVelocity)
        shooterVelocity = shooterVelocity or Vector3.new()

        local startPos = hookmuzzle()
        local targetPos = target.Position
        local targetVel = target.AssemblyLinearVelocity

        local D = targetPos - startPos
        local V_rel = targetVel - shooterVelocity

        local distance = D.Magnitude
        if distance < 0.5 or V_rel.Magnitude < 0.1 then
            return targetPos
        end

        if projectileSpeed <= 0 then
            return targetPos
        end

        local a = V_rel:Dot(V_rel) - projectileSpeed * projectileSpeed
        local b = 2 * D:Dot(V_rel)
        local c = D:Dot(D)

        local t = nil
        local epsilon = 1e-6

        if math.abs(a) < epsilon then
            if math.abs(b) > epsilon then
                local t_lin = -c / b
                if t_lin > epsilon then
                    t = t_lin
                end
            end
        else
            local disc = b * b - 4 * a * c
            if disc >= 0 then
                local sqrt_disc = math.sqrt(disc)
                local t1 = (-b - sqrt_disc) / (2 * a)
                local t2 = (-b + sqrt_disc) / (2 * a)
                if t1 > epsilon and t2 > epsilon then
                    t = math.min(t1, t2)
                elseif t1 > epsilon then
                    t = t1
                elseif t2 > epsilon then
                    t = t2
                end
            end
        end

        if not t then
            return targetPos
        end

        local maxTime = 5.0
        if t > maxTime then
            local cappedLead = (targetVel * maxTime).Magnitude
            local dirToTarget = D.Unit
            if targetVel:Dot(dirToTarget) > 0 then
                return targetPos + targetVel * maxTime
            else
                return targetPos
            end
        end

        local predictedPos = targetPos + targetVel * t

        local dirToTarget = D.Unit
        local dirToPredicted = (predictedPos - startPos).Unit
        if dirToTarget:Dot(dirToPredicted) < -0.5 then
            return targetPos
        end

        return predictedPos
    end
end

runcode(function()
    if not newData.changed then
        local ok, ev = pcall(function() return Instance.new("BindableEvent") end)
        if ok and ev then
            newData.changed = ev
        end
    end

    gamefunction:hookgame()
    funcs:onExit("delbindable", function()
        if newData.changed and newData.changed.Destroy then
            newData.changed:Destroy()
            newData.changed = nil
        end
    end)
end)

runcode(function()
    local WEAPON_CONFIG = {}
    local oldRaycast, oldStartShooting, oldGetSpread
    local target

    local TargetPart = {Value = "Head"}
    local Mode = {Value = "Mouse"}
    local Priority = {Value = "Closest"}
    local TargetingFOV = {Value = 100}
    local MaxDistance = {Value = 1000}
    local Prediction = {Enabled = true}
    local HitChance = {Value = 100}
    local WallCheck = {Enabled = true}
    local TeamCheck = {Enabled = true}
    local ClosestPart = {Enabled = false}
    do
        local ok, ItemLib = pcall(require, Controllers.ItemLibrary)
        if ok and ItemLib then
            for name, item in pairs(ItemLib.Items or {}) do
                WEAPON_CONFIG[name] = {
                    speed = item.ProjectileSpeed or 300,
                    grav = item.ProjectileGravity or 0
                }
            end
        end
    end

    local function getWeaponData()
        local ok, fc = pcall(require, lplr.PlayerScripts.Controllers.FighterController)
        if ok and fc and fc.LocalFighter and fc.LocalFighter.EquippedItem then
            return WEAPON_CONFIG[fc.LocalFighter.EquippedItem.Name] or {speed = 300, grav = 0}
        end
        return {speed = 300, grav = 0}
    end

    local SilentAim; SilentAim = GuiLibrary.Registry.combatPanel.API.CreateOptionsButton({
        Name = "SilentAim",
        Function = function(callback)
            if callback then
                RunLoops:BindToHeartbeat("SilentAim", function()
                    target = PlayerUtility.NewGetNearestEntity({
                        targetPart = TargetPart.Value,
                        wallCheck = (WallCheck.Enabled) or (false and WallCheck.Enabled),
                        mode = Mode.Value,
                        fov = TargetingFOV.Value,
                        maxDistance = MaxDistance.Value,
                        priority = Priority.Value,
                        teamCheck = TeamCheck.Enabled,
                        closestPart = ClosestPart.Enabled,
                    })
                end)
                oldRaycast = Controllers.util.Raycast
                Controllers.util.Raycast = function(...)
                    local args = {...}
                    if target and math.random(100) <= HitChance.Value then
                        local pos = target.Position
                        if Prediction.Enabled then
                            pos = PlayerUtility.predictPosition(target, getWeaponData().speed)
                        end
                        args[3] = pos
                    end
                    return oldRaycast(unpack(args))
                end
            else
                RunLoops:UnbindFromHeartbeat("SilentAim")
                Controllers.util.Raycast = oldRaycast or Controllers.util.Raycast
                target = nil
            end
        end
    })
    TargetPart = SilentAim.CreateDropdown({
        Name = "Target Part",
        List = {"Head","HumanoidRootPart","UpperTorso","LowerTorso","Random"},
        Default = "Head"
    })
    Mode = SilentAim.CreateDropdown({
        Name = "Targeting Logic",
        List = {"Mouse","Distance"},
        Default = "Mouse"
    })
    Priority = SilentAim.CreateDropdown({
        Name = "Priority",
        List = {"Closest","Lowest Health"},
        Default = "Closest"
    })
    TargetingFOV = SilentAim.CreateSlider({
        Name = "Targeting FOV",
        Min = 10,
        Max = 1200,
        Default = 100,
        Round = 1
    })
    MaxDistance = SilentAim.CreateSlider({
        Name = "Max Distance",
        Min = 50,
        Max = 5000,
        Default = 1000,
        Round = 1
    })
    Prediction = SilentAim.CreateToggle({
        Name = "Prediction",
        Default = true
    })
    HitChance = SilentAim.CreateSlider({
        Name = "Hit Chance (%)",
        Min = 1,
        Max = 100,
        Default = 100,
        Round = 1
    })
    WallCheck = SilentAim.CreateToggle({
        Name = "Wall Check",
        Default = true
    })
    TeamCheck = SilentAim.CreateToggle({
        Name = "Team Check",
        Default = true
    })
    ClosestPart = SilentAim.CreateToggle({
        Name = "Closest Part",
        Default = false
    })

    Mode:ShowWhen("Distance", MaxDistance)
    Mode:ShowWhen("Mouse", TargetingFOV)
end)

--// Blatant
runcode(function()
    local Speed = {}
    local SpeedSlider = {}
    local oldFunc

    Speed = GuiLibrary.Registry.blatantPanel.API.CreateOptionsButton({
        Name = "Speed",
        Function = function(callback)
            if callback then
                oldFunc = Controllers.mc._GetWalkSpeed
                Controllers.mc._GetWalkSpeed = function(...)
                    return SpeedSlider.Value
                end
            else
                Controllers.mc._GetWalkSpeed = oldFunc or Controllers.mc._GetWalkSpeed
            end
        end
    })

    SpeedSlider = Speed.CreateSlider({
        Name = "WalkSpeed",
        Min = 1,
        Max = 100,
        Default = 60,
        Round = 1
    })
end)

--// Utility
runcode(function()
    local AntiFreeze = {}
    local mod, og
    AntiFreeze = GuiLibrary.Registry.utillityPanel.API.CreateOptionsButton({
        Name = "AntiFreeze",
        Function = function(callback)
            if callback then
                mod = Controllers.rep
                og = mod.Get
                mod.Get = function(...)
                    local _, id = ...
                    if id == "IsFrozen" then return false end
                    return og(...)
                end
            else
                if mod and og then mod.Get = og end
            end
        end
    })
end)

--// Utility
runcode(function()
    local FastProjectiles = {}
    local Items
    local originalReloads = {}

    FastProjectiles = GuiLibrary.Registry.utillityPanel.API.CreateOptionsButton({
        Name = "FastProjectiles",
        Function = function(callback)
            if callback then
                Items = Controllers.ItemLibrary.Items

                for _, item in pairs(Items) do
                    if type(item) ~= "table" then
                        continue
                    end

                    local reload = item.ReloadLength
                    if reload ~= nil then
                        if originalReloads[item] == nil then
                            originalReloads[item] = reload
                        end

                        item.ReloadLength = item.Name == "Daggers" and 0.09 or 0
                    end
                end
            else
                for item, reload in pairs(originalReloads) do
                    if item then
                        item.ReloadLength = reload
                    end
                end
                table.clear(originalReloads)
            end
        end
    })
end)

runcode(function()
    local FullAccuracy = {}
    local oldAccuracy
    FullAccuracy = GuiLibrary.Registry.utillityPanel.API.CreateOptionsButton({
        Name = "FullAccuracy",
        Function = function(callback)
            if callback then
                oldAccuracy = Controllers.GunItem.IsFullyAiming
                Controllers.GunItem.IsFullyAiming = function() return true end
            else
                Controllers.GunItem.IsFullyAiming = oldAccuracy or Controllers.GunItem.IsFullyAiming
            end
        end
    })
end)

runcode(function()
    local NoFlashbang = {}
    local flash, ogFlash
    NoFlashbang = GuiLibrary.Registry.utillityPanel.API.CreateOptionsButton({
        Name = "NoFlashbang",
        Function = function(callback)
            if callback then
                flash = Controllers.fbMod
                ogFlash = flash.ReplicateFromServer
                flash.ReplicateFromServer = function(...)
                    local args = { ... }
                    if args[2] == "BlindEffect" then return end
                    return ogFlash(...)
                end
            else
                if flash and ogFlash then flash.ReplicateFromServer = ogFlash end
            end
        end
    })
end)

runcode(function()
    local PingSpoofer = {}
    local pingMeta, oldPing
    PingSpoofer = GuiLibrary.Registry.utillityPanel.API.CreateOptionsButton({
        Name = "PingSpoofer",
        Function = function(callback)
            if callback then
                pingMeta = getmetatable(Controllers.util)
                oldPing  = pingMeta.GetLocalConnectionPing
                pingMeta.GetLocalConnectionPing = function() return 1000 end
            else
                if pingMeta and oldPing then pingMeta.GetLocalConnectionPing = oldPing end
            end
        end
    })
end)

--// Render
runcode(function()
    local ViewModel, Rainbow, Smooth, Arms, Speed, Transparency, WeaponColor = {}, {}, {}, {}, {}, {}, {}
    local saved, hue, index, last = {}, 0, 1, 0

    local colors = {Color3.fromRGB(180,180,180), Color3.fromRGB(80,50,230),Color3.fromRGB(255,50,200),Color3.fromRGB(255,130,0), Color3.fromRGB(255,220,0)}

    ViewModel = GuiLibrary.Registry.renderPanel.API.CreateOptionsButton({
        Name = "ViewModel",
        Function = function(callback)
            if callback then
                RunLoops:BindToHeartbeat("ViewModel", function()
                    local weapon = getweapon and getweapon()
                    local visual = weapon and weapon:FindFirstChild("ItemVisual")
                    if not visual then return end

                    local color = WeaponColor.Color
                    if Rainbow.Enabled then
                        if Smooth.Enabled then
                            hue = (hue + 0.005) % 1
                            color = Color3.fromHSV(hue, 1, 1)
                        else
                            if tick() - last > (1 / math.max(Speed.Value, 0.1)) then
                                last = tick()
                                index = index % #colors + 1
                            end
                            color = colors[index]
                        end
                    end

                    for _,v in ipairs(visual:GetDescendants()) do
                        if v:IsA("BasePart") then
                            if not saved[v] then
                                saved[v] = {v.Color, v.Transparency}
                            end

                            v.Color = color
                            v.Transparency = Transparency.Value / 100
                        end
                    end

                    if Arms.Enabled then
                        for _,name in ipairs({"LeftArm","RightArm"}) do
                            local arm = weapon:FindFirstChild(name)
                            if arm then
                                if not saved[arm] then
                                    saved[arm] = {arm.Color, arm.Transparency}
                                end

                                arm.Color = color
                                arm.Transparency = Transparency.Value / 100
                            end
                        end
                    end
                end)
            else
                RunLoops:UnbindFromHeartbeat("ViewModel")
                for i, v in pairs(saved) do
                    if i then
                        i.Color = v[1]
                        i.Transparency = v[2]
                    end
                end
                saved = {}
            end
        end
    })

    Rainbow = ViewModel.CreateToggle({Name = "Rainbow"})
    Smooth = ViewModel.CreateToggle({Name = "Smooth", Default = true})
    Arms = ViewModel.CreateToggle({Name = "Arms"})
    Speed = ViewModel.CreateSlider({Name = "Snap Speed", Min = 1, Max = 20, Default = 4})
    Transparency = ViewModel.CreateSlider({Name = "Transparency", Min = 0, Max = 100, Default = 0})

    Rainbow:AddDependent(Smooth)
    Rainbow:AddDependent(Speed)

    WeaponColor = GuiLibrary.CreateColorOption(ViewModel, {
        Name = "WeaponColor",
        Default = {R = 151, G = 153, B = 163}
    })
end)

runcode(function()
    local hook
    local spoofTbl = {}

    local trans = (isfile("Phantom/storage/cache/loadout.json") and HttpService:JSONDecode(readfile("Phantom/storage/cache/loadout.json"))) or {};

    local SkinChanger = GuiLibrary.Registry.utillityPanel.API.CreateOptionsButton({
        Name = "SkinChanger",
        Function = function(callback)
            if callback then
                for i, v in Controllers.cosLib.Cosmetics do
                    spoofTbl[i] = { IsUniversal = true }
                end

                local wepTbl = Controllers.pData.CurrentData:Get("WeaponInventory")
                for i, v in wepTbl do
                    wepTbl[i] = trans[v.Name] or v
                end

                coroutine.wrap(Controllers.pData.CurrentData.ReplicateFromServer)(Controllers.pData.CurrentData, "DataValueChanged", "WeaponInventory", wepTbl)
                coroutine.wrap(Controllers.pData.CurrentData.ReplicateFromServer)(Controllers.pData.CurrentData, "DataValueChanged", "CosmeticInventory", spoofTbl)

                local remote = ReplicatedStorage.Remotes.Data.EquipCosmetic
                local method = string.lower("fireserver")
                hook = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
                    if self and self == remote and string.lower(getnamecallmethod()) == method then
                        local args = {...}
                        wepTbl = Controllers.pData.CurrentData:Get("WeaponInventory")
                        for _, v in wepTbl do
                            if v.Name == args[1] then
                                if args[3] then
                                    v[args[2]] = { Name = args[3], Inverted = (args[2] == "Wrap" and (args[4].IsInverted or false)) or nil }
                                else
                                    v[args[2]] = nil
                                end
                                trans[args[1]] = v
                            end
                        end
                        Controllers.pData.CurrentData:ReplicateFromServer("DataValueChanged", "WeaponInventory", wepTbl)
                        writefile("Phantom/storage/cache/loadout.json", HttpService:JSONEncode(trans))
                        return nil
                    end
                    return hook(self, ...)
                end))

                do
                    local cli = Controllers.cli
                    local cvm = Controllers.cvm

                    do
                        local og = cli._CreateViewModel
                        cli._CreateViewModel = function(...)
                            local idx, data = ...
                            local dt, nm = idx:ToEnum("Data"), idx:ToEnum("Name")
                            local res = data[dt][nm]
                            data[dt][nm] = (idx.ClientFighter and idx.ClientFighter.IsLocalPlayer and ((trans[res] and trans[res].Skin and trans[res].Skin.Name))) or res
                            return og(idx, data)
                        end
                    end

                    do
                        local og = cvm.GetWrap
                        cvm.GetWrap = function(self)
                            return (self.ClientItem and self.ClientItem.Name and self.ClientItem.ClientFighter and self.ClientItem.ClientFighter.IsLocalPlayer and trans[self.ClientItem.Name] and trans[self.ClientItem.Name].Wrap) or og(self)
                        end
                    end
                    do
                        local og = cli.GetWrap
                        cli.GetWrap = function(self)
                            return (self.Name and self.ClientFighter and self.ClientFighter.IsLocalPlayer and trans[self.Name] and trans[self.Name].Wrap) or og(self)
                        end
                    end

                    do
                        local og = cli.GetViewModelDetails
                        cli.GetViewModelDetails = function(self)
                            return (self.Name and self.ClientFighter and self.ClientFighter.IsLocalPlayer and self.ViewModel and trans[self.Name] and {
                                ViewModelName = self.ViewModel.Name,
                                Wrap  = trans[self.Name].Wrap,
                                Charm = trans[self.Name].Charm,
                            }) or og(self)
                        end
                    end

                    do
                        local og = cvm._Setup
                        cvm._Setup = function(self)
                            if self.ClientItem and self.ClientItem.Name and trans[self.ClientItem.Name] then
                                local og = self.Get
                                self.Get = function(cSelf, id)
                                    return (id == "Charm" and self.ClientItem and self.ClientItem.ClientFighter and self.ClientItem.ClientFighter.IsLocalPlayer and trans[self.ClientItem.Name] and trans[self.ClientItem.Name].Charm) or og(cSelf, id)
                                end
                            end
                            return og(self)
                        end
                    end

                    do
                        local fc  = require(Players.LocalPlayer.PlayerScripts.Controllers.FighterController)
                        local mod = require(Players.LocalPlayer.PlayerScripts.Modules.ClientReplicatedClasses.ClientEntity)
                        local og  = mod._PlayFinisher
                        mod._PlayFinisher = function(...)
                            local args = {...}
                            if args[4] and fc.LocalFighter and fc.LocalFighter.EquippedItem and args[4] == Players.LocalPlayer then
                                args[2] = (trans[fc.LocalFighter.EquippedItem.Name] and trans[fc.LocalFighter.EquippedItem.Name].Finisher and trans[fc.LocalFighter.EquippedItem.Name].Finisher.Name) or args[2]
                                return og(unpack(args))
                            end
                            return og(...)
                        end
                    end
                end
            end
        end
    })
end)

runcode(function()
    local ESP = {}
    local highlights = {}

    local fill
    local teams

    local function removeHL(entity)
        if highlights[entity] then
            highlights[entity]:Destroy()
            highlights[entity] = nil
        end
    end

    ESP = GuiLibrary.Registry.renderPanel.API.CreateOptionsButton({
        Name = "ESP",
        Function = function(callback)
            if callback then
                local shootingRange = workspace:FindFirstChild("ShootingRangeEntities")
                RunLoops:BindToHeartbeat("ESP", function()
                    local char = PlayerUtility.GetCharacter  ()
                    local seen = {}

                    for _, entity in ipairs(CollectionService:GetTagged("Entity")) do
                        if entity == char or not entity:IsA("Model") then continue end
                        if shootingRange and entity:IsDescendantOf(shootingRange) then continue end

                        local root = entity:FindFirstChild("HumanoidRootPart")
                        local hum = entity:FindFirstChildOfClass("Humanoid")

                        if not root or not hum or hum.Health <= 0 then
                            removeHL(entity)
                            continue
                        end

                        if teams.Enabled and root:FindFirstChild("TeammateLabel") then
                            removeHL(entity)
                            continue
                        end

                        seen[entity] = true

                        if not highlights[entity] then
                            local hl = safeNew("Highlight")
                            if hl then
                                hl.FillColor = Color3.fromRGB(255,50,50)
                                hl.OutlineColor = Color3.fromRGB(255,255,255)
                                hl.OutlineTransparency = 0
                                hl.Adornee = entity
                                hl.Parent = CoreGui
                                highlights[entity] = hl
                            end
                        end

                        highlights[entity].FillTransparency = fill.Value / 100
                    end

                    for entity in pairs(highlights) do
                        if not seen[entity] then
                            removeHL(entity)
                        end
                    end
                end)
            else
                RunLoops:UnbindFromHeartbeat("ESP")
                for entity in pairs(highlights) do
                    removeHL(entity)
                end
            end
        end
    })
    fill = ESP.CreateSlider({
        Name = "Fill",
        Min = 0,
        Max = 100,
        Default = 60,
        Round = 1
    })
    teams = ESP.CreateToggle({
        Name = "Teams",
        Default = true
    })
end)

runcode(function()
    local cache = {}
    local gui

    local Tags = {}
    local name = {}
    local dist = {}
    local hp = {}
    local level = {}
    local brackets = {}
    local bg = {}
    local teams = {}
    local corner = {}
    local fontOpt = {}
    local weight = {}
    local size = {}

    local function getGui()
        if gui then return gui end
        local g = safeNew("ScreenGui")
        if not g then return nil end
        g.Name = "Nametags"
        g.IgnoreGuiInset = true
        g.ResetOnSpawn = false
        g.Parent = CoreGui
        gui = g
        return gui
    end

    local function removeTag(entity)
        if cache[entity] then
            cache[entity].frame:Destroy()
            cache[entity] = nil
        end
    end

    local function makeTag(entity)
        local parentGui = getGui()
        if not parentGui then return nil end

        local frame = safeNew("Frame")
        if not frame then return nil end
        frame.AnchorPoint = Vector2.new(0.5, 1)
        frame.BackgroundTransparency = 1
        frame.BorderSizePixel = 0
        frame.Parent = parentGui

        local bgf = safeNew("Frame")
        if not bgf then frame:Destroy(); return nil end
        bgf.Size = UDim2.fromScale(1, 1)
        bgf.BorderSizePixel = 0
        bgf.BackgroundColor3 = Color3.new(0, 0, 0)
        bgf.Parent = frame

        local cornerObj = safeNew("UICorner")
        if cornerObj then cornerObj.Parent = bgf end

        local text = safeNew("TextLabel")
        if text then
            text.BackgroundTransparency = 1
            text.Size = UDim2.fromScale(1, 1)
            text.RichText = true
            text.TextStrokeTransparency = 0.4
            text.TextColor3 = Color3.new(1, 1, 1)
            text.Parent = bgf
        end

        cache[entity] = {
            frame = frame,
            bg = bgf,
            corner = cornerObj,
            text = text
        }

        return cache[entity]
    end

    local function rgb(c)
        return ("rgb(%d,%d,%d)"):format(c.R * 255, c.G * 255, c.B * 255)
    end

    local function rainbow(str)
        local out = {}
        local t = tick() * 0.25

        for i = 1, #str do
            local c = Color3.fromHSV((t + (i / #str)) % 1, 0.9, 1)
            out[i] = ('<font color="%s">%s</font>'):format(rgb(c), str:sub(i, i))
        end

        return table.concat(out)
    end

    local function getFontFace()
        local family = fontOpt.Value
        if family == "GothamSSm" or family == "Gotham" then
            family = "Montserrat"
        end

        family = family or "Montserrat"

        local weightName = (weight.Value == "Off" and "Regular") or weight.Value

        return Font.new(
            "rbxasset://fonts/families/" .. family .. ".json",
            Enum.FontWeight[weightName],
            Enum.FontStyle.Normal
        )
    end

    Tags = GuiLibrary.Registry.renderPanel.API.CreateOptionsButton({
        Name = "Nametags",
        Function = function(callback)
            if callback then
                RunLoops:BindToHeartbeat("Nametags", function()
                    local char = PlayerUtility.GetCharacter()
                    local localRoot = PlayerUtility.lplrRoot

                    local seen = {}
                    local shootingRange = workspace:FindFirstChild("ShootingRangeEntities")

                    for _, entity in ipairs(CollectionService:GetTagged("Entity")) do
                        if entity == char or not entity:IsA("Model") then continue end
                        if shootingRange and entity:IsDescendantOf(shootingRange) then continue end

                        local root = entity:FindFirstChild("HumanoidRootPart")
                        local hum = entity:FindFirstChildOfClass("Humanoid")

                        if not root or not hum or hum.Health <= 0 then
                            removeTag(entity)
                            continue
                        end

                        if teams.Enabled and root:FindFirstChild("TeammateLabel") then
                            removeTag(entity)
                            continue
                        end

                        seen[entity] = true

                        local tag = cache[entity] or makeTag(entity)
                        local plr = Players:GetPlayerFromCharacter(entity)
                        local parts = {}

                        local username = plr and (name.Enabled and plr.DisplayName ~= "" and plr.DisplayName or plr.Name) or entity.Name
                        parts[#parts+1] = '<font color="rgb(255,255,255)">' .. username:upper() .. "</font>"

                        if dist.Enabled and localRoot then
                            local d = math.floor((localRoot.Position - root.Position).Magnitude)
                            parts[#parts+1] = ('<font color="rgb(85,255,85)">%s%s%s</font>'):format(brackets.Enabled and "[" or "", d, brackets.Enabled and "]" or "")
                        end

                        if level.Enabled then
                            local lvl = tonumber((plr and plr:GetAttribute("Level")) or entity:GetAttribute("Level")) or 0
                            local txt = "Lv." .. lvl

                            if lvl >= 200 then
                                txt = rainbow(brackets.Enabled and ("[" .. txt .. "]") or txt)
                            else
                                txt = ('<font color="rgb(255,215,0)">%s%s%s</font>'):format(brackets.Enabled and "[" or "", txt, brackets.Enabled and "]" or "")
                            end

                            parts[#parts+1] = txt
                        end

                        if hp.Enabled then
                            local h = math.floor(hum.Health)
                            local c = Color3.fromHSV(math.clamp(h / hum.MaxHealth, 0, 1) / 3, 0.9, 1)
                            parts[#parts+1] = ('<font color="%s">%s%s%s</font>'):format(rgb(c), brackets.Enabled and "[" or "", h, brackets.Enabled and "]" or "")
                        end

                        tag.text.Text = table.concat(parts, " ")
                        tag.text.FontFace = getFontFace()
                        tag.text.TextSize = size.Value

                        tag.bg.BackgroundTransparency = bg.Enabled and 0.35 or 1
                        tag.corner.CornerRadius = UDim.new(0, corner.Value == "Square" and 0 or 6)

                        local bounds = tag.text.TextBounds
                        tag.frame.Size = UDim2.fromOffset(bounds.X + 10, bounds.Y + 6)

                        local pos, visible = Camera:WorldToViewportPoint(root.Position + Vector3.new(0, hum.HipHeight + 1.2, 0))

                        tag.frame.Visible = visible and pos.Z > 0

                        if tag.frame.Visible then
                            tag.frame.Position = UDim2.fromOffset(pos.X, pos.Y)
                        end
                    end

                    for ent in pairs(cache) do
                        if not seen[ent] then
                            removeTag(ent)
                        end
                    end
                end)
            else
                RunLoops:UnbindFromHeartbeat("Nametags")
                for entity in pairs(cache) do
                    removeTag(entity)
                end
                if gui then
                    gui:Destroy()
                    gui = nil
                end
            end
        end
    })
    name = Tags.CreateToggle({
        Name = "Display",
        Default = true
    })
    dist = Tags.CreateToggle({
        Name = "Distance",
        Default = true
    })
    hp = Tags.CreateToggle({
        Name = "Health",
        Default = true
    })
    level = Tags.CreateToggle({
        Name = "Level",
        Default = true
    })
    brackets = Tags.CreateToggle({
        Name = "Brackets",
        Default = true
    })
    bg = Tags.CreateToggle({
        Name = "Background",
        Default = true
    })
    teams = Tags.CreateToggle({
        Name = "Teams",
        Default = true
    })
    corner = Tags.CreateDropdown({
        Name = "Corners",
        List = {"Rounded", "Square"},
        Default = "Rounded"
    })
    fontOpt = Tags.CreateDropdown({
        Name = "Font",
        List = {"Arial", "Montserrat", "Nunito", "Ubuntu", "Roboto", "Arimo"},
        Default = "Montserrat"
    })
    weight = Tags.CreateDropdown({
        Name = "Weight",
        List = {"Regular", "Bold"},
        Default = "Bold"
    })
    size = Tags.CreateSlider({
        Name = "Size",
        Min = 7,
        Max = 20,
        Default = 13,
        Round = 1
    })
end)
