local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local InsertService = game:GetService("InsertService")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local MarketplaceService = game:GetService("MarketplaceService")
local ContentProvider = game:GetService("ContentProvider")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer

do
	local okEnv, env = pcall(getgenv)
	if not okEnv or type(env) ~= "table" then env = _G end
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

local GUN_ASSET_ID, PORTAL_ASSET_ID = 94472637589300, 97461745338366
local SFX_VOLUME = 0.8
local SHOT_SOUND_ID, OPEN_SOUND_ID, ENTER_SOUND_ID, EXIT_SOUND_ID = "", "", "", ""
local GUN_YAW, GUN_FORWARD, GUN_DOWN = math.pi, 0.4, 0.33
local GUN_LOWER = 0.15
local MUZZLE_OFFSET = CFrame.new(0, 0, 1.1)
local PORTAL_FIX_ROT, PORTAL_OFFSET, PORTAL_SPIN = CFrame.Angles(0, math.rad(-90), 0), CFrame.new(), 75
local GREEN, GREEN_BRIGHT = Color3.fromRGB(40, 220, 110), Color3.fromRGB(110, 255, 170)
local LIGHT_MIN, LIGHT_MAX = 0, 2.8
local FLASH_RANGE, LIGHT_RANGE = 16, 8
local RAISE_ANGLE, RECOIL_ANGLE = 90, 8
local RAISE_TIME, HOLD_TIME, LOWER_TIME = 0.25, 0.5, 0.35
local BOLT_TIME, BOLT_SIZE = 0.2, 0.4
local PORTAL_DIAMETER, PORTAL_THICKNESS = 6, 0.2
local PORTAL_COLOR = Color3.fromRGB(120, 124, 132)
local PORTAL_SMOOTH_DISC, PORTAL_BASE_COLOR = true, Color3.fromRGB(34, 150, 60)
local STRETCH_MAX, STRETCH_K, STRETCH_C, STRETCH_LAYERS = 3, 260, 10, 14
local TRIGGER_RADIUS, RAYCAST_DISTANCE = PORTAL_DIAMETER / 2 + 1.5, 5000
local TELEPORT_COOLDOWN, SPAWN_GRACE, MAX_STEP = 0, 1, 40
local SETTLE_TIME, MAX_EXIT_SPEED = 0.3, 100
local WALL_EXIT, CEILING_DROP, EXIT_CLEARANCE = 3, 4, 0.3
local TOSS_SPEED, WALL_PUSH = 32, 14
local MAX_LATERAL, FLOOR_NORMAL = PORTAL_DIAMETER * 0.3, 0.7
local R6_LEG_HEIGHT, BODY_HEAD, BODY_FOOT_MARGIN, BODY_WIDTH = 2, 2.5, 0.5, 3
local LIFT_STEPS, PUSH_STEPS = { 0, 1, 2, 3, 5 }, { 0, 2 }
local SPOT_BOX = Vector3.new(3, 4, 3)
local LATERAL_RADII = { 0, 1.5, 3 }
local RING_DIRS = {}
for i = 0, 7 do
	local a = i * math.pi / 4
	table.insert(RING_DIRS, Vector3.new(math.cos(a), 0, math.sin(a)))
end
local OPEN_TIME, CLOSE_TIME, MIN_SCALE = 0.5, 0.3, 0.05
local BURST_PARTICLES, BURST_RING_TIME, BURST_LIFETIME = 48, 0.55, 1.2
local TP_COMMAND_DELAY, TP_SEARCH_DIST, TP_SEARCH_HEIGHT, TP_RAY_DOWN = 0.35, 5, 8, 20
local WAIT_TIMEOUT, COMMAND_DEDUP = 10, 0.5
local COMMAND_PREFIX = "#"
local TOOL_NAME = "Portal gun"
local NO_SPACE_TEXT = "There is no physical space to move around safely"
local MAP_TRIES, COORD_RADIUS = 120, 15
local HANDOFF_FILE, HANDOFF_TTL = "portal_handoff.json", 180
local SAVES_FILE = "portal_saves.json"
local PLACE_RELOAD_SOURCE = ""
local ARRIVAL_RETURN_PORTAL = false
local PLACE_START_TIMEOUT, PLACE_MAX_TIMEOUT = 12, 120
local EXTREME_TRIES, EXTREME_RADIUS, ROOF_UP, ROOF_TRIES = 60, 180, 120, 40

local LOCKED_STATES = { Enum.HumanoidStateType.FallingDown, Enum.HumanoidStateType.Ragdoll }
local BAD_STATES = {
	[Enum.HumanoidStateType.FallingDown] = true,
	[Enum.HumanoidStateType.Ragdoll] = true,
	[Enum.HumanoidStateType.Physics] = true,
	[Enum.HumanoidStateType.PlatformStanding] = true,
}

local current, gen, portalEpoch = nil, 0, 0
local slots = {}
local placement = { slot = nil }
local tpBusy, lastMsg, lastMsgAt = false, "", 0
local gunTemplate, portalTemplate
local placeBusy, toolEnabled = false, true
local lastBack = nil

local F = {}

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

do
	local okEnv, env = pcall(getgenv)
	if not okEnv or type(env) ~= "table" then env = _G end
	function F.shutdown()
		pcall(function() F.detach() end)
		pcall(function() F.destroyAllPortals(true) end)
		pcall(function() F.destroyPortalTools() end)
		pcall(function() globalBin:clean() end)
		if env.__PORTAL_STOP == F.shutdown then env.__PORTAL_STOP = nil end
	end
	env.__PORTAL_STOP = F.shutdown
end

function F.make(class, props, parent)
	local inst = Instance.new(class)
	for k, v in pairs(props) do inst[k] = v end
	inst.Parent = parent
	return inst
end

function F.newPart(parent, name, size, cf, color, material, shape)
	return F.make("Part", {
		Name = name, Size = size, Color = color, Material = material, Shape = shape,
		CanCollide = false, CanTouch = false, CanQuery = false, Massless = true, CFrame = cf,
	}, parent)
end

