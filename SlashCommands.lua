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

local function selectedMuscle()
  return MM.DB:GetSelectedMuscleId()
end

local function muscleName(muscleId)
  local muscle = MM.DB:GetMuscle(muscleId)
  return muscle and muscle.name or muscleId
end

local function refresh()
  MM.UI:Refresh()
end

local function memoryRef(id)
  if id and MM.PredefinedMemories[id] then
    return { source = "predefined", id = id }
  end
  if id and MM.DB:Memories()[id] then
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
  MM:Print("created and activated empty profile " .. MM.DB:GetProfile(id).name .. ".")
end

local function profileClone(args)
  local name = table.concat(args, " ")
  local source = MM.DB:GetActiveProfileId()
  local id, reason = MM.DB:CloneProfile(source, name ~= "" and name or nil)
  if not id then
    MM:Warn(reason or "could not clone profile")
    return
  end
  MM.DB:SetActiveProfile(id)
  refresh()
  MM:Print("cloned profile to " .. MM.DB:GetProfile(id).name .. " and activated it.")
end

local function profileDefault(args)
  local id = MM.DB:FindProfileId(table.concat(args, " "))
  if not id then
    MM:Warn("usage: /mm profile default <name>")
    return
  end
  report("account default profile is now " .. MM.DB:GetProfile(id).name .. ".", MM.DB:SetGlobalProfile(id))
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

local function profileInherit()
  MM.DB:SetActiveProfile(nil)
  refresh()
  MM:Print("this character now inherits the account default profile (" .. MM.DB:GetProfile().name .. ").")
end

-- Muscles ------------------------------------------------------------------

local function muscleList()
  local selected = selectedMuscle()
  for index, entry in ipairs(MM.DB:GetProfileMuscles()) do
    local tags = (entry.enabled and "" or "  (disabled)") .. (entry.id == selected and "  (selected)" or "")
    MM:Print(string.format("%d. %s%s", index, entry.name, tags))
  end
end

local function muscleNew(args)
  local name = table.concat(args, " ")
  local id = MM.DB:CreateMuscle(name ~= "" and name or nil)
  MM.DB:SetSelectedMuscleId(id)
  MM.DB:SetSelectedSlot(nil)
  refresh()
  MM:Print("created muscle " .. muscleName(id) .. ".")
end

-- Resolve a muscle by profile-list index or by id/name.
local function resolveMuscleId(target)
  local index = tonumber(target)
  return index and (MM.DB:GetProfileMuscles()[index] or {}).id or MM.DB:FindMuscleId(target)
end

local function muscleSelect(args)
  local id = resolveMuscleId(table.concat(args, " "))
  if not id then
    MM:Warn("usage: /mm muscle select <index|name>")
    return
  end
  MM.DB:SetSelectedMuscleId(id)
  MM.DB:SetSelectedSlot(nil)
  refresh()
  MM:Print("selected muscle " .. muscleName(id) .. ".")
end

local function muscleRename(args)
  local target, new = args[1], args[2]
  if not target or not new then
    MM:Warn("usage: /mm muscle rename <index|name> <new>")
    return
  end

  local id = resolveMuscleId(target)
  if not id then
    MM:Warn("no muscle matching '" .. target .. "'.")
    return
  end
  report("renamed muscle to " .. new .. ".", MM.DB:RenameMuscle(id, new))
end

local function muscleDelete(args)
  local target = table.concat(args, " ")
  if target == "" then
    MM:Warn("usage: /mm muscle delete <index|name>")
    return
  end

  local id = resolveMuscleId(target)
  if not id then
    MM:Warn("no muscle matching '" .. target .. "'.")
    return
  end
  report(nil, MM.DB:DeleteMuscle(id))
end

local function setMuscleEnabled(enabled)
  return function(args)
    local id = resolveMuscleId(table.concat(args, " "))
    if not id then
      MM:Warn("usage: /mm muscle " .. (enabled and "enable" or "disable") .. " <index|name>")
      return
    end
    report(
      (enabled and "enabled" or "disabled") .. " muscle " .. muscleName(id) .. ".",
      MM.DB:SetMuscleEnabled(id, enabled)
    )
  end
end

local function muscleMove(args)
  local id = resolveMuscleId(args[1] or "")
  local toIndex = tonumber(args[2])
  if not id or not toIndex then
    MM:Warn("usage: /mm muscle move <index|name> <position>")
    return
  end
  report(string.format("moved %s to position %d.", muscleName(id), toIndex), MM.DB:MoveMuscle(id, toIndex))
end

local function setAllSlots(enabled)
  return function()
    local id = selectedMuscle()
    MM.DB:SetAllMuscleSlots(id, enabled)
    if not enabled then
      MM.DB:SetSelectedSlot(nil)
    end
    refresh()
    MM:Print(string.format("%s all slots in muscle %s.", enabled and "enabled" or "disabled", muscleName(id)))
  end
end

