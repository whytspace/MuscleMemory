local ADDON_NAME, MM = ...

local DB = {}
MM.DB = DB
MM:RegisterModule("DB", DB)

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

function DB:GetActiveLayouts(profileId)
  local profile = self:GetProfile(profileId)
  local active = {}
  if not profile then
    return active
  end

  for layoutId, config in pairs(profile.activeLayouts or {}) do
    local layout = self:GetLayout(layoutId)
    if layout and config.enabled ~= false and layout.enabled ~= false then
      active[#active + 1] = {
        id = layoutId,
        layout = layout,
        name = layout.name or layoutId,
        order = config.order or 100,
      }
    end
  end

  table.sort(active, function(left, right)
    if left.order == right.order then
      return left.name < right.name
    end
    return left.order < right.order
  end)

  for index, entry in ipairs(active) do
    entry.order = index
    profile.activeLayouts[entry.id].order = index
  end

  return active
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
  local baseId = string.gsub(string.lower(name or "layout"), "[^%w]+", "_")
  baseId = string.gsub(baseId, "^_+", "")
  baseId = string.gsub(baseId, "_+$", "")
  if baseId == "" then
    baseId = "layout"
  end

  local layoutId = baseId
  local suffix = 2
  while root.layouts[layoutId] do
    layoutId = baseId .. "_" .. suffix
    suffix = suffix + 1
  end

  root.layouts[layoutId] = {
    name = name or ("Layout " .. tostring(MM.Tables.Count(root.layouts) + 1)),
    enabled = true,
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
    local active = self:GetActiveLayouts()
    if active[1] then
      root.ui.selectedLayout = active[1].id
    else
      root.ui.selectedLayout = next(root.layouts)
    end
    root.ui.selectedSlot = nil
  end

  return true
end

function DB:MoveActiveLayout(layoutId, direction, profileId)
  local profile = self:GetProfile(profileId)
  if not profile or not profile.activeLayouts[layoutId] then
    return false
  end

  local layouts = self:GetActiveLayouts(profileId)
  local index
  for currentIndex, entry in ipairs(layouts) do
    if entry.id == layoutId then
      index = currentIndex
      break
    end
  end

  if not index then
    return false
  end

  local targetIndex = index + direction
  if targetIndex < 1 or targetIndex > #layouts then
    return false
  end

  local current = layouts[index]
  local target = layouts[targetIndex]
  profile.activeLayouts[current.id].order = targetIndex
  profile.activeLayouts[target.id].order = index
  return true
end

function DB:MoveActiveLayoutToIndex(layoutId, targetIndex, profileId)
  local profile = self:GetProfile(profileId)
  if not profile or not profile.activeLayouts[layoutId] then
    return false
  end

  local layouts = self:GetActiveLayouts(profileId)
  targetIndex = tonumber(targetIndex)
  if not targetIndex or targetIndex < 1 or targetIndex > #layouts then
    return false
  end

  local sourceIndex
  local moved
  for index, entry in ipairs(layouts) do
    if entry.id == layoutId then
      sourceIndex = index
      moved = entry
      break
    end
  end

  if not sourceIndex or sourceIndex == targetIndex then
    return false
  end

  table.remove(layouts, sourceIndex)
  table.insert(layouts, targetIndex, moved)

  for index, entry in ipairs(layouts) do
    profile.activeLayouts[entry.id].order = index
  end

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
