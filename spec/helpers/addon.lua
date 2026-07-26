-- Loads the add-on under plain Lua 5.1 for testing.
--
-- Each .lua file in the .toc is executed with the same `("MuscleMemory", MM)`
-- varargs WoW passes, inside a shared sandbox environment whose globals are the
-- fake WoW API from spec.helpers.wow_stubs. stdlib (string, table, …) falls
-- through to the real _G; unknown WoW globals are nil, which exercises the
-- add-on's own "is this API available?" guards.
--
-- UI files are skipped: they build real frames at load and aren't unit-tested.

local Stubs = require("spec.helpers.wow_stubs")

local M = {}

local helpersDir = (debug.getinfo(1, "S").source:sub(2)):match("^(.*)/[^/]*$")
local addonRoot = helpersDir:gsub("/spec/helpers$", "")

local function tocFiles(includeUI)
  local path = addonRoot .. "/MuscleMemory.toc"
  local handle = assert(io.open(path, "r"))
  local files = {}
  for line in handle:lines() do
    line = line:gsub("%s+$", "")
    local skipUI = not includeUI and line:match("^UI/")
    if line ~= "" and not line:match("^##") and line:match("%.lua$") and not skipUI then
      files[#files + 1] = line
    end
  end
  handle:close()
  return files
end

-- Load the add-on. Returns (MM, stubs, env). `env` is the shared global table:
-- mutate env.SomeApi mid-test to flip an API's availability, since the add-on
-- resolves globals through it at call time.
function M.load(opts)
  opts = opts or {}
  local stubs = opts.stubs or Stubs.new()
  local MM = {}
  local env = setmetatable({}, { __index = _G })
  for name, value in pairs(stubs.globals) do
    env[name] = value
  end

  for _, file in ipairs(tocFiles()) do
    local chunk = assert(loadfile(addonRoot .. "/" .. file))
    setfenv(chunk, env)
    chunk("MuscleMemory", MM)
  end

  -- Pin English so a locale forced in Locales.lua for testing can't fail the suite.
  MM.locale = "enUS"

  return MM, stubs, env
end

-- Load and initialize a clean saved-variables DB. The common starting point.
function M.fresh(opts)
  local MM, stubs, env = M.load(opts)
  MM.DB:Initialize()
  return MM, stubs, env
end

-- Load every .toc file (UI included) with a recording L; anything returned here
-- resolved at file scope, before the saved locale override could apply.
-- UI files build real frames, so unknown globals auto-stub to a callable dummy.
function M.fileScopeLookups()
  local dummy = {}
  setmetatable(dummy, {
    __index = function()
      return dummy
    end,
    __call = function()
      return dummy
    end,
    __concat = function()
      return ""
    end,
    __tostring = function()
      return ""
    end,
  })

  local env = setmetatable({}, {
    __index = function(_, key)
      local real = rawget(_G, key)
      if real ~= nil then
        return real
      end
      return dummy
    end,
  })

  local MM = {}
  local lookups = {}
  -- Read through a table so the recorder blames the chunk that triggered it.
  local loading = { file = "?" }

  for _, file in ipairs(tocFiles(true)) do
    loading.file = file
    local chunk = assert(loadfile(addonRoot .. "/" .. file))
    setfenv(chunk, env)
    pcall(chunk, "MuscleMemory", MM)

    -- Swap in the recording proxy as soon as the real one exists.
    if file:match("Locales/Locales%.lua$") then
      MM.L = setmetatable({}, {
        __index = function(_, key)
          lookups[#lookups + 1] = loading.file .. ": " .. tostring(key)
          return key
        end,
      })
    end
  end

  return lookups
end

M.Stubs = Stubs
M.root = addonRoot

-- Run one add-on file against a caller-supplied MM, for testing load-time behaviour.
function M.loadFile(relativePath, MM)
  local chunk = assert(loadfile(addonRoot .. "/" .. relativePath))
  setfenv(chunk, setmetatable({}, { __index = _G }))
  chunk("MuscleMemory", MM)
  return MM
end

return M
