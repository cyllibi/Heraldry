--[[ Database.lua
  SavedVariables, defaults, profiles and migrations.

    HeraldryDB     = { version =, profile = {...}, ui = {...} }       account-wide
    HeraldryCharDB = { version =, useCharacter =, profile = {...}|nil } this character

  ns.profile is the active profile (rules and display). ns.ui holds picker conveniences
  (favorite and recent icons) and the minimap button's state, always account-wide.

  ns.profile is replaced when "Use settings for this character only" toggles, so no
  module may keep a reference to it (or to its sub-tables) across calls: read ns.profile
  each time. PROFILE_CHANGED fires after every switch.

  Turning the character profile on copies the account profile, unless the character
  already has a copy from an earlier time; turning it off goes back to the account
  profile and keeps the character copy for later. ]]

local _, ns = ...

local DB = {}
ns.DB = DB

DB.VERSION = 1

local MAX_FAVORITES = 100
local MAX_RECENT_ICONS = 12

DB.POSITIONS = { "LEFT", "RIGHT", "TOP", "BOTTOM" }
local VALID_POSITION = { LEFT = true, RIGHT = true, TOP = true, BOTTOM = true }

-- Slider ranges for the numeric display options (used by the options page too).
DB.RANGES = {
    scale = { min = 0.5, max = 3, step = 0.05 },
    alpha = { min = 0.2, max = 1, step = 0.05 },
    gap = { min = 0, max = 20, step = 1 },
    x = { min = -60, max = 60, step = 1 },
    y = { min = -60, max = 60, step = 1 },
}

