-- portal/tool.lua
local M = ...
local F, C, S, X = M.F, M.C, M.S, M.X
local player = M.player
local LIGHT_MIN, LIGHT_RANGE, TOOL_NAME = C.LIGHT_MIN, C.LIGHT_RANGE, C.TOOL_NAME
local Bin = X.Bin
local commands = X.commands
local globalBin = X.globalBin

-- ITEM

function F.isPortalTool(inst)
	return typeof(inst) == "Instance" and inst:IsA("Tool") and inst.Name == TOOL_NAME
end

function F.findMarked(inst, attr)
	if inst:GetAttribute(attr) then return inst end
	for _, d in ipairs(inst:GetDescendants()) do
		if d:GetAttribute(attr) then return d end
	end
	return nil
end

function F.isToolPoseTrack(track)
	local name = string.lower(track.Name or "")
	if string.find(name, "tool", 1, true) then return true end
	local anim = track.Animation
	if not anim then return false end
	local id = string.lower(anim.AnimationId or "")
	return string.find(id, "507768375", 1, true)
		or string.find(id, "182393478", 1, true)
		or string.find(id, "522635514", 1, true)
		or string.find(id, "522638767", 1, true)
end

function F.suppressToolPose(humanoid, bin)
	local function sweep()
		local function kill(track)
			if F.isToolPoseTrack(track) then pcall(function() track:Stop(0) end) end
		end
		local animator = humanoid:FindFirstChildOfClass("Animator")
		if animator then
			for _, track in ipairs(animator:GetPlayingAnimationTracks()) do kill(track) end
		end
		local ok, tracks = pcall(function() return humanoid:GetPlayingAnimationTracks() end)
		if ok and tracks then
			for _, track in ipairs(tracks) do kill(track) end
		end
	end
	sweep()
	bin:add(humanoid.AnimationPlayed:Connect(function(track)
		if F.isToolPoseTrack(track) then pcall(function() track:Stop(0) end) end
	end))
	bin:delay(0, sweep)
	bin:delay(0.05, sweep)
	bin:delay(0.2, sweep)
end

function F.holdGun(s, tool)
	if not F.alive(s) or s.holding or not tool or tool.Parent ~= s.character then return end
	local model = tool:FindFirstChild("PortalDevice")
	if not model then return end
	local root = F.findMarked(model, "PortalRoot")
	local lens = F.findMarked(model, "PortalMuzzle")
	if not root or not lens or not s.hand.Parent or not s.shoulder.Parent then return end

	local gunBin = Bin.new()
	s.gunBin = gunBin
	s.holding = true
	s.heldTool = tool
	s.lens = lens
	s.light = lens:FindFirstChildOfClass("PointLight")
	s.sound = lens:FindFirstChildOfClass("Sound")
	gunBin:add(function()
		if s.shoulder.Parent then s.shoulder.C0 = s.baseC0 end
	end)

	local rootCFrame = s.hand.CFrame * s.offset
	F.alignTo(F.collectParts(model), root, rootCFrame)
	local weld = F.safe("gun weld", F.make, "Weld", { Part0 = s.hand, Part1 = root, C0 = s.offset }, root)
	if not weld then
		s.holding = false
		s.heldTool = nil
		s.lens, s.light, s.sound = nil, nil, nil
		s.gunBin = nil
		gunBin:clean()
		F.hideGunModel(model)
		F.applyGunVisibility()
		return
	end
	gunBin:add(weld)
	F.showGunModel(model)
	F.suppressToolPose(s.humanoid, gunBin)
	F.applyGunVisibility()
end

function F.releaseGun(s)
	if not s or not s.holding then return end
	s.holding = false
	s.shotId += 1
	if s.armTween then
		pcall(function() s.armTween:Cancel() end)
		s.armTween = nil
	end
	if s.light then
		s.light.Brightness = LIGHT_MIN
		s.light.Range = LIGHT_RANGE
	end
	local tool = s.heldTool
	local model = tool and tool:FindFirstChild("PortalDevice")
	if model then F.hideGunModel(model) end
	s.heldTool = nil
	s.lens, s.light, s.sound = nil, nil, nil
	local gunBin = s.gunBin
	s.gunBin = nil
	if gunBin then gunBin:clean() end
	F.applyGunVisibility()
end

function F.onGunUnequipped(tool)
	if S.pendingTool == tool then S.pendingTool = nil end
	if S.current and S.current.heldTool == tool then F.releaseGun(S.current) end
end

function F.onGunEquipped(tool)
	S.pendingTool = tool
	if S.current and tool.Parent == S.current.character then F.holdGun(S.current, tool) end
end

