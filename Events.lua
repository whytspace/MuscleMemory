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

-- Login and spec swaps stream spell/item/bar data in a burst; an early read can
-- misjudge a slot before item tooltips load. Trailing-debounce a few seconds so
-- we evaluate once it settles.
local REEVALUATE_DELAY = 3.0
local reevaluateGen = 0

local function reevaluateProfile()
  if not C_Timer then
    Events:PromptApplyIfChanged()
    return
  end
  reevaluateGen = reevaluateGen + 1
  local gen = reevaluateGen
  C_Timer.After(REEVALUATE_DELAY, function()
    if gen == reevaluateGen then
      Events:PromptApplyIfChanged()
    end
  end)
end
handlers.ACTIVE_PLAYER_SPECIALIZATION_CHANGED = reevaluateProfile
handlers.SPELLS_CHANGED = reevaluateProfile

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
