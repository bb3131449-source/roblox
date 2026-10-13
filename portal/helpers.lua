-- portal/helpers.lua
local M = ...
local F, C, S, X = M.F, M.C, M.S, M.X
local TweenService = game:GetService("TweenService")
local InsertService = game:GetService("InsertService")
local GUN_ASSET_ID, PORTAL_ASSET_ID = C.GUN_ASSET_ID, C.PORTAL_ASSET_ID

-- HELPERS
function F.make(class, props, parent)
	local inst = Instance.new(class)
	for k, v in pairs(props) do inst[k] = v end
	inst.Parent = parent
	return inst
end

function F.newPart(parent, name, size, cf, color, material, shape)
	return F.make("Part", {
		Name = name, Size = size, Color = color, Material = material, Shape = shape,
		CanCollide = false, CanTouch = false, CanQuery = false, Massless = true, CFrame = cf,
	}, parent)
end

function F.play(bin, obj, time, props, style, dir)
	if bin.dead then return nil end
	local tw = F.safe("tween", function()
		return TweenService:Create(obj, TweenInfo.new(time, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	end)
	if not tw then return nil end
	bin:add(tw)
	tw.Completed:Once(function() bin:remove(tw) end)
	tw:Play()
	return tw
end

function F.flatten(v, fallback)
	local f = Vector3.new(v.X, 0, v.Z)
	return f.Magnitude > 0.001 and f.Unit or fallback
end

function F.segmentDistance(a, b, p)
	local ab = b - a
	local len2 = ab:Dot(ab)
	local t = len2 > 0 and math.clamp((p - a):Dot(ab) / len2, 0, 1) or 0
	return (a + ab * t - p).Magnitude
end

function F.collectParts(inst)
	local list = {}
	if inst:IsA("BasePart") then table.insert(list, inst) end
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("BasePart") then table.insert(list, d) end
	end
	return list
end

function F.findHandle(model)
	if model:IsA("BasePart") then return model end
	return model:FindFirstChild("Handle", true) or model:FindFirstChildWhichIsA("BasePart", true)
end

function F.alignTo(parts, anchor, target)
	local delta = target * anchor.CFrame:Inverse()
	local frames = {}
	for i, p in ipairs(parts) do frames[i] = delta * p.CFrame end
	for i, p in ipairs(parts) do p.CFrame = frames[i] end
end

function F.adopt(cloned, container)
	if cloned:IsA("BasePart") then
		cloned.Parent = container
		return
	end
	for _, c in ipairs(cloned:GetChildren()) do c.Parent = container end
	cloned:Destroy()
end

-- ассеты чужие: вырезаем из них скрипты (LocalScript внутри Tool в персонаже выполнился бы на клиенте)
function F.stripScripts(inst)
	local removed = 0
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("LuaSourceContainer") then
			removed += 1
			pcall(d.Destroy, d)
		end
	end
	return removed
end

function F.tryLoad(assetId)
	local url = "rbxassetid://" .. assetId
	local methods = {
		function() return game:GetObjects(url)[1] end,
		function() return InsertService:LoadAsset(assetId) end,
		function() return InsertService:LoadLocalAsset(url) end,
	}
	for i, method in ipairs(methods) do
		local ok, result = pcall(method)
		if ok and typeof(result) == "Instance" then
			local removed = F.stripScripts(result)
			if removed > 0 then F.cmdLog(("asset %d: removed %d script(s)"):format(assetId, removed)) end
			return result
		end
		F.cmdLog(("asset %d method %d failed: %s"):format(assetId, i, ok and "empty result" or tostring(result)))
	end
	return nil
end

S.gunTemplate = F.tryLoad(GUN_ASSET_ID)
S.portalTemplate = F.tryLoad(PORTAL_ASSET_ID)
F.cmdLog("gun: " .. (S.gunTemplate and "ok" or "FAIL") .. " | portal: " .. (S.portalTemplate and "ok" or "FAIL"))