local function muscleCapture(args)
  local id = selectedMuscle()
  if args[1] and args[1] ~= "all" then
    local slot = tonumber(args[1])
    local ok, reason = MM.Capture:CaptureSlot(id, slot)
    if ok then
      MM:Print("captured " .. MM.Actions.GetSlotLabel(slot) .. " into " .. muscleName(id) .. ".")
    else
      MM:Warn(reason or "could not capture slot")
    end
  else
    local captured, failures = MM.Capture:CaptureFilledSlots(id)
    MM:Print(string.format("captured %d filled slots into %s, failed %d.", captured, muscleName(id), #failures))
    MM.Capture:PrintFailures(failures)
  end
  refresh()
end

local function slotEdit(args)
  local id = selectedMuscle()
  local slot = tonumber(args[1])
  if not MM.Actions.IsValidSlot(slot) then
    MM:Warn("usage: /mm muscle slot <1-" .. MM.MAX_ACTION_SLOT .. "> <verb>")
    return
  end

  local verb, arg = args[2], args[3]

  if not verb or verb == "show" then
    local muscle = MM.DB:GetMuscle(id)
    MM:Print(MM.Actions.GetSlotLabel(slot) .. ": " .. MM.Actions.GetAssignmentLabel(muscle and muscle.slots[slot]))
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
      MM:Warn(string.format("usage: /mm muscle slot %d %s <id>", slot, verb))
      return
    end
    assignment = { type = verb, id = actionId }
  elseif verb == "memory" then
    local ref = memoryRef(arg)
    if not ref then
      MM:Warn("unknown memory '" .. tostring(arg) .. "' (see /mm memory list)")
      return
    end
    assignment = { type = "memory", source = ref.source, id = ref.id }
  else
    MM:Warn("unknown slot verb '" .. verb .. "'.")
    return
  end

  MM.DB:SetSlot(id, slot, assignment)
  MM.DB:SetSelectedSlot(slot)
  refresh()
end

-- Memories -------------------------------------------------------------------

local function memoryList()
  local predefined = {}
  for id, memory in pairs(MM.PredefinedMemories) do
    predefined[#predefined + 1] = { id = id, name = memory.name or id }
  end
  table.sort(predefined, function(left, right)
    return left.id < right.id
  end)

  MM:Print("predefined memories (id — name):")
  for _, memory in ipairs(predefined) do
    MM:Print(string.format("  %s — %s", memory.id, memory.name))
  end

  local custom = MM.DB:Memories()
  if next(custom) then
    MM:Print("profile memories:")
    for id, memory in pairs(custom) do
      MM:Print(string.format("  %s — %s", id, memory.name or id))
    end
  end
end

local function memoryCopy(args)
  local key, reason = MM.DB:CopyPredefinedMemory(args[1], args[2])
  if key then
    MM:Print("copied predefined memory " .. tostring(args[1]) .. " to profile memory " .. key .. ".")
  else
    MM:Warn(reason or "could not copy memory")
  end
end

-- Top level ----------------------------------------------------------------

local function preview(args)
  MM.Applier:PreviewProfile(args[1] or MM.DB:GetActiveProfileId())
end

local function apply(args)
  MM.Applier:ApplyProfile(args[1] or MM.DB:GetActiveProfileId())
end

local function configFallback(args)
  if not args[1] then
    MM:Print("fallback: " .. MM.DB:GetFallback() .. " (what to do when a managed slot can't resolve).")
    return
  end
  report("fallback set to " .. args[1] .. ".", MM.DB:SetFallback(args[1]))
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
        new = { desc = "create an empty profile and use it on this character", args = "<name>", run = profileNew },
        clone = { desc = "clone the active profile and use it on this character", args = "<name>", run = profileClone },
        select = { desc = "use a profile on this character", args = "<name>", run = profileSelect },
        inherit = { desc = "use the account default profile on this character", run = profileInherit },
        default = { desc = "set the account default profile", args = "<name>", run = profileDefault },
        rename = { desc = "rename a profile", args = "<old> <new>", run = profileRename },
        delete = { desc = "delete a profile", args = "<name>", run = profileDelete },
      },
    },
    muscle = {
      desc = "manage the selected muscle",
      commands = {
        list = { desc = "list active muscles", run = muscleList },
        new = { desc = "create a muscle", args = "<name>", run = muscleNew },
        select = { desc = "select a muscle", args = "<index|name>", run = muscleSelect },
        rename = { desc = "rename a muscle", args = "<index|name> <new>", run = muscleRename },
        delete = { desc = "delete a muscle", args = "<index|name>", run = muscleDelete },
        move = { desc = "move a muscle to a position", args = "<index|name> <position>", run = muscleMove },
        enable = { desc = "enable a muscle in the active profile", args = "<index|name>", run = setMuscleEnabled(true) },
        disable = {
          desc = "disable a muscle in the active profile",
          args = "<index|name>",
          run = setMuscleEnabled(false),
        },
        enableall = { desc = "enable every slot", run = setAllSlots(true) },
        disableall = { desc = "clear every slot", run = setAllSlots(false) },
        capture = { desc = "capture a live slot, or all filled slots", args = "[slot|all]", run = muscleCapture },
        slot = {
          desc = "edit a slot",
          args = "<n> [spell|item|mount <id> | memory <id> | empty | ignore | disable | capture]",
          run = slotEdit,
        },
      },
    },
    memory = {
      desc = "manage memories",
      commands = {
        list = { desc = "list standard and custom memories", run = memoryList },
        copy = { desc = "copy a standard memory to custom", args = "<standard> [custom]", run = memoryCopy },
      },
    },
    config = {
      desc = "settings",
      commands = {
        fallback = { desc = "what to do with an unresolved slot", args = "<keep|clear>", run = configFallback },
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
