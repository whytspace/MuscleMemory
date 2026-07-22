local ADDON_NAME, MM = ...

local Applier = {}
MM.Applier = Applier
MM:RegisterModule("Applier", Applier)

function Applier:BuildPlan(profileId)
  local profile = MM.DB:GetProfile(profileId)
  if not profile then
    return nil, "profile not found"
  end

  -- A layer whose conditions don't match the current character is skipped, a
  -- dynamic complement to the per-profile enable toggle.
  local plan = {
    profileId = profileId or MM.DB:GetActiveProfileId(),
    slots = {},
    conflicts = {},
    layers = {},
  }
  for _, activeLayer in ipairs(MM.DB:GetActiveLayers(profileId)) do
    if MM.Conditions.Match(activeLayer.layer.conditions) then
      plan.layers[#plan.layers + 1] = activeLayer
    end
  end

  for _, activeLayer in ipairs(plan.layers) do
    for slot in pairs(activeLayer.layer.slots or {}) do
      local numericSlot = tonumber(slot)
      if not MM.Actions.IsValidSlot(numericSlot) then
        plan.conflicts[#plan.conflicts + 1] = {
          slot = tostring(slot),
          firstLayer = activeLayer.id,
          secondLayer = "invalid slot",
        }
      end
    end
  end

  for slot = 1, MM.MAX_ACTION_SLOT do
    local finalEntry
    local terminalEntry

    for _, activeLayer in ipairs(plan.layers) do
      local layer = activeLayer.layer
      local assignment = layer.slots and layer.slots[slot]
      if assignment then
        local resolved, reason = MM.Resolver:ResolveAction(assignment)
        local entry = {
          slot = slot,
          layerId = activeLayer.id,
          layer = layer,
          assignment = assignment,
          resolved = resolved,
          unresolvedReason = reason,
          fallback = MM.DB:GetFallback(),
        }

        if not (resolved and resolved.kind == "ignore") then
          if resolved and resolved.kind == "empty" then
            finalEntry = entry
            break
          elseif resolved then
            finalEntry = entry
            break
          else
            terminalEntry = entry
          end
        end
      end
    end

    plan.slots[slot] = finalEntry or terminalEntry
  end

  return plan
end

-- True if applying the profile would change at least one slot — i.e. a managed
-- slot whose resolved action differs from what is currently there, or an
-- unresolved slot that the fallback would clear.
function Applier:HasUnappliedChanges(profileId)
  local plan = self:BuildPlan(profileId)
  if not plan then
    return false
  end

  for slot = 1, MM.MAX_ACTION_SLOT do
    local entry = plan.slots[slot]
    if entry then
      if entry.resolved then
        if entry.resolved.pickupAvailable ~= false and not MM.Actions.IsResolvedInSlot(entry.resolved, slot) then
          return true
        end
      elseif entry.fallback == "clear" and HasAction and HasAction(slot) then
        return true
      end
    end
  end

  return false
end

-- Label for what a resolved entry would place, annotating the macro lifecycle.
function Applier:DescribeTo(entry)
  local resolved = entry.resolved
  if not resolved or resolved.kind == "empty" then
    return "empty"
  end
  local label = resolved.label
  local body = MM.Macros.ResolvedAsMacro(resolved)
  if body then
    local record = MM.DB:GetMacroRecord(entry.layerId, entry.slot)
    label = label .. (MM.Macros.WouldUpdate(record, body) and " (updates the macro)" or " (creates a macro)")
  elseif resolved.kind == "macro" and not resolved.macro then
    label = label .. " (recreates the macro)"
  end
  return label
end

-- A "N slot(s)" phrase without the awkward "1 slots".
local function slotCount(n)
  return n == 1 and "1 slot" or (n .. " slots")
end

function Applier:PreviewProfile(profileId)
  local plan, reason = self:BuildPlan(profileId)
  if not plan then
    MM:Warn(reason)
    return nil
  end

  local debug = MM.DB:GetRoot().debug

  for _, conflict in ipairs(plan.conflicts) do
    MM:Warn(
      string.format(
        "layer %s contains invalid slot %s (%s).",
        conflict.firstLayer,
        tostring(conflict.slot),
        conflict.secondLayer
      )
    )
  end

  -- Body: one "slot: from → to" line per change. Resolution problems are debug-only.
  local changed = 0
  local issues = {}
  for slot = 1, MM.MAX_ACTION_SLOT do
    local entry = plan.slots[slot]
    if entry then
      if entry.resolved and not MM.Actions.IsResolvedInSlot(entry.resolved, slot) then
        if entry.resolved.pickupAvailable == false then
          issues[#issues + 1] =
            string.format("%s: cannot restore %s (not available)", MM.Actions.GetSlotLabel(slot), entry.resolved.label)
        else
          changed = changed + 1
          MM:Print(
            string.format(
              "%s: %s → %s",
              MM.Actions.GetSlotLabel(slot),
              MM.Actions.GetLiveActionLabel(slot),
              self:DescribeTo(entry)
            )
          )
        end
      elseif not entry.resolved and entry.fallback == "clear" and HasAction and HasAction(slot) then
        changed = changed + 1
        MM:Print(string.format("%s: %s → empty", MM.Actions.GetSlotLabel(slot), MM.Actions.GetLiveActionLabel(slot)))
      elseif not entry.resolved and not MM.Actions.IsAssignmentInSlot(entry.assignment, slot) then
        issues[#issues + 1] =
          string.format("%s: %s (left unchanged)", MM.Actions.GetSlotLabel(slot), tostring(entry.unresolvedReason))
      end
    end
  end

  MM:Print(changed == 0 and "no changes" or (slotCount(changed) .. " would change"))

  if debug then
    for _, line in ipairs(issues) do
      MM:Debug(line)
    end
  end

  return plan
end

function Applier:CanApply()
  if InCombatLockdown and InCombatLockdown() then
    return false, "combat lockdown"
  end

  if GetCursorInfo and GetCursorInfo() then
    return false, "cursor is not empty"
  end

  return true
end

function Applier:ApplyEntry(entry)
  local slot = tonumber(entry.slot)
  if not MM.Actions.IsValidSlot(slot) then
    return false, "invalid action slot"
  end

  if not entry.resolved then
    if entry.fallback == "clear" then
      local ok, reason = MM.Actions.ClearSlot(slot)
      if ok then
        return true, "cleared unresolved slot"
      end
      return false, reason
    end

    return true, "left unresolved slot unchanged"
  end

  if entry.resolved.kind == "ignore" then
    return true, "ignored"
  end

  if entry.resolved.kind == "empty" then
    return MM.Actions.ClearSlot(slot)
  end

  if entry.resolved.pickupAvailable == false then
    return false, "action is not currently available"
  end

  -- Macro mode: a dynamicAction can render as a generated macro instead of the raw
  -- action. A body that won't render (action outside the family, or too long after
  -- substitution) falls back to placing the action directly rather than failing.
  local body = MM.Macros.ResolvedAsMacro(entry.resolved)
  if body then
    return self:ApplyMacroEntry(entry, slot, entry.resolved.dynamicAction, body)
  end

  -- A restorable macro doesn't exist on this character yet: recreate it in its
  -- captured scope first, then place it like any other macro.
  if entry.resolved.kind == "macro" and not entry.resolved.macro then
    local restored, restoreReason = MM.Macros.RestoreUserMacro(entry.resolved.restore)
    if not restored then
      return false, restoreReason
    end
    entry.resolved.macro = restored
  end

  local pickedUp
  if entry.resolved.kind == "spell" then
    pickedUp = MM.Spells.Pickup(entry.resolved.id)
  elseif entry.resolved.kind == "item" then
    pickedUp = MM.Items.Pickup(entry.resolved.id)
  elseif entry.resolved.kind == "macro" then
    pickedUp = MM.Macros.Pickup(entry.resolved.macro)
  elseif entry.resolved.kind == "mount" then
    pickedUp = MM.Mounts.Pickup(entry.resolved.id)
  elseif entry.resolved.kind == "battlepet" then
    pickedUp = MM.BattlePets.Pickup(entry.resolved.id)
  elseif entry.resolved.kind == "flyout" then
    pickedUp = MM.Flyouts.Pickup(entry.resolved.id)
  elseif entry.resolved.kind == "equipmentset" then
    pickedUp = MM.EquipmentSets.Pickup(entry.resolved.name)
  elseif entry.resolved.kind == "outfit" then
    pickedUp = MM.Outfits.Pickup(entry.resolved.id)
  else
    return false, "unsupported resolved action kind " .. tostring(entry.resolved.kind)
  end

  if not pickedUp or not GetCursorInfo or not GetCursorInfo() then
    ClearCursor()
    return false, "could not pick up action"
  end

  return MM.Actions.PlaceCursor(slot)
end

-- Reconcile the macro for `entry`'s slot to the already-rendered `body` (reuse /
-- edit / create) through the per-character registry, and place it.
function Applier:ApplyMacroEntry(entry, slot, dynamicAction, body)
  local record = MM.DB:GetMacroRecord(entry.layerId, slot)
  local macro, result = MM.Macros.EnsureMacro(record, MM.Macros.MacroName(dynamicAction), body)
  if not macro then
    return false, result
  end
  MM.DB:SetMacroRecord(entry.layerId, slot, result)

  -- Expose the macro on the resolved action so IsResolvedInSlot recognises it.
  entry.resolved.macro = macro

  if not MM.Macros.Pickup(macro) or not GetCursorInfo or not GetCursorInfo() then
    ClearCursor()
    return false, "could not pick up macro"
  end
  return MM.Actions.PlaceCursor(slot)
end

-- Delete generated macros no plan slot wants anymore (dynamicAction switched off macro
-- mode, slot reassigned, layer/dynamicAction deleted). Runs after applying, so a slot
-- that still wants its macro has refreshed the registry first.
function Applier:CleanupMacroOrphans(plan)
  local registry = MM.DB:GetMacroRegistry()

  local wanted = {}
  for slot = 1, MM.MAX_ACTION_SLOT do
    local entry = plan.slots[slot]
    if entry and entry.resolved and MM.Macros.ResolvedAsMacro(entry.resolved) then
      wanted[entry.layerId] = wanted[entry.layerId] or {}
      wanted[entry.layerId][slot] = true
    end
  end

  for layerId, slots in pairs(registry) do
    for slot, record in pairs(slots) do
      if not (wanted[layerId] and wanted[layerId][slot]) then
        MM.Macros.DeleteOwned(record)
        slots[slot] = nil
      end
    end
    if next(slots) == nil then
      registry[layerId] = nil
    end
  end

  -- Safety net: delete any macro carrying our owner marker that no surviving
  -- registry record accounts for, recovering from a lost or desynced registry.
  local referenced = {}
  for _, slots in pairs(registry) do
    for _, record in pairs(slots) do
      referenced[(record.name or "") .. "\0" .. (record.bodyHash or "")] = true
    end
  end

  local orphanIndices = {}
  for _, macro in ipairs(MM.Macros.Scan()) do
    if MM.Macros.IsOwned(macro) and not referenced[macro.name .. "\0" .. macro.bodyHash] then
      orphanIndices[#orphanIndices + 1] = macro.index
    end
  end
  -- Delete from the highest index down so DeleteMacro's renumbering can't shift a
  -- still-pending target.
  table.sort(orphanIndices, function(left, right)
    return left > right
  end)
  for _, index in ipairs(orphanIndices) do
    MM.Macros.Delete(index)
  end
end

function Applier:ApplyProfile(profileId, options)
  options = options or {}

  local canApply, reason = self:CanApply()
  if not canApply then
    MM:Warn("cannot apply: " .. reason)
    return false
  end

  local plan, planReason = self:BuildPlan(profileId)
  if not plan then
    MM:Warn(planReason)
    return false
  end

  if #plan.conflicts > 0 and not options.allowConflicts then
    MM:Warn("cannot apply because active layers contain invalid slots. Use /mm preview for details.")
    return false
  end

  local updated = 0
  local failed = 0
  local issues = {} -- debug-only: failures and left-unchanged slots

  for slot = 1, MM.MAX_ACTION_SLOT do
    local entry = plan.slots[slot]
    if entry and not (entry.resolved and MM.Actions.IsResolvedInSlot(entry.resolved, slot)) then
      -- Capture the outgoing action before ApplyEntry overwrites the slot.
      local from = MM.Actions.GetLiveActionLabel(slot)
      local to = entry.resolved and self:DescribeTo(entry) or "empty"
      local ok, applyReason = self:ApplyEntry(entry)
      if ok and entry.resolved then
        updated = updated + 1
        MM:Print(string.format("%s: %s → %s", MM.Actions.GetSlotLabel(slot), from, to))
      elseif ok and applyReason == "cleared unresolved slot" then
        updated = updated + 1
        MM:Print(string.format("%s: %s → empty", MM.Actions.GetSlotLabel(slot), from))
      elseif ok then
        issues[#issues + 1] =
          string.format("%s: %s (left unchanged)", MM.Actions.GetSlotLabel(slot), tostring(entry.unresolvedReason))
      else
        failed = failed + 1
        issues[#issues + 1] = string.format("%s: %s", MM.Actions.GetSlotLabel(slot), applyReason)
      end
    end
  end

  self:CleanupMacroOrphans(plan)

  MM:Print(updated == 0 and "no changes" or (slotCount(updated) .. " updated"))

  if MM.DB:GetRoot().debug then
    for _, line in ipairs(issues) do
      MM:Debug(line)
    end
  end

  return failed == 0
end
