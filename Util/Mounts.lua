local ADDON_NAME, MM = ...

local Mounts = {}
MM.Mounts = Mounts

-- The Mount Journal's "Summon Random Favorite Mount" button has no journal entry;
-- on the action bar it reports this sentinel id, so describe it from its summon
-- spell instead. Pickup and slot-matching then flow through spellId like any mount.
local RANDOM_FAVORITE_ID = 268435455
local RANDOM_FAVORITE_SPELL = 150544

function Mounts.GetInfo(mountId)
  if mountId == RANDOM_FAVORITE_ID then
    local spell = MM.Spells.GetInfo(RANDOM_FAVORITE_SPELL)
    return {
      id = mountId,
      name = spell and spell.name or "Random Favorite Mount",
      spellId = RANDOM_FAVORITE_SPELL,
      icon = spell and spell.icon,
      isCollected = true,
    }
  end

  if not mountId or not C_MountJournal or not C_MountJournal.GetMountInfoByID then
    return nil
  end

  local name, spellId, icon, _, _, _, _, _, _, _, isCollected = C_MountJournal.GetMountInfoByID(mountId)
  if not name then
    -- A captured mount keeps whatever id the action bar reported, and a
    -- companion/MOUNT slot reports the mount's summon spellID, not a journal
    -- mountID. Map that spell back to its mount and resolve from there.
    local mapped = C_MountJournal.GetMountFromSpell and C_MountJournal.GetMountFromSpell(mountId)
    if mapped and mapped ~= mountId then
      return Mounts.GetInfo(mapped)
    end
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

-- C_MountJournal.Pickup takes a *display index*, not a mountID, and that index
-- shifts with the journal's filters. Restore a normal mount by picking up its
-- summon spell instead, which lands as an equivalent mount button regardless of
-- filters. The random-favorite button is the one fixed index (0) and has no real
-- summon spell to pick up, so it uses Pickup directly.
function Mounts.Pickup(mountId)
  if mountId == RANDOM_FAVORITE_ID then
    if C_MountJournal and C_MountJournal.Pickup then
      C_MountJournal.Pickup(0)
      return true
    end
    return false
  end

  local info = Mounts.GetInfo(mountId)
  if info and info.spellId then
    return MM.Spells.Pickup(info.spellId)
  end

  return false
end
