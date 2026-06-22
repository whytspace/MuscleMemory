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
      local macro, reason = MM.Macros.FindForSlot(name, slot)
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

-- A spell dragged from the spellbook puts its book *slot index* on the cursor,
-- not its spellID (e.g. Counterspell drags as index 68, not 147362). Resolve the
-- index back to a real spellID; older clients (and the test harness) put the
-- spellID on the cursor directly, in which case the index isn't a valid book
-- slot and we fall back to the raw value.
local function cursorSpellId(index, bank, legacyId)
  if C_SpellBook and C_SpellBook.GetSpellBookItemInfo and type(index) == "number" then
    local banks = {}
    if bank ~= nil then
      banks[#banks + 1] = bank
    end
    if Enum and Enum.SpellBookSpellBank then
      banks[#banks + 1] = Enum.SpellBookSpellBank.Player
    end
    banks[#banks + 1] = 0

    for _, spellBank in ipairs(banks) do
      local ok, info = pcall(C_SpellBook.GetSpellBookItemInfo, index, spellBank)
      if ok and info and info.spellID and info.spellID > 0 then
        return info.spellID
      end
    end
  end

  return legacyId or index
end

function Capture:FromCursor()
  if not GetCursorInfo then
    return nil, "cursor API unavailable"
  end

  local cursorType, info1, info2, info3 = GetCursorInfo()
  if not cursorType then
    return nil, "cursor is empty"
  end

  if cursorType == "spell" then
    local spellId = cursorSpellId(info1, info2, info3)
    if not spellId then
      return nil, "could not read a spell from the cursor"
    end
    return { type = "spell", id = spellId }
  end

  local builder = fromCursor[cursorType]
  if not builder then
    return nil, "unsupported cursor type " .. tostring(cursorType)
  end
  return builder(info1)
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

function Capture:CaptureSlot(muscleId, slot)
  local assignment, reason = self:FromSlot(slot)
  if not assignment then
    return false, reason
  end

  MM.DB:SetSlot(muscleId, slot, assignment)
  return true, assignment.type
end

function Capture:CaptureFilledSlots(muscleId)
  local captured = 0
  local failures = {}

  for slot = 1, MM.MAX_ACTION_SLOT do
    if HasAction and HasAction(slot) then
      local ok, reason = self:CaptureSlot(muscleId, slot)
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
