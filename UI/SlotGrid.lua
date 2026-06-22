local ADDON_NAME, MM = ...

local SlotGrid = {}
MM.ui.SlotGrid = SlotGrid

local ICON_SIZE = 32
local CELL_GAP = 6
local LEFT_WIDTH = 174
local RIGHT_WIDTH = 250
local QUESTION_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local DELETE_MUSCLE_DIALOG = "MUSCLEMEMORY_DELETE_MUSCLE"

local function sortedMuscles()
  return MM.DB:GetProfileMuscles()
end

local function sortedMemories()
  local memories = {}
  for memoryId, memory in pairs(MM.StandardMemories or {}) do
    memories[#memories + 1] = { source = "standard", id = memoryId, name = memory.name or memoryId }
  end

  for memoryId, memory in pairs(MM.DB:GetRoot().customMemories or {}) do
    memories[#memories + 1] = { source = "custom", id = memoryId, name = memory.name or memoryId }
  end

  table.sort(memories, function(left, right)
    return left.name < right.name
  end)

  return memories
end

local function makeButton(parent, text, width, onClick)
  local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  button:SetSize(width or 100, 22)
  button:SetText(text)
  button:SetScript("OnClick", onClick)
  return button
end

local function makeListRow(parent, text, width, selected, onClick, rightInset, leftInset)
  local row = CreateFrame("Button", nil, parent)
  row:SetSize(width, 26)
  row:RegisterForClicks("LeftButtonUp")
  row:SetScript("OnClick", onClick)

  row.selected = row:CreateTexture(nil, "BACKGROUND")
  row.selected:SetAllPoints()
  row.selected:SetColorTexture(0.18, 0.32, 0.58, selected and 0.45 or 0)

  row.hover = row:CreateTexture(nil, "BACKGROUND")
  row.hover:SetAllPoints()
  row.hover:SetColorTexture(1, 1, 1, 0.08)
  row.hover:Hide()

  row.accent = row:CreateTexture(nil, "ARTWORK")
  row.accent:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -3)
  row.accent:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 3)
  row.accent:SetWidth(3)
  row.accent:SetColorTexture(0.45, 0.65, 1, selected and 0.9 or 0)

  row.label = row:CreateFontString(nil, "OVERLAY", selected and "GameFontHighlightSmall" or "GameFontNormalSmall")
  row.label:SetPoint("LEFT", row, "LEFT", leftInset or 8, 0)
  row.label:SetPoint("RIGHT", row, "RIGHT", -(rightInset or 6), 0)
  row.label:SetJustifyH("LEFT")
  row.label:SetText(text)

  row:SetScript("OnEnter", function(frame)
    frame.hover:Show()
  end)
  row:SetScript("OnLeave", function(frame)
    frame.hover:Hide()
  end)

  return row
end

local function makeEditBox(parent, width)
  local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
  box:SetSize(width, 22)
  box:SetAutoFocus(false)
  return box
end

local function makeCheckbox(parent, checked, onClick)
  local box = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  box:SetSize(20, 20)
  box:SetChecked(checked)
  box:SetScript("OnClick", onClick)
  return box
end

local function makeSectionLabel(parent, text)
  local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  label:SetText(text)
  return label
end

local function makeVerticalDivider(parent, relativeTo, relativePoint, x)
  local divider = parent:CreateTexture(nil, "ARTWORK")
  divider:SetPoint("TOP", relativeTo, "TOP" .. relativePoint, x, -4)
  divider:SetPoint("BOTTOM", relativeTo, "BOTTOM" .. relativePoint, x, 4)
  divider:SetWidth(1)
  divider:SetColorTexture(1, 1, 1, 0.12)
  return divider
end

