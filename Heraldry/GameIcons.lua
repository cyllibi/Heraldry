--[[ GameIcons.lua
  The built-in game icons: the list the macro icon picker shows, and search.

  On Forever the macro icon functions return file IDs only; icon file names are not
  available. Names come from two places:
    * IconNames.lua, labels made from the icons' file names (tools\iconnames.py), parsed
      the first time the picker or options need a name and released when the picker closes;
      nameplates never need one
    * the spell index: the first search starts a background scan of spell IDs that
      records each spell's icon under its name. The scan runs a few milliseconds per
      frame while it lasts and stops for good once done.
  A spell name wins over a file label when both exist. Known file IDs, texture paths,
  spell names and cached item names also work immediately. ]]

local _, ns = ...

local GameIcons = {}
ns.GameIcons = GameIcons

local SCAN_BUDGET_MS = 2.5       -- time per frame spent scanning spells (none in combat)
local SCAN_MIN_SPELL_ID = 100000 -- always scan at least this far...
local SCAN_STOP_GAP = 50000      -- ...then stop after this many IDs in a row without a spell
local MAX_NAMES_PER_ICON = 160   -- bytes of spell names kept per icon for search
local ICON_PATH_PREFIX = [[Interface\Icons\]]

local iconList       -- file IDs in macro picker order, built on first use
local inList = {}    -- file ID -> true
local extraIcons = {} -- spell icons the macro list lacks, in scan order
local searchText = {} -- file ID -> folded spell names, each word after a space (see Words)
local labels = {}    -- file ID -> a display name (first spell name or loose file name)
local fileLabels     -- file ID -> " " .. lower-case label from IconNames.lua, built on first use

local scanState = "idle" -- "idle", "running", "done"
local scanSpellID, scanMisses = 0, 0
local scanFrame
local scanListeners = {}

