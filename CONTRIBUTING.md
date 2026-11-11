# Working on Heraldry

## Layout
| Path | What |
|---|---|
| `Heraldry/` | The add-on (what ships). TOC load order: locale, core, identity, library, icons, database, matching, sharing, nameplates (core, then adapters with Blizzard last), UI, slash. |
| `Heraldry/Plates/` | `Plates.lua` places icons; one adapter file per nameplate add-on. |
| `Heraldry/UI/` | Options pages (one file each) and the icon picker. |
| `Heraldry/Library.lua` | Icon library manifest (format documented at the top). |
| `Heraldry/Libs/` | LibStub, CallbackHandler, LibDataBroker and LibDBIcon for the minimap button. Gitignored: the packager fetches them (`.pkgmeta` externals). For development, copy those four folders from any installed add-on that embeds them (EnhanceQoL does) or check them out from the URLs in `.pkgmeta`. |
| `tools/` | Maintainer scripts: `gameicons2lib.py` (the game-icons.net library, from `game-icons.txt`), `emote2lib.py` (single images and 7TV emotes), `blp.py` (DXT5 BLP writer for greyscale art), `credits.py`. |
| `tests/` | Headless tests: Lua 5.1 for the add-on, Python for the tools. |

Rules of the code base: everything goes through the add-on namespace (`local addonName, ns = ...`); the only
globals are `HeraldryDB`, `HeraldryCharDB`, `SLASH_HERALDRY1`/`SlashCmdList.HERALDRY` and the TOC's
`Heraldry_OnAddonCompartmentClick`. Every user-facing string lives in `Locales/enUS.lua`. Never store fields
on Blizzard or other add-ons' frames; never compare, concatenate or index with a value that may be secret
(`ns.IsSecret` first).

## Lint and tests
Tools live in the gitignored `.tools/` folder (luacheck 1.2.0, Lua 5.1.5). From the repository root:

```
.tools\luacheck.exe Heraldry tests                     # must report 0 warnings / 0 errors
for %f in (Heraldry\*.lua Heraldry\Locales\*.lua Heraldry\Plates\*.lua Heraldry\UI\*.lua) do .tools\lua51\luac5.1.exe -p %f
.tools\lua51\lua5.1.exe tests\run.lua                  # add-on logic, loads the shipped files
py -3 -m unittest discover -s tests -p "test_*.py"     # tools
```

The Lua tests load the real add-on files on top of `tests/wowstub.lua` and cover ruleset tokens, name
folding and keys, rule precedence (including secret values), icon ids, custom names, manifest validation,
migrations and profiles, and export/import. Everything visual is tested in game with `TESTING.md`.

## Adding library icons
Only add art Heraldry may ship: an open license (record the SPDX id and put the license text in
`Heraldry/licenses/`, unless the license lets the credit link to it) or explicit permission from the author
(record who, where and when).

**game-icons.net** (CC BY 3.0), the main set: add a line to `tools/game-icons.txt` and run

```
py -3 tools\gameicons2lib.py
py -3 tools\credits.py
```

It downloads what's missing (cached in `tools/.cache/`), fills enclosed areas black, adds a black outline,
writes `Heraldry/media/library/game-icons/<key>.blp` (128 px DXT5 with mipmaps, by `tools/blp.py`) and rewrites the game-icons block of `Library.lua`
(and the add-on's own icon, `Heraldry/media/heraldry.tga`). `--check` verifies the block and textures match
the list. Never remove a shipped line: its key is in players' rules.

**Game icon names** (`Heraldry/IconNames.lua`) come from the community listfile (file labels) and WoW
Forever's own spell tables as exported by wago.tools (product `wowf`; player abilities as spell IDs). To pick
up icons and abilities from a newer Forever build:

```
py -3 tools\iconnames.py --refresh
```

It downloads the verified listfile into `tools/.cache/listfile/` and the spell tables into `tools/.cache/wago/`,
records the Forever build in `build.txt` and the generated file, then regenerates the data; `--check` verifies
the file is in generated form. Without `--refresh` it reuses the
cached downloads. If wago.tools renames a column, the tool stops and names it.

**Anything else**, one image or 7TV emote at a time:

```
py -3 tools\emote2lib.py <file | URL | 7TV emote URL or id> --key <key> --name "<Name>" ^
    --tags <words> --author "<author>" --license <SPDX id | permission> [--permission "<details>"] ^
    [--source "<source>"] [--url <page>] --write
py -3 tools\credits.py
```

`--write` inserts the entry into `Library.lua`; without it the entry is printed. Keys are stored in players'
settings and export strings: never rename one; add an `aliases` entry instead. Each animated icon in use costs
its sheet's video memory (a 1024x1024 sheet is 4 MB); the tool prints it.

For local testing with art that must not ship, add `--dev`: the tool creates a separate add-on,
`HeraldryDev/` (TOC, `Library.lua`, `media/`), gitignored and ignored by the packager. Link it into the game
like Heraldry itself; Heraldry picks up its entries through the global `HeraldryDevLibrary`.

## Adding a nameplate adapter
Create `Heraldry/Plates/<AddOn>.lua`, list it in the TOC before `Plates\Blizzard.lua`, add the add-on to
`## OptionalDeps`, and register a table with `IsAvailable()`, `GetName(unit, nameplate) -> fontString, hints`
and optionally `Enable(plates)` (see the header of `Plates/Plates.lua` for the hints). Return nil for plates
the add-on isn't drawing right now, so the next adapter (or the generic fallback) gets them.

## Releases
Tag `vX.Y.Z` on main and push the tag; the GitHub workflow runs the BigWigs packager, which replaces
`@project-version@`, strips `#@do-not-package@` blocks and the paths in `.pkgmeta`'s ignore list, and uploads
to CurseForge (needs the `CF_API_KEY` secret and `X-Curse-Project-ID` in the TOC). Update `CHANGELOG.md`
first.

Check a package locally with the packager (`release.sh` from BigWigsMods/packager) in Git Bash, without
uploading: `bash release.sh -d -e -z -r <out dir>`, then inspect `<out dir>/Heraldry`. Checked on
2026-11-08: the package holds only `Heraldry/` (code, `CREDITS.md`, `licenses/`) plus the root `CHANGELOG.md`
and `LICENSE`; `tools`, `tests`, `HeraldryDev` and the docs are left out, and the packager reports
build type `version-forever` and game version `1.60.1`. (`-z` skips the zip only because Git Bash has no
`zip`; the GitHub workflow makes it.) That check predates the `.pkgmeta` externals (the minimap libraries)
and the game-icons textures: a local run now also needs `svn` for the WowAce externals, so it has not been
repeated. The `Package (dry run)` workflow (Actions tab, Run workflow) builds the zip on GitHub without uploading
it; its log lists every file that would ship, externals included. Before the
first release, run the packager once (locally with svn, or the GitHub workflow without
uploading) and check that `Heraldry/Libs/` holds the four libraries the TOC lists, that
`Heraldry/media/heraldry.tga` and `media/library/game-icons/` are in, and that `CREDITS.md` ships.
