local ADDON_NAME, MM = ...

local Resolver = {}
MM.Resolver = Resolver
MM:RegisterModule("Resolver", Resolver)

local function matchesRequirements(candidate)
  if candidate.enabled == false then
    return false
  end

  if candidate.classes then
    local _, classFile = UnitClass("player")
    local matched = false
    for _, class in ipairs(candidate.classes) do
      if class == classFile then
        matched = true
        break
      end
    end
    if not matched then
      return false
    end
  end

  if candidate.requiresKnownSpell and not MM.Spells.IsKnown(candidate.requiresKnownSpell) then
    return false
  end

  if candidate.requiresItem and not MM.Items.IsOwned(candidate.requiresItem) then
    return false
  end

  return true
end

function Resolver:ResolveAction(assignment)
  if not assignment then
    return nil, "missing assignment"
  end

  if assignment.type == "ignore" then
    return {
      kind = "ignore",
      label = "Ignore",
    }
  end

  if assignment.type == "empty" then
    return {
      kind = "empty",
      label = "Empty",
    }
  end

  if assignment.type == "spell" then
    if MM.Spells.IsKnown(assignment.id) then
      local info = MM.Spells.GetInfo(assignment.id)
      return {
        kind = "spell",
        id = assignment.id,
        label = info and info.name or ("spell " .. tostring(assignment.id)),
        icon = info and info.icon,
      }
    end
    return nil, "spell not known"
  end

  if assignment.type == "item" then
    if MM.Items.IsOwned(assignment.id) then
      return {
        kind = "item",
        id = assignment.id,
        label = "item " .. tostring(assignment.id),
      }
    end
    return nil, "item not owned"
  end

  if assignment.type == "macro" then
    local macro, reason = MM.Macros.Resolve(assignment)
    if macro then
      return {
        kind = "macro",
        macro = macro,
        label = macro.name,
      }
    end
    return nil, reason
  end

  if assignment.type == "mount" then
    local info = MM.Mounts.GetInfo(assignment.id)
    if info and MM.Mounts.IsKnown(assignment.id) then
      return {
        kind = "mount",
        id = assignment.id,
        label = info.name,
        icon = info.icon,
      }
    end
    return nil, "mount not known"
  end

  if assignment.type == "equipmentset" then
    if MM.EquipmentSets.Exists(assignment.name) then
      return {
        kind = "equipmentset",
        name = assignment.name,
        label = assignment.name,
      }
    end
    return nil, "equipment set not found"
  end

  if assignment.type == "group" then
    return self:ResolveGroupAssignment(assignment)
  end

  return nil, "unsupported assignment type " .. tostring(assignment.type)
end

function Resolver:ResolveGroupAssignment(assignment)
  local group = MM.DB:GetGroup({
    source = assignment.source,
    id = assignment.id,
  })

  if not group then
    return nil, "group not found"
  end

  if assignment.source ~= "custom" and not MM.DB:IsStandardGroupEnabled(assignment.id) then
    return nil, "group disabled"
  end

  if group.enabled == false then
    return nil, "group disabled"
  end

  for _, candidate in ipairs(group.candidates or {}) do
    if matchesRequirements(candidate) then
      local resolved = self:ResolveAction(candidate)
      if resolved then
        resolved.group = group
        return resolved
      end
    end
  end

  return nil, "group " .. tostring(group.name or assignment.id) .. " had no matching candidate"
end

function Resolver:GetEffectiveFallback(assignment, layout)
  if assignment and assignment.unresolvedFallback and assignment.unresolvedFallback ~= "inherit" then
    return assignment.unresolvedFallback, "slot"
  end

  if assignment and assignment.type == "group" then
    local group = MM.DB:GetGroup({
      source = assignment.source,
      id = assignment.id,
    })
    if group and group.unresolvedFallback and group.unresolvedFallback ~= "inherit" then
      return group.unresolvedFallback, "group"
    end
  end

  if layout and layout.unresolvedFallback and layout.unresolvedFallback ~= "inherit" then
    return layout.unresolvedFallback, "layout"
  end

  return MM.DB:GetRoot().globalFallback or "keep", "global"
end
