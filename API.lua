local ADDON_NAME, MM = ...

--------------------------------------------------------------------------------
-- MuscleMemory public API
--
-- The global `MuscleMemory` lets macros and other add-ons do everything the
-- slash commands do, and more. Quick start:
--
--   /run local id = MuscleMemory.actions.create("Defensives")
--        MuscleMemory.actions.addCandidate(id, { type = "spell", id = 498 })
--
-- Conventions:
--   * Mutators return true, or false and a reason.
--   * Getters and creators return a value, or nil and a reason.
--   * Returned tables are snapshots: editing them changes nothing. Inputs are
--     checked and rejected with a reason, never stored half-valid.
--   * Ids are exact — no fuzzy name matching. list() shows ids; create() and
--     copy() return the new id.
--
-- Data shapes:
--   assignment = { type = "spell"|"item"|"mount"|"macro"|"battlepet"|"flyout"
--                        |"equipmentset"|"outfit"|"empty"|"ignore", id = n, ... }
--              | { type = "dynamicaction", source = "custom"|"predefined", id = actionId }
--   candidate  = an assignment (except dynamicaction/empty/ignore),
--                plus optional `conditions`
--   conditions = { classes|specs|roles|factions|races = { ... },
--                  levelMin = n, levelMax = n }
--------------------------------------------------------------------------------

local api = { apiVersion = 1 }
MM.API = api

-- Internal glue, defined at the end of this file; validation lives in
-- Util/Validate.lua.
local refresh, refreshing, validId, validLayer, actionRef

-- Profiles ---------------------------------------------------------------------

api.profiles = {
  -- list() -> { { profileId, name, active, default }, ... }
  -- Lists all profiles and marks the active and the account default one.
  list = function()
    local active, default = MM.DB:GetActiveProfileId(), MM.DB:GetGlobalProfileId()
    local list = {}
    for _, entry in ipairs(MM.DB:GetProfileList()) do
      list[#list + 1] = {
        profileId = entry.id,
        name = entry.name,
        active = entry.id == active,
        default = entry.id == default,
      }
    end
    return list
  end,

  -- getActiveId() -> profileId
  -- Returns the id of the profile active on this character.
  getActiveId = function()
    return MM.DB:GetActiveProfileId()
  end,

  -- get(profileId) -> profile
  -- Returns one profile's full definition.
  get = function(profileId)
    local ok, reason = validId(profileId, "profileId")
    if not ok then
      return nil, reason
    end
    local profile = MM.DB:GetRoot().profiles[profileId]
    if not profile then
      return nil, "unknown profile"
    end
    local result = MM.Tables.DeepCopy(profile)
    result.profileId = profileId
    return result
  end,

  -- create(name) -> profileId
  -- Creates a new empty profile.
  create = function(name)
    local profileId = MM.DB:CreateProfile(name)
    refresh()
    return profileId
  end,

  -- copy(profileId, name) -> profileId
  -- Duplicates a profile under a new name.
  copy = function(profileId, name)
    local newId, reason = MM.DB:CloneProfile(profileId, name)
    if not newId then
      return nil, reason
    end
    refresh()
    return newId
  end,

  -- rename(profileId, name)
  -- Renames a profile.
  rename = function(profileId, name)
    return refreshing(MM.DB:RenameProfile(profileId, name))
  end,

  -- delete(profileId)
  -- Deletes a profile.
  delete = function(profileId)
    return refreshing(MM.DB:DeleteProfile(profileId))
  end,

  -- setDefault(profileId)
  -- Sets the account-wide default profile.
  setDefault = function(profileId)
    return refreshing(MM.DB:SetGlobalProfile(profileId))
  end,

  -- setCharacter(profileId)
  -- Sets this character's profile; pass false to inherit the account default.
  -- nil is rejected on purpose: it is usually a failed lookup, not intent.
  setCharacter = function(profileId)
    if profileId == false then
      return refreshing(MM.DB:SetActiveProfile(nil))
    end
    local ok, reason = validId(profileId, "profileId")
    if not ok then
      return false, reason .. ", or false to inherit"
    end
    return refreshing(MM.DB:SetActiveProfile(profileId))
  end,
}

-- Layers of the currently active profile ---------------------------------------

