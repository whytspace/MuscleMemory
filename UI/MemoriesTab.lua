local ADDON_NAME, MM = ...

-- The Memories tab. Browsing is fully live (list, per-character resolution,
-- candidate display) and Clone-to-edit is wired to DB:CopyStandardMemory. The
-- candidate/condition *editing* needs DB + Resolver work that doesn't exist yet,
-- so those controls are rendered to match the design but are inert for now.
local MemoriesTab = {}
MM.ui.MemoriesTab = MemoriesTab

local Widgets = MM.ui.Widgets
local colors = Widgets.colors

local RAIL_WIDTH = 268
local RULE_WIDTH = 330

local function refresh()
  MM.UI:Refresh()
end

local function memoryList()
  local memories = {}
  for id, memory in pairs(MM.StandardMemories or {}) do
    memories[#memories + 1] = { source = "standard", id = id, name = memory.name or id, locked = true }
  end
  for id, memory in pairs(MM.DB:GetRoot().customMemories or {}) do
    memories[#memories + 1] = { source = "custom", id = id, name = memory.name or id, locked = false }
  end
  table.sort(memories, function(left, right)
    return left.name < right.name
  end)
  return memories
end

local function resolveMemory(ref)
  return MM.Resolver:ResolveAction({ type = "memory", source = ref.source, id = ref.id })
end

-- The currently selected memory, defaulting to the first available.
local function selectedRef()
  local state = MM.ui.state
  if state.memory and MM.DB:GetMemory(state.memory) then
    return state.memory
  end
  local list = memoryList()
  if list[1] then
    state.memory = { source = list[1].source, id = list[1].id }
    return state.memory
  end
  return nil
end

local function selectMemory(ref)
  MM.ui.state.memory = ref
  MM.ui.state.candidate = 1
  MM.ui.state.condsOpen = false
  refresh()
end

local function selectCandidate(index)
  MM.ui.state.candidate = index
  MM.ui.state.condsOpen = false
  refresh()
end

local function cloneMemory(ref)
  if ref.source ~= "standard" then
    MM:Warn("cloning custom memories isn't supported yet.")
    return
  end
  local key, reason = MM.DB:CopyStandardMemory(ref.id)
  if not key then
    MM:Warn(reason or "could not clone memory")
    return
  end
  selectMemory({ source = "custom", id = key })
end

local function prettyClass(token)
  token = tostring(token)
  return token:sub(1, 1):upper() .. token:sub(2):lower()
end

-- Describe one candidate for the rows + rule panel.
local function candidateInfo(candidate)
  if candidate.type == "spell" then
    local info = MM.Spells.GetInfo(candidate.id)
    return info and info.name or ("Spell " .. tostring(candidate.id)), info and info.icon
  elseif candidate.type == "item" then
    local info = MM.Items.GetInfo(candidate.id)
    return info and info.name or ("Item " .. tostring(candidate.id)), info and info.icon
  elseif candidate.type == "mount" then
    local info = MM.Mounts.GetInfo(candidate.id)
    return info and info.name or ("Mount " .. tostring(candidate.id)), info and info.icon
  end
  return MM.Actions.GetAssignmentLabel(candidate), nil
end

-- Left rail ------------------------------------------------------------------

function MemoriesTab:BuildRail(parent, ref)
  local inset = CreateFrame("Frame", nil, parent)
  inset:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
  inset:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, 0)
  inset:SetWidth(RAIL_WIDTH)

  local newButton = Widgets.Button(inset, "+ New Memory", RAIL_WIDTH - 24, nil)
  newButton:SetPoint("BOTTOM", inset, "BOTTOM", 0, 10)
  newButton:Disable()
  newButton:SetScript("OnEnter", function(button)
    GameTooltip:SetOwner(button, "ANCHOR_TOP")
    GameTooltip:SetText(
      "Creating blank memories is coming soon \226\128\148 use Clone to edit for now.",
      1,
      1,
      1,
      1,
      true
    )
    GameTooltip:Show()
  end)
  newButton:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)

  local scroll, content = Widgets.ScrollList(inset)
  scroll:SetPoint("TOPLEFT", inset, "TOPLEFT", 8, -8)
  scroll:SetPoint("BOTTOMRIGHT", newButton, "TOPRIGHT", -8, 8)

  local y = 0
  for _, memory in ipairs(memoryList()) do
    local active = ref and memory.source == ref.source and memory.id == ref.id
    local memoryObj = MM.DB:GetMemory({ source = memory.source, id = memory.id })
    local resolved = resolveMemory(memory)

    local row = Widgets.ListRow(content, 44)
    row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
    row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, y)
    row:SetSelected(active)

    local tile = Widgets.Icon(row, 30)
    tile:SetPoint("LEFT", row, "LEFT", 8, 0)
    if resolved and resolved.icon then
      tile:SetTextureImage(resolved.icon)
      tile:SetBorder(1, colors.managed)
    else
      tile:SetSymbol(Widgets.TEX.warning)
      tile:SetBorder(1, colors.warn, 0.7)
    end

    local lock = row:CreateTexture(nil, "ARTWORK")
    lock:SetSize(12, 14)
    lock:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    if memory.locked then
      lock:SetTexture(Widgets.TEX.lock)
    else
      lock:Hide()
    end

    local name = Widgets.Label(row, "GameFontHighlight", memory.name)
    name:SetPoint("TOPLEFT", tile, "TOPRIGHT", 9, -1)
    name:SetPoint("RIGHT", lock, "LEFT", -4, 0)
    name:SetJustifyH("LEFT")
    name:SetWordWrap(false)
    if active then
      name:SetTextColor(Widgets.unpackColor(colors.gold))
    end

    local count = memoryObj and memoryObj.candidates and #memoryObj.candidates or 0
    local subText = resolved and ("resolves to " .. resolved.label) or ("no match \194\183 " .. count .. " candidates")
    local sub = Widgets.Label(row, "GameFontDisableSmall", subText)
    sub:SetPoint("BOTTOMLEFT", name, "BOTTOMLEFT", 0, -16)
    sub:SetPoint("RIGHT", lock, "LEFT", -4, 0)
    sub:SetJustifyH("LEFT")
    sub:SetWordWrap(false)

    row:SetScript("OnClick", function()
      selectMemory({ source = memory.source, id = memory.id })
    end)

    y = y - 47
  end
  content:SetHeight(math.max(1, -y))
