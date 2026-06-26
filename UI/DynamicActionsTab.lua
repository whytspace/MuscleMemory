local ADDON_NAME, MM = ...

-- The DynamicActions tab. Browsing is fully live (list, per-character resolution,
-- candidate display), predefined dynamicActions can be cloned into editable profile
-- dynamicActions, and profile candidates can be added, reordered, removed, and gated
-- by conditions.
local DynamicActionsTab = {}
MM.ui.DynamicActionsTab = DynamicActionsTab

local Widgets = MM.ui.Widgets
local colors = Widgets.colors

local RAIL_WIDTH = 250
local RULE_WIDTH = 330

local function refresh()
  MM.UI:Refresh()
end

local function dynamicActionList()
  local dynamicActions = {}
  for id, dynamicAction in pairs(MM.PredefinedDynamicActions or {}) do
    dynamicActions[#dynamicActions + 1] =
      { source = "predefined", id = id, name = dynamicAction.name or id, locked = true }
  end
  for id, dynamicAction in pairs(MM.DB:DynamicActions() or {}) do
    dynamicActions[#dynamicActions + 1] =
      { source = "custom", id = id, name = dynamicAction.name or id, locked = false }
  end
  table.sort(dynamicActions, function(left, right)
    return left.name < right.name
  end)
  return dynamicActions
end

local function resolveDynamicAction(ref)
  return MM.Resolver:ResolveAction({ type = "dynamicaction", source = ref.source, id = ref.id })
end

-- The currently selected dynamicAction, defaulting to the first available.
local function selectedRef()
  local state = MM.ui.state
  if state.dynamicAction and MM.DB:ResolveDynamicAction(state.dynamicAction) then
    return state.dynamicAction
  end
  local list = dynamicActionList()
  if list[1] then
    state.dynamicAction = { source = list[1].source, id = list[1].id }
    return state.dynamicAction
  end
  return nil
end

local function selectDynamicAction(ref)
  MM.ui.state.dynamicAction = ref
  -- Open with no candidate selected, so the rule panel shows the dynamicAction's own
  -- settings (macro mode), mirroring the layers tab's "no slot selected" state.
  MM.ui.state.candidate = nil
  MM.ui.state.condsOpen = false
  refresh()
end

local function selectCandidate(index)
  MM.ui.state.candidate = index
  MM.ui.state.condsOpen = false
  refresh()
end

local function cloneDynamicAction(ref)
  local key, reason = MM.DB:CloneDynamicAction(ref)
  if not key then
    MM:Warn(reason or "could not clone dynamic action")
    return
  end
  selectDynamicAction({ source = "custom", id = key })
end

-- Drag a spell/item/macro/mount/equipment set onto the candidate list to add it
-- to the (custom) dynamicAction.
local function addCandidateFromCursor(dynamicActionId)
  local assignment, reason = MM.Capture:FromCursor()
  if not assignment then
    MM:Warn(reason or "could not read cursor")
    return
  end
  local ok, err = MM.DB:AddCandidate(dynamicActionId, assignment)
  if not ok then
    MM:Warn(err or "could not add candidate")
  end
  if ClearCursor then
    ClearCursor()
  end
  refresh()
end

local function newDynamicAction()
  MM.ui.Modals.Input("New Dynamic Action", "Name the new Dynamic Action", "New Dynamic Action", "Create", function(name)
    local key = MM.DB:CreateDynamicAction(name ~= "" and name or nil)
    selectDynamicAction({ source = "custom", id = key })
  end)
end

local function renameDynamicAction(ref)
  local dynamicAction = MM.DB:ResolveDynamicAction(ref)
  MM.ui.Modals.Input(
    "Rename Dynamic Action",
    "New name for this Dynamic Action",
    dynamicAction and dynamicAction.name or "",
    "Rename",
    function(name)
      if name == "" then
        return
      end
      local ok, err = MM.DB:RenameDynamicAction(ref.id, name)
      if not ok then
        MM:Warn(err)
      end
      refresh()
    end
  )
end

local function deleteDynamicAction(ref)
  local dynamicAction = MM.DB:ResolveDynamicAction(ref)
  local name = dynamicAction and dynamicAction.name or ref.id
  MM.ui.Modals.Confirm(
    "Delete Dynamic Action",
    string.format('Delete custom dynamicAction "%s"? Slots bound to it will fall through on the next apply.', name),
    "Delete",
    function()
      local ok, err = MM.DB:DeleteDynamicAction(ref.id)
      if not ok then
        MM:Warn(err)
      end
      MM.ui.state.dynamicAction = nil
      refresh()
    end
  )
end

local function prettyClass(token)
  token = tostring(token)
  return token:sub(1, 1):upper() .. token:sub(2):lower()
end

-- Describe one candidate for the rows + rule panel.
local function candidateInfo(candidate)
  if candidate.type == "spell" then
    local info = MM.Spells.GetInfo(candidate.id)
    return info and info.name or ("Spell " .. tostring(candidate.id)), info and info.icon
  elseif candidate.type == "item" then
    local info = MM.Items.GetInfo(candidate.id)
    local name = info and info.name or ("Item " .. tostring(candidate.id))
    -- Crafted items show their quality crystal, lifted from the item link.
    local marker = MM.Items.GetQualityMarkup(candidate.id)
    if marker then
      name = name .. " " .. marker
    end
    return name, info and info.icon
  elseif candidate.type == "mount" then
    local info = MM.Mounts.GetInfo(candidate.id)
    return info and info.name or ("Mount " .. tostring(candidate.id)), info and info.icon
  elseif candidate.type == "battlepet" then
    local info = MM.BattlePets.GetInfo(candidate.id)
    return info and info.name or ("Pet " .. tostring(candidate.id)), info and info.icon
  elseif candidate.type == "flyout" then
    local info = MM.Flyouts.GetInfo(candidate.id)
    return info and info.name or ("Flyout " .. tostring(candidate.id)), info and info.icon
  end
  return MM.Actions.GetAssignmentLabel(candidate), nil
end

-- Show the rich client tooltip for a candidate (spell/item/…), anchored to its icon.
local function showCandidateTooltip(row)
  local candidate = row.data and row.data.candidate
  if not candidate then
    return
  end
  Widgets.SetActionTooltip(row.tile, candidate.type, candidate.id, (candidateInfo(candidate)))
end

-- Left rail ------------------------------------------------------------------

-- Initializer for a dynamicAction rail row (recycled by Widgets.DataList).
local function dynamicActionRowInit(row, data)
  local dynamicAction = data.dynamicAction
  if not row.mmInit then
    row.mmInit = true
    Widgets.decorateRow(row)

    row.tile = Widgets.Icon(row, 30)
    row.tile:SetPoint("LEFT", row, "LEFT", 8, 0)

    row.lock = row:CreateTexture(nil, "ARTWORK")
    row.lock:SetSize(12, 14)
    row.lock:SetPoint("RIGHT", row, "RIGHT", -8, 0)

    row.nameLabel = Widgets.Label(row, "GameFontHighlight", "")
    row.nameLabel:SetPoint("TOPLEFT", row.tile, "TOPRIGHT", 9, -1)
    row.nameLabel:SetPoint("RIGHT", row.lock, "LEFT", -4, 0)
    row.nameLabel:SetJustifyH("LEFT")
    row.nameLabel:SetWordWrap(false)

    row.sub = Widgets.Label(row, "GameFontDisableSmall", "")
    row.sub:SetPoint("BOTTOMLEFT", row.nameLabel, "BOTTOMLEFT", 0, -16)
    row.sub:SetPoint("RIGHT", row.lock, "LEFT", -4, 0)
    row.sub:SetJustifyH("LEFT")
    row.sub:SetWordWrap(false)

    row:SetScript("OnClick", function(self)
      if self.data then
        selectDynamicAction({ source = self.data.dynamicAction.source, id = self.data.dynamicAction.id })
      end
    end)

    -- Tooltip on the icon only; what the dynamicAction resolves to (its spell/item/…),
    -- plus a note on the { } macro badge when it applies.
    Widgets.AttachIconTooltip(row.tile, function(r)
      local ref = r.data and r.data.dynamicAction
      if not ref then
        return
      end
      local resolved = resolveDynamicAction(ref)
      if resolved then
        Widgets.SetActionTooltip(r.tile, resolved.kind, resolved.id, resolved.label)
      else
        Widgets.SetActionTooltip(r.tile, nil, nil, ref.name)
      end
      Widgets.AddMacroTooltipLine(MM.DB:ResolveDynamicAction({ source = ref.source, id = ref.id }), true)
    end)
  end

  row.data = data
  local ref = selectedRef()
  local active = ref and dynamicAction.source == ref.source and dynamicAction.id == ref.id
  row:SetSelected(active)

  local dynamicActionObj = MM.DB:ResolveDynamicAction({ source = dynamicAction.source, id = dynamicAction.id })
  row.tile:SetMacroBadge(dynamicActionObj ~= nil and MM.Macros.EffectiveMode(dynamicActionObj) == "macro")
  local resolved = resolveDynamicAction(dynamicAction)
  if resolved and resolved.icon then
    row.tile:SetTextureImage(resolved.icon)
    row.tile:SetBorder(1, colors.managed)
  else
    row.tile:SetSymbol(Widgets.TEX.warning)
    row.tile:SetBorder(1, colors.warn, 0.7)
  end

  if dynamicAction.locked then
    row.lock:SetTexture(Widgets.TEX.lock)
    row.lock:Show()
  else
    row.lock:Hide()
  end

  row.nameLabel:SetText(dynamicAction.name)
  if active then
    row.nameLabel:SetTextColor(Widgets.unpackColor(colors.gold))
  else
    row.nameLabel:SetTextColor(1, 1, 1)
  end

  local count = dynamicActionObj and dynamicActionObj.candidates and #dynamicActionObj.candidates or 0
  row.sub:SetText(resolved and ("resolves to " .. resolved.label) or ("no match \194\183 " .. count .. " candidates"))
end

function DynamicActionsTab:BuildRail(parent)
  local inset = CreateFrame("Frame", nil, parent)
  inset:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
  inset:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, 0)
  inset:SetWidth(RAIL_WIDTH)

  local newButton = Widgets.Button(inset, "+ New Dynamic Action", RAIL_WIDTH - 24, newDynamicAction)
  newButton:SetPoint("BOTTOM", inset, "BOTTOM", 0, 10)

  local list = Widgets.DataList(inset, "dynamicActions.rail", {
    extent = 44,
    spacing = 3,
    initializer = dynamicActionRowInit,
  })
  list.scrollBox:SetPoint("TOPLEFT", inset, "TOPLEFT", 8, -8)
  list.scrollBox:SetPoint("BOTTOMRIGHT", newButton, "TOPRIGHT", -8, 8)

  local items = {}
  for _, dynamicAction in ipairs(dynamicActionList()) do
    items[#items + 1] = { dynamicAction = dynamicAction }
  end
  list:SetItems(items)
end

-- Centre: candidate list -----------------------------------------------------

-- Initializer for a candidate row. Widgets.DataList recycles these Buttons, so
-- the children are built once (guarded by mmInit) and refreshed each call, and
-- the click/drag handlers read row.data live rather than closing over an index.
local function candidateRowInit(row, data)
  if not row.mmInit then
    row.mmInit = true
    Widgets.decorateRow(row)
    row:RegisterForDrag("LeftButton")

    row.handle = Widgets.DragDots(row)
    row.order = Widgets.Label(row, "GameFontNormalSmall", "")
    row.order:SetWidth(16)
    row.order:SetJustifyH("LEFT")
    row.order:SetTextColor(Widgets.unpackColor(colors.goldDim))
    row.tile = Widgets.Icon(row, 30)
    row.tile:SetBorder(1, colors.managed, 0.7)
    row.nameLabel = Widgets.Label(row, "GameFontHighlight", "")
    row.nameLabel:SetJustifyH("LEFT")
    row.nameLabel:SetWordWrap(false)
    row.condLabel = Widgets.Label(row, "GameFontDisableSmall", "")
    row.condLabel:SetTextColor(Widgets.unpackColor(colors.goldDim))

    row:SetScript("OnClick", function(self, mouseButton)
      local ref = selectedRef()
      local index = self.data and self.data.index
      if not ref or not index then
        return
      end
      if mouseButton == "RightButton" then
        if ref.source ~= "predefined" then
          local ok, err = MM.DB:RemoveCandidate(ref.id, index)
          if not ok then
            MM:Warn(err)
          end
          refresh()
        end
        return
      end
      -- Clicking the selected candidate again clears the selection, returning the
      -- rule panel to the dynamicAction-level (macro) settings.
      selectCandidate(MM.ui.state.candidate == index and nil or index)
    end)

    -- Drag a candidate onto another to reorder (the target is whichever row the
    -- cursor is over on release).
    row:SetScript("OnDragStart", function(self)
      local ref = selectedRef()
      if not self.data or not ref or ref.source == "predefined" then
        return
      end
      self:SetAlpha(0.5)
      DynamicActionsTab._dragCandidate = self.data.index
    end)
    row:SetScript("OnDragStop", function(self)
      self:SetAlpha(1)
      local from = DynamicActionsTab._dragCandidate
      DynamicActionsTab._dragCandidate = nil
      local ref = selectedRef()
      if not from or not ref or not DynamicActionsTab.candidateList then
        return
      end
      local target
      DynamicActionsTab.candidateList:ForEachFrame(function(frame)
        if frame.data and frame:IsMouseOver() then
          target = frame.data.index
        end
      end)
      if target and target ~= from then
        MM.DB:MoveCandidate(ref.id, from, target)
        refresh()
      end
    end)

    -- Tooltip on the icon only, not the whole row.
    Widgets.AttachIconTooltip(row.tile, showCandidateTooltip)
  end

  row.data = data
  local index, candidate = data.index, data.candidate
  local locked = (selectedRef() or {}).source == "predefined"

  row:SetSelected(index == MM.ui.state.candidate)

  row.order:SetText(tostring(index))
  row.order:ClearAllPoints()
  if locked then
    -- Predefined dynamicActions can't be reordered, so there's no drag handle.
    row.handle:Hide()
    row.order:SetPoint("LEFT", row, "LEFT", 12, 0)
  else
    row.handle:ClearAllPoints()
    row.handle:SetPoint("LEFT", row, "LEFT", 10, 0)
    row.handle:Show()
    row.order:SetPoint("LEFT", row.handle, "RIGHT", 8, 0)
  end

  local name, icon = candidateInfo(candidate)
  row.tile:ClearAllPoints()
  row.tile:SetPoint("LEFT", row.order, "RIGHT", 8, 0)
  if icon then
    row.tile:SetTextureImage(icon)
  else
    row.tile:SetGlyph("?", colors.faint)
  end

  row.nameLabel:SetText(name)
  row.nameLabel:ClearAllPoints()
  row.nameLabel:SetPoint("LEFT", row.tile, "RIGHT", 9, 0)

  local classes = candidate.conditions and candidate.conditions.classes
  if classes and #classes > 0 then
    local chips = {}
    for _, token in ipairs(classes) do
      chips[#chips + 1] = prettyClass(token)
    end
    row.condLabel:SetText(table.concat(chips, " / "))
    row.condLabel:ClearAllPoints()
    row.condLabel:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    row.condLabel:Show()
    row.nameLabel:SetPoint("RIGHT", row.condLabel, "LEFT", -6, 0)
  else
    row.condLabel:Hide()
    row.nameLabel:SetPoint("RIGHT", row, "RIGHT", -8, 0)
  end
end

function DynamicActionsTab:BuildCenter(parent, ref, dynamicAction)
  local center = CreateFrame("Frame", nil, parent)
  center:SetPoint("TOPLEFT", parent, "TOPLEFT", RAIL_WIDTH + 14, -14)
  center:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -(RULE_WIDTH + 14), 10)

  local title = Widgets.Title(center, dynamicAction and dynamicAction.name or "\226\128\148")
  title:SetPoint("TOPLEFT", center, "TOPLEFT", 12, -2)

  local locked = ref.source == "predefined"
  if locked then
    local tag = Widgets.Label(center, "GameFontDisableSmall", "PREDEFINED \194\183 read-only")
    tag:SetPoint("LEFT", title, "RIGHT", 12, 0)

    local clone = Widgets.Button(center, "Clone to edit", 110, function()
      cloneDynamicAction(ref)
    end)
    clone:SetPoint("TOPRIGHT", center, "TOPRIGHT", -12, -2)
  else
    local clone = Widgets.Button(center, "Clone", 60, function()
      cloneDynamicAction(ref)
    end)
    clone:SetPoint("TOPRIGHT", center, "TOPRIGHT", -12, -2)

    local del = Widgets.Button(center, "Delete", 64, function()
      deleteDynamicAction(ref)
    end)
    del:SetPoint("RIGHT", clone, "LEFT", -6, 0)

    local rename = Widgets.Button(center, "Rename", 66, function()
      renameDynamicAction(ref)
    end)
    rename:SetPoint("RIGHT", del, "LEFT", -6, 0)
  end

  -- Resolution chip.
  local resolved = resolveDynamicAction(ref)
  local chipText = resolved and ('On this character resolves to "' .. resolved.label .. '".')
    or "No candidate is usable by this character \226\128\148 slots bound here fall through."
  local chip = Widgets.Label(center, "GameFontHighlightSmall", chipText, resolved and colors.parchment or colors.warn)
  chip:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -14)
  chip:SetPoint("RIGHT", center, "RIGHT", -12, 0)
  chip:SetJustifyH("LEFT")

  local hintText = locked and "Priority order \194\183 the first usable action wins"
    or "Drag here to add \194\183 drag a row to reorder \194\183 right-click to remove \194\183 first usable wins"
  local hint = Widgets.Hint(center, hintText)
  hint:SetPoint("TOPLEFT", chip, "BOTTOMLEFT", 0, -10)

  -- Candidate rows — a retained DataProvider list, so selecting/removing a
  -- candidate no longer snaps the scroll to the top and the rows aren't leaked.
  local candidates = dynamicAction and dynamicAction.candidates or {}
  local list = Widgets.DataList(center, "dynamicActions.candidates", {
    extent = 40,
    spacing = 3,
    initializer = candidateRowInit,
  })
  DynamicActionsTab.candidateList = list
  list.scrollBox:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -8)
  list.scrollBox:SetPoint("BOTTOMRIGHT", center, "BOTTOMRIGHT", -30, 4)

  local items = {}
  for index, candidate in ipairs(candidates) do
    items[#items + 1] = { index = index, candidate = candidate }
  end

  -- Keep the scroll offset while browsing one dynamicAction; reset to the top when the
  -- selected dynamicAction changes (its candidate list is unrelated).
  local dynamicActionKey = ref.source .. ":" .. tostring(ref.id)
  list:SetItems(items, DynamicActionsTab._candidateKey == dynamicActionKey)
  DynamicActionsTab._candidateKey = dynamicActionKey

  if #candidates == 0 then
    local emptyText = locked and "This dynamic action has no candidates."
      or "No candidates yet \226\128\148 drag a spell, item, macro, mount or equipment set here to add one."
    local note = Widgets.Hint(center, emptyText)
    note:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -16)
    note:SetPoint("RIGHT", center, "RIGHT", -12, 0)
    note:SetJustifyH("LEFT")
  end

  -- Custom dynamicActions accept dropped actions as new candidates.
  if locked then
    if DynamicActionsTab.dropZone then
      DynamicActionsTab.dropZone:Detach()
    end
  else
    if not DynamicActionsTab.dropZone then
      DynamicActionsTab.dropZone = Widgets.DropZone("Drop to add a candidate")
    end
    DynamicActionsTab.dropZone:Attach(center, function()
      addCandidateFromCursor(ref.id)
    end)
  end
