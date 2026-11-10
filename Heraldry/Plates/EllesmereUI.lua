--[[ Plates\EllesmereUI.lua
  Adapter for EllesmereUI Nameplates (read against v9.8). EUI publishes its namespace as
  the global EllesmereNameplates_NS:
    plates[unit]          enemy plates; .name has a fixed width (the bar width x the Name
                          Width setting), justified by EUI's name slot (centred above the
                          bar by default), cut with an ellipsis or wrapped to two lines
    friendlyPlates[unit]  friendly full plates (health bar mode); .name is auto-sized
    pendingUnits[unit]    every friendly unit; in name-only mode EUI restyles Blizzard's
                          UnitFrame.name, collapsed to one centre point with no width, and
                          may add the guild as a second line
  Plates move between these tables without a new NAME_PLATE_UNIT_ADDED (duels, PvP
  flagging), so the plate is looked up again on every update.

  Beside the name EUI can draw target arrows (friendly full plates: at the name's edges;
  enemy plates: beside the health bar) and a raid marker (enemy plates: left of the name
  box); their widths are passed to Plates, which moves the icon past them only where they
  would overlap. In follower dungeons and delves EUI leaves friendly plates to Blizzard,
  and so does this adapter.

  A unit in one of EUI's tables is EUI's even while it shows no name (a friendly plate not
  built yet, a hidden one): the adapter then answers false, so the generic fallback never
  draws over it.

  EUI builds friendly plates after its own events (TryAddFriendlyPlate), possibly after
  Heraldry's update ran, and rebuilds plates when its settings change; Enable hooks those
  entry points. They are EUI internals that may be renamed, so each hook is optional. ]]

local _, ns = ...
local L = ns.L
local IsSecret = ns.IsSecret

local adapter = {
    id = "EllesmereUI",
    label = L.ADAPTER_EUI,
}

local FOLLOWER_DIFFICULTY = 208      -- delves; EUI treats them like follower dungeons
local ARROW_GAP = 2                  -- EUI's own spacing between name and target arrow
local RAID_MARKER_GAP = 3            -- EUI's own spacing between raid marker and name
local MIN_NAME_WIDTH = 20            -- EUI's floor for the enemy name box
local DEFAULT_MARKER_SIZE = 14       -- EUI's default nameRaidMarkerSize
local DEFAULT_ARROW_WIDTH = 16       -- EUI's "simple" target arrow
local CORNER_SLOTS = { textSlotBottomLeft = true, textSlotBottomRight = true, textSlotTopLeft = true,
    textSlotTopRight = true }

local FULL_PLATE_HINTS = { tight = true }
local NAME_ONLY_HINTS = { tight = true }
local ENEMY_HINTS = {}

local followerInstance = false

local function EUI()
    return EllesmereNameplates_NS
end

-- EUI's profile holds plain numbers; read instead of measuring inside the plate tree.
local function Profile()
    local db = EUI().db
    return db and db.profile
end

local function PlainNumber(value)
    if type(value) == "number" and not IsSecret(value) then return value end
end

local function Shown(region)
    if not region then return false end
    local shown = region:IsShown()
    return not IsSecret(shown) and shown
end

-- Mirrors EUI's own IsInFollowerDungeon, including its guard: the follower-dungeon API
-- is not on every client build.
local function UpdateInstance()
    local _, _, difficultyID = GetInstanceInfo()
    local isFollower = C_LFGInfo and C_LFGInfo.IsInLFGFollowerDungeon and C_LFGInfo.IsInLFGFollowerDungeon()
    followerInstance = difficultyID == FOLLOWER_DIFFICULTY or isFollower == true
end

function adapter.IsAvailable()
    local eui = EUI()
    return type(eui) == "table" and type(eui.plates) == "table" and type(eui.friendlyPlates) == "table"
end

-- EUI sizes enemy target arrows from the arrow style's width x targetArrowScale.
local function EnemyArrowWidth(eui, profile)
    local style = type(eui.ResolveTargetArrowStyle) == "function" and eui.ResolveTargetArrowStyle(profile)
    local width = style and PlainNumber(style.w) or DEFAULT_ARROW_WIDTH
    local scale = profile and PlainNumber(profile.targetArrowScale) or 1
    return math.floor(width * scale + 0.5)
end

-- EUI's enemy debuff row in its default "top" slot sits on the name when the name is EUI's
-- top text (also the default), centred and growing upwards. An icon placed above the name
-- goes one row higher: EUI's debuff icon size plus its debuff Y offset. EUI keeps its
-- aura frames private, so this is a fixed lift, not the row's live height: the icon sits
-- in the same place with or without debuffs, and a second row of debuffs is still
-- covered. Nil when the row isn't above the name.
local DEFAULT_DEBUFF_SIZE, DEFAULT_DEBUFF_OFFSET = 26, 2
local function TopLift(eui, profile, slot)
    if slot ~= "textSlotTop" or (profile and profile.debuffSlot or "top") ~= "top" then return nil end
    local size = type(eui.GetDebuffIconSize) == "function" and PlainNumber(eui.GetDebuffIconSize())
        or profile and PlainNumber(profile.debuffIconSize) or DEFAULT_DEBUFF_SIZE
    local offset = type(eui.GetDebuffYOffset) == "function" and PlainNumber(eui.GetDebuffYOffset())
        or profile and PlainNumber(profile.debuffYOffset) or DEFAULT_DEBUFF_OFFSET
    -- Plus the slot's own nudge, when the player moved EUI's debuff row up or down.
    local nudge = 0
    if type(eui.GetAuraSlotOffsets) == "function" then
        local _, y = eui.GetAuraSlotOffsets("debuffSlot")
        nudge = PlainNumber(y) or 0
    end
    return size + offset + nudge
