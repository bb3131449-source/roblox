-- portal/core.lua
local M = ...
local F, C, S, X = M.F, M.C, M.S, M.X

-- CORE
function F.cmdLog(msg)
	if rconsoleprint then rconsoleprint("[portal] " .. msg .. "\n") end
	print("[portal] " .. msg)
end

function F.safe(label, fn, ...)
	local ok, res = pcall(fn, ...)
	if not ok then
		F.cmdLog(label .. ": " .. tostring(res))
		return nil
	end
	return res
end

function F.dispose(item)
	local kind = typeof(item)
	if kind == "RBXScriptConnection" then
		item:Disconnect()
	elseif kind == "Instance" then
		if item:IsA("TweenBase") then item:Cancel() end
		item:Destroy()
	elseif kind == "function" then
		item()
	elseif kind == "thread" then
		task.cancel(item)
	end
end

function F.runDispose(item)
	local ok, err = pcall(F.dispose, item)
	if not ok then F.cmdLog("cleanup: " .. tostring(err)) end
end

local Bin = {}
Bin.__index = Bin

function Bin.new()
	return setmetatable({ items = {}, dead = false }, Bin)
end

function Bin:add(item)
	if self.dead then F.runDispose(item) else table.insert(self.items, item) end
	return item
end

function Bin:remove(item)
	local i = table.find(self.items, item)
	if i then table.remove(self.items, i) end
end

function Bin:release(item)
	self:remove(item)
	F.runDispose(item)
end

function Bin:delay(time, fn)
	if self.dead then return nil end
	local thread
	thread = task.delay(time, function()
		self:remove(thread)
		F.safe("delayed", fn)
	end)
	return self:add(thread)
end

function Bin:clean()
	self.dead = true
	local items = self.items
	self.items = {}
	for i = #items, 1, -1 do F.runDispose(items[i]) end
end

local globalBin = Bin.new()

X.Bin = Bin
X.globalBin = globalBin
