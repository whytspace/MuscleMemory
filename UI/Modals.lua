local ADDON_NAME, MM = ...
local L = MM.L

-- A single reusable modal dialog reconfigured per call: an input prompt (new /
-- rename) or a confirmation (delete). Built from stock dialog art so it reads as
-- a native popup while letting us control the button labels the mockup specifies.
local Modals = {}
MM.ui.Modals = Modals

local DIALOG_BACKDROP = {
  bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
  edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
  tile = true,
  tileSize = 32,
  edgeSize = 32,
  insets = { left = 11, right = 12, top = 12, bottom = 11 },
}

local function build()
  local overlay = CreateFrame("Frame", "MuscleMemoryDialog", UIParent)
  overlay:SetFrameStrata("FULLSCREEN_DIALOG")
  overlay:SetAllPoints(UIParent)
  overlay:EnableMouse(true)
  overlay:Hide()

  local shade = overlay:CreateTexture(nil, "BACKGROUND")
  shade:SetAllPoints()
  shade:SetColorTexture(0, 0, 0, 0.6)
  -- Exposed so the screenshot tour can hide it during a matte capture.
  overlay.shade = shade

  local box = CreateFrame("Frame", nil, overlay, "BackdropTemplate")
  box:SetSize(400, 200)
  box:SetPoint("CENTER")
  box:SetBackdrop(DIALOG_BACKDROP)
  overlay.box = box

  box.title = box:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  box.title:SetPoint("TOP", 0, -20)
  box.title:SetTextColor(MM.ui.Widgets.unpackColor(MM.ui.Widgets.colors.gold))

  box.message = box:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  box.message:SetPoint("TOPLEFT", 24, -52)
  box.message:SetPoint("TOPRIGHT", -24, -52)
  box.message:SetJustifyH("LEFT")
  box.message:SetSpacing(MM.ui.Widgets.LINE_SPACING)

  box.editBox = CreateFrame("EditBox", nil, box, "InputBoxTemplate")
  box.editBox:SetSize(330, 22)
  box.editBox:SetPoint("TOPLEFT", 28, -78)
  box.editBox:SetAutoFocus(false)

  box.accept = CreateFrame("Button", nil, box, "UIPanelButtonTemplate")
  box.accept:SetSize(120, 24)
  box.accept:SetPoint("BOTTOMRIGHT", box, "BOTTOM", -6, 18)

  box.cancel = CreateFrame("Button", nil, box, "UIPanelButtonTemplate")
  box.cancel:SetSize(120, 24)
  box.cancel:SetPoint("BOTTOMLEFT", box, "BOTTOM", 6, 18)
  box.cancel:SetText(CANCEL or L["Cancel"])

  -- Closing via Escape on the input mirrors Cancel.
  box.editBox:SetScript("OnEscapePressed", function()
    Modals.Hide()
  end)
  box.editBox:SetScript("OnEnterPressed", function()
    overlay.box.accept:Click()
  end)
  box.cancel:SetScript("OnClick", function()
    Modals.Hide()
  end)

  tinsert(UISpecialFrames, "MuscleMemoryDialog")
  return overlay
end

local function ensure()
  Modals.frame = Modals.frame or build()
  return Modals.frame
end

function Modals.Hide()
  if Modals.frame then
    Modals.frame:Hide()
  end
end

-- The Choose modal restyles the shared box (accept hidden, cancel centered and
-- rewired, list rows); reset that here so every show starts from the stock layout.
local function resetLayout(box)
  box.accept:Show()
  box.cancel:ClearAllPoints()
  box.cancel:SetPoint("BOTTOMLEFT", box, "BOTTOM", 6, 18)
  box.cancel:SetSize(120, 24)
  box.cancel:SetText(CANCEL or L["Cancel"])
  box.cancel:SetScript("OnClick", function()
    Modals.Hide()
  end)
  for _, row in ipairs(box.choices or {}) do
    row:Hide()
  end
end

