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
  local key, reason = MM.DB:CloneMemory(ref)
  if not key then
    MM:Warn(reason or "could not clone memory")
    return
  end
  selectMemory({ source = "custom", id = key })
end

-- Drag a spell/item/macro/mount/equipment set onto the candidate list to add it
-- to the (custom) memory.
local function addCandidateFromCursor(memoryId)
  local assignment, reason = MM.Capture:FromCursor()
  if not assignment then
    MM:Warn(reason or "could not read cursor")
    return
  end
  local ok, err = MM.DB:AddCandidate(memoryId, assignment)
  if not ok then
    MM:Warn(err or "could not add candidate")
  end
  if ClearCursor then
    ClearCursor()
  end
  refresh()
end

local function newMemory()
  MM.ui.Modals.Input("New Memory", "Name the new Memory", "New Memory", "Create", function(name)
    local key = MM.DB:CreateMemory(name ~= "" and name or nil)
    selectMemory({ source = "custom", id = key })
  end)
end

local function renameMemory(ref)
  local memory = MM.DB:GetMemory(ref)
  MM.ui.Modals.Input("Rename Memory", "New name for this Memory", memory and memory.name or "", "Rename", function(name)
    if name == "" then
      return
    end
    local ok, err = MM.DB:RenameMemory(ref.id, name)
    if not ok then
      MM:Warn(err)
    end
    refresh()
  end)
end

local function deleteMemory(ref)
  local memory = MM.DB:GetMemory(ref)
  local name = memory and memory.name or ref.id
  MM.ui.Modals.Confirm(
    "Delete Memory",
    string.format('Delete custom memory "%s"? Slots bound to it will fall through on the next apply.', name),
    "Delete",
    function()
      local ok, err = MM.DB:DeleteMemory(ref.id)
      if not ok then
        MM:Warn(err)
      end
      MM.ui.state.memory = nil
      refresh()
    end
  )
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
  elseif candidate.type == "battlepet" then
    local info = MM.BattlePets.GetInfo(candidate.id)
    return info and info.name or ("Pet " .. tostring(candidate.id)), info and info.icon
  elseif candidate.type == "flyout" then
    local info = MM.Flyouts.GetInfo(candidate.id)
    return info and info.name or ("Flyout " .. tostring(candidate.id)), info and info.icon
  end
  return MM.Actions.GetAssignmentLabel(candidate), nil
end

-- Left rail ------------------------------------------------------------------

