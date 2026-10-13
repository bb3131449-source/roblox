-- portal/sfx.lua
local M = ...
local F, C, S, X = M.F, M.C, M.S, M.X
local ContentProvider = game:GetService("ContentProvider")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")
local ENTER_SOUND_ID, EXIT_SOUND_ID, OPEN_SOUND_ID, SFX_VOLUME, SHOT_SOUND_ID = C.ENTER_SOUND_ID, C.EXIT_SOUND_ID, C.OPEN_SOUND_ID, C.SFX_VOLUME, C.SHOT_SOUND_ID

-- SFX
local SFX_CANDIDATES = {
	shot = { SHOT_SOUND_ID, "rbxasset://sounds/Rocket shot.wav", "rbxasset://sounds/swoosh.wav" },
	open = { OPEN_SOUND_ID, "rbxasset://sounds/electronicpingshort.wav", "rbxasset://sounds/switch.wav" },
	enter = { ENTER_SOUND_ID, "rbxasset://sounds/Rocket whoosh 01.wav", "rbxasset://sounds/swoosh.wav" },
	exit = { EXIT_SOUND_ID, "rbxasset://sounds/Rocket whoosh 01.wav", "rbxasset://sounds/swoosh.wav" },
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

task.spawn(function()
	for name, list in pairs(SFX_CANDIDATES) do
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

X.SFX_CANDIDATES = SFX_CANDIDATES
X.sfxReady = sfxReady
