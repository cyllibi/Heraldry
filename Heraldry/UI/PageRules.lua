--[[ UI\PageRules.lua
  The Guilds and Players pages: one builder, two kinds of rule.

  Guilds: the "my guild" rule pinned on top, then rules for named guilds, filtered to
  the current ruleset (a dropdown shows the others). Players: rules for characters,
  where "no icon" hides their guild's icon.

  Adding: the target, a guild or player seen on plates this session, or a typed name.
  Each opens the icon picker; picking creates the rule. Removing is immediate, with an
  Undo bar for a few seconds instead of a confirmation dialog. ]]

local _, ns = ...
local L = ns.L
local Widgets, Rules, Icons, Identity = ns.Widgets, ns.Rules, ns.Icons, ns.Identity

local ROW_HEIGHT = 34
local ROW_ICON_WIDTH, ROW_ICON_HEIGHT = 44, 24
local UNDO_SECONDS = 8
local MY_GUILD_HEIGHT = 62
local SEEN_DOT_SIZE = 10

local KIND_TEXT = {
    guilds = {
        title = L.PAGE_GUILDS, intro = L.GUILDS_INTRO, placeholder = L.GUILD_NAME_PLACEHOLDER,
        target = L.ADD_TARGET_GUILD, empty = L.GUILDS_EMPTY, emptyFiltered = L.GUILDS_EMPTY_FILTERED,
        recent = L.RECENT_GUILDS, recentEmpty = L.RECENT_GUILDS_EMPTY,
    },
    players = {
        title = L.PAGE_PLAYERS, intro = L.PLAYERS_INTRO, placeholder = L.PLAYER_NAME_PLACEHOLDER,
        target = L.ADD_TARGET_PLAYER, empty = L.PLAYERS_EMPTY, emptyFiltered = L.PLAYERS_EMPTY_FILTERED,
        recent = L.RECENT_PLAYERS, recentEmpty = L.RECENT_PLAYERS_EMPTY,
    },
}

--------------------------------------------------------------------------------
-- List rows
--------------------------------------------------------------------------------
-- A row: the icon (static until hovered), the name with a dot when that guild or player
-- was on a nameplate this session, what the icon is, and Remove. Clicking the row opens
-- the picker.
local function EditRow(self)
    local item = self.item
    ns.Options:EditRule(item.kind, item.key, item.name)
end

local function InitRow(row, item)
    if not row.Icon then
        row:SetHighlightTexture([[Interface\QuestFrame\UI-QuestTitleHighlight]], "ADD")
        row.Icon = Widgets.IconBox(row, ROW_ICON_WIDTH, ROW_ICON_HEIGHT)
        row.Icon:SetPoint("LEFT", 8, 0)
        row.Seen = row:CreateTexture(nil, "ARTWORK")
        row.Seen:SetSize(SEEN_DOT_SIZE, SEEN_DOT_SIZE)
        row.Seen:SetTexture([[Interface\COMMON\Indicator-Green]])
        row.Seen:SetPoint("LEFT", row.Icon, "RIGHT", 4, 6)
        row.Name = Widgets.Text(row, "GameFontHighlight")
        row.Name:SetPoint("LEFT", row.Seen, "RIGHT", 2, 0)
        row.Name:SetPoint("RIGHT", row, "RIGHT", -96, 0)
        row.Name:SetMaxLines(1)
        row.Detail = Widgets.Text(row, "GameFontDisableSmall")
        row.Detail:SetPoint("TOPLEFT", row.Seen, "BOTTOMLEFT", 0, -4)
        row.Detail:SetPoint("RIGHT", row.Name, "RIGHT")
        row.Detail:SetMaxLines(1)
        row.Remove = Widgets.Button(row, REMOVE, function(self) self.item.page:RemoveRule(self.item) end, 74)
        row.Remove:SetPoint("RIGHT", -6, 0)
        row:SetScript("OnClick", EditRow)
        row:SetScript("OnEnter", function(self)
            self.Icon:Animate(true)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.item.name, 1, 1, 1)
            if Rules:WasSeen(self.item.kind, self.item.key) then GameTooltip:AddLine(L.ROW_SEEN, 0.4, 1, 0.4) end
            GameTooltip:AddLine(L.ROW_CHANGE_HINT, nil, nil, nil, true)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function(self)
            self.Icon:Animate(false)
            GameTooltip:Hide()
        end)
    end
    row.item, row.Remove.item = item, item
    row.Icon:SetIcon(item.icon ~= "none" and item.icon or nil, true)
    row.Seen:SetAlpha(Rules:WasSeen(item.kind, item.key) and 1 or 0)
    row.Name:SetText(item.name)
    local detail = Icons:Describe(item.icon)
    if item.otherRuleset then
        detail = L.RULE_OTHER_RULESET:format(Identity.RulesetName(item.ruleset), detail)
        row.Name:SetFontObject("GameFontDisable")
    else
        row.Name:SetFontObject("GameFontHighlight")
    end
    row.Detail:SetText(detail)
