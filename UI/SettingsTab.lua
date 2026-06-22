local ADDON_NAME, MM = ...

-- The Settings tab: the single global fallback that decides what happens to a
-- managed slot whose memory can't resolve for the current character. The design
-- shows an Ignore/Clear segmented control; natively that's a pair of radios.
-- "Ignore" maps to the stored fallback value "keep".
local SettingsTab = {}
MM.ui.SettingsTab = SettingsTab

local Widgets = MM.ui.Widgets
local colors = Widgets.colors

local OPTIONS = {
  { value = "keep", label = "Ignore", hint = "Leave whatever action is already there." },
  { value = "clear", label = "Clear", hint = "Remove the existing action, if any." },
}

function SettingsTab:Build(parent)
  local column = CreateFrame("Frame", nil, parent)
  column:SetPoint("TOPLEFT", parent, "TOPLEFT", 40, -28)
  column:SetWidth(540)
  column:SetPoint("BOTTOM", parent, "BOTTOM", 0, 0)

  local heading = Widgets.Label(column, "GameFontNormalLarge", "Global Settings", colors.gold)
  heading:SetPoint("TOPLEFT", column, "TOPLEFT", 0, 0)

  local subHeading = Widgets.Label(column, "GameFontNormal", "When a slot can't resolve", colors.parchment)
  subHeading:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 0, -22)

  local blurb = Widgets.Label(
    column,
    "GameFontHighlightSmall",
    "If a Memory has no usable ability for the current character, decide what happens to that action-bar slot when a Muscle is applied."
  )
  blurb:SetPoint("TOPLEFT", subHeading, "BOTTOMLEFT", 0, -6)
  blurb:SetWidth(480)
  blurb:SetJustifyH("LEFT")
  blurb:SetTextColor(Widgets.unpackColor(colors.muted))

  self.radios = {}

  local anchor = blurb
  for _, option in ipairs(OPTIONS) do
    local radio = CreateFrame("CheckButton", nil, column, "UIRadioButtonTemplate")
    radio:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -14)
    self.radios[option.value] = radio

    local label = Widgets.Label(column, "GameFontHighlight", option.label, colors.parchment)
    label:SetPoint("LEFT", radio, "RIGHT", 6, 0)

    local hint = Widgets.Label(column, "GameFontDisableSmall", "\226\128\148 " .. option.hint)
    hint:SetPoint("LEFT", label, "RIGHT", 6, 0)

    radio:SetScript("OnClick", function()
      MM.DB:SetFallback(option.value)
      self:Refresh()
    end)

    anchor = radio
  end

  self:Refresh()
end

-- Built once; Refresh just re-syncs the radios to the stored fallback.
function SettingsTab:Refresh()
  local current = MM.DB:GetFallback()
  for value, radio in pairs(self.radios or {}) do
    radio:SetChecked(value == current)
  end
end
