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

function DB:GetLayout(layoutId)
  return self:GetRoot().layouts[layoutId]
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