end

--------------------------------------------------------------------------------
-- Page
--------------------------------------------------------------------------------
local function BuildMyGuild(page, content)
    local card = CreateFrame("Frame", nil, content, "InsetFrameTemplate")
    card:SetPoint("TOPLEFT", page.Intro, "BOTTOMLEFT", 0, -10)
    card:SetPoint("RIGHT", content, "RIGHT")
    card:SetHeight(MY_GUILD_HEIGHT)

    local iconButton = CreateFrame("Button", nil, card)
    iconButton:SetSize(56, 36)
    iconButton:SetPoint("LEFT", 12, 0)
    iconButton:SetHighlightTexture([[Interface\Buttons\ButtonHilight-Square]], "ADD")
    iconButton.Icon = Widgets.IconBox(iconButton, 52, 32)
    iconButton.Icon:SetPoint("CENTER")
    iconButton:SetScript("OnClick", function() ns.Options:EditMyGuild() end)
    Widgets.AttachTooltip(iconButton, L.MY_GUILD_CHANGE_ICON)

    local check = Widgets.Checkbox(card, L.MY_GUILD_ENABLE, L.MY_GUILD_TOOLTIP,
        function() return ns.profile.myGuild.enabled end,
        function(checked)
            if checked and not ns.profile.myGuild.icon then
                ns.Options:EditMyGuild()
                page:Refresh()
            else
                Rules:SetMyGuild(checked)
            end
        end)
    check:SetPoint("TOPLEFT", iconButton, "TOPRIGHT", 10, 4)

    local detail = Widgets.Text(card, "GameFontDisableSmall")
    detail:SetPoint("TOPLEFT", check, "BOTTOMLEFT", 4, -2)
    detail:SetPoint("RIGHT", card, "RIGHT", -12, 0)

    page:AddRefresh(function()
        local myGuild = ns.profile.myGuild
        check:Refresh()
        iconButton.Icon:SetIcon(myGuild.icon)
        local guild = Rules:GetMyGuildName()
        if not guild then
            detail:SetText(L.MY_GUILD_NONE)
        elseif Rules:Get("guilds", Identity:CachedGuildKey(guild)) then
            detail:SetText(L.MY_GUILD_OVERRIDDEN:format(guild))
        elseif not myGuild.icon then
            detail:SetText(L.MY_GUILD_PICK:format(guild))
        else
            detail:SetText(L.MY_GUILD_CURRENT:format(guild, Icons:Describe(myGuild.icon)))
        end
    end)
    return card
end

