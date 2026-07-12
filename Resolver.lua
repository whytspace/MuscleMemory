local ADDON_NAME, MM = ...

local Resolver = {}
MM.Resolver = Resolver
MM:RegisterModule("Resolver", Resolver)

local function matchesRequirements(candidate)
  if not MM.Conditions.Match(candidate.conditions) then
    return false
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
    -- The Single Button Assistant isn't a "known" spell; gate it on whether the
    -- assisted-combat feature is available instead.
    local available
    if MM.Spells.IsAssistedCombatActionSpell(assignment.id) then
      available = MM.Spells.IsAssistedCombatAvailable()
    else
      available = MM.Spells.IsKnown(assignment.id)
    end
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
    local owned = MM.Items.IsOwned(assignment.id)
    local available = owned and MM.Items.IsUsable(assignment.id)
    if options.requireAvailable and not available then
      return nil, owned and "item not usable" or "item not owned"
    end
    if not (info or available) then
      return nil, "item not found"
    end
    return {
      kind = "item",
      id = assignment.id,
      label = info and info.name or ("item " .. tostring(assignment.id)),
      icon = info and info.icon,
      pickupAvailable = available,
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
    local available = MM.Mounts.IsKnown(assignment.id)
    if options.requireAvailable and not available then
      return nil, "mount not known"
    end
    if not info then
      return nil, "mount not found"
    end
    return { kind = "mount", id = assignment.id, label = info.name, icon = info.icon, pickupAvailable = available }
  end,

  equipmentset = function(assignment)
    if not MM.EquipmentSets.Exists(assignment.name) then
      return nil, "equipment set not found"
    end
    return { kind = "equipmentset", name = assignment.name, label = assignment.name, pickupAvailable = true }
  end,

  battlepet = function(assignment, options)
    local info = MM.BattlePets.GetInfo(assignment.id)
    local available = MM.BattlePets.IsKnown(assignment.id)
    if options.requireAvailable and not available then
      return nil, "battle pet not owned"
    end
    if not info then
      return nil, "battle pet not found"
    end
    return { kind = "battlepet", id = assignment.id, label = info.name, icon = info.icon, pickupAvailable = available }
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

  dynamicaction = function(assignment)
    return Resolver:ResolveDynamicActionAssignment(assignment)
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

-- All dynamic actions (predefined and the active profile's own) that currently
-- resolve to the given assignment on this character, as sorted `{ source, id,
-- name }` references. Backs the bind-time suggestion: "this spell is covered by
-- a dynamic action — bind that instead?". Only id-carrying kinds can match, so
-- macro and equipment-set assignments never suggest.
function Resolver:FindDynamicActionsResolvingTo(assignment)
  if not assignment or not assignment.id then
    return {}
  end

  local matches = {}
  local function check(source, id, dynamicAction)
    local resolved = self:ResolveAction({ type = "dynamicaction", source = source, id = id })
    if resolved and resolved.kind == assignment.type and resolved.id == assignment.id then
      matches[#matches + 1] = { source = source, id = id, name = dynamicAction.name or id }
    end
  end

  for id, dynamicAction in pairs(MM.PredefinedDynamicActions or {}) do
    check("predefined", id, dynamicAction)
  end
  for id, dynamicAction in pairs(MM.DB:DynamicActions() or {}) do
    check("custom", id, dynamicAction)
  end

  table.sort(matches, function(left, right)
    if left.name ~= right.name then
      return left.name < right.name
    end
    return left.source < right.source
  end)
  return matches
end

function Resolver:ResolveDynamicActionAssignment(assignment)
  local dynamicAction = MM.DB:ResolveDynamicAction({
    source = assignment.source,
    id = assignment.id,
  })

  if not dynamicAction then
    return nil, "dynamic action not found"
  end

  for _, candidate in ipairs(dynamicAction.candidates or {}) do
    if matchesRequirements(candidate) then
      local resolved = self:ResolveAction(candidate, { requireAvailable = true })
      if resolved then
        resolved.dynamicAction = dynamicAction
        return resolved
      end
    end
  end

  return nil, "dynamic action " .. tostring(dynamicAction.name or assignment.id) .. " had no matching candidate"
end
