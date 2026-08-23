local ADDON_NAME, MM = ...

local DB = {}
MM.DB = DB
MM:RegisterModule("DB", DB)

-- Runtime-only UI selection. Never saved.
local session = {}

-- The layer every new profile starts with, matching the fresh-install seed.
local STARTER_LAYER = "Core"

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
  if savedSchemaVersion < 4 then
    self:MigrateToV4(root)
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
-- purpose; the v2 → v3 rename to "layers"/"actions" happens in MigrateToV3.
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
-- "memories" become "smart actions". The persisted per-profile keys and the
-- slot-assignment discriminator are renamed in place so existing setups survive.
function DB:MigrateToV3(root)
  for _, profile in pairs(root.profiles or {}) do
    if profile.muscles ~= nil then
      profile.layers = profile.muscles
      profile.muscles = nil
    end
    if profile.memories ~= nil then
      profile.actions = profile.memories
      profile.memories = nil
    end
    if profile.muscleOrder ~= nil then
      profile.layerOrder = profile.muscleOrder
      profile.muscleOrder = nil
    end

    for _, layer in pairs(profile.layers or {}) do
      for _, assignment in pairs(layer.slots or {}) do
        if type(assignment) == "table" and assignment.type == "memory" then
          assignment.type = "action"
        end
      end
    end
  end
end

-- v3 → v4: terminology rename only. "dynamic actions" become "smart actions",
-- and the persisted names drop the adjective, so renaming the concept again
-- needs no migration: the pool is `profile.actions`, the discriminator "action".
function DB:MigrateToV4(root)
  for _, profile in pairs(root.profiles or {}) do
    if profile.dynamicActions ~= nil then
      profile.actions = profile.dynamicActions
      profile.dynamicActions = nil
    end

    for _, layer in pairs(profile.layers or {}) do
      for _, assignment in pairs(layer.slots or {}) do
        if type(assignment) == "table" and assignment.type == "dynamicaction" then
          assignment.type = "action"
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

-- The given (or active) profile's layer pool / smartAction pool, ensure-initialized.
-- All layer and smartAction CRUD scopes through these, so it operates on the active
-- profile rather than a shared account-wide table.
function DB:Layers(profileId)
  local profile = self:GetProfile(profileId)
  if not profile then
    return {}
  end
  profile.layers = profile.layers or {}
  return profile.layers
end

function DB:SmartActions(profileId)
  local profile = self:GetProfile(profileId)
  if not profile then
    return {}
  end
  profile.actions = profile.actions or {}
  return profile.actions
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

-- Account-wide, and outside the undo snapshot: it records what the player has
-- been shown, not configuration.
function DB:HasSeenTutorial()
  return self:GetRoot().tutorialSeen == true
end

function DB:MarkTutorialSeen()
  self:GetRoot().tutorialSeen = true
end

-- Starts with one empty layer so there is somewhere to capture into. Import
-- passes `bare`: the package brings its own, and a stray empty one would just
-- sit underneath them.
function DB:CreateProfile(name, opts)
  local root = self:GetRoot()
  local id = uniqueId(name, "profile", root.profiles)

  local profile = {
    name = name and name ~= "" and name or ("Profile " .. (MM.Tables.Count(root.profiles) + 1)),
    fallback = "keep",
    layerOrder = {},
    layers = {},
    actions = {},
  }
  root.profiles[id] = profile

  if not (opts and opts.bare) then
    local layerId = uniqueId(STARTER_LAYER, "layer", profile.layers)
    profile.layers[layerId] = { name = STARTER_LAYER, slots = {}, enabled = true }
    profile.layerOrder[1] = layerId
  end

  return id, profile
end

-- Clone an existing profile 1:1 (layers, actions, order and fallback) under a
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
    actions = MM.Tables.DeepCopy(source.actions or {}),
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

-- `index` places the layer at that position in the stack (1 is the top, which
-- wins at apply time); out-of-range and nil append, so callers that don't care
-- about position keep the old behaviour.
function DB:CreateLayer(name, index)
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
    local last = #profile.layerOrder + 1
    table.insert(profile.layerOrder, math.min(math.max(tonumber(index) or last, 1), last), layerId)
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

-- Replace a layer's conditions wholesale. The editor works on a scratch copy
-- and commits it through here, so config mutations stay inside DB.
function DB:SetLayerConditions(layerId, conditions)
  local layer = self:GetLayer(layerId)
  if not layer then
    return false, "unknown layer"
  end
  layer.conditions = conditions
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
  -- Heal to the top of the stack, not to whatever `pairs` yields first: a stale
  -- selection otherwise lands on a layer unrelated to what the player sees.
  local ordered = self:GetProfileLayers()
  session.layer = ordered[1] and ordered[1].id or next(layers)
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

