local ADDON_NAME, MM = ...
local L = MM.L
local Widgets = MM.ui.Widgets
local colors = Widgets.colors

-- The onboarding tutorial: the window dims around one of its own regions and a
-- card beside it explains that region. Never writes configuration and never
-- picks a Layer or Smart Action for the player; a step may drop a view
-- selection so it points at the panel it is describing, nothing more.
local Tutorial = {}
MM.ui.Tutorial = Tutorial

local CARD_WIDTH = 330
local CARD_PAD = 14
local NAV_HEIGHT = 22
local BORDER = 2

-- The help "i" cropped to its disc, so it sits at text height inline.
local INLINE_ICON = "|TInterface\\common\\help-i:16:16:0:-8:64:64:14:50:14:50|t"

-- Re-registered on every tab rebuild, so a recycled frame leaves no stale rect.
local anchors = {}

function Tutorial:SetAnchor(id, frame)
  anchors[id] = frame
end

-- Steps ----------------------------------------------------------------------

-- Built on demand: L[] must not be called at file scope.
local function buildSteps()
  return {
    {
      id = "welcome",
      welcome = true,
      tab = "layers",
      headline = L["Welcome to Muscle Memory"],
      body = L["Muscle Memory will help you organize your action bars and keep them in sync across all your characters. This guide will take you through the basic concepts."],
      footnote = string.format(
        L["You can restart this tutorial at any time from the %s in the top-left corner."],
        INLINE_ICON
      ),
    },
    {
      id = "bars",
      tab = "layers",
      anchor = "layers.grid",
      headline = L["Your action bars"],
      body = L["This grid shows a copy of your action bar slots, giving you an easy overview of what Muscle Memory is managing for you."],
      action = L["Left-click a slot to start managing it with Muscle Memory."],
      -- The next step's panel only fills in once a slot is picked.
      require = function()
        return MM.DB:GetSelectedSlot() ~= nil or #MM.DB:GetProfileLayers() == 0
      end,
    },
    {
      id = "editor",
      tab = "layers",
      anchor = "layers.editor",
      headline = L["The Slot Editor"],
      body = L["This panel shows what is currently configured for the selected slot. That can be a spell, mount, pet, item, or a Smart Action (more about those later).\n\nYou can also tell Muscle Memory to empty the slot for you, or to stop managing it altogether."],
    },
    {
      id = "layers",
      tab = "layers",
      anchor = "layers.rail",
      headline = L["Layers"],
      body = L["A Layer is a set of managed action bar slots. If you manage the same slot with multiple Layers, the higher one wins."],
    },
    {
      id = "conditions",
      tab = "layers",
      anchor = "layers.editor",
      headline = L["Conditions"],
      body = L["Conditions let you apply a Layer only to certain characters, based on their class, their specialization, or even the professions they have.\n\nMuscle Memory only ever places actions the current character can actually use, so in many cases you will not need to define conditions explicitly."],
      -- The panel only shows Layer conditions while no slot is selected.
      enter = function()
        if MM.DB:GetSelectedSlot() then
          MM.DB:SetSelectedSlot(nil)
          MM.UI:Refresh()
        end
      end,
    },
    {
      id = "apply",
      tab = "layers",
      anchor = "frame.apply",
      headline = L["Preview and Apply"],
      body = L["Once you are happy with your setup, you can tell Muscle Memory to update your real action bars.\n\nIf you are unsure, preview the changes first and Muscle Memory will print everything it would do into your chat window."],
    },
    {
      id = "smartactions",
      tab = "actions",
      anchor = "actions.rail",
      headline = L["Smart Actions"],
      body = L["Have you ever found yourself wanting to bind a similar action to the same slot on different characters?\n\nThis is where Smart Actions come in. A Smart Action lets you bind a purpose, like Interrupt, instead of a spell, and Muscle Memory picks the first spell available on the current character."],
      action = L["Pick a Smart Action to see the spells it contains."],
    },
    {
      id = "choosing",
      tab = "actions",
      anchor = "actions.center",
      headline = L["First candidate wins"],
      body = L["Muscle Memory checks the list from the top down. The first candidate this character can use goes on the action bar.\n\nMost of the time that is enough, but sometimes you will want to set conditions on a candidate yourself. A macro is one example, since Muscle Memory cannot tell whether the current character can use it."],
    },
    {
      id = "custom",
      tab = "actions",
      anchor = "actions.clone",
      headline = L["Copying a Smart Action"],
      body = L["Muscle Memory ships with built-in Smart Actions. Those are read-only, so if you want to make changes you need to copy one first."],
      action = L["Copy this Smart Action now."],
      -- The next step is about macro mode, which only the editable copies have.
      require = function()
        local ref = MM.ui.state.smartAction
        return ref ~= nil and ref.source == "custom"
      end,
    },
    {
      id = "macro",
      tab = "actions",
      anchor = "actions.rule",
      headline = L["Macros"],
      body = L["Sometimes binding a simple spell is not enough. If you need focus casting or a modifier that you would otherwise write a macro for, Muscle Memory can create that macro for you automatically."],
      -- The panel only shows the macro setting while no candidate is selected.
      enter = function()
        if MM.ui.state.candidate then
          MM.ui.state.candidate = nil
          MM.UI:Refresh()
        end
      end,
    },
    {
      id = "undo",
      anchor = "frame.undo",
      headline = L["We all make mistakes sometimes"],
      body = L["Any setting you change can be undone.\n\nYour action bars only change when you press Apply."],
    },
    {
      id = "profiles",
      tab = "profiles",
      anchor = "profiles.selectors",
      headline = L["Profiles"],
      body = L["Layers, Smart Actions and conditions already give you a lot of flexibility. Sometimes, though, you want a completely separate Muscle Memory configuration. That is where Profiles come in."],
    },
    {
      id = "sharing",
      anchor = "frame.share",
      headline = L["Share your setup"],
      body = L["If you feel like sharing your configuration with others, you can export and import Muscle Memory profiles easily."],
    },
    {
      id = "about",
      tab = "about",
      -- Closing note, not a tour stop: hand the window back undimmed.
      dim = false,
      headline = L["That's it!"],
      body = L["If something ever goes wrong or does not work as intended, please file a bug report.\n\nHappy gaming!"],
    },
  }
