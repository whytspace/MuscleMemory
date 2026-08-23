local ADDON_NAME, MM = ...
local L = MM.L

-- The Profiles tab. A profile is a complete, self-contained data set (its own
-- layers, actions and fallback). This tab picks which profile applies — the
-- account-wide default and an optional per-character override — and manages the
-- list of profiles (new / clone / rename / delete).
local ProfilesTab = {}
MM.ui.ProfilesTab = ProfilesTab

local Widgets = MM.ui.Widgets
local colors = Widgets.colors

local function refresh()
  MM.UI:Refresh()
end

-- A profile switch can change what applies to this character, so prompt to
-- apply/preview just like the game events do.
local function switched()
  refresh()
  MM.Events:PromptApplyIfChanged()
end

-- Mutations ------------------------------------------------------------------

local function newProfile()
  MM.ui.Modals.Input(L["New Profile"], L["Name the new (empty) profile"], L["New Profile"], L["Create"], function(name)
    local id = MM.DB:CreateProfile(name ~= "" and name or nil)
    MM.DB:SetActiveProfile(id)
    switched()
  end)
end

local function cloneProfile(id)
  local profile = MM.DB:GetProfile(id)
  local suggested = string.format(L["%s Copy"], profile and profile.name or L["Profile"])
  MM.ui.Modals.Input(L["Clone Profile"], L["Name for the cloned profile"], suggested, L["Clone"], function(name)
    local newId, reason = MM.DB:CloneProfile(id, name ~= "" and name or nil)
    if not newId then
      MM:Warn(L[reason])
      return
    end
    MM.DB:SetActiveProfile(newId)
    switched()
  end)
end

local function renameProfile(id)
  local profile = MM.DB:GetProfile(id)
  MM.ui.Modals.Input(
    L["Rename Profile"],
    L["New name for this profile"],
    profile and profile.name or "",
    L["Rename"],
    function(name)
      if name == "" then
        return
      end
      local ok, reason = MM.DB:RenameProfile(id, name)
      if not ok then
        MM:Warn(L[reason])
      end
      refresh()
    end
  )
end

local function deleteProfile(id)
  local profile = MM.DB:GetProfile(id)
  local name = profile and profile.name or id
  MM.ui.Modals.Confirm(
    L["Delete Profile"],
    string.format(L['Delete profile "%s"? Its layers and Smart Actions are gone for good.'], name),
    L["Delete"],
    function()
      local ok, reason = MM.DB:DeleteProfile(id)
      if not ok then
        MM:Warn(L[reason])
      end
      switched()
    end
  )
end

-- Selector data --------------------------------------------------------------

local function globalData()
  local current = MM.DB:GetGlobalProfileId()
  local items = {}
  for _, profile in ipairs(MM.DB:GetProfileList()) do
    items[#items + 1] = {
      label = profile.name,
      selected = profile.id == current,
      onClick = function()
        MM.DB:SetGlobalProfile(profile.id)
        switched()
      end,
    }
  end
  local profile = MM.DB:GetProfile(current)
  return { current = profile and profile.name or "\226\128\148", items = items }
end

local function playerData()
  local override = MM.DB:GetCharacterState().profile
  local items = {
    {
      label = L["Use global default"],
      selected = override == nil,
      onClick = function()
        MM.DB:SetActiveProfile(nil)
        switched()
      end,
    },
  }
  for _, profile in ipairs(MM.DB:GetProfileList()) do
    items[#items + 1] = {
      label = profile.name,
      selected = profile.id == override,
      onClick = function()
        MM.DB:SetActiveProfile(profile.id)
        switched()
      end,
    }
  end

  local label
  if override and MM.DB:GetProfile(override) then
    label = MM.DB:GetProfile(override).name
  else
    local global = MM.DB:GetProfile(MM.DB:GetGlobalProfileId())
    label = global and string.format(L["Use global default (%s)"], global.name) or L["Use global default"]
  end
  return { current = label, items = items }
end

-- Build ----------------------------------------------------------------------

