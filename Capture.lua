local ADDON_NAME, MM = ...

local Capture = {}
MM.Capture = Capture

local function simple(type)
  return function(id)
    return { type = type, id = id }
  end
end

-- Spells capture as their base spell: a spec/talent override id (e.g. Chrono
-- Flames for Living Flame) is neither known nor placeable on other specs.
local function spellAssignment(id)
  return { type = "spell", id = MM.Spells.GetBaseSpell(id) }
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
    -- The full body, so a macro missing on another character can be recreated
    -- there (in the same scope) at apply time.
    body = body,
    scope = indexHint and MM.Macros.GetMacroScope(indexHint, globalCount) or nil,
    indexHint = indexHint,
    nameHint = name,
    -- Display icon: a macro with no chosen icon reports GetMacroInfo's "?"
    -- placeholder, so prefer the slot's live (resolved) texture for a meaningful
    -- preview of a missing/restorable macro.
    iconHint = (slot and GetActionTexture and GetActionTexture(slot)) or icon,
    -- The picked icon incl. the "?" placeholder; GetMacroInfo instead reports a
    -- "?" macro's *resolved* texture (verified in 12.0 via /dump).
    restoreIcon = (C_Macro and C_Macro.GetSelectedMacroIcon and indexHint and C_Macro.GetSelectedMacroIcon(indexHint))
      or icon,
  }
end

-- The cursor carries the numeric set id, but an action slot reports the set's
-- NAME through GetActionInfo (verified in 12.0), so accept both.
local function equipmentSetAssignment(id)
  local name
  if type(id) == "string" and MM.EquipmentSets.Exists(id) then
    name = id
  elseif type(id) == "number" and C_EquipmentSet and C_EquipmentSet.GetEquipmentSetInfo then
    name = C_EquipmentSet.GetEquipmentSetInfo(id)
  end
  if not name then
    return nil, "equipment set not found"
  end
  return { type = "equipmentset", name = name }
end

-- Outfit ids are per-character and can shift, so keep the name as a display
-- hint (resolution stays by id, like macros keep their nameHint).
local function outfitAssignment(id)
  local info = MM.Outfits.GetInfo(id)
  if not info then
    return nil, "outfit not found"
  end
  return { type = "outfit", id = id, nameHint = info.name }
end

-- Cursor type -> assignment builder.
local fromCursor = {
  spell = spellAssignment,
  item = simple("item"),
  mount = simple("mount"),
  battlepet = simple("battlepet"),
  flyout = simple("flyout"),
  macro = function(id)
    return macroAssignment(id, nil)
  end,
  equipmentset = equipmentSetAssignment,
  outfit = outfitAssignment,
}

-- Action-slot type -> assignment builder. Mount variants normalise to "mount";
-- a summoned battle pet ("summonpet") normalises to "battlepet" (its cursor type).
local fromSlot = {
  spell = spellAssignment,
  item = simple("item"),
  mount = simple("mount"),
  summonmount = simple("mount"),
  summonpet = simple("battlepet"),
  equipmentset = equipmentSetAssignment,
  outfit = outfitAssignment,
  macro = macroAssignment,
  flyout = simple("flyout"),
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
    return spellAssignment(spellId)
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

  -- The Single Button Assistant reports its recommended ability through
  -- GetActionInfo, not its own identity, so capture its stable action spell.
  if MM.Spells.IsAssistedCombatSlot(slot) then
    local spellId = MM.Spells.GetAssistedCombatActionSpell()
    if spellId then
      return { type = "spell", id = spellId }
    end
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

  -- One undo step for the whole sweep, not one per slot.
  MM.Undo:Batch(function()
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
  end, "capture all filled bar slots")

  return captured, failures
end

-- Sync one stored assignment to the live macro it resolves to; hints refresh
-- silently, changes to the macro itself (name/body/pick) report for the trace.
local function syncMacroSnapshot(assignment, macros)
  local macro = MM.Macros.Resolve(assignment, macros)
  if not macro then
    return false
  end
  assignment.indexHint = macro.index
  assignment.scope = macro.scope
  assignment.iconHint = macro.icon

  local fresh = {
    nameHint = macro.name,
    body = macro.body,
    bodyHash = macro.bodyHash,
    restoreIcon = (C_Macro and C_Macro.GetSelectedMacroIcon and C_Macro.GetSelectedMacroIcon(macro.index))
      or assignment.restoreIcon,
  }
  local changed = false
  for key, value in pairs(fresh) do
    if assignment[key] ~= value then
      assignment[key] = value
      changed = true
    end
  end
  return changed, macro.name
end

-- The addon syncs, it doesn't back up: on every UPDATE_MACROS, refresh every
-- stored macro assignment from the macro it resolves to — what Resolve binds is
-- what apply would place. Direct writes like a migration, not an undoable edit.
function Capture:HealMacroSnapshots()
  local macros = MM.Macros.Scan()
  for _, profile in pairs(MM.DB:GetRoot().profiles or {}) do
    for _, layer in pairs(profile.layers or {}) do
      for slot, assignment in pairs(layer.slots or {}) do
        if type(assignment) == "table" and assignment.type == "macro" then
          local changed, name = syncMacroSnapshot(assignment, macros)
          if changed then
            MM:Debug(
              string.format(
                "synced stored macro %q in layer %q, %s.",
                name,
                layer.name or "?",
                MM.Actions.GetSlotLabel(slot)
              )
            )
          end
        end
      end
    end
  end
end

function Capture:PrintFailures(failures)
  local L = MM.L
  for index, failure in ipairs(failures or {}) do
    if index > 5 then
      MM:Warn(string.format(L["%d more capture failures omitted."], #failures - 5))
      return
    end
    MM:Warn(string.format(L["%s capture failed: %s."], MM.Actions.GetSlotLabel(failure.slot), L[failure.reason]))
  end
end
