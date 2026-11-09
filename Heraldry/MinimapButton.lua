--[[ MinimapButton.lua
  The minimap button, made with LibDBIcon-1.0 (embedded in Libs\). Using the standard
  library is what makes minimap button collectors work: MinimapButtonButton, for one,
  gathers LibDBIcon's buttons through LibDBIcon:GetButtonList and its
  LibDBIcon_IconCreated callback, then re-parents the button, replaces its SetPoint and
  hooks its Show and Hide; EllesmereUI's minimap and EnhanceQoL's button bin collect them
  too. So this file never positions the button itself and shows or hides it only through
  LibDBIcon:Show and :Hide. Never call LibDBIcon:Refresh, :Lock or :Unlock here either:
  they put back the drag scripts collectors remove.

  Left-click opens or closes the options, right-click turns icons on or off, dragging moves
  the button around the minimap. Its position and whether it shows are saved account-wide
  in HeraldryDB.ui.minimap, the table format LibDBIcon reads and writes.

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

local function OnClick(self, button)
    if button == "RightButton" then
        ns.ToggleIcons()
        -- The tooltip is still up under the cursor: show the new state in it.
        local tooltip = dbIcon and dbIcon.tooltip
        if tooltip and tooltip:IsShown() and tooltip:IsOwned(self) then
            tooltip:ClearLines()
            OnTooltipShow(tooltip)
            tooltip:Show()
        end
    else
        ns.Options:Toggle()
    end
end

function OnTooltipShow(tooltip)
    tooltip:AddLine(L.ADDON_TITLE, 1, 1, 1)
    local state = ns.profile.display.enabled and GREEN_FONT_COLOR:WrapTextInColorCode(L.MINIMAP_ICONS_ON)
        or RED_FONT_COLOR:WrapTextInColorCode(L.MINIMAP_ICONS_OFF)
    tooltip:AddLine(state)
    tooltip:AddLine(L.MINIMAP_TIP_CLICK, 0.8, 0.8, 0.8)
    tooltip:AddLine(L.MINIMAP_TIP_RIGHT_CLICK, 0.8, 0.8, 0.8)
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
