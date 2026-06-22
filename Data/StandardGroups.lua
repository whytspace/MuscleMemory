local ADDON_NAME, MM = ...
local S = MM.SpellIds

local function Spell(spellId)
  return {
    type = "spell",
    id = spellId,
  }
end

local function ClassSpell(spellId, classes)
  local spell = Spell(spellId)
  spell.classes = classes
  return spell
end

MM.StandardGroups = {
  lust = {
    name = "Lust",
    candidates = {
      Spell(S.BLOODLUST),
      Spell(S.HEROISM),
      Spell(S.TIME_WARP),
      Spell(S.FURY_OF_THE_ASPECTS),
      ClassSpell(S.COMMAND_PET, { "HUNTER" }),
    },
  },
  interrupt = {
    name = "Kick / Interrupt",
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
      Spell(S.SPELL_LOCK),
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
