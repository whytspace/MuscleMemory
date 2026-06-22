local ADDON_NAME, MM = ...

-- The window: native frame chrome, the tab strip, the profile / Preview / Apply
-- header, and the content host that swaps in one tab module at a time. Public
-- surface (Open / Refresh / PromptApply) is what Core, SlashCommands and Events
-- already call, so it stays stable.
local UI = {}
MM.UI = UI
MM:RegisterModule("UI", UI)

MM.ui.state = MM.ui.state or { tab = "muscles" }

-- A standard Blizzard icon stands in for the addon logo; the .png in Assets is
-- web-only (the client loads BLP/TGA), so swap this for a packaged texture later.
MM.ui.LOGO_TEXTURE = "Interface\\Icons\\Spell_Shadow_Brainwash"

local TABS = {
  { id = "muscles", label = "Muscles" },
  { id = "memories", label = "Memories" },
  { id = "settings", label = "Settings" },
  { id = "about", label = "About" },
}

local TAB_DESCRIPTIONS = {
  muscles = "Muscles are stacked rules that decide what each action-bar slot becomes. Higher Muscles win; slots they don't touch show the Muscle beneath.",
  memories = "Memories are named stand-ins for an action (Interrupt, Taunt, Lust). Each resolves to whichever ability the current character actually has.",
}

local function tabBuilder(id)
  return ({
    muscles = MM.ui.MusclesTab,
    memories = MM.ui.MemoriesTab,
    settings = MM.ui.SettingsTab,
    about = MM.ui.AboutTab,
  })[id]
end

-- Profiles --------------------------------------------------------------------

local function newProfile()
  MM.ui.Modals.Input("New Profile", "Name the new profile", "New Profile", "Create", function(name)
    local id = MM.DB:CreateProfile(name ~= "" and name or nil)
    MM.DB:SetActiveProfile(id)
    UI:Refresh()
  end)
end

local function renameProfile()
  local id = MM.DB:GetActiveProfileId()
  local profile = MM.DB:GetProfile(id)
  MM.ui.Modals.Input(
    "Rename Profile",
    "New name for this profile",
    profile and profile.name or "",
    "Rename",
    function(name)
      if name == "" then
        return
      end
      local ok, reason = MM.DB:RenameProfile(id, name)
      if not ok then
        MM:Warn(reason)
      end
      UI:Refresh()
    end
  )
end

local function deleteProfile()
  local id = MM.DB:GetActiveProfileId()
  local profile = MM.DB:GetProfile(id)
  local name = profile and profile.name or id
  MM.ui.Modals.Confirm(
    "Delete Profile",
    string.format(
      'Delete profile "%s"? Its set of applied Muscles is removed \226\128\148 your Muscles, their order, and the fallback are untouched.',
      name
    ),
    "Delete",
    function()
      local ok, reason = MM.DB:DeleteProfile(id)
      if not ok then
        MM:Warn(reason)
      end
      UI:Refresh()
    end
  )
end

local function openProfileMenu(button)
  MenuUtil.CreateContextMenu(button, function(_, root)
    root:CreateTitle("Profiles")
    for _, profile in ipairs(MM.DB:GetProfileList()) do
      root:CreateRadio(profile.name, function()
        return profile.id == MM.DB:GetActiveProfileId()
      end, function()
        MM.DB:SetActiveProfile(profile.id)
        UI:Refresh()
      end)
    end
    root:CreateDivider()
    root:CreateButton("New profile\226\128\166", newProfile)
    root:CreateButton("Rename current\226\128\166", renameProfile)
    if #MM.DB:GetProfileList() > 1 then
      root:CreateButton("Delete current\226\128\166", deleteProfile)
    end
  end)
end

-- Chrome ----------------------------------------------------------------------

