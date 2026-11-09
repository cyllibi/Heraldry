--[[ Plates\Blizzard.lua
  Adapter for Blizzard's own nameplates. Registered after the add-on adapters.

  The name is nameplate.UnitFrame.name. Nameplate add-ons that draw their own plates
  (Plater, Platynator, ElvUI, ...) hide Blizzard's UnitFrame or move it under a hidden
  frame, while its name still reports itself shown; so the plate is only claimed while
  the UnitFrame really is on screen.

  Blizzard anchors the name across the health bar (a fixed-width, usually centre-
  justified box). Widths read inside the nameplate are secret on this client, so the box
  is worked out from plain numbers instead: Blizzard's default plate width, scaled by the
  nameplateHorizontalScale setting, less the 4 pixels Blizzard insets the name on each
  side. ]]

local _, ns = ...
local L = ns.L
local IsSecret = ns.IsSecret

local adapter = {
    id = "Blizzard",
    label = L.ADAPTER_BLIZZARD,
}

local DEFAULT_PLATE_WIDTH = 110  -- NamePlateDriverFrame's base nameplate width
local NAME_INSET = 4             -- Blizzard_NamePlateUnitFrame insets the name this much per side

local HINTS = {}

function adapter.IsAvailable()
    return true
end

local function Displayed(unitFrame, nameplate)
    if unitFrame:GetParent() ~= nameplate then return false end
    local visible, alpha = unitFrame:IsVisible(), unitFrame:GetAlpha()
    if IsSecret(visible) or IsSecret(alpha) then return false end
    return visible and alpha > 0
end

-- The name box width, from settings rather than measuring the plate.
local function NameBoxWidth()
    local scale = tonumber(C_CVar.GetCVar("nameplateHorizontalScale")) or 1
    return DEFAULT_PLATE_WIDTH * scale - 2 * NAME_INSET
end

function adapter.GetName(_, nameplate)
    local unitFrame = nameplate.UnitFrame
    if not unitFrame or unitFrame:IsForbidden() or not Displayed(unitFrame, nameplate) then return end
    HINTS.boxWidth = NameBoxWidth()
    return unitFrame.name, HINTS
end

ns.Plates:RegisterAdapter(adapter)
