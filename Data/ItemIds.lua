local ADDON_NAME, MM = ...

MM.ItemIds = {
  -- Battle Rez (engineering). Only items castable in combat belong here; the
  -- out-of-combat "defibrillate" tools (Goblin Jumper Cables, Gnomish Army
  -- Knives) are deliberately excluded. Profession and minimum level are enforced
  -- at resolve time by Items.IsUsable; the maximum usable level has no API and is
  -- passed as a levelMax condition (see PredefinedSmartActions).
  --
  -- Crafted items (Dragonflight onward) have a separate id per quality tier, so
  -- every tier is listed and whichever the player owns is matched. Ordered low
  -- level -> high level.
  UNSTABLE_TEMPORAL_TIME_SHIFTER = 158379, -- Battle for Azeroth, cap 50
  DISPOSABLE_SPECTROPHASIC_REANIMATOR = 184308, -- Shadowlands, cap 60
  CONVINCINGLY_REALISTIC_JUMPER_CABLES_Q1 = 221953, -- The War Within, cap 80
  CONVINCINGLY_REALISTIC_JUMPER_CABLES_Q2 = 221954,
  CONVINCINGLY_REALISTIC_JUMPER_CABLES_Q3 = 221955,
  EMERGENCY_SOUL_LINK_Q1 = 248486, -- Midnight, cap 90 (only two quality tiers)
  EMERGENCY_SOUL_LINK_Q2 = 269586,

  -- Lust drums (leatherworking). Each gives a Bloodlust-equivalent haste burst and
  -- the shared Exhaustion/Sated debuff, so any class can trigger Bloodlust by carrying
  -- them. No level cap (older drums still fire at max level); whichever the player
  -- owns is matched. Ordered low level -> high level. Quality-tier siblings for the
  -- crafted drums (Dragonflight onward) still need their ids confirmed in-game.
  DRUMS_OF_FURY = 120257, -- Warlords of Draenor
  DRUMS_OF_THE_MOUNTAIN = 142406, -- Legion
  DRUMS_OF_THE_MAELSTROM = 154167, -- Battle for Azeroth
  DRUMS_OF_DEATHLY_FEROCITY = 172233, -- Shadowlands
  FERAL_HIDE_DRUMS = 193470, -- Dragonflight
  VOID_TOUCHED_DRUMS = 244639, -- Midnight
}
