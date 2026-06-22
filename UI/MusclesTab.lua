local ADDON_NAME, MM = ...

-- The Muscles tab: left rail of muscles in the active profile, the centre grid
-- mirroring the player's live bars (each slot managed / pinned / memory-driven /
-- empty / pass-through), and the right-hand Slot Editor. Wired straight to DB,
-- Capture, Resolver and Actions.
local MusclesTab = {}
MM.ui.MusclesTab = MusclesTab

local Widgets = MM.ui.Widgets
local colors = Widgets.colors

local RAIL_WIDTH = 250
local EDITOR_WIDTH = 330
local CELL = 28
local CELL_GAP = 4
local LABEL_WIDTH = 64

local function refresh()
  MM.UI:Refresh()
end

-- Slot mutations -------------------------------------------------------------

local function assignSlot(muscleId, slot, assignment)
  MM.DB:SetSlot(muscleId, slot, assignment)
  MM.DB:SetSelectedSlot(slot)
  refresh()
end

local function assignFromCursor(muscleId, slot)
  local assignment, reason = MM.Capture:FromCursor()
  if not assignment then
    MM:Warn(reason or "could not read cursor")
    return
  end
  assignSlot(muscleId, slot, assignment)
  if ClearCursor then
    ClearCursor()
  end
end

-- Left-clicking a not-managed slot starts managing it, capturing whatever is
-- live there (or Empty if the bar slot is blank).
local function manageSlot(muscleId, slot)
  local ok, reason = MM.Capture:CaptureSlot(muscleId, slot)
  if not ok then
    MM.DB:SetSlot(muscleId, slot, { type = "empty" })
    if reason ~= "slot has no capturable action" then
      MM:Warn(reason or "could not capture slot")
    end
  end
  MM.DB:SetSelectedSlot(slot)
  refresh()
end

local function unmanageSlot(muscleId, slot)
  MM.DB:SetSlot(muscleId, slot, nil)
  if MM.DB:GetSelectedSlot() == slot then
    MM.DB:SetSelectedSlot(nil)
  end
  refresh()
end

-- Memory helpers -------------------------------------------------------------

