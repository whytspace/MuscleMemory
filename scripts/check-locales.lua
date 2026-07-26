-- Check the locale tables against the strings the add-on uses. Reports keys that
-- are missing (harmless, they fall back), redundant (source string gone) or whose
-- format markers don't match. --strict also fails on missing.

-- Works whether invoked by absolute path or from the repo root.
local root = (debug.getinfo(1, "S").source:sub(2)):match("^(.*)/scripts/[^/]*$") or "."

local function readFile(path)
  local handle = assert(io.open(path, "r"))
  local text = handle:read("*a")
  handle:close()
  return text
end

-- Source files to scan, from the .toc (Libs and the locale tables themselves excluded).
local function sourceFiles()
  local files = {}
  for line in readFile(root .. "/MuscleMemory.toc"):gmatch("[^\r\n]+") do
    line = line:gsub("%s+$", "")
    if line:match("%.lua$") and not line:match("^Libs/") and not line:match("^Locales/") then
      files[#files + 1] = line
    end
  end
  return files
end

local function localeFiles()
  local files = {}
  local pipe = io.popen("ls " .. root .. "/Locales/*.lua 2>/dev/null")
  for path in pipe:lines() do
    if not path:match("/Locales%.lua$") then
      files[#files + 1] = path
    end
  end
  pipe:close()
  return files
end

-- Set MM.locale per file, or its gate returns before registering the table.
local function loadLocales()
  local locales = {}
  for _, path in ipairs(localeFiles()) do
    local code = path:match("([^/]+)%.lua$")
    local MM = { Locales = {}, locale = code }
    local chunk = assert(loadfile(path))
    setfenv(chunk, setmetatable({}, { __index = _G }))
    chunk("MuscleMemory", MM)
    locales[code] = MM.Locales[code]
    if not locales[code] then
      error(string.format("%s registered no table for '%s' — check its MM.locale gate", path, code))
    end
  end
  return locales
end

-- A forced locale must never ship, but only a release should fail over it —
-- otherwise the checks are unusable while testing a translation.
local function checkForcedLocale(isRelease)
  local source = readFile(root .. "/Locales/Locales.lua")
  local forced = source:match('\n%s*MM%.locale%s*=%s*"([%a]+)"')
  if not forced then
    return
  end
  io.stderr:write(string.format("Locales/Locales.lua forces MM.locale = %q; restore GetLocale()\n", forced))
  if isRelease then
    os.exit(1)
  end
end

-- Resolve a quoted Lua literal to its real bytes, so "\226\128\148" and "—" compare equal.
local function unquote(quote, body)
  local chunk = loadstring("return " .. quote .. body .. quote)
  if not chunk then
    return nil
  end
  local ok, value = pcall(chunk)
  return ok and value or nil
end

-- Deliberately English surfaces; scanning them would just add noise.
local NOT_TRANSLATED = {
  ["API.lua"] = true,
  ["Util/Validate.lua"] = true,
  ["UI/Screenshot.lua"] = true,
  ["UI/ScreenshotTour.lua"] = true,
}

-- Hidden /mm commands are maintainer tools and stay English.
local IGNORE = {
  ["capture transparent marketing screenshots (maintainer tool)"] = true,
  ["build a showcase profile and capture every view"] = true,
  ["capture a single view"] = true,
}

-- Literal L["…"] keys, plus reasons and labels that reach L through a variable.
local function usedKeys()
  local keys = {}
  -- A trailing space or quote means a concatenation prefix, never a whole key.
  local function add(value)
    if type(value) ~= "string" or #value < 2 or IGNORE[value] then
      return
    end
    if value:match("[%s'\"]$") then
      return
    end
    keys[value] = true
  end

  for _, file in ipairs(sourceFiles()) do
    local src = NOT_TRANSLATED[file] and "" or readFile(root .. "/" .. file)

    for quote, body in src:gmatch("%f[%a]L%[%s*([\"'])(.-)%1%s*%]") do
      add(unquote(quote, body))
    end

    for call in src:gmatch("L:Plural%b()") do
      local quote, body = call:match("([\"'])(.-)%1")
      if quote then
        add(unquote(quote, body))
      end
    end

    for quote, body in src:gmatch("return%s+nil%s*,%s*([\"'])(.-)%1") do
      add(unquote(quote, body))
    end
    for quote, body in src:gmatch("return%s+false%s*,%s*([\"'])(.-)%1") do
      add(unquote(quote, body))
    end

    -- Anchored: PredefinedSmartActions.lua also ends in "Actions.lua".
    if file == "Util/Actions.lua" or file == "SlashCommands.lua" then
      for field, quote, body in src:gmatch("(%w+)%s*=%s*([\"'])(.-)%2") do
        if field == "label" or field == "name" or field == "desc" then
          add(unquote(quote, body))
        end
      end
    end
  end

  return keys
end

local ESCAPES = { n = "\n", r = "\r", t = "\t", ['"'] = '"', ["'"] = "'", ["\\"] = "\\" }

-- Resolve Lua escapes across a whole file so "\226\128\148" compares equal to "—".
local function decodeEscapes(text)
  local out, index, length = {}, 1, #text
  while index <= length do
    local char = text:sub(index, index)
    if char == "\\" then
      local digits = text:match("^(%d%d?%d?)", index + 1)
      if digits then
        out[#out + 1] = string.char(tonumber(digits) % 256)
        index = index + 1 + #digits
      else
        local following = text:sub(index + 1, index + 1)
        out[#out + 1] = ESCAPES[following] or following
        index = index + 2
      end
    else
      out[#out + 1] = char
      index = index + 1
    end
  end
  return table.concat(out)
end

-- All source as one decoded blob; indirect keys still appear verbatim in it.
local function sourceCorpus()
  local parts = {}
  for _, file in ipairs(sourceFiles()) do
    parts[#parts + 1] = decodeEscapes(readFile(root .. "/" .. file))
  end
  return table.concat(parts, "\n")
end

local function formatMarkers(text)
  local markers = {}
  for marker in text:gmatch("%%[%-%d%.]*([%a%%])") do
    if marker ~= "%" then
      markers[#markers + 1] = marker
    end
  end
  table.sort(markers)
  return table.concat(markers, ",")
end

local strict, isRelease = false, false
for _, option in ipairs({ ... }) do
  if option == "--strict" then
    strict = true
  elseif option == "--release" then
    isRelease = true
  end
end

checkForcedLocale(isRelease)

local locales = loadLocales()
local used = usedKeys()
local corpus = sourceCorpus()

local usedCount = 0
for _ in pairs(used) do
  usedCount = usedCount + 1
end

local codes = {}
for code in pairs(locales) do
  codes[#codes + 1] = code
end
table.sort(codes)

print(string.format("%d translatable keys found in source\n", usedCount))

local failed = false
for _, code in ipairs(codes) do
  local entries = locales[code]

  local translated, redundant, mismatched = 0, {}, {}
  for key, value in pairs(entries) do
    -- A locale's own plural rule is a function, not a translated string.
    if key ~= "plural" then
      translated = translated + 1
      -- Plural entries are "<singular key>#<form>"; the source holds only the base.
      if not corpus:find((key:gsub("#%a+$", "")), 1, true) then
        redundant[#redundant + 1] = key
      elseif formatMarkers(key) ~= formatMarkers(value) then
        mismatched[#mismatched + 1] = key
      end
    end
  end

  local base = {}
  for key in pairs(entries) do
    base[(key:gsub("#%a+$", ""))] = true
  end

  local missing = {}
  for key in pairs(used) do
    if not base[key] then
      missing[#missing + 1] = key
    end
  end

  table.sort(missing)
  table.sort(redundant)
  table.sort(mismatched)

  print(
    string.format(
      "%s: %d translated, %d missing, %d redundant, %d format mismatches",
      code,
      translated,
      #missing,
      #redundant,
      #mismatched
    )
  )

  for _, key in ipairs(mismatched) do
    print(string.format("  format   %q -> %q", key, entries[key]))
    failed = true
  end
  for _, key in ipairs(redundant) do
    print(string.format("  redundant %q", key))
    failed = true
  end
  for _, key in ipairs(missing) do
    print(string.format("  missing  %q", key))
    if strict then
      failed = true
    end
  end
end

os.exit(failed and 1 or 0)
