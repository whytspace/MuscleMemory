local ADDON_NAME, MM = ...

MM.defaults = {
  fallback = "keep",
  profile = "Default",
  profiles = {
    Default = {
      name = "Default",
      activeLayers = {
        { id = "Core", enabled = true },
      },
    },
  },
  layers = {
    Core = {
      name = "Core",
      slots = {},
    },
  },
  customGroups = {},
  characterState = {},
}

-- Auto-apply behaviour. Fixed for now, read by Events; not stored or configurable.
MM.triggers = {
  mode = "prompt",
  onLogin = false,
  onSpecChanged = true,
  onSpellAvailabilityChanged = true,
  afterCombatIfPending = true,
}
