local ADDON_NAME, MM = ...

local Tables = {}
MM.Tables = Tables

function Tables.DeepCopy(value)
  if type(value) ~= "table" then
    return value
  end

  local copy = {}
  for key, child in pairs(value) do
    copy[Tables.DeepCopy(key)] = Tables.DeepCopy(child)
  end
  return copy
end

-- Structural equality: same keys, same (recursively equal) values.
function Tables.DeepEquals(left, right)
  if left == right then
    return true
  end
  if type(left) ~= "table" or type(right) ~= "table" then
    return false
  end
  for key, value in pairs(left) do
    if not Tables.DeepEquals(value, right[key]) then
      return false
    end
  end
  for key in pairs(right) do
    if left[key] == nil then
      return false
    end
  end
  return true
end

function Tables.MergeDefaults(target, defaults)
  if type(target) ~= "table" then
    target = {}
  end

  for key, defaultValue in pairs(defaults) do
    if type(defaultValue) == "table" then
      target[key] = Tables.MergeDefaults(target[key], defaultValue)
    elseif target[key] == nil then
      target[key] = defaultValue
    end
  end

  return target
end

function Tables.Count(map)
  local count = 0
  for _ in pairs(map or {}) do
    count = count + 1
  end
  return count
end

-- The entry a selection should move to when the one identified by `id` is
-- removed from an ordered list: the one below it, else the one above, else nil.
-- Call it before the removal, on the list as displayed.
function Tables.NeighbourById(list, id)
  for index, entry in ipairs(list or {}) do
    if entry.id == id then
      return list[index + 1] or list[index - 1]
    end
  end
  return nil
end
