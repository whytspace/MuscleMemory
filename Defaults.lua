local ADDON_NAME, MM = ...

MM.SCHEMA_VERSION = 1

-- Structural defaults: containers and settings merged on every load so they
-- always exist. Deliberately omits starter content (the Core muscle, the
-- Default profile) so deleting those sticks instead of being re-seeded.
MM.defaults = {
  schemaVersion = MM.SCHEMA_VERSION,
  fallback = "keep",
  profile = "Default",
  profiles = {},
  muscles = {},
  customMemories = {},
  characterState = {},
}

-- Starter content copied once into a brand-new DB.
MM.seed = {
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
}