end

-- Right: condition editor ------------------------------------------------------

-- The rule panel when no candidate is selected: how the dynamicAction is executed.
-- Custom dynamicActions can switch to macro mode and edit the template; predefined
-- dynamicActions show a read-only note.
function DynamicActionsTab:BuildMacroPanel(inset, dynamicAction)
  local ref = selectedRef()
  local editable = ref and ref.source == "custom"

  local header = Widgets.SectionHeader(inset, "Execution")
  header:SetPoint("TOPLEFT", inset, "TOPLEFT", 16, -16)

  if not editable then
    local asMacro = dynamicAction and MM.Macros.EffectiveMode(dynamicAction) == "macro"
    local note = Widgets.Hint(
      inset,
      asMacro and "This predefined dynamic action is rendered as a macro. Clone it to change the body."
        or "Predefined dynamic actions place the resolved spell or item directly. Clone this dynamic action to render it as a macro instead."
    )
    note:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -10)
    note:SetPoint("RIGHT", inset, "RIGHT", -14, 0)
    note:SetJustifyH("LEFT")

    if asMacro then
      local body =
        Widgets.Label(inset, "GameFontDisableSmall", dynamicAction.macroTemplate or MM.MACRO_TEMPLATE_DEFAULT)
      body:SetPoint("TOPLEFT", note, "BOTTOMLEFT", 0, -10)
      body:SetPoint("RIGHT", inset, "RIGHT", -14, 0)
      body:SetJustifyH("LEFT")
    end
    return
  end

  local isMacro = dynamicAction and dynamicAction.mode == "macro"

  local box = Widgets.Checkbox(inset, isMacro, function(button)
    MM.DB:SetDynamicActionMode(ref.id, button:GetChecked() and "macro" or "normal")
    refresh()
  end)
  box:SetPoint("TOPLEFT", header, "BOTTOMLEFT", -4, -6)

  local boxLabel = Widgets.Label(inset, "GameFontHighlight", "Render as a macro")
  boxLabel:SetPoint("LEFT", box, "RIGHT", 2, 0)

  local intro = Widgets.Hint(
    inset,
    "Put a generated macro on the bar instead of the raw action, so you can add mouseover, focus and other conditions while the dynamic action still resolves the right spell or item for this character."
  )
  intro:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 4, -6)
  intro:SetPoint("RIGHT", inset, "RIGHT", -14, 0)
  intro:SetJustifyH("LEFT")

  if not isMacro then
    return
  end

  local anchor = intro
  if not MM.Macros.CandidatesCompatible(dynamicAction) then
    local badge = Widgets.Label(
      inset,
      "GameFontHighlightSmall",
      "Macro mode supports spell, item, toy and mount candidates only.",
      colors.warn
    )
    badge:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", 0, -10)
    badge:SetPoint("RIGHT", inset, "RIGHT", -14, 0)
    badge:SetJustifyH("LEFT")
    anchor = badge
  end

  local example = Widgets.Hint(inset, "Use %name% for the resolved action. Example:")
  example:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -12)
  example:SetPoint("RIGHT", inset, "RIGHT", -14, 0)
  example:SetJustifyH("LEFT")

  local sample =
    Widgets.Label(inset, "GameFontDisableSmall", "#showtooltip\n/use [@mouseover,help][@focus,help][] %name%")
  sample:SetPoint("TOPLEFT", example, "BOTTOMLEFT", 0, -4)
  sample:SetJustifyH("LEFT")

  local bodyHeader = Widgets.SectionHeader(inset, "Macro Body")
  bodyHeader:SetPoint("TOPLEFT", sample, "BOTTOMLEFT", 0, -12)

  -- Live count of the longest body any candidate would produce (the macro grows
  -- when %name% is filled in). Turns red past the 255 cap, where macro mode goes
  -- inactive and the dynamicAction falls back to placing the action directly.
  local count = Widgets.Label(inset, "GameFontHighlightSmall", "", colors.muted)

  local function updateCount(template)
    local worst = MM.Macros.WorstCaseLength(dynamicAction, template)
    local over = worst > MM.MACRO_BODY_LIMIT
    local text = string.format("Longest result: %d / %d characters", worst, MM.MACRO_BODY_LIMIT)
    if over then
      text = text .. " \226\128\148 over the macro limit, macro mode is inactive until it fits."
    end
    count:SetText(text)
    count:SetTextColor(Widgets.unpackColor(over and colors.danger or colors.muted))
  end

  local input = Widgets.MultiLineInput(
    inset,
    dynamicAction.macroTemplate or MM.MACRO_TEMPLATE_DEFAULT,
    MM.MACRO_TEMPLATE_LIMIT,
    function(text)
      MM.DB:SetDynamicActionTemplate(ref.id, text)
      updateCount(text)
    end
  )
  input:SetPoint("TOPLEFT", bodyHeader, "BOTTOMLEFT", 0, -6)
  input:SetPoint("RIGHT", inset, "RIGHT", -16, 0)
  input:SetHeight(84)

  count:SetPoint("TOPLEFT", input, "BOTTOMLEFT", 0, -8)
  count:SetPoint("RIGHT", inset, "RIGHT", -14, 0)
  count:SetJustifyH("LEFT")
  updateCount(dynamicAction.macroTemplate or MM.MACRO_TEMPLATE_DEFAULT)
