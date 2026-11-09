--[[ UI\PageGeneral.lua
  The root page: master switch, status (nameplate add-ons, ruleset, rules, profile),
  actions for the target, profile tools, and Diagnostics: the /heraldry check report in
  a copyable box. Also where data from a newer Heraldry is pointed out. ]]

local _, ns = ...
local L = ns.L
local Widgets = ns.Widgets

local COLUMN_WIDTH = 290
local COLUMN_GAP = 20
local DIAGNOSTICS_HEIGHT = 250

local function AdapterNames()
    local names = {}
    for _, adapter in ipairs(ns.Plates:GetActiveAdapters()) do
        names[#names + 1] = adapter.label
    end
    return table.concat(names, ", ")
end

local function CountRules()
    local ruleset = ns.Identity:GetRuleset()
    local guilds, players = 0, 0
    for key in pairs(ns.profile.guilds) do
        if ns.Identity.SplitGuildKey(key) == ruleset then guilds = guilds + 1 end
    end
    for _ in pairs(ns.profile.players) do players = players + 1 end
    return guilds, players
end

-- Red notices above everything else: saved data from a newer Heraldry. Returns the frame the
-- rest of the page anchors below.
local function BuildNotices(content, top)
    local anchor = top
    local function Notice(text)
        local line = Widgets.Text(content, "GameFontRed", text)
        line:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -10)
        line:SetPoint("RIGHT", content, "RIGHT")
        anchor = line
        return line
    end
    if ns.DB.newerData then Notice(L.NEWER_DATA) end
    return anchor
end

ns.Options:AddPage("general", L.ADDON_TITLE, function(page, content)
    local intro = Widgets.Text(content, "GameFontHighlight", L.GENERAL_INTRO)
    intro:SetPoint("TOPLEFT")
    intro:SetPoint("RIGHT", content, "RIGHT")
    local above = BuildNotices(content, intro)

    -- Left column: switch, status, target actions, profile.
    local enabled = Widgets.Checkbox(content, L.ENABLE, L.ENABLE_TOOLTIP,
        function() return ns.profile.display.enabled end,
        function(checked) ns.DB:SetDisplay("enabled", checked) end)
    enabled:SetPoint("TOPLEFT", above, "BOTTOMLEFT", -4, -12)

    -- Account-wide, like the button's position: not part of the character profile.
    local minimapAvailable = ns.MinimapButton:IsAvailable()
    local minimap = Widgets.Checkbox(content, L.MINIMAP_SHOW,
        minimapAvailable and L.MINIMAP_SHOW_TOOLTIP or L.MINIMAP_UNAVAILABLE,
        function() return ns.MinimapButton:IsShown() end,
        function(checked) ns.MinimapButton:SetShown(checked) end)
    minimap:SetPoint("LEFT", enabled, "LEFT", COLUMN_WIDTH + COLUMN_GAP, 0)
    minimap:SetActive(minimapAvailable)

    local statusHeader = Widgets.Header(content, L.STATUS)
    statusHeader:SetPoint("TOPLEFT", enabled, "BOTTOMLEFT", 4, -14)
    local status = Widgets.Text(content, "GameFontHighlight", nil, COLUMN_WIDTH)
    status:SetPoint("TOPLEFT", statusHeader, "BOTTOMLEFT", 0, -8)
    status:SetSpacing(4)

    local actionsHeader = Widgets.Header(content, L.QUICK_ACTIONS)
    actionsHeader:SetPoint("TOPLEFT", status, "BOTTOMLEFT", 0, -18)
    local message = Widgets.Text(content, "GameFontRedSmall", nil, COLUMN_WIDTH)
    local function TargetButton(text, kind)
        return Widgets.Button(content, text, function()
            local ok, reason = ns.Options:EditTargetRule(kind)
            message:SetText(ok and "" or reason)
        end)
    end
    local targetGuild = TargetButton(L.ACTION_TARGET_GUILD, "guilds")
    targetGuild:SetPoint("TOPLEFT", actionsHeader, "BOTTOMLEFT", 0, -8)
    local targetPlayer = TargetButton(L.ACTION_TARGET_PLAYER, "players")
    targetPlayer:SetPoint("LEFT", targetGuild, "RIGHT", 8, 0)
    message:SetPoint("TOPLEFT", targetGuild, "BOTTOMLEFT", 0, -6)

    local copy = Widgets.Button(content, L.PROFILE_COPY_ACCOUNT, function() ns.DB:CopyAccountToCharacter() end)
    copy:SetPoint("TOPLEFT", targetGuild, "BOTTOMLEFT", 0, -28)
    Widgets.AttachTooltip(copy, L.PROFILE_COPY_ACCOUNT, L.PROFILE_COPY_ACCOUNT_TOOLTIP)

    local help = Widgets.Text(content, "GameFontDisableSmall", L.SLASH_HELP_BODY, COLUMN_WIDTH)
    help:SetPoint("TOPLEFT", copy, "BOTTOMLEFT", 0, -16)
    help:SetSpacing(2)

    -- Right column: diagnostics.
    local diagnosticsHeader = Widgets.Header(content, L.DIAGNOSTICS)
    diagnosticsHeader:SetPoint("TOPLEFT", statusHeader, "TOPLEFT", COLUMN_WIDTH + COLUMN_GAP, 0)
    local diagnosticsIntro = Widgets.Text(content, "GameFontHighlightSmall", L.DIAGNOSTICS_INTRO, COLUMN_WIDTH)
    diagnosticsIntro:SetPoint("TOPLEFT", diagnosticsHeader, "BOTTOMLEFT", 0, -6)
    local report = Widgets.TextArea(content)
    report:SetPoint("TOPLEFT", diagnosticsIntro, "BOTTOMLEFT", 0, -8)
    report:SetSize(COLUMN_WIDTH, DIAGNOSTICS_HEIGHT)
    local function Fill()
        report:GetEditBox():SetText(table.concat(ns.Diagnostics:Lines(), "\n"))
    end
    local refresh = Widgets.Button(content, L.DIAGNOSTICS_REFRESH, Fill)
    refresh:SetPoint("TOPLEFT", report, "BOTTOMLEFT", 0, -6)
    report:GetEditBox():HookScript("OnEditFocusGained", function(self) self:HighlightText() end)

    page:AddRefresh(function()
        enabled:Refresh()
        minimap:Refresh()
        local guilds, players = CountRules()
        local guildName = ns.Rules:GetMyGuildName()
        status:SetText(L.STATUS_BODY:format(
            AdapterNames(),
            ns.Identity.RulesetName(ns.Identity:GetRuleset()),
            guildName or L.NO_GUILD,
            guilds, players,
            ns.DB:UsesCharacterProfile() and L.PROFILE_IS_CHARACTER or L.PROFILE_IS_ACCOUNT))
        copy:SetEnabled(ns.DB:UsesCharacterProfile())
        message:SetText("")
        Fill()
    end)
end)
