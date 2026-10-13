-- portal/saves.lua
local M = ...
local F, C, S, X = M.F, M.C, M.S, M.X
local HttpService = game:GetService("HttpService")
local SAVES_FILE = C.SAVES_FILE

-- SAVE / LOAD: именованные точки (память + файл, если есть writefile)

function F.readSaves()
	if S.portalSaves then return S.portalSaves end
	S.portalSaves = {}
	local raw
	if isfile and readfile then
		local ok, data = pcall(function()
			if isfile(SAVES_FILE) then return readfile(SAVES_FILE) end
		end)
		if ok and type(data) == "string" and #data > 0 then raw = data end
	end
	if not raw then
		local okEnv, env = pcall(function() return getgenv() end)
		if okEnv and type(env) == "table" and type(env.__PortalSaves) == "table" then
			S.portalSaves = env.__PortalSaves
			return S.portalSaves
		end
	end
	if raw then
		local ok, data = pcall(HttpService.JSONDecode, HttpService, raw)
		if ok and type(data) == "table" then S.portalSaves = data end
	end
	return S.portalSaves
end

function F.writeSaves()
	local data = S.portalSaves or {}
	local okEnv, env = pcall(function() return getgenv() end)
	if okEnv and type(env) == "table" then env.__PortalSaves = data end
	if writefile then
		local ok, err = pcall(writefile, SAVES_FILE, HttpService:JSONEncode(data))
		if not ok then F.cmdLog("save file: " .. tostring(err)) end
		return ok
	end
	return true -- in-memory only still counts as success
end

-- единая нормализация: save/load/del раньше обрезали имя по-разному (load/del не обрезали до 32)
function F.normName(raw)
	return (tostring(raw or ""):lower():gsub("%s+", "_"):sub(1, 32))
end

function F.saveCurrentSpot(name)
	local s = S.current
	if not F.alive(s) then return nil, "no character" end
	name = F.normName(name)
	if name == "" or not name:match("^[%w_%-]+$") then
		return nil, "bad name (use letters/digits/_/-)"
	end
	local pos = s.rootPart.Position
	local look = s.rootPart.CFrame.LookVector
	local saves = F.readSaves()
	saves[name] = {
		x = pos.X, y = pos.Y, z = pos.Z,
		lx = look.X, ly = look.Y, lz = look.Z,
		placeId = game.PlaceId,
		at = os.time(),
	}
	F.writeSaves()
	return saves[name]
end

function F.getSave(name)
	name = F.normName(name)
	if name == "" then return nil end
	local saves = F.readSaves()
	return saves[name], name
end

function F.listSaveNames()
	local saves = F.readSaves()
	local names = {}
	for k in pairs(saves) do table.insert(names, k) end
	table.sort(names)
	return names
end

function F.deleteSave(name)
	name = F.normName(name)
	if name == "" then return nil, "usage: #del <name>" end
	local saves = F.readSaves()
	if not saves[name] then return nil, "save not found: " .. name end
	saves[name] = nil
	F.writeSaves()
	return name
end

