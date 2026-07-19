local ADDON_NAME, MM = ...

local DB = {}
MM.DB = DB
MM:RegisterModule("DB", DB)

-- Runtime-only UI selection. Never saved.
local session = {}

-- Slugify a display name into a unique key for `taken` (a map of existing ids).
local function uniqueId(name, fallback, taken)
  local base = string.gsub(string.lower(name or fallback), "[^%w]+", "_")
  base = string.gsub(base, "^_+", "")
  base = string.gsub(base, "_+$", "")
  if base == "" then
    base = fallback
  end

  local id, suffix = base, 2
  while taken[id] do
    id, suffix = base .. "_" .. suffix, suffix + 1
  end
  return id
end

-- Exposed for modules that insert entries directly (Share's import re-keying).
function DB:UniqueId(name, fallback, taken)
  return uniqueId(name, fallback, taken)
end

-- Find an entry id in `map` by exact id or case-insensitive name.
local function matchByName(map, target)
  if not target or target == "" then
    return nil
  end
  if map[target] then
    return target
  end
  for id, entry in pairs(map) do
    if string.lower(entry.name or id) == string.lower(target) then
      return id
    end
  end
  return nil
end

function DB:Initialize()
  -- Seed starter content only into a brand-new DB; structural defaults always
  -- merge. This keeps a deleted Core/profile from resurrecting on the next load.
  local fresh = MuscleMemoryDB == nil
  local savedSchemaVersion = MuscleMemoryDB and tonumber(MuscleMemoryDB.schemaVersion) or 0
  MuscleMemoryDB = MM.Tables.MergeDefaults(MuscleMemoryDB, MM.defaults)
  self:MigrateSchema(MuscleMemoryDB, savedSchemaVersion)
  if fresh then
    MuscleMemoryDB = MM.Tables.MergeDefaults(MuscleMemoryDB, MM.seed)
  end
  self.root = MuscleMemoryDB
end

function DB:MigrateSchema(root, savedSchemaVersion)
  if savedSchemaVersion < 2 then
    self:MigrateToV2(root)
  end
  if savedSchemaVersion < 3 then
    self:MigrateToV3(root)
  end
  if savedSchemaVersion < MM.SCHEMA_VERSION then
    root.schemaVersion = MM.SCHEMA_VERSION
  end
end

-- v1 → v2: the muscle pool, memory pool and fallback setting move from the
-- account root into each profile, so every profile is a self-contained data set.
-- The formerly shared pools are copied wholesale into every profile; the
-- per-muscle enable flag moves from the activeMuscles entry onto the muscle.
-- Keys here are the historical v1/v2 names ("muscles", "memories", ...) on
-- purpose; the v2 → v3 rename to "layers"/"dynamicActions" happens in MigrateToV3.
function DB:MigrateToV2(root)
  local legacyMuscles = root.muscles
  local legacyMemories = root.customMemories
  local legacyFallback = root.fallback
  if not (legacyMuscles or legacyMemories or legacyFallback ~= nil) then
    return -- fresh DB or already converted
  end

  for _, profile in pairs(root.profiles or {}) do
    profile.muscles = MM.Tables.DeepCopy(legacyMuscles or {})
    profile.memories = MM.Tables.DeepCopy(legacyMemories or {})
    profile.fallback = profile.fallback or legacyFallback or "keep"

    -- activeMuscles {id, enabled} -> muscleOrder (ids) + muscle.enabled.
    local order, seen = {}, {}
    for _, entry in ipairs(profile.activeMuscles or {}) do
      local muscle = profile.muscles[entry.id]
      if muscle and not seen[entry.id] then
        muscle.enabled = entry.enabled ~= false
        order[#order + 1] = entry.id
        seen[entry.id] = true
      end
    end
    -- Muscles copied in but not part of this profile stay visible but disabled,
    -- so what the profile applies is unchanged.
    for id, muscle in pairs(profile.muscles) do
      if not seen[id] then
        muscle.enabled = false
        order[#order + 1] = id
        seen[id] = true
      end
    end
    profile.muscleOrder = order
    profile.activeMuscles = nil

    -- Stored memory references: "standard" source -> "predefined".
    for _, muscle in pairs(profile.muscles) do
      for _, assignment in pairs(muscle.slots or {}) do
        if type(assignment) == "table" and assignment.type == "memory" and assignment.source == "standard" then
          assignment.source = "predefined"
        end
      end
    end
  end

  root.muscles = nil
  root.customMemories = nil
  root.fallback = nil
end

-- v2 → v3: terminology rename only. "muscles" become "action bar layers" and
-- "memories" become "dynamic actions". The persisted per-profile keys and the
-- slot-assignment discriminator are renamed in place so existing setups survive.
function DB:MigrateToV3(root)
  for _, profile in pairs(root.profiles or {}) do
    if profile.muscles ~= nil then
      profile.layers = profile.muscles
      profile.muscles = nil
    end
    if profile.memories ~= nil then
      profile.dynamicActions = profile.memories
      profile.memories = nil
    end
    if profile.muscleOrder ~= nil then
      profile.layerOrder = profile.muscleOrder
      profile.muscleOrder = nil
    end

    for _, layer in pairs(profile.layers or {}) do
      for _, assignment in pairs(layer.slots or {}) do
        if type(assignment) == "table" and assignment.type == "memory" then
          assignment.type = "dynamicaction"
        end
      end
    end
  end
end

function DB:GetRoot()
  return self.root or MuscleMemoryDB or {}
end

-- Profiles -----------------------------------------------------------------

-- The character's own profile choice, else the account default, self-healing
-- if either pointer is stale.
function DB:GetActiveProfileId()
  local root = self:GetRoot()
  local character = root.characterState[self:GetCharacterKey()]
  local choice = character and character.profile
  if choice and root.profiles[choice] then
    return choice
  end
  if root.profile and root.profiles[root.profile] then
    return root.profile
  end
  return next(root.profiles)
end

function DB:GetProfile(profileId)
  profileId = profileId or self:GetActiveProfileId()
  return self:GetRoot().profiles[profileId]
end

-- The given (or active) profile's layer pool / dynamicAction pool, ensure-initialized.
-- All layer and dynamicAction CRUD scopes through these, so it operates on the active
-- profile rather than a shared account-wide table.
function DB:Layers(profileId)
  local profile = self:GetProfile(profileId)
  if not profile then
    return {}
  end
  profile.layers = profile.layers or {}
  return profile.layers
end

function DB:DynamicActions(profileId)
  local profile = self:GetProfile(profileId)
  if not profile then
    return {}
  end
  profile.dynamicActions = profile.dynamicActions or {}
  return profile.dynamicActions
end

-- The account-wide default profile (what players use unless they pick their own),
-- self-healing if the stored pointer is stale.
function DB:GetGlobalProfileId()
  local root = self:GetRoot()
  if root.profile and root.profiles[root.profile] then
    return root.profile
  end
  return next(root.profiles)
end

function DB:SetGlobalProfile(profileId)
  if not self:GetRoot().profiles[profileId] then
    return false, "unknown profile"
  end
  self:GetRoot().profile = profileId
  return true
end

function DB:GetProfileList()
  local list = {}
  for id, profile in pairs(self:GetRoot().profiles) do
    list[#list + 1] = { id = id, name = profile.name or id }
  end
  -- Duplicate names are legal (ids are the identity), so tie-break on the id
  -- to keep the order stable across rebuilds.
  table.sort(list, function(left, right)
    if left.name ~= right.name then
      return left.name < right.name
    end
    return left.id < right.id
  end)
  return list
end

function DB:FindProfileId(target)
  return matchByName(self:GetRoot().profiles, target)
end

function DB:FindLayerId(target)
  return matchByName(self:Layers(), target)
end

-- A new profile starts empty: its own layers, dynamicActions and fallback.
function DB:CreateProfile(name)
  local root = self:GetRoot()
  local id = uniqueId(name, "profile", root.profiles)

  root.profiles[id] = {
    name = name and name ~= "" and name or ("Profile " .. (MM.Tables.Count(root.profiles) + 1)),
    fallback = "keep",
    layerOrder = {},
    layers = {},
    dynamicActions = {},
  }
  return id, root.profiles[id]
end

-- Clone an existing profile 1:1 (layers, dynamicActions, order and fallback) under a
-- new name, fully independent of the source.
function DB:CloneProfile(sourceId, name)
  local root = self:GetRoot()
  local source = self:GetProfile(sourceId)
  if not source then
    return nil, "unknown profile"
  end

  local id = uniqueId(name, "profile", root.profiles)
  root.profiles[id] = {
    name = name and name ~= "" and name or ((source.name or "Profile") .. " Copy"),
    fallback = source.fallback or "keep",
    layerOrder = MM.Tables.DeepCopy(source.layerOrder or {}),
    layers = MM.Tables.DeepCopy(source.layers or {}),
    dynamicActions = MM.Tables.DeepCopy(source.dynamicActions or {}),
  }
  return id, root.profiles[id]
end

function DB:RenameProfile(profileId, name)
  local profile = self:GetProfile(profileId)
  if not profile then
    return false, "unknown profile"
  end

  name = string.gsub(name or "", "^%s+", "")
  name = string.gsub(name, "%s+$", "")
  if name == "" then
    return false, "profile name cannot be empty"
  end

  profile.name = name
  return true
end

function DB:DeleteProfile(profileId)
  local root = self:GetRoot()
  if not root.profiles[profileId] then
    return false, "unknown profile"
  end
  if MM.Tables.Count(root.profiles) <= 1 then
    return false, "cannot delete the last profile"
  end

  root.profiles[profileId] = nil

  -- Repair dangling pointers so the global default and any character override
  -- never reference a deleted profile.
  if root.profile == profileId then
    root.profile = next(root.profiles)
  end
  for _, character in pairs(root.characterState or {}) do
    if character.profile == profileId then
      character.profile = nil
    end
  end

  return true
end

-- Set THIS character's profile choice. A nil id clears the choice, so the
-- character falls back to the account default.
function DB:SetActiveProfile(profileId)
  if profileId and not self:GetRoot().profiles[profileId] then
    return false, "unknown profile"
  end
  self:GetCharacterState().profile = profileId
  return true
end

-- Layers -------------------------------------------------------------------

-- Every layer in the profile, in stored order, each tagged with its enabled
-- state. Position in the list is the order.
function DB:GetProfileLayers(profileId)
  local profile = self:GetProfile(profileId)
  local list = {}
  if not profile then
    return list
  end

  for _, id in ipairs(profile.layerOrder or {}) do
    local layer = self:GetLayer(id, profileId)
    if layer then
      list[#list + 1] = {
        id = id,
        layer = layer,
        name = layer.name or id,
        enabled = layer.enabled ~= false,
      }
    end
  end

  return list
end

-- The enabled subset, in order. This is what gets applied.
function DB:GetActiveLayers(profileId)
  local active = {}
  for _, entry in ipairs(self:GetProfileLayers(profileId)) do
    if entry.enabled then
      active[#active + 1] = entry
    end
  end
  return active
end

function DB:SetLayerEnabled(layerId, enabled, profileId)
  local layer = self:GetLayer(layerId, profileId)
  if not layer then
    return false, "layer is not part of this profile"
  end
  layer.enabled = enabled and true or false
  return true
end

function DB:GetLayer(layerId, profileId)
  return self:Layers(profileId)[layerId]
end

function DB:CreateLayer(name)
  local layers = self:Layers()
  local layerId = uniqueId(name, "layer", layers)

  layers[layerId] = {
    name = name or ("Layer " .. tostring(MM.Tables.Count(layers) + 1)),
    slots = {},
    enabled = true,
  }

  local profile = self:GetProfile()
  if profile then
    profile.layerOrder = profile.layerOrder or {}
    profile.layerOrder[#profile.layerOrder + 1] = layerId
  end

  return layerId, layers[layerId]
end

function DB:RenameLayer(layerId, name)
  local layer = self:GetLayer(layerId)
  if not layer then
    return false, "unknown layer"
  end

  name = string.gsub(name or "", "^%s+", "")
  name = string.gsub(name, "%s+$", "")
  if name == "" then
    return false, "layer name cannot be empty"
  end

  layer.name = name
  return true
end

function DB:DeleteLayer(layerId)
  local layers = self:Layers()
  if not layers[layerId] then
    return false, "unknown layer"
  end
  if MM.Tables.Count(layers) <= 1 then
    return false, "cannot delete the last layer"
  end

  layers[layerId] = nil

  local profile = self:GetProfile()
  local order = profile and profile.layerOrder
  for index = #(order or {}), 1, -1 do
    if order[index] == layerId then
      table.remove(order, index)
    end
  end

  return true
end

-- Move `layerId` to position `toIndex` within `profileId` (defaults to the
-- active profile). Explicit inputs, single array splice, no selection read.
function DB:MoveLayer(layerId, toIndex, profileId)
  local profile = self:GetProfile(profileId)
  local order = profile and profile.layerOrder
  if not order then
    return false, "unknown profile"
  end

  toIndex = tonumber(toIndex)
  if not toIndex then
    return false, "needs a target position"
  end
  toIndex = math.max(1, math.min(toIndex, #order))

  local fromIndex
  for index, id in ipairs(order) do
    if id == layerId then
      fromIndex = index
      break
    end
  end

  if not fromIndex then
    return false, "layer is not part of this profile"
  end
  if fromIndex == toIndex then
    return false, "layer is already at that position"
  end

  table.insert(order, toIndex, table.remove(order, fromIndex))
  return true
end

function DB:SetSlot(layerId, slot, assignment)
  local layer = self:GetLayer(layerId)
  slot = tonumber(slot)
  if not layer or not MM.Actions.IsValidSlot(slot) then
    return false
  end

  layer.slots[slot] = assignment
  return true
end

function DB:SetAllLayerSlots(layerId, enabled)
  local layer = self:GetLayer(layerId)
  if not layer then
    return false
  end

  if enabled then
    for slot = 1, MM.MAX_ACTION_SLOT do
      if layer.slots[slot] == nil then
        layer.slots[slot] = { type = "empty" }
      end
    end
  else
    layer.slots = {}
  end

  return true
end

-- Selection (runtime only) -------------------------------------------------

function DB:GetSelectedLayerId()
  local layers = self:Layers()
  if session.layer and layers[session.layer] then
    return session.layer
  end
  session.layer = next(layers)
  return session.layer
end

function DB:SetSelectedLayerId(layerId)
  if self:Layers()[layerId] then
    session.layer = layerId
  end
end

function DB:GetSelectedSlot()
  return session.slot
end

function DB:SetSelectedSlot(slot)
  slot = tonumber(slot)
  session.slot = MM.Actions.IsValidSlot(slot) and slot or nil
end

-- Settings -----------------------------------------------------------------

function DB:GetFallback()
  local profile = self:GetProfile()
  return (profile and profile.fallback) or "keep"
end

function DB:SetFallback(value)
  if value ~= "keep" and value ~= "clear" then
    return false, "fallback must be keep or clear"
  end
  local profile = self:GetProfile()
  if not profile then
    return false, "no active profile"
  end
  profile.fallback = value
  return true
end

-- How the add-on reacts when a re-scan finds changes to apply. Stored per
-- profile alongside the fallback; defaults to the popup (the historical behavior).
local RESPONSES = { ignore = true, print = true, popup = true, apply = true }

function DB:GetResponse()
  local profile = self:GetProfile()
  return (profile and profile.response) or "popup"
end

function DB:SetResponse(value)
  if not RESPONSES[value] then
    return false, "response must be ignore, print, popup or apply"
  end
  local profile = self:GetProfile()
  if not profile then
    return false, "no active profile"
  end
  profile.response = value
  return true
end

-- How binding a spell or item that a dynamic action resolves to behaves:
-- "never" binds the capture as-is, "suggest" offers the dynamic action in a
-- popup, "auto" binds the dynamic action directly (asking only when several
-- match). An editing-behavior preference, so it lives on the account root
-- rather than per profile.
local SUGGEST_MODES = { never = true, suggest = true, auto = true }

function DB:GetSuggestMode()
  local value = self:GetRoot().suggestDynamicActions
  if SUGGEST_MODES[value] then
    return value
  end
  return "suggest"
end

function DB:SetSuggestMode(value)
  if not SUGGEST_MODES[value] then
    return false, "suggestion mode must be never, suggest or auto"
  end
  self:GetRoot().suggestDynamicActions = value
  return true
end

-- DynamicActions -------------------------------------------------------------------
-- Profile dynamicActions live in `profile.dynamicActions`; index `self:DynamicActions()` directly.
-- Predefined dynamicActions are immutable add-on data.

function DB:GetPredefinedDynamicAction(dynamicActionId)
  return (MM.PredefinedDynamicActions or {})[dynamicActionId]
end

-- Resolve a stored `{ source, id }` reference: "custom" -> the profile's own
-- dynamicAction, anything else (predefined) -> the built-in dynamicAction.
function DB:ResolveDynamicAction(reference)
  if not reference then
    return nil
  end

  if reference.source == "custom" then
    return self:DynamicActions()[reference.id]
  end

  return self:GetPredefinedDynamicAction(reference.id)
end

-- Copy a predefined dynamicAction into an editable profile dynamicAction. Returns the new key
-- (dynamicActions are identified by key, so duplicate names are fine).
function DB:CopyPredefinedDynamicAction(dynamicActionId, newId, newName)
  local source = (MM.PredefinedDynamicActions or {})[dynamicActionId]
  if not source then
    return nil, "unknown predefined dynamic action"
  end

  local dynamicActions = self:DynamicActions()
  local name = newName or (source.name .. " Copy")
  local key = newId or uniqueId(name, dynamicActionId .. "_copy", dynamicActions)
  if dynamicActions[key] then
    return nil, "dynamic action already exists"
  end

  local copy = MM.Tables.DeepCopy(source)
  copy.name = name
  dynamicActions[key] = copy
  return key
end

-- Clone any dynamicAction (predefined or profile) into a new editable profile dynamicAction.
function DB:CloneDynamicAction(reference)
  local source = self:ResolveDynamicAction(reference)
  if not source then
    return nil, "unknown dynamic action"
  end

  local dynamicActions = self:DynamicActions()
  local name = (source.name or "Dynamic Action") .. " Copy"
  local key = uniqueId(name, "dynamicaction_copy", dynamicActions)
  local copy = MM.Tables.DeepCopy(source)
  copy.name = name
  dynamicActions[key] = copy
  return key
end

-- Predefined dynamicActions are immutable add-on data, so create / rename / delete and
-- all candidate edits operate only on the profile's own dynamicActions.

function DB:CreateDynamicAction(name)
  local dynamicActions = self:DynamicActions()
  local key = uniqueId(name, "dynamicaction", dynamicActions)
  dynamicActions[key] = {
    name = name and name ~= "" and name or ("Dynamic Action " .. tostring(MM.Tables.Count(dynamicActions) + 1)),
    candidates = {},
  }
  return key, dynamicActions[key]
end

function DB:RenameDynamicAction(dynamicActionId, name)
  local dynamicAction = self:DynamicActions()[dynamicActionId]
  if not dynamicAction then
    return false, "only profile dynamic actions can be renamed"
  end

  name = string.gsub(name or "", "^%s+", "")
  name = string.gsub(name, "%s+$", "")
  if name == "" then
    return false, "dynamic action name cannot be empty"
  end

  dynamicAction.name = name
  return true
end

-- Switch a dynamicAction between "normal" (place the resolved action) and "macro"
-- (place a generated macro). Enabling macro mode seeds the default template once;
-- the template is kept when switching back so toggling never loses the user's body.
function DB:SetDynamicActionMode(dynamicActionId, mode)
  local dynamicAction = self:DynamicActions()[dynamicActionId]
  if not dynamicAction then
    return false, "only profile dynamic actions can be edited"
  end
  if mode ~= "normal" and mode ~= "macro" then
    return false, "mode must be normal or macro"
  end

  if mode == "macro" then
    dynamicAction.mode = "macro"
    if not dynamicAction.macroTemplate or dynamicAction.macroTemplate == "" then
      dynamicAction.macroTemplate = MM.MACRO_TEMPLATE_DEFAULT
    end
  else
    dynamicAction.mode = nil
  end
  return true
end

function DB:SetDynamicActionTemplate(dynamicActionId, template)
  local dynamicAction = self:DynamicActions()[dynamicActionId]
  if not dynamicAction then
    return false, "only profile dynamic actions can be edited"
  end

  template = tostring(template or "")
  if #template > MM.MACRO_TEMPLATE_LIMIT then
    template = template:sub(1, MM.MACRO_TEMPLATE_LIMIT)
  end
  dynamicAction.macroTemplate = template
  return true
end

-- Slots bound to the deleted dynamicAction simply stop resolving and fall through on the
-- next apply, so there's no reference cleanup to do.
function DB:DeleteDynamicAction(dynamicActionId)
  local dynamicActions = self:DynamicActions()
  if not dynamicActions[dynamicActionId] then
    return false, "unknown dynamic action"
  end

  dynamicActions[dynamicActionId] = nil
  return true
end

-- Candidates -----------------------------------------------------------------

-- Append a candidate (a captured assignment) to a profile dynamicAction.
function DB:AddCandidate(dynamicActionId, assignment)
  local dynamicAction = self:DynamicActions()[dynamicActionId]
  if not dynamicAction then
    return false, "only profile dynamic actions can be edited"
  end
  if not assignment or not assignment.type then
    return false, "no action to add"
  end

  dynamicAction.candidates = dynamicAction.candidates or {}
  dynamicAction.candidates[#dynamicAction.candidates + 1] = assignment
  return true
end

function DB:RemoveCandidate(dynamicActionId, index)
  local dynamicAction = self:DynamicActions()[dynamicActionId]
  if not dynamicAction then
    return false, "only profile dynamic actions can be edited"
  end

  index = tonumber(index)
  if not index or not dynamicAction.candidates or not dynamicAction.candidates[index] then
    return false, "no candidate at that position"
  end

  table.remove(dynamicAction.candidates, index)
  return true
end

-- Move the candidate at `fromIndex` to `toIndex` (clamped). Single splice, like
-- MoveLayer.
function DB:MoveCandidate(dynamicActionId, fromIndex, toIndex)
  local dynamicAction = self:DynamicActions()[dynamicActionId]
  local candidates = dynamicAction and dynamicAction.candidates
  if not candidates then
    return false, "only profile dynamic actions can be edited"
  end

  fromIndex = tonumber(fromIndex)
  toIndex = tonumber(toIndex)
  if not fromIndex or not toIndex or not candidates[fromIndex] then
    return false, "invalid candidate position"
  end
  toIndex = math.max(1, math.min(toIndex, #candidates))
  if fromIndex == toIndex then
    return false, "candidate is already at that position"
  end

  table.insert(candidates, toIndex, table.remove(candidates, fromIndex))
  return true
end

-- Character state ----------------------------------------------------------

function DB:GetCharacterKey()
  local name = UnitName("player") or "Unknown"
  local realm = GetRealmName and GetRealmName() or "Unknown"
  return realm .. "-" .. name
end

function DB:GetCharacterState()
  local root = self:GetRoot()
  local key = self:GetCharacterKey()
  root.characterState[key] = root.characterState[key] or {}
  return root.characterState[key]
end

-- Generated macros are physical, per-character resources, so the registry that
-- tracks them (keyed by layer + slot) lives in character state. Each record is
-- { name, scope, bodyHash, indexHint } — enough to find, reuse or delete the macro.
function DB:GetMacroRegistry()
  local state = self:GetCharacterState()
  state.macroRegistry = state.macroRegistry or {}
  return state.macroRegistry
end

function DB:GetMacroRecord(layerId, slot)
  local layer = self:GetMacroRegistry()[layerId]
  return layer and layer[tonumber(slot)]
end

function DB:SetMacroRecord(layerId, slot, record)
  local registry = self:GetMacroRegistry()
  registry[layerId] = registry[layerId] or {}
  registry[layerId][tonumber(slot)] = record
end
