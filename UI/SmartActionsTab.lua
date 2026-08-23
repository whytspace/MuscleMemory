local ADDON_NAME, MM = ...
local L = MM.L

-- The SmartActions tab. Browsing is fully live (list, per-character resolution,
-- candidate display), predefined actions can be cloned into editable profile
-- actions, and profile candidates can be added, reordered, removed, and gated
-- by conditions.
local SmartActionsTab = {}
MM.ui.SmartActionsTab = SmartActionsTab

local Widgets = MM.ui.Widgets
local colors = Widgets.colors

-- Rail matches the rule panel: the centre candidate list has width to spare,
-- and the extra room keeps rail names and their resolution lines readable.
local RAIL_WIDTH = 260
local RULE_WIDTH = 260

local function refresh()
  MM.UI:Refresh()
end

-- Custom ("your") smart actions first, then the predefined ones, each block
-- sorted by the name shown — mirroring the rail's two sections.
local function smartActionList()
  local custom = {}
  for id, smartAction in pairs(MM.DB:SmartActions() or {}) do
    custom[#custom + 1] = { source = "custom", id = id, name = smartAction.name or id }
  end
  local predefined = {}
  for id, smartAction in pairs(MM.PredefinedSmartActions or {}) do
    predefined[#predefined + 1] = { source = "predefined", id = id, name = smartAction.name or id }
  end
  -- Sort on the displayed name: a predefined `name` is the English translation key.
  -- Duplicate names are legal for custom actions, so tie-break on the id to keep
  -- the rail order stable across rebuilds.
  local byName = function(left, right)
    if left.name ~= right.name then
      return left.name < right.name
    end
    return left.id < right.id
  end
  table.sort(custom, byName)
  table.sort(predefined, byName)
  return custom, predefined
end

local function resolveSmartAction(ref)
  return MM.Resolver:ResolveAction({ type = "action", source = ref.source, id = ref.id })
end

-- The currently selected smartAction, defaulting to the first available.
local function selectedRef()
  local state = MM.ui.state
  if state.smartAction and MM.DB:ResolveSmartAction(state.smartAction) then
    return state.smartAction
  end
  local custom, predefined = smartActionList()
  local first = custom[1] or predefined[1]
  if first then
    state.smartAction = { source = first.source, id = first.id }
    return state.smartAction
  end
  return nil
end

local function selectSmartAction(ref)
  MM.ui.state.smartAction = ref
  -- Open with no candidate selected, so the rule panel shows the smartAction's own
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

local function cloneSmartAction(ref)
  local key, reason = MM.DB:CloneSmartAction(ref)
  if not key then
    MM:Warn(L[reason or "could not clone smart action"])
    return
  end
  selectSmartAction({ source = "custom", id = key })
end

-- Drag a spell/item/macro/mount/equipment set onto the candidate list to add it
-- to the (custom) smartAction.
local function addCandidateFromCursor(smartActionId)
  local assignment, reason = MM.Capture:FromCursor()
  if not assignment then
    MM:Warn(L[reason or "could not read cursor"])
    return
  end
  local ok, err = MM.DB:AddCandidate(smartActionId, assignment)
  if not ok then
    MM:Warn(L[err or "could not add candidate"])
  end
  if ClearCursor then
    ClearCursor()
  end
  refresh()
end

local function newSmartAction()
  MM.ui.Modals.Input(
    L["New Smart Action"],
    L["Name the new Smart Action"],
    L["New Smart Action"],
    L["Create"],
    function(name)
      local key = MM.DB:CreateSmartAction(name ~= "" and name or nil)
      selectSmartAction({ source = "custom", id = key })
    end
  )
end

local function renameSmartAction(ref)
  local smartAction = MM.DB:ResolveSmartAction(ref)
  MM.ui.Modals.Input(
    L["Rename Smart Action"],
    L["New name for this Smart Action"],
    smartAction and smartAction.name or "",
    L["Rename"],
    function(name)
      if name == "" then
        return
      end
      local ok, err = MM.DB:RenameSmartAction(ref.id, name)
      if not ok then
        MM:Warn(L[err])
      end
      refresh()
    end
  )
end

local function deleteSmartAction(ref)
  local smartAction = MM.DB:ResolveSmartAction(ref)
  local name = smartAction and smartAction.name or ref.id
  MM.ui.Modals.Confirm(
    L["Delete Smart Action"],
    string.format(L['Delete custom Smart Action "%s"? Slots bound to it will fall through on the next apply.'], name),
    L["Delete"],
    function()
      -- Read the neighbour before the delete: nil selection would fall back to
      -- the top of the rail rather than to what sat beside this one.
      local neighbour = MM.Tables.NeighbourById(smartActionList(), ref.id)
      local ok, err = MM.DB:DeleteSmartAction(ref.id)
      if not ok then
        MM:Warn(L[err])
      end
      MM.ui.state.smartAction = neighbour and { source = "custom", id = neighbour.id } or nil
      refresh()
    end
  )
end

-- Title-casing the token is the last resort for a class that no longer exists.
local function prettyClass(token)
  token = tostring(token)
  local localized = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[token]
  return localized or (token:sub(1, 1):upper() .. token:sub(2):lower())
end

-- Describe one candidate for the rows + rule panel.
local function candidateInfo(candidate)
  if candidate.type == "spell" then
    local info = MM.Spells.GetInfo(candidate.id)
    return info and info.name or string.format(L["Spell %s"], tostring(candidate.id)), info and info.icon
  elseif candidate.type == "item" then
    local info = MM.Items.GetInfo(candidate.id)
    local name = info and info.name or string.format(L["Item %s"], tostring(candidate.id))
    -- Crafted items show their quality crystal, lifted from the item link.
    local marker = MM.Items.GetQualityMarkup(candidate.id)
    if marker then
      name = name .. " " .. marker
    end
    return name, info and info.icon
  elseif candidate.type == "mount" then
    local info = MM.Mounts.GetInfo(candidate.id)
    return info and info.name or string.format(L["Mount %s"], tostring(candidate.id)), info and info.icon
  elseif candidate.type == "battlepet" then
    local info = MM.BattlePets.GetInfo(candidate.id)
    return info and info.name or string.format(L["Pet %s"], tostring(candidate.id)), info and info.icon
  elseif candidate.type == "flyout" then
    local info = MM.Flyouts.GetInfo(candidate.id)
    return info and info.name or string.format(L["Flyout %s"], tostring(candidate.id)), info and info.icon
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

-- Initializer for a smartAction rail row (recycled by Widgets.DataList). A
-- `header` item renders as a plain section title instead — rows are pooled
-- across both kinds, so each pass shows/hides the other kind's children.
local function smartActionRowInit(row, data)
  local smartAction = data.smartAction
  if not row.mmInit then
    row.mmInit = true
    Widgets.decorateRow(row)

    row.headerLabel = Widgets.SectionHeader(row, "")
    row.headerLabel:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 8, 4)

    row.tile = Widgets.Icon(row, 30)
    row.tile:SetPoint("LEFT", row, "LEFT", 8, 0)

    -- Icon-only: the rail is too narrow for the word; the centre title carries it.
    row.pill = Widgets.Pill(row, nil, Widgets.ICON.import)
    row.pill:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    row.pill:SetPoint("TOP", row, "TOP", 0, -8)

    row.nameLabel = Widgets.Label(row, "GameFontHighlight", "")
    row.nameLabel:SetPoint("TOPLEFT", row.tile, "TOPRIGHT", 9, -1)
    row.nameLabel:SetPoint("RIGHT", row.pill, "LEFT", -3, 0)
    row.nameLabel:SetJustifyH("LEFT")
    row.nameLabel:SetWordWrap(false)

    row.sub = Widgets.Label(row, "GameFontDisableSmall", "")
    row.sub:SetPoint("BOTTOMLEFT", row.nameLabel, "BOTTOMLEFT", 0, -16)
    row.sub:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    row.sub:SetJustifyH("LEFT")
    row.sub:SetWordWrap(false)

    row:SetScript("OnClick", function(self)
      local ref = self.data and self.data.smartAction
      if ref then
        selectSmartAction({ source = ref.source, id = ref.id })
      end
    end)

    -- Tooltip on the icon only; what the smartAction resolves to (its spell/item/…),
    -- plus a note on the { } macro badge when it applies.
    Widgets.AttachIconTooltip(row.tile, function(r)
      local ref = r.data and r.data.smartAction
      if not ref then
        return
      end
      local resolved = resolveSmartAction(ref)
      if resolved then
        Widgets.SetActionTooltip(r.tile, resolved.kind, resolved.id, resolved.label)
      else
        Widgets.SetActionTooltip(r.tile, nil, nil, ref.name)
      end
      Widgets.AddMacroTooltipLine(MM.DB:ResolveSmartAction({ source = ref.source, id = ref.id }), true)
    end)
  end

  row.data = data
  if data.header then
    row:EnableMouse(false)
    row:SetSelected(false)
    row.headerLabel:SetText(data.header)
    row.headerLabel:Show()
    row.tile:Hide()
    row.nameLabel:SetText("")
    row.sub:SetText("")
    row.pill:SetActive(false)
    return
  end
  row:EnableMouse(true)
  row.headerLabel:Hide()
  row.tile:Show()

  local ref = selectedRef()
  local active = ref and smartAction.source == ref.source and smartAction.id == ref.id
  row:SetSelected(active)

  local smartActionObj = MM.DB:ResolveSmartAction({ source = smartAction.source, id = smartAction.id })
  row.tile:SetMacroBadge(smartActionObj ~= nil and MM.Macros.EffectiveMode(smartActionObj) == "macro")
  local resolved = resolveSmartAction(smartAction)
  if resolved and resolved.icon then
    row.tile:SetTextureImage(resolved.icon)
    row.tile:SetBorder(1, colors.managed)
  else
    row.tile:SetSymbol(Widgets.TEX.warning)
    row.tile:SetBorder(1, colors.warn, 0.7)
  end

  row.pill:SetActive(
    smartAction.source == "custom" and MM.Share:IsRecentImport("actions", MM.DB:GetActiveProfileId(), smartAction.id)
  )

  row.nameLabel:SetText(smartAction.name)
  if active then
    row.nameLabel:SetTextColor(Widgets.unpackColor(colors.gold))
  else
    row.nameLabel:SetTextColor(1, 1, 1)
  end

  local count = smartActionObj and smartActionObj.candidates and #smartActionObj.candidates or 0
  row.sub:SetText(
    resolved and string.format(L["resolves to %s"], resolved.label)
      or L:Plural(count, "no match \194\183 %d candidate", "no match \194\183 %d candidates")
  )
end

function SmartActionsTab:BuildRail(parent)
  local inset = CreateFrame("Frame", nil, parent)
  inset:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
  inset:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, 0)
  inset:SetWidth(RAIL_WIDTH)
  MM.ui.Tutorial:SetAnchor("actions.rail", inset)

  local newButton = Widgets.Button(inset, "+ " .. L["New Smart Action"], RAIL_WIDTH - 24, newSmartAction)
  newButton:SetPoint("BOTTOM", inset, "BOTTOM", 0, 8)

  local list = Widgets.DataList(inset, "actions.rail", {
    extent = 44,
    spacing = 3,
    initializer = smartActionRowInit,
  })
  list.scrollBox:SetPoint("TOPLEFT", inset, "TOPLEFT", 8, -8)
  list.scrollBox:SetPoint("BOTTOMRIGHT", newButton, "TOPRIGHT", -8, 8)

  -- Two sections: the profile's own smart actions first, then the predefined
  -- ones. The headers make the split obvious, so no per-row lock icon is needed.
  local custom, predefined = smartActionList()
  local items = { { header = L["Your Smart Actions"], extent = 26 } }
  for _, smartAction in ipairs(custom) do
    items[#items + 1] = { smartAction = smartAction }
  end
  items[#items + 1] = { header = L["Predefined (read-only)"], extent = 34 }
  for _, smartAction in ipairs(predefined) do
    items[#items + 1] = { smartAction = smartAction }
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
    row.idLabel = Widgets.Label(row, "GameFontDisableSmall", "")
    row.idLabel:SetJustifyH("LEFT")
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
            MM:Warn(L[err])
          end
          refresh()
        end
        return
      end
      -- Clicking the selected candidate again clears the selection, returning the
      -- rule panel to the smartAction-level (macro) settings.
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
      SmartActionsTab._dragCandidate = self.data.index
    end)
    row:SetScript("OnDragStop", function(self)
      self:SetAlpha(1)
      local from = SmartActionsTab._dragCandidate
      SmartActionsTab._dragCandidate = nil
      local ref = selectedRef()
      if not from or not ref or not SmartActionsTab.candidateList then
        return
      end
      local target
      SmartActionsTab.candidateList:ForEachFrame(function(frame)
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
    -- Predefined actions can't be reordered, so there's no drag handle.
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

  -- Same-named candidates (per-class racials, quality tiers) can only be told
  -- apart by their id, so show it next to the name — smaller, at the rendered
  -- name's end (the label itself spans to the row edge for truncation).
  if candidate.id then
    row.idLabel:SetText(tostring(candidate.id))
    row.idLabel:ClearAllPoints()
    row.idLabel:SetPoint("LEFT", row.nameLabel, "LEFT", row.nameLabel:GetStringWidth() + 10, 0)
    row.idLabel:Show()
  else
    row.idLabel:Hide()
  end
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

function SmartActionsTab:BuildCenter(parent, ref, smartAction)
  local center = CreateFrame("Frame", nil, parent)
  center:SetPoint("TOPLEFT", parent, "TOPLEFT", RAIL_WIDTH + 14, -14)
  center:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -(RULE_WIDTH + 14), 10)

  local title = Widgets.Title(center, smartAction and smartAction.name or "\226\128\148")
  title:SetPoint("TOPLEFT", center, "TOPLEFT", 12, -2)

  local pill = Widgets.Pill(center, L["Imported"], Widgets.ICON.import)
  pill:SetPoint("LEFT", title, "RIGHT", 8, 0)
  pill:SetActive(ref.source == "custom" and MM.Share:IsRecentImport("actions", MM.DB:GetActiveProfileId(), ref.id))

  -- Icon buttons: captions in a wordier language crowded the title out of the
  -- header, and the tooltip carries the wording instead.
  local locked = ref.source == "predefined"
  local clone = Widgets.IconButton(center, Widgets.ICON.clone, locked and L["Clone to edit"] or L["Clone"], function()
    cloneSmartAction(ref)
  end)
  Widgets.AnchorHeaderAction(clone, center, title)
  MM.ui.Tutorial:SetAnchor("actions.clone", clone)

  if not locked then
    local del = Widgets.IconButton(center, Widgets.ICON.delete, L["Delete"], function()
      deleteSmartAction(ref)
    end)
    del:SetPoint("RIGHT", clone, "LEFT", -6, 0)

    local rename = Widgets.IconButton(center, Widgets.ICON.rename, L["Rename"], function()
      renameSmartAction(ref)
    end)
    rename:SetPoint("RIGHT", del, "LEFT", -6, 0)
  end

  -- 12 inset on both sides, the icon cluster, and the pill with its gaps.
  local actionWidth = locked and 26 or (3 * 26 + 2 * 6)
  Widgets.TruncateToFit(title, center:GetWidth() - 24 - actionWidth - 8 - pill:GetWidth() - 8)

  -- Resolution chip.
  local resolved = resolveSmartAction(ref)
  local chipText = resolved and string.format(L['On this character resolves to "%s".'], resolved.label)
    or L["No candidate is usable by this character \226\128\148 slots bound here fall through."]
  local chip = Widgets.Label(center, "GameFontHighlightSmall", chipText, resolved and colors.parchment or colors.warn)
  chip:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -14)
  chip:SetPoint("RIGHT", center, "RIGHT", -12, 0)
  chip:SetJustifyH("LEFT")

  local hintText = locked and L["Priority order"]
    or L["Drag to add \194\183 drag a row to reorder \194\183 right-click to remove"]
  local hint = Widgets.Hint(center, hintText)
  hint:SetPoint("TOPLEFT", chip, "BOTTOMLEFT", 0, -10)
  -- Bounded right, so a longer translation wraps instead of running past the panel.
  hint:SetPoint("RIGHT", center, "RIGHT", -30, 0)
  hint:SetJustifyH("LEFT")

  -- Candidate rows — a retained DataProvider list, so selecting/removing a
  -- candidate no longer snaps the scroll to the top and the rows aren't leaked.
  local candidates = smartAction and smartAction.candidates or {}
  local list = Widgets.DataList(center, "actions.candidates", {
    extent = 40,
    spacing = 3,
    initializer = candidateRowInit,
  })
  SmartActionsTab.candidateList = list
  list.scrollBox:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -18)
  list.scrollBox:SetPoint("BOTTOMRIGHT", center, "BOTTOMRIGHT", -30, 4)

  local items = {}
  for index, candidate in ipairs(candidates) do
    items[#items + 1] = { index = index, candidate = candidate }
  end

  -- Keep the scroll offset while browsing one smartAction; reset to the top when the
  -- selected smartAction changes (its candidate list is unrelated).
  local smartActionKey = ref.source .. ":" .. tostring(ref.id)
  list:SetItems(items, SmartActionsTab._candidateKey == smartActionKey)
  SmartActionsTab._candidateKey = smartActionKey

  if #candidates == 0 then
    local emptyText = locked and L["This smart action has no candidates."]
      or L["No candidates yet \226\128\148 drag a spell, item, macro, mount or equipment set here to add one."]
    local note = Widgets.Hint(center, emptyText)
    note:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -16)
    note:SetPoint("RIGHT", center, "RIGHT", -12, 0)
    note:SetJustifyH("LEFT")
  end

  -- Custom actions accept dropped actions as new candidates.
  if locked then
    if SmartActionsTab.dropZone then
      SmartActionsTab.dropZone:Detach()
    end
  else
    if not SmartActionsTab.dropZone then
      SmartActionsTab.dropZone = Widgets.DropZone(L["Drop to add a candidate"])
    end
    SmartActionsTab.dropZone:Attach(center, function()
      addCandidateFromCursor(ref.id)
    end)
  end
end

-- Right: condition editor ------------------------------------------------------

-- The rule panel when no candidate is selected: how the smartAction is executed.
-- Custom actions can switch to macro mode and edit the template; predefined
-- actions show a read-only note.
function SmartActionsTab:BuildMacroPanel(inset, smartAction)
  local ref = selectedRef()
  local editable = ref and ref.source == "custom"

  local header = Widgets.SectionHeader(inset, L["Execution"])
  header:SetPoint("TOPLEFT", inset, "TOPLEFT", 16, -16)

  if not editable then
    local asMacro = smartAction and MM.Macros.EffectiveMode(smartAction) == "macro"
    local note = Widgets.Hint(
      inset,
      asMacro and L["This predefined smart action is rendered as a macro. Clone it to change the body."]
        or L["Predefined smart actions place the resolved spell or item directly. Clone this smart action to render it as a macro instead."]
    )
    note:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -10)
    note:SetPoint("RIGHT", inset, "RIGHT", -14, 0)
    note:SetJustifyH("LEFT")

    if asMacro then
      local body = Widgets.Label(inset, "GameFontDisableSmall", smartAction.macroTemplate or MM.MACRO_TEMPLATE_DEFAULT)
      body:SetPoint("TOPLEFT", note, "BOTTOMLEFT", 0, -10)
      body:SetPoint("RIGHT", inset, "RIGHT", -14, 0)
      body:SetJustifyH("LEFT")
    end
    return
  end

  local isMacro = smartAction and smartAction.mode == "macro"

  local box = Widgets.Checkbox(inset, isMacro, function(button)
    MM.DB:SetSmartActionMode(ref.id, button:GetChecked() and "macro" or "normal")
    refresh()
  end)
  box:SetPoint("TOPLEFT", header, "BOTTOMLEFT", -4, -6)

  local boxLabel = Widgets.Label(inset, "GameFontHighlight", L["Render as a macro"])
  boxLabel:SetPoint("LEFT", box, "RIGHT", 2, 0)

  local intro = Widgets.Hint(
    inset,
    L["Put a generated macro on the bar instead of the raw action, so you can add mouseover, focus and other conditions while the smart action still resolves the right spell or item for this character."]
  )
  intro:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 4, -6)
  intro:SetPoint("RIGHT", inset, "RIGHT", -14, 0)
  intro:SetJustifyH("LEFT")

  if not isMacro then
    return
  end

  local anchor = intro
  if not MM.Macros.CandidatesCompatible(smartAction) then
    local badge = Widgets.Label(
      inset,
      "GameFontHighlightSmall",
      L["Macro mode supports spell, item, toy and mount candidates only."],
      colors.warn
    )
    badge:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", 0, -10)
    badge:SetPoint("RIGHT", inset, "RIGHT", -14, 0)
    badge:SetJustifyH("LEFT")
    anchor = badge
  end

  local example = Widgets.Hint(inset, L["Use %name% for the resolved action. Example:"])
  example:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -12)
  example:SetPoint("RIGHT", inset, "RIGHT", -14, 0)
  example:SetJustifyH("LEFT")

  local sample =
    Widgets.Label(inset, "GameFontDisableSmall", "#showtooltip\n/use [@mouseover,help][@focus,help][] %name%")
  sample:SetPoint("TOPLEFT", example, "BOTTOMLEFT", 0, -4)
  sample:SetJustifyH("LEFT")

  local bodyHeader = Widgets.SectionHeader(inset, L["Macro Body"])
  bodyHeader:SetPoint("TOPLEFT", sample, "BOTTOMLEFT", 0, -12)

  -- Live count of the longest body any candidate would produce (the macro grows
  -- when %name% is filled in). Turns red past the 255 cap, where macro mode goes
  -- inactive and the smartAction falls back to placing the action directly.
  local count = Widgets.Label(inset, "GameFontHighlightSmall", "", colors.muted)

  local function updateCount(template)
    local worst = MM.Macros.WorstCaseLength(smartAction, template)
    local over = worst > MM.MACRO_BODY_LIMIT
    local text = string.format(L["Longest result: %d / %d characters"], worst, MM.MACRO_BODY_LIMIT)
    if over then
      text = string.format(L["%s \226\128\148 over the macro limit, macro mode is inactive until it fits."], text)
    end
    count:SetText(text)
    count:SetTextColor(Widgets.unpackColor(over and colors.danger or colors.muted))
  end

  local input = Widgets.MultiLineInput(
    inset,
    smartAction.macroTemplate or MM.MACRO_TEMPLATE_DEFAULT,
    MM.MACRO_TEMPLATE_LIMIT,
    function(text)
      MM.DB:SetSmartActionTemplate(ref.id, text)
      updateCount(text)
    end
  )
  input:SetPoint("TOPLEFT", bodyHeader, "BOTTOMLEFT", 0, -6)
  input:SetPoint("RIGHT", inset, "RIGHT", -16, 0)
  input:SetHeight(84)

  count:SetPoint("TOPLEFT", input, "BOTTOMLEFT", 0, -8)
  count:SetPoint("RIGHT", inset, "RIGHT", -14, 0)
  count:SetJustifyH("LEFT")
  updateCount(smartAction.macroTemplate or MM.MACRO_TEMPLATE_DEFAULT)
