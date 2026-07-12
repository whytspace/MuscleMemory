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

function Applier:PreviewProfile(profileId)
  local plan, reason = self:BuildPlan(profileId)
  if not plan then
    MM:Warn(reason)
    return nil
  end

  if #plan.conflicts > 0 then
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
  end

  local managed = 0
  local changed = 0
  local unchanged = 0
  local unresolvedKept = 0
  local unresolvedCleared = 0
  local unresolvedKeptEntries = {}
  local unrestorableEntries = {}
  local unavailable = 0
  for slot = 1, MM.MAX_ACTION_SLOT do
    local entry = plan.slots[slot]
    if entry then
      managed = managed + 1

      if entry.resolved then
        if MM.Actions.IsResolvedInSlot(entry.resolved, slot) then
          unchanged = unchanged + 1
        elseif entry.resolved.pickupAvailable == false then
          unavailable = unavailable + 1
          unchanged = unchanged + 1
          MM:Warn(
            string.format(
              "%s cannot restore %s because it is not currently available.",
              MM.Actions.GetSlotLabel(slot),
              entry.resolved.label
            )
          )
        else
          changed = changed + 1
          local label = entry.resolved.label
          local macroBody = MM.Macros.ResolvedAsMacro(entry.resolved)
          if macroBody then
            local record = MM.DB:GetMacroRecord(entry.layerId, slot)
            local verb = MM.Macros.WouldUpdate(record, macroBody) and "updates the macro" or "creates a macro"
            label = label .. " (" .. verb .. ")"
          end
          MM:Print(string.format("%s -> %s", MM.Actions.GetSlotLabel(slot), label))
        end
      elseif entry.fallback == "clear" then
        if HasAction and HasAction(slot) then
          changed = changed + 1
          unresolvedCleared = unresolvedCleared + 1
          MM:Print(
            string.format("%s -> clear unresolved slot (%s)", MM.Actions.GetSlotLabel(slot), entry.unresolvedReason)
          )
        else
          unchanged = unchanged + 1
        end
      elseif MM.Actions.IsAssignmentInSlot(entry.assignment, slot) then
        unchanged = unchanged + 1
        unrestorableEntries[#unrestorableEntries + 1] = entry
      else
        unchanged = unchanged + 1
        unresolvedKept = unresolvedKept + 1
        unresolvedKeptEntries[#unresolvedKeptEntries + 1] = entry
      end
    end
  end

  if MM.DB:GetRoot().debug and #unrestorableEntries > 0 then
    for _, entry in ipairs(unrestorableEntries) do
      MM:Debug(
        string.format(
          "%s currently matches but is not restorable: %s (%s).",
          MM.Actions.GetSlotLabel(entry.slot),
          tostring(entry.unresolvedReason),
          MM.Actions.GetAssignmentLabel(entry.assignment)
        )
      )
      MM:Debug(MM.Actions.GetRawSlotLabel(entry.slot))
    end
  end

  if changed == 0 then
    MM:Print(string.format("previewed %d managed slots: no changes.", managed))
  else
    MM:Print(string.format("previewed %d managed slots: %d would change, %d unchanged.", managed, changed, unchanged))
  end

  if unresolvedCleared > 0 then
    MM:Print(string.format("%d unresolved slots would be cleared by fallback.", unresolvedCleared))
  end

  if unavailable > 0 then
    MM:Print(string.format("%d managed slots cannot currently be restored.", unavailable))
  end

  if unresolvedKept > 0 then
    if MM.DB:GetRoot().debug then
      for _, entry in ipairs(unresolvedKeptEntries) do
        MM:Debug(
          string.format(
            "%s unresolved: %s. Fallback keep leaves it unchanged.",
            MM.Actions.GetSlotLabel(entry.slot),
            tostring(entry.unresolvedReason) .. " (" .. MM.Actions.GetAssignmentLabel(entry.assignment) .. ")"
          )
        )
        MM:Debug(MM.Actions.GetRawSlotLabel(entry.slot))
      end
    else
      MM:Print(
        string.format(
          "%d unresolved slots would be left unchanged. Enable debug (/mm debug), then preview again to list them.",
          unresolvedKept
        )
      )
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

  local applied = 0
  local skipped = 0
  local unresolved = 0
  local failed = 0

  for slot = 1, MM.MAX_ACTION_SLOT do
    local entry = plan.slots[slot]
    if entry then
      if entry.resolved and MM.Actions.IsResolvedInSlot(entry.resolved, slot) then
        skipped = skipped + 1
      else
        local ok, applyReason = self:ApplyEntry(entry)
        if ok then
          if entry.resolved then
            applied = applied + 1
          else
            unresolved = unresolved + 1
            MM:Warn(
              string.format(
                "%s unresolved: %s. %s.",
                MM.Actions.GetSlotLabel(entry.slot),
                entry.unresolvedReason,
                entry.fallback == "clear" and "Cleared slot" or "Left existing action unchanged"
              )
            )
          end
        else
          failed = failed + 1
          MM:Warn(string.format("%s failed: %s", MM.Actions.GetSlotLabel(entry.slot), applyReason))
        end
      end
    end
  end

  self:CleanupMacroOrphans(plan)

  MM:Print(
    string.format(
      "applied %d slots, skipped %d unchanged, left %d unresolved, failed %d.",
      applied,
      skipped,
      unresolved,
      failed
    )
  )
  return failed == 0
end
