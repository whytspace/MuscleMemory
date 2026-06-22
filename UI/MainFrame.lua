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
  frame:SetSize(1040, 620)
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
  self:ShowLayouts()
end

function UI:ClearContent()
  if self.content then
    self.content:Hide()
    self.content:SetParent(nil)
  end

  self.content = CreateFrame("Frame", nil, self.frame)
  self.content:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 16, -56)
  self.content:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT", -16, 16)
end

function UI:ShowLayouts()
  self:ClearContent()
  MM.ui.SlotGrid:Build(self.content)
end

-- Re-render the layouts view if the window is currently open.
function UI:Refresh()
  if self.frame and self.frame:IsShown() then
    self:ShowLayouts()
  end
end

function UI:Open()
  self:CreateFrame()
  self.frame:Show()
end