local function memoryList()
  local memories = {}
  for id, memory in pairs(MM.StandardMemories or {}) do
    memories[#memories + 1] = { source = "standard", id = id, name = memory.name or id }
  end
  for id, memory in pairs(MM.DB:GetRoot().customMemories or {}) do
    memories[#memories + 1] = { source = "custom", id = id, name = memory.name or id }
  end
  table.sort(memories, function(left, right)
    return left.name < right.name
  end)
  return memories
end

local function resolveMemory(source, id)
  return MM.Resolver:ResolveAction({ type = "memory", source = source, id = id })
end

-- Muscle CRUD ----------------------------------------------------------------

local function newMuscle()
  MM.ui.Modals.Input("New Muscle", "Name the new Muscle", "New Muscle", "Create", function(name)
    local id = MM.DB:CreateMuscle(name ~= "" and name or nil)
    MM.DB:SetSelectedMuscleId(id)
    MM.DB:SetSelectedSlot(nil)
    refresh()
  end)
end

local function renameMuscle(muscleId, currentName)
  MM.ui.Modals.Input("Rename Muscle", "New name for this Muscle", currentName, "Rename", function(name)
    if name == "" then
      return
    end
    local ok, reason = MM.DB:RenameMuscle(muscleId, name)
    if not ok then
      MM:Warn(reason)
    end
    refresh()
  end)
end

local function deleteMuscle(muscleId, currentName)
  MM.ui.Modals.Confirm(
    "Delete Muscle",
    string.format(
      'Delete Muscle "%s"? Slots it managed will fall through to lower Muscles on the next apply.',
      currentName
    ),
    "Delete",
    function()
      local ok, reason = MM.DB:DeleteMuscle(muscleId)
      if not ok then
        MM:Warn(reason)
      end
      refresh()
    end
  )
end

-- Left rail ------------------------------------------------------------------

-- Initializer for a muscle rail row (recycled by Widgets.DataList).
local function muscleRowInit(row, data)
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
        MM.DB:SetMuscleEnabled(e.id, not e.enabled)
        refresh()
      end
    end)

    row.nameLabel = Widgets.Label(row, "GameFontHighlight", "")
    row.nameLabel:SetPoint("LEFT", row.order, "RIGHT", 8, 0)
    row.nameLabel:SetPoint("RIGHT", row.check, "LEFT", -4, 0)
    row.nameLabel:SetJustifyH("LEFT")
    row.nameLabel:SetWordWrap(false)

    row:SetScript("OnClick", function(self, mouseButton)
      if mouseButton == "RightButton" then
        return
      end
      local e = self.data and self.data.entry
      if e then
        MM.DB:SetSelectedMuscleId(e.id)
        MM.DB:SetSelectedSlot(nil)
        refresh()
      end
    end)

    -- Drag a row onto another to reorder; the target is whichever row the cursor
    -- is over on release.
    row:SetScript("OnDragStart", function(self)
      self:SetAlpha(0.5)
      MusclesTab._dragFrom = self.data and self.data.entry.id
    end)
    row:SetScript("OnDragStop", function(self)
      self:SetAlpha(1)
      local fromId = MusclesTab._dragFrom
      MusclesTab._dragFrom = nil
      if not fromId or not MusclesTab.railList then
        return
      end
      local target
      MusclesTab.railList:ForEachFrame(function(frame)
        if frame.data and frame:IsMouseOver() then
          target = frame.data.index
        end
      end)
      if target then
        MM.DB:MoveMuscle(fromId, target)
        refresh()
      end
    end)
  end

  row.data = data
  local active = entry.id == MM.DB:GetSelectedMuscleId()

  row.order:SetText(tostring(data.index))
  row.order:SetTextColor(Widgets.unpackColor(active and colors.gold or colors.faint))

  row.check:SetChecked(entry.enabled)

  -- A conditioned muscle whose conditions don't match this character won't apply,
  -- so it reads as inactive (like a disabled one).
  local conditions = entry.muscle.conditions
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

function MusclesTab:BuildRail(parent)
  local inset = CreateFrame("Frame", nil, parent)
  inset:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
  inset:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, 0)
  inset:SetWidth(RAIL_WIDTH)

  local newButton = Widgets.Button(inset, "+ New Muscle", RAIL_WIDTH - 24, newMuscle)
  newButton:SetPoint("BOTTOM", inset, "BOTTOM", 0, 10)

  local footer = Widgets.Label(inset, "GameFontDisableSmall", "")
  footer:SetPoint("BOTTOMLEFT", newButton, "TOPLEFT", 2, 8)
  footer:SetPoint("BOTTOMRIGHT", newButton, "TOPRIGHT", -2, 8)
  footer:SetJustifyH("LEFT")
  local profile = MM.DB:GetProfile()
  footer:SetText("checked = applied in profile " .. (profile and profile.name or ""))

  local list = Widgets.DataList(inset, "muscles.rail", {
    extent = 32,
    spacing = 4,
    initializer = muscleRowInit,
  })
  MusclesTab.railList = list
  list.scrollBox:SetPoint("TOPLEFT", inset, "TOPLEFT", 8, -8)
  list.scrollBox:SetPoint("BOTTOMRIGHT", footer, "TOPRIGHT", -6, 6)

  local muscles = MM.DB:GetProfileMuscles()
  local items = {}
  for index, entry in ipairs(muscles) do
    items[#items + 1] = { index = index, entry = entry }
  end
  list:SetItems(items)

  if #muscles == 0 then
    local note = Widgets.Label(inset, "GameFontDisableSmall", "No Muscles in this profile yet.")
    note:SetPoint("TOPLEFT", inset, "TOPLEFT", 12, -16)
    note:SetPoint("TOPRIGHT", inset, "TOPRIGHT", -12, -16)
    note:SetJustifyH("LEFT")
  end
end

-- Centre grid ----------------------------------------------------------------

-- Paint one slot icon to reflect its managed state.
local function paintSlot(icon, muscle, slot)
  local assignment = muscle and muscle.slots and muscle.slots[slot]
  local managed = assignment ~= nil
  local selected = MM.DB:GetSelectedSlot() == slot

  icon:SetBadge(false)
  icon:SetAlphaAll(1)

  if not managed then
    local texture = MM.Actions.GetLiveSlotIcon(slot)
    if texture then
      icon:SetTextureImage(texture)
      icon:SetAlphaAll(0.42)
      icon:SetBorder(1, colors.faint, 0.5)
    else
      icon:SetTextureImage(nil)
      icon:SetBorder(1, colors.faint, 0.28)
    end
  elseif assignment.type == "empty" then
    icon:SetSymbol(Widgets.TEX.empty)
    icon:SetBorder(selected and 3 or 2, selected and colors.selected or colors.managed)
  elseif assignment.type == "ignore" then
    icon:SetTextureImage(MM.Actions.GetLiveSlotIcon(slot))
    icon:SetAlphaAll(0.42)
    icon:SetBorder(1, colors.faint, 0.5)
  elseif assignment.type == "memory" then
    local resolved = MM.Resolver:ResolveAction(assignment)
    icon:SetBadge(true)
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
    icon:SetBorder(selected and 3 or 2, selected and colors.selected or colors.managed)
  end
end

-- Build one reusable grid cell for a fixed slot. The cell is pooled (kept across
-- rebuilds and repainted), so its handlers read the live selected muscle rather
-- than closing over a per-build one. `slot` never changes for a given cell.
function MusclesTab:BuildSlotCell(parent, slot)
  local icon = Widgets.Icon(parent, CELL)
  icon:EnableMouse(true)
  icon:RegisterForDrag("LeftButton")

  -- Hit area / click handling lives on a button overlay so the Icon stays a
  -- pure visual.
  local hit = CreateFrame("Button", nil, icon)
  hit:SetAllPoints()
  hit:RegisterForClicks("LeftButtonUp", "RightButtonUp")

  hit:SetScript("OnClick", function(_, mouseButton)
    local muscleId = MM.DB:GetSelectedMuscleId()
    local muscle = MM.DB:GetMuscle(muscleId)
    if GetCursorInfo and GetCursorInfo() then
      assignFromCursor(muscleId, slot)
      return
    end
    local managed = muscle and muscle.slots and muscle.slots[slot] ~= nil
    if mouseButton == "RightButton" then
      if managed then
        unmanageSlot(muscleId, slot)
      end
      return
    end
    if managed then
      -- Re-clicking the selected slot deselects it (revealing the muscle's
      -- condition editor in the sidebar).
      if MM.DB:GetSelectedSlot() == slot then
        MM.DB:SetSelectedSlot(nil)
      else
        MM.DB:SetSelectedSlot(slot)
      end
      refresh()
    else
      manageSlot(muscleId, slot)
    end
  end)
  hit:SetScript("OnReceiveDrag", function()
    assignFromCursor(MM.DB:GetSelectedMuscleId(), slot)
  end)
  hit:SetScript("OnEnter", function(frame)
    local muscle = MM.DB:GetMuscle(MM.DB:GetSelectedMuscleId())
    GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
    GameTooltip:SetText(MM.Actions.GetSlotLabel(slot))
    local assignment = muscle and muscle.slots and muscle.slots[slot]
    if assignment then
      GameTooltip:AddLine(MM.Actions.GetAssignmentLabel(assignment), 1, 1, 1)
    else
      GameTooltip:AddLine("Not managed \226\128\148 click to manage", 0.7, 0.7, 0.7)
    end
    GameTooltip:Show()
  end)
  hit:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)

  return { icon = icon, hit = hit }
