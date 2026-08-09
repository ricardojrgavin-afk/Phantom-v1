local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")

local Camera = Workspace.CurrentCamera
local lplr = Players.LocalPlayer

local Utility = {lplrIsAlive = false, lplrConnections = {},lplrHumanoid = nil, lplrRoot = nil, FreeForAllMode = false}

local cleanupLplr = function()
	for _, conn in Utility.lplrConnections do
		if conn and conn.Connected then
			conn:Disconnect()
		end
	end
	table.clear(Utility.lplrConnections)
	Utility.lplrHumanoid = nil
	Utility.lplrRoot = nil
	Utility.lplrIsAlive = false
end

local bindHumanoid = function(char)
	cleanupLplr()

	local hum = char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid", 5)
	local root = char:FindFirstChild("HumanoidRootPart") or char:WaitForChild("HumanoidRootPart", 5)

	if not hum or not root then
		Utility.lplrIsAlive = false
		return
	end

	Utility.lplrHumanoid = hum
	Utility.lplrRoot = root
	Utility.lplrIsAlive = hum.Health > 0 and hum:GetState() ~= Enum.HumanoidStateType.Dead

	local connections = Utility.lplrConnections

	connections[#connections + 1] = hum.HealthChanged:Connect(function(h)
		Utility.lplrIsAlive = h > 0 and hum:GetState() ~= Enum.HumanoidStateType.Dead
	end)

	connections[#connections + 1] = hum.StateChanged:Connect(function(_, new)
		if new == Enum.HumanoidStateType.Dead then
			Utility.lplrIsAlive = false
		end
	end)

	connections[#connections + 1] = hum.Died:Connect(function()
		Utility.lplrIsAlive = false
	end)

	connections[#connections + 1] = root.AncestryChanged:Connect(function(_, parent)
		if not parent then
			Utility.lplrIsAlive = false
		end
	end)

	connections[#connections + 1] = hum.AncestryChanged:Connect(function(_, parent)
		if not parent then
			Utility.lplrIsAlive = false
		end
	end)
end

lplr.CharacterAdded:Connect(function(char)
	Utility.lplrIsAlive = false
	bindHumanoid(char)
end)

lplr.CharacterRemoving:Connect(function()
	cleanupLplr()
end)

if lplr.Character then
	task.defer(bindHumanoid, lplr.Character)
end

Utility.GetCharacter = function(plr)
	return (plr or lplr).Character
end

Utility.IsAlive = function(plr)
	plr = plr or lplr

	if plr == lplr then
		if not Utility.lplrIsAlive then return false end

		local hum = Utility.lplrHumanoid
		local root = Utility.lplrRoot
		local valid = hum and root and hum.Parent ~= nil and root.Parent ~= nil and hum.Health > 0 and hum:GetState() ~= Enum.HumanoidStateType.Dead

		if not valid then
			Utility.lplrIsAlive = false
			return false
		end

		return true
	end

	local char = plr.Character
	if not char then return false end
	local hum = char:FindFirstChildOfClass("Humanoid")
	local root = char:FindFirstChild("HumanoidRootPart")
	return hum ~= nil and root ~= nil and hum.Health > 0 and hum:GetState() ~= Enum.HumanoidStateType.Dead
end

Utility.IsEnemy = function(plr, teamCheck)
	if not plr or plr == lplr then return false end
	if teamCheck == false or Utility.FreeForAllMode then return true end
	local t1, t2 = plr.Team, lplr.Team
	if not t1 or not t2 then return true end
	return t1.TeamColor ~= t2.TeamColor
end

Utility.IsVisible = function(a, b)
	return Workspace:Raycast(a, b - a) == nil
end

Utility.GetNearestEntities = function(maxDist, teamCheck, wallCheck)
	local results = {}
	local myChar = Utility.GetCharacter()
	if not Utility.IsAlive() or not myChar then return results end
	local myRoot = myChar:FindFirstChild("HumanoidRootPart")
	if not myRoot then return results end

	for _, plr in Players:GetPlayers() do
		if plr ~= lplr and Utility.IsAlive(plr) and Utility.IsEnemy(plr, teamCheck) then
			local root = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
			if root then
				local dist = (root.Position - myRoot.Position).Magnitude
				if dist <= maxDist and (not wallCheck or Utility.IsVisible(myRoot.Position, root.Position)) then
					table.insert(results, {
						player = plr,
						character = plr.Character,
						distance = dist,
						health = plr.Character:FindFirstChildOfClass("Humanoid").Health,
					})
				end
			end
		end
	end

	table.sort(results, function(a, b) return a.distance < b.distance end)
	return results
end

Utility.GetNearestEntity = function(maxDist, teamCheck, wallCheck)
	return Utility.GetNearestEntities(maxDist, teamCheck, wallCheck)[1]
end

Utility.GetEntityNearMouse = function(fov, teamCheck)
	local mouse = UserInputService:GetMouseLocation()
	local closest, dist = nil, fov

	for _, plr in Players:GetPlayers() do
		if plr ~= lplr and Utility.IsAlive(plr) and Utility.IsEnemy(plr, teamCheck) then
			local root = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
			if root then
				local pos, vis = Camera:WorldToViewportPoint(root.Position)
				if vis then
					local m = (Vector2.new(pos.X, pos.Y) - mouse).Magnitude
					if m < dist then
						dist = m
						closest = plr
					end
				end
			end
		end
	end

	return closest
end

return Utility