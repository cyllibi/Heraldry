--[[ UI\IconPicker.lua
  The one icon picker every page uses: a movable window with tabs (Library, Game icons,
  Twitch Emotes when that add-on is loaded, Custom last), a search box, Favorites and
  Recent rows, a grid, and a preview of the selection beside a sample name, drawn with
  the player's own Display settings.

  The grid is a ScrollBox of rows; each row frame owns a fixed set of cells, so only the
  visible rows exist and scrolling recycles them. Cells show static thumbnails; only the
  hovered cell and the preview animate, so browsing never loads whole sprite sheets.

  Mouse: click selects, double-click chooses, right-click adds or removes a favorite.
  Keyboard (out of combat): arrows move the selection, Enter chooses, Escape closes.
  The window holds nothing protected and stays usable in combat.

  ns.IconPicker:Open{ subject =, current =, allowNone =, onPick = function(id) end } ]]

local _, ns = ...
local L = ns.L
local Widgets, Icons, GameIcons, Skin = ns.Widgets, ns.Icons, ns.GameIcons, ns.Skin

local Picker = {}
ns.IconPicker = Picker

local WINDOW_WIDTH, WINDOW_HEIGHT = 640, 640
local SEARCH_DELAY = 0.25           -- seconds of no typing before the grid refilters
local MAX_RECENT = 12               -- icons kept in the Recent row (and shown per row)
local PREVIEW_FONT_SIZE = 14
local GRIDS = {
    -- Named icons: room for wide art and a label.
    large = { cellWidth = 92, cellHeight = 70, iconWidth = 72, iconHeight = 40, columns = 6, label = true },
    small = { cellWidth = 42, cellHeight = 42, iconWidth = 36, iconHeight = 36, columns = 13 },
}
local STRIP = { cellWidth = 40, cellHeight = 34, iconWidth = 32, iconHeight = 26, columns = MAX_RECENT }

local TABS = {
    { id = "lib", text = L.PICKER_TAB_LIBRARY, grid = "large", hint = L.PICKER_HINT_LIBRARY },
    { id = "game", text = L.PICKER_TAB_GAME, grid = "small", hint = L.PICKER_HINT_GAME },
    { id = "twitch", text = L.PICKER_TAB_TWITCH, grid = "large", hint = L.PICKER_HINT_TWITCH,
        available = Icons.TwitchEmotesLoaded },
    { id = "custom", text = L.PICKER_TAB_CUSTOM, grid = "large", hint = L.PICKER_HINT_CUSTOM },
}

local window, options
local allCells = {}  -- every cell ever made, to recolor when EUI's accent changes
local state = { tab = "lib", query = "", items = {}, selected = nil, category = nil }
local searchGeneration = 0

--------------------------------------------------------------------------------
-- Items per tab: lists of icon ids (game icons stay file IDs until shown).
--------------------------------------------------------------------------------
local function Matches(query, ...)
    if query == "" then return true end
    for i = 1, select("#", ...) do
        local text = select(i, ...)
        if type(text) == "string" and ns.Identity.Fold(text):find(query, 1, true) then return true end
    end
    return false
end