local function makeSlotBorder(parent)
  local border = {}
  border.top = parent:CreateTexture(nil, "OVERLAY")
  border.top:SetPoint("TOPLEFT")
  border.top:SetPoint("TOPRIGHT")

  border.bottom = parent:CreateTexture(nil, "OVERLAY")
  border.bottom:SetPoint("BOTTOMLEFT")
  border.bottom:SetPoint("BOTTOMRIGHT")

  border.left = parent:CreateTexture(nil, "OVERLAY")
  border.left:SetPoint("TOPLEFT")
  border.left:SetPoint("BOTTOMLEFT")

  border.right = parent:CreateTexture(nil, "OVERLAY")
  border.right:SetPoint("TOPRIGHT")
  border.right:SetPoint("BOTTOMRIGHT")

  return border
end

local function setSlotBorder(border, thickness, r, g, b, a)
  border.top:SetHeight(thickness)
  border.bottom:SetHeight(thickness)
  border.left:SetWidth(thickness)
  border.right:SetWidth(thickness)

  border.top:SetColorTexture(r, g, b, a)
  border.bottom:SetColorTexture(r, g, b, a)
  border.left:SetColorTexture(r, g, b, a)
  border.right:SetColorTexture(r, g, b, a)
end

local function makeArrowButton(parent, direction, enabled, onClick)
  local button = CreateFrame("Button", nil, parent)
  button:SetSize(24, 24)
  button:SetScript("OnClick", onClick)

  local prefix = direction == "up" and "UI-ScrollBar-ScrollUpButton" or "UI-ScrollBar-ScrollDownButton"
  button:SetNormalTexture("Interface\\Buttons\\" .. prefix .. "-Up")
  button:SetPushedTexture("Interface\\Buttons\\" .. prefix .. "-Down")
  button:SetDisabledTexture("Interface\\Buttons\\" .. prefix .. "-Disabled")
  button:SetHighlightTexture("Interface\\Buttons\\" .. prefix .. "-Highlight")

  if not enabled then
    button:Disable()
  end

  return button
end

local function makeEmptyMarker(parent)
  local marker = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
  marker:SetPoint("CENTER", parent, "CENTER", 0, 0)
  marker:SetText("X")
  marker:SetTextColor(0.75, 0.82, 0.95, 0.95)
  marker:Hide()
  return marker
end

local function getMuscleSlot(muscle, slot)
  return muscle and muscle.slots and muscle.slots[slot] or nil
end

local function refresh()
  MM.UI:ShowMuscles()
end

local function deleteMuscle(muscleId)
  local ok, reason = MM.DB:DeleteMuscle(muscleId)
  if not ok then
    MM:Warn(reason or "could not delete muscle")
  end
  refresh()
end

local function confirmDeleteMuscle(muscleId, muscleName)
  if StaticPopupDialogs and StaticPopup_Show then
    StaticPopupDialogs[DELETE_MUSCLE_DIALOG] = StaticPopupDialogs[DELETE_MUSCLE_DIALOG]
      or {
        text = "Delete muscle %s?",
        button1 = "Delete",
        button2 = "Cancel",
        OnAccept = function(_, data)
          deleteMuscle(data.muscleId)
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
      }
    StaticPopup_Show(DELETE_MUSCLE_DIALOG, muscleName, nil, { muscleId = muscleId })
    return
  end

  deleteMuscle(muscleId)
end

local function assignSlot(muscleId, slot, assignment)
  MM.DB:SetSlot(muscleId, slot, assignment)
  MM.DB:SetSelectedSlot(slot)
  refresh()
end

local function enableSlotFromBar(muscleId, slot)
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

local function assignCursor(muscleId, slot)
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