end

function SmartActionsTab:BuildRule(parent, smartAction)
  local inset = CreateFrame("Frame", nil, parent)
  inset:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
  inset:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
  inset:SetWidth(RULE_WIDTH + 2)
  MM.ui.Tutorial:SetAnchor("actions.rule", inset)

  local candidates = smartAction and smartAction.candidates or {}
  local candidate = MM.ui.state.candidate and candidates[MM.ui.state.candidate]
  if not candidate then
    -- No candidate selected: the rule panel edits the smartAction itself (macro mode).
    self:BuildMacroPanel(inset, smartAction)
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

  local sub = Widgets.Label(inset, "GameFontDisableSmall", L["when to use this candidate"])
  sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)

  -- Live condition editor: custom actions are editable, predefined ones show
  -- their conditions read-only.
  local ref = selectedRef()
  local editable = ref and ref.source == "custom"

  local hint = Widgets.Hint(
    inset,
    editable and L["Leave everything off to use this whenever the character can cast it."]
      or L["Predefined smart action \226\128\148 conditions are read-only."]
  )
  hint:SetPoint("TOPLEFT", tile, "BOTTOMLEFT", 0, -14)
  hint:SetPoint("RIGHT", inset, "RIGHT", -14, 0)
  hint:SetJustifyH("LEFT")

  -- Scrollable so an all-expanded editor doesn't overflow the panel.
  local scrollBox, content = Widgets.ScrollList(inset, "actions.conditions")
  scrollBox:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -14)
  scrollBox:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -20, 12)
  -- The editor edits a scratch copy; every change is committed through the DB
  -- so config mutations stay behind one door.
  local working = MM.Tables.DeepCopy(candidate.conditions or {})
  local editor = MM.ui.ConditionsEditor:Build(content, working, editable, function()
    MM.DB:SetCandidateConditions(ref.id, MM.ui.state.candidate, working)
    refresh()
  end, RULE_WIDTH - 40)
  editor:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
  editor:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, 0)
  content:SetHeight(editor:GetHeight())
