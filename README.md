<p align="center">
  <img src="Assets/logo.png" alt="Muscle Memory" width="160">
</p>

# Muscle Memory

**Bind buttons by purpose, not just spell.**

Muscle Memory keeps your action bars consistent across every character. Capture your setup into
reusable **[layers](#layers-not-snapshots)**, then put the right spell, item, macro, mount, or
equipment set back into each slot on any character — with one click.

A slot can also point to a **[smart action](#smart-actions)** instead of a fixed spell. Bind a
button to *Interrupt*, *Taunt*, or *Bloodlust*, and every character gets whatever ability it actually
has for the job. One binding, every class.

> ⚠️ **Early development:** things mostly work, but bugs can occur. Please report issues on
> [GitHub](https://github.com/whytspace/MuscleMemory/issues) — attaching a debug report (About
> tab) makes them reproducible.

![Muscle Memory layers tab](https://raw.githubusercontent.com/whytspace/MuscleMemory/main/docs/images/layers.png)

## Features

- **Set up your bars once.** Snapshot your live bars into layers and apply them on any character —
  no rebuilding the same layout on every alt.
- **Slots that follow your class.** Build your own smart actions that resolve to whatever ability
  each character actually has — plus built-ins for the staples like Bloodlust, Interrupt, and Battle
  Rez.
- **Real macros when you need them.** Render a smart action as a macro for mouseover, focus,
  modifier, and conditional casts (`/use [@mouseover,help][@focus] %name%`); Muscle Memory writes and
  maintains the per-character macro for you.
- **Your macros travel with you.** A bound character macro is recreated on any character that doesn't
  have it yet, and keeps matching by name after you edit its body.
- **Suggestions while you bind.** Drop Kick onto a slot and Muscle Memory offers to bind *Interrupt*
  instead, so the slot keeps working on every character (configurable: never / suggest / automatic).
- **Everything that lives on a bar.** Spells, items, macros, mounts, toys, battle pets, flyouts, and
  equipment sets.
- **No surprises.** Preview shows what Apply would change first, and Apply is blocked in combat or
  with something on the cursor — it waits rather than half-applying.
- **Undo your slips.** Every configuration change — a deleted layer, a mis-assigned slot, a whole
  import — reverts step by step, and the window jumps to what changed.
- **Scriptable.** A public API lets macros and other add-ons drive everything in the window 😉
- **Separate setups.** Profiles keep independent configurations you can switch at once — an
  account-wide default, or a dedicated one per character.
- **Share your setup.** Export layers, smart actions, or whole profiles as a copyable string;
  imports preview what's inside and always create new entries, never overwrite yours.

## Layers, not snapshots

Most bar-saving addons store one monolithic snapshot and stamp the whole thing back down. Muscle
Memory never applies a full bar in one piece. A profile is an ordered stack of **layers**, each
owning only the slots it cares about. For every slot, Apply takes the **first** layer with something
to say — so higher layers win and lower ones fill in the rest.

That ordering makes layers composable:

- Put a specific layer **on top** — a class/spec overlay or one character's tweaks — and it overrides
  the shared layers beneath without touching them.
- Keep a **shared base layer** underneath for the buttons every character has in the same place. Edit
  it once and everyone who doesn't override that slot updates.
- Scope any layer with **conditions** so it only applies to the characters it's meant for.
- Drop **smart-action slots** into any layer, so one button resolves per character without forking
  the layer.

## Smart actions

A **smart action** is a named stand-in for an ability — *Interrupt*, *Bloodlust*, *Taunt* — rather
than a fixed spell. Behind the name is an ordered list of candidates, and each character resolves to
the **first one it can actually use**, checking class, spec, known spells, owned items, profession,
and level. One slot becomes Pummel on your Warrior, Mind Freeze on your Death Knight, and
Counterspell on your Mage.

![Muscle Memory smart actions tab](https://raw.githubusercontent.com/whytspace/MuscleMemory/main/docs/images/smart-actions.png)

Built-ins cover Bloodlust, Interrupt, Stun, Hard CC, Soft CC, Battle Rez, Taunt, Movement, and the
racials whose spell differs by class (Blood Elf: Arcane Torrent, Orc: Blood Fury, Draenei: Gift of
the Naaru) — and you can build your own:

- **Mix anything castable.** Candidates can blend spells, items, toys, and mounts — so *Bloodlust*
  resolves through each class's own version (Bloodlust, Heroism, Time Warp, Fury of the Aspects) and
  then to **War Drums** for the classes that have none. Every character brings the haste.
- **Order is priority.** Candidates are tried top to bottom, so you decide what wins.
- **Render as a macro.** Keep conditional logic (`[@focus,harm][]`, modifiers, mouseover) while
  `%name%` resolves per character. The built-in Interrupt ships this way — it hits your focus, falling
  back to your current target.

Muscle Memory writes and maintains the real per-character macro for you — edit the smart action and
the macro follows:

![Muscle Memory macro editor](https://raw.githubusercontent.com/whytspace/MuscleMemory/main/docs/images/macro-editor.png)

## Getting started

1. Type **`/mm`** to open the window.
2. Click a faded slot to capture whatever is on that action bar button.
3. Switch character, then press **Apply** (or run `/mm apply`) to restore the layer.

## Muscle Memory speaks your language

The window and its chat output follow your WoW client language. Any other locale runs in English.

- [x] English
- [x] Deutsch
- [x] Français

## Commands & API

The slash commands cover the daily essentials:

- `/mm` — open the window
- `/mm preview` — show what Apply would change, without touching your bars
- `/mm apply` — restore your bars from the active profile

Everything else — profiles, layers, smart actions, settings — is managed in the window, or
programmatically through the public API: the global `MuscleMemory` exposes it all to macros and
other add-ons (e.g. `/run MuscleMemory.layers.captureAll("healing")`). Explore it with
`/dump MuscleMemory`; [API.lua](API.lua) documents every function and the data shapes.

## Screenshots

| | |
|---|---|
| ![Layers](https://raw.githubusercontent.com/whytspace/MuscleMemory/main/docs/images/layers.png) | ![Smart actions](https://raw.githubusercontent.com/whytspace/MuscleMemory/main/docs/images/smart-actions.png) |
| ![Profiles](https://raw.githubusercontent.com/whytspace/MuscleMemory/main/docs/images/profiles.png) | ![Macro editor](https://raw.githubusercontent.com/whytspace/MuscleMemory/main/docs/images/macro-editor.png) |
| ![Rendered macro](https://raw.githubusercontent.com/whytspace/MuscleMemory/main/docs/images/macro-window.png) | ![Bind suggestion](https://raw.githubusercontent.com/whytspace/MuscleMemory/main/docs/images/suggestion.png) |

## License

Released under the [MIT License](LICENSE).
