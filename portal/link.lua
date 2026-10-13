-- portal/link.lua
local M = ...
local F, C, S, X = M.F, M.C, M.S, M.X
local BOLT_TIME, EXIT_CLEARANCE, OPEN_TIME, TELEPORT_COOLDOWN, TOSS_SPEED, TP_COMMAND_DELAY = C.BOLT_TIME, C.EXIT_CLEARANCE, C.OPEN_TIME, C.TELEPORT_COOLDOWN, C.TOSS_SPEED, C.TP_COMMAND_DELAY

-- LINK: вход рядом с вами, выход по resolve(); resolve() -> hit | nil, причина
function F.runLink(label, resolve)
	local s = S.current
	if not F.alive(s) then F.cmdLog("no local character") return end
	local exitHit, why = resolve()
	if not exitHit then F.cmdLog(why or "no destination") return end
	local entryHit = F.findSpot(s.rootPart)
	if not entryHit then
		F.notify("No free space near you")
		F.cmdLog("no free space near you")
		return
	end

	F.destroyAllPortals()
	F.resetPlacement()
	if not F.placeHorizontal(entryHit, 1) then
		F.destroyAllPortals()
		F.cmdLog("failed to build entrance")
		return
	end
	local epoch = S.portalEpoch

	task.wait(TP_COMMAND_DELAY)
	if epoch ~= S.portalEpoch or S.current ~= s or not F.alive(s) then
		if epoch == S.portalEpoch then F.destroyAllPortals() end
		F.cmdLog("link aborted")
		return
	end
	local exitHit2, why2 = resolve()
	if not exitHit2 or not F.placeHorizontal(exitHit2, 2) then
		F.destroyAllPortals()
		F.cmdLog(why2 or "failed to build exit")
		return
	end
	F.cmdLog("portals linked: you <-> " .. label)
end

-- ARRIVAL: в новом плейсе показывает портал выхода и выпускает через него персонажа
function F.runArrival(data)
	if not game:IsLoaded() then game.Loaded:Wait() end
	local s
	local deadline = os.clock() + 20
	while os.clock() < deadline do
		if F.alive(S.current) then s = S.current break end
		task.wait(0.1)
	end
	if not s then F.cmdLog("arrival: no character") return end
	local t0 = os.clock()
	while F.alive(s) and s.humanoid.FloorMaterial == Enum.Material.Air and os.clock() - t0 < 4 do task.wait(0.1) end
	if not F.alive(s) then return end
	task.wait(0.2)
	if not F.alive(s) then return end

	s.teleporting = true
	local function release()
		if S.current == s then
			s.teleporting = false
			s.cooldownUntil = os.clock() + TELEPORT_COOLDOWN
		end
	end

	local hit = F.findSpot(s.rootPart)
	if not hit then F.cmdLog("arrival: no free space, portal skipped") release() return end
	F.destroyAllPortals()
	F.resetPlacement()
	local portal = F.placeHorizontal(hit, 2, data.returnPortal and { placeId = data.from } or nil)
	if not portal then release() return end
	F.lockPortals(s, portal) -- с ARRIVAL_RETURN_PORTAL = true иначе сразу уносило бы обратно
	local epoch = S.portalEpoch

	task.wait(OPEN_TIME + BOLT_TIME + 0.1)
	if epoch ~= S.portalEpoch or not F.alive(s) then release() return end

	local ignore = F.characterIgnore()
	local stand = F.standHeight(s.humanoid, s.rootPart)
	local n = portal.cf.XVector
	local pos = F.snapToGround(portal.cf.Position + n * (stand + EXIT_CLEARANCE), stand, ignore)
	pos = F.findClearPosition(pos, stand, n, ignore) or pos
	local look = F.flatten(s.rootPart.CFrame.LookVector, Vector3.new(0, 0, -1))
	local finalCF = CFrame.lookAt(pos, pos + look)
	local vel = n * TOSS_SPEED

	local restore = F.lockStates(s.humanoid)
	local ghost = F.makeGhost(s.character)
	if not ghost then
		F.instantTeleport(s, finalCF, vel, restore)
		return
	end
	F.travel(s, nil, portal, finalCF, vel, restore, ghost)
end

