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
