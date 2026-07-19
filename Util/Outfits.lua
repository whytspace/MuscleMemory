local ADDON_NAME, MM = ...

-- Transmog outfits (12.0 lets them sit on action bars). Identified by their
-- numeric outfit id; C_TransmogOutfitInfo.GetOutfitInfo returns a table with
-- name and icon.
local Outfits = {}
MM.Outfits = Outfits

function Outfits.GetInfo(id)
  if not id or not C_TransmogOutfitInfo or not C_TransmogOutfitInfo.GetOutfitInfo then
    return nil
  end

  local info = C_TransmogOutfitInfo.GetOutfitInfo(id)
  if not info or not info.name then
    return nil
  end
  return { name = info.name, icon = info.icon }
end

function Outfits.IsKnown(id)
  return Outfits.GetInfo(id) ~= nil
end

function Outfits.Pickup(id)
  if not C_TransmogOutfitInfo or not C_TransmogOutfitInfo.PickupOutfit or not Outfits.IsKnown(id) then
    return false
  end

  C_TransmogOutfitInfo.PickupOutfit(id)
  return true
end
