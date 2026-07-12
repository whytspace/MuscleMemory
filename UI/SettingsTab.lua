local ADDON_NAME, MM = ...

-- The Settings tab: the active profile's fallback, which decides what happens to
-- a managed slot whose dynamicAction can't resolve for the current character. The design
-- shows an Ignore/Clear segmented control; natively that's a pair of radios.
-- "Ignore" maps to the stored fallback value "keep".
local SettingsTab = {}
MM.ui.SettingsTab = SettingsTab

local Widgets = MM.ui.Widgets
local colors = Widgets.colors

local FALLBACK_OPTIONS = {
  { value = "keep", label = "Ignore", hint = "Leave whatever action is already there." },
  { value = "clear", label = "Clear", hint = "Remove the existing action, if any." },
}

-- How binding an action covered by a Dynamic Action behaves.
local SUGGEST_OPTIONS = {
  { value = "never", label = "Never", hint = "Always bind exactly what you chose." },
  { value = "suggest", label = "Suggest", hint = "Ask via a popup." },
  { value = "auto", label = "Automatic", hint = "Bind the Dynamic Action; asks only when several match." },
}

-- How the add-on reacts when an event re-scan finds changes to apply.
local RESPONSE_OPTIONS = {
  { value = "ignore", label = "Do nothing", hint = "Detect changes silently." },
  { value = "print", label = "Print a message", hint = "List what would change in chat." },
  { value = "popup", label = "Show a popup", hint = "Ask to preview or apply." },
  { value = "apply", label = "Apply automatically", hint = "Apply and print a summary." },
}

-- Build a vertical radio group below `anchor`; returns the radios keyed by value
-- and the last row so the next section can anchor under it. Each option is a
-- full-width clickable row so the label and hint trigger the choice, not just
-- the radio dot; the radio itself is display-only.
local function buildRadioGroup(column, anchor, options, onSelect)
  local radios = {}
  for _, option in ipairs(options) do
    local row = CreateFrame("Button", nil, column)
    row:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -14)
    row:SetPoint("RIGHT", column, "RIGHT", 0, 0)
    row:SetHeight(20)

    local radio = CreateFrame("CheckButton", nil, row, "UIRadioButtonTemplate")
    radio:SetPoint("LEFT", row, "LEFT", 0, 0)
    radio:EnableMouse(false)
    radios[option.value] = radio

    local label = Widgets.Label(row, "GameFontHighlight", option.label, colors.parchment)
    label:SetPoint("LEFT", radio, "RIGHT", 6, 0)

    local hint = Widgets.Label(row, "GameFontDisableSmall", "\226\128\148 " .. option.hint)
    hint:SetPoint("LEFT", label, "RIGHT", 6, 0)

    row:SetScript("OnClick", function()
      onSelect(option.value)
    end)

    anchor = row
  end
  return radios, anchor
end

function SettingsTab:Build(parent)
  local column = CreateFrame("Frame", nil, parent)
  column:SetPoint("TOPLEFT", parent, "TOPLEFT", 40, -28)
  column:SetWidth(540)
  column:SetPoint("BOTTOM", parent, "BOTTOM", 0, 0)

  local subHeading = Widgets.Label(column, "GameFontNormal", "When a slot can't resolve", colors.parchment)
  subHeading:SetPoint("TOPLEFT", column, "TOPLEFT", 0, 0)

  local blurb = Widgets.Label(
    column,
    "GameFontHighlightSmall",
    "If a Dynamic Action has no usable ability for the current character, decide what happens to that action-bar slot when a Layer is applied."
  )
  blurb:SetPoint("TOPLEFT", subHeading, "BOTTOMLEFT", 0, -6)
  blurb:SetWidth(480)
  blurb:SetJustifyH("LEFT")
  blurb:SetTextColor(Widgets.unpackColor(colors.muted))

  local anchor
  self.fallbackRadios, anchor = buildRadioGroup(column, blurb, FALLBACK_OPTIONS, function(value)
    MM.DB:SetFallback(value)
    self:Refresh()
  end)

  local responseHeading = Widgets.Label(column, "GameFontNormal", "When changes are detected", colors.parchment)
  responseHeading:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -28)

  local responseBlurb = Widgets.Label(
    column,
    "GameFontHighlightSmall",
    "An event such as logging in, changing specialization or learning a spell re-scans the active profile. Choose how the add-on reacts when that scan finds changes to apply."
  )
  responseBlurb:SetPoint("TOPLEFT", responseHeading, "BOTTOMLEFT", 0, -6)
  responseBlurb:SetWidth(480)
  responseBlurb:SetJustifyH("LEFT")
  responseBlurb:SetTextColor(Widgets.unpackColor(colors.muted))

  self.responseRadios, anchor = buildRadioGroup(column, responseBlurb, RESPONSE_OPTIONS, function(value)
    MM.DB:SetResponse(value)
    self:Refresh()
  end)

  local suggestHeading = Widgets.Label(column, "GameFontNormal", "When binding an action", colors.parchment)
  suggestHeading:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -28)

  local suggestBlurb = Widgets.Label(
    column,
    "GameFontHighlightSmall",
    "Some abilities are covered by a Dynamic Action (an interrupt, a per-class racial, ...). Choose what happens when you bind one of those to a slot."
  )
  suggestBlurb:SetPoint("TOPLEFT", suggestHeading, "BOTTOMLEFT", 0, -6)
  suggestBlurb:SetWidth(480)
  suggestBlurb:SetJustifyH("LEFT")
  suggestBlurb:SetTextColor(Widgets.unpackColor(colors.muted))

  self.suggestRadios = buildRadioGroup(column, suggestBlurb, SUGGEST_OPTIONS, function(value)
    MM.DB:SetSuggestMode(value)
    self:Refresh()
  end)

  self:Refresh()
end

-- Built once; Refresh just re-syncs each group to its stored value.
function SettingsTab:Refresh()
  local fallback = MM.DB:GetFallback()
  for value, radio in pairs(self.fallbackRadios or {}) do
    radio:SetChecked(value == fallback)
  end

  local response = MM.DB:GetResponse()
  for value, radio in pairs(self.responseRadios or {}) do
    radio:SetChecked(value == response)
  end

  local suggestMode = MM.DB:GetSuggestMode()
  for value, radio in pairs(self.suggestRadios or {}) do
    radio:SetChecked(value == suggestMode)
  end
end
