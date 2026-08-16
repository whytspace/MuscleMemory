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
    -- An override id (spec/talent rename) is neither known nor placeable;
    -- resolve on its base spell instead.
    local id = MM.Spells.GetBaseSpell(assignment.id)
    local info = MM.Spells.GetInfo(id)
    -- The Single Button Assistant isn't a "known" spell; gate it on whether the
    -- assisted-combat feature is available instead.
    local available
    if MM.Spells.IsAssistedCombatActionSpell(id) then
      available = MM.Spells.IsAssistedCombatAvailable()
    else
      available = MM.Spells.IsKnown(id)
    end
    if options.requireAvailable and not available then
      return nil, "spell not known"
    end
    if not (info or available) then
      return nil, "spell not found"
    end
    return {
      kind = "spell",
      id = id,
      label = info and info.name or ("spell " .. tostring(id)),
      icon = info and info.icon,
      pickupAvailable = available,
    }
  end,

  item = function(assignment, options)
    local info = MM.Items.GetInfo(assignment.id)
    local owned = MM.Items.IsOwned(assignment.id)
    local usable = MM.Items.IsUsable(assignment.id) -- ownership-independent
    -- Smart-action candidates need the item in hand; a plain assignment doesn't.
    if options.requireAvailable and not (owned and usable) then
      return nil, owned and "item not usable" or "item not owned"
    end
    -- Place a usable item even if unowned (WoW greys it); an unusable one falls through.
    if not usable then
      return nil, "item not usable"
    end
    return {
      kind = "item",
      id = assignment.id,
      label = info and info.name or ("item " .. tostring(assignment.id)),
      icon = info and info.icon,
      pickupAvailable = true,
    }
  end,

  macro = function(assignment)
    local macro, reason, state = MM.Macros.Resolve(assignment)
    if macro then
      return { kind = "macro", macro = macro, label = macro.name }
    end
    -- A stored body makes a *missing* macro restorable: apply recreates it in
    -- its captured scope. An ambiguous name stays an error — creating another
    -- same-named macro would make it worse. Resolution itself never creates
    -- anything (it runs in previews and the login change-scan).
    if state == "missing" and assignment.body and assignment.nameHint then
      return {
        kind = "macro",
        restore = {
          name = assignment.nameHint,
          body = assignment.body,
          scope = assignment.scope,
          -- The player's picked icon (dynamic "?" or hardcoded id) as captured;
          -- iconHint is display-only. Fall back to iconHint for captures saved
          -- before restoreIcon existed.
          icon = assignment.restoreIcon or assignment.iconHint,
        },
        label = assignment.nameHint,
        icon = assignment.iconHint,
      }
    end
    return nil, reason
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

  outfit = function(assignment)
    local info = MM.Outfits.GetInfo(assignment.id)
    if not info then
      return nil, "outfit not found"
    end
    return { kind = "outfit", id = assignment.id, label = info.name, icon = info.icon, pickupAvailable = true }
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

  action = function(assignment)
    return Resolver:ResolveSmartActionAssignment(assignment)
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

-- All smart actions (predefined and the active profile's own) that currently
-- resolve to the given assignment on this character, as sorted `{ source, id,
-- name }` references. Backs the bind-time suggestion: "this spell is covered by
-- a smart action — bind that instead?". A captured macro matches the smart
-- action that generated it (same rendered body, or the owner-marked name after
-- the resolution changed); equipment sets never suggest.
function Resolver:FindSmartActionsResolvingTo(assignment)
  if not assignment or not (assignment.id or assignment.type == "macro") then
    return {}
  end

  local matches = {}
  local function check(source, id, smartAction)
    local resolved = self:ResolveAction({ type = "action", source = source, id = id })
    if not resolved then
      return
    end
    local match
    if assignment.type == "macro" then
      local body = MM.Macros.ResolvedAsMacro(resolved)
      match = (body and MM.Macros.HashBody(body) == assignment.bodyHash)
        or (
          body
          and MM.Macros.IsOwned({ name = assignment.nameHint })
          and MM.Macros.MacroName(smartAction) == assignment.nameHint
        )
    else
      -- Spells compare on the base id: resolution normalises overrides there.
      local targetId = assignment.type == "spell" and MM.Spells.GetBaseSpell(assignment.id) or assignment.id
      match = resolved.kind == assignment.type and resolved.id == targetId
    end
    if match then
      matches[#matches + 1] = { source = source, id = id, name = smartAction.name or id }
    end
  end

  for id, smartAction in pairs(MM.PredefinedSmartActions or {}) do
    check("predefined", id, smartAction)
  end
  for id, smartAction in pairs(MM.DB:SmartActions() or {}) do
    check("custom", id, smartAction)
  end

  table.sort(matches, function(left, right)
    if left.name ~= right.name then
      return left.name < right.name
    end
    return left.source < right.source
  end)
  return matches
end

function Resolver:ResolveSmartActionAssignment(assignment)
  local smartAction = MM.DB:ResolveSmartAction({
    source = assignment.source,
    id = assignment.id,
  })

  if not smartAction then
    return nil, "smart action not found"
  end

  for _, candidate in ipairs(smartAction.candidates or {}) do
    if matchesRequirements(candidate) then
      local resolved = self:ResolveAction(candidate, { requireAvailable = true })
      if resolved then
        resolved.smartAction = smartAction
        return resolved
      end
    end
  end

  return nil, "smart action " .. tostring(smartAction.name or assignment.id) .. " had no matching candidate"
end

-- Ask the client, once and early, everything the profile will later be judged
-- against. Some answers are computed on first ask rather than streamed in --
-- C_ToyBox.IsToyUsable returns nil until something requests it, then the real
-- verdict -- so whoever asks first reads a blank and, at login, that is the
-- change scan: it sees an unusable toy as usable and raises a phantom change.
-- Answers are discarded; the asking is the point.
--
-- Deliberately ignores layer enablement and conditions: at login the spec isn't
-- readable yet, so the matching subset isn't known, and a layer the player
-- enables or swaps spec into later has to be warm too.
function Resolver:WarmClientData(profileId)
  for _, entry in ipairs(MM.DB:GetProfileLayers(profileId)) do
    for _, assignment in pairs(entry.layer.slots or {}) do
      if assignment.type == "action" then
        local smartAction = MM.DB:ResolveSmartAction({ source = assignment.source, id = assignment.id })
        -- Every candidate, not just the one that would win: resolution stops at
        -- the first hit, which leaves the rest cold for the read that decides.
        for _, candidate in ipairs(smartAction and smartAction.candidates or {}) do
          self:ResolveAction(candidate, { requireAvailable = true })
        end
      else
        self:ResolveAction(assignment)
      end
    end
  end
end
