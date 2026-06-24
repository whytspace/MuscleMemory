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

## Changelog

Update `CHANGELOG.md` in the same commit when a change is relevant to players, release notes, or
addon-manager metadata. Pure internal cleanup, tests, formatting, and development-only chores can
skip it.

## Releases

Cut releases from a clean `main` branch:

```sh
scripts/release.sh patch    # X.Y.Z -> X.Y.(Z+1)
scripts/release.sh minor    # X.Y.Z -> X.(Y+1).0
scripts/release.sh major    # X.Y.Z -> (X+1).0.0
```

The script updates `MuscleMemory.toc`, moves the `CHANGELOG.md` Unreleased notes under the release
date, runs the release checks, creates a `chore: release vX.Y.Z` commit, and creates an annotated
tag. It does not push. Publish the release with:

```sh
git push origin main
git push origin vX.Y.Z
```

Pushing the tag runs the packaging workflow. The workflow uses BigWigsMods/packager, `.pkgmeta`,
and `CHANGELOG.md` to build the zip and publish a GitHub release. After the CurseForge project
exists, add its project ID to `MuscleMemory.toc` and set the `CF_API_TOKEN` repository secret to
upload there from the same workflow.

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

- **Profile** — a complete, self-contained data set: its own muscles, memories, and `fallback`
  setting. Switching profiles swaps the whole set. The profile list is account-wide; `root.profile`
  is the global default and each character may override it with its own choice (the Profiles tab or
  `/mm profile select`), stored under `characterState`. `/mm profile default` sets the global default.
- **Muscle** — maps action-bar slots to assignments; belongs to a profile (not shared between them).
  A profile's `muscleOrder` stacks its muscles, and for each slot the first enabled muscle that
  assigns it wins — hence "muscle". Each muscle carries its own `enabled` flag.
- **Assignment** — one of `ignore`, `empty`, `spell`, `item`, `macro`, `mount`, `equipmentset`,
  or `memory`.
- **Memory** — an ordered list of candidates; the first one the current character can use
  wins (e.g. the Interrupt memory resolves to Kick, Pummel, Counterspell, … per class).

Predefined memories are immutable add-on data. A profile's muscles, memories and fallback live in
SavedVariables (`MuscleMemoryDB`) under that profile.

## Applying

The applier refuses to run during combat lockdown or while the cursor is holding something. When a
managed slot can't resolve an assignment, the active profile's `fallback` setting (`keep` or `clear`,
set via `/mm config fallback`) decides whether to leave the existing action or clear the slot.

A few events (spec change, spells changed, leaving combat) — and switching the active profile —
re-evaluate it. If applying it would change a slot, `Events` raises a popup offering to apply —
nothing is stored or auto-applied; "pending" is just computed live from the current bars.
