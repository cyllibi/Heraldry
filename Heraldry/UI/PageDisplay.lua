--[[ UI\PageDisplay.lua
  Where and how the icon is drawn, with a live preview: a friendly name-only player
  (two lines, as EllesmereUI shows the guild) and an enemy plate with a centred,
  fixed-width name box (as Blizzard and EllesmereUI enemy plates have). The preview uses
  the same layout code as the real plates (Plates.Layout). ]]

local _, ns = ...
local L = ns.L
local Widgets, DB, Plates = ns.Widgets, ns.DB, ns.Plates

local PREVIEW_WIDTH, PREVIEW_HEIGHT = 220, 210
-- Sample name sizes: EllesmereUI's own defaults for name-only friendly names and enemy
-- names, used when EUI isn't loaded (its profile values are used when it is).
local FRIENDLY_FONT_SIZE, ENEMY_FONT_SIZE = 15, 12
local PREVIEW_BAR_WIDTH, PREVIEW_BAR_HEIGHT = 120, 12
local NAME_ONLY_HINTS = { tight = true }
-- The enemy name box has a fixed width: long names stop at its edge.
local ENEMY_HINTS = { boxWidth = PREVIEW_BAR_WIDTH }
local PREVIEW_NAME_SPACING = 4   -- the enemy sample's name sits this far above its bar
local SAMPLE_ICON_PATH = [[Interface\Icons\INV_Shirt_GuildTabard_01]]

local previewIcon -- chosen with "Preview icon"; not saved

local function PercentFormatter(value)
    return ("%d%%"):format(math.floor(value * 100 + 0.5))
end

local function PixelFormatter(value)
    return ("%d"):format(value)
end

-- The first icon the player uses, so the preview shows their own choice.
local function DefaultPreviewIcon()
    local profile = ns.profile
    if profile.myGuild.icon then return profile.myGuild.icon end
    local _, guildRule = next(profile.guilds)
    if guildRule then return guildRule.icon end
    for _, rule in pairs(profile.players) do
        if rule.icon ~= "none" then return rule.icon end
    end
    return "game:" .. (GetFileIDFromPath(SAMPLE_ICON_PATH) or ns.Icons.MISSING_ICON)
end

-- The icon the preview and "Try on target" use (also /heraldry try).
function ns.Options:PreviewIcon()
    return previewIcon or DefaultPreviewIcon()
end

