--[[ Diagnostics.lua
  The report behind /heraldry check and the Diagnostics box on the options' first page:
  what the game tells add-ons right now about the player and the target, and what
  Heraldry made of it. Secret values are shown as "<hidden>", never compared. ]]

local _, ns = ...
local L = ns.L

local IsSecret = ns.IsSecret

local Diagnostics = {}
ns.Diagnostics = Diagnostics

local function Show(value)
    if IsSecret(value) then return L.CHECK_SECRET end
    if value == nil then return L.CHECK_NIL end
    return tostring(value)
end

local function CountList(counts)
    local parts = {}
    for label, count in pairs(counts) do parts[#parts + 1] = ("%s %d"):format(label, count) end
    table.sort(parts)
    return #parts > 0 and table.concat(parts, ", ") or L.CHECK_NONE
end

-- The report as a list of lines: the client's state, then the target's.
function Diagnostics:Lines()
    local lines = {}
    local function Add(text, ...)
        lines[#lines + 1] = select("#", ...) > 0 and text:format(...) or text
    end

    local adapters = {}
    for _, adapter in ipairs(ns.Plates:GetActiveAdapters()) do adapters[#adapters + 1] = adapter.label end
    local inInstance, instanceType = IsInInstance()
    Add(L.CHECK_ADAPTERS, table.concat(adapters, ", "))
    Add(L.CHECK_RULESET, ns.Identity.RulesetName(ns.Identity:GetRuleset()), ns.Identity:GetRuleset())
    Add(L.CHECK_MY_GUILD, Show(GetGuildInfo("player")))
    Add(L.CHECK_CONTEXT, tostring(InCombatLockdown()), inInstance and instanceType or L.CHECK_OPEN_WORLD)
    local drawn, hiddenBy, hiddenNames = ns.Plates:GetStats()
    Add(L.CHECK_DRAWN, CountList(drawn))
    Add(L.CHECK_HIDDEN_BY, CountList(hiddenBy))
    Add(L.CHECK_HIDDEN_NAMES, hiddenNames)

    if not UnitExists("target") then
        Add(L.CHECK_NO_TARGET)
        return lines
    end
    local facts = ns.Rules:ReadUnit("target")
    if not facts.isPlayer then
        Add(facts.isPlayerSecret and L.TARGET_HIDDEN or L.TARGET_NOT_PLAYER)
    else
        local name = facts.nameSecret and L.CHECK_SECRET or Show(facts.name)
        local surname = facts.nameSecret and L.CHECK_SECRET or Show(facts.surname)
        Add(L.CHECK_NAME, name, surname, facts.playerKey or L.CHECK_NONE)
        Add(L.CHECK_GUILD, facts.guildSecret and L.CHECK_SECRET or Show(facts.guild), facts.guildKey or L.CHECK_NONE)
    end
    Add(L.CHECK_IN_MY_GUILD, Show(UnitIsInMyGuild("target")))
    -- Not on every client build; only this report uses it.
    if C_Secrets and C_Secrets.ShouldUnitIdentityBeSecret then
        Add(L.CHECK_IDENTITY_SECRET, Show(C_Secrets.ShouldUnitIdentityBeSecret("target")))
    end

    if facts.isPlayer or facts.isPlayerSecret then
        local profile = ns.profile
        local inMyGuild -- may be a secret boolean: assigned, never tested here
        if profile.myGuild.enabled then inMyGuild = UnitIsInMyGuild("target") end
        local icon, reason = ns.Rules.Match(profile, facts.playerKey, facts.guildKey, facts.nameSecret, inMyGuild)
        local reasonKey = "REASON_" .. reason:upper():gsub("%-", "_")
        Add(L.CHECK_MATCH, L[reasonKey], icon and ns.Icons:Describe(icon) or L.CHECK_NONE)
        ns.GameIcons:ReleaseNames() -- the label is kept on the spec; the name table isn't needed
    end

    local plate = ns.Plates:Describe("target")
    if not plate then
        Add(L.CHECK_NO_PLATE)
    elseif plate.adapter then
        Add(L.CHECK_PLATE, plate.adapter, tostring(plate.iconShown))
        Add(L.CHECK_BOX, plate.boxWidth and ("%d"):format(plate.boxWidth) or L.CHECK_BOX_NONE)
    elseif plate.hiddenBy then
        Add(L.CHECK_PLATE_HIDDEN, plate.hiddenBy)
    else
        Add(L.CHECK_PLATE_NONE)
    end
    return lines
end