local DISPLAY_DEFAULTS = {
    enabled = true,       -- master switch
    friendly = true,      -- show on friendly plates
    enemy = true,         -- show on enemy plates
    position = "TOP",     -- where the icon goes: above the name (Blizzard's plates keep the left for buffs)
    scale = 1,            -- icon height as a multiple of the name's font size
    alpha = 1,
    gap = 2,              -- pixels between the icon and the name
    x = 0,
    y = 0,
    -- Where icons show. Instances restrict nameplates; some players want icons only in town.
    world = true,
    dungeon = true,
    raid = true,
    pvp = true,
    hideInCombat = false,
    -- When the game hides a player's name, a player rule can't be checked. Off: guild
    -- icons still show (and a "none" rule for that player is not applied). On: nothing shows.
    strictPlayers = false,
    -- Plates from a nameplate add-on Heraldry has no adapter for: icon above the plate.
    unknownPlates = true,
    -- Blizzard's plates with a health bar: a taller icon spanning the name and the bar.
    tallBlizzard = false,
}
DB.DISPLAY_DEFAULTS = DISPLAY_DEFAULTS

--------------------------------------------------------------------------------
-- Migrations: DB.migrations[n] upgrades a store from version n-1 to n. Each step must be
-- safe to run on any older store; the version is stamped after each step succeeds.
-- Version 1 is the first format, so there are no steps yet.
--------------------------------------------------------------------------------
DB.migrations = {}

function DB.Migrate(store)
    local version = tonumber(store.version) or 0
    if version > DB.VERSION then
        -- Written by a newer Heraldry: keep it as is rather than guess at a downgrade.
        return false
    end
    for step = version + 1, DB.VERSION do
        local migrate = DB.migrations[step]
        if migrate then migrate(store) end
        store.version = step
    end
    return true
end

--------------------------------------------------------------------------------
-- Normalization: SavedVariables can be hand-edited or written by an older build, so
-- every field is checked and repaired, never trusted.
--------------------------------------------------------------------------------
local function NormalizeRules(rules, allowNone)
    if type(rules) ~= "table" then return {} end
    for key, rule in pairs(rules) do
        local valid = type(key) == "string" and type(rule) == "table" and type(rule.name) == "string"
            and rule.name ~= "" and ns.Icons.IsValidId(rule.icon, allowNone)
        if not valid then
            rules[key] = nil
        end
    end
    return rules
end

local function NormalizeDisplay(display)
    if type(display) ~= "table" then display = {} end
    for key, default in pairs(DISPLAY_DEFAULTS) do
        if type(display[key]) ~= type(default) then
            display[key] = default
        end
    end
    for key, range in pairs(DB.RANGES) do
        display[key] = ns.Clamp(display[key], range.min, range.max)
    end
    if not VALID_POSITION[display.position] then
        display.position = DISPLAY_DEFAULTS.position
    end
    return display
end

-- Picker favorite and recent icons: valid, distinct icon ids, at most `limit` of them.
local function NormalizeIconList(list, limit)
    local result, seen = {}, {}
    if type(list) == "table" then
        for _, id in ipairs(list) do
            if #result < limit and ns.Icons.IsValidId(id) and not seen[id] then
                seen[id] = true
                result[#result + 1] = id
            end
        end
    end
    return result
end

function DB.NormalizeProfile(profile)
    if type(profile) ~= "table" then profile = {} end

    local myGuild = type(profile.myGuild) == "table" and profile.myGuild or {}
    myGuild.enabled = myGuild.enabled == true
    if not ns.Icons.IsValidId(myGuild.icon) then myGuild.icon = nil end
    profile.myGuild = myGuild

    profile.guilds = NormalizeRules(profile.guilds, false)
    profile.players = NormalizeRules(profile.players, true)

    local custom, seen = {}, {}
    if type(profile.custom) == "table" then
        for _, file in ipairs(profile.custom) do
            local parsed = ns.Icons.ParseCustomName(file)
            if parsed and not seen[parsed.file] then
                seen[parsed.file] = true
                custom[#custom + 1] = parsed.file
            end
        end
    end
    profile.custom = custom

    profile.display = NormalizeDisplay(profile.display)
    return profile
end

function DB.NormalizeUI(ui)
    if type(ui) ~= "table" then ui = {} end
    ui.favoriteIcons = NormalizeIconList(ui.favoriteIcons, MAX_FAVORITES)
    ui.recentIcons = NormalizeIconList(ui.recentIcons, MAX_RECENT_ICONS)
    -- The minimap button, in LibDBIcon's format: hide, and the angle around the minimap.
    local minimap = type(ui.minimap) == "table" and ui.minimap or {}
    minimap.hide = minimap.hide == true
    if type(minimap.minimapPos) ~= "number" then minimap.minimapPos = nil end
    ui.minimap = minimap
    return ui
end

function DB.NewProfile()
    return DB.NormalizeProfile({})
end

--------------------------------------------------------------------------------
-- Loading and switching
--------------------------------------------------------------------------------
local account, character

-- A store written by a newer Heraldry may hold things this version can't read (a new icon
-- source, say); normalizing it would delete them at logout. Such a store is left exactly
-- as saved and this session works on a copy, which is never written back.
local function Open(saved)
    if DB.Migrate(saved) then return saved, false end
    return CopyTable(saved), true
end

-- Runs on ADDON_LOADED, when the client has put the saved tables in place.
function DB:Load()
    if type(HeraldryDB) ~= "table" then HeraldryDB = {} end
    if type(HeraldryCharDB) ~= "table" then HeraldryCharDB = {} end
    local newerAccount, newerCharacter
    account, newerAccount = Open(HeraldryDB)
    character, newerCharacter = Open(HeraldryCharDB)
    -- True when this session's changes won't be saved; Core tells the player once.
    self.newerData = newerAccount or newerCharacter

    account.profile = DB.NormalizeProfile(account.profile)
    -- Picker conveniences (favorite and recent icons) are not rules: always account-wide,
    -- whatever profile is active.
    account.ui = DB.NormalizeUI(account.ui)
    ns.ui = account.ui
    character.useCharacter = character.useCharacter == true
    if character.profile ~= nil then
        character.profile = DB.NormalizeProfile(character.profile)
    end
    self:Activate()
end

function DB:Activate()
    if character.useCharacter then
        if not character.profile then
            character.profile = CopyTable(account.profile)
        end
        ns.profile = character.profile
    else
        ns.profile = account.profile
    end
end

function DB:UsesCharacterProfile()
    return character.useCharacter
end

function DB:SetUseCharacterProfile(enabled)
    enabled = enabled == true
    if character.useCharacter == enabled then return end
    character.useCharacter = enabled
    self:Activate()
    ns.Fire("PROFILE_CHANGED")
end

-- "Copy account settings into this character now".
function DB:CopyAccountToCharacter()
    character.profile = CopyTable(account.profile)
    self:Activate()
    ns.Fire("PROFILE_CHANGED")
end

function DB:ResetDisplay()
    local display = ns.profile.display
    for key, value in pairs(DISPLAY_DEFAULTS) do
        display[key] = value
    end
    ns.Fire("DISPLAY_CHANGED")
end

function DB:SetDisplay(key, value)
    local range = DB.RANGES[key]
    if range then value = ns.Clamp(value, range.min, range.max) end
    ns.profile.display[key] = value
    ns.Fire("DISPLAY_CHANGED")
end