-- Library search matches the start of words in names and tags ("ice" finds Ice cube, not
-- Jeweled chalice); the text is folded once per entry by Icons.
local function LibraryItems(query)
    local items = {}
    local category = state.category
    for _, entry in ipairs(Icons:GetLibrary()) do
        if (not category or entry.category == category)
            and (query == "" or Icons.MatchesWords(Icons.LibrarySearchText(entry), query)) then
            items[#items + 1] = "lib:" .. entry.key
        end
    end
    return items
end

-- Emote names and categories are folded once by Icons; only the query is folded here.
local function TwitchItems(query)
    local items = {}
    local category = state.category
    for _, emote in ipairs(Icons:GetTwitchEmotes()) do
        if (not category or emote.category == category)
            and (query == "" or emote.folded:find(query, 1, true) or emote.labelFolded:find(query, 1, true)) then
            items[#items + 1] = "twitch:" .. emote.name
        end
    end
    return items
end

-- The category dropdown: library themes on the Library tab, emote packs and their folders
-- on the Twitch tab (rebuilt when packs change).
local categoryOptions, libraryCategoryOptions
local function CategoryOptions()
    if state.tab == "lib" then
        if not libraryCategoryOptions then
            libraryCategoryOptions = { { value = false, text = L.PICKER_ALL_CATEGORIES } }
            for _, category in ipairs(Icons:GetLibraryCategories()) do
                libraryCategoryOptions[#libraryCategoryOptions + 1] = { value = category, text = category }
            end
        end
        return libraryCategoryOptions
    end
    if not categoryOptions then
        categoryOptions = { { value = false, text = L.PICKER_ALL_CATEGORIES } }
        local _, categories = Icons:GetTwitchEmotes()
        for _, category in ipairs(categories) do
            categoryOptions[#categoryOptions + 1] = { value = category.key, text = category.label }
        end
    end
    return categoryOptions
end

local function HasCategories()
    if state.tab == "lib" then return #Icons:GetLibraryCategories() > 0 end
    return state.tab == "twitch"
end

local function CustomItems(query)
    local items = {}
    for _, file in ipairs(ns.profile.custom) do
        if Matches(query, file) then items[#items + 1] = "custom:" .. file end
    end
    return items
end

local function ItemId(item)
    if type(item) == "number" then return "game:" .. item end
    return item
end

local function CollectItems()
    local query = ns.Identity.Fold(state.query)
    if state.tab == "lib" then return LibraryItems(query) end
    if state.tab == "twitch" then return TwitchItems(query) end
    if state.tab == "custom" then return CustomItems(query) end
    return GameIcons:Search(state.query)
end

local function EmptyText()
    local filtering = state.query ~= ""
    if state.tab == "lib" then
        return filtering and L.PICKER_NO_MATCHES or L.PICKER_LIBRARY_EMPTY
    elseif state.tab == "custom" then
        return filtering and L.PICKER_NO_MATCHES or L.PICKER_CUSTOM_EMPTY
    end
    return L.PICKER_NO_MATCHES
end

--------------------------------------------------------------------------------
-- Favorites and recent picks (account-wide, in HeraldryDB.ui)
--------------------------------------------------------------------------------
local function IndexOf(list, id)
    for i, value in ipairs(list) do
        if value == id then return i end
    end
end

local function IsFavorite(id)
    return id ~= nil and IndexOf(ns.ui.favoriteIcons, id) ~= nil
end

local RefreshStrips, RefreshCells

local function ToggleFavorite(id)
    local favorites = ns.ui.favoriteIcons
    local index = IndexOf(favorites, id)
    if index then
        table.remove(favorites, index)
    else
        favorites[#favorites + 1] = id
    end
    RefreshStrips()
    RefreshCells()
end

local function RememberRecent(id)
    local recent = ns.ui.recentIcons
    local index = IndexOf(recent, id)
    if index then table.remove(recent, index) end
    table.insert(recent, 1, id)
    recent[MAX_RECENT + 1] = nil
end

--------------------------------------------------------------------------------
-- Selection, preview and choosing
--------------------------------------------------------------------------------
local function UpdatePreview(spec)
    local preview = window.Preview
    if not spec then
        preview.Region:Hide()
        return
    end
    preview.Region:SetIcon(spec)
    wipe(preview.Region.layout)
    ns.Plates.Layout(preview.Region, preview.Name, nil, spec, ns.profile.display)
    preview.Region.texture:SetAlpha(ns.profile.display.alpha)
    preview.Region:Show()
end

-- Library entries may not name the artist; then only the source is shown.
local function CreditText(credit)
    if not credit then return "" end
    if credit.author then
        return L.PICKER_CREDIT:format(credit.author, credit.source)
    end
    return L.PICKER_CREDIT_SOURCE:format(credit.source)
end

local function Select(id, index)
    state.selected, state.selectedIndex = id, index
    local spec = id and Icons:Resolve(id)
    UpdatePreview(spec)
    window.PreviewText:SetText(id and Icons:Describe(id) or L.PICKER_NOTHING_SELECTED)
    local credit = spec and spec.entry and spec.entry.credit
    window.PreviewCredit:SetText(CreditText(credit))
    window.Choose:SetEnabled(id ~= nil)
    RefreshCells()
end

local function Choose(id)
    local onPick = options and options.onPick
    if id and id ~= "none" then RememberRecent(id) end
    window:Hide()
    if id and onPick then onPick(id) end
end

--------------------------------------------------------------------------------
-- Cells (grid rows and the Favorites / Recent strips)
--------------------------------------------------------------------------------
local function CellTooltip(cell)
    local spec = Icons:Resolve(cell.id)
    if not spec then return end
    GameTooltip:SetOwner(cell, "ANCHOR_RIGHT")
    GameTooltip:SetText(spec.label, 1, 1, 1)
    GameTooltip:AddLine(spec.sourceLabel, nil, nil, nil)
    if spec.category then GameTooltip:AddLine(spec.category, 0.8, 0.8, 0.8) end
    local others = Icons.ParseId(cell.id) == "game" and GameIcons:GetOtherNames(spec.texture)
    if others then GameTooltip:AddLine(L.PICKER_ALSO_USED_BY:format(others), 0.8, 0.8, 0.8, true) end
    local entry = spec.entry
    if entry then
        if entry.anim then
            -- fps can be fractional after the tool dropped frames (12.5).
            local fps = ("%.1f"):format(entry.anim.fps):gsub("%.0$", "")
            GameTooltip:AddLine(L.PICKER_TOOLTIP_ANIMATED:format(entry.anim.frames, fps), 0.8, 0.8, 0.8)
        end
        GameTooltip:AddLine(CreditText(entry.credit), 0.8, 0.8, 0.8)
    end
    GameTooltip:AddLine(IsFavorite(cell.id) and L.PICKER_UNFAVORITE_HINT or L.PICKER_FAVORITE_HINT, 0.5, 0.8, 1)
    GameTooltip:AddLine(cell.id, 0.5, 0.5, 0.5)
    GameTooltip:Show()
end

local function PaintSelected(cell)
    cell.Selected:SetShown(cell.id ~= nil and cell.id == state.selected)
    cell.Favorite:SetShown(IsFavorite(cell.id))
end

local function CreateCell(parent, layout)
    local cell = CreateFrame("Button", nil, parent)
    cell:SetSize(layout.cellWidth - 4, layout.cellHeight - 4)
    cell:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    cell.Icon = Widgets.IconBox(cell, layout.iconWidth, layout.iconHeight)
    if layout.label then
        cell.Icon:SetPoint("TOP", 0, -4)
        cell.Label = Widgets.Text(cell, "GameFontHighlightSmall")
        cell.Label:SetPoint("TOPLEFT", cell.Icon, "BOTTOMLEFT", -6, -3)
        cell.Label:SetPoint("TOPRIGHT", cell.Icon, "BOTTOMRIGHT", 6, -3)
        cell.Label:SetJustifyH("CENTER")
        cell.Label:SetMaxLines(1)
    else
        cell.Icon:SetPoint("CENTER")
    end
    cell:SetHighlightTexture([[Interface\Buttons\ButtonHilight-Square]], "ADD")
    cell.Selected = cell:CreateTexture(nil, "OVERLAY")
    cell.Selected:SetTexture([[Interface\Buttons\CheckButtonHilight]])
    cell.Selected:SetBlendMode("ADD")
    cell.Selected:SetAllPoints()
    local r, g, b = Skin:AccentColor()
    if r then cell.Selected:SetVertexColor(r, g, b) end
    allCells[#allCells + 1] = cell
    cell.Favorite = cell:CreateTexture(nil, "OVERLAY", nil, 2)
    cell.Favorite:SetAtlas("PetJournal-FavoritesIcon")
    cell.Favorite:SetSize(12, 12)
    cell.Favorite:SetPoint("TOPRIGHT", -1, -1)
    cell:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            ToggleFavorite(self.id)
            CellTooltip(self)
        else
            Select(self.id, self.index)
        end
    end)
    cell:SetScript("OnDoubleClick", function(self) Choose(self.id) end)
    cell:SetScript("OnEnter", function(self)
        self.Icon:Animate(true)
        CellTooltip(self)
    end)
    cell:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
        self.Icon:Animate(false)
    end)
    return cell
end

-- Shows id in cell (nil hides it); index is its position in the grid's item list.
local function FillCell(cell, id, index)
    cell.id, cell.index = id, index
    if not id then
        cell:Hide()
        return
    end
    local spec = Icons:Resolve(id)
    cell.Icon:SetIcon(id, true)
    if cell.Label then cell.Label:SetText(spec and spec.label or id) end
    PaintSelected(cell)
    cell:Show()
end

local function InitRow(row, element)
    local layout = element.layout
    -- Each grid has one layout, so a pooled row builds its cells once.
    if not row.cells then
        row.cells = {}
        for column = 1, layout.columns do
            local cell = CreateCell(row, layout)
            cell:SetPoint("TOPLEFT", (column - 1) * layout.cellWidth + 2, -2)
            row.cells[column] = cell
        end
    end
    for column, cell in ipairs(row.cells) do
        local index = element.first + column - 1
        local item = state.items[index]
        FillCell(cell, item and ItemId(item), index)
    end
end

function RefreshCells()
    for _, grid in pairs(window.Grids) do
        grid.Box:ForEachFrame(function(row)
            for _, cell in ipairs(row.cells or {}) do PaintSelected(cell) end
        end)
    end
    for _, strip in ipairs(window.Strips) do
        for _, cell in ipairs(strip.cells) do PaintSelected(cell) end
    end
end

local function CreateStrip(label, emptyText, list)
    local strip = CreateFrame("Frame", nil, window)
    strip:SetSize(WINDOW_WIDTH - 36, STRIP.cellHeight)
    strip.Label = Widgets.Text(strip, "GameFontNormalSmall", label)
    strip.Label:SetPoint("LEFT")
    strip.Label:SetWidth(70)
    strip.Empty = Widgets.Text(strip, "GameFontDisableSmall", emptyText)
    strip.Empty:SetPoint("LEFT", 74, 0)
    strip.cells = {}
    for column = 1, STRIP.columns do
        local cell = CreateCell(strip, STRIP)
        cell:SetPoint("LEFT", 72 + (column - 1) * STRIP.cellWidth, 0)
        strip.cells[column] = cell
    end
    strip.list = list
    return strip
end

function RefreshStrips()
    for _, strip in ipairs(window.Strips) do
        local list = strip.list()
        for column, cell in ipairs(strip.cells) do
            local id = list[column]
            FillCell(cell, Icons.IsValidId(id) and id or nil)
        end
        strip.Empty:SetShown(#list == 0)
    end
end

--------------------------------------------------------------------------------
-- Tabs and filling
--------------------------------------------------------------------------------
local function TabInfo(id)
    for _, tab in ipairs(TABS) do
        if tab.id == id then return tab end
    end
end

local function Refill()
    local tab = TabInfo(state.tab)
    local layout = GRIDS[tab.grid]
    state.items = CollectItems()
    local rows = {}
    for first = 1, #state.items, layout.columns do
        rows[#rows + 1] = { first = first, layout = layout }
    end
    for name, grid in pairs(window.Grids) do
        grid:SetShown(name == tab.grid)
    end
    window.Grids[tab.grid]:SetItems(rows, EmptyText())
    window.Hint:SetText(tab.hint)
    window.CustomLink:SetShown(state.tab == "custom")
    window.Category:SetShown(HasCategories())
    if HasCategories() then window.Category:Refresh() end
end

local function SetTab(id)
    -- Category keys belong to one tab: a library theme means nothing on the Twitch tab.
    if state.tab ~= id then state.category = nil end
    state.tab = id
    for _, tab in ipairs(window.Tabs) do
        local selected = tab.id == id
        if selected then PanelTemplates_SelectTab(tab) else PanelTemplates_DeselectTab(tab) end
        Skin:SetTabSelected(tab, selected)
    end
    Refill()
end

--------------------------------------------------------------------------------
-- Keyboard
--------------------------------------------------------------------------------
-- Moves the selection by delta items in the current grid and scrolls it into view.
local function MoveSelection(delta)
    local count = #state.items
    if count == 0 then return end
    local index = state.selectedIndex
    local item = index and state.items[index]
    if not item or ItemId(item) ~= state.selected then
        index = 0
    end
    index = math.max(1, math.min(count, index + delta))
    Select(ItemId(state.items[index]), index)
    local layout = GRIDS[TabInfo(state.tab).grid]
    local row = math.floor((index - 1) / layout.columns) + 1
    window.Grids[TabInfo(state.tab).grid].Box:ScrollToElementDataIndex(row, ScrollBoxConstants.AlignNearest)
end

local KEY_MOVES = { LEFT = -1, RIGHT = 1 }

local function OnKeyDown(self, key)
    if InCombatLockdown() then return end
    local columns = GRIDS[TabInfo(state.tab).grid].columns
    local handled = true
    if key == "ESCAPE" then
        self:Hide()
    elseif KEY_MOVES[key] then
        MoveSelection(KEY_MOVES[key])
    elseif key == "UP" or key == "DOWN" then
        MoveSelection(key == "UP" and -columns or columns)
    elseif key == "ENTER" and state.selected then
        Choose(state.selected)
    else
        handled = false
    end
    self:SetPropagateKeyboardInput(not handled)
end

--------------------------------------------------------------------------------
-- Window
--------------------------------------------------------------------------------
local function OnSearchChanged(box)
    searchGeneration = searchGeneration + 1
    local generation = searchGeneration
    C_Timer.After(SEARCH_DELAY, function()
        if generation ~= searchGeneration or not window:IsShown() then return end
        state.query = box:GetText()
        Refill()
    end)
end

-- The sample name the preview icon sits beside, in the nameplate font when EUI has one.
local function PreviewFont()
    local eui = EllesmereNameplates_NS
    local file = type(eui) == "table" and type(eui.GetFont) == "function" and eui.GetFont()
    return type(file) == "string" and file or STANDARD_TEXT_FONT
end

local function CreatePreview()
    local preview = CreateFrame("Frame", nil, window, "InsetFrameTemplate")
    preview:SetSize(260, 64)
    preview:SetPoint("BOTTOMLEFT", 12, 34)
    Skin:Apply("Inset", preview)
    preview.Name = preview:CreateFontString(nil, "OVERLAY")
    preview.Name:SetFont(PreviewFont(), PREVIEW_FONT_SIZE, "OUTLINE")
    preview.Name:SetTextColor(0.25, 1, 0.25)
    preview.Name:SetText(L.PREVIEW_FRIENDLY_NAME)
    preview.Name:SetPoint("CENTER", 10, 0)
    preview.Region = ns.Plates.NewRegion(preview)
    window.Preview = preview

    window.PreviewText = Widgets.Text(window, "GameFontHighlight")
    window.PreviewText:SetPoint("TOPLEFT", preview, "TOPRIGHT", 12, -6)
    window.PreviewText:SetPoint("RIGHT", window, "RIGHT", -16, 0)
    window.PreviewCredit = Widgets.Text(window, "GameFontDisableSmall")
    window.PreviewCredit:SetPoint("TOPLEFT", window.PreviewText, "BOTTOMLEFT", 0, -4)
    window.PreviewCredit:SetPoint("RIGHT", window.PreviewText, "RIGHT")
end

local function CreateWindow()
    window = CreateFrame("Frame", nil, UIParent, "ButtonFrameTemplate")
    ButtonFrameTemplate_HidePortrait(window)
    window:SetSize(WINDOW_WIDTH, WINDOW_HEIGHT)
    window:SetPoint("CENTER")
    window:SetFrameStrata("DIALOG")
    window:SetToplevel(true)
    window:SetClampedToScreen(true)
    window:SetMovable(true)
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", window.StartMoving)
    window:SetScript("OnDragStop", window.StopMovingOrSizing)
    window:Hide()
    -- Keyboard propagation can't change in combat, so the window only listens for keys
    -- out of combat; the search box's own Escape still works.
    window:SetPropagateKeyboardInput(true)
    window:SetScript("OnKeyDown", OnKeyDown)

    local search = CreateFrame("EditBox", nil, window, "SearchBoxTemplate")
    search:SetSize(220, 20)
    search:SetPoint("TOPLEFT", 18, -32)
    search:HookScript("OnTextChanged", OnSearchChanged)
    search:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        if #state.items == 1 then Select(ItemId(state.items[1]), 1) end
    end)
    window.Search = search

    window.Category = Widgets.Dropdown(window, nil, 150, CategoryOptions,
        function() return state.category or false end,
        function(value)
            state.category = value or nil
            Refill()
        end)
    window.Category:SetPoint("LEFT", search, "RIGHT", 12, 0)
    window.Hint = Widgets.Text(window, "GameFontDisableSmall")
    window.Hint:SetPoint("LEFT", window.Category, "RIGHT", 12, 0)
    window.Hint:SetPoint("RIGHT", window, "RIGHT", -20, 0)
    window.Hint:SetWordWrap(true)

    window.Strips = {
        CreateStrip(L.PICKER_FAVORITES, L.PICKER_FAVORITES_EMPTY, function() return ns.ui.favoriteIcons end),
        CreateStrip(L.PICKER_RECENT, L.PICKER_RECENT_EMPTY, function() return ns.ui.recentIcons end),
    }
    window.Strips[1]:SetPoint("TOPLEFT", 18, -58)
    window.Strips[2]:SetPoint("TOPLEFT", window.Strips[1], "BOTTOMLEFT", 0, -2)

    local inset = window.Inset
    inset:ClearAllPoints()
    inset:SetPoint("TOPLEFT", 10, -164)
    inset:SetPoint("BOTTOMRIGHT", -10, 128)

    window.Tabs = {}
    local previous
    for _, tab in ipairs(TABS) do
        if not tab.available or tab.available() then
            local button = CreateFrame("Button", nil, window, "PanelTopTabButtonTemplate")
            button.id = tab.id
            button:SetText(tab.text)
            PanelTemplates_TabResize(button, 0)
            if previous then
                button:SetPoint("LEFT", previous, "RIGHT", 4, 0)
            else
                button:SetPoint("BOTTOMLEFT", inset, "TOPLEFT", 6, 0)
            end
            button:SetScript("OnClick", function(self) SetTab(self.id) end)
            Skin:Apply("Tab", button)
            window.Tabs[#window.Tabs + 1] = button
            previous = button
        end
    end

    window.Grids = {}
    for name, layout in pairs(GRIDS) do
        local grid = Widgets.List(inset, layout.cellHeight, InitRow, "Frame")
        grid:SetPoint("TOPLEFT", 4, -4)
        grid:SetPoint("BOTTOMRIGHT", -4, 4)
        window.Grids[name] = grid
    end

    window.CustomLink = Widgets.Button(window, L.PICKER_MANAGE_CUSTOM, function()
        window:Hide()
        ns.Options:Open("custom")
    end)
    window.CustomLink:SetPoint("TOPLEFT", inset, "BOTTOMLEFT", 4, -4)

    CreatePreview()

    window.Cancel = Widgets.Button(window, CANCEL, function() window:Hide() end)
    window.Cancel:SetPoint("BOTTOMRIGHT", -12, 8)
    window.Choose = Widgets.Button(window, L.PICKER_CHOOSE, function() Choose(state.selected) end)
    window.Choose:SetPoint("RIGHT", window.Cancel, "LEFT", -6, 0)
    window.None = Widgets.Button(window, L.PICKER_NONE, function() Choose("none") end)
    window.None:SetPoint("BOTTOMLEFT", 12, 8)
    Widgets.AttachTooltip(window.None, L.PICKER_NONE, L.PICKER_NONE_TOOLTIP)

    Skin:Apply("Shell", window)
    Skin:Apply("Inset", inset)
    Skin:Apply("EditBox", search)
    Skin:Apply("CloseButton", window.CloseButton)

    window:SetScript("OnShow", function(self)
        if not InCombatLockdown() then self:EnableKeyboard(true) end
        PlaySound(SOUNDKIT.IG_CHARACTER_INFO_OPEN)
    end)
    window:SetScript("OnHide", function()
        PlaySound(SOUNDKIT.IG_CHARACTER_INFO_CLOSE)
        options = nil
        for _, grid in pairs(window.Grids) do grid:SetItems({}) end
        state.items = {}
        window.Preview.Region:Hide()
        Icons:ForgetGameSpecs()
        GameIcons:ReleaseNames()
    end)

    Skin:OnLooksChanged(function()
        local r, g, b = Skin:AccentColor()
        if not r then return end
        for _, cell in ipairs(allCells) do cell.Selected:SetVertexColor(r, g, b) end
    end)
    ns.RegisterEvent("PLAYER_REGEN_DISABLED", function() window:EnableKeyboard(false) end)
    ns.RegisterEvent("PLAYER_REGEN_ENABLED", function()
        if window:IsShown() then window:EnableKeyboard(true) end
    end)
    ns.Listen("CUSTOM_CHANGED", function()
        if window:IsShown() and state.tab == "custom" then Refill() end
    end)
end

local function TabForIcon(id)
    local source = id and Icons.ParseId(id)
    if source and source ~= "none" and TabInfo(source) and (source ~= "twitch" or Icons.TwitchEmotesLoaded()) then
        return source
    end
    -- Start where there is something to pick.
    if #Icons:GetLibrary() > 0 then return "lib" end
    if Icons.TwitchEmotesLoaded() then return "twitch" end
    return "game"
end

function Picker:Open(openOptions)
    if not window then CreateWindow() end
    options = openOptions
    window:SetTitle(openOptions.subject and L.PICKER_TITLE_FOR:format(openOptions.subject) or L.PICKER_TITLE)
    window.None:SetShown(openOptions.allowNone == true)
    state.query, state.category = "", nil
    -- A Twitch pack may have registered emotes since the list was built.
    if Icons:RefreshTwitchEmotes() then categoryOptions = nil end
    window.Search:SetText("")
    local current = openOptions.current
    if current == "none" then current = nil end
    window:Show()
    window:Raise()
    RefreshStrips()
    SetTab(TabForIcon(current))
    Select(current)
end

function Picker:Close()
    if window then window:Hide() end
end