end

-- Where the "i" picks up from. Tabs without a step of their own start at 2.
local ENTRY = { layers = 2, actions = 7, profiles = 12 }

-- Geometry -------------------------------------------------------------------

-- A region's rect as offsets from the window's bottom-left, in the window's own
-- units, which is what lets the dim move with the window for free.
local function rectOf(region, pad)
  local window = MM.UI.frame
  if not (window and region and region.IsVisible and region:IsVisible()) then
    return nil
  end
  local left, bottom, width, height = region:GetRect()
  if not left or not width or width <= 0 or height <= 0 then
    return nil
  end
  local scale = region:GetEffectiveScale() / window:GetEffectiveScale()
  pad = pad or 0
  return {
    (left * scale) - window:GetLeft() - pad,
    (bottom * scale) - window:GetBottom() - pad,
    width * scale + pad * 2,
    height * scale + pad * 2,
  }
end

local function setQuad(region, left, bottom, right, top)
  if right <= left or top <= bottom then
    region:Hide()
    return
  end
  local window = MM.UI.frame
  region:ClearAllPoints()
  region:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", left, bottom)
  region:SetPoint("TOPRIGHT", window, "BOTTOMLEFT", right, top)
  region:Show()
end

-- Frames ---------------------------------------------------------------------

local function textButton(parent, text, onClick)
  local button = CreateFrame("Button", nil, parent)
  button:SetHeight(14)
  local label = Widgets.Label(button, "GameFontDisableSmall", text)
  label:SetPoint("LEFT")
  button:SetWidth(label:GetStringWidth() + 4)
  button:SetScript("OnEnter", function()
    label:SetTextColor(Widgets.unpackColor(colors.gold))
  end)
  button:SetScript("OnLeave", function()
    label:SetTextColor(Widgets.unpackColor(colors.muted))
  end)
  button:SetScript("OnClick", onClick)
  return button
end

-- A hairline gold rectangle, drawn from four textures.
local function thinBorder(frame)
  local edges = {}
  for index = 1, 4 do
    local edge = frame:CreateTexture(nil, "BORDER")
    edge:SetColorTexture(Widgets.unpackColor(colors.gold, 0.9))
    edges[index] = edge
  end
  edges[1]:SetPoint("TOPLEFT")
  edges[1]:SetPoint("TOPRIGHT")
  edges[1]:SetHeight(BORDER)
  edges[2]:SetPoint("BOTTOMLEFT")
  edges[2]:SetPoint("BOTTOMRIGHT")
  edges[2]:SetHeight(BORDER)
  edges[3]:SetPoint("TOPLEFT")
  edges[3]:SetPoint("BOTTOMLEFT")
  edges[3]:SetWidth(BORDER)
  edges[4]:SetPoint("TOPRIGHT")
  edges[4]:SetPoint("BOTTOMRIGHT")
  edges[4]:SetWidth(BORDER)
end

