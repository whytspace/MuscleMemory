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

-- Tokens are the *race file* string (UnitRace's second return), which is what
-- Conditions.Match compares against. Curated rather than enumerated so the names
-- read nicely and stay grouped by faction; any race missing here (e.g. a brand
-- new allied race) is still covered because the player's own race is merged in
-- live from the API below.
local RACES = {
  { token = "Human", name = "Human" },
  { token = "Dwarf", name = "Dwarf" },
  { token = "NightElf", name = "Night Elf" },
  { token = "Gnome", name = "Gnome" },
  { token = "Draenei", name = "Draenei" },
  { token = "Worgen", name = "Worgen" },
  { token = "VoidElf", name = "Void Elf" },
  { token = "LightforgedDraenei", name = "Lightforged Draenei" },
  { token = "DarkIronDwarf", name = "Dark Iron Dwarf" },
  { token = "KulTiran", name = "Kul Tiran" },
  { token = "Mechagnome", name = "Mechagnome" },
  { token = "Orc", name = "Orc" },
  { token = "Scourge", name = "Undead" },
  { token = "Tauren", name = "Tauren" },
  { token = "Troll", name = "Troll" },
  { token = "BloodElf", name = "Blood Elf" },
  { token = "Goblin", name = "Goblin" },
  { token = "Nightborne", name = "Nightborne" },
  { token = "HighmountainTauren", name = "Highmountain Tauren" },
  { token = "MagharOrc", name = "Mag'har Orc" },
  { token = "ZandalariTroll", name = "Zandalari Troll" },
  { token = "Vulpera", name = "Vulpera" },
  { token = "Pandaren", name = "Pandaren" },
  { token = "Dracthyr", name = "Dracthyr" },
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

-- The curated race list plus the player's own race (with its real token straight
-- from the API), so the character you're configuring is always selectable even
-- if it predates this list.
local function raceOptions()
  local options, seen = {}, {}
  for _, race in ipairs(RACES) do
    options[#options + 1] = race
    seen[race.token] = true
  end
  if UnitRace then
    local name, token = UnitRace("player")
    if token and not seen[token] then
      options[#options + 1] = { token = token, name = name or token }
    end
  end
  return options
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
  local chip = CreateFrame("Button", nil, parent, "BackdropTemplate")
  chip:SetHeight(22)
  chip:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1,
  })

  local label = chip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  label:SetPoint("CENTER")
  label:SetText(text)
  chip:SetWidth(label:GetStringWidth() + 24)

  if active then
    chip:SetBackdropColor(Widgets.unpackColor(colors.gold, 0.16))
    chip:SetBackdropBorderColor(Widgets.unpackColor(colors.gold, 0.85))
    label:SetTextColor(Widgets.unpackColor(colors.gold))
  else
    chip:SetBackdropColor(0.08, 0.08, 0.1, 0.6)
    chip:SetBackdropBorderColor(Widgets.unpackColor(colors.faint, 0.7))
    label:SetTextColor(Widgets.unpackColor(editable and colors.parchment or colors.faint))
  end

  if editable then
    chip:SetScript("OnClick", onClick)
    chip:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
  end
  return chip
end

-- A wrap-flow row of toggle chips for a list-valued dimension. Returns the y at
-- the bottom of the last chip row.
local function chipGroup(parent, top, conditions, field, options, editable, onChange)
  local x, y, rowHeight, right = 0, 0, 22, 290
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
  return top + y - rowHeight
end

-- Per-section expand state, keyed by title. nil = follow the default (open when
-- the section already has a selection); true/false = the user's explicit choice.
-- Persisted on the module because Build re-runs on every edit (the tabs rebuild
-- rather than retain), so a local wouldn't survive a toggle.
ConditionsEditor.open = ConditionsEditor.open or {}

local function isExpanded(title, active)
  local override = ConditionsEditor.open[title]
  if override ~= nil then
    return override
  end
  return active
end

-- Breathing room above each section header.
local SECTION_GAP = 14

local CHEVRON = {
  [true] = "Interface\\Buttons\\UI-MinusButton-Up",
  [false] = "Interface\\Buttons\\UI-PlusButton-Up",
}

-- A clickable section header that toggles its body. Label sits flush-left (lined
-- up with the chips); the expand/collapse glyph sits on the right. `active` tints
-- it gold and, with a count, shows "(n)" so usage reads even when collapsed.
local function sectionHeader(parent, top, title, count, active, expanded, onToggle)
  local button = CreateFrame("Button", nil, parent)
  button:SetHeight(22)
  button:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, top)
  button:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, top)
  button:SetScript("OnClick", onToggle)

  -- Subtle hover wash matching the left-side rail rows; the bright additive
  -- highlight reads as harsh across a header this wide.
  local hover = button:CreateTexture(nil, "BACKGROUND")
  hover:SetAllPoints()
  hover:SetColorTexture(1, 1, 1, 0.06)
  hover:Hide()
  button:SetScript("OnEnter", function()
    hover:Show()
  end)
  button:SetScript("OnLeave", function()
    hover:Hide()
  end)

  local label = Widgets.SectionHeader(button, count > 0 and (title .. " (" .. count .. ")") or title)
  label:SetPoint("LEFT", button, "LEFT", 0, 0)
  if active then
    label:SetTextColor(Widgets.unpackColor(colors.gold))
  end

  local glyph = button:CreateTexture(nil, "ARTWORK")
  glyph:SetSize(16, 16)
  glyph:SetPoint("RIGHT", button, "RIGHT", 0, 0)
  glyph:SetTexture(CHEVRON[expanded])

  return top - 26
