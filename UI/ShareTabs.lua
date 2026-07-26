local ADDON_NAME, MM = ...
local L = MM.L

-- The Export and Import tabs. Both share the same four-panel layout: an intro
-- column that holds the controls and the sharing string, then one column each
-- for Layers, Dynamic Actions, and the macros that ride along. Export packs a
-- selection of the active profile; import decodes a pasted string and creates
-- everything as new entities in the current or a new profile.
local ExportTab = {}
local ImportTab = {}
MM.ui.ExportTab = ExportTab
MM.ui.ImportTab = ImportTab

local Widgets = MM.ui.Widgets
local colors = Widgets.colors

-- Panel geometry: the content width is divided evenly into four columns, with
-- a groove (and a gap on each side of it) between neighbours. Every column owns
-- its own scrollbar space, so nothing pokes past the last column. INTRO_GAP
-- keeps the intro text clear of the first groove.
local PAD = 16
local GROOVE_GAP = 12
local SCROLLBAR_INSET = 20
local INTRO_GAP = 16

-- Shared row for the three lists (recycled by Widgets.DataList): a checkbox
-- item, or a plain read-only line (macros). Locked items are the custom dynamic
-- actions a checked layer references — they travel with it, so they can't be
-- unchecked. Clicking anywhere on a row toggles it.
local function rowInit(row, data)
  if not row.mmInit then
    row.mmInit = true

    -- Relation highlight: lit on rows the hovered row references or is
    -- referenced by (layer <-> dynamic action / macro).
    row.relHl = row:CreateTexture(nil, "BACKGROUND")
    row.relHl:SetAllPoints()
    row.relHl:SetColorTexture(Widgets.unpackColor(colors.gold, 0.12))
    row.relHl:Hide()

    row.check = Widgets.Checkbox(row, false)
    row.check:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.check:SetScript("OnClick", function(self)
      local d = row.data
      if d and d.onToggle and not d.locked then
        d.onToggle(self:GetChecked() and true or false)
      elseif d then
        self:SetChecked(d.checked)
      end
    end)

    row:SetScript("OnEnter", function(self)
      local d = self.data
      if d and d.onHover then
        d.onHover(d)
      end
    end)
    row:SetScript("OnLeave", function(self)
      local d = self.data
      if d and d.onHover then
        d.onHover(nil)
      end
    end)

    row.label = Widgets.Label(row, "GameFontHighlight", "")
    row.label:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.label:SetJustifyH("LEFT")
    row.label:SetWordWrap(false)

    row:SetScript("OnClick", function(self)
      local d = self.data
      if not d or d.plain or d.locked or not d.onToggle then
        return
      end
      local checked = not self.check:GetChecked()
      self.check:SetChecked(checked)
      d.onToggle(checked)
    end)
  end

  row.data = data
  row.relHl:Hide()
  row.label:ClearAllPoints()
  row.label:SetPoint("RIGHT", row, "RIGHT", -4, 0)
  if data.plain then
    row.check:Hide()
    row.label:SetPoint("LEFT", row, "LEFT", 4, 0)
  else
    row.check:Show()
    row.check:SetChecked(data.checked)
    row.check:SetEnabled(not data.locked)
    row.check:SetAlpha(data.locked and 0.5 or 1)
    row.label:SetPoint("LEFT", row.check, "RIGHT", 4, 0)
  end
  row.label:SetText(data.label)
  row.label:SetTextColor(Widgets.unpackColor(data.locked and colors.muted or colors.parchment))
end

