local ADDON_NAME, MM = ...

local UI = {}
MM.UI = UI
MM:RegisterModule("UI", UI)

function UI:OnInitialize()
  self:CreateFrame()
end

function UI:CreateFrame()
  if self.frame then
    return
  end

  local frame = CreateFrame("Frame", "MuscleMemoryFrame", UIParent, "BasicFrameTemplateWithInset")
  frame:SetSize(760, 520)
  frame:SetPoint("CENTER")
  frame:Hide()
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

  frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  frame.title:SetPoint("LEFT", frame.TitleBg, "LEFT", 6, 0)
  frame.title:SetText("Muscle Memory")

  frame.subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  frame.subtitle:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -34)
  frame.subtitle:SetText("Bind buttons by purpose, not just spells.")

  self.frame = frame
  self:CreateTabs()
  self:ShowLayouts()
end

function UI:CreateTabs()
  local frame = self.frame
  local tabs = {
    {
      id = "layouts",
      label = "Layouts",
      handler = function()
        self:ShowLayouts()
      end,
    },
    {
      id = "groups",
      label = "Action Groups",
      handler = function()
        self:ShowGroups()
      end,
    },
  }

  self.tabs = {}
  for index, tab in ipairs(tabs) do
    local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    button:SetSize(120, 24)
    button:SetPoint("TOPLEFT", frame, "TOPLEFT", 16 + ((index - 1) * 126), -56)
    button:SetText(tab.label)
    button:SetScript("OnClick", tab.handler)
    self.tabs[tab.id] = button
  end
end

function UI:ClearContent()
  if self.content then
    self.content:Hide()
    self.content:SetParent(nil)
  end

  self.content = CreateFrame("Frame", nil, self.frame)
  self.content:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 16, -88)
  self.content:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT", -16, 16)
end

function UI:ShowLayouts()
  self:ClearContent()
  MM.ui.SlotGrid:Build(self.content)
end

function UI:ShowGroups()
  self:ClearContent()
  MM.ui.GroupList:Build(self.content)
end

function UI:Open()
  self:CreateFrame()
  self.frame:Show()
end

function UI:Toggle()
  self:CreateFrame()
  if self.frame:IsShown() then
    self.frame:Hide()
  else
    self.frame:Show()
  end
end
