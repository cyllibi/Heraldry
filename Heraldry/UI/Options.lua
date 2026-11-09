--[[ UI\Options.lua
  The options panel: a canvas category under Game Menu > Options > AddOns, one
  subcategory per page. Rule lists, the icon grid and the live preview don't fit
  Blizzard's vertical layout, so every page is a canvas built from stock templates
  (UI\Widgets.lua).

  Page files call Options:AddPage(id, title, build) at load. A page's content is built
  on first show; afterwards page:Refresh() re-reads the profile, on show and whenever
  the profile, rules or display settings change while it is visible.

  With EllesmereUI loaded, the same pages also appear in EUI's own options window as a
  "Heraldry" section (EllesmereUI\PLUGINS_API.md), built by the same page functions.

  Blizzard's Settings panel can't open in combat, so an open requested in combat waits
  for the end of combat. ]]

local _, ns = ...
local L = ns.L
local Widgets = ns.Widgets

local Options = {}
ns.Options = Options

local PAGE_ORDER = { "general", "guilds", "players", "display", "sharing", "custom" }
local PAGE_PADDING = 16
local HEADER_HEIGHT = 58
local PLUGIN_PAGE_HEIGHT = 560   -- EUI scrolls its pages; ours have a fixed layout

local pages = {}
local pluginHosts = {}           -- pages built inside EllesmereUI's window
local rootCategory
local pendingOpen
local lastPageId     -- the Heraldry page shown last, where the minimap button reopens

--------------------------------------------------------------------------------
-- Pages
--------------------------------------------------------------------------------
local PageMixin = {}

