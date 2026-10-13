-- portal/gun.lua
local M = ...
local F, C, S, X = M.F, M.C, M.S, M.X
local Workspace = game:GetService("Workspace")
local BOLT_SIZE, BOLT_TIME, FLASH_RANGE, GREEN, GREEN_BRIGHT, HOLD_TIME = C.BOLT_SIZE, C.BOLT_TIME, C.FLASH_RANGE, C.GREEN, C.GREEN_BRIGHT, C.HOLD_TIME
local LIGHT_MAX, LIGHT_MIN, LIGHT_RANGE, LOWER_TIME, MUZZLE_OFFSET, RAISE_ANGLE = C.LIGHT_MAX, C.LIGHT_MIN, C.LIGHT_RANGE, C.LOWER_TIME, C.MUZZLE_OFFSET, C.RAISE_ANGLE
local RAISE_TIME, RECOIL_ANGLE = C.RAISE_TIME, C.RECOIL_ANGLE

-- GUN
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
	if not S.gunTemplate then return end
	F.safe("gun template", function()
		local cloned = S.gunTemplate:Clone()
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
	local s = S.current
	if not F.alive(s) or not s.holding or not s.lens then return end
	local bin = s.gunBin
	if not bin or bin.dead then return end
	s.shotId += 1
	local id = s.shotId
	local base, shoulder, light = s.baseC0, s.shoulder, s.light
	local function armC0(angle)
		return CFrame.new(base.Position) * CFrame.Angles(math.rad(angle), 0, 0) * base.Rotation
	end
	local function armActive() return F.alive(s) and s.shotId == id end

	F.playSfx("shot")
	if s.armTween then s.armTween:Cancel() end
	s.armTween = F.play(bin, shoulder, RAISE_TIME, { C0 = armC0(RAISE_ANGLE) })
	F.play(bin, light, 0.08, { Brightness = LIGHT_MAX, Range = FLASH_RANGE })
	F.spawnBolt(s, targetPos, color)

	bin:delay(RAISE_TIME + 0.03, function()
		if armActive() then s.armTween = F.play(bin, shoulder, 0.06, { C0 = armC0(RAISE_ANGLE + RECOIL_ANGLE) }) end
	end)
	bin:delay(0.15, function()
		if F.alive(s) then F.play(bin, light, 0.2, { Brightness = LIGHT_MIN, Range = LIGHT_RANGE }) end
	end)
	bin:delay(HOLD_TIME, function()
		if armActive() then s.armTween = F.play(bin, shoulder, LOWER_TIME, { C0 = base }) end
	end)
end

function F.registerPortal(cf, slot, opts)
	local placeId = opts and opts.placeId or nil
	local otherSlot = slot == 1 and 2 or 1
	if S.slots[otherSlot] and (placeId or S.slots[otherSlot].placeId) then F.closeSlot(otherSlot) end
	F.closeSlot(slot)
	local portal = F.buildPortal(cf)
	if not portal then return nil end
	portal.placeId = placeId
	S.slots[slot] = portal
	F.linkPortals()
	F.fireVisual(cf.Position, GREEN_BRIGHT)
	F.refreshUI()
	return portal
end

