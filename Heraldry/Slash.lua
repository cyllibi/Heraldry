--[[ Slash.lua
  /heraldry           open the options
  /heraldry guild     pick an icon for your target's guild
  /heraldry player    pick an icon for your target
  /heraldry check     what the client exposes about your target, for bug reports
  /heraldry try       show the Display page's preview icon on your target for 10 seconds
  /heraldry minimap   show or hide the minimap button
  /heraldry undo      put back what the minimap button's middle-click removed
  /heraldry help      this list ]]

local _, ns = ...
local L = ns.L

local function Check()
    ns.Print(L.CHECK_HEADER)
    for _, line in ipairs(ns.Diagnostics:Lines()) do ns.Print(line) end
end

local function TargetRule(kind)
    local ok, reason = ns.Options:EditTargetRule(kind)
    if not ok then ns.Print(reason) end
end

local function Try()
    local ok, reason = ns.Plates:ShowTest(ns.Options:PreviewIcon())
    ns.Print(ok and L.TEST_STARTED or reason)
end

local function ToggleMinimap()
    if not ns.MinimapButton:IsAvailable() then
        ns.Print(L.MINIMAP_UNAVAILABLE)
        return
    end
    local shown = not ns.MinimapButton:IsShown()
    ns.MinimapButton:SetShown(shown)
    ns.Print(shown and L.MINIMAP_TURNED_ON or L.MINIMAP_TURNED_OFF)
    ns.Fire("UI_CHANGED") -- refreshes the options' checkbox if it is on screen
end

local COMMANDS = {
    [""] = function() ns.Options:Open() end,
    guild = function() TargetRule("guilds") end,
    player = function() TargetRule("players") end,
    check = Check,
    try = Try,
    minimap = ToggleMinimap,
    undo = function() ns.MinimapButton.Undo() end,
    help = function()
        for line in L.SLASH_HELP_BODY:gmatch("[^\n]+") do ns.Print(line) end
    end,
}

SLASH_HERALDRY1 = "/heraldry"
SlashCmdList.HERALDRY = function(message)
    local command = ns.Trim(message or ""):lower()
    local handler = COMMANDS[command] or COMMANDS.help
    handler()
end
