--[[ Share.lua
  Export and import of rules as a text string a guild officer can post in Discord.

  String:  "!Heraldry:1:" .. base64(body) .. ":" .. adler32(body) as 8 hex digits
  Body:    one record per line, fields separated by tabs:
             M  <icon>                       the "my guild" icon
             G  <ruleset>  <name>  <icon>    a guild rule
             P  <name>  <icon>               a player rule ("none" allowed)
             C  <file>                       a custom icon file name
           Unknown record types are skipped, so later versions can add some.
  Nothing in an import string is ever executed: it is split into fields, every field is
  validated, and only then shown as a preview. Apply writes the previewed rules. ]]

local _, ns = ...

local Share = {}
ns.Share = Share

local Identity, Icons = ns.Identity, ns.Icons

local PREFIX = "!Heraldry:"
local FORMAT_VERSION = 1
local MAX_STRING_LENGTH = 200000
local MAX_RECORDS = 2000
local MAX_NAME_LENGTH = 64

Share.ERRORS = {
    EMPTY = "EMPTY",       -- nothing pasted
    FOREIGN = "FOREIGN",   -- not a Heraldry string
    NEWER = "NEWER",       -- made by a newer Heraldry
    DAMAGED = "DAMAGED",   -- cut off or altered (base64 or checksum)
    INVALID = "INVALID",   -- decodes, but a record is malformed
    NOTHING = "NOTHING",   -- valid, but holds no rules
}

--------------------------------------------------------------------------------
-- Base64 and Adler-32, in plain arithmetic (Lua 5.1, no bit library needed)
--------------------------------------------------------------------------------
local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local ENCODE, DECODE = {}, {}
for i = 1, 64 do
    local char = ALPHABET:sub(i, i)
    ENCODE[i - 1] = char
    DECODE[char] = i - 1
end

