local ADDON_NAME, MM = ...

local EquipmentSets = {}
MM.EquipmentSets = EquipmentSets

function EquipmentSets.GetId(name)
  if not name or not C_EquipmentSet or not C_EquipmentSet.GetEquipmentSetID then
    return nil
  end

  return C_EquipmentSet.GetEquipmentSetID(name)
end

function EquipmentSets.Exists(name)
  return EquipmentSets.GetId(name) ~= nil
end

function EquipmentSets.Pickup(name)
  if not C_EquipmentSet or not C_EquipmentSet.PickupEquipmentSet then
    return false
  end

  local id = EquipmentSets.GetId(name)
  if not id then
    return false
  end

  C_EquipmentSet.PickupEquipmentSet(id)
  return true
end
