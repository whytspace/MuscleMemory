local ADDON_NAME, MM = ...

-- Shared, native-styled UI building blocks. Every tab composes its frames from
-- these so the look stays consistent and the tab files stay about layout.
local Widgets = {}
MM.ui.Widgets = Widgets

-- Accent colours. The window itself uses Blizzard's stock frame art; these are
-- only for the bits the stock art has no equivalent for — managed-slot borders,
-- the selected glow, the gold section headers.
Widgets.colors = {
  gold = { 1.0, 0.82, 0.0 },
  goldDim = { 0.79, 0.66, 0.30 },
  parchment = { 0.90, 0.87, 0.80 },
  managed = { 0.62, 0.52, 0.28 },
  selected = { 1.0, 0.82, 0.0 },
  warn = { 0.82, 0.63, 0.40 },
  faint = { 0.42, 0.40, 0.34 },
  muted = { 0.56, 0.52, 0.42 },
  danger = { 0.83, 0.40, 0.32 },
}

local function unpackColor(color, alpha)
  return color[1], color[2], color[3], alpha or color[4] or 1
end
Widgets.unpackColor = unpackColor

-- Stock Blizzard textures used for the small status symbols the WoW font can't
-- draw as glyphs (warning, cleared-slot, predefined-lock).
Widgets.TEX = {
  warning = "Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew",
  empty = "Interface\\Buttons\\UI-GroupLoot-Pass-Up",
  lock = "Interface\\LFGFrame\\UI-LFG-ICON-LOCK",
}

-- A FontString on `parent`, optionally coloured. `font` is a Blizzard font
-- object name (e.g. "GameFontNormal").
function Widgets.Label(parent, font, text, color)
  local label = parent:CreateFontString(nil, "OVERLAY", font or "GameFontNormal")
  label:SetText(text or "")
  if color then
    label:SetTextColor(unpackColor(color))
  end
  return label
end

-- Secondary description / hint text. One style for every "explainer" line so
-- they all read the same.
function Widgets.Hint(parent, text)
  local hint = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  hint:SetText(text or "")
  hint:SetTextColor(unpackColor(Widgets.colors.muted))
  return hint
end

-- The small gold all-caps section heading used throughout the editor panels
-- ("SLOT EDITOR", "BIND TO A MEMORY", …).
function Widgets.SectionHeader(parent, text)
  local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  label:SetText(string.upper(text or ""))
  label:SetTextColor(unpackColor(Widgets.colors.goldDim))
  return label
end

-- A standard Blizzard push button.
function Widgets.Button(parent, text, width, onClick)
  local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  button:SetSize(width or 90, 22)
  button:SetText(text)
  if onClick then
    button:SetScript("OnClick", onClick)
  end
  return button
end

-- A dropdown selector: a left-aligned button with a dropdown arrow that opens a
-- radio context menu. `getData` returns { current = <button label>, items =
-- { { label, selected, onClick }, … } } and is called fresh on every open and on
-- :Sync(), so the control always reflects the live model.
function Widgets.Dropdown(parent, width, getData)
  local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  button:SetSize(width or 200, 24)

  local arrow = button:CreateTexture(nil, "OVERLAY")
  arrow:SetSize(12, 12)
  arrow:SetPoint("RIGHT", button, "RIGHT", -6, 0)
  arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")

  local text = button:GetFontString()
  if text then
    text:ClearAllPoints()
    text:SetPoint("LEFT", button, "LEFT", 10, 0)
    text:SetPoint("RIGHT", arrow, "LEFT", -4, 0)
    text:SetJustifyH("LEFT")
  end

  function button:Sync()
    self:SetText(getData().current or "")
  end

  button:SetScript("OnClick", function(self)
    local data = getData()
    MenuUtil.CreateContextMenu(self, function(_, root)
      for _, item in ipairs(data.items or {}) do
        root:CreateRadio(item.label, function()
          return item.selected
        end, function()
          item.onClick()
        end)
      end
    end)
  end)

  button:Sync()
  return button
end

