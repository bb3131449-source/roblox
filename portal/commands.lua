-- portal/commands.lua
local M = ...
local F, C, S, X = M.F, M.C, M.S, M.X
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local player = M.player
local COMMAND_DEDUP, COMMAND_PREFIX, COORD_RADIUS, GREEN, GUN_DOWN, GUN_FORWARD = C.COMMAND_DEDUP, C.COMMAND_PREFIX, C.COORD_RADIUS, C.GREEN, C.GUN_DOWN, C.GUN_FORWARD
local GUN_YAW, NO_SPACE_TEXT = C.GUN_YAW, C.NO_SPACE_TEXT
local BTN_BG = X.BTN_BG
local BTN_TEXT = X.BTN_TEXT
local globalBin = X.globalBin
local gui = X.gui

local commands = {}

function F.exclusive(name, fn, ...)
	if S.tpBusy or S.placeBusy then F.cmdLog(name .. ": another command is still running") return end
	S.tpBusy = true
	local ok, err = pcall(fn, ...)
	S.tpBusy = false
	if not ok then F.cmdLog(name .. " error: " .. tostring(err)) end
end

commands.player = function(args)
	local query = args[1]
	if not query then F.cmdLog("usage: #player <random|nickname>") return end
	local target
	if query:lower() == "random" then
		local pool = {}
		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= player and F.aliveRoot(p.Character) then table.insert(pool, p) end
		end
		for i = #pool, 2, -1 do
			local j = math.random(i)
			pool[i], pool[j] = pool[j], pool[i]
		end
		for _, p in ipairs(pool) do
			local root = F.aliveRoot(p.Character)
			if root and F.findSpot(root) then
				target = p
				break
			end
		end
		if not target then
			F.cmdLog("no suitable players (need a character and free space)")
			F.notify("No suitable players")
			return
		end
	else
		if query:lower() == player.Name:lower() then F.cmdLog("cannot target self") return end
		target = F.findPlayerByName(query)
		if not target then F.cmdLog("player not found: " .. query) return end
	end
	F.exclusive("player", F.runLink, target.Name, function()
		if not target.Parent then return nil, target.Name .. " left the game" end
		local root = F.aliveRoot(target.Character)
		if not root then return nil, target.Name .. " has no character" end
		local hit = F.findSpot(root)
		if not hit then
			F.notify("No free space near " .. target.Name)
			return nil, "no free space near " .. target.Name
		end
		return hit
	end)
end

commands.map = function(args)
	local mode = args[1] and args[1]:lower()
	local cached
	if mode == "random" then
		F.exclusive("map", F.runLink, "random map point", function()
			if not cached then cached = F.randomMapSpot() end
			if cached then return cached end
			F.notify("Could not find a safe spot on the map")
			return nil, "map random: no safe spot found"
		end)
		return
	end
	local x, y, z = F.parseCoords(args)
	if not x then F.cmdLog("usage: #map <random | x y z | x z>") return end
	F.exclusive("map", F.runLink, ("%g, %s, %g"):format(x, y and tostring(y) or "auto", z), function()
		if not cached then cached = F.spotNear(x, y, z) end
		if cached then return cached end
		F.notify(NO_SPACE_TEXT)
		return nil, "map: no safe platform within " .. COORD_RADIUS .. " studs"
	end)
end

commands.high = function()
	local cached
	F.exclusive("high", F.runLink, "highest point", function()
		if not cached then cached = F.findExtremeSpot(true) end
		if cached then return cached end
		F.notify("Could not find a high safe spot")
		return nil, "high: no safe elevated platform"
	end)
end

commands.low = function()
	local cached
	F.exclusive("low", F.runLink, "lowest point", function()
		if not cached then cached = F.findExtremeSpot(false) end
		if cached then return cached end
		F.notify("Could not find a low safe spot")
		return nil, "low: no safe low platform"
	end)
end

commands.roof = function()
	local cached
	F.exclusive("roof", F.runLink, "roof above you", function()
		if not cached then cached = F.findRoofSpot() end
		if cached then return cached end
		F.notify("No roof / upper platform found above you")
		return nil, "roof: nothing safe above"
	end)
end