-- Small invert-selection icon sitting at the right edge of a column header.
-- The tab assigns `onInvert`; it flips every non-locked checkbox in the column.
-- `hint` is an optional extra tooltip line (the actions column's locked note).
local function invertLink(host, hint)
  local button = CreateFrame("Button", nil, host)
  button:SetSize(16, 16)
  local icon = button:CreateTexture(nil, "ARTWORK")
  icon:SetSize(13, 13)
  icon:SetPoint("CENTER")
  icon:SetTexture(Widgets.ICON.invert)
  icon:SetAlpha(0.65)
  button:SetScript("OnEnter", function(self)
    icon:SetAlpha(1)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(L["Invert selection"])
    GameTooltip:AddLine(L["Flips every checkbox in this column."] .. (hint and (" " .. hint) or ""), 1, 1, 1, true)
    GameTooltip:Show()
  end)
  button:SetScript("OnLeave", function()
    icon:SetAlpha(0.65)
    GameTooltip:Hide()
  end)
  button:SetScript("OnClick", function(self)
    if self.onInvert then
      self.onInvert()
    end
  end)
  return button
end

-- Build the shared skeleton into `parent`: intro column plus three groove-split
-- list columns. Returns a table of hosts the tab fills in.
local function buildPanels(parent, key)
  local panels = {}

  -- Divide the actual content width into four equal columns; the space between
  -- neighbours is gap + groove + gap.
  -- 980 is both the fallback for an unresolved layout (GetWidth() -> 0) and
  -- the effective minimum; the window is fixed-size, so it never legitimately
  -- resolves below that.
  local total = math.max(parent:GetWidth() or 0, 980)
  -- Full PAD on the left; the right pad matches the gap a scrollbar has to its
  -- neighbouring groove, so the last column's bar gets the same treatment.
  local between = GROOVE_GAP * 2 + 2
  local rightPad = GROOVE_GAP
  local columnWidth = math.floor((total - PAD - rightPad - between * 3) / 4)
  panels.columnWidth = columnWidth

  panels.intro = CreateFrame("Frame", nil, parent)
  panels.intro:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD, -14)
  panels.intro:SetPoint("BOTTOM", parent, "BOTTOM", 0, 8)
  panels.intro:SetWidth(columnWidth)

  local columns = { { "layers", L["Layers"] }, { "actions", L["Dynamic Actions"] }, { "macros", L["Macros"] } }
  local left = PAD + columnWidth
  panels.columnFrames = {}
  for index, column in ipairs(columns) do
    -- Only one groove, next to the intro column; the three lists separate
    -- themselves through their headers and whitespace.
    if index == 1 then
      local groove = Widgets.VGroove(parent)
      groove:SetPoint("TOP", parent, "TOP", 0, -6)
      groove:SetPoint("BOTTOM", parent, "BOTTOM", 0, 6)
      groove:SetPoint("LEFT", parent, "LEFT", left + GROOVE_GAP, 0)
    end

    local host = CreateFrame("Frame", nil, parent)
    host:SetPoint("TOPLEFT", parent, "TOPLEFT", left + between, -14)
    host:SetPoint("BOTTOM", parent, "BOTTOM", 0, 8)
    host:SetWidth(columnWidth)

    local header = Widgets.SectionHeader(host, column[2])
    header:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
    header.baseTitle = column[2]
    panels[column[1] .. "Header"] = header

    -- Macros only ride along; there is no selection to invert there.
    if column[1] ~= "macros" then
      local hint = column[1] == "actions" and L["Items a selected layer needs stay included."] or nil
      local link = invertLink(host, hint)
      link:SetPoint("RIGHT", host, "TOPRIGHT", -SCROLLBAR_INSET, -5)
      panels[column[1] .. "Invert"] = link
    end

    local list = Widgets.DataList(host, key .. "." .. column[1], {
      extent = 24,
      spacing = 2,
      initializer = rowInit,
    })
    -- The scrollbar renders in the reserved right inset, so it stays within the
    -- column; pushed a little further right than DataList's default so it clears
    -- the row labels.
    list.scrollBox:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -8)
    list.scrollBox:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -SCROLLBAR_INSET, 0)
    list.scrollBar:ClearAllPoints()
    list.scrollBar:SetPoint("TOPLEFT", list.scrollBox, "TOPRIGHT", 10, 0)
    list.scrollBar:SetPoint("BOTTOMLEFT", list.scrollBox, "BOTTOMRIGHT", 10, 0)

    panels[column[1] .. "Host"] = host
    panels[column[1] .. "List"] = list
    panels.columnFrames[#panels.columnFrames + 1] = host
    left = left + between + columnWidth
  end

  -- Empty state replacing the three columns (mirrors the Layers tab's): a
  -- centered heading + body over the column area, right of the intro.
  panels.empty = CreateFrame("Frame", nil, parent)
  panels.empty:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD + columnWidth, 0)
  panels.empty:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
  panels.empty:Hide()

  panels.empty.heading = Widgets.Label(panels.empty, "GameFontNormalLarge", "", colors.parchment)
  panels.empty.heading:SetPoint("CENTER", panels.empty, "CENTER", 0, 30)

  panels.empty.body = Widgets.Label(panels.empty, "GameFontHighlightSmall", "")
  panels.empty.body:SetPoint("TOP", panels.empty.heading, "BOTTOM", 0, -10)
  panels.empty.body:SetWidth(360)
  panels.empty.body:SetJustifyH("CENTER")
  panels.empty.body:SetTextColor(Widgets.unpackColor(colors.faint))

  -- Pass a heading + body to swap the columns for the message; nil restores them.
  function panels.SetEmpty(heading, body)
    local isEmpty = heading ~= nil
    for _, frame in ipairs(panels.columnFrames) do
      frame:SetShown(not isEmpty)
    end
    panels.empty:SetShown(isEmpty)
    if isEmpty then
      panels.empty.heading:SetText(heading)
      panels.empty.body:SetText(body or "")
    end
  end

  return panels
end

-- A macro's identity across the share tabs: the body key used for dedupe,
-- sorting and the hover relations.
local function macroKey(assignment)
  return assignment.bodyHash or assignment.body or assignment.nameHint or "?"
end

-- Relation maps for the hover cross-highlight, in both directions. A layer
-- relates to the custom dynamic actions it references and to its macros — both
-- the ones bound directly in its slots and, transitively, the macro candidates
-- of its dynamic actions (those travel with the layer too). A dynamic action
-- relates to its macro candidates. Macros are identified by their body key.
local function buildRelations(layersByKey, actionsByKey)
  local rel = { layers = {}, actions = {}, macros = {} }
  local function entry(kind, key)
    rel[kind][key] = rel[kind][key] or { layers = {}, actions = {}, macros = {} }
    return rel[kind][key]
  end

  for daKey, action in pairs(actionsByKey or {}) do
    for _, candidate in ipairs(action.candidates or {}) do
      if type(candidate) == "table" and candidate.type == "macro" then
        local body = macroKey(candidate)
        entry("actions", daKey).macros[body] = true
        entry("macros", body).actions[daKey] = true
      end
    end
  end

  for layerKey, layer in pairs(layersByKey) do
    local carried = entry("layers", layerKey)
    for _, assignment in pairs(layer.slots or {}) do
      if type(assignment) == "table" then
        if assignment.type == "dynamicaction" and assignment.source == "custom" then
          carried.actions[assignment.id] = true
          entry("actions", assignment.id).layers[layerKey] = true
          for body in pairs(entry("actions", assignment.id).macros) do
            carried.macros[body] = true
            entry("macros", body).layers[layerKey] = true
          end
        elseif assignment.type == "macro" then
          local body = macroKey(assignment)
          carried.macros[body] = true
          entry("macros", body).layers[layerKey] = true
        end
      end
    end
  end
  return rel
end

-- One hover handler per tab: light up every row related to the hovered item
-- (plus the item's own row) across all three lists, or clear on nil. Applied
-- after a short hover-intent delay — crossing rows quickly neither flickers
-- highlights on nor blinks them off between two related rows.
-- Just enough to swallow row-crossing flicker without reading as lag.
local HOVER_DELAY = 0.04

local function hoverHandler(panels)
  local lists = { layers = panels.layersList, actions = panels.actionsList, macros = panels.macrosList }
  local pending, current

  local function apply(item)
    local related = item and item.hoverRel
    for column, list in pairs(lists) do
      local wanted = related and related[column]
      list:ForEachFrame(function(row)
        local d = row.data
        local hit = (d == item) or (wanted and d and d.selfKey and wanted[d.selfKey])
        row.relHl:SetShown(hit and true or false)
      end)
    end
  end

  return function(item)
    pending = item
    C_Timer.After(HOVER_DELAY, function()
      -- Only the latest hover wins; superseded timers do nothing.
      if pending ~= item or current == item then
        return
      end
      current = item
      apply(item)
    end)
  end
end

-- Column header with a "(selected / total)" counter; a single count for the
-- macros column (nothing there is individually selectable), plain title when
-- there is nothing to count.
local function setHeader(header, selected, total)
  local title = header.baseTitle
  if selected and total then
    title = string.format("%s (%d / %d)", title, selected, total)
  elseif selected then
    title = string.format("%s (%d)", title, selected)
  end
  header:SetText(title)
end

-- The custom dynamic action keys required by the included layers.
local function requiredActions(layersByKey, isIncluded)
  local required = {}
  for key, layer in pairs(layersByKey) do
    if isIncluded(key) then
      MM.Share:LayerDependencies(layer, required)
    end
  end
  return required
end

-- Flip each key's exclusion, skipping locked ones. A locked row keeps whatever
-- state is stored underneath — the lock only overrides it while it lasts.
local function invertExcluded(excluded, keys, locked)
  for key in pairs(keys) do
    if not locked[key] then
      excluded[key] = (not excluded[key]) or nil
    end
  end
end

-- The captured macros riding along in the selection (deduped by body): macros
-- bound in the included layers' slots, plus the macro candidates of every
-- included custom dynamic action. Also reports whether anything references an
-- equipment set. Each macro carries its scope so character macros are
-- recognizable.
local function macroItems(layersByKey, layerIncluded, actionsByKey, actionIncluded)
  local seen, macros, equipmentSets = {}, {}, false
  local function collect(assignment)
    if type(assignment) ~= "table" then
      return
    end
    if assignment.type == "macro" then
      local body = macroKey(assignment)
      if not seen[body] then
        seen[body] = true
        macros[#macros + 1] =
          { name = assignment.nameHint or L["Unnamed macro"], scope = assignment.scope, body = body }
      end
    elseif assignment.type == "equipmentset" then
      equipmentSets = true
    end
  end

  for key, layer in pairs(layersByKey) do
    if layerIncluded(key) then
      for _, assignment in pairs(layer.slots or {}) do
        collect(assignment)
      end
    end
  end
  for key, action in pairs(actionsByKey or {}) do
    if actionIncluded(key) then
      for _, candidate in ipairs(action.candidates or {}) do
        collect(candidate)
      end
    end
  end
  -- Same-named macros tie-break on the body key, so the order is stable no
  -- matter which layers are toggled or in what order they were walked.
  table.sort(macros, function(left, right)
    if left.name ~= right.name then
      return left.name < right.name
    end
    return tostring(left.body) < tostring(right.body)
  end)

  local items = {}
  for _, macro in ipairs(macros) do
    local suffix = macro.scope == "character" and ("  |cff8a8474" .. L["(character)"] .. "|r") or ""
    items[#items + 1] = { plain = true, label = macro.name .. suffix, selfKey = macro.body }
  end
  return items, equipmentSets
end

-- Attach the hover cross-highlight to a refreshed item list.
local function attachHover(items, relByKey, onHover)
  for _, item in ipairs(items) do
    item.hoverRel = item.selfKey and relByKey[item.selfKey] or nil
    item.onHover = onHover
  end
end

local function sortedActions(map)
  local actions = {}
  for key, action in pairs(map or {}) do
    actions[#actions + 1] = { key = key, name = action.name or key }
  end
  table.sort(actions, function(left, right)
    if left.name ~= right.name then
      return left.name < right.name
    end
    return left.key < right.key
  end)
  return actions
end

-- Centre a button's label+icon block (the stock template centers only the text).
local function addButtonIcon(button, texture)
  local text = button:GetFontString()
  text:ClearAllPoints()
  text:SetPoint("CENTER", button, "CENTER", 8, 0)
  local icon = button:CreateTexture(nil, "ARTWORK")
  icon:SetSize(12, 12)
  icon:SetTexture(texture)
  icon:SetPoint("RIGHT", text, "LEFT", -4, 0)
end

-- Export ----------------------------------------------------------------------

-- Selection is stored as exclusions, so everything (including entities created
-- after the tab was first opened) defaults to included. Reset when the active
-- profile changes.
local exportState

local function ensureExportState()
  local profileId = MM.DB:GetActiveProfileId()
  if not exportState or exportState.profileId ~= profileId then
    exportState = { profileId = profileId, excludedLayers = {}, excludedActions = {}, excludeSettings = false }
  end
  return exportState
end

local function exportSelection(profile, state)
  local selection = { settings = not state.excludeSettings, layers = {}, dynamicActions = {} }
  for id in pairs(profile.layers or {}) do
    if not state.excludedLayers[id] then
      selection.layers[id] = true
    end
  end
  for key in pairs(profile.dynamicActions or {}) do
    if not state.excludedActions[key] then
      selection.dynamicActions[key] = true
    end
  end
  return selection
end

function ExportTab:Refresh()
  local panels = self.panels
  if not panels then
    return
  end

  local state = ensureExportState()
  local profile = MM.DB:GetProfile(state.profileId)
  if not profile then
    return
  end

  self.settingsCheck:SetChecked(not state.excludeSettings)

  -- Nothing to share yet: swap the columns for a pointer to the other tabs.
  if not next(profile.layers or {}) and not next(profile.dynamicActions or {}) then
    panels.SetEmpty(
      L["Nothing to export yet"],
      L["This profile has no Layers or Dynamic Actions. Create some first — or import someone else's — then come back to share them."]
    )
    self.exportText = ""
    self.output.EditBox:SetText("")
    self.output:Hide()
    self.outputHeader:Hide()
    self.outputHint:Hide()
    self.note:SetText("")
    return
  end
  panels.SetEmpty(nil)

  local layersByKey = profile.layers or {}
  local included = function(id)
    return not state.excludedLayers[id]
  end
  local required = requiredActions(layersByKey, included)
  local actionsByKey = profile.dynamicActions or {}
  local actionIncluded = function(key)
    return required[key] or not state.excludedActions[key]
  end
  local rel = buildRelations(layersByKey, actionsByKey)
  self.onHover = self.onHover or hoverHandler(panels)

  local layerItems, selectedLayers = {}, 0
  for _, entry in ipairs(MM.DB:GetProfileLayers(state.profileId)) do
    local checked = not state.excludedLayers[entry.id]
    if checked then
      selectedLayers = selectedLayers + 1
    end
    layerItems[#layerItems + 1] = {
      label = entry.name,
      selfKey = entry.id,
      checked = checked,
      onToggle = function(include)
        state.excludedLayers[entry.id] = (not include) or nil
        ExportTab:Refresh()
      end,
    }
  end
  attachHover(layerItems, rel.layers, self.onHover)
  panels.layersList:SetItems(layerItems)
  setHeader(panels.layersHeader, selectedLayers, #layerItems)

  local actionItems, selectedActions = {}, 0
  for _, action in ipairs(sortedActions(profile.dynamicActions)) do
    local locked = required[action.key] and true or false
    local checked = locked or not state.excludedActions[action.key]
    if checked then
      selectedActions = selectedActions + 1
    end
    actionItems[#actionItems + 1] = {
      label = action.name,
      selfKey = action.key,
      checked = checked,
      locked = locked,
      onToggle = function(include)
        state.excludedActions[action.key] = (not include) or nil
        ExportTab:Refresh()
      end,
    }
  end
  attachHover(actionItems, rel.actions, self.onHover)
  panels.actionsList:SetItems(actionItems)
  setHeader(panels.actionsHeader, selectedActions, #actionItems)

  local macros, equipmentSets = macroItems(layersByKey, included, actionsByKey, actionIncluded)
  attachHover(macros, rel.macros, self.onHover)
  panels.macrosList:SetItems(macros)
  -- Total = the macros that would ride along with everything selected.
  local everything = function()
    return true
  end
  setHeader(panels.macrosHeader, #macros, #macroItems(layersByKey, everything, actionsByKey, everything))
  self.note:SetText(equipmentSets and L["Equipment sets only resolve for users with same-named sets."] or "")

  -- The whole "Share This" block only exists while there is a string to copy;
  -- an empty selection hides it rather than showing an empty box.
  local package = MM.Share:BuildPackage(state.profileId, exportSelection(profile, state))
  local text = package and MM.Share:Encode(package)
  self.exportText = text or ""
  self.output.EditBox:SetText(text or "")
  self.output:SetShown(text ~= nil)
  self.outputHeader:SetShown(text ~= nil)
  self.outputHint:SetShown(text ~= nil)
  self.outputHint:SetText(L["Click the string, then press Ctrl+C."])
end

function ExportTab:Build(parent)
  self.panels = self.panels or buildPanels(parent, "share.export")
  local intro = self.panels.intro

  if not self.built then
    self.built = true

    self.panels.layersInvert.onInvert = function()
      local state = ensureExportState()
      local profile = MM.DB:GetProfile(state.profileId)
      if profile then
        invertExcluded(state.excludedLayers, profile.layers or {}, {})
        ExportTab:Refresh()
      end
    end
    self.panels.actionsInvert.onInvert = function()
      local state = ensureExportState()
      local profile = MM.DB:GetProfile(state.profileId)
      if profile then
        local required = requiredActions(profile.layers or {}, function(id)
          return not state.excludedLayers[id]
        end)
        invertExcluded(state.excludedActions, profile.dynamicActions or {}, required)
        ExportTab:Refresh()
      end
    end

    local blurb = Widgets.Label(intro, "GameFontHighlight", L["Choose what to include in your export."])
    blurb:SetPoint("TOPLEFT", intro, "TOPLEFT", 0, 0)
    blurb:SetPoint("RIGHT", intro, "RIGHT", -INTRO_GAP, 0)
    blurb:SetJustifyH("LEFT")

    local blurb2 = Widgets.Label(
      intro,
      "GameFontHighlight",
      L["Custom Dynamic Actions a selected Layer uses come along automatically, as do the macros in its slots."]
    )
    blurb2:SetPoint("TOPLEFT", blurb, "BOTTOMLEFT", 0, -8)
    blurb2:SetPoint("RIGHT", intro, "RIGHT", -INTRO_GAP, 0)
    blurb2:SetJustifyH("LEFT")

    self.settingsCheck = Widgets.Checkbox(intro, true, function(check)
      local state = ensureExportState()
      state.excludeSettings = not check:GetChecked()
      ExportTab:Refresh()
    end)
    self.settingsCheck:SetPoint("TOPLEFT", blurb2, "BOTTOMLEFT", -4, -22)
    local settingsLabel = Widgets.Label(intro, "GameFontHighlight", L["Include profile settings"], colors.parchment)
    settingsLabel:SetPoint("LEFT", self.settingsCheck, "RIGHT", 4, 0)

    -- Conditional equipment-set note (they only resolve by name on the other side).
    self.note = Widgets.Hint(intro, "")
    self.note:SetPoint("TOPLEFT", self.settingsCheck, "BOTTOMLEFT", 4, -14)
    self.note:SetPoint("RIGHT", intro, "RIGHT", -INTRO_GAP, 0)
    self.note:SetJustifyH("LEFT")

    -- The string block sits at the bottom of the intro column, built bottom-up.
    self.outputHint = Widgets.Hint(intro, "")
    self.outputHint:SetPoint("BOTTOMLEFT", intro, "BOTTOMLEFT", 0, 0)
    self.outputHint:SetPoint("BOTTOMRIGHT", intro, "BOTTOMRIGHT", -INTRO_GAP, 0)
    self.outputHint:SetJustifyH("LEFT")

    self.output = Widgets.MultiLineInput(intro, "", 0, nil)
    self.output:SetPoint("BOTTOMLEFT", self.outputHint, "TOPLEFT", 0, 8)
    self.output:SetPoint("BOTTOMRIGHT", self.outputHint, "TOPRIGHT", 0, 8)
    self.output:SetHeight(56)

    self.outputHeader = Widgets.SectionHeader(intro, L["Share This"])
    self.outputHeader:SetPoint("BOTTOMLEFT", self.output, "TOPLEFT", 0, 8)

    -- Output, not input: edits snap back and focusing selects everything so
    -- Ctrl+C is the only step left.
    local edit = self.output.EditBox
    edit:HookScript("OnTextChanged", function(editBox, userInput)
      if userInput then
        editBox:SetText(ExportTab.exportText or "")
        editBox:HighlightText()
      end
    end)
    edit:HookScript("OnEditFocusGained", function(editBox)
      editBox:HighlightText()
    end)
  end

  self:Refresh()
end

-- Import ----------------------------------------------------------------------

-- Exclusion-based like the export state; the package is whatever the paste box
-- currently decodes to.
local importState = { package = nil, reason = nil, excludedLayers = {}, excludedActions = {} }

function ImportTab:Refresh()
  local panels = self.panels
  if not panels then
    return
  end

  local package = importState.package
  local included = function(key)
    return not importState.excludedLayers[key]
  end

  if not package then
    -- Nothing decoded yet (or the paste is invalid): swap the columns for a
    -- message; the paste box on the left stays the call to action.
    if importState.reason then
      panels.SetEmpty(
        L["Not a valid sharing string"],
        L["The pasted text couldn't be read. Copy the whole string, from !MM: to the end, and paste it again."]
      )
    else
      panels.SetEmpty(
        L["Nothing to preview yet"],
        L["Paste a sharing string on the left to see the Layers, Dynamic Actions and macros it contains."]
      )
    end
    self.note:SetText("")
    self.summary:SetText(importState.reason and ("|cffd1a05f" .. L[importState.reason] .. "|r") or "")
    self.nameBox:SetShown(self.newProfileCheck:GetChecked())
    self.accept:SetEnabled(false)
    return
  end
  panels.SetEmpty(nil)

  local layersByKey = {}
  for _, entry in ipairs(package.layers) do
    layersByKey[entry.key] = entry.layer
  end
  local required = requiredActions(layersByKey, included)
  local actionsByKey = package.dynamicActions
  local actionIncluded = function(key)
    return required[key] or not importState.excludedActions[key]
  end
  local rel = buildRelations(layersByKey, actionsByKey)
  self.onHover = self.onHover or hoverHandler(panels)

  local layerItems, layerCount = {}, 0
  for _, entry in ipairs(package.layers) do
    local key = entry.key
    local checked = not importState.excludedLayers[key]
    if checked then
      layerCount = layerCount + 1
    end
    layerItems[#layerItems + 1] = {
      label = entry.layer.name or key,
      selfKey = key,
      checked = checked,
      onToggle = function(include)
        importState.excludedLayers[key] = (not include) or nil
        ImportTab:Refresh()
      end,
    }
  end
  attachHover(layerItems, rel.layers, self.onHover)
  panels.layersList:SetItems(layerItems)
  setHeader(panels.layersHeader, layerCount, #layerItems)

  local actionItems, actionCount = {}, 0
  for _, action in ipairs(sortedActions(package.dynamicActions)) do
    local locked = required[action.key] and true or false
    local checked = locked or not importState.excludedActions[action.key]
    if checked then
      actionCount = actionCount + 1
    end
    actionItems[#actionItems + 1] = {
      label = action.name,
      selfKey = action.key,
      checked = checked,
      locked = locked,
      onToggle = function(include)
        importState.excludedActions[action.key] = (not include) or nil
        ImportTab:Refresh()
      end,
    }
  end
  attachHover(actionItems, rel.actions, self.onHover)
  panels.actionsList:SetItems(actionItems)
  setHeader(panels.actionsHeader, actionCount, #actionItems)

  local macros, equipmentSets = macroItems(layersByKey, included, actionsByKey, actionIncluded)
  attachHover(macros, rel.macros, self.onHover)
  panels.macrosList:SetItems(macros)
  -- Total = the macros that would ride along with everything selected.
  local everything = function()
    return true
  end
  local allMacros = macroItems(layersByKey, everything, actionsByKey, everything)
  setHeader(panels.macrosHeader, #macros, #allMacros)
  self.note:SetText(equipmentSets and L["Equipment sets only resolve if you have same-named sets."] or "")

  -- The summary describes the string's content; the column headers carry the
  -- current selection.
  local totalLayers = #package.layers
  local totalActions = MM.Tables.Count(package.dynamicActions)
  local from = package.profileName and string.format(L[' from "%s"'], package.profileName) or ""
  self.summary:SetText(
    string.format(
      L["Sharing string%s contains %d %s, %d %s and %d %s."],
      from,
      totalLayers,
      totalLayers == 1 and L["Layer"] or L["Layers"],
      totalActions,
      totalActions == 1 and L["Dynamic Action"] or L["Dynamic Actions"],
      #allMacros,
      #allMacros == 1 and L["Macro"] or L["Macros"]
    )
  )

  self.nameBox:SetShown(self.newProfileCheck:GetChecked())
  self.accept:SetEnabled(layerCount + actionCount > 0 or self.newProfileCheck:GetChecked())
end

local function decodeInput(text)
  if string.gsub(text or "", "%s+", "") == "" then
    importState.package, importState.reason = nil, nil
  else
    local package, reason = MM.Share:Decode(text)
    importState.package, importState.reason = package, reason
    importState.excludedLayers, importState.excludedActions = {}, {}
  end
  ImportTab:Refresh()
end

local function importSelection(package)
  local selection = { layers = {}, dynamicActions = {} }
  for _, entry in ipairs(package.layers) do
    if not importState.excludedLayers[entry.key] then
      selection.layers[entry.key] = true
    end
  end
  for key in pairs(package.dynamicActions) do
    if not importState.excludedActions[key] then
      selection.dynamicActions[key] = true
    end
  end
  return selection
end

local function runImport()
  local package = importState.package
  if not package then
    return
  end

  local target
  if ImportTab.newProfileCheck:GetChecked() then
    target = { newProfile = ImportTab.nameBox:GetText() or "" }
  else
    target = { profileId = MM.DB:GetActiveProfileId() }
  end

  local result, reason = MM.Share:Import(package, importSelection(package), target)
  if not result then
    MM:Warn(L[reason or "import failed"])
    return
  end

  local profile = MM.DB:GetProfile(result.profileId)
  MM:Print(
    string.format(
      L["imported %d layers and %d dynamic actions into profile %s."],
      #result.layers,
      #result.dynamicActions,
      profile and profile.name or result.profileId
    )
  )
  ImportTab:SetString("")
  ImportTab.nameBox:SetText("")
  ImportTab.newProfileCheck:SetChecked(false)
  MM.UI:Refresh()
  MM.Events:PromptApplyIfChanged()
end

-- Programmatic paste (screenshot tour); triggers the same decode as typing.
function ImportTab:SetString(text)
  if self.input then
    self.input.EditBox:SetText(text or "")
  end
end

function ImportTab:Build(parent)
  self.panels = self.panels or buildPanels(parent, "share.import")
  local intro = self.panels.intro

  if not self.built then
    self.built = true

    self.panels.layersInvert.onInvert = function()
      local package = importState.package
      if package then
        local keys = {}
        for _, entry in ipairs(package.layers) do
          keys[entry.key] = true
        end
        invertExcluded(importState.excludedLayers, keys, {})
        ImportTab:Refresh()
      end
    end
    self.panels.actionsInvert.onInvert = function()
      local package = importState.package
      if package then
        local layersByKey = {}
        for _, entry in ipairs(package.layers) do
          layersByKey[entry.key] = entry.layer
        end
        local required = requiredActions(layersByKey, function(key)
          return not importState.excludedLayers[key]
        end)
        invertExcluded(importState.excludedActions, package.dynamicActions or {}, required)
        ImportTab:Refresh()
      end
    end

    local blurb =
      Widgets.Label(intro, "GameFontHighlight", L["Paste a sharing string, choose what to take, and import it."])
    blurb:SetPoint("TOPLEFT", intro, "TOPLEFT", 0, 0)
    blurb:SetPoint("RIGHT", intro, "RIGHT", -INTRO_GAP, 0)
    blurb:SetJustifyH("LEFT")

    local blurb2 = Widgets.Label(
      intro,
      "GameFontHighlight",
      L["Everything imported is created new — nothing of yours is overwritten. New entries are highlighted as imported until your next reload."]
    )
    blurb2:SetPoint("TOPLEFT", blurb, "BOTTOMLEFT", 0, -8)
    blurb2:SetPoint("RIGHT", intro, "RIGHT", -INTRO_GAP, 0)
    blurb2:SetJustifyH("LEFT")

    local inputHeader = Widgets.SectionHeader(intro, L["Paste Here"])
    inputHeader:SetPoint("TOPLEFT", blurb2, "BOTTOMLEFT", 0, -26)

    self.input = Widgets.MultiLineInput(intro, "", 0, decodeInput)
    self.input:SetPoint("TOPLEFT", inputHeader, "BOTTOMLEFT", 0, -8)
    self.input:SetPoint("RIGHT", intro, "RIGHT", -INTRO_GAP, 0)
    self.input:SetHeight(56)

    self.summary = Widgets.Hint(intro, "")
    self.summary:SetPoint("TOPLEFT", self.input, "BOTTOMLEFT", 0, -8)
    self.summary:SetPoint("RIGHT", intro, "RIGHT", -INTRO_GAP, 0)
    self.summary:SetJustifyH("LEFT")

    -- Conditional equipment-set note (they only resolve by name on this side).
    self.note = Widgets.Hint(intro, "")
    self.note:SetPoint("TOPLEFT", self.summary, "BOTTOMLEFT", 0, -10)
    self.note:SetPoint("RIGHT", intro, "RIGHT", -INTRO_GAP, 0)
    self.note:SetJustifyH("LEFT")

    -- Target controls and the Import button, bottom-up.
    self.accept = Widgets.Button(intro, L["Import"], 120, runImport)
    self.accept:SetPoint("BOTTOMLEFT", intro, "BOTTOMLEFT", 0, 0)
    addButtonIcon(self.accept, Widgets.ICON.import)

    self.nameBox = CreateFrame("EditBox", nil, intro, "InputBoxTemplate")
    self.nameBox:SetSize(self.panels.columnWidth - 8 - INTRO_GAP, 22)
    self.nameBox:SetPoint("BOTTOMLEFT", self.accept, "TOPLEFT", 8, 12)
    self.nameBox:SetAutoFocus(false)
    self.nameBox:Hide()

    self.newProfileCheck = Widgets.Checkbox(intro, false, function()
      ImportTab:Refresh()
    end)
    self.newProfileCheck:SetPoint("BOTTOMLEFT", self.nameBox, "TOPLEFT", -12, 6)
    local newProfileLabel = Widgets.Label(intro, "GameFontHighlight", L["Import as a new profile"], colors.parchment)
    newProfileLabel:SetPoint("LEFT", self.newProfileCheck, "RIGHT", 4, 0)
  end

  self:Refresh()
end
