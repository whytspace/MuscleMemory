local ADDON_NAME, MM = ...

MM.SCHEMA_VERSION = 3

-- Structural defaults: containers merged on every load so they always exist.
-- Deliberately omits starter content (the Core layer, the Default profile) so
-- deleting those sticks instead of being re-seeded. Layers, dynamic actions and
-- the fallback setting now live inside each profile (schema v2+).
MM.defaults = {
  schemaVersion = MM.SCHEMA_VERSION,
  profile = "Default",
  profiles = {},
  characterState = {},
}

-- Starter content copied once into a brand-new DB. A profile is a complete,
-- self-contained data set: its own layers, dynamicActions and fallback.
MM.seed = {
  profiles = {
    Default = {
      name = "Default",
      fallback = "keep",
      response = "popup",
      layerOrder = { "Core" },
      layers = {
        Core = {
          name = "Core",
          slots = {},
          enabled = true,
        },
      },
      dynamicActions = {},
    },
  },
}
