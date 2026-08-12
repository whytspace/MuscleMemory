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

Update `CHANGELOG.md` for player-facing changes. Skip internal cleanup, tests, formatting, and development chores. Fold cosmetic layout tweaks into a single trailing "minor design improvements" entry.

Keep entries short and to the point — one or two sentences per entry, describing the visible behavior change, not the mechanism behind it. One flat list; start each entry with **[New]**, **[Change]**, or **[Fix]**, ordered New, Change, Fix. Phrase **[Fix]** entries as the misbehavior that stopped ("…no longer…"), not as present-tense descriptions of the corrected behavior.

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

## Adding a language

A language is a file plus a `.toc` line — no code changes.

1. Create `Locales/frFR.lua`, gating on the client language so only the matching one is ever loaded:

   ```lua
   local ADDON_NAME, MM = ...

   if MM.locale ~= "frFR" then
     return
   end

   MM.Locales.frFR = {
     ["no changes"] = "aucun changement",
   }
   ```

2. List it in `MuscleMemory.toc` beside the other locale files. Optionally add a `## Notes-frFR:` line for the add-on list.

3. Fill the table. Keys are the English strings **byte for byte**, including `—`, `·` and `…`; anything missing falls back to English, so a partial file ships fine. Format markers (`%s`, `%d`) must survive in the same number, though they may be reordered.

4. Add a `plural` rule only if the language needs more than the English one/other split. Count-dependent text goes through `L:Plural(n, "%d slot", "%d slots")` and is translated under the singular key with the form appended:

   ```lua
   plural = function(n)
     if n % 10 == 1 and n % 100 ~= 11 then
       return "one"
     end
     return "other"
   end,
   ["%d slot#one"] = "%d слот",
   ["%d slot#other"] = "%d слотов",
   ```

5. Run `devc lua scripts/check-locales.lua`, which reports missing, redundant and mismatched-format keys.

6. Tick the language off in the README list.

Not translated, deliberately: class, spec, role, faction and race names (read from the client), the predefined Smart Action names (raid shorthand), macro syntax, debug output, and `API.lua` / `Util/Validate.lua`, which are developer-facing.

Translations are maintainer-written. Don't enable CurseForge's localization system, and keep player-facing copy (CHANGELOG, README) free of anything that reads as an invitation to submit translations — state which languages ship, nothing more.

To preview a translation on a client of another language, swap the two lines at the top of `Locales/Locales.lua` and `/reload`. Restore them before releasing — `scripts/check-locales.lua --release` fails if you forget.

## Public API

`API.lua` exposes the global `MuscleMemory` (versioned with `apiVersion`) and is the developer-facing reference: conventions and data shapes in the header, one signature comment per function. Behavior contract: invalid inputs are rejected with a reason, and returned tables are snapshots — editing them changes nothing. Slash commands adapt onto the API. Published signatures are a compatibility contract; breaking them needs a release note. Share strings (`Share.lua`) deliberately stay out of the API until a concrete consumer appears.

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

### Debug reports

`!MMDBG:1!` strings (About tab, or `MuscleMemory.debug.report()`) capture live client state next to the profile. Decode with `devc lua scripts/dump-report.lua <file>`. `require("spec.helpers.report").load(text)` returns a hydrated `MM` whose captured client answers replay verbatim, so a client-specific bug becomes an offline regression test against `Applier:BuildPlan()`.

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

Before cutting: new screenshot-tour views need `process-shots.sh`'s `views` list (order-sensitive), the `/mm shot view` usage string, and the README gallery updated together; and diff features since the last tag — README bullets go stale silently. Never hand-take README screenshots; the tour produces them.
