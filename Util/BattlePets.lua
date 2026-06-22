local ADDON_NAME, MM = ...

local BattlePets = {}
MM.BattlePets = BattlePets

-- Battle pets are identified by an account-wide GUID string (e.g.
-- "BattlePet-0-000000000000"), so a captured pet restores on every character on
-- the account. GetPetInfoByPetID returns info only for a pet you own.
function BattlePets.GetInfo(petGuid)
  if not petGuid or not C_PetJournal or not C_PetJournal.GetPetInfoByPetID then
    return nil
  end

  local speciesId, customName, _, _, _, _, _, name, icon = C_PetJournal.GetPetInfoByPetID(petGuid)
  if not name then
    return nil
  end

  return {
    id = petGuid,
    name = customName or name,
    icon = icon,
    speciesId = speciesId,
  }
end

function BattlePets.IsKnown(petGuid)
  return BattlePets.GetInfo(petGuid) ~= nil
end

function BattlePets.Pickup(petGuid)
  if C_PetJournal and C_PetJournal.PickupPet then
    C_PetJournal.PickupPet(petGuid)
    return true
  end

  return false
end
