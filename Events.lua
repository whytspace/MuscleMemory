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
    MM.UI:PromptApply()
  end
end

-- Login fires these events in a burst while pet, spell and action-bar data
-- stream in. An early read can briefly show a slot as a restorable change
-- before the data settles (e.g. a pet ability that is actually unavailable).
-- Trailing-debounce the burst so we evaluate once it quiesces, matching what
-- /mm preview reports.
local REEVALUATE_DELAY = 1.0
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
handlers.PLAYER_REGEN_ENABLED = reevaluateProfile
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