function Tutorial:Build()
  if self.overlay then
    return
  end

  -- A child of the window, so it moves, hides and stacks along with it.
  local overlay = CreateFrame("Frame", "MuscleMemoryTutorial", MM.UI.frame)
  overlay:SetAllPoints(MM.UI.frame)
  overlay:Hide()
  overlay:SetScript("OnUpdate", function()
    Tutorial:Follow()
  end)
  self.overlay = overlay

  -- Four mouse-enabled frames, not one: the gap between them is the hole, so
  -- the highlighted region stays clickable and the dimmed rest does not.
  self.shade = {}
  for index = 1, 4 do
    local quad = CreateFrame("Frame", nil, overlay)
    quad:EnableMouse(true)
    local fill = quad:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints()
    fill:SetColorTexture(0, 0, 0, 0.62)
    self.shade[index] = quad
  end

  local highlightHost = CreateFrame("Frame", nil, overlay)
  highlightHost:SetAllPoints(overlay)
  self.highlightHost = highlightHost

  self.highlight = {}
  for index = 1, 4 do
    local edge = highlightHost:CreateTexture(nil, "ARTWORK")
    edge:SetColorTexture(Widgets.unpackColor(colors.gold, 0.9))
    self.highlight[index] = edge
  end

  local card = CreateFrame("Frame", nil, overlay)
  card:SetWidth(CARD_WIDTH)
  card:EnableMouse(true)
  -- Beside the window: anywhere on it eventually covers what a step points at.
  card:SetPoint("TOPLEFT", MM.UI.frame, "TOPRIGHT", 10, 0)
  self.card = card

  local background = card:CreateTexture(nil, "BACKGROUND")
  background:SetAllPoints()
  background:SetColorTexture(0.04, 0.03, 0.02, 0.95)
  thinBorder(card)

  card.close = CreateFrame("Button", nil, card, "UIPanelCloseButton")
  card.close:SetSize(22, 22)
  card.close:SetPoint("TOPRIGHT", card, "TOPRIGHT", -4, -4)
  card.close:SetScript("OnClick", function()
    Tutorial:Stop()
  end)

  card.headline = Widgets.Label(card, "GameFontNormal", "", colors.gold)
  card.headline:SetPoint("TOPLEFT", card, "TOPLEFT", CARD_PAD, -CARD_PAD)
  card.headline:SetJustifyH("LEFT")

  card.body = Widgets.Label(card, "GameFontHighlightSmall", "")
  card.body:SetJustifyH("LEFT")

  card.action = Widgets.Label(card, "GameFontNormalSmall", "", colors.gold)
  card.action:SetJustifyH("LEFT")

  card.footnote = Widgets.Hint(card, "")
  card.footnote:SetJustifyH("LEFT")

  card.progress = Widgets.Label(card, "GameFontDisableSmall", "")
  card.progress:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", CARD_PAD, CARD_PAD + 4)

  card.restart = textButton(card, L["Start over"], function()
    Tutorial:Goto(2)
  end)
  card.restart:SetPoint("LEFT", card.progress, "RIGHT", 10, 0)

  card.next = Widgets.Button(card, L["Next"], 74, function()
    Tutorial:Goto(Tutorial.index + 1)
  end)
  card.next:SetHeight(NAV_HEIGHT)
  card.next:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -CARD_PAD, CARD_PAD)

  card.back = Widgets.Button(card, L["Back"], 66, function()
    Tutorial:Goto(Tutorial.index - 1)
  end)
  card.back:SetHeight(NAV_HEIGHT)
  card.back:SetPoint("BOTTOMRIGHT", card.next, "BOTTOMLEFT", -6, 0)

  card.start = Widgets.Button(card, L["Show me around"], 140, function()
    Tutorial:Goto(2)
  end)
  card.start:SetHeight(NAV_HEIGHT)

  card.dismiss = Widgets.Button(card, L["Not now"], 90, function()
    Tutorial:Stop()
  end)
  card.dismiss:SetHeight(NAV_HEIGHT)
end

-- Rendering ------------------------------------------------------------------

local function layoutCard(card, step)
  local inner = CARD_WIDTH - CARD_PAD * 2
  card.headline:SetWidth(inner - 20)
  card.headline:SetText(step.headline or "")
  local height = CARD_PAD + card.headline:GetStringHeight()

  local anchor = card.headline
  local function place(region, text, gap)
    if not text then
      region:Hide()
      return
    end
    region:ClearAllPoints()
    region:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -gap)
    region:SetWidth(inner)
    region:SetText(text)
    region:Show()
    height = height + gap + region:GetStringHeight()
    anchor = region
  end

  place(card.body, step.body, 10)
  place(card.action, step.action, 10)
  place(card.footnote, step.footnote, 10)

  card.start:SetShown(step.welcome == true)
  card.dismiss:SetShown(step.welcome == true)
  card.back:SetShown(not step.welcome)
  card.next:SetShown(not step.welcome)
  card.progress:SetShown(not step.welcome)

  if step.welcome then
    card.start:ClearAllPoints()
    card.start:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -14)
    card.dismiss:ClearAllPoints()
    card.dismiss:SetPoint("LEFT", card.start, "RIGHT", 8, 0)
  end

  card:SetHeight(height + 14 + NAV_HEIGHT + CARD_PAD)
