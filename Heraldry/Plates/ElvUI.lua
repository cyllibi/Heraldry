--[[ Plates\ElvUI.lua
  Adapter for ElvUI nameplates (oUF based; fields as in ElvUI's Forever builds). ElvUI puts
  its unit frame on the nameplate as nameplate.unitFrame (told apart from Plater's by
  .blizzPlate) with the name in unitFrame.Name. While ElvUI's frame is hidden (style
  filters, hidden friendly players) the adapter answers false: ElvUI owns the plate, so
  no fallback icon appears.

  Not tested in game: ElvUI is not installed here. ]]

local _, ns = ...
local L = ns.L
local IsSecret = ns.IsSecret

local adapter = {
    id = "ElvUI",
    label = L.ADAPTER_ELVUI,
}

function adapter.IsAvailable()
    return C_AddOns.IsAddOnLoaded("ElvUI")
end

function adapter.GetName(_, nameplate)
    local unitFrame = nameplate.unitFrame
    if not (unitFrame and unitFrame.blizzPlate) or unitFrame:IsForbidden() then return end
    local visible = unitFrame:IsVisible()
    if IsSecret(visible) or not visible then return false end
    return unitFrame.Name or false
end

ns.Plates:RegisterAdapter(adapter)