end

function DynamicActionsTab:BuildRule(parent, dynamicAction)
  local inset = CreateFrame("Frame", nil, parent)
  inset:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
  inset:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
  inset:SetWidth(RULE_WIDTH + 2)

  local candidates = dynamicAction and dynamicAction.candidates or {}
  local candidate = MM.ui.state.candidate and candidates[MM.ui.state.candidate]
  if not candidate then
    -- No candidate selected: the rule panel edits the dynamicAction itself (macro mode).
    self:BuildMacroPanel(inset, dynamicAction)
    return
  end

  local name, icon = candidateInfo(candidate)

  local tile = Widgets.Icon(inset, 32)
  tile:SetPoint("TOPLEFT", inset, "TOPLEFT", 16, -16)
  if icon then
    tile:SetTextureImage(icon)
  else
    tile:SetGlyph("?", colors.faint)
  end
  tile:SetBorder(1, colors.managed, 0.7)
  Widgets.AttachIconTooltip(tile, function()
    Widgets.SetActionTooltip(tile, candidate.type, candidate.id, name)
  end)

  local title = Widgets.Label(inset, "GameFontHighlight", name)
  title:SetPoint("TOPLEFT", tile, "TOPRIGHT", 10, -1)
  title:SetPoint("RIGHT", inset, "RIGHT", -14, 0)
  title:SetJustifyH("LEFT")

  local sub = Widgets.Label(inset, "GameFontDisableSmall", "when to use this candidate")
  sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)

  -- Live condition editor: custom dynamicActions are editable, predefined ones show
  -- their conditions read-only.
  local ref = selectedRef()
  local editable = ref and ref.source == "custom"
  if editable then
    candidate.conditions = candidate.conditions or {}
  end

  local hint = Widgets.Hint(
    inset,
    editable and "Leave everything off to use this whenever the character can cast it."
      or "Predefined dynamic action \226\128\148 conditions are read-only."
  )
  hint:SetPoint("TOPLEFT", tile, "BOTTOMLEFT", 0, -14)
  hint:SetPoint("RIGHT", inset, "RIGHT", -14, 0)
  hint:SetJustifyH("LEFT")

  -- Scrollable so an all-expanded editor doesn't overflow the panel.
  local scrollBox, content = Widgets.ScrollList(inset, "dynamicActions.conditions")
  scrollBox:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -14)
  scrollBox:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -20, 12)
  local editor = MM.ui.ConditionsEditor:Build(content, candidate.conditions or {}, editable, function()
    refresh()
  end)
  editor:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
  editor:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, 0)
  content:SetHeight(editor:GetHeight())
