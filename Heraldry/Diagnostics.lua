--[[ Diagnostics.lua
  The report behind /heraldry check and the Diagnostics box on the options' first page:
  what the game tells add-ons right now about the player and the target, and what
  Heraldry made of it. Secret values are shown as "<hidden>", never compared.

  /heraldry outline draws translucent boxes over the parts of the target's Blizzard
  nameplate that Heraldry places icons against (name, health bar, debuff row, raid
  marker) for a few seconds, so their real positions can be seen in game without
  needing debuffs or a raid marker up. ]]

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

--------------------------------------------------------------------------------
-- /heraldry outline
--------------------------------------------------------------------------------
local OUTLINE_SECONDS = 15
local OUTLINE_PARTS = {
    -- key, colour, how to find it on a Blizzard UnitFrame
    { "OUTLINE_NAME", { 1, 0.2, 0.2 }, function(f) return f.name end },
    { "OUTLINE_BAR", { 0.2, 1, 0.2 }, function(f) return f.HealthBarsContainer end },
    { "OUTLINE_DEBUFFS", { 0.3, 0.5, 1 }, function(f) return f.AurasFrame and f.AurasFrame.DebuffListFrame end },
    { "OUTLINE_RAID", { 1, 1, 0.2 }, function(f) return f.RaidTargetFrame end },
}
local outlineBoxes = {}   -- textures in use, hidden again by the timer
local outlinePools = setmetatable({}, { __mode = "k" }) -- unit frame -> its boxes, reused
local outlineGeneration = 0

local function Size(region, method)
    if not (region and region[method]) then return L.CHECK_NIL end
    local value = region[method](region)
    if IsSecret(value) then return L.CHECK_SECRET end
    return type(value) == "number" and ("%.0f"):format(value) or L.CHECK_NIL
end

local function Plain(region, method)
    if not (region and type(region[method]) == "function") then return L.CHECK_NIL end
    return Show(region[method](region))
end

-- Returns the lines to print; draws the boxes when the target has a Blizzard plate.
function Diagnostics:OutlineTarget()
    if not UnitExists("target") then return { L.TARGET_NONE } end
    local nameplate = C_NamePlate.GetNamePlateForUnit("target")
    local unitFrame = nameplate and nameplate.UnitFrame
    if not unitFrame or unitFrame:IsForbidden() then return { L.CHECK_NO_PLATE } end

    for _, box in ipairs(outlineBoxes) do box:Hide() end
    wipe(outlineBoxes)
    local lines = { L.OUTLINE_HEADER:format(OUTLINE_SECONDS) }
    local shown = unitFrame:IsVisible()
    if IsSecret(shown) or not shown then
        -- Another nameplate add-on draws this plate and hides Blizzard's: the boxes can't show.
        lines[#lines + 1] = L.OUTLINE_HIDDEN
    end
    local pool = outlinePools[unitFrame] or {}
    outlinePools[unitFrame] = pool
    for index, part in ipairs(OUTLINE_PARTS) do
        local key, colour, find = part[1], part[2], part[3]
        local region = find(unitFrame)
        if region then
            local box = pool[index] or unitFrame:CreateTexture(nil, "OVERLAY", nil, 7)
            pool[index] = box
            box:ClearAllPoints()
            box:SetColorTexture(colour[1], colour[2], colour[3], 0.35)
            box:SetAllPoints(region)
            box:Show()
            outlineBoxes[#outlineBoxes + 1] = box
            lines[#lines + 1] = L.OUTLINE_PART:format(L[key], Size(region, "GetWidth"), Size(region, "GetHeight"),
                Plain(region, region.IsVisible and "IsVisible" or "IsShown"))
        else
            lines[#lines + 1] = L.OUTLINE_MISSING:format(L[key])
        end
    end
    outlineGeneration = outlineGeneration + 1
    local generation = outlineGeneration
    C_Timer.After(OUTLINE_SECONDS, function()
        if generation ~= outlineGeneration then return end
        for _, box in ipairs(outlineBoxes) do box:Hide() end
        wipe(outlineBoxes)
    end)
    return lines
end