function F.play(bin, obj, time, props, style, dir)
	if bin.dead then return nil end
	local tw = F.safe("tween", function()
		return TweenService:Create(obj, TweenInfo.new(time, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	end)
	if not tw then return nil end
	bin:add(tw)
	tw.Completed:Once(function() bin:remove(tw) end)
	tw:Play()
	return tw
end

function F.flatten(v, fallback)
	local f = Vector3.new(v.X, 0, v.Z)
	return f.Magnitude > 0.001 and f.Unit or fallback
end

function F.segmentDistance(a, b, p)
	local ab = b - a
	local len2 = ab:Dot(ab)
	local t = len2 > 0 and math.clamp((p - a):Dot(ab) / len2, 0, 1) or 0
	return (a + ab * t - p).Magnitude
end

function F.collectParts(inst)
	local list = {}
	if inst:IsA("BasePart") then table.insert(list, inst) end
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("BasePart") then table.insert(list, d) end
	end
	return list
end

function F.findHandle(model)
	if model:IsA("BasePart") then return model end
	return model:FindFirstChild("Handle", true) or model:FindFirstChildWhichIsA("BasePart", true)
end

function F.alignTo(parts, anchor, target)
	local delta = target * anchor.CFrame:Inverse()
	local frames = {}
	for i, p in ipairs(parts) do frames[i] = delta * p.CFrame end
	for i, p in ipairs(parts) do p.CFrame = frames[i] end
end

function F.adopt(cloned, container)
	if cloned:IsA("BasePart") then
		cloned.Parent = container
		return
	end
	for _, c in ipairs(cloned:GetChildren()) do c.Parent = container end
	cloned:Destroy()
end

function F.stripScripts(inst)
	local removed = 0
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("LuaSourceContainer") then
			removed += 1
			pcall(d.Destroy, d)
		end
	end
	return removed
end

function F.tryLoad(assetId)
	local url = "rbxassetid://" .. assetId
	local methods = {
		function() return game:GetObjects(url)[1] end,
		function() return InsertService:LoadAsset(assetId) end,
		function() return InsertService:LoadLocalAsset(url) end,
	}
	for i, method in ipairs(methods) do
		local ok, result = pcall(method)
		if ok and typeof(result) == "Instance" then
			local removed = F.stripScripts(result)
			if removed > 0 then F.cmdLog(("asset %d: removed %d script(s)"):format(assetId, removed)) end
			return result
		end
		F.cmdLog(("asset %d method %d failed: %s"):format(assetId, i, ok and "empty result" or tostring(result)))
	end
	return nil
end

gunTemplate = F.tryLoad(GUN_ASSET_ID)
portalTemplate = F.tryLoad(PORTAL_ASSET_ID)
F.cmdLog("gun: " .. (gunTemplate and "ok" or "FAIL") .. " | portal: " .. (portalTemplate and "ok" or "FAIL"))

local SFX_CANDIDATES = {
	shot = { SHOT_SOUND_ID, "rbxasset://sounds/Rocket shot.wav", "rbxasset://sounds/swoosh.wav" },
	open = { OPEN_SOUND_ID, "rbxasset://sounds/electronicpingshort.wav", "rbxasset://sounds/switch.wav" },
	enter = { ENTER_SOUND_ID, "rbxasset://sounds/electronicpingshort.wav", "rbxasset://sounds/switch.wav" },
	exit = { EXIT_SOUND_ID, "rbxasset://sounds/electronicpingshort.wav", "rbxasset://sounds/switch.wav" },
}
local sfxReady = {}

function F.normalizeSoundId(raw)
	if type(raw) == "number" then return "rbxassetid://" .. raw end
	if type(raw) ~= "string" or raw == "" then return nil end
	if raw:match("^%d+$") then return "rbxassetid://" .. raw end
	return raw
end

function F.probeSound(id)
	local snd = Instance.new("Sound")
	snd.SoundId, snd.Volume = id, 0
	snd.Parent = SoundService
	pcall(ContentProvider.PreloadAsync, ContentProvider, { snd })
	local ok = snd.IsLoaded and snd.TimeLength > 0
	snd:Destroy()
	return ok
end

function F.httpGet(url)
	local function valid(body)
		if type(body) ~= "string" then return nil end
		local head = body:match("^%s*(.)")
		if not head or head == "<" then return nil end
		return body
	end
	local function viaRequest(fn)
		local ok, res = pcall(fn, { Url = url, Method = "GET" })
		if not ok or type(res) ~= "table" then return nil end
		local code = tonumber(res.StatusCode)
		if res.Success == false or (code and code ~= 200) then return nil end
		return valid(res.Body)
	end
	local sources = {
		function()
			if type(syn) == "table" and type(syn.request) == "function" then return viaRequest(syn.request) end
		end,
		function()
			if type(request) == "function" then return viaRequest(request) end
		end,
		function()
			local ok, body = pcall(function() return game:HttpGet(url) end)
			if ok then return valid(body) end
		end,
	}
	for _, source in ipairs(sources) do
		local ok, body = pcall(source)
		if ok and body then return body end
	end
	return nil
end

function F.ensurePortalSound()
	if type(writefile) ~= "function" or type(isfile) ~= "function" or type(getcustomasset) ~= "function" then
		return nil
	end
	local fileName = "portal-gun.mp3"
	local url = "https://raw.githubusercontent.com/bb3131449-source/roblox/main/portal-gun.mp3"
	local ok, result = pcall(function()
		if not isfile(fileName) then
			local body = F.httpGet(url)
			if not body then return nil end
			writefile(fileName, body)
		end
		return getcustomasset(fileName)
	end)
	if ok and type(result) == "string" and result ~= "" then return result end
	return nil
end

task.spawn(function()
	local custom = F.ensurePortalSound()
	if custom then
		for _, name in ipairs({ "shot", "open", "enter", "exit" }) do sfxReady[name] = custom end
	end
	for name, list in pairs(SFX_CANDIDATES) do
		if not sfxReady[name] then
			for _, raw in ipairs(list) do
				local id = F.normalizeSoundId(raw)
				if id then
					local ok, loaded = pcall(F.probeSound, id)
					if ok and loaded then
						sfxReady[name] = id
						break
					end
				end
			end
		end
		F.cmdLog("sfx " .. name .. ": " .. (sfxReady[name] or "none"))
	end
end)

function F.playSfx(name, volume)
	local id = sfxReady[name]
	if not id then return end
	F.safe("sfx " .. name, function()
		local snd = Instance.new("Sound")
		snd.SoundId = id
		snd.Volume = (volume or 1) * SFX_VOLUME
		snd.PlaybackSpeed = 0.95 + math.random() * 0.1
		snd.Parent = SoundService
		snd:Play()
		Debris:AddItem(snd, math.max(snd.TimeLength, 1) + 1)
	end)
end
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
local overlapParams = OverlapParams.new()
overlapParams.FilterType = Enum.RaycastFilterType.Exclude

function F.characterIgnore()
	local list = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then table.insert(list, p.Character) end
	end
	return list
end

function F.castRay(origin, direction, ignore)
	rayParams.FilterDescendantsInstances = ignore
	local ok, result = pcall(Workspace.Raycast, Workspace, origin, direction, rayParams)
	if not ok then
		F.cmdLog("raycast: " .. tostring(result))
		return nil
	end
	return result
end

function F.castFromScreen()
	local cam = Workspace.CurrentCamera
	if not cam then return nil end
	local m = UserInputService:GetMouseLocation()
	local ray = cam:ViewportPointToRay(m.X, m.Y)
	local ignore = F.characterIgnore()
	local dir = ray.Direction * RAYCAST_DISTANCE
	for _ = 1, 8 do
		local hit = F.castRay(ray.Origin, dir, ignore)
		if not hit then return nil end
		local inst = hit.Instance
		if inst and inst:IsA("BasePart") and not inst:IsA("Terrain") and inst.Transparency >= 0.95 then
			table.insert(ignore, inst)
		else
			return hit
		end
	end
	return nil
end

function F.isClear(center, size, ignore)
	overlapParams.FilterDescendantsInstances = ignore
	local ok, parts = pcall(Workspace.GetPartBoundsInBox, Workspace, CFrame.new(center), size, overlapParams)
	if not ok then
		F.cmdLog("overlap query: " .. tostring(parts))
		return true
	end
	for _, p in ipairs(parts) do
		if p.CanCollide then return false end
	end
	return true
end

function F.alive(s)
	return s ~= nil and s == current and s.character.Parent ~= nil
		and s.rootPart.Parent ~= nil and s.humanoid.Health > 0
end

function F.aliveRoot(character)
	if not character or not character.Parent then return nil end
	local hum = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if hum and root and hum.Health > 0 then return root end
	return nil
end

local BTN_BG, BTN_HOVER = Color3.fromRGB(52, 54, 60), Color3.fromRGB(66, 69, 76)
local BTN_TEXT, BTN_STROKE = Color3.fromRGB(226, 229, 234), Color3.fromRGB(110, 114, 122)
local FADE = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local PANEL_X, PANEL_Y = 16, 0.3
local PILL_W, PILL_H, PILL_GAP = 78, 40, 10
local PILL_BG, PILL_BG_HOVER, PILL_ACTIVE = Color3.fromRGB(28, 31, 36), Color3.fromRGB(40, 44, 51), Color3.fromRGB(24, 138, 72)

local gui = F.make("ScreenGui", { Name = "PortalGui", ResetOnSpawn = false }, player:WaitForChild("PlayerGui"))
globalBin:add(gui)

local panel = F.make("Frame", {
	Name = "PortalButtons", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -PANEL_X, PANEL_Y, 0),
	Size = UDim2.fromOffset(PILL_W * 2 + PILL_GAP, PILL_H), BackgroundTransparency = 1, BorderSizePixel = 0, Visible = false,
}, gui)
F.make("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center,
	VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, PILL_GAP),
}, panel)

local hint = F.make("TextLabel", {
	Name = "Hint", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -PANEL_X, PANEL_Y, 30),
	Size = UDim2.fromOffset(170, 18), BackgroundTransparency = 1, Visible = false, TextXAlignment = Enum.TextXAlignment.Right,
	TextColor3 = Color3.fromRGB(170, 175, 182), Font = Enum.Font.Gotham, TextSize = 12, Text = "",
}, gui)
local notice = F.make("TextLabel", {
	Name = "Notice", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.38, 0),
	Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1, TextTransparency = 1, TextWrapped = true,
	TextColor3 = Color3.fromRGB(170, 175, 182), Font = Enum.Font.GothamMedium, TextSize = 18, Text = "",
}, gui)
local noticeId = 0

function F.notify(text, hold)
	noticeId += 1
	local id = noticeId
	if F.noticeTween then F.noticeTween:Cancel() end
	notice.Text, notice.TextTransparency = text, 0
	task.delay(hold or 3, function()
		if id ~= noticeId or not notice.Parent then return end
		F.noticeTween = TweenService:Create(notice, TweenInfo.new(0.4), { TextTransparency = 1 })
		F.noticeTween:Play()
	end)
end

do
	local infoFrame = F.make("TextButton", {
		Name = "Info", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 60),
		Size = UDim2.new(0.9, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Color3.fromRGB(30, 32, 36), BackgroundTransparency = 0.12,
		BorderSizePixel = 0, AutoButtonColor = false, Text = "", Visible = false, ZIndex = 5,
	}, gui)
	F.make("UICorner", { CornerRadius = UDim.new(0, 10) }, infoFrame)
	F.make("UISizeConstraint", { MaxSize = Vector2.new(460, math.huge) }, infoFrame)
	F.make("UIPadding", {
		PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10),
		PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 44),
	}, infoFrame)
	local infoLabel = F.make("TextLabel", {
		Name = "Text", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1, TextWrapped = true, RichText = false, ZIndex = 5,
		TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = BTN_TEXT, Font = Enum.Font.Gotham, TextSize = 14, Text = "",
	}, infoFrame)
	local closeButton = F.make("TextButton", {
		Name = "Close", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 34, 0, -4),
		Size = UDim2.fromOffset(32, 32), BackgroundColor3 = BTN_BG, BorderSizePixel = 0,
		AutoButtonColor = true, Text = "X", TextColor3 = BTN_TEXT, Font = Enum.Font.GothamBold,
		TextSize = 16, ZIndex = 6,
	}, infoFrame)
	F.make("UICorner", { CornerRadius = UDim.new(0, 8) }, closeButton)
	local expiresAt = 0

	local function hide()
		infoFrame.Visible = false
	end

	globalBin:add(infoFrame.Activated:Connect(hide))
	globalBin:add(closeButton.Activated:Connect(hide))
	globalBin:add(RunService.Heartbeat:Connect(function()
		if infoFrame.Visible and os.clock() >= expiresAt then hide() end
	end))

	function F.showInfo(lines, hold)
		infoLabel.Text = table.concat(lines, "\n")
		expiresAt = os.clock() + (hold or 10)
		infoFrame.Visible = true
	end
end

local buttons = {}

function F.paint(entry)
	local active, hover = entry.active, entry.hover
	TweenService:Create(entry.fill, FADE, {
		BackgroundColor3 = active and PILL_ACTIVE or (hover and PILL_BG_HOVER or PILL_BG),
	}):Play()
	TweenService:Create(entry.stroke, FADE, {
		Color = active and GREEN_BRIGHT or BTN_STROKE,
		Transparency = active and 0 or (hover and 0.15 or 0.4),
		Thickness = active and 2.2 or 1.5,
	}):Play()
	TweenService:Create(entry.label, FADE, { TextColor3 = active and Color3.new(1, 1, 1) or BTN_TEXT }):Play()
	TweenService:Create(entry.scale, FADE, { Scale = entry.pressed and 0.94 or (active and 1.06 or 1) }):Play()
end

