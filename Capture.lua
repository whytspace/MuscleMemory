local ADDON_NAME, MM = ...

local Capture = {}
MM.Capture = Capture

local function simple(type)
  return function(id)
    return { type = type, id = id }
  end
end

local function macroAssignment(index, slot)
  if not GetMacroInfo then
    return nil, "macro API unavailable"
  end

  local name, icon, body = GetMacroInfo(index)
  if not name and slot and GetActionText then
    name = GetActionText(slot)
    if name then
      local macro, reason = MM.Macros.FindUniqueByName(name)
      if not macro then
        return nil, reason
      end
      index, icon, body = macro.index, macro.icon, macro.body
    end
  end

  if not name then
    return nil, "macro not found"
  end

  local globalCount = GetNumMacros and GetNumMacros() or 0
  local indexHint = tonumber(index)
  return {
    type = "macro",
    bodyHash = MM.Macros.HashBody(body),
    scope = indexHint and MM.Macros.GetMacroScope(indexHint, globalCount) or nil,
    indexHint = indexHint,
    nameHint = name,
    iconHint = icon,
  }
end

local function equipmentSetAssignment(id)
  local name = C_EquipmentSet and C_EquipmentSet.GetEquipmentSetInfo and C_EquipmentSet.GetEquipmentSetInfo(id)
  if not name then
    return nil, "equipment set capture is unavailable"
  end
  return { type = "equipmentset", name = name }
end

-- Cursor type -> assignment builder.
local fromCursor = {
  spell = simple("spell"),
  item = simple("item"),
  mount = simple("mount"),
  macro = function(id)
    return macroAssignment(id, nil)
  end,
  equipmentset = equipmentSetAssignment,
}

-- Action-slot type -> assignment builder. Mount variants normalise to "mount".
local fromSlot = {
  spell = simple("spell"),
  item = simple("item"),
  mount = simple("mount"),
  summonmount = simple("mount"),
  equipmentset = equipmentSetAssignment,
  macro = macroAssignment,
  flyout = function()
    return { type = "ignore" }
  end,
}

function Capture:FromCursor()
  if not GetCursorInfo then
    return nil, "cursor API unavailable"
  end

  local cursorType, id = GetCursorInfo()
  if not cursorType then
    return nil, "cursor is empty"
  end

  local builder = fromCursor[cursorType]
  if not builder then
    return nil, "unsupported cursor type " .. tostring(cursorType)
  end
  return builder(id)
end

function Capture:FromSlot(slot)
  slot = tonumber(slot)
  if not MM.Actions.IsValidSlot(slot) then
    return nil, "invalid action slot"
  end

  if HasAction and not HasAction(slot) then
    return { type = "empty" }
  end

  local info = MM.Actions.GetInfo(slot)
  if not info or not info.actionType then
    return nil, "slot has no capturable action"
  end

  if info.actionType == "companion" and info.subType == "MOUNT" then
    return { type = "mount", id = info.id }
  end

  local builder = fromSlot[info.actionType]
  if not builder then
    return nil, "unsupported action type " .. tostring(info.actionType)
  end
  return builder(info.id, slot)
end

function Capture:CaptureSlot(layerId, slot)
  local assignment, reason = self:FromSlot(slot)
  if not assignment then
    return false, reason
  end

  MM.DB:SetSlot(layerId, slot, assignment)
  return true, assignment.type
end

function Capture:CaptureFilledSlots(layerId)
  local captured = 0
  local failures = {}

  for slot = 1, MM.MAX_ACTION_SLOT do
    if HasAction and HasAction(slot) then
      local ok, reason = self:CaptureSlot(layerId, slot)
      if ok then
        captured = captured + 1
      else
        failures[#failures + 1] = { slot = slot, reason = reason or "unknown reason" }
      end
    end
  end

  return captured, failures
end

function Capture:PrintFailures(failures)
  for index, failure in ipairs(failures or {}) do
    if index > 5 then
      MM:Warn(string.format("%d more capture failures omitted.", #failures - 5))
      return
    end
    MM:Warn(string.format("%s capture failed: %s.", MM.Actions.GetSlotLabel(failure.slot), failure.reason))
  end
end
