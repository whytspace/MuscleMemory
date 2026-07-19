# Changelog

All notable player-facing changes are recorded here.

## Unreleased

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
