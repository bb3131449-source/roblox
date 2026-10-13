-- portal/teleport.lua
local M = ...
local F, C, S, X = M.F, M.C, M.S, M.X
local RunService = game:GetService("RunService")
local BAD_STATES, BODY_FOOT_MARGIN, BODY_HEAD, BODY_WIDTH, CEILING_DROP, EXIT_CLEARANCE = C.BAD_STATES, C.BODY_FOOT_MARGIN, C.BODY_HEAD, C.BODY_WIDTH, C.CEILING_DROP, C.EXIT_CLEARANCE
local FLOOR_NORMAL, LATERAL_RADII, LIFT_STEPS, LOCKED_STATES, MAX_EXIT_SPEED, MAX_LATERAL = C.FLOOR_NORMAL, C.LATERAL_RADII, C.LIFT_STEPS, C.LOCKED_STATES, C.MAX_EXIT_SPEED, C.MAX_LATERAL
local PUSH_STEPS, R6_LEG_HEIGHT, RING_DIRS, SETTLE_TIME, TELEPORT_COOLDOWN, TOSS_SPEED = C.PUSH_STEPS, C.R6_LEG_HEIGHT, C.RING_DIRS, C.SETTLE_TIME, C.TELEPORT_COOLDOWN, C.TOSS_SPEED
local WALL_EXIT, WALL_PUSH = C.WALL_EXIT, C.WALL_PUSH

-- TELEPORT
function F.standHeight(hum, root)
	local leg = hum.RigType == Enum.HumanoidRigType.R6 and R6_LEG_HEIGHT or 0
	return hum.HipHeight + root.Size.Y / 2 + leg
end

function F.bodyBox(pos, stand)
	local bottom, top = pos.Y - stand + BODY_FOOT_MARGIN, pos.Y + BODY_HEAD
	return Vector3.new(pos.X, (bottom + top) / 2, pos.Z), Vector3.new(BODY_WIDTH, top - bottom, BODY_WIDTH)
end

function F.snapToGround(pos, stand, ignore)
	local hit = F.mapCast(pos + Vector3.new(0, 2, 0), Vector3.new(0, -(stand + 4), 0), ignore)
	if hit and hit.Normal.Y > 0.5 then
		local minY = hit.Position.Y + stand + 0.05
		if pos.Y < minY then return Vector3.new(pos.X, minY, pos.Z) end
	end
	return pos
end

function F.findClearPosition(pos, stand, normal, ignore)
	for _, radius in ipairs(LATERAL_RADII) do
		local dirs = radius == 0 and { Vector3.zero } or RING_DIRS
		for _, lift in ipairs(LIFT_STEPS) do
			for _, push in ipairs(PUSH_STEPS) do
				for _, dir in ipairs(dirs) do
					local candidate = pos + dir * radius + normal * push + Vector3.new(0, lift, 0)
					local center, size = F.bodyBox(candidate, stand)
					if F.isClear(center, size, ignore) then return candidate end
				end
			end
		end
	end
	return nil
end

function F.exitTransform(s, from, to)
	local root = s.rootPart
	local n = to.cf.XVector
	local stand = F.standHeight(s.humanoid, root)
	local out = WALL_EXIT
	if n.Y > FLOOR_NORMAL then out = stand + EXIT_CLEARANCE
	elseif n.Y < -FLOOR_NORMAL then out = CEILING_DROP end

	local rel = from.cf:PointToObjectSpace(root.Position)
	local lat = Vector3.new(0, rel.Y, -rel.Z)
	if lat.Magnitude > MAX_LATERAL then lat = lat.Unit * MAX_LATERAL end
	local pos = to.cf:PointToWorldSpace(Vector3.new(out, lat.Y, lat.Z))

	local function through(v)
		local l = from.cf:VectorToObjectSpace(v)
		return to.cf:VectorToWorldSpace(Vector3.new(-l.X, l.Y, -l.Z))
	end
	local rootLook = F.flatten(root.CFrame.LookVector, Vector3.new(0, 0, -1))
	local look = F.flatten(through(root.CFrame.LookVector), F.flatten(n, rootLook))
	local vel = through(root.AssemblyLinearVelocity)
	local want = n.Y > FLOOR_NORMAL and TOSS_SPEED or (n.Y < -FLOOR_NORMAL and 0 or WALL_PUSH)
	local along = vel:Dot(n)
	if along < want then vel += n * (want - along) end
	if vel.Magnitude > MAX_EXIT_SPEED then vel = vel.Unit * MAX_EXIT_SPEED end
	return pos, look, vel, stand
end

function F.setStateEnabled(hum, state, value)
	local ok, err = pcall(hum.SetStateEnabled, hum, state, value)
	if not ok then F.cmdLog("SetStateEnabled " .. tostring(state) .. ": " .. tostring(err)) end
end

function F.lockStates(hum)
	local saved = {}
	for _, state in ipairs(LOCKED_STATES) do
		local ok, was = pcall(hum.GetStateEnabled, hum, state)
		if ok then
			saved[state] = was
			F.setStateEnabled(hum, state, false)
		else
			F.cmdLog("GetStateEnabled " .. tostring(state) .. ": " .. tostring(was))
		end
	end
	return function()
		if not hum.Parent then return end
		for state, was in pairs(saved) do F.setStateEnabled(hum, state, was) end
	end
end

function F.finishTeleport(s, restore)
	restore()
	local hum = s.humanoid
	if hum.Parent and BAD_STATES[hum:GetState()] then
		local target = hum.FloorMaterial == Enum.Material.Air and Enum.HumanoidStateType.Freefall or Enum.HumanoidStateType.Running
		F.safe("ChangeState", function() hum:ChangeState(target) end)
	end
	s.teleporting = false
	s.cooldownUntil = os.clock() + TELEPORT_COOLDOWN
	s.lastPos = nil
end

function F.settle(s, restore)
	local started = os.clock()
	local conn
	conn = RunService.PostSimulation:Connect(function()
		local root = s.rootPart
		if root.Parent then
			root.AssemblyAngularVelocity = Vector3.zero
			local v = root.AssemblyLinearVelocity
			if v.Magnitude > MAX_EXIT_SPEED then root.AssemblyLinearVelocity = v.Unit * MAX_EXIT_SPEED end
		end
		if os.clock() - started < SETTLE_TIME then return end
		s.bin:release(conn)
		F.finishTeleport(s, restore)
	end)
	s.bin:add(conn)
end