end

function MusclesTab:BuildLegend(parent)
  local strip = CreateFrame("Frame", nil, parent)
  strip:SetHeight(24)

  local entries = {
    { glyph = nil, badge = false, label = "Managed (pinned)" },
    { glyph = nil, badge = true, label = "Memory-driven" },
    { symbol = Widgets.TEX.empty, badge = false, label = "Empty (clears)" },
    { glyph = nil, badge = false, label = "Selected", selected = true },
  }

  local x = 4
  for _, entry in ipairs(entries) do
    local swatch = Widgets.Icon(strip, 18)
    swatch:SetPoint("LEFT", strip, "LEFT", x, 0)
    if entry.symbol then
      swatch:SetSymbol(entry.symbol)
    else
      swatch:SetTextureImage(nil)
    end
    swatch:SetBorder(2, entry.selected and colors.selected or colors.managed)
    swatch:SetBadge(entry.badge)

    local label = Widgets.Label(strip, "GameFontHighlightSmall", entry.label, colors.parchment)
    label:SetPoint("LEFT", swatch, "RIGHT", 6, 0)
    x = x + 24 + label:GetStringWidth() + 22
  end

  return strip
end

-- The grid is built once into a persistent, pooled structure and re-attached to
-- the current centre on each rebuild; cells (keyed by slot) and bar-row labels
-- are reused and repainted rather than recreated, so a Muscles refresh no longer
-- orphans ~150 icon frames.
function MusclesTab:BuildGrid(parent, muscleId, muscle)
  local grid = MusclesTab.grid
  if not grid then
    grid = { cells = {}, rowLabels = {} }
    MusclesTab.grid = grid

    grid.frame = CreateFrame("Frame", nil, parent)

    grid.title = Widgets.Title(grid.frame, "")
    grid.title:SetPoint("TOPLEFT", grid.frame, "TOPLEFT", 12, -2)

    grid.delete = Widgets.Button(grid.frame, "Delete", 60, function()
      local id = MM.DB:GetSelectedMuscleId()
      local m = MM.DB:GetMuscle(id)
      deleteMuscle(id, m and m.name or id)
    end)
    grid.delete:SetPoint("TOPRIGHT", grid.frame, "TOPRIGHT", -12, -2)

    grid.rename = Widgets.Button(grid.frame, "Rename", 66, function()
      local id = MM.DB:GetSelectedMuscleId()
      local m = MM.DB:GetMuscle(id)
      renameMuscle(id, m and m.name or id)
    end)
    grid.rename:SetPoint("RIGHT", grid.delete, "LEFT", -6, 0)

    local hint = Widgets.Hint(
      grid.frame,
      "Click a slot to manage it \194\183 right-click to stop \194\183 click a managed slot to edit"
    )
    hint:SetPoint("TOPLEFT", grid.title, "BOTTOMLEFT", 0, -14)

    -- Column headers.
    grid.headerRow = CreateFrame("Frame", nil, grid.frame)
    grid.headerRow:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -12)
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

  grid.title:SetText(muscle and muscle.name or muscleId)
  if MM.Tables.Count(MM.DB:GetRoot().muscles or {}) <= 1 then
    grid.delete:Disable()
  else
    grid.delete:Enable()
  end

  -- Bars (real Edit Mode bars and their scattered slot ranges, not 1..120 linear).
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
    rowLabel:SetText(bar.label)
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
      paintSlot(cell.icon, muscle, slot)
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
  grid.legend:SetPoint("TOPLEFT", grid.area, "BOTTOMLEFT", 0, -14)