function DB:SetFallback(value, profileId)
  if value ~= "keep" and value ~= "clear" then
    return false, "fallback must be keep or clear"
  end
  local profile = self:GetProfile(profileId)
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

function DB:SetResponse(value, profileId)
  if not RESPONSES[value] then
    return false, "response must be ignore, print, popup or apply"
  end
  local profile = self:GetProfile(profileId)
  if not profile then
    return false, "no active profile"
  end
  profile.response = value
  return true
end

-- How binding a spell or item that a smart action resolves to behaves:
-- "never" binds the capture as-is, "suggest" offers the smart action in a
-- popup, "auto" binds the smart action directly (asking only when several
-- match). An editing-behavior preference, so it lives on the account root
-- rather than per profile.
local SUGGEST_MODES = { never = true, suggest = true, auto = true }

function DB:GetSuggestMode()
  local value = self:GetRoot().suggestSmartActions
  if SUGGEST_MODES[value] then
    return value
  end
  return "suggest"
end

function DB:SetSuggestMode(value)
  if not SUGGEST_MODES[value] then
    return false, "suggestion mode must be never, suggest or auto"
  end
  self:GetRoot().suggestSmartActions = value
  return true
end

-- SmartActions -------------------------------------------------------------------
-- Profile actions live in `profile.actions`; index `self:SmartActions()` directly.
-- Predefined actions are immutable add-on data.

function DB:GetPredefinedSmartAction(smartActionId)
  return (MM.PredefinedSmartActions or {})[smartActionId]
end

-- Resolve a stored `{ source, id }` reference: "custom" -> the profile's own
-- smartAction, anything else (predefined) -> the built-in smartAction.
function DB:ResolveSmartAction(reference)
  if not reference then
    return nil
  end

  if reference.source == "custom" then
    return self:SmartActions()[reference.id]
  end

  return self:GetPredefinedSmartAction(reference.id)
end

-- Copy a predefined smartAction into an editable profile smartAction. Returns the new key
-- (actions are identified by key, so duplicate names are fine).
function DB:CopyPredefinedSmartAction(smartActionId, newId, newName)
  local source = (MM.PredefinedSmartActions or {})[smartActionId]
  if not source then
    return nil, "unknown predefined smart action"
  end

  local actions = self:SmartActions()
  local name = newName or string.format(MM.L["%s Copy"], source.name)
  local key = newId or uniqueId(name, smartActionId .. "_copy", actions)
  if actions[key] then
    return nil, "smart action already exists"
  end

  local copy = MM.Tables.DeepCopy(source)
  copy.name = name
  actions[key] = copy
  return key
end

-- Clone any smartAction (predefined or profile) into a new editable profile smartAction.
function DB:CloneSmartAction(reference)
  local source = self:ResolveSmartAction(reference)
  if not source then
    return nil, "unknown smart action"
  end

  local actions = self:SmartActions()
  local name = string.format(MM.L["%s Copy"], source.name or MM.L["Smart Action"])
  local key = uniqueId(name, "action_copy", actions)
  local copy = MM.Tables.DeepCopy(source)
  copy.name = name
  actions[key] = copy
  return key
end

-- Predefined actions are immutable add-on data, so create / rename / delete and
-- all candidate edits operate only on the profile's own actions.

-- Adoption: the import door. Insert a fully-formed table under a key the caller
-- has already uniqued (imports allocate all keys up front so cross-references
-- can be rewritten before anything is stored).
-- Every smart action is named, so anything downstream (the macro namer, the
-- rail) can rely on it. Stored once, so switching language never renames one.
local function defaultSmartActionName(actions)
  return string.format(MM.L["Smart Action %d"], MM.Tables.Count(actions) + 1)
end

function DB:AdoptSmartAction(profileId, key, action)
  local actions = self:SmartActions(profileId)
  if not self:GetProfile(profileId) then
    return nil, "unknown profile"
  end
  if actions[key] then
    return nil, "smart action already exists"
  end
  -- A sharing string is untrusted: name an unnamed action here rather than
  -- letting a nameless one reach the macro namer.
  if type(action.name) ~= "string" or action.name == "" then
    action.name = defaultSmartActionName(actions)
  end
  actions[key] = action
  return key
end

