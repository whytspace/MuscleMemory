# Changelog

All notable user-facing changes will be recorded here.

## Unreleased

- Binding a spell or item that a Dynamic Action resolves to now offers to bind the Dynamic Action instead (e.g. Kick -> Interrupt), so the slot keeps working across your characters. Choose the behavior under Settings -> "When binding an action": Never, Suggest (popup, the default) or Automatic.
- Added predefined Dynamic Actions for the racials whose spell differs by class: **Blood Elf: Arcane Torrent**, **Orc: Blood Fury** and **Draenei: Gift of the Naaru**. Bind these instead of the raw racial and every character gets the variant it actually knows.

- Toys learned into the Toy Box can now be restored: availability and pickup go through the Toy Box APIs, so a bound toy no longer reports "not currently available" once the physical item has left the bags.

- Fixed a mount slot being reported as an unapplied change on every login (and re-applied without effect): mount actions now match whether the action bar reports the journal mount or its summon spell.

## 0.5.1 - 2026-06-26

## 0.5.0 - 2026-06-26

## 0.4.1 - 2026-06-26

## 0.4.0 - 2026-06-26

- Leaving combat no longer triggers a change re-scan or the "changes are available" prompt; changes are still detected on spec and spell changes.
- Added icons across the UI: the Layers and Dynamic Actions tabs now carry glyphs; a fork badge marks slots (and dynamic-action lists) where a dynamic action is bound; and a `{ }` badge marks dynamic actions that render as macros, on the slot, in the bind list, and in the dynamic-actions list. Hovering an action icon now also shows the badge glyph with a short "This is a dynamic action" / "This is a macro" note.
- Renamed the two core concepts for clarity: "muscles" are now **action bar layers** and "memories" are now **dynamic actions**. The window tabs, slash commands (`/mm layer`, `/mm action`), and help text use the new names. Existing setups are migrated automatically.

## 0.3.0 - 2026-06-25

- Memories can now be rendered as a macro instead of placing the spell or item directly, so you get macro flexibility (mouseover, focus, modifier and conditional casts) while the memory still resolves the right action for your class, spec, and what you actually have. Turn it on per memory in the Memories tab and write a body with `%name%` where the resolved spell or item goes, e.g. `/use [@mouseover,help][@focus] %name%`. The add-on creates and maintains a per-character macro for you and removes it once it is no longer used. Available for memories whose candidates are all spells, items, toys, or mounts.
- The predefined "Interrupt" memory now ships as a macro that interrupts your focus target (falling back to your current target): `/use [@focus,harm][] %name%`, still resolving to each class's own interrupt.
- Added a predefined "Battle Rez" memory covering the Druid, Death Knight, Warlock, and Paladin combat resurrection spells plus the engineering battle-rez items (Emergency Soul Link, Convincingly Realistic Jumper Cables, and earlier expansions'), resolving to whichever you can currently use.
- Item memories now resolve only to items you can actually use: those out of their level range, requiring a profession you lack, or sitting in the bank are no longer treated as available.
- Crafted items in a memory now show their quality crystal next to the name.
- Hovering a memory or one of its candidates now shows a tooltip with the spell/item it resolves to, in the memory rail, the candidate list, and the muscles slot list.
- Added a per-profile "When changes are detected" setting that chooses how the add-on reacts when an event re-scan finds changes: do nothing, print a message, show the popup (the default), or apply automatically.
- Fixed a spurious "changes are available" prompt at login: a slot that cannot currently be restored (such as a temporarily unavailable pet ability) no longer triggers the prompt once the game has finished loading.

## 0.2.0 - 2026-06-24

- Profiles are now complete, self-contained setups: each profile holds its own muscles and memories, so switching profiles swaps your entire setup rather than just toggling muscles on and off. Existing data is migrated automatically.
- Creating a profile now starts empty; use Clone to copy an existing profile one-to-one.
- Moved profile selection out of the header into a dedicated Profiles tab, where you set the account-wide default profile and an optional override for the current character.
- Switching profiles now offers to apply or preview the change, the same as spec and spell changes already do.
- Renamed the built-in memories from "standard" to "predefined".

## 0.1.4 - 2026-06-23

- Muscle Memory is now published on CurseForge.

## 0.1.3 - 2026-06-23

- Recognize the Single Button Assistant when capturing a slot, so it is saved and applied as the assistant itself instead of the ability it currently recommends.

## 0.1.2 - 2026-06-23

- Show the Muscle Memory logo in WoW's add-ons list.
- Recognize placeholder spells (such as "Command Pet" becoming "Primal Rage"), so they are not re-applied continuously.

## 0.1.1 - 2026-06-23

- Release under the MIT License.

## 0.1.0 - 2026-06-23

- Initial public launch track for Muscle Memory.
- Capture and apply action-bar muscles across characters.
- Resolve purpose-based memories such as interrupt, taunt, lust, defensives, movement, mounts, items, macros, battle pets, and equipment sets.
- Manage profiles, muscles, memories, fallback behavior, and condition-aware candidates through slash commands and the in-game UI.
- Package releases through a maintainer script and the WoW addon packager workflow.
