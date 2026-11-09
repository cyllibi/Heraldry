--[[ UI\PageSharing.lua
  Export: pick what to include, get a string to copy. Import: paste a string, see
  exactly what it adds or changes (each line can be unticked), then apply. ]]

local _, ns = ...
local L = ns.L
local Widgets, Share, Icons, Identity = ns.Widgets, ns.Share, ns.Icons, ns.Identity

local COLUMN_GAP = 16
local AREA_HEIGHT = 110
local PREVIEW_ROW_HEIGHT = 26

local STATUS_COLOR = { new = GREEN_FONT_COLOR, change = YELLOW_FONT_COLOR, same = GRAY_FONT_COLOR }
local STATUS_TEXT = { new = L.IMPORT_NEW, change = L.IMPORT_CHANGE, same = L.IMPORT_SAME }
local KIND_TEXT = { myGuild = L.MY_GUILD, guilds = L.IMPORT_KIND_GUILD, players = L.IMPORT_KIND_PLAYER,
    custom = L.IMPORT_KIND_CUSTOM }
local ERROR_TEXT = {
    [Share.ERRORS.EMPTY] = L.IMPORT_ERROR_EMPTY,
    [Share.ERRORS.FOREIGN] = L.IMPORT_ERROR_FOREIGN,
    [Share.ERRORS.NEWER] = L.IMPORT_ERROR_NEWER,
    [Share.ERRORS.DAMAGED] = L.IMPORT_ERROR_DAMAGED,
    [Share.ERRORS.INVALID] = L.IMPORT_ERROR_INVALID,
    [Share.ERRORS.NOTHING] = L.IMPORT_ERROR_NOTHING,
}

local function InitChangeRow(row, change)
    if not row.Check then
        row.Check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        row.Check:SetSize(22, 22)
        row.Check:SetPoint("LEFT", 2, 0)
        row.Check:SetScript("OnClick", function(self) self.change.skip = not self:GetChecked() end)
        row.Icon = Widgets.IconBox(row, 32, 18)
        row.Icon:SetPoint("LEFT", row.Check, "RIGHT", 4, 0)
        row.Text = Widgets.Text(row, "GameFontHighlightSmall")
        row.Text:SetPoint("LEFT", row.Icon, "RIGHT", 6, 0)
        row.Text:SetPoint("RIGHT", -4, 0)
        row.Text:SetMaxLines(1)
    end
    row.Check.change = change
    row.Check:SetChecked(not change.skip)
    row.Check:SetShown(change.status ~= "same")
    row.Icon:SetIcon(change.icon ~= "none" and change.icon or nil, true)
    local subject = change.name or ""
    if change.kind == "guilds" and change.ruleset ~= Identity:GetRuleset() then
        subject = L.RULE_OTHER_RULESET:format(Identity.RulesetName(change.ruleset), subject)
    end
    local status = STATUS_COLOR[change.status]:WrapTextInColorCode(STATUS_TEXT[change.status])
    row.Text:SetText(L.IMPORT_ROW:format(status, KIND_TEXT[change.kind], subject, Icons:Describe(change.icon)))
end