end

-- Repaint the changed grid cell(s) in place (slot; 0/nil = bulk); no-ops when the grid is hidden.
function MusclesTab:OnBarsChanged(slot)
  local grid = MusclesTab.grid
  if not grid or not grid.frame:IsVisible() then
    return
  end

  local muscle = MM.DB:GetMuscle(MM.DB:GetSelectedMuscleId())
  if slot and slot ~= 0 then
    local cell = grid.cells[slot]
    if cell and cell.icon:IsShown() then
      paintSlot(cell.icon, muscle, slot)
    end
    return
  end

  for cellSlot, cell in pairs(grid.cells) do
    if cell.icon:IsShown() then
      paintSlot(cell.icon, muscle, cellSlot)
    end
  end
end

function MusclesTab:BuildEmptyGrid(parent)
  local box = CreateFrame("Frame", nil, parent)
  box:SetPoint("CENTER")
  box:SetSize(360, 160)

  local heading = Widgets.Label(box, "GameFontNormalLarge", "No Muscles yet", colors.parchment)
  heading:SetPoint("TOP", box, "TOP", 0, 0)

  local body = Widgets.Label(
    box,
    "GameFontHighlightSmall",
    "Muscles stack to decide what each action-bar slot becomes. Create your first one to start managing slots."
  )
  body:SetPoint("TOP", heading, "BOTTOM", 0, -10)
  body:SetWidth(340)
  body:SetJustifyH("CENTER")
  body:SetTextColor(Widgets.unpackColor(colors.faint))

  local button = Widgets.Button(box, "+ New Muscle", 140, newMuscle)
  button:SetPoint("TOP", body, "BOTTOM", 0, -16)