function SlotGrid:BuildMusclesPane(parent, muscleId)
  local title = makeSectionLabel(parent, "Muscles")
  title:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)

  local create = makeButton(parent, "New", 58, function()
    local nextNumber = MM.Tables.Count(MM.DB:GetRoot().muscles or {}) + 1
    local id = MM.DB:CreateMuscle("Muscle " .. tostring(nextNumber))
    MM.DB:SetSelectedMuscleId(id)
    MM.DB:SetSelectedSlot(nil)
    refresh()
  end)
  create:SetPoint("TOPRIGHT", parent, "TOPLEFT", LEFT_WIDTH, 2)

  local muscles = sortedMuscles()
  local y = -30
  for index, muscle in ipairs(muscles) do
    local button = makeListRow(
      parent,
      tostring(index) .. ". " .. muscle.name,
      LEFT_WIDTH,
      muscle.id == muscleId,
      function()
        MM.DB:SetSelectedMuscleId(muscle.id)
        MM.DB:SetSelectedSlot(nil)
        refresh()
      end,
      58,
      26
    )
    button:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)

    local check = makeCheckbox(button, muscle.enabled, function()
      MM.DB:SetMuscleEnabled(muscle.id, not muscle.enabled)
      refresh()
    end)
    check:SetPoint("LEFT", button, "LEFT", 2, 0)
    if not muscle.enabled then
      button.label:SetTextColor(0.5, 0.5, 0.5)
    end

    local up = makeArrowButton(button, "up", index > 1, function()
      MM.DB:MoveMuscle(muscle.id, index - 1)
      refresh()
    end)
    up:SetPoint("RIGHT", button, "RIGHT", -25, 0)

    local down = makeArrowButton(button, "down", index < #muscles, function()
      MM.DB:MoveMuscle(muscle.id, index + 1)
      refresh()
    end)
    down:SetPoint("RIGHT", button, "RIGHT", -1, 0)

    y = y - 28
  end
end

function SlotGrid:BuildToolbar(parent, muscleId)
  local preview = makeButton(parent, "Preview", 78, function()
    MM.Applier:PreviewProfile()
  end)
  preview:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)

  local apply = makeButton(parent, "Apply", 70, function()
    MM.Applier:ApplyProfile()
  end)
  apply:SetPoint("RIGHT", preview, "LEFT", -8, 0)

  local enableAll = makeButton(parent, "Enable All", 90, function()
    MM.DB:SetAllMuscleSlots(muscleId, true)
    refresh()
  end)
  enableAll:SetPoint("RIGHT", apply, "LEFT", -8, 0)

  local disableAll = makeButton(parent, "Disable All", 90, function()
    MM.DB:SetAllMuscleSlots(muscleId, false)
    MM.DB:SetSelectedSlot(nil)
    refresh()
  end)
  disableAll:SetPoint("RIGHT", enableAll, "LEFT", -8, 0)
end

function SlotGrid:BuildSlotButton(parent, muscleId, muscle, slot, point, relativeTo, x, y)
  local assignment = getMuscleSlot(muscle, slot)
  local configured = assignment ~= nil
  local selected = MM.DB:GetSelectedSlot() == slot

  local button = CreateFrame("Button", nil, parent)
  button:SetSize(ICON_SIZE, ICON_SIZE)
  button:SetPoint(point, relativeTo, x, y)
  button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  button:RegisterForDrag("LeftButton")

  button.bg = button:CreateTexture(nil, "BACKGROUND")
  button.bg:SetAllPoints()
  button.bg:SetColorTexture(0.04, 0.04, 0.04, configured and 0.95 or 0.25)

  button.icon = button:CreateTexture(nil, "ARTWORK")
  button.icon:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -2)
  button.icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 2)

  button.emptyMarker = makeEmptyMarker(button)

  local iconState = configured and MM.Actions.GetAssignmentIconState(assignment, slot)
    or {
      kind = "icon",
      texture = MM.Actions.GetLiveSlotIcon(slot),
    }
  if iconState.kind == "empty" then
    button.icon:SetColorTexture(0, 0, 0, 0)
    button.emptyMarker:Show()
  elseif iconState.kind == "ignore" then
    button.icon:SetColorTexture(0, 0, 0, 0)
  elseif iconState.kind == "preserve" then
    button.icon:SetTexture(QUESTION_ICON)
  elseif iconState.texture then
    button.icon:SetTexture(iconState.texture)
  else
    button.icon:SetColorTexture(0, 0, 0, 0)
  end
  button.icon:SetAlpha(configured and 1 or 0.45)

  button.border = makeSlotBorder(button)
  if selected then
    setSlotBorder(button.border, 3, 0.45, 0.68, 1, 0.95)
  elseif configured then
    setSlotBorder(button.border, 2, 0.32, 0.58, 1, 0.78)
  else
    setSlotBorder(button.border, 1, 0.85, 0.9, 1, 0.16)
  end

  button:SetAlpha(configured and 1 or 0.68)
  button.tooltipText = MM.Actions.GetAssignmentLabel(assignment)
  button:SetScript("OnEnter", function(frame)
    GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
    GameTooltip:SetText(MM.Actions.GetSlotLabel(slot))
    if configured then
      GameTooltip:AddLine(frame.tooltipText, 1, 1, 1)
    else
      GameTooltip:AddLine("Disabled in this muscle", 0.75, 0.75, 0.75)
    end
    GameTooltip:Show()
  end)
  button:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)
  button:SetScript("OnClick", function(_, mouseButton)
    if GetCursorInfo and GetCursorInfo() then
      assignCursor(muscleId, slot)
      return
    end

    if mouseButton == "RightButton" then
      assignSlot(muscleId, slot, nil)
      return
    end

    if not configured then
      enableSlotFromBar(muscleId, slot)
    else
      MM.DB:SetSelectedSlot(slot)
      refresh()
    end
  end)
  button:SetScript("OnReceiveDrag", function()
    assignCursor(muscleId, slot)
  end)
