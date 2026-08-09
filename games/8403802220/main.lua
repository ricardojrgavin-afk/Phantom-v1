repeat task.wait() until game:IsLoaded()

local getgenv = _G.getgenv or getgenv
local readfile = _G.readfile or readfile

local Players = cloneref(game:GetService("Players"))
local StarterGui = cloneref(game:GetService("StarterGui"))
local ReplicatedStorage = cloneref(game:GetService("ReplicatedStorage"))
local TweenService = cloneref(game:GetService("TweenService"))
local UserInputService = cloneref(game:GetService("UserInputService"))
local RunService = cloneref(game:GetService("RunService"))
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

local PlayerUtility = phantom.module:Load("utility") or error("Failed to load utility module")

for _, v in ipairs({"Antideath","Gravity","ESP","AntiFall","TriggerBot","AimAssist","AutoClicker","AnimationPlayer","FastStop"}) do
    UI.kit:deregister(v .. "Module")
end

local utilAPI = GuiLibrary.Registry.utilityPanel.API

local movementAPI = GuiLibrary.Registry.movementPanel.API
local combatAPI = GuiLibrary.Registry.combatPanel.API
local visualsAPI = GuiLibrary.Registry.visualsPanel.API
local buildAPI = GuiLibrary.Registry.buildPanel.API
local inventoryAPI = GuiLibrary.Registry.inventoryPanel.API

--[[
local function getNeedlePrompts()
    local prompts = {}

    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("ProximityPrompt") and obj.Name == "ProximityPrompt" then
            local needle = obj.Parent
            if needle and needle.Name == "ColorNeedleMain" then
                table.insert(prompts, obj)
            end
        end
    end

    return prompts
end
]]

local deletedDoors = {}
buildAPI.CreateOptionsButton({
    Name = "Delete All Doors",
    Function = function(callback)
        if callback then
            table.clear(deletedDoors)

            for _, obj in ipairs(workspace:GetDescendants()) do
                if obj.Name and string.find(string.lower(obj.Name), "door") then
                    if obj.Parent then
                        table.insert(deletedDoors, {
                            Object = obj,
                            Parent = obj.Parent
                        })

                        obj.Parent = nil
                    end
                end
            end
        else
            for _, data in ipairs(deletedDoors) do
                local obj = data.Object
                local parent = data.Parent

                if obj and parent then
                    obj.Parent = parent
                end
            end

            table.clear(deletedDoors)
        end
    end
})

buildAPI.CreateOptionsButton({
    Name = "Open All Cages",
    Function = function(callback)
        if callback then
            for _, prompt in ipairs(workspace:GetDescendants()) do
                if prompt:IsA("ProximityPrompt") and string.find(string.lower(prompt.Parent.Name or ""), "cagedoor") then
                    fireproximityprompt(prompt)
                end
            end
        end
    end
})

movementAPI.CreateOptionsButton({
    Name = "Auto Sprint",
    Function = function(callback)
        if callback then
            local sprintRemote = ReplicatedStorage:WaitForChild("RemoteEvents"):WaitForChild("Miscs"):WaitForChild("SprintChange")

            RunLoops:BindToHeartbeat("AutoSprint", function()
                sprintRemote:FireServer(true)
            end)
        else
            RunLoops:UnbindFromHeartbeat("AutoSprint")
        end
    end
})

combatAPI.CreateOptionsButton({
    Name = "No Cooldown Baton",
    Function = function(callback)
        if callback then
            local baton = lplr.Backpack:FindFirstChild("Baton") or lplr.Character:FindFirstChild("Baton")
            if baton and baton:FindFirstChild("CoolDownTime") then
                baton.CoolDownTime.Value = 0
            end
        end
    end
})

buildAPI.CreateOptionsButton({
    Name = "Unlock All Cage Doors",
    Function = function(callback)
        if callback then
            local cages = workspace.Map.CageRoom.Cages:GetChildren()
            local vetCages = workspace.Map.Vets.VetCages.Cages:GetChildren()
            for _, cage in ipairs(cages) do
                local prompt = cage.Cage.CageDoor.CageDoorPrompt.ProximityPrompt
                prompt.Enabled = true
            end
            for _, cage in ipairs(vetCages) do
                local prompt = cage.Cage.CageDoor.CageDoorPrompt.ProximityPrompt
                prompt.Enabled = true
            end
        end
    end
})

utilAPI.CreateOptionsButton({
    Name = "Disable Guard Clean",
    Function = function(callback)
        if callback then
            local cleanScript = workspace:FindFirstChild(lplr.Name):FindFirstChild("GuardCleanScript")
            if cleanScript then
                cleanScript.Disabled = true
            end
        end
    end
})

combatAPI.CreateOptionsButton({
    Name = "Auto Bark & Bite",
    Function = function(callback)
        if callback then
            local barkRemote = ReplicatedStorage:WaitForChild("RemoteEvents"):WaitForChild("Dog"):WaitForChild("DogBark")
            local biteRemote = ReplicatedStorage:WaitForChild("RemoteEvents"):WaitForChild("Dog"):WaitForChild("DogBite")

            local lastBark = 0
            local lastBite = 0

            RunLoops:BindToHeartbeat("AutoBarkBite", function()
                local tickTime = tick()

                if tickTime - lastBark >= 0.2 then
                    barkRemote:FireServer()
                    lastBark = tickTime
                end

                if tickTime - lastBite >= 0.3 then
                    biteRemote:FireServer()
                    lastBite = tickTime
                end
            end)
        else
            RunLoops:UnbindFromHeartbeat("AutoBarkBite")
        end
    end
})

inventoryAPI.CreateOptionsButton({
    Name = "Remove Muzzle/Leash Restrictions",
    Function = function(callback)
        if callback then
            for _, plr in pairs(Players:GetChildren()) do
                local char = plr.Character
                if char and char:FindFirstChild("IsADog") then
                    local prompt = char.HumanoidRootPart.LeashProximityPrompt
                    if prompt then
                        prompt.Enabled = true
                        prompt.ActionText = "Leash"
                    end
                    local muzzlePrompt = char.HumanoidRootPart.MuzzleProximityPrompt
                    if muzzlePrompt then
                        muzzlePrompt.Enabled = true
                    end
                end
            end
        end
    end
})

inventoryAPI.CreateOptionsButton({
    Name = "Infinite Dog Food",
    Function = function(callback)
        if callback then
            local eatRemote = ReplicatedStorage:WaitForChild("RemoteEvents"):WaitForChild("Miscs"):WaitForChild("EatRemote")
            local lastEat = 0

            RunLoops:BindToHeartbeat("InfiniteDogFood", function()
                if tick() - lastEat >= 0.5 then
                    eatRemote:FireServer()
                    lastEat = tick()
                end
            end)
        else
            RunLoops:UnbindFromHeartbeat("InfiniteDogFood")
        end
    end
})

visualsAPI.CreateOptionsButton({
    Name = "Clear Damage Indicators",
    Function = function(callback)
        if callback then
            for _, indicator in pairs(workspace:GetDescendants()) do
                if indicator.Name == "DamageIndicator" then
                    indicator:Destroy()
                end
            end
        end
    end
})

