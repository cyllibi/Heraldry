--[[ Identity.lua
  Who a rule is about. WoW Forever has no realms: every character lives in one
  region-wide ruleset (PvE, PvP, RP, RP-PvP, Hardcore) and has a first name and a
  surname that together are unique in the region.

  Keys (stored in SavedVariables and export strings, so they never change format):
    guild:  "<ruleset token>/<folded guild name>"   e.g. "pve/kachow"
            Guild names are only unique within a ruleset.
    player: "<folded first name> <folded surname>"   e.g. "somebody stormwind"
            Character names are unique region-wide, so no ruleset prefix.
  Ruleset tokens are fixed ASCII constants, never the client's localized names. ]]

local _, ns = ...
local L = ns.L

local Identity = {}
ns.Identity = Identity

--------------------------------------------------------------------------------
-- Ruleset
--------------------------------------------------------------------------------
-- Enum.GameRule keys that select a ruleset, mapped to the token fragment they add.
-- A future "...Ruleset" flag missing from this table still produces a distinct token
-- (its key, lowercased), so a new ruleset can never collide with an existing one.
local RULESET_FLAGS = {
    HardcoreRuleset = "hc",
    PvPRuleset = "pvp",
    RPRuleset = "rp",
}

-- Sorted flag combinations that have a friendlier token. Anything else keeps the raw
-- "+"-joined combination.
local COMBINED_TOKENS = {
    [""] = "pve",
    ["pvp+rp"] = "rppvp",
}

Identity.KNOWN_RULESETS = { "pve", "pvp", "rp", "rppvp", "hc" }

-- isActive(ruleValue) -> boolean, gameRules: the Enum.GameRule table.
-- Checks every ruleset flag, so RP-PvP is not mistaken for PvP.
function Identity.ComputeRuleset(isActive, gameRules)
    local active = {}
    for key, value in pairs(gameRules) do
        if type(key) == "string" and key:find("Ruleset$") and isActive(value) then
            active[#active + 1] = RULESET_FLAGS[key] or key:gsub("Ruleset$", ""):lower()
        end
    end
    table.sort(active)
    local combined = table.concat(active, "+")
    return COMBINED_TOKENS[combined] or combined
end

local currentRuleset

function Identity:GetRuleset()
    if not currentRuleset then
        currentRuleset = Identity.ComputeRuleset(C_GameRules.IsGameRuleActive, Enum.GameRule)
    end
    return currentRuleset
end

-- Display name of a ruleset token, for the options panel and diagnostics.
function Identity.RulesetName(token)
    return rawget(L, "RULESET_" .. token) or token
end

--------------------------------------------------------------------------------
-- Name folding
--------------------------------------------------------------------------------
-- string.lower only folds ASCII. Forever names allow accented Latin letters, so a typed
-- "élise" must still match the game's "Élise". Fold the two UTF-8 blocks names use:
-- Latin-1 Supplement (U+00C0-U+00DE, except U+00D7) and Latin Extended-A (U+0100-U+017F,
-- where each even code point's lowercase is the next one; U+0178 folds to U+00FF).
local FOLD = {}
do
    local function utf8(code)
        if code < 0x800 then
            return string.char(0xC0 + math.floor(code / 64), 0x80 + code % 64)
        end
    end
    for code = 0xC0, 0xDE do
        if code ~= 0xD7 then FOLD[utf8(code)] = utf8(code + 0x20) end
    end
    for code = 0x100, 0x176, 2 do
        -- U+0130 (dotted I, folds outside the block) is skipped, and the odd-paired runs
        -- U+0139-U+0148 and U+0179-U+017E are handled below; the rest pairs even -> odd.
        if code ~= 0x130 and not (code >= 0x138 and code <= 0x148) then
            FOLD[utf8(code)] = utf8(code + 1)
        end
    end
    for code = 0x139, 0x147, 2 do FOLD[utf8(code)] = utf8(code + 1) end
    for code = 0x179, 0x17D, 2 do FOLD[utf8(code)] = utf8(code + 1) end
    FOLD[utf8(0x178)] = utf8(0xFF)
end

-- Lowercases (ASCII and the Latin blocks above), trims and collapses inner whitespace.
function Identity.Fold(text)
    text = ns.Trim(text):gsub("%s+", " "):lower()
    return (text:gsub("[\195-\197][\128-\191]", FOLD))
end

--------------------------------------------------------------------------------
-- Keys
--------------------------------------------------------------------------------
local function SurnameSeparator()
    return Constants.CharacterNameSeparatorConsts.CHARACTERNAME_SURNAME_SEPARATOR
end

-- "First Surname" as the game shows it, from UnitName's two returns. Some units already
-- carry the surname in the first value; never double it.
function Identity.FullName(name, surname)
    if surname and surname ~= "" then
        local tail = SurnameSeparator() .. surname
        if name:sub(-#tail) ~= tail then
            return name .. tail
        end
    end
    return name
end

function Identity.GuildKey(ruleset, guildName)
    return ruleset .. "/" .. Identity.Fold(guildName)
end

-- Typed names use a space between first name and surname; the game's own separator is
-- normalized to a space too, so both spellings give the same key.
function Identity.PlayerKeyFromText(fullName)
    local separator = SurnameSeparator()
    if separator ~= " " then
        local pattern = separator:gsub("%W", "%%%0")
        fullName = fullName:gsub(pattern, " ")
    end
    return Identity.Fold(fullName)
end

function Identity.PlayerKey(name, surname)
    return Identity.PlayerKeyFromText(Identity.FullName(name, surname))
end

-- "pve/kachow" -> "pve", "kachow".
function Identity.SplitGuildKey(key)
    return key:match("^([^/]+)/(.+)$")
end

--------------------------------------------------------------------------------
-- Cached lookups for the nameplate path. Inputs are plain (non-secret) strings only;
-- callers check that first. Keys are built once per distinct name for the session.
--------------------------------------------------------------------------------
local playerKeyCache = {}   -- [name][surname or ""] = key
local guildKeyCache = {}    -- [guild name] = key (current ruleset)

function Identity:CachedPlayerKey(name, surname)
    local row = playerKeyCache[name]
    if not row then
        row = {}
        playerKeyCache[name] = row
    end
    local slot = surname or ""
    local key = row[slot]
    if not key then
        key = Identity.PlayerKey(name, surname)
        row[slot] = key
    end
    return key
end

function Identity:CachedGuildKey(guildName)
    local key = guildKeyCache[guildName]
    if not key then
        key = Identity.GuildKey(self:GetRuleset(), guildName)
        guildKeyCache[guildName] = key
    end
    return key
end
