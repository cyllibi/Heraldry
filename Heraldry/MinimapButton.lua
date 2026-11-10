--[[ MinimapButton.lua
  The minimap button, made with LibDBIcon-1.0 (embedded in Libs\). Using the standard
  library is what makes minimap button collectors work: MinimapButtonButton, for one,
  gathers LibDBIcon's buttons through LibDBIcon:GetButtonList and its
  LibDBIcon_IconCreated callback, then re-parents the button, replaces its SetPoint and
  hooks its Show and Hide; EllesmereUI's minimap and EnhanceQoL's button bin collect them
  too. So this file never positions the button itself and shows or hides it only through
  LibDBIcon:Show and :Hide. Never call LibDBIcon:Refresh, :Lock or :Unlock here either:
  they put back the drag scripts collectors remove.

  The button is a shortcut; the options are for changing settings. Its clicks
  (MinimapButton.Click, shared with the add-on compartment entry):
                  with a target                         without a target
    left-click    pick an icon for the target           the Players page
    right-click   pick an icon for the target's guild   the Guilds page
    middle-click  remove the target's player and        the options (open or close)
                  guild icons, if any (/heraldry undo
                  puts them back)
    shift-click   show or hide icons (any button, target or not)
  A target the action can't use (an NPC, yourself, a hidden name) gets a chat line saying
  why, as /heraldry player and /heraldry guild do. Right-click on yourself edits the
  My guild icon, which a plain rule for your own guild would silently override. Dragging moves the button around the
  minimap. Its position and whether it shows are saved account-wide in
  HeraldryDB.ui.minimap, the table format LibDBIcon reads and writes.

  The add-on compartment entry comes from the TOC (AddonCompartmentFunc, same clicks), so
  the button is not also added to the compartment. If the libraries are missing (a broken
  install), there is no button and everything else works. ]]

local _, ns = ...
local L = ns.L

local MinimapButton = {}
ns.MinimapButton = MinimapButton

local NAME = "Heraldry"
local ICON = [[Interface\AddOns\Heraldry\media\heraldry]]

local dbIcon

local function Libraries()
    if type(LibStub) ~= "table" then return end
    return LibStub("LibDataBroker-1.1", true), LibStub("LibDBIcon-1.0", true)
end

local OnTooltipShow

--------------------------------------------------------------------------------
-- Clicks, shared by the minimap button and the add-on compartment entry
--------------------------------------------------------------------------------
local lastCleared -- { { kind, key, rule }, ... } from the last middle-click, for /heraldry undo

local function TargetIsSelf()
    return ns.Rules:ReadUnit("target").isSelf
end

local function EditTargetRule(kind)
    -- Your own guild has its own rule (My guild); a plain rule would silently override it.
    if kind == "guilds" and TargetIsSelf() then
        ns.Options:EditMyGuild()
        return
    end
    local ok, reason = ns.Options:EditTargetRule(kind)
    if not ok then ns.Print(reason) end
end

