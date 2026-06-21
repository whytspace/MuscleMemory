local ADDON_NAME, MM = ...

local Actions = {}
MM.Actions = Actions

function Actions.IsValidSlot(slot)
  return type(slot) == "number" and slot >= 1 and slot <= MM.MAX_ACTION_SLOT and slot == math.floor(slot)
end

function Actions.GetInfo(slot)
  if not Actions.IsValidSlot(slot) or not GetActionInfo then
    return nil
  end

  local actionType, id, subType = GetActionInfo(slot)
  return {
    actionType = actionType,
    id = id,
    subType = subType,
  }
end

function Actions.ClearSlot(slot)
  if not Actions.IsValidSlot(slot) then
    return false, "invalid action slot"
  end

  if HasAction and not HasAction(slot) then
    return true
  end

  PickupAction(slot)
  ClearCursor()
  return true
end

function Actions.PlaceCursor(slot)
  if not Actions.IsValidSlot(slot) then
    return false, "invalid action slot"
  end

  PlaceAction(slot)
  ClearCursor()
  return true
end

function Actions.GetSlotLabel(slot)
  local bar = math.floor((slot - 1) / MM.ACTIONS_PER_BAR) + 1
  local button = ((slot - 1) % MM.ACTIONS_PER_BAR) + 1
  return string.format("bar %d button %d", bar, button)
end