-- Adopt a fully-formed layer: stored under a fresh key and appended below the
-- existing layers.
function DB:AdoptLayer(profileId, layer)
  local profile = self:GetProfile(profileId)
  if not profile then
    return nil, "unknown profile"
  end
  local layers = self:Layers(profileId)
  local key = uniqueId(layer.name, "layer", layers)
  layers[key] = layer
  profile.layerOrder = profile.layerOrder or {}
  profile.layerOrder[#profile.layerOrder + 1] = key
  return key
end

function DB:CreateSmartAction(name)
  local actions = self:SmartActions()
  local key = uniqueId(name, "action", actions)
  actions[key] = {
    name = name and name ~= "" and name or defaultSmartActionName(actions),
    candidates = {},
  }
  return key, actions[key]
end

function DB:RenameSmartAction(smartActionId, name)
  local smartAction = self:SmartActions()[smartActionId]
  if not smartAction then
    return false, "only profile smart actions can be renamed"
  end

  name = string.gsub(name or "", "^%s+", "")
  name = string.gsub(name, "%s+$", "")
  if name == "" then
    return false, "smart action name cannot be empty"
  end

  smartAction.name = name
  return true
end

-- Switch a smartAction between "normal" (place the resolved action) and "macro"
-- (place a generated macro). Enabling macro mode seeds the default template once;
-- the template is kept when switching back so toggling never loses the user's body.
function DB:SetSmartActionMode(smartActionId, mode)
  local smartAction = self:SmartActions()[smartActionId]
  if not smartAction then
    return false, "only profile smart actions can be edited"
  end
  if mode ~= "normal" and mode ~= "macro" then
    return false, "mode must be normal or macro"
  end

  if mode == "macro" then
    smartAction.mode = "macro"
    if not smartAction.macroTemplate or smartAction.macroTemplate == "" then
      smartAction.macroTemplate = MM.MACRO_TEMPLATE_DEFAULT
    end
  else
    smartAction.mode = nil
  end
  return true
end

function DB:SetSmartActionTemplate(smartActionId, template)
  local smartAction = self:SmartActions()[smartActionId]
  if not smartAction then
    return false, "only profile smart actions can be edited"
  end

  -- The limit is bytes, so cut on a character boundary — a raw sub would leave
  -- half a multi-byte character behind.
  template = MM.Macros.TruncateBytes(tostring(template or ""), MM.MACRO_TEMPLATE_LIMIT)
  smartAction.macroTemplate = template
  return true
end

-- Slots bound to the deleted smartAction simply stop resolving and fall through on the
-- next apply, so there's no reference cleanup to do.
function DB:DeleteSmartAction(smartActionId)
  local actions = self:SmartActions()
  if not actions[smartActionId] then
    return false, "unknown smart action"
  end

  actions[smartActionId] = nil
  return true
end

-- Candidates -----------------------------------------------------------------

-- Add a candidate (a captured assignment) to a profile smartAction, at `index`
-- (clamped) or appended when no index is given.
function DB:AddCandidate(smartActionId, assignment, index)
  local smartAction = self:SmartActions()[smartActionId]
  if not smartAction then
    return false, "only profile smart actions can be edited"
  end
  if not assignment or not assignment.type then
    return false, "no action to add"
  end

  smartAction.candidates = smartAction.candidates or {}
  index = math.max(1, math.min(tonumber(index) or (#smartAction.candidates + 1), #smartAction.candidates + 1))
  table.insert(smartAction.candidates, index, assignment)
  return true
end

function DB:RemoveCandidate(smartActionId, index)
  local smartAction = self:SmartActions()[smartActionId]
  if not smartAction then
    return false, "only profile smart actions can be edited"
  end

  index = tonumber(index)
  if not index or not smartAction.candidates or not smartAction.candidates[index] then
    return false, "no candidate at that position"
  end

  table.remove(smartAction.candidates, index)
  return true
end

-- Replace a candidate's conditions wholesale (scratch-copy commit, like
-- SetLayerConditions).
function DB:SetCandidateConditions(smartActionId, index, conditions)
  local smartAction = self:SmartActions()[smartActionId]
  if not smartAction then
    return false, "only profile smart actions can be edited"
  end

  index = tonumber(index)
  local candidate = index and smartAction.candidates and smartAction.candidates[index]
  if not candidate then
    return false, "no candidate at that position"
  end

  candidate.conditions = conditions
  return true
end

-- Move the candidate at `fromIndex` to `toIndex` (clamped). Single splice, like
-- MoveLayer.
function DB:MoveCandidate(smartActionId, fromIndex, toIndex)
  local smartAction = self:SmartActions()[smartActionId]
  local candidates = smartAction and smartAction.candidates
  if not candidates then
    return false, "only profile smart actions can be edited"
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
