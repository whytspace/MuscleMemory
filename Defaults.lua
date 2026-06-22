local ADDON_NAME, MM = ...

MM.defaults = {
  globalFallback = "keep",
  activeProfile = "Default",
  profiles = {
    Default = {
      name = "Default",
      activeLayers = {
        Core = {
          enabled = true,
          order = 1,
        },
      },
      triggers = {
        mode = "prompt",
        onLogin = false,
        onSpecChanged = true,
        onSpellAvailabilityChanged = true,
        afterCombatIfPending = true,
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
  ui = {
    selectedLayer = "Core",
    selectedGroupSource = "standard",
    selectedGroupId = "interrupt",
  },
}
