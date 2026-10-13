-- portal/ui.lua
local M = ...
local F, C, S, X = M.F, M.C, M.S, M.X
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local player = M.player
local GREEN, GREEN_BRIGHT = C.GREEN, C.GREEN_BRIGHT
local globalBin = X.globalBin

-- UI
local BTN_BG, BTN_HOVER = Color3.fromRGB(52, 54, 60), Color3.fromRGB(66, 69, 76)
local BTN_TEXT, BTN_STROKE = Color3.fromRGB(226, 229, 234), Color3.fromRGB(110, 114, 122)
local FADE = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local PANEL_X, PANEL_Y = 14, 0.3 -- отступ слева (px) и высота центра панели (0..1 от экрана)

local gui = F.make("ScreenGui", { Name = "PortalGui", ResetOnSpawn = false }, player:WaitForChild("PlayerGui"))
globalBin:add(gui)

local panel = F.make("Frame", {
	Name = "PortalButtons", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, PANEL_X, PANEL_Y, 0),
	Size = UDim2.fromOffset(170, 80), BackgroundTransparency = 1, Visible = false,
}, gui)
F.make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, panel)

local hint = F.make("TextLabel", {
	Name = "Hint", AnchorPoint = Vector2.new(0, 0), Position = UDim2.new(0, PANEL_X, PANEL_Y, 48),
	Size = UDim2.fromOffset(170, 18), BackgroundTransparency = 1, Visible = false,
	TextColor3 = Color3.fromRGB(170, 175, 182), Font = Enum.Font.Gotham, TextSize = 12, Text = "",
}, gui)
local notice = F.make("TextLabel", {
	Name = "Notice", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.38, 0),
	Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1, TextTransparency = 1, TextWrapped = true,
	TextColor3 = Color3.fromRGB(170, 175, 182), Font = Enum.Font.GothamMedium, TextSize = 18, Text = "",
}, gui)

function F.notify(text, hold)
	S.noticeId += 1
	local id = S.noticeId
	if F.noticeTween then F.noticeTween:Cancel() end -- иначе старое затухание гасит новый текст
	notice.Text, notice.TextTransparency = text, 0
	task.delay(hold or 3, function()
		if id ~= S.noticeId or not notice.Parent then return end
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
	local active = entry.active
	TweenService:Create(entry.button, FADE, { BackgroundColor3 = entry.hover and BTN_HOVER or BTN_BG }):Play()
	TweenService:Create(entry.stroke, FADE, {
		Color = active and GREEN or BTN_STROKE,
		Transparency = active and 0.05 or (entry.hover and 0.3 or 0.55),
	}):Play()
end

function F.makeButton(index, name)
	local b = F.make("TextButton", {
		Name = name, LayoutOrder = index, Size = UDim2.new(1, 0, 0, 36),
		BackgroundColor3 = BTN_BG, BorderSizePixel = 0, AutoButtonColor = false,
		TextColor3 = BTN_TEXT, Font = Enum.Font.GothamMedium, TextSize = 13, Text = "",
	}, panel)
	F.make("UICorner", { CornerRadius = UDim.new(0, 8) }, b)
	local stroke = F.make("UIStroke", {
		Color = BTN_STROKE, Thickness = 1, Transparency = 0.55, ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, b)
	local entry = { button = b, stroke = stroke, hover = false, active = false }
	b.MouseEnter:Connect(function() entry.hover = true F.paint(entry) end)
	b.MouseLeave:Connect(function() entry.hover = false F.paint(entry) end)
	buttons[index] = entry
end

F.makeButton(1, "EntrancePortal")
F.makeButton(2, "ExitPortal")

function F.refreshUI()
	local both = S.slots[1] ~= nil and S.slots[2] ~= nil
	local placeLink = (S.slots[1] and S.slots[1].placeId) or (S.slots[2] and S.slots[2].placeId)
	buttons[1].button.Text = S.slots[1] and (both and "close portals" or "close entrance portal") or "entrance portal"
	buttons[2].button.Text = S.slots[2] and (both and "close portals" or "close exit portal") or "exit portal"
	if placeLink then
		buttons[1].button.Text, buttons[2].button.Text = "close place portal", "close place portal"
	end
	for i = 1, 2 do
		buttons[i].active = S.placement.slot == i
		F.paint(buttons[i])
	end
	hint.Text = S.placement.slot == 1 and "tap a surface: entrance"
		or S.placement.slot == 2 and "tap a surface: exit" or ""
end

local previewMarker = F.newPart(Workspace, "PortalPreview", Vector3.new(0.5, 0.5, 0.5), CFrame.new(), GREEN_BRIGHT, Enum.Material.Neon, Enum.PartType.Ball)
previewMarker.Anchored, previewMarker.Transparency = true, 1
globalBin:add(previewMarker)

function F.resetPlacement()
	S.placement.slot = nil
	F.refreshUI()
end

function F.gunHeld()
	return S.current ~= nil and S.current.holding == true
end

function F.applyGunVisibility()
	local held = F.gunHeld()
	panel.Visible, hint.Visible = held, held
	if not held and S.placement.slot then F.resetPlacement() end
end

F.refreshUI()

X.BTN_BG = BTN_BG
X.BTN_HOVER = BTN_HOVER
X.BTN_TEXT = BTN_TEXT
X.BTN_STROKE = BTN_STROKE
X.FADE = FADE
X.PANEL_X = PANEL_X
X.PANEL_Y = PANEL_Y
X.gui = gui
X.panel = panel
X.hint = hint
X.notice = notice
X.buttons = buttons
X.previewMarker = previewMarker
