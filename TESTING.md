# Heraldry: in-game test checklist

Everything here runs in the WoW Forever client. Tick each line; when one fails, note what you saw and the
output of `/heraldry check` with the affected player targeted.

## Setup
1. Link the add-on into the game (once):
   `New-Item -ItemType Junction -Path "<WoW folder>\_forever_\Interface\AddOns\Heraldry" -Target "<repository>\Heraldry"`
2. Turn on Lua errors: `/console scriptErrors 1` (or install BugSack + BugGrabber).
3. The development library add-on (`HeraldryDev\`, gitignored, never packaged) gives two library icons for
   testing: **Dance (dev)**, animated 64x64 at 25 fps, and **McQueen (dev)**, static wide. Link it too:
   `New-Item -ItemType Junction -Path "<WoW folder>\_forever_\Interface\AddOns\HeraldryDev" -Target "<repository>\HeraldryDev"`
   To recreate it (add `--force` to replace existing files):
   `py -3 tools\emote2lib.py 01F6MZGCNG000255K4X1K7NTHR --key dev_dance --name "Dance (dev)" --license none --dev --write`
   `py -3 tools\emote2lib.py 01FZEPTYQG000CDB2YM8X7YW9S --key dev_mcqueen --name "McQueen (dev)" --source "Disney/Pixar (personal use)" --license none --dev --write`

## Load and first run
- [ ] Fresh install (delete `HeraldryDB` from `WTF\Account\<account>\SavedVariables\Heraldry.lua`): log in,
      no Lua error, no chat message.
- [ ] Game Menu > Options > AddOns shows **Heraldry** with Guilds, Players, Display, Sharing, Custom icons.
      Every page opens without errors and looks like the stock settings (fonts, checkboxes, sliders).
- [ ] The addon compartment (minimap add-on drawer) has Heraldry; clicking it opens the options.
- [ ] `/heraldry` opens the options; `/heraldry help` lists the commands; an unknown word shows the help.
- [ ] `/heraldry` in combat says the options open after combat, and they do.
- [ ] Diagnostics box on the first page: lists the nameplate add-ons, icons on screen per add-on, plates
      with hidden names, and (with a target) the target's name, guild and matching rule; Refresh updates it;
      clicking the box selects all for Ctrl+C.
- [ ] Newer data: set `version = 99` in `HeraldryDB` (SavedVariables file, game closed), log in: one chat
      line says changes won't be saved and the first page shows the notice; change a rule, `/reload`, the file
      still has `version = 99` and the original rules. Restore the file afterwards.

## Minimap button
- [ ] The Checked Shield button is on the minimap; its tooltip lists click, right-click and drag. Click opens
      the options; click again with a Heraldry page showing closes them.
- [ ] Right-click with the tooltip up: icons on plates turn off, the tooltip says so; right-click again turns
      them back on.
- [ ] Drag it around the minimap, `/reload`: it stays where you left it.
- [ ] Untick "Minimap button" on the first page: the button goes. `/heraldry minimap` brings it back and the
      checkbox follows.
- [ ] Heraldry appears in the add-on list and the compartment with the shield icon, once each.
- [ ] In combat, with a Heraldry page open: a click closes the options, and they don't reopen when combat
      ends; no "action blocked" message or Lua error, and a game setting changed just before (on another
      page) is kept. With the options closed, a click in combat says they open after combat, and they do.
- [ ] Reopening with the button returns to the Heraldry page used last.
- [ ] The add-on drawer's Heraldry entry: click and right-click do the same as the button.
- [ ] **EllesmereUI minimap flyout:** the shield appears in the flyout labelled Heraldry; click, right-click
      and the tooltip work there (no "Drag" line in the flyout). With the flyout closed, untick the checkbox:
      the button is gone from the flyout without a gap; tick it: it comes back. (EUI re-shows a button that
      hides while its flyout is open, so test with it closed.)
- [ ] **EnhanceQoL's Minimap Button Bin** (if used): the button is binned; hiding and showing it with the
      checkbox keeps it in the bin.
- [ ] **MinimapButtonButton** (install it and turn EllesmereUI's minimap module off; EUI disables MBB): the
      button is collected into MBB's drawer, clicks and the tooltip work there, and hiding it with the
      checkbox removes it from the drawer without a gap. `/mbb list` shows `LibDBIcon10_Heraldry`.
- [ ] TwitchEmotes (which embeds an older LibDBIcon) loaded too: both its button and Heraldry's work.
- [ ] Missing libraries: rename `Heraldry\Libs` and restart: no Lua error, no button, the checkbox is greyed
      out with a tooltip that says why, `/heraldry minimap` explains. Rename it back.

## Library
- [ ] The Library tab lists the game-icons set; searching "shield", "wolf" or "crown" finds them, and so do
      tag words such as "hunter", "bird", "undead", "healer", "tank", "frost" and "death knight". "ice" finds
      Ice cube but not Jeweled chalice.
- [ ] The category dropdown appears on the Library tab with the themes (Shields & heraldry, Weapons, ...);
      picking one narrows the grid, search works inside it, and switching to Twitch Emotes and back resets it.
- [ ] Scroll through all ~430 library icons: smooth, no hitch the second time through.
- [ ] Sharpness at your own UI scale: the picker's large grid, and a plate icon with the Display Size at 3,
      look crisp (the library is 128 px DXT5 BLP). Each icon shows a black outline and black enclosed
      areas (Checked Shield's checks, Griffin Shield's griffin); no icon is a green square.
- [ ] On a 20 px nameplate icon over bright ground (snow, sand), the shape is still readable.
- [ ] The tooltip credits the author ("By Lorc, from game-icons.net").

## Rules and the picker
- [ ] Guilds page, My guild card shows "Your guild on this character: <guild>". Tick the checkbox with no
      icon chosen: the picker opens; cancel leaves it off; choosing an icon turns it on.
- [ ] Picker: tabs Library, Game icons, Twitch Emotes (only with TwitchEmotes loaded), Custom.
- [ ] Library tab shows Dance (dev) and McQueen (dev) with names. Grid cells are still; hovering Dance
      animates it, leaving stops it; the preview at the bottom animates the selection.
- [ ] Searching "dance" filters the Library tab; clearing it restores the list.
- [ ] Game icons tab: scrolls smoothly through thousands of icons. Hovering icons shows names, not
      "Icon 1234" (item icons read like "Sword", "Gem ruby"). Searching "sword" or "gem" fills the grid at
      once; searching a spell name you know ("Fireball", "Heroic Strike") shows its icon at once; a partial
      word ("fire") shows "Indexing spell names..." progress and fills in more results over several seconds;
      "ice" doesn't find Sacrifice. An icon ID (`134400`) and a path (`Interface\Icons\INV_Misc_QuestionMark`)
      each show that icon; typing other digits ("1266") shows no icon, never a green square.
- [ ] Twitch Emotes tab (TwitchEmotes installed): the category dropdown lists packs (BTTV+FFZ, Pepes, ...,
      Giga Twitch Emotes and any other installed pack, by their titles); search by emote name works;
      animated emotes play on hover.
- [ ] Twitch packs (with a third-party pack that registers into TwitchEmotes installed): a wide static emote
      is wide, not tall, in the picker, a rule row and on a plate; an animated emote whose frames are narrower
      than its strip has no transparent band in its thumbnail and animates on hover and on plates; a very tall
      strip (up to 8192 px) animates; an emote a pack replaces by name shows the pack's art.
- [ ] Double-click chooses; Choose button chooses; Cancel and Escape close without changes; the window
      can be dragged.
- [ ] Right-click an icon: a star appears and it shows in the Favorites row; right-click again removes it.
      Chosen icons appear first in the Recent row next time. Both rows survive `/reload` and are the same
      with "this character only" on or off.
- [ ] Keyboard (out of combat, search box not focused): arrow keys move the selection through the grid and
      scroll it into view; Enter chooses.
- [ ] The preview at the bottom shows the selected icon beside "Fenna Brightwater" at your Display position
      and size.
- [ ] Add a guild by typing its name, by **Target's guild**, and from **Seen guilds**. Each opens the picker
      titled with the guild name, and the rule appears in the list with its icon.
- [ ] Name autocomplete (guilds and players, after seeing some plates): typing the start of a seen name fills
      in the rest, highlighted; typing on narrows it, Backspace drops the suggestion, Tab accepts it, Enter adds
      what the box shows. With "Ana" and "Anaxis" both seen, typing `Ana` suggests nothing more. After an add
      clears the box, the first letter typed completes again.
- [ ] In a crowded city, **Seen guilds** and **Seen players** scroll instead of running off the screen.
- [ ] Remove a rule: it disappears and an Undo bar shows for about 8 seconds; Undo restores it.
- [ ] Ruleset filter "All rulesets" shows rules from other rulesets dimmed with a ruleset label.
- [ ] Players page: add your target; choose **No icon** in the picker; the row says "No icon (hides the
      guild icon)".
- [ ] Typing a first name only ("Somebody") is accepted with a yellow warning about the missing surname.
- [ ] If the client lets a character have no surname (character creation, or an existing one): target it,
      `/heraldry check` shows `surname: <none>`, and a rule for its one-word name shows its icon.
- [ ] Rule rows: icons are still until hovered; a green dot marks guilds/players seen on plates this session
      (tooltip says so); clicking a row opens the picker.
- [ ] `/heraldry guild` and `/heraldry player` with: no target, an NPC, yourself (player), a guildless
      player (guild). Each prints a specific message instead of opening the picker.

## Nameplates: EllesmereUI loaded
Check icon position against the name, size, and that it moves with the plate.
- [ ] **Friendly full plates** (EUI friendly players with health bar): icon left of the name, same height
      as the name text, tight against the text.
- [ ] **Friendly name-only** (EUI default): icon left of the name. With EUI's guild subtitle on, the icon
      lines up with the name (first line), not the guild line.
- [ ] **Enemy plates** (duel a guildmate or flag for PvP against a matched guild): icon left of the name
      text itself, not at the left edge of the health bar. Try a long and a short name.
- [ ] Switch EUI friendly mode (name-only <-> health bar) and move EUI's enemy name slot: icons follow
      within half a second, no duplicate icons.
- [ ] Start and finish a duel with a guildmate: the icon moves from the friendly to the enemy plate and back.
- [ ] With EUI's Show Target Arrows on, target a matched friendly player (health bar mode): the icon moves
      out past the left arrow, and back when you untarget.
- [ ] With EUI's name raid marker on, mark a matched enemy: the icon moves left of the marker.
- [ ] Enemy plates with a long "First Surname" name that EUI cuts with "...": the icon sits at the edge of the
      name box, not past it. With EUI's enemy name wrap on, the icon lines up with the first line.
      `/heraldry check` shows the name box width it used.
- [ ] Short enemy name with a raid marker: the icon stays close to the name if there is room; with a long
      name it moves left of the marker.
- [ ] Follower dungeon or delve: friendly names are Blizzard's there; the icon still sits beside them
      (`/heraldry check` names Blizzard nameplates).
- [ ] EUI skin: the picker window, buttons, checkboxes, dropdowns, edit boxes, lists and tabs use the
      EllesmereUI look; with Heraldry's skinning turned off in EUI's options (Blizzard Skins+ > Third-Party
      Addons) and a `/reload`, they use the Blizzard look.
- [ ] EUI options window: a **Heraldry** section at the bottom of the sidebar with two modules, Heraldry
      (General, Guilds, Players, Sharing, Custom icons) and Display; changes there show on the Blizzard
      options pages too. EUI's Reset button appears only on Display and resets only display settings.
      Pages fit EUI's content width without text running off the edge.
- [ ] Change EUI's accent colour: the picker's selected-icon highlight follows it.
- [ ] EUI friendly full plates (health bar mode): walk into a crowd of matched players; no icon flashes above
      a plate before EUI builds it.

## Nameplates: Blizzard (disable EllesmereUINameplates)
- [ ] Friendly and enemy Blizzard plates: icon left of the name text, not at the bar's edge. A long name: the
      icon stays at the bar's edge (`/heraldry check` shows the box width; compare with the bar).
- [ ] Forever's level indicator and the icon don't overlap in the default position.

## Nameplates: other add-ons (one at a time, EllesmereUINameplates disabled)
For each, check friendly and enemy plates, that `/heraldry check` names the add-on that drew the icon, and
that there is never an icon at a hidden Blizzard plate's position.
- [ ] **Plater:** icon beside the name in the bar, and beside the name on friendly players without a bar.
      With a long name, the icon stays at the bar's edge. With Plater hiding friendly players (city
      setting), no icon floats where their plates would be; Diagnostics counts them under "hides the plate".
- [ ] **ElvUI** (nameplates module on): icon beside the name. Units ElvUI hides (style filters) get no
      icon. With ElvUI's nameplates off, Blizzard's.
- [ ] **Threat Plates:** icon beside the name.
- [ ] **Platynator**, or any other plate add-on: icon centred above the plate without covering its name;
      check says "Generic". Untick Display > "Show on unrecognised nameplate add-ons": those icons go away.

## Display options (watch the live preview and real plates together)
- [ ] Each position (left, right, above, below) moves the icon on the preview and on plates.
- [ ] Size, gap, offsets and opacity sliders update plates immediately.
- [ ] Untick friendly, then enemy plates: icons hide on that side only.
- [ ] Untick Open world: icons hide in the world and come back when ticked.
- [ ] Hide in combat: icons hide when combat starts and return after.
- [ ] Reset display settings and the panel's Defaults button restore the defaults (rules stay).
- [ ] Animated library icons play on plates and stop when the plate leaves the screen (no stutter in a
      crowd).
- [ ] With an animated icon on screen: Alt+Z twice, then take a portal (loading screen). The icon still
      animates afterwards and never shows the whole sprite sheet.
- [ ] **Try on target:** target any unit with a plate, click Try on target (or type `/heraldry try`): the
      preview icon shows on its plate for 10 seconds with the current settings, then goes away (unless a rule
      matches). It stays on that unit even if its plate scrolls away and comes back. With no target it says
      why.

## Combat, instances and secret values
- [ ] In combat in the open world, icons stay on matched players. Run `/heraldry check` on a matched
      player in combat and note which values show as `<hidden>`.
- [ ] In a dungeon with guildmates: note whether friendly plates show icons (the game may restrict them).
      No Lua errors either way. `/heraldry check` inside the instance: note hidden values.
- [ ] Battleground or arena (if available): enemy plates of matched guilds.
- [ ] "Show nothing when a name is hidden": with a player set to No icon, in a place where names are hidden,
      ticking it removes the guild icon for that player.

## Profiles and persistence
- [ ] Tick "Use settings for this character only": rules stay (copied). Add a rule; untick: the rule is gone
      (account settings). Tick again: the character's rule is back.
- [ ] "Copy shared settings to this character" replaces the character copy.
- [ ] `/reload`: everything persists, icons come back on visible plates without moving.
- [ ] Full client restart (exit the game, start again): settings persist.
- [ ] Log in on an alt in another guild: "My guild" follows the alt's guild.

## Sharing
- [ ] Export with all boxes ticked: a `!Heraldry:1:...` string appears selected; Ctrl+C copies it.
- [ ] Paste it on another character with the character profile on (empty rules): Preview lists every rule
      as New; untick one; Apply adds the rest only.
- [ ] Import the same string again: every row says Already set.
- [ ] Paste garbage, a truncated string, and a string with one character changed: each shows a clear
      error and nothing changes.
- [ ] A rule using a Twitch emote, imported on a client without TwitchEmotes: the row says it needs the
      TwitchEmotes add-on and shows a question mark; plates show no icon for it.

## Custom icons
- [ ] Create `Interface\AddOns\Heraldry_Custom\`, copy `HeraldryDev\media\dev_mcqueen.tga` there as
      `mcqueen_wide.tga`, restart the game fully.
- [ ] Custom icons page: typing `mcqueen_wide` previews it; Register adds it; it appears in the picker's
      Custom tab and works on plates at a 2:1 shape.
- [ ] A bad name (`my icon`, `x_anim2x2_9_10`) shows an error and is not added.

## Texture checks
- [ ] Orientation: the library's DXT5 BLPs, the add-on's own TGA icon and emote2lib's TGAs (top-left
      origin) appear upright, not mirrored or flipped, on plates and in the picker (an asymmetric icon such
      as Wolf head faces right).
- [ ] The animated sheet plays all 198 frames in order without showing parts of neighbouring frames or the
      empty bottom of the sheet.

## Performance
- [ ] In a crowded city, `/console scriptProfile 1`, `/reload`, wait a minute, check Heraldry's CPU in an
      add-on profiler: no steady growth, nothing per frame except while the Game icons search is indexing.