end

-- Centre: candidate list -----------------------------------------------------

function MemoriesTab:BuildCenter(parent, ref, memory)
  local center = CreateFrame("Frame", nil, parent)
  center:SetPoint("TOPLEFT", parent, "TOPLEFT", RAIL_WIDTH + 14, -6)
  center:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -(RULE_WIDTH + 14), 6)

  local title = Widgets.Title(center, memory and memory.name or "\226\128\148")
  title:SetPoint("TOPLEFT", center, "TOPLEFT", 4, -2)

  local locked = ref.source == "standard"
  if locked then
    local tag = Widgets.Label(center, "GameFontDisableSmall", "PREDEFINED \194\183 read-only")
    tag:SetPoint("LEFT", title, "RIGHT", 12, 0)

    local clone = Widgets.Button(center, "Clone to edit", 110, function()
      cloneMemory(ref)
    end)
    clone:SetPoint("TOPRIGHT", center, "TOPRIGHT", -4, -2)
  else
    local clone = Widgets.Button(center, "Clone", 60, function()
      cloneMemory(ref)
    end)
    clone:SetPoint("TOPRIGHT", center, "TOPRIGHT", -4, -2)

    -- Inert editing controls (rename / delete / add) — rendered, disabled.
    for _, spec in ipairs({ { "Delete", 60 }, { "Rename", 66 }, { "+ Add action", 100 } }) do
      local button = Widgets.Button(center, spec[1], spec[2], nil)
      button:SetPoint("RIGHT", clone, "LEFT", -6, 0)
      button:Disable()
      clone = button
    end
  end

  -- Resolution chip.
  local resolved = resolveMemory(ref)
  local chipText = resolved and ('On this character resolves to "' .. resolved.label .. '".')
    or "No candidate is usable by this character \226\128\148 slots bound here fall through."
  local chip = Widgets.Label(center, "GameFontHighlightSmall", chipText, resolved and colors.parchment or colors.warn)
  chip:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
  chip:SetPoint("RIGHT", center, "RIGHT", -4, 0)
  chip:SetJustifyH("LEFT")

  local hint =
    Widgets.Hint(center, (locked and "Priority order" or "Drag to reorder") .. " \194\183 the first usable action wins")
  hint:SetPoint("TOPLEFT", chip, "BOTTOMLEFT", 0, -10)

  -- Candidate rows.
  local scroll, content = Widgets.ScrollList(center)
  scroll:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -8)
  scroll:SetPoint("BOTTOMRIGHT", center, "BOTTOMRIGHT", -22, 4)

  local candidates = memory and memory.candidates or {}
  local selected = MM.ui.state.candidate or 1
  local y = 0
  for index, candidate in ipairs(candidates) do
    local name, icon = candidateInfo(candidate)
    local row = Widgets.ListRow(content, 40)
    row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
    row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, y)
    row:SetSelected(index == selected)

    local order = Widgets.Label(row, "GameFontNormalSmall", tostring(index))
    order:SetWidth(16)
    order:SetJustifyH("LEFT")
    if locked then
      -- Predefined memories can't be reordered, so there's no drag handle.
      order:SetPoint("LEFT", row, "LEFT", 12, 0)
    else
      local handle = Widgets.DragDots(row)
      handle:SetPoint("LEFT", row, "LEFT", 10, 0)
      order:SetPoint("LEFT", handle, "RIGHT", 8, 0)
    end
    order:SetTextColor(Widgets.unpackColor(colors.goldDim))

    local tile = Widgets.Icon(row, 30)
    tile:SetPoint("LEFT", order, "RIGHT", 8, 0)
    if icon then
      tile:SetTextureImage(icon)
    else
      tile:SetGlyph("?", colors.faint)
    end
    tile:SetBorder(1, colors.managed, 0.7)

    local label = Widgets.Label(row, "GameFontHighlight", name)
    label:SetPoint("LEFT", tile, "RIGHT", 9, 0)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)

    if candidate.classes then
      local chips = {}
      for _, token in ipairs(candidate.classes) do
        chips[#chips + 1] = prettyClass(token)
      end
      local condition = Widgets.Label(row, "GameFontDisableSmall", table.concat(chips, " / "))
      condition:SetPoint("RIGHT", row, "RIGHT", -8, 0)
      condition:SetTextColor(Widgets.unpackColor(colors.goldDim))
      label:SetPoint("RIGHT", condition, "LEFT", -6, 0)
    else
      label:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    end

    row:SetScript("OnClick", function()
      selectCandidate(index)
    end)

    y = y - 43
  end
  content:SetHeight(math.max(1, -y))

  if #candidates == 0 then
    local note = Widgets.Label(center, "GameFontDisableSmall", "This memory has no candidates.")
    note:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -16)
  end
