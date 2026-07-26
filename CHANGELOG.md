# Changelog

All notable player-facing changes are recorded here.

## Unreleased

- **[New]** Muscle Memory now speaks German, the first language beyond English. The window and its chat messages follow your client language, falling back to English anywhere a translation is missing. The predefined Dynamic Action names (Interrupt, Bloodlust, Taunt, ...) deliberately stay English, since that is the shorthand players use.
- **[Change]** Class, role, faction and race names in the condition editor now come from the game itself, so they always match the wording you see elsewhere in the client.
- **[Change]** Minor design improvements: section headings are set apart by size instead of capitals, and buttons grow to fit their caption.

## 0.13.0 - 2026-07-25

- **[Change]** When the apply prompt opens, the pending changes are now also printed to chat (like `/mm preview`), so you can see what triggered it — even if the situation has resolved itself by the time you check.
- **[Change]** Editing a macro now updates its copy in your layers: renames, body and icon changes sync automatically, so applying on another character recreates the latest version — no re-capture needed.
- **[Fix]** Recreated macros keep the icon you picked: the dynamic `?` no longer freezes to whatever icon showed at capture time. Existing captures heal automatically.
- **[Fix]** A slot holding the Single Button Assistant is no longer mistaken for the ability it currently recommends: preview, apply and chat messages now treat it as the assistant.
- **[Fix]** Preview and apply report unavailable actions consistently ("Fetch is not available"); they no longer count as failed.
- **[Fix]** Apply no longer reports a phantom "empty → empty" update.

## 0.12.0 - 2026-07-25

- **[New]** The slash commands have been replaced by a public API: everything they did (and more, like creating Dynamic Actions) is now available to macros and other add-ons through the global `MuscleMemory`. For example:
  - `/run MuscleMemory.profiles.setCharacter("raid")` — switch this character to a profile
  - `/run MuscleMemory.layers.captureAll("healing")` — capture your current bars into a layer
  - `/run MuscleMemory.actions.create("Defensives")` — create a Dynamic Action, previously UI-only
- **[New]** Accidental changes are no longer final: Undo and Redo revert configuration edits step by step — a deleted layer, a mis-assigned slot or a whole import comes back with one click, and the window jumps to what changed so you can see it. Your live action bars are never touched by an undo; only Apply changes those.
- **[Change]** `/mm` is trimmed to the essentials: open the window, `preview`, `apply` and `debug`. Everything else is managed in the window or through the new API.

## 0.11.0 - 2026-07-24

- **[New]** New Dynamic Actions can be created directly from a slot's regular action.
- **[New]** Export and import columns have an invert-selection button that flips every checkbox at once.
- **[Fix]** Slots that fail to apply (e.g. all macro slots are full) are now warned about visibly instead of only with `/mm debug`, and the apply summary reports the failed count.

## 0.10.0 - 2026-07-24

