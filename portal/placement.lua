-- portal/placement.lua
local M = ...
local F, C, S, X = M.F, M.C, M.S, M.X
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local buttons = X.buttons
local globalBin = X.globalBin
local previewMarker = X.previewMarker

-- PLACEMENT
function F.placePortalAt(hit)
	local slot = S.placement.slot
	if not hit or not slot then return end
	if not F.registerPortal(F.surfaceFrame(hit), slot) then return end
	S.placement.slot = nil
	F.refreshUI()
end

function F.onButton(i)
	if not F.gunHeld() or S.placeBusy then return end
	local placeLink = (S.slots[1] and S.slots[1].placeId) or (S.slots[2] and S.slots[2].placeId)
	if placeLink or (S.slots[1] and S.slots[2]) then
		F.destroyAllPortals()
		F.resetPlacement()
	elseif S.slots[i] then
		F.closeSlot(i)
		F.resetPlacement()
	else
		S.placement.slot = S.placement.slot ~= i and i or nil
		F.refreshUI()
	end
end

for i = 1, 2 do
	globalBin:add(buttons[i].button.Activated:Connect(function() F.onButton(i) end))
end

globalBin:add(UserInputService.InputBegan:Connect(function(input, gpe)
	if gpe or S.placeBusy or not S.placement.slot or not F.gunHeld() then return end
	if input.UserInputType ~= Enum.UserInputType.Touch and input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
	F.placePortalAt(F.castFromScreen())
end))

globalBin:add(RunService.RenderStepped:Connect(function()
	if not S.placement.slot or not F.gunHeld() then
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

