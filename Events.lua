local ADDON_NAME, MM = ...

local Events = {}
MM.Events = Events
MM:RegisterModule("Events", Events)

local PENDING_PROMPT_COOLDOWN_SECONDS = 30

function Events:OnInitialize()
  local frame = MM.eventFrame
  self.pendingPromptTimes = {}
  frame:RegisterEvent("PLAYER_REGEN_ENABLED")
  frame:RegisterEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED")
  frame:RegisterEvent("SPELLS_CHANGED")
  frame:RegisterEvent("PLAYER_ENTERING_WORLD")
end

function Events:MarkPending(profileId, reason)
  local state = MM.DB:GetCharacterState()
  profileId = profileId or MM.DB:GetActiveProfileId()
  state.pendingProfiles[profileId] = { reason = reason or "pending" }
end

function Events:ShouldPrintPendingPrompt(profileId, reason)
  local key = tostring(profileId) .. ":" .. tostring(reason)
  local now = time()
  local lastPrompt = self.pendingPromptTimes[key]
  if lastPrompt and (now - lastPrompt) < PENDING_PROMPT_COOLDOWN_SECONDS then
    return false
  end

  self.pendingPromptTimes[key] = now
  return true
end

function Events:PromptOrApply(profileId, reason)
  local profile = MM.DB:GetProfile(profileId)
  if not profile then
    return
  end

  local mode = MM.triggers.mode or "manual"
  if mode == "manual" then
    return
  end

  if InCombatLockdown and InCombatLockdown() then
    self:MarkPending(profileId, reason)
    return
  end

  if mode == "auto" then
    MM.Applier:ApplyProfile(profileId)
    return
  end

  self:MarkPending(profileId, reason)
  if self:ShouldPrintPendingPrompt(profileId, reason) then
    MM:Print(string.format("%s is pending because %s. Use /mm apply to apply it.", profile.name or profileId, reason))
  end
end

function Events:OnEvent(event)
  local profileId = MM.DB:GetActiveProfileId()
  local triggers = MM.triggers

  if event == "PLAYER_REGEN_ENABLED" then
    local state = MM.DB:GetCharacterState()
    local pending = state.pendingProfiles[profileId]
    if pending and triggers.afterCombatIfPending ~= false then
      self:PromptOrApply(profileId, pending.reason or "combat ended")
    end
    return
  end

  if event == "PLAYER_ENTERING_WORLD" and triggers.onLogin then
    self:PromptOrApply(profileId, "login or reload")
    return
  end

  if event == "ACTIVE_PLAYER_SPECIALIZATION_CHANGED" and triggers.onSpecChanged then
    self:PromptOrApply(profileId, "specialization changed")
    return
  end

  if event == "SPELLS_CHANGED" and triggers.onSpellAvailabilityChanged then
    self:PromptOrApply(profileId, "available spells changed")
  end
end
