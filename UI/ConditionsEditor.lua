local ADDON_NAME, MM = ...

-- A reusable editor for a `conditions` table (the one Conditions.Match reads),
-- used by both memory candidates and muscles. Builds into `parent`, mutates the
-- passed `conditions` table in place, and calls `onChange` after each edit. When
-- `editable` is false it renders the same controls read-only (for predefined
-- memories). Returns the container frame with its height set.
local ConditionsEditor = {}
MM.ui.ConditionsEditor = ConditionsEditor

local Widgets = MM.ui.Widgets
local colors = Widgets.colors

local CLASSES = {
  { token = "WARRIOR", name = "Warrior" },
  { token = "PALADIN", name = "Paladin" },
  { token = "HUNTER", name = "Hunter" },
  { token = "ROGUE", name = "Rogue" },
  { token = "PRIEST", name = "Priest" },
  { token = "DEATHKNIGHT", name = "Death Knight" },
  { token = "SHAMAN", name = "Shaman" },
  { token = "MAGE", name = "Mage" },
  { token = "WARLOCK", name = "Warlock" },
  { token = "MONK", name = "Monk" },
  { token = "DRUID", name = "Druid" },
  { token = "DEMONHUNTER", name = "Demon Hunter" },
  { token = "EVOKER", name = "Evoker" },
}

local ROLES = {
  { token = "TANK", name = "Tank" },
  { token = "HEALER", name = "Healer" },
  { token = "DAMAGER", name = "DPS" },
}

local FACTIONS = {
  { token = "Alliance", name = "Alliance" },
  { token = "Horde", name = "Horde" },
}

-- The player's current class specs (spec conditions can only be set for your own
-- class, which is the realistic case — you configure on the character you play).
local function playerSpecs()
  local specs = {}
  if not GetNumSpecializations then
    return specs
  end
  for index = 1, GetNumSpecializations() do
    local id, name = GetSpecializationInfo(index)
    if id then
      specs[#specs + 1] = { token = id, name = name or ("Spec " .. index) }
    end
  end
  return specs
end

local function listHas(list, value)
  if not list then
    return false
  end
  for _, entry in ipairs(list) do
    if entry == value then
      return true
    end
  end
  return false
end

-- Toggle `value` in conditions[field], dropping the field when it empties.
local function toggle(conditions, field, value)
  local list = conditions[field] or {}
  for index, entry in ipairs(list) do
    if entry == value then
      table.remove(list, index)
      conditions[field] = #list > 0 and list or nil
      return
    end
  end
  list[#list + 1] = value
  conditions[field] = list
end

local function makeChip(parent, text, active, editable, onClick)
  local chip = CreateFrame("Button", nil, parent)
  chip:SetHeight(22)

  local label = chip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  label:SetPoint("CENTER")
  label:SetText(text)
  chip:SetWidth(label:GetStringWidth() + 18)

  local bg = chip:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()

  if active then
    bg:SetColorTexture(Widgets.unpackColor(colors.gold, 0.16))
    label:SetTextColor(Widgets.unpackColor(colors.gold))
  else
    bg:SetColorTexture(0.1, 0.1, 0.12, 0.8)
    label:SetTextColor(Widgets.unpackColor(editable and colors.parchment or colors.faint))
  end

  if editable then
    chip:SetScript("OnClick", onClick)
    chip:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
  end
  return chip
end

-- A wrap-flow row of toggle chips for a list-valued dimension.
local function chipGroup(parent, top, conditions, field, options, editable, onChange)
  local x, y, rowHeight, right = 0, 0, 22, 296
  for _, option in ipairs(options) do
    local active = listHas(conditions[field], option.token)
    local chip = makeChip(parent, option.name, active, editable, function()
      toggle(conditions, field, option.token)
      onChange()
    end)
    if x + chip:GetWidth() > right and x > 0 then
      x, y = 0, y - (rowHeight + 4)
    end
    chip:SetPoint("TOPLEFT", parent, "TOPLEFT", x, top + y)
    x = x + chip:GetWidth() + 5
  end
  return top + y - (rowHeight + 8)
end

local function section(parent, top, title)
  local header = Widgets.SectionHeader(parent, title)
  header:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, top)
  return top - 18
end

-- Builds into a frame the caller anchors (top-left + a width via a right anchor).
function ConditionsEditor:Build(parent, conditions, editable, onChange)
  local frame = CreateFrame("Frame", nil, parent)
  local y = 0

  y = section(frame, y, "Class")
  y = chipGroup(frame, y, conditions, "classes", CLASSES, editable, onChange)

  local specs = playerSpecs()
  if #specs > 0 then
    y = section(frame, y, "Specialization")
    y = chipGroup(frame, y, conditions, "specs", specs, editable, onChange)
  end

  y = section(frame, y, "Role")
  y = chipGroup(frame, y, conditions, "roles", ROLES, editable, onChange)

  y = section(frame, y, "Faction")
  y = chipGroup(frame, y, conditions, "factions", FACTIONS, editable, onChange)

  -- Level range.
  y = section(frame, y, "Level range")
  local function levelBox(field)
    local box = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    box:SetSize(54, 22)
    box:SetAutoFocus(false)
    box:SetNumeric(true)
    box:SetText(conditions[field] and tostring(conditions[field]) or "")
    if box.SetEnabled then
      box:SetEnabled(editable)
    end
    box:SetScript("OnEnterPressed", box.ClearFocus)
    box:SetScript("OnEscapePressed", box.ClearFocus)
    box:SetScript("OnEditFocusLost", function(self)
      local value = tonumber(self:GetText())
      conditions[field] = value
      onChange()
    end)
    return box
  end
  local minBox = levelBox("levelMin")
  minBox:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, y - 2)
  local dash = Widgets.Label(frame, "GameFontDisableSmall", "to")
  dash:SetPoint("LEFT", minBox, "RIGHT", 8, 0)
  local maxBox = levelBox("levelMax")
  maxBox:SetPoint("LEFT", dash, "RIGHT", 8, 0)
  y = y - 30

  frame:SetHeight(-y + 4)
  return frame
end
