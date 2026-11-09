--[[ UI\Widgets.lua
  Small builders over Blizzard's stock templates, so every page looks native and
  behaves the same. Each control has :Refresh() to re-read its value from the profile.
  Templates: UICheckButtonTemplate, MinimalSliderWithSteppersTemplate,
  WowStyle1DropdownTemplate, UIPanelButtonTemplate, InputBoxTemplate, WowScrollBoxList
  with MinimalScrollBar, ScrollingEditBoxTemplate, InsetFrameTemplate. ]]

local _, ns = ...

local Widgets = {}
ns.Widgets = Widgets

Widgets.LABEL_WIDTH = 120       -- left column for slider and dropdown labels
Widgets.SLIDER_WIDTH = 180
Widgets.ROW_SPACING = 6
local BUTTON_PADDING = 24
local MIN_BUTTON_WIDTH = 80

local function ShowTooltip(owner, title, text)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(title, 1, 1, 1)
    if text then GameTooltip:AddLine(text, nil, nil, nil, true) end
    GameTooltip:Show()
end

function Widgets.AttachTooltip(frame, title, text)
    frame:HookScript("OnEnter", function(self)
        local resolvedTitle = type(title) == "function" and title() or title
        if resolvedTitle then ShowTooltip(self, resolvedTitle, type(text) == "function" and text() or text) end
    end)
    frame:HookScript("OnLeave", GameTooltip_Hide)
end

function Widgets.Text(parent, font, text, width)
    local fontString = parent:CreateFontString(nil, "ARTWORK", font or "GameFontHighlight")
    fontString:SetJustifyH("LEFT")
    if width then
        fontString:SetWidth(width)
        fontString:SetWordWrap(true)
    end
    if text then fontString:SetText(text) end
    return fontString
end

function Widgets.Header(parent, text)
    return Widgets.Text(parent, "GameFontNormalLarge", text)
end

function Widgets.Button(parent, text, onClick, width)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetText(text)
    button:SetHeight(22)
    button:SetWidth(width or math.max(MIN_BUTTON_WIDTH, button:GetFontString():GetStringWidth() + BUTTON_PADDING))
    button:SetScript("OnClick", onClick)
    ns.Skin:Apply("Button", button)
    return button
end

function Widgets.Checkbox(parent, label, tooltip, get, set)
    local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    check:SetSize(26, 26)
    check.Label = Widgets.Text(check, "GameFontHighlight", label)
    check.Label:SetPoint("LEFT", check, "RIGHT", 2, 1)
    check:SetHitRectInsets(0, -(check.Label:GetStringWidth() + 6), 0, 0)
    check:SetScript("OnClick", function(self)
        local checked = self:GetChecked()
        PlaySound(checked and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
        set(checked)
    end)
    if tooltip then Widgets.AttachTooltip(check, label, tooltip) end
    ns.Skin:Apply("Checkbox", check)
    function check:Refresh()
        self:SetChecked(get())
    end
    function check:SetActive(active)
        self:SetEnabled(active)
        self.Label:SetFontObject(active and "GameFontHighlight" or "GameFontDisable")
    end
    return check
end

-- formatter(value) -> text shown right of the slider.
function Widgets.Slider(parent, label, range, formatter, get, set)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(Widgets.LABEL_WIDTH + Widgets.SLIDER_WIDTH + 60, 26)
    row.Label = Widgets.Text(row, "GameFontHighlight", label)
    row.Label:SetPoint("LEFT")
    row.Label:SetWidth(Widgets.LABEL_WIDTH - 10)

    local slider = CreateFrame("Frame", nil, row, "MinimalSliderWithSteppersTemplate")
    slider:SetPoint("LEFT", row, "LEFT", Widgets.LABEL_WIDTH, 0)
    slider:SetWidth(Widgets.SLIDER_WIDTH)
    local labels = MinimalSliderWithSteppersMixin.Label
    local formatters = { [labels.Right] = CreateMinimalSliderFormatter(labels.Right, formatter) }
    local steps = math.floor((range.max - range.min) / range.step + 0.5)
    slider:Init(get(), range.min, range.max, steps, formatters)
    slider:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, value)
        if row.refreshing then return end
        -- Snap: the slider reports fractional steps while dragging.
        value = range.min + math.floor((value - range.min) / range.step + 0.5) * range.step
        set(value)
    end, row)
    row.Slider = slider

    function row:Refresh()
        self.refreshing = true
        slider:SetValue(get())
        self.refreshing = false
    end
    function row:SetActive(active)
        slider:SetEnabled(active)
        self.Label:SetFontObject(active and "GameFontHighlight" or "GameFontDisable")
    end
    return row
