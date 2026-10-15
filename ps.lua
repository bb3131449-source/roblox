return function(ctx)
local F, Bin, globalBin, commands, player = ctx.F, ctx.Bin, ctx.globalBin, ctx.commands, ctx.player
local Debris, RunService, SoundService, Workspace = ctx.Debris, ctx.RunService, ctx.SoundService, ctx.Workspace
local GREEN, GREEN_BRIGHT, MUZZLE_OFFSET, SFX_VOLUME = ctx.GREEN, ctx.GREEN_BRIGHT, ctx.MUZZLE_OFFSET, ctx.SFX_VOLUME
local Players = game:GetService("Players")

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

	FLING_RADIUS = 60,
	FLING_DURATION = 2,
	FLING_MAX_TARGETS = 10,
	blacklist = {},
}

Players.PlayerAdded:Connect(function(plr)
	plr.CharacterAdded:Connect(function()
		F.PS.blacklist[plr] = nil
	end)
end)
for _, plr in ipairs(Players:GetPlayers()) do
	plr.CharacterAdded:Connect(function()
		F.PS.blacklist[plr] = nil
	end)
end

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

function F.psHasCollision(char)
	if not char or not char.Parent then return false end
	for _, p in ipairs(char:GetDescendants()) do
		if p:IsA("BasePart") and p.CanCollide then return true end
	end
	return false
end

function F.psFlingOne(plr)
	local s = ctx.getCurrent()
	if not F.alive(s) then return false, "self lost" end
	local myChar, myRoot = s.character, s.rootPart

	local char = plr.Character
	if not char or not char.Parent then return false, "left" end
	local tr = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Head")
	if not tr then return false, "no target root" end
	local thum = char:FindFirstChildOfClass("Humanoid")

	local startPos = tr.Position
	local duration = F.PS.FLING_DURATION
	local t0 = os.clock()
	local a = 0

	repeat
		if not myRoot.Parent or not tr.Parent then break end
		if not F.alive(s) then break end
		if F.PS.blacklist[plr] then break end

		a += 100
		local vel = tr.AssemblyLinearVelocity
		local off = thum and thum.MoveDirection * (vel.Magnitude / 1.25) or Vector3.zero
		local up = CFrame.new(tr.Position) * (CFrame.new(0, 1.5, 0) + off) * CFrame.Angles(math.rad(a), 0, 0)
		local dn = CFrame.new(tr.Position) * (CFrame.new(0, -1.5, 0) + off) * CFrame.Angles(math.rad(a), 0, 0)

		for _, cf in ipairs({ up, dn }) do
			myRoot.CFrame = cf
			pcall(function() myChar:PivotTo(cf) end)
			myRoot.AssemblyLinearVelocity = Vector3.new(9e7, 9e8, 9e7)
			myRoot.AssemblyAngularVelocity = Vector3.new(9e8, 9e8, 9e8)
			task.wait()
		end
	until os.clock() - t0 > duration

	task.wait(0.25)
	if not tr.Parent then return true, "gone" end
	local moved = (tr.Position - startPos).Magnitude
	if moved > 15 then return true, "flung" end
	return false, ("resisted %.1f"):format(moved)
end

