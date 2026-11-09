--[[ Icons.lua
  Icon ids, what they draw, and the texture wrapper every icon on screen uses.

  An icon id is "<source>:<value>":
    lib:<key>       the bundled library (Library.lua, media\library\)
    game:<fileID>   a built-in game icon (GameIcons.lua lists them)
    twitch:<emote>  an emote from TwitchEmotes or a pack registering into it (TwitchEmotes_Giga,
                    ...), when loaded
    custom:<file>   a player-supplied file in Interface\AddOns\Heraldry_Custom\
    none            player rules only: show nothing, even if the guild has an icon

  Icons:Resolve(id) turns an id into a spec: texture, aspect, tex coords and FlipBook
  layout. Region wraps one texture (plus its FlipBook) and applies specs to it, so the
  plates, the picker and the previews all draw icons the same way. ]]

local _, ns = ...
local L = ns.L

local Icons = {}
ns.Icons = Icons

local LIBRARY_PATH = [[Interface\AddOns\Heraldry\media\library\]]
-- A maintainer's development library: the separate, never-packaged HeraldryDev add-on
-- (written by tools\emote2lib.py --dev) leaves its entries in this global. Heraldry only
-- reads it, so a fresh clone or a release simply has none.
local DEV_LIBRARY_PATH = [[Interface\AddOns\HeraldryDev\media\]]
local CUSTOM_PATH = [[Interface\AddOns\Heraldry_Custom\]]
local CUSTOM_ADDON = "Heraldry_Custom"

-- Shown in place of an icon id the client can't resolve (a library key from a newer
-- release, an emote pack that isn't loaded), so a rule never silently draws nothing.
Icons.MISSING_ICON = 134400 -- Interface\Icons\INV_Misc_QuestionMark

-- Game icons carry a dark bevel; trimming it matches how the game draws icons small.
local GAME_ICON_COORDS = { 0.07, 0.93, 0.07, 0.93 }
local FULL_COORDS = { 0, 1, 0, 1 }

-- Frame sizes for animated icons, by shape (library and custom alike).
Icons.ANIM_FRAME = { square = { 64, 64 }, wide = { 128, 64 } }
Icons.MAX_TEXTURE = 1024
local MAX_NAME_LENGTH = 64
local MAX_FPS = 60

--------------------------------------------------------------------------------
-- Id parsing
--------------------------------------------------------------------------------
-- Returns source, value; nil for a malformed id. Values are plain strings except game
-- ids (numbers). Pure: does not check that the icon exists.
function Icons.ParseId(id)
    if type(id) ~= "string" then return nil end
    if id == "none" then return "none" end
    local source, value = id:match("^(%l+):(.+)$")
    if source == "lib" and value:match("^[%l%d_]+$") then
        return "lib", value
    elseif source == "game" and value:match("^%d+$") then
        return "game", tonumber(value)
    elseif source == "twitch" and not value:find("[%c:]") and #value <= MAX_NAME_LENGTH then
        return "twitch", value
    elseif source == "custom" and Icons.ParseCustomName(value) then
        return "custom", value
    end
end

function Icons.IsValidId(id, allowNone)
    local source = Icons.ParseId(id)
    if source == "none" then return allowNone == true end
    return source ~= nil
end

--------------------------------------------------------------------------------
-- Custom file names
--------------------------------------------------------------------------------
-- "<name>[_wide][_anim<cols>x<rows>_<frames>_<fps>]", with an optional .tga/.blp
-- extension. Returns { file =, shape =, anim = } or nil, error string.
function Icons.ParseCustomName(text)
    if type(text) ~= "string" then return nil, L.CUSTOM_ERROR_NAME end
    local file = ns.Trim(text):gsub("%.[Tt][Gg][Aa]$", ""):gsub("%.[Bb][Ll][Pp]$", "")
    if file == "" or #file > MAX_NAME_LENGTH or not file:match("^[%w_%-]+$") then
        return nil, L.CUSTOM_ERROR_NAME
    end
    local spec = { file = file, shape = "square" }
    local base, cols, rows, frames, fps = file:match("^(.-)_anim(%d+)x(%d+)_(%d+)_(%d+)$")
    if base then
        cols, rows, frames, fps = tonumber(cols), tonumber(rows), tonumber(frames), tonumber(fps)
        if cols < 1 or rows < 1 or frames < 1 or frames > cols * rows or fps < 1 or fps > MAX_FPS then
            return nil, L.CUSTOM_ERROR_ANIM
        end
        spec.anim = { cols = cols, rows = rows, frames = frames, fps = fps }
    else
        base = file
    end
    if base:match("_wide$") then
        spec.shape = "wide"
    end
    if spec.anim then
        local frame = Icons.ANIM_FRAME[spec.shape]
        if spec.anim.cols * frame[1] > Icons.MAX_TEXTURE or spec.anim.rows * frame[2] > Icons.MAX_TEXTURE then
            return nil, L.CUSTOM_ERROR_ANIM
        end
    end
    return spec
