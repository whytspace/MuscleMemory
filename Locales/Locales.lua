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

-- Which plural form a count takes. A locale that needs more than the English
-- two defines its own `plural` (ruRU: one/few/many, frFR: 0 counts as one).
local function defaultPlural(n)
  return n == 1 and "one" or "other"
end

-- Pluralized text: L:Plural(n, "%d slot", "%d slots"). A locale translates it
-- under the singular key with the form appended — "%d slot#one", "#other",
-- "#few", … — and untranslated falls back to the two English forms.
function MM.L:Plural(n, singular, plural)
  local locale = MM.Locales[MM.locale]
  local form = ((locale and locale.plural) or defaultPlural)(n)
  local text = (locale and locale[singular .. "#" .. form]) or (form == "one" and singular) or plural or singular
  return string.format(text, n)
end
