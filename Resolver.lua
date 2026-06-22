local ADDON_NAME, MM = ...

local Resolver = {}
MM.Resolver = Resolver
MM:RegisterModule("Resolver", Resolver)

local function matchesRequirements(candidate)
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

-- One resolver per assignment type. Each returns a resolved action or (nil, reason).
local resolvers = {
  ignore = function()
    return { kind = "ignore", label = "Ignore" }
  end,

  empty = function()
    return { kind = "empty", label = "Empty" }
  end,

  spell = function(assignment, options)
    local info = MM.Spells.GetInfo(assignment.id)
    local available = MM.Spells.IsKnown(assignment.id)
    if options.requireAvailable and not available then
      return nil, "spell not known"
    end
    if not (info or available) then
      return nil, "spell not found"
    end
    return {
      kind = "spell",
      id = assignment.id,
      label = info and info.name or ("spell " .. tostring(assignment.id)),
      icon = info and info.icon,
      pickupAvailable = available,
    }
  end,

  item = function(assignment, options)
    local info = MM.Items.GetInfo(assignment.id)
    if options.requireAvailable and not MM.Items.IsOwned(assignment.id) then
      return nil, "item not owned"
    end
    if not (info or MM.Items.IsOwned(assignment.id)) then
      return nil, "item not found"
    end
    return {
      kind = "item",
      id = assignment.id,
      label = info and info.name or ("item " .. tostring(assignment.id)),
    }
  end,

  macro = function(assignment)
    local macro, reason = MM.Macros.Resolve(assignment)
    if not macro then
      return nil, reason
    end
    return { kind = "macro", macro = macro, label = macro.name }
  end,

  mount = function(assignment, options)
    local info = MM.Mounts.GetInfo(assignment.id)
    if options.requireAvailable and not MM.Mounts.IsKnown(assignment.id) then
      return nil, "mount not known"
    end
    if not info then
      return nil, "mount not found"
    end
    return { kind = "mount", id = assignment.id, label = info.name, icon = info.icon }
  end,

  equipmentset = function(assignment)
    if not MM.EquipmentSets.Exists(assignment.name) then
      return nil, "equipment set not found"
    end
    return { kind = "equipmentset", name = assignment.name, label = assignment.name }
  end,

  flyout = function(assignment, options)
    local info = MM.Flyouts.GetInfo(assignment.id)
    local available = MM.Flyouts.IsKnown(assignment.id)
    if options.requireAvailable and not available then
      return nil, "flyout not known"
    end
    if not info then
      return nil, "flyout not found"
    end
    return {
      kind = "flyout",
      id = assignment.id,
      label = info.name,
      icon = info.icon,
      pickupAvailable = available,
    }
  end,

  memory = function(assignment)
    return Resolver:ResolveMemoryAssignment(assignment)
  end,
}

function Resolver:ResolveAction(assignment, options)
  if not assignment then
    return nil, "missing assignment"
  end

  local resolve = resolvers[assignment.type]
  if not resolve then
    return nil, "unsupported assignment type " .. tostring(assignment.type)
  end

  return resolve(assignment, options or {})
end

function Resolver:ResolveMemoryAssignment(assignment)
  local memory = MM.DB:GetMemory({
    source = assignment.source,
    id = assignment.id,
  })

  if not memory then
    return nil, "memory not found"
  end

  for _, candidate in ipairs(memory.candidates or {}) do
    if matchesRequirements(candidate) then
      local resolved = self:ResolveAction(candidate, { requireAvailable = true })
      if resolved then
        resolved.memory = memory
        return resolved
      end
    end
  end

  return nil, "memory " .. tostring(memory.name or assignment.id) .. " had no matching candidate"
end
