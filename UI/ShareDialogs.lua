local ADDON_NAME, MM = ...

-- The export and import dialogs. Export packs a selection of the active
-- profile's layers and dynamic actions into a copyable string; import decodes a
-- pasted string, previews its content with the same checkbox list, and creates
-- everything as new entities in the current or a new profile.
local ShareDialogs = {}
MM.ui.ShareDialogs = ShareDialogs

local Widgets = MM.ui.Widgets
local colors = Widgets.colors

local DIALOG_BACKDROP = {
  bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
  edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
  tile = true,
  tileSize = 32,
  edgeSize = 32,
  insets = { left = 11, right = 12, top = 12, bottom = 11 },
}

-- Shared checkbox-list row (recycled by Widgets.DataList): a section header, or
-- a checkbox item. Locked items are the custom dynamic actions a checked layer
-- references — always exported/imported with it, so they can't be unchecked.
local function checkRowInit(row, data)
  if not row.mmInit then
    row.mmInit = true

    row.headerLabel = Widgets.SectionHeader(row, "")
    row.headerLabel:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 2, 3)

    row.check = Widgets.Checkbox(row, false)
    row.check:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.check:SetScript("OnClick", function(self)
      local d = row.data
      if d and d.onToggle then
        d.onToggle(self:GetChecked() and true or false)
      end
    end)

    row.label = Widgets.Label(row, "GameFontHighlight", "")
    row.label:SetPoint("LEFT", row.check, "RIGHT", 4, 0)
    row.label:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.label:SetJustifyH("LEFT")
    row.label:SetWordWrap(false)

    -- The whole row toggles, not just the checkbox.
    row:SetScript("OnClick", function(self)
      local d = self.data
      if not d or d.header or d.locked or not d.onToggle then
        return
      end
      local checked = not self.check:GetChecked()
      self.check:SetChecked(checked)
      d.onToggle(checked)
    end)
  end

  row.data = data
  if data.header then
    row.headerLabel:SetText(data.header)
    row.headerLabel:Show()
    row.check:Hide()
    row.label:SetText("")
    return
  end

  row.headerLabel:Hide()
  row.check:Show()
  row.check:SetChecked(data.checked)
  row.check:SetEnabled(not data.locked)
  row.check:SetAlpha(data.locked and 0.5 or 1)
  row.label:SetText(data.label)
  if data.locked then
    row.label:SetTextColor(Widgets.unpackColor(colors.muted))
  else
    row.label:SetTextColor(Widgets.unpackColor(colors.parchment))
  end
end

-- One overlay + dialog box, mirroring the Modals look. `name` feeds
-- UISpecialFrames so Escape closes the dialog.
local function buildDialog(name, width, height, title)
  local overlay = CreateFrame("Frame", name, UIParent)
  overlay:SetFrameStrata("FULLSCREEN_DIALOG")
  overlay:SetAllPoints(UIParent)
  overlay:EnableMouse(true)
  overlay:Hide()

  local shade = overlay:CreateTexture(nil, "BACKGROUND")
  shade:SetAllPoints()
  shade:SetColorTexture(0, 0, 0, 0.6)
  -- Exposed so the screenshot tour can hide it during a matte capture.
  overlay.shade = shade

  local box = CreateFrame("Frame", nil, overlay, "BackdropTemplate")
  box:SetSize(width, height)
  box:SetPoint("CENTER")
  box:SetBackdrop(DIALOG_BACKDROP)
  overlay.box = box

  box.title = box:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  box.title:SetPoint("TOP", 0, -20)
  box.title:SetText(title)
  box.title:SetTextColor(Widgets.unpackColor(colors.gold))

  tinsert(UISpecialFrames, name)
  return overlay
end

-- The custom dynamic action keys required by the checked layers. `layersByKey`
-- maps key -> layer table (profile layers for export, package layers for import).
local function requiredActions(layersByKey, checkedLayers)
  local required = {}
  for key, layer in pairs(layersByKey) do
    if checkedLayers[key] then
      MM.Share:LayerDependencies(layer, required)
    end
  end
  return required
end

