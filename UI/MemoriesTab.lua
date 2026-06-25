local ADDON_NAME, MM = ...

-- The Memories tab. Browsing is fully live (list, per-character resolution,
-- candidate display), predefined memories can be cloned into editable profile
-- memories, and profile candidates can be added, reordered, removed, and gated
-- by conditions.
local MemoriesTab = {}
MM.ui.MemoriesTab = MemoriesTab

local Widgets = MM.ui.Widgets
local colors = Widgets.colors

local RAIL_WIDTH = 250
local RULE_WIDTH = 330

local function refresh()
  MM.UI:Refresh()
end

local function memoryList()
  local memories = {}
  for id, memory in pairs(MM.PredefinedMemories or {}) do
    memories[#memories + 1] = { source = "predefined", id = id, name = memory.name or id, locked = true }
  end
  for id, memory in pairs(MM.DB:Memories() or {}) do
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
  if state.memory and MM.DB:ResolveMemory(state.memory) then
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
  -- Open with no candidate selected, so the rule panel shows the memory's own
  -- settings (macro mode), mirroring the muscles tab's "no slot selected" state.
  MM.ui.state.candidate = nil
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
  local memory = MM.DB:ResolveMemory(ref)
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
  local memory = MM.DB:ResolveMemory(ref)
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
    local name = info and info.name or ("Item " .. tostring(candidate.id))
    -- Crafted items show their quality crystal, lifted from the item link.
    local marker = MM.Items.GetQualityMarkup(candidate.id)
    if marker then
      name = name .. " " .. marker
    end
    return name, info and info.icon
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

-- Show the rich client tooltip for a candidate (spell/item/…), anchored to its icon.
local function showCandidateTooltip(row)
  local candidate = row.data and row.data.candidate
  if not candidate then
    return
  end
  Widgets.SetActionTooltip(row.tile, candidate.type, candidate.id, (candidateInfo(candidate)))
end

-- Left rail ------------------------------------------------------------------

-- Initializer for a memory rail row (recycled by Widgets.DataList).
local function memoryRowInit(row, data)
  local memory = data.memory
  if not row.mmInit then
    row.mmInit = true
    Widgets.decorateRow(row)

    row.tile = Widgets.Icon(row, 30)
    row.tile:SetPoint("LEFT", row, "LEFT", 8, 0)

    row.lock = row:CreateTexture(nil, "ARTWORK")
    row.lock:SetSize(12, 14)
    row.lock:SetPoint("RIGHT", row, "RIGHT", -8, 0)

    row.nameLabel = Widgets.Label(row, "GameFontHighlight", "")
    row.nameLabel:SetPoint("TOPLEFT", row.tile, "TOPRIGHT", 9, -1)
    row.nameLabel:SetPoint("RIGHT", row.lock, "LEFT", -4, 0)
    row.nameLabel:SetJustifyH("LEFT")
    row.nameLabel:SetWordWrap(false)

    row.sub = Widgets.Label(row, "GameFontDisableSmall", "")
    row.sub:SetPoint("BOTTOMLEFT", row.nameLabel, "BOTTOMLEFT", 0, -16)
    row.sub:SetPoint("RIGHT", row.lock, "LEFT", -4, 0)
    row.sub:SetJustifyH("LEFT")
    row.sub:SetWordWrap(false)

    row:SetScript("OnClick", function(self)
      if self.data then
        selectMemory({ source = self.data.memory.source, id = self.data.memory.id })
      end
    end)

    -- Tooltip on the icon only; shows what the memory resolves to (its spell/item/…).
    Widgets.AttachIconTooltip(row.tile, function(r)
      local resolved = r.data and resolveMemory(r.data.memory)
      if resolved then
        Widgets.SetActionTooltip(r.tile, resolved.kind, resolved.id, resolved.label)
      end
    end)
  end

  row.data = data
  local ref = selectedRef()
  local active = ref and memory.source == ref.source and memory.id == ref.id
  row:SetSelected(active)

  local memoryObj = MM.DB:ResolveMemory({ source = memory.source, id = memory.id })
  local resolved = resolveMemory(memory)
  if resolved and resolved.icon then
    row.tile:SetTextureImage(resolved.icon)
    row.tile:SetBorder(1, colors.managed)
  else
    row.tile:SetSymbol(Widgets.TEX.warning)
    row.tile:SetBorder(1, colors.warn, 0.7)
  end

  if memory.locked then
    row.lock:SetTexture(Widgets.TEX.lock)
    row.lock:Show()
  else
    row.lock:Hide()
  end

  row.nameLabel:SetText(memory.name)
  if active then
    row.nameLabel:SetTextColor(Widgets.unpackColor(colors.gold))
  else
    row.nameLabel:SetTextColor(1, 1, 1)
  end

  local count = memoryObj and memoryObj.candidates and #memoryObj.candidates or 0
  row.sub:SetText(resolved and ("resolves to " .. resolved.label) or ("no match \194\183 " .. count .. " candidates"))
end

function MemoriesTab:BuildRail(parent)
  local inset = CreateFrame("Frame", nil, parent)
  inset:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
  inset:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, 0)
  inset:SetWidth(RAIL_WIDTH)

  local newButton = Widgets.Button(inset, "+ New Memory", RAIL_WIDTH - 24, newMemory)
  newButton:SetPoint("BOTTOM", inset, "BOTTOM", 0, 10)

  local list = Widgets.DataList(inset, "memories.rail", {
    extent = 44,
    spacing = 3,
    initializer = memoryRowInit,
  })
  list.scrollBox:SetPoint("TOPLEFT", inset, "TOPLEFT", 8, -8)
  list.scrollBox:SetPoint("BOTTOMRIGHT", newButton, "TOPRIGHT", -8, 8)

  local items = {}
  for _, memory in ipairs(memoryList()) do
    items[#items + 1] = { memory = memory }
  end
  list:SetItems(items)
end

-- Centre: candidate list -----------------------------------------------------

-- Initializer for a candidate row. Widgets.DataList recycles these Buttons, so
-- the children are built once (guarded by mmInit) and refreshed each call, and
-- the click/drag handlers read row.data live rather than closing over an index.
local function candidateRowInit(row, data)
  if not row.mmInit then
    row.mmInit = true
    Widgets.decorateRow(row)
    row:RegisterForDrag("LeftButton")

    row.handle = Widgets.DragDots(row)
    row.order = Widgets.Label(row, "GameFontNormalSmall", "")
    row.order:SetWidth(16)
    row.order:SetJustifyH("LEFT")
    row.order:SetTextColor(Widgets.unpackColor(colors.goldDim))
    row.tile = Widgets.Icon(row, 30)
    row.tile:SetBorder(1, colors.managed, 0.7)
    row.nameLabel = Widgets.Label(row, "GameFontHighlight", "")
    row.nameLabel:SetJustifyH("LEFT")
    row.nameLabel:SetWordWrap(false)
    row.condLabel = Widgets.Label(row, "GameFontDisableSmall", "")
    row.condLabel:SetTextColor(Widgets.unpackColor(colors.goldDim))

    row:SetScript("OnClick", function(self, mouseButton)
      local ref = selectedRef()
      local index = self.data and self.data.index
      if not ref or not index then
        return
      end
      if mouseButton == "RightButton" then
        if ref.source ~= "predefined" then
          local ok, err = MM.DB:RemoveCandidate(ref.id, index)
          if not ok then
            MM:Warn(err)
          end
          refresh()
        end
        return
      end
      -- Clicking the selected candidate again clears the selection, returning the
      -- rule panel to the memory-level (macro) settings.
      selectCandidate(MM.ui.state.candidate == index and nil or index)
    end)

    -- Drag a candidate onto another to reorder (the target is whichever row the
    -- cursor is over on release).
    row:SetScript("OnDragStart", function(self)
      local ref = selectedRef()
      if not self.data or not ref or ref.source == "predefined" then
        return
      end
      self:SetAlpha(0.5)
      MemoriesTab._dragCandidate = self.data.index
    end)
    row:SetScript("OnDragStop", function(self)
      self:SetAlpha(1)
      local from = MemoriesTab._dragCandidate
      MemoriesTab._dragCandidate = nil
      local ref = selectedRef()
      if not from or not ref or not MemoriesTab.candidateList then
        return
      end
      local target
      MemoriesTab.candidateList:ForEachFrame(function(frame)
        if frame.data and frame:IsMouseOver() then
          target = frame.data.index
        end
      end)
      if target and target ~= from then
        MM.DB:MoveCandidate(ref.id, from, target)
        refresh()
      end
    end)

    -- Tooltip on the icon only, not the whole row.
    Widgets.AttachIconTooltip(row.tile, showCandidateTooltip)
  end

  row.data = data
  local index, candidate = data.index, data.candidate
  local locked = (selectedRef() or {}).source == "predefined"

  row:SetSelected(index == MM.ui.state.candidate)

  row.order:SetText(tostring(index))
  row.order:ClearAllPoints()
  if locked then
    -- Predefined memories can't be reordered, so there's no drag handle.
    row.handle:Hide()
    row.order:SetPoint("LEFT", row, "LEFT", 12, 0)
  else
    row.handle:ClearAllPoints()
    row.handle:SetPoint("LEFT", row, "LEFT", 10, 0)
    row.handle:Show()
    row.order:SetPoint("LEFT", row.handle, "RIGHT", 8, 0)
  end

  local name, icon = candidateInfo(candidate)
  row.tile:ClearAllPoints()
  row.tile:SetPoint("LEFT", row.order, "RIGHT", 8, 0)
  if icon then
    row.tile:SetTextureImage(icon)
  else
    row.tile:SetGlyph("?", colors.faint)
  end

  row.nameLabel:SetText(name)
  row.nameLabel:ClearAllPoints()
  row.nameLabel:SetPoint("LEFT", row.tile, "RIGHT", 9, 0)

  local classes = candidate.conditions and candidate.conditions.classes
  if classes and #classes > 0 then
    local chips = {}
    for _, token in ipairs(classes) do
      chips[#chips + 1] = prettyClass(token)
    end
    row.condLabel:SetText(table.concat(chips, " / "))
    row.condLabel:ClearAllPoints()
    row.condLabel:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    row.condLabel:Show()
    row.nameLabel:SetPoint("RIGHT", row.condLabel, "LEFT", -6, 0)
  else
    row.condLabel:Hide()
    row.nameLabel:SetPoint("RIGHT", row, "RIGHT", -8, 0)
  end
end

function MemoriesTab:BuildCenter(parent, ref, memory)
  local center = CreateFrame("Frame", nil, parent)
  center:SetPoint("TOPLEFT", parent, "TOPLEFT", RAIL_WIDTH + 14, -14)
  center:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -(RULE_WIDTH + 14), 10)

  local title = Widgets.Title(center, memory and memory.name or "\226\128\148")
  title:SetPoint("TOPLEFT", center, "TOPLEFT", 12, -2)

  local locked = ref.source == "predefined"
  if locked then
    local tag = Widgets.Label(center, "GameFontDisableSmall", "PREDEFINED \194\183 read-only")
    tag:SetPoint("LEFT", title, "RIGHT", 12, 0)

    local clone = Widgets.Button(center, "Clone to edit", 110, function()
      cloneMemory(ref)
    end)
    clone:SetPoint("TOPRIGHT", center, "TOPRIGHT", -12, -2)
  else
    local clone = Widgets.Button(center, "Clone", 60, function()
      cloneMemory(ref)
    end)
    clone:SetPoint("TOPRIGHT", center, "TOPRIGHT", -12, -2)

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
  chip:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -14)
  chip:SetPoint("RIGHT", center, "RIGHT", -12, 0)
  chip:SetJustifyH("LEFT")

  local hintText = locked and "Priority order \194\183 the first usable action wins"
    or "Drag here to add \194\183 drag a row to reorder \194\183 right-click to remove \194\183 first usable wins"
  local hint = Widgets.Hint(center, hintText)
  hint:SetPoint("TOPLEFT", chip, "BOTTOMLEFT", 0, -10)

  -- Candidate rows — a retained DataProvider list, so selecting/removing a
  -- candidate no longer snaps the scroll to the top and the rows aren't leaked.
  local candidates = memory and memory.candidates or {}
  local list = Widgets.DataList(center, "memories.candidates", {
    extent = 40,
    spacing = 3,
    initializer = candidateRowInit,
  })
  MemoriesTab.candidateList = list
  list.scrollBox:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -8)
  list.scrollBox:SetPoint("BOTTOMRIGHT", center, "BOTTOMRIGHT", -30, 4)

  local items = {}
  for index, candidate in ipairs(candidates) do
    items[#items + 1] = { index = index, candidate = candidate }
  end

  -- Keep the scroll offset while browsing one memory; reset to the top when the
  -- selected memory changes (its candidate list is unrelated).
  local memoryKey = ref.source .. ":" .. tostring(ref.id)
  list:SetItems(items, MemoriesTab._candidateKey == memoryKey)
  MemoriesTab._candidateKey = memoryKey

  if #candidates == 0 then
    local emptyText = locked and "This memory has no candidates."
      or "No candidates yet \226\128\148 drag a spell, item, macro, mount or equipment set here to add one."
    local note = Widgets.Hint(center, emptyText)
    note:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -16)
    note:SetPoint("RIGHT", center, "RIGHT", -12, 0)
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