end

-- Right slot editor ----------------------------------------------------------

local function statusFor(assignment)
  if not assignment then
    return "Not managed.", colors.faint
  end
  if assignment.type == "empty" then
    return "Clears whatever is in this slot when the Muscle applies.", colors.parchment
  end
  if assignment.type == "memory" then
    local memory = MM.DB:GetMemory({ source = assignment.source, id = assignment.id })
    local resolved = resolveMemory(assignment.source, assignment.id)
    if resolved then
      return 'Resolves to "' .. resolved.label .. '" for this character.', colors.goldDim
    end
    return 'No candidate in "'
      .. (memory and memory.name or assignment.id)
      .. '" is usable by this character \226\128\148 the slot falls through to your live action.',
      colors.warn
  end
  return "Managed \226\128\148 pins this exact action into the slot.", colors.goldDim
end

-- The Slot Editor's drop overlay: drop a pinnable action anywhere on the sidebar
-- to pin it to the selected slot.
local function dropZone()
  if not MusclesTab.dropZone then
    MusclesTab.dropZone = Widgets.DropZone("Drop to pin this action")
  end
  return MusclesTab.dropZone
end

-- Initializer for a "Bind to a Memory" row (recycled by Widgets.DataList). The
-- click reads the live selected muscle/slot, since the list outlives any rebuild.
local function memoryBindRowInit(row, data)
  local memory = data.memory
  if not row.mmInit then
    row.mmInit = true
    Widgets.decorateRow(row)

    row.tile = Widgets.Icon(row, 24)
    row.tile:SetPoint("LEFT", row, "LEFT", 6, 0)
    row.tile:SetBadge(true)

    row.nameLabel = Widgets.Label(row, "GameFontHighlight", "")
    row.nameLabel:SetPoint("LEFT", row.tile, "RIGHT", 8, 0)

    row.resolution = Widgets.Label(row, "GameFontDisableSmall", "")
    row.resolution:SetPoint("RIGHT", row, "RIGHT", -8, 0)

    row:SetScript("OnClick", function(self)
      local m = self.data and self.data.memory
      local muscleId = MM.DB:GetSelectedMuscleId()
      local slot = MM.DB:GetSelectedSlot()
      if m and muscleId and slot then
        assignSlot(muscleId, slot, { type = "memory", source = m.source, id = m.id })
      end
    end)
  end

  row.data = data
  local resolved = resolveMemory(memory.source, memory.id)
  if resolved and resolved.icon then
    row.tile:SetTextureImage(resolved.icon)
    row.tile:SetBorder(1, colors.managed)
  else
    row.tile:SetSymbol(Widgets.TEX.warning)
    row.tile:SetBorder(1, colors.warn, 0.7)
  end

  row.nameLabel:SetText(memory.name)
  row.resolution:SetText(resolved and resolved.label or "no match")
  row.resolution:SetTextColor(Widgets.unpackColor(resolved and colors.goldDim or colors.danger))
end