local function makeTabButton(parent, label, onClick)
  local button = CreateFrame("Button", nil, parent)
  button:SetHeight(24)

  button.label = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  button.label:SetPoint("CENTER")
  button.label:SetText(label)
  button:SetWidth(button.label:GetStringWidth() + 26)

  button.underline = button:CreateTexture(nil, "ARTWORK")
  button.underline:SetPoint("BOTTOMLEFT", 4, -2)
  button.underline:SetPoint("BOTTOMRIGHT", -4, -2)
  button.underline:SetHeight(2)
  button.underline:SetColorTexture(MM.ui.Widgets.unpackColor(MM.ui.Widgets.colors.gold))

  button:SetScript("OnClick", onClick)
  button:SetScript("OnEnter", function(self)
    if not self.active then
      self.label:SetTextColor(MM.ui.Widgets.unpackColor(MM.ui.Widgets.colors.parchment))
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
    self.underline:SetShown(active)
  end

  return button
end

function UI:CreateFrame()
  if self.frame then
    return
  end

  local frame = CreateFrame("Frame", "MuscleMemoryFrame", UIParent, "PortraitFrameTemplate")
  frame:SetSize(1180, 720)
  frame:SetPoint("CENTER")
  frame:SetFrameStrata("HIGH")
  frame:Hide()
  frame:SetMovable(true)
  frame:EnableMouse(true)

  tinsert(UISpecialFrames, "MuscleMemoryFrame")

  if frame.SetTitle then
    frame:SetTitle("Muscle Memory")
  end
  if frame.SetPortraitToAsset then
    frame:SetPortraitToAsset(MM.ui.LOGO_TEXTURE)
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

  -- Header row: tabs (left) + profile / Preview / Apply (right).
  self.tabButtons = {}
  local previousTab
  for _, tab in ipairs(TABS) do
    local button = makeTabButton(frame, tab.label, function()
      self:SelectTab(tab.id)
    end)
    if previousTab then
      button:SetPoint("LEFT", previousTab, "RIGHT", 6, 0)
    else
      button:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -52)
    end
    previousTab = button
    self.tabButtons[tab.id] = button
  end

  local apply = MM.ui.Widgets.Button(frame, "Apply Now", 96, function()
    MM.Applier:ApplyProfile()
    self:Refresh()
  end)
  apply:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -16, -52)

  local preview = MM.ui.Widgets.Button(frame, "Preview\226\128\166", 86, function()
    MM.Applier:PreviewProfile()
  end)
  preview:SetPoint("RIGHT", apply, "LEFT", -8, 0)

  self.profileButton = MM.ui.Widgets.Button(frame, "Profile", 168, function(button)
    openProfileMenu(button)
  end)
  self.profileButton:SetPoint("RIGHT", preview, "LEFT", -10, 0)

  -- Tab description line.
  self.description = MM.ui.Widgets.Label(frame, "GameFontHighlightSmall", "", MM.ui.Widgets.colors.faint)
  self.description:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -86)
  self.description:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -18, -86)
  self.description:SetJustifyH("LEFT")
  self.description:SetTextColor(0.56, 0.52, 0.42)

  self.divider = MM.ui.Widgets.Hairline(frame, true)
  self.divider:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -106)
  self.divider:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -106)

  -- One shared inset sits behind all tab content so the three panels read as a
  -- single recessed surface; tabs separate their panels with groove dividers.
  self.contentInset = MM.ui.Widgets.Inset(frame)
  self.contentInset:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -112)
  self.contentInset:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10, 12)

  self.frame = frame
end

-- Rebuild the active tab into a fresh content frame.
function UI:ShowContent()
  if self.content then
    self.content:Hide()
    self.content:SetParent(nil)
  end

  self.content = CreateFrame("Frame", nil, self.frame)
  self.content:SetPoint("TOPLEFT", self.contentInset, "TOPLEFT", 5, -5)
  self.content:SetPoint("BOTTOMRIGHT", self.contentInset, "BOTTOMRIGHT", -5, 5)

  local tab = MM.ui.state.tab
  for id, button in pairs(self.tabButtons) do
    button:SetActive(id == tab)
  end

  local profile = MM.DB:GetProfile()
  self.profileButton:SetText("Profile:  " .. (profile and profile.name or "\226\128\148") .. "  \226\150\190")

  local description = TAB_DESCRIPTIONS[tab]
  self.description:SetText(description or "")
  self.description:SetShown(description ~= nil)

  local builder = tabBuilder(tab)
  if builder then
    builder:Build(self.content)
  end
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

  StaticPopupDialogs[APPLY_DIALOG] = StaticPopupDialogs[APPLY_DIALOG]
    or {
      text = "Muscle Memory: action bar changes are available. Apply them?",
      button1 = "Apply",
      button2 = "Close",
      OnAccept = function()
        MM.Applier:ApplyProfile()
      end,
      timeout = 0,
      whileDead = true,
      hideOnEscape = true,
      preferredIndex = 3,
    }
  StaticPopup_Show(APPLY_DIALOG)
end
