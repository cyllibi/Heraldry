--[[ Matching.lua
  Which icon a player gets, and the rule edits the options and slash commands make.

  Order, first match wins:
    1. a player rule for the character: an icon, or "none" (no icon, guild icon hidden)
    2. a guild rule for the unit's guild in the current ruleset
    3. the "my guild" rule, if enabled, for members of the current character's guild
  A name or guild the client hands back as a secret value can't be looked up, so that
  step is skipped. "My guild" still works with a secret UnitIsInMyGuild result: it is
  passed on, untouched, for SetAlphaFromBoolean. ]]

local _, ns = ...
local L = ns.L

local Rules = {}
ns.Rules = Rules

local IsSecret = ns.IsSecret
local Identity = ns.Identity

local MAX_RECENT = 50

--------------------------------------------------------------------------------
-- Pure matching
--------------------------------------------------------------------------------
-- playerKey / guildKey: nil when unknown or unreadable. nameHidden: the name was secret.
-- inMyGuild: boolean, secret boolean, or nil when "my guild" is off or unknown.
-- Returns icon id, reason, secretShow (the secret boolean when the result depends on it).
function Rules.Match(profile, playerKey, guildKey, nameHidden, inMyGuild)
    if playerKey then
        local rule = profile.players[playerKey]
        if rule then
            if rule.icon == "none" then return nil, "player-none" end
            return rule.icon, "player"
        end
    elseif nameHidden and profile.display.strictPlayers then
        return nil, "name-hidden"
    end
    if guildKey then
        local rule = profile.guilds[guildKey]
        if rule then return rule.icon, "guild" end
    end
    local myGuild = profile.myGuild
    if myGuild.enabled and myGuild.icon then
        -- IsSecret first: even comparing a secret with nil throws.
        if IsSecret(inMyGuild) then
            return myGuild.icon, "my-guild-secret", inMyGuild
        elseif inMyGuild then
            return myGuild.icon, "my-guild"
        end
    end
    return nil, "no-rule"
end

--------------------------------------------------------------------------------
-- Units
--------------------------------------------------------------------------------
-- Everything the client exposes about a unit's identity, as plain values where it can.
-- Shared by matching, the recently-seen list and /heraldry check. `facts` (optional) is
-- a table to fill, so the per-plate path allocates nothing.
function Rules:ReadUnit(unit, facts)
    if facts then wipe(facts) else facts = {} end
    local isPlayer = UnitIsPlayer(unit)
    facts.isPlayerSecret = IsSecret(isPlayer)
    facts.isPlayer = not facts.isPlayerSecret and isPlayer or false
    if facts.isPlayerSecret then
        -- Who this is can't be read at all, so neither can name or guild.
        facts.nameSecret, facts.guildSecret = true, true
        return facts
    end
    if not facts.isPlayer then return facts end

    local isSelf = UnitIsUnit(unit, "player")
    facts.isSelf = not IsSecret(isSelf) and isSelf or false

    local name, surname = UnitName(unit)
    facts.nameSecret = IsSecret(name) or IsSecret(surname)
    if not facts.nameSecret and name then
        facts.name, facts.surname = name, surname
        facts.fullName = Identity.FullName(name, surname)
        facts.playerKey = Identity:CachedPlayerKey(name, surname)
    end

    local guild = GetGuildInfo(unit)
    facts.guildSecret = IsSecret(guild)
    if not facts.guildSecret and guild then
        facts.guild = guild
        facts.guildKey = Identity:CachedGuildKey(guild)
    end
    return facts
end

local scratchFacts = {}

-- The icon for a nameplate unit: id, reason, secretShow, nameHidden. Nil id: show nothing.
-- When even UnitIsPlayer is secret, only "my guild" can still decide (UnitIsInMyGuild is
-- false for NPCs), so that path stays open.
function Rules:ResolveUnit(unit, profile)
    local facts = self:ReadUnit(unit, scratchFacts)
    if facts.isSelf or not (facts.isPlayer or facts.isPlayerSecret) then return nil, "not-player" end
    self:NoteSeen(facts)
    local inMyGuild
    if profile.myGuild.enabled then
        inMyGuild = UnitIsInMyGuild(unit)
    end
    local icon, reason, secretShow = Rules.Match(profile, facts.playerKey, facts.guildKey, facts.nameSecret, inMyGuild)
    return icon, reason, secretShow, facts.nameSecret
