--[[ Plates\Plates.lua
  Puts the matched icon next to the name on every nameplate.

  Nameplate add-ons draw names in different places, so the name text is found through
  adapters (Plates\*.lua), tried in registration order: add-on adapters first, then
  Blizzard's own plate, then a generic fallback for plates no known add-on owns.
  An adapter is a table:
    id, label          for /heraldry check and the options status
    IsAvailable()      true when its nameplate add-on is loaded (checked at login)
    Enable(plates)     optional: hook the add-on so plates.MarkUnit / plates.MarkAll run
                       when it rebuilds a plate
    fallback = true    only for the generic fallback: skipped when an add-on owns the plate
    GetName(unit, nameplate) -> anchor, hints
                       the FontString showing the unit's name; nil to pass the plate on
                       to the next adapter; or false: "my add-on owns this plate but shows
                       no name right now" (hidden on purpose, or not built yet). Later
                       adapters may still claim it (Blizzard, when the add-on leaves the
                       plate to Blizzard), but the generic fallback won't, so no icon
                       floats over a plate an add-on chose to hide.
                       hints (non-secret values only, optional):
                         tight = true      the FontString's box hugs the text (auto width)
                         fontSize = n      the name's size, when the add-on knows it
                         boxWidth = n      width of a fixed name box: long names are cut
                                           there, so the icon never goes past the box
                         wraps = true      a name wider than the box wraps to 2 lines
                         edgeLeft/Right    something drawn just outside the name box on that
                                           side (target arrows, raid marker), this many
                                           pixels wide including its spacing; the icon
                                           moves past it only if they would overlap
                         anchorOnly = true anchor is not a name but a frame to sit above
                                           (generic fallback); host = the frame to draw on,
                                           lift = extra height above it
                         topAnchor = frame  something centred just above the name (a
                                           names-only plate's raid marker): an icon placed
                                           above the name goes on its top edge instead
                         topLift = n       extra height an icon placed above the name must
                                           clear (Blizzard's debuff row), staying centred on
                                           the name
                         span = { left, right, height, lift }
                                           Blizzard plates with a health bar: frames whose
                                           outer edges the icon sits beside on each side,
                                           the height of the name and bar together, and how
                                           far the middle of that is above the frames'
                                           middle. Used when display.tallBlizzard is on and
                                           the icon goes left or right of the name.

  The icon is a texture on the name FontString's parent frame ("host"), so it follows
  that frame's visibility, alpha and scale. One texture per host, reused as plates are
  recycled; a texture showing for one unit is hidden as soon as its unit's name moves
  to another host or the host moves to another unit.

  Inside the 12.x nameplate tree widget metrics can be secret and single point + size
  regions render displaced. So: no arithmetic on anything read from a plate unless it
  passed IsSecret; text width comes from an off-plate measuring FontString; the icon is
  anchored by two opposite corners with plain-number offsets.

  Updates: NAME_PLATE_UNIT_ADDED (at once, then again next frame for add-ons that build
  their plate in the same event), unit events that change identity or reaction, target
  and raid marker changes (they move things beside the name), setting changes, and a slow
  safety-net ticker for things no event announces (late guild data, plates switching
  between friendly and enemy owners, font changes). Work per update is skipped wherever
  inputs are unchanged. ]]

local _, ns = ...

local Plates = {}
ns.Plates = Plates

local IsSecret = ns.IsSecret
local Icons, Rules = ns.Icons, ns.Rules
local C_NamePlate, UnitCanAttack, InCombatLockdown = C_NamePlate, UnitCanAttack, InCombatLockdown

local REFRESH_INTERVAL = 0.5     -- seconds between safety-net passes while plates exist
local TEST_SECONDS = 10          -- "Show on my target" duration
local DEFAULT_FONT_SIZE = 12     -- used when the name's size can't be read
local LINE_SPACING = 1.15        -- line height as a multiple of font size, for 2-line names
local MAX_NAMEPLATE_TOKENS = 80  -- nameplate1..N probed after a loading screen
local ICON_LAYER, ICON_SUBLEVEL = "OVERLAY", 7

local adapters = {}
local activeAdapters = {}

local units = {}                 -- nameplate unit token -> true while its plate exists
local unitCount = 0
local unitRegion = {}            -- unit -> Region showing for it
-- Host frames belong to Blizzard or to the nameplate add-on, so our state about them
-- lives here, weakly keyed, never as fields on their frames.
local hostRegion = setmetatable({}, { __mode = "k" })

local dirty = {}
local pump = CreateFrame("Frame")
pump:Hide()
local ticker
local context = "world"          -- "world", "dungeon", "raid", "pvp"
local unitAdapter = {}           -- unit -> adapter that drew its icon (diagnostics)
local hiddenNames = {}           -- unit -> true while its plate's name is hidden from add-ons
local unitHiddenBy = {}          -- unit -> adapter whose add-on hides that plate's name
local test                       -- { guid =, unit =, icon =, timer = } while "Try on target" runs

local NAMEPLATE_TOKENS = {}
for i = 1, MAX_NAMEPLATE_TOKENS do
    NAMEPLATE_TOKENS[i] = "nameplate" .. i
end

local INSTANCE_CONTEXT = { none = "world", party = "dungeon", scenario = "dungeon", raid = "raid",
    pvp = "pvp", arena = "pvp" }

--------------------------------------------------------------------------------
-- Adapters
--------------------------------------------------------------------------------
function Plates:RegisterAdapter(adapter)
    adapters[#adapters + 1] = adapter
end

-- The anchor (name FontString, or a frame for the fallback), hints and adapter; or nil
-- and the adapter whose add-on owns the plate but shows no name there.
local function FindName(unit, nameplate)
    local owner
    for i = 1, #activeAdapters do
        local adapter = activeAdapters[i]
        if not (adapter.fallback and owner) then
            local anchor, hints = adapter.GetName(unit, nameplate)
            if anchor then return anchor, hints, adapter end
            if anchor == false then owner = owner or adapter end
        end
    end
    return nil, nil, nil, owner
end

function Plates:GetActiveAdapters()
    return activeAdapters
end

-- For diagnostics: plates currently showing an icon, by adapter label; plates a nameplate
-- add-on hides that would have had an icon, by adapter label; and how many plates on
-- screen have names hidden from add-ons by the game.
function Plates:GetStats()
    local byAdapter, hiddenBy = {}, {}
    for unit, adapter in pairs(unitAdapter) do
        if unitRegion[unit] then byAdapter[adapter.label] = (byAdapter[adapter.label] or 0) + 1 end
    end
    for _, adapter in pairs(unitHiddenBy) do
        hiddenBy[adapter.label] = (hiddenBy[adapter.label] or 0) + 1
    end
    local hidden = 0
    for _ in pairs(hiddenNames) do hidden = hidden + 1 end
    return byAdapter, hiddenBy, hidden
end

--------------------------------------------------------------------------------
-- Measuring: a FontString outside the plate tree returns plain numbers.
--------------------------------------------------------------------------------
local rulerFrame = CreateFrame("Frame", nil, UIParent)
rulerFrame:SetSize(1, 1)
rulerFrame:SetPoint("BOTTOMRIGHT", UIParent, "TOPLEFT", -100, 100)
rulerFrame:SetAlpha(0)
local ruler = rulerFrame:CreateFontString(nil, "ARTWORK")

local function MeasureText(region, text, file, size, flags)
    local cache = region.measure
    if cache.text == text and cache.file == file and cache.size == size and cache.flags == flags then
        return cache.width
    end
    ruler:SetFont(file, size, flags or "")
    ruler:SetText(text)
    cache.text, cache.file, cache.size, cache.flags = text, file, size, flags
    cache.width = ruler:GetStringWidth()
    return cache.width
end

-- The name's first line and the number of lines, from plain text only.
local function ReadText(fontString)
    local text = fontString:GetText()
    if IsSecret(text) or not text or text == "" then return nil, 1 end
    local newline = text:find("\n", 1, true)
    if not newline then return text, 1 end
    local _, breaks = text:gsub("\n", "")
    return text:sub(1, newline - 1), breaks + 1
end

--------------------------------------------------------------------------------
-- Layout
--------------------------------------------------------------------------------
-- How much further out the icon must go to clear something drawn just outside the name
-- box (edge: its width from the box edge outward). Distances are measured outward from
-- the text's edge; room is the free space between the text and the box edge.
local function Clearance(gap, iconWidth, room, edge)
    if not edge or edge <= 0 then return 0 end
    if gap < room + edge and gap + iconWidth > room then
        return room + edge - gap
    end
    return 0
end

-- Where the icon's centre goes: a point on the anchor and an offset from it.
local function Placement(region, fontString, hints, display, size, iconWidth, iconHeight)
    local position, gap = display.position, display.gap
    local halfWidth, halfHeight = iconWidth / 2, iconHeight / 2
    if hints and hints.anchorOnly then
        return "TOP", 0, gap + halfHeight + (hints.lift or 0)
    end

    local file, _, flags = fontString:GetFont()
    if IsSecret(file) or IsSecret(flags) then file = nil end
    local justify = fontString:GetJustifyH()
    if IsSecret(justify) then justify = "CENTER" end

    local text, lines = ReadText(fontString)
    local textWidth = text and file and MeasureText(region, text, file, size, flags)
    local boxWidth = hints and hints.boxWidth
    if textWidth and boxWidth and textWidth > boxWidth then
        -- Cut off with an ellipsis at the box edge, or wrapped onto a second line.
        textWidth = boxWidth
        if hints.wraps and lines == 1 then lines = 2 end
    end
    local tight = hints and hints.tight and lines == 1

    -- Keep the icon level with the first line of a two-line name (EUI's guild line).
    local firstLine = (lines - 1) * size * LINE_SPACING / 2

    if position == "LEFT" or position == "RIGHT" then
        local left = position == "LEFT"
        -- Free space between the text and the box edge on this side.
        local room = 0
        if not tight and textWidth and boxWidth then
            local spare = math.max(0, boxWidth - textWidth)
            if justify == "CENTER" then
                room = spare / 2
            elseif (justify == "LEFT") ~= left then
                room = spare
            end
        end
        local edge = hints and (left and hints.edgeLeft or not left and hints.edgeRight)
        local reach = gap + halfWidth + Clearance(gap, iconWidth, room, edge)
        if tight then
            return position, left and -reach or reach, firstLine
        elseif textWidth then
            if justify == "LEFT" then
                return "LEFT", left and -reach or textWidth + reach, firstLine
            elseif justify == "RIGHT" then
                return "RIGHT", left and -(textWidth + reach) or reach, firstLine
            end
            return "CENTER", left and -(textWidth / 2 + reach) or textWidth / 2 + reach, firstLine
        end
        -- Text width unknown (secret name): centred above is never on the wrong side, and
        -- it clears Blizzard's debuff row like a chosen "above" does.
        return "TOP", 0, gap + halfHeight + (hints and hints.topLift or 0)
    end

    local point = position
    local y = position == "TOP" and gap + halfHeight + (hints and hints.topLift or 0) or -(gap + halfHeight)
    if not tight and textWidth and justify == "LEFT" then
        return point .. "LEFT", textWidth / 2, y
    elseif not tight and textWidth and justify == "RIGHT" then
        return point .. "RIGHT", -textWidth / 2, y
    end
    return point, 0, y
end

-- The tall icon beside a Blizzard plate's name and health bar (hints.span), or nil.
local function SpanPlacement(hints, display, spec)
    local span = hints and hints.span
    if not (span and display.tallBlizzard) then return nil end
    local position = display.position
    if position ~= "LEFT" and position ~= "RIGHT" then return nil end
    local left = position == "LEFT"
    local height = span.height * display.scale
    local width = height * spec.aspect
    local x = display.gap + width / 2
    return left and span.left or span.right, position, left and -x or x, span.lift, width, height
end

-- Anchors region's texture next to the anchor. Shared by the plates and the previews.
function Plates.Layout(region, anchor, hints, spec, display)
    local point, x, y, width, height
    local spanAnchor
    spanAnchor, point, x, y, width, height = SpanPlacement(hints, display, spec)
    if spanAnchor then
        anchor = spanAnchor
    else
        local size
        if not (hints and hints.anchorOnly) then
            local _
            _, size = anchor:GetFont()
        end
        if IsSecret(size) or not size or size <= 0 then size = hints and hints.fontSize or DEFAULT_FONT_SIZE end
        height = size * display.scale
        width = height * spec.aspect
        local topAnchor = display.position == "TOP" and hints and hints.topAnchor
        if topAnchor then
            -- Ride on top of what Blizzard centres above the name (the raid marker).
            anchor, point, x, y = topAnchor, "TOP", 0, display.gap + height / 2
        else
            point, x, y = Placement(region, anchor, hints, display, size, width, height)
        end
    end
    x, y = x + display.x, y + display.y

    local last = region.layout
    if last.anchor == anchor and last.point == point and last.x == x and last.y == y
        and last.width == width and last.height == height then
        return
    end
    last.anchor, last.point, last.x, last.y, last.width, last.height = anchor, point, x, y, width, height
    local texture = region.texture
    texture:ClearAllPoints()
    texture:SetPoint("TOPLEFT", anchor, point, x - width / 2, y + height / 2)
    texture:SetPoint("BOTTOMRIGHT", anchor, point, x + width / 2, y - height / 2)
end

function Plates.NewRegion(host)
    local region = Icons.CreateRegion(host, ICON_LAYER, ICON_SUBLEVEL)
    region.layout, region.measure = {}, {}
    return region
end

--------------------------------------------------------------------------------
-- Per-unit update
--------------------------------------------------------------------------------
local function Release(unit)
    local region = unitRegion[unit]
    if region then
        region:Hide()
        region.unit = nil
        unitRegion[unit] = nil
    end
    unitAdapter[unit] = nil
    unitHiddenBy[unit] = nil
end

local function ShownHere(display)
    if not display.enabled or not display[context] then return false end
    return not (display.hideInCombat and InCombatLockdown())
end

local function ShownForReaction(unit, display)
    if display.friendly and display.enemy then return true end
    local canAttack = UnitCanAttack("player", unit)
    if IsSecret(canAttack) then return false end
    if canAttack then return display.enemy end
    return display.friendly
end

-- The icon for a unit: the "Show on my target" test wins, then the rules. Icons from an
-- add-on that isn't loaded (a Twitch emote) show nothing on plates; the options still
-- show them as a question mark.
-- The test follows the unit, not the nameplate token, which is recycled for other units.
local function IsTestUnit(unit)
    if not test then return false end
    local guid = UnitGUID(unit)
    if test.guid and not IsSecret(guid) then return guid == test.guid end
    return test.unit == unit
end

local function IconFor(unit, profile)
    if IsTestUnit(unit) then
        return Icons:Resolve(test.icon)
    end
    local display = profile.display
    if not ShownHere(display) then return nil end
    local iconId, _, secretShow, nameHidden = Rules:ResolveUnit(unit, profile)
    hiddenNames[unit] = nameHidden or nil
    local spec = iconId and Icons:Resolve(iconId)
    if not spec or spec.requires or not ShownForReaction(unit, display) then return nil end
    return spec, secretShow
end

-- firstPass: the synchronous update on NAME_PLATE_UNIT_ADDED. Other plate add-ons may
-- not have shown their frames yet, so the generic fallback waits for the next frame
-- rather than flash the icon in its place for one frame.
local function Update(unit, firstPass)
    local profile = ns.profile
    local display = profile.display
    local nameplate = C_NamePlate.GetNamePlateForUnit(unit)
    if not nameplate or nameplate:IsForbidden() then
        return Release(unit)
    end

    local spec, secretShow = IconFor(unit, profile)
    if not spec then
        return Release(unit)
    end

    local anchor, hints, adapter, owner = FindName(unit, nameplate)
    if not anchor or anchor:IsForbidden() or not anchor:IsShown() or (firstPass and hints and hints.anchorOnly) then
        Release(unit)
        unitHiddenBy[unit] = owner
        return
    end
    local host = hints and hints.host or anchor:GetParent()
    if not host or host:IsForbidden() then
        return Release(unit)
    end
    -- A host that isn't on screen (a name parked under a hidden frame) can be shared by
    -- several units; drawing there would only pass the texture back and forth.
    local visible = host:IsVisible()
    if IsSecret(visible) or not visible then
        return Release(unit)
    end

    local region = hostRegion[host]
    if not region then
        region = Plates.NewRegion(host)
        hostRegion[host] = region
    end
    if unitRegion[unit] ~= region then
        Release(unit)
        -- The host was showing another unit's icon: that unit's plate moved on.
        if region.unit and unitRegion[region.unit] == region then
            unitRegion[region.unit] = nil
        end
        region.unit = unit
        unitRegion[unit] = region
    end
    unitAdapter[unit] = adapter

    region:SetIcon(spec)
    Plates.Layout(region, anchor, hints, spec, display)
    if IsSecret(secretShow) then
        region.texture:SetAlphaFromBoolean(secretShow, display.alpha, 0)
        region.alphaSet = nil
    elseif region.alphaSet ~= display.alpha then
        region.texture:SetAlpha(display.alpha)
        region.alphaSet = display.alpha
    end
    region:Show()
end

local function ProcessDirty(self)
    self:Hide()
    for unit in pairs(dirty) do
        dirty[unit] = nil
        if units[unit] then Update(unit) end
    end
end
pump:SetScript("OnUpdate", ProcessDirty)

function Plates.MarkUnit(unit)
    if units[unit] then
        dirty[unit] = true
        pump:Show()
    end
end

function Plates.MarkAll()
    for unit in pairs(units) do
        dirty[unit] = true
    end
    if next(dirty) then pump:Show() end
end

-- Display changes (size, position) must re-anchor even when nothing else changed.
local function Relayout()
    for _, region in pairs(hostRegion) do
        wipe(region.layout)
        region.alphaSet = nil
    end
    Plates.MarkAll()
end

local function SetTicker()
    if unitCount > 0 and not ticker then
        ticker = C_Timer.NewTicker(REFRESH_INTERVAL, Plates.MarkAll)
    elseif unitCount == 0 and ticker then
        ticker:Cancel()
        ticker = nil
    end
end

local function AddUnit(unit)
    if not units[unit] then
        units[unit] = true
        unitCount = unitCount + 1
        SetTicker()
    end
    Update(unit, true)
    Plates.MarkUnit(unit)
end

local function RemoveUnit(unit)
    if units[unit] then
        units[unit] = nil
        unitCount = unitCount - 1
        SetTicker()
    end
    dirty[unit] = nil
    hiddenNames[unit] = nil
    Release(unit)
end

-- Friendly player plates are missing from C_NamePlate.GetNamePlates, so after a loading
-- screen every token is probed instead.
local function Sweep()
    for _, unit in ipairs(NAMEPLATE_TOKENS) do
        if C_NamePlate.GetNamePlateForUnit(unit) then
            AddUnit(unit)
        elseif units[unit] then
            RemoveUnit(unit)
        end
    end
end

local function UpdateContext()
    local _, instanceType = IsInInstance()
    context = INSTANCE_CONTEXT[instanceType] or "world"
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------
local function OnUnitEvent(_, unit)
    if units[unit] then Plates.MarkUnit(unit) end
end

-- Auras only move an icon placed above the name on Blizzard's plates (past the debuff row,
-- whose height follows the auras): skip every other plate, which in a raid pull is most.
local function OnAuraEvent(_, unit)
    local adapter = unitAdapter[unit]
    if unitRegion[unit] and adapter and adapter.id == "Blizzard" and ns.profile.display.position == "TOP" then
        Plates.MarkUnit(unit)
    end
end

-- Adapters whose add-on is loaded, in registration order. Runs once, at login.
function Plates:EnableAdapters()
    for _, adapter in ipairs(adapters) do
        if adapter.IsAvailable() then
            activeAdapters[#activeAdapters + 1] = adapter
            if adapter.Enable then adapter.Enable(Plates) end
        end
    end
end

-- The adapter search on its own, for the headless tests.
Plates.FindName = FindName

ns.RegisterEvent("PLAYER_LOGIN", function()
    Plates:EnableAdapters()

    ns.RegisterEvent("NAME_PLATE_UNIT_ADDED", function(_, unit) AddUnit(unit) end)
    ns.RegisterEvent("NAME_PLATE_UNIT_REMOVED", function(_, unit) RemoveUnit(unit) end)
    ns.RegisterEvent("UNIT_NAME_UPDATE", OnUnitEvent)
    ns.RegisterEvent("UNIT_FACTION", OnUnitEvent)
    ns.RegisterEvent("UNIT_FLAGS", OnUnitEvent)
    ns.RegisterEvent("PLAYER_GUILD_UPDATE", Plates.MarkAll)
    ns.RegisterEvent("PLAYER_REGEN_DISABLED", Plates.MarkAll)
    ns.RegisterEvent("PLAYER_REGEN_ENABLED", Plates.MarkAll)
    ns.RegisterEvent("ZONE_CHANGED_NEW_AREA", function()
        UpdateContext()
        Plates.MarkAll()
    end)
    ns.RegisterEvent("PLAYER_ENTERING_WORLD", function()
        UpdateContext()
        Sweep()
    end)
    -- Target arrows and raid markers beside the name come and go with these.
    ns.RegisterEvent("PLAYER_TARGET_CHANGED", Plates.MarkAll)
    ns.RegisterEvent("RAID_TARGET_UPDATE", Plates.MarkAll)
    -- Blizzard's debuff row above the name grows and shrinks with the unit's auras.
    ns.RegisterEvent("UNIT_AURA", OnAuraEvent)
    ns.RegisterEvent("DISPLAY_SIZE_CHANGED", Relayout)
    ns.RegisterEvent("UI_SCALE_CHANGED", Relayout)
end)

ns.Listen("PROFILE_CHANGED", Relayout)
ns.Listen("DISPLAY_CHANGED", Relayout)
ns.Listen("RULES_CHANGED", Plates.MarkAll)
ns.Listen("CUSTOM_CHANGED", Plates.MarkAll)
ns.Listen("ICONS_CHANGED", Plates.MarkAll)

-- For /heraldry check: what the unit's plate looks like to Heraldry, or nil without a
-- plate. unit may be "target"; plates are tracked by their own nameplateN token.
--   adapter      label of the adapter whose anchor the plate uses (nil: none)
--   hiddenBy     label of the add-on that owns the plate but shows no name there
--   iconShown    whether Heraldry's icon is showing
--   boxWidth     the name box width the placement is clamped to, when known
function Plates:Describe(unit)
    local nameplate = C_NamePlate.GetNamePlateForUnit(unit)
    if not nameplate then return nil end
    local token = nameplate.namePlateUnitToken or unit
    local anchor, hints, adapter, owner = FindName(token, nameplate)
    local region = unitRegion[token]
    return {
        adapter = adapter and adapter.label,
        hiddenBy = owner and owner.label,
        iconShown = region ~= nil and region.texture:IsShown(),
        boxWidth = anchor and hints and hints.boxWidth,
    }
end

-- "Show on my target": draws icon on the target's plate for a few seconds, rules or not.
-- Returns true, or false and a message.
function Plates:ShowTest(icon)
    local nameplate = C_NamePlate.GetNamePlateForUnit("target")
    local token = nameplate and nameplate.namePlateUnitToken
    if not token or not units[token] then return false, ns.L.TEST_NO_PLATE end
    if test then test.timer:Cancel() end
    local guid = UnitGUID("target")
    local current = { unit = token, guid = not IsSecret(guid) and guid or nil, icon = icon }
    current.timer = C_Timer.NewTimer(TEST_SECONDS, function()
        if test == current then test = nil end
        Plates.MarkAll()
    end)
    test = current
    Plates.MarkAll()
    return true
end