-- The target's own rules (player, then guild) as { kind, key, name, rule } entries; and
-- the reason the target can't be read, when it can't. Hidden names and guilds count as
-- having no rule: they are left alone.
local function TargetRules()
    local found = {}
    local playerKey, playerName = ns.Rules:TargetSubject("players")
    if playerKey and ns.Rules:Get("players", playerKey) then
        found[#found + 1] = { kind = "players", key = playerKey, name = playerName }
    end
    local guildKey, guildName = ns.Rules:TargetSubject("guilds")
    if guildKey and ns.Rules:Get("guilds", guildKey) then
        found[#found + 1] = { kind = "guilds", key = guildKey, name = guildName }
    end
    -- TargetSubject's second value is the reason, not a name, when the key is nil.
    return found, not playerKey and playerName or nil
end

local function Describe(entry)
    local text = entry.kind == "players" and L.MINIMAP_CLEARED_PLAYER or L.MINIMAP_CLEARED_GUILD
    return text:format(entry.name)
end

-- Removes the target's player rule and its guild's rule, whichever exist, says what went
-- and keeps them for /heraldry undo (the options' rule lists undo rather than confirm,
-- and so does this). Only rules the game lets Heraldry read are touched.
function MinimapButton.ClearTarget()
    local found, reason = TargetRules()
    if #found == 0 then
        ns.Print(reason or L.MINIMAP_CLEARED_NOTHING)
        return
    end
    lastCleared = {}
    local removed = {}
    for _, entry in ipairs(found) do
        entry.rule = ns.Rules:Remove(entry.kind, entry.key)
        lastCleared[#lastCleared + 1] = entry
        removed[#removed + 1] = Describe(entry)
    end
    ns.Print(L.MINIMAP_CLEARED:format(table.concat(removed, L.LIST_SEPARATOR)))
end

-- /heraldry undo: puts back what the last middle-click removed, once.
function MinimapButton.Undo()
    if not lastCleared then
        ns.Print(L.UNDO_NOTHING)
        return
    end
    local restored = {}
    for _, entry in ipairs(lastCleared) do
        ns.Rules:Set(entry.kind, entry.key, entry.rule.name, entry.rule.icon)
        restored[#restored + 1] = Describe(entry)
    end
    lastCleared = nil
    ns.Print(L.UNDO_DONE:format(table.concat(restored, L.LIST_SEPARATOR)))
end

-- button: "LeftButton", "RightButton" or "MiddleButton" (others count as left).
function MinimapButton.Click(button)
    if IsShiftKeyDown() then
        ns.ToggleIcons()
        return
    end
    local hasTarget = UnitExists("target")
    if button == "RightButton" then
        if hasTarget then EditTargetRule("guilds") else ns.Options:Open("guilds") end
    elseif button == "MiddleButton" then
        if hasTarget then MinimapButton.ClearTarget() else ns.Options:Toggle() end
    else
        if hasTarget then EditTargetRule("players") else ns.Options:Open("players") end
    end
end

local function OnClick(self, button)
    MinimapButton.Click(button)
    -- The tooltip is still up under the cursor: show the new state in it.
    local tooltip = dbIcon and dbIcon.tooltip
    if tooltip and tooltip:IsShown() and tooltip:IsOwned(self) then
        tooltip:ClearLines()
        OnTooltipShow(tooltip)
        tooltip:Show()
    end
end

-- What each click does right now, for the tooltip: the target's name and guild when the
-- game shows them, a plain description when it doesn't.
function MinimapButton.ClickLines()
    if not UnitExists("target") then
        return { L.MINIMAP_TIP_LEFT_PAGE, L.MINIMAP_TIP_RIGHT_PAGE, L.MINIMAP_TIP_MIDDLE_OPTIONS,
            L.MINIMAP_TIP_SHIFT }
    end
    local playerKey, playerName = ns.Rules:TargetSubject("players")
    local guildKey, guildName = ns.Rules:TargetSubject("guilds")
    local right
    if TargetIsSelf() then
        right = L.MINIMAP_TIP_RIGHT_MY_GUILD
    else
        right = guildKey and L.MINIMAP_TIP_RIGHT_NAMED:format(guildName) or L.MINIMAP_TIP_RIGHT_TARGET
    end
    local found = TargetRules()
    local removes = {}
    for _, entry in ipairs(found) do removes[#removes + 1] = Describe(entry) end
    return {
        playerKey and L.MINIMAP_TIP_LEFT_NAMED:format(playerName) or L.MINIMAP_TIP_LEFT_TARGET,
        right,
        #removes > 0 and L.MINIMAP_TIP_MIDDLE_REMOVES:format(table.concat(removes, L.LIST_SEPARATOR))
            or L.MINIMAP_TIP_MIDDLE_NOTHING,
        L.MINIMAP_TIP_SHIFT,
    }
end

function OnTooltipShow(tooltip)
    tooltip:AddLine(L.ADDON_TITLE, 1, 1, 1)
    local state = ns.profile.display.enabled and GREEN_FONT_COLOR:WrapTextInColorCode(L.MINIMAP_ICONS_ON)
        or RED_FONT_COLOR:WrapTextInColorCode(L.MINIMAP_ICONS_OFF)
    tooltip:AddLine(state)
    for _, line in ipairs(MinimapButton.ClickLines()) do
        tooltip:AddLine(line, 0.8, 0.8, 0.8)
    end
    -- Only on the minimap itself: inside a collector's drawer, dragging means nothing useful.
    local owner = tooltip:GetOwner()
    if owner and owner:GetParent() == Minimap then
        tooltip:AddLine(L.MINIMAP_TIP_DRAG, 0.8, 0.8, 0.8)
    end
end

function MinimapButton:Init()
    local broker, icon = Libraries()
    if not (broker and icon) or icon:IsRegistered(NAME) then return end
    local object = broker:NewDataObject(NAME, {
        type = "launcher",
        label = L.ADDON_TITLE,
        icon = ICON,
        OnClick = OnClick,
        OnTooltipShow = OnTooltipShow,
    })
    -- Nil when another add-on already made a data object with this name: not ours to use.
    if not object then return end
    icon:Register(NAME, object, ns.ui.minimap)
    dbIcon = icon
end

-- False when the libraries are missing: the options then disable the checkbox.
function MinimapButton:IsAvailable()
    return dbIcon ~= nil
end

function MinimapButton:IsShown()
    return not ns.ui.minimap.hide
end

function MinimapButton:SetShown(shown)
    ns.ui.minimap.hide = not shown
    if not dbIcon then return end
    if shown then dbIcon:Show(NAME) else dbIcon:Hide(NAME) end
end

ns.Listen("LOADED", function() MinimapButton:Init() end)
