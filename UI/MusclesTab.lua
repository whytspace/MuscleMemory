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
local CELL = 30
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

function MusclesTab:BuildRail(parent, muscleId)
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

  local scroll, content = Widgets.ScrollList(inset)
  scroll:SetPoint("TOPLEFT", inset, "TOPLEFT", 8, -8)
  scroll:SetPoint("BOTTOMRIGHT", footer, "TOPRIGHT", -8, 6)

  local muscles = MM.DB:GetProfileMuscles()
  self.railRows = {}

  local y = 0
  for index, entry in ipairs(muscles) do
    local row = Widgets.ListRow(content, 32)
    row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
    row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, y)
    row:SetSelected(entry.id == muscleId)
    row.index = index
    self.railRows[index] = row

    local handle = Widgets.DragDots(row)
    handle:SetPoint("LEFT", row, "LEFT", 9, 0)

    local order = Widgets.Label(row, "GameFontNormalSmall", tostring(index))
    order:SetPoint("LEFT", handle, "RIGHT", 6, 0)
    order:SetWidth(16)
    order:SetJustifyH("LEFT")
    order:SetTextColor(Widgets.unpackColor(entry.id == muscleId and colors.gold or colors.faint))

    local check = Widgets.Checkbox(row, entry.enabled, function()
      MM.DB:SetMuscleEnabled(entry.id, not entry.enabled)
      refresh()
    end)
    check:SetPoint("RIGHT", row, "RIGHT", -4, 0)

    local name = Widgets.Label(row, "GameFontHighlight", entry.name)
    name:SetPoint("LEFT", order, "RIGHT", 8, 0)
    name:SetPoint("RIGHT", check, "LEFT", -4, 0)
    name:SetJustifyH("LEFT")
    name:SetWordWrap(false)
    if not entry.enabled then
      name:SetTextColor(Widgets.unpackColor(colors.faint))
    elseif entry.id == muscleId then
      name:SetTextColor(Widgets.unpackColor(colors.gold))
    end

    row:SetScript("OnClick", function(_, mouseButton)
      if mouseButton == "RightButton" then
        return
      end
      MM.DB:SetSelectedMuscleId(entry.id)
      MM.DB:SetSelectedSlot(nil)
      refresh()
    end)

    -- Drag a row onto another to reorder. Both scripts fire on the source, so
    -- the drop target is whichever row the cursor is over on release.
    row:RegisterForDrag("LeftButton")
    row:SetScript("OnDragStart", function(frame)
      frame:SetAlpha(0.5)
      MusclesTab._dragFrom = entry.id
    end)
    row:SetScript("OnDragStop", function(frame)
      frame:SetAlpha(1)
      local fromId = MusclesTab._dragFrom
      MusclesTab._dragFrom = nil
      if not fromId then
        return
      end
      for _, candidate in ipairs(MusclesTab.railRows) do
        if candidate:IsMouseOver() then
          MM.DB:MoveMuscle(fromId, candidate.index)
          refresh()
          return
        end
      end
    end)

    y = y - 36
  end
  content:SetHeight(math.max(1, -y))

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