function F.psFlingPlayers(pos, radius)
	local PS = F.PS
	local s = ctx.getCurrent()
	if not F.alive(s) then return end
	local myChar, myRoot, myHum = s.character, s.rootPart, s.humanoid
	if not myRoot or not myHum then return end

	local targets = {}
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= player and not PS.blacklist[plr] then
			local char = plr.Character
			if char and char.Parent then
				local hrp = char:FindFirstChild("HumanoidRootPart")
				if hrp and (hrp.Position - pos).Magnitude <= radius then
					if F.psHasCollision(char) then
						table.insert(targets, plr)
					else
						PS.blacklist[plr] = true
						F.cmdLog("ps " .. plr.Name .. ": no collision")
					end
				end
			end
		end
	end

	if #targets == 0 then
		F.cmdLog("ps: no valid targets")
		return
	end

	local state = {
		cam = Workspace.CurrentCamera,
		sType = nil, sSubj = nil, sCF = nil,
		prevFallen = Workspace.FallenPartsDestroyHeight,
		hidden = {},
		savedPos = myRoot.CFrame,
		seatWas = true,
		stab = nil,
		stabRot = nil,
		cleaned = false,
		flung = 0,
		blocked = 0,
	}

	local function restoreAll()
		if state.cleaned then return end
		state.cleaned = true

		for inst, t in pairs(state.hidden) do
			if inst and inst.Parent then
				pcall(function() inst.Transparency = t end)
			end
		end

		if state.cam then
			pcall(function()
				state.cam.CameraType = state.sType or Enum.CameraType.Custom
			end)
			if state.sSubj then
				pcall(function() state.cam.CameraSubject = state.sSubj end)
			end
			if state.sCF then
				pcall(function() state.cam.CFrame = state.sCF end)
			end
		end

		if myHum and myHum.Parent then
			pcall(function()
				myHum:SetStateEnabled(Enum.HumanoidStateType.Seated, state.seatWas)
			end)
		end

		pcall(function()
			Workspace.FallenPartsDestroyHeight = state.prevFallen
		end)

		if state.stab then pcall(function() state.stab:Destroy() end) end
		if state.stabRot then pcall(function() state.stabRot:Destroy() end) end

		F.cmdLog(("ps: flung %d, blacklisted %d"):format(state.flung or 0, state.blocked or 0))
	end

	for _, d in ipairs(myChar:GetDescendants()) do
		if d:IsA("BasePart") or d:IsA("Decal") then
			state.hidden[d] = d.Transparency
			d.Transparency = 1
		end
	end

	if state.cam then
		state.sType, state.sSubj, state.sCF = state.cam.CameraType, state.cam.CameraSubject, state.cam.CFrame
		state.cam.CameraType = Enum.CameraType.Scriptable
		state.cam.CFrame = state.sCF
	end

	pcall(function()
		Workspace.FallenPartsDestroyHeight = -9e9
	end)

	local stab = Instance.new("BodyVelocity")
	stab.Velocity = Vector3.zero
	stab.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
	stab.P = 1e6
	pcall(function() stab.Parent = myRoot end)
	state.stab = stab

	local stabRot = Instance.new("BodyAngularVelocity")
	stabRot.AngularVelocity = Vector3.zero
	stabRot.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
	stabRot.P = 1e6
	pcall(function() stabRot.Parent = myRoot end)
	state.stabRot = stabRot

	pcall(function()
		state.seatWas = myHum:GetStateEnabled(Enum.HumanoidStateType.Seated)
	end)
	pcall(function()
		myHum:SetStateEnabled(Enum.HumanoidStateType.Seated, false)
	end)

	local deadConn
	deadConn = myHum.Died:Connect(function()
		restoreAll()
		if deadConn then deadConn:Disconnect() end
	end)

	local charGoneConn
	charGoneConn = myChar.AncestryChanged:Connect(function(_, parent)
		if not parent then
			restoreAll()
			if charGoneConn then charGoneConn:Disconnect() end
		end
	end)

	local MAX = PS.FLING_MAX_TARGETS
	for _, plr in ipairs(targets) do
		if state.flung + state.blocked >= MAX then break end
		if state.cleaned then break end

		local ok, res = pcall(F.psFlingOne, plr)
		if ok and res == true then
			state.flung += 1
			F.cmdLog("ps " .. plr.Name .. ": flung")
		else
			PS.blacklist[plr] = true
			state.blocked += 1
			F.cmdLog("ps " .. plr.Name .. ": blocked (" .. tostring(res) .. ")")
		end
	end

	if myRoot.Parent then
		myRoot.AssemblyLinearVelocity = Vector3.zero
		myRoot.AssemblyAngularVelocity = Vector3.zero
	end

	local t1 = os.clock()
	while not state.cleaned do
		if not myRoot.Parent then break end
		myRoot.CFrame = state.savedPos
		myRoot.AssemblyLinearVelocity = Vector3.zero
		myRoot.AssemblyAngularVelocity = Vector3.zero
		pcall(function() myChar:PivotTo(state.savedPos) end)
		if (myRoot.Position - state.savedPos.Position).Magnitude < 25 then break end
		if os.clock() - t1 > 3 then break end
		task.wait()
	end

	if myRoot.Parent then
		myRoot.AssemblyLinearVelocity = Vector3.zero
		myRoot.AssemblyAngularVelocity = Vector3.zero
	end
	task.wait()

	if deadConn then deadConn:Disconnect() end
	if charGoneConn then charGoneConn:Disconnect() end

	restoreAll()
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

	task.spawn(function()
		F.safe("ps fling", F.psFlingPlayers, pos, PS.FLING_RADIUS)
	end)

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
		pcall(function()
			clone:PivotTo(cf)
			glow.Position = (cf * MUZZLE_OFFSET).Position
		end)
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
	ctx.setToolEnabled(false)
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
	local s = ctx.getCurrent()
	if not F.alive(s) then
		F.cmdLog("ps: no local character")
		return
	end
	if PS.armed > 0 then
		F.cmdLog("ps: previous gun is still armed")
		return
	end
	if not ctx.getToolEnabled() or #F.collectTools() == 0 then
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

commands.psunblock = function()
	local PS = F.PS
	local n = 0
	for plr in pairs(PS.blacklist) do
		PS.blacklist[plr] = nil
		n += 1
	end
	F.cmdLog(("ps: unblocked %d"):format(n))
end
end