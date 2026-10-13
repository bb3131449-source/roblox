-- portal/portal.lua
local M = ...
local F, C, S, X = M.F, M.C, M.S, M.X
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local BOLT_TIME, BURST_LIFETIME, BURST_PARTICLES, BURST_RING_TIME, CLOSE_TIME, GREEN = C.BOLT_TIME, C.BURST_LIFETIME, C.BURST_PARTICLES, C.BURST_RING_TIME, C.CLOSE_TIME, C.GREEN
local GREEN_BRIGHT, MIN_SCALE, OPEN_TIME, PORTAL_BASE_COLOR, PORTAL_COLOR, PORTAL_DIAMETER = C.GREEN_BRIGHT, C.MIN_SCALE, C.OPEN_TIME, C.PORTAL_BASE_COLOR, C.PORTAL_COLOR, C.PORTAL_DIAMETER
local PORTAL_FIX_ROT, PORTAL_OFFSET, PORTAL_SMOOTH_DISC, PORTAL_SPIN, PORTAL_THICKNESS, STRETCH_C = C.PORTAL_FIX_ROT, C.PORTAL_OFFSET, C.PORTAL_SMOOTH_DISC, C.PORTAL_SPIN, C.PORTAL_THICKNESS, C.STRETCH_C
local STRETCH_K, STRETCH_LAYERS, STRETCH_MAX = C.STRETCH_K, C.STRETCH_LAYERS, C.STRETCH_MAX
local Bin = X.Bin

-- PORTAL
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
	if not S.portalTemplate then return false end
	local ok, err = pcall(function()
		local cloned = S.portalTemplate:Clone()
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
	if not S.portalTemplate then return false end
	local texture
	for _, p in ipairs(F.collectParts(S.portalTemplate)) do
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
	local collapsed = flat and portal.collapsed -- скрытые слои уже свёрнуты, повторно их не трогаем
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

function F.driveStretch(portal, target)
	if portal and portal.stretch and not portal.bin.dead then portal.stretch.target = target end
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
	F.burstSparks(portal)
	F.growRing(portal, PORTAL_DIAMETER * 0.4, PORTAL_DIAMETER * 1.8, 0, GREEN_BRIGHT)
	F.growRing(portal, PORTAL_DIAMETER * 0.3, PORTAL_DIAMETER * 1.3, 0.12, GREEN)
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
	F.animatePortal(portal, 0, CLOSE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	portal.bin:delay(CLOSE_TIME + 0.1, function() portal.bin:clean() end)
end

function F.linkPortals()
	local a, b = S.slots[1], S.slots[2]
	if a then a.paired = nil end
	if b then b.paired = nil end
	if a and b and not a.placeId and not b.placeId then a.paired, b.paired = b, a end
end

function F.closeSlot(i, instant)
	local p = S.slots[i]
	if not p then return end
	S.slots[i] = nil
	p.paired = nil
	F.closePortal(p, instant)
	F.linkPortals()
	S.portalEpoch += 1
	F.refreshUI()
end

function F.destroyAllPortals(instant)
	F.closeSlot(1, instant)
	F.closeSlot(2, instant)
	S.portalEpoch += 1
end