-- Right: condition editor ------------------------------------------------------

-- The rule panel when no candidate is selected: how the memory is executed.
-- Custom memories can switch to macro mode and edit the template; predefined
-- memories show a read-only note.
function MemoriesTab:BuildMacroPanel(inset, memory)
  local ref = selectedRef()
  local editable = ref and ref.source == "custom"

  local header = Widgets.SectionHeader(inset, "Execution")
  header:SetPoint("TOPLEFT", inset, "TOPLEFT", 16, -16)

  if not editable then
    local asMacro = memory and MM.Macros.EffectiveMode(memory) == "macro"
    local note = Widgets.Hint(
      inset,
      asMacro and "This predefined memory is rendered as a macro. Clone it to change the body."
        or "Predefined memories place the resolved spell or item directly. Clone this memory to render it as a macro instead."
    )
    note:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -10)
    note:SetPoint("RIGHT", inset, "RIGHT", -14, 0)
    note:SetJustifyH("LEFT")

    if asMacro then
      local body = Widgets.Label(inset, "GameFontDisableSmall", memory.macroTemplate or MM.MACRO_TEMPLATE_DEFAULT)
      body:SetPoint("TOPLEFT", note, "BOTTOMLEFT", 0, -10)
      body:SetPoint("RIGHT", inset, "RIGHT", -14, 0)
      body:SetJustifyH("LEFT")
    end
    return
  end

  local isMacro = memory and memory.mode == "macro"

  local box = Widgets.Checkbox(inset, isMacro, function(button)
    MM.DB:SetMemoryMode(ref.id, button:GetChecked() and "macro" or "normal")
    refresh()
  end)
  box:SetPoint("TOPLEFT", header, "BOTTOMLEFT", -4, -6)

  local boxLabel = Widgets.Label(inset, "GameFontHighlight", "Render as a macro")
  boxLabel:SetPoint("LEFT", box, "RIGHT", 2, 0)

  local intro = Widgets.Hint(
    inset,
    "Put a generated macro on the bar instead of the raw action, so you can add mouseover, focus and other conditions while the memory still resolves the right spell or item for this character."
  )
  intro:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 4, -6)
  intro:SetPoint("RIGHT", inset, "RIGHT", -14, 0)
  intro:SetJustifyH("LEFT")

  if not isMacro then
    return
  end

  local anchor = intro
  if not MM.Macros.CandidatesCompatible(memory) then
    local badge = Widgets.Label(
      inset,
      "GameFontHighlightSmall",
      "Macro mode supports spell, item, toy and mount candidates only.",
      colors.warn
    )
    badge:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", 0, -10)
    badge:SetPoint("RIGHT", inset, "RIGHT", -14, 0)
    badge:SetJustifyH("LEFT")
    anchor = badge
  end

  local example = Widgets.Hint(inset, "Use %name% for the resolved action. Example:")
  example:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -12)
  example:SetPoint("RIGHT", inset, "RIGHT", -14, 0)
  example:SetJustifyH("LEFT")

  local sample =
    Widgets.Label(inset, "GameFontDisableSmall", "#showtooltip\n/use [@mouseover,help][@focus,help][] %name%")
  sample:SetPoint("TOPLEFT", example, "BOTTOMLEFT", 0, -4)
  sample:SetJustifyH("LEFT")

  local bodyHeader = Widgets.SectionHeader(inset, "Macro Body")
  bodyHeader:SetPoint("TOPLEFT", sample, "BOTTOMLEFT", 0, -12)

  -- Live count of the longest body any candidate would produce (the macro grows
  -- when %name% is filled in). Turns red past the 255 cap, where macro mode goes
  -- inactive and the memory falls back to placing the action directly.
  local count = Widgets.Label(inset, "GameFontHighlightSmall", "", colors.muted)

  local function updateCount(template)
    local worst = MM.Macros.WorstCaseLength(memory, template)
    local over = worst > MM.MACRO_BODY_LIMIT
    local text = string.format("Longest result: %d / %d characters", worst, MM.MACRO_BODY_LIMIT)
    if over then
      text = text .. " \226\128\148 over the macro limit, macro mode is inactive until it fits."
    end
    count:SetText(text)
    count:SetTextColor(Widgets.unpackColor(over and colors.danger or colors.muted))
  end

  local input = Widgets.MultiLineInput(
    inset,
    memory.macroTemplate or MM.MACRO_TEMPLATE_DEFAULT,
    MM.MACRO_TEMPLATE_LIMIT,
    function(text)
      MM.DB:SetMemoryTemplate(ref.id, text)
      updateCount(text)
    end
  )
  input:SetPoint("TOPLEFT", bodyHeader, "BOTTOMLEFT", 0, -6)
  input:SetPoint("RIGHT", inset, "RIGHT", -16, 0)
  input:SetHeight(84)

  count:SetPoint("TOPLEFT", input, "BOTTOMLEFT", 0, -8)
  count:SetPoint("RIGHT", inset, "RIGHT", -14, 0)
  count:SetJustifyH("LEFT")
  updateCount(memory.macroTemplate or MM.MACRO_TEMPLATE_DEFAULT)
