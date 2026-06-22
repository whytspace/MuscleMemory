local ADDON_NAME, MM = ...

local Events = {}
MM.Events = Events
MM:RegisterModule("Events", Events)

-- Events that can change which abilities resolve, so the active profile is
-- worth re-checking. Combat end is included so changes made mid-combat surface
-- once it's safe to apply.
function Events:OnInitialize()
  local frame = MM.eventFrame
  frame:RegisterEvent("PLAYER_REGEN_ENABLED")
  frame:RegisterEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED")
  frame:RegisterEvent("SPELLS_CHANGED")
end

-- Re-evaluate the active profile; if applying it would change a slot, prompt.
-- Skips during combat — PLAYER_REGEN_ENABLED re-checks once it ends.
function Events:OnEvent()
  if InCombatLockdown and InCombatLockdown() then
    return
  end

  if MM.Applier:HasUnappliedChanges() then
    MM.UI:PromptApply()
  end
end
