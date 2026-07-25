local ADDON_NAME, MM = ...

-- The window: native frame chrome, the tab strip, the profile / Preview / Apply
-- header, and the content host that swaps in one tab module at a time. Public
-- surface (Open / Refresh / PromptApply) is what Core, SlashCommands and Events
-- already call, so it stays stable.
local UI = {}
MM.UI = UI
MM:RegisterModule("UI", UI)

MM.ui.state = MM.ui.state or { tab = "layers" }

-- The packaged logo texture (Assets/logo.tga; regenerate from logo.png with
-- scripts/build-textures.sh). Used for the title-bar portrait and the About page.
MM.ui.LOGO_TEXTURE = "Interface\\AddOns\\MuscleMemory\\Assets\\logo"

local TABS = {
  { id = "layers", label = "Layers", icon = MM.ui.Widgets.ICON.layers },
  { id = "dynamicActions", label = "Dynamic Actions", icon = MM.ui.Widgets.ICON.dynamicAction },
  { id = "settings", label = "Settings" },
  { id = "profiles", label = "Profiles" },
  { id = "export", label = "Export", icon = MM.ui.Widgets.ICON.export },
  { id = "import", label = "Import", icon = MM.ui.Widgets.ICON.import },
  { id = "about", label = "About" },
}

local TAB_DESCRIPTIONS = {
  layers = "Layers are stacked rules that decide what each action-bar slot becomes. Higher Layers win; slots they don't touch show the Layer beneath.",
  dynamicActions = "Dynamic Actions are named stand-ins for an action (Interrupt, Taunt, Bloodlust). Each resolves to whichever ability the current character actually has.",
  settings = "Settings tune how the active profile behaves \226\128\148 each profile keeps its own.",
  profiles = "Profiles are self-contained setups, each with its own Layers and Dynamic Actions. Choose the account-wide default and an optional per-character override.",
  export = "Bundle Layers, Dynamic Actions and settings from the active profile into a copyable string other players can import.",
  import = "Paste a sharing string, pick what to take, and import it into the current or a new profile. Imports always create new entries — nothing of yours is overwritten.",
}

local function tabBuilder(id)
  return ({
    layers = MM.ui.LayersTab,
    dynamicActions = MM.ui.DynamicActionsTab,
    profiles = MM.ui.ProfilesTab,
    settings = MM.ui.SettingsTab,
    export = MM.ui.ExportTab,
    import = MM.ui.ImportTab,
    about = MM.ui.AboutTab,
  })[id]
end

-- Chrome ----------------------------------------------------------------------

local function makeTabButton(parent, label, onClick, iconTexture)
  local button = CreateFrame("Button", nil, parent)
  button:SetHeight(24)

  if iconTexture then
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetSize(15, 15)
    button.icon:SetPoint("LEFT", button, "LEFT", 8, 0)
    button.icon:SetTexture(iconTexture)
  end

  button.label = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  button.label:SetText(label)
  if button.icon then
    button.label:SetPoint("LEFT", button.icon, "RIGHT", 5, 0)
    button:SetWidth(button.label:GetStringWidth() + 36)
  else
    button.label:SetPoint("CENTER")
    button:SetWidth(button.label:GetStringWidth() + 26)
  end

  button.underline = button:CreateTexture(nil, "ARTWORK")
  button.underline:SetPoint("BOTTOMLEFT", 4, -2)
  button.underline:SetPoint("BOTTOMRIGHT", -4, -2)
  button.underline:SetHeight(2)
  button.underline:SetColorTexture(MM.ui.Widgets.unpackColor(MM.ui.Widgets.colors.gold))

  button:SetScript("OnClick", onClick)
  button:SetScript("OnEnter", function(self)
    if not self.active then
      self.label:SetTextColor(MM.ui.Widgets.unpackColor(MM.ui.Widgets.colors.parchment))
      if self.icon then
        self.icon:SetVertexColor(0.85, 0.85, 0.85)
      end
    end
  end)
  button:SetScript("OnLeave", function(self)
    self:SetActive(self.active)
  end)

  function button:SetActive(active)
    self.active = active
    if active then
      self.label:SetTextColor(MM.ui.Widgets.unpackColor(MM.ui.Widgets.colors.gold))
    else
      self.label:SetTextColor(0.54, 0.49, 0.32)
    end
    if self.icon then
      -- Dim the two-tone glyph for inactive tabs without flattening its gold ramp.
      self.icon:SetVertexColor(active and 1 or 0.6, active and 1 or 0.6, active and 1 or 0.6)
    end
    self.underline:SetShown(active)
  end

  return button
end