function F.bindTool(tool)
	if S.boundTools[tool] or not F.isPortalTool(tool) then return end
	S.boundTools[tool] = true
	globalBin:add(tool.Equipped:Connect(function()
		F.onGunEquipped(tool)
	end))
	globalBin:add(tool.Unequipped:Connect(function()
		F.onGunUnequipped(tool)
	end))
	globalBin:add(tool.AncestryChanged:Connect(function()
		if tool.Parent ~= player.Character then F.onGunUnequipped(tool) end
	end))
	globalBin:add(tool.Destroying:Connect(function()
		S.boundTools[tool] = nil
		F.onGunUnequipped(tool)
	end))
	if tool.Parent == player.Character then F.onGunEquipped(tool) end
end

function F.collectTools()
	local list = {}
	local function take(container)
		if not container then return end
		for _, child in ipairs(container:GetChildren()) do
			if F.isPortalTool(child) then table.insert(list, child) end
		end
	end
	take(player:FindFirstChild("Backpack"))
	take(player.Character)
	return list
end

function F.dedupeTools()
	local list = F.collectTools()
	if #list <= 1 then return end
	local keep = list[1]
	local character = player.Character
	for _, tool in ipairs(list) do
		if character and tool.Parent == character then
			keep = tool
			break
		end
	end
	for _, tool in ipairs(list) do
		if tool ~= keep then tool:Destroy() end
	end
end

function F.watchTools(container)
	if not container or S.watchedContainers[container] then return end
	S.watchedContainers[container] = true
	globalBin:add(container.ChildAdded:Connect(function(child)
		if not F.isPortalTool(child) then return end
		F.bindTool(child)
		F.dedupeTools()
	end))
	for _, child in ipairs(container:GetChildren()) do
		if F.isPortalTool(child) then F.bindTool(child) end
	end
	F.dedupeTools()
end

function F.buildPortalTool()
	local tool = F.make("Tool", {
		Name = TOOL_NAME,
		RequiresHandle = true,
		CanBeDropped = false,
		ManualActivationOnly = true,
	})
	local handle = F.newPart(tool, "Handle", Vector3.new(0.2, 0.2, 0.2), CFrame.new(), Color3.fromRGB(112, 116, 125), Enum.Material.SmoothPlastic)
	handle.Transparency = 1
	handle.CastShadow = false
	local gun = F.buildGun(CFrame.new())
	if not gun then
		tool:Destroy()
		return nil
	end
	gun.model.Parent = tool
	return tool
end

function F.ensureStarter()
	if not S.toolTemplate or not S.toolEnabled then return end
	local sg = player:FindFirstChild("StarterGear")
	if not sg then return end
	local found = false
	for _, child in ipairs(sg:GetChildren()) do
		if F.isPortalTool(child) then
			if not found then found = true else child:Destroy() end
		end
	end
	if found then return end
	local copy = S.toolTemplate:Clone()
	local ok, err = pcall(function() copy.Parent = sg end)
	if not ok then
		F.cmdLog("StarterGear: " .. tostring(err))
		copy:Destroy()
	end
end

function F.grantTool()
	if not S.toolTemplate or not S.toolEnabled then return end
	if #F.collectTools() > 0 then
		F.dedupeTools()
		return
	end
	local backpack = player:FindFirstChild("Backpack")
	if not backpack then return end
	local tool = S.toolTemplate:Clone()
	F.bindTool(tool)
	tool.Parent = backpack
	if not S.toolGivenLogged then
		S.toolGivenLogged = true
		F.cmdLog("Portal gun given")
	end
end

function F.maintainTool(character)
	F.watchTools(character)
	task.spawn(function()
		for _ = 1, 12 do
			if player.Character ~= character or not S.toolEnabled then return end
			F.ensureStarter()
			F.grantTool()
			if #F.collectTools() > 0 then return end
			task.wait(0.25)
		end
	end)
end

function F.removeToolInstances()
	local tools = {}
	for tool in pairs(S.boundTools) do table.insert(tools, tool) end
	for _, tool in ipairs(F.collectTools()) do
		if not table.find(tools, tool) then table.insert(tools, tool) end
	end
	for _, tool in ipairs(tools) do pcall(function() tool:Destroy() end) end
	local sg = player:FindFirstChild("StarterGear")
	if sg then
		for _, child in ipairs(sg:GetChildren()) do
			if F.isPortalTool(child) then pcall(function() child:Destroy() end) end
		end
	end
end

function F.destroyPortalTools()
	F.removeToolInstances()
	if S.toolTemplate then
		pcall(function() S.toolTemplate:Destroy() end)
		S.toolTemplate = nil
	end
end

commands.give = function()
	S.toolEnabled = true
	local backpack = player:FindFirstChild("Backpack")
	if backpack then F.watchTools(backpack) end
	if player.Character then F.watchTools(player.Character) end
	F.ensureStarter()
	F.grantTool()
	F.cmdLog(#F.collectTools() > 0 and "gun given (kept after reset)" or "give failed: no backpack or template")
end

commands.take = function()
	S.toolEnabled = false
	F.removeToolInstances()
	F.cmdLog("gun removed (will not return after reset)")
end

