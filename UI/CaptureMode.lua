local ADDON_NAME, MM = ...

local CaptureMode = {}
MM.ui.CaptureMode = CaptureMode

local function makeMacroAssignment(index, slot)
  if not GetMacroInfo then
    return nil, "macro API unavailable"
  end

  local name, icon, body = GetMacroInfo(index)
  if not name and GetActionText then
    name = GetActionText(slot)
    if name then
      local macro, reason = MM.Macros.FindUniqueByName(name)
      if not macro then
        return nil, reason
      end

      index = macro.index
      icon = macro.icon
      body = macro.body
    end
  end

  if not name then
    return nil, "macro not found"
  end

  local globalCount = 0
  if GetNumMacros then
    globalCount = GetNumMacros() or 0
  end

  local indexHint = tonumber(index)

  return {
    type = "macro",
    bodyHash = MM.Macros.HashBody(body),
    scope = indexHint and MM.Macros.GetMacroScope(indexHint, globalCount) or nil,
    indexHint = indexHint,
    nameHint = name,
    iconHint = icon,
    unresolvedFallback = "inherit",
  }
end

local function makeEquipmentSetAssignment(id)
  if C_EquipmentSet and C_EquipmentSet.GetEquipmentSetInfo then
    local name = C_EquipmentSet.GetEquipmentSetInfo(id)
    if name then
      return {
        type = "equipmentset",
        name = name,
        unresolvedFallback = "inherit",
      }
    end
  end

  return nil, "equipment set capture is unavailable"
end

local function makeCursorMacroAssignment(index)
  return makeMacroAssignment(index, nil)
end

local function makeCursorEquipmentSetAssignment(id)
  return makeEquipmentSetAssignment(id)
end

function CaptureMode:GetAssignmentFromCursor()
  if not GetCursorInfo then
    return nil, "cursor API unavailable"
  end

  local cursorType, id = GetCursorInfo()
  if not cursorType then
    return nil, "cursor is empty"
  end

  if cursorType == "spell" then
    return {
      type = "spell",
      id = id,
      unresolvedFallback = "inherit",
    }
  end

  if cursorType == "item" then
    return {
      type = "item",
      id = id,
      unresolvedFallback = "inherit",
    }
  end

  if cursorType == "macro" then
    return makeCursorMacroAssignment(id)
  end

  if cursorType == "mount" then
    return {
      type = "mount",
      id = id,
      unresolvedFallback = "inherit",
    }
  end

  if cursorType == "equipmentset" then
    return makeCursorEquipmentSetAssignment(id)
  end

  return nil, "unsupported cursor type " .. tostring(cursorType)
end

function CaptureMode:GetAssignmentFromSlot(slot)
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

  if info.actionType == "spell" then
    return {
      type = "spell",
      id = info.id,
      unresolvedFallback = "inherit",
    }
  end

  if info.actionType == "item" then
    return {
      type = "item",
      id = info.id,
      unresolvedFallback = "inherit",
    }
  end

  if info.actionType == "macro" then
    return makeMacroAssignment(info.id, slot)
  end

  if info.actionType == "mount" or info.actionType == "summonmount" then
    return {
      type = "mount",
      id = info.id,
      unresolvedFallback = "inherit",
    }
  end

  if info.actionType == "companion" and info.subType == "MOUNT" then
    return {
      type = "mount",
      id = info.id,
      unresolvedFallback = "inherit",
    }
  end

  if info.actionType == "equipmentset" then
    return makeEquipmentSetAssignment(info.id)
  end

  if info.actionType == "flyout" then
    return {
      type = "ignore",
      captureNote = "flyout actions are not managed yet",
    }
  end

  return nil, "unsupported action type " .. tostring(info.actionType)
end

function CaptureMode:CaptureSlot(layoutId, slot)
  local assignment, reason = self:GetAssignmentFromSlot(slot)
  if not assignment then
    return false, reason
  end

  MM.ui.SlotEditor:SetAssignment(layoutId, slot, assignment)
  return true, assignment.type
end

function CaptureMode:CaptureFilledSlots(layoutId)
  local captured = 0
  local skipped = 0
  local failed = 0
  local failures = {}

  for slot = 1, MM.MAX_ACTION_SLOT do
    if HasAction and HasAction(slot) then
      local ok, reason = self:CaptureSlot(layoutId, slot)
      if ok then
        captured = captured + 1
      else
        failed = failed + 1
        failures[#failures + 1] = {
          slot = slot,
          reason = reason or "unknown reason",
        }
      end
    else
      skipped = skipped + 1
    end
  end

  return captured, skipped, failed, failures
end

function CaptureMode:PrintFailures(failures)
  for index, failure in ipairs(failures or {}) do
    if index > 5 then
      MM:Warn(string.format("%d more capture failures omitted.", #failures - 5))
      return
    end

    MM:Warn(string.format("%s capture failed: %s.", MM.Actions.GetSlotLabel(failure.slot), failure.reason))
  end
end

function CaptureMode:Start(layoutId)
  local root = MM.DB:GetRoot()
  layoutId = layoutId or root.ui.selectedLayout or "Core"
  local captured, _, failed, failures = self:CaptureFilledSlots(layoutId)
  MM:Print(string.format("captured %d filled slots into layout %s, failed %d.", captured, layoutId, failed))
  self:PrintFailures(failures)
end

function CaptureMode:Stop() end
