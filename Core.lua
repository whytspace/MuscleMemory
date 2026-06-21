local ADDON_NAME, MM = ...

MM.name = ADDON_NAME
MM.displayName = "Muscle Memory"
MM.version = "0.1.0"
MM.modules = MM.modules or {}
MM.events = MM.events or {}
MM.ui = MM.ui or {}
MM.util = MM.util or {}

MM.MAX_ACTION_SLOT = 120
MM.ACTIONS_PER_BAR = 12

function MM:RegisterModule(name, module)
  self.modules[name] = module
  module.name = name
  module.addon = self
end

function MM:CallModules(method, ...)
  for _, module in pairs(self.modules) do
    if type(module[method]) == "function" then
      module[method](module, ...)
    end
  end
end

function MM:IsReady()
  return self.ready == true
end

function MM:Initialize()
  if self.ready then
    return
  end

  self.DB:Initialize()
  self:CallModules("OnInitialize")
  self.ready = true
  self:Print("loaded. Use /mm to open Muscle Memory.")
end

function MM:ApplyProfile(profileId, options)
  return self.Applier:ApplyProfile(profileId, options)
end

function MM:PreviewProfile(profileId)
  return self.Applier:PreviewProfile(profileId)
end

function MM:Open()
  if self.UI and self.UI.Open then
    self.UI:Open()
  end
end

local eventFrame = CreateFrame("Frame")
MM.eventFrame = eventFrame

eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:SetScript("OnEvent", function(_, event, ...)
  if event == "ADDON_LOADED" then
    local addonName = ...
    if addonName == ADDON_NAME then
      MM:Initialize()
    end
    return
  end

  if MM.Events and MM.Events.OnEvent then
    MM.Events:OnEvent(event, ...)
  end
end)