end

-- Right: condition editor (inert preview) ------------------------------------

function MemoriesTab:BuildRule(parent, memory)
  local inset = CreateFrame("Frame", nil, parent)
  inset:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
  inset:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
  inset:SetWidth(RULE_WIDTH)

  local candidates = memory and memory.candidates or {}
  local candidate = candidates[MM.ui.state.candidate or 1]
  if not candidate then
    local note = Widgets.Label(inset, "GameFontDisableSmall", "Select a candidate to see when it is used.")
    note:SetPoint("TOPLEFT", inset, "TOPLEFT", 16, -20)
    note:SetPoint("TOPRIGHT", inset, "TOPRIGHT", -16, -20)
    note:SetJustifyH("LEFT")
    return
  end

  local name, icon = candidateInfo(candidate)

  local tile = Widgets.Icon(inset, 32)
  tile:SetPoint("TOPLEFT", inset, "TOPLEFT", 16, -16)
  if icon then
    tile:SetTextureImage(icon)
  else
    tile:SetGlyph("?", colors.faint)
  end
  tile:SetBorder(1, colors.managed, 0.7)

  local title = Widgets.Label(inset, "GameFontHighlight", name)
  title:SetPoint("TOPLEFT", tile, "TOPRIGHT", 10, -1)
  title:SetPoint("RIGHT", inset, "RIGHT", -14, 0)
  title:SetJustifyH("LEFT")

  local sub = Widgets.Label(inset, "GameFontDisableSmall", "when to use this candidate")
  sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)

  -- "No conditions" info box.
  local box = CreateFrame("Frame", nil, inset, "BackdropTemplate")
  box:SetPoint("TOPLEFT", tile, "BOTTOMLEFT", 0, -14)
  box:SetPoint("RIGHT", inset, "RIGHT", -14, 0)
  box:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1,
  })
  box:SetBackdropColor(0.08, 0.075, 0.05, 0.6)
  box:SetBackdropBorderColor(0.16, 0.15, 0.12, 1)

  local dot = box:CreateTexture(nil, "ARTWORK")
  dot:SetSize(8, 8)
  dot:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -12)
  dot:SetColorTexture(0.5, 0.78, 0.63, 1)

  local heading = Widgets.Label(box, "GameFontHighlightSmall", "No conditions", colors.parchment)
  heading:SetPoint("LEFT", dot, "RIGHT", 8, 0)

  local body = Widgets.Label(
    box,
    "GameFontDisableSmall",
    "Used whenever this character can cast it. The built-in check already handles class, race, and whether the action is learned \226\128\148 most candidates need nothing more."
  )
  body:SetPoint("TOPLEFT", dot, "BOTTOMLEFT", 0, -8)
  body:SetPoint("RIGHT", box, "RIGHT", -12, 0)
  body:SetJustifyH("LEFT")
  body:SetSpacing(2)
  box:SetHeight(body:GetStringHeight() + 44)

  local anchor = box

  -- Any class restriction already in the data, shown read-only.
  if candidate.classes then
    local classHead = Widgets.Label(inset, "GameFontNormalSmall", "Class", colors.goldDim)
    classHead:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 0, -14)

    local x = 0
    local previous = classHead
    for _, token in ipairs(candidate.classes) do
      local chip = Widgets.Label(inset, "GameFontHighlightSmall", "  " .. prettyClass(token) .. "  ", colors.parchment)
      if previous == classHead then
        chip:SetPoint("TOPLEFT", classHead, "BOTTOMLEFT", 0, -6)
      else
        chip:SetPoint("LEFT", previous, "RIGHT", 8, 0)
      end
      previous = chip
      x = x + 1
    end
    anchor = classHead
  end

  -- The advanced condition controls the design shows are not wired yet.
  local soon = Widgets.Label(
    inset,
    "GameFontDisableSmall",
    "Specialization, role, level and faction conditions are coming soon \226\128\148 the editor below is a preview."
  )
  soon:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, candidate.classes and -28 or -16)
  soon:SetPoint("RIGHT", inset, "RIGHT", -14, 0)
  soon:SetJustifyH("LEFT")
  soon:SetSpacing(2)
  soon:SetTextColor(Widgets.unpackColor(colors.faint))

  local addCond = Widgets.Button(inset, "+ Add a condition (advanced)", RULE_WIDTH - 28, nil)
  addCond:SetPoint("TOPLEFT", soon, "BOTTOMLEFT", 0, -12)
  addCond:Disable()
end

-- Assembly -------------------------------------------------------------------

function MemoriesTab:Build(parent)
  local ref = selectedRef()
  if not ref then
    local note = Widgets.Label(parent, "GameFontHighlight", "No memories available.")
    note:SetPoint("CENTER")
    return
  end

  local memory = MM.DB:GetMemory(ref)
  local candidateCount = memory and memory.candidates and #memory.candidates or 0
  if (MM.ui.state.candidate or 1) > candidateCount then
    MM.ui.state.candidate = 1
  end

  self:BuildRail(parent, ref)
  self:BuildCenter(parent, ref, memory)
  self:BuildRule(parent, memory)

  local leftGroove = Widgets.VGroove(parent)
  leftGroove:SetPoint("TOPLEFT", parent, "TOPLEFT", RAIL_WIDTH + 6, -6)
  leftGroove:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", RAIL_WIDTH + 6, 6)

  local rightGroove = Widgets.VGroove(parent)
  rightGroove:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -(RULE_WIDTH + 6), -6)
  rightGroove:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -(RULE_WIDTH + 6), 6)
end
