local ADDON_NAME, MM = ...

-- Input validation for the public API boundary (see API.lua). Validators return
-- a normalized deep copy of their input, or nil and a reason — the copy is what
-- gets stored, so callers can never alias SavedVariables.

local Validate = {}
MM.Validate = Validate

-- Per-type required fields of an assignment. `id` entries are normalized with
-- tonumber; "any" ids (battle pet GUIDs) pass through as given.
local ASSIGNMENT_TYPES = {
  spell = { id = "number" },
  item = { id = "number" },
  mount = { id = "number" },
  flyout = { id = "number" },
  outfit = { id = "any" },
  battlepet = { id = "any" },
  macro = {},
  equipmentset = { name = "string" },
  empty = {},
  ignore = {},
  action = {},
}

local CONDITION_LISTS =
  { classes = true, specs = true, roles = true, factions = true, races = true, professions = true }

function Validate.Conditions(conditions)
  if conditions == nil then
    return nil
  end
  if type(conditions) ~= "table" then
    return nil, "conditions must be a table"
  end
  for key, value in pairs(conditions) do
    if CONDITION_LISTS[key] then
      if type(value) ~= "table" then
        return nil, "condition '" .. key .. "' must be a list"
      end
    elseif key == "levelMin" or key == "levelMax" then
      if type(value) ~= "number" then
        return nil, "condition '" .. key .. "' must be a number"
      end
    else
      return nil, "unknown condition '" .. tostring(key) .. "'"
    end
  end
  return MM.Tables.DeepCopy(conditions)
end

function Validate.Assignment(assignment)
  if type(assignment) ~= "table" then
    return nil, "assignment must be a table"
  end
  local fields = ASSIGNMENT_TYPES[assignment.type]
  if not fields then
    return nil, "unknown assignment type '" .. tostring(assignment.type) .. "'"
  end

  local result = MM.Tables.DeepCopy(assignment)
  for field, kind in pairs(fields) do
    local value = result[field]
    if kind == "number" then
      value = tonumber(value)
      if not value then
        return nil, assignment.type .. " assignment needs a numeric '" .. field .. "'"
      end
      result[field] = value
    elseif value == nil then
      return nil, assignment.type .. " assignment needs '" .. field .. "'"
    elseif kind == "string" and type(value) ~= "string" then
      return nil, assignment.type .. " assignment needs a string '" .. field .. "'"
    end
  end

  if assignment.type == "macro" and not (result.nameHint or result.bodyHash) then
    return nil, "macro assignment needs 'nameHint' or 'bodyHash'"
  end
  if assignment.type == "action" then
    if result.source ~= "custom" and result.source ~= "predefined" then
      return nil, "action assignment needs source 'custom' or 'predefined'"
    end
    if not MM.DB:ResolveSmartAction({ source = result.source, id = result.id }) then
      return nil, "unknown smart action '" .. tostring(result.id) .. "'"
    end
  end

  return result
end

-- A candidate is an assignment that resolves to something placeable, plus
-- optional conditions.
function Validate.Candidate(candidate)
  if type(candidate) ~= "table" then
    return nil, "candidate must be a table"
  end
  if candidate.type == "action" or candidate.type == "empty" or candidate.type == "ignore" then
    return nil, "'" .. candidate.type .. "' cannot be a candidate"
  end
  local result, reason = Validate.Assignment(candidate)
  if not result then
    return nil, reason
  end
  if candidate.conditions ~= nil then
    local conditions, conditionsReason = Validate.Conditions(candidate.conditions)
    if not conditions then
      return nil, conditionsReason
    end
    result.conditions = conditions
  end
  return result
end
