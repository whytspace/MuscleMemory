local ADDON_NAME, MM = ...

local DB = {}
MM.DB = DB
MM:RegisterModule("DB", DB)

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

-- Self-heals if the stored pointer is missing (e.g. its profile was deleted).
function DB:GetActiveProfileId()
  local root = self:GetRoot()
  if root.activeProfile and root.profiles[root.activeProfile] then
    return root.activeProfile
  end

  root.activeProfile = next(root.profiles)
  return root.activeProfile
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

-- A new profile is a copy of the active profile's layer selection and
-- triggers, so it starts as a variation of your current setup.
function DB:CreateProfile(name)
  local root = self:GetRoot()
  local id = uniqueId(name, "profile", root.profiles)
  local source = self:GetProfile()

  root.profiles[id] = {
    name = name and name ~= "" and name or ("Profile " .. (MM.Tables.Count(root.profiles) + 1)),
    activeLayers = MM.Tables.DeepCopy(source and source.activeLayers or {}),
    triggers = MM.Tables.DeepCopy(source and source.triggers or MM.defaults.profiles.Default.triggers),
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

function DB:SetActiveProfile(profileId)
  local root = self:GetRoot()
  if not root.profiles[profileId] then
    return false, "unknown profile"
  end
  root.activeProfile = profileId
  return true
end

-- Every layer in the profile, ordered, each tagged with its enabled state.
-- This is the canonical list for the UI and reordering.
function DB:GetProfileLayers(profileId)
  local profile = self:GetProfile(profileId)
  local list = {}
  if not profile then
    return list
  end

  for layerId, config in pairs(profile.activeLayers or {}) do
    local layer = self:GetLayer(layerId)
    if layer then
      list[#list + 1] = {
        id = layerId,
        layer = layer,
        name = layer.name or layerId,
        order = config.order or 100,
        enabled = config.enabled ~= false,
      }
    end
  end

  table.sort(list, function(left, right)
    if left.order == right.order then
      return left.name < right.name
    end
    return left.order < right.order
  end)

  for index, entry in ipairs(list) do
    entry.order = index
    profile.activeLayers[entry.id].order = index
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
  local config = profile and profile.activeLayers[layerId]
  if not config then
    return false, "layer is not part of this profile"
  end

  config.enabled = enabled and true or false
  return true
end

function DB:GetLayer(layerId)
  return self:GetRoot().layers[layerId]
end

-- Self-heals if the stored pointer is missing (e.g. its layer was deleted).
function DB:GetSelectedLayerId()
  local root = self:GetRoot()
  if root.ui.selectedLayer and root.layers[root.ui.selectedLayer] then
    return root.ui.selectedLayer
  end

  root.ui.selectedLayer = next(root.layers)
  return root.ui.selectedLayer
end

function DB:SetSelectedLayerId(layerId)
  local root = self:GetRoot()
  if root.layers[layerId] then
    root.ui.selectedLayer = layerId
  end
end

function DB:GetSelectedSlot()
  return tonumber(self:GetRoot().ui.selectedSlot)
end

function DB:SetSelectedSlot(slot)
  local root = self:GetRoot()
  slot = tonumber(slot)
  if MM.Actions.IsValidSlot(slot) then
    root.ui.selectedSlot = slot
  else
    root.ui.selectedSlot = nil
  end
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
    profile.activeLayers[layerId] = {
      enabled = true,
      order = MM.Tables.Count(profile.activeLayers) + 1,
    }
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
    if profile.activeLayers then
      profile.activeLayers[layerId] = nil
    end
  end

  return true
end

-- Move `layerId` to position `toIndex` within `profileId` (defaults to the
-- active profile). Explicit inputs, single mutation, no selection state read.
function DB:MoveLayer(layerId, toIndex, profileId)
  local profile = self:GetProfile(profileId)
  if not profile or not profile.activeLayers[layerId] then
    return false, "layer is not part of this profile"
  end

  toIndex = tonumber(toIndex)
  if not toIndex then
    return false, "needs a target position"
  end

  local layers = self:GetProfileLayers(profileId)
  toIndex = math.max(1, math.min(toIndex, #layers))

  local fromIndex
  for index, entry in ipairs(layers) do
    if entry.id == layerId then
      fromIndex = index
      break
    end
  end

  if not fromIndex or fromIndex == toIndex then
    return false, "layer is already at that position"
  end

  table.insert(layers, toIndex, table.remove(layers, fromIndex))
  for index, entry in ipairs(layers) do
    profile.activeLayers[entry.id].order = index
  end
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

function DB:CopyStandardGroup(groupId, newId, newName)
  local source = MM.StandardGroups[groupId]
  if not source then
    return nil, "unknown standard group"
  end

  local root = self:GetRoot()
  newId = newId or (groupId .. "_copy")
  if root.customGroups[newId] then
    return nil, "custom group already exists"
  end

  local copy = MM.Tables.DeepCopy(source)
  copy.id = newId
  copy.name = newName or (source.name .. " Copy")
  copy.sourceStandard = groupId
  root.customGroups[newId] = copy
  return copy
end

function DB:GetCharacterKey()
  local name = UnitName("player") or "Unknown"
  local realm = GetRealmName and GetRealmName() or "Unknown"
  return realm .. "-" .. name
end

function DB:GetCharacterState()
  local root = self:GetRoot()
  local key = self:GetCharacterKey()
  root.characterState[key] = root.characterState[key] or {
    lastApplied = {},
    pendingProfiles = {},
  }
  return root.characterState[key]
end
