-- Decode a Muscle Memory string — a "!MMDBG:1!" debug report or a "!MM:2!"
-- sharing string — and print it as readable, sorted Lua.
--
-- Run from the repo root (inside the devcontainer):
--   lua scripts/dump-report.lua <file-with-string>

package.path = "./?.lua;./?/init.lua;" .. package.path
local addon = require("spec.helpers.addon")

local path = arg and arg[1]
if not path then
  print("usage: lua scripts/dump-report.lua <file-with-string>")
  os.exit(1)
end

local handle = assert(io.open(path, "r"))
local text = handle:read("*a"):gsub("%s+", "")
handle:close()

local MM = addon.fresh()
local decoded, reason
if text:match("^!MMDBG:") then
  decoded, reason = MM.Diagnostics:Decode(text)
else
  decoded, reason = MM.Share:Decode(text)
end
if not decoded then
  print("decode failed: " .. tostring(reason))
  os.exit(1)
end

local function dumpValue(value, indent)
  indent = indent or ""
  if type(value) ~= "table" then
    if type(value) == "string" and value:find("\n") then
      return string.format("%q", value)
    end
    return tostring(value)
  end
  local keys = {}
  for key in pairs(value) do
    keys[#keys + 1] = key
  end
  table.sort(keys, function(left, right)
    if type(left) == type(right) and (type(left) == "number" or type(left) == "string") then
      return left < right
    end
    return tostring(left) < tostring(right)
  end)
  local lines = { "{" }
  for _, key in ipairs(keys) do
    lines[#lines + 1] = indent .. "  " .. tostring(key) .. " = " .. dumpValue(value[key], indent .. "  ")
  end
  lines[#lines + 1] = indent .. "}"
  return table.concat(lines, "\n")
end

print(dumpValue(decoded))
