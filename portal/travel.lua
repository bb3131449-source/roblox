-- portal/travel.lua
local M = ...
local F, C, S, X = M.F, M.C, M.S, M.X
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")
local FLOOR_NORMAL, STRETCH_MAX, TELEPORT_COOLDOWN = C.FLOOR_NORMAL, C.STRETCH_MAX, C.TELEPORT_COOLDOWN

-- TRAVEL ANIMATIONS
-- Четыре анимации: vertical enter / vertical exit / horizontal enter / horizontal exit.
-- Настоящий персонаж на время перехода скрыт и заморожен, анимацию играет его клон ("призрак").
-- Isolated in an IIFE so the many locals here don't exhaust the main chunk's 200-register limit.
F.makeGhost, F.travel, F.travelOut = (function()
	local GHOST_MIN, GHOST_START = 0.12, 0.2
	local Debris = game:GetService("Debris")

	local function clamp01(x) return math.clamp(x, 0, 1) end
	local function lerp(a, b, t) return a + (b - a) * t end
	local function smooth(x)
		x = clamp01(x)
		return x * x * (3 - 2 * x)
	end
	local function outCubic(x) return 1 - (1 - x) ^ 3 end
	local function outBack(x, c1)
		local t = x - 1
		return 1 + (c1 + 1) * t * t * t + c1 * t * t
	end

	-- c = { C = центр портала, n = нормаль портала, cf0 = поза корня (старт для входа / финал для выхода) }
	-- каждая pose возвращает: CFrame корня, масштаб, видимость (0..1)

	-- 1) ВЕРТИКАЛЬНЫЙ ВХОД (портал на стене): тело закручивается вокруг нормали и втягивается в плоскость
	local function poseVerticalEnter(c, a)
		local e = a ^ 1.8
		local off = c.cf0.Position - c.C
		local nc = off:Dot(c.n)
		local lat = off - c.n * nc
		local R = CFrame.fromAxisAngle(c.n, math.pi * 0.9 * e)
		local pos = c.C + R:VectorToWorldSpace(lat * (1 - e)) + c.n * lerp(nc, -0.6, e)
		return CFrame.new(pos) * R * c.cf0.Rotation, lerp(1, 0.22, e), 1 - smooth((a - 0.7) / 0.3)
	end

	-- 2) ВЕРТИКАЛЬНЫЙ ВЫХОД: скользит из стены, раскручивается, масштаб с небольшим "поп"-перелётом
	local function poseVerticalExit(c, a)
		local e = a ^ 1.25
		local pos = (c.C - c.n * 0.8):Lerp(c.cf0.Position, e)
		local R = CFrame.fromAxisAngle(c.n, -math.pi * 0.9 * (1 - e))
		local k = GHOST_START + (1 - GHOST_START) * outBack(a, 1.3)
		return CFrame.new(pos) * R * c.cf0.Rotation, k, smooth(a / 0.22)
	end

	-- 3) ГОРИЗОНТАЛЬНЫЙ ВХОД (портал на полу/потолке): полный оборот и проваливание в воронку
	local function poseHorizontalEnter(c, a)
		local e = a ^ 1.6
		local off = c.cf0.Position - c.C
		local nc = off:Dot(c.n)
		local lat = off - c.n * nc
		local R = CFrame.fromAxisAngle(c.n, math.pi * 2 * e)
		local pos = c.C + R:VectorToWorldSpace(lat * (1 - e)) + c.n * lerp(nc, -2.2, e)
		return CFrame.new(pos) * R * c.cf0.Rotation, lerp(1, 0.16, e), 1 - smooth((a - 0.78) / 0.22)
	end

	-- 4) ГОРИЗОНТАЛЬНЫЙ ВЫХОД: ускоряющийся выброс из портала с раскруткой.
	-- Конечная скорость (производная e^2.2 при a=1) примерно равна TOSS_SPEED, поэтому передача физике без рывка.
	local function poseHorizontalExit(c, a)
		local e = a ^ 2.2
		local pos = (c.C - c.n * 2.2):Lerp(c.cf0.Position, e)
		local R = CFrame.fromAxisAngle(c.n, -math.pi * 2 * (1 - e))
		local k = GHOST_START + (1 - GHOST_START) * outCubic(clamp01(a / 0.75))
		return CFrame.new(pos) * R * c.cf0.Rotation, k, smooth(a / 0.18)
	end

	local PROFILE = {
		verticalEnter = { time = 0.26, pose = poseVerticalEnter, fov = -4 },
		verticalExit = { time = 0.30, pose = poseVerticalExit, punch = 7 },
		horizontalEnter = { time = 0.30, pose = poseHorizontalEnter, fov = -6 },
		horizontalExit = { time = 0.36, pose = poseHorizontalExit, punch = 11 },
	}

	local function portalKind(portal)
		return math.abs(portal.cf.XVector.Y) > FLOOR_NORMAL and "horizontal" or "vertical"
	end

	-- GHOST
	local function makeGhost(character)
		local ok, ghost = pcall(function()
			local was = character.Archivable
			character.Archivable = true
			local copy = character:Clone()
			character.Archivable = was
			return copy
		end)
		if not ok or not ghost then
			F.cmdLog("ghost clone failed: " .. tostring(ghost))
			return nil
		end
		for _, d in ipairs(ghost:GetDescendants()) do
			if d:IsA("LuaSourceContainer") or d:IsA("Tool") or d:IsA("Humanoid") or d:IsA("Sound")
				or d:IsA("ForceField") or d:IsA("BillboardGui") or d:IsA("Highlight") then
				pcall(function() d:Destroy() end)
			end
		end
		local alpha = {}
		for _, d in ipairs(ghost:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Anchored, d.CanCollide, d.CanTouch, d.CanQuery, d.Massless = true, false, false, false, true
				alpha[d] = d.Transparency
			elseif d:IsA("Decal") then
				alpha[d] = d.Transparency
			end
		end
		ghost.Name = "PortalGhost"
		if not ghost.PrimaryPart then ghost.PrimaryPart = ghost:FindFirstChild("HumanoidRootPart") end
		if not ghost.PrimaryPart then
			ghost:Destroy()
			return nil
		end
		ghost.Parent = Workspace
		return { model = ghost, alpha = alpha, noScale = false }
	end

	local function poseGhost(g, cf, scale, vis)
		if not g.noScale then
			local ok = pcall(g.model.ScaleTo, g.model, math.max(scale, GHOST_MIN))
			if not ok then g.noScale = true end
		end
		g.model:PivotTo(cf)
		for inst, original in pairs(g.alpha) do
			inst.Transparency = 1 - vis * (1 - original)
		end
	end

	-- прячет настоящего персонажа (локально), возвращает apply (вызывать каждый кадр) и restore
	local function hideCharacter(character)
		local saved = {}
		for _, d in ipairs(character:GetDescendants()) do
			if d:IsA("BasePart") or d:IsA("Decal") then saved[d] = d.Transparency end
		end
		local function apply()
			for inst in pairs(saved) do
				if inst.Parent then inst.Transparency = 1 end
			end
		end
		local function restore()
			for inst, t in pairs(saved) do
				if inst.Parent then pcall(function() inst.Transparency = t end) end
			end
		end
		apply()
		return apply, restore
	end

	local function runAnim(s, duration, step, done, fail)
		local t0 = os.clock()
		local conn
		conn = RunService.RenderStepped:Connect(function()
			local a = math.clamp((os.clock() - t0) / duration, 0, 1)
			local ok, res = pcall(step, a)
			if not ok then F.cmdLog("anim: " .. tostring(res)) end
			if not ok or res == false then
				s.bin:release(conn)
				if fail then F.safe("anim fail", fail) end
				return
			end
			if a >= 1 then
				s.bin:release(conn)
				if done then F.safe("anim done", done) end
			end
		end)
		s.bin:add(conn)
	end

	local function entryEffects()
		F.playSfx("enter")
	end

	local function exitEffects()
		F.playSfx("exit")
	end

	-- SEQUENCE: вход (призрак втягивается) -> перенос скрытого тела -> выход (призрак появляется) -> физика
	-- from == nil: прибытие из другого плейса, только фаза выхода
	local function travel(s, from, to, finalCF, vel, restoreStates, ghost)
		local toKind = portalKind(to)
		local fromKind = from and portalKind(from) or nil
		local enter = fromKind and (fromKind == "horizontal" and PROFILE.horizontalEnter or PROFILE.verticalEnter) or nil
		local exit = toKind == "horizontal" and PROFILE.horizontalExit or PROFILE.verticalExit
		local root, character = s.rootPart, s.character
		local cam = Workspace.CurrentCamera
		local baseFov = cam and cam.FieldOfView
		local fovTween

		local applyHide, restoreVisible = hideCharacter(character)
		local hideConn = RunService.RenderStepped:Connect(applyHide)
		s.bin:add(hideConn)
		root.Anchored = true
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero

		local finished = false
		local function cleanup()
			if finished then return end
			finished = true
			s.bin:release(hideConn)
			if from then F.driveStretch(from, 0) end
			F.driveStretch(to, 0)
			restoreVisible()
			pcall(function() ghost.model:Destroy() end)
			if root.Parent then pcall(function() root.Anchored = false end) end
			if fovTween then pcall(function() fovTween:Cancel() end) end
			if cam and baseFov then pcall(function() cam.FieldOfView = baseFov end) end
		end
		s.bin:add(cleanup)

		local function abort()
			s.bin:release(cleanup)
			restoreStates()
			s.teleporting = false
			s.cooldownUntil = os.clock() + TELEPORT_COOLDOWN
		end

		local function fov(goal, time, style, dir)
			if not cam or not baseFov then return end
			if fovTween then fovTween:Cancel() end
			fovTween = TweenService:Create(cam, TweenInfo.new(time, style, dir), { FieldOfView = goal })
			fovTween:Play()
		end

		local function playExit()
			if not F.alive(s) then abort() return end
			if from then F.driveStretch(from, 0) end
			character:PivotTo(finalCF)
			local ctx = { C = to.cf.Position, n = to.cf.XVector, cf0 = finalCF }
			local cf0, k0, v0 = exit.pose(ctx, 0)
			poseGhost(ghost, cf0, k0, v0)
			exitEffects(to, toKind, exit.time)
			if baseFov then
				cam.FieldOfView = baseFov + exit.punch
				fov(baseFov, exit.time + 0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			end
			runAnim(s, exit.time, function(a)
				if not F.alive(s) then return false end
				local cf, k, vis = exit.pose(ctx, a)
				poseGhost(ghost, cf, k, vis)
				F.driveStretch(to, STRETCH_MAX * 0.85 * smooth(a / 0.9))
			end, function()
				F.driveStretch(to, 0)
				s.bin:release(cleanup)
				if not F.alive(s) then
					restoreStates()
					s.teleporting = false
					return
				end
				root.AssemblyAngularVelocity = Vector3.zero
				root.AssemblyLinearVelocity = vel
				F.settle(s, restoreStates)
			end, abort)
		end

		if not from then
			playExit()
			return
		end

		local ctxIn = { C = from.cf.Position, n = from.cf.XVector, cf0 = root.CFrame }
		entryEffects(from, fromKind, enter.time)
		if baseFov then fov(baseFov + enter.fov, enter.time, Enum.EasingStyle.Quad, Enum.EasingDirection.In) end
		runAnim(s, enter.time, function(a)
			if not F.alive(s) then return false end
			local cf, k, vis = enter.pose(ctxIn, a)
			poseGhost(ghost, cf, k, vis)
			F.driveStretch(from, -STRETCH_MAX * 0.9 * smooth(a / 0.7))
		end, playExit, abort)
	end

	local function travelOut(s, from, ghost, restoreStates, onReady, onAbort)
		local kind = portalKind(from)
		local enter = kind == "horizontal" and PROFILE.horizontalEnter or PROFILE.verticalEnter
		local root, character = s.rootPart, s.character

		local applyHide, restoreVisible = hideCharacter(character)
		local hideConn = RunService.RenderStepped:Connect(applyHide)
		s.bin:add(hideConn)
		root.Anchored = true
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero

		local finished = false
		local function cleanup()
			if finished then return end
			finished = true
			s.bin:release(hideConn)
			F.driveStretch(from, 0)
			restoreVisible()
			pcall(function() ghost.model:Destroy() end)
			if root.Parent then pcall(function() root.Anchored = false end) end
		end
		s.bin:add(cleanup)

		local handle = { done = false }
		function handle.cancel()
			if handle.done then return end
			handle.done = true
			s.bin:release(cleanup)
			restoreStates()
			s.teleporting = false
			s.cooldownUntil = os.clock() + TELEPORT_COOLDOWN
			if onAbort then onAbort() end
		end

		local ctxIn = { C = from.cf.Position, n = from.cf.XVector, cf0 = root.CFrame }
		entryEffects(from, kind, enter.time)
		runAnim(s, enter.time, function(a)
			if not F.alive(s) then return false end
			local cf, k, vis = enter.pose(ctxIn, a)
			poseGhost(ghost, cf, k, vis)
			F.driveStretch(from, -STRETCH_MAX * 0.9 * smooth(a / 0.7))
		end, function()
			F.driveStretch(from, 0)
			if not F.alive(s) then handle.cancel() return end
			onReady(handle)
		end, handle.cancel)
		return handle
	end

	return makeGhost, travel, travelOut
end)()

function F.instantTeleport(s, finalCF, vel, restore)
	local moved = F.safe("pivot", function()
		s.character:PivotTo(finalCF)
		return true
	end)
	if not moved then
		restore()
		s.teleporting = false
		return
	end
	s.rootPart.AssemblyAngularVelocity = Vector3.zero
	s.rootPart.AssemblyLinearVelocity = vel
	F.settle(s, restore)
end

function F.teleportThrough(from, to)
	local s = S.current
	if not F.alive(s) or s.teleporting or s.humanoid.SeatPart or from.bin.dead or to.bin.dead then return end
	s.teleporting = true
	F.lockPortals(s, from, to)

	-- запоминаем точку входа для #back
	do
		local p = s.rootPart.Position
		S.lastBack = { x = p.X, y = p.Y, z = p.Z, placeId = game.PlaceId, at = os.time() }
	end

	local ignore = F.characterIgnore()
	local pos, look, vel, stand = F.exitTransform(s, from, to)
	pos = F.snapToGround(pos, stand, ignore)
	local clear = F.findClearPosition(pos, stand, to.cf.XVector, ignore)
	if clear then pos = clear else F.cmdLog("exit crowded, forcing teleport") end

	local finalCF = CFrame.lookAt(pos, pos + look)
	local restore = F.lockStates(s.humanoid)
	local ghost = F.makeGhost(s.character)
	if not ghost then
		F.instantTeleport(s, finalCF, vel, restore)
		return
	end
	F.travel(s, from, to, finalCF, vel, restore, ghost)
end