function F.makeButton(index, name)
	local b = F.make("TextButton", {
		Name = name, LayoutOrder = index, Size = UDim2.fromOffset(PILL_W, PILL_H),
		BackgroundTransparency = 1, BorderSizePixel = 0, AutoButtonColor = false, Text = "",
	}, panel)
	local shadow = F.make("Frame", {
		Name = "Shadow", Position = UDim2.fromOffset(0, 3), Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.65, BorderSizePixel = 0, ZIndex = 1,
	}, b)
	F.make("UICorner", { CornerRadius = UDim.new(1, 0) }, shadow)
	local fill = F.make("Frame", {
		Name = name .. "Fill", Size = UDim2.fromScale(1, 1), BackgroundColor3 = PILL_BG,
		BackgroundTransparency = 0.06, BorderSizePixel = 0, ZIndex = 2,
	}, b)
	F.make("UICorner", { CornerRadius = UDim.new(1, 0) }, fill)
	F.make("UIGradient", {
		Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(185, 190, 200)),
	}, fill)
	local stroke = F.make("UIStroke", {
		Color = BTN_STROKE, Thickness = 1.5, Transparency = 0.4, ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, fill)
	local scale = F.make("UIScale", { Scale = 1 }, fill)
	local label = F.make("TextLabel", {
		Name = "Label", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 3,
		TextColor3 = BTN_TEXT, Font = Enum.Font.GothamBold, TextSize = 18, Text = tostring(index),
	}, fill)
	local entry = { button = b, fill = fill, stroke = stroke, scale = scale, label = label, hover = false, active = false, pressed = false }
	b.MouseEnter:Connect(function() entry.hover = true F.paint(entry) end)
	b.MouseLeave:Connect(function() entry.hover, entry.pressed = false, false F.paint(entry) end)
	b.MouseButton1Down:Connect(function() entry.pressed = true F.paint(entry) end)
	b.MouseButton1Up:Connect(function() entry.pressed = false F.paint(entry) end)
	buttons[index] = entry
end

F.makeButton(1, "EntrancePortal")
F.makeButton(2, "ExitPortal")

function F.refreshUI()
	for i = 1, 2 do
		buttons[i].label.Text = slots[i] and "X" or tostring(i)
	end
	for i = 1, 2 do
		buttons[i].active = placement.slot == i
		F.paint(buttons[i])
	end
	hint.Text = placement.slot == 1 and "tap a surface: entrance"
		or placement.slot == 2 and "tap a surface: exit" or ""
end

local previewMarker = F.newPart(Workspace, "PortalPreview", Vector3.new(0.5, 0.5, 0.5), CFrame.new(), GREEN_BRIGHT, Enum.Material.Neon, Enum.PartType.Ball)
previewMarker.Anchored, previewMarker.Transparency = true, 1
globalBin:add(previewMarker)

function F.resetPlacement()
	placement.slot = nil
	F.refreshUI()
end

function F.gunHeld()
	return current ~= nil and current.holding == true
end

function F.applyGunVisibility()
	local held = F.gunHeld()
	panel.Visible, hint.Visible = held, held
	if not held and placement.slot then F.resetPlacement() end
end

F.refreshUI()

function F.surfaceFrame(hit)
	local n = hit.Normal
	local ref = Vector3.yAxis
	if math.abs(n.Y) > 0.99 then
		local cam = Workspace.CurrentCamera
		ref = F.flatten(cam and cam.CFrame.LookVector or Vector3.zAxis, Vector3.zAxis)
	end
	local y = (ref - n * ref:Dot(n)).Unit
	return CFrame.fromMatrix(hit.Position + n * (PORTAL_THICKNESS / 2), n, y)
end

function F.fillFromTemplate(container, cf)
	if not portalTemplate then return false end
	local ok, err = pcall(function()
		local cloned = portalTemplate:Clone()
		local parts = F.collectParts(cloned)
		assert(#parts > 0, "template has no parts")
		for _, p in ipairs(parts) do
			p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery, p.Massless = true, false, false, false, true
		end
		local target = cf * PORTAL_OFFSET * PORTAL_FIX_ROT
		if cloned:IsA("PVInstance") then
			cloned:PivotTo(target)
		else
			F.alignTo(parts, F.findHandle(cloned) or parts[1], target)
		end
		F.adopt(cloned, container)
	end)
	if not ok then
		F.cmdLog("portal template: " .. tostring(err))
		container:ClearAllChildren()
		return false
	end
	return true
end

function F.smoothPortal(container)
	for _, p in ipairs(F.collectParts(container)) do
		if p:IsA("MeshPart") then
			F.safe("render fidelity", function() p.RenderFidelity = Enum.RenderFidelity.Precise end)
		end
	end
end

function F.fillSmoothDisc(container, cf)
	if not portalTemplate then return false end
	local texture
	for _, p in ipairs(F.collectParts(portalTemplate)) do
		local sm = p:FindFirstChildOfClass("SpecialMesh")
		if sm and sm.TextureId ~= "" then
			texture = sm.TextureId
			break
		end
		if p:IsA("MeshPart") and p.TextureID ~= "" then
			texture = p.TextureID
			break
		end
	end
	if not texture then return false end
	local layers = {}
	for i = 1, STRETCH_LAYERS do
		local part = F.safe("portal layer", F.newPart, container, "Layer" .. i,
			Vector3.new(PORTAL_THICKNESS, PORTAL_DIAMETER, PORTAL_DIAMETER), cf, PORTAL_BASE_COLOR,
			Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
		if not part then
			container:ClearAllChildren()
			return false
		end
		part.Anchored = true
		F.make("Decal", { Texture = texture, Face = Enum.NormalId.Right }, part)
		if i == 1 then F.make("Decal", { Texture = texture, Face = Enum.NormalId.Left }, part) end
		layers[i] = part
	end
	return layers
end

function F.poseLayers(portal)
	local layers = portal.layers
	local c = portal.cf
	local n = c.XVector
	local sc = math.max(portal.scaleValue or 0, MIN_SCALE)
	local b = portal.stretch.x
	local ratio = b / STRETCH_MAX
	local lift = math.clamp(b, 0, STRETCH_MAX * 1.2)
	local rho = b >= 0 and (1 - 0.18 * math.min(ratio, 1.2)) or (1 + 0.25 * math.max(ratio, -1.2))
	local taper = 0.78 * math.min(lift / STRETCH_MAX, 1)
	local rot = CFrame.fromAxisAngle(n, math.rad(portal.angle)) * c.Rotation
	local count = #layers
	local th = math.max(PORTAL_THICKNESS, lift / (count - 1) * 1.3)
	local radius = PORTAL_DIAMETER / 2 * rho
	local flat = lift < 0.04
	local collapsed = flat and portal.collapsed
	portal.collapsed = flat
	for i, part in ipairs(layers) do
		if i == 1 or not flat then
			local f = (i - 1) / (count - 1)
			local r = radius * (1 - taper * f ^ 1.5)
			local z = lift * f + (i - 1) * 0.006
			part.Size = Vector3.new(math.max(th * sc, 0.01), math.max(2 * r * sc, 0.01), math.max(2 * r * sc, 0.01))
			part.CFrame = CFrame.new(c.Position + n * (z * sc)) * rot
		elseif not collapsed then
			part.Size = Vector3.new(0.05, 0.05, 0.05)
			part.CFrame = CFrame.new(c.Position) * rot
		end
	end
end

function F.applyProgress(portal, p)
	if portal.bin.dead then return end
	if portal.layers then
		portal.scaleValue = p
		if portal.pose then portal.pose() end
	elseif not portal.noScale then
		local ok, err = pcall(portal.model.ScaleTo, portal.model, math.max(p, MIN_SCALE))
		if not ok then
			portal.noScale = true
			F.cmdLog("portal scale: " .. tostring(err))
		end
	end
	local alpha = math.clamp(p, 0, 1)
	for part, original in pairs(portal.alpha) do
		part.Transparency = 1 - alpha * (1 - original)
	end
end

function F.animatePortal(portal, goal, time, style, dir)
	if portal.animTween then portal.animTween:Cancel() end
	portal.animTween = F.play(portal.bin, portal.progress, time, { Value = goal }, style, dir)
end

function F.growRing(portal, startD, endD, delay, color)
	portal.bin:delay(delay, function()
		local ring = F.safe("burst ring", F.newPart, Workspace, "PortalBurstRing",
			Vector3.new(0.1, startD, startD), portal.cf, color, Enum.Material.Neon, Enum.PartType.Cylinder)
		if not ring then return end
		ring.Anchored, ring.Transparency = true, 0.25
		portal.bin:add(ring)
		F.play(portal.bin, ring, BURST_RING_TIME, { Size = Vector3.new(0.1, endD, endD), Transparency = 1 })
		portal.bin:delay(BURST_RING_TIME, function() portal.bin:release(ring) end)
	end)
end

function F.burstSparks(portal)
	local anchor = F.safe("burst anchor", F.newPart, Workspace, "PortalBurst",
		Vector3.new(0.2, 0.2, 0.2), portal.cf, GREEN, Enum.Material.Neon)
	if not anchor then return end
	anchor.Anchored, anchor.Transparency = true, 1
	portal.bin:add(anchor)
	F.safe("burst emitter", function()
		local emitter = F.make("ParticleEmitter", {
			Color = ColorSequence.new(GREEN_BRIGHT, GREEN), LightEmission = 1, LightInfluence = 0,
			Rate = 0, Lifetime = NumberRange.new(0.35, 0.7), Speed = NumberRange.new(10, 24),
			SpreadAngle = Vector2.new(180, 180), Drag = 4,
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) }),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) }),
		}, anchor)
		emitter:Emit(BURST_PARTICLES)
		local light = F.make("PointLight", { Color = GREEN, Brightness = 0, Range = 14 }, anchor)
		F.play(portal.bin, light, 0.1, { Brightness = 5 })
		portal.bin:delay(0.1, function() F.play(portal.bin, light, 0.45, { Brightness = 0 }) end)
	end)
	portal.bin:delay(BURST_LIFETIME, function() portal.bin:release(anchor) end)
end