-- A compact square icon-glyph button (rename pencil, delete trash, …) built
-- from a Blizzard icon texture so it reads as native chrome.
function Widgets.IconButton(parent, texture, tooltip, onClick)
  local button = CreateFrame("Button", nil, parent)
  button:SetSize(26, 24)

  local bg = button:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(0, 0, 0, 0.35)

  local icon = button:CreateTexture(nil, "ARTWORK")
  icon:SetPoint("CENTER")
  icon:SetSize(14, 14)
  icon:SetTexture(texture)
  button.icon = icon

  button:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
  if onClick then
    button:SetScript("OnClick", onClick)
  end
  if tooltip then
    button:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:SetText(tooltip)
      GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
      GameTooltip:Hide()
    end)
  end
  return button
end

-- A checkbox (used for the per-muscle "applied in this profile" toggle).
function Widgets.Checkbox(parent, checked, onClick)
  local box = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  box:SetSize(22, 22)
  box:SetChecked(checked)
  if onClick then
    box:SetScript("OnClick", onClick)
  end
  return box
end

-- A dark inset panel — the rails and content backgrounds sit on these.
function Widgets.Inset(parent)
  return CreateFrame("Frame", nil, parent, "InsetFrameTemplate3")
end

-- A 1px hairline divider. `horizontal` draws a full-width line; otherwise a
-- full-height vertical line. Anchor the returned texture yourself.
function Widgets.Hairline(parent, horizontal)
  local line = parent:CreateTexture(nil, "ARTWORK")
  line:SetColorTexture(1, 1, 1, 0.08)
  if horizontal then
    line:SetHeight(1)
  else
    line:SetWidth(1)
  end
  return line
end

-- Clear a retained host before rebuilding its contents. WoW frames are pooled by
-- the client rather than freed, so callers use this only inside retained tab
-- frames; heavyweight children such as scroll lists and grids keep their own
-- pools and reattach during the rebuild.
function Widgets.ClearChildren(parent)
  for _, child in ipairs({ parent:GetChildren() }) do
    child:Hide()
    child:ClearAllPoints()
    child:SetParent(nil)
  end
end

-- A vertical groove separator (dark line + light highlight) for splitting the
-- shared content inset into panels. Anchor its TOP/BOTTOM yourself.
function Widgets.VGroove(parent)
  local groove = CreateFrame("Frame", nil, parent)
  groove:SetWidth(2)

  local dark = groove:CreateTexture(nil, "ARTWORK")
  dark:SetPoint("TOPLEFT")
  dark:SetPoint("BOTTOMLEFT")
  dark:SetWidth(1)
  dark:SetColorTexture(0, 0, 0, 0.5)

  local light = groove:CreateTexture(nil, "ARTWORK")
  light:SetPoint("TOPRIGHT")
  light:SetPoint("BOTTOMRIGHT")
  light:SetWidth(1)
  light:SetColorTexture(1, 1, 1, 0.06)

  return groove
end

-- A vertically scrolling region using the modern thin scrollbar
-- (Guild/Communities/Settings look): a WowScrollBox scrolling a single child,
-- paired with a MinimalScrollBar to its right. Returns (scrollBox, content); add
-- content to `content` and set its height. The scrollbar sits just to the
-- region's right, so the caller leaves a little room there.
--
-- Pass a `key` to cache and reuse the frames across tab rebuilds, so the scroll
-- offset survives a refresh (the same trick DataList uses). On reuse the previous
-- child is detached — the caller rebuilds a fresh one each time.
local scrollLists = {}

function Widgets.ScrollList(parent, key)
  local list = key and scrollLists[key]
  if not list then
    local scrollBox = CreateFrame("Frame", nil, parent, "WowScrollBox")
    local scrollBar = CreateFrame("EventFrame", nil, parent, "MinimalScrollBar")

    local content = CreateFrame("Frame", nil, scrollBox)
    content.scrollable = true
    content:SetScript("OnSizeChanged", function()
      scrollBox:FullUpdate()
    end)

    local view = CreateScrollBoxLinearView()
    view:SetPanExtent(40)
    ScrollUtil.InitScrollBoxWithScrollBar(scrollBox, scrollBar, view)

    list = { scrollBox = scrollBox, scrollBar = scrollBar, content = content }
    if key then
      scrollLists[key] = list
    end
  else
    -- Detach the previous child so the caller's fresh one is the only thing in
    -- the kept-alive (still-scrolled) box.
    for _, child in ipairs({ list.content:GetChildren() }) do
      child:Hide()
      child:ClearAllPoints()
      child:SetParent(nil)
    end
  end

  list.scrollBox:SetParent(parent)
  list.scrollBox:ClearAllPoints()
  list.scrollBar:SetParent(parent)
  list.scrollBar:ClearAllPoints()
  list.scrollBar:SetPoint("TOPLEFT", list.scrollBox, "TOPRIGHT", 6, 0)
  list.scrollBar:SetPoint("BOTTOMLEFT", list.scrollBox, "BOTTOMRIGHT", 6, 0)
  list.scrollBox:Show()
  list.scrollBar:Show()

  return list.scrollBox, list.content
