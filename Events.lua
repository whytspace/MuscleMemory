local ADDON_NAME, MM = ...

local Events = {}
MM.Events = Events
MM:RegisterModule("Events", Events)

-- Dispatch by event name; events that mean the same thing share a handler.
local handlers = {}

-- Repaint just the changed grid cell (slot; 0/nil = bulk), never a full refresh.
function handlers.ACTIONBAR_SLOT_CHANGED(slot)
  if MM.ui and MM.ui.MusclesTab then
    MM.ui.MusclesTab:OnBarsChanged(slot)
  end
end

-- Prompt to apply/preview when applying the active profile would change a slot
-- and we're not in combat. Shared by game events and the in-game profile switch,
-- so both behave the same. (Slash commands deliberately don't prompt.)
function Events:PromptApplyIfChanged()
  if InCombatLockdown and InCombatLockdown() then
    return
  end
  if MM.Applier:HasUnappliedChanges() then
    MM.UI:PromptApply()
  end
end

local function reevaluateProfile()
  Events:PromptApplyIfChanged()
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
