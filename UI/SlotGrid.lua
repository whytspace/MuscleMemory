local ADDON_NAME, MM = ...

local SlotGrid = {}
MM.ui.SlotGrid = SlotGrid

local function getAssignmentLabel(assignment)
  if not assignment then
    return "Ignore"
  end

  if assignment.type == "group" then
    local group = MM.DB:GetGroup({ source = assignment.source, id = assignment.id })
    return group and group.name or ("Group: " .. tostring(assignment.id))
  end

  return assignment.type or "Ignore"
end

function SlotGrid:Build(parent)
  local root = MM.DB:GetRoot()
  local layoutId = root.ui.selectedLayout or "Core"
  local layout = MM.DB:GetLayout(layoutId)

  local title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT")
  title:SetText("Layout: " .. (layout and layout.name or layoutId))

  local apply = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  apply:SetSize(90, 24)
  apply:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
  apply:SetText("Apply")
  apply:SetScript("OnClick", function()
    MM.Applier:ApplyProfile()
  end)

  local preview = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  preview:SetSize(90, 24)
  preview:SetPoint("RIGHT", apply, "LEFT", -8, 0)
  preview:SetText("Preview")
  preview:SetScript("OnClick", function()
    MM.Applier:PreviewProfile()
  end)

  local help = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  help:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
  help:SetText("Click a slot to cycle: Ignore -> Empty -> Kick / Interrupt -> Taunt.")

  local startY = -52
  for bar = 1, math.floor(MM.MAX_ACTION_SLOT / MM.ACTIONS_PER_BAR) do
    local barLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    barLabel:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, startY - ((bar - 1) * 34) - 6)
    barLabel:SetText("Bar " .. bar)

    for buttonIndex = 1, MM.ACTIONS_PER_BAR do
      local slot = ((bar - 1) * MM.ACTIONS_PER_BAR) + buttonIndex
      local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
      button:SetSize(48, 28)
      button:SetPoint("TOPLEFT", parent, "TOPLEFT", 54 + ((buttonIndex - 1) * 52), startY - ((bar - 1) * 34))

      local assignment = layout and layout.slots[slot]
      button:SetText(buttonIndex)
      button.tooltipText = getAssignmentLabel(assignment)
      button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(MM.Actions.GetSlotLabel(slot))
        GameTooltip:AddLine(self.tooltipText, 1, 1, 1)
        GameTooltip:Show()
      end)
      button:SetScript("OnLeave", function()
        GameTooltip:Hide()
      end)
      button:SetScript("OnClick", function()
        MM.ui.SlotEditor:CycleSlot(layoutId, slot)
        MM.UI:ShowLayouts()
      end)
    end
  end
end
