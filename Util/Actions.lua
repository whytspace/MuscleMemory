local ADDON_NAME, MM = ...

local Actions = {}
MM.Actions = Actions

-- The eight standard action bars in Edit Mode order, each 12 buttons. WoW's
-- action-slot numbering does NOT run linearly with the visible bar order: only
-- Bar 1 is slots 1-12; the rest map to scattered MultiBar ranges (the slots in
-- between are the main bar's stance/paging pages, not separate bars). `base` is
-- the slot before each bar's first button.
Actions.BARS = {
  { base = 0 }, -- Bar 1  · slots 1-12    (main)
  { base = 60 }, -- Bar 2  · slots 61-72   (bottom left)
  { base = 48 }, -- Bar 3  · slots 49-60   (bottom right)
  { base = 24 }, -- Bar 4  · slots 25-36   (right)
  { base = 36 }, -- Bar 5  · slots 37-48   (left)
  { base = 144 }, -- Bar 6  · slots 145-156
  { base = 156 }, -- Bar 7  · slots 157-168
  { base = 168 }, -- Bar 8  · slots 169-180
}

local function normalizeText(text)
  return string.lower(tostring(text or ""))
end

local function getAssignmentName(assignment)
  if not assignment then
    return nil
  end

  if assignment.type == "spell" then
    local info = MM.Spells.GetInfo(assignment.id)
    return info and info.name or nil
  end

  if assignment.type == "item" then
    local info = MM.Items.GetInfo(assignment.id)
    return info and info.name or nil
  end

  if assignment.type == "macro" then
    return assignment.nameHint
  end

  if assignment.type == "mount" then
    local info = MM.Mounts.GetInfo(assignment.id)
    return info and info.name or nil
  end

  if assignment.type == "equipmentset" then
    return assignment.name
  end

  return nil
end

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
  for index, bar in ipairs(Actions.BARS) do
    if slot > bar.base and slot <= bar.base + MM.ACTIONS_PER_BAR then
      return string.format("bar %d button %d", index, slot - bar.base)
    end
  end
  -- Stance / paging / vehicle slots that aren't one of the eight visible bars.
  return string.format("slot %d", slot)
end

function Actions.GetAssignmentLabel(assignment)
  if not assignment then
    return "Ignore"
  end

  if assignment.type == "ignore" then
    return "Ignore"
  end

  if assignment.type == "empty" then
    return "Empty"
  end

  if assignment.type == "memory" then
    local memory = MM.DB:GetMemory({ source = assignment.source, id = assignment.id })
    return memory and memory.name or ("Memory: " .. tostring(assignment.id))
  end

  if assignment.type == "spell" then
    local info = MM.Spells.GetInfo(assignment.id)
    if info and info.name then
      return string.format("%s (spell %s)", info.name, tostring(assignment.id))
    end
    return "Spell ID: " .. tostring(assignment.id)
  end

  if assignment.type == "item" then
    local info = MM.Items.GetInfo(assignment.id)
    if info and info.name then
      return string.format("%s (item %s)", info.name, tostring(assignment.id))
    end
    return "Item ID: " .. tostring(assignment.id)
  end

  if assignment.type == "macro" then
    return "Macro: " .. tostring(assignment.nameHint or assignment.bodyHash)
  end

  if assignment.type == "mount" then
    local info = MM.Mounts.GetInfo(assignment.id)
    return info and info.name or ("Mount ID: " .. tostring(assignment.id))
  end

  if assignment.type == "equipmentset" then
    return "Equipment Set: " .. tostring(assignment.name)
  end

  return assignment.type or "Unknown"
end

function Actions.GetRawSlotLabel(slot)
  local info = Actions.GetInfo(slot)
  if not info then
    return "no action info"
  end

  local text = GetActionText and GetActionText(slot) or nil
  return string.format(
    "current slot: type=%s id=%s subtype=%s text=%s",
    tostring(info.actionType),
    tostring(info.id),
    tostring(info.subType),
    tostring(text)
  )
end

function Actions.GetLiveSlotIcon(slot)
  if not Actions.IsValidSlot(slot) or not GetActionTexture then
    return nil
  end

  return GetActionTexture(slot)
end

function Actions.GetAssignmentIcon(assignment, slot)
  if not assignment then
    return Actions.GetLiveSlotIcon(slot)
  end

  if assignment.type == "empty" then
    return nil
  end

  if assignment.type == "memory" then
    local resolved = MM.Resolver:ResolveAction(assignment)
    return resolved and resolved.icon or nil
  end

  if assignment.type == "spell" then
    local info = MM.Spells.GetInfo(assignment.id)
    return info and info.icon or nil
  end

  if assignment.type == "item" then
    local info = MM.Items.GetInfo(assignment.id)
    return info and info.icon or nil
  end

  if assignment.type == "macro" then
    return assignment.iconHint
  end

  if assignment.type == "mount" then
    local info = MM.Mounts.GetInfo(assignment.id)
    return info and info.icon or nil
  end

  return Actions.GetLiveSlotIcon(slot)
end

function Actions.GetAssignmentIconState(assignment, slot)
  if not assignment then
    return {
      kind = "icon",
      texture = Actions.GetLiveSlotIcon(slot),
    }
  end

  if assignment.type == "empty" then
    return { kind = "empty" }
  end

  if assignment.type == "ignore" then
    return { kind = "ignore" }
  end

  if assignment.type == "memory" then
    local resolved = MM.Resolver:ResolveAction(assignment)
    if resolved then
      if resolved.kind == "empty" then
        return { kind = "empty" }
      end

      if resolved.kind == "ignore" then
        return { kind = "ignore" }
      end

      return {
        kind = "icon",
        texture = resolved.icon,
      }
    end

    if MM.DB:GetFallback() == "clear" then
      return { kind = "empty" }
    end

    return { kind = "preserve" }
  end

  local texture = Actions.GetAssignmentIcon(assignment, slot)
  if texture then
    return {
      kind = "icon",
      texture = texture,
    }
  end

  return { kind = "preserve" }
end

-- Does the live action in `slot` match a target identity? `target` carries a
-- `kind` plus whichever identity fields that kind needs (id, name, bodyHash,
-- macroIndex, setName). Shared by IsAssignmentInSlot and IsResolvedInSlot.
local function slotMatches(slot, target)
  if target.kind == "ignore" then
    return true
  end

  if target.kind == "empty" then
    return not (not HasAction or HasAction(slot))
  end

  local info = Actions.GetInfo(slot)
  if not info or not info.actionType then
    return false
  end

  if target.kind == "spell" then
    if info.actionType == "spell" and info.id == target.id then
      return true
    end
    if GetActionText and target.name then
      return normalizeText(GetActionText(slot)) == normalizeText(target.name)
    end
    return false
  end

  if target.kind == "item" then
    return info.actionType == "item" and info.id == target.id
  end

  if target.kind == "macro" then
    if info.actionType ~= "macro" then
      return false
    end
    if target.macroIndex and info.id == target.macroIndex then
      return true
    end
    if not target.bodyHash then
      return false
    end
    -- info.id may not be a usable macro index in this client: try it directly,
    -- then fall back to the slot's macro name + the stored body hash via a scan.
    if GetMacroInfo then
      local _, _, body = GetMacroInfo(info.id)
      if body and MM.Macros.HashBody(body) == target.bodyHash then
        return true
      end
    end
    local name = GetActionText and GetActionText(slot)
    if name then
      for _, macro in ipairs(MM.Macros.Scan()) do
        if macro.name == name and macro.bodyHash == target.bodyHash then
          return true
        end
      end
    end
    return false
  end

  if target.kind == "mount" then
    return (
      info.actionType == "mount"
      or info.actionType == "summonmount"
      or (info.actionType == "companion" and info.subType == "MOUNT")
    ) and info.id == target.id
  end

  if target.kind == "equipmentset" then
    if info.actionType ~= "equipmentset" or not C_EquipmentSet or not C_EquipmentSet.GetEquipmentSetInfo then
      return false
    end
    return C_EquipmentSet.GetEquipmentSetInfo(info.id) == target.setName
  end

  return false
end

function Actions.IsAssignmentInSlot(assignment, slot)
  if not assignment then
    return true
  end

  return slotMatches(slot, {
    kind = assignment.type,
    id = assignment.id,
    name = getAssignmentName(assignment),
    bodyHash = assignment.bodyHash,
    macroIndex = assignment.indexHint,
    setName = assignment.name,
  })
end

function Actions.IsResolvedInSlot(resolved, slot)
  if not resolved then
    return false
  end

  return slotMatches(slot, {
    kind = resolved.kind,
    id = resolved.id,
    name = resolved.label,
    bodyHash = resolved.macro and resolved.macro.bodyHash,
    macroIndex = resolved.macro and resolved.macro.index,
    setName = resolved.name,
  })
end
