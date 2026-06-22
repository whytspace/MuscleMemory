local ADDON_NAME, MM = ...

local Slash = {}
MM.Slash = Slash
MM:RegisterModule("Slash", Slash)

-- Split a command line into tokens. Whitespace separates tokens, but a
-- "quoted run" or 'quoted run' is kept whole, so names may contain spaces.
local function words(text)
  text = text or ""
  local list, index = {}, 1
  while index <= #text do
    local char = string.sub(text, index, index)
    if char == " " or char == "\t" then
      index = index + 1
    elseif char == '"' or char == "'" then
      local close = string.find(text, char, index + 1, true) or (#text + 1)
      list[#list + 1] = string.sub(text, index + 1, close - 1)
      index = close + 1
    else
      local stop = string.find(text, "%s", index) or (#text + 1)
      list[#list + 1] = string.sub(text, index, stop - 1)
      index = stop
    end
  end
  return list
end

local function selectedLayer()
  return MM.DB:GetSelectedLayerId()
end

local function layerName(layerId)
  local layer = MM.DB:GetLayer(layerId)
  return layer and layer.name or layerId
end

local function refresh()
  MM.UI:Refresh()
end

local function groupRef(id)
  if id and MM.StandardGroups[id] then
    return { source = "standard", id = id }
  end
  if id and MM.DB:GetCustomGroup(id) then
    return { source = "custom", id = id }
  end
  return nil
end

-- Report the result of a DB call: refresh (and print successMsg, if any) on
-- success, else warn with the reason. Pass the DB call LAST so its (ok, reason)
-- multi-return survives: report("done.", MM.DB:DoThing(id)).
local function report(successMsg, ok, reason)
  if ok then
    refresh()
    if successMsg then
      MM:Print(successMsg)
    end
  else
    MM:Warn(reason or "command failed")
  end
end

-- Profiles -----------------------------------------------------------------

local function profileList()
  local active = MM.DB:GetActiveProfileId()
  for _, profile in ipairs(MM.DB:GetProfileList()) do
    MM:Print(profile.name .. (profile.id == active and "  (active)" or ""))
  end
end

local function profileNew(args)
  local name = table.concat(args, " ")
  local id = MM.DB:CreateProfile(name ~= "" and name or nil)
  MM.DB:SetActiveProfile(id)
  refresh()
  MM:Print("created and activated profile " .. MM.DB:GetProfile(id).name .. ".")
end

local function profileSelect(args)
  local id = MM.DB:FindProfileId(table.concat(args, " "))
  if not id then
    MM:Warn("usage: /mm profile select <name>")
    return
  end
  report("active profile is now " .. MM.DB:GetProfile(id).name .. ".", MM.DB:SetActiveProfile(id))
end

local function profileRename(args)
  local old, new = args[1], args[2]
  if not old or not new then
    MM:Warn("usage: /mm profile rename <old> <new>")
    return
  end

  local id = MM.DB:FindProfileId(old)
  if not id then
    MM:Warn("no profile matching '" .. old .. "'.")
    return
  end
  report("renamed profile to " .. new .. ".", MM.DB:RenameProfile(id, new))
end

local function profileDelete(args)
  local target = table.concat(args, " ")
  if target == "" then
    MM:Warn("usage: /mm profile delete <name>")
    return
  end

  local id = MM.DB:FindProfileId(target)
  if not id then
    MM:Warn("no profile matching '" .. target .. "'.")
    return
  end
  report(nil, MM.DB:DeleteProfile(id))
end

-- Layers ------------------------------------------------------------------

local function layerList()
  local selected = selectedLayer()
  for _, entry in ipairs(MM.DB:GetProfileLayers()) do
    local tags = (entry.enabled and "" or "  (disabled)") .. (entry.id == selected and "  (selected)" or "")
    MM:Print(string.format("%d. %s%s", entry.order, entry.name, tags))
  end
end

local function layerNew(args)
  local name = table.concat(args, " ")
  local id = MM.DB:CreateLayer(name ~= "" and name or nil)
  MM.DB:SetSelectedLayerId(id)
  MM.DB:SetSelectedSlot(nil)
  refresh()
  MM:Print("created layer " .. layerName(id) .. ".")
end

-- Resolve a layer by profile-list index or by id/name.
local function resolveLayerId(target)
  local index = tonumber(target)
  return index and (MM.DB:GetProfileLayers()[index] or {}).id or MM.DB:FindLayerId(target)
end

local function layerSelect(args)
  local id = resolveLayerId(table.concat(args, " "))
  if not id then
    MM:Warn("usage: /mm layer select <index|name>")
    return
  end
  MM.DB:SetSelectedLayerId(id)
  MM.DB:SetSelectedSlot(nil)
  refresh()
  MM:Print("selected layer " .. layerName(id) .. ".")
end

local function layerRename(args)
  local target, new = args[1], args[2]
  if not target or not new then
    MM:Warn("usage: /mm layer rename <index|name> <new>")
    return
  end

  local id = resolveLayerId(target)
  if not id then
    MM:Warn("no layer matching '" .. target .. "'.")
    return
  end
  report("renamed layer to " .. new .. ".", MM.DB:RenameLayer(id, new))
end

local function layerDelete(args)
  local target = table.concat(args, " ")
  if target == "" then
    MM:Warn("usage: /mm layer delete <index|name>")
    return
  end

  local id = resolveLayerId(target)
  if not id then
    MM:Warn("no layer matching '" .. target .. "'.")
    return
  end
  report(nil, MM.DB:DeleteLayer(id))
end

local function setLayerEnabled(enabled)
  return function(args)
    local id = resolveLayerId(table.concat(args, " "))
    if not id then
      MM:Warn("usage: /mm layer " .. (enabled and "enable" or "disable") .. " <index|name>")
      return
    end
    report(
      (enabled and "enabled" or "disabled") .. " layer " .. layerName(id) .. ".",
      MM.DB:SetLayerEnabled(id, enabled)
    )
  end
end

local function layerMove(args)
  local id = resolveLayerId(args[1] or "")
  local toIndex = tonumber(args[2])
  if not id or not toIndex then
    MM:Warn("usage: /mm layer move <index|name> <position>")
    return
  end
  report(string.format("moved %s to position %d.", layerName(id), toIndex), MM.DB:MoveLayer(id, toIndex))
end

local function setAllSlots(enabled)
  return function()
    local id = selectedLayer()
    MM.DB:SetAllLayerSlots(id, enabled)
    if not enabled then
      MM.DB:SetSelectedSlot(nil)
    end
    refresh()
    MM:Print(string.format("%s all slots in layer %s.", enabled and "enabled" or "disabled", layerName(id)))
  end
end

local function layerCapture(args)
  local id = selectedLayer()
  if args[1] and args[1] ~= "all" then
    local slot = tonumber(args[1])
    local ok, reason = MM.Capture:CaptureSlot(id, slot)
    if ok then
      MM:Print("captured " .. MM.Actions.GetSlotLabel(slot) .. " into " .. layerName(id) .. ".")
    else
      MM:Warn(reason or "could not capture slot")
    end
  else
    local captured, failures = MM.Capture:CaptureFilledSlots(id)
    MM:Print(string.format("captured %d filled slots into %s, failed %d.", captured, layerName(id), #failures))
    MM.Capture:PrintFailures(failures)
  end
  refresh()
end

local function slotEdit(args)
  local id = selectedLayer()
  local slot = tonumber(args[1])
  if not MM.Actions.IsValidSlot(slot) then
    MM:Warn("usage: /mm layer slot <1-" .. MM.MAX_ACTION_SLOT .. "> <verb>")
    return
  end

  local verb, arg = args[2], args[3]

  if not verb or verb == "show" then
    local layer = MM.DB:GetLayer(id)
    MM:Print(MM.Actions.GetSlotLabel(slot) .. ": " .. MM.Actions.GetAssignmentLabel(layer and layer.slots[slot]))
    return
  end

  if verb == "capture" then
    report("captured " .. MM.Actions.GetSlotLabel(slot) .. ".", MM.Capture:CaptureSlot(id, slot))
    return
  end

  local assignment
  if verb == "empty" or verb == "ignore" then
    assignment = { type = verb }
  elseif verb == "disable" then
    assignment = nil
  elseif verb == "spell" or verb == "item" or verb == "mount" then
    local actionId = tonumber(arg)
    if not actionId then
      MM:Warn(string.format("usage: /mm layer slot %d %s <id>", slot, verb))
      return
    end
    assignment = { type = verb, id = actionId }
  elseif verb == "group" then
    local ref = groupRef(arg)
    if not ref then
      MM:Warn("unknown group '" .. tostring(arg) .. "' (see /mm group list)")
      return
    end
    assignment = { type = "group", source = ref.source, id = ref.id }
  else
    MM:Warn("unknown slot verb '" .. verb .. "'.")
    return
  end

  MM.DB:SetSlot(id, slot, assignment)
  MM.DB:SetSelectedSlot(slot)
  refresh()
end

-- Groups -------------------------------------------------------------------

local function groupList()
  local standard = {}
  for id, group in pairs(MM.StandardGroups) do
    standard[#standard + 1] = { id = id, name = group.name or id }
  end
  table.sort(standard, function(left, right)
    return left.id < right.id
  end)

  MM:Print("standard groups (id — name):")
  for _, group in ipairs(standard) do
    MM:Print(string.format("  %s — %s", group.id, group.name))
  end

  local custom = MM.DB:GetRoot().customGroups
  if next(custom) then
    MM:Print("custom groups:")
    for id, group in pairs(custom) do
      MM:Print(string.format("  %s — %s", id, group.name or id))
    end
  end
end

local function groupCopy(args)
  local group, reason = MM.DB:CopyStandardGroup(args[1], args[2])
  if group then
    MM:Print("copied standard group " .. tostring(args[1]) .. " to custom group " .. group.id .. ".")
  else
    MM:Warn(reason or "could not copy group")
  end
end

-- Top level ----------------------------------------------------------------

local function preview(args)
  MM.Applier:PreviewProfile(args[1] or MM.DB:GetActiveProfileId())
end

local function apply(args)
  MM.Applier:ApplyProfile(args[1] or MM.DB:GetActiveProfileId())
end

local function toggleDebug()
  local root = MM.DB:GetRoot()
  root.debug = not root.debug
  MM:Print("debug " .. (root.debug and "enabled" or "disabled") .. ".")
end

-- The command tree. A node is either a branch (has `commands`) or a leaf
-- (has `run`). `help` and an empty argument list both print a branch's
-- children, so every level is self-documenting.
local tree = {
  desc = "Muscle Memory commands",
  commands = {
    profile = {
      desc = "manage profiles",
      commands = {
        list = { desc = "list profiles", run = profileList },
        new = { desc = "create and activate a profile", args = "<name>", run = profileNew },
        select = { desc = "switch active profile", args = "<name>", run = profileSelect },
        rename = { desc = "rename a profile", args = "<old> <new>", run = profileRename },
        delete = { desc = "delete a profile", args = "<name>", run = profileDelete },
      },
    },
    layer = {
      desc = "manage the selected layer",
      commands = {
        list = { desc = "list active layers", run = layerList },
        new = { desc = "create a layer", args = "<name>", run = layerNew },
        select = { desc = "select a layer", args = "<index|name>", run = layerSelect },
        rename = { desc = "rename a layer", args = "<index|name> <new>", run = layerRename },
        delete = { desc = "delete a layer", args = "<index|name>", run = layerDelete },
        move = { desc = "move a layer to a position", args = "<index|name> <position>", run = layerMove },
        enable = { desc = "enable a layer in the active profile", args = "<index|name>", run = setLayerEnabled(true) },
        disable = {
          desc = "disable a layer in the active profile",
          args = "<index|name>",
          run = setLayerEnabled(false),
        },
        enableall = { desc = "enable every slot", run = setAllSlots(true) },
        disableall = { desc = "clear every slot", run = setAllSlots(false) },
        capture = { desc = "capture a live slot, or all filled slots", args = "[slot|all]", run = layerCapture },
        slot = {
          desc = "edit a slot",
          args = "<n> [spell|item|mount <id> | group <id> | empty | ignore | disable | capture]",
          run = slotEdit,
        },
      },
    },
    group = {
      desc = "manage action groups",
      commands = {
        list = { desc = "list standard and custom groups", run = groupList },
        copy = { desc = "copy a standard group to custom", args = "<standard> [custom]", run = groupCopy },
      },
    },
    preview = { desc = "preview the active or named profile", args = "[profile]", run = preview },
    apply = { desc = "apply the active or named profile", args = "[profile]", run = apply },
    debug = { desc = "toggle debug output", run = toggleDebug },
  },
}

local function printHelp(node, path)
  local prefix = "/mm" .. (path ~= "" and (" " .. path) or "")
  MM:Print(prefix .. " — " .. node.desc .. ":")

  local names = {}
  for name in pairs(node.commands) do
    names[#names + 1] = name
  end
  table.sort(names)

  for _, name in ipairs(names) do
    local child = node.commands[name]
    local tail = child.commands and " ..." or (child.args and (" " .. child.args) or "")
    MM:Print(string.format("  %s %s%s — %s", prefix, name, tail, child.desc))
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
    MM:Warn(string.format("unknown command '%s'. Try /mm %shelp.", key, path == "" and "" or (path .. " ")))
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