end

-- options() -> { { value =, text = } }, evaluated each time the menu opens.
function Widgets.Dropdown(parent, label, width, options, get, set)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize((label and Widgets.LABEL_WIDTH or 0) + width, 26)
    local dropdown = CreateFrame("DropdownButton", nil, row, "WowStyle1DropdownTemplate")
    dropdown:SetWidth(width)
    if label then
        row.Label = Widgets.Text(row, "GameFontHighlight", label)
        row.Label:SetPoint("LEFT")
        dropdown:SetPoint("LEFT", row, "LEFT", Widgets.LABEL_WIDTH, 0)
    else
        dropdown:SetPoint("LEFT")
    end
    dropdown:SetupMenu(function(_, root)
        for _, option in ipairs(options()) do
            root:CreateRadio(option.text, function() return get() == option.value end, function()
                set(option.value)
            end)
        end
    end)
    row.Dropdown = dropdown
    ns.Skin:Apply("Dropdown", dropdown)
    function row:Refresh()
        dropdown:GenerateMenu()
    end
    function row:SetActive(active)
        dropdown:SetEnabled(active)
        if self.Label then self.Label:SetFontObject(active and "GameFontHighlight" or "GameFontDisable") end
    end
    return row
end

-- Single-line input with grey placeholder text.
function Widgets.EditBox(parent, width, placeholder)
    local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    box:SetSize(width, 22)
    box:SetAutoFocus(false)
    box:SetMaxLetters(64)
    if placeholder then
        box.Placeholder = Widgets.Text(box, "GameFontDisable", placeholder)
        box.Placeholder:SetPoint("LEFT", box, "LEFT", 2, 0)
        box:HookScript("OnTextChanged", function(self)
            self.Placeholder:SetShown(self:GetText() == "")
        end)
    end
    box:SetScript("OnEscapePressed", box.ClearFocus)
    ns.Skin:Apply("EditBox", box)
    return box
end