ns.Options:AddPage("sharing", L.PAGE_SHARING, function(page, content)
    local columnWidth = (content:GetWidth() > 0 and content:GetWidth() or 600) / 2 - COLUMN_GAP / 2

    ---------------------------------------------------------------- export
    local export = CreateFrame("Frame", nil, content)
    export:SetPoint("TOPLEFT")
    export:SetPoint("BOTTOMLEFT")
    export:SetWidth(columnWidth)

    local exportHeader = Widgets.Header(export, L.EXPORT)
    exportHeader:SetPoint("TOPLEFT")
    local exportIntro = Widgets.Text(export, "GameFontHighlightSmall", L.EXPORT_INTRO, columnWidth)
    exportIntro:SetPoint("TOPLEFT", exportHeader, "BOTTOMLEFT", 0, -6)

    local include = { myGuild = true, guilds = true, players = true, custom = false, allRulesets = false }
    local checks = {}
    local previous = exportIntro
    for _, option in ipairs({
        { key = "myGuild", text = L.EXPORT_MY_GUILD },
        { key = "guilds", text = L.EXPORT_GUILDS },
        { key = "players", text = L.EXPORT_PLAYERS },
        { key = "custom", text = L.EXPORT_CUSTOM, tooltip = L.EXPORT_CUSTOM_TOOLTIP },
        { key = "allRulesets", text = L.EXPORT_ALL_RULESETS },
    }) do
        local check = Widgets.Checkbox(export, option.text, option.tooltip,
            function() return include[option.key] end,
            function(checked) include[option.key] = checked end)
        check:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", previous == exportIntro and -4 or 0, -2)
        checks[#checks + 1] = check
        previous = check
    end

    local exportArea = Widgets.TextArea(export)
    local exportStatus = Widgets.Text(export, "GameFontHighlightSmall")
    local makeExport = Widgets.Button(export, L.EXPORT_CREATE, function()
        local payload = Share.Build(ns.profile, include, Identity:GetRuleset())
        local count = Share.CountRules(payload)
        local editBox = exportArea:GetEditBox()
        if count == 0 then
            editBox:SetText("")
            exportStatus:SetText(L.EXPORT_NOTHING)
            return
        end
        local text = Share.Encode(payload)
        editBox:SetText(text)
        editBox:SetFocus()
        editBox:HighlightText()
        exportStatus:SetText(L.EXPORT_DONE:format(count, #text))
    end)
    makeExport:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 4, -8)
    exportArea:SetPoint("TOPLEFT", makeExport, "BOTTOMLEFT", 0, -8)
    exportArea:SetPoint("RIGHT", export, "RIGHT")
    exportArea:SetHeight(AREA_HEIGHT)
    exportArea:GetEditBox():HookScript("OnEditFocusGained", function(self) self:HighlightText() end)
    exportStatus:SetPoint("TOPLEFT", exportArea, "BOTTOMLEFT", 2, -6)
    exportStatus:SetPoint("RIGHT", export, "RIGHT")

    ---------------------------------------------------------------- import
    local import = CreateFrame("Frame", nil, content)
    import:SetPoint("TOPRIGHT")
    import:SetPoint("BOTTOMRIGHT")
    import:SetWidth(columnWidth)

    local importHeader = Widgets.Header(import, L.IMPORT)
    importHeader:SetPoint("TOPLEFT")
    local importIntro = Widgets.Text(import, "GameFontHighlightSmall", L.IMPORT_INTRO, columnWidth)
    importIntro:SetPoint("TOPLEFT", importHeader, "BOTTOMLEFT", 0, -6)

    local importArea = Widgets.TextArea(import)
    importArea:SetPoint("TOPLEFT", importIntro, "BOTTOMLEFT", 0, -8)
    importArea:SetPoint("RIGHT", import, "RIGHT")
    importArea:SetHeight(AREA_HEIGHT)

    local importStatus = Widgets.Text(import, "GameFontHighlightSmall")
    local changes
    local previewList, apply

    local function ShowChanges(list, message)
        changes = list
        previewList:SetItems(list or {}, "")
        previewList:SetShown(list ~= nil)
        importStatus:SetText(message or "")
        apply:SetEnabled(list ~= nil)
    end

    local previewButton = Widgets.Button(import, L.IMPORT_PREVIEW, function()
        local payload, problem = Share.Decode(importArea:GetEditBox():GetText())
        if not payload then
            ShowChanges(nil, RED_FONT_COLOR:WrapTextInColorCode(ERROR_TEXT[problem]))
            return
        end
        local list = Share.Diff(ns.profile, payload)
        local new, changed = 0, 0
        for _, change in ipairs(list) do
            if change.status == "new" then new = new + 1 elseif change.status == "change" then changed = changed + 1 end
        end
        ShowChanges(list, L.IMPORT_SUMMARY:format(new, changed, #list - new - changed))
    end)
    previewButton:SetPoint("TOPLEFT", importArea, "BOTTOMLEFT", 0, -8)

    apply = Widgets.Button(import, L.IMPORT_APPLY, function()
        if not changes then return end
        local applied = Share.Apply(ns.profile, changes)
        importArea:GetEditBox():SetText("")
        ShowChanges(nil, L.IMPORT_APPLIED:format(applied))
        ns.Fire("RULES_CHANGED")
        ns.Fire("CUSTOM_CHANGED")
    end)
    apply:SetPoint("LEFT", previewButton, "RIGHT", 6, 0)
    importStatus:SetPoint("TOPLEFT", previewButton, "BOTTOMLEFT", 2, -6)
    importStatus:SetPoint("RIGHT", import, "RIGHT")

    previewList = Widgets.List(import, PREVIEW_ROW_HEIGHT, InitChangeRow)
    previewList:SetPoint("TOPLEFT", importStatus, "BOTTOMLEFT", -2, -6)
    previewList:SetPoint("BOTTOMRIGHT")
    ShowChanges(nil)

    page:AddRefresh(function()
        for _, check in ipairs(checks) do check:Refresh() end
    end)
end)