function PageMixin:AddRefresh(refresh)
    self.refreshers[#self.refreshers + 1] = refresh
end

function PageMixin:Refresh()
    if not self.built then return end
    self.ProfileCheck:Refresh()
    for _, refresh in ipairs(self.refreshers) do
        refresh()
    end
end

-- Settings calls these on canvas frames; Heraldry saves as it goes, so commit and
-- refresh need nothing. Defaults resets this page's own settings where it has any.
function PageMixin:OnCommit() end
function PageMixin:OnRefresh() end
function PageMixin:OnDefault()
    if self.onDefault then self.onDefault() end
end

local function AddProfileCheck(page)
    page.ProfileCheck = Widgets.Checkbox(page, L.PROFILE_CHARACTER, L.PROFILE_CHARACTER_TOOLTIP,
        function() return ns.DB:UsesCharacterProfile() end,
        function(checked) ns.DB:SetUseCharacterProfile(checked) end)
    page.ProfileCheck:SetPoint("TOPRIGHT", page, "TOPRIGHT",
        -(PAGE_PADDING + page.ProfileCheck.Label:GetStringWidth() + 4), -PAGE_PADDING + 2)
end

local function BuildPage(page)
    page.built = true
    page.Title = Widgets.Text(page, "GameFontHighlightHuge", page.title)
    page.Title:SetPoint("TOPLEFT", PAGE_PADDING, -PAGE_PADDING)
    AddProfileCheck(page)

    page.Divider = page:CreateTexture(nil, "ARTWORK")
    page.Divider:SetAtlas("Options_HorizontalDivider", true)
    page.Divider:SetPoint("TOPLEFT", PAGE_PADDING, -(HEADER_HEIGHT - 12))
    page.Divider:SetPoint("TOPRIGHT", -PAGE_PADDING, -(HEADER_HEIGHT - 12))

    page.Content = CreateFrame("Frame", nil, page)
    page.Content:SetPoint("TOPLEFT", PAGE_PADDING, -HEADER_HEIGHT)
    page.Content:SetPoint("BOTTOMRIGHT", -PAGE_PADDING, PAGE_PADDING)
    page.build(page, page.Content)
end

function Options:AddPage(id, title, build)
    local page = Mixin(CreateFrame("Frame"), PageMixin)
    page:Hide()
    page.id, page.title, page.build, page.refreshers = id, title, build, {}
    page:SetScript("OnShow", function(shown)
        lastPageId = shown.id
        if not shown.built then BuildPage(shown) end
        shown:Refresh()
    end)
    pages[id] = page
    return page
end

local function RefreshVisiblePages()
    for _, page in pairs(pages) do
        if page:IsVisible() then page:Refresh() end
    end
    for _, host in ipairs(pluginHosts) do
        if host:IsVisible() then host:Refresh() end
    end
end
ns.Listen("PROFILE_CHANGED", RefreshVisiblePages)
ns.Listen("RULES_CHANGED", RefreshVisiblePages)
ns.Listen("DISPLAY_CHANGED", RefreshVisiblePages)
ns.Listen("CUSTOM_CHANGED", RefreshVisiblePages)
ns.Listen("UI_CHANGED", RefreshVisiblePages)

--------------------------------------------------------------------------------
-- Registration and opening
--------------------------------------------------------------------------------
ns.RegisterEvent("PLAYER_LOGIN", function()
    local root = pages[PAGE_ORDER[1]]
    rootCategory = Settings.RegisterCanvasLayoutCategory(root, L.ADDON_TITLE)
    root.category = rootCategory
    for i = 2, #PAGE_ORDER do
        local page = pages[PAGE_ORDER[i]]
        page.category = Settings.RegisterCanvasLayoutSubcategory(rootCategory, page, page.title)
    end
    Settings.RegisterAddOnCategory(rootCategory)
end)

--------------------------------------------------------------------------------
-- EllesmereUI plugin section: the same pages, in EUI's window. EUI titles the page, so
-- the host only carries the profile checkbox and the page's content. Display is its own
-- module because EUI's footer Reset belongs to a module: there it resets the Display
-- settings and nothing else, as the Settings panel's Defaults does on the Display page.
--------------------------------------------------------------------------------
local PLUGIN_MODULES = {
    { key = "Rules", title = L.ADDON_TITLE, pages = { "general", "guilds", "players", "sharing", "custom" } },
    { key = "Display", title = L.PAGE_DISPLAY, pages = { "display" },
        onReset = function() ns.DB:ResetDisplay() end },
}

-- EUI shows "General" for the root page; the Settings panel titles it "Heraldry".
local function PluginPageName(id)
    return id == "general" and L.PAGE_GENERAL or pages[id].title
end

local function PageByPluginName(pageName)
    for _, id in ipairs(PAGE_ORDER) do
        if PluginPageName(id) == pageName then return pages[id] end
    end
end

local function BuildPluginPage(pageName, parent, yOffset)
    local source = PageByPluginName(pageName)
    local host = Mixin(CreateFrame("Frame", nil, parent), PageMixin)
    host.refreshers, host.built = {}, true
    host:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, yOffset)
    host:SetPoint("RIGHT", parent, "RIGHT")
    host:SetHeight(PLUGIN_PAGE_HEIGHT)
    AddProfileCheck(host)
    host.Content = CreateFrame("Frame", nil, host)
    host.Content:SetPoint("TOPLEFT", PAGE_PADDING, -(PAGE_PADDING + 30))
    host.Content:SetPoint("BOTTOMRIGHT", -PAGE_PADDING, PAGE_PADDING)
    source.build(host, host.Content)
    host:SetScript("OnShow", host.Refresh)
    pluginHosts[#pluginHosts + 1] = host
    host:Refresh()
    return PLUGIN_PAGE_HEIGHT - yOffset
end

if EllesmereUI and EllesmereUI.RegisterPlugin then
    ns.RegisterEvent("PLAYER_LOGIN", function()
        local modules = {}
        for _, spec in ipairs(PLUGIN_MODULES) do
            local names = {}
            for _, id in ipairs(spec.pages) do names[#names + 1] = PluginPageName(id) end
            modules[#modules + 1] = {
                key = spec.key,
                title = spec.title,
                description = L.PLUGIN_DESCRIPTION,
                pages = names,
                buildPage = BuildPluginPage,
                onPageCacheRestore = RefreshVisiblePages,
                onReset = spec.onReset,
                -- Pages build real widgets and read the profile; keep them out of EUI's
                -- hidden search pre-build.
                searchPrebuild = false,
            }
        end
        EllesmereUI.RegisterPlugin("Heraldry", { label = L.ADDON_TITLE, modules = modules })
    end)
end

ns.RegisterEvent("PLAYER_REGEN_ENABLED", function()
    if pendingOpen then
        local pageId = pendingOpen
        pendingOpen = nil
        Options:Open(pageId)
    end
end)

function Options:Open(pageId)
    local page = pages[pageId or "general"] or pages.general
    if InCombatLockdown() then
        if not pendingOpen then ns.Print(L.OPEN_AFTER_COMBAT) end
        pendingOpen = page.id
        return
    end
    Settings.OpenToCategory(page.category:GetID())
end

-- The minimap button and the compartment: close the Settings panel when it shows a Heraldry
-- page (in combat too: closing is allowed, and a pending open would bring it back after),
-- else open it at the page used last.
function Options:Toggle()
    if SettingsPanel and SettingsPanel:IsShown() then
        for _, page in pairs(pages) do
            if page:IsVisible() then
                pendingOpen = nil
                if SettingsPanel.Close then
                    SettingsPanel:Close(true)
                else
                    HideUIPanel(SettingsPanel)
                end
                return
            end
        end
    end
    self:Open(lastPageId)
end

--------------------------------------------------------------------------------
-- Rule editing flows shared by the pages and the slash commands
--------------------------------------------------------------------------------
-- Opens the picker for a rule; picking an icon creates or updates it.
function Options:EditRule(kind, key, name)
    local rule = ns.Rules:Get(kind, key)
    ns.IconPicker:Open({
        subject = name,
        current = rule and rule.icon,
        allowNone = kind == "players",
        onPick = function(icon) ns.Rules:Set(kind, key, name, icon) end,
    })
end

-- The same for the current target's guild or the target. Returns false and a message
-- when the target can't be used.
function Options:EditTargetRule(kind)
    local key, nameOrError = ns.Rules:TargetSubject(kind)
    if not key then return false, nameOrError end
    self:EditRule(kind, key, nameOrError)
    return true
end

function Options:EditMyGuild()
    local myGuild = ns.profile.myGuild
    ns.IconPicker:Open({
        subject = ns.Rules:GetMyGuildName() or L.MY_GUILD,
        current = myGuild.icon,
        onPick = function(icon) ns.Rules:SetMyGuild(true, icon) end,
    })
end
