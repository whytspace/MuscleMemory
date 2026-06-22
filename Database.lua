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
  MuscleMemoryDB = MM.Tables.MergeDefaults(MuscleMemoryDB, MM.defaults)
  if fresh then
    MuscleMemoryDB = MM.Tables.MergeDefaults(MuscleMemoryDB, MM.seed)
  end
  self.root = MuscleMemoryDB
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
  return matchByName(self:GetRoot().muscles, target)
end

-- A new profile copies the active profile's muscle selection, so it starts as a
-- variation of your current setup.
function DB:CreateProfile(name)
  local root = self:GetRoot()
  local id = uniqueId(name, "profile", root.profiles)
  local source = self:GetProfile()

  root.profiles[id] = {
    name = name and name ~= "" and name or ("Profile " .. (MM.Tables.Count(root.profiles) + 1)),
    activeMuscles = MM.Tables.DeepCopy(source and source.activeMuscles or {}),
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

  for _, entry in ipairs(profile.activeMuscles or {}) do
    local muscle = self:GetMuscle(entry.id)
    if muscle then
      list[#list + 1] = {
        id = entry.id,
        muscle = muscle,
        name = muscle.name or entry.id,
        enabled = entry.enabled ~= false,
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
  local profile = self:GetProfile(profileId)
  for _, entry in ipairs(profile and profile.activeMuscles or {}) do
    if entry.id == muscleId then
      entry.enabled = enabled and true or false
      return true
    end
  end
  return false, "muscle is not part of this profile"
end

function DB:GetMuscle(muscleId)
  return self:GetRoot().muscles[muscleId]
end

function DB:CreateMuscle(name)
  local root = self:GetRoot()
  local muscleId = uniqueId(name, "muscle", root.muscles)

  root.muscles[muscleId] = {
    name = name or ("Muscle " .. tostring(MM.Tables.Count(root.muscles) + 1)),
    slots = {},
  }

  local profile = self:GetProfile()
  if profile then
    profile.activeMuscles = profile.activeMuscles or {}
    profile.activeMuscles[#profile.activeMuscles + 1] = { id = muscleId, enabled = true }
  end

  return muscleId, root.muscles[muscleId]
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
  local root = self:GetRoot()
  if not root.muscles[muscleId] then
    return false, "unknown muscle"
  end
  if MM.Tables.Count(root.muscles or {}) <= 1 then
    return false, "cannot delete the last muscle"
  end

  root.muscles[muscleId] = nil

  for _, profile in pairs(root.profiles or {}) do
    for index = #(profile.activeMuscles or {}), 1, -1 do
      if profile.activeMuscles[index].id == muscleId then
        table.remove(profile.activeMuscles, index)
      end
    end
  end

  return true
end

-- Move `muscleId` to position `toIndex` within `profileId` (defaults to the
-- active profile). Explicit inputs, single array splice, no selection read.
function DB:MoveMuscle(muscleId, toIndex, profileId)
  local profile = self:GetProfile(profileId)
  local muscles = profile and profile.activeMuscles
  if not muscles then
    return false, "unknown profile"
  end

  toIndex = tonumber(toIndex)
  if not toIndex then
    return false, "needs a target position"
  end
  toIndex = math.max(1, math.min(toIndex, #muscles))

  local fromIndex
  for index, entry in ipairs(muscles) do
    if entry.id == muscleId then
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

  table.insert(muscles, toIndex, table.remove(muscles, fromIndex))
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
  local root = self:GetRoot()
  if session.muscle and root.muscles[session.muscle] then
    return session.muscle
  end
  session.muscle = next(root.muscles)
  return session.muscle
end

function DB:SetSelectedMuscleId(muscleId)
  if self:GetRoot().muscles[muscleId] then
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
  return self:GetRoot().fallback or "keep"
end

function DB:SetFallback(value)
  if value ~= "keep" and value ~= "clear" then
    return false, "fallback must be keep or clear"
  end
  self:GetRoot().fallback = value
  return true
end

-- Memories -------------------------------------------------------------------

function DB:GetCustomMemory(memoryId)
  return self:GetRoot().customMemories[memoryId]
end

function DB:GetMemory(reference)
  if not reference then
    return nil
  end

  if reference.source == "custom" then
    return self:GetCustomMemory(reference.id)
  end

  return MM.StandardMemories[reference.id]
end

-- Copy a standard memory into an editable custom memory. Returns the new key
-- (memories are identified by key, so duplicate names are fine).
function DB:CopyStandardMemory(memoryId, newId, newName)
  local source = MM.StandardMemories[memoryId]
  if not source then
    return nil, "unknown standard memory"
  end

  local root = self:GetRoot()
  local name = newName or (source.name .. " Copy")
  local key = newId or uniqueId(name, memoryId .. "_copy", root.customMemories)
  if root.customMemories[key] then
    return nil, "custom memory already exists"
  end

  local copy = MM.Tables.DeepCopy(source)
  copy.name = name
  root.customMemories[key] = copy
  return key
end

-- Clone any memory (standard or custom) into a new editable custom memory.
function DB:CloneMemory(reference)
  local source = self:GetMemory(reference)
  if not source then
    return nil, "unknown memory"
  end

  local root = self:GetRoot()
  local name = (source.name or "Memory") .. " Copy"
  local key = uniqueId(name, "memory_copy", root.customMemories)
  local copy = MM.Tables.DeepCopy(source)
  copy.name = name
  root.customMemories[key] = copy
  return key
end

-- Standard memories are immutable add-on data, so create / rename / delete and
-- all candidate edits operate only on custom memories.

function DB:CreateMemory(name)
  local root = self:GetRoot()
  local key = uniqueId(name, "memory", root.customMemories)
  root.customMemories[key] = {
    name = name and name ~= "" and name or ("Memory " .. tostring(MM.Tables.Count(root.customMemories) + 1)),
    candidates = {},
  }
  return key, root.customMemories[key]
end

function DB:RenameMemory(memoryId, name)
  local memory = self:GetCustomMemory(memoryId)
  if not memory then
    return false, "only custom memories can be renamed"
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
  local root = self:GetRoot()
  if not root.customMemories[memoryId] then
    return false, "unknown custom memory"
  end

  root.customMemories[memoryId] = nil
  return true
end

-- Candidates -----------------------------------------------------------------

-- Append a candidate (a captured assignment) to a custom memory.
function DB:AddCandidate(memoryId, assignment)
  local memory = self:GetCustomMemory(memoryId)
  if not memory then
    return false, "only custom memories can be edited"
  end
  if not assignment or not assignment.type then
    return false, "no action to add"
  end

  memory.candidates = memory.candidates or {}
  memory.candidates[#memory.candidates + 1] = assignment
  return true
end

function DB:RemoveCandidate(memoryId, index)
  local memory = self:GetCustomMemory(memoryId)
  if not memory then
    return false, "only custom memories can be edited"
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
  local memory = self:GetCustomMemory(memoryId)
  local candidates = memory and memory.candidates
  if not candidates then
    return false, "only custom memories can be edited"
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
