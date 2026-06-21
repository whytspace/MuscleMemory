local ADDON_NAME, MM = ...

local Items = {}
MM.Items = Items

function Items.GetInfo(itemId)
  if not itemId then
    return nil
  end

  if C_Item and C_Item.GetItemInfo then
    local name, link, _, _, _, _, _, _, _, icon = C_Item.GetItemInfo(itemId)
    if name then
      return {
        id = itemId,
        name = name,
        link = link,
        icon = icon,
      }
    end
  end

  if GetItemInfo then
    local name, link, _, _, _, _, _, _, _, icon = GetItemInfo(itemId)
    if name then
      return {
        id = itemId,
        name = name,
        link = link,
        icon = icon,
      }
    end
  end

  return nil
end

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

function Items.IsEquipped(itemId)
  if not itemId or not IsEquippedItem then
    return false
  end

  return IsEquippedItem(itemId) == true
end

function Items.IsOwned(itemId)
  return Items.GetCount(itemId) > 0 or Items.IsEquipped(itemId)
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
