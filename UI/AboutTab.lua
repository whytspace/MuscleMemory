local ADDON_NAME, MM = ...
local L = MM.L

-- The About tab: logo, name, tagline, version/author pulled from the .toc, the
-- two-paragraph pitch, and a copyable link to the project page.
local AboutTab = {}
MM.ui.AboutTab = AboutTab

local Widgets = MM.ui.Widgets
local colors = Widgets.colors

-- Read straight from our own .toc; the fields are guaranteed present, so a
-- missing one should fail loudly rather than show a fake value.
local function metadata(key)
  return C_AddOns.GetAddOnMetadata(ADDON_NAME, key)
end

local GITHUB_URL = metadata("X-Website")

function AboutTab:Build(parent)
  local column = CreateFrame("Frame", nil, parent)
  column:SetPoint("TOP", parent, "TOP", 0, -36)
  column:SetWidth(520)
  column:SetPoint("BOTTOM", parent, "BOTTOM", 0, 10)

  local logo = column:CreateTexture(nil, "ARTWORK")
  logo:SetSize(96, 96)
  logo:SetPoint("TOP", column, "TOP", 0, 0)
  logo:SetTexture(MM.ui.LOGO_TEXTURE)

  local title = Widgets.Label(column, "GameFontNormalHuge", "Muscle Memory", colors.gold)
  title:SetPoint("TOP", logo, "BOTTOM", 0, -16)

  local tagline =
    Widgets.Label(column, "GameFontHighlight", L["Bind buttons by purpose, not just spell."], colors.goldDim)
  tagline:SetPoint("TOP", title, "BOTTOM", 0, -8)

  local meta = Widgets.Label(
    column,
    "GameFontDisableSmall",
    string.format(L["v%s  \194\183  by %s"], metadata("Version"), metadata("Author"))
  )
  meta:SetPoint("TOP", tagline, "BOTTOM", 0, -10)

  local para1 = Widgets.Label(
    column,
    "GameFontHighlightSmall",
    L["Muscle Memory keeps your action bars consistent across characters. Capture how your bars are set up into reusable Layers, and restore them on any character \226\128\148 putting the right spell, item, macro, mount, or equipment set back into each slot."]
  )
  para1:SetPoint("TOP", meta, "BOTTOM", 0, -22)
  para1:SetWidth(460)
  para1:SetJustifyH("CENTER")
  para1:SetTextColor(Widgets.unpackColor(colors.parchment))

  local para2 = Widgets.Label(
    column,
    "GameFontHighlightSmall",
    L["Slots can also point to purpose-based Smart Actions such as Interrupt, Taunt, or Bloodlust. Each character gets whatever ability it actually has for that purpose, so one Layer works across many classes."]
  )
  para2:SetPoint("TOP", para1, "BOTTOM", 0, -12)
  para2:SetWidth(460)
  para2:SetJustifyH("CENTER")
  para2:SetTextColor(Widgets.unpackColor(colors.parchment))

  local linkLabel = Widgets.Label(column, "GameFontDisableSmall", L["Project page (copy the link):"])
  linkLabel:SetPoint("TOP", para2, "BOTTOM", 0, -26)

  local link = CreateFrame("EditBox", nil, column, "InputBoxTemplate")
  link:SetSize(320, 22)
  link:SetPoint("TOP", linkLabel, "BOTTOM", 0, -8)
  link:SetAutoFocus(false)
  link:SetText(GITHUB_URL)
  link:SetCursorPosition(0)
  link:SetScript("OnEscapePressed", link.ClearFocus)
  link:SetScript("OnEnterPressed", link.ClearFocus)
  -- Keep it effectively read-only: re-assert the URL if edited.
  link:SetScript("OnTextChanged", function(editBox, userInput)
    if userInput and editBox:GetText() ~= GITHUB_URL then
      editBox:SetText(GITHUB_URL)
      editBox:HighlightText()
    end
  end)
  link:SetScript("OnEditFocusGained", function(editBox)
    editBox:HighlightText()
  end)

  -- Debug report: one click packs the live bars, the client's answers for
  -- everything the profile references, and the profile itself into a copyable
  -- string, so a bug report carries the state needed to reproduce it.
  local reportHint = Widgets.Hint(
    column,
    L["Found a bug? Generate a debug report and attach it. It includes your action bars, macros, known spells and items, and the active profile."]
  )
  reportHint:SetPoint("TOP", link, "BOTTOM", 0, -24)
  reportHint:SetWidth(460)
  reportHint:SetJustifyH("CENTER")

  local reportButton = Widgets.Button(column, L["Generate debug report"], 180, function()
    local text, reason = MM.Diagnostics:Report()
    self.reportText = text or ""
    local edit = self.reportOutput.EditBox
    edit:SetText(text or L[tostring(reason)])
    self.reportOutput:Show()
    self.reportOutputHint:SetShown(text ~= nil)
    if text then
      edit:SetFocus()
      edit:HighlightText()
    end
  end)
  reportButton:SetPoint("TOP", reportHint, "BOTTOM", 0, -10)

  self.reportOutput = Widgets.MultiLineInput(column, "", 0, nil)
  self.reportOutput:SetPoint("TOP", reportButton, "BOTTOM", 0, -10)
  self.reportOutput:SetPoint("LEFT", column, "LEFT", 30, 0)
  self.reportOutput:SetPoint("RIGHT", column, "RIGHT", -30, 0)
  self.reportOutput:SetHeight(56)
  self.reportOutput:Hide()

  self.reportOutputHint = Widgets.Hint(column, L["Click the string, then press Ctrl+C."])
  self.reportOutputHint:SetPoint("TOP", self.reportOutput, "BOTTOM", 0, -6)
  self.reportOutputHint:Hide()

  -- Output, not input: edits snap back and focusing selects everything so
  -- Ctrl+C is the only step left (same pattern as the Export tab).
  local edit = self.reportOutput.EditBox
  edit:HookScript("OnTextChanged", function(editBox, userInput)
    if userInput then
      editBox:SetText(AboutTab.reportText or "")
      editBox:HighlightText()
    end
  end)
  edit:HookScript("OnEditFocusGained", function(editBox)
    editBox:HighlightText()
  end)
end

-- Static content — built once, nothing to update on refresh.
function AboutTab:Refresh() end
