-- portal/place.lua
local M = ...
local F, C, S, X = M.F, M.C, M.S, M.X
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local player = M.player
local ARRIVAL_RETURN_PORTAL, HANDOFF_FILE, HANDOFF_TTL, MAX_STEP, PLACE_MAX_TIMEOUT, PLACE_RELOAD_SOURCE = C.ARRIVAL_RETURN_PORTAL, C.HANDOFF_FILE, C.HANDOFF_TTL, C.MAX_STEP, C.PLACE_MAX_TIMEOUT, C.PLACE_RELOAD_SOURCE
local PLACE_START_TIMEOUT, SPAWN_GRACE, TELEPORT_COOLDOWN, TRIGGER_RADIUS = C.PLACE_START_TIMEOUT, C.SPAWN_GRACE, C.TELEPORT_COOLDOWN, C.TRIGGER_RADIUS
local globalBin = X.globalBin

-- PLACE TELEPORT
function F.queueFn()
	return queue_on_teleport or queueonteleport or (syn and syn.queue_on_teleport) or (fluxus and fluxus.queue_on_teleport)
end

function F.clearHandoff()
	if delfile and isfile then
		pcall(function() if isfile(HANDOFF_FILE) then delfile(HANDOFF_FILE) end end)
	end
end

function F.clearQueue()
	if not F.handoffQueued then return end
	F.handoffQueued = false
	local clear = clear_teleport_queue or (syn and syn.clear_teleport_queue)
	if clear then pcall(clear) end
end

function F.writeHandoff(toPlace)
	local data = {
		token = HttpService:GenerateGUID(false), from = game.PlaceId, to = toPlace,
		uid = player.UserId, at = os.time(), returnPortal = ARRIVAL_RETURN_PORTAL, tool = S.toolEnabled,
	}
	local json = HttpService:JSONEncode(data)
	local stored, queued = false, false
	if writefile then stored = pcall(writefile, HANDOFF_FILE, json) end
	local q = F.queueFn()
	if q then
		local code = ("getgenv().__PortalHandoff = [==[%s]==]\n"):format(json)
		if PLACE_RELOAD_SOURCE ~= "" then
			code = code .. ("loadstring(game:HttpGet(%q))()"):format(PLACE_RELOAD_SOURCE)
		end
		queued = pcall(q, code)
		F.handoffQueued = queued
	end
	return data, stored or queued
end

-- вызывается один раз при старте; файл удаляется сразу (одноразовый), данные валидируются
function F.takeHandoff()
	local raw
	local okEnv, env = pcall(function() return getgenv() end)
	if okEnv and type(env) == "table" and type(env.__PortalHandoff) == "string" then
		raw, env.__PortalHandoff = env.__PortalHandoff, nil
	end
	if not raw and isfile and readfile then
		local ok, content = pcall(function()
			if isfile(HANDOFF_FILE) then return readfile(HANDOFF_FILE) end
			return nil
		end)
		if ok and type(content) == "string" then raw = content end
	end
	F.clearHandoff()
	if not raw then return nil end
	local ok, data = pcall(HttpService.JSONDecode, HttpService, raw)
	if not ok or type(data) ~= "table" then return nil end
	if data.to ~= game.PlaceId or data.uid ~= player.UserId or type(data.token) ~= "string" then return nil end
	if math.abs(os.time() - (tonumber(data.at) or 0)) > HANDOFF_TTL then return nil end
	return data
end

function F.enterPlacePortal(portal)
	local s = S.current
	if S.placeBusy or not F.alive(s) or s.teleporting or s.humanoid.SeatPart then return end
	if S.slots[1] ~= portal and S.slots[2] ~= portal then return end
	local placeId = portal.placeId
	if not placeId then return end

	S.placeBusy, s.teleporting = true, true
	F.lockPortals(s, portal) -- при неудаче перехода не пытаемся снова, пока игрок стоит в портале
	do
		local p = s.rootPart.Position
		S.lastBack = { x = p.X, y = p.Y, z = p.Z, placeId = game.PlaceId, at = os.time() }
	end
	local _, stored = F.writeHandoff(placeId)
	if not stored then
		F.cmdLog("no writefile/queue_on_teleport: exit portal in the new place will not appear")
	end
	local restore = F.lockStates(s.humanoid)
	local conns, active, handle = {}, true, nil

	local function onAbort()
		active = false
		for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
		table.clear(conns)
		S.placeBusy = false
		F.clearHandoff()
		F.clearQueue()
	end

	local function fail(reason)
		if not active then return end
		F.cmdLog("place teleport failed: " .. tostring(reason))
		F.notify("Teleport failed")
		if handle then handle.cancel() else onAbort() end
	end

	local function launch(h)
		handle = h
		if not F.alive(s) or (S.slots[1] ~= portal and S.slots[2] ~= portal) then
			h.cancel()
			return
		end
		local tpState
		table.insert(conns, TeleportService.TeleportInitFailed:Connect(function(plr, _, msg)
			if plr == player then fail(msg) end
		end))
		table.insert(conns, player.OnTeleport:Connect(function(state)
			tpState = state
			if state == Enum.TeleportState.Failed then fail("OnTeleport: Failed") end
		end))
		local ok, err = pcall(TeleportService.Teleport, TeleportService, placeId, player)
		if not ok then
			fail(err)
			return
		end
		local t0 = os.clock()
		task.spawn(function()
			while active do
				task.wait(1)
				local waited = os.clock() - t0
				if waited > PLACE_MAX_TIMEOUT or (not tpState and waited > PLACE_START_TIMEOUT) then
					fail("timeout")
					return
				end
			end
		end)
	end

	local ghost = F.makeGhost(s.character)
	if ghost then
		F.travelOut(s, portal, ghost, restore, launch, onAbort)
	else
		local done = false
		launch({
			cancel = function()
				if done then return end
				done = true
				restore()
				s.teleporting = false
				s.cooldownUntil = os.clock() + TELEPORT_COOLDOWN
				onAbort()
			end,
		})
	end
end

-- защита от мгновенного повторного входа: порталы последнего перехода "спят", пока игрок не отойдёт от них
-- (иначе подброс/падение у выхода, два близких портала или упавший перенос в другой плейс запускают переход снова)
function F.lockPortals(s, ...)
	for _, portal in ipairs({ ... }) do s.locks[portal] = true end
end

function F.updateLocks(s)
	local pos = s.rootPart.Position
	for portal in pairs(s.locks) do
		if portal.bin.dead or (pos - portal.cf.Position).Magnitude > TRIGGER_RADIUS + 2.5 then
			s.locks[portal] = nil
		end
	end
end

globalBin:add(RunService.Heartbeat:Connect(function()
	local s = S.current
	if not F.alive(s) then return end
	F.updateLocks(s)
	if s.teleporting then return end
	local pos, last = s.rootPart.Position, s.lastPos
	s.lastPos = pos
	if not last then return end
	local now = os.clock()
	if now < s.cooldownUntil or now - s.spawnedAt < SPAWN_GRACE then return end
	if (pos - last).Magnitude > MAX_STEP then return end
	for i = 1, 2 do
		local portal = S.slots[i]
		if portal and not s.locks[portal] and (portal.placeId or portal.paired) then
			local c = portal.cf.Position
			if (pos - c).Magnitude <= TRIGGER_RADIUS or F.segmentDistance(last, pos, c) <= TRIGGER_RADIUS then
				if portal.placeId then F.enterPlacePortal(portal) else F.teleportThrough(portal, portal.paired) end
				return
			end
		end
	end
end))

