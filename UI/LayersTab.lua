local ADDON_NAME, MM = ...
local L = MM.L

-- The Layers tab: left rail of layers in the active profile, the centre grid
-- mirroring the player's live bars (each slot managed / pinned / smartAction-driven /
-- empty / pass-through), and the right-hand Slot Editor. Wired straight to DB,
-- Capture, Resolver and Actions.
local LayersTab = {}
MM.ui.LayersTab = LayersTab

local Widgets = MM.ui.Widgets
local colors = Widgets.colors

local RAIL_WIDTH = 220
local EDITOR_WIDTH = 260
local CELL = 28
local CELL_GAP = 4
local LABEL_WIDTH = 64

local function refresh()
  MM.UI:Refresh()
end

-- Slot mutations -------------------------------------------------------------

local function assignSlot(layerId, slot, assignment)
  MM.DB:SetSlot(layerId, slot, assignment)
  MM.DB:SetSelectedSlot(slot)
  refresh()
end

local function resolveSmartAction(source, id)
  return MM.Resolver:ResolveAction({ type = "action", source = source, id = id })
end

-- Style a suggestion row like the sidebar's "Bind to a Smart Action" rows —
-- icon tile plus name — with the source (predefined/custom) on the right, since
-- every match resolves to the same action anyway.
local function suggestionRowInit(row, match)
  if not row.mmInit then
    row.mmInit = true
    Widgets.decorateRow(row)

    row.tile = Widgets.Icon(row, 24)
    row.tile:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.tile:SetBadge(true)

    row.nameLabel = Widgets.Label(row, "GameFontHighlight", "")
    row.nameLabel:SetPoint("LEFT", row.tile, "RIGHT", 8, 0)

    row.sourceLabel = Widgets.Label(row, "GameFontDisableSmall", "")
    row.sourceLabel:SetPoint("RIGHT", row, "RIGHT", -8, 0)
  end

  local smartActionObj = MM.DB:ResolveSmartAction({ source = match.source, id = match.id })
  row.tile:SetMacroBadge(smartActionObj ~= nil and MM.Macros.EffectiveMode(smartActionObj) == "macro")
  local resolved = resolveSmartAction(match.source, match.id)
  if resolved and resolved.icon then
    row.tile:SetTextureImage(resolved.icon)
    row.tile:SetBorder(1, colors.managed)
  else
    row.tile:SetSymbol(Widgets.TEX.warning)
    row.tile:SetBorder(1, colors.warn, 0.7)
  end

  row.nameLabel:SetText(match.name)
  row.sourceLabel:SetText(L[match.source])
end

