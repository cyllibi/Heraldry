# Heraldry: design

Heraldry shows an icon next to the names of chosen guilds and players on nameplates.
It grew out of an earlier single-guild prototype and targets **WoW Forever only** (interface `16001`).
The audience is the Kachow guild, distributed through CurseForge.

## Goal
Players pick an icon for any guild (their own, allies, enemies) and, optionally, for individual players.
A per-player icon overrides the guild icon. Nothing shows for guilds or players the user hasn't chosen.

Out of scope: guild registry, syncing between players, a companion app, target frame and tooltips, retail.

## Plates
The icon attaches to the plate's name text. Name text is found through **adapters**, one per nameplate
add-on, tried in order for every plate on every update (plates change owner without a new
`NAME_PLATE_UNIT_ADDED`): EllesmereUI, Plater, ElvUI, Threat Plates, then Blizzard, then a generic
fallback. An adapter only claims a plate its add-on is actually drawing. When its add-on owns a plate
but shows no name there (hidden on purpose, e.g. friendly players in cities, or not built yet) it answers
"mine, hidden": Blizzard's adapter may still take the plate if the add-on left it to Blizzard, but the
generic fallback never does, so no icon floats over a hidden plate. The fallback can also be turned off
(Display: "Show on unrecognised nameplate add-ons").

| Plate | Name text | Box |
|---|---|---|
| EllesmereUI friendly, full plate | `EllesmereNameplates_NS.friendlyPlates[unit].name` | auto-sized ("tight") |
| EllesmereUI enemy | `EllesmereNameplates_NS.plates[unit].name` | fixed width (bar width x Name Width %), justified by EUI's name slot; corner slots are auto-sized |
| EllesmereUI friendly, name-only | `nameplate.UnitFrame.name` (Blizzard's, restyled by EUI) | one centre point, may hold a second guild line |
| Plater | `nameplate.CurrentUnitNameString` (`unitFrame.unitName` in the bar, or `ActorNameSpecial`, auto-sized) | `Plater.db.profile.plate_config[unitFrame.ActorType].health[1]` / tight |
| ElvUI | `nameplate.unitFrame.Name` (`.blizzPlate` tells it from Plater) | measured |
| Threat Plates | `nameplate.TPFrame.visual.NameText` | measured |
| Blizzard (EUI not loaded, EUI leaves friendly players or follower dungeons/delves to Blizzard) | `nameplate.UnitFrame.name`, only while the UnitFrame is on screen (parent is the nameplate, visible, alpha > 0) | anchored across the health bar: the name's width or the bar area's when readable, else Forever's layout (190 on Forever, 230 on mainline, 152 for the Classic style, x the nameplate size's scale, less 12 x scale a side; Forever centres names above the bar with the level box outside it) |
| Generic (Platynator, unknown plate add-ons) | none: Heraldry's own frame over the nameplate | icon centred above the nameplate, lifted 14 px to clear a name drawn above the bar |

Plater, ElvUI and Threat Plates adapters follow their current Forever sources and are not tested in
game here; Platynator has no public namespace, so it gets the generic fallback.

- The icon is a texture on the name text's parent frame, so it follows that frame's alpha, scale and
  visibility. One texture per host frame, reused as Blizzard and EUI recycle plates. When a unit's name
  moves to another host (EUI slot change, friendly/enemy promotion, mode switch) the old texture hides.
- **Restricted plate tree (12.x):** widget metrics inside nameplates can be secret, and single point +
  `SetSize` regions render displaced. So:
  - The icon is anchored by two opposite corners (`TOPLEFT`, `BOTTOMRIGHT`) to one point of the name
    FontString, with plain-number offsets.
  - Text width comes from a hidden measuring FontString outside the plate tree (same font file, size and
    flags, the name's first line), never from the plate's own `GetWidth`/`GetStringWidth`.
  - Every value read from a plate goes through `issecretvalue` before any comparison or arithmetic.
- **Placement:** for a tight box the icon sits off the box edge. For a fixed-width box the icon is offset
  from the side the text is justified to by the measured width (centre-justified: half the width from the
  centre), clamped to the box width the adapter knows from plain settings (never measured inside the
  plate, where widths are secret), so a long name cut with an
  ellipsis keeps the icon at the box edge; a name wider than a wrapping box counts as two lines. Two-line
  names align with the first line. If the text can't be measured (secret name), the icon goes centred
  above the name, which is never on the wrong side.
- **Beside the name:** EUI's target arrows (friendly full plates at the name's edges; enemy plates beside
  the health bar) and EUI's name raid marker (enemy plates, left of the name box) are passed as widths just
  outside the box edge. The icon moves past them only when it would overlap them; a short centred name
  usually leaves room inside the box. Updated on target and raid marker changes.