end

-- Everything that depends on where the window is, without touching the text.
function Tutorial:Layout()
  local step = self.steps and self.steps[self.index]
  if not step then
    return
  end

  -- PortraitFrameTemplate puts tab content at +1, the portrait at +20, the
  -- border at +499 and the title bar at +509. The dim goes in the gap, so the
  -- window's own chrome draws over it and nothing needs re-ordering. Redone
  -- every layout because SetToplevel shifts the base as windows are raised.
  local base = MM.UI.frame:GetFrameLevel()
  self.overlay:SetFrameLevel(base + 100)
  self.highlightHost:SetFrameLevel(base + 520)
  self.card:SetFrameLevel(base + 600)

  -- Held a few pixels inside the window: the frame's rect runs past its border
  -- art, and the dim's square corners would show at the rounded ones.
  local bounds = step.dim ~= false and rectOf(MM.UI.frame, -6) or nil
  local hole = step.anchor and rectOf(anchors[step.anchor], 4) or nil

  if bounds and hole then
    local windowLeft, windowBottom = bounds[1], bounds[2]
    local windowRight, windowTop = windowLeft + bounds[3], windowBottom + bounds[4]
    local left, bottom = hole[1], hole[2]
    local right, top = left + hole[3], bottom + hole[4]

    setQuad(self.shade[1], windowLeft, top, windowRight, windowTop)
    setQuad(self.shade[2], windowLeft, windowBottom, windowRight, bottom)
    setQuad(self.shade[3], windowLeft, bottom, left, top)
    setQuad(self.shade[4], right, bottom, windowRight, top)

    setQuad(self.highlight[1], left, top - BORDER, right, top)
    setQuad(self.highlight[2], left, bottom, right, bottom + BORDER)
    setQuad(self.highlight[3], left, bottom, left + BORDER, top)
    setQuad(self.highlight[4], right - BORDER, bottom, right, top)
  elseif bounds then
    setQuad(self.shade[1], bounds[1], bounds[2], bounds[1] + bounds[3], bounds[2] + bounds[4])
    for index = 2, 4 do
      self.shade[index]:Hide()
    end
    for index = 1, 4 do
      self.highlight[index]:Hide()
    end
  else
    for index = 1, 4 do
      self.shade[index]:Hide()
      self.highlight[index]:Hide()
    end
  end
end

function Tutorial:Render()
  local step = self.steps and self.steps[self.index]
  if not step then
    return
  end

  layoutCard(self.card, step)

  self.card.progress:SetText(string.format(L["%d of %d"], self.index - 1, #self.steps - 1))
  -- Nothing to start over from on the opening step.
  self.card.restart:SetShown(self.index > 2)
  self.card.back:SetEnabled(self.index > 1)
  self.card.next:SetText(self.index >= #self.steps and L["Close"] or L["Next"])
  -- Held until the next step's panel has something to show.
  self.card.next:SetEnabled(step.require == nil or step.require())

  self:Layout()
end

-- The overlay rides along with the window, but not with its changing level.
function Tutorial:Follow()
  if not self.active then
    return
  end
  local level = MM.UI.frame and MM.UI.frame:GetFrameLevel()
  if level ~= self.atLevel then
    self.atLevel = level
    self:Layout()
  end
end

-- Control --------------------------------------------------------------------

function Tutorial:IsActive()
  return self.active == true
end

function Tutorial:Goto(index)
  if not self.steps then
    return
  end

  if index > #self.steps then
    self:Stop()
    return
  end
  self.index = math.max(1, index)

  local step = self.steps[self.index]

  -- Tab switches and view fix-ups rebuild content, which calls back in through
  -- OnRefresh. Suppress that and render once, at the end.
  self.navigating = true
  if step.tab and MM.ui.state.tab ~= step.tab then
    MM.UI:SelectTab(step.tab)
  end
  if step.enter then
    step.enter()
  end
  self.navigating = false

  self:Render()
end

function Tutorial:Start(atWelcome)
  if not (MM.UI.frame and MM.UI.frame:IsShown()) then
    MM.UI:Open()
  end
  self:Build()

  self.steps = buildSteps()
  self.active = true
  self.overlay:Show()

  if atWelcome then
    self:Goto(1)
  else
    self:Goto(ENTRY[MM.ui.state.tab] or 2)
  end
end

function Tutorial:Stop()
  if not self.active then
    return
  end
  self.active = false
  if self.overlay then
    self.overlay:Hide()
  end
end

-- The tab has just rebuilt, so the highlight needs its fresh anchor.
function Tutorial:OnRefresh()
  if not self.active or self.navigating then
    return
  end
  self:Render()
end
