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
  Forever's own constants in Camelot\Blizzard_NamePlateConstants.lua).

  With the Display option for it on, the icon is as tall as the name and health bar
  together and sits just outside the bar (left of it, or right of the level box when it
  shows, and past the raid marker or classification icon on the left when they show),
  like a crest. That needs the bar to be shown (not a names-only plate) and its
  height and the name's: the bar's own height when readable, else NamePlateSetupOptions'
  healthBarHeight, healthBarFontHeight and healthBarToNameAboveSpacing. Styles that put
  the name inside the bar use the bar's height alone.

  Blizzard's crowd-control and loss-of-control icons (AurasFrame, right of the bar) may
  overlap a right-side icon. They win: Heraldry's icon is a texture on the UnitFrame
  itself, and AurasFrame is a child frame a level up, so it always draws on top. Keep it
  that way (never raise the icon onto its own frame above the plate). ]]

local _, ns = ...
local L = ns.L
local IsSecret = ns.IsSecret

local adapter = {
    id = "Blizzard",
    label = L.ADAPTER_BLIZZARD,
}

local LEGACY_PLATE_WIDTH = 110   -- the old NamePlateDriverFrame's base nameplate width
local LEGACY_NAME_INSET = 4      -- and how far it inset the name per side
local NAME_SPACING = 2           -- NamePlateConstants.HEALTH_BAR_TO_NAME_ABOVE_SPACING, if the options lack it

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

-- A frame's width or height when it is a plain positive number, else nil.
local function ReadSize(region, method)
    if not (region and region[method]) then return nil end
    local value = region[method](region)
    if IsSecret(value) or type(value) ~= "number" or value <= 0 then return nil end
    return value
end

local function ReadWidth(region)
    return ReadSize(region, "GetWidth")
end

-- True only for a plain true (a secret or missing answer counts as no).
local function Plainly(region, method)
    if not (region and type(region[method]) == "function") then return false end
    local value = region[method](region)
    return not IsSecret(value) and value == true
end

local function Number(value)
    return type(value) == "number" and value > 0 and value or nil
end

-- The span hint for a tall icon beside the name and health bar, or nil when the plate
-- shows no bar (names only) or its heights can't be worked out.
function adapter.Span(unitFrame, span)
    local bar = unitFrame.HealthBarsContainer
    if not Plainly(bar, "IsShown") or Plainly(unitFrame, "IsShowOnlyName") then return nil end
    local options = type(NamePlateSetupOptions) == "table" and NamePlateSetupOptions or {}
    local barHeight = ReadSize(bar, "GetHeight") or Number(options.healthBarHeight)
    if not barHeight then return nil end
    local height = barHeight
    local styles = type(NamePlateConstants) == "table" and NamePlateConstants.NAME_ANCHOR_STYLES
    local inside = styles and options.unitNameAnchorStyle ~= nil
        and options.unitNameAnchorStyle == styles.InsideHealthBar
    if not inside then
        local nameHeight = Number(options.healthBarFontHeight)
        if not nameHeight and unitFrame.name then
            local _, size = unitFrame.name:GetFont()
            nameHeight = not IsSecret(size) and Number(size) or nil
        end
        if not nameHeight then return nil end
        height = barHeight + (Number(options.healthBarToNameAboveSpacing) or NAME_SPACING) + nameHeight
    end
    -- Left of the bar Blizzard draws the raid marker, and left of that the PvP or
    -- elite/rare classification icon (they keep their place when hidden): sit past the
    -- outermost one showing.
    local level, raid, class = unitFrame.PlayerLevelDiffFrame, unitFrame.RaidTargetFrame, unitFrame.ClassificationFrame
    span.left = Plainly(class, "IsShown") and class or Plainly(raid, "IsShown") and raid or bar
    span.right = Plainly(level, "IsShown") and level or bar
    span.height = height
    span.lift = (height - barHeight) / 2
    return span
end

local SPAN = {}

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
    HINTS.span = ns.profile.display.tallBlizzard and adapter.Span(unitFrame, SPAN) or nil
    return unitFrame.name, HINTS
end

ns.Plates:RegisterAdapter(adapter)
