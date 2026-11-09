--[[ UI\Skin.lua
  EllesmereUI theming for Heraldry's own frames, through EUI's public skinning API
  (EllesmereUI\SKINNING_API.md). EUI only themes frames an add-on hands it, and only while
  the player has third-party skinning on for Heraldry; without EUI nothing here runs and
  the stock templates keep Blizzard's look.

  Heraldry builds its frames lazily, after login, so every builder calls Skin:Apply as it
  creates a control; Apply does nothing until EUI has handed over its primitives. ]]

local _, ns = ...

local Skin = {}
ns.Skin = Skin

local primitives -- EUI's "S" table, once its callback ran

-- Skin:Apply("Button", button) calls S.Button(button) when skinning is on.
function Skin:Apply(kind, ...)
    local apply = primitives and primitives[kind]
    if apply then apply(...) end
end

function Skin:IsActive()
    return primitives ~= nil
end

-- The player's accent color for highlights Heraldry draws itself, or nil when unskinned.
function Skin:AccentColor()
    if primitives and primitives.GetAccentColor then
        return primitives.GetAccentColor()
    end
end

-- Runs fn whenever the player changes EUI's accent or theme, for colors Heraldry applies
-- itself from AccentColor (skinned frames follow on their own). Listeners registered
-- before EUI hands over its primitives are attached when it does.
local looksListeners = {}
function Skin:OnLooksChanged(fn)
    looksListeners[#looksListeners + 1] = fn
    if primitives and primitives.OnLooksChanged then primitives.OnLooksChanged(fn) end
end

-- Tabs Heraldry switches itself look selected only through this (S.SetTabSelection,
-- EUI skinning API version 2).
function Skin:SetTabSelected(tab, selected)
    if primitives and primitives.SetTabSelection then
        primitives.SetTabSelection(tab, selected)
    end
end

if EllesmereUI and EllesmereUI.RegisterSkin then
    EllesmereUI.RegisterSkin("Heraldry", function(S)
        primitives = S
        if S.OnLooksChanged then
            for _, fn in ipairs(looksListeners) do S.OnLooksChanged(fn) end
        end
    end)
end