- **Updates:** `NAME_PLATE_UNIT_ADDED` (at once, and again next frame for add-ons that build their plate in
  the same event), `_REMOVED`, `UNIT_NAME_UPDATE`, `UNIT_FLAGS`, `UNIT_FACTION` (nameplate units only),
  `PLAYER_GUILD_UPDATE`, combat start/end, zone changes, a token sweep after loading screens
  (`C_NamePlate.GetNamePlates` omits friendly player plates), setting changes, hooks on EUI's plate
  builders, and a 0.5 s safety-net pass while plates exist, for late guild data and changes no event
  announces. Texture, layout and alpha are only touched when their inputs changed.
- Forbidden plates (`IsForbidden()`) are skipped; restricted ones follow the rules above. A host frame that
  isn't on screen is skipped too, so names parked under a hidden frame don't share one texture.
- Icons from an add-on that isn't loaded (a Twitch emote) show nothing on plates; the options show them as
  a question mark with the add-on's name.
- **Try on target:** the Display page (and `/heraldry try`, since the options window blocks targeting) can
  show the preview icon on the target's plate for 10 seconds with the current settings, without a rule.
  The test follows the unit's GUID, not the recycled nameplate token.
- The player's own plate never gets an icon.
- Known overlap: EUI's target arrows and name raid marker also sit beside the name. Position and offset
  options let the user move the icon clear.

## Matching
For each player plate, in order:
1. **Player rule** for that character: an icon, or "none" to hide their guild icon.
2. **Guild rule** for the unit's guild.
3. **My guild** rule, if enabled.
4. Nothing.

### Identity on WoW Forever
Forever has no realms. Every character lives in one large **ruleset** (PvE, PvP, RP, RP-PvP, and
Hardcore) and has a first name plus a surname.

- **Ruleset:** read from `C_GameRules.IsGameRuleActive(Enum.GameRule.*Ruleset)`, checking every flag so
  RP-PvP doesn't collapse into PvP. Stored as fixed tokens `pve`, `pvp`, `rp`, `rppvp`, `hc`, never the
  client's localized names. Unknown flags give the raw `+`-joined combination, so a new ruleset never
  collides with an old one.
- **Guild key:** `ruleset/folded guild name`. Guild names are only unique within a ruleset, and settings
  are account-wide, so a "Kachow" on PvE and a "Kachow" on PvP stay separate.
- **Player key:** `folded first name + " " + folded surname`, from `UnitName(unit)` (which returns the
  surname where retail returns the realm; some units already carry it in the first value). Character
  names are unique region-wide on Forever, so player keys have no ruleset prefix. The game's separator
  (`Constants.CharacterNameSeparatorConsts`) and a typed space give the same key.
- **Folding:** trim, collapse spaces, lowercase ASCII plus the Latin-1 and Latin Extended-A letters names
  use, so a typed "élise" matches "Élise".
- **My guild:** follows whichever guild the current character is in, checked with `UnitIsInMyGuild(unit)`.
  It survives renames and works on alts in any guild.
- `GetGuildInfo(unit)` can return nil for a while after a plate appears; nil means "check again", which
  the safety-net pass does.

The Guilds page shows only the current ruleset's entries, with a filter to see the rest.

### Secret values
Midnight-era clients can hand add-ons "secret" names that can't be compared or used as table keys.
When a name comes back secret, that rule type is skipped for the plate. "My guild" still works when
`UnitIsInMyGuild` returns a secret boolean, through `SetAlphaFromBoolean`. Expect rules to work in the
open world and possibly drop out in instances and combat. `/heraldry check` reports what the client
exposes about the target.

A secret name means a player rule can't be checked, so the guild icon shows, even for a player whose
rule is "none". The Display option "Show nothing when a name is hidden" turns that into no icon.

## Icons
Every rule points at an icon id, prefixed by source. In order of importance:

| Source | Id | Notes |
|---|---|---|
| **Library** (main feature) | `lib:<key>` | Icons shipped with the add-on, static and animated. Starts with about 430 heraldic, fantasy and symbol silhouettes from game-icons.net (CC BY 3.0); emotes whose artists give permission can join later. |
| **Game icons** | `game:<fileID>` | Thousands of built-in icons, nothing to ship. |
| **Twitch Emotes** (optional) | `twitch:<emote>` | Borrowed from the user's own TwitchEmotes add-on and any pack registering into it (TwitchEmotes_Giga, ...), when loaded. Heraldry ships none of that art. |
| **Custom** (minor, bottom of the page) | `custom:<file>` | Player-supplied files. |