end

-- A retained, recycling list: one WowScrollBox kept alive (cached by `key`) plus
-- a pool of row frames, re-parented onto each fresh container on a tab rebuild.
-- Because the scroll box itself is never recreated, the scroll offset is kept
-- across updates for free, and rows are reused rather than orphaned. (WoW's
-- DataProvider ScrollBox needs an XML row template per row type, which this
-- Lua-only add-on doesn't define, so we pool rows by hand on the same scroll-box
-- API that ScrollList already uses.) `opts` is read only the first time a key is
-- seen: { extent = rowHeight, spacing = gap, initializer = fn(row, elementData) }.
-- The initializer builds the row's children once (guard on a flag) and updates
-- them from the element data on every call.
local dataLists = {}

function Widgets.DataList(parent, key, opts)
  local list = dataLists[key]
  if not list then
    local scrollBox = CreateFrame("Frame", nil, parent, "WowScrollBox")
    local scrollBar = CreateFrame("EventFrame", nil, parent, "MinimalScrollBar")

    local content = CreateFrame("Frame", nil, scrollBox)
    content.scrollable = true
    content:SetScript("OnSizeChanged", function()
      scrollBox:FullUpdate()
    end)

    local view = CreateScrollBoxLinearView()
    view:SetPanExtent(opts.extent)
    ScrollUtil.InitScrollBoxWithScrollBar(scrollBox, scrollBar, view)

    list = {
      scrollBox = scrollBox,
      scrollBar = scrollBar,
      content = content,
      rows = {},
      extent = opts.extent,
      spacing = opts.spacing or 0,
      initializer = opts.initializer,
    }

    -- `retain` (default true) leaves the scroll offset alone; pass false to jump
    -- back to the top (e.g. when the list's subject changed).
    function list:SetItems(items, retain)
      items = items or {}
      local gap = self.extent + self.spacing
      for index, data in ipairs(items) do
        local row = self.rows[index]
        if not row then
          row = CreateFrame("Button", nil, self.content)
          row:SetHeight(self.extent)
          self.rows[index] = row
        end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, -(index - 1) * gap)
        row:SetPoint("TOPRIGHT", self.content, "TOPRIGHT", 0, -(index - 1) * gap)
        row:Show()
        self.initializer(row, data)
      end
      for index = #items + 1, #self.rows do
        self.rows[index]:Hide()
      end
      self.content:SetHeight(math.max(1, #items * gap - self.spacing))
      if retain == false and self.scrollBox.ScrollToBegin then
        self.scrollBox:ScrollToBegin()
      end
    end

    function list:ForEachFrame(fn)
      for _, row in ipairs(self.rows) do
        if row:IsShown() then
          fn(row)
        end
      end
    end

    dataLists[key] = list
  end

  -- Re-attach onto the current container — a legacy tab rebuild makes a fresh one.
  list.scrollBox:SetParent(parent)
  list.scrollBox:ClearAllPoints()
  list.scrollBar:SetParent(parent)
  list.scrollBar:ClearAllPoints()
  list.scrollBar:SetPoint("TOPLEFT", list.scrollBox, "TOPRIGHT", 6, 0)
  list.scrollBar:SetPoint("BOTTOMLEFT", list.scrollBox, "BOTTOMRIGHT", 6, 0)
  list.scrollBox:Show()
  list.scrollBar:Show()

  return list
end

-- A multi-line text box for free-form input (macro bodies). Built on Blizzard's
-- InputScrollFrameTemplate so it scrolls and caps length natively. `onChange`
-- fires with the current text on every edit. Anchor it and set its height.
function Widgets.MultiLineInput(parent, text, maxLetters, onChange)
  local frame = CreateFrame("ScrollFrame", nil, parent, "InputScrollFrameTemplate")
  local edit = frame.EditBox
  edit:SetMaxLetters(maxLetters or 0)
  edit:SetFontObject("ChatFontNormal")
  edit:SetMultiLine(true)
  if frame.CharCount then
    frame.CharCount:Hide()
  end

  -- Keep the edit box pinned to the scroll frame's width so long lines wrap down
  -- instead of running off the right edge. The width isn't known until the frame
  -- is laid out, so sync it whenever the frame resizes (and once up front).
  local function syncWidth()
    local width = frame:GetWidth()
    if width and width > 0 then
      edit:SetWidth(width)
    end
  end
  frame:HookScript("OnSizeChanged", syncWidth)
  syncWidth()

  edit:SetText(text or "")
  -- Hook, don't replace: InputScrollFrameTemplate wires its own OnTextChanged to
  -- keep the caret scrolled into view. Overwriting it makes the cursor jump.
  edit:HookScript("OnTextChanged", function(self)
    if onChange then
      onChange(self:GetText())
    end
  end)
  edit:SetScript("OnEscapePressed", function(self)
    self:ClearFocus()
  end)
  return frame
end

-- The little three-bar "priority list" badge that marks a memory-driven slot.
-- Pinned to the bottom-right corner of `parent`.
function Widgets.MemoryBadge(parent, size)
  size = size or 13
  local badge = CreateFrame("Frame", nil, parent)
  badge:SetSize(size, size)
  badge:SetPoint("BOTTOMRIGHT", 2, -2)

  local bg = badge:CreateTexture(nil, "OVERLAY")
  bg:SetAllPoints()
  bg:SetColorTexture(0.08, 0.075, 0.05, 1)

  local lineWidth = size - 5
  for index = 1, 3 do
    local bar = badge:CreateTexture(nil, "OVERLAY", nil, 1)
    bar:SetSize(lineWidth, 1.5)
    bar:SetPoint("TOP", 0, -(index - 1) * 3 - 2)
    if index == 1 then
      bar:SetColorTexture(unpackColor(Widgets.colors.gold))
    else
      bar:SetColorTexture(0.60, 0.50, 0.19, 1)
    end
  end
  return badge
end

-- A small 2x3 dot grid used as a drag handle (the WoW font has no braille).
function Widgets.DragDots(parent)
  local dots = CreateFrame("Frame", nil, parent)
  dots:SetSize(6, 12)
  for index = 0, 5 do
    local dot = dots:CreateTexture(nil, "ARTWORK")
    dot:SetSize(2, 2)
    dot:SetPoint("TOPLEFT", dots, "TOPLEFT", (index % 2) * 4, -math.floor(index / 2) * 4)
    dot:SetColorTexture(unpackColor(Widgets.colors.faint))
  end
  return dots
end

-- Four edge textures forming a rectangular border around `parent`.
local function createBorder(parent)
  local border = {}
  for _, edge in ipairs({ "top", "bottom", "left", "right" }) do
    border[edge] = parent:CreateTexture(nil, "OVERLAY", nil, 2)
  end
  border.top:SetPoint("TOPLEFT")
  border.top:SetPoint("TOPRIGHT")
  border.bottom:SetPoint("BOTTOMLEFT")
  border.bottom:SetPoint("BOTTOMRIGHT")
  border.left:SetPoint("TOPLEFT")
  border.left:SetPoint("BOTTOMLEFT")
  border.right:SetPoint("TOPRIGHT")
  border.right:SetPoint("BOTTOMRIGHT")
  return border
end

local function setBorder(border, thickness, color, alpha)
  local r, g, b = color[1], color[2], color[3]
  border.top:SetHeight(thickness)
  border.bottom:SetHeight(thickness)
  border.left:SetWidth(thickness)
  border.right:SetWidth(thickness)
  for _, edge in ipairs({ "top", "bottom", "left", "right" }) do
    border[edge]:SetColorTexture(r, g, b, alpha or 1)
  end
end

-- A reusable icon cell: background, the action icon, an optional centred glyph
-- (∅ / ⚠ for empty / unresolved), an optional memory badge, and a settable
-- border. Returned object exposes Set* helpers so callers stay declarative.
function Widgets.Icon(parent, size)
  local icon = CreateFrame("Frame", nil, parent)
  icon:SetSize(size, size)

  icon.bg = icon:CreateTexture(nil, "BACKGROUND")
  icon.bg:SetAllPoints()
  icon.bg:SetColorTexture(0.04, 0.04, 0.05, 0.95)

  icon.texture = icon:CreateTexture(nil, "ARTWORK")
  icon.texture:SetPoint("TOPLEFT", 1, -1)
  icon.texture:SetPoint("BOTTOMRIGHT", -1, 1)
  icon.texture:SetTexCoord(0.07, 0.93, 0.07, 0.93)

  icon.glyph = icon:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  icon.glyph:SetPoint("CENTER")
  icon.glyph:Hide()

  -- Bound-key text in the top-right corner, mirroring WoW's own action buttons.
  icon.hotkey = icon:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  icon.hotkey:SetPoint("TOPRIGHT", -1, -1)
  icon.hotkey:SetJustifyH("RIGHT")
  icon.hotkey:SetTextColor(unpackColor(Widgets.colors.parchment))
  icon.hotkey:Hide()

  icon.border = createBorder(icon)

  local function hideSymbol(self)
    if self.symbol then
      self.symbol:Hide()
    end
  end

  function icon:SetTextureImage(texture)
    self.glyph:Hide()
    hideSymbol(self)
    if texture then
      self.texture:SetTexture(texture)
      self.texture:Show()
    else
      self.texture:Hide()
    end
  end

  function icon:SetGlyph(text, color)
    self.texture:Hide()
    hideSymbol(self)
    self.glyph:SetText(text)
    self.glyph:SetTextColor(unpackColor(color or Widgets.colors.goldDim))
    self.glyph:Show()
  end

  -- A centred status texture (warning / cleared / lock) at ~60% of the cell.
  function icon:SetSymbol(texture)
    self.texture:Hide()
    self.glyph:Hide()
    if not self.symbol then
      self.symbol = self:CreateTexture(nil, "ARTWORK", nil, 1)
      self.symbol:SetPoint("CENTER")
      local extent = math.floor(size * 0.6)
      self.symbol:SetSize(extent, extent)
    end
    self.symbol:SetTexture(texture)
    self.symbol:Show()
  end

  function icon:SetBorder(thickness, color, alpha)
    setBorder(self.border, thickness, color, alpha)
  end

  function icon:SetHotkey(text)
    if text and text ~= "" then
      self.hotkey:SetText(text)
      self.hotkey:Show()
    else
      self.hotkey:Hide()
    end
  end

  function icon:SetBadge(show)
    if show and not self.badge then
      self.badge = Widgets.MemoryBadge(self, math.max(11, math.floor(size * 0.36)))
    end
    if self.badge then
      self.badge:SetShown(show)
    end
  end

  function icon:SetAlphaAll(alpha)
    self.texture:SetAlpha(alpha)
    self.glyph:SetAlpha(alpha)
  end

  return icon
end

-- Apply the shared list-row visuals (selection background, hover, left accent
-- bar + a :SetSelected method) to an existing Button. Used by ListRow and by
-- DataList row initializers, which receive a pooled bare Button to dress.
local function decorateRow(row)
  row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

  row.selectedBg = row:CreateTexture(nil, "BACKGROUND")
  row.selectedBg:SetAllPoints()
  row.selectedBg:SetColorTexture(0.13, 0.11, 0.05, 0)

  row.hover = row:CreateTexture(nil, "BACKGROUND", nil, 1)
  row.hover:SetAllPoints()
  row.hover:SetColorTexture(1, 1, 1, 0.06)
  row.hover:Hide()

  row.accent = row:CreateTexture(nil, "ARTWORK")
  row.accent:SetPoint("TOPLEFT", 0, -2)
  row.accent:SetPoint("BOTTOMLEFT", 0, 2)
  row.accent:SetWidth(2)
  row.accent:SetColorTexture(unpackColor(Widgets.colors.gold, 0))

  row:SetScript("OnEnter", function(self)
    self.hover:Show()
  end)
  row:SetScript("OnLeave", function(self)
    self.hover:Hide()
  end)

  function row:SetSelected(selected)
    self.selectedBg:SetColorTexture(0.13, 0.11, 0.05, selected and 1 or 0)
    self.accent:SetColorTexture(unpackColor(Widgets.colors.gold, selected and 0.95 or 0))
  end
end
Widgets.decorateRow = decorateRow

-- Populate GameTooltip with the rich client tooltip for an action identified by
-- kind + id — a memory candidate, or whatever a memory/slot resolves to. Falls
-- back to plain text for kinds with no native tooltip (macro, equipment set, …).
-- Callers hide the tooltip themselves on leave.
function Widgets.SetActionTooltip(owner, kind, id, fallbackText, anchor)
  GameTooltip:SetOwner(owner, anchor or "ANCHOR_RIGHT")
  if kind == "item" and id and GameTooltip.SetItemByID then
    GameTooltip:SetItemByID(id)
  elseif kind == "spell" and id and GameTooltip.SetSpellByID then
    GameTooltip:SetSpellByID(id)
  elseif kind == "mount" and id and GameTooltip.SetSpellByID then
    local info = MM.Mounts.GetInfo(id)
    GameTooltip:SetSpellByID(info and info.spellId or id)
  elseif fallbackText then
    GameTooltip:SetText(fallbackText)
  else
    GameTooltip:Hide()
    return
  end
  GameTooltip:Show()
end

-- Show a tooltip while hovering just an icon (from Widgets.Icon), not the whole
-- row. Clicks and drags still fall through to the row. The tooltip appears after a
-- short hover delay. `show` receives the icon's parent row so it can read the live
-- row data.
local TOOLTIP_DELAY = 0.35

function Widgets.AttachIconTooltip(icon, show)
  icon:SetMouseClickEnabled(false)
  icon:SetMouseMotionEnabled(true)
  icon:SetScript("OnEnter", function(self)
    if self.tooltipTimer then
      self.tooltipTimer:Cancel()
    end
    self.tooltipTimer = C_Timer.NewTimer(TOOLTIP_DELAY, function()
      self.tooltipTimer = nil
      if self:IsMouseOver() then
        show(self:GetParent())
      end
    end)
  end)
  icon:SetScript("OnLeave", function(self)
    if self.tooltipTimer then
      self.tooltipTimer:Cancel()
      self.tooltipTimer = nil
    end
    GameTooltip:Hide()
  end)
end

-- A selectable list row (muscle rail, memory rail, slot-editor memory options).
-- Returns a Button with a highlight, a left accent bar, and a `.label`.
function Widgets.ListRow(parent, height)
  local row = CreateFrame("Button", nil, parent)
  row:SetHeight(height or 30)
  decorateRow(row)
  return row
end

-- The cursor types we can capture and pin/add.
local PINNABLE = { spell = true, item = true, mount = true, macro = true, equipmentset = true }

-- A drop overlay that covers a panel (set via :Attach) while a pinnable action is
-- on the cursor, so dropping anywhere on the panel runs the attached callback.
-- Shared by the Slot Editor (pin to slot) and the Memories candidate list (add a
-- candidate). One per consumer; re-Attach it to the current panel each rebuild.
function Widgets.DropZone(labelText)
  local overlay = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
  overlay:Hide()
  overlay:EnableMouse(true)
  overlay:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 2,
  })
  overlay:SetBackdropColor(unpackColor(Widgets.colors.gold, 0.1))
  overlay:SetBackdropBorderColor(unpackColor(Widgets.colors.gold, 0.85))

  overlay.label = Widgets.Label(overlay, "GameFontHighlight", labelText, Widgets.colors.gold)
  overlay.label:SetPoint("CENTER")

  local function drop(self)
    if self.active and self.onDrop and GetCursorInfo and GetCursorInfo() then
      self.onDrop()
    end
  end
  overlay:SetScript("OnReceiveDrag", drop)
  overlay:SetScript("OnMouseUp", drop)

  function overlay:Refresh()
    local cursorType = GetCursorInfo and GetCursorInfo()
    local parent = self:GetParent()
    local show = self.active and cursorType and PINNABLE[cursorType] and parent and parent:IsVisible()
    self:SetShown(show and true or false)
  end

  overlay:RegisterEvent("CURSOR_CHANGED")
  overlay:SetScript("OnEvent", function(self)
    self:Refresh()
  end)

  function overlay:Attach(panel, onDrop)
    self.active = true
    self.onDrop = onDrop
    self:SetParent(panel)
    self:ClearAllPoints()
    self:SetAllPoints(panel)
    self:SetFrameLevel(panel:GetFrameLevel() + 20)
    self:Refresh()
  end

  function overlay:Detach()
    self.active = false
    self.onDrop = nil
    self:Hide()
  end

  return overlay
end

-- Header text for the centre column of a tab (active muscle / memory name).
function Widgets.Title(parent, text)
  local title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetText(text or "")
  title:SetTextColor(unpackColor(Widgets.colors.gold))
  return title
end
