-- repeat
--     task.wait()
-- until game:IsLoaded()

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

--local PlayerUtility = loadstring(readfile("Phantom/lib/Utility.lua"))() no worky for this game
--local WhitelistModule = loadstring(game:HttpGet("https://raw.githubusercontent.com/XzynAstralz/Aristois/main/Librarys/Whitelist.lua"))()
local DrawLibrary = nil
local entity, UI, ops = phantom.entity, phantom.UI, phantom.ops

local GuiLibrary, funcs = UI, ops  -- compat aliases
local Runtime = funcs.runtime
local RunLoops = Runtime.RunLoops
local runcode = Runtime.run
local createNotification = GuiLibrary.toast
--shared.WhitelistFile = WhitelistModule
getgenv().SecureMode = true

local newData = {
    charStats = {},
    connections = {}
}


local force = --[[ setmetatable({
    funny = "require.table",
    remotes = {
        PickupRemote = "path",
    },
})--]]

runcode(function()
    local Damage = {}
    local DamageBooster = {}
    local originalNamecall = nil
    DamageBooster = GuiLibrary.Registry.combatPanel.API.CreateOptionsButton({
        Name = "DamageBooster",
        Function = function(callback)
            if callback then
                originalNamecall = hookmetamethod(game, "__namecall", function(self, ...)
                    if not checkcaller() then
                        if getnamecallmethod() == "FireServer" then
                            if self.Name == "CombatRemoteEvent" then
                                local args = {...}
                                if args[1] == "HitHumans" or args[2] == "HitHumans" then
                                    for i=1, Damage.Value do
                                        originalNamecall(self, ...)
                                    end
                                end
                            end;
                        end;
                    end;
                    return originalNamecall(self, ...)
                end);
            else
                if originalNamecall then
                    hookmetamethod(game, "__namecall", originalNamecall)
                end
            end
        end
    })
    Damage = DamageBooster.CreateSlider({
        Name = "Damage",
        Min = 1,
        Max = 4,
        Default = 1,
        Round = 0
    })
end)

runcode(function()
    local ReachSlider = {}
    local Reach = {}
    local originalAttackFunction = nil
    local toggleConnection = nil
    local Reach = GuiLibrary.Registry.combatPanel.API.CreateOptionsButton({
        Name = "Reach",
        Function = function(callback)
            if callback then
                local function overrideAttack(healthComponent)
                    local localCombat = healthComponent:WaitForChild("LocalCombat")
                    local scriptEnv = getsenv(localCombat)
                    local originalAttack = scriptEnv.Attack
                    scriptEnv.Attack = function(...)
                        local args = { ... }
                        args[2] = Vector3.new(ReachSlider.Value, ReachSlider.Value, ReachSlider.Value)
                        return originalAttack(unpack(args))
                    end
                end
                local player = game.Players.LocalPlayer
                local character = player.Character or player.CharacterAdded:Wait()
                overrideAttack(character:WaitForChild("Health"))
                toggleConnection = player.CharacterAdded:Connect(function(newCharacter)
                    task.wait(1)
                    overrideAttack(newCharacter:WaitForChild("Health"))
                end)
            else
                if toggleConnection then
                    toggleConnection:Disconnect()
                    toggleConnection = nil
                end
            end
        end
    })
    ReachSlider = Reach.CreateSlider({
        Name = "Reach",
        Min = 8,
        Max = 30,
        Default = 12,
        Round = 0
    })
end)

runcode(function()
    local FreezeAll = {}
    FreezeAll = GuiLibrary.Registry.blatantPanel.API.CreateOptionsButton({
        Name = "FreezeAll (Ravenger)",
        Function = function(callback)
            if callback then
                local combatRemote = workspace:WaitForChild(game.Players.LocalPlayer.Name):WaitForChild("CombatRemoteEvent")
                local frozenPlayers = {}
                local allSameTeam = true
                for _, p in pairs(game.Players:GetPlayers()) do
                    if p.Team ~= lplr.Team then
                        allSameTeam = false
                        break
                    end
                end
                for _, p in pairs(game.Players:GetPlayers()) do
                    local char = p.Character
                    if p ~= lplr and char and char:FindFirstChild("HumanoidRootPart") then
                        if not allSameTeam and p.Team ~= lplr.Team then
                            combatRemote:FireServer("HitHumans", char.Humanoid, "Skill2B", 10000, "kHIG", true)
                            table.insert(frozenPlayers, p)
                        elseif allSameTeam then
                            combatRemote:FireServer("HitHumans", char.Humanoid, "Skill2B", 10000, "kHIG", true)
                            table.insert(frozenPlayers, p)
                        end
                    end
                end
                if #frozenPlayers > 0 then
                    game:GetService("TeleportService"):Teleport(game.PlaceId, lplr)
                end
                FreezeAll.Toggle(false)
            end
        end
    })
end)

runcode(function()
    local AutoBoss = {}
    AutoBoss = GuiLibrary.Registry.blatantPanel.API.CreateOptionsButton({
        Name = "AutoBoss",
        Function = function(callback)
            if callback then
                local function monitorUnusualBills()
                    for _, folder in pairs(workspace.Current:GetChildren()) do
                        if folder:IsA("Folder") then
                            for _, bill in pairs(folder:GetChildren()) do
                                if bill.Name == "UnusualBill" then
                                    bill:GetPropertyChangedSignal("Transparency"):Connect(function()
                                        if bill.Transparency ~= 1 then
                                            lplr.Character:SetPrimaryPartCFrame(CFrame.new(bill.Position))
                                        end
                                    end)
                                end
                            end
                        end
                    end
                end
                monitorUnusualBills()
            end
        end
    })
end)