- **[Fix]** Spells renamed by a spec or talent (e.g. Evoker's Chrono Flames replacing Living Flame) now capture and resolve as their base spell, so they no longer show as "no match" in Dynamic Actions. Already-saved candidates work without re-adding them.
- **[Fix]** Restoring a macro with no chosen icon keeps its dynamic `#showtooltip` icon instead of freezing the icon that happened to show when it was captured. Macros captured before this fix need re-capturing to benefit.
- **[Fix]** Usable items you're out of are restored greyed instead of falling back to a lower layer, and unlearned toys are no longer placed.
- **[Fix]** The apply prompt no longer keeps reappearing for changes that can't be applied.
- **[Change]** Improved `/mm preview` and `/mm apply` output: each changed slot is listed; enable `/mm debug` for the rest.

## 0.9.0 - 2026-07-19

- **[New]** Transmog outfits on action bars are now captured and restored.
- **[Change]** Export and import are now their own tabs, previewing Layers, Dynamic Actions, and macros side by side.
- **[Fix]** Capturing an equipment set from an action bar slot works again.

## 0.8.0 - 2026-07-19

- **[New]** Share your setup: export layers, dynamic actions, or whole profiles as a copyable string, and import shared strings into the current or a new profile (`/mm export`, `/mm import`). Imports always create new entries and are tagged until the next reload.

## 0.7.0 - 2026-07-19

- **[Change]** Slot editor bind list is split into personal and predefined sections.
- **[Fix]** Warlock Interrupt now uses Command Demon, so it works with any summoned demon.
- **[Fix]** Capturing a generated macro now suggests its Dynamic Action.
- **[Fix]** Grid no longer overlaps the legend for classes with many action bars (e.g. Paladin, Druid).

## 0.6.1 - 2026-07-12

- **[Fix]** Added missing `/mm config suggest` command.

## 0.6.0 - 2026-07-12

- **[New]** Macros now restore across characters.
- **[New]** Missing macros are recreated when applied.
- **[New]** See slots bound by other enabled layers.
- **[New]** Candidate lists now show spell and item IDs.
- **[New]** Binding can suggest the matching Dynamic Action.
- **[New]** Added Dynamic Actions for class-specific racial spells.
- **[Change]** User macro slots now show the macro badge.
- **[Change]** Grid legend is shorter and easier to scan.
- **[Change]** Changed macros now resolve by name.
- **[Change]** Capture existing macro slots again once.
- **[Change]** Spec choices now follow the selected classes.
- **[Change]** Dynamic Actions are split into personal and predefined lists.
- **[Fix]** Grid legend now renders again.
- **[Fix]** Debug hint now explains how to list unresolved slots.
- **[Fix]** Toys now restore from the Toy Box.
- **[Fix]** Mounts no longer reapply on every login.

## 0.5.1 - 2026-06-26

- **[Fix]** Missing predefined actions no longer crash apply.
- **[Fix]** Generated macros keep longer Dynamic Action names.
- **[Fix]** CurseForge now shows only the current release notes.

## 0.5.0 - 2026-06-26

- **[New]** Bloodlust now falls back to drums.
- **[New]** Slot editor tooltips now identify Dynamic Actions and macros.
- **[Change]** Lust is now called Bloodlust.
- **[Change]** Slot editor is simpler and easier to scan.

## 0.4.1 - 2026-06-26

- **[Change]** Apply prompts now use Apply and Cancel.
- **[Fix]** Closing an apply prompt no longer applies changes.

## 0.4.0 - 2026-06-26

- **[New]** Added icons and badges across the UI.
- **[Change]** Muscles are now called action bar layers.
- **[Change]** Memories are now called Dynamic Actions.
- **[Change]** Existing setups migrate automatically.
- **[Fix]** Leaving combat no longer triggers a change scan.

## 0.3.0 - 2026-06-25

- **[New]** Dynamic Actions can now use macros.
- **[New]** Added a focus-target macro for Interrupt.
- **[New]** Added a predefined Battle Rez Dynamic Action.
- **[New]** Crafted items now show their quality.
- **[New]** Tooltips now show resolved actions.
- **[New]** Choose what happens when changes are detected.
- **[Change]** Item actions now ignore unusable items.
- **[Fix]** Unavailable slots no longer trigger login prompts.

## 0.2.0 - 2026-06-24

- **[New]** Clone an existing profile to copy it.
- **[New]** Set a default profile and character overrides.
- **[New]** Preview or apply when switching profiles.
- **[Change]** Profiles now contain the full setup.
- **[Change]** New profiles now start empty.
- **[Change]** Profile selection moved into its own tab.
- **[Change]** Standard Dynamic Actions are now called predefined.

## 0.1.4 - 2026-06-23

- **[New]** Muscle Memory is now on CurseForge.

## 0.1.3 - 2026-06-23

- **[New]** Capture and restore the Single Button Assistant.

## 0.1.2 - 2026-06-23

- **[New]** Added the logo to WoW's add-ons list.
- **[Fix]** Placeholder spells no longer reapply continuously.

## 0.1.1 - 2026-06-23

- **[New]** Released under the MIT License.

## 0.1.0 - 2026-06-23

- **[New]** First public release.
- **[New]** Capture and apply action bars across characters.
- **[New]** Resolve purpose-based actions for each character.
- **[New]** Manage profiles, layers, actions, and conditions.
