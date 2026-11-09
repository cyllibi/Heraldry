# Changelog

All notable changes to Heraldry. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added
- Icons next to the names of chosen guilds and players on nameplates, with player rules (including
  "no icon"), guild rules per ruleset, and a "my guild" rule that follows your character's guild.
- EllesmereUI Nameplates support (full plates, name-only and enemy plates) and Blizzard nameplates.
- Icon sources: the Heraldry library (static and animated), built-in game icons
  named and searchable by spell name and file name, emotes from the TwitchEmotes add-on, and custom image
  files.
- Options under AddOns: Guilds, Players, Display (with a live preview), Sharing and Custom icons.
- Account-wide settings with an optional per-character copy.
- Export and import of rules as text, with a preview before applying.
- `/heraldry`, `/heraldry guild`, `/heraldry player`, `/heraldry check`, and the same check as a Diagnostics
  box in the options.
- Plater, ElvUI and Threat Plates adapters, and a fallback that puts the icon above the nameplate for any
  other nameplate add-on.
- EllesmereUI skinning and a Heraldry section in EllesmereUI's options.
- Icon picker favorites, recent icons, keyboard navigation, and a preview beside a sample name.
- "Try on target" on the Display page, and `/heraldry try`.
- About 430 library icons from game-icons.net: shields, emblems, crowns, weapons, beasts, zodiac signs,
  elements and more, outlined so they read on any ground, sharp at 128 px (compressed BLP), grouped into
  categories in the picker and searchable by theme, class and role words.
- A minimap button (LibDBIcon, so minimap button collectors such as MinimapButtonButton pick it up), with
  `/heraldry minimap` to show or hide it.
- Guild and player name boxes complete names seen on nameplates this session; the Seen lists scroll.
