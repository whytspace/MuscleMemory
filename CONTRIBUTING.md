# Contributing

## Setup

Use the dev container for all project tools:

```sh
devc up
devc luacheck .
devc stylua .
devc busted
devc lua scripts/check-locales.lua
```

Run the checks before committing.

`check-locales.lua` compares every `Locales/*.lua` table against the strings the add-on actually uses, reporting keys that are missing (untranslated — harmless, they fall back to English), redundant (the source string is gone) or whose `%s`/`%d` markers don't match the key. It exits non-zero for the latter two. Pass `--strict` to fail on untranslated keys too.

To load edits in WoW, symlink the repo into the AddOns folder:

```sh
git config core.fileMode false
ln -s "$PWD" "/Applications/Games/World of Warcraft/_retail_/Interface/AddOns/MuscleMemory"
```

The Git setting is local to this clone and prevents WoW's permission updates from appearing as executable-bit changes.

## Changelog

Update `CHANGELOG.md` for player-facing changes. Skip internal cleanup, tests, formatting, and development chores.

Keep entries short and player-focused, in one flat list. Start each with **[New]**, **[Change]**, or **[Fix]**, ordered New, Change, Fix.

```md
- **[New]** See slots bound by other layers.
- **[Change]** Macros now work across characters.
- **[Fix]** Mounts no longer reapply at login.
```

## Project rules

- Support current retail WoW only.
- Expose capabilities through the public API rather than slash commands. `/mm` stays a deliberately tiny set: open, `preview`, `apply`, `debug` (plus the undocumented maintainer tool `/mm shot`).
- Keep decisions DRY: when several paths answer the same question, extract one shared function all of them consume instead of parallel near-copies (e.g. `Applier:ClassifyEntry` drives preview, apply, and `api.preview`).
- Use `WowScrollBox`, `MinimalScrollBar`, `MenuUtil`, and `TabSystem`. Avoid legacy UI systems.
- Verify UI and command changes in-game with `/reload`.

## Public API

`API.lua` exposes the global `MuscleMemory` (versioned with `apiVersion`) and is the developer-facing reference: conventions and data shapes in the header, one signature comment per function. Behavior contract: invalid inputs are rejected with a reason, and returned tables are snapshots — editing them changes nothing. Slash commands adapt onto the API. Published signatures are a compatibility contract; breaking them needs a release note.

## Tests

Tests use Busted and a fake WoW API:

```sh
devc busted
devc busted --coverage
```

Use `spec/helpers/addon.lua` for a clean add-on and database. Use `spec/helpers/wow_stubs.lua` to control spells, items, mounts, macros, slots, and the cursor.

```lua
local addon = require("spec.helpers.addon")
local MM, stubs = addon.fresh()
stubs:setSpell(1766, { name = "Kick", known = true })
```

Pure logic and WoW API boundaries need unit tests. Test real frames and command wiring in-game.

## Assets

WoW textures must be uncompressed, power-of-two, 32-bit RGBA TGA files. Keep source PNGs in `Assets/`.

```sh
scripts/build-textures.sh
scripts/build-textures.sh 512
```

This needs ImageMagick. Reference textures without the extension.

Process README screenshots with:

```sh
scripts/process-shots.sh
scripts/process-shots.sh layers
```

Outputs go to `docs/images/`. ImageMagick is required. `pngquant` and `oxipng` are optional.

## Releases

Start from a clean `main` branch:

```sh
scripts/release.sh patch
scripts/release.sh minor
scripts/release.sh major
```

The script updates the version and changelog, runs checks, commits, and tags. It does not push.

```sh
git push origin main
git push origin vX.Y.Z
```

Pushing the tag builds the zip and publishes the GitHub release. CurseForge also needs its project ID in `MuscleMemory.toc` and the `CF_API_TOKEN` repository secret.
