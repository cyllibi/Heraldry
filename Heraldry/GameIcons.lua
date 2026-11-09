--[[ GameIcons.lua
  The built-in game icons: the list the macro icon picker shows, and search.

  On Forever the macro icon functions return file IDs only; icon file names are not
  available. Search therefore matches spell names: the first search starts a background
  scan of spell IDs that records each spell's icon under its name. The scan runs a few
  milliseconds per frame while it lasts and stops for good once done. Exact file IDs,
  texture paths, spell names and cached item names also work immediately. ]]

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
local searchText = {} -- file ID -> folded spell names, "\n"-separated
local labels = {}    -- file ID -> a display name (first spell name or loose file name)

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

function GameIcons:GetIconName(fileID)
    return labels[fileID]
end

--------------------------------------------------------------------------------
-- Spell name index
--------------------------------------------------------------------------------
local function IndexSpell(name, icon)
    local folded = ns.Identity.Fold(name)
    local existing = searchText[icon]
    if not existing then
        searchText[icon] = folded
        labels[icon] = labels[icon] or name
        if not inList[icon] then
            inList[icon] = true
            extraIcons[#extraIcons + 1] = icon
        end
    elseif #existing < MAX_NAMES_PER_ICON and not existing:find(folded, 1, true) then
        searchText[icon] = existing .. "\n" .. folded
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
        AddUnique(results, seen, tonumber(query))
        return results
    end
    if query:find("[/\\]") then
        AddUnique(results, seen, GetFileIDFromPath(query) or GetFileIDFromPath(ICON_PATH_PREFIX .. query))
        return results
    end

    -- Exact names first: a spell the player knows, an item in the client's cache.
    AddUnique(results, seen, C_Spell.GetSpellTexture(query))
    AddUnique(results, seen, select(5, C_Item.GetItemInfoInstant(query)))

    self:StartIndex()
    local folded = ns.Identity.Fold(query)
    local function Match(fileID)
        local names = searchText[fileID]
        local label = labels[fileID]
        return (names and names:find(folded, 1, true)) or (label and label:lower():find(folded, 1, true))
    end
    for _, fileID in ipairs(list) do
        if Match(fileID) then AddUnique(results, seen, fileID) end
    end
    for _, fileID in ipairs(extraIcons) do
        if Match(fileID) then AddUnique(results, seen, fileID) end
    end
    return results
end
