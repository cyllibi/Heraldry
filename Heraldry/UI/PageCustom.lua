--[[ UI\PageCustom.lua
  Custom icons: the player's own image files in Interface\AddOns\Heraldry_Custom\.
  WoW can't list a folder, so each file is registered by name once. The client only
  sees files that existed when it started, and draws a missing file as nothing, which
  the page says plainly. ]]

local _, ns = ...
local L = ns.L
local Widgets, Icons = ns.Widgets, ns.Icons

local ROW_HEIGHT = 34

local function InitRow(row, item)
    if not row.Icon then
        row:SetHighlightTexture([[Interface\QuestFrame\UI-QuestTitleHighlight]], "ADD")
        row.Icon = Widgets.IconBox(row, 44, 24)
        row.Icon:SetPoint("LEFT", 8, 0)
        row.Name = Widgets.Text(row, "GameFontHighlight")
        row.Name:SetPoint("LEFT", row.Icon, "RIGHT", 12, 0)
        row.Remove = Widgets.Button(row, REMOVE, function(self)
            local custom = ns.profile.custom
            for i, file in ipairs(custom) do
                if file == self.file then
                    table.remove(custom, i)
                    break
                end
            end
            ns.Fire("CUSTOM_CHANGED")
        end, 74)
        row.Remove:SetPoint("RIGHT", -6, 0)
    end
    row.Remove.file = item.file
    row.Icon:SetIcon("custom:" .. item.file)
    row.Name:SetText(item.file)
end

ns.Options:AddPage("custom", L.PAGE_CUSTOM, function(page, content)
    local folder = Icons.CustomFolderHint()
    local intro = Widgets.Text(content, "GameFontHighlight", L.CUSTOM_INTRO:format(folder))
    intro:SetPoint("TOPLEFT")
    intro:SetPoint("RIGHT", content, "RIGHT")
    intro:SetSpacing(3)

    local input = Widgets.EditBox(content, 240, L.CUSTOM_PLACEHOLDER)
    input:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", 6, -14)
    local preview = Widgets.IconBox(content, 56, 32)
    local register = Widgets.Button(content, L.CUSTOM_REGISTER, nil)
    register:SetPoint("LEFT", input, "RIGHT", 6, 0)
    preview:SetPoint("LEFT", register, "RIGHT", 12, 0)
    local message = Widgets.Text(content, "GameFontHighlightSmall")
    message:SetPoint("TOPLEFT", input, "BOTTOMLEFT", -4, -6)
    message:SetPoint("RIGHT", content, "RIGHT")

    input:HookScript("OnTextChanged", function(self)
        local parsed = Icons.ParseCustomName(self:GetText())
        preview:SetIcon(parsed and "custom:" .. parsed.file or nil)
    end)

    local function Register()
        local parsed, problem = Icons.ParseCustomName(input:GetText())
        if not parsed then
            message:SetText(RED_FONT_COLOR:WrapTextInColorCode(problem))
            return
        end
        for _, file in ipairs(ns.profile.custom) do
            if file == parsed.file then
                message:SetText(L.CUSTOM_ALREADY)
                return
            end
        end
        table.insert(ns.profile.custom, parsed.file)
        input:SetText("")
        input:ClearFocus()
        message:SetText(L.CUSTOM_ADDED:format(parsed.file))
        ns.Fire("CUSTOM_CHANGED")
    end
    register:SetScript("OnClick", Register)
    input:SetScript("OnEnterPressed", Register)

    local list = Widgets.List(content, ROW_HEIGHT, InitRow)
    list:SetPoint("TOPLEFT", message, "BOTTOMLEFT", -2, -10)
    list:SetPoint("BOTTOMRIGHT")

    page:AddRefresh(function()
        local items = {}
        for _, file in ipairs(ns.profile.custom) do items[#items + 1] = { file = file } end
        list:SetItems(items, L.CUSTOM_EMPTY)
    end)
end)
