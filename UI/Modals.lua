local ADDON_NAME, MM = ...

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
  box.message:SetSpacing(3)

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
  box.cancel:SetText(CANCEL or "Cancel")

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

-- opts: title, message (confirm) | label+value (input), acceptLabel, kind
-- ("input"|"confirm"), and onAccept (receives the entered text for inputs).
local function show(opts)
  local overlay = ensure()
  local box = overlay.box
  local isInput = opts.kind == "input"

  box.title:SetText(opts.title or "")
  box.accept:SetText(opts.acceptLabel or (isInput and (DONE or "Done")) or (DELETE or "Delete"))

  if isInput then
    box.message:SetText(opts.label or "")
    box.editBox:Show()
    box.editBox:SetText(opts.value or "")
    box.editBox:HighlightText()
    box:SetHeight(178)
  else
    box.message:SetText(opts.message or "")
    box.editBox:Hide()
    box:SetHeight(186)
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
