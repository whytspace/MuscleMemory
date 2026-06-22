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

- **Profile** — chooses which layers are active (and in what order) for the current character,
  plus its auto-apply triggers. A profile is a lightweight selection over layers; the slot
  content lives in the layers.
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

The applier refuses to run during combat lockdown or while the cursor is holding something.
Unresolved assignments fall back to `keep`, which leaves the existing slot untouched and prints a
warning. The fallback can be overridden per slot, group, layer, or globally.

## Verification notes

This is an MVP skeleton and should be verified against the current Retail client:

- The `.toc` interface version should track the live client.
- Action-slot range is conservatively 1–120.
- Standard group spell IDs need a Retail pass before release.
- Warlock interrupt and Death Knight mounted-movement candidates need current-client verification.