end

--------------------------------------------------------------------------------
-- Recently seen (this session): plain names and guilds from plates, so the options can
-- offer them instead of making the player type them.
--------------------------------------------------------------------------------
-- Lists: newest first, at most MAX_RECENT each; `listed` makes the per-plate check O(1).
-- `known` holds every key seen this session, uncapped, so a rule's "seen" dot stays after
-- the list drops it.
local recentGuilds, recentPlayers = {}, {}
local listed = { [recentGuilds] = {}, [recentPlayers] = {} }
local known = { [recentGuilds] = {}, [recentPlayers] = {} }

local function Remember(list, key, name)
    local inList = listed[list]
    if inList[key] then return end
    inList[key] = true
    known[list][key] = true
    table.insert(list, 1, { key = key, name = name })
    local dropped = list[MAX_RECENT + 1]
    if dropped then
        inList[dropped.key] = nil
        list[MAX_RECENT + 1] = nil
    end
end

function Rules:NoteSeen(facts)
    if facts.guildKey then Remember(recentGuilds, facts.guildKey, facts.guild) end
    if facts.playerKey then Remember(recentPlayers, facts.playerKey, facts.fullName) end
end

function Rules:GetRecent(kind)
    return kind == "guilds" and recentGuilds or recentPlayers
end

-- Whether a rule's guild or player was on a nameplate this session (rule lists mark it).
function Rules:WasSeen(kind, key)
    return known[kind == "guilds" and recentGuilds or recentPlayers][key] == true
end

--------------------------------------------------------------------------------
-- Edits. kind is "guilds" or "players".
--------------------------------------------------------------------------------
function Rules:Set(kind, key, name, icon)
    ns.profile[kind][key] = { name = name, icon = icon }
    ns.Fire("RULES_CHANGED")
end

function Rules:Remove(kind, key)
    local rule = ns.profile[kind][key]
    ns.profile[kind][key] = nil
    ns.Fire("RULES_CHANGED")
    return rule
end

function Rules:Get(kind, key)
    return ns.profile[kind][key]
end

function Rules:SetMyGuild(enabled, icon)
    local myGuild = ns.profile.myGuild
    myGuild.enabled = enabled
    if icon ~= nil then myGuild.icon = icon end
    ns.Fire("RULES_CHANGED")
end

-- Key and display name for typed text; nil, nil, error for unusable input; a fourth
-- value is a warning to show while still accepting the name.
function Rules.KeyForText(kind, text)
    text = ns.Trim(text or ""):gsub("%s+", " ")
    if text == "" then return nil, nil, L.ERROR_EMPTY_NAME end
    if text:find("[/%c]") or #text > 64 then return nil, nil, L.ERROR_BAD_NAME end
    if kind == "guilds" then
        return Identity.GuildKey(Identity:GetRuleset(), text), text
    end
    -- Forever characters normally carry a surname, and a first name alone won't match
    -- them; but the client allows an empty surname (EllesmereUI handles that case), so
    -- this is a warning, not a refusal.
    local key = Identity.PlayerKeyFromText(text)
    if not key:find(" ", 1, true) then return key, text, nil, L.WARN_NO_SURNAME end
    return key, text
end

-- The current target as a rule subject. Returns key, display name, or nil, message.
function Rules:TargetSubject(kind)
    if not UnitExists("target") then return nil, L.TARGET_NONE end
    local facts = self:ReadUnit("target")
    if facts.isPlayerSecret then return nil, L.TARGET_HIDDEN end
    if not facts.isPlayer then return nil, L.TARGET_NOT_PLAYER end
    if kind == "guilds" then
        if facts.guildSecret then return nil, L.TARGET_GUILD_HIDDEN end
        if not facts.guild then return nil, L.TARGET_NO_GUILD end
        return facts.guildKey, facts.guild
    end
    if facts.isSelf then return nil, L.TARGET_SELF end
    if facts.nameSecret or not facts.playerKey then return nil, L.TARGET_NAME_HIDDEN end
    return facts.playerKey, facts.fullName
end

-- The current character's guild name, or nil.
function Rules:GetMyGuildName()
    local guild = GetGuildInfo("player")
    if IsSecret(guild) then return nil end
    return guild
end
