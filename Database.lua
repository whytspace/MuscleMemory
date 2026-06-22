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

function DB:GetActiveProfileId()
  return self:GetRoot().activeProfile or "Default"
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

function DB:FindLayoutId(target)
  return matchByName(self:GetRoot().layouts, target)
end

function DB:CreateProfile(name)
  local root = self:GetRoot()
  local id = uniqueId(name, "profile", root.profiles)

  local activeLayouts, order = {}, 1
  for layoutId in pairs(root.layouts) do
    activeLayouts[layoutId] = { enabled = true, order = order }
    order = order + 1
  end

  root.profiles[id] = {
    name = name and name ~= "" and name or ("Profile " .. (MM.Tables.Count(root.profiles) + 1)),
    activeLayouts = activeLayouts,
    triggers = MM.Tables.DeepCopy(MM.defaults.profiles.Default.triggers),
  }
  root.activeProfile = id
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
  if root.activeProfile == profileId then
    root.activeProfile = next(root.profiles)
  end
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

-- Every layout in the profile, ordered, each tagged with its enabled state.
-- This is the canonical list for the UI and reordering.
function DB:GetProfileLayouts(profileId)
  local profile = self:GetProfile(profileId)
  local list = {}
  if not profile then
    return list
  end

  for layoutId, config in pairs(profile.activeLayouts or {}) do
    local layout = self:GetLayout(layoutId)
    if layout then
      list[#list + 1] = {
        id = layoutId,
        layout = layout,
        name = layout.name or layoutId,
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
    profile.activeLayouts[entry.id].order = index
  end

  return list
end

-- The enabled subset, in order. This is what gets applied.
function DB:GetActiveLayouts(profileId)
  local active = {}
  for _, entry in ipairs(self:GetProfileLayouts(profileId)) do
    if entry.enabled then
      active[#active + 1] = entry
    end
  end
  return active
end

function DB:SetLayoutEnabled(layoutId, enabled, profileId)
  local profile = self:GetProfile(profileId)
  local config = profile and profile.activeLayouts[layoutId]
  if not config then
    return false, "layout is not part of this profile"
  end

  config.enabled = enabled and true or false
  return true
end

function DB:GetLayout(layoutId)
  return self:GetRoot().layouts[layoutId]
end

function DB:GetSelectedLayoutId()
  local root = self:GetRoot()
  if root.ui.selectedLayout and root.layouts[root.ui.selectedLayout] then
    return root.ui.selectedLayout
  end

  root.ui.selectedLayout = "Core"
  return root.ui.selectedLayout
end

function DB:SetSelectedLayoutId(layoutId)
  local root = self:GetRoot()
  if root.layouts[layoutId] then
    root.ui.selectedLayout = layoutId
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

function DB:CreateLayout(name)
  local root = self:GetRoot()
  local layoutId = uniqueId(name, "layout", root.layouts)

  root.layouts[layoutId] = {
    name = name or ("Layout " .. tostring(MM.Tables.Count(root.layouts) + 1)),
    revision = 1,
    unresolvedFallback = "inherit",
    slots = {},
  }

  local profile = self:GetProfile(root.activeProfile)
  if profile then
    profile.activeLayouts[layoutId] = {
      enabled = true,
      order = MM.Tables.Count(profile.activeLayouts) + 1,
    }
  end

  root.ui.selectedLayout = layoutId
  root.ui.selectedSlot = nil
  return layoutId, root.layouts[layoutId]
end

function DB:RenameLayout(layoutId, name)
  local layout = self:GetLayout(layoutId)
  if not layout then
    return false, "unknown layout"
  end

  name = string.gsub(name or "", "^%s+", "")
  name = string.gsub(name, "%s+$", "")
  if name == "" then
    return false, "layout name cannot be empty"
  end

  layout.name = name
  return true
end

function DB:DeleteLayout(layoutId)
  local root = self:GetRoot()
  if not root.layouts[layoutId] then
    return false, "unknown layout"
  end

  if MM.Tables.Count(root.layouts or {}) <= 1 then
    return false, "cannot delete the last layout"
  end

  root.layouts[layoutId] = nil

  for _, profile in pairs(root.profiles or {}) do
    if profile.activeLayouts then
      profile.activeLayouts[layoutId] = nil
    end
  end

  if root.ui.selectedLayout == layoutId then
    local remaining = self:GetProfileLayouts()[1]
    root.ui.selectedLayout = remaining and remaining.id or next(root.layouts)
    root.ui.selectedSlot = nil
  end

  return true
end

-- Move `layoutId` to position `toIndex` within `profileId` (defaults to the
-- active profile). Explicit inputs, single mutation, no selection state read.
function DB:MoveLayout(layoutId, toIndex, profileId)
  local profile = self:GetProfile(profileId)
  if not profile or not profile.activeLayouts[layoutId] then
    return false, "layout is not part of this profile"
  end

  toIndex = tonumber(toIndex)
  if not toIndex then
    return false, "needs a target position"
  end

  local layouts = self:GetProfileLayouts(profileId)
  toIndex = math.max(1, math.min(toIndex, #layouts))

  local fromIndex
  for index, entry in ipairs(layouts) do
    if entry.id == layoutId then
      fromIndex = index
      break
    end
  end

  if not fromIndex or fromIndex == toIndex then
    return false, "layout is already at that position"
  end

  table.insert(layouts, toIndex, table.remove(layouts, fromIndex))
  for index, entry in ipairs(layouts) do
    profile.activeLayouts[entry.id].order = index
  end
  return true
end

function DB:SetSlot(layoutId, slot, assignment)
  local layout = self:GetLayout(layoutId)
  slot = tonumber(slot)
  if not layout or not MM.Actions.IsValidSlot(slot) then
    return false
  end

  layout.slots[slot] = assignment
  layout.revision = (layout.revision or 1) + 1
  return true
end

function DB:SetAllLayoutSlots(layoutId, enabled)
  local layout = self:GetLayout(layoutId)
  if not layout then
    return false
  end

  if enabled then
    for slot = 1, MM.MAX_ACTION_SLOT do
      if layout.slots[slot] == nil then
        layout.slots[slot] = { type = "empty" }
      end
    end
  else
    layout.slots = {}
  end

  layout.revision = (layout.revision or 1) + 1
  return true
end

function DB:GetCustomGroup(groupId)
  return self:GetRoot().customGroups[groupId]
end

function DB:GetStandardGroupOverride(groupId)
  local root = self:GetRoot()
  root.standardGroupOverrides[groupId] = root.standardGroupOverrides[groupId] or {}
  return root.standardGroupOverrides[groupId]
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

function DB:IsStandardGroupEnabled(groupId)
  local group = MM.StandardGroups[groupId]
  if not group or not group.enabled then
    return false
  end

  local override = self:GetRoot().standardGroupOverrides[groupId]
  if override and override.enabled == false then
    return false
  end

  return true
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
  copy.immutable = false
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
