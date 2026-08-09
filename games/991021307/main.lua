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

local entity, UI, ops = phantom.entity, phantom.UI, phantom.ops
local GuiLibrary, funcs = UI, ops
local Runtime = funcs.runtime
local RunLoops = Runtime.RunLoops
local runcode = Runtime.run
local createNotification = GuiLibrary.toast


for _, v in ipairs({"AntiAFK", "Antideath", "Gravity", "FovChanger", "ESP", "Cape", "AimAssist", "AntiFall"}) do
    UI.kit:deregister(v .. "Module")
end

runcode(function()
    local zonesFolder = workspace:WaitForChild("Zones")
    local zoneList = {}
    local allZoneParts = {}
    local ZoneTPDropdown = {Value = ""}

    local safeZonePart = workspace:WaitForChild("MainMap"):WaitForChild("Model"):WaitForChild("Part")
    table.insert(zoneList, "Safe Zone")
    allZoneParts["Safe Zone"] = {safeZonePart}

    local zones = {}

    for _, zone in ipairs(zonesFolder:GetChildren()) do
        local num = tonumber(zone.Name)
        if num then
            table.insert(zones, zone)
        end
    end

    table.sort(zones, function(a, b)
        return tonumber(a.Name) < tonumber(b.Name)
    end)

    for _, zone in ipairs(zones) do
        table.insert(zoneList, zone.Name)

        allZoneParts[zone.Name] = {}

        local parts = zone:GetChildren()
        table.sort(parts, function(a, b)
            return a.Name < b.Name
        end)

        for _, part in ipairs(parts) do
            if part:IsA("BasePart") then
                table.insert(allZoneParts[zone.Name], part)
            end
        end
    end

    local ZoneTPButton
    ZoneTPButton = GuiLibrary.Registry.miscPanel.API.CreateOptionsButton({
        Name = "ZoneTP",
        Function = function(callback)
            if callback then
                local selectedZone = ZoneTPDropdown.Value
                local parts = allZoneParts[selectedZone]
                if parts and #parts > 0 then
                    lplr.Character.HumanoidRootPart.CFrame = parts[1].CFrame
                end
                ZoneTPButton.Toggle()
            end
        end
    })

    ZoneTPButton.CreateDropdown({
        Name = "Select Zone",
        List = zoneList,
        Default = zoneList[1] or "",
        Function = function(selectedZone)
            ZoneTPDropdown.Value = selectedZone
        end
    })
end)