function Share.Base64Encode(data)
    local out = {}
    for i = 1, #data, 3 do
        local a, b, c = data:byte(i, i + 2)
        local n = a * 65536 + (b or 0) * 256 + (c or 0)
        local c1, c2 = math.floor(n / 262144), math.floor(n / 4096) % 64
        local c3, c4 = math.floor(n / 64) % 64, n % 64
        out[#out + 1] = ENCODE[c1] .. ENCODE[c2] .. (b and ENCODE[c3] or "=") .. (c and ENCODE[c4] or "=")
    end
    return table.concat(out)
end

function Share.Base64Decode(text)
    if #text % 4 ~= 0 or text:find("[^%w%+/=]") then return nil end
    local out = {}
    for i = 1, #text, 4 do
        local quad = text:sub(i, i + 3)
        local padding = #quad:match("=*$")
        if padding > 2 or (padding > 0 and i + 4 <= #text) or quad:sub(1, 4 - padding):find("=") then
            return nil
        end
        local n = 0
        for j = 1, 4 do
            n = n * 64 + (DECODE[quad:sub(j, j)] or 0)
        end
        local a, b, c = math.floor(n / 65536), math.floor(n / 256) % 256, n % 256
        if padding == 0 then
            out[#out + 1] = string.char(a, b, c)
        elseif padding == 1 then
            out[#out + 1] = string.char(a, b)
        else
            out[#out + 1] = string.char(a)
        end
    end
    return table.concat(out)
end

function Share.Checksum(data)
    local a, b = 1, 0
    for i = 1, #data do
        a = (a + data:byte(i)) % 65521
        b = (b + a) % 65521
    end
    return ("%04x%04x"):format(b, a)
end

--------------------------------------------------------------------------------
-- Payload: { myGuild = icon|nil, guilds = { {ruleset, name, icon} }, players = { {name,
-- icon} }, custom = { file } }
--------------------------------------------------------------------------------
-- options: myGuild, guilds, players, custom (booleans); allRulesets (else current only).
function Share.Build(profile, options, ruleset)
    local payload = { guilds = {}, players = {}, custom = {} }
    if options.myGuild and profile.myGuild.icon then
        payload.myGuild = profile.myGuild.icon
    end
    if options.guilds then
        for key, rule in pairs(profile.guilds) do
            local keyRuleset = Identity.SplitGuildKey(key)
            if keyRuleset and (options.allRulesets or keyRuleset == ruleset) then
                payload.guilds[#payload.guilds + 1] = { ruleset = keyRuleset, name = rule.name, icon = rule.icon }
            end
        end
        table.sort(payload.guilds, function(a, b) return a.ruleset .. a.name < b.ruleset .. b.name end)
    end
    if options.players then
        for _, rule in pairs(profile.players) do
            payload.players[#payload.players + 1] = { name = rule.name, icon = rule.icon }
        end
        table.sort(payload.players, function(a, b) return a.name < b.name end)
    end
    if options.custom then
        for _, file in ipairs(profile.custom) do
            payload.custom[#payload.custom + 1] = file
        end
    end
    return payload
end

function Share.CountRules(payload)
    return (payload.myGuild and 1 or 0) + #payload.guilds + #payload.players + #payload.custom
end

function Share.Encode(payload)
    local lines = {}
    if payload.myGuild then
        lines[#lines + 1] = "M\t" .. payload.myGuild
    end
    for _, rule in ipairs(payload.guilds) do
        lines[#lines + 1] = ("G\t%s\t%s\t%s"):format(rule.ruleset, rule.name, rule.icon)
    end
    for _, rule in ipairs(payload.players) do
        lines[#lines + 1] = ("P\t%s\t%s"):format(rule.name, rule.icon)
    end
    for _, file in ipairs(payload.custom) do
        lines[#lines + 1] = "C\t" .. file
    end
    local body = table.concat(lines, "\n")
    return PREFIX .. FORMAT_VERSION .. ":" .. Share.Base64Encode(body) .. ":" .. Share.Checksum(body)
end

local function ValidName(name)
    return name and name ~= "" and #name <= MAX_NAME_LENGTH and not name:find("[%c/]")
end

local function ValidRuleset(token)
    return token and token:match("^[%l%d%+]+$") ~= nil and #token <= 32
end

local function ParseRecord(payload, fields)
    local kind = fields[1]
    if kind == "M" then
        if not Icons.IsValidId(fields[2]) then return false end
        payload.myGuild = fields[2]
    elseif kind == "G" then
        local ruleset, name, icon = fields[2], fields[3], fields[4]
        if not (ValidRuleset(ruleset) and ValidName(name) and Icons.IsValidId(icon)) then return false end
        payload.guilds[#payload.guilds + 1] = { ruleset = ruleset, name = name, icon = icon }
    elseif kind == "P" then
        local name, icon = fields[2], fields[3]
        if not (ValidName(name) and Icons.IsValidId(icon, true)) then return false end
        payload.players[#payload.players + 1] = { name = name, icon = icon }
    elseif kind == "C" then
        local parsed = Icons.ParseCustomName(fields[2])
        if not parsed then return false end
        payload.custom[#payload.custom + 1] = parsed.file
    end
    return true
end

-- Returns payload, or nil and one of Share.ERRORS.
function Share.Decode(text)
    text = (text or ""):gsub("%s+", "")
    if text == "" then return nil, Share.ERRORS.EMPTY end
    if #text > MAX_STRING_LENGTH then return nil, Share.ERRORS.DAMAGED end
    local version, encoded, checksum = text:match("^!Heraldry:(%d+):([^:]*):(%x+)$")
    if not version then
        return nil, text:find(PREFIX, 1, true) == 1 and Share.ERRORS.DAMAGED or Share.ERRORS.FOREIGN
    end
    if tonumber(version) > FORMAT_VERSION then return nil, Share.ERRORS.NEWER end
    local body = Share.Base64Decode(encoded)
    if not body or Share.Checksum(body) ~= checksum:lower() then return nil, Share.ERRORS.DAMAGED end

    local payload = { guilds = {}, players = {}, custom = {} }
    local count = 0
    for line in (body .. "\n"):gmatch("([^\n]*)\n") do
        if line ~= "" then
            count = count + 1
            if count > MAX_RECORDS then return nil, Share.ERRORS.INVALID end
            local fields = {}
            for field in (line .. "\t"):gmatch("([^\t]*)\t") do
                fields[#fields + 1] = field
            end
            if not ParseRecord(payload, fields) then return nil, Share.ERRORS.INVALID end
        end
    end
    if Share.CountRules(payload) == 0 then return nil, Share.ERRORS.NOTHING end
    return payload
end

--------------------------------------------------------------------------------
-- Preview and apply
--------------------------------------------------------------------------------
-- A change: { kind = "myGuild"|"guilds"|"players"|"custom", key =, name =, ruleset =,
-- icon =, oldIcon =, status = "new"|"change"|"same" }
function Share.Diff(profile, payload)
    local changes = {}
    local function Add(change, current)
        if current == nil then
            change.status = "new"
        elseif current == change.icon then
            change.status = "same"
        else
            change.status, change.oldIcon = "change", current
        end
        changes[#changes + 1] = change
    end
    if payload.myGuild then
        -- Applying also switches "my guild" on, so a disabled rule counts as new.
        Add({ kind = "myGuild", icon = payload.myGuild }, profile.myGuild.enabled and profile.myGuild.icon or nil)
    end
    for _, rule in ipairs(payload.guilds) do
        local key = Identity.GuildKey(rule.ruleset, rule.name)
        local current = profile.guilds[key]
        Add({ kind = "guilds", key = key, name = rule.name, ruleset = rule.ruleset, icon = rule.icon },
            current and current.icon)
    end
    for _, rule in ipairs(payload.players) do
        local key = Identity.PlayerKeyFromText(rule.name)
        local current = profile.players[key]
        Add({ kind = "players", key = key, name = rule.name, icon = rule.icon }, current and current.icon)
    end
    local registered = {}
    for _, file in ipairs(profile.custom) do registered[file] = true end
    for _, file in ipairs(payload.custom) do
        local change = { kind = "custom", name = file, icon = "custom:" .. file }
        change.status = registered[file] and "same" or "new"
        changes[#changes + 1] = change
    end
    return changes
end

-- Applies the changes the player kept (change.skip unset). Returns the number applied.
function Share.Apply(profile, changes)
    local registered = {}
    for _, file in ipairs(profile.custom) do registered[file] = true end
    local function ApplyOne(change)
        if change.kind == "myGuild" then
            profile.myGuild.icon = change.icon
            profile.myGuild.enabled = true
        elseif change.kind == "custom" then
            -- A string can name the same file twice.
            if registered[change.name] then return false end
            registered[change.name] = true
            profile.custom[#profile.custom + 1] = change.name
        else
            profile[change.kind][change.key] = { name = change.name, icon = change.icon }
        end
        return true
    end
    local applied = 0
    for _, change in ipairs(changes) do
        if change.status ~= "same" and not change.skip and ApplyOne(change) then
            applied = applied + 1
        end
    end
    return applied
end