-- Bind a captured assignment, honoring the suggestion mode when smart actions
-- resolve to it on this character ("Kick" -> the Interrupt smart action):
-- "never" binds the capture as-is, "auto" binds a sole matching smart action
-- directly, and "suggest" (or several "auto" matches) asks. In the popup a row
-- binds the smart action, "Keep" binds the capture unchanged, Escape binds
-- nothing. Only these single-slot binds prompt; bulk layer capture stays literal.
local function assignSuggesting(layerId, slot, assignment)
  local mode = MM.DB:GetSuggestMode()
  local matches = mode ~= "never" and MM.Resolver:FindSmartActionsResolvingTo(assignment) or {}
  if #matches == 0 then
    assignSlot(layerId, slot, assignment)
    return
  end

  if mode == "auto" and #matches == 1 then
    assignSlot(layerId, slot, { type = "action", source = matches[1].source, id = matches[1].id })
    return
  end

  local resolved = MM.Resolver:ResolveAction(assignment)
  local name = (resolved and resolved.label) or MM.Actions.GetAssignmentLabel(assignment)
  MM.ui.Modals.Choose({
    title = L["Bind a Smart Action instead?"],
    message = string.format(
      L["%s is covered by %s. Do you want to bind the Smart Action instead? You can disable this behavior in the settings."],
      name,
      L:Plural(#matches, "a Smart Action", "multiple Smart Actions")
    ),
    options = matches,
    rowInit = suggestionRowInit,
    onSelect = function(match)
      assignSlot(layerId, slot, { type = "action", source = match.source, id = match.id })
    end,
    cancelLabel = string.format(L["Keep %s"], name),
    onCancel = function()
      assignSlot(layerId, slot, assignment)
    end,
  })
end

-- Exposed for the screenshot tour, which stages the suggestion dialog.
function LayersTab:PromptSuggestion(layerId, slot, assignment)
  assignSuggesting(layerId, slot, assignment)
end

local function assignFromCursor(layerId, slot)
  local assignment, reason = MM.Capture:FromCursor()
  if not assignment then
    MM:Warn(L[reason or "could not read cursor"])
    return
  end
  if ClearCursor then
    ClearCursor()
  end
  assignSuggesting(layerId, slot, assignment)
end

-- Left-clicking a not-managed slot starts managing it, capturing whatever is
-- live there (or Empty if the bar slot is blank).
local function manageSlot(layerId, slot)
  local assignment, reason = MM.Capture:FromSlot(slot)
  if not assignment then
    MM.DB:SetSlot(layerId, slot, { type = "empty" })
    if reason ~= "slot has no capturable action" then
      MM:Warn(L[reason or "could not capture slot"])
    end
    MM.DB:SetSelectedSlot(slot)
    refresh()
    return
  end
  assignSuggesting(layerId, slot, assignment)
end

-- Turn a regular assignment into a fresh Smart Action seeded with that
-- action as its only candidate, then rebind the slot to it.
local function convertToSmartAction(layerId, slot, assignment)
  local prefill = MM.Actions.GetAssignmentName(assignment)
  MM.ui.Modals.Input(L["Convert to Smart Action"], L["Name the new Smart Action"], prefill, L["Convert"], function(name)
    -- One undo step for the whole conversion.
    MM.Undo:Batch(function()
      local key = MM.DB:CreateSmartAction(name ~= "" and name or prefill)
      MM.DB:AddCandidate(key, MM.Tables.DeepCopy(assignment))
      assignSlot(layerId, slot, { type = "action", source = "custom", id = key })
    end, string.format(L["convert %s to a Smart Action"], prefill))
  end)
end

local function unmanageSlot(layerId, slot)
  MM.DB:SetSlot(layerId, slot, nil)
  if MM.DB:GetSelectedSlot() == slot then
    MM.DB:SetSelectedSlot(nil)
  end
  refresh()
end

-- SmartAction helpers -------------------------------------------------------------

-- Custom ("your") smart actions and the predefined ones as separate sorted
-- lists, so the bind list can section them like the Smart Actions rail.
local function smartActionList()
  local custom = {}
  for id, smartAction in pairs(MM.DB:SmartActions() or {}) do
    custom[#custom + 1] = { source = "custom", id = id, name = smartAction.name or id }
  end
  local predefined = {}
  for id, smartAction in pairs(MM.PredefinedSmartActions or {}) do
    predefined[#predefined + 1] = { source = "predefined", id = id, name = smartAction.name or id }
  end
  -- Sort on the displayed name; tie-break on the id since duplicate names are
  -- legal for custom actions, so the bind list order stays stable across rebuilds.
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

-- Layer CRUD ----------------------------------------------------------------

local function newLayer()
  MM.ui.Modals.Input(L["New Layer"], L["Name the new Layer"], L["New Layer"], L["Create"], function(name)
    local id = MM.DB:CreateLayer(name ~= "" and name or nil)
    MM.DB:SetSelectedLayerId(id)
    MM.DB:SetSelectedSlot(nil)
    refresh()
  end)
end

local function renameLayer(layerId, currentName)
  MM.ui.Modals.Input(L["Rename Layer"], L["New name for this Layer"], currentName, L["Rename"], function(name)
    if name == "" then
      return
    end
    local ok, reason = MM.DB:RenameLayer(layerId, name)
    if not ok then
      MM:Warn(L[reason])
    end
    refresh()
  end)
end

local function deleteLayer(layerId, currentName)
  MM.ui.Modals.Confirm(
    L["Delete Layer"],
    string.format(
      L['Delete Layer "%s"? Slots it managed will fall through to lower Layers on the next apply.'],
      currentName
    ),
    L["Delete"],
    function()
      local ok, reason = MM.DB:DeleteLayer(layerId)
      if not ok then
        MM:Warn(L[reason])
      end
      refresh()
    end
  )
end

-- Left rail ------------------------------------------------------------------

-- Initializer for a layer rail row (recycled by Widgets.DataList).
local function layerRowInit(row, data)
  local entry = data.entry
  if not row.mmInit then
    row.mmInit = true
    Widgets.decorateRow(row)
    row:RegisterForDrag("LeftButton")

    row.handle = Widgets.DragDots(row)
    row.handle:SetPoint("LEFT", row, "LEFT", 9, 0)

    row.order = Widgets.Label(row, "GameFontNormalSmall", "")
    row.order:SetPoint("LEFT", row.handle, "RIGHT", 6, 0)
    row.order:SetWidth(16)
    row.order:SetJustifyH("LEFT")

    row.check = Widgets.Checkbox(row, false)
    row.check:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.check:SetScript("OnClick", function()
      local e = row.data and row.data.entry
      if e then
        MM.DB:SetLayerEnabled(e.id, not e.enabled)
        refresh()
      end
    end)

    -- Icon-only: the rail is too narrow for the word; the grid title carries it.
    row.pill = Widgets.Pill(row, nil, Widgets.ICON.import)
    row.pill:SetPoint("RIGHT", row.check, "LEFT", -2, 0)

    row.nameLabel = Widgets.Label(row, "GameFontHighlight", "")
    row.nameLabel:SetPoint("LEFT", row.order, "RIGHT", 8, 0)
    row.nameLabel:SetPoint("RIGHT", row.pill, "LEFT", -3, 0)
    row.nameLabel:SetJustifyH("LEFT")
    row.nameLabel:SetWordWrap(false)

    row:SetScript("OnClick", function(self, mouseButton)
      if mouseButton == "RightButton" then
        return
      end
      local e = self.data and self.data.entry
      if e then
        MM.DB:SetSelectedLayerId(e.id)
        MM.DB:SetSelectedSlot(nil)
        refresh()
      end
    end)

    -- Drag a row onto another to reorder; the target is whichever row the cursor
    -- is over on release.
    row:SetScript("OnDragStart", function(self)
      self:SetAlpha(0.5)
      LayersTab._dragFrom = self.data and self.data.entry.id
    end)
    row:SetScript("OnDragStop", function(self)
      self:SetAlpha(1)
      local fromId = LayersTab._dragFrom
      LayersTab._dragFrom = nil
      if not fromId or not LayersTab.railList then
        return
      end
      local target
      LayersTab.railList:ForEachFrame(function(frame)
        if frame.data and frame:IsMouseOver() then
          target = frame.data.index
        end
      end)
      if target then
        MM.DB:MoveLayer(fromId, target)
        refresh()
      end
    end)
  end

  row.data = data
  local active = entry.id == MM.DB:GetSelectedLayerId()

  row.order:SetText(tostring(data.index))
  row.order:SetTextColor(Widgets.unpackColor(active and colors.gold or colors.faint))

  row.check:SetChecked(entry.enabled)
  row.pill:SetActive(MM.Share:IsRecentImport("layers", MM.DB:GetActiveProfileId(), entry.id))

  -- A conditioned layer whose conditions don't match this character won't apply,
  -- so it reads as inactive (like a disabled one).
  local conditions = entry.layer.conditions
  local inactive = not entry.enabled or (MM.Conditions.Any(conditions) and not MM.Conditions.Match(conditions))

  row.nameLabel:SetText(entry.name)
  if inactive then
    row.nameLabel:SetTextColor(Widgets.unpackColor(colors.faint))
  elseif active then
    row.nameLabel:SetTextColor(Widgets.unpackColor(colors.gold))
  else
    row.nameLabel:SetTextColor(1, 1, 1)
  end

  row:SetSelected(active)
end

function LayersTab:BuildRail(parent)
  local inset = CreateFrame("Frame", nil, parent)
  inset:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
  inset:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, 0)
  inset:SetWidth(RAIL_WIDTH)

  local newButton = Widgets.Button(inset, L["+ New Layer"], RAIL_WIDTH - 24, newLayer)
  newButton:SetPoint("BOTTOM", inset, "BOTTOM", 0, 8)

  local list = Widgets.DataList(inset, "layers.rail", {
    extent = 32,
    spacing = 4,
    initializer = layerRowInit,
  })
  LayersTab.railList = list
  list.scrollBox:SetPoint("TOPLEFT", inset, "TOPLEFT", 8, -8)
  list.scrollBox:SetPoint("BOTTOMRIGHT", newButton, "TOPRIGHT", -6, 8)

  local layers = MM.DB:GetProfileLayers()
  local items = {}
  for index, entry in ipairs(layers) do
    items[#items + 1] = { index = index, entry = entry }
  end
  list:SetItems(items)

  if #layers == 0 then
    local note = Widgets.Label(inset, "GameFontDisableSmall", L["No Layers in this profile yet."])
    note:SetPoint("TOPLEFT", inset, "TOPLEFT", 12, -16)
    note:SetPoint("TOPRIGHT", inset, "TOPRIGHT", -12, -16)
    note:SetJustifyH("LEFT")
  end
end

-- Centre grid ----------------------------------------------------------------

-- Slots bound by other apply-relevant layers (enabled and conditions matching,
-- the same set BuildPlan applies), keyed slot -> { layer names } in priority
-- order. The selected layer is excluded: its own binding already paints the
-- cell. Membership is by binding, not resolution, so an unresolvable Taunt on
-- a Mage still counts.
local function otherLayerSlots(selectedLayerId)
  local map = {}
  for _, activeLayer in ipairs(MM.DB:GetActiveLayers() or {}) do
    if activeLayer.id ~= selectedLayerId and MM.Conditions.Match(activeLayer.layer.conditions) then
      for slot in pairs(activeLayer.layer.slots or {}) do
        local numericSlot = tonumber(slot)
        if numericSlot then
          map[numericSlot] = map[numericSlot] or {}
          table.insert(map[numericSlot], activeLayer.layer.name or activeLayer.id)
        end
      end
    end
  end
  return map
end

-- Paint one slot icon to reflect its managed state.
-- `suppressSelected` skips the thick selection outline; the sidebar icon always
-- represents the selected slot, so the highlight is redundant there.
-- `otherLayers` (the otherLayerSlots map) marks unmanaged slots that another
-- layer binds; a slot the selected layer manages keeps its normal border — the
-- overlap lives in the tooltip.
local function paintSlot(icon, layer, slot, suppressSelected, otherLayers)
  local assignment = layer and layer.slots and layer.slots[slot]
  local managed = assignment ~= nil
  local selected = not suppressSelected and MM.DB:GetSelectedSlot() == slot

  icon:SetBadge(false)
  icon:SetMacroBadge(false)
  icon:SetAlphaAll(1)
  icon:SetHotkey(MM.Actions.GetSlotHotkey(slot))

  if not managed then
    local elsewhere = otherLayers and otherLayers[slot] ~= nil
    local texture = MM.Actions.GetLiveSlotIcon(slot)
    if texture then
      icon:SetTextureImage(texture)
      icon:SetAlphaAll(0.42)
    else
      icon:SetTextureImage(nil)
    end
    if elsewhere then
      icon:SetBorder(2, colors.otherLayer, 0.55)
    else
      icon:SetBorder(1, colors.faint, texture and 0.5 or 0.28)
    end
  elseif assignment.type == "empty" then
    icon:SetSymbol(Widgets.TEX.empty)
    icon:SetBorder(selected and 3 or 2, selected and colors.selected or colors.managed)
  elseif assignment.type == "ignore" then
    icon:SetTextureImage(MM.Actions.GetLiveSlotIcon(slot))
    icon:SetAlphaAll(0.42)
    icon:SetBorder(1, colors.faint, 0.5)
  elseif assignment.type == "action" then
    local resolved = MM.Resolver:ResolveAction(assignment)
    icon:SetBadge(true)
    local smartAction = MM.DB:ResolveSmartAction({ source = assignment.source, id = assignment.id })
    icon:SetMacroBadge(smartAction ~= nil and MM.Macros.EffectiveMode(smartAction) == "macro")
    if resolved and resolved.icon then
      icon:SetTextureImage(resolved.icon)
      icon:SetBorder(selected and 3 or 2, selected and colors.selected or colors.managed)
    elseif resolved and resolved.kind == "empty" then
      icon:SetSymbol(Widgets.TEX.empty)
      icon:SetBorder(selected and 3 or 2, selected and colors.selected or colors.managed)
    else
      icon:SetSymbol(Widgets.TEX.warning)
      icon:SetBorder(selected and 3 or 2, selected and colors.selected or colors.warn)
    end
  else
    local state = MM.Actions.GetAssignmentIconState(assignment, slot)
    if state.kind == "icon" and state.texture then
      icon:SetTextureImage(state.texture)
    elseif state.kind == "empty" then
      icon:SetSymbol(Widgets.TEX.empty)
    else
      icon:SetGlyph("?", colors.goldDim)
    end
    -- A pinned user macro carries the macro badge too, not just macro-rendered
    -- smart actions.
    icon:SetMacroBadge(assignment.type == "macro")
    icon:SetBorder(selected and 3 or 2, selected and colors.selected or colors.managed)
  end
end

-- Build one reusable grid cell for a fixed slot. The cell is pooled (kept across
-- rebuilds and repainted), so its handlers read the live selected layer rather
-- than closing over a per-build one. `slot` never changes for a given cell.
function LayersTab:BuildSlotCell(parent, slot)
  local icon = Widgets.Icon(parent, CELL)
  icon:EnableMouse(true)
  icon:RegisterForDrag("LeftButton")

  -- Hit area / click handling lives on a button overlay so the Icon stays a
  -- pure visual.
  local hit = CreateFrame("Button", nil, icon)
  hit:SetAllPoints()
  hit:RegisterForClicks("LeftButtonUp", "RightButtonUp")

  hit:SetScript("OnClick", function(_, mouseButton)
    local layerId = MM.DB:GetSelectedLayerId()
    local layer = MM.DB:GetLayer(layerId)
    if GetCursorInfo and GetCursorInfo() then
      assignFromCursor(layerId, slot)
      return
    end
    local managed = layer and layer.slots and layer.slots[slot] ~= nil
    if mouseButton == "RightButton" then
      if managed then
        unmanageSlot(layerId, slot)
      end
      return
    end
    if managed then
      -- Re-clicking the selected slot deselects it (revealing the layer's
      -- condition editor in the sidebar).
      if MM.DB:GetSelectedSlot() == slot then
        MM.DB:SetSelectedSlot(nil)
      else
        MM.DB:SetSelectedSlot(slot)
      end
      refresh()
    else
      manageSlot(layerId, slot)
    end
  end)
  hit:SetScript("OnReceiveDrag", function()
    assignFromCursor(MM.DB:GetSelectedLayerId(), slot)
  end)
  hit:SetScript("OnEnter", function(frame)
    local layer = MM.DB:GetLayer(MM.DB:GetSelectedLayerId())
    GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
    GameTooltip:SetText(MM.Actions.GetSlotLabel(slot))
    local assignment = layer and layer.slots and layer.slots[slot]
    if assignment then
      GameTooltip:AddLine(MM.Actions.GetAssignmentLabel(assignment), 1, 1, 1)
      -- For a smartAction-driven slot, explain the badges and show what it
      -- resolves to for this character.
      if assignment.type == "action" then
        local resolved = MM.Resolver:ResolveAction(assignment)
        if resolved then
          GameTooltip:AddLine(string.format(L["Resolves to: %s"], resolved.label), Widgets.unpackColor(colors.goldDim))
        else
          GameTooltip:AddLine(L["No usable candidate"], 0.9, 0.4, 0.4)
        end
        Widgets.AddBadgeTooltipSeparator()
        Widgets.AddSmartActionTooltipLine()
        Widgets.AddMacroTooltipLine(MM.DB:ResolveSmartAction({ source = assignment.source, id = assignment.id }))
      end
    else
      GameTooltip:AddLine(L["Not managed \226\128\148 click to manage"], 0.7, 0.7, 0.7)
    end
    local others = LayersTab.grid and LayersTab.grid.otherLayers and LayersTab.grid.otherLayers[slot]
    if others then
      GameTooltip:AddLine(
        string.format(assignment and L["Also managed by: %s"] or L["Managed by: %s"], table.concat(others, ", ")),
        Widgets.unpackColor(colors.otherLayer)
      )
    end
    GameTooltip:Show()
  end)
  hit:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)

  return { icon = icon, hit = hit }
end

function LayersTab:BuildLegend(parent)
  local strip = CreateFrame("Frame", nil, parent)

  -- Badge glyphs on the first line, slot states on the second. Badge entries
  -- show the badge tile itself (as it appears on a cell) rather than a
  -- bordered swatch.
  local entries = {
    { icon = Widgets.ICON.smartAction, label = L["Smart Action"] },
    { icon = Widgets.ICON.macro, label = L["Macro"] },
    { label = L["Managed by this Layer"], newRow = true },
    { label = L["Managed by another Layer"], color = colors.otherLayer, alpha = 0.55 },
    { symbol = Widgets.TEX.empty, label = L["Empty (clears)"] },
  }

  -- Wrap-flow within the grid's width so the legend never runs into the
  -- sidebar. The strip is anchored by a single point, so it needs an explicit
  -- size for its rect to resolve (without one it doesn't render at all).
  local wrapWidth = LABEL_WIDTH + MM.ACTIONS_PER_BAR * (CELL + CELL_GAP)
  local rowHeight = 26
  local x, row = 4, 0
  for _, entry in ipairs(entries) do
    local swatch
    if entry.icon then
      swatch = Widgets.IconBadge(strip, 18, entry.icon)
      swatch:ClearAllPoints()
    else
      swatch = Widgets.Icon(strip, 18)
      if entry.symbol then
        swatch:SetSymbol(entry.symbol)
      else
        swatch:SetTextureImage(nil)
      end
      swatch:SetBorder(2, entry.color or colors.managed, entry.alpha)
    end

    local label = Widgets.Label(strip, "GameFontHighlightSmall", entry.label, colors.parchment)
    local width = 24 + label:GetStringWidth() + 22
    if x > 4 and (entry.newRow or x + width > wrapWidth) then
      x, row = 4, row + 1
    end
    swatch:SetPoint("TOPLEFT", strip, "TOPLEFT", x, -(row * rowHeight) - 3)
    label:SetPoint("LEFT", swatch, "RIGHT", 6, 0)
    x = x + width
  end
  strip:SetSize(wrapWidth, (row + 1) * rowHeight)

  return strip
end

-- The grid is built once into a persistent, pooled structure and re-attached to
-- the current centre on each rebuild; cells (keyed by slot) and bar-row labels
-- are reused and repainted rather than recreated, so a Layers refresh no longer
-- orphans ~150 icon frames.
function LayersTab:BuildGrid(parent, layerId, layer)
  local grid = LayersTab.grid
  if not grid then
    grid = { cells = {}, rowLabels = {} }
    LayersTab.grid = grid

    grid.frame = CreateFrame("Frame", nil, parent)

    grid.title = Widgets.Title(grid.frame, "")
    grid.title:SetPoint("TOPLEFT", grid.frame, "TOPLEFT", 12, -2)

    grid.pill = Widgets.Pill(grid.frame, L["Imported"], Widgets.ICON.import)
    grid.pill:SetPoint("LEFT", grid.title, "RIGHT", 8, 0)

    grid.delete = Widgets.Button(grid.frame, L["Delete"], 60, function()
      local id = MM.DB:GetSelectedLayerId()
      local m = MM.DB:GetLayer(id)
      deleteLayer(id, m and m.name or id)
    end)
    grid.delete:SetPoint("TOPRIGHT", grid.frame, "TOPRIGHT", -12, -2)

    grid.rename = Widgets.Button(grid.frame, L["Rename"], 66, function()
      local id = MM.DB:GetSelectedLayerId()
      local m = MM.DB:GetLayer(id)
      renameLayer(id, m and m.name or id)
    end)
    grid.rename:SetPoint("RIGHT", grid.delete, "LEFT", -6, 0)

    local hint = Widgets.Hint(grid.frame, L["Click a slot to manage it \194\183 right-click to stop managing it"])
    hint:SetPoint("TOPLEFT", grid.title, "BOTTOMLEFT", 0, -14)
    -- Bounded right, so a longer translation wraps instead of running past the grid.
    hint:SetPoint("RIGHT", grid.frame, "RIGHT", -12, 0)
    hint:SetJustifyH("LEFT")

    -- Column headers.
    grid.headerRow = CreateFrame("Frame", nil, grid.frame)
    grid.headerRow:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -22)
    grid.headerRow:SetSize(LABEL_WIDTH + MM.ACTIONS_PER_BAR * (CELL + CELL_GAP), 16)
    for column = 1, MM.ACTIONS_PER_BAR do
      local label = Widgets.Label(grid.headerRow, "GameFontHighlightSmall", tostring(column), colors.parchment)
      label:SetPoint("LEFT", grid.headerRow, "LEFT", LABEL_WIDTH + (column - 1) * (CELL + CELL_GAP) + CELL / 2, 0)
      label:SetJustifyH("CENTER")
    end

    grid.area = CreateFrame("Frame", nil, grid.frame)
    grid.area:SetPoint("TOPLEFT", grid.headerRow, "BOTTOMLEFT", 0, -2)

    grid.legend = self:BuildLegend(grid.frame)
  end

  -- Re-attach onto the current centre (recreated each rebuild) and refresh chrome.
  grid.frame:SetParent(parent)
  grid.frame:ClearAllPoints()
  grid.frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
  grid.frame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
  grid.frame:Show()

  grid.title:SetText(layer and layer.name or layerId)
  grid.pill:SetActive(MM.Share:IsRecentImport("layers", MM.DB:GetActiveProfileId(), layerId))
  if MM.Tables.Count(MM.DB:Layers() or {}) <= 1 then
    grid.delete:Disable()
  else
    grid.delete:Enable()
  end

  -- Bars (real Edit Mode bars and their scattered slot ranges, not 1..120 linear).
  grid.otherLayers = otherLayerSlots(layerId)
  local bars = MM.Actions.GetGridBars()
  local active = {}
  for barIndex, bar in ipairs(bars) do
    local y = -(barIndex - 1) * (CELL + CELL_GAP)

    local rowLabel = grid.rowLabels[barIndex]
    if not rowLabel then
      rowLabel = Widgets.Label(grid.area, "GameFontHighlightSmall", "", colors.parchment)
      grid.rowLabels[barIndex] = rowLabel
    end
    rowLabel:ClearAllPoints()
    rowLabel:SetPoint("TOPLEFT", grid.area, "TOPLEFT", 0, y - (CELL - 12) / 2)
    rowLabel:SetText(L[bar.label])
    rowLabel:Show()

    for button = 1, MM.ACTIONS_PER_BAR do
      local slot = bar.base + button
      active[slot] = true
      local cell = grid.cells[slot]
      if not cell then
        cell = self:BuildSlotCell(grid.area, slot)
        grid.cells[slot] = cell
      end
      cell.icon:ClearAllPoints()
      cell.icon:SetPoint("TOPLEFT", grid.area, "TOPLEFT", LABEL_WIDTH + (button - 1) * (CELL + CELL_GAP), y)
      cell.icon:Show()
      paintSlot(cell.icon, layer, slot, nil, grid.otherLayers)
    end
  end

  -- Hide cells and row labels left over from a previous (larger) bar layout.
  for slot, cell in pairs(grid.cells) do
    if not active[slot] then
      cell.icon:Hide()
    end
  end
  for index = #bars + 1, #grid.rowLabels do
    grid.rowLabels[index]:Hide()
  end

  grid.area:SetSize(LABEL_WIDTH + MM.ACTIONS_PER_BAR * (CELL + CELL_GAP), #bars * (CELL + CELL_GAP))
  grid.legend:ClearAllPoints()
  grid.legend:SetPoint("BOTTOMLEFT", grid.frame, "BOTTOMLEFT", 12, 10)
end

-- Repaint the changed grid cell(s) in place (slot; 0/nil = bulk); no-ops when the grid is hidden.
function LayersTab:OnBarsChanged(slot)
  local grid = LayersTab.grid
  if not grid or not grid.frame:IsVisible() then
    return
  end

  local layer = MM.DB:GetLayer(MM.DB:GetSelectedLayerId())
  if slot and slot ~= 0 then
    local cell = grid.cells[slot]
    if cell and cell.icon:IsShown() then
      paintSlot(cell.icon, layer, slot, nil, grid.otherLayers)
    end
    return
  end

  for cellSlot, cell in pairs(grid.cells) do
    if cell.icon:IsShown() then
      paintSlot(cell.icon, layer, cellSlot, nil, grid.otherLayers)
    end
  end
end

function LayersTab:BuildEmptyGrid(parent)
  local box = CreateFrame("Frame", nil, parent)
  box:SetPoint("CENTER")
  box:SetSize(360, 160)

  local heading = Widgets.Label(box, "GameFontNormalLarge", L["No Layers yet"], colors.parchment)
  heading:SetPoint("TOP", box, "TOP", 0, 0)

  local body = Widgets.Label(
    box,
    "GameFontHighlightSmall",
    L["Layers stack to decide what each action-bar slot becomes. Create your first one to start managing slots."]
  )
  body:SetPoint("TOP", heading, "BOTTOM", 0, -10)
  body:SetWidth(340)
  body:SetJustifyH("CENTER")
  body:SetTextColor(Widgets.unpackColor(colors.faint))

  local button = Widgets.Button(box, L["+ New Layer"], 140, newLayer)
  button:SetPoint("TOP", body, "BOTTOM", 0, -16)
end

-- Right slot editor ----------------------------------------------------------

-- The Slot Editor's drop overlay: drop a pinnable action anywhere on the sidebar
-- to pin it to the selected slot.
local function dropZone()
  if not LayersTab.dropZone then
    LayersTab.dropZone = Widgets.DropZone(L["Drop to pin this action"])
  end
  return LayersTab.dropZone
end

-- Initializer for a "Bind to a Smart Action" row (recycled by Widgets.DataList). The
-- click reads the live selected layer/slot, since the list outlives any rebuild.
-- A `header` item renders as a plain section title instead — rows are pooled
-- across both kinds, so each pass shows/hides the other kind's children.
local function smartActionBindRowInit(row, data)
  local smartAction = data.smartAction
  if not row.mmInit then
    row.mmInit = true
    Widgets.decorateRow(row)

    row.headerLabel = Widgets.SectionHeader(row, "")
    row.headerLabel:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 4)

    row.tile = Widgets.Icon(row, 24)
    row.tile:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.tile:SetBadge(true)

    row.nameLabel = Widgets.Label(row, "GameFontHighlight", "")
    row.nameLabel:SetPoint("LEFT", row.tile, "RIGHT", 8, 0)

    row.resolution = Widgets.Label(row, "GameFontDisableSmall", "")
    row.resolution:SetPoint("RIGHT", row, "RIGHT", -8, 0)

    row:SetScript("OnClick", function(self)
      local m = self.data and self.data.smartAction
      local layerId = MM.DB:GetSelectedLayerId()
      local slot = MM.DB:GetSelectedSlot()
      if m and layerId and slot then
        assignSlot(layerId, slot, { type = "action", source = m.source, id = m.id })
      end
    end)

    -- Tooltip on the icon only; the resolved spell/item plus a note on what the
    -- fork and { } badges mean.
    Widgets.AttachIconTooltip(row.tile, function(r)
      local m = r.data and r.data.smartAction
      if not m then
        return
      end
      local resolved = resolveSmartAction(m.source, m.id)
      if resolved then
        Widgets.SetActionTooltip(r.tile, resolved.kind, resolved.id, resolved.label)
      else
        Widgets.SetActionTooltip(r.tile, nil, nil, m.name)
      end
      Widgets.AddBadgeTooltipSeparator()
      Widgets.AddSmartActionTooltipLine()
      Widgets.AddMacroTooltipLine(MM.DB:ResolveSmartAction({ source = m.source, id = m.id }))
    end)
  end

  row.data = data
  if data.header then
    row:EnableMouse(false)
    row.headerLabel:SetText(data.header)
    row.headerLabel:Show()
    row.tile:Hide()
    row.nameLabel:SetText("")
    row.resolution:SetText("")
    return
  end
  row:EnableMouse(true)
  row.headerLabel:Hide()
  row.tile:Show()

  local smartActionObj = MM.DB:ResolveSmartAction({ source = smartAction.source, id = smartAction.id })
  row.tile:SetMacroBadge(smartActionObj ~= nil and MM.Macros.EffectiveMode(smartActionObj) == "macro")
  local resolved = resolveSmartAction(smartAction.source, smartAction.id)
  if resolved and resolved.icon then
    row.tile:SetTextureImage(resolved.icon)
    row.tile:SetBorder(1, colors.managed)
  else
    row.tile:SetSymbol(Widgets.TEX.warning)
    row.tile:SetBorder(1, colors.warn, 0.7)
  end

  row.nameLabel:SetText(smartAction.name)
  row.resolution:SetText(resolved and resolved.label or L["no match"])
  row.resolution:SetTextColor(Widgets.unpackColor(resolved and colors.goldDim or colors.danger))
end

function LayersTab:BuildEditor(parent, layerId, layer)
  local inset = CreateFrame("Frame", nil, parent)
  inset:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
  inset:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
  inset:SetWidth(EDITOR_WIDTH + 2)

  local slot = MM.DB:GetSelectedSlot()
  if not slot then
    -- No slot selected: the sidebar edits the whole layer's conditions.
    if LayersTab.dropZone then
      LayersTab.dropZone:Detach()
    end

    local header = Widgets.SectionHeader(inset, L["Layer Conditions"])
    header:SetPoint("TOPLEFT", inset, "TOPLEFT", 16, -14)

    local hint = Widgets.Hint(inset, L["When should this Layer apply? Leave everything off to always apply it."])
    hint:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -8)
    hint:SetPoint("RIGHT", inset, "RIGHT", -14, 0)
    hint:SetJustifyH("LEFT")

    if layer then
      -- The editor outgrows the panel once several sections are expanded, so it
      -- lives in a scroll region; the scrollbar appears only when it overflows.
      local scrollBox, content = Widgets.ScrollList(inset, "layers.conditions")
      scrollBox:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -14)
      scrollBox:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -20, 12)
      -- The editor edits a scratch copy; every change is committed through the
      -- DB so config mutations stay behind one door.
      local working = MM.Tables.DeepCopy(layer.conditions or {})
      local editor = MM.ui.ConditionsEditor:Build(content, working, true, function()
        MM.DB:SetLayerConditions(layerId, working)
        refresh()
      end, EDITOR_WIDTH - 40)
      editor:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
      editor:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, 0)
      content:SetHeight(editor:GetHeight())
    end
    return
  end

  local assignment = layer and layer.slots and layer.slots[slot]

  local header = Widgets.SectionHeader(inset, L["Slot Editor"])
  header:SetPoint("TOPLEFT", inset, "TOPLEFT", 16, -14)

  local icon = Widgets.Icon(inset, 36)
  icon:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -10)
  paintSlot(icon, layer, slot, true)
  Widgets.AttachIconTooltip(icon, function()
    if not assignment then
      return
    end
    if assignment.type == "action" then
      local resolved = resolveSmartAction(assignment.source, assignment.id)
      if resolved then
        Widgets.SetActionTooltip(icon, resolved.kind, resolved.id, resolved.label)
      else
        Widgets.SetActionTooltip(icon, nil, nil, MM.Actions.GetAssignmentLabel(assignment))
      end
      Widgets.AddBadgeTooltipSeparator()
      Widgets.AddSmartActionTooltipLine()
      Widgets.AddMacroTooltipLine(MM.DB:ResolveSmartAction({ source = assignment.source, id = assignment.id }))
    else
      Widgets.SetActionTooltip(icon, assignment.type, assignment.id, MM.Actions.GetAssignmentLabel(assignment))
    end
  end)

  local title = Widgets.Label(inset, "GameFontHighlight", MM.Actions.GetAssignmentLabel(assignment))
  title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -2)
  title:SetPoint("RIGHT", inset, "RIGHT", -14, 0)
  title:SetJustifyH("LEFT")
  title:SetWordWrap(false)

  local loc = Widgets.Label(inset, "GameFontDisableSmall", MM.Actions.GetSlotLabel(slot))
  loc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)

  -- One outer edge each: anchoring both would pin them to half the inset and
  -- override the width Button sized to the caption.
  local emptyButton = Widgets.Button(inset, L["Empty"], 70, function()
    assignSlot(layerId, slot, { type = "empty" })
  end)
  emptyButton:SetPoint("BOTTOMLEFT", inset, "BOTTOMLEFT", 16, 12)

  local stopButton = Widgets.Button(inset, L["Stop managing"], 120, function()
    unmanageSlot(layerId, slot)
  end)
  stopButton:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -14, 12)

  -- The whole panel is a drop target (see the overlay); the hint sits just under
  -- the assigned-action icon.
  local dropHint =
    Widgets.Hint(inset, L["Drag a spell, item, macro, mount or equipment set onto this panel to pin it to the slot."])
  dropHint:SetPoint("TOPLEFT", icon, "BOTTOMLEFT", 0, -12)
  dropHint:SetPoint("RIGHT", inset, "RIGHT", -14, 0)
  dropHint:SetJustifyH("LEFT")

  -- Regular assignments can be promoted into a new Smart Action in one step.
  local sectionAnchor = dropHint
  if assignment and assignment.type ~= "empty" and assignment.type ~= "action" then
    local convert = Widgets.Button(inset, L["Convert to Smart Action"], 180, function()
      convertToSmartAction(layerId, slot, assignment)
    end)
    convert:SetPoint("TOPLEFT", dropHint, "BOTTOMLEFT", 0, -12)
    sectionAnchor = convert
  end

  -- "Bind to a Smart Action"
  local smartActionHeader = Widgets.SectionHeader(inset, L["Bind to a Smart Action"])
  smartActionHeader:SetPoint("TOPLEFT", sectionAnchor, "BOTTOMLEFT", 0, -16)

  local list = Widgets.DataList(inset, "layers.smartActionbind", {
    extent = 34,
    spacing = 3,
    initializer = smartActionBindRowInit,
  })
  list.scrollBox:SetPoint("TOPLEFT", smartActionHeader, "BOTTOMLEFT", 0, -8)
  list.scrollBox:SetPoint("BOTTOMRIGHT", stopButton, "TOPRIGHT", 0, 10)

  -- Two sections mirroring the Smart Actions rail, so two smart actions
  -- sharing a name are still distinguishable here.
  local custom, predefined = smartActionList()
  local items = { { header = L["Your Smart Actions"], extent = 22 } }
  for _, smartAction in ipairs(custom) do
    items[#items + 1] = { smartAction = smartAction }
  end
  items[#items + 1] = { header = L["Predefined"], extent = 30 }
  for _, smartAction in ipairs(predefined) do
    items[#items + 1] = { smartAction = smartAction }
  end
  list:SetItems(items)

  dropZone():Attach(inset, function()
    assignFromCursor(layerId, slot)
  end)
end

-- Assembly -------------------------------------------------------------------

function LayersTab:BuildContent(parent)
  local layerId = MM.DB:GetSelectedLayerId()
  local layer = MM.DB:GetLayer(layerId)

  self:BuildRail(parent)
  self:BuildEditor(parent, layerId, layer)

  local leftGroove = Widgets.VGroove(parent)
  leftGroove:SetPoint("TOPLEFT", parent, "TOPLEFT", RAIL_WIDTH + 6, -6)
  leftGroove:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", RAIL_WIDTH + 6, 6)

  local rightGroove = Widgets.VGroove(parent)
  rightGroove:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -(EDITOR_WIDTH + 6), -6)
  rightGroove:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -(EDITOR_WIDTH + 6), 6)

  -- A button behind the grid: clicking empty centre space deselects the slot
  -- (interactive children handle their own clicks first).
  local center = CreateFrame("Button", nil, parent)
  center:SetPoint("TOPLEFT", parent, "TOPLEFT", RAIL_WIDTH + 14, -14)
  center:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -(EDITOR_WIDTH + 14), 10)
  center:RegisterForClicks("LeftButtonUp")
  center:SetScript("OnClick", function()
    if MM.DB:GetSelectedSlot() then
      MM.DB:SetSelectedSlot(nil)
      refresh()
    end
  end)

  if #MM.DB:GetProfileLayers() == 0 then
    self:BuildEmptyGrid(center)
  else
    self:BuildGrid(center, layerId, layer)
  end
end

function LayersTab:Build(parent)
  self.parent = parent
  self:Refresh()
end

function LayersTab:Refresh()
  if not self.parent then
    return
  end
  Widgets.ClearChildren(self.parent)
  self:BuildContent(self.parent)
end
