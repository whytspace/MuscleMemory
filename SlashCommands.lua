local ADDON_NAME, MM = ...

local Slash = {}
MM.Slash = Slash
MM:RegisterModule("Slash", Slash)

-- The player-facing command surface is deliberately tiny: managing profiles,
-- layers and smart actions lives in the UI and the public API (API.lua).

local function words(text)
  local list = {}
  for token in string.gmatch(text or "", "%S+") do
    list[#list + 1] = token
  end
  return list
end

local function preview()
  MM.Applier:PreviewProfile()
end

local function apply()
  MM.Applier:ApplyProfile()
end

local function toggleDebug()
  local root = MM.DB:GetRoot()
  root.debug = not root.debug
  MM:Print(root.debug and MM.L["debug enabled."] or MM.L["debug disabled."])
end

-- A node is either a branch (has `commands`) or a leaf (has `run`). `help` and
-- an empty argument list both print a branch's children; `hidden` nodes work
-- but stay out of the help output.
local tree = {
  desc = "open the Muscle Memory window",
  commands = {
    preview = { desc = "preview the active profile", run = preview, order = 1 },
    apply = { desc = "apply the active profile", run = apply, order = 2 },
    debug = { desc = "toggle debug output", run = toggleDebug, order = 3 },
    shot = {
      desc = "capture transparent marketing screenshots (maintainer tool)",
      hidden = true,
      commands = {
        tour = {
          desc = "build a showcase profile and capture every view",
          run = function()
            MM.ScreenshotTour:Run()
          end,
        },
        view = {
          desc = "capture a single view",
          args = "<layers|smart-actions|macro-editor|macro-window|profiles|export|import|suggestion>",
          run = function(args)
            MM.ScreenshotTour:RunOne(args[1])
          end,
        },
      },
    },
  },
}

-- Descs are stored in English and localized here, at print time.
local function printHelp(node, path)
  local prefix = "/mm" .. (path ~= "" and (" " .. path) or "")
  MM:Print(prefix .. " — " .. MM.L[node.desc])

  local names = {}
  for name, child in pairs(node.commands) do
    if not child.hidden then
      names[#names + 1] = name
    end
  end
  -- Curated order first (the `order` field), alphabetical for the rest.
  table.sort(names, function(left, right)
    local leftOrder = node.commands[left].order or math.huge
    local rightOrder = node.commands[right].order or math.huge
    if leftOrder ~= rightOrder then
      return leftOrder < rightOrder
    end
    return left < right
  end)

  for _, name in ipairs(names) do
    local child = node.commands[name]
    local tail = child.commands and " ..." or (child.args and (" " .. child.args) or "")
    MM:Print(string.format("  %s %s%s — %s", prefix, name, tail, MM.L[child.desc]))
  end
end

local function dispatch(node, tokens, path)
  if not node.commands then
    node.run(tokens)
    return
  end

  local key = tokens[1]
  if not key or key == "help" then
    printHelp(node, path)
    return
  end

  local child = node.commands[key]
  if not child then
    MM:Warn(string.format(MM.L["unknown command '%s'. Try /mm %shelp."], key, path == "" and "" or (path .. " ")))
    return
  end

  table.remove(tokens, 1)
  dispatch(child, tokens, path == "" and key or (path .. " " .. key))
end

function Slash:Handle(message)
  local tokens = words(message)
  if #tokens == 0 then
    MM:Open()
    return
  end
  dispatch(tree, tokens, "")
end

function Slash:OnInitialize()
  SLASH_MUSCLEMEMORY1 = "/mm"
  SLASH_MUSCLEMEMORY2 = "/musclememory"
  SlashCmdList.MUSCLEMEMORY = function(message)
    self:Handle(message)
  end
end