function F.openPortal(portal)
	if portal.closing or portal.bin.dead then return end
	F.animatePortal(portal, 1, OPEN_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	F.playSfx("open", 0.7)
end

function F.buildPortal(cf)
	local container = F.safe("portal container", F.make, "Model", { Name = "PortalInstance" })
	if not container then return nil end
	local portal = { cf = cf, model = container, bin = Bin.new(), alpha = {}, closing = false, noScale = false }
	portal.bin:add(container)
	local pivot = cf * PORTAL_OFFSET * PORTAL_FIX_ROT
	local layers = PORTAL_SMOOTH_DISC and F.fillSmoothDisc(container, cf) or nil
	if layers then
		pivot = cf
		portal.layers = layers
		portal.stretch = { x = 0, v = 0, target = 0 }
	elseif not F.fillFromTemplate(container, cf) then
		local disc = F.safe("portal disc", F.newPart, container, "Disc",
			Vector3.new(PORTAL_THICKNESS, PORTAL_DIAMETER, PORTAL_DIAMETER), cf, PORTAL_COLOR,
			Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
		if not disc then
			portal.bin:clean()
			return nil
		end
		disc.Anchored = true
		pivot = cf
	end
	F.safe("portal smooth", F.smoothPortal, container)
	local progress = F.safe("portal progress", F.make, "NumberValue", { Value = 0 })
	if not progress then
		portal.bin:clean()
		return nil
	end
	portal.progress = progress
	portal.bin:add(progress)
	portal.bin:add(progress.Changed:Connect(function(p) F.applyProgress(portal, p) end))
	portal.pivot = pivot
	F.safe("portal pivot", function() container.WorldPivot = pivot end)
	portal.shift, portal.angle = Vector3.zero, 0
	portal.pose = function()
		if portal.bin.dead then return end
		if portal.layers then
			F.poseLayers(portal)
			return
		end
		local base = portal.pivot + portal.shift
		local spin = CFrame.fromAxisAngle(portal.cf.XVector, math.rad(portal.angle))
		pcall(function() container:PivotTo(CFrame.new(base.Position) * spin * base.Rotation) end)
	end
	portal.bin:add(RunService.RenderStepped:Connect(function(dt)
		if portal.bin.dead then return end
		portal.angle = (portal.angle + PORTAL_SPIN * dt * math.clamp(progress.Value, 0, 1)) % 360
		local st = portal.stretch
		if st then
			local h = math.min(dt, 1 / 30) / 2
			for _ = 1, 2 do
				st.v += (STRETCH_K * (st.target - st.x) - STRETCH_C * st.v) * h
				st.x += st.v * h
			end
		end
		portal.pose()
	end))
	for _, part in ipairs(F.collectParts(container)) do portal.alpha[part] = part.Transparency end
	for _, d in ipairs(container:GetDescendants()) do
		if d:IsA("Decal") then portal.alpha[d] = d.Transparency end
	end
	F.applyProgress(portal, 0)
	container.Parent = Workspace
	portal.bin:delay(BOLT_TIME, function() F.openPortal(portal) end)
	return portal
end

function F.closePortal(portal, instant)
	if instant then
		portal.bin:clean()
		return
	end
	portal.closing = true
	F.playSfx("open", 0.7)
	F.animatePortal(portal, 0, CLOSE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	portal.bin:delay(CLOSE_TIME + 0.1, function() portal.bin:clean() end)
end

function F.linkPortals()
	local a, b = slots[1], slots[2]
	if a then a.paired = nil end
	if b then b.paired = nil end
	if a and b and not a.placeId and not b.placeId then a.paired, b.paired = b, a end
end

function F.closeSlot(i, instant)
	local p = slots[i]
	if not p then return end
	slots[i] = nil
	p.paired = nil
	F.closePortal(p, instant)
	F.linkPortals()
	portalEpoch += 1
	F.refreshUI()
end

function F.destroyAllPortals(instant)
	F.closeSlot(1, instant)
	F.closeSlot(2, instant)
	portalEpoch += 1
end

function F.hideGunModel(model)
	for _, p in ipairs(F.collectParts(model)) do
		if p:GetAttribute("PortalShownT") == nil then
			p:SetAttribute("PortalShownT", p.Transparency)
		end
		p.Transparency = 1
	end
end

function F.showGunModel(model)
	for _, p in ipairs(F.collectParts(model)) do
		local shown = p:GetAttribute("PortalShownT")
		if shown ~= nil then p.Transparency = shown end
	end
end

function F.addGunTemplate(model, root, rootCFrame)
	if not gunTemplate then return end
	F.safe("gun template", function()
		local cloned = gunTemplate:Clone()
		local parts = F.collectParts(cloned)
		local handle = F.findHandle(cloned)
		assert(handle, "gun template has no parts")
		F.alignTo(parts, handle, rootCFrame)
		for _, p in ipairs(parts) do
			p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery, p.Massless = false, false, false, false, true
			F.make("WeldConstraint", { Part0 = root, Part1 = p }, p)
		end
		F.adopt(cloned, model)
	end)
end

function F.buildGun(rootCFrame)
	local model = F.make("Model", { Name = "PortalDevice" })
	local root = F.newPart(model, "Root", Vector3.new(0.2, 0.2, 0.2), rootCFrame, Color3.fromRGB(112, 116, 125), Enum.Material.SmoothPlastic)
	root.Transparency = 1
	root:SetAttribute("PortalRoot", true)
	model.PrimaryPart = root
	F.addGunTemplate(model, root, rootCFrame)
	local muzzle = F.newPart(model, "Muzzle", Vector3.new(0.05, 0.05, 0.05), rootCFrame * MUZZLE_OFFSET, GREEN, Enum.Material.Neon)
	muzzle.Transparency = 1
	muzzle:SetAttribute("PortalMuzzle", true)
	F.make("WeldConstraint", { Part0 = root, Part1 = muzzle }, muzzle)
	local light = F.make("PointLight", { Color = GREEN, Brightness = LIGHT_MIN, Range = LIGHT_RANGE }, muzzle)
	local sound = nil
	F.hideGunModel(model)
	return { model = model, root = root, lens = muzzle, light = light, sound = sound }
end

function F.spawnBolt(s, targetPos, color)
	local bin = s.gunBin
	if not bin or bin.dead or not s.lens then return end
	local bolt = F.safe("bolt", F.make, "Part", {
		Name = "PortalBolt", Shape = Enum.PartType.Ball, Size = Vector3.new(BOLT_SIZE, BOLT_SIZE, BOLT_SIZE),
		Color = color or GREEN_BRIGHT, Material = Enum.Material.Neon, Anchored = true,
		CanCollide = false, CanTouch = false, CanQuery = false, Position = s.lens.Position,
	}, Workspace)
	if not bolt then return end
	bin:add(bolt)
	F.play(bin, bolt, BOLT_TIME, { Position = targetPos }, Enum.EasingStyle.Linear)
	bin:delay(BOLT_TIME, function() bin:release(bolt) end)
end

function F.fireVisual(targetPos, color)
	local s = current
	if not F.alive(s) or not s.holding or not s.lens then return end
	local bin = s.gunBin
	if not bin or bin.dead then return end
	s.shotId += 1
	local id = s.shotId
	local base, shoulder = s.baseC0, s.shoulder
	local function armC0(angle)
		return CFrame.new(base.Position) * CFrame.Angles(math.rad(angle), 0, 0) * base.Rotation
	end
	local function armActive() return F.alive(s) and s.shotId == id end

	F.playSfx("shot")
	if s.armTween then s.armTween:Cancel() end
	s.armTween = F.play(bin, shoulder, RAISE_TIME, { C0 = armC0(RAISE_ANGLE) })
	F.spawnBolt(s, targetPos, color)

	bin:delay(RAISE_TIME + 0.03, function()
		if armActive() then s.armTween = F.play(bin, shoulder, 0.06, { C0 = armC0(RAISE_ANGLE + RECOIL_ANGLE) }) end
	end)
	bin:delay(HOLD_TIME, function()
		if armActive() then s.armTween = F.play(bin, shoulder, LOWER_TIME, { C0 = base }) end
	end)
end

function F.registerPortal(cf, slot, opts)
	local placeId = opts and opts.placeId or nil
	local otherSlot = slot == 1 and 2 or 1
	if slots[otherSlot] and (placeId or slots[otherSlot].placeId) then F.closeSlot(otherSlot) end
	F.closeSlot(slot)
	local portal = F.buildPortal(cf)
	if not portal then return nil end
	portal.placeId = placeId
	slots[slot] = portal
	F.linkPortals()
	F.fireVisual(cf.Position, GREEN_BRIGHT)
	F.refreshUI()
	return portal
end

function F.placePortalAt(hit)
	local slot = placement.slot
	if not hit or not slot then return end
	if not F.registerPortal(F.surfaceFrame(hit), slot) then return end
	placement.slot = nil
	F.refreshUI()
end

function F.onButton(i)
	if not F.gunHeld() or placeBusy then return end
	local placeLink = (slots[1] and slots[1].placeId) or (slots[2] and slots[2].placeId)
	if placeLink or (slots[1] and slots[2]) then
		F.destroyAllPortals()
		F.resetPlacement()
	elseif slots[i] then
		F.closeSlot(i)
		F.resetPlacement()
	else
		placement.slot = placement.slot ~= i and i or nil
		F.refreshUI()
	end
end

for i = 1, 2 do
	globalBin:add(buttons[i].button.Activated:Connect(function() F.onButton(i) end))
end

globalBin:add(UserInputService.InputBegan:Connect(function(input, gpe)
	if gpe or placeBusy or not placement.slot or not F.gunHeld() then return end
	if input.UserInputType ~= Enum.UserInputType.Touch and input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
	F.placePortalAt(F.castFromScreen())
end))

globalBin:add(RunService.RenderStepped:Connect(function()
	if not placement.slot or not F.gunHeld() then
		previewMarker.Transparency = 1
		return
	end
	local hit = F.castFromScreen()
	if hit then
		previewMarker.CFrame = CFrame.new(hit.Position + hit.Normal * 0.15)
		previewMarker.Transparency = 0.5
	else
		previewMarker.Transparency = 1
	end
end))

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

local makeGhost, travel, travelOut = (function()
	local GHOST_MIN = 0.12
	local Debris = game:GetService("Debris")

	local function clamp01(x) return math.clamp(x, 0, 1) end
	local function lerp(a, b, t) return a + (b - a) * t end
	local function smooth(x)
		x = clamp01(x)
		return x * x * (3 - 2 * x)
	end

	local function poseVerticalEnter(c, a)
		local e = a ^ 2.2
		local off = c.cf0.Position - c.C
		local nc = off:Dot(c.n)
		local lat = off - c.n * nc
		local pos = c.C + lat * (1 - e) + c.n * lerp(nc, -0.9, e)
		return CFrame.new(pos) * c.cf0.Rotation, 1, 1 - smooth((a - 0.5) / 0.5)
	end

	local function poseVerticalExit(c, a)
		local e = a ^ 1.25
		local pos = (c.C - c.n * 0.9):Lerp(c.cf0.Position, e)
		return CFrame.new(pos) * c.cf0.Rotation, 1, smooth((a - 0.05) / 0.4)
	end

	local function poseHorizontalEnter(c, a)
		local e = a ^ 1.9
		local off = c.cf0.Position - c.C
		local nc = off:Dot(c.n)
		local lat = off - c.n * nc
		local pos = c.C + lat * (1 - e) + c.n * lerp(nc, -2.4, e)
		return CFrame.new(pos) * c.cf0.Rotation, 1, 1 - smooth((a - 0.6) / 0.4)
	end

	local function poseHorizontalExit(c, a)
		local e = a ^ 2.2
		local pos = (c.C - c.n * 2.4):Lerp(c.cf0.Position, e)
		return CFrame.new(pos) * c.cf0.Rotation, 1, smooth(a / 0.3)
	end

	local PROFILE = {
		verticalEnter = { time = 0.32, pose = poseVerticalEnter, fov = -5 },
		verticalExit = { time = 0.38, pose = poseVerticalExit, punch = 8 },
		horizontalEnter = { time = 0.38, pose = poseHorizontalEnter, fov = -7 },
		horizontalExit = { time = 0.42, pose = poseHorizontalExit, punch = 12 },
	}

	local function portalKind(portal)
		return math.abs(portal.cf.XVector.Y) > FLOOR_NORMAL and "horizontal" or "vertical"
	end

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
		local highlight = F.safe("ghost highlight", F.make, "Highlight", {
			FillColor = GREEN_BRIGHT, OutlineColor = GREEN_BRIGHT, FillTransparency = 1, OutlineTransparency = 1,
			DepthMode = Enum.HighlightDepthMode.Occluded, Adornee = ghost,
		}, ghost)
		local emitter = F.safe("ghost emitter", F.make, "ParticleEmitter", {
			Color = ColorSequence.new(GREEN_BRIGHT, GREEN), LightEmission = 1, LightInfluence = 0,
			Rate = 0, Lifetime = NumberRange.new(0.3, 0.6), Speed = NumberRange.new(1, 6),
			SpreadAngle = Vector2.new(180, 180), Drag = 2,
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) }),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) }),
		}, ghost.PrimaryPart)
		return { model = ghost, alpha = alpha, noScale = false, highlight = highlight, emitter = emitter }
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
		local v = clamp01(vis)
		local glow = math.sin(math.pi * v)
		if g.highlight then
			g.highlight.FillTransparency = 1 - 0.6 * glow
			g.highlight.OutlineTransparency = 1 - 0.85 * math.sqrt(math.max(glow, 0))
		end
		if g.emitter then g.emitter.Rate = 25 + 110 * (1 - v) end
	end

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

	local function entryEffects(portal)
		F.playSfx("enter", 0.7)
	end

	local function exitEffects(portal)
		F.playSfx("exit", 0.7)
		F.burstSparks(portal)
	end

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
			end, function()
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
		end, function()
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
	local s = current
	if not F.alive(s) or s.teleporting or s.humanoid.SeatPart or from.bin.dead or to.bin.dead then return end
	s.teleporting = true
	F.lockPortals(s, from, to)

	do
		local p = s.rootPart.Position
		lastBack = { x = p.X, y = p.Y, z = p.Z, placeId = game.PlaceId, at = os.time() }
	end

	local ignore = F.characterIgnore()
	local pos, look, vel, stand = F.exitTransform(s, from, to)
	pos = F.snapToGround(pos, stand, ignore)
	local clear = F.findClearPosition(pos, stand, to.cf.XVector, ignore)
	if clear then pos = clear else F.cmdLog("exit crowded, forcing teleport") end

	local finalCF = CFrame.lookAt(pos, pos + look)
	local restore = F.lockStates(s.humanoid)
	local ghost = makeGhost(s.character)
	if not ghost then
		F.instantTeleport(s, finalCF, vel, restore)
		return
	end
	travel(s, from, to, finalCF, vel, restore, ghost)
