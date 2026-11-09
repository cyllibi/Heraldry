--[[ Core.lua
  The add-on namespace: event dispatch, the internal message bus, chat output and the
  few helpers every other file shares. Loaded right after the locale, so nothing here
  may touch another module at file scope.

  Lifecycle: ADDON_LOADED (our own) loads the SavedVariables (Database.lua), then
  PLAYER_LOGIN starts the modules that registered for it, in TOC order. ]]

local addonName, ns = ...
local L = ns.L

ns.addonName = addonName
ns.version = C_AddOns.GetAddOnMetadata(addonName, "Version")

local CHAT_PREFIX = "|cff6fb7ffHeraldry|r: "

-- Values the 12.x client marks secret can only reach display sinks. Every unit value
-- and every widget metric read from a nameplate goes through this test first.
local issecretvalue = issecretvalue
function ns.IsSecret(value)
    return issecretvalue(value)
end

--------------------------------------------------------------------------------
-- Events: one frame, any number of handlers per event, called in registration order.
--------------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
local eventHandlers = {}

function ns.RegisterEvent(event, handler)
    local list = eventHandlers[event]
    if not list then
        list = {}
        eventHandlers[event] = list
        eventFrame:RegisterEvent(event)
    end
    list[#list + 1] = handler
end

function ns.UnregisterEvent(event, handler)
    local list = eventHandlers[event]
    if not list then return end
    for i = #list, 1, -1 do
        if list[i] == handler then table.remove(list, i) end
    end
    if #list == 0 then
        eventHandlers[event] = nil
        eventFrame:UnregisterEvent(event)
    end
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    local list = eventHandlers[event]
    -- A handler may unregister itself (ADDON_LOADED does); the count is taken first.
    for i = 1, #list do
        local handler = list[i]
        if handler then handler(event, ...) end
    end
end)

--------------------------------------------------------------------------------
-- Messages between modules ("LOADED", "PROFILE_CHANGED", "RULES_CHANGED",
-- "DISPLAY_CHANGED", "CUSTOM_CHANGED", "UI_CHANGED" for account-wide interface settings
-- such as the minimap button). Kept separate from game events so a typo can't register a
-- nonexistent game event.
--------------------------------------------------------------------------------
local listeners = {}

function ns.Listen(message, handler)
    local list = listeners[message]
    if not list then
        list = {}
        listeners[message] = list
    end
    list[#list + 1] = handler
end

function ns.Fire(message, ...)
    local list = listeners[message]
    if not list then return end
    for i = 1, #list do
        list[i](message, ...)
    end
end

--------------------------------------------------------------------------------
-- Output
--------------------------------------------------------------------------------
-- Replies to slash commands and one-time notices only; Heraldry prints nothing else.
function ns.Print(text, ...)
    if select("#", ...) > 0 then
        text = text:format(...)
    end
    DEFAULT_CHAT_FRAME:AddMessage(CHAT_PREFIX .. text)
end

-- Bad data that a maintainer must fix (an invalid manifest entry) goes to the normal
-- error handler, so BugSack and /console scriptErrors show it, without stopping the load.
function ns.ReportError(text)
    geterrorhandler()(addonName .. ": " .. text)
end

--------------------------------------------------------------------------------
-- Small shared helpers
--------------------------------------------------------------------------------
function ns.Clamp(value, low, high)
    if value < low then return low end
    if value > high then return high end
    return value
end

function ns.Trim(text)
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

--------------------------------------------------------------------------------
-- Startup
--------------------------------------------------------------------------------
local function OnAddonLoaded(event, loadedName)
    if loadedName ~= addonName then return end
    ns.UnregisterEvent(event, OnAddonLoaded)
    ns.DB:Load()
    ns.Fire("LOADED")
end
ns.RegisterEvent("ADDON_LOADED", OnAddonLoaded)

-- One-time notices, at most one line each per session.
ns.RegisterEvent("PLAYER_LOGIN", function()
    if ns.DB.newerData then
        ns.Print(L.NEWER_DATA)
    end
end)

-- Addon compartment (the add-on drawer by the minimap). A TOC-declared global by design.
-- Same clicks as the minimap button.
function Heraldry_OnAddonCompartmentClick(_, mouseButton)
    if mouseButton == "RightButton" then
        ns.ToggleIcons()
    else
        ns.Options:Toggle()
    end
end

-- Right-click on the minimap button or the compartment entry: the master switch.
function ns.ToggleIcons()
    ns.DB:SetDisplay("enabled", not ns.profile.display.enabled)
end
