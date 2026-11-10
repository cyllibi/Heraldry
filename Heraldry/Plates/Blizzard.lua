--[[ Plates\Blizzard.lua
  Adapter for Blizzard's own nameplates. Registered after the add-on adapters.

  The name is nameplate.UnitFrame.name. Nameplate add-ons that draw their own plates
  (Plater, Platynator, ElvUI, ...) hide Blizzard's UnitFrame or move it under a hidden
  frame, while its name still reports itself shown; so the plate is only claimed while
  the UnitFrame really is on screen.

  Blizzard anchors the name across the health bar (a fixed-width box; long names are cut
  with an ellipsis), so the icon needs the box's width to clear a cut name. In order:
    1. the name's own width, when the game lets add-ons read it (not secret)
    2. the health bar area's width (HealthBarsContainer), likewise
    3. Forever's own layout numbers: NamePlateConstants' plate width (190 on Forever, 230
       on mainline, 152 for the Classic style) times the nameplate size's scale
       (NamePlateSetupOptions), less its 12 px x scale content inset per side. Forever
       centres names above the bar and puts the level box outside it, so this is the name
       box; where a level box shrinks the bar it errs wide, which only moves the icon a
       little further out for long names
    4. the old nameplate layout (110 wide, nameplateHorizontalScale), for clients without
       those tables
  Forever's layout is in Blizzard_NamePlates (NamePlateUnitFrameMixin:UpdateAnchors, with
  Forever's own constants in Camelot\Blizzard_NamePlateConstants.lua). ]]

local _, ns = ...
local L = ns.L
local IsSecret = ns.IsSecret

local adapter = {
    id = "Blizzard",
    label = L.ADAPTER_BLIZZARD,
}

local LEGACY_PLATE_WIDTH = 110   -- the old NamePlateDriverFrame's base nameplate width
local LEGACY_NAME_INSET = 4      -- and how far it inset the name per side

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

-- A frame's width when it is a plain positive number, else nil.
local function ReadWidth(region)
    if not (region and region.GetWidth) then return nil end
    local width = region:GetWidth()
    if IsSecret(width) or type(width) ~= "number" or width <= 0 then return nil end
    return width
end

-- The name box width from Forever's own layout tables, or the old layout's numbers.
local function LayoutBoxWidth()
    local constants, options = NamePlateConstants, NamePlateSetupOptions
    if type(constants) == "table" and type(options) == "table" then
        local base = options.useClassicHealthBar and constants.CLASSIC_NAME_PLATE_WIDTH or constants.NAME_PLATE_WIDTH
        local scale, inset = options.horizontalScale, options.insetWidth
        if type(base) == "number" and type(scale) == "number" and type(inset) == "number" then
            return base * scale - 2 * inset
        end
    end
    local scale = tonumber(C_CVar.GetCVar("nameplateHorizontalScale")) or 1
    return LEGACY_PLATE_WIDTH * scale - 2 * LEGACY_NAME_INSET
end

function adapter.NameBoxWidth(unitFrame)
    return ReadWidth(unitFrame.name) or ReadWidth(unitFrame.HealthBarsContainer) or LayoutBoxWidth()
end

function adapter.GetName(_, nameplate)
    local unitFrame = nameplate.UnitFrame
    if not unitFrame or unitFrame:IsForbidden() or not Displayed(unitFrame, nameplate) then return end
    HINTS.boxWidth = adapter.NameBoxWidth(unitFrame)
    return unitFrame.name, HINTS
end

ns.Plates:RegisterAdapter(adapter)
