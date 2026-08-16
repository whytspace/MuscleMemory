local ADDON_NAME, MM = ...

local Events = {}
MM.Events = Events
MM:RegisterModule("Events", Events)

-- Dispatch by event name; events that mean the same thing share a handler.
local handlers = {}

-- Repaint just the changed grid cell (slot; 0/nil = bulk), never a full refresh.
function handlers.ACTIONBAR_SLOT_CHANGED(slot)
  if MM.ui and MM.ui.LayersTab then
    MM.ui.LayersTab:OnBarsChanged(slot)
  end
end

-- Prompt to apply/preview when applying the active profile would change a slot
-- and we're not in combat. Shared by game events and the in-game profile switch,
-- so both behave the same. (Slash commands deliberately don't prompt.)
function Events:PromptApplyIfChanged()
  if InCombatLockdown and InCombatLockdown() then
    return
  end
  if not MM.Applier:HasUnappliedChanges() then
    -- A settled re-eval found nothing to do; clear a prompt an earlier,
    -- unsettled read may have raised.
    MM.UI:DismissApplyPrompt()
    return
  end

  -- The active profile decides how to react to detected changes.
  local response = MM.DB:GetResponse()
  if response == "ignore" then
    return
  elseif response == "print" then
    MM.Applier:PreviewProfile()
  elseif response == "apply" then
    MM.Applier:ApplyProfile()
  else
    -- Print the preview alongside the popup: by the time the player types
    -- /mm preview, late-streamed data may have settled and the diff vanished,
    -- so capture the trigger reason at prompt time.
    MM.Applier:PreviewProfile()
    MM.UI:PromptApply()
  end
end

-- Login, zoning and spec swaps stream data in a burst; an early read misjudges
-- slots, or sees empty bars. Trailing-debounce until it settles.
local REEVALUATE_DELAY = 5.0
local reevaluateGen = 0
-- Timers keep ticking through a loading screen, so the delay can expire
-- mid-load, when the bars read as empty. Skip that read;
-- LOADING_SCREEN_DISABLED schedules a fresh one.
local loadingScreen = false

local function reevaluateProfile()
  if not C_Timer then
    Events:PromptApplyIfChanged()
    return
  end
  reevaluateGen = reevaluateGen + 1
  local gen = reevaluateGen
  C_Timer.After(REEVALUATE_DELAY, function()
    if gen == reevaluateGen and not loadingScreen then
      Events:PromptApplyIfChanged()
    end
  end)
end
-- Warm the client's lazily-computed answers before the delay runs, so the read
-- that decides isn't the one asking first. Only on the two events that open a
-- burst: SPELLS_CHANGED repeats too often to warm on.
local function warmAndReevaluate()
  MM.Resolver:WarmClientData()
  reevaluateProfile()
end
handlers.ACTIVE_PLAYER_SPECIALIZATION_CHANGED = warmAndReevaluate
handlers.SPELLS_CHANGED = reevaluateProfile
-- SPELLS_CHANGED fires mid-load, starting the delay too early; restart it here.
handlers.PLAYER_ENTERING_WORLD = warmAndReevaluate

function handlers.LOADING_SCREEN_ENABLED()
  loadingScreen = true
end

function handlers.LOADING_SCREEN_DISABLED()
  loadingScreen = false
  reevaluateProfile()
end

-- Fires at login when macro data loads, on every macro change — and on mere
-- selection in the macro frame, in bursts. Trailing-debounce so clicking
-- through macros stays lag-free; one sync once the burst settles.
local SYNC_MACROS_DELAY = 1.0
local syncMacrosGen = 0

handlers.UPDATE_MACROS = function()
  if not C_Timer then
    MM.Capture:HealMacroSnapshots()
    return
  end
  syncMacrosGen = syncMacrosGen + 1
  local gen = syncMacrosGen
  C_Timer.After(SYNC_MACROS_DELAY, function()
    if gen == syncMacrosGen then
      MM.Capture:HealMacroSnapshots()
    end
  end)
end

function Events:OnInitialize()
  for event in pairs(handlers) do
    MM.eventFrame:RegisterEvent(event)
  end
end

function Events:OnEvent(event, ...)
  local handler = handlers[event]
  if handler then
    handler(...)
  end
end
