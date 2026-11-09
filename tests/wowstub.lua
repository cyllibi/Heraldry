-- Minimal WoW API stub so the add-on's own files load under plain Lua 5.1.
-- Only what the pure-logic files touch at load time or in the tested functions.

local stub = {}

-- Frames: any method is a no-op returning nil, except the few the tested code reads
-- back. Regions record their anchors; font strings measure 6 pixels per character.
local function noop() end
local regionMethods = {}
function regionMethods:ClearAllPoints() self.points = {} end
function regionMethods:SetPoint(...) self.points[#self.points + 1] = { ... } end
function regionMethods:SetFont(file, size, flags) self.font = { file, size, flags } end
function regionMethods:GetFont() return self.font[1], self.font[2], self.font[3] end
function regionMethods:SetText(text) self.text = text end
function regionMethods:GetText() return self.text end
function regionMethods:GetStringWidth() return #(self.text or "") * 6 end
function regionMethods:SetJustifyH(justify) self.justify = justify end
function regionMethods:GetJustifyH() return self.justify or "CENTER" end
local regionMeta = { __index = function(_, key) return regionMethods[key] or noop end }
function stub.Region()
    return setmetatable({ points = {}, font = {} }, regionMeta)
end

local frameMethods = {}
function frameMethods:CreateTexture() return stub.Region() end
function frameMethods:CreateFontString() return stub.Region() end
local frameMeta = { __index = function(_, key) return frameMethods[key] or noop end }
function CreateFrame()
    return setmetatable({}, frameMeta)
end

UIParent = CreateFrame()
DEFAULT_CHAT_FRAME = { AddMessage = function(_, text) stub.lastMessage = text end }

-- Secret values: opaque sentinels the tests hand out where the client would. Like the
-- client's, they throw when concatenated, ordered, measured, indexed or called, so a
-- test fails if one leaks into anything but a display sink. (Lua 5.1 can't trap ==
-- against nil; the add-on tests IsSecret first by rule.)
local secrets = setmetatable({}, { __mode = "k" })
local function misuse() error("secret value misused", 2) end
function stub.Secret()
    local value = newproxy(true)
    local meta = getmetatable(value)
    meta.__concat, meta.__lt, meta.__le, meta.__len = misuse, misuse, misuse, misuse
    meta.__index, meta.__newindex, meta.__call = misuse, misuse, misuse
    meta.__add, meta.__sub, meta.__mul, meta.__div, meta.__unm = misuse, misuse, misuse, misuse, misuse
    secrets[value] = true
    return value
end
function issecretvalue(value)
    return value ~= nil and secrets[value] == true
end

stub.errors = {}
function geterrorhandler()
    return function(message) stub.errors[#stub.errors + 1] = message end
end

function CopyTable(source)
    local copy = {}
    for key, value in pairs(source) do
        copy[key] = type(value) == "table" and CopyTable(value) or value
    end
    return copy
end

function wipe(t)
    for key in pairs(t) do t[key] = nil end
    return t
end

stub.loadedAddOns = {}
stub.addOnTitles = {}
C_AddOns = {
    GetAddOnMetadata = function(name, field)
        if field == "Title" then return stub.addOnTitles[name] or name end
        return "test"
    end,
    IsAddOnLoaded = function(name) return stub.loadedAddOns[name] == true end,
}

Constants = { CharacterNameSeparatorConsts = { CHARACTERNAME_SURNAME_SEPARATOR = " " } }

stub.activeRules = {}
Enum = { GameRule = { HardcoreRuleset = 1, PvPRuleset = 2, RPRuleset = 3, MinimapDisabled = 4 } }
C_GameRules = { IsGameRuleActive = function(rule) return stub.activeRules[rule] == true end }

GDAPI_REALMTYPE_NORMAL = "Normal"
GDAPI_REALMTYPE_PVP = "PvP"
GDAPI_REALMTYPE_RP = "RP"
GDAPI_REALMTYPE_PVP_RP = "RP PvP"
GUILD_PLAYSTYLE_HARDCORE = "Hardcore"

-- Unit API, driven by stub.units[token] = { name =, surname =, guild =, player =, myGuild = }
stub.units = {}
local function unitField(unit, field)
    local data = stub.units[unit]
    return data and data[field]
end
function UnitIsPlayer(unit)
    local value = unitField(unit, "player")
    if issecretvalue(value) then return value end
    return value == true
end
function UnitIsUnit(a, b) return a == b end
function UnitName(unit) return unitField(unit, "name"), unitField(unit, "surname") end
function GetGuildInfo(unit) return unitField(unit, "guild") end
function UnitIsInMyGuild(unit) return unitField(unit, "myGuild") end
function UnitExists(unit) return stub.units[unit] ~= nil end

return stub
