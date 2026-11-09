-- luacheck configuration for Heraldry (WoW Forever, Lua 5.1).
-- Run from the repository root:  .tools\luacheck.exe Heraldry tests
std = "lua51"
max_line_length = 140
codes = true
-- Methods defined with ":" for a uniform module API need not use self.
self = false

exclude_files = {
    ".tools/",
    "HeraldryDev/",  -- generated, gitignored dev add-on
    "Heraldry/Libs/", -- third-party libraries, fetched by the packager
}

-- The only globals Heraldry writes: its SavedVariables, its slash command and the
-- AddonCompartmentFunc named in the TOC.
globals = {
    "HeraldryDB",
    "HeraldryCharDB",
    "SLASH_HERALDRY1",
    "Heraldry_OnAddonCompartmentClick",
    SlashCmdList = { fields = { HERALDRY = { read_only = false } } },
}

-- WoW API and FrameXML the add-on reads.
read_globals = {
    -- Lua extensions in the WoW client
    "wipe", "issecretvalue", "geterrorhandler", "hooksecurefunc", "debugprofilestop",

    -- Namespaced APIs
    "C_AddOns", "C_CVar", "C_GameRules", "C_Item", "C_LFGInfo", "C_NamePlate", "C_Secrets", "C_Spell", "C_Timer",
    "Constants", "Enum",

    -- Units and game state
    "GetGuildInfo", "GetInstanceInfo", "GetTime", "InCombatLockdown", "IsInInstance", "UnitCanAttack", "UnitExists",
    "UnitGUID", "UnitIsInMyGuild", "UnitIsPlayer", "UnitIsUnit", "UnitName",

    -- Icons and textures
    "GetFileIDFromPath", "GetLooseMacroIcons", "GetLooseMacroItemIcons", "GetMacroIcons", "GetMacroItemIcons",

    -- Frames, templates and UI utilities
    "ButtonFrameTemplate_HidePortrait", "CopyTable", "CreateDataProvider", "CreateFrame",
    "CreateMinimalSliderFormatter", "CreateScrollBoxListLinearView", "DEFAULT_CHAT_FRAME", "GameTooltip",
    "GameTooltip_Hide", "MenuUtil", "MinimalSliderWithSteppersMixin", "Mixin", "PanelTemplates_DeselectTab",
    "PanelTemplates_SelectTab", "PanelTemplates_TabResize", "PlaySound", "ScrollBoxConstants", "ScrollUtil",
    "Settings", "SettingsPanel", "HideUIPanel", "SOUNDKIT", "UIParent", "LibStub", "Minimap",

    -- Global strings and colors
    "ADD", "CANCEL", "REMOVE", "SEARCH", "STANDARD_TEXT_FONT",
    "GDAPI_REALMTYPE_NORMAL", "GDAPI_REALMTYPE_PVP", "GDAPI_REALMTYPE_PVP_RP", "GDAPI_REALMTYPE_RP",
    "GUILD_PLAYSTYLE_HARDCORE",
    "GRAY_FONT_COLOR", "GREEN_FONT_COLOR", "RED_FONT_COLOR", "YELLOW_FONT_COLOR",

    -- Other add-ons, read only when present
    "HeraldryDevLibrary",                                       -- HeraldryDev (maintainers only)
    "EllesmereUI",                                              -- EllesmereUI (skin and plugin APIs)
    "EllesmereNameplates_NS",                                   -- EllesmereUI Nameplates
    "Plater",                                                   -- Plater Nameplates
    "TwitchEmotes_defaultpack", "TwitchEmotes_animation_metadata", -- TwitchEmotes (+ Giga)
}

-- Strings read better unwrapped; the locale file is data, not code.
files["Heraldry/Locales/"] = { max_line_length = false }

-- Headless tests run under plain Lua 5.1; tests/wowstub.lua defines the WoW API the
-- add-on reads (read-only above), so writing those globals is the stub's whole job.
files["tests/"] = {
    ignore = { "121", "122" },
}
