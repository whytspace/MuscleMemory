local ADDON_NAME, MM = ...

local Applier = {}
MM.Applier = Applier
MM:RegisterModule("Applier", Applier)

function Applier:BuildPlan(profileId)
  local profile = MM.DB:GetProfile(profileId)
  if not profile then
    return nil, "profile not found"
  end

  local plan = {
    profileId = profileId or MM.DB:GetActiveProfileId(),
    slots = {},
    conflicts = {},
    layers = MM.DB:GetActiveLayers(profileId),
  }

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
            terminalEntry = entry
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
          MM:Print(string.format("%s -> %s", MM.Actions.GetSlotLabel(slot), entry.resolved.label))
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
        string.format("%d unresolved slots would be left unchanged. Use /mm debug to list them.", unresolvedKept)
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

  local pickedUp
  if entry.resolved.kind == "spell" then
    pickedUp = MM.Spells.Pickup(entry.resolved.id)
  elseif entry.resolved.kind == "item" then
    pickedUp = MM.Items.Pickup(entry.resolved.id)
  elseif entry.resolved.kind == "macro" then
    pickedUp = MM.Macros.Pickup(entry.resolved.macro)
  elseif entry.resolved.kind == "mount" then
    pickedUp = MM.Mounts.Pickup(entry.resolved.id)
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

function Applier:ApplyProfile(profileId, options)
  options = options or {}

  local canApply, reason = self:CanApply()
  if not canApply then
    if reason == "combat lockdown" then
      MM.Events:MarkPending(profileId or MM.DB:GetActiveProfileId(), reason)
    end
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
  local unchanged = 0
  local failed = 0

  for slot = 1, MM.MAX_ACTION_SLOT do
    local entry = plan.slots[slot]
    if entry then
      local ok, applyReason = self:ApplyEntry(entry)
      if ok then
        if entry.resolved then
          applied = applied + 1
        else
          unchanged = unchanged + 1
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

  MM.DB:GetCharacterState().pendingProfiles[plan.profileId] = nil

  MM:Print(string.format("applied %d slots, left %d unresolved, failed %d.", applied, unchanged, failed))
  return failed == 0
end