end

-- Builds into a frame the caller anchors (top-left + a width via a right anchor).
-- Each dimension is a collapsible section: only the headers show until one is
-- opened, and a section with selections opens itself so it's visible "in use".
function ConditionsEditor:Build(parent, conditions, editable, onChange)
  local frame = CreateFrame("Frame", nil, parent)
  local y = 0

  local sections = {
    { title = "Class", field = "classes", options = CLASSES },
  }
  local specs = playerSpecs()
  if #specs > 0 then
    sections[#sections + 1] = { title = "Specialization", field = "specs", options = specs }
  end
  sections[#sections + 1] = { title = "Role", field = "roles", options = ROLES }
  sections[#sections + 1] = { title = "Faction", field = "factions", options = FACTIONS }
  sections[#sections + 1] = { title = "Race", field = "races", options = raceOptions() }

  for index, sec in ipairs(sections) do
    if index > 1 then
      y = y - SECTION_GAP
    end
    local count = conditions[sec.field] and #conditions[sec.field] or 0
    local expanded = isExpanded(sec.title, count > 0)
    y = sectionHeader(frame, y, sec.title, count, count > 0, expanded, function()
      ConditionsEditor.open[sec.title] = not expanded
      onChange()
    end)
    if expanded then
      -- Toggling a chip pins the section open, so clearing its last selection
      -- doesn't yank the section closed mid-edit.
      y = chipGroup(frame, y, conditions, sec.field, sec.options, editable, function()
        ConditionsEditor.open[sec.title] = true
        onChange()
      end)
    end
  end

  -- Level range — collapsible like the rest, with two numeric inputs as its body.
  y = y - SECTION_GAP
  local levelActive = conditions.levelMin ~= nil or conditions.levelMax ~= nil
  local levelExpanded = isExpanded("Level range", levelActive)
  y = sectionHeader(frame, y, "Level range", 0, levelActive, levelExpanded, function()
    ConditionsEditor.open["Level range"] = not levelExpanded
    onChange()
  end)
  if levelExpanded then
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
      box:SetScript("OnEditFocusLost", function(editBox)
        conditions[field] = tonumber(editBox:GetText())
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
  end

  frame:SetHeight(-y + 4)
  return frame
end
