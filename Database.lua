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
  MuscleMemoryDB = MM.Tables.MergeDefaults(MuscleMemoryDB, MM.defaults)
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

function DB:FindLayerId(target)
  return matchByName(self:GetRoot().layers, target)
end

-- A new profile copies the active profile's layer selection, so it starts as a
-- variation of your current setup.
function DB:CreateProfile(name)
  local root = self:GetRoot()
  local id = uniqueId(name, "profile", root.profiles)
  local source = self:GetProfile()

  root.profiles[id] = {
    name = name and name ~= "" and name or ("Profile " .. (MM.Tables.Count(root.profiles) + 1)),
    activeLayers = MM.Tables.DeepCopy(source and source.activeLayers or {}),
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

-- Layers -------------------------------------------------------------------

-- Every layer in the profile, in stored order, each tagged with its enabled
-- state. Position in the list is the order.
function DB:GetProfileLayers(profileId)
  local profile = self:GetProfile(profileId)
  local list = {}
  if not profile then
    return list
  end

  for _, entry in ipairs(profile.activeLayers or {}) do
    local layer = self:GetLayer(entry.id)
    if layer then
      list[#list + 1] = {
        id = entry.id,
        layer = layer,
        name = layer.name or entry.id,
        enabled = entry.enabled ~= false,
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
  local profile = self:GetProfile(profileId)
  for _, entry in ipairs(profile and profile.activeLayers or {}) do
    if entry.id == layerId then
      entry.enabled = enabled and true or false
      return true
    end
  end
  return false, "layer is not part of this profile"
end

function DB:GetLayer(layerId)
  return self:GetRoot().layers[layerId]
end

function DB:CreateLayer(name)
  local root = self:GetRoot()
  local layerId = uniqueId(name, "layer", root.layers)

  root.layers[layerId] = {
    name = name or ("Layer " .. tostring(MM.Tables.Count(root.layers) + 1)),
    slots = {},
  }

  local profile = self:GetProfile()
  if profile then
    profile.activeLayers = profile.activeLayers or {}
    profile.activeLayers[#profile.activeLayers + 1] = { id = layerId, enabled = true }
  end

  return layerId, root.layers[layerId]
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
  local root = self:GetRoot()
  if not root.layers[layerId] then
    return false, "unknown layer"
  end
  if MM.Tables.Count(root.layers or {}) <= 1 then
    return false, "cannot delete the last layer"
  end

  root.layers[layerId] = nil

  for _, profile in pairs(root.profiles or {}) do
    for index = #(profile.activeLayers or {}), 1, -1 do
      if profile.activeLayers[index].id == layerId then
        table.remove(profile.activeLayers, index)
      end
    end
  end

  return true
end

-- Move `layerId` to position `toIndex` within `profileId` (defaults to the
-- active profile). Explicit inputs, single array splice, no selection read.
function DB:MoveLayer(layerId, toIndex, profileId)
  local profile = self:GetProfile(profileId)
  local layers = profile and profile.activeLayers
  if not layers then
    return false, "unknown profile"
  end

  toIndex = tonumber(toIndex)
  if not toIndex then
    return false, "needs a target position"
  end
  toIndex = math.max(1, math.min(toIndex, #layers))

  local fromIndex
  for index, entry in ipairs(layers) do
    if entry.id == layerId then
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

  table.insert(layers, toIndex, table.remove(layers, fromIndex))
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
  local root = self:GetRoot()
  if session.layer and root.layers[session.layer] then
    return session.layer
  end
  session.layer = next(root.layers)
  return session.layer
end

function DB:SetSelectedLayerId(layerId)
  if self:GetRoot().layers[layerId] then
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
  return self:GetRoot().fallback or "keep"
end

function DB:SetFallback(value)
  if value ~= "keep" and value ~= "clear" then
    return false, "fallback must be keep or clear"
  end
  self:GetRoot().fallback = value
  return true
end

-- Groups -------------------------------------------------------------------

function DB:GetCustomGroup(groupId)
  return self:GetRoot().customGroups[groupId]
end

function DB:GetGroup(reference)
  if not reference then
    return nil
  end

  if reference.source == "custom" then
    return self:GetCustomGroup(reference.id)
  end

  return MM.StandardGroups[reference.id]
end

-- Copy a standard group into an editable custom group. Returns the new key
-- (groups are identified by key, so duplicate names are fine).
function DB:CopyStandardGroup(groupId, newId, newName)
  local source = MM.StandardGroups[groupId]
  if not source then
    return nil, "unknown standard group"
  end

  local root = self:GetRoot()
  local name = newName or (source.name .. " Copy")
  local key = newId or uniqueId(name, groupId .. "_copy", root.customGroups)
  if root.customGroups[key] then
    return nil, "custom group already exists"
  end

  local copy = MM.Tables.DeepCopy(source)
  copy.name = name
  root.customGroups[key] = copy
  return key
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