-- The captured macros riding along in the checked layers (named, deduped by
-- body), and whether any slot references an equipment set (which only resolves
-- by name).
local function selectionNotes(layersByKey, checkedLayers)
  local seen, macros, equipmentSets = {}, {}, false
  for key, layer in pairs(layersByKey) do
    if checkedLayers[key] then
      for _, assignment in pairs(layer.slots or {}) do
        if type(assignment) == "table" then
          if assignment.type == "macro" then
            local body = assignment.bodyHash or assignment.body or assignment.nameHint or "?"
            if not seen[body] then
              seen[body] = true
              macros[#macros + 1] = assignment.nameHint or "Unnamed macro"
            end
          elseif assignment.type == "equipmentset" then
            equipmentSets = true
          end
        end
      end
    end
  end
  table.sort(macros)
  return macros, equipmentSets
end

-- The macros are not selectable — they ride along with their layers — but they
-- are listed like the dynamic actions so the user sees exactly what a package
-- carries.
local function appendMacroItems(items, macros)
  if #macros == 0 then
    return
  end
  items[#items + 1] = { header = "Macros", extent = 28 }
  for _, name in ipairs(macros) do
    items[#items + 1] = {
      label = name .. "  |cff8a8474(rides along with its layer)|r",
      checked = true,
      locked = true,
    }
  end
end

-- Content height of a checkbox list, capped so very large selections scroll
-- instead of growing the dialog past the screen. The dialogs size themselves to
-- this, so a short package gets a short window rather than a slab of dead space.
local LIST_MAX = 280

local function listContentHeight(items, extent, spacing)
  local total = 0
  for _, item in ipairs(items) do
    total = total + (item.extent or extent) + spacing
  end
  return math.min(LIST_MAX, math.max(0, total - spacing))
end

-- Export ---------------------------------------------------------------------

local function exportProfileId()
  return MM.DB:GetActiveProfileId()
end

-- Rebuild the checkbox list and the string from the current selection.
local function refreshExport(dialog)
  local state = dialog.state
  local profile = MM.DB:GetProfile(state.profileId)
  if not profile then
    return
  end

  local layersByKey = profile.layers or {}
  local required = requiredActions(layersByKey, state.layers)

  local items = { { header = "Layers", extent = 22 } }
  for _, entry in ipairs(MM.DB:GetProfileLayers(state.profileId)) do
    items[#items + 1] = {
      label = entry.name,
      checked = state.layers[entry.id] and true or false,
      onToggle = function(checked)
        state.layers[entry.id] = checked or nil
        refreshExport(dialog)
      end,
    }
  end

  local actions = {}
  for key, action in pairs(profile.dynamicActions or {}) do
    actions[#actions + 1] = { key = key, name = action.name or key }
  end
  table.sort(actions, function(left, right)
    return left.name < right.name
  end)
  if #actions > 0 then
    items[#items + 1] = { header = "Dynamic Actions", extent = 28 }
    for _, action in ipairs(actions) do
      local locked = required[action.key] and true or false
      items[#items + 1] = {
        label = action.name .. (locked and "  |cff8a8474(needed by a layer)|r" or ""),
        checked = locked or (state.dynamicActions[action.key] and true or false),
        locked = locked,
        onToggle = function(checked)
          state.dynamicActions[action.key] = checked or nil
          refreshExport(dialog)
        end,
      }
    end
  end

  local macros, equipmentSets = selectionNotes(layersByKey, state.layers)
  appendMacroItems(items, macros)

  items[#items + 1] = { header = "Profile", extent = 28 }
  items[#items + 1] = {
    label = "Settings (fallback and response)",
    checked = state.settings and true or false,
    onToggle = function(checked)
      state.settings = checked or false
      refreshExport(dialog)
    end,
  }

  dialog.list:SetItems(items)

  -- Fit the dialog to the list: fixed chrome above and below plus the rows.
  local height = listContentHeight(items, 24, 2)
  dialog.listHost:SetHeight(math.max(height, 1))
  dialog.box:SetHeight(272 + height)

  local selection = { settings = state.settings, layers = state.layers, dynamicActions = state.dynamicActions }
  local package, reason = MM.Share:BuildPackage(state.profileId, selection)
  local text = package and MM.Share:Encode(package)
  dialog.exportText = text or ""
  dialog.output.EditBox:SetText(text or "")
  dialog.outputHint:SetText(
    text and "Click the string, press Ctrl+C, and share it." or ("|cffd1a05f" .. (reason or "") .. "|r")
  )

  dialog.notes:SetText(equipmentSets and "Equipment sets only resolve for users with same-named sets." or "")
end

local function buildExportDialog()
  local overlay = buildDialog("MuscleMemoryExportDialog", 480, 560, "Export & Share")
  local box = overlay.box

  box.hint = Widgets.Hint(box, "")
  box.hint:SetPoint("TOPLEFT", 24, -48)
  box.hint:SetPoint("TOPRIGHT", -24, -48)
  box.hint:SetJustifyH("LEFT")
  overlay.hint = box.hint

  local listHost = CreateFrame("Frame", nil, box)
  listHost:SetPoint("TOPLEFT", 24, -72)
  listHost:SetPoint("TOPRIGHT", -34, -72)
  listHost:SetHeight(280)
  overlay.listHost = listHost

  overlay.notes = Widgets.Hint(box, "")
  overlay.notes:SetPoint("TOPLEFT", listHost, "BOTTOMLEFT", 0, -6)
  overlay.notes:SetPoint("TOPRIGHT", listHost, "BOTTOMRIGHT", 0, -6)
  overlay.notes:SetJustifyH("LEFT")

  overlay.output = Widgets.MultiLineInput(box, "", 0, nil)
  overlay.output:SetPoint("TOPLEFT", listHost, "BOTTOMLEFT", 0, -28)
  overlay.output:SetPoint("TOPRIGHT", listHost, "BOTTOMRIGHT", 0, -28)
  overlay.output:SetHeight(96)

  -- The string is output, not input: any edit snaps back to the generated text,
  -- and focusing selects everything so Ctrl+C is the only step left.
  local edit = overlay.output.EditBox
  edit:HookScript("OnTextChanged", function(self, userInput)
    if userInput then
      self:SetText(overlay.exportText or "")
      self:HighlightText()
    end
  end)
  edit:HookScript("OnEditFocusGained", function(self)
    self:HighlightText()
  end)

  overlay.outputHint = Widgets.Hint(box, "")
  overlay.outputHint:SetPoint("TOPLEFT", overlay.output, "BOTTOMLEFT", 0, -6)
  overlay.outputHint:SetPoint("TOPRIGHT", overlay.output, "BOTTOMRIGHT", 0, -6)
  overlay.outputHint:SetJustifyH("LEFT")

  local close = CreateFrame("Button", nil, box, "UIPanelButtonTemplate")
  close:SetSize(120, 24)
  close:SetPoint("BOTTOM", box, "BOTTOM", 0, 18)
  close:SetText("Close")
  close:SetScript("OnClick", function()
    overlay:Hide()
  end)

  return overlay
end

function ShareDialogs:OpenExport()
  self.exportDialog = self.exportDialog or buildExportDialog()
  local dialog = self.exportDialog

  local profileId = exportProfileId()
  local profile = MM.DB:GetProfile(profileId)
  if not profile then
    return
  end

  -- Everything checked by default: the common case is sharing the whole profile.
  local state = { profileId = profileId, layers = {}, dynamicActions = {}, settings = true }
  for id in pairs(profile.layers or {}) do
    state.layers[id] = true
  end
  for key in pairs(profile.dynamicActions or {}) do
    state.dynamicActions[key] = true
  end
  dialog.state = state

  dialog.hint:SetText('Choose what to share from profile "' .. (profile.name or profileId) .. '".')

  dialog.list = Widgets.DataList(dialog.listHost, "share.export", {
    extent = 24,
    spacing = 2,
    initializer = checkRowInit,
  })
  dialog.list.scrollBox:SetPoint("TOPLEFT", dialog.listHost, "TOPLEFT", 0, 0)
  dialog.list.scrollBox:SetPoint("BOTTOMRIGHT", dialog.listHost, "BOTTOMRIGHT", 0, 0)

  refreshExport(dialog)
  dialog:Show()
  dialog:Raise()
end

-- Import ---------------------------------------------------------------------

-- Rebuild the preview from the decoded package and current checkbox state.
local function refreshImport(dialog)
  local state = dialog.state
  local package = state.package

  if not package then
    -- Nothing decoded yet: a compact dialog around the paste box, the selection
    -- and target controls appear once a string decodes.
    dialog.list:SetItems({})
    dialog.summary:SetText(state.reason and ("|cffd1a05f" .. state.reason .. "|r") or "")
    dialog.notes:SetText("")
    dialog.accept:SetEnabled(false)
    dialog.newProfileCheck:Hide()
    dialog.newProfileLabel:Hide()
    dialog.nameBox:Hide()
    dialog.listHost:SetHeight(1)
    dialog.box:SetHeight(240)
    return
  end

  local layersByKey = {}
  for _, entry in ipairs(package.layers) do
    layersByKey[entry.key] = entry.layer
  end
  local required = requiredActions(layersByKey, state.layers)

  local items = {}
  if #package.layers > 0 then
    items[#items + 1] = { header = "Layers", extent = 22 }
    for _, entry in ipairs(package.layers) do
      local key = entry.key
      items[#items + 1] = {
        label = entry.layer.name or key,
        checked = state.layers[key] and true or false,
        onToggle = function(checked)
          state.layers[key] = checked or nil
          refreshImport(dialog)
        end,
      }
    end
  end

  local actions = {}
  for key, action in pairs(package.dynamicActions) do
    actions[#actions + 1] = { key = key, name = action.name or key }
  end
  table.sort(actions, function(left, right)
    return left.name < right.name
  end)
  if #actions > 0 then
    items[#items + 1] = { header = "Dynamic Actions", extent = 28 }
    for _, action in ipairs(actions) do
      local locked = required[action.key] and true or false
      items[#items + 1] = {
        label = action.name .. (locked and "  |cff8a8474(needed by a layer)|r" or ""),
        checked = locked or (state.dynamicActions[action.key] and true or false),
        locked = locked,
        onToggle = function(checked)
          state.dynamicActions[action.key] = checked or nil
          refreshImport(dialog)
        end,
      }
    end
  end

  local macros, equipmentSets = selectionNotes(layersByKey, state.layers)
  appendMacroItems(items, macros)

  dialog.list:SetItems(items)

  local height = listContentHeight(items, 24, 2)
  dialog.listHost:SetHeight(math.max(height, 1))
  dialog.box:SetHeight(290 + height)

  local layerCount, actionCount = 0, 0
  for key in pairs(state.layers) do
    if layersByKey[key] then
      layerCount = layerCount + 1
    end
  end
  for key in pairs(package.dynamicActions) do
    if required[key] or state.dynamicActions[key] then
      actionCount = actionCount + 1
    end
  end

  local from = package.profileName and (' from "' .. package.profileName .. '"') or ""
  dialog.summary:SetText(
    string.format(
      "Import%s: %d %s, %d %s.",
      from,
      layerCount,
      layerCount == 1 and "layer" or "layers",
      actionCount,
      actionCount == 1 and "dynamic action" or "dynamic actions"
    )
  )

  dialog.notes:SetText(equipmentSets and "Equipment sets only resolve if you have same-named sets." or "")

  dialog.newProfileCheck:Show()
  dialog.newProfileLabel:Show()
  dialog.nameBox:SetShown(dialog.newProfileCheck:GetChecked())
  dialog.accept:SetEnabled(layerCount + actionCount > 0 or dialog.newProfileCheck:GetChecked())
end

local function decodeInto(dialog, text)
  local state = dialog.state
  if string.gsub(text or "", "%s+", "") == "" then
    state.package, state.reason = nil, nil
    refreshImport(dialog)
    return
  end

  local package, reason = MM.Share:Decode(text)
  state.package, state.reason = package, reason
  state.layers, state.dynamicActions = {}, {}
  if package then
    -- Everything checked by default; unchecking is the exception.
    for _, entry in ipairs(package.layers) do
      state.layers[entry.key] = true
    end
    for key in pairs(package.dynamicActions) do
      state.dynamicActions[key] = true
    end
  end
  refreshImport(dialog)
end

local function runImport(dialog)
  local state = dialog.state
  if not state.package then
    return
  end

  local target
  if dialog.newProfileCheck:GetChecked() then
    target = { newProfile = dialog.nameBox:GetText() or "" }
  else
    target = { profileId = MM.DB:GetActiveProfileId() }
  end

  local selection = { layers = state.layers, dynamicActions = state.dynamicActions }
  local result, reason = MM.Share:Import(state.package, selection, target)
  if not result then
    MM:Warn(reason or "import failed")
    return
  end

  local profile = MM.DB:GetProfile(result.profileId)
  MM:Print(
    string.format(
      "imported %d layers and %d dynamic actions into profile %s.",
      #result.layers,
      #result.dynamicActions,
      profile and profile.name or result.profileId
    )
  )
  dialog:Hide()
  MM.UI:Refresh()
  MM.Events:PromptApplyIfChanged()
end

local function buildImportDialog()
  local overlay = buildDialog("MuscleMemoryImportDialog", 480, 620, "Import")
  local box = overlay.box

  local hint = Widgets.Hint(box, "Paste a Muscle Memory sharing string.")
  hint:SetPoint("TOPLEFT", 24, -48)
  hint:SetPoint("TOPRIGHT", -24, -48)
  hint:SetJustifyH("LEFT")

  overlay.input = Widgets.MultiLineInput(box, "", 0, function(text)
    decodeInto(overlay, text)
  end)
  overlay.input:SetPoint("TOPLEFT", 24, -66)
  overlay.input:SetPoint("TOPRIGHT", -34, -66)
  overlay.input:SetHeight(72)

  overlay.summary = Widgets.Hint(box, "")
  overlay.summary:SetPoint("TOPLEFT", overlay.input, "BOTTOMLEFT", 0, -8)
  overlay.summary:SetPoint("TOPRIGHT", overlay.input, "BOTTOMRIGHT", 0, -8)
  overlay.summary:SetJustifyH("LEFT")

  local listHost = CreateFrame("Frame", nil, box)
  listHost:SetPoint("TOPLEFT", overlay.input, "BOTTOMLEFT", 0, -30)
  listHost:SetPoint("TOPRIGHT", overlay.input, "BOTTOMRIGHT", 0, -30)
  listHost:SetHeight(250)
  overlay.listHost = listHost

  overlay.notes = Widgets.Hint(box, "")
  overlay.notes:SetPoint("TOPLEFT", listHost, "BOTTOMLEFT", 0, -6)
  overlay.notes:SetPoint("TOPRIGHT", listHost, "BOTTOMRIGHT", 0, -6)
  overlay.notes:SetJustifyH("LEFT")

  overlay.newProfileCheck = Widgets.Checkbox(box, false, function()
    refreshImport(overlay)
  end)
  overlay.newProfileCheck:SetPoint("TOPLEFT", listHost, "BOTTOMLEFT", -4, -24)

  overlay.newProfileLabel = Widgets.Label(box, "GameFontHighlight", "Import as a new profile", colors.parchment)
  overlay.newProfileLabel:SetPoint("LEFT", overlay.newProfileCheck, "RIGHT", 4, 0)

  overlay.nameBox = CreateFrame("EditBox", nil, box, "InputBoxTemplate")
  overlay.nameBox:SetSize(180, 22)
  overlay.nameBox:SetPoint("LEFT", overlay.newProfileLabel, "RIGHT", 16, 0)
  overlay.nameBox:SetAutoFocus(false)
  overlay.nameBox:Hide()

  overlay.accept = CreateFrame("Button", nil, box, "UIPanelButtonTemplate")
  overlay.accept:SetSize(120, 24)
  overlay.accept:SetPoint("BOTTOMRIGHT", box, "BOTTOM", -6, 18)
  overlay.accept:SetText("Import")
  -- Shift the label right by half the icon block so icon + text sit centered.
  local acceptText = overlay.accept:GetFontString()
  acceptText:ClearAllPoints()
  acceptText:SetPoint("CENTER", overlay.accept, "CENTER", 8, 0)
  local acceptIcon = overlay.accept:CreateTexture(nil, "ARTWORK")
  acceptIcon:SetSize(12, 12)
  acceptIcon:SetTexture(Widgets.ICON.import)
  acceptIcon:SetPoint("RIGHT", acceptText, "LEFT", -4, 0)
  overlay.accept:SetScript("OnClick", function()
    runImport(overlay)
  end)

  local cancel = CreateFrame("Button", nil, box, "UIPanelButtonTemplate")
  cancel:SetSize(120, 24)
  cancel:SetPoint("BOTTOMLEFT", box, "BOTTOM", 6, 18)
  cancel:SetText(CANCEL or "Cancel")
  cancel:SetScript("OnClick", function()
    overlay:Hide()
  end)

  return overlay
end

function ShareDialogs:OpenImport()
  self.importDialog = self.importDialog or buildImportDialog()
  local dialog = self.importDialog

  dialog.state = { package = nil, reason = nil, layers = {}, dynamicActions = {} }
  dialog.input.EditBox:SetText("")
  dialog.newProfileCheck:SetChecked(false)
  dialog.nameBox:SetText("")

  dialog.list = Widgets.DataList(dialog.listHost, "share.import", {
    extent = 24,
    spacing = 2,
    initializer = checkRowInit,
  })
  dialog.list.scrollBox:SetPoint("TOPLEFT", dialog.listHost, "TOPLEFT", 0, 0)
  dialog.list.scrollBox:SetPoint("BOTTOMRIGHT", dialog.listHost, "BOTTOMRIGHT", 0, 0)

  refreshImport(dialog)
  dialog:Show()
  dialog:Raise()
  dialog.input.EditBox:SetFocus()
end
