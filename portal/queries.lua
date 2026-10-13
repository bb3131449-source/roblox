-- portal/queries.lua
local M = ...
local F, C, S, X = M.F, M.C, M.S, M.X
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local RAYCAST_DISTANCE = C.RAYCAST_DISTANCE

-- QUERIES
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
local overlapParams = OverlapParams.new()
overlapParams.FilterType = Enum.RaycastFilterType.Exclude

function F.characterIgnore()
	local list = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then table.insert(list, p.Character) end
	end
	return list
end

function F.castRay(origin, direction, ignore)
	rayParams.FilterDescendantsInstances = ignore
	local ok, result = pcall(Workspace.Raycast, Workspace, origin, direction, rayParams)
	if not ok then
		F.cmdLog("raycast: " .. tostring(result))
		return nil
	end
	return result
end

function F.castFromScreen()
	local cam = Workspace.CurrentCamera
	if not cam then return nil end
	local m = UserInputService:GetMouseLocation()
	local ray = cam:ViewportPointToRay(m.X, m.Y)
	local ignore = F.characterIgnore()
	local dir = ray.Direction * RAYCAST_DISTANCE
	-- невидимые детали (хитбоксы, триггеры) пропускаем: портал садится на то, что видно
	for _ = 1, 8 do
		local hit = F.castRay(ray.Origin, dir, ignore)
		if not hit then return nil end
		local inst = hit.Instance
		if inst and inst:IsA("BasePart") and not inst:IsA("Terrain") and inst.Transparency >= 0.95 then
			table.insert(ignore, inst)
		else
			return hit
		end
	end
	return nil
end

function F.isClear(center, size, ignore)
	overlapParams.FilterDescendantsInstances = ignore
	local ok, parts = pcall(Workspace.GetPartBoundsInBox, Workspace, CFrame.new(center), size, overlapParams)
	if not ok then
		F.cmdLog("overlap query: " .. tostring(parts))
		return true
	end
	for _, p in ipairs(parts) do
		if p.CanCollide then return false end
	end
	return true
end

function F.alive(s)
	return s ~= nil and s == S.current and s.character.Parent ~= nil
		and s.rootPart.Parent ~= nil and s.humanoid.Health > 0
end

function F.aliveRoot(character)
	if not character or not character.Parent then return nil end
	local hum = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if hum and root and hum.Health > 0 then return root end
	return nil
end

X.rayParams = rayParams
X.overlapParams = overlapParams
