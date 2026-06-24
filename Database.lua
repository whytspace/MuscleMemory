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
  if savedSchemaVersion < MM.SCHEMA_VERSION then
    root.schemaVersion = MM.SCHEMA_VERSION
  end
end

-- v1 → v2: muscles, memories and the fallback setting move from the account
-- root into each profile, so every profile is a self-contained data set. The
-- formerly shared pools are copied wholesale into every profile; the per-muscle
-- enable flag moves from the activeMuscles entry onto the muscle itself.
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

-- The given (or active) profile's muscle pool / memory pool, ensure-initialized.
-- All muscle and memory CRUD scopes through these, so it operates on the active
-- profile rather than a shared account-wide table.
function DB:Muscles(profileId)
  local profile = self:GetProfile(profileId)
  if not profile then
    return {}
  end
  profile.muscles = profile.muscles or {}
  return profile.muscles
end

function DB:Memories(profileId)
  local profile = self:GetProfile(profileId)
  if not profile then
    return {}
  end
  profile.memories = profile.memories or {}
  return profile.memories
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
  table.sort(list, function(left, right)
    return left.name < right.name
  end)
  return list
end

function DB:FindProfileId(target)
  return matchByName(self:GetRoot().profiles, target)
end

function DB:FindMuscleId(target)
  return matchByName(self:Muscles(), target)
end

-- A new profile starts empty: its own muscles, memories and fallback.
function DB:CreateProfile(name)
  local root = self:GetRoot()
  local id = uniqueId(name, "profile", root.profiles)

  root.profiles[id] = {
    name = name and name ~= "" and name or ("Profile " .. (MM.Tables.Count(root.profiles) + 1)),
    fallback = "keep",
    muscleOrder = {},
    muscles = {},
    memories = {},
  }
  return id, root.profiles[id]
end

-- Clone an existing profile 1:1 (muscles, memories, order and fallback) under a
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
    muscleOrder = MM.Tables.DeepCopy(source.muscleOrder or {}),
    muscles = MM.Tables.DeepCopy(source.muscles or {}),
    memories = MM.Tables.DeepCopy(source.memories or {}),
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

-- Muscles -------------------------------------------------------------------

-- Every muscle in the profile, in stored order, each tagged with its enabled
-- state. Position in the list is the order.
function DB:GetProfileMuscles(profileId)
  local profile = self:GetProfile(profileId)
  local list = {}
  if not profile then
    return list
  end

  for _, id in ipairs(profile.muscleOrder or {}) do
    local muscle = self:GetMuscle(id, profileId)
    if muscle then
      list[#list + 1] = {
        id = id,
        muscle = muscle,
        name = muscle.name or id,
        enabled = muscle.enabled ~= false,
      }
    end
  end

  return list
end