local function BuildPage(kind)
    local text = KIND_TEXT[kind]
    return function(page, content)
        page.Intro = Widgets.Text(content, "GameFontHighlight", text.intro)
        page.Intro:SetPoint("TOPLEFT")
        page.Intro:SetPoint("RIGHT", content, "RIGHT")
        page.Intro:SetWordWrap(true)
        local above = kind == "guilds" and BuildMyGuild(page, content) or page.Intro

        -- Add row
        local input = Widgets.EditBox(content, 200, text.placeholder)
        input:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 6, -14)
        local errorText = Widgets.Text(content, "GameFontRedSmall")
        local function AddTyped()
            local key, name, problem, warning = Rules.KeyForText(kind, input:GetText())
            errorText:SetText(problem or (warning and YELLOW_FONT_COLOR:WrapTextInColorCode(warning)) or "")
            if not key then return end
            input:SetText("")
            input:ClearFocus()
            ns.Options:EditRule(kind, key, name)
        end
        input:SetScript("OnEnterPressed", AddTyped)
        -- Complete from the names seen on nameplates this session, newest first.
        local names = {}
        Widgets.InlineComplete(input, function()
            wipe(names)
            for i, entry in ipairs(Rules:GetRecent(kind)) do names[i] = entry.name end
            return names
        end)
        local add = Widgets.Button(content, ADD, AddTyped)
        add:SetPoint("LEFT", input, "RIGHT", 6, 0)
        local target = Widgets.Button(content, text.target, function()
            local ok, reason = ns.Options:EditTargetRule(kind)
            errorText:SetText(ok and "" or reason)
        end)
        target:SetPoint("LEFT", add, "RIGHT", 6, 0)
        local recent = Widgets.Button(content, text.recent, nil)
        recent:SetPoint("LEFT", target, "RIGHT", 6, 0)
        recent:SetScript("OnClick", function(self)
            MenuUtil.CreateContextMenu(self, function(_, root)
                local seen = Rules:GetRecent(kind)
                if #seen == 0 then
                    root:CreateTitle(text.recentEmpty)
                    return
                end
                root:CreateTitle(text.recent)
                -- A busy city fills the list faster than a screen is tall.
                if root.SetScrollMode then root:SetScrollMode(Widgets.MENU_MAX_HEIGHT) end
                for _, entry in ipairs(seen) do
                    local label = Rules:Get(kind, entry.key) and L.RECENT_HAS_RULE:format(entry.name) or entry.name
                    root:CreateButton(label, function() ns.Options:EditRule(kind, entry.key, entry.name) end)
                end
            end)
        end)
        errorText:SetPoint("TOPLEFT", input, "BOTTOMLEFT", -4, -4)

        -- Filter row
        local filter = Widgets.EditBox(content, 160, SEARCH)
        filter:SetPoint("TOPLEFT", input, "BOTTOMLEFT", 0, -22)
        filter:HookScript("OnTextChanged", function() page:Refresh() end)
        local showAll = false
        if kind == "guilds" then
            local rulesets = Widgets.Dropdown(content, nil, 180, function()
                return {
                    { value = false, text = L.FILTER_THIS_RULESET:format(Identity.RulesetName(Identity:GetRuleset())) },
                    { value = true, text = L.FILTER_ALL_RULESETS },
                }
            end, function() return showAll end, function(value)
                showAll = value
                page:Refresh()
            end)
            rulesets:SetPoint("LEFT", filter, "RIGHT", 12, 0)
            page:AddRefresh(function() rulesets:Refresh() end)
        end
        local count = Widgets.Text(content, "GameFontDisableSmall")
        count:SetPoint("RIGHT", content, "RIGHT", -4, 0)
        count:SetPoint("BOTTOM", filter, "BOTTOM", 0, 4)

        -- Undo bar, under the list
        local undo = CreateFrame("Frame", nil, content)
        undo:SetHeight(24)
        undo:SetPoint("BOTTOMLEFT")
        undo:SetPoint("BOTTOMRIGHT")
        undo:Hide()
        undo.Text = Widgets.Text(undo, "GameFontHighlight")
        undo.Text:SetPoint("LEFT", 4, 0)
        undo.Button = Widgets.Button(undo, L.UNDO, function()
            local removed = undo.removed
            undo:Hide()
            if removed then Rules:Set(kind, removed.key, removed.rule.name, removed.rule.icon) end
        end)
        undo.Button:SetPoint("LEFT", undo.Text, "RIGHT", 10, 0)

        local list = Widgets.List(content, ROW_HEIGHT, InitRow)
        list:SetPoint("TOPLEFT", filter, "BOTTOMLEFT", -6, -8)
        list:SetPoint("BOTTOMRIGHT", undo, "TOPRIGHT", 0, 4)

        local generation = 0
        function page:RemoveRule(item)
            local rule = Rules:Remove(kind, item.key)
            if not rule then return end
            generation = generation + 1
            local mine = generation
            undo.removed = { key = item.key, rule = rule }
            undo.Text:SetText(L.REMOVED_RULE:format(rule.name))
            undo:Show()
            C_Timer.After(UNDO_SECONDS, function()
                if generation == mine then undo:Hide() end
            end)
        end

        page:AddRefresh(function()
            local ruleset = Identity:GetRuleset()
            local query = Identity.Fold(filter:GetText())
            local items, total = {}, 0
            for key, rule in pairs(ns.profile[kind]) do
                local keyRuleset = kind == "guilds" and Identity.SplitGuildKey(key)
                local other = keyRuleset and keyRuleset ~= ruleset
                if not other or showAll then
                    total = total + 1
                    if query == "" or Identity.Fold(rule.name):find(query, 1, true) then
                        items[#items + 1] = {
                            page = page, kind = kind, key = key, name = rule.name, icon = rule.icon,
                            ruleset = keyRuleset, otherRuleset = other,
                        }
                    end
                end
            end
            table.sort(items, function(a, b)
                if a.otherRuleset ~= b.otherRuleset then return not a.otherRuleset end
                return Identity.Fold(a.name) < Identity.Fold(b.name)
            end)
            list:SetItems(items, total == 0 and text.empty or text.emptyFiltered)
            count:SetText(L.RULE_COUNT:format(#items, total))
        end)
    end
end

ns.Options:AddPage("guilds", KIND_TEXT.guilds.title, BuildPage("guilds"))
ns.Options:AddPage("players", KIND_TEXT.players.title, BuildPage("players"))