-- opts: title, message (confirm) | label+value (input), acceptLabel, kind
-- ("input"|"confirm"), and onAccept (receives the entered text for inputs).
local function show(opts)
  local overlay = ensure()
  local box = overlay.box
  resetLayout(box)
  local isInput = opts.kind == "input"

  box.title:SetText(opts.title or "")
  box.accept:SetText(opts.acceptLabel or (isInput and (DONE or L["Done"])) or (DELETE or L["Delete"]))

  if isInput then
    box.message:SetText(opts.label or "")
    box.editBox:Show()
    box.editBox:SetText(opts.value or "")
    box.editBox:HighlightText()
    box:SetHeight(178)
  else
    box.message:SetText(opts.message or "")
    box.editBox:Hide()
    -- Size to content: the message starts 52px down, then a gap plus the
    -- button row (24) and bottom inset (18) so short confirmations aren't tall.
    box:SetHeight(52 + box.message:GetStringHeight() + 22 + 42)
  end

  box.accept:SetScript("OnClick", function()
    local value = isInput and box.editBox:GetText() or nil
    Modals.Hide()
    if opts.onAccept then
      opts.onAccept(value)
    end
  end)

  overlay:Show()
  overlay:Raise()
  if isInput then
    box.editBox:SetFocus()
  end
end

-- Public helpers ------------------------------------------------------------

function Modals.Input(title, label, value, acceptLabel, onAccept)
  show({
    kind = "input",
    title = title,
    label = label,
    value = value,
    acceptLabel = acceptLabel,
    onAccept = function(text)
      text = string.gsub(text or "", "^%s+", "")
      text = string.gsub(text, "%s+$", "")
      onAccept(text)
    end,
  })
end

function Modals.Confirm(title, message, acceptLabel, onAccept)
  show({
    kind = "confirm",
    title = title,
    message = message,
    acceptLabel = acceptLabel,
    onAccept = function()
      onAccept()
    end,
  })
end

-- A one-of-N picker. opts: title, message, options (array, opaque to Modals),
-- rowInit(row, option) styling each pooled list row (a plain full-width Button —
-- the caller owns its look, so the rows can match its own lists), onSelect(option),
-- cancelLabel and onCancel for the explicit cancel row. Escape closes the dialog
-- without either callback.
function Modals.Choose(opts)
  local overlay = ensure()
  local box = overlay.box
  resetLayout(box)

  box.title:SetText(opts.title or "")
  box.message:SetText(opts.message or "")
  box.editBox:Hide()
  box.accept:Hide()
  box.cancel:ClearAllPoints()
  box.cancel:SetPoint("BOTTOM", box, "BOTTOM", 0, 18)
  box.cancel:SetText(opts.cancelLabel or (CANCEL or L["Cancel"]))
  -- Size to the label: "Keep <spell name>" easily overflows the stock 120px.
  local cancelText = box.cancel:GetFontString()
  box.cancel:SetWidth(math.max(120, (cancelText and cancelText:GetStringWidth() or 0) + 40))
  box.cancel:SetScript("OnClick", function()
    Modals.Hide()
    if opts.onCancel then
      opts.onCancel()
    end
  end)

  box.choices = box.choices or {}
  local top = 52 + box.message:GetStringHeight() + 14
  for index, option in ipairs(opts.options) do
    local row = box.choices[index]
    if not row then
      row = CreateFrame("Button", nil, box)
      row:SetHeight(28)
      row:SetPoint("LEFT", box, "LEFT", 24, 0)
      row:SetPoint("RIGHT", box, "RIGHT", -24, 0)
      box.choices[index] = row
    end
    row:SetPoint("TOP", box, "TOP", 0, -(top + (index - 1) * 30))
    opts.rowInit(row, option)
    row:SetScript("OnClick", function()
      Modals.Hide()
      opts.onSelect(option)
    end)
    row:Show()
  end

  -- Message, the option rows, then a gap plus the cancel row and bottom inset.
  box:SetHeight(top + #opts.options * 30 + 12 + 24 + 18)

  overlay:Show()
  overlay:Raise()
end