end

function SlotGrid:BuildGrid(parent, muscleId, muscle)
  local title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
  title:SetText("Muscle")

  local nameBox = makeEditBox(parent, 170)
  nameBox:SetPoint("LEFT", title, "RIGHT", 12, 0)
  nameBox:SetText(muscle and muscle.name or muscleId)
  nameBox:SetCursorPosition(0)

  local delete = makeButton(parent, "Delete", 66, function()
    confirmDeleteMuscle(muscleId, muscle and muscle.name or muscleId)
  end)
  delete:SetPoint("LEFT", nameBox, "RIGHT", 10, 0)
  if MM.Tables.Count(MM.DB:GetRoot().muscles or {}) <= 1 then
    delete:Disable()
  end

  local originalName = muscle and muscle.name or muscleId
  local function saveName()
    local value = nameBox:GetText()
    if value == originalName then
      return
    end

    local ok, reason = MM.DB:RenameMuscle(muscleId, value)
    if ok then
      refresh()
    else
      nameBox:SetText(originalName)
      MM:Warn(reason or "could not rename muscle")
    end
  end

  nameBox:SetScript("OnEnterPressed", function(frame)
    frame:ClearFocus()
  end)
  nameBox:SetScript("OnEscapePressed", function(frame)
    frame:SetText(originalName)
    frame:ClearFocus()
  end)
  nameBox:SetScript("OnEditFocusLost", saveName)

  self:BuildToolbar(parent, muscleId)

  local grid = CreateFrame("Frame", nil, parent)
  grid:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -42)
  grid:SetSize(520, 420)

  for column = 1, MM.ACTIONS_PER_BAR do
    local header = grid:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    header:SetPoint("TOPLEFT", grid, "TOPLEFT", 54 + ((column - 1) * (ICON_SIZE + CELL_GAP)), 0)
    header:SetText(tostring(column))
  end

  for bar = 1, math.floor(MM.MAX_ACTION_SLOT / MM.ACTIONS_PER_BAR) do
    local rowLabel = grid:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    rowLabel:SetPoint("TOPLEFT", grid, "TOPLEFT", 0, -24 - ((bar - 1) * (ICON_SIZE + CELL_GAP)))
    rowLabel:SetText("Bar " .. tostring(bar))

    for buttonIndex = 1, MM.ACTIONS_PER_BAR do
      local slot = ((bar - 1) * MM.ACTIONS_PER_BAR) + buttonIndex
      self:BuildSlotButton(
        grid,
        muscleId,
        muscle,
        slot,
        "TOPLEFT",
        grid,
        54 + ((buttonIndex - 1) * (ICON_SIZE + CELL_GAP)),
        -18 - ((bar - 1) * (ICON_SIZE + CELL_GAP))
      )
    end
  end
end