function ProfilesTab:Build(parent)
  local column = CreateFrame("Frame", nil, parent)
  column:SetPoint("TOPLEFT", parent, "TOPLEFT", 40, -28)
  column:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -40, 20)

  -- Selectors sit side by side: the account default (left) and this character's
  -- override (right).
  local globalHeader = Widgets.SectionHeader(column, L["Global profile"])
  globalHeader:SetPoint("TOPLEFT", column, "TOPLEFT", 0, 0)
  local globalHint = Widgets.Label(column, "GameFontDisableSmall", L["The default every character uses."])
  globalHint:SetPoint("TOPLEFT", globalHeader, "BOTTOMLEFT", 0, -4)
  self.globalDropdown = Widgets.Dropdown(column, 260, globalData)
  self.globalDropdown:SetPoint("TOPLEFT", globalHint, "BOTTOMLEFT", 0, -8)

  local playerHeader = Widgets.SectionHeader(column, L["This character"])
  playerHeader:SetPoint("TOPLEFT", globalHeader, "TOPLEFT", 300, 0)
  local playerHint = Widgets.Label(column, "GameFontDisableSmall", L["Override the default for this character only."])
  playerHint:SetPoint("TOPLEFT", playerHeader, "BOTTOMLEFT", 0, -4)
  self.playerDropdown = Widgets.Dropdown(column, 260, playerData)
  self.playerDropdown:SetPoint("TOPLEFT", playerHint, "BOTTOMLEFT", 0, -8)

  -- A full-width invisible row that spans the selectors (its bottom follows the
  -- equal-height dropdowns), so the rule below can run the whole content width
  -- like the tab-description divider rather than only under the two dropdowns.
  local selectorRow = CreateFrame("Frame", nil, column)
  selectorRow:SetPoint("TOPLEFT", column, "TOPLEFT", 0, 0)
  selectorRow:SetPoint("TOPRIGHT", column, "TOPRIGHT", -20, 0)
  selectorRow:SetPoint("BOTTOMLEFT", self.globalDropdown, "BOTTOMLEFT", 0, 0)
  MM.ui.Tutorial:SetAnchor("profiles.selectors", selectorRow)

  -- Separate the selectors from the manage list. The rule extends past the
  -- column's content margins so it lines up with the tab-description divider above
  -- (same left/right inset). The -31 / +51 offsets cancel most of the column's
  -- margins, leaving ~9px each side to match that divider's length.
  local rule = Widgets.Hairline(column, true)
  rule:SetPoint("TOPLEFT", selectorRow, "BOTTOMLEFT", -31, -38)
  rule:SetPoint("TOPRIGHT", selectorRow, "BOTTOMRIGHT", 51, -38)

  -- Manage list. Anchored back at the column's left edge, not the full-bleed rule.
  local manageHeader = Widgets.SectionHeader(column, L["Manage profiles"])
  manageHeader:SetPoint("TOPLEFT", selectorRow, "BOTTOMLEFT", 0, -72)

  self.manageHost = CreateFrame("Frame", nil, column)
  self.manageHost:SetPoint("TOPLEFT", manageHeader, "BOTTOMLEFT", 0, -10)
  self.manageHost:SetPoint("RIGHT", column, "RIGHT", -20, 0)
  self.manageHost:SetHeight(400)

  -- New profile button, pushed to the far right of the manage-header row.
  self.newButton = Widgets.Button(column, L["+ New profile"], 130, newProfile)
  self.newButton:SetPoint("BOTTOMRIGHT", self.manageHost, "TOPRIGHT", 0, 8)

  self:Refresh()
end

-- Rebuild one manage row per profile (count changes on new/clone/delete).
local function buildRows(self)
  Widgets.ClearChildren(self.manageHost)
  local list = MM.DB:GetProfileList()
  local anchor
  for _, profile in ipairs(list) do
    local id = profile.id
    local row = CreateFrame("Frame", nil, self.manageHost)
    row:SetHeight(26)
    if anchor then
      row:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
    else
      row:SetPoint("TOPLEFT", self.manageHost, "TOPLEFT", 0, 0)
    end
    row:SetPoint("RIGHT", self.manageHost, "RIGHT", 0, 0)

    -- A faint bottom separator so the eye connects each name to its buttons
    -- across the wide gap.
    local rule = Widgets.Hairline(row, true)
    rule:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    rule:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)

    local name = Widgets.Label(row, "GameFontHighlight", profile.name, colors.parchment)
    name:SetPoint("LEFT", row, "LEFT", 8, 0)

    if MM.Share:IsImportedProfile(id) then
      local pill = Widgets.Pill(row, L["Imported"])
      pill:SetPoint("LEFT", name, "RIGHT", 8, 0)
    end

    local delete = Widgets.IconButton(row, Widgets.ICON.delete, L["Delete"], function()
      deleteProfile(id)
    end)
    delete:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    delete:SetMotionScriptsWhileDisabled(true)
    Widgets.SetIconButtonEnabled(delete, #list > 1)

    local rename = Widgets.IconButton(row, Widgets.ICON.rename, L["Rename"], function()
      renameProfile(id)
    end)
    rename:SetPoint("RIGHT", delete, "LEFT", -6, 0)

    local clone = Widgets.IconButton(row, Widgets.ICON.clone, L["Clone"], function()
      cloneProfile(id)
    end)
    clone:SetPoint("RIGHT", rename, "LEFT", -6, 0)

    anchor = row
  end
end

function ProfilesTab:Refresh()
  if self.globalDropdown then
    self.globalDropdown:Sync()
  end
  if self.playerDropdown then
    self.playerDropdown:Sync()
  end
  buildRows(self)
end
