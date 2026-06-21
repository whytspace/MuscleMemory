local ADDON_NAME, MM = ...

local Applier = {}
MM.Applier = Applier
MM:RegisterModule("Applier", Applier)

local function sortedActiveLayouts(profile)
  local active = {}
  for layoutId, config in pairs(profile.activeLayouts or {}) do
    if config.enabled ~= false then
      active[#active + 1] = {
        id = layoutId,
        order = config.order or 100,
      }
    end
  end

  table.sort(active, function(left, right)
    if left.order == right.order then
      return left.id < right.id
    end
    return left.order < right.order
  end)

  return active
end

function Applier:BuildPlan(profileId)
  local profile = MM.DB:GetProfile(profileId)
  if not profile then
    return nil, "profile not found"
  end

  local plan = {
    profileId = profileId or MM.DB:GetActiveProfileId(),
    slots = {},
    conflicts = {},
  }

  for _, activeLayout in ipairs(sortedActiveLayouts(profile)) do
    local layout = MM.DB:GetLayout(activeLayout.id)
    if layout and layout.enabled ~= false then
      for slot, assignment in pairs(layout.slots or {}) do
        local numericSlot = tonumber(slot)
        if not MM.Actions.IsValidSlot(numericSlot) then
          plan.conflicts[#plan.conflicts + 1] = {
            slot = tostring(slot),
            firstLayout = activeLayout.id,
            secondLayout = "invalid slot",
          }
        elseif plan.slots[numericSlot] then
          plan.conflicts[#plan.conflicts + 1] = {
            slot = numericSlot,
            firstLayout = plan.slots[numericSlot].layoutId,
            secondLayout = activeLayout.id,
          }
        else
          local resolved, reason = MM.Resolver:ResolveAction(assignment)
          local fallback, fallbackSource = MM.Resolver:GetEffectiveFallback(assignment, layout)
          plan.slots[numericSlot] = {
            slot = numericSlot,
            layoutId = activeLayout.id,
            layout = layout,
            assignment = assignment,
            resolved = resolved,
            unresolvedReason = reason,
            fallback = fallback,
            fallbackSource = fallbackSource,
          }
        end
      end
    end
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
          "slot %d is assigned by both %s and %s.",
          conflict.slot,
          conflict.firstLayout,
          conflict.secondLayout
        )
      )
    end
  end

  local count = 0
  for slot, entry in pairs(plan.slots) do
    count = count + 1
    local label = entry.resolved and entry.resolved.label or ("unresolved: " .. tostring(entry.unresolvedReason))
    MM:Print(string.format("%s -> %s", MM.Actions.GetSlotLabel(slot), label))
  end

  MM:Print(string.format("previewed %d managed slots.", count))
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
    MM:Warn("cannot apply because active layouts contain slot conflicts. Use /mm preview for details.")
    return false
  end

  local applied = 0
  local unchanged = 0
  local failed = 0

  for _, entry in pairs(plan.slots) do
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

  local state = MM.DB:GetCharacterState()
  state.lastApplied[plan.profileId] = time()
  state.pendingProfiles[plan.profileId] = nil

  MM:Print(string.format("applied %d slots, left %d unresolved, failed %d.", applied, unchanged, failed))
  return failed == 0
end