function SlotGrid:BuildSlotPane(parent, muscleId, muscle)
  local selectedSlot = MM.DB:GetSelectedSlot()
  local title = makeSectionLabel(parent, "Selected Slot")
  title:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)

  if not selectedSlot then
    local note = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    note:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)
    note:SetWidth(RIGHT_WIDTH)
    note:SetJustifyH("LEFT")
    note:SetText("Click a faded slot to enable and capture it, or click an enabled slot to edit it.")
    return
  end

  local assignment = getMuscleSlot(muscle, selectedSlot)
  local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  label:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
  label:SetWidth(RIGHT_WIDTH)
  label:SetJustifyH("LEFT")
  label:SetText(MM.Actions.GetSlotLabel(selectedSlot) .. ": " .. MM.Actions.GetAssignmentLabel(assignment))

  local capture = makeButton(parent, "Capture Current", 118, function()
    local ok, reason = MM.Capture:CaptureSlot(muscleId, selectedSlot)
    if not ok then
      MM:Warn(reason or "could not capture slot")
    end
    refresh()
  end)
  capture:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -12)

  local empty = makeButton(parent, "Empty", 62, function()
    assignSlot(muscleId, selectedSlot, { type = "empty" })
  end)
  empty:SetPoint("LEFT", capture, "RIGHT", 8, 0)

  local disable = makeButton(parent, "Disable", 70, function()
    assignSlot(muscleId, selectedSlot, nil)
  end)
  disable:SetPoint("LEFT", empty, "RIGHT", 8, 0)

  local spellLabel = makeSectionLabel(parent, "Spell ID")
  spellLabel:SetPoint("TOPLEFT", capture, "BOTTOMLEFT", 0, -22)

  local spellInput = makeEditBox(parent, 96)
  spellInput:SetPoint("LEFT", spellLabel, "RIGHT", 12, 0)
  if spellInput.SetNumeric then
    spellInput:SetNumeric(true)
  end
  if assignment and assignment.type == "spell" then
    spellInput:SetText(tostring(assignment.id))
  end

  local function setSpell()
    local spellId = tonumber(spellInput:GetText())
    if spellId then
      assignSlot(muscleId, selectedSlot, { type = "spell", id = spellId })
    else
      MM:Warn("enter a spell ID first.")
    end
  end
  spellInput:SetScript("OnEnterPressed", setSpell)
  spellInput:SetScript("OnEscapePressed", spellInput.ClearFocus)

  local setSpellButton = makeButton(parent, "Set", 44, setSpell)
  setSpellButton:SetPoint("LEFT", spellInput, "RIGHT", 8, 0)

  local memoriesLabel = makeSectionLabel(parent, "Memories")
  memoriesLabel:SetPoint("TOPLEFT", spellLabel, "BOTTOMLEFT", 0, -22)

  local y = -26
  for _, memory in ipairs(sortedMemories()) do
    local button = makeButton(parent, memory.name, RIGHT_WIDTH, function()
      assignSlot(muscleId, selectedSlot, {
        type = "memory",
        source = memory.source,
        id = memory.id,
      })
    end)
    button:SetPoint("TOPLEFT", memoriesLabel, "BOTTOMLEFT", 0, y)
    y = y - 24
  end
end

function SlotGrid:Build(parent)
  local muscleId = MM.DB:GetSelectedMuscleId()
  local muscle = MM.DB:GetMuscle(muscleId)

  local left = CreateFrame("Frame", nil, parent)
  left:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
  left:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, 0)
  left:SetWidth(LEFT_WIDTH)
  self:BuildMusclesPane(left, muscleId)

  makeVerticalDivider(parent, left, "RIGHT", 9)

  local center = CreateFrame("Frame", nil, parent)
  center:SetPoint("TOPLEFT", left, "TOPRIGHT", 18, 0)
  center:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -(RIGHT_WIDTH + 18), 0)
  self:BuildGrid(center, muscleId, muscle)

  local right = CreateFrame("Frame", nil, parent)
  right:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
  right:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
  right:SetWidth(RIGHT_WIDTH)
  makeVerticalDivider(parent, right, "LEFT", -9)
  self:BuildSlotPane(right, muscleId, muscle)
end
