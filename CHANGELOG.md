# Changelog

All notable user-facing changes will be recorded here.

## Unreleased

- Profiles are now complete, self-contained setups: each profile holds its own muscles and memories, so switching profiles swaps your entire setup rather than just toggling muscles on and off. Existing data is migrated automatically.
- Creating a profile now starts empty; use Clone to copy an existing profile one-to-one.
- Moved profile selection out of the header into a dedicated Profiles tab, where you set the account-wide default profile and an optional override for the current character.
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
