-- Headless tests for Heraldry's pure logic. They load the shipped add-on files (not
-- copies) into one namespace, the way the client does, on top of tests\wowstub.lua.
--
-- Run from the repository root:  .tools\lua51\lua5.1.exe tests\run.lua

local stub = dofile("tests/wowstub.lua")

local ADDON = "Heraldry"
local FILES = {
    "Locales/enUS.lua", "Core.lua", "Identity.lua", "Library.lua", "Icons.lua", "IconNames.lua", "GameIcons.lua",
    "Database.lua", "Matching.lua", "Share.lua", "Plates/Plates.lua",
}

-- The gitignored development library add-on, when present, is validated too.
local devManifest = io.open("HeraldryDev/Library.lua", "r")
if devManifest then
    devManifest:close()
    dofile("HeraldryDev/Library.lua")
end

local ns = {}
for _, file in ipairs(FILES) do
    local chunk = assert(loadfile(ADDON .. "/" .. file))
    chunk(ADDON, ns)
end
local L, Identity, Icons, DB, Rules, Share, Plates = ns.L, ns.Identity, ns.Icons, ns.DB, ns.Rules, ns.Share, ns.Plates

--------------------------------------------------------------------------------
-- A tiny runner
--------------------------------------------------------------------------------
local passed, failed = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then
        passed = passed + 1
    else
        failed = failed + 1
        print("FAIL " .. name .. "\n     " .. tostring(err))
    end
end
local function eq(actual, expected, label)
    if actual ~= expected then
        error(("%s: expected %s, got %s"):format(label or "value", tostring(expected), tostring(actual)), 2)
    end
end
local function near(actual, expected, label)
    if math.abs(actual - expected) > 1e-9 then
        error(("%s: expected %s, got %s"):format(label or "value", tostring(expected), tostring(actual)), 2)
    end
end
local function truthy(value, label)
    if not value then error((label or "value") .. " should be true", 2) end
end

local function freshProfile()
    return DB.NewProfile()
end

--------------------------------------------------------------------------------
-- Identity
--------------------------------------------------------------------------------
test("ruleset tokens", function()
    local rules = Enum.GameRule
    local function ruleset(active)
        local set = {}
        for _, rule in ipairs(active) do set[rule] = true end
        return Identity.ComputeRuleset(function(rule) return set[rule] == true end, rules)
    end
    eq(ruleset({}), "pve", "no flags")
    eq(ruleset({ rules.PvPRuleset }), "pvp", "pvp")
    eq(ruleset({ rules.RPRuleset }), "rp", "rp")
    eq(ruleset({ rules.RPRuleset, rules.PvPRuleset }), "rppvp", "rp-pvp is not pvp")
    eq(ruleset({ rules.HardcoreRuleset }), "hc", "hardcore")
    eq(ruleset({ rules.HardcoreRuleset, rules.PvPRuleset }), "hc+pvp", "unknown combination stays raw")
    eq(ruleset({ rules.MinimapDisabled }), "pve", "non-ruleset rules are ignored")
    local future = { HardcoreRuleset = 1, PvPRuleset = 2, RPRuleset = 3, FantasyRuleset = 9 }
    eq(Identity.ComputeRuleset(function(rule) return rule == 9 end, future), "fantasy", "new flag gets its own token")
end)

test("ruleset display names", function()
    eq(Identity.RulesetName("rppvp"), "RP PvP")
    eq(Identity.RulesetName("hc+pvp"), "hc+pvp", "unknown tokens show as is")
end)

test("name folding", function()
    eq(Identity.Fold("  Kachow   Racing  "), "kachow racing", "trim and collapse")
    eq(Identity.Fold("ÉLISE"), "élise", "Latin-1 uppercase")
    eq(Identity.Fold("ÀÉÎÕÜÞ"), "àéîõüþ", "Latin-1 range")
    eq(Identity.Fold("×"), "×", "multiplication sign has no case")
    eq(Identity.Fold("ĀĘŁŃŒŠŸŽ"), "āęłńœšÿž", "Latin Extended-A pairs")
    eq(Identity.Fold("ā"), "ā", "lowercase stays")
end)

test("player and guild keys", function()
    eq(Identity.PlayerKey("Somebody", "Stormwind"), "somebody stormwind")
    eq(Identity.PlayerKey("Somebody Stormwind", "Stormwind"), "somebody stormwind", "surname already in name")
    eq(Identity.PlayerKey("Somebody", nil), "somebody", "no surname")
    eq(Identity.PlayerKey("Somebody", ""), "somebody", "empty surname")
    eq(Identity.PlayerKeyFromText(" somebody   STORMWIND "), "somebody stormwind", "typed")
    eq(Identity.GuildKey("pve", " Kachow "), "pve/kachow")
    eq(select(2, Identity.SplitGuildKey("rppvp/the order")), "the order")

    local separators = Constants.CharacterNameSeparatorConsts
    separators.CHARACTERNAME_SURNAME_SEPARATOR = "·"
    eq(Identity.PlayerKey("Somebody", "Stormwind"), "somebody stormwind", "game separator becomes a space")
    eq(Identity.PlayerKeyFromText("Somebody·Stormwind"), "somebody stormwind")
    separators.CHARACTERNAME_SURNAME_SEPARATOR = " "
end)

--------------------------------------------------------------------------------
-- Matching
--------------------------------------------------------------------------------
test("rule precedence", function()
    local profile = freshProfile()
    profile.guilds["pve/kachow"] = { name = "Kachow", icon = "game:1" }
    profile.players["fast racer"] = { name = "Fast Racer", icon = "game:2" }
    profile.players["quiet one"] = { name = "Quiet One", icon = "none" }
    profile.myGuild = { enabled = true, icon = "game:3" }

    eq(Rules.Match(profile, "fast racer", "pve/kachow", false, true), "game:2", "player beats guild")
    local icon, reason = Rules.Match(profile, "quiet one", "pve/kachow", false, true)
    eq(icon, nil, "player none hides guild")
    eq(reason, "player-none")
    eq(Rules.Match(profile, "someone", "pve/kachow", false, true), "game:1", "guild beats my guild")
    eq(Rules.Match(profile, "someone", "pve/other", false, true), "game:3", "my guild")
    eq(Rules.Match(profile, "someone", "pve/other", false, false), nil, "not in my guild")
    eq(Rules.Match(profile, "someone", nil, false, nil), nil, "nothing known")

    local secret = stub.Secret()
    local secretIcon, secretReason, show = Rules.Match(profile, nil, nil, true, secret)
    eq(secretIcon, "game:3", "secret my-guild still yields the icon")
    eq(secretReason, "my-guild-secret")
    eq(show, secret, "the secret is passed through untouched")

    eq(Rules.Match(profile, nil, "pve/kachow", true, nil), "game:1", "hidden name falls back to guild")
    profile.display.strictPlayers = true
    eq(Rules.Match(profile, nil, "pve/kachow", true, nil), nil, "strict: hidden name shows nothing")

    profile.myGuild.enabled = false
    eq(Rules.Match(profile, "someone", "pve/other", false, true), nil, "my guild off")
end)

test("reading units", function()
    stub.units.nameplate1 = { player = true, name = "Fast", surname = "Racer", guild = "Kachow" }
    local facts = Rules:ReadUnit("nameplate1")
    eq(facts.playerKey, "fast racer")
    eq(facts.guildKey, Identity:GetRuleset() .. "/kachow")
    eq(facts.fullName, "Fast Racer")

    stub.units.nameplate2 = { player = true, name = stub.Secret(), guild = stub.Secret() }
    facts = Rules:ReadUnit("nameplate2")
    truthy(facts.nameSecret, "name secret")
    truthy(facts.guildSecret, "guild secret")
    eq(facts.playerKey, nil)
    eq(facts.guildKey, nil)

    stub.units.nameplate3 = { player = false, name = "Boar" }
    eq(Rules:ReadUnit("nameplate3").isPlayer, false)
end)