commands.save = function(args)
	local name = args[1]
	if not name then
		local names = F.listSaveNames()
		if #names == 0 then
			F.cmdLog("usage: #save <name>  (no saves yet)")
		else
			F.cmdLog("usage: #save <name>  | saved: " .. table.concat(names, ", "))
		end
		return
	end
	local data, err = F.saveCurrentSpot(name)
	if not data then
		F.cmdLog("save failed: " .. tostring(err))
		F.notify("Save failed")
		return
	end
	local key = F.normName(name)
	F.cmdLog(("saved '%s' at %.1f, %.1f, %.1f (place %d)"):format(key, data.x, data.y, data.z, data.placeId or 0))
	F.notify("Saved: " .. key)
end

commands.load = function(args)
	local name = args[1]
	if not name then
		local names = F.listSaveNames()
		if #names == 0 then
			F.cmdLog("usage: #load <name>  (no saves yet)")
		else
			F.cmdLog("usage: #load <name>  | saved: " .. table.concat(names, ", "))
		end
		return
	end
	local data, key = F.getSave(name)
	if not data then
		F.cmdLog("save not found: " .. tostring(name))
		local names = F.listSaveNames()
		if #names > 0 then F.cmdLog("available: " .. table.concat(names, ", ")) end
		F.notify("Save not found")
		return
	end
	if data.placeId and data.placeId ~= game.PlaceId then
		F.cmdLog(("save '%s' is from place %d (you are in %d) — still trying nearby spot"):format(
			key, data.placeId, game.PlaceId))
	end
	local cached
	F.exclusive("load", F.runLink, "save:" .. key, function()
		if not cached then
			cached = F.spotNear(data.x, data.y, data.z)
			if not cached then
				-- fallback: accept a ray hit even if supports are imperfect
				local ignore = F.characterIgnore()
				local hit = F.mapCast(
					Vector3.new(data.x, data.y + 8, data.z),
					Vector3.new(0, -20, 0),
					ignore)
				if hit and hit.Normal.Y > 0.5 then cached = hit end
			end
		end
		if cached then return cached end
		F.notify(NO_SPACE_TEXT)
		return nil, "load: no safe platform near saved point"
	end)
end

commands.list = function()
	local names = F.listSaveNames()
	if #names == 0 then
		F.cmdLog("no saved points (use #save <name>)")
		F.showInfo({ "No saved points", "Use #save <name>" }, 5)
		return
	end
	local saves = F.readSaves()
	local lines = { "Saved points (" .. #names .. "):" }
	for _, name in ipairs(names) do
		local d = saves[name]
		if type(d) == "table" then
			table.insert(lines, ("%s  ->  %.1f, %.1f, %.1f  (place %s)"):format(
				name, d.x or 0, d.y or 0, d.z or 0, tostring(d.placeId or "?")))
		else
			table.insert(lines, name)
		end
	end
	for _, line in ipairs(lines) do F.cmdLog(line) end
	if #lines > 16 then
		local extra = #lines - 15
		for i = #lines, 16, -1 do table.remove(lines, i) end
		table.insert(lines, "... +" .. extra .. " more (see console)")
	end
	F.showInfo(lines, 15)
end

commands.del = function(args)
	local name = args[1]
	if not name then
		local names = F.listSaveNames()
		if #names == 0 then
			F.cmdLog("usage: #del <name>  (no saves yet)")
		else
			F.cmdLog("usage: #del <name>  | saved: " .. table.concat(names, ", "))
		end
		return
	end
	local key, err = F.deleteSave(name)
	if not key then
		F.cmdLog(tostring(err))
		F.notify("Delete failed")
		return
	end
	F.cmdLog("deleted save: " .. key)
	F.notify("Deleted: " .. key)
end

commands.delete = commands.del -- alias

commands.back = function()
	if not S.lastBack then
		F.cmdLog("nothing to go back to (walk through a portal first)")
		F.notify("No previous portal position")
		return
	end
	if S.lastBack.placeId and S.lastBack.placeId ~= game.PlaceId then
		F.cmdLog(("back point is in place %d (you are in %d)"):format(S.lastBack.placeId, game.PlaceId))
		F.notify("Back point is in another place")
		return
	end
	local bx, by, bz = S.lastBack.x, S.lastBack.y, S.lastBack.z
	local cached
	F.exclusive("back", F.runLink, "back", function()
		if not cached then
			cached = F.spotNear(bx, by, bz)
			if not cached then
				local ignore = F.characterIgnore()
				local hit = F.mapCast(Vector3.new(bx, by + 8, bz), Vector3.new(0, -20, 0), ignore)
				if hit and hit.Normal.Y > 0.5 then cached = hit end
			end
		end
		if cached then return cached end
		F.notify(NO_SPACE_TEXT)
		return nil, "back: no safe platform at previous point"
	end)
end

commands.place = function(args)
	local id = tonumber(args[1])
	if not id or id ~= math.floor(id) or id <= 0 then F.cmdLog("usage: #place <placeId>") return end
	if id == game.PlaceId then
		F.notify("You are already in this place")
		return
	end
	F.exclusive("place", function()
		local s = S.current
		if not F.alive(s) then F.cmdLog("no local character") return end
		local okInfo, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, id, Enum.InfoType.Asset)
		if okInfo and type(info) == "table" and info.AssetTypeId ~= 9 then
			F.notify("This id is not a place")
			F.cmdLog(("id %d is not a place"):format(id))
			return
		end
		if not okInfo then F.cmdLog("place check skipped: " .. tostring(info)) end
		if S.current ~= s or not F.alive(s) or s.teleporting or S.placeBusy then
			F.cmdLog("place: aborted, state changed")
			return
		end
		local hit = F.findSpot(s.rootPart)
		if not hit then
			F.notify("No free space near you")
			F.cmdLog("no free space near you")
			return
		end
		F.destroyAllPortals()
		F.resetPlacement()
		if not F.placeHorizontal(hit, 1, { placeId = id }) then
			F.destroyAllPortals()
			F.cmdLog("failed to build place portal")
			return
		end
		F.cmdLog(("place portal open -> %d, walk into it"):format(id))
	end)
