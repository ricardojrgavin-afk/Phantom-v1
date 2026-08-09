local Players = cloneref(game:GetService("Players"))
local Workspace = cloneref(game:GetService("Workspace"))
local ReplicatedStorage = cloneref(game:GetService("ReplicatedStorage"))
local CoreGui = cloneref(game:GetService("CoreGui"))
local Camera = Workspace.CurrentCamera
local lplr = Players.LocalPlayer

local UI = phantom.UI
local GuiLibrary = UI
local funcs = phantom.ops
local Runtime = phantom.ops.runtime
local RunLoops = Runtime.RunLoops
local runcode = Runtime.run
local PlayerUtility = phantom.module:Load("utility")

local regionUtil = nil
local gunData = nil
local controllerEnv = {}
local saShared = {}
local clientPhasedParts = {}
local detectedMods = {}

local PLAYER_STATE = {
    ALIVE = 0,
    DEAD = 1,
}
local TEAM = {
    NONE = "None",
    FOUNDATION = "Foundation",
    DCLASS = "Class - D",
    CI = "Chaos Insurgency",
    SCP = "SCP",
}
local ZONE = {
    UNKNOWN = "Unknown",
    SURFACE = "Surface",
    FACILITY = "Facility",
    VENT = "Vent",
    RK_ZONE = "RK Zone",
}

local GameData = {
    changed = nil,
    connections = {},
    data = {
        playerState = PLAYER_STATE.ALIVE,
        team = TEAM.NONE,
        zone = ZONE.UNKNOWN,
        isRogue = false,
        isInfected = false,
        inVent = false,
        activeSCPs = {},
        detectedStaff = {},
        equippedGun = nil,
        currentAmmo = nil,
        ammoCount = nil,
        magazineSize = nil,
        isReloading = false,
        fps = 0,
        ping = nil,
        nearbyEnemies = {},
        nearbyAllies = {},
    }
}

local Prediction = (function()
    local ok, m = pcall(function()
        return loadstring(readfile("Phantom/lib/Prediction.lua"))()
    end)
    return ok and m or nil
end)()

task.spawn(function()
    local cs = lplr.PlayerScripts:WaitForChild("Controller", 30)
    if not cs then warn("Controller script not found after 30s") return end
    if not getsenv then warn("getsenv not supported") return end
    controllerEnv = getsenv(cs) or {}
    warn("getsenv OK | SimulateShot present:", controllerEnv.SimulateShot ~= nil)
end)

local scprp = {}
task.spawn(function()
    local uf = ReplicatedStorage:WaitForChild("Utility"):WaitForChild("Function")
    local ud = ReplicatedStorage:WaitForChild("Utility"):WaitForChild("Data")
    local rem = ReplicatedStorage:WaitForChild("Remotes")

    local ok, Delta = pcall(require, ReplicatedStorage:WaitForChild("Delta"):WaitForChild("DeltaFramework"))
    local delta = ok and Delta or nil

    regionUtil = require(uf:WaitForChild("RegionUtil"))

    scprp.Delta = delta
    scprp.CS = delta and delta.CS or nil
    scprp.Event = delta and delta:Get("Networking"):Retrieve("Event") or nil
    scprp.RegionUtil = require(uf:WaitForChild("RegionUtil"))
    scprp.IsRK = require(uf:WaitForChild("IsRK"))
    scprp.GetHumanoid = require(uf:WaitForChild("GetHumanoid"))
    scprp.InteractData = require(ud:WaitForChild("Interactions"))
    scprp.Clipboard = require(ReplicatedStorage:WaitForChild("MiscModules"):WaitForChild("Clipboard"))
    scprp.Remotes = {
        Interact = rem:WaitForChild("Interact"),
    }
end)

local Net = {}

Net.isReady = function()
    return scprp.Event ~= nil
end

Net.waitForEvent = function(timeout)
    local t = tick()
    repeat task.wait(0.5) until scprp.Event ~= nil or tick() - t > (timeout or 30)
    return scprp.Event
end

Net.waitFor = function(getter, timeout)
    local t = tick()
    local v
    repeat task.wait(0.1) v = getter() until v ~= nil or tick() - t > (timeout or 30)
    return v
end

Net.FireServer = function(...)
    if not scprp.Event then return end
    pcall(scprp.Event.FireServer, scprp.Event, ...)
end

Net.CallServerAsync = function(eventType, model, delay)
    task.delay(delay or 0.3, function()
        Net.FireServer(eventType, model)
    end)
end

Net.FireInteract = function(...)
    if not scprp.Remotes or not scprp.Remotes.Interact then return end
    pcall(scprp.Remotes.Interact.FireServer, scprp.Remotes.Interact, ...)
end

Net.onEvent = function(callback)
    local event = Net.waitForEvent()
    if not event then return function() end end
    local conn = event.OnClientEvent:Connect(callback)
    return function() conn:Disconnect() end
end

task.spawn(function()
    local gunSettingsFolder = ReplicatedStorage:WaitForChild("GunSettings", 15)
    if not gunSettingsFolder then return end

    local lastGun = nil
    while true do
        task.wait(0.5)
        local char = lplr.Character
        local equip = char and char:FindFirstChildOfClass("Tool")
        local gunName = equip and equip.Name

        if gunName ~= lastGun then
            lastGun = gunName
            if gunName then
                local settingsModule = gunSettingsFolder:FindFirstChild(gunName)
                if settingsModule then
                    local ok, settings = pcall(require, settingsModule)
                    if ok and type(settings) == "table" then
                        gunData = settings
                        GameData.data.magazineSize = settings.Clip
                        if GameData.changed then
                            GameData.changed("gunData", settings)
                        end
                    end
                end
            else
                gunData = nil
                GameData.data.magazineSize = nil
            end
        end
    end
end)