local function BuildPreview(page, parent)
    local box = CreateFrame("Frame", nil, parent, "InsetFrameTemplate")
    box:SetSize(PREVIEW_WIDTH, PREVIEW_HEIGHT)
    local caption = Widgets.Text(box, "GameFontNormal", L.PREVIEW)
    caption:SetPoint("TOPLEFT", 10, -8)

    local function SampleName(text, r, g, b)
        local name = box:CreateFontString(nil, "OVERLAY")
        name:SetFont(STANDARD_TEXT_FONT, ENEMY_FONT_SIZE, "OUTLINE") -- refined by ApplyFonts
        name:SetTextColor(r, g, b)
        name:SetText(text)
        return name
    end

    -- Friendly, name only: auto-sized, centred, guild on a second line.
    local friendly = SampleName(L.PREVIEW_FRIENDLY_NAME, 0.25, 1, 0.25)
    friendly:SetPoint("CENTER", box, "TOP", 0, -64)
    friendly:SetJustifyH("CENTER")
    friendly:SetWordWrap(true) -- an explicit newline only breaks with word wrap on

    -- Enemy: health bar with the name in a fixed-width centred box above it.
    local bar = CreateFrame("StatusBar", nil, box)
    bar:SetSize(PREVIEW_BAR_WIDTH, PREVIEW_BAR_HEIGHT)
    bar:SetPoint("CENTER", box, "TOP", 0, -150)
    bar:SetStatusBarTexture([[Interface\TargetingFrame\UI-StatusBar]])
    bar:SetStatusBarColor(0.8, 0.1, 0.1)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0.7)
    local barBackground = bar:CreateTexture(nil, "BACKGROUND")
    barBackground:SetAllPoints()
    barBackground:SetColorTexture(0, 0, 0, 0.6)
    local enemy = SampleName(L.PREVIEW_ENEMY_NAME, 1, 0.3, 0.3)
    enemy:SetPoint("BOTTOM", bar, "TOP", 0, 4)
    enemy:SetWidth(PREVIEW_BAR_WIDTH)
    enemy:SetJustifyH("CENTER")
    enemy:SetWordWrap(false)

    local friendlyRegion = Plates.NewRegion(box)
    local enemyRegion = Plates.NewRegion(box)

    local choose = Widgets.Button(box, L.PREVIEW_CHOOSE_ICON, function()
        ns.IconPicker:Open({
            subject = L.PREVIEW,
            current = ns.Options:PreviewIcon(),
            onPick = function(icon)
                previewIcon = icon
                page:Refresh()
            end,
        })
    end)
    choose:SetPoint("BOTTOMLEFT", 8, 10)

    -- Try the icon on a real plate without making a rule.
    local status = Widgets.Text(parent, "GameFontHighlightSmall", nil, PREVIEW_WIDTH)
    local test = Widgets.Button(box, L.TEST_ON_TARGET, function()
        local ok, reason = ns.Plates:ShowTest(ns.Options:PreviewIcon())
        status:SetText(ok and L.TEST_STARTED or RED_FONT_COLOR:WrapTextInColorCode(reason))
    end)
    test:SetPoint("BOTTOMRIGHT", -8, 10)
    Widgets.AttachTooltip(test, L.TEST_ON_TARGET, L.TEST_ON_TARGET_TOOLTIP)

    status:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 2, -6)
    local note = Widgets.Text(parent, "GameFontDisableSmall", L.PREVIEW_NOTE, PREVIEW_WIDTH)
    note:SetPoint("TOPLEFT", status, "BOTTOMLEFT", 0, -6)

    -- The nameplates' own font and sizes when EllesmereUI provides them.
    local function ApplyFonts()
        local eui = EllesmereNameplates_NS
        local file, friendlySize, enemySize = STANDARD_TEXT_FONT, FRIENDLY_FONT_SIZE, ENEMY_FONT_SIZE
        if type(eui) == "table" then
            local euiFile = type(eui.GetFont) == "function" and eui.GetFont()
            if type(euiFile) == "string" then file = euiFile end
            local profile = eui.db and eui.db.profile
            if profile then
                friendlySize = tonumber(profile.friendlyNameSize) or friendlySize
                local slot = type(eui.FindNameSlot) == "function" and eui.FindNameSlot()
                enemySize = slot and tonumber(profile[slot .. "Size"]) or enemySize
            end
        end
        friendly:SetFont(file, friendlySize, "OUTLINE")
        enemy:SetFont(file, enemySize, "OUTLINE")
    end

    -- The tall icon option applies to Blizzard's plates, so the preview shows it only when
    -- EllesmereUI's plates (which keep their own layout) aren't loaded.
    local enemySpan = { left = bar, right = bar }
    local function UpdateSpan(display)
        if display.tallBlizzard and type(EllesmereNameplates_NS) ~= "table" then
            local _, size = enemy:GetFont()
            enemySpan.height = PREVIEW_BAR_HEIGHT + PREVIEW_NAME_SPACING + (size or ENEMY_FONT_SIZE)
            enemySpan.lift = (enemySpan.height - PREVIEW_BAR_HEIGHT) / 2
            ENEMY_HINTS.span = enemySpan
        else
            ENEMY_HINTS.span = nil
        end
    end

    page:AddRefresh(function()
        local display = ns.profile.display
        ApplyFonts()
        UpdateSpan(display)
        friendly:SetText(L.PREVIEW_FRIENDLY_NAME .. "\n" .. L.PREVIEW_GUILD_LINE)
        local spec = ns.Icons:Resolve(ns.Options:PreviewIcon())
        for _, pair in ipairs({ { friendlyRegion, friendly, NAME_ONLY_HINTS }, { enemyRegion, enemy, ENEMY_HINTS } }) do
            local region, fontString, hints = pair[1], pair[2], pair[3]
            if spec and display.enabled then
                region:SetIcon(spec)
                wipe(region.layout)
                Plates.Layout(region, fontString, hints, spec, display)
                region.texture:SetAlpha(display.alpha)
                region:Show()
            else
                region:Hide()
            end
        end
    end)
    return box
end