An id that can't be resolved here (a library key from a newer release, a Twitch emote without the
add-on) shows a question mark in the options, labelled as such in the rule lists and import preview.

The icon picker is one shared window with tabs Library, Game icons, Twitch Emotes (only when that add-on is
loaded) and Custom (last), a search box, Favorites and Recent rows (account-wide in `HeraldryDB.ui`, whatever
profile is active; right-click toggles a favorite), a grid, and the selection previewed beside a sample name
with the player's Display settings.
Click selects, double-click or Enter chooses, arrow keys move (out of combat), Escape closes.

### Library
- `Heraldry\media\library\` holds the textures; `Heraldry\Library.lua` is the manifest: one entry per icon
  with key, display name, file, shape (square or wide), art and texture size, tags for search, credit
  (source, author, license, url, permission), optional aliases for renamed keys, and for animated icons the
  grid, frame count, frame rate and a static thumbnail.
- **Shapes and sizes:** static art fits `128x128` (square) or `256x128` (wide), cropped by tex coords
  within a power-of-two texture. Animated frames fit `64x64` square or `128x64` wide, on a sprite sheet of
  at most `1024x1024` (about 4 MB of video memory, loaded once).
- **Animation:** a sprite sheet played with WoW's `FlipBook` animation, with explicit frame width and
  height in texture pixels (the grid rarely fills the sheet). Duration is frames / fps. The client runs
  it, so there is no add-on CPU per frame. Animations stop when the icon hides.
- **Picker memory:** the grid shows static thumbnails; only the hovered cell and the preview animate, and
  game icon data (specs and the icon name table) is released when the picker closes. Each game-icons texture is about 23 KB (128x128 DXT5 with
  mipmaps), loaded the first time its cell is shown; scrolling through all ~430 of them loads about 10 MB, which the client
  keeps cached for the session. Nameplates only load the icons rules use.
- **Maintainer tooling:** `tools\emote2lib.py` (ffmpeg-based) turns a 7TV emote (by URL or id) or any
  image file or URL (GIF, APNG, PNG, AVIF) into a library texture, thumbnail and manifest entry. Too many
  frames: drop every other frame until the sheet fits. Example: 7TV `01F6MZGCNG000255K4X1K7NTHR` is
  128x128, 198 frames at 25 fps; at 64x64 it fits a 1024x1024 sheet as 16x13 at full speed.
  `tools\credits.py` builds `CREDITS.md` from the manifest.
- **Finding icons:** each library entry may name a `category` (14 themes for the game-icons set: Shields &
  heraldry, Weapons, Magic & alchemy, ...), offered in the picker's category dropdown on the Library tab as
  on the Twitch tab. Search matches the start of words in the name and tags, every query word must match,
  and hyphens count as spaces ("ice" finds Ice cube, not Jeweled chalice; "death knight" works). Tags carry
  class, role and spell-school words (healer, tank, frost, shadow, ...). The search text is folded once per
  entry.
- **Trademarks:** some icons depict or are named after other companies' marks (Triforce, Super mushroom,
  MP5, Overmind). The CC BY license covers the art's copyright only; the maintainer decided on 2026-11-09 to
  ship them as they are.
- **game-icons.net set:** `tools\game-icons.txt` lists the icons (curated by theme, with search tags; the
  second half was picked by the maintainer from RPG Awesome's hand-curated selection, with game-icons.net's
  own tags);
  `tools\gameicons2lib.py` rebuilds them all. The site's white silhouettes vanish on bright ground and fine
  cut-outs vanish at nameplate size, so every icon gets its enclosed transparent areas filled black and a
  round black outline about 1.5 px wide at a 20 px icon, then is fitted into 128x128. Picker cells are 40
  UI units (about 56 px at 1080p, 75 px at 1440p, 112 px at 4K) and plate icons can be as large, so 64 px
  would soften on large screens. The textures are **DXT5 BLP with mipmaps** (`tools\blp.py`, a small
  encoder for greyscale art; same layout as EllesmereUI's BLPs): about 23 KB each, compressed in video
  memory too, so the ~430-icon set is about 10 MB where 128 px TGAs would be 28 MB. Checked in WoW Forever
  on 2026-11-09 next to TGA and palettized BLP. The game finds the file from the manifest's extensionless
  path. Black and white only; the gold add-on icon stays a TGA.
  Keys are `gi_<name>`; each entry credits the icon's author, links its page and notes the changes, as
  CC BY 3.0 asks.
- **Development library:** test art that may not ship goes into a separate add-on, `HeraldryDev`
  (`emote2lib.py --dev`), gitignored and excluded from packages. It sets the global `HeraldryDevLibrary`,
  which Heraldry reads (never writes) when present; its textures live under `HeraldryDev\media\`.
- **Rights:** only art Heraldry has a license or explicit permission for ships, credited per entry in the
  manifest and in `CREDITS.md`; license texts go in `Heraldry\licenses\`. 7TV emotes are uploaded by users
  and may include copyrighted art; the maintainer decides what ships.

### Game icons
Picked from the built-in icon list (the same set the macro icon picker uses), stored by file id. Forever
returns file ids only, no names, so `Heraldry/IconNames.lua`, generated by `tools\iconnames.py`, names them:
- **Player abilities:** WoW Forever is vanilla's nine classes and talents plus Season of Discovery runes, with
  its own game data (wago.tools product `wowf`; retail's spells would be wrong: no Heroic Strike ranks, Death
  Grip instead). The tool reads Forever's spell tables and lists, under each icon, the spell IDs of every
  ability a player can have: class skill lines (including rune abilities), pet abilities, talents, racials and
  rogue poisons. Every ability sharing an icon is kept (up to 8), so Evocation's icon is also found as Booming
  Voice, Purge and Devour Magic. Ranks collapse to the first. NPC spells, mounts, companion pets and the
  rune-engraving helper spells are left out. About 640 icons have abilities. The add-on asks the game for each
  spell's name (`C_Spell.GetSpellName`), so names are in the client's language and exactly Forever's. The
  first ability (baseline before talents, then the older spell) is the display name; the picker's tooltip
  lists the others. The generated file records the Forever build it came from.
- **File labels:** a short label for each of about 34,000 icon files, from the community listfile
  (github.com/wowdev/wow-listfile, verified release): `INV_Misc_Gem_Ruby_01` becomes "Gem ruby" (type
  prefixes, numbers and variant letters dropped). They name every icon no ability uses. They are English.

The data is one string of `<id delta> <label>[|<spell id>|...]` lines (about 825 KB, always loaded). It is
parsed into tables (measured under Lua 5.1: about 20 ms and 4.2 MB) only when a game icon's name is shown or
searched (the picker, the options' rule lists and import preview, `/heraldry check`), and dropped when the
picker or an options page closes, or right after the check. Nameplates never read names, so they never parse
it. There is no background work: search is complete from the first keystroke. The file names and spell data
are Blizzard's, collected by those projects; the file is outside Heraldry's MIT license.

Search matches the start of words in ability names and file labels, like the library. Typed digits find an
icon only when it is in the macro list or the data (any other number would show the missing-texture
square). Texture paths, spell names the client knows and cached item names work at once. Icons and
abilities added after the data was built stay unnamed ("Icon 1234") until it is rebuilt.

### Twitch Emotes
Read from `TwitchEmotes_defaultpack` (name to `path:height:width`, the `|T` escape's order) and
`TwitchEmotes_animation_metadata` (vertical-strip sprite sheets) when TwitchEmotes is loaded. Other packs
(TwitchEmotes_Giga, ...) register into the same tables, so they need no code of their
own; packs that register after login are picked up when they load. Categories are the emote's subfolder, or
the pack's TOC title (colour codes stripped). Animation data comes from third-party packs, so every field is
checked: frames must fit the image, and strips padded in width are cropped to the frame. Data that doesn't add
up shows the first frame still. Played with the same FlipBook code.

### Custom icons (minor)
Kept as simple as the client allows; it sits at the bottom of the picker and options.

- **Folder:** `Interface\AddOns\Heraldry_Custom\`, outside the add-on's own folder so updates don't delete it.
- **Same sizes as the library.** A name ending in `_wide` is wide, anything else square. Animated files carry
  their layout in the name: `<name>[_wide]_anim<cols>x<rows>_<frames>_<fps>.tga`.
- **Format:** TGA, 32-bit with alpha, or BLP.
- **Registering:** WoW can't list a folder, so the player types the file name once; the panel previews it.
  New files need a full game restart, and the panel says so.
- Custom icons only appear on that player's screen.

## Display
Defaults: icon left of the name, height equal to the name text, shown on friendly and enemy plates.

Options:
- Enabled (master switch)
- Show on friendly plates, show on enemy plates
- Position: left of name, right of name, above, below
- Size, as a multiple of the name text's height
- Horizontal and vertical offset
- Gap between icon and name
- Opacity
- Where: open world, dungeons, raids, battlegrounds and arenas; hide in combat
- Show nothing when a name is hidden (see Secret values)

## Settings
- `SavedVariables: HeraldryDB`: account-wide profile (rules, custom icons, display).
- `SavedVariablesPerCharacter: HeraldryCharDB`: a "Use settings for this character only" checkbox.
  Turning it on copies the account profile into the character's, so nothing is lost; turning it off goes
  back to the account profile and keeps the character copy in case it's turned back on. "Copy shared
  settings to this character" replaces the character copy on request.
- A `version` field and a migration step from day one, so later releases can change the format safely.
  Every field is normalized on load. Saved data from a newer release is never rewritten: the session works
  on a normalized copy, changes aren't saved, and the player is told once.
- `HeraldryDB.ui` keeps the picker's favorite and recent icons and the minimap button (`minimap = { hide,
  minimapPos }`, LibDBIcon's format), account-wide.

```lua
HeraldryDB = {
  version = 1,
  profile = {
    myGuild = { enabled = false, icon = nil },
    guilds  = { ["pve/kachow"] = { name = "Kachow", icon = "lib:kachow" } },
    players = { ["somebody stormwind"] = { name = "Somebody Stormwind", icon = "none" } },
    custom  = { "guildcrest_wide" },
    display = { enabled = true, friendly = true, enemy = true, position = "LEFT",
                scale = 1.0, alpha = 1.0, gap = 2, x = 0, y = 0,
                world = true, dungeon = true, raid = true, pvp = true,
                hideInCombat = false, strictPlayers = false, unknownPlates = true,
                tallBlizzard = false },
  },
}
HeraldryCharDB = { version = 1, useCharacter = false, profile = nil }
```

## Interface
- **Options panel** under the game's AddOns settings: canvas pages built from Blizzard's stock templates
  (checkboxes, minimal sliders, dropdowns, scroll lists), because rule lists, the icon grid and the live
  preview don't fit the vertical Settings layout.
- **EllesmereUI:** EUI does not reskin third-party frames by itself. Heraldry registers with
  `EllesmereUI.RegisterSkin` and hands every control and the picker window to its primitives (the player can
  turn this off in EUI); the selection highlight follows EUI's accent colour live. With
  `EllesmereUI.RegisterPlugin` the same pages also appear as a Heraldry section in EUI's own window, in two
  modules: Heraldry (General, Guilds, Players, Sharing, Custom icons) and Display, which alone has EUI's
  Reset button. Pages:
  - **Heraldry** (root): master switch, status (nameplate add-ons, ruleset, guild, rule counts, profile),
    buttons for the target, copy-to-character, slash commands, and **Diagnostics**: the `/heraldry check`
    report (adapters, icons on screen per adapter, plates with hidden names, the target's readable or
    hidden values and matching rule) in a copyable box. A notice for saved data from a newer Heraldry.
  - **Guilds:** "My guild" rule at the top, then a list with add (typed, target's guild, guilds seen on
    plates this session), change icon (click the row), remove with Undo, search and ruleset filter. The
    name box completes from the guilds seen this session, newest first (never extending a name that already
    matches exactly); the Seen menu scrolls once it is taller than about 400 px. Rows
    show static icons that animate on hover and a dot for guilds seen this session. A typed player name
    without a surname is accepted with a warning (most characters have one).
  - **Players:** the same for characters.
  - **Display:** the options above, with a live preview using the real layout code. "Tall icon on Blizzard
    nameplates" (off by default) makes the icon on Blizzard plates that show a health bar as tall as the name
    and bar together, just outside the bar (left of it and of the raid marker or classification icon when they
    show, or right of the level box); Size scales it from
    there. The heights come from the bar itself when readable, else Forever's NamePlateSetupOptions;
    names-only plates, EllesmereUI and other add-ons keep the normal icon. The preview shows it only when
    EllesmereUI's plates aren't loaded.
  - **Sharing:** export and import.
  - **Custom icons** (last): register, preview, remove.
  - Profile checkbox at the top of every page.
- **Minimap button** (on by default; a checkbox on the root page and `/heraldry minimap`): a shortcut, since
  settings are changed in the options. With a target, click picks an icon for the target, right-click for the
  target's guild, and middle-click removes the target's player and guild rules (whichever exist, saying what
  went in chat; `/heraldry undo` puts them back, the rule lists' undo-not-confirm rule). Right-click on
  yourself edits the My guild icon instead of making a plain rule that would override it. Without a target, click opens the Players page, right-click the Guilds page, and
  middle-click opens or closes the options. Shift-click (any button) turns icons on or off; drag moves it.
  A target an action can't use (an NPC, yourself, a hidden name) gets the same chat line as `/heraldry
  player` and `/heraldry guild`. The tooltip names the target and guild a click would act on, and what a
  middle-click would remove. The add-on
  drawer entry has the same clicks. The icon is game-icons.net's Checked
  Shield, filled and outlined like the library. Built with LibDBIcon-1.0 rather than by hand, because that is
  what minimap button collectors understand: MinimapButtonButton gathers LibDBIcon buttons through
  `GetButtonList` and the `LibDBIcon_IconCreated` callback, then re-parents the button, replaces its
  `SetPoint` and hooks `Show`/`Hide`. So Heraldry never positions the button itself and shows or hides it
  only through LibDBIcon. The add-on compartment entry stays the TOC's (with the same clicks), so the button
  isn't added there too. The click reopens the Heraldry page used last, and closes the panel when it shows a
  Heraldry page, in combat too. The add-on's own icon is the one coloured icon: Checked Shield in gold.
- The Settings panel can't open in combat; an open requested in combat happens when combat ends. The
  icon picker is a separate window and works in combat.
- **Slash commands:**
  - `/heraldry` opens the panel
  - `/heraldry guild` sets an icon for your target's guild (opens the picker)
  - `/heraldry player` sets an icon for your target (opens the picker)
  - `/heraldry check` reports what the client exposes about your target
  - `/heraldry try` shows the Display preview icon on your target for 10 seconds
  - `/heraldry minimap` shows or hides the minimap button
  - `/heraldry help`
- **Later:** unit right-click menu entries, a page inside EllesmereUI's own settings window.

## Sharing
No syncing, but a cheap way to hand out a setup: **Export** produces a text string of selected rules
(and custom icon names); **Import** pastes one in and shows what it will add or change, line by line,
before applying. A guild officer posts the Kachow string in Discord, and members set up in one paste.
Custom icon files still travel separately.

Format: `!Heraldry:<version>:<base64 body>:<Adler-32>`; the body is one tab-separated record per line
(`M` my guild icon, `G` guild rule, `P` player rule, `C` custom file name). Nothing is executed: every
field is validated, unknown record types are skipped, and newer versions, damaged and foreign strings
get distinct messages.

## Quality bar
This goes on CurseForge with our names on it, so:

- **Code:** one file per concern (core, identity, icons, matching, plates and adapters, sharing, options,
  slash), no globals beyond the SavedVariables, the slash command and the TOC's addon compartment
  callback, no debug output, errors surfaced only through the normal error handler.
  `luacheck` with the repository's `.luacheckrc` reports nothing.
- **Strings:** all user-facing text in one locale table, so translations can be added without touching code.
- **Performance:** event-driven, cached lookups, no per-frame work; check with the in-game profiler
  (`/console scriptProfile`) under a crowded city.
- **Testing:** headless Lua 5.1 tests for the pure logic, and the in-game checklist in `TESTING.md`
  covering EUI full plates, EUI name-only, plain Blizzard plates, friendly and enemy, in and out of combat,
  in an instance, `/reload`, character profile on and off.
- **Release:** git repo, `CHANGELOG.md`, `README.md` with screenshots, `LICENSE`, `.pkgmeta`, and the
  BigWigs packager on GitHub Actions to build and upload tagged releases to CurseForge.
- **Art:** only art with a license or explicit permission ships, credited per entry. The McQueen image
  stays a personal custom icon.

## Build order
1. Git repo, `Heraldry\` add-on folder, file layout, settings and profiles with migrations.
2. Identity (ruleset, keys), matching, slash commands. Port the prototype's plate code.
3. Enemy plates and display options.
4. Icon system: library manifest with static and animated (FlipBook) icons, game icons, icon picker.
5. Options panel.
6. Maintainer tooling for converting 7TV emotes into library icons.
7. Export and import.
8. Custom icons.
9. Testing checklist, README, packaging, first CurseForge release.
