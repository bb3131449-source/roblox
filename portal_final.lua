-- portal_final.lua
-- Roblox portal system: teleports players from one anchored portal part to another.
-- Place this script inside a ServerScriptService or a part script, and make sure
-- there are parts named "PortalA" and "PortalB" in Workspace.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local PORTAL_COOLDOWN = 1.25
local PORTAL_OFFSET = Vector3.new(0, 3, 0)

local portalA = workspace:FindFirstChild("PortalA")
local portalB = workspace:FindFirstChild("PortalB")

if not portalA or not portalB then
    warn("PortalA and PortalB must both exist in Workspace before using portal_final.lua")
    return
end

local function getCharacterFromPart(part)
    if not part or not part.Parent then
        return nil
    end

    local model = part.Parent
    if model:IsA("Model") and model:FindFirstChildOfClass("Humanoid") then
        return model
    end

    local parent = part.Parent
    while parent do
        if parent:IsA("Model") and parent:FindFirstChildOfClass("Humanoid") then
            return parent
        end
        parent = parent.Parent
    end

    return nil
end

local function getRootPart(model)
    if not model then
        return nil
    end

    local humanoidRootPart = model:FindFirstChild("HumanoidRootPart")
    if humanoidRootPart and humanoidRootPart:IsA("BasePart") then
        return humanoidRootPart
    end

    return model:FindFirstChildWhichIsA("BasePart")
end

local function addPortalVisuals(portal)
    if portal:FindFirstChild("PortalGlow") then
        return
    end

    local glow = Instance.new("Part")
    glow.Name = "PortalGlow"
    glow.Parent = portal
    glow.Material = Enum.Material.Neon
    glow.Color = Color3.fromRGB(88, 201, 255)
    glow.Transparency = 0.35
    glow.CanCollide = false
    glow.Anchored = true
    glow.CanTouch = false
    glow.CanQuery = false
    glow.Size = Vector3.new(portal.Size.X * 1.05, portal.Size.Y * 1.05, portal.Size.Z * 1.05)
    glow.CFrame = portal.CFrame
    glow.Shape = Enum.PartType.Cylinder
    glow.Orientation = Vector3.new(0, 0, 90)

    local tweenInfo = TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
    local goal = { Rotation = glow.Rotation + Vector3.new(0, 360, 0) }
    local tween = TweenService:Create(glow, tweenInfo, goal)
    tween:Play()
end

local function teleportCharacter(character, destination)
    if not character then
        return false
    end

    local rootPart = getRootPart(character)
    if not rootPart then
        return false
    end

    rootPart.CFrame = destination.CFrame + PORTAL_OFFSET
    return true
end

local portalCooldowns = {}

local function canUsePortal(player, portal)
    local key = player.UserId .. ":" .. portal.Name
    local now = tick()
    local lastUse = portalCooldowns[key]

    if lastUse and (now - lastUse) < PORTAL_COOLDOWN then
        return false
    end

    portalCooldowns[key] = now
    return true
end

local function handlePortalTouch(portal, destinationPortal)
    return function(hit)
        if not hit then
            return
        end

        local character = getCharacterFromPart(hit)
        if not character then
            return
        end

        local player = Players:GetPlayerFromCharacter(character)
        if not player then
            return
        end

        if not canUsePortal(player, portal) then
            return
        end

        local destination = destinationPortal
        if destination then
            teleportCharacter(character, destination)
        end
    end
end

for _, portal in ipairs({ portalA, portalB }) do
    if not portal:IsA("BasePart") then
        continue
    end

    portal.Anchored = true
    portal.CanCollide = true
    portal.CanTouch = true
    portal.CanQuery = true
    portal.Material = Enum.Material.Neon
    portal.Color = Color3.fromRGB(142, 227, 255)
    portal.Transparency = 0.2
    addPortalVisuals(portal)
end

portalA.Touched:Connect(handlePortalTouch(portalA, portalB))
portalB.Touched:Connect(handlePortalTouch(portalB, portalA))

print("Portal system initialized. Use PortalA and PortalB in Workspace.")