-- Inline completion: while the player types at the end of the box, the first candidate that
-- starts with the text (any case) fills in the rest, highlighted, so typing on replaces it,
-- Backspace removes it and Tab or Enter accepts it. candidates() returns names, best first.
-- A name that already matches what was typed is never extended: with "Ana" and "Anaxis" both
-- seen, typing Ana and pressing Enter means Ana.
-- Edit box positions are byte offsets, so # is right for names with accented letters too
-- (case is folded for A-Z only: string.lower doesn't know accented capitals).
function Widgets.InlineComplete(box, candidates)
    local typedLength = 0
    box:HookScript("OnTextChanged", function(self, userInput)
        local text = self:GetText()
        local length = #text
        if not userInput then
            -- Cleared or set by code (after Add): the next key starts a fresh word.
            if length == 0 then typedLength = 0 end
            return
        end
        local grew = length > typedLength
        typedLength = length
        if not grew or self:GetCursorPosition() ~= length then return end
        local typed = text:lower()
        local names = candidates()
        for _, name in ipairs(names) do
            if name:lower() == typed then return end
        end
        for _, name in ipairs(names) do
            if #name > length and name:sub(1, length):lower() == typed then
                self:SetText(name)
                self:HighlightText(length, #name)
                self:SetCursorPosition(length)
                return
            end
        end
    end)
    box:HookScript("OnTabPressed", function(self)
        local length = #self:GetText()
        self:HighlightText(length, length)
        self:SetCursorPosition(length)
        typedLength = length
    end)
end

-- Multi-line, scrolling text area. Returns the container; :GetEditBox() for the text.
function Widgets.TextArea(parent)
    local inset = CreateFrame("Frame", nil, parent, "InsetFrameTemplate")
    local area = CreateFrame("Frame", nil, inset, "ScrollingEditBoxTemplate")
    area:SetPoint("TOPLEFT", 6, -6)
    area:SetPoint("BOTTOMRIGHT", -24, 6)
    local bar = CreateFrame("EventFrame", nil, inset, "MinimalScrollBar")
    bar:SetPoint("TOPLEFT", area, "TOPRIGHT", 6, 0)
    bar:SetPoint("BOTTOMLEFT", area, "BOTTOMRIGHT", 6, 0)
    ScrollUtil.RegisterScrollBoxWithScrollBar(area:GetScrollBox(), bar)
    ns.Skin:Apply("Inset", inset)
    ns.Skin:Apply("ScrollBar", bar)
    inset.Area = area
    function inset:GetEditBox()
        return area:GetEditBox()
    end
    return inset
end

-- A scrolling list. initialize(row, item) fills a pooled row frame; rows of one list
-- share a template and height. Returns the inset; :SetItems(list) replaces the content.
function Widgets.List(parent, rowHeight, initialize, template)
    local inset = CreateFrame("Frame", nil, parent, "InsetFrameTemplate")
    local box = CreateFrame("Frame", nil, inset, "WowScrollBoxList")
    box:SetPoint("TOPLEFT", 4, -4)
    box:SetPoint("BOTTOMRIGHT", -22, 4)
    local bar = CreateFrame("EventFrame", nil, inset, "MinimalScrollBar")
    bar:SetPoint("TOPLEFT", box, "TOPRIGHT", 4, 0)
    bar:SetPoint("BOTTOMLEFT", box, "BOTTOMRIGHT", 4, 0)
    local view = CreateScrollBoxListLinearView()
    view:SetElementExtent(rowHeight)
    view:SetElementInitializer(template or "Button", initialize)
    ScrollUtil.InitScrollBoxListWithScrollBar(box, bar, view)
    ns.Skin:Apply("Inset", inset)
    ns.Skin:Apply("ScrollBar", bar)

    inset.Empty = Widgets.Text(inset, "GameFontDisable", nil)
    inset.Empty:SetPoint("TOPLEFT", 20, -20)
    inset.Empty:SetPoint("RIGHT", -20, 0)
    inset.Empty:SetJustifyH("CENTER")
    inset.Box = box

    function inset:SetItems(items, emptyText)
        box:SetDataProvider(CreateDataProvider(items), ScrollBoxConstants.RetainScrollPosition)
        self.Empty:SetText(emptyText or "")
        self.Empty:SetShown(#items == 0)
    end
    return inset
end

-- An icon preview inside a frame: a Region filling a box of the given size.
-- SetIcon(id, static): static shows the thumbnail; Animate(on) plays it (on hover).
function Widgets.IconBox(parent, width, height)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(width, height)
    frame.Region = ns.Icons.CreateRegion(frame, "ARTWORK")
    function frame:SetIcon(id, static)
        local spec = id and ns.Icons:Resolve(id)
        if not spec then
            self.Region:Clear()
            return
        end
        self.Region:SetIcon(spec, static)
        self.Region:FitInto(self, self:GetWidth(), self:GetHeight())
        self.Region:Show()
    end
    function frame:Animate(animate)
        local spec = self.Region.spec
        if spec and spec.anim then self:SetIcon(spec.id, not animate) end
    end
    frame:SetScript("OnHide", function(self) self.Region:StopAnimation() end)
    frame:SetScript("OnShow", function(self)
        if self.Region.spec then self.Region:PlayAnimation() end
    end)
    return frame
end