-- The enabled subset, in order. This is what gets applied.
function DB:GetActiveMuscles(profileId)
  local active = {}
  for _, entry in ipairs(self:GetProfileMuscles(profileId)) do
    if entry.enabled then
      active[#active + 1] = entry
    end
  end
  return active
end

function DB:SetMuscleEnabled(muscleId, enabled, profileId)
  local muscle = self:GetMuscle(muscleId, profileId)
  if not muscle then
    return false, "muscle is not part of this profile"
  end
  muscle.enabled = enabled and true or false
  return true
end

function DB:GetMuscle(muscleId, profileId)
  return self:Muscles(profileId)[muscleId]
end

function DB:CreateMuscle(name)
  local muscles = self:Muscles()
  local muscleId = uniqueId(name, "muscle", muscles)

  muscles[muscleId] = {
    name = name or ("Muscle " .. tostring(MM.Tables.Count(muscles) + 1)),
    slots = {},
    enabled = true,
  }

  local profile = self:GetProfile()
  if profile then
    profile.muscleOrder = profile.muscleOrder or {}
    profile.muscleOrder[#profile.muscleOrder + 1] = muscleId
  end

  return muscleId, muscles[muscleId]
end

function DB:RenameMuscle(muscleId, name)
  local muscle = self:GetMuscle(muscleId)
  if not muscle then
    return false, "unknown muscle"
  end

  name = string.gsub(name or "", "^%s+", "")
  name = string.gsub(name, "%s+$", "")
  if name == "" then
    return false, "muscle name cannot be empty"
  end

  muscle.name = name
  return true
end

function DB:DeleteMuscle(muscleId)
  local muscles = self:Muscles()
  if not muscles[muscleId] then
    return false, "unknown muscle"
  end
  if MM.Tables.Count(muscles) <= 1 then
    return false, "cannot delete the last muscle"
  end

  muscles[muscleId] = nil

  local profile = self:GetProfile()
  local order = profile and profile.muscleOrder
  for index = #(order or {}), 1, -1 do
    if order[index] == muscleId then
      table.remove(order, index)
    end
  end

  return true
end

-- Move `muscleId` to position `toIndex` within `profileId` (defaults to the
-- active profile). Explicit inputs, single array splice, no selection read.
function DB:MoveMuscle(muscleId, toIndex, profileId)
  local profile = self:GetProfile(profileId)
  local order = profile and profile.muscleOrder
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
    if id == muscleId then
      fromIndex = index
      break
    end
  end

  if not fromIndex then
    return false, "muscle is not part of this profile"
  end
  if fromIndex == toIndex then
    return false, "muscle is already at that position"
  end

  table.insert(order, toIndex, table.remove(order, fromIndex))
  return true
end

function DB:SetSlot(muscleId, slot, assignment)
  local muscle = self:GetMuscle(muscleId)
  slot = tonumber(slot)
  if not muscle or not MM.Actions.IsValidSlot(slot) then
    return false
  end

  muscle.slots[slot] = assignment
  return true
end

function DB:SetAllMuscleSlots(muscleId, enabled)
  local muscle = self:GetMuscle(muscleId)
  if not muscle then
    return false
  end

  if enabled then
    for slot = 1, MM.MAX_ACTION_SLOT do
      if muscle.slots[slot] == nil then
        muscle.slots[slot] = { type = "empty" }
      end
    end
  else
    muscle.slots = {}
  end

  return true
end

-- Selection (runtime only) -------------------------------------------------

function DB:GetSelectedMuscleId()
  local muscles = self:Muscles()
  if session.muscle and muscles[session.muscle] then
    return session.muscle
  end
  session.muscle = next(muscles)
  return session.muscle
end

function DB:SetSelectedMuscleId(muscleId)
  if self:Muscles()[muscleId] then
    session.muscle = muscleId
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

-- Memories -------------------------------------------------------------------
-- Profile memories live in `profile.memories`; index `self:Memories()` directly.
-- Predefined memories are immutable add-on data.

function DB:GetPredefinedMemory(memoryId)
  return MM.PredefinedMemories[memoryId]
end

-- Resolve a stored `{ source, id }` reference: "custom" -> the profile's own
-- memory, anything else (predefined) -> the built-in memory.
function DB:ResolveMemory(reference)
  if not reference then
    return nil
  end

  if reference.source == "custom" then
    return self:Memories()[reference.id]
  end

  return self:GetPredefinedMemory(reference.id)
end

-- Copy a predefined memory into an editable profile memory. Returns the new key
-- (memories are identified by key, so duplicate names are fine).
function DB:CopyPredefinedMemory(memoryId, newId, newName)
  local source = MM.PredefinedMemories[memoryId]
  if not source then
    return nil, "unknown predefined memory"
  end

  local memories = self:Memories()
  local name = newName or (source.name .. " Copy")
  local key = newId or uniqueId(name, memoryId .. "_copy", memories)
  if memories[key] then
    return nil, "memory already exists"
  end

  local copy = MM.Tables.DeepCopy(source)
  copy.name = name
  memories[key] = copy
  return key
end

-- Clone any memory (predefined or profile) into a new editable profile memory.
function DB:CloneMemory(reference)
  local source = self:ResolveMemory(reference)
  if not source then
    return nil, "unknown memory"
  end

  local memories = self:Memories()
  local name = (source.name or "Memory") .. " Copy"
  local key = uniqueId(name, "memory_copy", memories)
  local copy = MM.Tables.DeepCopy(source)
  copy.name = name
  memories[key] = copy
  return key
end

-- Predefined memories are immutable add-on data, so create / rename / delete and
-- all candidate edits operate only on the profile's own memories.

function DB:CreateMemory(name)
  local memories = self:Memories()
  local key = uniqueId(name, "memory", memories)
  memories[key] = {
    name = name and name ~= "" and name or ("Memory " .. tostring(MM.Tables.Count(memories) + 1)),
    candidates = {},
  }
  return key, memories[key]
end

function DB:RenameMemory(memoryId, name)
  local memory = self:Memories()[memoryId]
  if not memory then
    return false, "only profile memories can be renamed"
  end

  name = string.gsub(name or "", "^%s+", "")
  name = string.gsub(name, "%s+$", "")
  if name == "" then
    return false, "memory name cannot be empty"
  end

  memory.name = name
  return true
end

-- Slots bound to the deleted memory simply stop resolving and fall through on the
-- next apply, so there's no reference cleanup to do.
function DB:DeleteMemory(memoryId)
  local memories = self:Memories()
  if not memories[memoryId] then
    return false, "unknown memory"
  end

  memories[memoryId] = nil
  return true
end

-- Candidates -----------------------------------------------------------------

-- Append a candidate (a captured assignment) to a profile memory.
function DB:AddCandidate(memoryId, assignment)
  local memory = self:Memories()[memoryId]
  if not memory then
    return false, "only profile memories can be edited"
  end
  if not assignment or not assignment.type then
    return false, "no action to add"
  end

  memory.candidates = memory.candidates or {}
  memory.candidates[#memory.candidates + 1] = assignment
  return true
end

function DB:RemoveCandidate(memoryId, index)
  local memory = self:Memories()[memoryId]
  if not memory then
    return false, "only profile memories can be edited"
  end

  index = tonumber(index)
  if not index or not memory.candidates or not memory.candidates[index] then
    return false, "no candidate at that position"
  end

  table.remove(memory.candidates, index)
  return true
end

-- Move the candidate at `fromIndex` to `toIndex` (clamped). Single splice, like
-- MoveMuscle.
function DB:MoveCandidate(memoryId, fromIndex, toIndex)
  local memory = self:Memories()[memoryId]
  local candidates = memory and memory.candidates
  if not candidates then
    return false, "only profile memories can be edited"
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
