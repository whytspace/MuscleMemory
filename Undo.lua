local ADDON_NAME, MM = ...

-- Session-only, snapshot-based undo for configuration changes. Every DB config
-- mutator is wrapped to push a deep copy of the config subtree (profiles, the
-- default/character profile pointers and the account settings) onto a bounded
-- stack before it runs; Undo/Redo restore a snapshot wholesale. Applying to the
-- action bars is deliberately NOT undoable — bars and macros are external state
-- outside the snapshot.

local Undo = {}
MM.Undo = Undo
MM:RegisterModule("Undo", Undo)

Undo.MAX_STEPS = 20

-- Stack entries are { state = <snapshot>, label = <what undoing it reverts> }.
local stack, redo = {}, {}
local batchDepth = 0
local batchCaptured = false
local batchLabel = nil
local restoring = false

-- What a snapshot covers: everything "configuration", nothing runtime.
local function capture()
  local root = MM.DB:GetRoot()
  local characterProfiles = {}
  for key, state in pairs(root.characterState or {}) do
    characterProfiles[key] = state.profile
  end
  return {
    profiles = MM.Tables.DeepCopy(root.profiles),
    profile = root.profile,
    suggest = root.suggestDynamicActions,
    characterProfiles = characterProfiles,
  }
end

local function restore(snapshot)
  local root = MM.DB:GetRoot()
  root.profiles = MM.Tables.DeepCopy(snapshot.profiles)
  root.profile = snapshot.profile
  root.suggestDynamicActions = snapshot.suggest
  for key, state in pairs(root.characterState or {}) do
    state.profile = snapshot.characterProfiles[key]
  end
end

local function refresh()
  if MM.UI and MM.UI.Refresh then
    MM.UI:Refresh()
  end
end

-- Focus: where two snapshots differ, so Undo/Redo can land the player on what
-- actually changed. `after` is the state about to be shown.

local function unionKeys(left, right)
  local keys = {}
  for key in pairs(left or {}) do
    keys[key] = true
  end
  for key in pairs(right or {}) do
    keys[key] = true
  end
  return keys
end

local function layerFocus(beforeProfile, afterProfile)
  for layerId in pairs(unionKeys(beforeProfile.layers, afterProfile.layers)) do
    local beforeLayer = (beforeProfile.layers or {})[layerId]
    local afterLayer = (afterProfile.layers or {})[layerId]
    if not MM.Tables.DeepEquals(beforeLayer, afterLayer) then
      local slotFocus
      for slot in pairs(unionKeys(beforeLayer and beforeLayer.slots, afterLayer and afterLayer.slots)) do
        local beforeSlot = beforeLayer and beforeLayer.slots and beforeLayer.slots[slot]
        local afterSlot = afterLayer and afterLayer.slots and afterLayer.slots[slot]
        if not MM.Tables.DeepEquals(beforeSlot, afterSlot) then
          slotFocus = tonumber(slot)
          break
        end
      end
      -- Select the layer only if it exists in the shown state.
      return { tab = "layers", layerId = afterLayer and layerId or nil, slot = slotFocus }
    end
  end
  if not MM.Tables.DeepEquals(beforeProfile.layerOrder, afterProfile.layerOrder) then
    return { tab = "layers" }
  end
  return nil
end