end

local function EnemyHints(eui, plate, profile)
    wipe(ENEMY_HINTS)
    local slot = type(eui.FindNameSlot) == "function" and eui.FindNameSlot()
    ENEMY_HINTS.fontSize = profile and slot and PlainNumber(profile[slot .. "Size"])
    if slot and CORNER_SLOTS[slot] then
        ENEMY_HINTS.tight = true -- EUI clears the width in corner slots
    elseif type(eui.GetHealthBarWidth) == "function" then
        local barWidth = PlainNumber(eui.GetHealthBarWidth())
        if barWidth then
            if slot == "textSlotTop" and type(eui.NP_TopNameWidth) == "function" then
                barWidth = PlainNumber(eui.NP_TopNameWidth(plate, barWidth)) or barWidth
            end
            local percent = profile and PlainNumber(profile.enemyNameWidthPct) or 100
            ENEMY_HINTS.boxWidth = math.max(barWidth * percent / 100, MIN_NAME_WIDTH)
            ENEMY_HINTS.wraps = profile and profile.enemyNameWrap == true
        end
    end
    local left, right = 0, 0
    if Shown(plate.nameRaidFrame) then
        left = (profile and PlainNumber(profile.nameRaidMarkerSize) or DEFAULT_MARKER_SIZE) + RAID_MARKER_GAP
    end
    -- The target's arrows hug the bar's sides, at the edge of a full-width name box.
    if Shown(plate.leftArrow) then
        local arrow = EnemyArrowWidth(eui, profile) + ARROW_GAP
        left, right = left + arrow, right + arrow
    end
    ENEMY_HINTS.edgeLeft, ENEMY_HINTS.edgeRight = left, right
    ENEMY_HINTS.topLift = TopLift(eui, profile, slot)
    return ENEMY_HINTS
end

local function FullPlateHints(plate, profile)
    FULL_PLATE_HINTS.fontSize = profile and PlainNumber(profile.friendlyNameTextSize)
    local arrows = Shown(plate.leftArrow) and PlainNumber(plate._arrowW)
    FULL_PLATE_HINTS.edgeLeft = arrows and arrows + ARROW_GAP or nil
    FULL_PLATE_HINTS.edgeRight = FULL_PLATE_HINTS.edgeLeft
    return FULL_PLATE_HINTS
end

function adapter.GetName(unit, nameplate)
    local eui = EUI()
    local profile = Profile()

    local friendly = eui.friendlyPlates[unit]
    if friendly then
        if not friendly:IsShown() then return false end
        return friendly.name, FullPlateHints(friendly, profile)
    end

    local enemy = eui.plates[unit]
    if enemy then
        return enemy.name, EnemyHints(eui, enemy, profile)
    end

    -- Name-only mode: EUI's restyled Blizzard name. With EUI's friendly players turned
    -- off, or in follower dungeons and delves, the plate is Blizzard's own and the
    -- Blizzard adapter takes it.
    if not followerInstance and profile and profile.showFriendlyPlayers ~= false
        and profile.friendlyNameOnly ~= false and eui.pendingUnits and eui.pendingUnits[unit] then
        local unitFrame = nameplate.UnitFrame
        if unitFrame and not unitFrame:IsForbidden() then
            NAME_ONLY_HINTS.fontSize = PlainNumber(profile.friendlyNameSize)
            return unitFrame.name, NAME_ONLY_HINTS
        end
        return false
    end

    -- A friendly unit whose full plate EUI hasn't built yet (or keeps hidden) is still
    -- EUI's: Blizzard's frame is suppressed there, and nothing should float over it.
    if not followerInstance and profile and profile.showFriendlyPlayers ~= false
        and eui.pendingUnits and eui.pendingUnits[unit] then
        return false
    end
end

local UNIT_HOOKS = { "TryAddFriendlyPlate", "RemoveFriendlyPlate", "RemoveFriendlyPlateNoRestore" }
local REFRESH_HOOKS = {
    "RefreshAllSettings", "UpdateFriendlyNameplateSystem", "RefreshFriendlyNameSize",
    "RefreshFriendlyNameTextSize", "RefreshFriendlyBelowName", "NP_SyncFriendlyNameFormat",
}

function adapter.Enable(plates)
    local eui = EUI()
    for _, name in ipairs(UNIT_HOOKS) do
        if type(eui[name]) == "function" then
            hooksecurefunc(eui, name, plates.MarkUnit)
        end
    end
    for _, name in ipairs(REFRESH_HOOKS) do
        if type(eui[name]) == "function" then
            hooksecurefunc(eui, name, plates.MarkAll)
        end
    end
    UpdateInstance()
    ns.RegisterEvent("PLAYER_ENTERING_WORLD", UpdateInstance)
    ns.RegisterEvent("ZONE_CHANGED_NEW_AREA", UpdateInstance)
end

ns.Plates:RegisterAdapter(adapter)