end

--------------------------------------------------------------------------------
-- Library
--------------------------------------------------------------------------------
local function IsPowerOfTwo(n)
    if n < 1 or n % 1 ~= 0 then return false end
    while n > 1 do
        if n % 2 ~= 0 then return false end
        n = n / 2
    end
    return true
end

local function IsPositiveInteger(n)
    return type(n) == "number" and n >= 1 and n % 1 == 0
end

local function IsTextureSize(w, h)
    return IsPositiveInteger(w) and IsPositiveInteger(h) and IsPowerOfTwo(w) and IsPowerOfTwo(h)
        and w <= Icons.MAX_TEXTURE and h <= Icons.MAX_TEXTURE
end

-- Pure check of one manifest entry. Returns true or nil, reason.
function Icons.ValidateLibraryEntry(entry)
    if type(entry) ~= "table" then return nil, "entry is not a table" end
    if type(entry.key) ~= "string" or not entry.key:match("^[%l%d_]+$") then return nil, "bad key" end
    if type(entry.name) ~= "string" or entry.name == "" then return nil, "missing name" end
    if type(entry.file) ~= "string" or not entry.file:match("^[%w_%-/]+$") then return nil, "bad file" end
    if entry.shape ~= "square" and entry.shape ~= "wide" then return nil, "shape must be square or wide" end
    if not (IsPositiveInteger(entry.width) and IsPositiveInteger(entry.height)) then return nil, "bad size" end
    if not IsTextureSize(entry.texWidth, entry.texHeight) then return nil, "texture size must be powers of two up to 1024" end
    if entry.tags ~= nil and type(entry.tags) ~= "table" then return nil, "tags must be a list" end
    if entry.category ~= nil and (type(entry.category) ~= "string" or entry.category == "") then
        return nil, "category must be a name"
    end
    if entry.aliases ~= nil and type(entry.aliases) ~= "table" then return nil, "aliases must be a list" end
    if type(entry.credit) ~= "table" or type(entry.credit.source) ~= "string" or type(entry.credit.license) ~= "string" then
        return nil, "credit needs source and license"
    end
    local anim = entry.anim
    if anim == nil then
        if entry.width > entry.texWidth or entry.height > entry.texHeight then return nil, "art larger than texture" end
        return true
    end
    if type(anim) ~= "table" then return nil, "anim must be a table" end
    -- fps may be fractional: the tool halves it when it drops frames to fit the sheet.
    if not (IsPositiveInteger(anim.cols) and IsPositiveInteger(anim.rows) and IsPositiveInteger(anim.frames)
        and type(anim.fps) == "number" and anim.fps > 0 and anim.fps <= MAX_FPS) then
        return nil, "anim needs cols, rows, frames and fps (up to 60)"
    end
    if anim.frames > anim.cols * anim.rows then return nil, "more frames than grid cells" end
    local frame = Icons.ANIM_FRAME[entry.shape]
    if entry.width > frame[1] or entry.height > frame[2] then return nil, "frame larger than the shape allows" end
    if anim.cols * entry.width > entry.texWidth or anim.rows * entry.height > entry.texHeight then
        return nil, "grid larger than texture"
    end
    local thumb = entry.thumb
    if type(thumb) ~= "table" or type(thumb.file) ~= "string" or not thumb.file:match("^[%w_%-/]+$")
        or not IsTextureSize(thumb.texWidth, thumb.texHeight) then
        return nil, "animated icons need a thumb"
    end
    return true
end

local library        -- key -> entry (aliases included)
local libraryList    -- ordered list of entries, as in the manifest
local devEntries = {} -- entry -> true for entries from the development library

