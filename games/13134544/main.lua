repeat task.wait() until game:IsLoaded()

local getgenv = _G.getgenv or getgenv
local readfile = _G.readfile or readfile

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

local phantom = getgenv().phantom
local entity, UI, ops = phantom.entity, phantom.UI, phantom.ops
local GuiLibrary, funcs = UI, ops
local Runtime = funcs.runtime
local RunLoops = Runtime.RunLoops
local runcode = Runtime.run
local createNotification = GuiLibrary.toast

local PlayerUtility = phantom.module:Load("utility") or loadstring(readfile("Phantom/lib/Utility.lua"))()

for _, v in ipairs({"Antideath", "Gravity", "ESP", "AntiFall", "AimAssist", "BreadCrumbs"}) do
    UI.kit:deregister(v .. "Module")
end

local foundSwords = {}

local function findClosestMatch(name)
    for _, item in ipairs(lplr.Character:GetChildren()) do
        if item.Name:find(name) then return item end
    end
    for _, item in ipairs(lplr.Backpack:GetChildren()) do
        if item.Name:find(name) then return item end
    end
end

local function GetSword()
    if not foundSwords.Sword then
        local m = findClosestMatch("Sword")
        if m then foundSwords.Sword = m.Name end
    end
    return foundSwords.Sword
end

local function IsSwordEquipped()
    local chr = lplr.Character
    local name = GetSword()
    if not chr or not name then return false end
    for _, item in ipairs(chr:GetChildren()) do
        if item.Name == name and item:IsA("Tool") then return true end
    end
    return false
end

local remotes = { AttackRemote = ReplicatedStorage.Modules.Knit.Services.ToolService.RF.AttackPlayerWithSword }
local Distance = {Value = 21}

runcode(function()
    local adornments, Killaura, LegitAura, ShowTarget, swordtype = {}, {}, {}, {}, nil
    local data = {Attacking = false, attackingEntity = nil}
    local lastClick = 0

    local function clear()
        for _, v in ipairs(adornments) do v.Adornee = nil end
    end

    local function attack(entity)
        if entity and swordtype then remotes.AttackRemote:InvokeServer(entity, true, swordtype) end
    end

    local function reset()
        data.Attacking = false
        data.attackingEntity = nil
        clear()
    end

    UserInputService.InputBegan:Connect(function(input, gpe)
        if not gpe and LegitAura.Enabled and input.UserInputType == Enum.UserInputType.MouseButton1 then
            lastClick = os.clock()
        end
    end)

    Killaura = GuiLibrary.Registry.combatPanel.API.CreateOptionsButton({
        Name = "Killaura",
        Beta = true,
        Function = function(callback)
            if not callback then clear() return RunLoops:UnbindFromHeartbeat("Killaura") end
            RunLoops:BindToHeartbeat("Killaura", function()
                if not PlayerUtility.IsAlive() or not IsSwordEquipped() then return reset() end
                if LegitAura.Enabled and not UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) and (os.clock() - lastClick) > 0.05 then return reset() end

                local nearest = PlayerUtility.GetNearestEntities(Distance.Value, false, false)
                if #nearest == 0 then return reset() end

                local entity = nearest[1].character
                local root = entity and entity:FindFirstChild("HumanoidRootPart")
                local hum = entity and entity:FindFirstChildOfClass("Humanoid")
                if not root or not hum or hum.Health <= 0 then return reset() end

                swordtype = swordtype or GetSword()
                data.Attacking = true
                data.attackingEntity = entity
                attack(entity)

                for i, v in ipairs(adornments) do
                    local e = nearest[i]
                    local ec = e and e.character
                    local er = ec and ec:FindFirstChild("HumanoidRootPart")
                    local eh = ec and ec:FindFirstChildOfClass("Humanoid")
                    v.Adornee = (ShowTarget.Enabled and eh and eh.Health > 0 and er) or nil
                end
            end, 0.2)
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
    LegitAura = Killaura.CreateToggle({
        Name = "Semi",
        Default = true,
    })
end)

--[[runcode(function()
    local lastBowFireTime = 0
    local firing = false
    local BowCooldown = 3

    local arrowSpeed = {Value = 120}
    local distance = {Value = 100}
    local gravityEffect = {Value = 30}

    local function canshoot()
        return tick() - lastBowFireTime >= BowCooldown
    end

    local function isVisible(entity)
        local origin = lplr.Character.HumanoidRootPart.Position
        local target = entity.character.HumanoidRootPart.Position

        local ray = Ray.new(origin, (target - origin))
        local hit = workspace:FindPartOnRay(ray, lplr.Character)

        return hit == nil or hit:IsDescendantOf(entity.character)
    end

    local function avoidParts(entity, position)
        local origin = lplr.Character.HumanoidRootPart.Position
        local ray = Ray.new(origin, (position - origin))

        local hit, hitPos = workspace:FindPartOnRay(ray, lplr.Character)
        if hit and not hit:IsDescendantOf(entity.character) then
            return hitPos + (hit.Position - hitPos).Unit * 5
        end

        return position
    end

    local function setup()
        if lplr.Character then
            lplr.Character:WaitForChild("Humanoid").Died:Connect(function()
                firing = false
            end)
        end
    end

    setup()
    lplr.CharacterAdded:Connect(function(character)
        character:WaitForChild("Humanoid").Died:Connect(function()
            firing = false
        end)
        setup()
    end)

    local function predictPosition(entity)
        local root = entity.character.HumanoidRootPart
        local myRoot = lplr.Character.HumanoidRootPart

        local targetPosition = root.Position
        local flightTime = (targetPosition - myRoot.Position).Magnitude / arrowSpeed.Value

        local predicted = targetPosition
            + (root.Velocity * flightTime)
            + (0.5 * Vector3.new(0, gravityEffect.Value, 0) * flightTime^2)

        return avoidParts(entity, predicted)
    end

    local ProjectileAura = GuiLibrary.Registry.combatPanel.API.CreateOptionsButton({
        Name = "ProjectileAura",
        Function = function(callback)
            if callback then
                RunLoops:BindToHeartbeat("ProjectileAura", function()
                    local entities = PlayerUtility.GetNearestEntities(distance.Value, false, false)
                    local nearest = entities[1]

                    if not nearest then return end

                    if nearest.character:FindFirstChild("ForceField") then return end

                    if not isVisible(nearest) then return end

                    if canshoot() and not firing then
                        firing = true
                        
                        print("work")
                        lplr.Character:WaitForChild("DefaultBow"):WaitForChild("__comm__"):WaitForChild("RF"):WaitForChild("Fire"):InvokeServer(
                            predictPosition(nearest),
                            math.huge
                        )

                        lastBowFireTime = tick()
                        task.wait(0.25)
                        firing = false
                    end
                end)
            else

            end
        end
    })
    ProjectileAura.CreateSlider({
        Name = "distance",
        Min = 1,
        Max = 100,
        Default = 100,
        Round = 1,
        Function = function(Value)
            distance.Value = Value
        end
    })
    ProjectileAura.CreateSlider({
        Name = "arrowSpeed",
        Min = 1,
        Max = 300,
        Default = 120,
        Round = 1,
        Function = function(Value)
            arrowSpeed.Value = Value
        end
    })
    ProjectileAura.CreateSlider({
        Name = "gravityEffect",
        Min = 1,
        Max = 196,
        Default = 30,
        Round = 1,
        Function = function(Value)
            gravityEffect.Value = Value
        end
    })
end)--]]