test("typed rule names", function()
    local key, name = Rules.KeyForText("guilds", "  Kachow  ")
    eq(key, Identity:GetRuleset() .. "/kachow")
    eq(name, "Kachow")
    local missing, _, problem = Rules.KeyForText("players", "   ")
    eq(missing, nil)
    eq(problem, L.ERROR_EMPTY_NAME)
    eq(Rules.KeyForText("guilds", "bad/name"), nil, "slash is rejected")
end)

--------------------------------------------------------------------------------
-- Icons
--------------------------------------------------------------------------------
test("icon ids", function()
    eq(Icons.ParseId("lib:kachow"), "lib")
    eq(select(2, Icons.ParseId("game:134400")), 134400)
    eq(Icons.ParseId("twitch:catJAM"), "twitch")
    eq(Icons.ParseId("custom:mcqueen_wide"), "custom")
    eq(Icons.ParseId("none"), "none")
    eq(Icons.ParseId("lib:Bad Key"), nil)
    eq(Icons.ParseId("game:abc"), nil)
    eq(Icons.ParseId("foo:bar"), nil)
    eq(Icons.ParseId(42), nil)
    eq(Icons.IsValidId("none"), false, "none only where allowed")
    eq(Icons.IsValidId("none", true), true)
end)

test("custom file names", function()
    local spec = Icons.ParseCustomName("mcqueen_wide.tga")
    eq(spec.file, "mcqueen_wide")
    eq(spec.shape, "wide")
    eq(spec.anim, nil)
    spec = Icons.ParseCustomName("dance_anim8x8_60_20")
    eq(spec.shape, "square")
    eq(spec.anim.cols, 8)
    eq(spec.anim.frames, 60)
    spec = Icons.ParseCustomName("parrot_wide_anim8x16_100_12.BLP")
    eq(spec.shape, "wide")
    eq(spec.anim.rows, 16)
    eq(Icons.ParseCustomName("too_many_anim2x2_5_10"), nil, "frames exceed grid")
    eq(Icons.ParseCustomName("too_wide_wide_anim9x1_9_10"), nil, "sheet wider than 1024")
    eq(Icons.ParseCustomName("bad name"), nil, "space")
    eq(Icons.ParseCustomName("../escape"), nil, "path")
    eq(Icons.ParseCustomName(""), nil, "empty")
end)

local function staticEntry()
    return {
        key = "kachow", name = "Kachow", file = "kachow", shape = "wide",
        width = 244, height = 128, texWidth = 256, texHeight = 128,
        credit = { source = "test", license = "CC0-1.0" },
    }
end

local function animatedEntry()
    return {
        key = "dance", name = "Dance", file = "dance", shape = "square",
        width = 64, height = 64, texWidth = 1024, texHeight = 1024,
        anim = { cols = 16, rows = 13, frames = 198, fps = 25 },
        thumb = { file = "dance_thumb", texWidth = 64, texHeight = 64 },
        credit = { source = "7TV", license = "permission", author = "someone" },
    }
end

test("library entry validation", function()
    truthy(Icons.ValidateLibraryEntry(staticEntry()), "static")
    truthy(Icons.ValidateLibraryEntry(animatedEntry()), "animated")
    local function rejects(mutate, label)
        local entry = mutate(animatedEntry()) or nil
        local ok = Icons.ValidateLibraryEntry(entry)
        eq(ok, nil, label)
    end
    rejects(function(e) e.anim.rows = 17; return e end, "grid taller than texture")
    rejects(function(e) e.anim.frames = 300; return e end, "more frames than cells")
    rejects(function(e) e.texWidth = 1000; return e end, "texture not a power of two")
    rejects(function(e) e.thumb = nil; return e end, "animated without thumb")
    rejects(function(e) e.credit = nil; return e end, "no credit")
    rejects(function(e) e.key = "Bad"; return e end, "uppercase key")
    rejects(function(e) e.width = 80; return e end, "frame larger than shape")
end)

test("shipped manifest (and the dev library, if present) is valid", function()
    for _, manifest in ipairs({ ns.LibraryManifest, HeraldryDevLibrary or {} }) do
        for index, entry in ipairs(manifest) do
            local ok, reason = Icons.ValidateLibraryEntry(entry)
            truthy(ok, ("entry %d (%s): %s"):format(index, tostring(entry.key), tostring(reason)))
        end
    end
end)

