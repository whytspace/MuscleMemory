local ADDON_NAME, MM = ...
local S = MM.SpellIds
local I = MM.ItemIds

local function Spell(spellId)
  return {
    type = "spell",
    id = spellId,
  }
end

local function ClassSpell(spellId, classes)
  local spell = Spell(spellId)
  spell.conditions = { classes = classes }
  return spell
end

-- Required profession (e.g. engineering) and minimum level are enforced by the
-- resolver's IsUsable check. A maximum usable level has no WoW API and isn't
-- reliably in the tooltip, so items with a level cap pass it here as a levelMax
-- condition (e.g. { levelMax = 60 }).
local function Item(itemId, conditions)
  return {
    type = "item",
    id = itemId,
    conditions = conditions,
  }
end

MM.PredefinedDynamicActions = {
  lust = {
    name = "Bloodlust",
    candidates = {
      Spell(S.BLOODLUST),
      Spell(S.HEROISM),
      Spell(S.TIME_WARP),
      Spell(S.FURY_OF_THE_ASPECTS),
      ClassSpell(S.COMMAND_PET, { "HUNTER" }),
      -- Drums let any class trigger Bloodlust when it has no spell of its own.
      -- Listed last so a class lust always wins; ordered low level -> high level.
      Item(I.DRUMS_OF_FURY),
      Item(I.DRUMS_OF_THE_MOUNTAIN),
      Item(I.DRUMS_OF_THE_MAELSTROM),
      Item(I.DRUMS_OF_DEATHLY_FEROCITY),
      Item(I.FERAL_HIDE_DRUMS),
      Item(I.VOID_TOUCHED_DRUMS),
    },
  },
  interrupt = {
    name = "Interrupt",
    -- Shipped as a macro so the interrupt fires at your focus target (falling back
    -- to your current target via the empty conditional), while still resolving to
    -- each class's own ability.
    mode = "macro",
    macroTemplate = "#showtooltip\n/use [@focus,harm][] %name%",
    candidates = {
      Spell(S.SOLAR_BEAM),
      Spell(S.SKULL_BASH),
      Spell(S.KICK),
      Spell(S.COUNTERSPELL),
      Spell(S.PUMMEL),
      Spell(S.REBUKE),
      Spell(S.WIND_SHEAR),
      Spell(S.MIND_FREEZE),
      Spell(S.DISRUPT),
      Spell(S.QUELL),
      Spell(S.COUNTER_SHOT),
      Spell(S.MUZZLE),
      Spell(S.SPEAR_HAND_STRIKE),
      Spell(S.SILENCE),
      -- Base Command Demon: casts the summoned demon's ability (Spell Lock,
      -- Axe Toss, ...) and survives pet switches, like Command Pet for hunters.
      Spell(S.COMMAND_DEMON),
    },
  },
  stun = {
    name = "Stun",
    candidates = {
      Spell(S.SHOCKWAVE),
      Spell(S.STORM_BOLT),
      Spell(S.LEG_SWEEP),
      Spell(S.HAMMER_OF_JUSTICE),
      Spell(S.KIDNEY_SHOT),
      Spell(S.CHEAP_SHOT),
      Spell(S.CHAOS_NOVA),
      Spell(S.FEL_ERUPTION),
      Spell(S.MIGHTY_BASH),
      Spell(S.MAIM),
      Spell(S.INTIMIDATION),
      Spell(S.SHADOWFURY),
      Spell(S.AXE_TOSS),
      Spell(S.ASPHYXIATE),
      Spell(S.CAPACITOR_TOTEM),
      Spell(S.WAR_STOMP),
    },
  },
  hard_cc = {
    name = "Hard CC",
    candidates = {
      Spell(S.POLYMORPH),
      Spell(S.HEX),
      Spell(S.FREEZING_TRAP),
      Spell(S.REPENTANCE),
      Spell(S.PARALYSIS),
      Spell(S.IMPRISON),
      Spell(S.FEAR),
      Spell(S.BANISH),
      Spell(S.HIBERNATE),
      Spell(S.CYCLONE),
      Spell(S.SLEEP_WALK),
      Spell(S.SHACKLE_UNDEAD),
      Spell(S.SAP),
    },
  },
  soft_cc = {
    name = "Soft CC",
    candidates = {
      Spell(S.DRAGONS_BREATH),
      Spell(S.SUPERNOVA),
      Spell(S.THUNDERSTORM),
      Spell(S.BLINDING_SLEET),
      Spell(S.BLIND),
      Spell(S.GOUGE),
      Spell(S.PSYCHIC_SCREAM),
      Spell(S.INTIMIDATING_SHOUT),
      Spell(S.BLINDING_LIGHT),
      Spell(S.INCAPACITATING_ROAR),
      Spell(S.SIGIL_OF_MISERY),
      Spell(S.SCATTER_SHOT),
      Spell(S.MORTAL_COIL),
      Spell(S.HOWL_OF_TERROR),
    },
  },
  battle_rez = {
    name = "Battle Rez",
    candidates = {
      Spell(S.REBIRTH),
      Spell(S.RAISE_ALLY),
      Spell(S.SOULSTONE),
      Spell(S.INTERCESSION),
      -- Items ordered low level -> high level, and low quality -> high quality
      -- within an item.
      Item(I.UNSTABLE_TEMPORAL_TIME_SHIFTER, { levelMax = 50 }),
      Item(I.DISPOSABLE_SPECTROPHASIC_REANIMATOR, { levelMax = 60 }),
      Item(I.CONVINCINGLY_REALISTIC_JUMPER_CABLES_Q1, { levelMax = 80 }),
      Item(I.CONVINCINGLY_REALISTIC_JUMPER_CABLES_Q2, { levelMax = 80 }),
      Item(I.CONVINCINGLY_REALISTIC_JUMPER_CABLES_Q3, { levelMax = 80 }),
      Item(I.EMERGENCY_SOUL_LINK_Q1, { levelMax = 90 }),
      Item(I.EMERGENCY_SOUL_LINK_Q2, { levelMax = 90 }),
    },
  },
  taunt = {
    name = "Taunt",
    candidates = {
      Spell(S.TAUNT),
      Spell(S.GROWL),
      Spell(S.DARK_COMMAND),
      Spell(S.HAND_OF_RECKONING),
      Spell(S.PROVOKE),
      Spell(S.TORMENT),
    },
  },
  -- Racials whose spell id differs by class. A character of the wrong race (or a
  -- class combination without a variant) knows none of them and the action
  -- resolves to nothing, so no race conditions are needed.
  arcane_torrent = {
    name = "Blood Elf: Arcane Torrent",
    candidates = {
      Spell(S.ARCANE_TORRENT_WARRIOR),
      Spell(S.ARCANE_TORRENT_PALADIN),
      Spell(S.ARCANE_TORRENT_HUNTER),
      Spell(S.ARCANE_TORRENT_ROGUE),
      Spell(S.ARCANE_TORRENT_PRIEST),
      Spell(S.ARCANE_TORRENT_DEATHKNIGHT),
      Spell(S.ARCANE_TORRENT_MAGE_WARLOCK),
      Spell(S.ARCANE_TORRENT_MONK),
      Spell(S.ARCANE_TORRENT_DEMONHUNTER),
    },
  },
  blood_fury = {
    name = "Orc: Blood Fury",
    candidates = {
      Spell(S.BLOOD_FURY_ATTACK_POWER),
      Spell(S.BLOOD_FURY_SPELL_POWER),
      Spell(S.BLOOD_FURY_BOTH),
    },
  },
  gift_of_the_naaru = {
    name = "Draenei: Gift of the Naaru",
    candidates = {
      Spell(S.GIFT_OF_THE_NAARU_WARRIOR),
      Spell(S.GIFT_OF_THE_NAARU_PALADIN),
      Spell(S.GIFT_OF_THE_NAARU_HUNTER),
      Spell(S.GIFT_OF_THE_NAARU_PRIEST),
      Spell(S.GIFT_OF_THE_NAARU_DEATHKNIGHT),
      Spell(S.GIFT_OF_THE_NAARU_SHAMAN),
      Spell(S.GIFT_OF_THE_NAARU_MAGE),
      Spell(S.GIFT_OF_THE_NAARU_MONK),
    },
  },
  movement = {
    name = "Movement",
    candidates = {
      Spell(S.DEATH_CHARGE),
      Spell(S.HEROIC_LEAP),
      Spell(S.FEL_RUSH),
      Spell(S.ROLL),
      Spell(S.CHI_TORPEDO),
      Spell(S.BLINK),
      Spell(S.SHIMMER),
      Spell(S.SPRINT),
      Spell(S.DASH),
      Spell(S.DIVINE_STEED),
      Spell(S.HOVER),
      Spell(S.ASPECT_OF_THE_CHEETAH),
      Spell(S.GHOST_WOLF),
      Spell(S.BURNING_RUSH),
      Spell(S.DEATHS_ADVANCE),
      Spell(S.CHARGE),
      Spell(S.DISENGAGE),
    },
  },
}