local function dynamicActionFocus(beforeProfile, afterProfile)
  for actionId in pairs(unionKeys(beforeProfile.dynamicActions, afterProfile.dynamicActions)) do
    local beforeAction = (beforeProfile.dynamicActions or {})[actionId]
    local afterAction = (afterProfile.dynamicActions or {})[actionId]
    if not MM.Tables.DeepEquals(beforeAction, afterAction) then
      local candidateFocus
      if beforeAction and afterAction then
        local beforeCandidates = beforeAction.candidates or {}
        local afterCandidates = afterAction.candidates or {}
        for index = 1, math.max(#beforeCandidates, #afterCandidates) do
          if not MM.Tables.DeepEquals(beforeCandidates[index], afterCandidates[index]) then
            candidateFocus = math.min(index, #afterCandidates)
            break
          end
        end
        if candidateFocus == 0 then
          candidateFocus = nil
        end
      end
      return { tab = "dynamicActions", actionId = afterAction and actionId or nil, candidate = candidateFocus }
    end
  end
  return nil
end

local function focusOf(before, after)
  local mine = MM.DB:GetCharacterKey()
  if before.characterProfiles[mine] ~= after.characterProfiles[mine] or before.profile ~= after.profile then
    return { tab = "profiles" }
  end
  if before.suggest ~= after.suggest then
    return { tab = "settings" }
  end

  local activeId = after.characterProfiles[mine] or after.profile or next(after.profiles)
  for profileId in pairs(unionKeys(before.profiles, after.profiles)) do
    if not MM.Tables.DeepEquals(before.profiles[profileId], after.profiles[profileId]) then
      local beforeProfile, afterProfile = before.profiles[profileId], after.profiles[profileId]
      if profileId ~= activeId or not beforeProfile or not afterProfile then
        -- Created/deleted profiles and edits outside the active one.
        return { tab = "profiles" }
      end
      if beforeProfile.fallback ~= afterProfile.fallback or beforeProfile.response ~= afterProfile.response then
        return { tab = "settings" }
      end
      return layerFocus(beforeProfile, afterProfile)
        or dynamicActionFocus(beforeProfile, afterProfile)
        or { tab = "profiles" } -- anything else, e.g. a profile rename
    end
  end
  return nil
end

-- The profile this snapshot has the current character on (their own choice,
-- else the account default).
local function effectiveProfile(snapshot)
  return snapshot.characterProfiles[MM.DB:GetCharacterKey()] or snapshot.profile
end

-- Switching profiles by hand runs the apply-prompt check (ProfilesTab); a
-- restore that lands the character on a different profile mirrors that.
local function promptIfProfileChanged(before, after)
  -- MM.UI is absent under the test harness; Events assumes it.
  if effectiveProfile(before) ~= effectiveProfile(after) and MM.Events and MM.UI then
    MM.Events:PromptApplyIfChanged()
  end
end

local function applyFocus(focus)
  if not focus then
    return
  end
  if MM.ui and MM.ui.state then
    MM.ui.state.tab = focus.tab
    if focus.tab == "dynamicActions" and focus.actionId then
      MM.ui.state.dynamicAction = { source = "custom", id = focus.actionId }
      MM.ui.state.candidate = focus.candidate
    end
  end
  if focus.layerId then
    MM.DB:SetSelectedLayerId(focus.layerId)
    MM.DB:SetSelectedSlot(focus.slot)
  end
end

-- Labels: human phrases for what the mutation about to run would do, built at
-- mutation time while the touched entities still exist to be named.

local function layerName(layerId)
  local layer = MM.DB:GetLayer(layerId)
  return (layer and layer.name) or tostring(layerId)
end

local function actionName(actionId)
  local action = MM.DB:DynamicActions()[actionId]
  return (action and action.name) or tostring(actionId)
end

local function profileName(profileId)
  local profile = MM.DB:GetProfile(profileId)
  return (profile and profile.name) or tostring(profileId)
end

local function candidateName(actionId, index)
  local action = MM.DB:DynamicActions()[actionId]
  local candidate = action and action.candidates and action.candidates[tonumber(index) or -1]
  return candidate and MM.Actions.GetAssignmentName(candidate) or ("candidate " .. tostring(index))
end

local DESCRIBE = {
  SetGlobalProfile = function(profileId)
    return "set the default profile to " .. profileName(profileId)
  end,
  CreateProfile = function(name)
    return name and ("create profile " .. name) or "create a profile"
  end,
  CloneProfile = function(sourceId)
    return "copy profile " .. profileName(sourceId)
  end,
  RenameProfile = function(profileId)
    return "rename profile " .. profileName(profileId)
  end,
  DeleteProfile = function(profileId)
    return "delete profile " .. profileName(profileId)
  end,
  SetActiveProfile = function(profileId)
    return profileId and ("switch to profile " .. profileName(profileId)) or "inherit the default profile"
  end,
  CreateLayer = function(name)
    return name and ("create layer " .. name) or "create a layer"
  end,
  RenameLayer = function(layerId)
    return "rename layer " .. layerName(layerId)
  end,
  DeleteLayer = function(layerId)
    return "delete layer " .. layerName(layerId)
  end,
  MoveLayer = function(layerId)
    return "move layer " .. layerName(layerId)
  end,
  SetLayerEnabled = function(layerId, enabled)
    return (enabled and "enable layer " or "disable layer ") .. layerName(layerId)
  end,
  SetLayerConditions = function(layerId)
    return "edit conditions of layer " .. layerName(layerId)
  end,
  SetSlot = function(_, slot, assignment)
    local where = MM.Actions.GetSlotLabel(tonumber(slot) or slot)
    if not assignment then
      return "stop managing " .. where
    end
    return "assign " .. MM.Actions.GetAssignmentName(assignment) .. " to " .. where
  end,
  SetAllLayerSlots = function(layerId, enabled)
    local name = layerName(layerId)
    return enabled and ("manage every slot of layer " .. name) or ("clear all slots of layer " .. name)
  end,
  AdoptLayer = function(_, layer)
    return "import layer " .. tostring(layer and layer.name)
  end,
  SetFallback = function(value)
    return "set fallback to " .. tostring(value)
  end,
  SetResponse = function(value)
    return "set response to " .. tostring(value)
  end,
  SetSuggestMode = function(value)
    return "set suggestions to " .. tostring(value)
  end,
  CreateDynamicAction = function(name)
    return name and ("create Dynamic Action " .. name) or "create a Dynamic Action"
  end,
  CopyPredefinedDynamicAction = function(actionId)
    return "copy predefined Dynamic Action " .. tostring(actionId)
  end,
  CloneDynamicAction = function(reference)
    local source = MM.DB:ResolveDynamicAction(reference)
    return "copy Dynamic Action " .. tostring(source and source.name)
  end,
  RenameDynamicAction = function(actionId)
    return "rename Dynamic Action " .. actionName(actionId)
  end,
  DeleteDynamicAction = function(actionId)
    return "delete Dynamic Action " .. actionName(actionId)
  end,
  SetDynamicActionMode = function(actionId, mode)
    return (mode == "macro" and "enable macro mode for " or "disable macro mode for ") .. actionName(actionId)
  end,
  SetDynamicActionTemplate = function(actionId)
    return "edit the macro template of " .. actionName(actionId)
  end,
  AdoptDynamicAction = function(_, _, action)
    return "import Dynamic Action " .. tostring(action and action.name)
  end,
  AddCandidate = function(actionId, assignment)
    return "add " .. MM.Actions.GetAssignmentName(assignment) .. " to " .. actionName(actionId)
  end,
  RemoveCandidate = function(actionId, index)
    return "remove " .. candidateName(actionId, index) .. " from " .. actionName(actionId)
  end,
  MoveCandidate = function(actionId)
    return "reorder the candidates of " .. actionName(actionId)
  end,
  SetCandidateConditions = function(actionId, index)
    return "edit conditions of " .. candidateName(actionId, index) .. " in " .. actionName(actionId)
  end,
}

-- Labels must never break a mutation, so descriptor errors fall back to the
-- bare method name. `...` starts with the DB self argument.
local function describe(name, _, ...)
  local descriptor = DESCRIBE[name]
  if not descriptor then
    return name
  end
  local ok, label = pcall(descriptor, ...)
  return (ok and label) or name
end

-- Called by the DB mutator wrappers before every config mutation. Skips when a
-- batch already captured its snapshot, and when nothing has changed since the
-- top of the stack (failed mutations and no-op commits leave no empty steps).
function Undo:BeforeMutation(name, ...)
  if restoring then
    return
  end
  local label
  if batchDepth > 0 then
    if batchCaptured then
      return
    end
    batchCaptured = true
    label = batchLabel
  end
  label = label or describe(name, ...)

  local snapshot = capture()
  local top = stack[#stack]
  if top and MM.Tables.DeepEquals(top.state, snapshot) then
    -- The step's previous mutation turned out to be a no-op; the label now
    -- belongs to the mutation about to run.
    top.label = label
    return
  end

  stack[#stack + 1] = { state = snapshot, label = label }
  if #stack > self.MAX_STEPS then
    table.remove(stack, 1)
  end
  redo = {}
end

-- Group every mutation inside `fn` into a single undo step (e.g. an import),
-- labeled `label` in the tooltip. Return values and errors pass through.
function Undo:Batch(fn, label)
  batchDepth = batchDepth + 1
  if batchDepth == 1 then
    batchLabel = label
  end
  local results = { pcall(fn) }
  batchDepth = batchDepth - 1
  if batchDepth == 0 then
    batchCaptured = false
    batchLabel = nil
  end
  if not results[1] then
    error(results[2], 0)
  end
  return unpack(results, 2)
end

-- What the next Undo/Redo would revert, for tooltips. nil when there is none.
function Undo:NextUndoLabel()
  local entry = stack[#stack]
  return entry and entry.label
end

function Undo:NextRedoLabel()
  local entry = redo[#redo]
  return entry and entry.label
end

function Undo:CanUndo()
  return #stack > 0
end

function Undo:CanRedo()
  return #redo > 0
end

-- Revert the most recent configuration change.
function Undo:Undo()
  local current = capture()

  -- A top identical to the current state carries no change (e.g. the last
  -- mutation failed after snapshotting) — drop it and reach for the one below.
  if stack[#stack] and MM.Tables.DeepEquals(stack[#stack].state, current) then
    table.remove(stack)
  end

  local entry = table.remove(stack)
  if not entry then
    return false, "nothing to undo"
  end

  redo[#redo + 1] = { state = current, label = entry.label }
  restoring = true
  restore(entry.state)
  restoring = false
  applyFocus(focusOf(current, entry.state))
  refresh()
  promptIfProfileChanged(current, entry.state)
  return true
end

-- Restore the change most recently undone. Any new mutation clears redo.
function Undo:Redo()
  local entry = table.remove(redo)
  if not entry then
    return false, "nothing to redo"
  end

  local current = capture()
  stack[#stack + 1] = { state = current, label = entry.label }
  restoring = true
  restore(entry.state)
  restoring = false
  applyFocus(focusOf(current, entry.state))
  refresh()
  promptIfProfileChanged(current, entry.state)
  return true
end

-- Forget all undo history (used by maintainer tools that churn the config).
function Undo:Reset()
  stack, redo = {}, {}
end

-- Every DB method that mutates configuration. Wrapped at load; anything not
-- listed here (getters, selection, macro records) never snapshots.
local MUTATORS = {
  "SetGlobalProfile",
  "CreateProfile",
  "CloneProfile",
  "RenameProfile",
  "DeleteProfile",
  "SetActiveProfile",
  "CreateLayer",
  "RenameLayer",
  "DeleteLayer",
  "MoveLayer",
  "SetLayerEnabled",
  "SetLayerConditions",
  "SetSlot",
  "SetAllLayerSlots",
  "AdoptLayer",
  "SetFallback",
  "SetResponse",
  "SetSuggestMode",
  "CreateDynamicAction",
  "CopyPredefinedDynamicAction",
  "CloneDynamicAction",
  "RenameDynamicAction",
  "DeleteDynamicAction",
  "SetDynamicActionMode",
  "SetDynamicActionTemplate",
  "AdoptDynamicAction",
  "AddCandidate",
  "RemoveCandidate",
  "MoveCandidate",
  "SetCandidateConditions",
}

for _, name in ipairs(MUTATORS) do
  local original = MM.DB[name]
  MM.DB[name] = function(...)
    Undo:BeforeMutation(name, ...)
    return original(...)
  end
end
