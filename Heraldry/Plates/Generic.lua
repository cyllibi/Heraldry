--[[ Plates\Generic.lua
  The fallback for plates no known nameplate add-on owns: an add-on Heraldry has no
  adapter for (Platynator, small Forever plate add-ons). Without a name to sit beside,
  the icon goes centred above the nameplate, lifted a little so it clears a name such an
  add-on draws above its bar. Plates a known add-on owns but hides never come here (see
  Plates.lua), and the Display option "unknownPlates" turns the fallback off.

  The icon is drawn on Heraldry's own frame, one per nameplate, covering it. ]]

local _, ns = ...
local L = ns.L

local adapter = {
    id = "Generic",
    label = L.ADAPTER_GENERIC,
    fallback = true,
}

local LIFT = 14 -- pixels above the plate's top, roughly one line of name text

local holders = setmetatable({}, { __mode = "k" }) -- nameplate -> our frame
local hints = { anchorOnly = true, lift = LIFT }

function adapter.IsAvailable()
    return true
end

function adapter.GetName(_, nameplate)
    if not ns.profile.display.unknownPlates then return end
    local holder = holders[nameplate]
    if not holder then
        holder = CreateFrame("Frame", nil, nameplate)
        holder:SetAllPoints(nameplate)
        holders[nameplate] = holder
    end
    hints.host = holder
    return holder, hints
end

ns.Plates:RegisterAdapter(adapter)
