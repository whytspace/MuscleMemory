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

## UI conventions

Build the UI with current WoW UI systems, not their legacy equivalents — the add-on targets
current retail only. In particular: `WowScrollBox` + `MinimalScrollBar` for scrolling (not
`UIPanelScrollFrameTemplate`), `MenuUtil` context menus (not `UIDropDownMenu`), and the
`TabSystem` for tabs. When unsure, mirror a recent Blizzard panel (Communities, Settings).

## Textures and assets

The game can't load PNG/SVG at runtime — UI textures must be **TGA** (32-bit RGBA,
uncompressed, power-of-two dimensions). Keep source PNGs in `Assets/` and generate the `.tga`:

```sh
scripts/build-textures.sh        # all Assets/*.png -> .tga at 256x256
scripts/build-textures.sh 512    # override the size
```

Needs ImageMagick (`brew install imagemagick`). Reference textures by path without extension,
e.g. `Interface\AddOns\MuscleMemory\Assets\logo`.

## Testing

Unit tests run under [Busted](https://lunarmodules.github.io/busted/) in the dev container:

```sh
devc busted              # run the suite
devc busted --coverage   # also write luacov.report.out
```

The WoW client API isn't available outside the game, so `spec/helpers/wow_stubs.lua` provides a
controllable fake of it — a mutable `world` (known spells, bag contents, mounts, macros, action-bar
slots, the cursor) that every stub reads from. Pickups move things onto the cursor and `PlaceAction`
drops the cursor into a slot, so capture/apply round-trips are fully simulated.

`spec/helpers/addon.lua` loads the add-on the way WoW does: each non-UI file from the `.toc` is run
with its `("MuscleMemory", MM)` varargs inside a shared sandbox whose globals are the fake API.
A spec typically starts from `addon.fresh()`, which returns `(MM, stubs, env)` with a clean DB.

```lua
local addon = require("spec.helpers.addon")
local MM, stubs = addon.fresh()
stubs:setSpell(1766, { name = "Kick", known = true })
-- exercise MM.* and assert on the result or on stubs.world
```

What's tested and what isn't:

- **Covered:** the pure logic and API-boundary modules — `Util/*`, `Database`, `Resolver`,
  `Capture`, `Applier`, and the event-driven apply prompt in `Events`.
- **Not unit-tested:** `UI/*` (real frames) and most of `SlashCommands`/`Core` (command dispatch and
  frame wiring). Verify those in-game with `/reload`; an error display add-on such as
  BugGrabber/BugSack helps surface runtime errors.

## Data model

- **Profile** — an ordered selection of which muscles are active. A profile is a lightweight
  selection over muscles; the slot content lives in the muscles. Profiles are account-wide; each
  character either inherits the account-default profile or picks its own (`/mm profile select`),
  stored under `characterState`.
- **Muscle** — maps action-bar slots to assignments. Global and reusable across profiles. The
  active muscles are stacked in order, and for each slot the first muscle that assigns it wins —
  hence "muscle".
- **Assignment** — one of `ignore`, `empty`, `spell`, `item`, `macro`, `mount`, `equipmentset`,
  or `memory`.
- **Memory** — an ordered list of candidates; the first one the current character can use
  wins (e.g. the Interrupt memory resolves to Kick, Pummel, Counterspell, … per class).

Standard memories are immutable add-on data. Custom memories and muscles live in SavedVariables
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
- Standard memory spell IDs need a Retail pass before release.
- Warlock interrupt and Death Knight mounted-movement candidates need current-client verification.