api.layers = {
  -- list() -> { { layerId, name, enabled }, ... }
  -- Lists all layers in priority order.
  list = function()
    local list = {}
    for _, entry in ipairs(MM.DB:GetProfileLayers()) do
      list[#list + 1] = { layerId = entry.id, name = entry.name, enabled = entry.enabled }
    end
    return list
  end,

  -- get(layerId) -> layer
  -- Returns one layer including its slots and conditions.
  get = function(layerId)
    local layer, reason = validLayer(layerId)
    if not layer then
      return nil, reason
    end
    local result = MM.Tables.DeepCopy(layer)
    result.layerId = layerId
    return result
  end,

  -- create(name) -> layerId
  -- Creates a new empty layer.
  create = function(name)
    local layerId = MM.DB:CreateLayer(name)
    refresh()
    return layerId
  end,

  -- rename(layerId, name)
  -- Renames a layer.
  rename = function(layerId, name)
    return refreshing(MM.DB:RenameLayer(layerId, name))
  end,

  -- delete(layerId)
  -- Deletes a layer.
  delete = function(layerId)
    return refreshing(MM.DB:DeleteLayer(layerId))
  end,

  -- move(layerId, toIndex)
  -- Moves a layer to a new priority position. A no-op move is a success.
  move = function(layerId, toIndex)
    local ok, reason = MM.DB:MoveLayer(layerId, tonumber(toIndex))
    if not ok and reason == "layer is already at that position" then
      return true
    end
    return refreshing(ok, reason)
  end,

  -- setEnabled(layerId, enabled)
  -- Enables or disables a layer.
  setEnabled = function(layerId, enabled)
    if type(enabled) ~= "boolean" then
      return false, "enabled must be true or false"
    end
    return refreshing(MM.DB:SetLayerEnabled(layerId, enabled))
  end,

  -- setConditions(layerId, conditions)
  -- Sets when the layer applies (class, spec, level, ...).
  setConditions = function(layerId, conditions)
    local ok, idReason = validId(layerId, "layerId")
    if not ok then
      return false, idReason
    end
    local validated, reason = MM.Validate.Conditions(conditions or {})
    if not validated then
      return false, reason
    end
    return refreshing(MM.DB:SetLayerConditions(layerId, validated))
  end,

  -- getSlot(layerId, slot) -> assignment
  -- Returns the slot's assignment; nil = slot not managed by this layer.
  getSlot = function(layerId, slot)
    local layer, reason = validLayer(layerId)
    if not layer then
      return nil, reason
    end
    slot = tonumber(slot)
    if not MM.Actions.IsValidSlot(slot) then
      return nil, "slot must be 1-" .. MM.MAX_ACTION_SLOT
    end
    return MM.Tables.DeepCopy(layer.slots and layer.slots[slot])
  end,

  -- setSlot(layerId, slot, assignment)
  -- Assigns an action to a slot; nil assignment = stop managing the slot.
  setSlot = function(layerId, slot, assignment)
    local layer, layerReason = validLayer(layerId)
    if not layer then
      return false, layerReason
    end
    slot = tonumber(slot)
    if not MM.Actions.IsValidSlot(slot) then
      return false, "slot must be 1-" .. MM.MAX_ACTION_SLOT
    end
    local validated
    if assignment ~= nil then
      local reason
      validated, reason = MM.Validate.Assignment(assignment)
      if not validated then
        return false, reason
      end
    end
    return refreshing(MM.DB:SetSlot(layerId, slot, validated))
  end,

  -- setAllSlots(layerId, enabled)
  -- Manages every slot as Empty, or clears all managed slots.
  setAllSlots = function(layerId, enabled)
    if type(enabled) ~= "boolean" then
      return false, "enabled must be true or false"
    end
    return refreshing(MM.DB:SetAllLayerSlots(layerId, enabled))
  end,

  -- capture(layerId, slot)
  -- Captures one live action bar slot into the layer.
  capture = function(layerId, slot)
    local layer, reason = validLayer(layerId)
    if not layer then
      return false, reason
    end
    return refreshing(MM.Capture:CaptureSlot(layerId, tonumber(slot)))
  end,

  -- captureAll(layerId) -> capturedCount, failures
  -- Captures every filled action bar slot into the layer.
  captureAll = function(layerId)
    local layer, reason = validLayer(layerId)
    if not layer then
      return nil, reason
    end
    local captured, failures = MM.Capture:CaptureFilledSlots(layerId)
    refresh()
    return captured, MM.Tables.DeepCopy(failures)
  end,
}

-- Dynamic Actions of the currently active profile ------------------------------

api.actions = {
  -- list() -> { { actionId, source, name }, ... }
  -- Lists all dynamic actions, custom and predefined.
  list = function()
    local list = {}
    for actionId, action in pairs(MM.DB:DynamicActions()) do
      list[#list + 1] = { actionId = actionId, source = "custom", name = action.name or actionId }
    end
    for actionId, action in pairs(MM.PredefinedDynamicActions or {}) do
      list[#list + 1] = { actionId = actionId, source = "predefined", name = action.name or actionId }
    end
    table.sort(list, function(left, right)
      if left.source ~= right.source then
        return left.source == "custom"
      end
      return left.actionId < right.actionId
    end)
    return list
  end,

  -- get(actionId[, source]) -> action
  -- Returns one dynamic action's full definition. Without an explicit source
  -- ("custom" or "predefined"), custom actions are checked first.
  get = function(actionId, source)
    local ref, reason = actionRef(actionId, source)
    if not ref then
      return nil, reason
    end
    local result = MM.Tables.DeepCopy(MM.DB:ResolveDynamicAction(ref))
    result.actionId = ref.id
    result.source = ref.source
    return result
  end,

  -- create(name) -> actionId
  -- Creates a new empty custom dynamic action.
  create = function(name)
    local actionId = MM.DB:CreateDynamicAction(name)
    refresh()
    return actionId
  end,

  -- copy(actionId[, name][, source]) -> actionId
  -- Duplicates any dynamic action into an editable custom one.
  copy = function(actionId, name, source)
    local ref, reason = actionRef(actionId, source)
    if not ref then
      return nil, reason
    end
    local newId = MM.DB:CloneDynamicAction(ref)
    if name ~= nil then
      local ok, renameReason = MM.DB:RenameDynamicAction(newId, name)
      if not ok then
        MM.DB:DeleteDynamicAction(newId)
        return nil, renameReason
      end
    end
    refresh()
    return newId
  end,

  -- rename(actionId, name)
  -- Renames a custom dynamic action.
  rename = function(actionId, name)
    return refreshing(MM.DB:RenameDynamicAction(actionId, name))
  end,

  -- delete(actionId)
  -- Deletes a custom dynamic action.
  delete = function(actionId)
    return refreshing(MM.DB:DeleteDynamicAction(actionId))
  end,

  -- addCandidate(actionId, candidate[, index])
  -- Adds a candidate, at the end unless index is given.
  addCandidate = function(actionId, candidate, index)
    local validated, reason = MM.Validate.Candidate(candidate)
    if not validated then
      return false, reason
    end
    return refreshing(MM.DB:AddCandidate(actionId, validated, index))
  end,

  -- removeCandidate(actionId, index)
  -- Removes the candidate at index; later candidates shift down.
  removeCandidate = function(actionId, index)
    return refreshing(MM.DB:RemoveCandidate(actionId, index))
  end,

  -- moveCandidate(actionId, fromIndex, toIndex)
  -- Reorders candidates; earlier = higher priority.
  moveCandidate = function(actionId, fromIndex, toIndex)
    return refreshing(MM.DB:MoveCandidate(actionId, fromIndex, toIndex))
  end,

  -- setMacroMode(actionId, enabled)
  -- Toggles placing a generated macro instead of the resolved action.
  setMacroMode = function(actionId, enabled)
    if type(enabled) ~= "boolean" then
      return false, "enabled must be true or false"
    end
    return refreshing(MM.DB:SetDynamicActionMode(actionId, enabled and "macro" or "normal"))
  end,

  -- setMacroTemplate(actionId, template)
  -- Edits the generated macro's body template. Rejects oversized templates
  -- instead of silently truncating.
  setMacroTemplate = function(actionId, template)
    if type(template) ~= "string" then
      return false, "template must be a string"
    end
    if #template > MM.MACRO_TEMPLATE_LIMIT then
      return false, "template exceeds " .. MM.MACRO_TEMPLATE_LIMIT .. " characters"
    end
    return refreshing(MM.DB:SetDynamicActionTemplate(actionId, template))
  end,
}

-- Settings ---------------------------------------------------------------------

local CONFIG = {
  fallback = { get = "GetFallback", set = "SetFallback" },
  response = { get = "GetResponse", set = "SetResponse" },
  suggest = { get = "GetSuggestMode", set = "SetSuggestMode" },
}

api.config = {
  -- get(key) -> value
  -- Reads a setting: "fallback" | "response" | "suggest".
  get = function(key)
    local entry = CONFIG[key]
    if not entry then
      return nil, "unknown setting '" .. tostring(key) .. "'"
    end
    return MM.DB[entry.get](MM.DB)
  end,

  -- set(key, value)
  -- Changes a setting.
  set = function(key, value)
    local entry = CONFIG[key]
    if not entry then
      return false, "unknown setting '" .. tostring(key) .. "'"
    end
    return refreshing(MM.DB[entry.set](MM.DB, value))
  end,
}

-- Apply cycle ------------------------------------------------------------------

-- preview() -> { { slot, from, to }, ... }
-- Reports what applying would change, without touching the bars.
function api.preview()
  local plan, reason = MM.Applier:BuildPlan()
  if not plan then
    return nil, reason
  end

  local changes = {}
  for slot = 1, MM.MAX_ACTION_SLOT do
    local entry = plan.slots[slot]
    if entry then
      if
        entry.resolved
        and entry.resolved.pickupAvailable ~= false
        and not MM.Actions.IsResolvedInSlot(entry.resolved, slot)
      then
        changes[#changes + 1] =
          { slot = slot, from = MM.Actions.GetLiveActionLabel(slot), to = MM.Applier:DescribeTo(entry) }
      elseif not entry.resolved and entry.fallback == "clear" and HasAction and HasAction(slot) then
        changes[#changes + 1] = { slot = slot, from = MM.Actions.GetLiveActionLabel(slot), to = "empty" }
      end
    end
  end
  return changes
end

-- undo()
-- Reverts the most recent configuration change (session-only). Applying to the
-- bars is never undone.
function api.undo()
  return MM.Undo:Undo()
end

-- redo()
-- Restores the configuration change most recently undone.
function api.redo()
  return MM.Undo:Redo()
end

-- apply()
-- Applies the active profile to the action bars.
function api.apply()
  local ok, reason = MM.Applier:CanApply()
  if not ok then
    return false, reason
  end
  if MM.Applier:ApplyProfile() == true then
    return true
  end
  return false, "not everything could be applied (see chat output)"
end

-- Internals --------------------------------------------------------------------

refresh = function()
  if MM.UI and MM.UI.Refresh then
    MM.UI:Refresh()
  end
end

-- Wrap a mutator so a successful call refreshes an open UI.
refreshing = function(ok, reason)
  if ok then
    refresh()
  end
  return ok, reason
end

validId = function(value, what)
  if type(value) ~= "string" or value == "" then
    return false, what .. " must be an id string"
  end
  return true
end

validLayer = function(layerId)
  local ok, reason = validId(layerId, "layerId")
  if not ok then
    return nil, reason
  end
  local layer = MM.DB:GetLayer(layerId)
  if not layer then
    return nil, "unknown layer"
  end
  return layer
end

-- Resolve an actionId to its source pool: explicit source, else custom first
-- (mutations only ever touch custom, so your own actions shadow predefined ones).
actionRef = function(actionId, source)
  local ok, reason = validId(actionId, "actionId")
  if not ok then
    return nil, reason
  end
  if source ~= nil and source ~= "custom" and source ~= "predefined" then
    return nil, "source must be 'custom' or 'predefined'"
  end
  for _, pool in ipairs(source and { source } or { "custom", "predefined" }) do
    if MM.DB:ResolveDynamicAction({ source = pool, id = actionId }) then
      return { source = pool, id = actionId }
    end
  end
  return nil, "unknown dynamic action"
end

MuscleMemory = api