ns.Options:AddPage("display", L.PAGE_DISPLAY, function(page, content)
    local controls = {}
    local function Track(control)
        controls[#controls + 1] = control
        return control
    end
    local function Check(key, label, tooltip)
        return Track(Widgets.Checkbox(content, label, tooltip,
            function() return ns.profile.display[key] end,
            function(checked) DB:SetDisplay(key, checked) end))
    end
    local function Slider(key, label, formatter)
        return Track(Widgets.Slider(content, label, DB.RANGES[key], formatter,
            function() return ns.profile.display[key] end,
            function(value) DB:SetDisplay(key, value) end))
    end

    local preview = BuildPreview(page, content)
    preview:SetPoint("TOPRIGHT")

    local enabled = Check("enabled", L.ENABLE, L.ENABLE_TOOLTIP)
    enabled:SetPoint("TOPLEFT", -4, 0)
    local friendly = Check("friendly", L.SHOW_FRIENDLY)
    friendly:SetPoint("TOPLEFT", enabled, "BOTTOMLEFT", 0, -2)
    local enemy = Check("enemy", L.SHOW_ENEMY)
    enemy:SetPoint("LEFT", friendly, "RIGHT", 150, 0)

    local layoutHeader = Widgets.Header(content, L.LAYOUT)
    layoutHeader:SetPoint("TOPLEFT", friendly, "BOTTOMLEFT", 4, -12)
    local positions = {}
    for _, position in ipairs(DB.POSITIONS) do
        positions[#positions + 1] = { value = position, text = L["POSITION_" .. position] }
    end
    local position = Track(Widgets.Dropdown(content, L.POSITION, 150, function() return positions end,
        function() return ns.profile.display.position end,
        function(value) DB:SetDisplay("position", value) end))
    position:SetPoint("TOPLEFT", layoutHeader, "BOTTOMLEFT", 0, -8)

    local rows = {
        Slider("scale", L.SIZE, PercentFormatter),
        Slider("gap", L.GAP, PixelFormatter),
        Slider("x", L.OFFSET_X, PixelFormatter),
        Slider("y", L.OFFSET_Y, PixelFormatter),
        Slider("alpha", L.OPACITY, PercentFormatter),
    }
    local previous = position
    for _, row in ipairs(rows) do
        row:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -Widgets.ROW_SPACING)
        previous = row
    end
    local tall = Check("tallBlizzard", L.TALL_BLIZZARD, L.TALL_BLIZZARD_TOOLTIP)
    tall:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", -4, -6)
    previous = tall

    local whereHeader = Widgets.Header(content, L.WHERE)
    whereHeader:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 4, -14)
    local world = Check("world", L.WHERE_WORLD)
    world:SetPoint("TOPLEFT", whereHeader, "BOTTOMLEFT", -4, -6)
    local dungeon = Check("dungeon", L.WHERE_DUNGEON)
    dungeon:SetPoint("LEFT", world, "RIGHT", 150, 0)
    local raid = Check("raid", L.WHERE_RAID)
    raid:SetPoint("TOPLEFT", world, "BOTTOMLEFT", 0, -2)
    local pvp = Check("pvp", L.WHERE_PVP)
    pvp:SetPoint("LEFT", raid, "RIGHT", 150, 0)
    local combat = Check("hideInCombat", L.HIDE_IN_COMBAT)
    combat:SetPoint("TOPLEFT", raid, "BOTTOMLEFT", 0, -2)
    local strict = Check("strictPlayers", L.STRICT_PLAYERS, L.STRICT_PLAYERS_TOOLTIP)
    strict:SetPoint("TOPLEFT", combat, "BOTTOMLEFT", 0, -2)
    local unknown = Check("unknownPlates", L.UNKNOWN_PLATES, L.UNKNOWN_PLATES_TOOLTIP)
    unknown:SetPoint("TOPLEFT", strict, "BOTTOMLEFT", 0, -2)

    local reset = Widgets.Button(content, L.RESET_DISPLAY, function() DB:ResetDisplay() end)
    reset:SetPoint("TOPLEFT", unknown, "BOTTOMLEFT", 4, -12)
    page.onDefault = function() DB:ResetDisplay() end

    page:AddRefresh(function()
        local on = ns.profile.display.enabled
        local beside = ns.profile.display.position == "LEFT" or ns.profile.display.position == "RIGHT"
        for _, control in ipairs(controls) do
            control:Refresh()
            -- The tall icon only applies beside the name, not above or below it.
            if control == tall then control:SetActive(on and beside)
            elseif control ~= enabled then control:SetActive(on) end
        end
    end)
end)
