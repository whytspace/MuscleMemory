local ADDON_NAME, MM = ...

-- Grab the WoW screenshot API before the module table shadows the global name.
local TakeScreenshot = Screenshot

local Screenshot = {}
MM.Screenshot = Screenshot
MM:RegisterModule("Screenshot", Screenshot)

local COLORS = {
  black = { 0, 0, 0 },
  white = { 1, 1, 1 },
}

-- Let a recolour render before capturing it.
local RENDER_DELAY = 0.5
-- The client throttles back-to-back screenshots, so two captures too close
-- together collapse into one file. Keep a wide gap between the black and white
-- shots so both are written.
local SHOT_GAP = 1.5

-- Lossless captures only: JPEG compression smears colour around every edge,
-- which wrecks both the chroma key and the black/white matte.
local function ensurePng()
  if GetCVar and GetCVar("screenshotFormat") ~= "png" then
    SetCVar("screenshotFormat", "png")
    MM:Print("set screenshotFormat to png for clean captures.")
  end
end

-- A fullscreen backdrop sits above the world and default UI (HIGH); the captured
-- frame is lifted above it (DIALOG), so the shot shows only that frame over a
-- solid colour. Reused across shots.
local function ensureBackdrop()
  local frame = Screenshot.frame
  if not frame then
    frame = CreateFrame("Frame", nil, UIParent)
    frame:SetAllPoints(UIParent)
    frame:SetFrameStrata("HIGH")
    frame.tex = frame:CreateTexture(nil, "BACKGROUND")
    frame.tex:SetAllPoints(frame)
    Screenshot.frame = frame
  end
  return frame
end

-- Dismiss any open static popup (e.g. the apply-confirmation dialog a profile
-- switch raises) so it doesn't sit in the shot.
local function hidePopups()
  for index = 1, (STATICPOPUP_NUMDIALOGS or 4) do
    local popup = _G["StaticPopup" .. index]
    if popup and popup:IsShown() then
      popup:Hide()
    end
  end
end

local function paint(target, color, strata)
  hidePopups()
  local frame = ensureBackdrop()
  frame.tex:SetColorTexture(color[1], color[2], color[3], 1)
  frame:Show()
  -- Only restrata when asked. Some frames (the macro window) corrupt their content
  -- on a strata change, so the caller positions them once and passes raise=false.
  if strata then
    target:SetFrameStrata(strata)
  end
end

-- Two-shot difference matte: capture `target` on black then white so true alpha
-- can be recovered offline (best edge quality and handles translucency). Restores
-- the target's strata and hides the backdrop when done, then calls onDone. By
-- default the target is lifted to DIALOG above the backdrop; pass raise = false to
-- leave its strata alone (the caller already positioned it above the backdrop, as
-- the macro window must since a strata change corrupts it).
function Screenshot:CaptureMatte(target, onDone, raise)
  target = target or MM.UI.frame
  raise = raise ~= false
  local strata = raise and "DIALOG" or nil
  ensurePng()

  local savedStrata = target:GetFrameStrata()
  local function finish()
    if self.frame then
      self.frame:Hide()
    end
    if raise then
      target:SetFrameStrata(savedStrata)
    end
    if onDone then
      onDone()
    end
  end

  paint(target, COLORS.black, strata)
  C_Timer.After(RENDER_DELAY, function()
    TakeScreenshot()
    C_Timer.After(SHOT_GAP, function()
      paint(target, COLORS.white, strata)
      C_Timer.After(RENDER_DELAY, function()
        TakeScreenshot()
        C_Timer.After(RENDER_DELAY, finish)
      end)
    end)
  end)
end
