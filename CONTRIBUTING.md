# Contributing

## Development container

This repository includes a devcontainer with Lua 5.1, LuaRocks, Luacheck, StyLua, and the Lua
language server. All tooling runs through `devc`:

```sh
devc up
devc luacheck .
devc stylua .
devc lua-language-server --version
```

WoW embeds a Lua 5.1-family runtime with Blizzard-specific globals, so Luacheck is configured
through `.luacheckrc` rather than as a plain Lua application. Run `devc luacheck .` and
`devc stylua .` before committing — both should be clean.

## Data model

- **Profile** — an ordered selection of which layers are active. A profile is a lightweight
  selection over layers; the slot content lives in the layers. Profiles are account-wide; each
  character either inherits the account-default profile or picks its own (`/mm profile select`),
  stored under `characterState`.
- **Layer** — maps action-bar slots to assignments. Global and reusable across profiles. The
  active layers are stacked in order, and for each slot the first layer that assigns it wins —
  hence "layer".
- **Assignment** — one of `ignore`, `empty`, `spell`, `item`, `macro`, `mount`, `equipmentset`,
  or `group`.
- **Action Group** — an ordered list of candidates; the first one the current character can use
  wins (e.g. the Interrupt group resolves to Kick, Pummel, Counterspell, … per class).

Standard groups are immutable add-on data. Custom groups and layers live in SavedVariables
(`MuscleMemoryDB`).

## Applying

The applier refuses to run during combat lockdown or while the cursor is holding something. When a
managed slot can't resolve an assignment, the global `fallback` setting (`keep` or `clear`, set via
`/mm config fallback`) decides whether to leave the existing action or clear the slot.

A few events (spec change, spells changed, leaving combat) re-evaluate the active profile. If
applying it would change a slot, `Events` raises a popup offering to apply — nothing is stored or
auto-applied; "pending" is just computed live from the current bars.

## Verification notes

This is an MVP skeleton and should be verified against the current Retail client:

- The `.toc` interface version should track the live client.
- Action-slot range is conservatively 1–120.
- Standard group spell IDs need a Retail pass before release.
- Warlock interrupt and Death Knight mounted-movement candidates need current-client verification.
