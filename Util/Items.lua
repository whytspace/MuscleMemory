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

  -- Bags only: bank and reagent-bank items can't be used or dragged to a bar
  -- until withdrawn, so they don't count as available.
  if C_Item and C_Item.GetItemCount then
    return C_Item.GetItemCount(itemId, false, false, false) or 0
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

-- A learned toy lives in the Toy Box, not the bags, so GetItemCount reports 0.
-- PlayerHasToy answers ownership for those.
function Items.IsToy(itemId)
  return itemId ~= nil and PlayerHasToy ~= nil and PlayerHasToy(itemId) == true
end

function Items.IsOwned(itemId)
  return Items.GetCount(itemId) > 0 or Items.IsEquipped(itemId) or Items.IsToy(itemId)
end

-- An unmet requirement (wrong level, class, or profession) renders as a red line
-- in the item tooltip. This is the standard red the client uses for those lines.
local function isRequirementRed(r, g, b)
  return r ~= nil and r > 0.9 and g < 0.2 and b < 0.2
end

-- Scan the item's tooltip for an unmet (red) requirement line. Returns true if
-- one is found, false if the tooltip is clean, or nil if the tooltip data isn't
-- available (no C_TooltipInfo, or the item isn't cached yet).
local function tooltipHasUnmetRequirement(itemId)
  if not (C_TooltipInfo and C_TooltipInfo.GetItemByID) then
    return nil
  end

  local data = C_TooltipInfo.GetItemByID(itemId)
  if not data or not data.lines then
    return nil
  end

  for _, line in ipairs(data.lines) do
    if TooltipUtil and TooltipUtil.SurfaceArgs then
      TooltipUtil.SurfaceArgs(line)
    end
    local color = line.leftColor
    if color and color.GetRGB and isRequirementRed(color:GetRGB()) then
      return true
    end
  end

  return false
end

-- Whether the character could use the item (meets level/class/profession), read
-- from the red requirement lines in its tooltip. Ownership-independent: a usable
-- item you're out of still counts, so it restores greyed rather than yielding the
-- slot. IsUsableItem is avoided -- it reports items you don't own as unusable.
function Items.IsUsable(itemId)
  if not itemId then
    return false
  end

  -- Toys must be learned to place; an unlearned toy (GetToyInfo knows it anyway)
  -- falls through. A learned toy defers to the Toy Box's own usability answer.
  if C_ToyBox and C_ToyBox.GetToyInfo and C_ToyBox.GetToyInfo(itemId) then
    if not (PlayerHasToy and PlayerHasToy(itemId)) then
      return false
    end
    if C_ToyBox.IsToyUsable then
      return C_ToyBox.IsToyUsable(itemId) ~= false
    end
    return true
  end

  return tooltipHasUnmetRequirement(itemId) ~= true
end

-- The crafting-quality crystal markup for an item, or nil for items without a
-- quality. The client embeds the crystal atlas in the item link's name, so we
-- lift it from there: this needs no data of our own and works for any item,
-- including custom ones (the quality APIs return nil for these items).
function Items.GetQualityMarkup(itemId)
  local info = Items.GetInfo(itemId)
  local link = info and info.link
  if not link then
    return nil
  end

  return link:match("|A:Professions%-ChatIcon%-Quality.-|a")
end

function Items.Pickup(itemId)
  -- A learned toy can't be picked up as a bag item; the Toy Box has its own pickup.
  if Items.IsToy(itemId) and C_ToyBox and C_ToyBox.PickupToyBoxItem then
    C_ToyBox.PickupToyBoxItem(itemId)
    return true
  end

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