function UI:CreateFrame()
  if self.frame then
    return
  end

  local frame = CreateFrame("Frame", "MuscleMemoryFrame", UIParent, "PortraitFrameTemplate")
  -- Tall enough for a 15-bar grid plus the legend on the Layers tab.
  frame:SetSize(1000, 754)
  frame:SetPoint("CENTER")
  frame:SetFrameStrata("MEDIUM")
  frame:SetToplevel(true)
  frame:Hide()
  frame:SetMovable(true)
  frame:EnableMouse(true)

  -- NOT in UISpecialFrames: the panel manager sweeps that list and would close
  -- us whenever a managed panel (spellbook, talents) opens. Handle Escape
  -- ourselves so the window stays put alongside Blizzard panels.
  frame:EnableKeyboard(true)
  frame:SetPropagateKeyboardInput(true)
  frame:SetScript("OnKeyDown", function(f, key)
    if key == "ESCAPE" then
      f:SetPropagateKeyboardInput(false)
      f:Hide()
    else
      f:SetPropagateKeyboardInput(true)
    end
  end)

  if frame.SetTitle then
    frame:SetTitle("Muscle Memory")
  end
  if frame.SetPortraitToAsset then
    frame:SetPortraitToAsset(MM.ui.LOGO_TEXTURE)
    -- Zoom the portrait texture out so the full logo sits inside the circular
    -- ring instead of being clipped by it, on a black disc.
    local portrait = frame.PortraitContainer and frame.PortraitContainer.portrait
    if portrait then
      portrait:SetTexCoord(-0.15, 1.15, -0.15, 1.15)

      local backdrop = frame.PortraitContainer:CreateTexture(nil, "BACKGROUND")
      backdrop:SetAllPoints(portrait)
      backdrop:SetColorTexture(0, 0, 0, 1)

      local mask = frame.PortraitContainer:CreateMaskTexture()
      mask:SetAllPoints(backdrop)
      mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDED", "CLAMPTOBLACKADDED")
      backdrop:AddMaskTexture(mask)
    end
  end

  -- Drag from the title bar.
  local titleRegion = frame.TitleContainer or frame
  titleRegion:EnableMouse(true)
  titleRegion:RegisterForDrag("LeftButton")
  titleRegion:SetScript("OnDragStart", function()
    frame:StartMoving()
  end)
  titleRegion:SetScript("OnDragStop", function()
    frame:StopMovingOrSizing()
  end)
  -- Right-click the title bar to snap the window back to centre.
  titleRegion:SetScript("OnMouseUp", function(_, button)
    if button == "RightButton" then
      self:ResetPosition()
    end
  end)

  -- Header row: tabs (left) + profile / Preview / Apply (right).
  self.tabButtons = {}
  local previousTab
  for _, tab in ipairs(TABS) do
    local button = makeTabButton(frame, tab.label, function()
      self:SelectTab(tab.id)
    end, tab.icon)
    if previousTab then
      button:SetPoint("LEFT", previousTab, "RIGHT", 6, 0)
    else
      -- Start the row clear of the top-left portrait rather than tucked under it,
      -- and high enough to reclaim the empty band below the title bar.
      button:SetPoint("TOPLEFT", frame, "TOPLEFT", 64, -34)
    end
    previousTab = button
    self.tabButtons[tab.id] = button
  end

  local apply = MM.ui.Widgets.Button(frame, "Apply Now", 96, function()
    MM.Applier:ApplyProfile()
    self:Refresh()
  end)
  apply:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -16, -34)

  local preview = MM.ui.Widgets.Button(frame, "Preview\226\128\166", 86, function()
    MM.Applier:PreviewProfile()
  end)
  preview:SetPoint("RIGHT", apply, "LEFT", -8, 0)

  -- Undo/Redo revert configuration changes (never the bars themselves). They
  -- keep their place and fade when there is nothing to do; tooltips stay alive
  -- on the disabled state so the buttons remain discoverable.
  self.redoButton = MM.ui.Widgets.IconButton(frame, MM.ui.Widgets.ICON.redo, function()
    local label = MM.Undo:NextRedoLabel()
    return "Redo", label or "Nothing to redo"
  end, function()
    MM.Undo:Redo()
  end)
  self.redoButton:SetPoint("RIGHT", preview, "LEFT", -16, 0)
  self.redoButton:SetMotionScriptsWhileDisabled(true)

  self.undoButton = MM.ui.Widgets.IconButton(frame, MM.ui.Widgets.ICON.undo, function()
    local label = MM.Undo:NextUndoLabel()
    return "Undo", label or "Nothing to undo"
  end, function()
    MM.Undo:Undo()
  end)
  self.undoButton:SetPoint("RIGHT", self.redoButton, "LEFT", -6, 0)
  self.undoButton:SetMotionScriptsWhileDisabled(true)

  -- One shared inset sits behind all tab content so the three panels read as a
  -- single recessed surface; tabs separate their panels with groove dividers. It
  -- starts right under the tab row.
  self.contentInset = MM.ui.Widgets.Inset(frame)
  self.contentInset:SetPoint("TOPLEFT", frame, "TOPLEFT", 5, -60)
  self.contentInset:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -5, 6)

  -- The tab description sits at the top of the inset, above the tab body, with a
  -- hairline separating the two. Both hide for tabs that have no description.
  self.description = MM.ui.Widgets.Hint(self.contentInset, "")
  self.description:SetPoint("TOPLEFT", self.contentInset, "TOPLEFT", 14, -12)
  self.description:SetPoint("TOPRIGHT", self.contentInset, "TOPRIGHT", -14, -12)
  self.description:SetJustifyH("LEFT")

  self.divider = MM.ui.Widgets.Hairline(self.contentInset, true)
  self.divider:SetPoint("TOPLEFT", self.description, "BOTTOMLEFT", 0, -10)
  self.divider:SetPoint("TOPRIGHT", self.description, "BOTTOMRIGHT", 0, -10)

  self.frame = frame
