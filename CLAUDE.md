# Heraldry: a WoW Forever add-on

Heraldry targets WoW Forever (interface `16001`). Retail is not a goal.

Heraldry (`Heraldry\`) shows an icon next to the names of guilds and players the user picks, on nameplates.
Per-player rules override per-guild rules. Icons come from a bundled library (game-icons.net silhouettes,
filled and outlined; animated icons are supported), built-in game icons, emotes from TwitchEmotes packs, and
(minor) custom files. It grew out of an earlier single-guild prototype, since retired.

- **Read first:** `DESIGN.md` (authoritative design), `CONTRIBUTING.md` (layout, lint, tests, packaging),
  `TESTING.md` (in-game checklist).
- **Compatibility:** Heraldry is a standalone add-on: Blizzard's own nameplates are the primary target and
  must work well with nothing else installed. EllesmereUI Nameplates is the recommended upgrade for a nicer
  look and gets first-class support; Plater, ElvUI and Threat Plates have adapters, and a generic fallback
  covers the rest. 12.x "secret values" restrict what add-ons can read on nameplates; never compare or do
  maths on values that may be secret.
- **Checks:** `.tools\luacheck.exe .` (0 warnings), `luac5.1 -p` on every file, `.tools\lua51\lua5.1.exe
  tests\run.lua`, the Python tool tests, `tools\credits.py --check`, `tools\gameicons2lib.py --check` and `tools\iconnames.py --check`.
  All must pass before committing.
- **Art rules:** only art with a license or explicit permission ships, credited per library entry. Library
  icons are black and white; only Heraldry's own icon (`media\heraldry.tga`) is gold. Unlicensed test art
  lives only in the gitignored `HeraldryDev\` add-on.
- **Review process:** a builder plus two critic agents (design/compatibility and code quality) score each
  round 1-100; 95+ passes. Reviews live in the gitignored `.reviews\`. Every brief tells the critics to:
  - check every list, menu and dropdown against the user's real data sizes (e.g. ~80 TwitchEmotes packs,
    hundreds of seen guilds): it must scroll or page, never run off the screen;
  - judge whether a feature does its job, not only whether the change is correct, and propose what is
    missing (the minimap button had no click to reach the options with a target up until the user asked).
- **Repository:** public at github.com/cyllibi/Heraldry, MIT licensed. Keep unrelated projects out of it.

## Environment
- The developer's local setup (folders, the add-ons they run) is in the gitignored `CLAUDE.local.md`, never in
  tracked files. Never write local paths, drive letters, user names or personal add-on lists into anything
  committed: docs, comments, tool defaults or commit messages.
- Tools: ffmpeg (on PATH, in `FFMPEG_DIR`, or `--ffmpeg-dir`), Python 3, and luacheck plus Lua 5.1 in the
  gitignored `.tools\`.
- `Heraldry\Libs\` (minimap button libraries) is gitignored; see CONTRIBUTING.md for where to get them.
- Some add-ons ask not to be used as code references (Auctionator, Syndicator); respect that.
- Ask the user before writing anything into the WoW folder. WoW only loads new texture files on a full
  restart, not `/reload`. Testing is in-game only.