end

function MemoriesTab:BuildRule(parent, memory)
  local inset = CreateFrame("Frame", nil, parent)
  inset:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
  inset:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
  inset:SetWidth(RULE_WIDTH + 2)

  local candidates = memory and memory.candidates or {}
  local candidate = MM.ui.state.candidate and candidates[MM.ui.state.candidate]
  if not candidate then
    -- No candidate selected: the rule panel edits the memory itself (macro mode).
    self:BuildMacroPanel(inset, memory)
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
  Widgets.AttachIconTooltip(tile, function()
    Widgets.SetActionTooltip(tile, candidate.type, candidate.id, name)
  end)

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

  -- Scrollable so an all-expanded editor doesn't overflow the panel.
  local scrollBox, content = Widgets.ScrollList(inset, "memories.conditions")
  scrollBox:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -14)
  scrollBox:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -20, 12)
  local editor = MM.ui.ConditionsEditor:Build(content, candidate.conditions or {}, editable, function()
    refresh()
  end)
  editor:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
  editor:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, 0)
  content:SetHeight(editor:GetHeight())
end

-- Assembly -------------------------------------------------------------------

function MemoriesTab:BuildContent(parent)
  local ref = selectedRef()
  if not ref then
    local note = Widgets.Label(parent, "GameFontHighlight", "No memories available.")
    note:SetPoint("CENTER")
    return
  end

  local memory = MM.DB:ResolveMemory(ref)
  local candidateCount = memory and memory.candidates and #memory.candidates or 0
  if MM.ui.state.candidate and MM.ui.state.candidate > candidateCount then
    MM.ui.state.candidate = nil
  end

  self:BuildRail(parent)
  self:BuildCenter(parent, ref, memory)
  self:BuildRule(parent, memory)

  local leftGroove = Widgets.VGroove(parent)
  leftGroove:SetPoint("TOPLEFT", parent, "TOPLEFT", RAIL_WIDTH + 6, -6)
  leftGroove:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", RAIL_WIDTH + 6, 6)

  local rightGroove = Widgets.VGroove(parent)
  rightGroove:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -(RULE_WIDTH + 6), -6)
  rightGroove:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -(RULE_WIDTH + 6), 6)
end

function MemoriesTab:Build(parent)
  self.parent = parent
  self:Refresh()
end

function MemoriesTab:Refresh()
  if not self.parent then
    return
  end
  Widgets.ClearChildren(self.parent)
  self:BuildContent(self.parent)
end
