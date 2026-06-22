local ADDON_NAME, MM = ...

MM.defaults = {
  globalFallback = "keep",
  activeProfile = "Default",
  profiles = {
    Default = {
      name = "Default",
      activeLayouts = {
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
  layouts = {
    Core = {
      name = "Core",
      slots = {},
    },
  },
  customGroups = {},
  characterState = {},
  ui = {
    selectedLayout = "Core",
    selectedGroupSource = "standard",
    selectedGroupId = "interrupt",
  },
}
