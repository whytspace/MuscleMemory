std = "lua51"
codes = true
max_line_length = false
ignore = {
  "211/ADDON_NAME",
  "212/self"
}

exclude_files = {
  ".devcontainer/**"
}

globals = {
  "MuscleMemoryDB",
  "SLASH_MUSCLEMEMORY1",
  "SLASH_MUSCLEMEMORY2",
  "SlashCmdList"
}

read_globals = {
  "ADDON_LOADED",
  "C_EquipmentSet",
  "C_Item",
  "C_MountJournal",
  "C_Spell",
  "C_SpellBook",
  "ClearCursor",
  "CreateFrame",
  "GameFontDisableSmall",
  "GameFontHighlight",
  "GameFontNormalLarge",
  "GameFontNormalSmall",
  "GameTooltip",
  "GetActionInfo",
  "GetCursorInfo",
  "GetItemCount",
  "GetMacroInfo",
  "GetNumMacros",
  "GetRealmName",
  "GetSpellInfo",
  "HasAction",
  "InCombatLockdown",
  "IsPlayerSpell",
  "IsSpellKnown",
  "MAX_ACCOUNT_MACROS",
  "PickupAction",
  "PickupItem",
  "PickupMacro",
  "PickupSpell",
  "PlaceAction",
  "UIParent",
  "UnitClass",
  "UnitName",
  "print",
  "time"
}
