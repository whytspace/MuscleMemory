local ADDON_NAME, MM = ...

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

  local tagline = Widgets.Label(column, "GameFontHighlight", "Bind buttons by purpose, not just spell.", colors.goldDim)
  tagline:SetPoint("TOP", title, "BOTTOM", 0, -8)

  local meta =
    Widgets.Label(column, "GameFontDisableSmall", "v" .. metadata("Version") .. "  \194\183  by " .. metadata("Author"))
  meta:SetPoint("TOP", tagline, "BOTTOM", 0, -10)

  local para1 = Widgets.Label(
    column,
    "GameFontHighlightSmall",
    "Muscle Memory keeps your action bars consistent across characters. Capture how your bars are set up into reusable Muscles, and restore them on any character \226\128\148 putting the right spell, item, macro, mount, or equipment set back into each slot."
  )
  para1:SetPoint("TOP", meta, "BOTTOM", 0, -22)
  para1:SetWidth(460)
  para1:SetJustifyH("CENTER")
  para1:SetSpacing(3)
  para1:SetTextColor(Widgets.unpackColor(colors.parchment))

  local para2 = Widgets.Label(
    column,
    "GameFontHighlightSmall",
    "Slots can also point to purpose-based Memories such as Interrupt, Taunt, or Lust. Each character gets whatever ability it actually has for that purpose, so one Muscle works across many classes."
  )
  para2:SetPoint("TOP", para1, "BOTTOM", 0, -12)
  para2:SetWidth(460)
  para2:SetJustifyH("CENTER")
  para2:SetSpacing(3)
  para2:SetTextColor(Widgets.unpackColor(colors.parchment))

  local linkLabel = Widgets.Label(column, "GameFontDisableSmall", "Project page (copy the link):")
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
end

-- Static content — built once, nothing to update on refresh.
function AboutTab:Refresh() end
