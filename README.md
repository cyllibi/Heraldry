# Heraldry

A World of Warcraft **Forever** add-on that shows an icon next to the names of the guilds and players you
choose, on friendly and enemy nameplates. Mark your own guild, your allies, your rivals, or one particular
player.

<!-- Screenshots: add before the first release (EllesmereUI plates, Blizzard plates, the options). -->

## Features
- An icon for any guild, an icon (or no icon) for any player, and a "my guild" icon that follows whichever
  guild your character is in.
- Icons from Heraldry's own library (static and animated), the game's built-in icons (searchable by spell
  name), the TwitchEmotes add-on if you have it, or your own image files.
- Works with **EllesmereUI Nameplates** (full plates, name-only and enemy plates, skinned to match
  EllesmereUI, with its own section in EUI's options) and with Blizzard's nameplates. Plater, ElvUI and
  Threat Plates have adapters too (untested in game so far). With any other nameplate add-on (Platynator,
  small Forever plate add-ons) the icon sits centred above the nameplate; plates a known add-on hides never
  get an icon.
- Position, size, gap, offsets and opacity, with a live preview; per-context visibility (world, dungeons,
  raids, PvP, combat).
- Settings shared by all characters, or per character.
- Share your setup as a text string; others preview it before applying.

## Use
- `/heraldry` opens the options (also under Game Menu > Options > AddOns, and the add-on drawer).
- The minimap button (a gold shield): click for the options, right-click to show or hide icons, drag to move.
  Minimap button collectors (EllesmereUI's minimap, MinimapButtonButton) pick it up. `/heraldry minimap`
  or the checkbox on the options' first page hides it.
- `/heraldry guild` picks an icon for your target's guild; `/heraldry player` for your target;
  `/heraldry try` shows your preview icon on your target for 10 seconds.
- `/heraldry check` shows what the game tells add-ons about your target, for bug reports; the same report
  is under Diagnostics on the options' first page.
- In the icon picker, right-click an icon to make it a favorite; arrow keys and Enter work too.

In dungeons, raids and combat the game can hide names and guilds from add-ons. Heraldry then skips what it
can't read; see the Display page and `/heraldry check`.

## Custom icons
Put 32-bit TGA (or BLP) files in `Interface\AddOns\Heraldry_Custom\`, restart the game, and register them by
name on the Custom icons page. Square icons are 128x128; add `_wide` to the name for 256x128. Animated
sheets are named `name_anim<columns>x<rows>_<frames>_<fps>` with 64x64 frames (128x64 for `_wide`).

## Credits
- Library icons and Heraldry's own icon: from [game-icons.net](https://game-icons.net) (CC BY 3.0), filled and
  outlined; each icon's author is listed in [`Heraldry/CREDITS.md`](Heraldry/CREDITS.md), generated from the
  manifest.
- Game icon names: made from the icons' file names in the community
  [wow-listfile](https://github.com/wowdev/wow-listfile); the names themselves are Blizzard's.
- Twitch Emotes: shown from your own installed TwitchEmotes add-on and any emote pack that registers into it
  (TwitchEmotes_Giga, ...). Heraldry ships none of that art; credit belongs to those add-ons and the emotes'
  creators.

## License
Heraldry's code is under the [MIT License](LICENSE). The bundled icons keep their own license (CC BY 3.0, see
[`Heraldry/CREDITS.md`](Heraldry/CREDITS.md)).

## Development
See [`CONTRIBUTING.md`](CONTRIBUTING.md) for the layout, lint, tests, the icon tooling and releases.