task.spawn(function()
    local t = tick()
    repeat task.wait(0.5) until regionUtil ~= nil or tick() - t > 30

    local INFECTED_CHECK = {"Infected", "008Infected", "SCP008", "Zombie", "008"}

    local function onCharacterAdded(char)
        GameData.data.playerState = PLAYER_STATE.ALIVE
        if GameData.changed then GameData.changed("playerState", PLAYER_STATE.ALIVE) end
        local hum = char:WaitForChild("Humanoid", 5)
        if hum then
            hum.Died:Connect(function()
                GameData.data.playerState = PLAYER_STATE.DEAD
                if GameData.changed then GameData.changed("playerState", PLAYER_STATE.DEAD) end
            end)
        end
    end

    if lplr.Character then task.spawn(onCharacterAdded, lplr.Character) end
    table.insert(GameData.connections, lplr.CharacterAdded:Connect(onCharacterAdded))
    table.insert(GameData.connections, lplr:GetPropertyChangedSignal("Team"):Connect(function()
        GameData.data.team = lplr.Team and lplr.Team.Name or TEAM.NONE
        if GameData.changed then GameData.changed("team", GameData.data.team) end
    end))

    while true do
        task.wait(1)
        local char = lplr.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")

        GameData.data.team = lplr.Team and lplr.Team.Name or TEAM.NONE

        if char then
            GameData.data.isRogue = char:HasTag("Rogue")
            local infected = false
            for _, tag in ipairs(INFECTED_CHECK) do
                if char:HasTag(tag) then infected = true break end
            end
            GameData.data.isInfected = infected
        end

        if hrp and regionUtil then
            local okV, inVent = pcall(regionUtil.IsInCIVent, regionUtil, hrp.Position)
            GameData.data.inVent = okV and inVent or false

            local zone = ZONE.UNKNOWN
            for _, name in ipairs({ZONE.SURFACE, ZONE.RK_ZONE, ZONE.FACILITY}) do
                local okZ, inZ = pcall(regionUtil.IsInCustomZone, regionUtil, name, char)
                if okZ and inZ then zone = name break end
            end
            if GameData.data.inVent then zone = ZONE.VENT end
            GameData.data.zone = zone
        end

        local equip = char and char:FindFirstChildOfClass("Tool")
        local ammoObj = equip and equip:FindFirstChild("CurrentAmmo")
        GameData.data.equippedGun = equip and equip.Name or nil
        GameData.data.currentAmmo = ammoObj and ammoObj.Value or nil

        local scps = {}
        local scpFolder = workspace:FindFirstChild("SCPs")
        if scpFolder then
            for _, model in ipairs(scpFolder:GetChildren()) do
                local hum = model:FindFirstChildOfClass("Humanoid")
                if hum and hum.Health > 0 then
                    scps[#scps + 1] = model.Name
                end
            end
        end
        GameData.data.activeSCPs = scps

        GameData.data.detectedStaff = detectedMods
    end
end)

task.spawn(function()
    local t = tick()
    repeat task.wait(0.5) until controllerEnv.Reload ~= nil or tick() - t > 30

    if controllerEnv.Reload then
        local origReload = controllerEnv.Reload
        controllerEnv.Reload = newcclosure(function(...)
            GameData.data.isReloading = true
            if GameData.changed then GameData.changed("isReloading", true) end
            local r = origReload(...)
            GameData.data.isReloading = false
            if GameData.changed then GameData.changed("isReloading", false) end
            return r
        end)
    end

    while true do
        task.wait(0.1)
        local char = lplr.Character
        local equip = char and char:FindFirstChildOfClass("Tool")
        if equip then
            local ammoObj = equip:FindFirstChild("CurrentAmmo")
            local maxObj = equip:FindFirstChild("MaxAmmo") or equip:FindFirstChild("MagazineSize")
            local prev = GameData.data.ammoCount
            GameData.data.ammoCount = ammoObj and ammoObj.Value or nil
            GameData.data.magazineSize = maxObj and maxObj.Value or nil
            if GameData.data.ammoCount ~= prev and GameData.changed then
                GameData.changed("ammoCount", GameData.data.ammoCount)
            end
        else
            GameData.data.ammoCount = nil
            GameData.data.magazineSize = nil
            GameData.data.isReloading = false
        end
    end
end)

task.spawn(function()
    local RunService = game:GetService("RunService")
    local Stats = game:GetService("Stats")
    local SAMPLE_SIZE = 30
    local dtSamples = {}

    table.insert(GameData.connections, RunService.Heartbeat:Connect(function(dt)
        dtSamples[#dtSamples + 1] = dt
        if #dtSamples > SAMPLE_SIZE then table.remove(dtSamples, 1) end
    end))

    local t = tick()
    repeat task.wait(0.5) until regionUtil ~= nil or tick() - t > 30

    while true do
        task.wait(2)

        if #dtSamples > 0 then
            local sum = 0
            for _, v in ipairs(dtSamples) do sum = sum + v end
            GameData.data.fps = math.round(1 / (sum / #dtSamples))
        end

        local okP, ping = pcall(function()
            return Stats.Network.ServerStatsItem["Data Ping"].Value
        end)
        GameData.data.ping = okP and math.round(ping) or nil

        if GameData.changed then
            GameData.changed("performance", {
                fps = GameData.data.fps,
                ping = GameData.data.ping,
            })
        end

        local char = lplr.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if hrp then
            local nearbyEnemies = {}
            local nearbyAllies = {}
            local myTeam = lplr.Team and lplr.Team.Name

            for _, plr in ipairs(Players:GetPlayers()) do
                if plr == lplr then continue end
                local pChar = plr.Character
                local pHRP = pChar and pChar:FindFirstChild("HumanoidRootPart")
                if not pHRP then continue end
                local dist = (hrp.Position - pHRP.Position).Magnitude
                if dist > 60 then continue end
                local hum = pChar:FindFirstChildOfClass("Humanoid")
                if not hum or hum.Health <= 0 then continue end
                local entry = {
                    name = plr.Name,
                    dist = math.round(dist),
                    team = plr.Team and plr.Team.Name or TEAM.NONE,
                }
                if plr.Team and plr.Team.Name == myTeam then
                    nearbyAllies[#nearbyAllies + 1] = entry
                else
                    nearbyEnemies[#nearbyEnemies + 1] = entry
                end
            end

            table.sort(nearbyEnemies, function(a, b) return a.dist < b.dist end)
            table.sort(nearbyAllies, function(a, b) return a.dist < b.dist end)

            GameData.data.nearbyEnemies = nearbyEnemies
            GameData.data.nearbyAllies = nearbyAllies
            if GameData.changed then
                GameData.changed("proximity", {
                    enemies = nearbyEnemies,
                    allies = nearbyAllies,
                })
            end
        end
    end
end)

for _, v in ipairs({"Antideath","Gravity","ESP","AntiFall","TriggerBot","AimAssist","BreadCrumbs","AutoClicker","ServerHop","NoClip","FPSBooster","FovChanger","AnimationPlayer","Speed","FastStop","Rejoin","Fly"}) do
    UI.kit:deregister(v .. "Module")
end

local SPAWN_LOCS = {
    "O5", "Security Department", "Intelligence Agency",
    "Internal Security Department", "Intel Spawn Area",
    "Mobile Task Force", "Rapid Response Team",
    "Scientific Department", "Medical Department",
    "Administrative Department", "Chaos Insurgency",
}

local function getSpawnZone(pos)
    if not regionUtil then return nil end
    for _, loc in ipairs(SPAWN_LOCS) do
        local ok, res = pcall(regionUtil.IsInLocation, regionUtil, loc, pos)
        if ok and res then
            return loc == "Intel Spawn Area" and "Intel" or loc
        end
    end
    return nil
end

local isAlly, findGun, isSpawnKill, ownBase
do
    isAlly = function(plr)
        local mt, tt = lplr.Team, plr.Team
        if not mt or not tt then return false end
        if mt == tt then return true end
        local function info(t)
            local cat = t:GetAttribute("Team_Category") or ""
            local h = cat == "HOSTILE"
            local ih = not h and (t.Name == "Chaos Insurgency" or t.Name == "Class - D")
            return cat, ih, cat == "FOUNDATION" or (not h and not ih and cat ~= "NEUTRAL")
        end
        local mc, mih, mif = info(mt)
        local tc, tih, tif = info(tt)
        return (mc ~= "" and mc == tc) or (mif and tif) or (mih and tih)
    end

    findGun = function()
        if gunData then return end
        if not controllerEnv.SimulateShot then return end
        local getUpvals = debug.getupvalues or getupvalues
        if not getUpvals then return end
        local ok, uvs = pcall(getUpvals, controllerEnv.SimulateShot)
        if not ok then return end
        for _, uv in pairs(uvs) do
            if type(uv) == "table" and type(uv.TBS) == "number" and type(uv.Last) == "number" and type(uv.CurrentAmmo) == "number" then
                gunData = uv
                return
            end
        end
    end

    isSpawnKill = function(targetChar)
        if not targetChar then return false end
        local hrp = targetChar:FindFirstChild("HumanoidRootPart")
        if not hrp then return false end
        local targetPlr = Players:GetPlayerFromCharacter(targetChar)
        local teamName = targetPlr and targetPlr.Team and targetPlr.Team.Name
        local spawn = getSpawnZone(hrp.Position)
        if not spawn then return false end
        if teamName == spawn then return true end
        if spawn == "O5" then
            return targetPlr and targetPlr:GetAttribute("O5") and teamName ~= "Chaos Insurgency"
        end
        return false
    end

    ownBase = function()
        local hrp = lplr.Character and lplr.Character:FindFirstChild("HumanoidRootPart")
        if not hrp then return false end
        local myTeam = lplr.Team and lplr.Team.Name
        local spawn = getSpawnZone(hrp.Position)
        return spawn ~= nil and myTeam == spawn
    end
end

runcode(function()
    local InfiniteStamina = {}
    local origFixStamina

    InfiniteStamina = GuiLibrary.Registry.movementPanel.API.CreateOptionsButton({
        Name = "InfiniteStamina",
        Function = function(enabled)
            if enabled then
                origFixStamina = shared.FixCharacterSpeed
                shared.FixCharacterSpeed = newcclosure(function(p250, ...)
                    local char = lplr.Character
                    local a966, a076
                    if char then
                        a966 = char:GetAttribute("966Target")
                        a076 = char:GetAttribute("076Slowdown")
                        if a966 then char:SetAttribute("966Target", nil) end
                        if a076 then char:SetAttribute("076Slowdown", nil) end
                    end
                    origFixStamina(p250, ...)
                    if char then
                        if a966 then char:SetAttribute("966Target", a966) end
                        if a076 then char:SetAttribute("076Slowdown", a076) end
                    end
                end)
            else
                if origFixStamina then
                    shared.FixCharacterSpeed = origFixStamina
                    origFixStamina = nil
                end
                pcall(shared.FixCharacterSpeed)
            end
        end
    })
end)

runcode(function()
    local Phase = {}
    local phaseDisabled = {}

    Phase = GuiLibrary.Registry.movementPanel.API.CreateOptionsButton({
        Name = "Phase",
        Function = function(enabled)
            if enabled then
                local phaseRp = RaycastParams.new()
                phaseRp.FilterType = Enum.RaycastFilterType.Exclude

                RunLoops:BindToHeartbeat("Phase", function()
                    local char = lplr.Character
                    local hrp = char and char:FindFirstChild("HumanoidRootPart")
                    if not char or not hrp then return end
                    local hum = char:FindFirstChildOfClass("Humanoid")
                    local hipH = hum and hum.HipHeight or 2

                    phaseRp.FilterDescendantsInstances = {char}

                    local floorParts = {}
                    local downDist = Vector3.new(0, -(hipH + 4), 0)
                    local footR = 0.9
                    for _, off in ipairs({
                        Vector3.new(0, 0, 0),
                        Vector3.new( footR, 0, footR),
                        Vector3.new(-footR, 0, footR),
                        Vector3.new( footR, 0, -footR),
                        Vector3.new(-footR, 0, -footR),
                    }) do
                        local h = workspace:Raycast(hrp.Position + off, downDist, phaseRp)
                        if h and h.Instance then floorParts[h.Instance] = true end
                    end

                    local nearby = workspace:GetPartBoundsInBox(hrp.CFrame, Vector3.new(10, 12, 10))
                    local current = {}

                    for _, part in ipairs(nearby) do
                        if part:IsDescendantOf(char) then continue end
                        if floorParts[part] then continue end
                        current[part] = true
                        if phaseDisabled[part] == nil then
                            phaseDisabled[part] = part.CanCollide
                            clientPhasedParts[part] = true
                            part.CanCollide = false
                        end
                    end

                    for part, orig in pairs(phaseDisabled) do
                        if not current[part] then
                            pcall(function() part.CanCollide = orig end)
                            clientPhasedParts[part] = nil
                            phaseDisabled[part] = nil
                        end
                    end
                end)
            else
                RunLoops:UnbindFromHeartbeat("Phase")
                for part, orig in pairs(phaseDisabled) do
                    pcall(function() part.CanCollide = orig end)
                    clientPhasedParts[part] = nil
                end
                phaseDisabled = {}
                local char = lplr.Character
                local hum = char and char:FindFirstChildOfClass("Humanoid")
                if hum then hum.Jump = true end
            end
        end
    })
end)

runcode(function()
    local Interactions = {}
    local PhaseDoors = {}
    local AutoBreakVents = {}
    local AntiCuff = {}

    local dpDisabled = {}
    local dpParts = {}
    local pdActive = false

    local DOOR_NAMES = {}
    pcall(function()
        local interactData = scprp.InteractData
        if not interactData then return end
        for name, data in pairs(interactData) do
            if type(data) == "table" and type(data.Open) == "number" then
                DOOR_NAMES[name] = true
            end
        end
    end)

    local abvLastFire = 0
    local abvVents = {}
    local abvConns = {}
    local function abvBuildCache()
        abvVents = {}
        for _, part in ipairs(workspace:GetDescendants()) do
            if part:IsA("BasePart") and part.Name == "VentClickable" then
                local cd = part:FindFirstChildOfClass("ClickDetector")
                if cd then abvVents[part] = cd end
            end
        end
        if #abvConns == 0 then
            abvConns[1] = workspace.DescendantAdded:Connect(function(d)
                if d:IsA("BasePart") and d.Name == "VentClickable" then
                    local cd = d:FindFirstChildOfClass("ClickDetector") or d.ChildAdded:Wait()
                    if cd and cd:IsA("ClickDetector") then abvVents[d] = cd end
                end
            end)
            abvConns[2] = workspace.DescendantRemoving:Connect(function(d)
                if abvVents[d] then abvVents[d] = nil end
            end)
        end
    end

    Interactions = GuiLibrary.Registry.blatantPanel.API.CreateOptionsButton({
        Name = "Interactions",
        Function = function(enabled)
            if enabled then
                abvBuildCache()
                local CS = game:GetService("CollectionService")

                local function fireEvent(name, model)
                    Net.FireServer(name, model)
                    Net.FireServer(name, {
                        model = model,
                        object = model,
                    })
                end

                local acControls = nil
                pcall(function()
                    acControls = require(lplr.PlayerScripts:WaitForChild("PlayerModule", 0)):GetControls()
                end)

                local function addDoor(obj)
                    if obj.Name == "C4" then return end
                    local list = obj:IsA("BasePart") and {obj} or obj:GetDescendants()
                    for _, part in ipairs(list) do
                        if not part:IsA("BasePart") then continue end
                        if dpDisabled[part] == nil then
                            dpDisabled[part] = part.CanCollide
                            clientPhasedParts[part] = true
                            table.insert(dpParts, part)
                        end
                        part.CanCollide = false
                    end
                end

                RunLoops:BindToHeartbeat("InteractionFeatures", function()
                    if PhaseDoors.Enabled then
                        if not pdActive then
                            pdActive = true
                            for _, door in ipairs(CS:GetTagged("Interaction")) do addDoor(door) end
                            for _, container in ipairs({"Map", "F3XBuilt"}) do
                                local root = workspace:FindFirstChild(container)
                                if root then
                                    for _, obj in ipairs(root:GetDescendants()) do
                                        if DOOR_NAMES[obj.Name] then addDoor(obj) end
                                    end
                                end
                            end
                        end
                        for _, part in ipairs(dpParts) do part.CanCollide = false end
                        for _, door in ipairs(CS:GetTagged("Interaction")) do addDoor(door) end
                    elseif pdActive then
                        pdActive = false
                        for part, orig in pairs(dpDisabled) do
                            pcall(function() part.CanCollide = orig end)
                            clientPhasedParts[part] = nil
                        end
                        dpDisabled = {}
                        dpParts = {}
                    end

                    if AutoBreakVents.Enabled then
                        local now = tick()
                        if now - abvLastFire >= 0.1 then
                            abvLastFire = now
                            local hrp = lplr.Character and lplr.Character:FindFirstChild("HumanoidRootPart")
                            if hrp then
                                for part, cd in pairs(abvVents) do
                                    if (part.Position - hrp.Position).Magnitude <= 12 then
                                        pcall(fireclickdetector, cd)
                                    end
                                end
                            end
                        end
                    end

                    if AntiCuff.Enabled then
                        local char = lplr.Character
                        if char then
                            local ld = char:FindFirstChild("LeftDetain")
                            if ld then
                                pcall(function() ld:Destroy() end)
                                if acControls then
                                    pcall(function() acControls:Enable() end)
                                end
                            end
                        end
                    end

                end)
            else
                RunLoops:UnbindFromHeartbeat("InteractionFeatures")
                pdActive = false
                for part, orig in pairs(dpDisabled) do
                    pcall(function() part.CanCollide = orig end)
                end
                dpDisabled = {}
                dpParts = {}
                for _, c in ipairs(abvConns) do c:Disconnect() end
                abvConns = {}
                abvVents = {}
            end
        end
    })

    PhaseDoors = Interactions.CreateToggle({
        Name = "PhaseDoors",
        Default = false
    })
    AutoBreakVents = Interactions.CreateToggle({
        Name = "BreakVents",
        Default = false
    })
    AntiCuff = Interactions.CreateToggle({
        Name = "AntiCuff",
        Default = false
    })
end)

runcode(function()
    local HitBox = {}
    local HitBoxSize = {}
    local origSizes = {}
    local lastHBScan = 0

    HitBox = GuiLibrary.Registry.combatPanel.API.CreateOptionsButton({
        Name = "HitBox",
        Function = function(enabled)
            if enabled then
                RunLoops:BindToHeartbeat("HitBox", function()
                    local now = tick()
                    if now - lastHBScan < 0.5 then return end
                    lastHBScan = now
                    local expand = (HitBoxSize and HitBoxSize.Value) or 4
                    for _, plr in ipairs(Players:GetPlayers()) do
                        if plr == lplr then continue end
                        local char = plr.Character
                        if not char then continue end
                        local hrp = char:FindFirstChild("HumanoidRootPart")
                        if not hrp then continue end
                        if not origSizes[hrp] then origSizes[hrp] = hrp.Size end
                        pcall(function()
                            hrp.Size = origSizes[hrp] + Vector3.new(expand, expand, expand)
                        end)
                    end
                end)
            else
                RunLoops:UnbindFromHeartbeat("HitBox")
                for part, size in pairs(origSizes) do
                    pcall(function() part.Size = size end)
                end
                origSizes = {}
                lastHBScan = 0
            end
        end
    })
    HitBoxSize = HitBox.CreateSlider({
        Name = "Size",
        Min = 1,
        Max = 10,
        Default = 4,
        Round = 0
    })
end)

runcode(function()
    local AutoReload = {}
    AutoReload = GuiLibrary.Registry.combatPanel.API.CreateOptionsButton({
        Name = "AutoReload",
        Function = function(enabled)
            if enabled then
                local lastAttempt = 0
                local lastTool = nil
                RunLoops:BindToHeartbeat("AutoReload", function()
                    local char = lplr.Character
                    if not char then return end
                    local tool = char:FindFirstChildOfClass("Tool")
                    if not tool then lastTool = nil return end
                    local ammoObj = tool:FindFirstChild("CurrentAmmo")
                    if not ammoObj then return end
                    if tool ~= lastTool then
                        lastTool = tool
                        lastAttempt = tick() + 0.3
                    end
                    if ammoObj.Value > 0 then return end
                    if tick() >= lastAttempt then
                        lastAttempt = tick() + 1.5
                        pcall(controllerEnv.Reload)
                    end
                end)
            else
                RunLoops:UnbindFromHeartbeat("AutoReload")
            end
        end
    })
end)

runcode(function()
    local Fly = {}
    local FlyValue = {}
    local FlyVerticalValue = {}
    local UIS = game:GetService("UserInputService")
    local flyLinVel = nil
    local flyAttach = nil

    local FlyUtil = {}

    FlyUtil.createLinVel = function(hrp)
        if flyLinVel and flyLinVel.Parent then return end
        flyAttach = Instance.new("Attachment")
        flyAttach.Parent = hrp
        flyLinVel = Instance.new("LinearVelocity")
        flyLinVel.Attachment0 = flyAttach
        flyLinVel.RelativeTo = Enum.ActuatorRelativeTo.World
        flyLinVel.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
        flyLinVel.MaxForce = math.huge
        flyLinVel.VectorVelocity = Vector3.zero
        flyLinVel.Parent = hrp
    end

    FlyUtil.cleanupLinVel = function()
        if flyLinVel then flyLinVel:Destroy() flyLinVel = nil end
        if flyAttach then flyAttach:Destroy() flyAttach = nil end
    end

    Fly = GuiLibrary.Registry.movementPanel.API.CreateOptionsButton({
        Name = "Fly",
        Function = function(enabled)
            local i = 0
            local verticalVelocity = 0
            if enabled then
                RunLoops:BindToHeartbeat("Fly", function(dt)
                    local char = lplr.Character
                    local hrp = char and char:FindFirstChild("HumanoidRootPart")
                    local hum = char and char:FindFirstChildOfClass("Humanoid")
                    if not hrp or not hum or hum.Health <= 0 then return end

                    FlyUtil.createLinVel(hrp)

                    i = i + (dt * 4)
                    local moveDir = hum.MoveDirection
                    local bounce = math.sin(i * math.pi) * 0.01

                    if not UIS:GetFocusedTextBox() then
                        if UIS:IsKeyDown(Enum.KeyCode.Space) then
                            verticalVelocity = FlyVerticalValue.Value
                        elseif UIS:IsKeyDown(Enum.KeyCode.LeftControl) then
                            verticalVelocity = -FlyVerticalValue.Value
                        else
                            verticalVelocity = bounce
                        end
                    else
                        verticalVelocity = bounce
                    end

                    local hVel = moveDir * FlyValue.Value
                    flyLinVel.VectorVelocity = Vector3.new(hVel.X, verticalVelocity, hVel.Z)
                end)
            else
                RunLoops:UnbindFromHeartbeat("Fly")
                FlyUtil.cleanupLinVel()
                local char = lplr.Character
                local hum = char and char:FindFirstChildOfClass("Humanoid")
                if hum then hum:ChangeState(Enum.HumanoidStateType.GettingUp) end
            end
        end
    })

    FlyValue = Fly.CreateSlider({
        Name = "Speed",
        Min = 0,
        Max = 42,
        Default = 42,
        Round = 1
    })
    FlyVerticalValue = Fly.CreateSlider({
        Name = "Vertical",
        Min = 0,
        Max = 100,
        Default = 60,
        Round = 1
    })
end)

runcode(function()
    local Speed = {}
    local SpeedSlider = {}
    local WallCheck = {}
    local AutoJump = {}

    local wallRp = RaycastParams.new()
    wallRp.FilterType = Enum.RaycastFilterType.Exclude
    wallRp.RespectCanCollide = true

    Speed = GuiLibrary.Registry.movementPanel.API.CreateOptionsButton({
        Name = "Speed",
        Function = function(enabled)
            if enabled then
                local conn = game:GetService("RunService").PreSimulation:Connect(function(dt)
                    local char = lplr.Character
                    local hrp = char and char:FindFirstChild("HumanoidRootPart")
                    local hum = char and char:FindFirstChildOfClass("Humanoid")
                    if not hrp or not hum or hum.Health <= 0 then return end

                    local state = hum:GetState()
                    if state == Enum.HumanoidStateType.Climbing then return end

                    local moveDir = hum.MoveDirection
                    if moveDir.Magnitude == 0 then return end

                    local vel = hrp.AssemblyLinearVelocity
                    local horizSpeed = Vector3.new(vel.X, 0, vel.Z).Magnitude
                    local destination = moveDir * math.max(SpeedSlider.Value - horizSpeed, 0) * dt

                    if WallCheck.Enabled then
                        wallRp.FilterDescendantsInstances = {char}
                        wallRp.CollisionGroup = hrp.CollisionGroup
                        local ray = workspace:Raycast(hrp.Position, destination, wallRp)
                        if ray then
                            destination = (ray.Position + ray.Normal) - hrp.Position
                        end
                    end

                    hrp.CFrame = hrp.CFrame + destination
                    hrp.AssemblyLinearVelocity = moveDir * horizSpeed + Vector3.new(0, vel.Y, 0)

                    if AutoJump.Enabled and moveDir ~= Vector3.zero and
                        (state == Enum.HumanoidStateType.Running or state == Enum.HumanoidStateType.Landed) then
                        hum:ChangeState(Enum.HumanoidStateType.Jumping)
                    end
                end)
                Speed._conn = conn
            else
                if Speed._conn then Speed._conn:Disconnect(); Speed._conn = nil end
            end
        end
    })

    SpeedSlider = Speed.CreateSlider({
        Name = "Value",
        Min = 1,
        Max = 42,
        Default = 42,
        Round = 1
    })
    WallCheck = Speed.CreateToggle({
        Name = "WallCheck",
        Default = true
    })
    AutoJump = Speed.CreateToggle({
        Name = "AutoJump",
        Default = false
    })
end)

runcode(function()
    local Sprint = {}
    local isCrouching = false
    local isAiming = false
    local sprinting = false
    local selfCalling = false
    local equipCooldown = false
    local origSetRun = nil

    task.spawn(function()
        local t = tick()
        repeat task.wait(0.2) until controllerEnv.SetCrouch ~= nil or tick() - t > 30
        if not controllerEnv.SetCrouch then return end
        local orig = controllerEnv.SetCrouch
        controllerEnv.SetCrouch = newcclosure(function(p, ...)
            isCrouching = p == true
            return orig(p, ...)
        end)
    end)

    task.spawn(function()
        local t = tick()
        repeat task.wait(0.2) until controllerEnv.SetAim ~= nil or tick() - t > 30
        if not controllerEnv.SetAim then return end
        local orig = controllerEnv.SetAim
        controllerEnv.SetAim = newcclosure(function(p, ...)
            isAiming = p == true
            return orig(p, ...)
        end)
    end)

    local reAssertTime = 0

    lplr.CharacterAdded:Connect(function()
        sprinting = false
    end)

    Sprint = GuiLibrary.Registry.combatPanel.API.CreateOptionsButton({
        Name = "Sprint",
        Function = function(enabled)
            if enabled then
                sprinting = false
                reAssertTime = 0

                if controllerEnv.SetRun and not origSetRun then
                    origSetRun = controllerEnv.SetRun
                    controllerEnv.SetRun = newcclosure(function(val, ...)
                        if not selfCalling then
                            sprinting = false
                            if not val then
                                reAssertTime = tick() + 0.25
                            end
                        end
                        return origSetRun(val, ...)
                    end)
                end

                task.spawn(function()
                    while Sprint.Enabled do
                        local char = lplr.Character
                        local hum = char and char:FindFirstChildOfClass("Humanoid")
                        local shouldRun = hum and hum.Health > 0
                            and not isCrouching
                            and not isAiming
                            and tick() >= reAssertTime
                            and hum.MoveDirection.Magnitude > 0

                        if shouldRun and not sprinting then
                            sprinting = true
                            selfCalling = true
                            pcall(origSetRun, true)
                            selfCalling = false
                        elseif not shouldRun and sprinting then
                            sprinting = false
                            selfCalling = true
                            pcall(origSetRun, false)
                            selfCalling = false
                        end
                        task.wait()
                    end

                    sprinting = false
                    selfCalling = true
                    pcall(origSetRun or controllerEnv.SetRun, false)
                    selfCalling = false
                    if origSetRun then
                        controllerEnv.SetRun = origSetRun
                        origSetRun = nil
                    end
                end)
            else
                sprinting = false
                if origSetRun then
                    controllerEnv.SetRun = origSetRun
                    origSetRun = nil
                end
                pcall(controllerEnv.SetRun, false)
            end
        end
    })
end)

runcode(function()
    local NoSlowdown = {}
    local origFCS = nil

    local SLOW_ATTRS = {
        "076Slowdown", "966Target", "HoldingTrolley",
        "InjuredState", "LowHealthSlow", "SCPSlow",
    }

    local function stripSlowdown(char)
        if not char then return end
        for _, attr in ipairs(SLOW_ATTRS) do
            if char:GetAttribute(attr) ~= nil then
                pcall(function() char:SetAttribute(attr, nil) end)
            end
        end
    end

    NoSlowdown = GuiLibrary.Registry.movementPanel.API.CreateOptionsButton({
        Name = "NoSlowdown",
        Function = function(enabled)
            if enabled then
                origFCS = shared.FixCharacterSpeed
                if origFCS then
                    shared.FixCharacterSpeed = newcclosure(function(...)
                        stripSlowdown(lplr.Character)
                        return origFCS(...)
                    end)
                end
                RunLoops:BindToHeartbeat("NoSlowdown", function()
                    local char = lplr.Character
                    local hum = char and char:FindFirstChildOfClass("Humanoid")
                    if not hum or hum.Health <= 0 then return end
                    stripSlowdown(char)
                    if hum.WalkSpeed < 16 then hum.WalkSpeed = 16 end
                    if hum.JumpPower < 35 then hum.JumpPower = 50 end
                end)
            else
                RunLoops:UnbindFromHeartbeat("NoSlowdown")
                if origFCS then
                    shared.FixCharacterSpeed = origFCS
                    origFCS = nil
                end
            end
        end
    })
end)

runcode(function()
    local SilentAim = {}
    local SATargetPart = {}
    local SAMode = {}
    local SAPriority = {}
    local SATargetingFOV = {}
    local SAMaxDistance = {}
    local SAHitChance = {}
    local SASpread = {}
    local SAWallCheck = {}
    local SATeamCheck = {}

    local SAShowFOV = {}
    local SATargetDot = {}
    local SATargetNPCs = {}
    local SATargetInfected = {}
    local SAWallbang = {}
    local SAWallbangDist = {}
    local SAWallbangRegion = {}
    local SAPartSwitch = {}
    local SAPrediction = {}

    local u12 = nil
    local origCastRay = nil
    local origBulletHit = nil
    local target = nil
    local saFovCircle = nil
    local saTargetDot = nil
    local saPartSwitchState = false
    local lastSwitchFlip = 0
    local predTrackers = {}

    local canTarget = function(plr)
        local char = plr.Character
        if not char then return false end
        if char:HasTag("TutorialImmunity") and not char:HasTag("Infected") then return false end
        if char:HasTag("087Instance") then return false end
        if char:HasTag("Unauthorized") then return false end
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if not hrp then return false end
        if hrp.Position.Y < -385 then return false end
        if plr.Team and plr.Team.Name == "Class - D" then
            local isHostile = char:HasTag("Rogue") or char:FindFirstChildOfClass("Tool") ~= nil
            if not isHostile then
                local inRestricted = false
                if regionUtil then
                    local zone = getSpawnZone(hrp.Position)
                    inRestricted = zone ~= nil and zone ~= "Chaos Insurgency"
                end
                if not inRestricted then return false end
            end
        end
        if regionUtil then
            local ok, inRK = pcall(regionUtil.IsInCustomZone, regionUtil, "RK Zone", char)
            if ok and inRK then return false end
            local ok2, inVent = pcall(regionUtil.IsInCIVent, regionUtil, hrp.Position)
            if ok2 and inVent then return false end
        end
        return true
    end

    local SAUtil = {}

    local visParams = RaycastParams.new()
    visParams.FilterType = Enum.RaycastFilterType.Exclude

    SAUtil.isVisible = function(targetPart)
        local char = lplr.Character
        if not char then return true end
        local origin = Camera.CFrame.Position
        local target = targetPart.Position
        local dir = target - origin
        local dist = dir.Magnitude
        if dist < 0.1 then return true end
        local ignored = {char}
        for _ = 1, 4 do
            visParams.FilterDescendantsInstances = ignored
            local ray = workspace:Raycast(origin, dir, visParams)
            if not ray then return true end
            if ray.Instance:IsDescendantOf(targetPart.Parent) then return true end
            if ray.Distance >= dist then return true end
            if ray.Instance.CanCollide or clientPhasedParts[ray.Instance] then return false end
            table.insert(ignored, ray.Instance)
        end
        return false
    end

    SAUtil.isTargetAlly = function(t)
        if not t or not t.Parent then return false end
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= lplr and p.Character and t:IsDescendantOf(p.Character) then
                if regionUtil then
                    local hrp = p.Character:FindFirstChild("HumanoidRootPart")
                    if hrp then
                        local ok, inVent = pcall(regionUtil.IsInCIVent, regionUtil, hrp.Position)
                        if ok and inVent then return true end
                    end
                end
                if p.Team and p.Team.Name == "Class - D" then
                    local isHostile = p.Character:HasTag("Rogue") or p.Character:FindFirstChildOfClass("Tool") ~= nil
                    if not isHostile then
                        local inRestricted = false
                        if regionUtil then
                            local hrpC = p.Character:FindFirstChild("HumanoidRootPart")
                            if hrpC then
                                local zone = getSpawnZone(hrpC.Position)
                                inRestricted = zone ~= nil and zone ~= "Chaos Insurgency"
                            end
                        end
                        if not inRestricted then return true end
                    end
                end
                return isAlly(p)
            end
        end
        if t.Parent.Name == "Combat AI" then
            local myTeam = lplr.Team
            local npcTeam = t.Parent:GetAttribute("Team")
            if myTeam and npcTeam and npcTeam == myTeam.Name then return true end
        end
        return false
    end

    local INFECTED_TAGS = {"Infected", "008Infected", "SCP008", "Zombie", "008"}

    local function getNearestTarget()
        local root = PlayerUtility.lplrRoot
        if not root then return nil end

        local center = Camera.ViewportSize / 2
        local modeVal = (SAMode and SAMode.Value) or "Mouse"
        local fovVal = (SATargetingFOV and SATargetingFOV.Value) or math.huge
        local maxDistVal = (SAMaxDistance and SAMaxDistance.Value) or math.huge
        local primaryName = (SATargetPart and SATargetPart.Value) or "Head"
        local switchVal = SAPartSwitch and SAPartSwitch.Value
        local switchActive = switchVal and switchVal ~= "Off"
        local partName = (switchActive and (saPartSwitchState and switchVal or primaryName)) or primaryName
        local otherName = switchActive and (saPartSwitchState and primaryName or switchVal) or nil
        local results = {}

        local function addCandidate(pChar)
            local hum = pChar:FindFirstChildOfClass("Humanoid")
            local hrp = pChar:FindFirstChild("HumanoidRootPart")
            if not hum or not hrp or hum.Health <= 0 then return end

            local pickedPart
            if partName == "Random" then
                local parts = {}
                for _, p in ipairs(pChar:GetDescendants()) do
                    if p:IsA("BasePart") then table.insert(parts, p) end
                end
                pickedPart = #parts > 0 and parts[math.random(1, #parts)] or hrp
            else
                local found = pChar:FindFirstChild(partName)
                pickedPart = (found and found:IsA("BasePart") and found) or hrp
            end
            if not pickedPart then return end

            if SAWallCheck.Enabled and not SAUtil.isVisible(pickedPart) then
                if SAWallbang.Enabled then
                    if SAWallbangRegion.Enabled then
                        local wbMax = (SAWallbangDist and SAWallbangDist.Value) or 120
                        if (root.Position - hrp.Position).Magnitude > wbMax then return end
                    end
                else
                    local fallback, bestDist = nil, math.huge
                    for _, p in ipairs(pChar:GetChildren()) do
                        if not p:IsA("BasePart") then continue end
                        if not SAUtil.isVisible(p) then continue end
                        local sp, onSc = Camera:WorldToViewportPoint(p.Position)
                        if not onSc then continue end
                        local d = (Vector2.new(sp.X, sp.Y) - center).Magnitude
                        if d < bestDist then bestDist = d; fallback = p end
                    end
                    if not fallback then return end
                    pickedPart = fallback
                end
            end

            local screenPos, onScreen = Camera:WorldToViewportPoint(pickedPart.Position)
            if not onScreen then return end

            local distance = (root.Position - hrp.Position).Magnitude
            local mouseDist = (Vector2.new(screenPos.X, screenPos.Y) - center).Magnitude

            if modeVal == "Distance" then
                if distance > maxDistVal then return end
            else
                if mouseDist > fovVal then return end
            end

            table.insert(results, {
                part = pickedPart,
                distance = distance,
                mouseDist = mouseDist,
                health = hum.Health,
            })
        end

        for _, plr in ipairs(Players:GetPlayers()) do
            if plr == lplr then continue end
            local pChar = plr.Character
            if not pChar then continue end

            if isAlly(plr) then
                if not SATargetInfected.Enabled then continue end
                local infected = false
                for _, tag in ipairs(INFECTED_TAGS) do
                    if pChar:HasTag(tag) then infected = true break end
                end
                if not infected then
                    infected = pChar:GetAttribute("Infected") or pChar:GetAttribute("SCP008") ~= nil
                end
                if not infected then continue end
            end

            if not canTarget(plr) then continue end

            if scprp.IsRK then
                local ok, isRK = pcall(scprp.IsRK, lplr, plr)
                if ok and isRK then continue end
            end

            addCandidate(pChar)
        end

        if SATargetNPCs.Enabled then
            local playerChars = {}
            for _, p in ipairs(Players:GetPlayers()) do
                if p.Character then playerChars[p.Character] = true end
            end
            local myTeam = lplr.Team

            local function tryNPC(obj)
                if not obj:IsA("Model") then return end
                if playerChars[obj] or obj == lplr.Character then return end
                if obj:HasTag("TutorialImmunity") or obj:HasTag("087Instance") or obj:HasTag("Unauthorized") then return end
                local hrp = obj:FindFirstChild("HumanoidRootPart")
                if not hrp or hrp.Position.Y < -385 then return end
                if obj.Name == "Combat AI" and myTeam then
                    local npcTeam = obj:GetAttribute("Team")
                    if npcTeam and npcTeam == myTeam.Name then return end
                end
                local hum = obj:FindFirstChildOfClass("Humanoid")
                if not hum or hum.Health <= 0 then return end
                local inSCPs = obj.Parent and (obj.Parent.Name == "SCPs"
                    or (obj.Parent.Parent and obj.Parent.Parent.Name == "SCPs"))
                if inSCPs and hum.MaxHealth == 0 and string.sub(obj.Name, 1, 8) ~= "SCP-939-" then return end
                addCandidate(obj)
            end
            for _, obj in ipairs(workspace:GetChildren()) do
                tryNPC(obj)
            end
            local scpFolder = workspace:FindFirstChild("SCPs")
            if scpFolder then
                for _, obj in ipairs(scpFolder:GetChildren()) do
                    tryNPC(obj)
                end
            end
        end

        if #results == 0 then return nil end

        local priorityVal = (SAPriority and SAPriority.Value) or "Closest"
        table.sort(results, function(a, b)
            if priorityVal == "Lowest Health" then return a.health < b.health end
            if modeVal == "Distance" then return a.distance < b.distance end
            return a.mouseDist < b.mouseDist
        end)

        return results[1].part
    end

    SilentAim = GuiLibrary.Registry.combatPanel.API.CreateOptionsButton({
        Name = "SilentAim",
        Function = function(enabled)
            if enabled then
                if Drawing and not saFovCircle then
                    saFovCircle = Drawing.new("Circle")
                    saFovCircle.Color = Color3.new(1, 1, 1)
                    saFovCircle.Thickness = 1.5
                    saFovCircle.Filled = false
                    saFovCircle.NumSides = 64
                    saFovCircle.Visible = false
                end
                if Drawing and not saTargetDot then
                    saTargetDot = Drawing.new("Circle")
                    saTargetDot.Color = Color3.fromRGB(255, 60, 60)
                    saTargetDot.Thickness = 0
                    saTargetDot.Radius = 5
                    saTargetDot.Filled = true
                    saTargetDot.NumSides = 16
                    saTargetDot.Visible = false
                end

                RunLoops:BindToHeartbeat("SilentAimTarget", function()
                    local _equip = lplr.Character and lplr.Character:FindFirstChildOfClass("Tool")
                    local hasGun = _equip and _equip:FindFirstChild("CurrentAmmo") ~= nil
                    target = hasGun and getNearestTarget() or nil

                    if Prediction and SAPrediction.Enabled then
                        findGun()
                        for _, plr in ipairs(Players:GetPlayers()) do
                            if plr ~= lplr and plr.Character then
                                local hrp = plr.Character:FindFirstChild("HumanoidRootPart")
                                if hrp then
                                    if not predTrackers[plr.Character] then
                                        predTrackers[plr.Character] = Prediction.NewTracker(8)
                                    end
                                    Prediction.PushSample(predTrackers[plr.Character], hrp.Position, hrp.AssemblyLinearVelocity)
                                end
                            end
                        end
                    end

                    if saFovCircle then
                        local mouseMode = (SAMode and SAMode.Value) ~= "Distance"
                        saFovCircle.Visible = SAShowFOV.Enabled and mouseMode
                        if saFovCircle.Visible then
                            local vp = Camera.ViewportSize
                            saFovCircle.Position = Vector2.new(vp.X / 2, vp.Y / 2)
                            saFovCircle.Radius = (SATargetingFOV and SATargetingFOV.Value) or 100
                        end
                    end

                    if saTargetDot then
                        saTargetDot.Visible = false
                        local _t = lplr.Character and lplr.Character:FindFirstChildOfClass("Tool")
                        local hasTool = _t and _t:FindFirstChild("CurrentAmmo")
                        if target and SATargetDot.Enabled and hasTool then
                            local sp, onSc = Camera:WorldToViewportPoint(target.Position)
                            if onSc and sp.Z > 0 then
                                saTargetDot.Position = Vector2.new(sp.X, sp.Y)
                                saTargetDot.Visible = true
                            end
                        end
                    end
                end)

                if origCastRay then return end

                task.spawn(function()
                    local t = tick()
                    repeat task.wait(0.5) until controllerEnv.SimulateShot or tick() - t > 30

                    if not controllerEnv.SimulateShot then
                        return
                    end

                    local getUpvals = debug.getupvalues or getupvalues
                    if not getUpvals then
                        return
                    end

                    local ok, upvals = pcall(getUpvals, controllerEnv.SimulateShot)
                    if not ok then return end

                    for _, uv in pairs(upvals) do
                        if type(uv) == "table" and type(uv.Get) == "function" then
                            local got, util = pcall(uv.Get, uv, "Utility")
                            if got and util and type(util) == "table" and type(util.CastRay) == "function" then
                                u12 = util
                                pcall(function()
                                    local ok, ru = pcall(uv.Get, uv, "RegionUtil")
                                    if ok and type(ru) == "table" and type(ru.IsInCustomZone) == "function" then
                                        regionUtil = ru
                                    end
                                end)
                                break
                            end
                        end
                    end

                    if not u12 then
                        return
                    end

                    origCastRay = u12.CastRay
                    u12.CastRay = function(self, origin, direction, ...)
                        local char = lplr.Character
                        local tool = char and char:FindFirstChildOfClass("Tool")
                        local hasTool = tool and tool:FindFirstChild("CurrentAmmo")
                        if SilentAim.Enabled and hasTool and target and direction.Magnitude >= 2000 then
                            if not SAUtil.isTargetAlly(target) then
                                local hitChance = (SAHitChance and SAHitChance.Value) or 100
                                if math.random(100) <= hitChance then
                                    local hitPos = target.Position
                                    if Prediction and SAPrediction.Enabled then
                                        local tracker = predTrackers[target.Parent]
                                        if tracker then
                                            local myHRP = lplr.Character and lplr.Character:FindFirstChild("HumanoidRootPart")
                                            local shooterVel = myHRP and myHRP.AssemblyLinearVelocity or Vector3.zero
                                            local hrp = target.Parent:FindFirstChild("HumanoidRootPart")
                                            local targetVel = hrp and hrp.AssemblyLinearVelocity or Vector3.zero
                                            local autoSpeed = gunData and (
                                                gunData.MuzzleVelocity or gunData.BulletSpeed or
                                                gunData.Speed or gunData.Velocity or gunData.MuzzVelocity
                                            )
                                            local bulletSpeed = autoSpeed or 900
                                            local pred, _ = Prediction.SolveTrajectory(
                                                origin, bulletSpeed, 0, target.Position, targetVel,
                                                workspace.Gravity,
                                                5, nil, nil,
                                                {
                                                    tracker = tracker,
                                                    latency = 0,
                                                    shooterVelocity = shooterVel,
                                                    velocityWeight = 0.78,
                                                    accelWeight = 0.12,
                                                    closeRange = 45,
                                                    closeVelocityDamping = 0.6,
                                                }
                                            )
                                            if pred then
                                                hitPos = pred
                                            end
                                        end
                                    end
                                    local spread = SASpread and SASpread.Value or 0
                                    if spread > 0 then
                                        local shotVec = hitPos - origin
                                        local shotMag = shotVec.Magnitude
                                        if shotMag > 0 then
                                            local fwd = shotVec / shotMag
                                            local arb = math.abs(fwd.Y) < 0.9 and Vector3.new(0,1,0) or Vector3.new(1,0,0)
                                            local right = fwd:Cross(arb).Unit
                                            local up = fwd:Cross(right).Unit
                                            local angle = math.random() * math.pi * 2
                                            local dist = math.sqrt(math.random()) * spread
                                            hitPos = hitPos + right * (math.cos(angle) * dist) + up * (math.sin(angle) * dist)
                                        end
                                    end
                                    return {
                                        Position = hitPos,
                                        Instance = target,
                                        Normal = Vector3.new(0, 1, 0),
                                    }
                                end
                            end
                        end
                        return origCastRay(self, origin, direction, ...)
                    end

                    if controllerEnv.BulletHit and not origBulletHit then
                        origBulletHit = controllerEnv.BulletHit
                        controllerEnv.BulletHit = function(p117, p118, p119, u119, p120)
                            if SilentAim.Enabled then
                                local switchVal = SAPartSwitch and SAPartSwitch.Value
                                if switchVal and switchVal ~= "Off" then
                                    local now = tick()
                                    if now - lastSwitchFlip >= 0.05 then
                                        saPartSwitchState = not saPartSwitchState
                                        lastSwitchFlip = now
                                    end
                                end
                            end
                            if SilentAim.Enabled and SAWallbang.Enabled and target and p118 then
                                local hrp = lplr.Character and lplr.Character:FindFirstChild("HumanoidRootPart")
                                local wbMax = (SAWallbangDist and SAWallbangDist.Value) or 120
                                local dist = hrp and (target.Position - hrp.Position).Magnitude or math.huge
                                local hitInst = p118.Instance
                                local shooterInVent = false
                                if hrp and regionUtil then
                                    local ok, v = pcall(regionUtil.IsInCIVent, regionUtil, hrp.Position)
                                    shooterInVent = ok and v or false
                                end
                                if hitInst and dist <= wbMax then
                                    local parentHum = hitInst.Parent and hitInst.Parent:FindFirstChildOfClass("Humanoid")
                                    if not parentHum then
                                        if not SAUtil.isTargetAlly(target) and not isSpawnKill(target.Parent) and not ownBase() and not shooterInVent then
                                            local fakeHit = {
                                                Instance = target,
                                                Position = target.Position,
                                                Normal = Vector3.new(0, 1, 0),
                                                Material = p118.Material,
                                            }
                                            return origBulletHit(p117, fakeHit, p119, u119, p120)
                                        end
                                    end
                                end
                            end
                            return origBulletHit(p117, p118, p119, u119, p120)
                        end
                    end
                end)
            else
                RunLoops:UnbindFromHeartbeat("SilentAimTarget")
                target = nil
                saPartSwitchState = false
                lastSwitchFlip = 0
                table.clear(predTrackers)
                if saFovCircle then saFovCircle.Visible = false saFovCircle:Remove() saFovCircle = nil end
                if saTargetDot then saTargetDot.Visible = false saTargetDot:Remove() saTargetDot = nil end
                if origCastRay and u12 then
                    u12.CastRay = origCastRay
                    origCastRay = nil
                end
                if origBulletHit and controllerEnv then
                    controllerEnv.BulletHit = origBulletHit
                    origBulletHit = nil
                end
            end
        end
    })
    SATargetPart = SilentAim.CreateDropdown({
        Name = "Part",
        List = {
            "Random",
            "Head",
            "UpperTorso", "LowerTorso",
            "LeftUpperArm", "LeftLowerArm", "LeftHand",
            "RightUpperArm", "RightLowerArm", "RightHand",
            "LeftUpperLeg", "LeftLowerLeg", "LeftFoot",
            "RightUpperLeg", "RightLowerLeg", "RightFoot",
            "HumanoidRootPart",
            "Torso", "Left Arm", "Right Arm", "Left Leg", "Right Leg",
        },
        Default = "HumanoidRootPart"
    })
    SAPartSwitch = SilentAim.CreateDropdown({
        Name = "Switch",
        List = {
            "Off",
            "Head",
            "UpperTorso", "LowerTorso",
            "LeftUpperArm", "LeftLowerArm", "LeftHand",
            "RightUpperArm", "RightLowerArm", "RightHand",
            "LeftUpperLeg", "LeftLowerLeg", "LeftFoot",
            "RightUpperLeg", "RightLowerLeg", "RightFoot",
            "HumanoidRootPart",
            "Torso", "Left Arm", "Right Arm", "Left Leg", "Right Leg"
        },
        Default = "Off"
    })
    SAMode = SilentAim.CreateDropdown({
        Name = "Mode",
        List = {"Mouse", "Distance"},
        Default = "Mouse"
    })
    SAPriority = SilentAim.CreateDropdown({
        Name = "Priority",
        List = {"Closest", "Lowest Health"},
        Default = "Closest"
    })
    SATargetingFOV = SilentAim.CreateSlider({
        Name = "FOV",
        Min = 10,
        Max = 1200,
        Default = 100,
        Round = 1
    })
    SAMaxDistance = SilentAim.CreateSlider({
        Name = "MaxDist",
        Min = 50,
        Max = 5000,
        Default = 1000,
        Round = 1
    })
    SAHitChance = SilentAim.CreateSlider({
        Name = "HitChance",
        Min = 1,
        Max = 100,
        Default = 100,
        Round = 1
    })
    SASpread = SilentAim.CreateSlider({
        Name = "Spread (Legit)",
        Min = 0,
        Max = 5,
        Default = 0,
        Round = 0
    })
    SAPrediction = SilentAim.CreateToggle({
        Name = "Prediction",
        Default = false
    })
    SAWallCheck = SilentAim.CreateToggle({
        Name = "WallCheck",
        Default = true
    })
    SAWallbang = SilentAim.CreateToggle({
        Name = "Wallbang",
        Default = false
    })
    SAWallbangRegion = SilentAim.CreateToggle({
        Name = "RegionCheck",
        Default = true,
    })
    SAWallbangDist = SilentAim.CreateSlider({
        Name = "WallbangDist",
        Min = 10,
        Max = 400,
        Default = 120,
        Round = 1,
    })
    SATeamCheck = SilentAim.CreateToggle({
        Name = "TeamCheck",
        Default = true
    })
    SAShowFOV = SilentAim.CreateToggle({
        Name = "FovCircle",
        Default = true
    })
    SATargetDot = SilentAim.CreateToggle({
        Name = "TargetDot",
        Default = true
    })
    SATargetNPCs = SilentAim.CreateToggle({
        Name = "NPCs",
        Default = false
    })
    SATargetInfected = SilentAim.CreateToggle({
        Name = "Infected",
        Default = true
    })
    saShared.wallbang = SAWallbang
    saShared.wallbangDist = SAWallbangDist
    SAMode:ShowWhen("Mouse", SATargetingFOV)
    SAMode:ShowWhen("Distance", SAMaxDistance)
    SAMode:ShowWhen("Mouse", SAShowFOV)
    SAWallbang:AddDependent(SAWallbangDist)
    SAWallbang:AddDependent(SAWallbangRegion)
end)

runcode(function()
    local AutoSkipTutorial = {}
    local skipConn = nil
    local pollActive = false
    local doNext = nil

    local function applySkip()
        pcall(function()
            if shared.LockerTutorial then
                shared.LockerTutorial.Active = false
                shared.LockerTutorial.Step = 999
            end
        end)
        pcall(function()
            local tb = ReplicatedStorage:FindFirstChild("TutorialBind")
            if tb and tb:IsA("ValueBase") then tb.Value = false end
        end)
        pcall(function()
            for k, v in pairs(shared) do
                local kl = tostring(k):lower()
                if kl:find("tutorial") or kl:find("locker") then
                    if type(v) == "table" then
                        if v.Active ~= nil then v.Active = false end
                        if v.Step ~= nil then v.Step = 999 end
                        if v.Enabled ~= nil then v.Enabled = false end
                    elseif type(v) == "boolean" then
                        pcall(function() shared[k] = false end)
                    end
                end
            end
        end)
        pcall(function()
            for k, v in pairs(controllerEnv) do
                local kl = tostring(k):lower()
                if kl:find("tutorial") or kl:find("locker") then
                    if type(v) == "boolean" then controllerEnv[k] = false end
                    if type(v) == "number" then controllerEnv[k] = 999 end
                end
            end
        end)
    end

    AutoSkipTutorial = GuiLibrary.Registry.utillityPanel.API.CreateOptionsButton({
        Name = "AutoSkipTutorial",
        Function = function(enabled)
            if enabled then
                applySkip()
                task.spawn(function()
                    local function findBind()
                        if getinstances then
                            for _, v in ipairs(getinstances()) do
                                if v.ClassName == "BindableEvent" and v.Name == "TutorialBind" then return v end
                            end
                        end
                        for _, v in ipairs(ReplicatedStorage:GetDescendants()) do
                            if v:IsA("BindableEvent") and v.Name == "TutorialBind" then return v end
                        end
                        local direct = ReplicatedStorage:FindFirstChild("TutorialBind")
                        if direct and direct:IsA("BindableEvent") then return direct end
                    end

                    local bind
                    for _ = 1, 5 do
                        bind = findBind()
                        if bind then break end
                        task.wait(3)
                    end
                    if not bind then return end

                    task.wait(0.5)

                    local u2 = nil
                    if getconnections then
                        local getUpvals = debug.getupvalues or getupvalues
                        if getUpvals then
                            for _, c in ipairs(getconnections(bind.Event)) do
                                if not c.Function then continue end
                                local ok, upvals = pcall(getUpvals, c.Function)
                                if not ok then continue end
                                for _, uv in pairs(upvals) do
                                    if type(uv) == "table"
                                        and type(uv.Fire) == "function"
                                        and uv.Event ~= nil
                                        and uv ~= bind
                                    then
                                        u2 = uv
                                        break
                                    end
                                end
                                if u2 then break end
                            end
                        end
                    end

                    doNext = function()
                        if u2 then
                            pcall(u2.Fire, u2, "Next")
                        else
                            pcall(bind.Fire, bind, "Next")
                        end
                    end

                    skipConn = bind.Event:Connect(function(msg)
                        if msg == "Create" then
                            task.delay(0.15, doNext)
                        end
                    end)

                    local lt = shared.LockerTutorial
                    if lt and lt.Active then
                        task.delay(0.2, doNext)
                    end
                end)

                pollActive = true
                local lastStep = nil
                RunLoops:BindToHeartbeat("TutorialSkipPoll", function()
                    if not pollActive then return end
                    pcall(function()
                        local lt = shared.LockerTutorial
                        if lt and lt.Active then
                            applySkip()
                            if doNext and lt.Step ~= lastStep then
                                lastStep = lt.Step
                                task.delay(0.15, doNext)
                            end
                        else
                            lastStep = nil
                        end
                    end)
                end)

                UI.toast("Auto Skip Tutorial", "Tutorial bypassed", 2)
            else
                pollActive = false
                doNext = nil
                RunLoops:UnbindFromHeartbeat("TutorialSkipPoll")
                if skipConn then skipConn:Disconnect() skipConn = nil end
            end
        end
    })
end)

runcode(function()
    local AutoDoors = {}
    local ADRadius = {}
    local ADCooldown = {}

    local doorCooldowns = {}

    AutoDoors = GuiLibrary.Registry.utillityPanel.API.CreateOptionsButton({
        Name = "AutoDoors",
        Function = function(enabled)
            if enabled then
                RunLoops:BindToHeartbeat("AutoDoors", function()
                    if not Net.isReady() then return end
                    local char = lplr.Character
                    local hrp = char and char:FindFirstChild("HumanoidRootPart")
                    if not hrp then return end
                    local radius = (ADRadius and ADRadius.Value) or 8
                    local cdTime = (ADCooldown and ADCooldown.Value) or 2
                    local now = tick()
                    local pos = hrp.Position
                    local CS = game:GetService("CollectionService")
                    for _, door in ipairs(CS:GetTagged("Interaction")) do
                        local scanners = door:FindFirstChild("Scanners")
                        local closest = math.huge
                        if scanners then
                            for _, part in ipairs(scanners:GetDescendants()) do
                                if part:IsA("BasePart") then
                                    local d = (pos - part.Position).Magnitude
                                    if d < closest then closest = d end
                                end
                            end
                        else
                            local bp = door:FindFirstChildWhichIsA("BasePart")
                            if bp then closest = (pos - bp.Position).Magnitude end
                        end
                        if closest > radius then continue end
                        local last = doorCooldowns[door] or 0
                        if now - last < cdTime then continue end
                        doorCooldowns[door] = now
                        local target = door:GetAttribute("Allowed") and door or (door.Parent and door.Parent:GetAttribute("Allowed") and door.Parent) or door
                        Net.FireInteract(target)
                    end
                end)
            else
                RunLoops:UnbindFromHeartbeat("AutoDoors")
                doorCooldowns = {}
            end
        end
    })

    ADRadius = AutoDoors.CreateSlider({
        Name = "Radius",
        Min = 3,
        Max = 12,
        Default = 8,
        Round = 1
    })
    ADCooldown = AutoDoors.CreateSlider({
        Name = "Cooldown",
        Min = 0,
        Max = 10,
        Default = 2,
        Round = 1
    })
end)

runcode(function()
    local StaffDetector = {}
    local knownStaff = {}
    local sdConns = {}
    local lastSDScan = 0
    local CS = game:GetService("CollectionService")
    local STAFF_KW = {"staff", "mod", "admin", "moderator", "srmod"}

    local StaffUtil = {}

    StaffUtil.hasKW = function(str)
        local s = string.lower(tostring(str))
        for _, kw in ipairs(STAFF_KW) do
            if s:find(kw, 1, true) then return true end
        end
        return false
    end

    StaffUtil.getStaffLabel = function(attrRank)
        if attrRank >= 253 then return "Dev"
        elseif attrRank >= 249 then return "Mod"
        elseif attrRank >= 248 then return "Staff"
        end
        return nil
    end

    StaffUtil.detectStaff = function(plr)
        local attrRank = plr:GetAttribute("GroupRank") or 0
        local lbl = StaffUtil.getStaffLabel(attrRank)
        if lbl then return lbl, "GroupRank:" .. attrRank end

        for _, tag in ipairs(CS:GetTags(plr)) do
            if StaffUtil.hasKW(tag) then return "Staff", "PlayerTag:" .. tag end
        end

        if plr.Character then
            for _, tag in ipairs(CS:GetTags(plr.Character)) do
                if StaffUtil.hasKW(tag) then return "Staff", "CharTag:" .. tag end
            end
        end

        if plr.Character then
            local hrp = plr.Character:FindFirstChild("HumanoidRootPart")
            if hrp then
                for _, d in ipairs(hrp:GetDescendants()) do
                    if (d:IsA("TextLabel") or d:IsA("TextButton")) and StaffUtil.hasKW(d.Text) then
                        return "Staff", "OverheadGUI:" .. d.Text
                    end
                end
            end
        end

        return nil
    end

    StaffUtil.checkPlayer = function(plr)
        if plr == lplr then return end
        local lbl, method = StaffUtil.detectStaff(plr)
        if lbl and not knownStaff[plr] then
            knownStaff[plr] = lbl
            detectedMods[plr] = lbl
            GameData.data.detectedStaff = detectedMods
            if GameData.changed then GameData.changed("detectedStaff", detectedMods) end
            local team = plr.Team and plr.Team.Name or "No Team"
            UI.toast("Staff Detected", "[" .. lbl .. "] " .. plr.Name .. " - " .. team .. " (" .. method .. ")", 20)
        end
    end

    StaffDetector = GuiLibrary.Registry.utillityPanel.API.CreateOptionsButton({
        Name = "StaffDetector",
        Function = function(enabled)
            if enabled then
                knownStaff = {}

                local function watchPlayer(plr)
                    task.spawn(StaffUtil.checkPlayer, plr)
                    table.insert(sdConns, plr.CharacterAdded:Connect(function()
                        task.spawn(StaffUtil.checkPlayer, plr)
                    end))
                    table.insert(sdConns, plr:GetAttributeChangedSignal("GroupRank"):Connect(function()
                        task.spawn(StaffUtil.checkPlayer, plr)
                    end))
                end

                for _, plr in ipairs(Players:GetPlayers()) do
                    watchPlayer(plr)
                end

                table.insert(sdConns, Players.PlayerAdded:Connect(function(plr)
                    watchPlayer(plr)
                end))
                table.insert(sdConns, Players.PlayerRemoving:Connect(function(plr)
                    knownStaff[plr] = nil
                    detectedMods[plr] = nil
                end))

                RunLoops:BindToHeartbeat("StaffDetector", function()
                    local now = tick()
                    if now - lastSDScan < 1 then return end
                    lastSDScan = now
                    for _, plr in ipairs(Players:GetPlayers()) do
                        task.spawn(StaffUtil.checkPlayer, plr)
                    end
                end)
            else
                for _, c in ipairs(sdConns) do if c then c:Disconnect() end end
                table.clear(sdConns)
                RunLoops:UnbindFromHeartbeat("StaffDetector")
                knownStaff = {}
                table.clear(detectedMods)
            end
        end
    })
end)

runcode(function()
    local PlayerESP = {}
    local ESPColor = {}
    local ESPThickness = {}
    local ESPMaxDist = {}
    local ESPShowName = {}
    local ESPShowDist = {}
    local ESPShowHP = {}
    local ESPShowDead = {}
    local ESPTeamCheck = {}
    local ESPWallCheck = {}
    local ESPNPCs = {}
    local ESPSCPs = {}
    local ESPBoxScale = {}
    local ESPIconSize = {}

    local COLOR_FNS = {
        ["Team Color"] = function(plr) return plr.TeamColor.Color end,
        ["White"] = function() return Color3.new(1, 1, 1) end,
        ["Red"] = function() return Color3.fromRGB(255, 50, 50) end,
        ["Blue"] = function() return Color3.fromRGB(50, 130, 255) end,
        ["Green"] = function() return Color3.fromRGB(50, 220, 50) end,
    }

    local espDrawings = {}
    local npcDrawings = {}
    local scpDrawings = {}
    local scpIconLabels = {}
    local scpIconHbConn = nil
    local espConns = {}
    local lastNpcScan = 0
    local ESPSCPIcons = {}

    local SCP_ICONS = {
        ["SCP-096"] = "rbxassetid://18331642946",
        ["SCP-076"] = "rbxassetid://135999022506930",
        ["SCP-066"] = "rbxassetid://137393076938781",
        ["SCP-023"] = "rbxassetid://113724456710159",
        ["SCP-173"] = "rbxassetid://18331648041",
        ["SCP-106"] = "rbxassetid://96544176625498",
        ["SCP-016"] = "rbxassetid://134750178929271",
        ["SCP-002"] = "rbxassetid://18331611642",
        ["SCP-093"] = "rbxassetid://121237674708895",
        ["SCP-2950"] = "rbxassetid://18331673441",
        ["SCP-049"] = "rbxassetid://18331626830",
        ["SCP-1299"] = "rbxassetid://112013851167938",
        ["SCP-1025"] = "rbxassetid://18331668905",
        ["SCP-079"] = "rbxassetid://18331632480",
        ["SCP-966"] = "rbxassetid://18331661155",
        ["SCP-008"] = "rbxassetid://18331618967",
        ["SCP-131"] = "rbxassetid://18331645478",
        ["SCP-457"] = "rbxassetid://18331657938",
        ["SCP-938"] = "rbxassetid://82048297498607",
        ["SCP-939"] = "rbxassetid://121290404504761",
        ["SCP-409"] = "rbxassetid://18331650869",
        ["SCP-316"] = "rbxassetid://98373350749130",
        ["SCP-299"] = "rbxassetid://130395557822524",
        ["SCP-087"] = "rbxassetid://18331635059",
        ["SCP-999"] = "rbxassetid://18331665908",
    }
    pcall(function()
        local cb = scprp.Clipboard
        if cb and cb.SCPs then
            for num, data in pairs(cb.SCPs) do
                if data.Icon then
                    SCP_ICONS["SCP-" .. num] = data.Icon
                end
            end
        end
    end)
    local espWcParams = RaycastParams.new()
    espWcParams.FilterType = Enum.RaycastFilterType.Exclude

    local function newEntry()
        local function ln()
            local l = Drawing.new("Line")
            l.Visible = false; l.Thickness = 1; l.ZIndex = 2
            return l
        end
        local lbl = Drawing.new("Text")
        lbl.Visible = false; lbl.Size = 13; lbl.Outline = true
        lbl.Center = true; lbl.Font = Drawing.Fonts.UI; lbl.ZIndex = 3
        local hbg = Drawing.new("Line")
        hbg.Visible = false; hbg.Thickness = 3
        hbg.Color = Color3.new(0,0,0); hbg.ZIndex = 2
        local hfg = Drawing.new("Line")
        hfg.Visible = false; hfg.Thickness = 2; hfg.ZIndex = 3
        return { ln(), ln(), ln(), ln(), lbl, hbg, hfg }
    end

    local function hideEntry(e)
        if not e then return end
        for _, d in ipairs(e) do d.Visible = false end
    end

    local function freeEntry(plr)
        local e = espDrawings[plr]
        if not e then return end
        for _, d in ipairs(e) do d:Remove() end
        espDrawings[plr] = nil
    end

    local function disconnectESP()
        for _, c in ipairs(espConns) do
            if c and c.Disconnect then c:Disconnect() end
        end
        table.clear(espConns)
    end

    PlayerESP = GuiLibrary.Registry.renderPanel.API.CreateOptionsButton({
        Name = "ESP",
        Function = function(enabled)
            if enabled then
                for _, plr in ipairs(Players:GetPlayers()) do
                    if plr ~= lplr then espDrawings[plr] = newEntry() end
                end
                table.insert(espConns, Players.PlayerAdded:Connect(function(plr)
                    if plr ~= lplr then espDrawings[plr] = newEntry() end
                end))
                table.insert(espConns, Players.PlayerRemoving:Connect(freeEntry))

                local function trySCPModel(obj)
                    if not obj:IsA("Model") then return end
                    if not obj:FindFirstChildOfClass("Humanoid") then return end
                    if not obj:FindFirstChild("HumanoidRootPart") then return end
                    if scpDrawings[obj] then return end
                    scpDrawings[obj] = newEntry()
                    local function lookupIcon(name)
                        return SCP_ICONS[name] or SCP_ICONS[name:match("(SCP%-%d+)") or ""]
                    end
                    local iconId = lookupIcon(obj.Name)
                        or (obj.Parent and lookupIcon(obj.Parent.Name))
                        or (obj.Parent and obj.Parent.Parent and lookupIcon(obj.Parent.Parent.Name))
                    if iconId then
                        local hrpRef = obj:FindFirstChild("HumanoidRootPart")
                        if hrpRef then
                            local headPart = obj:FindFirstChild("Head")
                            local yOff
                            if headPart and headPart:IsA("BasePart") then
                                yOff = (headPart.Position.Y + headPart.Size.Y / 2) - hrpRef.Position.Y + 1.8
                            else
                                yOff = 5
                            end
                            local bb = Instance.new("BillboardGui")
                            bb.Name = "SCPIcon"
                            bb.AlwaysOnTop = true
                            bb.Size = UDim2.new(0, 20, 0, 20)
                            bb.StudsOffset = Vector3.new(0, yOff, 0)
                            bb.MaxDistance = 0
                            bb.Enabled = false
                            bb.Parent = hrpRef
                            local img = Instance.new("ImageLabel")
                            img.BackgroundTransparency = 1
                            img.Image = iconId
                            img.Size = UDim2.new(1, 0, 1, 0)
                            img.ScaleType = Enum.ScaleType.Fit
                            img.Parent = bb
                            scpIconLabels[obj] = bb
                        end
                    end
                end

                local function setupSCPWatcher(sf)
                    local function processDesc(desc)
                        if desc:IsA("Model") then
                            pcall(trySCPModel, desc)
                        elseif desc.Parent and desc.Parent:IsA("Model") then
                            pcall(trySCPModel, desc.Parent)
                        end
                    end
                    for _, child in ipairs(sf:GetChildren()) do
                        pcall(trySCPModel, child)
                        for _, desc in ipairs(child:GetDescendants()) do
                            processDesc(desc)
                        end
                    end
                    table.insert(espConns, sf.ChildAdded:Connect(function(child)
                        pcall(trySCPModel, child)
                    end))
                    table.insert(espConns, sf.DescendantAdded:Connect(processDesc))
                end

                local _scpFolderNow = workspace:FindFirstChild("SCPs")
                if _scpFolderNow then
                    setupSCPWatcher(_scpFolderNow)
                end
                table.insert(espConns, workspace.ChildAdded:Connect(function(child)
                    if child.Name == "SCPs" then
                        setupSCPWatcher(child)
                    end
                end))

                game:GetService("RunService"):BindToRenderStep("PhantomPlayerESP", Enum.RenderPriority.Camera.Value + 1, function()
                    local cam = workspace.CurrentCamera
                    local myHRP = lplr.Character and lplr.Character:FindFirstChild("HumanoidRootPart")
                    local maxD = (ESPMaxDist and ESPMaxDist.Value) or 5000
                    local thick = (ESPThickness and ESPThickness.Value) or 1
                    local cfn = COLOR_FNS[(ESPColor and ESPColor.Value) or "Team Color"]
                                   or COLOR_FNS["Team Color"]

                    for _, plr in ipairs(Players:GetPlayers()) do
                        if plr == lplr then continue end
                        local e = espDrawings[plr]
                        if not e then continue end
                        if not plr.Parent then hideEntry(e) continue end
                        if ESPTeamCheck.Enabled and isAlly(plr) and not detectedMods[plr] then hideEntry(e) continue end

                        local char = plr.Character
                        local hum = char and char:FindFirstChildOfClass("Humanoid")
                        local hrp = char and char:FindFirstChild("HumanoidRootPart")
                        if not char or not hum or not hrp then hideEntry(e) continue end
                        if not ESPShowDead.Enabled and hum.Health <= 0 then hideEntry(e) continue end
                        if myHRP and (myHRP.Position - hrp.Position).Magnitude > maxD then
                            hideEntry(e) continue
                        end

                        if ESPWallCheck.Enabled and myHRP then
                            local wcDir = hrp.Position - myHRP.Position
                            local wcIgnored = {lplr.Character, char}
                            local wcBlocked = false
                            for _ = 1, 8 do
                                espWcParams.FilterDescendantsInstances = wcIgnored
                                local ray = workspace:Raycast(myHRP.Position, wcDir * 0.99, espWcParams)
                                if not ray then break end
                                if ray.Instance.CanCollide then wcBlocked = true break end
                                table.insert(wcIgnored, ray.Instance)
                            end
                            if wcBlocked then hideEntry(e) continue end
                        end

                        local hipH = math.max(hum.HipHeight, 0.5)
                        local head = char:FindFirstChild("Head")
                        if head and not head:IsA("BasePart") then head = nil end
                        local topWorld = head
                            and (head.Position + Vector3.new(0, head.Size.Y * 0.5 + 0.1, 0))
                            or (hrp.Position + Vector3.new(0, hipH * 1.55 + 0.4, 0))
                        local botWorld = hrp.Position - Vector3.new(0, hipH + 1.0, 0)
                        local topSP, vis = cam:WorldToViewportPoint(topWorld)
                        local botSP = cam:WorldToViewportPoint(botWorld)
                        local hrpSP = cam:WorldToViewportPoint(hrp.Position)
                        if topSP.Z <= 0 then hideEntry(e) continue end

                        local espScale = ((ESPBoxScale and ESPBoxScale.Value) or 100) / 100
                        local midY = (topSP.Y + botSP.Y) / 2
                        local bh = math.max(math.abs(botSP.Y - topSP.Y), 8) * espScale
                        local bw = bh * 0.45
                        local cx = hrpSP.X
                        local x1, x2 = cx - bw/2, cx + bw/2
                        local y1, y2 = midY - bh/2, midY + bh/2
                        local col = cfn(plr)

                        local function setLn(ln, fx, fy, tx, ty)
                            ln.From = Vector2.new(fx, fy)
                            ln.To = Vector2.new(tx, ty)
                            ln.Color = col; ln.Thickness = thick; ln.Visible = true
                        end
                        setLn(e[1], x1, y1, x2, y1)
                        setLn(e[2], x1, y2, x2, y2)
                        setLn(e[3], x1, y1, x1, y2)
                        setLn(e[4], x2, y1, x2, y2)

                        local lbl = e[5]
                        local espModLbl = detectedMods[plr]
                        if ESPShowName.Enabled then
                            local nm = plr.DisplayName ~= "" and plr.DisplayName or plr.Name
                            if ESPShowDist.Enabled and myHRP then
                                nm = nm .. " [" .. math.floor(
                                    (myHRP.Position - hrp.Position).Magnitude) .. "m]"
                            end
                            if saShared.wallbang and saShared.wallbang.Enabled and myHRP then
                                local wbMax = (saShared.wallbangDist and saShared.wallbangDist.Value) or 120
                                if (myHRP.Position - hrp.Position).Magnitude <= wbMax then
                                    nm = nm .. " [WB]"
                                end
                            end
                            if espModLbl then
                                nm = "[" .. string.upper(espModLbl) .. "] " .. nm
                            end
                            lbl.Text = nm
                            lbl.Color = espModLbl and Color3.fromRGB(255, 80, 80) or col
                            lbl.Position = Vector2.new(cx, y1 - 15)
                            lbl.Visible = true
                        else
                            lbl.Visible = false
                        end

                        if ESPShowHP.Enabled then
                            local pct = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
                            local hCol = Color3.fromHSV(pct / 3, 0.85, 0.9)
                            local bx = x1 - 4
                            e[6].From = Vector2.new(bx, y1); e[6].To = Vector2.new(bx, y2)
                            e[6].Visible = true
                            e[7].From = Vector2.new(bx, y2)
                            e[7].To = Vector2.new(bx, y2 - bh * pct)
                            e[7].Color = hCol; e[7].Visible = true
                        else
                            e[6].Visible = false; e[7].Visible = false
                        end
                    end

                    local anyEntity = ESPNPCs.Enabled or ESPSCPs.Enabled
                    if anyEntity then
                        local now = tick()
                        local playerChars = {}
                        for _, p in ipairs(Players:GetPlayers()) do
                            if p.Character then playerChars[p.Character] = true end
                        end
                        local scpFolder = workspace:FindFirstChild("SCPs")

                        if now - lastNpcScan >= 0.5 then
                            lastNpcScan = now
                            local currentNPCs = {}
                            for _, obj in ipairs(workspace:GetChildren()) do
                                if not obj:IsA("Model") then continue end
                                if playerChars[obj] or obj == lplr.Character then continue end
                                if scpFolder and (obj == scpFolder or obj:IsDescendantOf(scpFolder)) then continue end
                                if not obj:FindFirstChildOfClass("Humanoid") then continue end
                                if not obj:FindFirstChild("HumanoidRootPart") then continue end
                                currentNPCs[obj] = true
                                if not npcDrawings[obj] then npcDrawings[obj] = newEntry() end
                            end
                            for model, e in pairs(npcDrawings) do
                                if not currentNPCs[model] then
                                    for _, d in ipairs(e) do d:Remove() end
                                    npcDrawings[model] = nil
                                end
                            end
                            for model, e in pairs(scpDrawings) do
                                if not model.Parent then
                                    for _, d in ipairs(e) do d:Remove() end
                                    scpDrawings[model] = nil
                                    if scpIconLabels[model] then
                                        scpIconLabels[model]:Destroy()
                                        scpIconLabels[model] = nil
                                    end
                                end
                            end
                        end

                        local function renderEntityESP(drawings, col, enabled, iconTable, showIcons)
                            if enabled then
                                for model, e in pairs(drawings) do
                                    pcall(function()
                                        if not model.Parent then
                                            hideEntry(e)
                                            if iconTable and iconTable[model] then iconTable[model].Enabled = false end
                                            return
                                        end
                                        local hrp2 = model:FindFirstChild("HumanoidRootPart")
                                        local hum2 = model:FindFirstChildOfClass("Humanoid")
                                        local isImmortal = hum2 and hum2.MaxHealth == 0
                                        if not hrp2 or not hum2 or (not ESPShowDead.Enabled and hum2.Health <= 0 and not isImmortal) then
                                            hideEntry(e)
                                            if iconTable and iconTable[model] then iconTable[model].Enabled = false end
                                            return
                                        end
                                        if myHRP and (myHRP.Position - hrp2.Position).Magnitude > maxD then
                                            hideEntry(e)
                                            if iconTable and iconTable[model] then iconTable[model].Enabled = showIcons end
                                            return
                                        end
                                        if ESPWallCheck.Enabled and myHRP then
                                            local wcDir2 = hrp2.Position - myHRP.Position
                                            local wcIgnored2 = {lplr.Character, model}
                                            local wcBlocked2 = false
                                            for _ = 1, 8 do
                                                espWcParams.FilterDescendantsInstances = wcIgnored2
                                                local ray2 = workspace:Raycast(myHRP.Position, wcDir2 * 0.99, espWcParams)
                                                if not ray2 then break end
                                                if ray2.Instance.CanCollide then wcBlocked2 = true break end
                                                table.insert(wcIgnored2, ray2.Instance)
                                            end
                                            if wcBlocked2 then
                                                hideEntry(e)
                                                if iconTable and iconTable[model] then iconTable[model].Enabled = false end
                                                return
                                            end
                                        end
                                        local hipH2 = math.max(hum2.HipHeight, 0.5)
                                        local head2 = model:FindFirstChild("Head")
                                        if head2 and not head2:IsA("BasePart") then head2 = nil end
                                        local topW2 = head2 and (head2.Position + Vector3.new(0, head2.Size.Y * 0.5 + 0.1, 0))
                                                    or (hrp2.Position + Vector3.new(0, hipH2 * 1.55 + 0.4, 0))
                                        local botW2 = hrp2.Position - Vector3.new(0, hipH2 + 1.0, 0)
                                        local tsp2, vis2 = cam:WorldToViewportPoint(topW2)
                                        local bsp2 = cam:WorldToViewportPoint(botW2)
                                        local hrpsp2 = cam:WorldToViewportPoint(hrp2.Position)
                                        if not vis2 or tsp2.Z <= 0 then
                                            hideEntry(e)
                                            if iconTable and iconTable[model] then iconTable[model].Enabled = showIcons end
                                            return
                                        end
                                        local espScale2 = ((ESPBoxScale and ESPBoxScale.Value) or 100) / 100
                                        local midY2 = (tsp2.Y + bsp2.Y) / 2
                                        local bh2 = math.max(math.abs(bsp2.Y - tsp2.Y), 8) * espScale2
                                        local bw2 = bh2 * 0.45
                                        local cx2 = hrpsp2.X
                                        local nx1, nx2 = cx2 - bw2/2, cx2 + bw2/2
                                        local ny1, ny2 = midY2 - bh2/2, midY2 + bh2/2
                                        e[1].From = Vector2.new(nx1, ny1); e[1].To = Vector2.new(nx2, ny1); e[1].Color = col; e[1].Thickness = thick; e[1].Visible = true
                                        e[2].From = Vector2.new(nx1, ny2); e[2].To = Vector2.new(nx2, ny2); e[2].Color = col; e[2].Thickness = thick; e[2].Visible = true
                                        e[3].From = Vector2.new(nx1, ny1); e[3].To = Vector2.new(nx1, ny2); e[3].Color = col; e[3].Thickness = thick; e[3].Visible = true
                                        e[4].From = Vector2.new(nx2, ny1); e[4].To = Vector2.new(nx2, ny2); e[4].Color = col; e[4].Thickness = thick; e[4].Visible = true
                                        e[5].Text = model.Name; e[5].Color = col
                                        e[5].Position = Vector2.new(cx2, ny1 - 11)
                                        e[5].Visible = true
                                        if ESPShowHP.Enabled then
                                            local pct2 = math.clamp(hum2.Health / math.max(hum2.MaxHealth, 1), 0, 1)
                                            local hCol2 = Color3.fromHSV(pct2 / 3, 0.85, 0.9)
                                            local bx2 = nx1 - 4
                                            e[6].From = Vector2.new(bx2, ny1); e[6].To = Vector2.new(bx2, ny2); e[6].Visible = true
                                            e[7].From = Vector2.new(bx2, ny2); e[7].To = Vector2.new(bx2, ny2 - bh2 * pct2)
                                            e[7].Color = hCol2; e[7].Visible = true
                                        else
                                            e[6].Visible = false; e[7].Visible = false
                                        end
                                        if iconTable and iconTable[model] then
                                            if showIcons then
                                                local depth = hrpsp2.Z
                                                if depth > 0 then
                                                    local studsPerPx = depth * math.tan(math.rad(cam.FieldOfView * 0.5)) / (cam.ViewportSize.Y * 0.5)
                                                    local targetY = ny1 - 22
                                                    local deltaStuds = (hrpsp2.Y - targetY) * studsPerPx
                                                    iconTable[model].StudsOffset = Vector3.new(0, math.max(deltaStuds, 0.1), 0)
                                                end
                                                local iSz = (ESPIconSize and ESPIconSize.Value) or 20
                                                iconTable[model].Size = UDim2.new(0, iSz, 0, iSz)
                                                iconTable[model].Enabled = true
                                            else
                                                iconTable[model].Enabled = false
                                            end
                                        end
                                    end)
                                end
                            else
                                for model, e in pairs(drawings) do
                                    pcall(function()
                                        hideEntry(e)
                                        if iconTable and iconTable[model] then iconTable[model].Enabled = false end
                                    end)
                                end
                            end
                        end

                        renderEntityESP(npcDrawings, Color3.fromRGB(255, 140, 0), ESPNPCs.Enabled)
                        renderEntityESP(scpDrawings, Color3.fromRGB(255, 50, 50), ESPSCPs.Enabled, scpIconLabels, ESPSCPs.Enabled and ESPSCPIcons.Enabled)

                    else
                        for _, e in pairs(npcDrawings) do hideEntry(e) end
                        for model, e in pairs(scpDrawings) do
                            pcall(function()
                                hideEntry(e)
                                if scpIconLabels[model] then scpIconLabels[model].Enabled = false end
                            end)
                        end
                    end
                end)
            else
                game:GetService("RunService"):UnbindFromRenderStep("PhantomPlayerESP")
                disconnectESP()
                for plr in pairs(espDrawings) do freeEntry(plr) end
                for _, e in pairs(npcDrawings) do for _, d in ipairs(e) do d:Remove() end end
                npcDrawings = {}
                for _, e in pairs(scpDrawings) do for _, d in ipairs(e) do d:Remove() end end
                scpDrawings = {}
                for _, bb in pairs(scpIconLabels) do pcall(function() bb:Destroy() end) end
                scpIconLabels = {}
            end
        end
    })

    ESPColor = PlayerESP.CreateDropdown({
        Name = "Color",
        List = {"Team Color", "White", "Red", "Blue", "Green"},
        Default = "Team Color"
    })
    ESPThickness = PlayerESP.CreateSlider({
        Name = "Thickness",
        Min = 1,
        Max = 4,
        Default = 1,
        Round = 1
    })
    ESPMaxDist = PlayerESP.CreateSlider({
        Name = "MaxDist",
        Min = 50,
        Max = 5000,
        Default = 5000,
        Round = 1
    })
    ESPBoxScale = PlayerESP.CreateSlider({
        Name = "BoxScale",
        Min = 50,
        Max = 300,
        Default = 100,
        Round = 1
    })
    ESPShowName = PlayerESP.CreateToggle({
        Name = "Name",
        Default = true
    })
    ESPShowDist = PlayerESP.CreateToggle({
        Name = "Distance",
        Default = true
    })
    ESPShowHP = PlayerESP.CreateToggle({
        Name = "HpBar",
        Default = true
    })
    ESPShowDead = PlayerESP.CreateToggle({
        Name = "Dead",
        Default = false
    })
    ESPTeamCheck = PlayerESP.CreateToggle({
        Name = "TeamCheck",
        Default = true
    })
    ESPWallCheck = PlayerESP.CreateToggle({
        Name = "WallCheck",
        Default = false
    })
    ESPNPCs = PlayerESP.CreateToggle({
        Name = "NPCs",
        Default = false
    })
    ESPSCPs = PlayerESP.CreateToggle({
        Name = "SCPs",
        Default = false
    })
    ESPSCPIcons = PlayerESP.CreateToggle({
        Name = "ScpIcons",
        Default = true
    })
    ESPIconSize = PlayerESP.CreateSlider({
        Name = "IconSize",
        Min = 8,
        Max = 64,
        Default = 20,
        Round = 1
    })
    ESPSCPs:AddDependent(ESPSCPIcons)
    ESPSCPIcons:AddDependent(ESPIconSize)
end)

runcode(function()
    local Nametags = {}
    local ShowDisplayName = {}
    local ShowTeam = {}
    local ShowDistance = {}
    local ShowHealth = {}
    local ShowBrackets = {}
    local ShowStaffRank = {}
    local TagBg = {}
    local TagBgCorner = {}
    local FontChoice = {}
    local BoldWeight = {}
    local TextSize = {}
    local NTTeamCheck = {}
    local NTSCPs = {}
    local NTSCPIcons = {}
    local NTIconSize = {}
    local NTScale = {}

    local tags = {}
    local scpTags = {}
    local cleanupConns = {}
    local ntScpIconLabels = {}
    local ntScpScanTick = 0
    local nameTagGui = nil

    local NT_SCP_ICONS = {
        ["SCP-096"] = "rbxassetid://18331642946",
        ["SCP-076"] = "rbxassetid://135999022506930",
        ["SCP-066"] = "rbxassetid://137393076938781",
        ["SCP-023"] = "rbxassetid://113724456710159",
        ["SCP-173"] = "rbxassetid://18331648041",
        ["SCP-106"] = "rbxassetid://96544176625498",
        ["SCP-016"] = "rbxassetid://134750178929271",
        ["SCP-002"] = "rbxassetid://18331611642",
        ["SCP-093"] = "rbxassetid://121237674708895",
        ["SCP-2950"] = "rbxassetid://18331673441",
        ["SCP-049"] = "rbxassetid://18331626830",
        ["SCP-1299"] = "rbxassetid://112013851167938",
        ["SCP-1025"] = "rbxassetid://18331668905",
        ["SCP-079"] = "rbxassetid://18331632480",
        ["SCP-966"] = "rbxassetid://18331661155",
        ["SCP-008"] = "rbxassetid://18331618967",
        ["SCP-131"] = "rbxassetid://18331645478",
        ["SCP-457"] = "rbxassetid://18331657938",
        ["SCP-938"] = "rbxassetid://82048297498607",
        ["SCP-939"] = "rbxassetid://121290404504761",
        ["SCP-409"] = "rbxassetid://18331650869",
        ["SCP-316"] = "rbxassetid://98373350749130",
        ["SCP-299"] = "rbxassetid://130395557822524",
        ["SCP-087"] = "rbxassetid://18331635059",
        ["SCP-999"] = "rbxassetid://18331665908",
    }
    pcall(function()
        local cb = scprp.Clipboard
        if cb and cb.SCPs then
            for num, data in pairs(cb.SCPs) do
                if data.Icon then NT_SCP_ICONS["SCP-" .. num] = data.Icon end
            end
        end
    end)
    local function ntLookupIcon(name)
        return NT_SCP_ICONS[name] or NT_SCP_ICONS[name:match("(SCP%-%d+)") or ""]
    end

    local FONT_FAMILIES = {
        Arial = "rbxasset://fonts/families/Arimo.json",
        Gotham = "rbxasset://fonts/families/GothamSSm.json",
        Montserrat = "rbxasset://fonts/families/Montserrat.json",
        Nunito = "rbxasset://fonts/families/Nunito.json",
        Ubuntu = "rbxasset://fonts/families/Ubuntu.json",
        Roboto = "rbxasset://fonts/families/Roboto.json",
        ["Source Sans"] = "rbxasset://fonts/families/SourceSansPro.json",
    }
    local FONT_WEIGHT_MAP = {
        Off = Enum.FontWeight.Regular,
        Semibold = Enum.FontWeight.SemiBold,
        Bold = Enum.FontWeight.Bold,
        Black = Enum.FontWeight.Heavy,
    }

    local function getNameTagGui()
        if nameTagGui and nameTagGui.Parent then return nameTagGui end
        nameTagGui = Instance.new("ScreenGui")
        nameTagGui.Name = "PhantomNameTags"
        nameTagGui.ResetOnSpawn = false
        nameTagGui.IgnoreGuiInset = true
        nameTagGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        pcall(function()
            if gethui then
                nameTagGui.Parent = gethui()
            else
                if protect_gui then protect_gui(nameTagGui) end
                nameTagGui.Parent = CoreGui
            end
        end)
        return nameTagGui
    end

    local function clearTag(plr)
        local entry = tags[plr]
        if entry and entry.board then entry.board:Destroy() end
        tags[plr] = nil
    end

    local function clearAllTags()
        for plr in pairs(tags) do clearTag(plr) end
    end

    local function buildScpTag(model)
        local entry = scpTags[model]
        if entry and entry.board then entry.board:Destroy() end
        local hrp = model:FindFirstChild("HumanoidRootPart")
        if not hrp then return end
        local board = Instance.new("Frame")
        board.Name = "ScpNametag"
        board.AnchorPoint = Vector2.new(0.5, 1)
        board.BackgroundTransparency = 1
        board.BorderSizePixel = 0
        board.Size = UDim2.new(0, 140, 0, 28)
        board.Visible = false
        board.Parent = getNameTagGui()
        local bg = Instance.new("Frame")
        bg.BackgroundColor3 = Color3.new(0, 0, 0)
        bg.BackgroundTransparency = 1
        bg.Size = UDim2.new(1, 0, 1, 0)
        bg.BorderSizePixel = 0
        bg.Parent = board
        local bgCorner = Instance.new("UICorner")
        bgCorner.CornerRadius = UDim.new(0, 5)
        bgCorner.Parent = bg
        local label = Instance.new("TextLabel")
        label.AnchorPoint = Vector2.new(0.5, 0.5)
        label.Position = UDim2.new(0.5, 0, 0.5, 0)
        label.BackgroundTransparency = 1
        label.Size = UDim2.new(1, 0, 1, 0)
        label.TextWrapped = false
        label.TextXAlignment = Enum.TextXAlignment.Center
        label.TextYAlignment = Enum.TextYAlignment.Center
        label.TextScaled = false
        label.TextStrokeTransparency = 0.3
        label.TextStrokeColor3 = Color3.new(0, 0, 0)
        label.TextColor3 = Color3.new(1, 1, 1)
        label.RichText = true
        label.Font = Enum.Font.GothamSemibold
        label.Parent = bg
        local iconLabel = Instance.new("ImageLabel")
        iconLabel.Name = "ScpNTIcon"
        iconLabel.AnchorPoint = Vector2.new(0.5, 1)
        iconLabel.Position = UDim2.new(0.5, 0, 0, -4)
        iconLabel.BackgroundTransparency = 1
        iconLabel.BorderSizePixel = 0
        iconLabel.ScaleType = Enum.ScaleType.Fit
        iconLabel.Visible = false
        iconLabel.Parent = board
        scpTags[model] = {
            board = board, bg = bg, bgCorner = bgCorner, label = label, iconLabel = iconLabel,
            cText = nil, cFont = nil, cFontW = nil, cTextSz = nil,
            cBW = nil, cBH = nil, cBgTrans = nil, cCornerR = nil,
        }
    end

    local function clearScpTag(model)
        local entry = scpTags[model]
        if entry and entry.board then entry.board:Destroy() end
        scpTags[model] = nil
    end

    local function clearAllScpTags()
        for model in pairs(scpTags) do clearScpTag(model) end
    end

    local function disconnectCleanup()
        for _, c in ipairs(cleanupConns) do
            if c and c.Disconnect then c:Disconnect() end
        end
        table.clear(cleanupConns)
    end

    local function buildTag(plr, char)
        clearTag(plr)
        if not char then return end
        local hrp = char:WaitForChild("HumanoidRootPart", 3)
        if not hrp then return end

        local board = Instance.new("Frame")
        board.Name = "Nametag"
        board.AnchorPoint = Vector2.new(0.5, 1)
        board.BackgroundTransparency = 1
        board.BorderSizePixel = 0
        board.Size = UDim2.new(0, 140, 0, 28)
        board.Visible = false
        board.Parent = getNameTagGui()

        local bg = Instance.new("Frame")
        bg.BackgroundColor3 = Color3.new(0, 0, 0)
        bg.BackgroundTransparency = 1
        bg.Size = UDim2.new(1, 0, 1, 0)
        bg.BorderSizePixel = 0
        bg.Parent = board

        local bgCorner = Instance.new("UICorner")
        bgCorner.CornerRadius = UDim.new(0, 5)
        bgCorner.Parent = bg

        local label = Instance.new("TextLabel")
        label.AnchorPoint = Vector2.new(0.5, 0.5)
        label.Position = UDim2.new(0.5, 0, 0.5, 0)
        label.BackgroundTransparency = 1
        label.Size = UDim2.new(1, 0, 1, 0)
        label.TextWrapped = false
        label.TextXAlignment = Enum.TextXAlignment.Center
        label.TextYAlignment = Enum.TextYAlignment.Center
        label.TextScaled = false
        label.TextStrokeTransparency = 0.3
        label.TextStrokeColor3 = Color3.new(0, 0, 0)
        label.TextColor3 = Color3.new(1, 1, 1)
        label.RichText = true
        label.Font = Enum.Font.GothamSemibold
        label.Parent = bg

        tags[plr] = {
            board = board, bg = bg, bgCorner = bgCorner, label = label,
            cText = nil, cFont = nil, cFontW = nil, cTextSz = nil,
            cBW = nil, cBH = nil, cBgTrans = nil, cCornerR = nil,
        }
    end

    Nametags = GuiLibrary.Registry.renderPanel.API.CreateOptionsButton({
        Name = "Nametags",
        Function = function(enabled)
            if enabled then
                local function watchPlayer(plr)
                    if plr == lplr then return end
                    if plr.Character then
                        task.spawn(buildTag, plr, plr.Character)
                    end
                    table.insert(cleanupConns, plr.CharacterAdded:Connect(function(char)
                        task.spawn(buildTag, plr, char)
                    end))
                end
                for _, plr in ipairs(Players:GetPlayers()) do watchPlayer(plr) end
                table.insert(cleanupConns, Players.PlayerAdded:Connect(watchPlayer))
                table.insert(cleanupConns, Players.PlayerRemoving:Connect(clearTag))

                local _cfFamily, _cfWeight, _cfObj = nil, nil, nil
                local function getTargetFont()
                    local family = FONT_FAMILIES[(FontChoice and FontChoice.Value) or "Gotham"]
                        or "rbxasset://fonts/families/GothamSSm.json"
                    local w = FONT_WEIGHT_MAP[(BoldWeight and BoldWeight.Value)] or Enum.FontWeight.SemiBold
                    if family ~= _cfFamily or w ~= _cfWeight then
                        _cfFamily, _cfWeight = family, w
                        _cfObj = Font.new(family, w)
                    end
                    return _cfObj
                end

                local infoTick = 0
                local ntWbRp = RaycastParams.new()
                ntWbRp.FilterType = Enum.RaycastFilterType.Exclude
                RunLoops:BindToHeartbeat("Nametags", function(dt)
                    infoTick = infoTick + dt
                    local vp = Camera.ViewportSize
                    local viewScale = math.clamp(vp.Y / 1080, 0.82, 1.4)
                    local ntScale = ((NTScale and NTScale.Value) or 100) / 100
                    local textSz = math.max(7, math.floor(((TextSize and TextSize.Value) or 13) * viewScale * ntScale))
                    local targetFont = getTargetFont()
                    local myRoot = lplr.Character and lplr.Character:FindFirstChild("HumanoidRootPart")
                    local doInfoUpdate = infoTick >= 0.1
                    if doInfoUpdate then infoTick = 0 end

                    for _, plr in ipairs(Players:GetPlayers()) do
                        if plr == lplr then continue end
                        if NTTeamCheck.Enabled and isAlly(plr) and not detectedMods[plr] then clearTag(plr) continue end

                        local char = plr.Character
                        local hum = char and char:FindFirstChildOfClass("Humanoid")
                        local root = char and char:FindFirstChild("HumanoidRootPart")
                        local entry = tags[plr]

                        if not char or not hum or not root or hum.Health <= 0 or not root:IsDescendantOf(workspace) then
                            if entry then entry.board.Visible = false end
                            continue
                        end

                        if not entry or not entry.board.Parent then continue end

                        local head = char:FindFirstChild("Head")
                        local topPos = (head and head:IsA("BasePart"))
                            and (head.Position + Vector3.new(0, head.Size.Y / 2 + 0.15, 0))
                            or (root.Position + Vector3.new(0, math.max((hum and hum.HipHeight) or 2, 0.5) + 1.2, 0))
                        local sp, onScreen = Camera:WorldToViewportPoint(topPos)
                        if not onScreen or sp.Z <= 0 then entry.board.Visible = false continue end

                        entry.board.Visible = true
                        entry.board.Position = UDim2.fromOffset(sp.X, sp.Y)

                        if doInfoUpdate then
                            local baseName = (ShowDisplayName.Enabled and plr.DisplayName ~= "" and plr.DisplayName) or plr.Name
                            local tc = (plr.Team and plr.Team.TeamColor and plr.Team.TeamColor.Color) or Color3.new(1, 1, 1)
                            local teamClr = ("rgb(%d,%d,%d)"):format(
                                math.floor(tc.R * 255), math.floor(tc.G * 255), math.floor(tc.B * 255))
                            local text = ('<font color="%s">%s</font>'):format(teamClr, string.upper(baseName))

                            if ShowDistance.Enabled and myRoot then
                                local dist = math.floor((myRoot.Position - root.Position).Magnitude)
                                if ShowBrackets.Enabled then
                                    text = '<font color="rgb(85,255,85)">[</font><font color="rgb(255,255,255)">'
                                        .. dist .. '</font><font color="rgb(85,255,85)">]</font> ' .. text
                                else
                                    text = '<font color="rgb(85,255,85)">' .. dist .. "</font> " .. text
                                end
                            end

                            if ShowTeam.Enabled and plr.Team then
                                local teamName = plr.Team.Name
                                if ShowBrackets.Enabled then
                                    text = text .. ' <font color="rgb(200,200,200)">[' .. teamName .. "]</font>"
                                else
                                    text = text .. ' <font color="rgb(200,200,200)">' .. teamName .. "</font>"
                                end
                            end

                            if ShowHealth.Enabled then
                                local hp = math.floor(hum.Health)
                                local maxhp = math.max(hum.MaxHealth, 1)
                                local hc = Color3.fromHSV(math.clamp(hp / maxhp, 0, 1) / 2.5, 0.89, 0.75)
                                local hStr = ("rgb(%d,%d,%d)"):format(
                                    math.floor(hc.R * 255), math.floor(hc.G * 255), math.floor(hc.B * 255))
                                if ShowBrackets.Enabled then
                                    text = text .. (' <font color="%s">[%d]</font>'):format(hStr, hp)
                                else
                                    text = text .. (' <font color="%s">%d</font>'):format(hStr, hp)
                                end
                            end

                            if ShowStaffRank.Enabled then
                                local rank = plr:GetAttribute("GroupRank") or 0
                                local ntModLbl = detectedMods[plr]
                                local clr, rankTag
                                if rank >= 253 then
                                    clr = "rgb(0,175,225)"; rankTag = "DEV"
                                elseif rank >= 249 then
                                    clr = "rgb(20,150,55)"; rankTag = "MOD"
                                elseif rank >= 248 then
                                    clr = "rgb(200,200,200)"; rankTag = "STAFF"
                                elseif ntModLbl then
                                    clr = "rgb(255,80,80)"; rankTag = string.upper(ntModLbl)
                                end
                                if rankTag then
                                    text = text .. (' <font color="%s">[%s]</font>'):format(clr, rankTag)
                                end
                            end

                            if saShared.wallbang and saShared.wallbang.Enabled and myRoot then
                                local wbMax = (saShared.wallbangDist and saShared.wallbangDist.Value) or 120
                                if (myRoot.Position - root.Position).Magnitude <= wbMax then
                                    ntWbRp.FilterDescendantsInstances = {lplr.Character, char}
                                    local dir = root.Position - myRoot.Position
                                    if workspace:Raycast(myRoot.Position, dir * 0.99, ntWbRp) then
                                        text = text .. ' <font color="rgb(255,165,0)">WB</font>'
                                    end
                                end
                            end

                            if entry.cText ~= text then
                                entry.cText = text
                                entry.label.Text = text
                            end
                            if entry.cFont ~= targetFont.Family or entry.cFontW ~= targetFont.Weight then
                                entry.cFont = targetFont.Family
                                entry.cFontW = targetFont.Weight
                                entry.label.FontFace = targetFont
                            end
                            if entry.cTextSz ~= textSz then
                                entry.cTextSz = textSz
                                entry.label.TextSize = textSz
                            end
                        end

                        local bounds = entry.label.TextBounds
                        local newW = math.max(40, bounds.X + 8)
                        local newH = math.max(14, bounds.Y + 4)
                        if entry.cBW ~= newW or entry.cBH ~= newH then
                            entry.cBW, entry.cBH = newW, newH
                            entry.board.Size = UDim2.new(0, newW, 0, newH)
                        end

                        local newTrans = (TagBg and TagBg.Enabled) and 0.35 or 1
                        if entry.cBgTrans ~= newTrans then
                            entry.cBgTrans = newTrans
                            entry.bg.BackgroundTransparency = newTrans
                        end

                        local newR = (TagBgCorner and TagBgCorner.Value == "Square") and 0 or 5
                        if entry.cCornerR ~= newR then
                            entry.cCornerR = newR
                            entry.bgCorner.CornerRadius = UDim.new(0, newR)
                        end
                    end

                    if NTSCPs.Enabled then
                        for model, entry in pairs(scpTags) do
                            local hum = model:FindFirstChildOfClass("Humanoid")
                            local root = model:FindFirstChild("HumanoidRootPart")
                            if not model.Parent or not hum or not root or hum.Health <= 0 then
                                entry.board.Visible = false
                                continue
                            end
                            local head = model:FindFirstChild("Head")
                            local topPos = (head and head:IsA("BasePart"))
                                and (head.Position + Vector3.new(0, head.Size.Y / 2 + 0.15, 0))
                                or (root.Position + Vector3.new(0, math.max((hum and hum.HipHeight) or 2, 0.5) + 1.2, 0))
                            local sp, onScreen = Camera:WorldToViewportPoint(topPos)
                            if not onScreen or sp.Z <= 0 then entry.board.Visible = false continue end
                            entry.board.Visible = true
                            entry.board.Position = UDim2.fromOffset(sp.X, sp.Y)
                            if doInfoUpdate then
                                local text = ('<font color="rgb(255,140,0)">%s</font>'):format(string.upper(model.Name))
                                if ShowDistance.Enabled and myRoot then
                                    local dist = math.floor((myRoot.Position - root.Position).Magnitude)
                                    if ShowBrackets.Enabled then
                                        text = '<font color="rgb(85,255,85)">[</font><font color="rgb(255,255,255)">'
                                            .. dist .. '</font><font color="rgb(85,255,85)">]</font> ' .. text
                                    else
                                        text = '<font color="rgb(85,255,85)">' .. dist .. "</font> " .. text
                                    end
                                end
                                if ShowHealth.Enabled then
                                    local hp = math.floor(hum.Health)
                                    local maxhp = math.max(hum.MaxHealth, 1)
                                    local hc = Color3.fromHSV(math.clamp(hp / maxhp, 0, 1) / 2.5, 0.89, 0.75)
                                    local hStr = ("rgb(%d,%d,%d)"):format(
                                        math.floor(hc.R * 255), math.floor(hc.G * 255), math.floor(hc.B * 255))
                                    if ShowBrackets.Enabled then
                                        text = text .. (' <font color="%s">[%d]</font>'):format(hStr, hp)
                                    else
                                        text = text .. (' <font color="%s">%d</font>'):format(hStr, hp)
                                    end
                                end
                                if entry.cText ~= text then
                                    entry.cText = text
                                    entry.label.Text = text
                                end
                                if entry.cFont ~= targetFont.Family or entry.cFontW ~= targetFont.Weight then
                                    entry.cFont = targetFont.Family
                                    entry.cFontW = targetFont.Weight
                                    entry.label.FontFace = targetFont
                                end
                                if entry.cTextSz ~= textSz then
                                    entry.cTextSz = textSz
                                    entry.label.TextSize = textSz
                                end
                            end
                            local bounds = entry.label.TextBounds
                            local newW = math.max(40, bounds.X + 8)
                            local newH = math.max(14, bounds.Y + 4)
                            if entry.cBW ~= newW or entry.cBH ~= newH then
                                entry.cBW, entry.cBH = newW, newH
                                entry.board.Size = UDim2.new(0, newW, 0, newH)
                            end
                            local newTrans = (TagBg and TagBg.Enabled) and 0.35 or 1
                            if entry.cBgTrans ~= newTrans then
                                entry.cBgTrans = newTrans
                                entry.bg.BackgroundTransparency = newTrans
                            end
                            local newR = (TagBgCorner and TagBgCorner.Value == "Square") and 0 or 5
                            if entry.cCornerR ~= newR then
                                entry.cCornerR = newR
                                entry.bgCorner.CornerRadius = UDim.new(0, newR)
                            end
                            if entry.iconLabel then
                                if NTSCPIcons.Enabled then
                                    local iconId = ntLookupIcon(model.Name)
                                        or (model.Parent and ntLookupIcon(model.Parent.Name))
                                        or (model.Parent and model.Parent.Parent and ntLookupIcon(model.Parent.Parent.Name))
                                    if iconId then
                                        local sz = (NTIconSize and NTIconSize.Value) or 20
                                        entry.iconLabel.Image = iconId
                                        entry.iconLabel.Size = UDim2.new(0, sz, 0, sz)
                                        entry.iconLabel.Visible = true
                                    else
                                        entry.iconLabel.Visible = false
                                    end
                                else
                                    entry.iconLabel.Visible = false
                                end
                            end
                        end
                    end

                    local ntIconsOn = NTSCPIcons.Enabled
                    local ntIconSz = (NTIconSize and NTIconSize.Value) or 20
                    for _, bb in pairs(ntScpIconLabels) do
                        pcall(function()
                            bb.Enabled = ntIconsOn
                            bb.Size = UDim2.new(0, ntIconSz, 0, ntIconSz)
                        end)
                    end

                    ntScpScanTick = ntScpScanTick + dt
                    if (NTSCPs.Enabled or NTSCPIcons.Enabled) and ntScpScanTick >= 0.5 then
                        ntScpScanTick = 0
                        local scpFolder = workspace:FindFirstChild("SCPs")
                        if scpFolder then
                            local function tryNtSCP(obj)
                                if not obj:IsA("Model") then return end
                                if not obj:FindFirstChildOfClass("Humanoid") then return end
                                if not obj:FindFirstChild("HumanoidRootPart") then return end
                                if NTSCPIcons.Enabled and not NTSCPs.Enabled and not ntScpIconLabels[obj] then
                                    local iconId = ntLookupIcon(obj.Name)
                                        or (obj.Parent and ntLookupIcon(obj.Parent.Name))
                                        or (obj.Parent and obj.Parent.Parent and ntLookupIcon(obj.Parent.Parent.Name))
                                    if iconId then
                                        local hrpRef = obj:FindFirstChild("HumanoidRootPart")
                                        if hrpRef then
                                            local headPart = obj:FindFirstChild("Head")
                                            local yOff
                                            if headPart and headPart:IsA("BasePart") then
                                                yOff = (headPart.Position.Y + headPart.Size.Y / 2) - hrpRef.Position.Y + 1.8
                                            else
                                                yOff = 5
                                            end
                                            local bb = Instance.new("BillboardGui")
                                            bb.Name = "NTSCPIcon"
                                            bb.AlwaysOnTop = true
                                            bb.Size = UDim2.new(0, 20, 0, 20)
                                            bb.StudsOffset = Vector3.new(0, yOff, 0)
                                            bb.MaxDistance = 0
                                            bb.Enabled = false
                                            bb.Parent = hrpRef
                                            local img = Instance.new("ImageLabel")
                                            img.BackgroundTransparency = 1
                                            img.Image = iconId
                                            img.Size = UDim2.new(1, 0, 1, 0)
                                            img.ScaleType = Enum.ScaleType.Fit
                                            img.Parent = bb
                                            ntScpIconLabels[obj] = bb
                                        end
                                    end
                                end
                                if NTSCPs.Enabled and not scpTags[obj] then
                                    buildScpTag(obj)
                                end
                            end
                            for _, desc in ipairs(scpFolder:GetDescendants()) do
                                tryNtSCP(desc)
                            end
                        end
                        for model, il in pairs(ntScpIconLabels) do
                            if not model.Parent or not model:FindFirstChild("HumanoidRootPart") then
                                il:Destroy()
                                ntScpIconLabels[model] = nil
                            end
                        end
                        for model in pairs(scpTags) do
                            if not model.Parent or not model:FindFirstChild("HumanoidRootPart") then
                                clearScpTag(model)
                            end
                        end
                    end
                end)
            else
                RunLoops:UnbindFromHeartbeat("Nametags")
                disconnectCleanup()
                clearAllTags()
                if nameTagGui then nameTagGui:Destroy(); nameTagGui = nil end
                clearAllScpTags()
                for _, bb in pairs(ntScpIconLabels) do pcall(function() bb:Destroy() end) end
                ntScpIconLabels = {}
            end
        end
    })

    NTSCPs = Nametags.CreateToggle({
        Name = "SCPs",
        Default = false
    })
    NTSCPIcons = Nametags.CreateToggle({
        Name = "ScpIcons",
        Default = false
    })
    NTSCPs:AddDependent(NTSCPIcons)
    NTIconSize = Nametags.CreateSlider({
        Name = "IconSize",
        Min = 8,
        Max = 64,
        Default = 20,
        Round = 1
    })
    NTSCPIcons:AddDependent(NTIconSize)
    ShowDisplayName = Nametags.CreateToggle({
        Name = "Display",
        Default = true
    })
    ShowTeam = Nametags.CreateToggle({
        Name = "Team",
        Default = true
    })
    ShowDistance = Nametags.CreateToggle({
        Name = "Distance",
        Default = true
    })
    ShowHealth = Nametags.CreateToggle({
        Name = "Health",
        Default = true
    })
    ShowBrackets = Nametags.CreateToggle({
        Name = "Brackets",
        Default = true
    })
    TagBg = Nametags.CreateToggle({
        Name = "BG",
        Default = true
    })
    NTTeamCheck = Nametags.CreateToggle({
        Name = "TeamCheck",
        Default = true
    })
    ShowStaffRank = Nametags.CreateToggle({
        Name = "Staff",
        Default = true
    })
    TagBgCorner = Nametags.CreateDropdown({
        Name = "Corner",
        List = {"Rounded", "Square"},
        Default = "Rounded"
    })
    FontChoice = Nametags.CreateDropdown({
        Name = "Font",
        List = {"Arial", "Gotham", "Montserrat", "Nunito", "Ubuntu", "Roboto", "Source Sans"},
        Default = "Gotham"
    })
    BoldWeight = Nametags.CreateDropdown({
        Name = "Bold",
        List = {"Off", "Semibold", "Bold", "Black"},
        Default = "Semibold"
    })
    TextSize = Nametags.CreateSlider({
        Name = "Size",
        Min = 7,
        Max = 20,
        Default = 13,
        Round = 1
    })
    NTScale = Nametags.CreateSlider({
        Name = "TagScale",
        Min = 50,
        Max = 200,
        Default = 100,
        Round = 1
    })
end)

runcode(function()
    local Tracers = {}
    local TracerThickness = {}
    local TracerDistLabel = {}
    local TracerTeamCheck = {}
    local POOL = 50
    local drawLines = {}
    local drawLabels = {}

    local TracersPool = {}

    TracersPool.alloc = function()
        for j = 1, POOL do
            if not drawLines[j] then
                local ln = Drawing.new("Line")
                ln.Visible = false
                ln.Transparency = 1
                ln.Thickness = 1
                ln.ZIndex = 1
                drawLines[j] = ln
            end
            if not drawLabels[j] then
                local lb = Drawing.new("Text")
                lb.Visible = false
                lb.Color = Color3.new(1, 1, 1)
                lb.Size = 13
                lb.Outline = true
                lb.Center = true
                lb.Font = Drawing.Fonts.UI
                drawLabels[j] = lb
            end
        end
    end

    TracersPool.free = function()
        for j = 1, #drawLines do drawLines[j]:Remove() end
        for j = 1, #drawLabels do drawLabels[j]:Remove() end
        drawLines = {}
        drawLabels = {}
    end

    Tracers = GuiLibrary.Registry.renderPanel.API.CreateOptionsButton({
        Name = "Tracers",
        Function = function(enabled)
            if enabled then
                TracersPool.alloc()
                RunLoops:BindToHeartbeat("Tracers", function()
                    local vp = Camera.ViewportSize
                    local origin = Vector2.new(vp.X / 2, vp.Y)
                    local myRoot = lplr.Character and lplr.Character:FindFirstChild("HumanoidRootPart")
                    local i = 1
                    for _, plr in ipairs(Players:GetPlayers()) do
                        if plr == lplr then continue end
                        if TracerTeamCheck.Enabled and isAlly(plr) then continue end
                        local char = plr.Character
                        local hrp = char and char:FindFirstChild("HumanoidRootPart")
                        local hum = char and char:FindFirstChildOfClass("Humanoid")
                        if not hrp or not hum or hum.Health <= 0 then continue end
                        if TracerWallCheck.Enabled and myRoot then
                            local wcp = RaycastParams.new()
                            wcp.FilterType = Enum.RaycastFilterType.Exclude
                            wcp.FilterDescendantsInstances = {lplr.Character, char}
                            local dir = hrp.Position - myRoot.Position
                            if workspace:Raycast(myRoot.Position, dir * 0.99, wcp) then continue end
                        end
                        local pos, onScreen = Camera:WorldToViewportPoint(hrp.Position)
                        if not onScreen or pos.Z <= 0 then continue end
                        if i > POOL then continue end

                        local screenPos = Vector2.new(pos.X, pos.Y)
                        local ln = drawLines[i]
                        ln.From = origin
                        ln.To = screenPos
                        ln.Color = plr.TeamColor.Color
                        ln.Thickness = (TracerThickness and TracerThickness.Value) or 1
                        ln.Visible = true

                        local lb = drawLabels[i]
                        if TracerDistLabel.Enabled and myRoot then
                            local dist = math.floor((myRoot.Position - hrp.Position).Magnitude)
                            lb.Text = dist .. "m"
                            lb.Position = Vector2.new(
                                (origin.X + screenPos.X) / 2,
                                (origin.Y + screenPos.Y) / 2 - 8
                            )
                            lb.Visible = true
                        else
                            lb.Visible = false
                        end

                        i += 1
                    end
                    for j = i, POOL do
                        drawLines[j].Visible = false
                        drawLabels[j].Visible = false
                    end
                end)
            else
                RunLoops:UnbindFromHeartbeat("Tracers")
                TracersPool.free()
            end
        end
    })

    TracerThickness = Tracers.CreateSlider({
        Name = "Thickness",
        Min = 1,
        Max = 8,
        Default = 1,
        Round = 1
    })
    TracerDistLabel = Tracers.CreateToggle({
        Name = "DistLabel",
        Default = false
    })
    TracerTeamCheck = Tracers.CreateToggle({
        Name = "TeamCheck",
        Default = true
    })
    TracerWallCheck = Tracers.CreateToggle({
        Name = "WallCheck",
        Default = false
    })
end)

runcode(function()
    local Fullbright = {}
    local NoFog = {}
    local Lighting = cloneref(game:GetService("Lighting"))
    local orig = {}

    Fullbright = GuiLibrary.Registry.renderPanel.API.CreateOptionsButton({
        Name = "Fullbright",
        Function = function(enabled)
            if enabled then
                orig.Ambient = Lighting.Ambient
                orig.OutdoorAmbient = Lighting.OutdoorAmbient
                orig.Brightness = Lighting.Brightness
                orig.FogEnd = Lighting.FogEnd
                Lighting.Ambient = Color3.new(1, 1, 1)
                Lighting.OutdoorAmbient = Color3.new(1, 1, 1)
                Lighting.Brightness = 2
                if NoFog.Enabled then Lighting.FogEnd = 1e6 end
            else
                Lighting.Ambient = orig.Ambient or Color3.fromRGB(70, 70, 70)
                Lighting.OutdoorAmbient = orig.OutdoorAmbient or Color3.fromRGB(70, 70, 70)
                Lighting.Brightness = orig.Brightness or 1
                Lighting.FogEnd = orig.FogEnd or 1000
            end
        end
    })

    NoFog = Fullbright.CreateToggle({
        Name = "NoFog",
        Default = true,
        Function = function(on)
            if Fullbright.Enabled then
                Lighting.FogEnd = on and 1e6 or (orig.FogEnd or 1000)
            end
        end
    })
end)

runcode(function()
    local XRay = {}
    local XRayAlpha = {}
    local xrayParts = {}
    local xrayConns = {}
    local xrayActive = false

    local XRayUtil = {}

    XRayUtil.isCharPart = function(part)
        local model = part:FindFirstAncestorOfClass("Model")
        return model ~= nil and Players:GetPlayerFromCharacter(model) ~= nil
    end

    XRayUtil.applyPart = function(part)
        if not xrayActive then return end
        if not part:IsA("BasePart") then return end
        if XRayUtil.isCharPart(part) then return end
        if xrayParts[part] then return end
        if part.Transparency >= 0.95 then return end
        local alpha = (XRayAlpha and XRayAlpha.Value) or 0.75
        xrayParts[part] = true
        pcall(function() part.LocalTransparencyModifier = alpha end)
    end

    XRayUtil.restoreAll = function()
        xrayActive = false
        for part in pairs(xrayParts) do
            pcall(function() part.LocalTransparencyModifier = 0 end)
        end
        xrayParts = {}
    end

    XRay = GuiLibrary.Registry.renderPanel.API.CreateOptionsButton({
        Name = "XRay",
        Function = function(enabled)
            if enabled then
                xrayActive = true
                for _, part in ipairs(workspace:GetDescendants()) do
                    XRayUtil.applyPart(part)
                end
                table.insert(xrayConns, workspace.DescendantAdded:Connect(function(inst)
                    task.defer(XRayUtil.applyPart, inst)
                end))
                table.insert(xrayConns, workspace.DescendantRemoving:Connect(function(inst)
                    xrayParts[inst] = nil
                end))
            else
                for _, c in ipairs(xrayConns) do c:Disconnect() end
                table.clear(xrayConns)
                XRayUtil.restoreAll()
            end
        end
    })

    XRayAlpha = XRay.CreateSlider({
        Name = "Alpha",
        Min = 0.5,
        Max = 0.95,
        Default = 0.75,
        Round = 2
    })
end)

runcode(function()
    local NoFall = {}

    NoFall = GuiLibrary.Registry.movementPanel.API.CreateOptionsButton({
        Name = "NoFall",
        Function = function(enabled)
            if enabled then
                RunLoops:BindToHeartbeat("NoFall", function()
                    local char = lplr.Character
                    local hrp = char and char:FindFirstChild("HumanoidRootPart")
                    local hum = char and char:FindFirstChildOfClass("Humanoid")
                    if not hrp or not hum or hum.Health <= 0 then return end
                    local vel = hrp.AssemblyLinearVelocity
                    if vel.Y < -75 then
                        hrp.AssemblyLinearVelocity = Vector3.new(vel.X, -75, vel.Z)
                    end
                end)
            else
                RunLoops:UnbindFromHeartbeat("NoFall")
            end
        end
    })
end)

runcode(function()
    local Teleport = {}
    local TPLocation = {}
    local TPLiftSpeed = {}
    local TPGlideSpeed = {}

    local locationNames = {}
    local locationMap = {}

    local function addLoc(name, pos)
        if name and pos and not locationMap[name] then
            locationMap[name] = pos
            table.insert(locationNames, name)
        end
    end

    pcall(function()
        local spawns = workspace:FindFirstChild("Spawns")
        if not spawns then return end
        for _, sp in ipairs(spawns:GetChildren()) do
            if sp:IsA("SpawnLocation") then
                addLoc(sp.Name, sp.Position + Vector3.new(0, 3, 0))
            end
        end
    end)

    pcall(function()
        local rs = game:GetService("ReplicatedStorage")
        local wpFolder = rs:FindFirstChild("Test_Waypoints")
        if not wpFolder then return end
        local generic = wpFolder:FindFirstChild("Generic")
        if not generic then return end
        local data = require(generic)
        for name, entry in pairs(data) do
            if type(entry) == "table" and entry.Steps and entry.Steps[1] then
                local pos = entry.Steps[1].Position
                if typeof(pos) == "Vector3" then
                    addLoc(name, pos + Vector3.new(0, 2, 0))
                end
            end
        end
    end)

    table.sort(locationNames)

    local cancelTP = false

    Teleport = GuiLibrary.Registry.movementPanel.API.CreateOptionsButton({
        Name = "Teleport",
        Function = function(enabled)
            if not enabled then cancelTP = true return end
            cancelTP = false
            local dest = locationMap[TPLocation.Value]
            if not dest then Teleport:Toggle(false) return end

            task.spawn(function()
                local char = lplr.Character
                local hrp = char and char:FindFirstChild("HumanoidRootPart")
                if not hrp then Teleport:Toggle(false) return end

                local rp = RaycastParams.new()
                rp.FilterType = Enum.RaycastFilterType.Exclude
                rp.FilterDescendantsInstances = {char}

                local function skyY(pos)
                    local excl = {char}
                    local skyRp = RaycastParams.new()
                    skyRp.FilterType = Enum.RaycastFilterType.Exclude
                    local origin = Vector3.new(pos.X, 2000, pos.Z)
                    for _ = 1, 40 do
                        local dist = origin.Y - pos.Y
                        if dist < 1 then break end
                        skyRp.FilterDescendantsInstances = excl
                        local hit = workspace:Raycast(origin, Vector3.new(0, -dist, 0), skyRp)
                        if not hit then break end
                        if hit.Instance.CanCollide then
                            return hit.Position.Y + 20
                        end
                        table.insert(excl, hit.Instance)
                        origin = Vector3.new(pos.X, hit.Position.Y - 0.05, pos.Z)
                    end
                    return pos.Y + 20
                end

                local function travelTo(from, to, speed)
                    local dist = (to - from).Magnitude
                    if dist < 0.01 then return true end
                    local elapsed = 0
                    local duration = dist / math.max(1, speed)
                    while elapsed < duration do
                        if cancelTP then return false end
                        local dt = task.wait()
                        elapsed = elapsed + dt
                        local t = math.min(elapsed / duration, 1)
                        hrp = lplr.Character and lplr.Character:FindFirstChild("HumanoidRootPart")
                        if not hrp then return false end
                        hrp.CFrame = CFrame.new(from:Lerp(to, t))
                        pcall(function() hrp.AssemblyLinearVelocity = Vector3.zero end)
                    end
                    return true
                end

                local liftSpeed = math.max(1, TPLiftSpeed.Value or 60)
                local glideSpeed = math.max(1, TPGlideSpeed.Value or 60)

                local start = hrp.Position
                local high = math.max(skyY(start), skyY(dest))
                local skyStart = Vector3.new(start.X, high, start.Z)
                local skyDest = Vector3.new(dest.X, high, dest.Z)

                if not travelTo(start, skyStart, liftSpeed) then return end
                if not travelTo(skyStart, skyDest, glideSpeed) then return end
                if not travelTo(skyDest, dest, liftSpeed) then return end

                Teleport:Toggle(false)
            end)
        end
    })

    TPLocation = Teleport.CreateDropdown({
        Name = "Location",
        List = locationNames,
        Default = locationNames[1],
    })

    TPLiftSpeed = Teleport.CreateSlider({
        Name = "LiftSpeed",
        Min = 10,
        Max = 500,
        Default = 40,
        Increment = 10,
    })

    TPGlideSpeed = Teleport.CreateSlider({
        Name = "GlideSpeed",
        Min = 10,
        Max = 500,
        Default = 42,
        Increment = 10,
    })
end)

runcode(function()
    local Lighting = game:GetService("Lighting")
    local thermalCC = nil
    local thermalBloom = nil
    local thermalBillboards = {}
    local thermalConns = {}

    local ThermalBrightness = nil
    local ThermalContrast = nil
    local ThermalAmbient = nil
    local ThermalIconSize = nil

    local ThermalUtil = {}

    ThermalUtil.getColor = function(plr)
        if not plr then return Color3.fromRGB(0, 255, 100) end
        local team = plr.Team and plr.Team.Name or ""
        if team == "Class - D" then return Color3.fromRGB(255, 220, 50) end
        if team == "Chaos Insurgency" then return Color3.fromRGB(50, 180, 255) end
        if team == "SCP" then return Color3.fromRGB(0, 255, 100) end
        return Color3.fromRGB(255, 80, 20)
    end

    ThermalUtil.addBillboard = function(char, color)
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if not hrp then return end
        local existing = hrp:FindFirstChild("PhantomThermal")
        if existing then existing:Destroy() end
        local bb = Instance.new("BillboardGui")
        bb.Name = "PhantomThermal"
        bb.AlwaysOnTop = true
        bb.Size = UDim2.new(4, 0, 4, 0)
        bb.AutoLocalize = false
        local img = Instance.new("ImageLabel")
        img.BackgroundTransparency = 1
        img.Image = "rbxassetid://108052646597930"
        img.ImageColor3 = color
        img.Size = UDim2.new(1, 0, 1, 0)
        img.Parent = bb
        bb.Parent = hrp
        thermalBillboards[hrp] = bb
    end

    ThermalUtil.rebuild = function()
        for hrp, bb in pairs(thermalBillboards) do
            pcall(function() bb:Destroy() end)
        end
        thermalBillboards = {}
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= lplr and plr.Character then
                ThermalUtil.addBillboard(plr.Character, ThermalUtil.getColor(plr))
            end
        end
        local scpFolder = workspace:FindFirstChild("SCPs")
        if scpFolder then
            for _, model in ipairs(scpFolder:GetChildren()) do
                if model:FindFirstChild("HumanoidRootPart") then
                    ThermalUtil.addBillboard(model, Color3.fromRGB(0, 255, 100))
                end
            end
        end
    end

    ThermalUtil.applySettings = function()
        if not thermalCC then return end
        local brightness = (ThermalBrightness and ThermalBrightness.Value or 40) / 100
        local contrast = (ThermalContrast and ThermalContrast.Value or 60) / 100
        local ambient = math.floor(ThermalAmbient and ThermalAmbient.Value or 15)
        local iconSize = ThermalIconSize and ThermalIconSize.Value or 4

        thermalCC.Contrast = contrast
        thermalCC.Brightness = 0
        thermalCC.Saturation = -1
        thermalCC.TintColor = Color3.fromRGB(20, 25, 45)

        Lighting.Brightness = brightness
        Lighting.Ambient = Color3.fromRGB(ambient, ambient, math.floor(ambient * 1.6))
        Lighting.OutdoorAmbient = Color3.fromRGB(ambient, ambient, math.floor(ambient * 1.6))

        if thermalBloom then
            thermalBloom.Intensity = 0.8
            thermalBloom.Size = 24
            thermalBloom.Threshold = 0.85
        end

        for hrp, bb in pairs(thermalBillboards) do
            if bb and bb.Parent then
                bb.Size = UDim2.new(iconSize, 0, iconSize, 0)
            end
        end
    end

    ThermalUtil.enable = function()
        thermalCC = Instance.new("ColorCorrectionEffect")
        thermalCC.Name = "PhantomThermal"
        thermalCC.Parent = Lighting

        thermalBloom = Instance.new("BloomEffect")
        thermalBloom.Name = "PhantomThermalBloom"
        thermalBloom.Intensity = 0.8
        thermalBloom.Size = 24
        thermalBloom.Threshold = 0.85
        thermalBloom.Parent = Lighting

        ThermalUtil.rebuild()

        local lastIconSize = -1
        RunLoops:BindToHeartbeat("ThermalVision", function()
            if thermalCC then
                thermalCC.Contrast = (ThermalContrast and ThermalContrast.Value or 60) / 100
                thermalCC.Brightness = 0
                thermalCC.Saturation = -1
                local brightness = (ThermalBrightness and ThermalBrightness.Value or 40) / 100
                local ambient = math.floor(ThermalAmbient and ThermalAmbient.Value or 15)
                Lighting.Brightness = brightness
                Lighting.Ambient = Color3.fromRGB(ambient, ambient, math.floor(ambient * 1.6))
                Lighting.OutdoorAmbient = Color3.fromRGB(ambient, ambient, math.floor(ambient * 1.6))
            end
            local iconSize = ThermalIconSize and ThermalIconSize.Value or 4
            if iconSize ~= lastIconSize then
                lastIconSize = iconSize
                for hrp, bb in pairs(thermalBillboards) do
                    if bb and bb.Parent then
                        bb.Size = UDim2.new(iconSize, 0, iconSize, 0)
                    end
                end
            end
            for hrp, bb in pairs(thermalBillboards) do
                if not hrp.Parent or not bb.Parent then
                    thermalBillboards[hrp] = nil
                end
            end
        end)

        for _, plr in ipairs(Players:GetPlayers()) do
            table.insert(thermalConns, plr.CharacterAdded:Connect(function(char)
                task.wait(0.1)
                ThermalUtil.addBillboard(char, ThermalUtil.getColor(plr))
            end))
        end
        table.insert(thermalConns, Players.PlayerAdded:Connect(function(plr)
            table.insert(thermalConns, plr.CharacterAdded:Connect(function(char)
                task.wait(0.1)
                ThermalUtil.addBillboard(char, ThermalUtil.getColor(plr))
            end))
        end))
    end

    ThermalUtil.disable = function()
        RunLoops:UnbindFromHeartbeat("ThermalVision")
        if thermalCC then thermalCC:Destroy() thermalCC = nil end
        if thermalBloom then thermalBloom:Destroy() thermalBloom = nil end
        for _, c in ipairs(thermalConns) do pcall(function() c:Disconnect() end) end
        thermalConns = {}
        for hrp, bb in pairs(thermalBillboards) do
            pcall(function() bb:Destroy() end)
        end
        thermalBillboards = {}
        Lighting.Brightness = 1
        Lighting.Ambient = Color3.fromRGB(100, 100, 100)
        Lighting.OutdoorAmbient = Color3.fromRGB(127, 127, 127)
    end

    local ThermalVision = GuiLibrary.Registry.renderPanel.API.CreateOptionsButton({
        Name = "ThermalVision",
        Function = function(enabled)
            if enabled then
                ThermalUtil.enable()
            else
                ThermalUtil.disable()
            end
        end
    })

    ThermalBrightness = ThermalVision.CreateSlider({
        Name = "Brightness",
        Min = 0,
        Max = 100,
        Default = 40,
        Increment = 5,
    })
    ThermalContrast = ThermalVision.CreateSlider({
        Name = "Contrast",
        Min = 0,
        Max = 100,
        Default = 60,
        Increment = 5,
    })
    ThermalAmbient = ThermalVision.CreateSlider({
        Name = "Ambient",
        Min = 0,
        Max = 80,
        Default = 15,
        Increment = 5,
    })
    ThermalIconSize = ThermalVision.CreateSlider({
        Name = "IconSize",
        Min = 1,
        Max = 10,
        Default = 4,
        Increment = 1,
    })
end)

runcode(function()
    local autoConns = {}

    local AutoMinigame = GuiLibrary.Registry.utillityPanel.API.CreateOptionsButton({
        Name = "AutoMinigame",
        Function = function(enabled)
            if enabled then
                table.insert(autoConns, Net.onEvent(function(eventName, model)
                    if not AutoMinigame or not AutoMinigame.Enabled then return end
                    if not model or not model.Parent then return end

                    if eventName == "Timing" then
                        Net.CallServerAsync("Breakable Door", model, 0.3)

                    elseif eventName == "Electrical Box" then
                        Net.CallServerAsync(model.Name, model, 0.5)

                    elseif eventName == "Keypad" then
                        local doorModel = model.Parent and model.Parent.Parent
                        if not doorModel then return end
                        local code = doorModel:GetAttribute("Code")
                            or doorModel:GetAttribute("Password")
                            or doorModel:GetAttribute("KeypadCode")
                        if code then
                            Net.CallServerAsync("Bunker Door 2", tostring(code), 0.3)
                        end
                    end
                end))
            else
                for _, c in ipairs(autoConns) do pcall(c) end
                autoConns = {}
            end
        end
    })
end)

runcode(function()
    local chamHighlights = {}
    local chamConns = {}
    local ChamFill = nil
    local ChamOutline = nil
    local ChamDepth = nil
    local ChamTeamCheck = nil
    local ChamSCPs = nil
    local ChamPulse = nil
    local pulseT = 0

    local TEAM_COLORS = {
        ["Class - D"] = Color3.fromRGB(255, 140, 0),
        ["Chaos Insurgency"] = Color3.fromRGB(0, 140, 255),
        ["SCP"] = Color3.fromRGB(255, 50, 200),
    }
    local DEFAULT_COLOR = Color3.fromRGB(220, 50, 50)
    local SCP_COLOR = Color3.fromRGB(255, 50, 200)

    local ChamUtil = {}

    ChamUtil.getColor = function(plr)
        if not plr then return SCP_COLOR end
        local team = plr.Team and plr.Team.Name or ""
        return TEAM_COLORS[team] or DEFAULT_COLOR
    end

    ChamUtil.add = function(char, color, ally)
        if not char then return end
        if ally and not (ChamTeamCheck and ChamTeamCheck.Enabled) then return end
        local existing = char:FindFirstChild("PhantomCham")
        if existing then existing:Destroy() end
        local depth = (ChamDepth and ChamDepth.Value == "Occluded")
            and Enum.HighlightDepthMode.Occluded
            or Enum.HighlightDepthMode.AlwaysOnTop
        local hl = Instance.new("Highlight")
        hl.Name = "PhantomCham"
        hl.FillColor = color
        hl.OutlineColor = Color3.new(1, 1, 1)
        hl.FillTransparency = 0.4
        hl.OutlineTransparency = 0
        hl.DepthMode = depth
        hl.Parent = char
        chamHighlights[char] = hl
    end

    ChamUtil.rebuild = function()
        for _, hl in pairs(chamHighlights) do pcall(function() hl:Destroy() end) end
        chamHighlights = {}
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= lplr and plr.Character then
                local ally = isAlly and isAlly(plr)
                ChamUtil.add(plr.Character, ChamUtil.getColor(plr), ally)
            end
        end
        if ChamSCPs and ChamSCPs.Enabled then
            local scpFolder = workspace:FindFirstChild("SCPs")
            if scpFolder then
                for _, model in ipairs(scpFolder:GetChildren()) do
                    if model:FindFirstChild("HumanoidRootPart") then
                        ChamUtil.add(model, SCP_COLOR, false)
                    end
                end
            end
        end
    end

    local Chams = GuiLibrary.Registry.renderPanel.API.CreateOptionsButton({
        Name = "Chams",
        Function = function(enabled)
            if enabled then
                ChamUtil.rebuild()
                for _, plr in ipairs(Players:GetPlayers()) do
                    table.insert(chamConns, plr.CharacterAdded:Connect(function(char)
                        task.wait(0.1)
                        ChamUtil.add(char, ChamUtil.getColor(plr), isAlly and isAlly(plr))
                    end))
                end
                table.insert(chamConns, Players.PlayerAdded:Connect(function(plr)
                    table.insert(chamConns, plr.CharacterAdded:Connect(function(char)
                        task.wait(0.1)
                        ChamUtil.add(char, ChamUtil.getColor(plr), isAlly and isAlly(plr))
                    end))
                end))
                local lastTeamCheck = nil
                local lastSCPs = nil
                RunLoops:BindToHeartbeat("Chams", function(dt)
                    local teamCheck = ChamTeamCheck and ChamTeamCheck.Enabled
                    local showSCPs = ChamSCPs and ChamSCPs.Enabled
                    if teamCheck ~= lastTeamCheck or showSCPs ~= lastSCPs then
                        lastTeamCheck = teamCheck
                        lastSCPs = showSCPs
                        ChamUtil.rebuild()
                    end
                    local fill = (ChamFill and ChamFill.Value or 4) / 10
                    local outline = (ChamOutline and ChamOutline.Value or 0) / 10
                    local depth = (ChamDepth and ChamDepth.Value == "Occluded")
                        and Enum.HighlightDepthMode.Occluded
                        or Enum.HighlightDepthMode.AlwaysOnTop
                    if ChamPulse and ChamPulse.Enabled then
                        pulseT = pulseT + (dt or 0.016)
                        fill = math.abs(math.sin(pulseT * 2)) * fill
                    end
                    for char, hl in pairs(chamHighlights) do
                        if not char.Parent or not hl.Parent then
                            chamHighlights[char] = nil
                        else
                            hl.FillTransparency = fill
                            hl.OutlineTransparency = outline
                            hl.DepthMode = depth
                        end
                    end
                end)
            else
                RunLoops:UnbindFromHeartbeat("Chams")
                for _, c in ipairs(chamConns) do pcall(function() c:Disconnect() end) end
                chamConns = {}
                for _, hl in pairs(chamHighlights) do pcall(function() hl:Destroy() end) end
                chamHighlights = {}
            end
        end
    })

    ChamDepth = Chams.CreateDropdown({
        Name = "Depth",
        List = {"AlwaysOnTop", "Occluded"},
        Default = "AlwaysOnTop",
    })
    ChamFill = Chams.CreateSlider({
        Name = "Fill",
        Min = 0,
        Max = 10,
        Default = 4,
        Increment = 1,
    })
    ChamOutline = Chams.CreateSlider({
        Name = "Outline",
        Min = 0,
        Max = 10,
        Default = 0,
        Increment = 1,
    })
    ChamTeamCheck = Chams.CreateToggle({
        Name = "TeamCheck",
        Default = true,
    })
    ChamSCPs = Chams.CreateToggle({
        Name = "SCPs",
        Default = true,
    })
    ChamPulse = Chams.CreateToggle({
        Name = "Pulse",
        Default = false,
    })
end)

runcode(function()
    local CrosshairStyle = nil
    local CrosshairGap = nil
    local CrosshairLength = nil
    local CrosshairThickness = nil
    local CrosshairSize = nil

    local function newLine(z)
        local l = Drawing.new("Line")
        l.Color = Color3.new(1,1,1); l.Thickness = 2
        l.Transparency = 1; l.Visible = false; l.ZIndex = z or 5
        return l
    end
    local function newCircle(z)
        local c = Drawing.new("Circle")
        c.Color = Color3.new(1,1,1); c.Thickness = 1.5
        c.Filled = false; c.Visible = false; c.NumSides = 64; c.ZIndex = z or 5
        return c
    end
    local function newDot(z)
        local c = Drawing.new("Circle")
        c.Color = Color3.new(1,1,1); c.Thickness = 0
        c.Filled = true; c.Visible = false; c.NumSides = 32; c.ZIndex = z or 5
        return c
    end

    local W = {} for i=1,8 do W[i]=newLine(5) end
    local B = {} for i=1,8 do B[i]=newLine(4) end
    local WC = {newCircle(5), newCircle(5)}
    local BC = {newCircle(4), newCircle(4)}
    local WD = {newDot(5)}
    local BD = {newDot(4)}

    local allDrawings = {}
    for _,v in ipairs(W) do table.insert(allDrawings,v) end
    for _,v in ipairs(B) do table.insert(allDrawings,v) end
    for _,v in ipairs(WC) do table.insert(allDrawings,v) end
    for _,v in ipairs(BC) do table.insert(allDrawings,v) end
    for _,v in ipairs(WD) do table.insert(allDrawings,v) end
    for _,v in ipairs(BD) do table.insert(allDrawings,v) end

    local function hideAll()
        for _,d in ipairs(allDrawings) do d.Visible = false end
    end

    local function setLine(w, b, from, to, thick, col)
        col = col or Color3.new(1,1,1)
        w.From=from; w.To=to; w.Thickness=thick; w.Color=col; w.Visible=true
        b.From=from; b.To=to; b.Thickness=thick+2; b.Color=Color3.new(0,0,0); b.Visible=true
    end

    local STYLES = {
        ["Cross"] = function(cx, cy, gap, len, thick)
            setLine(W[1],B[1], Vector2.new(cx-gap-len,cy), Vector2.new(cx-gap,cy), thick)
            setLine(W[2],B[2], Vector2.new(cx+gap,cy), Vector2.new(cx+gap+len,cy), thick)
            setLine(W[3],B[3], Vector2.new(cx,cy-gap-len), Vector2.new(cx,cy-gap), thick)
            setLine(W[4],B[4], Vector2.new(cx,cy+gap), Vector2.new(cx,cy+gap+len), thick)
        end,
        ["T-Cross"] = function(cx, cy, gap, len, thick)
            setLine(W[1],B[1], Vector2.new(cx-gap-len,cy), Vector2.new(cx-gap,cy), thick)
            setLine(W[2],B[2], Vector2.new(cx+gap,cy), Vector2.new(cx+gap+len,cy), thick)
            setLine(W[3],B[3], Vector2.new(cx,cy+gap), Vector2.new(cx,cy+gap+len), thick)
        end,
        ["X"] = function(cx, cy, gap, len, thick)
            local d = (gap+len) * 0.707
            local g = gap * 0.707
            setLine(W[1],B[1], Vector2.new(cx-d,cy-d), Vector2.new(cx-g,cy-g), thick)
            setLine(W[2],B[2], Vector2.new(cx+g,cy+g), Vector2.new(cx+d,cy+d), thick)
            setLine(W[3],B[3], Vector2.new(cx+d,cy-d), Vector2.new(cx+g,cy-g), thick)
            setLine(W[4],B[4], Vector2.new(cx-g,cy+g), Vector2.new(cx-d,cy+d), thick)
        end,
        ["Dot"] = function(cx, cy, gap, len, thick, size)
            WD[1].Position = Vector2.new(cx,cy); WD[1].Radius = size; WD[1].Color = Color3.new(1,1,1); WD[1].Visible=true
            BD[1].Position = Vector2.new(cx,cy); BD[1].Radius = size+2; BD[1].Color = Color3.new(0,0,0); BD[1].Visible=true
        end,
        ["Circle"] = function(cx, cy, gap, len, thick, size)
            WC[1].Position=Vector2.new(cx,cy); WC[1].Radius=size; WC[1].Thickness=thick; WC[1].Visible=true
            BC[1].Position=Vector2.new(cx,cy); BC[1].Radius=size+2; BC[1].Thickness=thick+2; BC[1].Color=Color3.new(0,0,0); BC[1].Visible=true
        end,
        ["CircleDot"] = function(cx, cy, gap, len, thick, size)
            WC[1].Position=Vector2.new(cx,cy); WC[1].Radius=size; WC[1].Thickness=thick; WC[1].Visible=true
            BC[1].Position=Vector2.new(cx,cy); BC[1].Radius=size+2; BC[1].Thickness=thick+2; BC[1].Color=Color3.new(0,0,0); BC[1].Visible=true
            WD[1].Position=Vector2.new(cx,cy); WD[1].Radius=2; WD[1].Color=Color3.new(1,1,1); WD[1].Visible=true
            BD[1].Position=Vector2.new(cx,cy); BD[1].Radius=4; BD[1].Color=Color3.new(0,0,0); BD[1].Visible=true
        end,
        ["Bracket"] = function(cx, cy, gap, len, thick)
            local blen = len * 0.5
            setLine(W[1],B[1], Vector2.new(cx-gap-len,cy-gap), Vector2.new(cx-gap-len+blen,cy-gap), thick)
            setLine(W[2],B[2], Vector2.new(cx-gap-len,cy-gap), Vector2.new(cx-gap-len,cy-gap+blen), thick)
            setLine(W[3],B[3], Vector2.new(cx+gap+len,cy-gap), Vector2.new(cx+gap+len-blen,cy-gap), thick)
            setLine(W[4],B[4], Vector2.new(cx+gap+len,cy-gap), Vector2.new(cx+gap+len,cy-gap+blen), thick)
            setLine(W[5],B[5], Vector2.new(cx-gap-len,cy+gap), Vector2.new(cx-gap-len+blen,cy+gap), thick)
            setLine(W[6],B[6], Vector2.new(cx-gap-len,cy+gap), Vector2.new(cx-gap-len,cy+gap-blen), thick)
            setLine(W[7],B[7], Vector2.new(cx+gap+len,cy+gap), Vector2.new(cx+gap+len-blen,cy+gap), thick)
            setLine(W[8],B[8], Vector2.new(cx+gap+len,cy+gap), Vector2.new(cx+gap+len,cy+gap-blen), thick)
        end,
        ["Sniper"] = function(cx, cy, gap, len, thick, size)
            setLine(W[1],B[1], Vector2.new(cx-gap-len*2,cy), Vector2.new(cx-gap,cy), 1)
            setLine(W[2],B[2], Vector2.new(cx+gap,cy), Vector2.new(cx+gap+len*2,cy), 1)
            setLine(W[3],B[3], Vector2.new(cx,cy-gap-len*2), Vector2.new(cx,cy-gap), 1)
            setLine(W[4],B[4], Vector2.new(cx,cy+gap), Vector2.new(cx,cy+gap+len*2), 1)
            WD[1].Position=Vector2.new(cx,cy); WD[1].Radius=2; WD[1].Color=Color3.new(1,1,1); WD[1].Visible=true
            BD[1].Position=Vector2.new(cx,cy); BD[1].Radius=4; BD[1].Color=Color3.new(0,0,0); BD[1].Visible=true
        end,
        ["CrossDot"] = function(cx, cy, gap, len, thick, size)
            setLine(W[1],B[1], Vector2.new(cx-gap-len,cy), Vector2.new(cx-gap,cy), thick)
            setLine(W[2],B[2], Vector2.new(cx+gap,cy), Vector2.new(cx+gap+len,cy), thick)
            setLine(W[3],B[3], Vector2.new(cx,cy-gap-len), Vector2.new(cx,cy-gap), thick)
            setLine(W[4],B[4], Vector2.new(cx,cy+gap), Vector2.new(cx,cy+gap+len), thick)
            WD[1].Position=Vector2.new(cx,cy); WD[1].Radius=size; WD[1].Color=Color3.new(1,1,1); WD[1].Visible=true
            BD[1].Position=Vector2.new(cx,cy); BD[1].Radius=size+2; BD[1].Color=Color3.new(0,0,0); BD[1].Visible=true
        end,
    }

    local Crosshair = GuiLibrary.Registry.renderPanel.API.CreateOptionsButton({
        Name = "Crosshair",
        Function = function(enabled)
            hideAll()
            if enabled then
                RunLoops:BindToHeartbeat("Crosshair", function()
                    local char = lplr.Character
                    local equip = char and char:FindFirstChildOfClass("Tool")
                    local hasGun = equip and equip:FindFirstChild("CurrentAmmo") ~= nil
                    hideAll()
                    if not hasGun then return end
                    local vp = Camera.ViewportSize
                    local cx, cy = vp.X / 2, vp.Y / 2
                    local gap = CrosshairGap and CrosshairGap.Value or 6
                    local len = CrosshairLength and CrosshairLength.Value or 10
                    local thick = CrosshairThickness and CrosshairThickness.Value or 2
                    local size = CrosshairSize and CrosshairSize.Value or 3
                    local style = CrosshairStyle and CrosshairStyle.Value or "Cross"
                    local fn = STYLES[style] or STYLES["Cross"]
                    fn(cx, cy, gap, len, thick, size)
                end)
            else
                RunLoops:UnbindFromHeartbeat("Crosshair")
            end
        end
    })

    CrosshairStyle = Crosshair.CreateDropdown({
        Name = "Style",
        List = {"Cross","CrossDot","T-Cross","X","Dot","Circle","CircleDot","Bracket","Sniper"},
        Default = "Cross",
    })
    CrosshairGap = Crosshair.CreateSlider({
        Name = "Gap",
        Min = 0,
        Max = 20,
        Default = 6,
        Increment = 1,
    })
    CrosshairLength = Crosshair.CreateSlider({
        Name = "Length",
        Min = 2,
        Max = 40,
        Default = 10,
        Increment = 1,
    })
    CrosshairThickness = Crosshair.CreateSlider({
        Name = "Thickness",
        Min = 1,
        Max = 6,
        Default = 2,
        Increment = 1,
    })
    CrosshairSize = Crosshair.CreateSlider({
        Name = "DotSize",
        Min = 1,
        Max = 8,
        Default = 3,
        Increment = 1,
    })
end)