end

local function anchorContent(frame, inset, divider)
  if divider then
    -- Below the description's hairline; left edge still flush with the inset.
    frame:SetPoint("TOPLEFT", divider, "BOTTOMLEFT", -9, -6)
  else
    frame:SetPoint("TOPLEFT", inset, "TOPLEFT", 5, -5)
  end
  frame:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -5, 5)
end

-- Show the active tab. Each tab owns one retained root frame; tabs with dynamic
-- state expose :Refresh to update that root in place when commands or controls
-- mutate the model.
function UI:ShowContent()
  local tab = MM.ui.state.tab

  for id, button in pairs(self.tabButtons) do
    button:SetActive(id == tab)
  end

  local description = TAB_DESCRIPTIONS[tab]
  self.description:SetText(description or "")
  self.description:SetShown(description ~= nil)
  self.divider:SetShown(description ~= nil)

  self.tabFrames = self.tabFrames or {}
  for id, frame in pairs(self.tabFrames) do
    if id ~= tab then
      frame:Hide()
    end
  end

  local builder = tabBuilder(tab)
  local frame = self.tabFrames[tab]
  local firstBuild = frame == nil
  if not frame then
    frame = CreateFrame("Frame", nil, self.frame)
    anchorContent(frame, self.contentInset, description ~= nil and self.divider or nil)
    self.tabFrames[tab] = frame
    if builder then
      builder:Build(frame)
    end
  end

  self:UpdateUndoButtons()

  frame:Show()
  if builder and builder.Refresh and not firstBuild then
    builder:Refresh()
  end
end

-- Undo/Redo stay in place; whichever has nothing to do is disabled and faded
-- rather than hidden, so the row never shifts.
local function setUndoButtonState(button, enabled)
  button:SetEnabled(enabled)
  button.icon:SetDesaturated(not enabled)
  button.icon:SetAlpha(enabled and 1 or 0.3)
end

function UI:UpdateUndoButtons()
  if not self.undoButton then
    return
  end
  setUndoButtonState(self.undoButton, MM.Undo:CanUndo())
  setUndoButtonState(self.redoButton, MM.Undo:CanRedo())
end

function UI:SelectTab(tab)
  MM.ui.state.tab = tab
  if self.frame and self.frame:IsShown() then
    self:ShowContent()
  end
end

function UI:Refresh()
  if self.frame and self.frame:IsShown() then
    self:ShowContent()
  end
end

-- Snap the window back to the centre of the screen — handy after dragging it
-- around, e.g. to line up repeatable screenshots.
function UI:ResetPosition()
  self:CreateFrame()
  self.frame:ClearAllPoints()
  self.frame:SetPoint("CENTER")
end

function UI:Open()
  self:CreateFrame()
  self.frame:Show()
  self:ShowContent()
end

function UI:OnInitialize()
  self:CreateFrame()
end

-- Apply prompt ----------------------------------------------------------------

local APPLY_DIALOG = "MUSCLEMEMORY_APPLY"

function UI:PromptApply()
  if not (StaticPopupDialogs and StaticPopup_Show) then
    return
  end

  -- Standard Blizzard two-button layout: button1 (left, OnAccept) is the OK
  -- action -- Apply -- and button2 (right, OnCancel) just dismisses. Apply lives
  -- on OnAccept, which the framework only fires on a real button1 click, so the
  -- recycle/displace path (which routes through OnCancel) can never apply.
  StaticPopupDialogs[APPLY_DIALOG] = StaticPopupDialogs[APPLY_DIALOG]
    or {
      text = "Muscle Memory: action bar changes are available (details in chat). Apply them now?\nUse /mm to open the window.",
      button1 = "Apply",
      button2 = "Cancel",
      OnAccept = function()
        MM.Applier:ApplyProfile()
      end,
      -- Cancel just closes; no apply on any dismissal path.
      timeout = 0,
      whileDead = true,
      hideOnEscape = true,
      preferredIndex = 3,
    }

  StaticPopup_Show(APPLY_DIALOG)
end

function UI:DismissApplyPrompt()
  if StaticPopup_Hide then
    StaticPopup_Hide(APPLY_DIALOG)
  end
end
