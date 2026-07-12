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

local function tocFiles()
  local path = addonRoot .. "/MuscleMemory.toc"
  local handle = assert(io.open(path, "r"))
  local files = {}
  for line in handle:lines() do
    line = line:gsub("%s+$", "")
    if line ~= "" and not line:match("^##") and line:match("%.lua$") and not line:match("^UI/") then
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

  return MM, stubs, env
end

-- Load and initialize a clean saved-variables DB. The common starting point.
function M.fresh(opts)
  local MM, stubs, env = M.load(opts)
  MM.DB:Initialize()
  return MM, stubs, env
end

M.Stubs = Stubs

return M
