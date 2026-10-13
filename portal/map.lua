-- portal/map.lua
local M = ...
local F, C, S, X = M.F, M.C, M.S, M.X
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local player = M.player
local COORD_RADIUS, EXTREME_RADIUS, EXTREME_TRIES, FLOOR_NORMAL, MAP_TRIES, ROOF_TRIES = C.COORD_RADIUS, C.EXTREME_RADIUS, C.EXTREME_TRIES, C.FLOOR_NORMAL, C.MAP_TRIES, C.ROOF_TRIES
local ROOF_UP, SPOT_BOX, TP_RAY_DOWN, TP_SEARCH_DIST, TP_SEARCH_HEIGHT = C.ROOF_UP, C.SPOT_BOX, C.TP_RAY_DOWN, C.TP_SEARCH_DIST, C.TP_SEARCH_HEIGHT

-- COMMANDS
function F.findPlayerByName(query)
	if not query or query == "" then return nil end
	local q = query:lower()
	local prefix, substr, substrLen = nil, nil, math.huge
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= player then
			for _, name in ipairs({ p.Name:lower(), p.DisplayName:lower() }) do
				if name == q then return p end
				if not prefix and name:sub(1, #q) == q then prefix = p end
				if name:find(q, 1, true) and #name < substrLen then substr, substrLen = p, #name end
			end
		end
	end
	return prefix or substr
end

function F.findSpot(root)
	local look = F.flatten(root.CFrame.LookVector, Vector3.new(0, 0, -1))
	local right = look:Cross(Vector3.yAxis)
	local dirs = { look, right, -right, -look }
	local ignore = F.characterIgnore()
	local down = Vector3.new(0, -TP_RAY_DOWN, 0)
	local lift = Vector3.new(0, TP_SEARCH_HEIGHT, 0)
	for _, dist in ipairs({ TP_SEARCH_DIST, TP_SEARCH_DIST + 2 }) do
		for _, dir in ipairs(dirs) do
			local hit = F.mapCast(root.Position + dir * dist + lift, down, ignore)
			if hit and hit.Normal.Y > 0.7 and F.isClear(hit.Position + Vector3.new(0, 3, 0), SPOT_BOX, ignore) then
				return hit
			end
		end
	end
	local hit = F.mapCast(root.Position + lift, down, ignore)
	return hit and hit.Normal.Y > 0.7 and hit or nil
end

function F.placeHorizontal(hit, slot, opts)
	if not hit then return nil end
	return F.registerPortal(F.surfaceFrame({ Position = hit.Position, Normal = Vector3.yAxis }), slot, opts)
end

-- MAP QUERIES
local BAD_SURFACE_NAMES = { "kill", "lava", "death", "damage", "acid", "spike", "void", "hurt" }
local SUPPORT_OFFSETS = { Vector3.new(2.5, 0, 0), Vector3.new(-2.5, 0, 0), Vector3.new(0, 0, 2.5), Vector3.new(0, 0, -2.5) }
local COORD_OFFSETS = { Vector2.zero }
for r = 2.5, COORD_RADIUS, 2.5 do
	local n = math.max(8, math.floor(r * 2))
	for k = 0, n - 1 do
		local a = k / n * math.pi * 2
		table.insert(COORD_OFFSETS, Vector2.new(math.cos(a) * r, math.sin(a) * r))
	end
end

local mapParams = RaycastParams.new()
mapParams.FilterType = Enum.RaycastFilterType.Exclude
pcall(function() mapParams.RespectCanCollide = true end)

function F.mapCast(origin, direction, ignore)
	mapParams.FilterDescendantsInstances = ignore
	local ok, result = pcall(Workspace.Raycast, Workspace, origin, direction, mapParams)
	return ok and result or nil
end

function F.badName(inst)
	local cur, depth = inst, 0
	while cur and cur ~= Workspace and depth < 3 do
		local n = cur.Name:lower()
		for _, w in ipairs(BAD_SURFACE_NAMES) do
			if n:find(w, 1, true) then return true end
		end
		cur, depth = cur.Parent, depth + 1
	end
	return false
end

-- твёрдая ровная площадка: не вода, не невидимая/«убивающая», не край (4 опоры), не ниже FallenPartsDestroyHeight, над ней свободно
function F.spotValid(hit, ignore)
	if hit.Normal.Y < FLOOR_NORMAL or hit.Material == Enum.Material.Water then return false end
	local inst = hit.Instance
	if inst and not inst:IsA("Terrain") and (inst.Transparency > 0.9 or F.badName(inst)) then return false end
	if hit.Position.Y < Workspace.FallenPartsDestroyHeight + 25 then return false end
	for _, off in ipairs(SUPPORT_OFFSETS) do
		local h = F.mapCast(hit.Position + off + Vector3.new(0, 2, 0), Vector3.new(0, -5, 0), ignore)
		if not h or h.Normal.Y < FLOOR_NORMAL or h.Material == Enum.Material.Water
			or math.abs(h.Position.Y - hit.Position.Y) > 1.5 then
			return false
		end
	end
	return F.isClear(hit.Position + Vector3.new(0, 3.5, 0), SPOT_BOX, ignore)
end

function F.mapBounds()
	local cached = S.mapBoundsCache
	if cached and os.clock() - cached.at < 30 then return cached.min, cached.max, cached.parts end
	local mn = Vector3.new(math.huge, math.huge, math.huge)
	local mx = Vector3.new(-math.huge, -math.huge, -math.huge)
	local parts = {}
	local count = 0
	for _, d in ipairs(Workspace:GetDescendants()) do
		count += 1
		if count % 4000 == 0 then task.wait() end
		if d:IsA("BasePart") and not d:IsA("Terrain") and d.CanCollide and d.Transparency < 0.9
			and d.Size.Magnitude < 6000 and d.Position.Magnitude < 50000 then
			local model = d:FindFirstAncestorOfClass("Model")
			if not (model and Players:GetPlayerFromCharacter(model)) then
				local r, p = d.Size.Magnitude / 2, d.Position
				mn = Vector3.new(math.min(mn.X, p.X - r), math.min(mn.Y, p.Y - r), math.min(mn.Z, p.Z - r))
				mx = Vector3.new(math.max(mx.X, p.X + r), math.max(mx.Y, p.Y + r), math.max(mx.Z, p.Z + r))
				if d.Anchored and d.Size.X >= 8 and d.Size.Z >= 8 then table.insert(parts, d) end
			end
		end
	end
	if mn.X == math.huge then -- карта из одного террейна: ищем вокруг игрока
		local root = S.current and S.current.rootPart
		local c = root and root.Position or Vector3.zero
		mn, mx = c - Vector3.new(512, 256, 512), c + Vector3.new(512, 256, 512)
	end
	S.mapBoundsCache = { min = mn, max = mx, parts = parts, at = os.clock() }
	return mn, mx, parts
end

function F.randomMapSpot()
	local mn, mx, parts = F.mapBounds()
	local s = S.current
	local origin = s and s.rootPart and s.rootPart.Position
	local ignore = F.characterIgnore()
	local top, len = mx.Y + 20, math.min(mx.Y - mn.Y + 60, 8000)
	for i = 1, MAP_TRIES do
		local hit
		if parts and #parts > 0 and i % 3 ~= 0 then
			local p = parts[math.random(#parts)]
			if p.Parent then
				local pos = p.CFrame:PointToWorldSpace(Vector3.new(
					(math.random() - 0.5) * p.Size.X * 0.8, p.Size.Y / 2, (math.random() - 0.5) * p.Size.Z * 0.8))
				hit = F.mapCast(pos + Vector3.new(0, 6, 0), Vector3.new(0, -14, 0), ignore)
			end
		else
			local x = mn.X + math.random() * (mx.X - mn.X)
			local z = mn.Z + math.random() * (mx.Z - mn.Z)
			hit = F.mapCast(Vector3.new(x, top, z), Vector3.new(0, -len, 0), ignore)
		end
		if hit and F.spotValid(hit, ignore) and (not origin or (hit.Position - origin).Magnitude > 20) then return hit end
		if i % 20 == 0 then task.wait() end
	end
	return nil
end

-- ближайшая валидная площадка в радиусе COORD_RADIUS от точки; при заданном y ищем в полосе y±15
function F.spotNear(x, y, z)
	local ignore = F.characterIgnore()
	local top, len
	if y then
		top, len = y + COORD_RADIUS, COORD_RADIUS * 2
	else
		local mn, mx = F.mapBounds()
		top, len = mx.Y + 20, math.min(mx.Y - mn.Y + 60, 8000)
	end
	for i, o in ipairs(COORD_OFFSETS) do
		local hit = F.mapCast(Vector3.new(x + o.X, top, z + o.Y), Vector3.new(0, -len, 0), ignore)
		if hit and F.spotValid(hit, ignore) then return hit end
		if i % 30 == 0 then task.wait() end
	end
	return nil
end

function F.parseCoords(args)
	local nums = {}
	for _, token in ipairs(args) do
		for piece in token:gsub("[%(%),;]", " "):gmatch("%S+") do
			local v = tonumber(piece)
			if not v or v ~= v or math.abs(v) > 1e6 then return nil end
			table.insert(nums, v)
		end
	end
	if #nums == 3 then return nums[1], nums[2], nums[3] end
	if #nums == 2 then return nums[1], nil, nums[2] end
	return nil
end

-- HIGH / LOW: ищем валидную площадку с max/min Y (сначала вокруг игрока, потом по всей карте)
function F.findExtremeSpot(wantHigh)
	local s = S.current
	local origin = (s and s.rootPart and s.rootPart.Position) or Vector3.zero
	local ignore = F.characterIgnore()
	local mn, mx = F.mapBounds()
	local topY = mx.Y + 30
	local rayLen = math.min(mx.Y - mn.Y + 80, 9000)
	local best, bestY = nil, wantHigh and -math.huge or math.huge

	local function consider(hit)
		if not hit or not F.spotValid(hit, ignore) then return end
		local y = hit.Position.Y
		if (wantHigh and y > bestY) or (not wantHigh and y < bestY) then
			best, bestY = hit, y
		end
	end

	-- 1) плотная сетка вокруг игрока
	local radii = { 0, 15, 30, 50, 80, 120, EXTREME_RADIUS }
	local stepCount = 0
	for _, r in ipairs(radii) do
		local steps = r == 0 and 1 or math.max(8, math.floor(r / 4))
		for k = 0, steps - 1 do
			local a = (k / steps) * math.pi * 2
			local x = origin.X + math.cos(a) * r
			local z = origin.Z + math.sin(a) * r
			consider(F.mapCast(Vector3.new(x, topY, z), Vector3.new(0, -rayLen, 0), ignore))
			stepCount += 1
			if stepCount % 24 == 0 then task.wait() end
		end
	end

	-- 2) если вокруг слабо — случайные точки по всей карте
	if not best or (wantHigh and bestY < origin.Y + 8) or (not wantHigh and bestY > origin.Y - 8) then
		for i = 1, EXTREME_TRIES do
			local x = mn.X + math.random() * (mx.X - mn.X)
			local z = mn.Z + math.random() * (mx.Z - mn.Z)
			consider(F.mapCast(Vector3.new(x, topY, z), Vector3.new(0, -rayLen, 0), ignore))
			if i % 15 == 0 then task.wait() end
		end
	end
	return best
end

-- ROOF: площадка выше игрока (крыша / верхний этаж) в радиусе
function F.findRoofSpot()
	local s = S.current
	if not F.alive(s) then return nil end
	local origin = s.rootPart.Position
	local ignore = F.characterIgnore()
	local best, bestY = nil, origin.Y

	local function consider(hit)
		if not hit or not F.spotValid(hit, ignore) then return end
		local y = hit.Position.Y
		-- только выше текущей позиции, с запасом
		if y > origin.Y + 4 and y > bestY then
			best, bestY = hit, y
		end
	end

	-- лучи сверху вниз в колонне над игроком + кольца
	local top = origin.Y + ROOF_UP
	local down = Vector3.new(0, -(ROOF_UP + 10), 0)
	consider(F.mapCast(Vector3.new(origin.X, top, origin.Z), down, ignore))
	for r = 4, 40, 4 do
		local n = math.max(6, math.floor(r))
		for k = 0, n - 1 do
			local a = (k / n) * math.pi * 2
			local x = origin.X + math.cos(a) * r
			local z = origin.Z + math.sin(a) * r
			consider(F.mapCast(Vector3.new(x, top, z), down, ignore))
		end
		task.wait()
	end

	-- запасной проход: несколько случайных точек выше
	if not best then
		for i = 1, ROOF_TRIES do
			local ang = math.random() * math.pi * 2
			local rad = math.random() * 50
			local x = origin.X + math.cos(ang) * rad
			local z = origin.Z + math.sin(ang) * rad
			consider(F.mapCast(Vector3.new(x, top, z), down, ignore))
			if i % 10 == 0 then task.wait() end
		end
	end
	return best
end

X.BAD_SURFACE_NAMES = BAD_SURFACE_NAMES
X.SUPPORT_OFFSETS = SUPPORT_OFFSETS
X.COORD_OFFSETS = COORD_OFFSETS
X.mapParams = mapParams
