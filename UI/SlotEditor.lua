local ADDON_NAME, MM = ...

local SlotEditor = {}
MM.ui.SlotEditor = SlotEditor

local function getSortedStandardGroups()
  local groups = {}
  for groupId, group in pairs(MM.StandardGroups or {}) do
    groups[#groups + 1] = {
      id = groupId,
      name = group.name or groupId,
    }
  end

  table.sort(groups, function(left, right)
    return left.name < right.name
  end)

  return groups
end

local function clearChildren(frame)
  local children = { frame:GetChildren() }
  for _, child in ipairs(children) do
    child:Hide()
    child:SetParent(nil)
  end
end

local function makeButton(parent, label, width, onClick)
  local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  button:SetSize(width or 120, 24)
  button:SetText(label)
  button:SetScript("OnClick", onClick)
  return button
end

function SlotEditor:SetAssignment(layoutId, slot, assignment)
  local layout = MM.DB:GetLayout(layoutId)
  slot = tonumber(slot)
  if not layout or not MM.Actions.IsValidSlot(slot) then
    return
  end

  if assignment then
    layout.slots[slot] = assignment
  else
    layout.slots[slot] = nil
  end

  layout.revision = (layout.revision or 1) + 1
end

function SlotEditor:CreateFrame()
  if self.frame then
    return
  end

  local frame = CreateFrame("Frame", "MuscleMemorySlotEditorFrame", MM.UI.frame, "BasicFrameTemplateWithInset")
  frame:SetSize(430, 360)
  frame:SetPoint("CENTER", MM.UI.frame, "CENTER", 0, 0)
  frame:SetFrameStrata("DIALOG")
  frame:Hide()
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

  frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  frame.title:SetPoint("LEFT", frame.TitleBg, "LEFT", 6, 0)
  frame.title:SetText("Edit Slot")

  if frame.CloseButton then
    frame.CloseButton:SetScript("OnClick", function()
      frame:Hide()
    end)
  end

  frame.body = CreateFrame("Frame", nil, frame)
  frame.body:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -34)
  frame.body:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, 16)

  self.frame = frame
end

function SlotEditor:Refresh(layoutId, slot)
  self:CreateFrame()

  local frame = self.frame
  local body = frame.body
  local layout = MM.DB:GetLayout(layoutId)
  local assignment = layout and layout.slots[slot]
  clearChildren(body)

  frame.title:SetText("Edit " .. MM.Actions.GetSlotLabel(slot))

  local current = body:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  current:SetPoint("TOPLEFT")
  current:SetText(MM.Actions.GetAssignmentLabel(assignment))

  local hint = body:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  hint:SetPoint("TOPLEFT", current, "BOTTOMLEFT", 0, -6)
  hint:SetText("Choose what Muscle Memory should place in this action bar slot.")

  local ignore = makeButton(body, "Ignore", 105, function()
    self:SetAssignment(layoutId, slot, nil)
    MM.UI:ShowLayouts()
    self:Refresh(layoutId, slot)
  end)
  ignore:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -14)

  local empty = makeButton(body, "Empty", 105, function()
    self:SetAssignment(layoutId, slot, { type = "empty" })
    MM.UI:ShowLayouts()
    self:Refresh(layoutId, slot)
  end)
  empty:SetPoint("LEFT", ignore, "RIGHT", 8, 0)

  local capture = makeButton(body, "Capture Current Slot", 150, function()
    local ok, reason = MM.ui.CaptureMode:CaptureSlot(layoutId, slot)
    if ok then
      MM:Print("captured " .. MM.Actions.GetSlotLabel(slot) .. ".")
      MM.UI:ShowLayouts()
      self:Refresh(layoutId, slot)
    else
      MM:Warn(reason or "could not capture slot")
    end
  end)
  capture:SetPoint("LEFT", empty, "RIGHT", 8, 0)

  local groupTitle = body:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  groupTitle:SetPoint("TOPLEFT", ignore, "BOTTOMLEFT", 0, -16)
  groupTitle:SetText("Standard Action Groups")

  local groups = getSortedStandardGroups()
  for index, group in ipairs(groups) do
    local button = makeButton(body, group.name, 190, function()
      self:SetAssignment(layoutId, slot, {
        type = "group",
        source = "standard",
        id = group.id,
        unresolvedFallback = "inherit",
      })
      MM.UI:ShowLayouts()
      self:Refresh(layoutId, slot)
    end)

    local column = (index - 1) % 2
    local row = math.floor((index - 1) / 2)
    button:SetPoint("TOPLEFT", groupTitle, "BOTTOMLEFT", column * 198, -8 - (row * 28))
  end

  local spellLabel = body:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  spellLabel:SetPoint("TOPLEFT", groupTitle, "BOTTOMLEFT", 0, -120)
  spellLabel:SetText("Spell ID")

  local spellInput = CreateFrame("EditBox", nil, body, "InputBoxTemplate")
  spellInput:SetSize(110, 24)
  spellInput:SetPoint("LEFT", spellLabel, "RIGHT", 12, 0)
  spellInput:SetAutoFocus(false)
  if spellInput.SetNumeric then
    spellInput:SetNumeric(true)
  end
  if assignment and assignment.type == "spell" and assignment.id then
    spellInput:SetText(tostring(assignment.id))
  end

  local setSpell
  setSpell = function()
    local spellId = tonumber(spellInput:GetText())
    if not spellId then
      MM:Warn("enter a spell ID first.")
      return
    end

    self:SetAssignment(layoutId, slot, {
      type = "spell",
      id = spellId,
      unresolvedFallback = "inherit",
    })
    spellInput:ClearFocus()
    MM.UI:ShowLayouts()
    self:Refresh(layoutId, slot)
  end

  spellInput:SetScript("OnEnterPressed", setSpell)
  spellInput:SetScript("OnEscapePressed", function(input)
    input:ClearFocus()
  end)

  local spellButton = makeButton(body, "Set Spell", 100, setSpell)
  spellButton:SetPoint("LEFT", spellInput, "RIGHT", 12, 0)

  local close = makeButton(body, "Close", 90, function()
    frame:Hide()
  end)
  close:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", 0, 0)
end

function SlotEditor:Open(layoutId, slot)
  self:Refresh(layoutId, slot)
  self.frame:Show()
end