end

-- Assembly -------------------------------------------------------------------

function DynamicActionsTab:BuildContent(parent)
  local ref = selectedRef()
  if not ref then
    local note = Widgets.Label(parent, "GameFontHighlight", "No dynamic actions available.")
    note:SetPoint("CENTER")
    return
  end

  local dynamicAction = MM.DB:ResolveDynamicAction(ref)
  local candidateCount = dynamicAction and dynamicAction.candidates and #dynamicAction.candidates or 0
  if MM.ui.state.candidate and MM.ui.state.candidate > candidateCount then
    MM.ui.state.candidate = nil
  end

  self:BuildRail(parent)
  self:BuildCenter(parent, ref, dynamicAction)
  self:BuildRule(parent, dynamicAction)

  local leftGroove = Widgets.VGroove(parent)
  leftGroove:SetPoint("TOPLEFT", parent, "TOPLEFT", RAIL_WIDTH + 6, -6)
  leftGroove:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", RAIL_WIDTH + 6, 6)

  local rightGroove = Widgets.VGroove(parent)
  rightGroove:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -(RULE_WIDTH + 6), -6)
  rightGroove:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -(RULE_WIDTH + 6), 6)
end

function DynamicActionsTab:Build(parent)
  self.parent = parent
  self:Refresh()
end

function DynamicActionsTab:Refresh()
  if not self.parent then
    return
  end
  Widgets.ClearChildren(self.parent)
  self:BuildContent(self.parent)
end