end
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
		uid = player.UserId, at = os.time(), returnPortal = ARRIVAL_RETURN_PORTAL, tool = toolEnabled,
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
	local s = current
	if placeBusy or not F.alive(s) or s.teleporting or s.humanoid.SeatPart then return end
	if slots[1] ~= portal and slots[2] ~= portal then return end
	local placeId = portal.placeId
	if not placeId then return end

	placeBusy, s.teleporting = true, true
	F.lockPortals(s, portal)
	do
		local p = s.rootPart.Position
		lastBack = { x = p.X, y = p.Y, z = p.Z, placeId = game.PlaceId, at = os.time() }
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
		placeBusy = false
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
		if not F.alive(s) or (slots[1] ~= portal and slots[2] ~= portal) then
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

	local ghost = makeGhost(s.character)
	if ghost then
		travelOut(s, portal, ghost, restore, launch, onAbort)
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
	local s = current
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
		local portal = slots[i]
		if portal and not s.locks[portal] and (portal.placeId or portal.paired) then
			local c = portal.cf.Position
			if (pos - c).Magnitude <= TRIGGER_RADIUS or F.segmentDistance(last, pos, c) <= TRIGGER_RADIUS then
				if portal.placeId then F.enterPlacePortal(portal) else F.teleportThrough(portal, portal.paired) end
				return
			end
		end
	end
end))

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

local mapBoundsCache
function F.mapBounds()
	local cached = mapBoundsCache
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
	if mn.X == math.huge then
		local root = current and current.rootPart
		local c = root and root.Position or Vector3.zero
		mn, mx = c - Vector3.new(512, 256, 512), c + Vector3.new(512, 256, 512)
	end
	mapBoundsCache = { min = mn, max = mx, parts = parts, at = os.clock() }
	return mn, mx, parts
end

function F.randomMapSpot()
	local mn, mx, parts = F.mapBounds()
	local s = current
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

function F.findExtremeSpot(wantHigh)
	local s = current
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

function F.findRoofSpot()
	local s = current
	if not F.alive(s) then return nil end
	local origin = s.rootPart.Position
	local ignore = F.characterIgnore()
	local best, bestY = nil, origin.Y

	local function consider(hit)
		if not hit or not F.spotValid(hit, ignore) then return end
		local y = hit.Position.Y
		if y > origin.Y + 4 and y > bestY then
			best, bestY = hit, y
		end
	end

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

local portalSaves = nil

function F.readSaves()
	if portalSaves then return portalSaves end
	portalSaves = {}
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
			portalSaves = env.__PortalSaves
			return portalSaves
		end
	end
	if raw then
		local ok, data = pcall(HttpService.JSONDecode, HttpService, raw)
		if ok and type(data) == "table" then portalSaves = data end
	end
	return portalSaves
end

function F.writeSaves()
	local data = portalSaves or {}
	local okEnv, env = pcall(function() return getgenv() end)
	if okEnv and type(env) == "table" then env.__PortalSaves = data end
	if writefile then
		local ok, err = pcall(writefile, SAVES_FILE, HttpService:JSONEncode(data))
		if not ok then F.cmdLog("save file: " .. tostring(err)) end
		return ok
	end
	return true
end

function F.normName(raw)
	return (tostring(raw or ""):lower():gsub("%s+", "_"):sub(1, 32))
end

function F.saveCurrentSpot(name)
	local s = current
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

function F.runLink(label, resolve)
	local s = current
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
	local epoch = portalEpoch

	task.wait(TP_COMMAND_DELAY)
	if epoch ~= portalEpoch or current ~= s or not F.alive(s) then
		if epoch == portalEpoch then F.destroyAllPortals() end
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

function F.runArrival(data)
	if not game:IsLoaded() then game.Loaded:Wait() end
	local s
	local deadline = os.clock() + 20
	while os.clock() < deadline do
		if F.alive(current) then s = current break end
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
		if current == s then
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
	F.lockPortals(s, portal)
	local epoch = portalEpoch

	task.wait(OPEN_TIME + BOLT_TIME + 0.1)
	if epoch ~= portalEpoch or not F.alive(s) then release() return end

	local ignore = F.characterIgnore()
	local stand = F.standHeight(s.humanoid, s.rootPart)
	local n = portal.cf.XVector
	local pos = F.snapToGround(portal.cf.Position + n * (stand + EXIT_CLEARANCE), stand, ignore)
	pos = F.findClearPosition(pos, stand, n, ignore) or pos
	local look = F.flatten(s.rootPart.CFrame.LookVector, Vector3.new(0, 0, -1))
	local finalCF = CFrame.lookAt(pos, pos + look)
	local vel = n * TOSS_SPEED

	local restore = F.lockStates(s.humanoid)
	local ghost = makeGhost(s.character)
	if not ghost then
		F.instantTeleport(s, finalCF, vel, restore)
		return
	end
	travel(s, nil, portal, finalCF, vel, restore, ghost)
end

local commands = {}

function F.exclusive(name, fn, ...)
	if tpBusy or placeBusy then F.cmdLog(name .. ": another command is still running") return end
	tpBusy = true
	local ok, err = pcall(fn, ...)
	tpBusy = false
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

commands.delete = commands.del

commands.back = function()
	if not lastBack then
		F.cmdLog("nothing to go back to (walk through a portal first)")
		F.notify("No previous portal position")
		return
	end
	if lastBack.placeId and lastBack.placeId ~= game.PlaceId then
		F.cmdLog(("back point is in place %d (you are in %d)"):format(lastBack.placeId, game.PlaceId))
		F.notify("Back point is in another place")
		return
	end
	local bx, by, bz = lastBack.x, lastBack.y, lastBack.z
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
		local s = current
		if not F.alive(s) then F.cmdLog("no local character") return end
		local okInfo, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, id, Enum.InfoType.Asset)
		if okInfo and type(info) == "table" and info.AssetTypeId ~= 9 then
			F.notify("This id is not a place")
			F.cmdLog(("id %d is not a place"):format(id))
			return
		end
		if not okInfo then F.cmdLog("place check skipped: " .. tostring(info)) end
		if current ~= s or not F.alive(s) or s.teleporting or placeBusy then
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
	local s = current
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
	if not portalTemplate then
		F.showInfo({ "Portal template not loaded" }, 8)
		return
	end
	local lines = { "Portal template: " .. portalTemplate.ClassName }
	for _, p in ipairs(F.collectParts(portalTemplate)) do
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
		"ps (throw gun, green blast) | give | take (stops script) | clear | pos | portalinfo | help",
	}
	for _, line in ipairs(lines) do F.cmdLog(line) end
	F.showInfo(lines, 15)
end

