local ADDON_NAME, MM = ...

local Items = {}
MM.Items = Items

function Items.GetCount(itemId)
  if not itemId then
    return 0
  end

  if C_Item and C_Item.GetItemCount then
    return C_Item.GetItemCount(itemId, false, false, true) or 0
  end

  if GetItemCount then
    return GetItemCount(itemId, false, true) or 0
  end

  return 0
end

function Items.IsOwned(itemId)
  return Items.GetCount(itemId) > 0
end

function Items.Pickup(itemId)
  if C_Item and C_Item.PickupItem then
    C_Item.PickupItem(itemId)
    return true
  end

  if PickupItem then
    PickupItem(itemId)
    return true
  end

  return false
end
