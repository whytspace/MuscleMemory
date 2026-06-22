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

-- Test files run under Busted, which injects describe/it/assert/spy/etc.
files["spec"] = {
  std = "lua51+busted"
}

globals = {
  "MuscleMemoryDB",
  "SLASH_MUSCLEMEMORY1",
  "SLASH_MUSCLEMEMORY2",
  "SlashCmdList",
  "StaticPopupDialogs"
}

read_globals = {
  "ADDON_LOADED",
  "C_AddOns",
  "C_EquipmentSet",
  "C_Item",
  "C_MountJournal",
  "C_Spell",
  "C_SpellBook",
  "CANCEL",
  "ClearCursor",
  "CreateFrame",
  "CreateScrollBoxLinearView",
  "DELETE",
  "DONE",
  "Enum",
  "MenuUtil",
  "ScrollUtil",
  "UISpecialFrames",
  "tinsert",
  "GameFontDisableSmall",
  "GameFontHighlight",
  "GameFontNormalLarge",
  "GameFontNormalSmall",
  "GameTooltip",
  "GetActionInfo",
  "GetActionText",
  "GetActionTexture",
  "GetCursorInfo",
  "GetItemInfo",
  "GetItemCount",
  "GetMacroInfo",
  "GetNumMacros",
  "GetNumSpecializations",
  "GetNumShapeshiftForms",
  "GetRealmName",
  "GetSpecialization",
  "GetSpecializationInfo",
  "GetSpecializationRole",
  "GetSpellInfo",
  "HasAction",
  "InCombatLockdown",
  "IsEquippedItem",
  "IsPlayerSpell",
  "IsSpellKnown",
  "MAX_ACCOUNT_MACROS",
  "PickupAction",
  "PickupItem",
  "PickupMacro",
  "PickupSpell",
  "PlaceAction",
  "StaticPopup_Show",
  "UIParent",
  "UnitClass",
  "UnitFactionGroup",
  "UnitLevel",
  "UnitName",
  "UnitRace",
  "print",
  "time"
}
