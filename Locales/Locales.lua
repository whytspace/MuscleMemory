local ADDON_NAME, MM = ...

-- get the locale of the client
MM.locale = GetLocale()
-- MM.locale = "deDE" -- for testing

-- Locale tables register themselves here; English needs none (keys are the strings).
MM.Locales = {}

-- Never swapped, so a file-scope `local L = MM.L` stays valid. Never call L[]
-- at file scope.
MM.L = setmetatable({}, {
  __index = function(_, key)
    local locale = MM.Locales[MM.locale]
    local value = locale and locale[key]
    if value ~= nil then
      return value
    end
    return key
  end,
})