end

commands.clear = function()
	F.destroyAllPortals()
	F.resetPlacement()
	F.cmdLog("portals cleared")
end

commands.pos = function()
	local s = S.current
	if not F.alive(s) then F.cmdLog("pos: no local character") return end
	if not s.holding or not s.heldTool then
		F.cmdLog("pos: equip Portal gun first, stand still, then send #pos")
		return
	end
	local model = s.heldTool:FindFirstChild("PortalDevice")
	local root
	if model then
		for _, d in ipairs(model:GetDescendants()) do
			if d:GetAttribute("PortalRoot") then root = d end
		end
	end
	if not root then F.cmdLog("pos: gun model not found") return end
	local hrp, hand = s.rootPart, s.hand

	local report = {}
	local function out(msg)
		F.cmdLog(msg)
		table.insert(report, msg)
	end

	local function showCopyButton(text)
		local old = gui:FindFirstChild("PortalCopy")
		if old then old:Destroy() end
		local clip = setclipboard or toclipboard or (Clipboard and Clipboard.set)

		local frame = F.make("Frame", {
			Name = "PortalCopy", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -90),
			Size = UDim2.fromOffset(250, 40), BackgroundTransparency = 1,
		}, gui)
		F.make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8) }, frame)

		local function styled(btn)
			F.make("UICorner", { CornerRadius = UDim.new(0, 8) }, btn)
			F.make("UIStroke", { Color = GREEN, Thickness = 1, Transparency = 0.2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, btn)
			return btn
		end

		local copy = styled(F.make("TextButton", {
			Size = UDim2.new(1, -48, 1, 0), BackgroundColor3 = BTN_BG, BorderSizePixel = 0, AutoButtonColor = false,
			TextColor3 = BTN_TEXT, Font = Enum.Font.GothamMedium, TextSize = 13,
			Text = clip and "Копировать логи pos" or "Показать логи pos",
		}, frame))
		local close = styled(F.make("TextButton", {
			Size = UDim2.fromOffset(40, 40), BackgroundColor3 = BTN_BG, BorderSizePixel = 0, AutoButtonColor = false,
			TextColor3 = BTN_TEXT, Font = Enum.Font.GothamMedium, TextSize = 14, Text = "X",
		}, frame))

		local box
		copy.Activated:Connect(function()
			if clip then
				local ok, err = pcall(clip, text)
				copy.Text = ok and "Скопировано" or "Ошибка копирования"
				if not ok then F.cmdLog("copy: " .. tostring(err)) end
				task.delay(1.5, function()
					if copy.Parent then copy.Text = "Копировать логи pos" end
				end)
				return
			end
			if box then
				box:Destroy()
				box = nil
				return
			end
			box = F.make("TextBox", {
				AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0, -8), Size = UDim2.fromOffset(340, 220),
				BackgroundColor3 = BTN_BG, BorderSizePixel = 0, TextColor3 = BTN_TEXT, Font = Enum.Font.Code, TextSize = 11,
				TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
				MultiLine = true, TextWrapped = true, ClearTextOnFocus = false, Text = text,
			}, frame)
			F.make("UICorner", { CornerRadius = UDim.new(0, 8) }, box)
			box:GetPropertyChangedSignal("Text"):Connect(function()
				if box and box.Text ~= text then box.Text = text end
			end)
		end)
		close.Activated:Connect(function() frame:Destroy() end)
	end

	local function v3(v) return string.format("%.3f, %.3f, %.3f", v.X, v.Y, v.Z) end
	local function deg(cf)
		local x, y, z = cf:ToEulerAnglesXYZ()
		return string.format("%.1f, %.1f, %.1f", math.deg(x), math.deg(y), math.deg(z))
	end
	local function boxOf(frame, list)
		local mn = Vector3.new(math.huge, math.huge, math.huge)
		local mx = Vector3.new(-math.huge, -math.huge, -math.huge)
		for _, p in ipairs(list) do
			local h = p.Size / 2
			for sx = -1, 1, 2 do
				for sy = -1, 1, 2 do
					for sz = -1, 1, 2 do
						local v = frame:PointToObjectSpace(p.CFrame:PointToWorldSpace(Vector3.new(h.X * sx, h.Y * sy, h.Z * sz)))
						mn = Vector3.new(math.min(mn.X, v.X), math.min(mn.Y, v.Y), math.min(mn.Z, v.Z))
						mx = Vector3.new(math.max(mx.X, v.X), math.max(mx.Y, v.Y), math.max(mx.Z, v.Z))
					end
				end
			end
		end
		return mn, mx
	end
	local function fmt(mn, mx)
		return "min(" .. v3(mn) .. ") max(" .. v3(mx) .. ") size(" .. v3(mx - mn) .. ")"
	end

	local gunParts = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d ~= root and d ~= s.lens and d.Transparency < 0.99 then
			table.insert(gunParts, d)
		end
	end
	if #gunParts == 0 then F.cmdLog("pos: gun has no visible parts") return end
	local weld
	for _, w in ipairs(root:GetChildren()) do
		if w:IsA("Weld") and w.Part1 == root then weld = w end
	end

	out("=== GUN POS BEGIN ===")
	out(string.format("rig=%s hipHeight=%.2f speed=%.2f", s.humanoid.RigType == Enum.HumanoidRigType.R15 and "R15" or "R6",
		s.humanoid.HipHeight, hrp.AssemblyLinearVelocity.Magnitude))
	out(string.format("consts GUN_YAW=%.4f GUN_FORWARD=%.3f GUN_DOWN=%.3f", GUN_YAW, GUN_FORWARD, GUN_DOWN))
	out("offset.pos=" .. v3(s.offset.Position) .. " offset.eulerXYZ=" .. deg(s.offset))
	if weld then out("weld.C0.pos=" .. v3(weld.C0.Position) .. " weld.C0.eulerXYZ=" .. deg(weld.C0)) end
	out("-- HRP space (x=right, y=up, z=BACK; forward=-z)")
	local relHand = hrp.CFrame:ToObjectSpace(hand.CFrame)
	local relRoot = hrp.CFrame:ToObjectSpace(root.CFrame)
	out("hand.pos=" .. v3(relHand.Position))
	out("hand axes X|Y|Z=" .. v3(relHand.XVector) .. " | " .. v3(relHand.YVector) .. " | " .. v3(relHand.ZVector))
	out("gunRoot.pos=" .. v3(relRoot.Position))
	out("gunRoot axes X|Y|Z=" .. v3(relRoot.XVector) .. " | " .. v3(relRoot.YVector) .. " | " .. v3(relRoot.ZVector))
	if s.lens then out("muzzle.pos=" .. v3(hrp.CFrame:PointToObjectSpace(s.lens.Position))) end
	local mn, mx = boxOf(hrp.CFrame, { hand })
	out("hand box=" .. fmt(mn, mx))
	local arm = {}
	for _, n in ipairs({ "RightUpperArm", "RightLowerArm", "RightHand", "Right Arm" }) do
		local p = s.character:FindFirstChild(n)
		if p then table.insert(arm, p) end
	end
	mn, mx = boxOf(hrp.CFrame, arm)
	out("arm box=" .. fmt(mn, mx))
	local torso = s.character:FindFirstChild("UpperTorso") or s.character:FindFirstChild("Torso")
	if torso then
		mn, mx = boxOf(hrp.CFrame, { torso })
		out("torso box=" .. fmt(mn, mx))
	end
	mn, mx = boxOf(hrp.CFrame, gunParts)
	out("gun box=" .. fmt(mn, mx))
	out("-- hand space")
	local half = hand.Size / 2
	out("hand.size=" .. v3(hand.Size))
	local lmn, lmx = boxOf(hand.CFrame, gunParts)
	out("gun box=" .. fmt(lmn, lmx))
	out(string.format("overlap gun/hand per axis=%.3f, %.3f, %.3f (all > 0 = intersect)",
		math.min(half.X, lmx.X) - math.max(-half.X, lmn.X),
		math.min(half.Y, lmx.Y) - math.max(-half.Y, lmn.Y),
		math.min(half.Z, lmx.Z) - math.max(-half.Z, lmn.Z)))
	table.sort(gunParts, function(a, b) return a.Size.X * a.Size.Y * a.Size.Z > b.Size.X * b.Size.Y * b.Size.Z end)
	for i = 1, math.min(6, #gunParts) do
		local p = gunParts[i]
		out(string.format("part %s size(%s) center_in_hand(%s)", p.Name, v3(p.Size), v3(hand.CFrame:PointToObjectSpace(p.Position))))
	end
	out("shoulder.C0.pos=" .. v3(s.shoulder.C0.Position) .. " baseC0.eulerXYZ=" .. deg(s.baseC0))
	out("=== GUN POS END ===")

	showCopyButton(table.concat(report, "\n"))
end

commands.portalinfo = function()
	if not S.portalTemplate then
		F.showInfo({ "Portal template not loaded" }, 8)
		return
	end
	local lines = { "Portal template: " .. S.portalTemplate.ClassName }
	for _, p in ipairs(F.collectParts(S.portalTemplate)) do
		local extra = ""
		if p:IsA("MeshPart") then
			extra = " mesh=" .. tostring(p.MeshId)
		elseif p:IsA("Part") then
			extra = " shape=" .. tostring(p.Shape)
		end
		local sm = p:FindFirstChildOfClass("SpecialMesh")
		if sm then extra = extra .. " special=" .. tostring(sm.MeshType) end
		table.insert(lines, ("%s [%s] %.2f x %.2f x %.2f%s"):format(p.Name, p.ClassName, p.Size.X, p.Size.Y, p.Size.Z, extra))
	end
	for _, line in ipairs(lines) do F.cmdLog(line) end
	if #lines > 10 then
		local extra = #lines - 9
		for i = #lines, 10, -1 do table.remove(lines, i) end
		table.insert(lines, "... +" .. extra .. " more (see console)")
	end
	F.showInfo(lines, 30)
end

commands.help = function()
	local lines = {
		"Commands (prefix " .. COMMAND_PREFIX .. "):",
		"player <random|nick>",
		"map <random|x y z>",
		"high | low | roof | back",
		"save <name> | load <name> | del <name> | list",
		"place <id>",
		"give | take | clear | pos | portalinfo | help",
	}
	for _, line in ipairs(lines) do F.cmdLog(line) end
	F.showInfo(lines, 15)
end

function F.handleCommand(msg)
	if type(msg) ~= "string" then return end
	if msg:sub(1, #COMMAND_PREFIX):lower() ~= COMMAND_PREFIX then return end
	local now = os.clock()
	if msg == S.lastMsg and now - S.lastMsgAt < COMMAND_DEDUP then return end
	S.lastMsg, S.lastMsgAt = msg, now

	local parts = {}
	for w in msg:sub(#COMMAND_PREFIX + 1):gmatch("%S+") do table.insert(parts, w) end
	local cmd = parts[1] and parts[1]:lower()
	if not cmd then return end
	local handler = commands[cmd]
	if not handler then F.cmdLog("unknown command: " .. cmd) return end
	local ok, err = pcall(handler, { table.unpack(parts, 2) })
	if not ok then F.cmdLog("error: " .. tostring(err)) end
end

globalBin:add(player.Chatted:Connect(F.handleCommand))

F.safe("TextChatService", function()
	local TCS = game:GetService("TextChatService")
	globalBin:add(TCS.MessageReceived:Connect(function(m)
		if m.TextSource and m.TextSource.UserId == player.UserId then F.handleCommand(m.Text) end
	end))
end)

X.commands = commands