local function AddIcon(list, value)
    local fileID = value
    if type(value) == "string" then
        -- The "loose" lists hold bare file names; try them as written and under Icons.
        local name = value:gsub("%.$", "")
        fileID = GetFileIDFromPath(name) or GetFileIDFromPath(ICON_PATH_PREFIX .. name)
        if fileID and not labels[fileID] then
            labels[fileID] = name:match("([^/\\]+)$")
        end
    end
    if fileID and not inList[fileID] then
        inList[fileID] = true
        list[#list + 1] = fileID
    end
end

-- Built directly rather than through IconDataProviderMixin, which shares its state with
-- Blizzard's macro window and collects every icon texture.
function GameIcons:GetList()
    if not iconList then
        local raw = {}
        GetLooseMacroIcons(raw)
        GetLooseMacroItemIcons(raw)
        GetMacroIcons(raw)
        GetMacroItemIcons(raw)
        iconList = {}
        for _, value in ipairs(raw) do
            AddIcon(iconList, value)
        end
    end
    return iconList
end

-- Parses IconNames.lua's "<delta> <label>" lines into a table (about 17 ms and 4 MB) the
-- first time the picker or the options need a name; ReleaseNames drops the table again.
local function FileLabels()
    if not fileLabels then
        fileLabels = {}
        local fileID = 0
        for delta, label in (ns.IconNamesData or ""):gmatch("(%d+) ([^\n]+)") do
            fileID = fileID + tonumber(delta)
            fileLabels[fileID] = " " .. label
        end
    end
    return fileLabels
end

-- Called when the picker closes; the next name parses the table again.
function GameIcons:ReleaseNames()
    fileLabels = nil
end

-- For tests and diagnostics: whether the name table is parsed right now.
function GameIcons:HasNames()
    return fileLabels ~= nil
end

-- Spell name first, then the file name label, then a loose macro icon's raw file name.
function GameIcons:GetIconName(fileID)
    local label = labels[fileID]
    if label and searchText[fileID] then return label end
    local fileLabel = FileLabels()[fileID]
    if fileLabel then return (fileLabel:gsub("^ (%l?)", string.upper)) end
    return label
end

-- True when fileID is an icon Heraldry knows about, not just any number.
function GameIcons:IsKnownIcon(fileID)
    self:GetList()
    return inList[fileID] or FileLabels()[fileID] ~= nil
end

--------------------------------------------------------------------------------
-- Spell name index
--------------------------------------------------------------------------------
-- " word word": folded, with hyphens as spaces, so search can match the start of each word.
local function Words(text)
    return " " .. ns.Identity.Fold(text):gsub("%-", " ")
end

local function IndexSpell(name, icon)
    local words = Words(name)
    local existing = searchText[icon]
    if not existing then
        searchText[icon] = words
        labels[icon] = name -- the first spell's name beats a loose icon's file name
        if not inList[icon] then
            inList[icon] = true
            extraIcons[#extraIcons + 1] = icon
        end
    elseif #existing < MAX_NAMES_PER_ICON and not (existing .. " "):find(words .. " ", 1, true) then
        searchText[icon] = existing .. words
    end
end

local function ScanStep(frame)
    if InCombatLockdown() then return end
    local started = debugprofilestop()
    local GetSpellName, GetSpellTexture = C_Spell.GetSpellName, C_Spell.GetSpellTexture
    repeat
        scanSpellID = scanSpellID + 1
        local name = GetSpellName(scanSpellID)
        if name then
            scanMisses = 0
            local icon = GetSpellTexture(scanSpellID)
            if icon and name ~= "" then IndexSpell(name, icon) end
        else
            scanMisses = scanMisses + 1
            if scanSpellID > SCAN_MIN_SPELL_ID and scanMisses > SCAN_STOP_GAP then
                scanState = "done"
                frame:SetScript("OnUpdate", nil)
                ns.Icons:ForgetGameSpecs()
                break
            end
        end
    until debugprofilestop() - started > SCAN_BUDGET_MS
    for _, listener in ipairs(scanListeners) do
        listener(scanState == "done")
    end
end

-- listener(done) runs after every scan step until the index is complete.
function GameIcons:OnIndexProgress(listener)
    scanListeners[#scanListeners + 1] = listener
end

function GameIcons:StartIndex()
    if scanState ~= "idle" then return end
    self:GetList()
    scanState = "running"
    scanFrame = scanFrame or CreateFrame("Frame")
    scanFrame:SetScript("OnUpdate", ScanStep)
end

function GameIcons:IsIndexing()
    return scanState == "running"
end

-- Spell IDs scanned so far, for the progress text.
function GameIcons:GetIndexProgress()
    return scanSpellID
end

--------------------------------------------------------------------------------
-- Search
--------------------------------------------------------------------------------
local function AddUnique(results, seen, fileID)
    if fileID and not seen[fileID] then
        seen[fileID] = true
        results[#results + 1] = fileID
    end
end

-- Returns a list of file IDs. An empty query returns the whole list.
function GameIcons:Search(query)
    local list = self:GetList()
    query = ns.Trim(query or "")
    if query == "" then return list end

    local results, seen = {}, {}
    if query:match("^%d+$") then
        -- Only a real icon: any other number would show the missing-texture square.
        local fileID = tonumber(query)
        if self:IsKnownIcon(fileID) then AddUnique(results, seen, fileID) end
        return results
    end
    if query:find("[/\\]") then
        AddUnique(results, seen, GetFileIDFromPath(query) or GetFileIDFromPath(ICON_PATH_PREFIX .. query))
        return results
    end

    -- Exact names first: a spell the player knows, an item in the client's cache.
    AddUnique(results, seen, C_Spell.GetSpellTexture(query))
    AddUnique(results, seen, select(5, C_Item.GetItemInfoInstant(query)))

    -- Then every icon whose spell names or file label have a word starting with each
    -- query word, as in the library ("ice" finds Ice Lance, not Sacrifice).
    self:StartIndex()
    local words = {}
    for word in Words(query):gmatch("[^ ]+") do words[#words + 1] = " " .. word end
    local files = FileLabels()
    local function HasWords(text)
        if not text then return false end
        for _, word in ipairs(words) do
            if not text:find(word, 1, true) then return false end
        end
        return true
    end
    local function Match(fileID)
        if HasWords(searchText[fileID]) or HasWords(files[fileID]) then return true end
        -- A loose macro icon the listfile doesn't name: its raw file name, underscores as spaces.
        local label = not files[fileID] and labels[fileID]
        return label and HasWords(Words((label:gsub("_", " ")))) or false
    end
    for _, fileID in ipairs(list) do
        if Match(fileID) then AddUnique(results, seen, fileID) end
    end
    for _, fileID in ipairs(extraIcons) do
        if Match(fileID) then AddUnique(results, seen, fileID) end
    end
    return results
end
