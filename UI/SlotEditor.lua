local ADDON_NAME, MM = ...

local SlotEditor = {}
MM.ui.SlotEditor = SlotEditor

function SlotEditor:CycleSlot(layoutId, slot)
  local layout = MM.DB:GetLayout(layoutId)
  if not layout then
    return
  end

  local current = layout.slots[slot]
  if not current then
    layout.slots[slot] = { type = "empty" }
  elseif current.type == "empty" then
    layout.slots[slot] = {
      type = "group",
      source = "standard",
      id = "interrupt",
      unresolvedFallback = "inherit",
    }
  elseif current.type == "group" and current.id == "interrupt" then
    layout.slots[slot] = {
      type = "group",
      source = "standard",
      id = "taunt",
      unresolvedFallback = "inherit",
    }
  else
    layout.slots[slot] = nil
  end

  layout.revision = (layout.revision or 1) + 1
end
