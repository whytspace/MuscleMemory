local ADDON_NAME, MM = ...

MM.defaults = {
  fallback = "keep",
  profile = "Default",
  profiles = {
    Default = {
      name = "Default",
      activeMuscles = {
        { id = "Core", enabled = true },
      },
    },
  },
  muscles = {
    Core = {
      name = "Core",
      slots = {},
    },
  },
  customMemories = {},
  characterState = {},
}
