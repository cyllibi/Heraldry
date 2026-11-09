--[[ Plates\Plater.lua
  Adapter for Plater Nameplates (fields as in Plater's Forever builds, v663). Plater puts
  its unit frame on the nameplate as nameplate.unitFrame (with .PlateFrame) and keeps the
  FontString showing the name in nameplate.CurrentUnitNameString: the name inside the
  health bar, or ActorNameSpecial, an auto-sized name when the plate shows no bar
  (friendly players, name-only NPCs). A plate with Plater's frame is Plater's: while that
  frame is hidden (friendly players hidden in cities, filters) the adapter answers false,
  so no fallback icon appears; Blizzard's adapter still takes the plate if Plater left it
  to Blizzard. The name box width comes from Plater's profile (per actor type, the health
  bar width), not from measuring the plate.

  Not tested in game: Plater is not installed here. ]]

local _, ns = ...
local L = ns.L
local IsSecret = ns.IsSecret

local adapter = {
    id = "Plater",
    label = L.ADAPTER_PLATER,
}

local BAR_HINTS = {}
local SPECIAL_HINTS = { tight = true }

-- Plater.db.profile.plate_config[actorType].health = { width, height }.
local function BarWidth(unitFrame)
    local profile = Plater.db and Plater.db.profile
    local configs = profile and profile.plate_config
    local config = type(configs) == "table" and configs[unitFrame.ActorType]
    local width = type(config) == "table" and type(config.health) == "table" and config.health[1]
    if type(width) == "number" and not IsSecret(width) and width > 0 then return width end
end

function adapter.IsAvailable()
    return C_AddOns.IsAddOnLoaded("Plater") and type(Plater) == "table"
end

function adapter.GetName(_, nameplate)
    local unitFrame = nameplate.unitFrame
    if not (unitFrame and unitFrame.PlateFrame) or unitFrame:IsForbidden() then return end
    local visible = unitFrame:IsVisible()
    if IsSecret(visible) or not visible then return false end
    local name = nameplate.CurrentUnitNameString
    if not name then return false end
    if name == nameplate.ActorNameSpecial then return name, SPECIAL_HINTS end
    BAR_HINTS.boxWidth = BarWidth(unitFrame)
    return name, BAR_HINTS
end

-- Plater rewrites names and switches between its two name strings in these.
function adapter.Enable(plates)
    local function MarkPlate(plateFrame)
        local unit = type(plateFrame) == "table" and plateFrame.namePlateUnitToken
        if unit then plates.MarkUnit(unit) end
    end
    for _, name in ipairs({ "UpdatePlateText", "UpdateUnitName" }) do
        if type(Plater[name]) == "function" then
            hooksecurefunc(Plater, name, MarkPlate)
        end
    end
end

ns.Plates:RegisterAdapter(adapter)