local function AddEntries(entries, label, isDev)
    for index, entry in ipairs(entries) do
        local ok, reason = Icons.ValidateLibraryEntry(entry)
        if ok and library[entry.key] then
            ok, reason = nil, "duplicate key"
        end
        if ok then
            library[entry.key] = entry
            libraryList[#libraryList + 1] = entry
            devEntries[entry] = isDev or nil
        else
            ns.ReportError(("%s entry %d (%s): %s"):format(label, index, tostring(entry.key), reason))
        end
    end
end

local function BuildLibrary()
    library, libraryList = {}, {}
    AddEntries(ns.LibraryManifest, "library", false)
    if type(HeraldryDevLibrary) == "table" then
        AddEntries(HeraldryDevLibrary, "development library", true)
    end
    for _, entry in ipairs(libraryList) do
        for _, alias in ipairs(entry.aliases or {}) do
            if not library[alias] then library[alias] = entry end
        end
    end
end

function Icons:GetLibrary()
    if not libraryList then BuildLibrary() end
    return libraryList
end

-- The library's categories in manifest order (entries without one are left out).
local libraryCategories
function Icons:GetLibraryCategories()
    if not libraryCategories then
        libraryCategories = {}
        local seen = {}
        for _, entry in ipairs(self:GetLibrary()) do
            local category = entry.category
            if category and not seen[category] then
                seen[category] = true
                libraryCategories[#libraryCategories + 1] = category
            end
        end
    end
    return libraryCategories
end

-- Search text for an entry: its name and tags, folded once, hyphens as spaces, padded so
-- every word starts after a space (" crowned skull undead lich king ").
local librarySearch = setmetatable({}, { __mode = "k" })
function Icons.LibrarySearchText(entry)
    local text = librarySearch[entry]
    if not text then
        local words = entry.name .. " " .. table.concat(entry.tags or {}, " ")
        text = " " .. ns.Identity.Fold((words:gsub("%-", " "))) .. " "
        librarySearch[entry] = text
    end
    return text
end

-- True when every word of the folded query starts a word of `text` (from LibrarySearchText):
-- "ice" finds Ice cube and Frost, not Jeweled chalice; "death kn" finds Death knight tags.
function Icons.MatchesWords(text, query)
    -- Hyphens count as spaces in the query too ("Two-handed sword", "death-knight").
    for word in query:gsub("%-", " "):gmatch("[^ ]+") do
        if not text:find(" " .. word, 1, true) then return false end
    end
    return true
end

local function LibraryPath(entry, file)
    return (devEntries[entry] and DEV_LIBRARY_PATH or LIBRARY_PATH) .. file:gsub("/", "\\")
end

--------------------------------------------------------------------------------
-- TwitchEmotes (optional). TwitchEmotes keeps every emote in two globals that other emote
-- packs register into too (TwitchEmotes_Giga, ...):
--   TwitchEmotes_defaultpack[name] = "path.tga:height:width"   (the |T escape's order)
--   TwitchEmotes_animation_metadata[path] = { nFrames, frameWidth, frameHeight,
--       imageWidth, imageHeight, framerate }   a vertical strip of frames
-- Read-only; the art ships in those add-ons, not here. Since packs write the data
-- themselves, every animation field is checked before use.
--------------------------------------------------------------------------------
local function TwitchEmotesLoaded()
    return C_AddOns.IsAddOnLoaded("TwitchEmotes") and type(TwitchEmotes_defaultpack) == "table"
end
Icons.TwitchEmotesLoaded = TwitchEmotesLoaded

local MAX_TEXTURE_SIDE = 8192 -- the tallest strips third-party packs ship

local addOnTitles = {} -- add-on folder -> readable title

-- A pack's own title from its TOC, without colour codes and inline textures.
local function AddOnTitle(folder)
    local title = addOnTitles[folder]
    if not title then
        title = C_AddOns.GetAddOnMetadata(folder, "Title") or folder
        title = ns.Trim(title:gsub("|T.-|t", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
        if title == "" then title = folder end
        addOnTitles[folder] = title
    end
    return title
end

-- The category an emote's path belongs to, as key, label: a subfolder under the pack's
-- emotes folder ("...\Emotes\Pepes\EZ.tga" -> "Pepes"), else the pack itself, labelled
-- with its title ("...\TwitchEmotes_Giga\emotes\x.tga" -> "Giga Twitch Emotes").
local function TwitchCategory(path)
    local folder = path:match("\\[Ee][Mm][Oo][Tt][Ee][Ss]\\([^\\]+)\\[^\\]+$")
    if folder then return folder, folder end
    local addOn = path:match("^[Ii]nterface\\[Aa]dd[Oo]ns\\([^\\]+)\\")
    if addOn then return addOn, AddOnTitle(addOn) end
    return L.SOURCE_TWITCH, L.SOURCE_TWITCH
end
Icons.TwitchCategory = TwitchCategory

local function PositiveNumber(value)
    return type(value) == "number" and value > 0 and value <= MAX_TEXTURE_SIDE and value
end

-- Checked animation data for a strip, or nil. Also returns the first frame's tex coords
-- when at least that part makes sense, for a still image of an unusable strip.
local function ReadStrip(meta)
    if type(meta) ~= "table" then return nil end
    local frameWidth, frameHeight = PositiveNumber(meta.frameWidth), PositiveNumber(meta.frameHeight)
    local imageWidth = PositiveNumber(meta.imageWidth) or frameWidth
    local imageHeight = PositiveNumber(meta.imageHeight)
    if not (frameWidth and frameHeight and imageWidth and imageHeight
        and frameWidth <= imageWidth and frameHeight <= imageHeight) then
        return nil
    end
    local firstFrame = { 0, frameWidth / imageWidth, 0, frameHeight / imageHeight }
    local frames, fps = PositiveNumber(meta.nFrames), PositiveNumber(meta.framerate)
    if not (frames and fps and frames % 1 == 0 and frames > 1 and frames * frameHeight <= imageHeight) then
        return nil, firstFrame
    end
    return {
        rows = frames, cols = 1, frames = frames, duration = frames / fps,
        frameWidth = frameWidth, frameHeight = frameHeight,
    }, firstFrame
end

local function TwitchSpec(emote)
    local value = TwitchEmotes_defaultpack[emote]
    if type(value) ~= "string" then return nil end
    local path, height, width = value:match("^(.-):(%d+):(%d+)$")
    path = path or value
    height, width = tonumber(height), tonumber(width)
    local _, categoryLabel = TwitchCategory(path)
    local spec = {
        texture = path, coords = FULL_COORDS, label = emote, sourceLabel = L.SOURCE_TWITCH,
        category = categoryLabel,
        aspect = (width and height and width > 0 and height > 0) and width / height or 1,
    }
    local meta = type(TwitchEmotes_animation_metadata) == "table" and TwitchEmotes_animation_metadata[path]
    local anim, firstFrame = ReadStrip(meta)
    if firstFrame then
        local frameWidth, frameHeight = PositiveNumber(meta.frameWidth), PositiveNumber(meta.frameHeight)
        spec.aspect = frameWidth / frameHeight
        -- The strip's first frame, without the padding some packs add to its width.
        spec.thumbCoords = firstFrame
        if anim then
            spec.anim = anim
        else
            -- Animation data that doesn't add up: show the first frame, still.
            spec.coords = firstFrame
        end
    end
    return spec
end
Icons.TwitchSpec = TwitchSpec

-- Sorted list of { name =, folded =, category =, categoryLabel =, labelFolded = } and
-- the sorted categories ({ key =, label = }). Built on first use, after login, when the
-- packs that load with TwitchEmotes have registered; rebuilt by RefreshTwitchEmotes if
-- a pack registers emotes later.
local twitchList, twitchCategories
local twitchCount -- emotes registered when the list or the first Twitch spec was made

local function CountTwitchEmotes()
    local count = 0
    for _ in pairs(TwitchEmotes_defaultpack) do count = count + 1 end
    return count
end

local function BuildTwitchEmotes()
    twitchList, twitchCategories = {}, {}
    if not TwitchEmotesLoaded() then return end
    twitchCount = CountTwitchEmotes()
    local seen = {}
    for emote, value in pairs(TwitchEmotes_defaultpack) do
        if type(emote) == "string" and type(value) == "string" and #emote <= MAX_NAME_LENGTH
            and not emote:find("[%c:]") then
            local key, label = TwitchCategory(value)
            twitchList[#twitchList + 1] = {
                name = emote, folded = emote:lower(), category = key, categoryLabel = label,
                labelFolded = label:lower(),
            }
            if not seen[key] then
                seen[key] = true
                twitchCategories[#twitchCategories + 1] = { key = key, label = label }
            end
        end
    end
    table.sort(twitchList, function(a, b) return a.folded < b.folded end)
    table.sort(twitchCategories, function(a, b) return a.label:lower() < b.label:lower() end)
end

function Icons:GetTwitchEmotes()
    if not twitchList then BuildTwitchEmotes() end
    return twitchList, twitchCategories
end

local specCache = {}

-- Packs that register after login (load on demand) reach plates and lists here.
ns.RegisterEvent("PLAYER_LOGIN", function()
    ns.RegisterEvent("ADDON_LOADED", function()
        if Icons:RefreshTwitchEmotes() then ns.Fire("ICONS_CHANGED") end
    end)
end)

-- Rebuilds the list when the number of registered emotes has changed since it was built, which is
-- how newly registered packs show up. A pack that only replaces existing emotes after login isn't
-- noticed until the next /reload. Returns true when something changed, after dropping cached Twitch
-- specs so plates pick up the new art.
function Icons:RefreshTwitchEmotes()
    if not twitchCount or not TwitchEmotesLoaded() or CountTwitchEmotes() == twitchCount then
        return false
    end
    if twitchList then
        BuildTwitchEmotes()
    else
        twitchCount = CountTwitchEmotes()
    end
    for id in pairs(specCache) do
        if Icons.ParseId(id) == "twitch" then specCache[id] = nil end
    end
    return true
end

--------------------------------------------------------------------------------
-- Specs
--------------------------------------------------------------------------------
local function LibrarySpec(entry)
    local spec = {
        texture = LibraryPath(entry, entry.file),
        aspect = entry.width / entry.height,
        label = entry.name,
        sourceLabel = L.SOURCE_LIBRARY,
        entry = entry,
    }
    if entry.anim then
        local anim = entry.anim
        spec.coords = FULL_COORDS
        spec.anim = {
            rows = anim.rows, cols = anim.cols, frames = anim.frames, duration = anim.frames / anim.fps,
            frameWidth = entry.width, frameHeight = entry.height,
        }
        spec.thumbTexture = LibraryPath(entry, entry.thumb.file)
        spec.thumbCoords = { 0, entry.width / entry.thumb.texWidth, 0, entry.height / entry.thumb.texHeight }
    else
        spec.coords = { 0, entry.width / entry.texWidth, 0, entry.height / entry.texHeight }
    end
    return spec
end

local function CustomSpec(file)
    local parsed = Icons.ParseCustomName(file)
    local spec = {
        texture = CUSTOM_PATH .. parsed.file,
        coords = FULL_COORDS,
        aspect = parsed.shape == "wide" and 2 or 1,
        label = parsed.file,
        sourceLabel = L.SOURCE_CUSTOM,
    }
    if parsed.anim then
        local frame = Icons.ANIM_FRAME[parsed.shape]
        local anim = parsed.anim
        spec.anim = {
            rows = anim.rows, cols = anim.cols, frames = anim.frames, duration = anim.frames / anim.fps,
            frameWidth = frame[1], frameHeight = frame[2],
        }
    end
    return spec
end

local function GameSpec(fileID)
    return {
        texture = fileID, coords = GAME_ICON_COORDS, aspect = 1,
        label = ns.GameIcons:GetIconName(fileID) or L.GAME_ICON_ID:format(fileID),
        sourceLabel = L.SOURCE_GAME,
    }
end

-- requires: the add-on the icon comes from, when that is why it is missing.
local function MissingSpec(id, requires)
    local spec = GameSpec(Icons.MISSING_ICON)
    spec.label, spec.missing, spec.requires = id, true, requires
    return spec
end

-- id -> spec, or nil for "none" and malformed ids. Ids that are well formed but not
-- available here resolve to the question mark. Custom files resolve whether or not
-- they are registered on the Custom page, so rules using them keep working.
function Icons:Resolve(id)
    local spec = specCache[id]
    if spec then return spec end
    local source, value = Icons.ParseId(id)
    if source == "lib" then
        local entry = (self:GetLibrary() and library[value])
        spec = entry and LibrarySpec(entry) or MissingSpec(id)
    elseif source == "game" then
        spec = GameSpec(value)
    elseif source == "twitch" then
        if TwitchEmotesLoaded() then
            twitchCount = twitchCount or CountTwitchEmotes()
            spec = TwitchSpec(value) or MissingSpec(id)
        else
            spec = MissingSpec(id, "TwitchEmotes")
        end
    elseif source == "custom" then
        spec = CustomSpec(value)
    else
        return nil
    end
    spec.id = id
    specCache[id] = spec
    return spec
end

-- Game icon specs are cheap to rebuild: dropped when the picker closes (thousands may
-- have been browsed) and when the spell index finishes (their labels improve).
function Icons:ForgetGameSpecs()
    for id in pairs(specCache) do
        if Icons.ParseId(id) == "game" then specCache[id] = nil end
    end
end

-- One line for lists: "Kachow (Library)", "Fireball (Game icon)".
function Icons:Describe(id)
    if id == "none" then return L.ICON_NONE end
    local spec = id and self:Resolve(id)
    if not spec then return L.ICON_NOT_SET end
    if spec.requires then return L.ICON_NEEDS_ADDON:format(spec.requires) end
    if spec.missing then return L.ICON_MISSING:format(id) end
    return L.ICON_DESCRIPTION:format(spec.label, spec.sourceLabel)
end

--------------------------------------------------------------------------------
-- Custom icons
--------------------------------------------------------------------------------
-- The custom folder is a separate "add-on" folder the player creates; it never needs a
-- TOC, so this only tells the UI whether the player has set one up and loaded it.
function Icons.CustomFolderHint()
    return CUSTOM_PATH, CUSTOM_ADDON
end

--------------------------------------------------------------------------------
-- Region: one texture showing one icon, static or animated.
--------------------------------------------------------------------------------
local Region = {}
Region.__index = Region

function Icons.CreateRegion(parent, layer, subLevel)
    local texture = parent:CreateTexture(nil, layer or "ARTWORK", nil, subLevel)
    -- Plates move every frame; snapping makes small icons shimmer against the name.
    texture:SetSnapToPixelGrid(false)
    texture:SetTexelSnappingBias(0)
    texture:Hide()
    return setmetatable({ texture = texture, animate = true }, Region)
end

-- static: draw the thumbnail / first frame instead of animating (picker grid cells).
-- Custom sheets have no thumbnail and an unknown size, so they always animate.
function Region:SetIcon(spec, static)
    local useThumb = (static and spec.anim and spec.thumbCoords) and true or false
    if self.spec == spec and self.static == useThumb then return end
    self.spec, self.static = spec, useThumb
    self:StopAnimation()
    local texture = self.texture
    if useThumb then
        texture:SetTexture(spec.thumbTexture or spec.texture)
        local coords = spec.thumbCoords
        texture:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
        return
    end
    texture:SetTexture(spec.texture)
    local coords = spec.coords
    texture:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
    if spec.anim then
        self:EnsureAnimation()
        local anim, flip = spec.anim, self.flip
        flip:SetFlipBookRows(anim.rows)
        flip:SetFlipBookColumns(anim.cols)
        flip:SetFlipBookFrames(anim.frames)
        flip:SetDuration(anim.duration)
        -- Explicit frame size in texture pixels: the grid rarely fills the sheet
        -- (16x13 frames on 1024x1024), and 0 would slice the whole texture evenly.
        flip:SetFlipBookFrameWidth(anim.frameWidth)
        flip:SetFlipBookFrameHeight(anim.frameHeight)
        if texture:IsShown() then self:PlayAnimation() end
    end
end

function Region:EnsureAnimation()
    if self.group then return end
    self.group = self.texture:CreateAnimationGroup()
    self.group:SetLooping("REPEAT")
    self.flip = self.group:CreateAnimation("FlipBook")
end

-- The group's own state is asked every time: the client can stop a group while its
-- texture is hidden (culled plate, loading screen), and a stale flag would then leave
-- the whole sprite sheet showing.
function Region:PlayAnimation()
    if not self.animate then return end
    local spec = self.spec
    if not (spec and spec.anim and not self.static) then return end
    if not self.group:IsPlaying() then self.group:Play() end
end

function Region:StopAnimation()
    if self.group and self.group:IsPlaying() then self.group:Stop() end
end

function Region:Show()
    self.texture:Show()
    self:PlayAnimation()
end

function Region:Hide()
    self:StopAnimation()
    self.texture:Hide()
end

function Region:Clear()
    self:Hide()
    self.spec = nil
    self.texture:SetTexture(nil)
end

-- Fit the icon inside a box of the given size, keeping its aspect, centred on anchor.
function Region:FitInto(anchor, boxWidth, boxHeight)
    local aspect = self.spec and self.spec.aspect or 1
    local width, height = boxWidth, boxWidth / aspect
    if height > boxHeight then
        width, height = boxHeight * aspect, boxHeight
    end
    local texture = self.texture
    texture:ClearAllPoints()
    texture:SetPoint("TOPLEFT", anchor, "CENTER", -width / 2, height / 2)
    texture:SetPoint("BOTTOMRIGHT", anchor, "CENTER", width / 2, -height / 2)
end
