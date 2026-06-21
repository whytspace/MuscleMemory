# Muscle Memory

**Bind buttons by purpose, not just spells.**

Muscle Memory keeps action bars consistent across characters. A profile chooses active layouts, layouts assign action bar slots, and slots can point to regular actions or purpose-based action groups such as Kick / Interrupt and Taunt.

## Current MVP Commands

- `/mm` opens the configuration window.
- `/mm apply [profile]` applies the active profile, or the named profile.
- `/mm preview [profile]` prints the resolved slot plan without changing action bars.
- `/mm copygroup <standard> [custom]` copies an immutable standard action group into editable custom data.
- `/mm debug` toggles debug output.

## Current Model

- **Profile**: chooses which layouts are active.
- **Layout**: maps action slots to assignments.
- **Assignment**: `ignore`, `empty`, `spell`, `item`, `macro`, `mount`, `equipmentset`, or `group`.
- **Action Group**: ordered candidates; the first currently available candidate wins.

Standard groups are immutable add-on data. User custom groups and layouts live in SavedVariables.

## Safety

The applier refuses to run while in combat lockdown or while the cursor is holding something. Unresolved assignments default to `keep`, which leaves the existing slot untouched and prints a warning.

## Verification Notes

This folder is an MVP skeleton and should be verified in the current Retail client. In particular:

- The `.toc` interface version should be updated if the live client expects a newer value.
- Action slot range is currently conservative at 1-120.
- Standard group spell IDs need a Retail pass before release.
- Warlock interrupt and Death Knight mounted movement candidates need current-client verification.
