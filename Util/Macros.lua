local ADDON_NAME, MM = ...

local Macros = {}
MM.Macros = Macros

local function hashString(text)
  text = text or ""
  local hash = 5381
  for index = 1, #text do
    hash = (hash * 33 + string.byte(text, index)) % 4294967296
  end
  return string.format("%08x", hash)
end

function Macros.HashBody(body)
  return hashString(body)
end

function Macros.GetMacroScope(index, globalCount)
  local maxAccount = MAX_ACCOUNT_MACROS or 120
  if index <= globalCount or index <= maxAccount then
    return "global"
  end
  return "character"
end

function Macros.Scan()
  local results = {}
  if not GetNumMacros or not GetMacroInfo then
    return results
  end

  local globalCount, characterCount = GetNumMacros()
  globalCount = globalCount or 0
  characterCount = characterCount or 0

  for index = 1, globalCount do
    local name, icon, body = GetMacroInfo(index)
    if name then
      results[#results + 1] = {
        index = index,
        scope = "global",
        name = name,
        icon = icon,
        body = body or "",
        bodyHash = Macros.HashBody(body),
      }
    end
  end

  local firstCharacterIndex = (MAX_ACCOUNT_MACROS or 120) + 1
  for offset = 0, characterCount - 1 do
    local index = firstCharacterIndex + offset
    local name, icon, body = GetMacroInfo(index)
    if name then
      results[#results + 1] = {
        index = index,
        scope = "character",
        name = name,
        icon = icon,
        body = body or "",
        bodyHash = Macros.HashBody(body),
      }
    end
  end

  return results
end

function Macros.FindUniqueByName(name)
  if not name then
    return nil, "macro name unavailable"
  end

  local match
  local count = 0
  for _, macro in ipairs(Macros.Scan()) do
    if macro.name == name then
      match = macro
      count = count + 1
    end
  end

  if count == 1 then
    return match
  end

  if count > 1 then
    return nil, "macro name is ambiguous"
  end

  return nil, "macro name not found"
end

-- Best-effort lookup of the macro shown on `slot`. The slot's action id isn't a
-- reliable macro index, so match by name and disambiguate same-named macros by
-- the slot's icon, falling back to the first match.
function Macros.FindForSlot(name, slot)
  if not name then
    return nil, "macro name unavailable"
  end

  local matches = {}
  for _, macro in ipairs(Macros.Scan()) do
    if macro.name == name then
      matches[#matches + 1] = macro
    end
  end

  if #matches == 0 then
    return nil, "macro name not found"
  end
  if #matches == 1 then
    return matches[1]
  end

  local texture = slot and GetActionTexture and GetActionTexture(slot)
  if texture then
    for _, macro in ipairs(matches) do
      if macro.icon == texture then
        return macro
      end
    end
  end
  return matches[1]
end

function Macros.Resolve(reference)
  if not reference or not reference.bodyHash then
    return nil, "macro reference has no body hash"
  end

  local macros = Macros.Scan()
  for _, macro in ipairs(macros) do
    if macro.index == reference.indexHint and macro.bodyHash == reference.bodyHash then
      return macro
    end
  end

  for _, macro in ipairs(macros) do
    if macro.scope == reference.scope and macro.bodyHash == reference.bodyHash then
      return macro
    end
  end

  for _, macro in ipairs(macros) do
    if macro.bodyHash == reference.bodyHash then
      return macro
    end
  end

  return nil, "macro body hash not found"
end

function Macros.Pickup(macro)
  if not macro or not macro.index then
    return false
  end

  if PickupMacro then
    PickupMacro(macro.index)
    return true
  end

  return false
end
