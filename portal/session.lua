-- portal/session.lua
local M = ...
local F, C, S, X = M.F, M.C, M.S, M.X
local Workspace = game:GetService("Workspace")
local player = M.player
local GUN_DOWN, GUN_FORWARD, GUN_LOWER, GUN_YAW, TOOL_NAME, WAIT_TIMEOUT = C.GUN_DOWN, C.GUN_FORWARD, C.GUN_LOWER, C.GUN_YAW, C.TOOL_NAME, C.WAIT_TIMEOUT
local Bin = X.Bin
local globalBin = X.globalBin

-- SESSION
function F.detach(only)
	if only and only ~= S.current then return end
	local s = S.current
	S.current = nil
	S.gen += 1
	if s then
		F.releaseGun(s)
		s.bin:clean()
	end
	F.applyGunVisibility()
end

function F.attach(character)
	F.detach()
	S.gen += 1
	local myGen = S.gen
	local function stale()
		return S.gen ~= myGen or player.Character ~= character or character.Parent == nil
	end

	local humanoid = character:WaitForChild("Humanoid", WAIT_TIMEOUT)
	if not humanoid or stale() then return end
	local isR15 = humanoid.RigType == Enum.HumanoidRigType.R15
	local hand = character:WaitForChild(isR15 and "RightHand" or "Right Arm", WAIT_TIMEOUT)
	local holder = character:WaitForChild(isR15 and "RightUpperArm" or "Torso", WAIT_TIMEOUT)
	local shoulder = holder and holder:WaitForChild(isR15 and "RightShoulder" or "Right Shoulder", WAIT_TIMEOUT)
	local rootPart = character:WaitForChild("HumanoidRootPart", WAIT_TIMEOUT)
	if stale() then return end
	if not (hand and shoulder and rootPart) then
		F.cmdLog("attach aborted: rig parts missing")
		return
	end

	local old = character:FindFirstChild("PortalDevice")
	if old then old:Destroy() end

	local baseOffset = isR15 and CFrame.new(0, -0.15 - GUN_LOWER, 0) or CFrame.new(0, -0.9 - GUN_LOWER, 0)
	local offset = baseOffset * CFrame.Angles(math.rad(-90), 0, 0) * CFrame.Angles(0, GUN_YAW, 0) * CFrame.new(0, GUN_DOWN, GUN_FORWARD)
	local baseC0 = shoulder.C0
	local bin = Bin.new()
	bin:add(function()
		if shoulder.Parent then shoulder.C0 = baseC0 end
	end)

	local s = {
		character = character, humanoid = humanoid, rootPart = rootPart,
		hand = hand, offset = offset,
		shoulder = shoulder, baseC0 = baseC0,
		lens = nil, light = nil, sound = nil,
		bin = bin, gunBin = nil, holding = false, heldTool = nil,
		shotId = 0, armTween = nil, teleporting = false, locks = {},
		spawnedAt = os.clock(), cooldownUntil = 0, lastPos = nil,
	}
	bin:add(character.AncestryChanged:Connect(function()
		if not character:IsDescendantOf(Workspace) then F.detach(s) end
	end))
	S.current = s

	local worn = character:FindFirstChild(TOOL_NAME)
	if F.isPortalTool(worn) then
		F.holdGun(s, worn)
	elseif S.pendingTool and S.pendingTool.Parent == character then
		F.holdGun(s, S.pendingTool)
	end
	F.applyGunVisibility()
end

globalBin:add(player.CharacterRemoving:Connect(function() F.detach() end))
globalBin:add(player.CharacterAdded:Connect(function(character)
	F.maintainTool(character)
	task.spawn(F.attach, character)
end))
globalBin:add(player.ChildAdded:Connect(function(child)
	if child.Name == "Backpack" then
		F.watchTools(child)
		F.grantTool()
	elseif child.Name == "StarterGear" then
		F.ensureStarter()
	end
end))

local arrival = F.takeHandoff()
if arrival and arrival.tool == false then S.toolEnabled = false end
S.toolTemplate = F.buildPortalTool()
if not S.toolTemplate then
	F.cmdLog("Portal gun build failed")
else
	-- script may be nil when the code is run via loadstring / executor
	local cacheParent = (typeof(script) == "Instance" and script) or nil
	local cache = F.make("Folder", { Name = "PortalGunCache" }, cacheParent)
	globalBin:add(cache)
	S.toolTemplate.Parent = cache
	local backpack = player:FindFirstChild("Backpack")
	if backpack then F.watchTools(backpack) end
	F.ensureStarter()
	F.grantTool()
	if not backpack then
		task.spawn(function()
			local bp = player:WaitForChild("Backpack", WAIT_TIMEOUT)
			if not bp then return end
			F.watchTools(bp)
			F.ensureStarter()
			F.grantTool()
		end)
	end
end

if player.Character then
	F.maintainTool(player.Character)
	task.spawn(F.attach, player.Character)
end

-- script is often nil in executors / loadstring; guard to avoid "attempt to index nil with 'Destroying'"
if typeof(script) == "Instance" then
	script.Destroying:Connect(function()
		F.detach()
		F.destroyAllPortals(true)
		F.destroyPortalTools()
		globalBin:clean()
	end)
end

if arrival then
	task.spawn(function()
		local ok, err = pcall(F.runArrival, arrival)
		if not ok then
			F.cmdLog("arrival: " .. tostring(err))
			if S.current then S.current.teleporting = false end
		end
	end)
end
F.cmdLog("ready. type #help in chat")

X.arrival = arrival
