local ADDON_NAME, MM = ...

local Mounts = {}
MM.Mounts = Mounts

function Mounts.GetInfo(mountId)
  if not mountId or not C_MountJournal or not C_MountJournal.GetMountInfoByID then
    return nil
  end

  local name, spellId, icon, _, _, _, _, _, _, _, isCollected = C_MountJournal.GetMountInfoByID(mountId)
  if not name then
    return nil
  end

  return {
    id = mountId,
    name = name,
    spellId = spellId,
    icon = icon,
    isCollected = isCollected,
  }
end

function Mounts.IsKnown(mountId)
  local info = Mounts.GetInfo(mountId)
  return info and info.isCollected ~= false
end

function Mounts.Pickup(mountId)
  if C_MountJournal and C_MountJournal.Pickup then
    C_MountJournal.Pickup(mountId)
    return true
  end

  return false
end