function MusclesTab:BuildEditor(parent, muscleId, muscle)
  local inset = CreateFrame("Frame", nil, parent)
  inset:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
  inset:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
  inset:SetWidth(EDITOR_WIDTH + 2)

  local slot = MM.DB:GetSelectedSlot()
  if not slot then
    -- No slot selected: the sidebar edits the whole muscle's conditions.
    if MusclesTab.dropZone then
      MusclesTab.dropZone:Detach()
    end

    local header = Widgets.SectionHeader(inset, "Muscle Conditions")
    header:SetPoint("TOPLEFT", inset, "TOPLEFT", 16, -14)

    local hint = Widgets.Hint(inset, "When should this Muscle apply? Leave everything off to always apply it.")
    hint:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -8)
    hint:SetPoint("RIGHT", inset, "RIGHT", -14, 0)
    hint:SetJustifyH("LEFT")

    if muscle then
      muscle.conditions = muscle.conditions or {}
      -- The editor outgrows the panel once several sections are expanded, so it
      -- lives in a scroll region; the scrollbar appears only when it overflows.
      local scrollBox, content = Widgets.ScrollList(inset, "muscles.conditions")
      scrollBox:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -14)
      scrollBox:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -20, 12)
      local editor = MM.ui.ConditionsEditor:Build(content, muscle.conditions, true, function()
        refresh()
      end)
      editor:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
      editor:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, 0)
      content:SetHeight(editor:GetHeight())
    end
    return
  end

  local assignment = muscle and muscle.slots and muscle.slots[slot]

  local header = Widgets.SectionHeader(inset, "Slot Editor")
  header:SetPoint("TOPLEFT", inset, "TOPLEFT", 16, -14)

  local icon = Widgets.Icon(inset, 36)
  icon:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -10)
  paintSlot(icon, muscle, slot)

  local title = Widgets.Label(inset, "GameFontHighlight", MM.Actions.GetAssignmentLabel(assignment))
  title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -2)
  title:SetPoint("RIGHT", inset, "RIGHT", -14, 0)
  title:SetJustifyH("LEFT")
  title:SetWordWrap(false)

  local loc = Widgets.Label(inset, "GameFontDisableSmall", MM.Actions.GetSlotLabel(slot))
  loc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)

  local statusText, statusColor = statusFor(assignment)
  local status = Widgets.Label(inset, "GameFontHighlightSmall", statusText, statusColor)
  status:SetPoint("TOPLEFT", icon, "BOTTOMLEFT", 0, -12)
  status:SetPoint("RIGHT", inset, "RIGHT", -14, 0)
  status:SetJustifyH("LEFT")
  status:SetSpacing(2)

  -- "This slot is set to"
  local setToHeader = Widgets.SectionHeader(inset, "This slot is set to")
  setToHeader:SetPoint("TOPLEFT", status, "BOTTOMLEFT", 0, -14)

  local emptyButton = Widgets.Button(inset, "Empty (clear it)", 150, function()
    assignSlot(muscleId, slot, { type = "empty" })
  end)
  emptyButton:SetPoint("TOPLEFT", setToHeader, "BOTTOMLEFT", 0, -8)

  local stopButton = Widgets.Button(inset, "Stop managing", 130, function()
    unmanageSlot(muscleId, slot)
  end)
  stopButton:SetPoint("LEFT", emptyButton, "RIGHT", 8, 0)

  -- "Bind to a Memory"
  local memoryHeader = Widgets.SectionHeader(inset, "Bind to a Memory")
  memoryHeader:SetPoint("TOPLEFT", emptyButton, "BOTTOMLEFT", 0, -16)

  -- The whole panel is a drop target (see the overlay); a hint sits at the foot.
  local dropHint =
    Widgets.Hint(inset, "Drag a spell, item, macro, mount or equipment set onto this panel to pin it to the slot.")
  dropHint:SetPoint("BOTTOMLEFT", inset, "BOTTOMLEFT", 14, 12)
  dropHint:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -14, 12)
  dropHint:SetJustifyH("LEFT")

  local list = Widgets.DataList(inset, "muscles.memorybind", {
    extent = 34,
    spacing = 3,
    initializer = memoryBindRowInit,
  })
  list.scrollBox:SetPoint("TOPLEFT", memoryHeader, "BOTTOMLEFT", 0, -8)
  list.scrollBox:SetPoint("BOTTOMRIGHT", dropHint, "TOPRIGHT", -14, -10)

  local items = {}
  for _, memory in ipairs(memoryList()) do
    items[#items + 1] = { memory = memory }
  end
  list:SetItems(items)

  dropZone():Attach(inset, function()
    assignFromCursor(muscleId, slot)
  end)
end

-- Assembly -------------------------------------------------------------------

function MusclesTab:Build(parent)
  local muscleId = MM.DB:GetSelectedMuscleId()
  local muscle = MM.DB:GetMuscle(muscleId)

  self:BuildRail(parent)
  self:BuildEditor(parent, muscleId, muscle)

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

  if #MM.DB:GetProfileMuscles() == 0 then
    self:BuildEmptyGrid(center)
  else
    self:BuildGrid(center, muscleId, muscle)
  end
end
