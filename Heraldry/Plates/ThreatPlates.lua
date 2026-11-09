--[[ Plates\ThreatPlates.lua
  Adapter for Threat Plates (fields as in its Forever-capable develop branch, 13.3.x):
  the plate is nameplate.TPFrame, the name nameplate.TPFrame.visual.NameText. A hidden
  TPFrame (units Threat Plates hides) answers false, so no fallback icon appears.

  Not tested in game: Threat Plates is not installed here. ]]

local _, ns = ...
local L = ns.L
local IsSecret = ns.IsSecret

local adapter = {
    id = "ThreatPlates",
    label = L.ADAPTER_THREATPLATES,
}

function adapter.IsAvailable()
    return C_AddOns.IsAddOnLoaded("TidyPlates_ThreatPlates")
end

function adapter.GetName(_, nameplate)
    local frame = nameplate.TPFrame
    if not frame or frame:IsForbidden() then return end
    local shown = frame:IsShown()
    if IsSecret(shown) or not shown then return false end
    return frame.visual and frame.visual.NameText or false
end

ns.Plates:RegisterAdapter(adapter)
