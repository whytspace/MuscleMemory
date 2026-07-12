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
  -- The client appends a trailing newline when it persists a macro, so the body
  -- read back after a reload (46 bytes) differs from what we render (45). Strip
  -- trailing whitespace before hashing so the idempotency check survives a reload
  -- instead of reporting a permanent pending change.
  body = (body or ""):gsub("%s+$", "")
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
    return nil, string.format("macro name %q is ambiguous", name)
  end

  return nil, string.format("macro %q not found", name)
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

  -- Name fallback: the body changed (edited, or another character's copy of an
  -- addon-generated macro), but a macro of the captured name still exists —
  -- bind that; the exact hash matches above always win. Same scope preferred;
  -- an ambiguous name is a real error the user must resolve, not a guess.
  -- EnsureMacro passes no name, so generated macros never reuse by name.
  local name = reference.nameHint or reference.name
  if name then
    local inScope, anywhere = {}, {}
    for _, macro in ipairs(macros) do
      if macro.name == name then
        anywhere[#anywhere + 1] = macro
        if macro.scope == reference.scope then
          inScope[#inScope + 1] = macro
        end
      end
    end
    local pool = #inScope > 0 and inScope or anywhere
    if #pool == 1 then
      return pool[1]
    end
    if #pool > 1 then
      return nil, string.format("macro name %q is ambiguous", name)
    end
    return nil, string.format("macro %q not found", name), "missing"
  end

  return nil, "macro body hash not found", "missing"
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

-- Macro mode -----------------------------------------------------------------
-- A dynamicAction whose every candidate is in this family can render as a generated
-- macro: the `/use` verb invokes spell, item (incl. toys) and mount by name, so a
-- single `%name%` template covers them all. Battle pets (`/summonpet`), equipment
-- sets (`/equipset`) and flyouts have no place in such a macro and are excluded.
Macros.FAMILY = { spell = true, item = true, mount = true }

-- True only when the dynamicAction has candidates and every one is macro-able. Derived,
-- never stored: the toggle persists as intent, compatibility follows the list.
function Macros.CandidatesCompatible(dynamicAction)
  local candidates = dynamicAction and dynamicAction.candidates
  if not candidates or #candidates == 0 then
    return false
  end
  for _, candidate in ipairs(candidates) do
    if not Macros.FAMILY[candidate.type] then
      return false
    end
  end
  return true
end

-- The display name a candidate contributes to %name%. Only the macro-able family
-- matters; others can't be in a macro-mode dynamicAction anyway.
local function candidateName(candidate)
  if candidate.type == "spell" then
    local info = MM.Spells.GetInfo(candidate.id)
    return info and info.name
  elseif candidate.type == "item" then
    local info = MM.Items.GetInfo(candidate.id)
    return info and info.name
  elseif candidate.type == "mount" then
    local info = MM.Mounts.GetInfo(candidate.id)
    return info and info.name
  end
  return nil
end

-- Length of the body `template` would produce for a given name/id, uncapped (so
-- the editor can show how far over the limit it is).
function Macros.RenderedLength(template, name, id)
  local body = (template or ""):gsub("%%name%%", (tostring(name or ""):gsub("%%", "%%%%")))
  body = body:gsub("%%id%%", (tostring(id or ""):gsub("%%", "%%%%")))
  return #body
end

-- The longest body any candidate would render to: the candidate whose name pushes
-- the macro closest to (or past) the 255 cap. Candidates with names not yet known
-- are skipped; the applier's own render cap is the final guard for those.
function Macros.WorstCaseLength(dynamicAction, template)
  template = template or (dynamicAction and dynamicAction.macroTemplate) or MM.MACRO_TEMPLATE_DEFAULT
  local worst = Macros.RenderedLength(template, "", "")
  for _, candidate in ipairs(dynamicAction and dynamicAction.candidates or {}) do
    if Macros.FAMILY[candidate.type] then
      local name = candidateName(candidate)
      if name then
        local length = Macros.RenderedLength(template, name, candidate.id)
        if length > worst then
          worst = length
        end
      end
    end
  end
  return worst
end

-- True when every candidate's rendered body fits the 255-char macro cap.
function Macros.FitsLimit(dynamicAction, template)
  return Macros.WorstCaseLength(dynamicAction, template) <= MM.MACRO_BODY_LIMIT
end

-- The mode actually used at apply time: "macro" only when the dynamicAction opted in, its
-- candidates are all macro-able, AND the body fits the 255-char cap; else "normal".
-- Single source of truth shared by the applier, the idempotency check, the editor.
function Macros.EffectiveMode(dynamicAction)
  if
    dynamicAction
    and dynamicAction.mode == "macro"
    and Macros.CandidatesCompatible(dynamicAction)
    and Macros.FitsLimit(dynamicAction)
  then
    return "macro"
  end
  return "normal"
end

-- Substitute the resolved action into a template: %name% -> its display name,
-- %id% -> its numeric id. Replacement values are %-escaped so a name containing
-- "%" can't corrupt the body. Fails if the result would exceed the 255 cap.
function Macros.RenderTemplate(template, resolved)
  template = template or MM.MACRO_TEMPLATE_DEFAULT
  if not resolved then
    return nil, "nothing resolved to substitute"
  end

  local function escape(value)
    return (tostring(value or ""):gsub("%%", "%%%%"))
  end

  local body = template:gsub("%%name%%", escape(resolved.label))
  body = body:gsub("%%id%%", escape(resolved.id))

  if #body > MM.MACRO_BODY_LIMIT then
    return nil, "macro body exceeds " .. MM.MACRO_BODY_LIMIT .. " characters"
  end
  return body
end

-- The macro body a resolved action should be placed as, or nil if it should go on
-- the bar directly: nil unless its dynamicAction is in (effective) macro mode, the action
-- is in the macro-able family, and the body fits the cap. Single decision point
-- shared by the applier, the idempotency check, cleanup, and preview.
function Macros.ResolvedAsMacro(resolved)
  local dynamicAction = resolved and resolved.dynamicAction
  if dynamicAction and Macros.EffectiveMode(dynamicAction) == "macro" and Macros.FAMILY[resolved.kind] then
    return Macros.RenderTemplate(dynamicAction.macroTemplate, resolved)
  end
  return nil
end

-- Trim `text` to at most `maxBytes`, without splitting a UTF-8 sequence (so a
-- localized macro name never ends in a broken half-character).
local function truncateBytes(text, maxBytes)
  if #text <= maxBytes then
    return text
  end
  local cut = maxBytes
  -- Back off while the next byte is a UTF-8 continuation byte (0x80-0xBF), i.e. the
  -- cut falls inside a multi-byte character.
  while cut > 0 do
    local nextByte = string.byte(text, cut + 1)
    if not nextByte or nextByte < 0x80 or nextByte >= 0xC0 then
      break
    end
    cut = cut - 1
  end
  return text:sub(1, cut)
end

-- A generated macro is named after its dynamicAction, plus an owner marker so we can
-- recognise our macros, truncated to fit the 64-byte name cap. The name is cosmetic
-- (it labels the bar button); tracking keys on the registry, so collisions between
-- two dynamicActions sharing a prefix are harmless.
function Macros.MacroName(dynamicAction)
  local name = dynamicAction and dynamicAction.name or "Dynamic Action"
  if name == "" then
    name = "Dynamic Action"
  end
  local marker = MM.MACRO_NAME_MARKER
  return truncateBytes(name, MM.MACRO_NAME_LIMIT - #marker) .. marker
end

-- True for a macro we generated — recognised by the owner marker on its name.
-- Used as a cleanup safety net when the tracking registry is lost.
function Macros.IsOwned(macro)
  local marker = MM.MACRO_NAME_MARKER
  local name = macro and macro.name
  return type(name) == "string" and #name >= #marker and name:sub(-#marker) == marker
end

-- Thin guarded wrappers over the global macro API (none of which exist under the
-- test harness, matching how Pickup guards PickupMacro).
function Macros.Create(name, body)
  if not CreateMacro then
    return nil, "macro API unavailable"
  end
  local _, characterCount = GetNumMacros()
  if (characterCount or 0) >= (MAX_CHARACTER_MACROS or 30) then
    return nil, "character macro slots are full"
  end
  local index = CreateMacro(name, MM.MACRO_DYNAMIC_ICON, body, true)
  return index
end

function Macros.Edit(index, name, body)
  if not EditMacro then
    return false
  end
  EditMacro(index, name, MM.MACRO_DYNAMIC_ICON, body)
  return true
end

function Macros.Delete(index)
  if not DeleteMacro then
    return false
  end
  DeleteMacro(index)
  return true
end

-- Recreate a user's captured macro (name + body) in its captured scope — a
-- global macro stays global, a character macro stays per-character. Unlike
-- EnsureMacro's generated macros these belong to the player: no owner marker,
-- never touched by orphan cleanup.
function Macros.RestoreUserMacro(restore)
  if not (CreateMacro and GetNumMacros) then
    return nil, "macro API unavailable"
  end
  if not restore or not restore.name or not restore.body then
    return nil, "no stored macro body to restore"
  end

  local globalCount, characterCount = GetNumMacros()
  local perCharacter = restore.scope ~= "global"
  if perCharacter and (characterCount or 0) >= (MAX_CHARACTER_MACROS or 30) then
    return nil, "character macro slots are full"
  end
  if not perCharacter and (globalCount or 0) >= (MAX_ACCOUNT_MACROS or 120) then
    return nil, "account macro slots are full"
  end

  local index = CreateMacro(restore.name, restore.icon or MM.MACRO_DYNAMIC_ICON, restore.body, perCharacter)
  if not index then
    return nil, "could not create macro"
  end
  return {
    index = index,
    scope = perCharacter and "character" or "global",
    name = restore.name,
    body = restore.body,
    bodyHash = Macros.HashBody(restore.body),
  }
end

-- Reconcile the macro for a slot to `name` + `body`, reusing where possible:
--   * a character macro already holding this exact body -> reuse it (renaming it
--     if the desired name changed, e.g. the dynamicAction was renamed),
--   * our previous macro still untouched at its index   -> edit in place,
--   * otherwise                                         -> create a new one.
-- Returns (macro, record) or (nil, reason); `record` is what to persist.
function Macros.EnsureMacro(reference, name, body)
  local bodyHash = Macros.HashBody(body)

  local existing = Macros.Resolve({
    scope = "character",
    bodyHash = bodyHash,
    indexHint = reference and reference.indexHint,
  })
  if existing then
    -- The body is unchanged but the title may not be (a rename only changes the
    -- name), so bring the reused macro's name up to date.
    if existing.name ~= name then
      Macros.Edit(existing.index, name, body)
      existing.name = name
    end
    return existing, { name = name, scope = "character", bodyHash = bodyHash, indexHint = existing.index }
  end

  -- Edit in place only if our last macro is verifiably still there (same name and
  -- the body we wrote), so a shifted index never clobbers an unrelated macro.
  if reference and reference.indexHint and GetMacroInfo then
    local currentName, _, currentBody = GetMacroInfo(reference.indexHint)
    if currentName == reference.name and currentBody and Macros.HashBody(currentBody) == reference.bodyHash then
      if Macros.Edit(reference.indexHint, name, body) then
        local macro =
          { index = reference.indexHint, scope = "character", name = name, body = body, bodyHash = bodyHash }
        return macro, { name = name, scope = "character", bodyHash = bodyHash, indexHint = reference.indexHint }
      end
    end
  end

  local index, reason = Macros.Create(name, body)
  if not index then
    return nil, reason
  end
  local macro = { index = index, scope = "character", name = name, body = body, bodyHash = bodyHash }
  return macro, { name = name, scope = "character", bodyHash = bodyHash, indexHint = index }
end

-- Would EnsureMacro reuse/edit an existing macro for this slot (true) or create a
-- fresh one (false)? Mirrors EnsureMacro's reuse + edit-in-place conditions so the
-- preview wording matches what apply actually does. `record` is the slot's stored
-- registry entry (may be nil).
function Macros.WouldUpdate(record, body)
  local bodyHash = Macros.HashBody(body)

  -- Reuse: a character macro already holds this exact body.
  if Macros.Resolve({ scope = "character", bodyHash = bodyHash, indexHint = record and record.indexHint }) then
    return true
  end

  -- Edit in place: our previous macro is still where we left it, unchanged.
  if record and record.indexHint and GetMacroInfo then
    local name, _, currentBody = GetMacroInfo(record.indexHint)
    if name == record.name and currentBody and Macros.HashBody(currentBody) == record.bodyHash then
      return true
    end
  end

  return false
end

-- Delete a generated macro, but only after confirming the record still points at
-- the macro we created (by name + the body we wrote), so we never remove a
-- macro the player made. Falls back to a name+hash scan if the index shifted.
function Macros.DeleteOwned(record)
  if not record or not GetMacroInfo then
    return false
  end

  if record.indexHint then
    local name, _, body = GetMacroInfo(record.indexHint)
    if name == record.name and body and Macros.HashBody(body) == record.bodyHash then
      return Macros.Delete(record.indexHint)
    end
  end

  for _, macro in ipairs(Macros.Scan()) do
    if macro.name == record.name and macro.bodyHash == record.bodyHash then
      return Macros.Delete(macro.index)
    end
  end
  return false
end
