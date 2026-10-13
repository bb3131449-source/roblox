-- portal/main.lua — точка входа. Кладите папку `portal` (все .lua рядом) в workspace executor
-- и запускайте: loadstring(readfile("portal/main.lua"))()
local ROOT = "portal"   -- папка с модулями в workspace executor
local BASE_URL = "https://raw.githubusercontent.com/bb3131449-source/roblox/main/portal"     -- необязательно: если задан (напр. "https://raw.githubusercontent.com/user/repo/main/portal"), модули грузятся по HTTP вместо readfile

local MODULES = {
	"config",    -- настройки и константы
	"core",      -- cmdLog / safe / dispose / Bin
	"helpers",   -- make, newPart, play, загрузка ассетов
	"sfx",       -- звуки
	"queries",   -- raycast / overlap / alive
	"ui",        -- кнопки, подсказки, уведомления
	"portal",    -- построение, анимация и закрытие порталов
	"gun",       -- пушка, выстрел, регистрация портала
	"placement", -- установка порталов кликом
	"teleport",  -- расчёт выхода, состояния, settle
	"travel",    -- анимации перехода (призрак) + teleportThrough
	"place",     -- переход в другой плейс + триггер порталов
	"map",       -- поиск площадок (player/map/high/low/roof)
	"saves",     -- #save / #load / #del
	"link",      -- runLink / runArrival
	"commands",  -- чат-команды
	"tool",      -- предмет Portal gun (Backpack/StarterGear)
	"session",   -- attach/detach персонажа и запуск
}

local okEnv, env = pcall(getgenv)
if not okEnv or type(env) ~= "table" then env = _G end

local Players = game:GetService("Players")
local player = Players.LocalPlayer

-- защита от двойного запуска (то же поведение, что и в монолите)
do
	local now = os.time()
	if type(env.__PORTAL_STOP) == "function" then
		local sameJob = env.__PORTAL_JOB == game.JobId and env.__PORTAL_PLACE == game.PlaceId
		if sameJob and now - (tonumber(env.__PORTAL_STARTED) or 0) < 8 then
			warn("[portal] instance already starting, duplicate skipped")
			return
		end
		pcall(env.__PORTAL_STOP)
	end
	env.__PORTAL_STARTED, env.__PORTAL_JOB, env.__PORTAL_PLACE = now, game.JobId, game.PlaceId
end

local function readModule(name)
	if BASE_URL ~= "" then
		return game:HttpGet(BASE_URL .. "/" .. name .. ".lua")
	end
	return readfile(ROOT .. "/" .. name .. ".lua")
end

-- M — общий контекст модулей: F — функции, C — конфиг, S — изменяемое состояние, X — общие объекты
local M = {
	F = {},
	C = nil,
	S = {
		gen = 0, portalEpoch = 0, slots = {}, placement = { slot = nil },
		tpBusy = false, lastMsg = "", lastMsgAt = 0, placeBusy = false, toolEnabled = true,
		noticeId = 0, boundTools = {}, watchedContainers = {}, toolGivenLogged = false,
	},
	X = {},
	player = player,
}

env.__PORTAL_STOP = function()
	local F, X = M.F, M.X
	pcall(function() F.detach() end)
	pcall(function() F.destroyAllPortals(true) end)
	pcall(function() F.destroyPortalTools() end)
	pcall(function() X.globalBin:clean() end)
end

for _, name in ipairs(MODULES) do
	local okRead, src = pcall(readModule, name)
	if not okRead or type(src) ~= "string" or src == "" then
		warn(("[portal] cannot read module '%s': %s"):format(name, tostring(src)))
		pcall(env.__PORTAL_STOP)
		return
	end
	local fn, err = loadstring(src, "=portal/" .. name)
	if not fn then
		warn(("[portal] syntax error in '%s': %s"):format(name, tostring(err)))
		pcall(env.__PORTAL_STOP)
		return
	end
	if name == "config" then
		M.C = fn()
	else
		local ok, runErr = pcall(fn, M)
		if not ok then
			warn(("[portal] module '%s' failed: %s"):format(name, tostring(runErr)))
			pcall(env.__PORTAL_STOP)
			return
		end
	end
end