end

-- Assembly -------------------------------------------------------------------

function SmartActionsTab:BuildContent(parent)
  local ref = selectedRef()
  if not ref then
    local note = Widgets.Label(parent, "GameFontHighlight", L["No smart actions available."])
    note:SetPoint("CENTER")
    return
  end

  local smartAction = MM.DB:ResolveSmartAction(ref)
  local candidateCount = smartAction and smartAction.candidates and #smartAction.candidates or 0
  if MM.ui.state.candidate and MM.ui.state.candidate > candidateCount then
    MM.ui.state.candidate = nil
  end

  self:BuildRail(parent)
  self:BuildCenter(parent, ref, smartAction)
  self:BuildRule(parent, smartAction)

  local leftGroove = Widgets.VGroove(parent)
  leftGroove:SetPoint("TOPLEFT", parent, "TOPLEFT", RAIL_WIDTH + 6, -6)
  leftGroove:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", RAIL_WIDTH + 6, 6)

  local rightGroove = Widgets.VGroove(parent)
  rightGroove:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -(RULE_WIDTH + 6), -6)
  rightGroove:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -(RULE_WIDTH + 6), 6)

  -- Groove to groove and full height, as on the Layers tab.
  local centerColumn = CreateFrame("Frame", nil, parent)
  centerColumn:SetPoint("TOPLEFT", parent, "TOPLEFT", RAIL_WIDTH + 6, 0)
  centerColumn:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -(RULE_WIDTH + 6), 0)
  MM.ui.Tutorial:SetAnchor("actions.center", centerColumn)
end

function SmartActionsTab:Build(parent)
  self.parent = parent
  self:Refresh()
end

function SmartActionsTab:Refresh()
  if not self.parent then
    return
  end
  Widgets.ClearChildren(self.parent)
  self:BuildContent(self.parent)
end