function MemoriesTab:BuildRail(parent, ref)
  local inset = CreateFrame("Frame", nil, parent)
  inset:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
  inset:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, 0)
  inset:SetWidth(RAIL_WIDTH)

  local newButton = Widgets.Button(inset, "+ New Memory", RAIL_WIDTH - 24, newMemory)
  newButton:SetPoint("BOTTOM", inset, "BOTTOM", 0, 10)

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

    local del = Widgets.Button(center, "Delete", 64, function()
      deleteMemory(ref)
    end)
    del:SetPoint("RIGHT", clone, "LEFT", -6, 0)

    local rename = Widgets.Button(center, "Rename", 66, function()
      renameMemory(ref)
    end)
    rename:SetPoint("RIGHT", del, "LEFT", -6, 0)
  end

  -- Resolution chip.
  local resolved = resolveMemory(ref)
  local chipText = resolved and ('On this character resolves to "' .. resolved.label .. '".')
    or "No candidate is usable by this character \226\128\148 slots bound here fall through."
  local chip = Widgets.Label(center, "GameFontHighlightSmall", chipText, resolved and colors.parchment or colors.warn)
  chip:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
  chip:SetPoint("RIGHT", center, "RIGHT", -4, 0)
  chip:SetJustifyH("LEFT")

  local hintText = locked and "Priority order \194\183 the first usable action wins"
    or "Drag here to add \194\183 drag a row to reorder \194\183 right-click to remove \194\183 first usable wins"
  local hint = Widgets.Hint(center, hintText)
  hint:SetPoint("TOPLEFT", chip, "BOTTOMLEFT", 0, -10)

  -- Candidate rows.
  local scroll, content = Widgets.ScrollList(center)
  scroll:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -8)
  scroll:SetPoint("BOTTOMRIGHT", center, "BOTTOMRIGHT", -22, 4)

  local candidates = memory and memory.candidates or {}
  local selected = MM.ui.state.candidate or 1
  MemoriesTab.candidateRows = {}
  local y = 0
  for index, candidate in ipairs(candidates) do
    local name, icon = candidateInfo(candidate)
    local row = Widgets.ListRow(content, 40)
    row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
    row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, y)
    row:SetSelected(index == selected)
    row.candidateIndex = index
    MemoriesTab.candidateRows[index] = row

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

      -- Drag a candidate onto another to reorder (same pattern as the muscle rail).
      row:RegisterForDrag("LeftButton")
      row:SetScript("OnDragStart", function(frame)
        frame:SetAlpha(0.5)
        MemoriesTab._dragCandidate = index
      end)
      row:SetScript("OnDragStop", function(frame)
        frame:SetAlpha(1)
        local from = MemoriesTab._dragCandidate
        MemoriesTab._dragCandidate = nil
        if not from then
          return
        end
        for _, candidateRow in ipairs(MemoriesTab.candidateRows) do
          if candidateRow:IsMouseOver() then
            MM.DB:MoveCandidate(ref.id, from, candidateRow.candidateIndex)
            refresh()
            return
          end
        end
      end)
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

    local classes = candidate.conditions and candidate.conditions.classes
    if classes and #classes > 0 then
      local chips = {}
      for _, token in ipairs(classes) do
        chips[#chips + 1] = prettyClass(token)
      end
      local condition = Widgets.Label(row, "GameFontDisableSmall", table.concat(chips, " / "))
      condition:SetPoint("RIGHT", row, "RIGHT", -8, 0)
      condition:SetTextColor(Widgets.unpackColor(colors.goldDim))
      label:SetPoint("RIGHT", condition, "LEFT", -6, 0)
    else
      label:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    end

    row:SetScript("OnClick", function(_, mouseButton)
      if mouseButton == "RightButton" then
        if not locked then
          local ok, err = MM.DB:RemoveCandidate(ref.id, index)
          if not ok then
            MM:Warn(err)
          end
          refresh()
        end
        return
      end
      selectCandidate(index)
    end)

    y = y - 43
  end
  content:SetHeight(math.max(1, -y))

  if #candidates == 0 then
    local emptyText = locked and "This memory has no candidates."
      or "No candidates yet \226\128\148 drag a spell, item, macro, mount or equipment set here to add one."
    local note = Widgets.Hint(center, emptyText)
    note:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -16)
    note:SetPoint("RIGHT", center, "RIGHT", -4, 0)
    note:SetJustifyH("LEFT")
  end

  -- Custom memories accept dropped actions as new candidates.
  if locked then
    if MemoriesTab.dropZone then
      MemoriesTab.dropZone:Detach()
    end
  else
    if not MemoriesTab.dropZone then
      MemoriesTab.dropZone = Widgets.DropZone("Drop to add a candidate")
    end
    MemoriesTab.dropZone:Attach(center, function()
      addCandidateFromCursor(ref.id)
    end)
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

  -- Live condition editor: custom memories are editable, predefined ones show
  -- their conditions read-only.
  local ref = selectedRef()
  local editable = ref and ref.source == "custom"
  if editable then
    candidate.conditions = candidate.conditions or {}
  end

  local hint = Widgets.Hint(
    inset,
    editable and "Leave everything off to use this whenever the character can cast it."
      or "Predefined memory \226\128\148 conditions are read-only."
  )
  hint:SetPoint("TOPLEFT", tile, "BOTTOMLEFT", 0, -14)
  hint:SetPoint("RIGHT", inset, "RIGHT", -14, 0)
  hint:SetJustifyH("LEFT")

  local editor = MM.ui.ConditionsEditor:Build(inset, candidate.conditions or {}, editable, function()
    refresh()
  end)
  editor:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 4, -14)
  editor:SetPoint("RIGHT", inset, "RIGHT", -14, 0)
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