function MusclesTab:BuildSlot(parent, muscleId, muscle, slot, x, y)
  local icon = Widgets.Icon(parent, CELL)
  icon:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  icon:EnableMouse(true)
  icon:RegisterForDrag("LeftButton")
  paintSlot(icon, muscle, slot)

  -- Hit area / click handling lives on a button overlay so the Icon stays a
  -- pure visual.
  local hit = CreateFrame("Button", nil, icon)
  hit:SetAllPoints()
  hit:RegisterForClicks("LeftButtonUp", "RightButtonUp")

  hit:SetScript("OnClick", function(_, mouseButton)
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
      MM.DB:SetSelectedSlot(slot)
      refresh()
    else
      manageSlot(muscleId, slot)
    end
  end)
  hit:SetScript("OnReceiveDrag", function()
    assignFromCursor(muscleId, slot)
  end)
  hit:SetScript("OnEnter", function(frame)
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

function MusclesTab:BuildGrid(parent, muscleId, muscle)
  local title = Widgets.Title(parent, muscle and muscle.name or muscleId)
  title:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, -2)

  local rename = Widgets.Button(parent, "Rename", 66, function()
    renameMuscle(muscleId, muscle and muscle.name or muscleId)
  end)
  rename:SetPoint("LEFT", title, "RIGHT", 14, 0)

  local delete = Widgets.Button(parent, "Delete", 60, function()
    deleteMuscle(muscleId, muscle and muscle.name or muscleId)
  end)
  delete:SetPoint("LEFT", rename, "RIGHT", 6, 0)
  if MM.Tables.Count(MM.DB:GetRoot().muscles or {}) <= 1 then
    delete:Disable()
  end

  local hint =
    Widgets.Hint(parent, "Click a slot to manage it \194\183 right-click to stop \194\183 click a managed slot to edit")
  hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)

  -- Column headers.
  local headerRow = CreateFrame("Frame", nil, parent)
  headerRow:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -8)
  headerRow:SetSize(LABEL_WIDTH + MM.ACTIONS_PER_BAR * (CELL + CELL_GAP), 16)
  for column = 1, MM.ACTIONS_PER_BAR do
    local label = Widgets.Label(headerRow, "GameFontDisableSmall", tostring(column))
    label:SetPoint("LEFT", headerRow, "LEFT", LABEL_WIDTH + (column - 1) * (CELL + CELL_GAP) + CELL / 2, 0)
    label:SetJustifyH("CENTER")
  end

  -- Bars (real Edit Mode bars and their scattered slot ranges, not 1..120 linear).
  local bars = MM.Actions.GetGridBars()
  local grid = CreateFrame("Frame", nil, parent)
  grid:SetPoint("TOPLEFT", headerRow, "BOTTOMLEFT", 0, -2)

  for barIndex, bar in ipairs(bars) do
    local y = -(barIndex - 1) * (CELL + CELL_GAP)
    local rowLabel = Widgets.Label(grid, "GameFontHighlightSmall", bar.label, colors.parchment)
    rowLabel:SetPoint("TOPLEFT", grid, "TOPLEFT", 0, y - (CELL - 12) / 2)

    for button = 1, MM.ACTIONS_PER_BAR do
      local slot = bar.base + button
      local x = LABEL_WIDTH + (button - 1) * (CELL + CELL_GAP)
      self:BuildSlot(grid, muscleId, muscle, slot, x, y)
    end
  end
  grid:SetSize(LABEL_WIDTH + MM.ACTIONS_PER_BAR * (CELL + CELL_GAP), #bars * (CELL + CELL_GAP))

  local legend = self:BuildLegend(parent)
  legend:SetPoint("TOPLEFT", grid, "BOTTOMLEFT", 0, -14)
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

function MusclesTab:BuildEditor(parent, muscleId, muscle)
  local inset = CreateFrame("Frame", nil, parent)
  inset:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
  inset:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
  inset:SetWidth(EDITOR_WIDTH)

  local slot = MM.DB:GetSelectedSlot()
  if not slot then
    if MusclesTab.dropZone then
      MusclesTab.dropZone:Detach()
    end
    local note = Widgets.Label(
      inset,
      "GameFontHighlightSmall",
      "Click a slot in the grid to manage it in this Muscle and edit it here."
    )
    note:SetPoint("TOPLEFT", inset, "TOPLEFT", 16, -20)
    note:SetPoint("TOPRIGHT", inset, "TOPRIGHT", -16, -20)
    note:SetJustifyH("LEFT")
    note:SetTextColor(Widgets.unpackColor(colors.faint))
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

  local scroll, content = Widgets.ScrollList(inset)
  scroll:SetPoint("TOPLEFT", memoryHeader, "BOTTOMLEFT", 0, -8)
  scroll:SetPoint("BOTTOMRIGHT", dropHint, "TOPRIGHT", -14, -10)

  local y = 0
  for _, memory in ipairs(memoryList()) do
    local row = Widgets.ListRow(content, 34)
    row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
    row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, y)

    local resolved = resolveMemory(memory.source, memory.id)
    local tile = Widgets.Icon(row, 24)
    tile:SetPoint("LEFT", row, "LEFT", 6, 0)
    tile:SetBadge(true)
    if resolved and resolved.icon then
      tile:SetTextureImage(resolved.icon)
      tile:SetBorder(1, colors.managed)
    else
      tile:SetSymbol(Widgets.TEX.warning)
      tile:SetBorder(1, colors.warn, 0.7)
    end

    local name = Widgets.Label(row, "GameFontHighlight", memory.name)
    name:SetPoint("LEFT", tile, "RIGHT", 8, 0)

    local resolutionText = resolved and resolved.label or "no match"
    local resolution = Widgets.Label(row, "GameFontDisableSmall", resolutionText)
    resolution:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    resolution:SetTextColor(Widgets.unpackColor(resolved and colors.goldDim or colors.danger))

    row:SetScript("OnClick", function()
      assignSlot(muscleId, slot, { type = "memory", source = memory.source, id = memory.id })
    end)

    y = y - 37
  end
  content:SetHeight(math.max(1, -y))

  dropZone():Attach(inset, function()
    assignFromCursor(muscleId, slot)
  end)
end

-- Assembly -------------------------------------------------------------------

function MusclesTab:Build(parent)
  local muscleId = MM.DB:GetSelectedMuscleId()
  local muscle = MM.DB:GetMuscle(muscleId)

  self:BuildRail(parent, muscleId)
  self:BuildEditor(parent, muscleId, muscle)

  local leftGroove = Widgets.VGroove(parent)
  leftGroove:SetPoint("TOPLEFT", parent, "TOPLEFT", RAIL_WIDTH + 6, -6)
  leftGroove:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", RAIL_WIDTH + 6, 6)

  local rightGroove = Widgets.VGroove(parent)
  rightGroove:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -(EDITOR_WIDTH + 6), -6)
  rightGroove:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -(EDITOR_WIDTH + 6), 6)

  local center = CreateFrame("Frame", nil, parent)
  center:SetPoint("TOPLEFT", parent, "TOPLEFT", RAIL_WIDTH + 14, -10)
  center:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -(EDITOR_WIDTH + 14), 10)

  if #MM.DB:GetProfileMuscles() == 0 then
    self:BuildEmptyGrid(center)
  else
    self:BuildGrid(center, muscleId, muscle)
  end
end