test("library index, aliases and specs", function()
    local manifest = ns.LibraryManifest
    local saved = {}
    for i, entry in ipairs(manifest) do saved[i] = entry end
    for i = #manifest, 1, -1 do manifest[i] = nil end
    local renamed = animatedEntry()
    renamed.aliases = { "old_dance" }
    manifest[1], manifest[2], manifest[3] = staticEntry(), renamed, staticEntry()

    -- Icons builds its index once; load a fresh copy of the file to rebuild it.
    local devLibrary = HeraldryDevLibrary
    HeraldryDevLibrary = nil
    stub.errors = {}
    local chunk = assert(loadfile(ADDON .. "/Icons.lua"))
    local scratch = setmetatable({ LibraryManifest = manifest }, { __index = ns })
    chunk(ADDON, scratch)
    local icons = scratch.Icons
    eq(#icons:GetLibrary(), 2, "duplicate key skipped")
    eq(#stub.errors, 1, "duplicate reported")
    local wide = icons:Resolve("lib:kachow")
    eq(wide.aspect, 244 / 128, "wide aspect")
    eq(wide.coords[2], 244 / 256, "crop to art")
    local animated = icons:Resolve("lib:old_dance")
    eq(animated.entry.key, "dance", "alias resolves")
    eq(animated.anim.duration, 198 / 25, "duration = frames / fps")
    eq(animated.anim.frameWidth, 64, "explicit frame width")
    eq(icons:Resolve("lib:gone").missing, true, "unknown key shows the question mark")
    eq(icons:Resolve("twitch:catJAM").requires, "TwitchEmotes", "twitch without the add-on")
    eq(icons:Resolve("none"), nil)

    for i = #manifest, 1, -1 do manifest[i] = nil end
    for i, entry in ipairs(saved) do manifest[i] = entry end
    HeraldryDevLibrary = devLibrary
end)

test("development library entries load from their own add-on", function()
    local devLibrary = HeraldryDevLibrary
    HeraldryDevLibrary = { staticEntry() }
    HeraldryDevLibrary[1].key = "dev_only"
    local scratch = setmetatable({ LibraryManifest = {} }, { __index = ns })
    assert(loadfile(ADDON .. "/Icons.lua"))(ADDON, scratch)
    local spec = scratch.Icons:Resolve("lib:dev_only")
    truthy(spec.texture:find("HeraldryDev", 1, true), "dev art comes from the HeraldryDev folder")
    HeraldryDevLibrary = devLibrary
end)

--------------------------------------------------------------------------------
-- Database
--------------------------------------------------------------------------------
test("migrations", function()
    local store = {}
    truthy(DB.Migrate(store), "fresh store")
    eq(store.version, DB.VERSION)
    local newer = { version = DB.VERSION + 1, profile = { keep = true } }
    eq(DB.Migrate(newer), false, "newer data is left alone")
    eq(newer.version, DB.VERSION + 1)

    -- The runner applies every step in order and stamps each version.
    local saved = DB.migrations
    local steps = {}
    DB.migrations = { function() steps[#steps + 1] = 1 end }
    local old = { version = 0 }
    DB.Migrate(old)
    DB.migrations = saved
    eq(#steps, 1, "step 1 ran")
    eq(old.version, DB.VERSION)
end)

test("profile normalization", function()
    local profile = DB.NormalizeProfile({
        myGuild = { enabled = "yes", icon = "bogus" },
        guilds = { ["pve/a"] = { name = "A", icon = "game:1" }, ["pve/b"] = { name = "B", icon = "none" }, [3] = {} },
        players = { ["x y"] = { name = "X Y", icon = "none" }, ["z"] = "oops" },
        custom = { "one", "one", "bad name", "two_wide" },
        display = { scale = 99, position = "MIDDLE", gap = "wide", alpha = 0 },
    })
    eq(profile.myGuild.enabled, false)
    eq(profile.myGuild.icon, nil, "invalid icon dropped")
    truthy(profile.guilds["pve/a"], "valid guild kept")
    eq(profile.guilds["pve/b"], nil, "guilds can't use none")
    truthy(profile.players["x y"], "players can use none")
    eq(profile.players.z, nil)
    eq(#profile.custom, 2, "custom deduped and validated")
    eq(profile.display.scale, DB.RANGES.scale.max, "clamped")
    eq(profile.display.alpha, DB.RANGES.alpha.min, "clamped")
    eq(profile.display.position, "LEFT", "invalid position reset")
    eq(profile.display.gap, DB.DISPLAY_DEFAULTS.gap, "wrong type reset")
    eq(profile.display.enemy, true, "missing filled")
    eq(DB.NormalizeProfile(nil).display.enabled, true, "nil becomes a fresh profile")
end)

test("character profile copy semantics", function()
    HeraldryDB, HeraldryCharDB = nil, nil
    DB:Load()
    eq(HeraldryDB.version, DB.VERSION)
    eq(ns.profile, HeraldryDB.profile, "account profile active")

    ns.profile.guilds["pve/kachow"] = { name = "Kachow", icon = "game:1" }
    DB:SetUseCharacterProfile(true)
    eq(ns.profile, HeraldryCharDB.profile, "character profile active")
    truthy(ns.profile.guilds["pve/kachow"], "copied from account")
    ns.profile.guilds["pve/alts"] = { name = "Alts", icon = "game:2" }
    eq(HeraldryDB.profile.guilds["pve/alts"], nil, "copy is independent")

    DB:SetUseCharacterProfile(false)
    eq(ns.profile, HeraldryDB.profile, "back to account")
    DB:SetUseCharacterProfile(true)
    truthy(ns.profile.guilds["pve/alts"], "character copy kept for later")

    DB:CopyAccountToCharacter()
    eq(ns.profile.guilds["pve/alts"], nil, "fresh copy replaces it")

    DB:Load()
    eq(ns.profile, HeraldryCharDB.profile, "choice survives a reload")
end)

test("picker favorites and recent icons are account-wide", function()
    HeraldryDB, HeraldryCharDB = { ui = { favoriteIcons = { "game:1", "game:1", "bogus" } } }, nil
    DB:Load()
    eq(ns.ui, HeraldryDB.ui)
    eq(#ns.ui.favoriteIcons, 1, "deduplicated and validated")
    eq(#ns.ui.recentIcons, 0)
    local ui = ns.ui
    DB:SetUseCharacterProfile(true)
    eq(ns.ui, ui, "the character profile doesn't split them")
    eq(HeraldryCharDB.profile.favoriteIcons, nil, "not copied into profiles")
end)

--------------------------------------------------------------------------------
-- Sharing
--------------------------------------------------------------------------------
test("base64 round trip", function()
    for length = 0, 40 do
        local bytes = {}
        for i = 1, length do bytes[i] = string.char((i * 37 + length) % 256) end
        local data = table.concat(bytes)
        eq(Share.Base64Decode(Share.Base64Encode(data)), data, "length " .. length)
    end
    eq(Share.Base64Encode("Man"), "TWFu")
    eq(Share.Base64Encode("Ma"), "TWE=")
    eq(Share.Base64Decode("TW=u"), nil, "padding in the middle")
    eq(Share.Base64Decode("TWF"), nil, "bad length")
    eq(Share.Checksum("Wikipedia"), "11e60398", "Adler-32 reference value")
end)

local function sampleProfile()
    local profile = freshProfile()
    profile.myGuild = { enabled = true, icon = "lib:kachow" }
    profile.guilds["pve/kachow"] = { name = "Kachow", icon = "game:134400" }
    profile.guilds["pvp/rivals"] = { name = "Rivals", icon = "twitch:catJAM" }
    profile.players["fast racer"] = { name = "Fast Racer", icon = "none" }
    profile.custom = { "mcqueen_wide" }
    return profile
end

test("export and import round trip", function()
    local options = { myGuild = true, guilds = true, players = true, custom = true, allRulesets = true }
    local text = Share.Encode(Share.Build(sampleProfile(), options, "pve"))
    truthy(text:find("^!Heraldry:1:"), "prefix")

    -- Pasting through chat or Discord can wrap the string.
    local wrapped = text:sub(1, 20) .. "\n  " .. text:sub(21) .. "  \n"
    local payload = assert(Share.Decode(wrapped))
    eq(payload.myGuild, "lib:kachow")
    eq(#payload.guilds, 2)
    eq(#payload.players, 1)
    eq(payload.players[1].icon, "none")
    eq(payload.custom[1], "mcqueen_wide")

    local current = Share.Build(sampleProfile(), { guilds = true }, "pve")
    eq(#current.guilds, 1, "current ruleset only")
end)

test("import rejects bad strings", function()
    local options = { guilds = true }
    local text = Share.Encode(Share.Build(sampleProfile(), options, "pve"))
    eq(select(2, Share.Decode("")), Share.ERRORS.EMPTY)
    eq(select(2, Share.Decode("hello")), Share.ERRORS.FOREIGN)
    eq(select(2, Share.Decode(text:gsub("^!Heraldry:1:", "!Heraldry:9:"))), Share.ERRORS.NEWER)
    eq(select(2, Share.Decode(text:sub(1, -3))), Share.ERRORS.DAMAGED, "cut off")
    local flipped = text:gsub(":(%w)(%w)", function(a, b) return ":" .. b .. a end, 1)
    eq(select(2, Share.Decode(flipped)), Share.ERRORS.DAMAGED, "altered")

    local function encodeBody(body)
        return "!Heraldry:1:" .. Share.Base64Encode(body) .. ":" .. Share.Checksum(body)
    end
    eq(select(2, Share.Decode(encodeBody("G\tpve\tKachow\tlua:os.exit()"))), Share.ERRORS.INVALID, "bad icon")
    eq(select(2, Share.Decode(encodeBody("G\tPvE!\tKachow\tgame:1"))), Share.ERRORS.INVALID, "bad ruleset")
    eq(select(2, Share.Decode(encodeBody("P\tbad/name\tgame:1"))), Share.ERRORS.INVALID, "bad name")
    eq(select(2, Share.Decode(encodeBody("M\tnone"))), Share.ERRORS.INVALID, "my guild can't be none")
    eq(select(2, Share.Decode(encodeBody("X\tfuture record"))), Share.ERRORS.NOTHING, "unknown records skipped")
    truthy(Share.Decode(encodeBody("X\tfuture\nG\tpve\tKachow\tgame:1")), "unknown records don't block")
end)

test("import preview and apply", function()
    local target = freshProfile()
    target.guilds["pve/kachow"] = { name = "Kachow", icon = "game:134400" }
    target.players["fast racer"] = { name = "Fast Racer", icon = "game:5" }
    local options = { myGuild = true, guilds = true, players = true, custom = true, allRulesets = true }
    local payload = Share.Decode(Share.Encode(Share.Build(sampleProfile(), options, "pve")))
    local changes = Share.Diff(target, payload)
    local byStatus = { new = 0, change = 0, same = 0 }
    for _, change in ipairs(changes) do byStatus[change.status] = byStatus[change.status] + 1 end
    eq(byStatus.same, 1, "Kachow unchanged")
    eq(byStatus.change, 1, "Fast Racer changes")
    eq(byStatus.new, 3, "my guild, Rivals, custom")

    for _, change in ipairs(changes) do
        if change.kind == "players" then change.skip = true end
    end
    eq(Share.Apply(target, changes), 3, "skipped and unchanged rows not applied")
    eq(target.players["fast racer"].icon, "game:5", "unticked change kept")
    eq(target.guilds["pvp/rivals"].icon, "twitch:catJAM")
    eq(target.myGuild.enabled, true, "my guild switched on")
    eq(target.custom[1], "mcqueen_wide")
end)

--------------------------------------------------------------------------------
-- Round 2 fixes
--------------------------------------------------------------------------------
test("data from a newer version is never rewritten", function()
    local futureRule = { name = "Kachow", icon = "emoji:racecar" }
    HeraldryDB = { version = DB.VERSION + 1, profile = { guilds = { ["pve/kachow"] = futureRule } } }
    HeraldryCharDB = nil
    DB:Load()
    truthy(DB.newerData, "flagged")
    eq(HeraldryDB.profile.guilds["pve/kachow"], futureRule, "saved rule untouched")
    eq(HeraldryDB.version, DB.VERSION + 1, "version untouched")
    eq(ns.profile.guilds["pve/kachow"], nil, "this session works on a cleaned copy")
    ns.profile.guilds["pve/new"] = { name = "New", icon = "game:1" }
    eq(HeraldryDB.profile.guilds["pve/new"], nil, "edits are not saved")
    HeraldryDB, HeraldryCharDB = nil, nil
    DB:Load()
    eq(DB.newerData, false, "a normal store is not flagged")
end)

test("secret UnitIsPlayer keeps the my-guild path open", function()
    HeraldryDB, HeraldryCharDB = nil, nil
    DB:Load()
    local profile = ns.profile
    profile.myGuild = { enabled = true, icon = "game:3" }
    local myGuild = stub.Secret()
    stub.units.nameplate9 = { player = stub.Secret(), myGuild = myGuild }
    local icon, reason, show, nameHidden = Rules:ResolveUnit("nameplate9", profile)
    eq(icon, "game:3")
    eq(reason, "my-guild-secret")
    eq(show, myGuild)
    eq(nameHidden, true)
    stub.units.nameplate10 = { player = stub.Secret(), myGuild = false }
    eq(Rules:ResolveUnit("nameplate10", profile), nil, "plain false: nothing")
    profile.display.strictPlayers = true
    eq(Rules:ResolveUnit("nameplate9", profile), nil, "strict: unknown identity shows nothing")
end)

test("rules remember who was seen", function()
    stub.units.nameplate11 = { player = true, name = "Seen", surname = "Today", guild = "Seenguild" }
    Rules:ResolveUnit("nameplate11", ns.profile)
    truthy(Rules:WasSeen("players", "seen today"), "player")
    truthy(Rules:WasSeen("guilds", Identity:GetRuleset() .. "/seenguild"), "guild")
    eq(Rules:WasSeen("players", "never seen"), false)
end)

test("library search matches the start of words in names and tags", function()
    local entry = { key = "gi_crowned_skull", name = "Crowned skull", tags = { "undead", "lich king", "death-knight" } }
    local text = Icons.LibrarySearchText(entry)
    truthy(Icons.MatchesWords(text, "skull"), "a word of the name")
    truthy(Icons.MatchesWords(text, "crow"), "a word start")
    truthy(Icons.MatchesWords(text, "lich ki"), "every query word must start a word")
    truthy(Icons.MatchesWords(text, "death knight"), "hyphenated tags match with a space")
    truthy(Icons.MatchesWords(text, "death-knight"), "and with the hyphen typed")
    truthy(Icons.MatchesWords(Icons.LibrarySearchText({ name = "Two-handed sword" }), "two-handed"),
        "a hyphenated name typed as shown")
    truthy(Icons.MatchesWords(text, "crow-"), "a trailing hyphen doesn't stop the match")
    eq(Icons.MatchesWords(text, "rown"), false, "not the middle of a word")
    eq(Icons.MatchesWords(text, "gi_crowned"), false, "the key is not searched")
    eq(Icons.MatchesWords(text, "skull frost"), false, "all words must match")
    eq(Icons.LibrarySearchText(entry), text, "folded once")
end)

test("library categories are validated and listed in manifest order", function()
    local base = { key = "x", name = "X", file = "x", shape = "square", width = 64, height = 64,
        texWidth = 64, texHeight = 64, credit = { source = "s", license = "CC0-1.0" } }
    base.category = "Weapons"
    truthy(Icons.ValidateLibraryEntry(base))
    base.category = ""
    eq(Icons.ValidateLibraryEntry(base), nil, "an empty category is refused")
    base.category = 3
    eq(Icons.ValidateLibraryEntry(base), nil, "a category must be a string")
    local categories = Icons:GetLibraryCategories()
    truthy(#categories > 1, "the shipped library has categories")
    local seen = {}
    for _, category in ipairs(categories) do
        eq(seen[category], nil, "listed once: " .. category)
        seen[category] = true
    end
    eq(categories[1], Icons:GetLibrary()[1].category, "manifest order")
end)

test("the minimap button state is repaired and kept", function()
    local ui = DB.NormalizeUI({ minimap = { hide = "yes", minimapPos = 200 } })
    eq(ui.minimap.hide, false, "only true hides")
    eq(ui.minimap.minimapPos, 200)
    ui = DB.NormalizeUI({ minimap = { hide = true, minimapPos = "left" } })
    eq(ui.minimap.hide, true)
    eq(ui.minimap.minimapPos, nil, "a bad angle is dropped: LibDBIcon uses its default")
    eq(DB.NormalizeUI(nil).minimap.hide, false)
end)

test("minimap clicks: target shortcuts, pages without a target, middle-click clears", function()
    -- The click handler, with the options stubbed to record what was asked of them.
    local calls = {}
    local savedOptions, savedShift = ns.Options, IsShiftKeyDown
    ns.Options = {
        Open = function(_, page) calls[#calls + 1] = "open " .. tostring(page) end,
        Toggle = function() calls[#calls + 1] = "toggle" end,
        EditMyGuild = function() calls[#calls + 1] = "my guild" end,
        EditTargetRule = function(_, kind)
            local key, reason = Rules:TargetSubject(kind)
            if not key then return false, reason end
            calls[#calls + 1] = "edit " .. kind .. " " .. key
            return true
        end,
    }
    local shift = false
    IsShiftKeyDown = function() return shift end
    assert(loadfile(ADDON .. "/MinimapButton.lua"))(ADDON, ns)
    local Click = ns.MinimapButton.Click
    local function last() return calls[#calls] end

    stub.units.target = nil
    Click("LeftButton"); eq(last(), "open players", "no target: click")
    Click("RightButton"); eq(last(), "open guilds", "no target: right-click")
    Click("MiddleButton"); eq(last(), "toggle", "no target: middle-click")
    eq(ns.MinimapButton.ClickLines()[1], L.MINIMAP_TIP_LEFT_PAGE, "tooltip without a target")

    local enabled = ns.profile.display.enabled
    shift = true
    Click("LeftButton"); eq(ns.profile.display.enabled, not enabled, "shift-click toggles icons")
    stub.units.target = { player = true, name = "Goober", surname = "Ppea", guild = "Clickers" }
    local count = #calls
    Click("RightButton"); eq(ns.profile.display.enabled, enabled, "with a target too, any button")
    eq(#calls, count, "shift-click does nothing else")
    shift = false

    local playerKey = Rules:TargetSubject("players")
    local guildKey = Rules:TargetSubject("guilds")
    Click("LeftButton"); eq(last(), "edit players " .. playerKey, "target: click picks for the player")
    Click("RightButton"); eq(last(), "edit guilds " .. guildKey, "target: right-click picks for the guild")
    local lines = ns.MinimapButton.ClickLines()
    eq(lines[1], L.MINIMAP_TIP_LEFT_NAMED:format("Goober Ppea"), "tooltip names the target")
    eq(lines[2], L.MINIMAP_TIP_RIGHT_NAMED:format("Clickers"), "and the guild")

    Rules:Set("players", playerKey, "Goober Ppea", "lib:gi_checked_shield")
    Rules:Set("guilds", guildKey, "Clickers", "lib:gi_checked_shield")
    count = #calls
    truthy(ns.MinimapButton.ClickLines()[3]:find(L.MINIMAP_CLEARED_GUILD:format("Clickers"), 1, true),
        "the middle-click line says what it would remove")
    Click("MiddleButton")
    eq(#calls, count, "middle-click with a target never opens anything")
    eq(Rules:Get("players", playerKey), nil, "player rule removed")
    eq(Rules:Get("guilds", guildKey), nil, "guild rule removed")
    eq(stub.lastMessage:find(L.MINIMAP_CLEARED_PLAYER:format("Goober Ppea"), 1, true) ~= nil, true, "says so")
    eq(ns.MinimapButton.ClickLines()[3], L.MINIMAP_TIP_MIDDLE_NOTHING, "then nothing to remove")
    Click("MiddleButton")
    truthy(stub.lastMessage:find(L.MINIMAP_CLEARED_NOTHING, 1, true), "nothing left to remove")
    ns.MinimapButton.Undo()
    eq(Rules:Get("players", playerKey).icon, "lib:gi_checked_shield", "undo puts the player rule back")
    eq(Rules:Get("guilds", guildKey).name, "Clickers", "and the guild rule")
    ns.MinimapButton.Undo()
    truthy(stub.lastMessage:find(L.UNDO_NOTHING, 1, true), "undo works once")
    Rules:Remove("players", playerKey)
    Rules:Remove("guilds", guildKey)

    Rules:Set("guilds", guildKey, "Clickers", "lib:gi_checked_shield")
    Click("MiddleButton")
    eq(Rules:Get("guilds", guildKey), nil, "a guild rule alone goes too")
    truthy(stub.lastMessage:find(L.MINIMAP_CLEARED_GUILD:format("Clickers"), 1, true), "and is named")

    stub.units.target = { player = true, name = "Lone", surname = "Wolf" }
    Click("RightButton"); eq(last(), "open guilds", "a player in no guild: the Guilds page")
    eq(ns.MinimapButton.ClickLines()[2], L.MINIMAP_TIP_RIGHT_PAGE, "and the tooltip says so")
    Click("LeftButton"); eq(last(), "edit players lone wolf", "click still picks for the player")

    stub.units.target = { player = false, name = "Hogger" }
    Click("LeftButton")
    truthy(stub.lastMessage:find(L.TARGET_NOT_PLAYER, 1, true), "an NPC target says why")
    Click("MiddleButton")
    truthy(stub.lastMessage:find(L.TARGET_NOT_PLAYER, 1, true), "middle-click on an NPC says why")
    eq(ns.MinimapButton.ClickLines()[1], L.MINIMAP_TIP_LEFT_TARGET, "tooltip without a readable name")

    local savedIsUnit = UnitIsUnit
    UnitIsUnit = function() return true end -- the target is you
    stub.units.target = { player = true, name = "Me", surname = "Myself", guild = "Clickers" }
    Click("RightButton"); eq(last(), "my guild", "right-click on yourself edits My guild")
    eq(ns.MinimapButton.ClickLines()[2], L.MINIMAP_TIP_RIGHT_MY_GUILD, "and the tooltip says so")
    UnitIsUnit = savedIsUnit

    stub.units.target = nil
    ns.Options, IsShiftKeyDown = savedOptions, savedShift
end)

test("blizzard plates: the name box comes from the plate, then Forever's layout", function()
    local adapter
    local fakePlates = { RegisterAdapter = function(_, registered) adapter = registered end }
    local copy = setmetatable({ Plates = fakePlates }, { __index = ns })
    assert(loadfile(ADDON .. "/Plates/Blizzard.lua"))(ADDON, copy)
    local function Frame(width) return { GetWidth = function() return width end } end
    local saved = { NamePlateConstants, NamePlateSetupOptions, C_CVar }

    NamePlateConstants = { NAME_PLATE_WIDTH = 190, CLASSIC_NAME_PLATE_WIDTH = 152 } -- Forever's
    NamePlateSetupOptions = { horizontalScale = 1, insetWidth = 12 }
    eq(adapter.NameBoxWidth({ name = Frame(180), HealthBarsContainer = Frame(200) }), 180, "the name's own width")
    eq(adapter.NameBoxWidth({ name = Frame(stub.Secret()), HealthBarsContainer = Frame(200) }), 200,
        "a secret name width falls back to the health bar area")
    eq(adapter.NameBoxWidth({ name = Frame(stub.Secret()), HealthBarsContainer = Frame(stub.Secret()) }), 166,
        "then Forever's layout: 190 less 12 a side")
    NamePlateSetupOptions = { horizontalScale = 1.25, insetWidth = 15, useClassicHealthBar = true }
    eq(adapter.NameBoxWidth({ name = Frame(0) }), 152 * 1.25 - 30, "the Classic style at a larger size")
    NamePlateConstants, NamePlateSetupOptions = nil, nil
    C_CVar = { GetCVar = function() return "1.2" end }
    near(adapter.NameBoxWidth({}), 110 * 1.2 - 8, "the old layout when Forever's tables are missing")

    NamePlateConstants, NamePlateSetupOptions, C_CVar = saved[1], saved[2], saved[3]
end)

test("seen lists are capped but the seen mark is not", function()
    local first = Identity:GetRuleset() .. "/seenguild"
    for i = 1, 60 do
        stub.units.nameplate12 = { player = true, name = "Crowd", surname = "Member" .. i, guild = "Crowd" .. i }
        Rules:ResolveUnit("nameplate12", ns.profile)
    end
    local guilds = Rules:GetRecent("guilds")
    eq(#guilds, 50, "capped")
    eq(guilds[1].name, "Crowd60", "newest first")
    truthy(Rules:WasSeen("guilds", first), "dropped from the list, still seen")
    stub.units.nameplate12 = { player = true, name = "Seen", surname = "Today", guild = "Seenguild" }
    Rules:ResolveUnit("nameplate12", ns.profile)
    eq(Rules:GetRecent("guilds")[1].name, "Seenguild", "seen again: back at the top")
end)

test("typed player names without a surname are accepted with a warning", function()
    local key, name, problem, warning = Rules.KeyForText("players", "Somebody")
    eq(key, "somebody")
    eq(name, "Somebody")
    eq(problem, nil)
    eq(warning, L.WARN_NO_SURNAME)
    eq(select(4, Rules.KeyForText("players", "Somebody Stormwind")), nil, "no warning with a surname")
    eq(select(4, Rules.KeyForText("guilds", "Kachow")), nil, "guilds have no surname")
end)

test("import never registers a custom file twice", function()
    local target = freshProfile()
    local body = "C\tdance\nC\tdance\nC\tother"
    local payload = assert(Share.Decode("!Heraldry:1:" .. Share.Base64Encode(body) .. ":" .. Share.Checksum(body)))
    eq(Share.Apply(target, Share.Diff(target, payload)), 2)
    eq(#target.custom, 2)
end)

-- TwitchEmotes data shaped like the installed packs (TwitchEmotes, Giga, a third-party pack).
local TWITCH = [[Interface\AddOns\TwitchEmotes\Emotes\]]
local PACK = [[Interface\AddOns\TwitchEmotes_Example\emotes\]]

local function LoadTwitch(pack, metadata)
    stub.loadedAddOns.TwitchEmotes = true
    stub.addOnTitles.TwitchEmotes_Example = "Example Emotes"
    stub.addOnTitles.TwitchEmotes_Giga = "|cff00ff00Giga|r Twitch Emotes|TInterface\\x:0|t"
    TwitchEmotes_defaultpack, TwitchEmotes_animation_metadata = pack, metadata or {}
    local scratch = setmetatable({}, { __index = ns })
    assert(loadfile(ADDON .. "/Icons.lua"))(ADDON, scratch)
    return scratch.Icons
end

local function UnloadTwitch()
    stub.loadedAddOns.TwitchEmotes = nil
    TwitchEmotes_defaultpack, TwitchEmotes_animation_metadata = nil, nil
end

test("twitch: list, categories and pack titles", function()
    local icons = LoadTwitch({
        catJAM = TWITCH .. "Custom\\catJAM.tga:28:28",
        EZ = TWITCH .. "Pepes\\EZ.tga:28:28",
        judhead = [[Interface\AddOns\TwitchEmotes_Giga\emotes\judhead.tga:20:20]],
        ["!wide"] = PACK .. "_wide.tga:28:80",
    })
    local list, categories = icons:GetTwitchEmotes()
    eq(#list, 4)
    eq(list[1].name, "!wide", "punctuation in names is kept")
    eq(list[2].name, "catJAM", "sorted case-insensitively")
    local labels = {}
    for _, category in ipairs(categories) do labels[#labels + 1] = category.key .. "=" .. category.label end
    eq(table.concat(labels, ","), "Custom=Custom,TwitchEmotes_Example=Example Emotes,"
        .. "TwitchEmotes_Giga=Giga Twitch Emotes,Pepes=Pepes", "pack titles without colour and texture codes")
    eq(select(1, icons:GetTwitchEmotes()), list, "built once")
    UnloadTwitch()
end)

test("twitch: size suffix is height:width, as in |T escapes", function()
    local icons = LoadTwitch({
        eShrug = TWITCH .. "Custom\\eShrug.tga:32:64",
        ["!wide"] = PACK .. "_wide.tga:28:80",
        square = TWITCH .. "Custom\\square.tga:28:28",
        bare = TWITCH .. "Custom\\bare.tga",
    })
    eq(icons:Resolve("twitch:eShrug").aspect, 2, "64 wide, 32 high")
    near(icons:Resolve("twitch:!wide").aspect, 80 / 28, "a pack's wide emote")
    eq(icons:Resolve("twitch:square").aspect, 1)
    eq(icons:Resolve("twitch:bare").aspect, 1, "no suffix")
    eq(icons:Resolve("twitch:bare").texture, TWITCH .. "Custom\\bare.tga")
    UnloadTwitch()
end)

test("twitch: animated strips, padding and bad data", function()
    local function path(file) return PACK .. file .. ".tga" end
    local icons = LoadTwitch({
        ["padded"] = path("padded") .. ":28:28",
        tall = path("tall") .. ":28:28",
        noNumbers = path("noNumbers") .. ":28:28",
        tooMany = path("tooMany") .. ":28:28",
        zero = path("zero") .. ":28:28",
        garbage = path("garbage") .. ":28:28",
    }, {
        [path("padded")] = { nFrames = 30, frameWidth = 43, frameHeight = 32, imageWidth = 64, imageHeight = 1024, framerate = 20 },
        [path("tall")] = { nFrames = 256, frameWidth = 32, frameHeight = 32, imageWidth = 32, imageHeight = 8192, framerate = 30 },
        [path("noNumbers")] = { nFrames = "30", frameWidth = 32, frameHeight = 32, imageWidth = 32, imageHeight = 1024, framerate = 20 },
        [path("tooMany")] = { nFrames = 40, frameWidth = 32, frameHeight = 32, imageWidth = 32, imageHeight = 1024, framerate = 20 },
        [path("zero")] = { nFrames = 30, frameWidth = 32, frameHeight = 32, imageWidth = 32, imageHeight = 1024, framerate = 0 },
        [path("garbage")] = { nFrames = 30, frameWidth = 0, frameHeight = 32, imageHeight = 1024, framerate = 20 },
    })
    local padded = icons:Resolve("twitch:padded")
    near(padded.aspect, 43 / 32, "aspect from the frame")
    eq(padded.anim.rows, 30, "vertical strip")
    eq(padded.anim.frameWidth, 43, "explicit frame width")
    near(padded.thumbCoords[2], 43 / 64, "thumbnail drops the strip's padding")
    near(padded.thumbCoords[4], 32 / 1024)

    eq(icons:Resolve("twitch:tall").anim.frames, 256, "8192 px strips are fine")

    for _, name in ipairs({ "noNumbers", "tooMany", "zero" }) do
        local spec = icons:Resolve("twitch:" .. name)
        eq(spec.anim, nil, name .. ": no animation")
        near(spec.coords[4], 32 / 1024, name .. ": still first frame")
    end
    local garbage = icons:Resolve("twitch:garbage")
    eq(garbage.anim, nil, "unusable frame size")
    eq(garbage.coords[4], 1, "whole texture")
    eq(garbage.aspect, 1, "the |T size")
    UnloadTwitch()
end)

test("twitch: packs registering late are picked up", function()
    local pack = { EZ = TWITCH .. "Pepes\\EZ.tga:28:28" }
    local icons = LoadTwitch(pack)
    eq(icons:Resolve("twitch:late").missing, true, "unknown for now")
    eq(icons:RefreshTwitchEmotes(), false, "nothing new")
    pack.late = PACK .. "late.tga:28:56"
    eq(icons:RefreshTwitchEmotes(), true, "a pack registered more")
    eq(icons:Resolve("twitch:late").aspect, 2, "cached spec dropped")
    local list = icons:GetTwitchEmotes()
    eq(#list, 2)
    UnloadTwitch()
end)

--------------------------------------------------------------------------------
-- Icon placement (Plates.Layout with the stub's measuring: 6 px per character)
--------------------------------------------------------------------------------
local function display(overrides)
    local result = CopyTable(DB.DISPLAY_DEFAULTS)
    for key, value in pairs(overrides or {}) do result[key] = value end
    return result
end

local function name(text, justify, size)
    local fontString = stub.Region()
    fontString:SetFont("font.ttf", size or 12, "OUTLINE")
    fontString:SetText(text)
    fontString:SetJustifyH(justify or "CENTER")
    return fontString
end

local square = { aspect = 1 }

-- Returns the anchor point and the icon centre's offset from it.
local function place(fontString, hints, overrides)
    local region = Plates.NewRegion(CreateFrame())
    Plates.Layout(region, fontString, hints, square, display(overrides))
    local topLeft, bottomRight = region.texture.points[1], region.texture.points[2]
    eq(topLeft[1], "TOPLEFT")
    eq(bottomRight[1], "BOTTOMRIGHT")
    return topLeft[3], (topLeft[4] + bottomRight[4]) / 2, (topLeft[5] + bottomRight[5]) / 2
end

test("placement: tall icon beside a Blizzard plate's name and bar", function()
    local bar, level = stub.Region(), stub.Region()
    local span = { left = bar, right = level, height = 30, lift = 9 }
    local region = Plates.NewRegion(CreateFrame())
    Plates.Layout(region, name("Fast Racer"), { span = span }, square, display({ tallBlizzard = true }))
    local topLeft, bottomRight = region.texture.points[1], region.texture.points[2]
    eq(topLeft[2], bar, "beside the bar, not the name")
    eq(topLeft[3], "LEFT")
    eq((topLeft[4] + bottomRight[4]) / 2, -(2 + 15), "gap + half the 30 px icon")
    eq((topLeft[5] + bottomRight[5]) / 2, 9, "centred on the name and bar together")
    eq(topLeft[5] - bottomRight[5], 30, "as tall as both")

    region = Plates.NewRegion(CreateFrame())
    Plates.Layout(region, name("Fast Racer"), { span = span }, square,
        display({ tallBlizzard = true, position = "RIGHT", scale = 0.5 }))
    topLeft = region.texture.points[1]
    eq(topLeft[2], level, "right of the level box")
    eq(topLeft[3], "RIGHT")

    local point = place(name("Fast Racer"), { span = span }, { tallBlizzard = false })
    eq(point, "CENTER", "off: the normal placement")
    point = place(name("Fast Racer"), { span = span }, { tallBlizzard = true, position = "TOP" })
    eq(point, "TOP", "above or below the name: the normal placement")
end)

test("blizzard plates: the tall icon's span from the bar and Forever's layout", function()
    local adapter
    local copy = setmetatable({ Plates = { RegisterAdapter = function(_, a) adapter = a end } }, { __index = ns })
    assert(loadfile(ADDON .. "/Plates/Blizzard.lua"))(ADDON, copy)
    local function Frame(fields)
        local frame = { IsShown = function() return true end }
        for key, value in pairs(fields or {}) do frame[key] = value end
        return frame
    end
    local saved = { NamePlateConstants, NamePlateSetupOptions }
    NamePlateConstants = { NAME_ANCHOR_STYLES = { InsideHealthBar = 1, AboveHealthBar = 3 } }
    NamePlateSetupOptions = { unitNameAnchorStyle = 3, healthBarHeight = 10, healthBarFontHeight = 12,
        healthBarToNameAboveSpacing = 2 }

    local bar = Frame({ GetHeight = function() return 11 end })
    local unitFrame = { HealthBarsContainer = bar, name = name("Fast Racer") }
    local span = adapter.Span(unitFrame, {})
    eq(span.left, bar)
    eq(span.right, bar, "no level box: right of the bar")
    eq(span.height, 11 + 2 + 12, "the bar's own height, the spacing and the name")
    eq(span.lift, (25 - 11) / 2)

    unitFrame.RaidTargetFrame = Frame({ IsShown = function() return false end })
    unitFrame.ClassificationFrame = Frame({ IsShown = function() return false end })
    eq(adapter.Span(unitFrame, {}).left, bar, "no marker or classification showing: beside the bar")
    unitFrame.RaidTargetFrame.IsShown = function() return true end
    eq(adapter.Span(unitFrame, {}).left, unitFrame.RaidTargetFrame, "past a raid marker")
    unitFrame.ClassificationFrame.IsShown = function() return true end
    eq(adapter.Span(unitFrame, {}).left, unitFrame.ClassificationFrame, "past the classification icon too")
    unitFrame.RaidTargetFrame, unitFrame.ClassificationFrame = nil, nil

    bar.GetHeight = function() return stub.Secret() end
    unitFrame.PlayerLevelDiffFrame = Frame()
    span = adapter.Span(unitFrame, {})
    eq(span.height, 10 + 2 + 12, "a secret height: Forever's healthBarHeight")
    eq(span.right, unitFrame.PlayerLevelDiffFrame, "past the level box when it shows")

    NamePlateSetupOptions.unitNameAnchorStyle = 1
    eq(adapter.Span(unitFrame, {}).height, 10, "name inside the bar: the bar alone")

    unitFrame.IsShowOnlyName = function() return true end
    eq(adapter.Span(unitFrame, {}), nil, "a names-only plate gets no span")
    unitFrame.IsShowOnlyName = nil
    bar.IsShown = function() return stub.Secret() end
    eq(adapter.Span(unitFrame, {}), nil, "nor does a bar whose visibility is secret")

    NamePlateConstants, NamePlateSetupOptions = saved[1], saved[2]
end)

test("placement: tight box", function()
    local point, x, y = place(name("Fast Racer"), { tight = true })
    eq(point, "LEFT")
    eq(x, -(2 + 6), "gap + half the icon")
    eq(y, 0)
    point, x = place(name("Fast Racer"), { tight = true }, { position = "RIGHT" })
    eq(point, "RIGHT")
    eq(x, 8)
end)

test("placement: centred fixed box uses the measured text", function()
    local point, x = place(name("Fast Racer"))  -- 60 px wide
    eq(point, "CENTER")
    eq(x, -(30 + 2 + 6))
    point, x = place(name("Fast Racer", "LEFT"), nil, { position = "RIGHT" })
    eq(point, "LEFT")
    eq(x, 60 + 2 + 6)
    point, x = place(name("Fast Racer", "RIGHT"))
    eq(point, "RIGHT")
    eq(x, -(60 + 8))
end)

test("placement: long names stop at the box", function()
    local long = name(("x"):rep(30)) -- 180 px, box 100
    local point, x, y = place(long, { boxWidth = 100 })
    eq(point, "CENTER")
    eq(x, -(50 + 8), "clamped to the box")
    eq(y, 0)
    local _, _, wrappedY = place(long, { boxWidth = 100, wraps = true })
    near(wrappedY, 12 * 1.15 / 2, "wrapped: level with the first line")
end)

test("placement: clears arrows and markers only where they would overlap", function()
    -- 60 px name, 12 px icon, gap 2; a 14 px marker just outside the box's left edge.
    local _, x = place(name("Fast Racer"), { tight = true, edgeLeft = 14 })
    eq(x, -(14 + 6), "tight box: the icon starts past the marker")
    _, x = place(name("Fast Racer"), { boxWidth = 64, edgeLeft = 14 })
    eq(x, -(30 + 2 + 6 + (2 + 14 - 2)), "2 px of room: moved past the marker")
    _, x = place(name("Fast Racer"), { boxWidth = 120, edgeLeft = 14 })
    eq(x, -(30 + 2 + 6), "30 px of room: the icon fits beside the name, inside the box")
    _, x = place(name("Fast Racer"), { tight = true, edgeLeft = 14 }, { position = "RIGHT" })
    eq(x, 8, "only on its own side")
    _, x = place(name("Fast Racer"), { tight = true, edgeLeft = 1 }, { gap = 4 })
    eq(x, -(4 + 6), "a gap already wider than the item: no change")
end)

test("adapters: owned-but-hidden plates stop the fallback", function()
    local function Fake(id, answer, fallback)
        return { id = id, label = id, fallback = fallback, IsAvailable = function() return true end,
            GetName = function() return answer end }
    end
    -- A fresh copy of Plates.lua per chain, with fake adapters only.
    local function Chain(...)
        local copy = setmetatable({}, { __index = ns })
        assert(loadfile(ADDON .. "/Plates/Plates.lua"))(ADDON, copy)
        for i = 1, select("#", ...) do copy.Plates:RegisterAdapter(select(i, ...)) end
        copy.Plates:EnableAdapters()
        return copy.Plates.FindName("nameplate1", CreateFrame())
    end
    local generic = Fake("Generic", CreateFrame(), true)
    local nameText = stub.Region()

    local anchor, _, adapter, owner = Chain(Fake("Owner", false), Fake("Blizzard", nil), generic)
    eq(anchor, nil, "owner hides the plate: nothing drawn")
    eq(adapter, nil)
    eq(owner.id, "Owner")
    _, _, adapter = Chain(Fake("Owner", false), Fake("Blizzard", nameText), generic)
    eq(adapter.id, "Blizzard", "an owner that left the plate to Blizzard")
    _, _, adapter = Chain(Fake("Other", nil), Fake("Blizzard", nil), generic)
    eq(adapter.id, "Generic", "unknown plates get the fallback")
end)

test("placement: two-line names align with the first line", function()
    local _, _, y = place(name("Fast Racer\n<Kachow>"), { tight = true })
    near(y, 12 * 1.15 / 2)
end)

test("placement: hidden text and unknown plates go above", function()
    local secret = name("x")
    secret.text = stub.Secret()
    local point, x, y = place(secret)
    eq(point, "TOP")
    eq(x, 0)
    eq(y, 2 + 6)
    point = place(CreateFrame(), { anchorOnly = true, fontSize = 12 })
    eq(point, "TOP")
end)

test("placement: offsets, size and a hidden font size", function()
    local hidden = name("Fast Racer")
    hidden.font[2] = stub.Secret()
    local region = Plates.NewRegion(CreateFrame())
    Plates.Layout(region, hidden, { tight = true, fontSize = 20 }, square, display({ x = 5, y = -3, scale = 2 }))
    local topLeft, bottomRight = region.texture.points[1], region.texture.points[2]
    eq(bottomRight[4] - topLeft[4], 40, "20 px name x scale 2")
    eq((topLeft[4] + bottomRight[4]) / 2, -(2 + 20) + 5)
    eq((topLeft[5] + bottomRight[5]) / 2, -3)
end)

--------------------------------------------------------------------------------
-- Game icons
--------------------------------------------------------------------------------
test("game icons: ability and file names, word-start search and real file IDs only", function()
    -- The macro list as the client gives it: one loose file name and two file IDs.
    local saved = { GetLooseMacroIcons, GetLooseMacroItemIcons, GetMacroIcons, GetMacroItemIcons,
        GetFileIDFromPath, C_Spell, C_Item, ns.IconNamesData }
    GetLooseMacroIcons = function(raw) raw[#raw + 1] = "INV_Misc_QuestionMark" end
    GetLooseMacroItemIcons, GetMacroItemIcons = function() end, function() end
    GetMacroIcons = function(raw) raw[#raw + 1] = 132089; raw[#raw + 1] = 9999999 end
    GetFileIDFromPath = function(path) return path:lower():find("questionmark") and 134400 or nil end
    -- The game's spell names (Forever's IDs; 12052 is a second spell named Evocation).
    local spellNames = {
        [370] = "Purge", [12051] = "Evocation", [12052] = "Evocation", [12321] = "Booming Voice",
        [11426] = "Ice Barrier", [14177] = "Cold Blood", [5] = "Anti-Magic Shell",
        [78] = "Heroic Strike", [8676] = "Ambush",
    }
    C_Spell = {
        GetSpellTexture = function() return nil end,
        GetSpellName = function(spellID) return spellNames[spellID] end,
    }
    C_Item = { GetItemInfoInstant = function() return nil end }
    local GameIcons = ns.GameIcons

    -- A small IconNames.lua: a file label alone, labels with abilities, abilities alone,
    -- and a spell the client doesn't know (999).
    ns.IconNamesData = table.concat({
        "132089 ambush",                              -- 132089
        "2311 question mark",                         -- 134400
        "1588 ice lament|11426|14177",                -- 135988
        "64012 |5",                                   -- 200000
        "1 |999",                                     -- 200001: nobody's name left
        "1 nature purge|370|12051|12052|12321",       -- 200002
    }, "\n")
    GameIcons:ReleaseNames()

    eq(GameIcons:GetIconName(132089), "Ambush", "a file label, capitalized")
    eq(GameIcons:GetIconName(134400), "Question mark", "the file label beats the loose raw name")
    eq(GameIcons:GetIconName(135988), "Ice Barrier", "the first ability names the icon")
    eq(GameIcons:GetOtherNames(135988), "Cold Blood", "the other")
    eq(GameIcons:GetIconName(200002), "Purge", "the game's name for the first spell")
    eq(GameIcons:GetOtherNames(200002), "Evocation, Booming Voice", "a repeated name shows once")
    eq(GameIcons:GetOtherNames(200000), nil, "one ability, no others")
    eq(GameIcons:GetIconName(200000), "Anti-Magic Shell", "an ability icon without a file label")
    eq(GameIcons:GetIconName(200001), nil, "a spell the client doesn't know names nothing")
    eq(GameIcons:GetIconName(9999999), nil, "an icon nobody names")
    truthy(GameIcons:HasNames(), "naming an icon parses the data")
    GameIcons:ReleaseNames()
    eq(GameIcons:HasNames(), false, "released when the picker closes")

    local function ids(query)
        local found = {}
        for _, fileID in ipairs(GameIcons:Search(query)) do found[#found + 1] = fileID end
        return table.concat(found, ",")
    end
    eq(ids("ambu"), "132089", "a word start")
    eq(ids("mbush"), "", "not the middle of a word")
    eq(ids("question"), "134400", "a loose icon")
    eq(ids("ice barrier"), "135988", "an ability icon the macro list lacks")
    eq(ids("cold blood"), "135988", "found by every ability that uses it")
    eq(ids("booming"), "200002", "Evocation's icon by Booming Voice")
    eq(ids("evocation"), "200002", "and by Evocation")
    eq(ids("ice lament"), "135988", "and by its file label")
    eq(ids("ice"), "135988", "\"ice\" is a word start; nothing else starts a word with it")
    eq(ids("anti-magic"), "200000", "a hyphenated ability as typed")
    eq(ids("magic shell"), "200000", "and by later words")
    eq(ids("1266"), "", "a number that isn't a known icon finds nothing")
    eq(ids("1"), "", "nor does the first digit typed")
    eq(ids("132089"), "132089", "a known file ID")
    eq(ids("9999999"), "9999999", "an unnamed icon from the macro list")
    eq(ids("135988"), "135988", "an icon the data names but the macro list lacks")
    truthy(#GameIcons:Search("") == 3, "an empty query lists the macro icons")

    -- Nameplates resolve icons but never read labels, so they never parse the data.
    GameIcons:ReleaseNames()
    Icons:ForgetGameSpecs()
    local spec = Icons:Resolve("game:135988")
    eq(spec.texture, 135988, "a game spec resolves")
    eq(GameIcons:HasNames(), false, "resolving a game icon doesn't parse names")
    local missing = Icons:Resolve("lib:no_such_icon")
    truthy(missing.missing, "a missing library icon")
    eq(GameIcons:HasNames(), false, "nor does a missing icon")
    eq(spec.label, "Ice Barrier", "the label is looked up when read")
    eq(Icons:Describe("game:9999999"), L.ICON_DESCRIPTION:format(L.GAME_ICON_ID:format(9999999), L.SOURCE_GAME),
        "an unnamed icon describes itself by number")

    -- The shipped data (Forever's spells): Evocation's icon is also Booming Voice's, and
    -- Heroic Strike names an icon.
    ns.IconNamesData = saved[8]
    GameIcons:ReleaseNames()
    truthy((" " .. ids("booming voice") .. ","):find("136075,", 1, true), "shipped: Booming Voice's icon")
    truthy((" " .. ids("evocation") .. ","):find("136075,", 1, true), "shipped: is Evocation's icon")
    truthy((" " .. ids("heroic strike") .. ","):find("132282,", 1, true), "shipped: Heroic Strike")
    GameIcons:ReleaseNames()
    Icons:ForgetGameSpecs()

    GetLooseMacroIcons, GetLooseMacroItemIcons, GetMacroIcons, GetMacroItemIcons,
        GetFileIDFromPath, C_Spell, C_Item = unpack(saved, 1, 7)
end)

--------------------------------------------------------------------------------
-- Strings
--------------------------------------------------------------------------------
test("every string the code uses is in the locale", function()
    local missing = {}
    local windows = package.config:sub(1, 1) == "\\"
    local sources = io.popen(windows and ('dir /s /b "' .. ADDON .. '\\*.lua"') or ('find ' .. ADDON .. ' -name "*.lua"'))
    local scanned = 0
    for path in sources:lines() do
        scanned = scanned + 1
        local handle = assert(io.open(path, "r"))
        local text = handle:read("*a")
        handle:close()
        for key in text:gmatch("L%.([%u_][%w_]*)") do
            if rawget(L, key) == nil then missing[#missing + 1] = key .. " (" .. path:match("[^\\/]+$") .. ")" end
        end
    end
    sources:close()
    truthy(scanned > 10, "found the add-on's source files")
    for _, position in ipairs(DB.POSITIONS) do
        if rawget(L, "POSITION_" .. position) == nil then missing[#missing + 1] = "POSITION_" .. position end
    end
    for _, reason in ipairs({ "player", "player-none", "name-hidden", "guild", "my-guild", "my-guild-secret",
        "no-rule", "not-player" }) do
        local key = "REASON_" .. reason:upper():gsub("%-", "_")
        if rawget(L, key) == nil then missing[#missing + 1] = key end
    end
    for _, token in ipairs(Identity.KNOWN_RULESETS) do
        if rawget(L, "RULESET_" .. token) == nil then missing[#missing + 1] = "RULESET_" .. token end
    end
    eq(#missing, 0, "missing strings: " .. table.concat(missing, ", "))
end)

print(("%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