function F.handleCommand(msg)
	if type(msg) ~= "string" then return end
	if msg:sub(1, #COMMAND_PREFIX):lower() ~= COMMAND_PREFIX then return end
	local now = os.clock()
	if msg == lastMsg and now - lastMsgAt < COMMAND_DEDUP then return end
	lastMsg, lastMsgAt = msg, now

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

local toolTemplate
local pendingTool
local toolGivenLogged = false
local boundTools = {}
local watchedContainers = {}

function F.isPortalTool(inst)
	return typeof(inst) == "Instance" and inst:IsA("Tool") and inst.Name == TOOL_NAME
end

function F.findMarked(inst, attr)
	if inst:GetAttribute(attr) then return inst end
	for _, d in ipairs(inst:GetDescendants()) do
		if d:GetAttribute(attr) then return d end
	end
	return nil
end

function F.isToolPoseTrack(track)
	local name = string.lower(track.Name or "")
	if string.find(name, "tool", 1, true) then return true end
	local anim = track.Animation
	if not anim then return false end
	local id = string.lower(anim.AnimationId or "")
	return string.find(id, "507768375", 1, true)
		or string.find(id, "182393478", 1, true)
		or string.find(id, "522635514", 1, true)
		or string.find(id, "522638767", 1, true)
end

function F.suppressToolPose(humanoid, bin)
	local function sweep()
		local function kill(track)
			if F.isToolPoseTrack(track) then pcall(function() track:Stop(0) end) end
		end
		local animator = humanoid:FindFirstChildOfClass("Animator")
		if animator then
			for _, track in ipairs(animator:GetPlayingAnimationTracks()) do kill(track) end
		end
		local ok, tracks = pcall(function() return humanoid:GetPlayingAnimationTracks() end)
		if ok and tracks then
			for _, track in ipairs(tracks) do kill(track) end
		end
	end
	sweep()
	bin:add(humanoid.AnimationPlayed:Connect(function(track)
		if F.isToolPoseTrack(track) then pcall(function() track:Stop(0) end) end
	end))
	bin:delay(0, sweep)
	bin:delay(0.05, sweep)
	bin:delay(0.2, sweep)
end

function F.holdGun(s, tool)
	if not F.alive(s) or s.holding or not tool or tool.Parent ~= s.character then return end
	local model = tool:FindFirstChild("PortalDevice")
	if not model then return end
	local root = F.findMarked(model, "PortalRoot")
	local lens = F.findMarked(model, "PortalMuzzle")
	if not root or not lens or not s.hand.Parent or not s.shoulder.Parent then return end

	local gunBin = Bin.new()
	s.gunBin = gunBin
	s.holding = true
	s.heldTool = tool
	s.lens = lens
	s.light = lens:FindFirstChildOfClass("PointLight")
	s.sound = lens:FindFirstChildOfClass("Sound")
	gunBin:add(function()
		if s.shoulder.Parent then s.shoulder.C0 = s.baseC0 end
	end)

	local rootCFrame = s.hand.CFrame * s.offset
	F.alignTo(F.collectParts(model), root, rootCFrame)
	local weld = F.safe("gun weld", F.make, "Weld", { Part0 = s.hand, Part1 = root, C0 = s.offset }, root)
	if not weld then
		s.holding = false
		s.heldTool = nil
		s.lens, s.light, s.sound = nil, nil, nil
		s.gunBin = nil
		gunBin:clean()
		F.hideGunModel(model)
		F.applyGunVisibility()
		return
	end
	gunBin:add(weld)
	F.showGunModel(model)
	F.suppressToolPose(s.humanoid, gunBin)
	F.applyGunVisibility()
end

function F.releaseGun(s)
	if not s or not s.holding then return end
	s.holding = false
	s.shotId += 1
	if s.armTween then
		pcall(function() s.armTween:Cancel() end)
		s.armTween = nil
	end
	if s.light then
		s.light.Brightness = LIGHT_MIN
		s.light.Range = LIGHT_RANGE
	end
	local tool = s.heldTool
	local model = tool and tool:FindFirstChild("PortalDevice")
	if model then F.hideGunModel(model) end
	s.heldTool = nil
	s.lens, s.light, s.sound = nil, nil, nil
	local gunBin = s.gunBin
	s.gunBin = nil
	if gunBin then gunBin:clean() end
	F.applyGunVisibility()
end

function F.onGunUnequipped(tool)
	if pendingTool == tool then pendingTool = nil end
	if current and current.heldTool == tool then F.releaseGun(current) end
end

function F.onGunEquipped(tool)
	pendingTool = tool
	if current and tool.Parent == current.character then F.holdGun(current, tool) end
end

function F.bindTool(tool)
	if boundTools[tool] or not F.isPortalTool(tool) then return end
	boundTools[tool] = true
	globalBin:add(tool.Equipped:Connect(function()
		F.onGunEquipped(tool)
	end))
	globalBin:add(tool.Unequipped:Connect(function()
		F.onGunUnequipped(tool)
	end))
	globalBin:add(tool.AncestryChanged:Connect(function()
		if tool.Parent ~= player.Character then F.onGunUnequipped(tool) end
	end))
	globalBin:add(tool.Destroying:Connect(function()
		boundTools[tool] = nil
		F.onGunUnequipped(tool)
	end))
	if tool.Parent == player.Character then F.onGunEquipped(tool) end
end

function F.collectTools()
	local list = {}
	local function take(container)
		if not container then return end
		for _, child in ipairs(container:GetChildren()) do
			if F.isPortalTool(child) then table.insert(list, child) end
		end
	end
	take(player:FindFirstChild("Backpack"))
	take(player.Character)
	return list
end

function F.dedupeTools()
	local list = F.collectTools()
	if #list <= 1 then return end
	local keep = list[1]
	local character = player.Character
	for _, tool in ipairs(list) do
		if character and tool.Parent == character then
			keep = tool
			break
		end
	end
	for _, tool in ipairs(list) do
		if tool ~= keep then tool:Destroy() end
	end
end

function F.watchTools(container)
	if not container or watchedContainers[container] then return end
	watchedContainers[container] = true
	globalBin:add(container.ChildAdded:Connect(function(child)
		if not F.isPortalTool(child) then return end
		F.bindTool(child)
		F.dedupeTools()
	end))
	for _, child in ipairs(container:GetChildren()) do
		if F.isPortalTool(child) then F.bindTool(child) end
	end
	F.dedupeTools()
end

function F.buildPortalTool()
	local tool = F.make("Tool", {
		Name = TOOL_NAME,
		RequiresHandle = true,
		CanBeDropped = false,
		ManualActivationOnly = true,
	})
	local handle = F.newPart(tool, "Handle", Vector3.new(0.2, 0.2, 0.2), CFrame.new(), Color3.fromRGB(112, 116, 125), Enum.Material.SmoothPlastic)
	handle.Transparency = 1
	handle.CastShadow = false
	local gun = F.buildGun(CFrame.new())
	if not gun then
		tool:Destroy()
		return nil
	end
	gun.model.Parent = tool
	return tool
end

function F.ensureStarter()
	if not toolTemplate or not toolEnabled then return end
	local sg = player:FindFirstChild("StarterGear")
	if not sg then return end
	local found = false
	for _, child in ipairs(sg:GetChildren()) do
		if F.isPortalTool(child) then
			if not found then found = true else child:Destroy() end
		end
	end
	if found then return end
	local copy = toolTemplate:Clone()
	local ok, err = pcall(function() copy.Parent = sg end)
	if not ok then
		F.cmdLog("StarterGear: " .. tostring(err))
		copy:Destroy()
	end
end

function F.grantTool()
	if not toolTemplate or not toolEnabled then return end
	if #F.collectTools() > 0 then
		F.dedupeTools()
		return
	end
	local backpack = player:FindFirstChild("Backpack")
	if not backpack then return end
	local tool = toolTemplate:Clone()
	F.bindTool(tool)
	tool.Parent = backpack
	if not toolGivenLogged then
		toolGivenLogged = true
		F.cmdLog("Portal gun given")
	end
end

function F.maintainTool(character)
	F.watchTools(character)
	task.spawn(function()
		for _ = 1, 12 do
			if player.Character ~= character or not toolEnabled then return end
			F.ensureStarter()
			F.grantTool()
			if #F.collectTools() > 0 then return end
			task.wait(0.25)
		end
	end)
end

function F.removeToolInstances()
	local tools = {}
	for tool in pairs(boundTools) do table.insert(tools, tool) end
	for _, tool in ipairs(F.collectTools()) do
		if not table.find(tools, tool) then table.insert(tools, tool) end
	end
	for _, tool in ipairs(tools) do pcall(function() tool:Destroy() end) end
	local sg = player:FindFirstChild("StarterGear")
	if sg then
		for _, child in ipairs(sg:GetChildren()) do
			if F.isPortalTool(child) then pcall(function() child:Destroy() end) end
		end
	end
end

function F.destroyPortalTools()
	F.removeToolInstances()
	if toolTemplate then
		pcall(function() toolTemplate:Destroy() end)
		toolTemplate = nil
	end
end

F.PS = {
	THROW_DISTANCE = 18,
	FLIGHT_TIME = 1.2,
	FLIGHT_ARC = 7,
	FUSE_TIME = 2.5,
	REST_LIFT = 0.45,
	BEEP_SOUND = "rbxasset://sounds/electronicpingshort.wav",
	BOOM_SOUND = "rbxasset://sounds/impact_explosion_03.mp3",
	BEEP_VOLUME = 1.2,
	BOOM_VOLUME = 2.5,
	BEEP_TIMES = { 0, 0.5, 0.95, 1.35, 1.7, 1.98, 2.2, 2.36 },
	SPARK_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds",
	SMOKE_TEXTURE = "rbxasset://textures/particles/smoke_main.dds",
	WHITE = Color3.fromRGB(235, 255, 242),
	DEEP = Color3.fromRGB(12, 120, 60),
	SCALE = 2.7,
	busy = false,
	armed = 0,
	post = false,
	shakes = 0,
	shakeBase = Vector3.zero,
}

function F.psSound(id, volume, speed, parent)
	if not id or id == "" then return end
	F.safe("ps sound", function()
		local snd = Instance.new("Sound")
		snd.SoundId = id
		snd.Volume = volume * SFX_VOLUME
		snd.PlaybackSpeed = speed or 1
		snd.RollOffMinDistance = 25
		snd.RollOffMaxDistance = 450
		snd.Parent = parent or SoundService
		snd:Play()
		Debris:AddItem(snd, 6)
	end)
end

function F.psDiscCF(position, normal)
	local ref = math.abs(normal.Y) > 0.99 and Vector3.xAxis or Vector3.yAxis
	local tangent = normal:Cross(ref).Unit
	return CFrame.fromMatrix(position, normal, tangent)
end

function F.psCloneGun(model)
	local clone = model:Clone()
	F.stripScripts(clone)
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("JointInstance") or d:IsA("WeldConstraint") or d:IsA("Sound") then
			d:Destroy()
		elseif d:IsA("PointLight") then
			d.Brightness = 0
		elseif d:IsA("BasePart") then
			d.Anchored, d.CanCollide, d.CanTouch, d.CanQuery, d.Massless = true, false, false, false, true
		end
	end
	F.showGunModel(clone)
	return clone
end

function F.psLandingSpot(s, dir)
	local PS = F.PS
	local ignore = F.characterIgnore()
	local origin = s.rootPart.Position
	local target = origin + dir * PS.THROW_DISTANCE
	local wall = F.castRay(origin, dir * PS.THROW_DISTANCE, ignore)
	if wall then target = wall.Position - dir * 0.7 end
	local ground = F.castRay(target + Vector3.new(0, 5, 0), Vector3.new(0, -40, 0), ignore)
	if ground then return ground.Position, ground.Normal end
	return Vector3.new(target.X, origin.Y - 3, target.Z), Vector3.yAxis
end

function F.psEnsureHeld(s)
	if s.holding and s.heldTool and s.heldTool.Parent == s.character then return s.heldTool end
	local tool = F.collectTools()[1]
	if not tool then return nil end
	if tool.Parent ~= s.character then
		pcall(function() s.humanoid:EquipTool(tool) end)
	end
	local deadline = os.clock() + 2.5
	while os.clock() < deadline do
		if not F.alive(s) then return nil end
		if s.holding and s.heldTool == tool then return tool end
		task.wait(0.05)
	end
	return nil
end

function F.psExplode(ground, normal)
	local PS = F.PS
	local K = PS.SCALE
	local Lighting = game:GetService("Lighting")
	local rng = Random.new()
	local fx = Bin.new()
	local fxHandle = globalBin:add(function() fx:clean() end)
	local folder = fx:add(F.make("Folder", { Name = "PortalPSFx" }, Workspace))
	local up = Vector3.yAxis
	local n = normal.Magnitude > 0 and normal.Unit or up
	local pos = ground + n * 1.5
	local myRoot = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local dist = myRoot and (myRoot.Position - pos).Magnitude or 0
	local f = math.clamp(1.15 - dist / 240, 0.15, 1)

	local function part(props)
		props.Anchored, props.CanCollide, props.CanTouch, props.CanQuery, props.CastShadow = true, false, false, false, false
		props.Material = props.Material or Enum.Material.Neon
		return F.make("Part", props, folder)
	end
	local function grow(obj, time, size, style)
		F.play(fx, obj, time, { Size = size, Transparency = 1 }, style or Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	end
	local function ball(name, color, startSize, startT, pivot)
		return part({ Name = name, Shape = Enum.PartType.Ball, Size = Vector3.new(startSize, startSize, startSize), Color = color, Transparency = startT, Position = pivot or pos })
	end
	local function cube(v) return Vector3.new(v, v, v) end

	local em = part({ Name = "Emitter", Size = Vector3.one, Transparency = 1, Position = pos })

	F.psSound(PS.BOOM_SOUND, PS.BOOM_VOLUME, 0.8, em)
	F.psSound(PS.BOOM_SOUND, PS.BOOM_VOLUME * 0.8, 0.5, em)

	local core = ball("Core", PS.WHITE, 3, 0)
	local light = F.make("PointLight", { Color = GREEN, Brightness = 22, Range = 60, Shadows = false }, core)
	grow(core, 0.5, cube(16 * K))
	F.play(fx, light, 2.6, { Brightness = 0 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	grow(ball("Heart", Color3.new(1, 1, 1), 1, 0), 0.4, cube(10 * K))
	grow(ball("Shell", GREEN_BRIGHT, 4, 0.35), 1.5, cube(46 * K))

	fx:delay(0.1, function() grow(ball("Shell2", GREEN, 3, 0.5), 1.2, cube(30 * K)) end)
	fx:delay(0.3, function() grow(ball("Shell3", PS.WHITE, 10, 0.8), 1.8, cube(60 * K)) end)

	local function disc(delay, diameter, time, color, startT, thick)
		fx:delay(delay, function()
			local d = part({
				Name = "Disc", Shape = Enum.PartType.Cylinder, Size = Vector3.new(thick, 3, 3), Color = color,
				Transparency = startT, CFrame = F.psDiscCF(ground + n * 0.12, n),
			})
			grow(d, time, Vector3.new(thick * 0.3, diameter, diameter))
		end)
	end
	disc(0, 64 * K, 1.4, GREEN_BRIGHT, 0.25, 0.3)
	disc(0.08, 44 * K, 1.1, PS.WHITE, 0.4, 0.2)
	disc(0.22, 90 * K, 1.8, GREEN, 0.5, 0.2)

	local function pillar(width, height, startT, time, color)
		local p = part({
			Name = "Pillar", Shape = Enum.PartType.Cylinder, Size = Vector3.new(height, width, width), Color = color,
			Transparency = startT, CFrame = CFrame.new(ground + up * (height / 2)) * CFrame.Angles(0, 0, math.pi / 2),
		})
		grow(p, time, Vector3.new(height * 1.15, 0.1, 0.1), Enum.EasingStyle.Quad)
	end
	pillar(14, 255, 0.2, 1.6, GREEN_BRIGHT)
	pillar(33, 210, 0.7, 1.3, GREEN)
	pillar(6, 345, 0, 1.0, PS.WHITE)

	local function cseq(a, b, c)
		return ColorSequence.new({ ColorSequenceKeypoint.new(0, a), ColorSequenceKeypoint.new(0.35, b), ColorSequenceKeypoint.new(1, c) })
	end
	local function nseq(a, b, c)
		return NumberSequence.new({ NumberSequenceKeypoint.new(0, a), NumberSequenceKeypoint.new(0.4, b), NumberSequenceKeypoint.new(1, c) })
	end
	local function burst(props, count, delayTime)
		props.Rate = 0
		props.Enabled = false
		props.LightInfluence = 0
		local e = F.safe("ps emitter", F.make, "ParticleEmitter", props, em)
		if not e then return end
		local function go()
			if e.Parent then e:Emit(count) end
		end
		if delayTime and delayTime > 0 then fx:delay(delayTime, go) else go() end
	end

	burst({
		Texture = PS.SPARK_TEXTURE, Color = cseq(Color3.new(1, 1, 1), GREEN_BRIGHT, GREEN), LightEmission = 1,
		Size = nseq(7, 4.5, 0), Transparency = nseq(0, 0.2, 1), Lifetime = NumberRange.new(1.6, 3.2),
		Speed = NumberRange.new(70, 180), SpreadAngle = Vector2.new(180, 180), Acceleration = Vector3.new(0, -40, 0), Drag = 1.5,
		Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-120, 120),
	}, 70, 0)
	burst({
		Texture = PS.SMOKE_TEXTURE, Color = cseq(Color3.fromRGB(120, 255, 175), Color3.fromRGB(20, 140, 70), Color3.fromRGB(8, 50, 30)),
		LightEmission = 0.7, Size = nseq(20, 45, 66), Transparency = nseq(0.3, 0.6, 1), Lifetime = NumberRange.new(2.2, 3.6),
		Speed = NumberRange.new(15, 60), SpreadAngle = Vector2.new(180, 180), Drag = 2,
		Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-60, 60),
	}, 12, 0.03)
	burst({
		Texture = PS.SPARK_TEXTURE, Color = cseq(PS.WHITE, GREEN_BRIGHT, GREEN), LightEmission = 1,
		Size = nseq(4, 2.4, 0), Transparency = nseq(0, 0.3, 1), Lifetime = NumberRange.new(2.8, 4.8),
		Speed = NumberRange.new(9, 36), SpreadAngle = Vector2.new(40, 40), Acceleration = Vector3.new(0, 18, 0), Drag = 1,
		Rotation = NumberRange.new(0, 360),
	}, 25, 0.2)
	burst({
		Texture = PS.SPARK_TEXTURE, Color = cseq(Color3.new(1, 1, 1), GREEN_BRIGHT, GREEN), LightEmission = 1,
		Size = nseq(4.5, 2.4, 0), Transparency = nseq(0, 0.3, 1), Lifetime = NumberRange.new(1.4, 2.5),
		Speed = NumberRange.new(45, 120), SpreadAngle = Vector2.new(180, 180), Acceleration = Vector3.new(0, -25, 0), Drag = 1,
	}, 30, 0.15)

	local shards = {}
	local function shard(props, vel, life, gravity, streak, width)
		local p = part(props)
		table.insert(shards, { part = p, vel = vel, life = life, age = 0, gravity = gravity, streak = streak, w = width, size0 = p.Size })
	end
	for i = 1, 48 do
		local a = (i / 48) * math.pi * 2 + rng:NextNumber(-0.08, 0.08)
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		shard({
			Name = "Streak", Size = Vector3.new(0.8, 0.8, 2), Color = (i % 3 == 0) and PS.WHITE or GREEN_BRIGHT,
			Position = ground + up * 0.6 + dir * 2,
		}, dir * rng:NextNumber(105, 195) + up * rng:NextNumber(0, 9), rng:NextNumber(0.9, 1.5), 0, true, 0.8)
	end
	local ember = { GREEN, GREEN_BRIGHT, PS.WHITE }
	for i = 1, 40 do
		local a = rng:NextNumber(0, math.pi * 2)
		local el = rng:NextNumber(0.35, 1.45)
		local dir = Vector3.new(math.cos(a) * math.cos(el), math.sin(el), math.sin(a) * math.cos(el))
		local s = rng:NextNumber(0.6, 1.6)
		shard({
			Name = "Ember", Shape = (i % 2 == 0) and Enum.PartType.Ball or Enum.PartType.Block, Size = Vector3.new(s, s, s),
			Color = ember[rng:NextInteger(1, #ember)], Position = pos,
		}, dir * rng:NextNumber(60, 165), rng:NextNumber(1.9, 3.4), 70, false, 0)
	end

	local simThread
	simThread = task.spawn(function()
		local last = os.clock()
		while #shards > 0 and not fx.dead do
			local now = os.clock()
			local dt = math.min(now - last, 0.05)
			last = now
			for i = #shards, 1, -1 do
				local sh = shards[i]
				sh.age += dt
				if sh.age >= sh.life or not sh.part.Parent then
					pcall(function() sh.part:Destroy() end)
					table.remove(shards, i)
				else
					sh.vel += Vector3.new(0, -sh.gravity * dt, 0)
					local p = sh.part.Position + sh.vel * dt
					local k = sh.age / sh.life
					if sh.streak then
						local speed = sh.vel.Magnitude
						local len = math.clamp(speed * 0.07, 0.5, 9) * (1 - k)
						local w = sh.w * (1 - k * 0.7)
						sh.part.Size = Vector3.new(w, w, math.max(len, 0.05))
						if speed > 0.01 then sh.part.CFrame = CFrame.lookAt(p, p + sh.vel) else sh.part.Position = p end
					else
						sh.part.Size = sh.size0 * (1 - k * 0.8)
						sh.part.Position = p
					end
					sh.part.Transparency = k * k
				end
			end
			RunService.Heartbeat:Wait()
		end
		fx:remove(simThread)
	end)
	if coroutine.status(simThread) == "suspended" then fx:add(simThread) end

	if not PS.post then
		PS.post = true
		fx:add(function() PS.post = false end)
		local cc = F.safe("ps cc", F.make, "ColorCorrectionEffect", {
			Name = "PortalPSCC", TintColor = Color3.fromRGB(140, 255, 185), Brightness = 0.3 * f, Contrast = 0.25 * f, Saturation = 0.4 * f,
		}, Lighting)
		if cc then
			fx:add(cc)
			F.play(fx, cc, 2.8, { TintColor = Color3.new(1, 1, 1), Brightness = 0, Contrast = 0, Saturation = 0 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		end
		local bloom = F.safe("ps bloom", F.make, "BloomEffect", { Name = "PortalPSBloom", Intensity = 2.5 * f, Size = 24, Threshold = 0.8 }, Lighting)
		if bloom then
			fx:add(bloom)
			F.play(fx, bloom, 3.0, { Intensity = 0 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		end
	end

	local pg = player:FindFirstChildOfClass("PlayerGui")
	if pg then
		local sg = F.safe("ps flash", F.make, "ScreenGui", { Name = "PortalPSFlash", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 1000 }, pg)
		if sg then
			fx:add(sg)
			local frame = F.make("Frame", {
				Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(200, 255, 222),
				BackgroundTransparency = 1 - 0.8 * f, BorderSizePixel = 0,
			}, sg)
			F.play(fx, frame, 1.8, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		end
	end

	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if hum and f > 0.2 then
		if PS.shakes == 0 then PS.shakeBase = hum.CameraOffset end
		PS.shakes += 1
		local live = true
		local function stopShake()
			if not live then return end
			live = false
			PS.shakes -= 1
			if PS.shakes <= 0 then
				PS.shakes = 0
				if hum.Parent then hum.CameraOffset = PS.shakeBase end
			end
		end
		fx:add(stopShake)
		local shakeThread
		shakeThread = task.spawn(function()
			local t0 = os.clock()
			while true do
				local k = (os.clock() - t0) / 1.6
				if k >= 1 or fx.dead or not hum.Parent then break end
				local amp = 2.4 * f * (1 - k) ^ 2
				hum.CameraOffset = PS.shakeBase + Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1), 0) * amp
				RunService.RenderStepped:Wait()
			end
			stopShake()
			fx:remove(shakeThread)
		end)
		if coroutine.status(shakeThread) == "suspended" then fx:add(shakeThread) end
	end

	fx:delay(8, function()
		globalBin:remove(fxHandle)
		fx:clean()
	end)
end

function F.psBomb(bin, folder, clone, startCF, restCF, ground, normal)
	local PS = F.PS
	local anchor = F.make("Part", {
		Name = "PSAnchor", Size = Vector3.one, Transparency = 1, Anchored = true,
		CanCollide = false, CanTouch = false, CanQuery = false, CFrame = restCF,
	}, folder)
	local glow = F.make("Part", {
		Name = "PSGlow", Shape = Enum.PartType.Ball, Size = Vector3.new(0.6, 0.6, 0.6), Color = GREEN_BRIGHT,
		Material = Enum.Material.Neon, Transparency = 0.7, Anchored = true, CanCollide = false,
		CanTouch = false, CanQuery = false, CastShadow = false,
	}, folder)
	local light = F.make("PointLight", { Color = GREEN, Brightness = 0, Range = 14 }, glow)
	local hl = F.safe("ps highlight", F.make, "Highlight", {
		Adornee = clone, FillColor = GREEN, OutlineColor = GREEN_BRIGHT, FillTransparency = 1, OutlineTransparency = 0.5,
	}, folder)

	local function pivot(cf)
		clone:PivotTo(cf)
		glow.Position = (cf * MUZZLE_OFFSET).Position
	end

	local startPos, startRot, restRot = startCF.Position, startCF.Rotation, restCF.Rotation
	local t0 = os.clock()
	while not bin.dead do
		local t = math.clamp((os.clock() - t0) / PS.FLIGHT_TIME, 0, 1)
		local pos = startPos:Lerp(restCF.Position, t) + Vector3.new(0, PS.FLIGHT_ARC * 4 * t * (1 - t), 0)
		pivot(CFrame.new(pos) * startRot:Lerp(restRot, t))
		if t >= 1 then break end
		RunService.Heartbeat:Wait()
	end

	local b0 = os.clock()
	while not bin.dead do
		local u = math.clamp((os.clock() - b0) / 0.2, 0, 1)
		pivot(restCF + Vector3.new(0, 0.7 * math.sin(math.pi * u), 0))
		if u >= 1 then break end
		RunService.Heartbeat:Wait()
	end

	local function beep(i)
		if bin.dead then return end
		F.psSound(PS.BEEP_SOUND, PS.BEEP_VOLUME, 0.9 + i * 0.14, anchor)
		glow.Transparency = 0.05
		glow.Size = Vector3.new(1.5, 1.5, 1.5)
		light.Brightness = 4
		if hl then hl.FillTransparency = 0.2 end
		F.play(bin, glow, 0.22, { Transparency = 0.7, Size = Vector3.new(0.6, 0.6, 0.6) })
		F.play(bin, light, 0.22, { Brightness = 0.3 })
		if hl then F.play(bin, hl, 0.22, { FillTransparency = 0.85 }) end
	end

	local fuseStart = os.clock()
	for i, t in ipairs(PS.BEEP_TIMES) do
		bin:delay(t, function() beep(i) end)
	end

	local rng = Random.new()
	while not bin.dead do
		local e = os.clock() - fuseStart
		if e >= PS.FUSE_TIME then break end
		if e > PS.FUSE_TIME - 0.45 then
			local j = Vector3.new(rng:NextNumber(-0.06, 0.06), rng:NextNumber(-0.06, 0.06), rng:NextNumber(-0.06, 0.06))
			pivot(restCF + j)
			glow.Transparency = 0.05 + 0.2 * rng:NextNumber()
			light.Brightness = 2 + 3 * rng:NextNumber()
			if hl then hl.FillTransparency = 0.5 * rng:NextNumber() end
		end
		RunService.Heartbeat:Wait()
	end
	if bin.dead then return end

	pcall(function() folder:Destroy() end)
	F.psExplode(ground, normal)
	task.wait(6)
end

function F.psRun(s)
	local PS = F.PS
	local tool = F.psEnsureHeld(s)
	if not tool or not F.alive(s) then
		F.cmdLog("ps: could not take the gun in hand")
		return
	end
	local model = tool:FindFirstChild("PortalDevice")
	local root = model and F.findMarked(model, "PortalRoot")
	if not root then
		F.cmdLog("ps: gun model not found")
		return
	end

	local bin = Bin.new()
	local handle = globalBin:add(function() bin:clean() end)
	local base, shoulder = s.baseC0, s.shoulder
	local function armC0(angle)
		return CFrame.new(base.Position) * CFrame.Angles(math.rad(angle), 0, 0) * base.Rotation
	end
	local function ready()
		return F.alive(s) and shoulder.Parent ~= nil and s.holding
	end
	local function swing(time, angle, style, dir)
		s.armTween = F.play(bin, shoulder, time, { C0 = armC0(angle) }, style, dir)
		task.wait(time)
		return ready()
	end
	local function abort()
		bin:clean()
		globalBin:remove(handle)
	end

	if not swing(0.25, 55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out) then return abort() end
	s.armTween = F.play(bin, shoulder, 0.1, { C0 = armC0(78) }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	task.wait(0.08)
	if not ready() then return abort() end

	local startCF = root.CFrame
	local dir = F.flatten(s.rootPart.CFrame.LookVector, Vector3.zAxis)
	local ground, normal = F.psLandingSpot(s, dir)
	local clone = F.psCloneGun(model)
	local folder = F.make("Folder", { Name = "PortalPSBomb" }, Workspace)
	clone.Parent = folder
	F.hideGunModel(model)

	local restPos = ground + normal * PS.REST_LIFT
	local restCF = CFrame.lookAt(restPos, restPos + dir) * CFrame.Angles(0, math.pi, 0) * CFrame.Angles(0, 0, math.rad(12))

	local bombBin = Bin.new()
	local bombHandle = globalBin:add(function() bombBin:clean() end)
	bombBin:add(folder)
	local bombThread
	bombThread = task.spawn(function()
		PS.armed += 1
		F.safe("ps bomb", F.psBomb, bombBin, folder, clone, startCF, restCF, ground, normal)
		PS.armed = math.max(PS.armed - 1, 0)
		bombBin:remove(bombThread)
		globalBin:remove(bombHandle)
		bombBin:clean()
	end)
	if coroutine.status(bombThread) == "suspended" then bombBin:add(bombThread) end

	task.wait(0.06)
	if ready() then
		s.armTween = F.play(bin, shoulder, 0.3, { C0 = base })
		task.wait(0.32)
	end
	toolEnabled = false
	F.removeToolInstances()
	F.cmdLog("gun thrown, type #give to get it back")
	abort()
end

commands.ps = function()
	local PS = F.PS
	if PS.busy then
		F.cmdLog("ps: already throwing")
		return
	end
	local s = current
	if not F.alive(s) then
		F.cmdLog("ps: no local character")
		return
	end
	if PS.armed > 0 then
		F.cmdLog("ps: previous gun is still armed")
		return
	end
	if not toolEnabled or #F.collectTools() == 0 then
		F.cmdLog("ps: no Portal gun, type #give first")
		return
	end
	PS.busy = true
	task.spawn(function()
		local ok, err = pcall(F.psRun, s)
		PS.busy = false
		if not ok then F.cmdLog("ps error: " .. tostring(err)) end
	end)
end

commands.give = function()
	toolEnabled = true
	local backpack = player:FindFirstChild("Backpack")
	if backpack then F.watchTools(backpack) end
	if player.Character then F.watchTools(player.Character) end
	F.ensureStarter()
	F.grantTool()
	F.cmdLog(#F.collectTools() > 0 and "gun given (kept after reset)" or "give failed: no backpack or template")
end

commands.take = function()
	toolEnabled = false
	F.cmdLog("gun removed, script stopped")
	F.shutdown()
end

function F.detach(only)
	if only and only ~= current then return end
	local s = current
	current = nil
	gen += 1
	if s then
		F.releaseGun(s)
		s.bin:clean()
	end
	F.applyGunVisibility()
end

function F.attach(character)
	F.detach()
	gen += 1
	local myGen = gen
	local function stale()
		return gen ~= myGen or player.Character ~= character or character.Parent == nil
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
	current = s

	local worn = character:FindFirstChild(TOOL_NAME)
	if F.isPortalTool(worn) then
		F.holdGun(s, worn)
	elseif pendingTool and pendingTool.Parent == character then
		F.holdGun(s, pendingTool)
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
if arrival and arrival.tool == false then toolEnabled = false end
toolTemplate = F.buildPortalTool()
if not toolTemplate then
	F.cmdLog("Portal gun build failed")
else
	local cacheParent = (typeof(script) == "Instance" and script) or nil
	local cache = F.make("Folder", { Name = "PortalGunCache" }, cacheParent)
	globalBin:add(cache)
	toolTemplate.Parent = cache
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
			if current then current.teleporting = false end
		end
	end)
end
F.cmdLog("ready. type #help in chat")
