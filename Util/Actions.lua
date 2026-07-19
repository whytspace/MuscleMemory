local ADDON_NAME, MM = ...

local Actions = {}
MM.Actions = Actions

-- The action bars and their (non-linear) action-slot ranges, each 12 buttons.
-- WoW's slot numbering does NOT run with the visible bar order: only Bar 1 is
-- slots 1-12; the standard bars map to scattered MultiBar ranges. The Stance
-- bars are the main bar's per-form/stance pages (a Druid in Cat Form sees one of
-- these in place of Bar 1) — only relevant to classes with shapeshift forms.
-- `base` is the slot before each bar's first button; `stance` marks form pages.
-- `binding` is the key-binding action prefix (button index appended) for bars
-- that own physical buttons. The paged bars (Page 2, the stance pages, the
-- Skyriding bonus bar) reuse Bar 1's physical buttons, so they carry no binding
-- of their own and show no key in the grid (Bar 1 already shows those keys).
Actions.BARS = {
  { label = "Bar 1", base = 0, binding = "ACTIONBUTTON" }, -- slots 1-12    (main)
  { label = "Bar 2", base = 60, binding = "MULTIACTIONBAR1BUTTON" }, -- slots 61-72   (bottom left)
  { label = "Bar 3", base = 48, binding = "MULTIACTIONBAR2BUTTON" }, -- slots 49-60   (bottom right)
  { label = "Bar 4", base = 24, binding = "MULTIACTIONBAR3BUTTON" }, -- slots 25-36   (right)
  { label = "Bar 5", base = 36, binding = "MULTIACTIONBAR4BUTTON" }, -- slots 37-48   (left)
  { label = "Bar 6", base = 144, binding = "MULTIACTIONBAR5BUTTON" }, -- slots 145-156
  { label = "Bar 7", base = 156, binding = "MULTIACTIONBAR6BUTTON" }, -- slots 157-168
  { label = "Bar 8", base = 168, binding = "MULTIACTIONBAR7BUTTON" }, -- slots 169-180
  { label = "Page 2", base = 12 }, -- slots 13-24 (main bar's second page)
  { label = "Stance 1", base = 72, stance = true }, -- slots 73-84
  { label = "Stance 2", base = 84, stance = true }, -- slots 85-96
  { label = "Stance 3", base = 96, stance = true }, -- slots 97-108
  { label = "Stance 4", base = 108, stance = true }, -- slots 109-120
  { label = "Skyriding", base = 120 }, -- slots 121-132 (bonus bar while skyriding)
}

-- The bars to show for the current character: the standard bars always, plus the
-- stance/form pages only for classes that shapeshift.
function Actions.GetGridBars()
  local hasForms = GetNumShapeshiftForms and GetNumShapeshiftForms() > 0
  local bars = {}
  for _, bar in ipairs(Actions.BARS) do
    if not bar.stance or hasForms then
      bars[#bars + 1] = bar
    end
  end
  return bars
end

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

  if assignment.type == "battlepet" then
    local info = MM.BattlePets.GetInfo(assignment.id)
    return info and info.name or nil
  end

  if assignment.type == "flyout" then
    local info = MM.Flyouts.GetInfo(assignment.id)
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
  for _, bar in ipairs(Actions.BARS) do
    if slot > bar.base and slot <= bar.base + MM.ACTIONS_PER_BAR then
      return string.format("%s button %d", string.lower(bar.label), slot - bar.base)
    end
  end
  -- Paging / vehicle slots that aren't one of the listed bars.
  return string.format("slot %d", slot)
end

-- Abbreviate a single binding token to WoW's action-bar hotkey style. WoW's
-- GetBindingText only shortens the modifiers (ALT/CTRL/SHIFT); it leaves mouse
-- buttons as their full localized name ("Middle Mouse", "Mouse Button 5"), so we
-- shorten those ourselves: BUTTON3 -> M3, BUTTON5 -> M5, the mouse wheel -> Mw*,
-- and numpad digits -> N*. Anything else (letters, F-keys, Space, ...) keeps
-- WoW's own name via GetBindingText.
local MODIFIER_ABBR = { ALT = "A", CTRL = "C", SHIFT = "S" }

local function abbreviateKeyToken(token)
  if MODIFIER_ABBR[token] then
    return MODIFIER_ABBR[token]
  end
  local mouseButton = token:match("^BUTTON(%d+)$")
  if mouseButton then
    return "M" .. mouseButton
  end
  if token == "MOUSEWHEELUP" then
    return "MwU"
  end
  if token == "MOUSEWHEELDOWN" then
    return "MwD"
  end
  local numpad = token:match("^NUMPAD(%d)$")
  if numpad then
    return "N" .. numpad
  end
  return GetBindingText(token, 1)
end

-- The bound key for a slot's physical button, abbreviated in WoW's action-bar
-- style (e.g. ALT-BUTTON4 -> "AM4", BUTTON3 -> "M3"), or nil when nothing is
-- bound. Paged slots (Page 2, stance, Skyriding) have no binding of their own,
-- so they show no key.
function Actions.GetSlotHotkey(slot)
  if not GetBindingKey or not GetBindingText then
    return nil
  end
  for _, bar in ipairs(Actions.BARS) do
    if bar.binding and slot > bar.base and slot <= bar.base + MM.ACTIONS_PER_BAR then
      local key = GetBindingKey(bar.binding .. (slot - bar.base))
      if not key then
        return nil
      end
      local text = ""
      for token in string.gmatch(key, "[^-]+") do
        text = text .. abbreviateKeyToken(token)
      end
      return text ~= "" and text or nil
    end
  end
  return nil
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

  if assignment.type == "dynamicaction" then
    local dynamicAction = MM.DB:ResolveDynamicAction({ source = assignment.source, id = assignment.id })
    return dynamicAction and dynamicAction.name or ("Dynamic Action: " .. tostring(assignment.id))
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

  if assignment.type == "battlepet" then
    local info = MM.BattlePets.GetInfo(assignment.id)
    return info and info.name or ("Battle Pet: " .. tostring(assignment.id))
  end

  if assignment.type == "flyout" then
    local info = MM.Flyouts.GetInfo(assignment.id)
    return info and info.name or ("Flyout ID: " .. tostring(assignment.id))
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

  if assignment.type == "dynamicaction" then
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

  if assignment.type == "battlepet" then
    local info = MM.BattlePets.GetInfo(assignment.id)
    return info and info.icon or nil
  end

  if assignment.type == "flyout" then
    local info = MM.Flyouts.GetInfo(assignment.id)
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

  if assignment.type == "dynamicaction" then
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
    -- The Single Button Assistant is a spell, but the bar never reports it via
    -- FindSpellActionButtons (it shows the recommended ability instead), so match
    -- it with the dedicated assisted-combat query.
    if MM.Spells.IsAssistedCombatActionSpell(target.id) then
      return MM.Spells.IsAssistedCombatSlot(slot)
    end
    -- Ask the action bar for the canonical spell id: FindSpellActionButtons
    -- accepts base spell ids when the placed button currently shows an override.
    if info.actionType == "spell" and MM.Spells.IsOnActionSlot(target.id, slot) then
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
    -- Mount actions report either the journal mountID or the summon spellID
    -- depending on the action form (a companion/MOUNT slot reports the spellID),
    -- and the captured id may be in the other form than what the bar shows after
    -- applying. Compare the raw ids first, then normalize both through the
    -- journal (Mounts.GetInfo maps a spellID back to its mount) before declaring
    -- a mismatch.
    if
      info.actionType == "mount"
      or info.actionType == "summonmount"
      or (info.actionType == "companion" and info.subType == "MOUNT")
    then
      if info.id == target.id then
        return true
      end
      local slotMount = MM.Mounts.GetInfo(info.id)
      local targetMount = MM.Mounts.GetInfo(target.id)
      return slotMount ~= nil and targetMount ~= nil and slotMount.id == targetMount.id
    end
    -- Applying picks a mount up via its summon spell, so it can also land as a
    -- plain "spell" action. Match that by the mount's journal spellId, then by the
    -- button's text (the mount's name). GetInfo maps a summon-spellID target back
    -- to its mount, so this holds whichever id the capture stored.
    if info.actionType == "spell" then
      local mount = MM.Mounts.GetInfo(target.id)
      if mount and info.id == mount.spellId then
        return true
      end
      if GetActionText and target.name then
        return normalizeText(GetActionText(slot)) == normalizeText(target.name)
      end
    end
    return false
  end

  if target.kind == "battlepet" then
    return (info.actionType == "summonpet" or info.actionType == "battlepet") and info.id == target.id
  end

  if target.kind == "flyout" then
    return info.actionType == "flyout" and info.id == target.id
  end

  if target.kind == "equipmentset" then
    if info.actionType ~= "equipmentset" then
      return false
    end
    -- The slot reports either the set's name (12.0) or its numeric id.
    if type(info.id) == "string" then
      return info.id == target.setName
    end
    if not C_EquipmentSet or not C_EquipmentSet.GetEquipmentSetInfo then
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

  -- A dynamicAction in macro mode places a generated macro, not the raw action. Match the
  -- slot against the macro's current name AND rendered body: a dynamicAction rename changes
  -- the name (not the body), so a stale-named macro must read as a pending change.
  -- A body that won't render falls through to plain matching, like the applier.
  local body = MM.Macros.ResolvedAsMacro(resolved)
  if body then
    local info = Actions.GetInfo(slot)
    if not info or info.actionType ~= "macro" then
      return false
    end
    local expectedName = MM.Macros.MacroName(resolved.dynamicAction)
    local expectedHash = MM.Macros.HashBody(body)

    if GetMacroInfo then
      local liveName, _, liveBody = GetMacroInfo(info.id)
      if liveName == expectedName and liveBody and MM.Macros.HashBody(liveBody) == expectedHash then
        return true
      end
    end
    -- Fallback for clients where the slot's id isn't a usable macro index: match by
    -- the slot's macro name plus a name+hash scan.
    if GetActionText and GetActionText(slot) == expectedName then
      for _, macro in ipairs(MM.Macros.Scan()) do
        if macro.name == expectedName and macro.bodyHash == expectedHash then
          return true
        end
      end
    end
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
