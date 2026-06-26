local ADDON_NAME, MM = ...

MM.modules = MM.modules or {}
MM.ui = MM.ui or {}

MM.MAX_ACTION_SLOT = 180
MM.ACTIONS_PER_BAR = 12

-- Macro mode: a dynamicAction can render as a generated, per-character macro instead of
-- placing the resolved spell/item directly, so users can wrap it in mouseover /
-- focus / conditional logic while the dynamicAction still resolves the right action.
MM.MACRO_TEMPLATE_DEFAULT = "#showtooltip\n/use %name%"
-- The macro body is hard-capped at 255 by the client; the editable template is
-- held below that so substituting %name% (the resolved action's name) still fits.
MM.MACRO_BODY_LIMIT = 255
MM.MACRO_TEMPLATE_LIMIT = 200
-- Macro names cap at 64 bytes in storage (the default UI editbox stops at 16, but
-- CreateMacro/EditMacro accept up to 64 — verified in-game). We name generated macros
-- after their dynamicAction and suffix this marker so we can recognise (and safely clean
-- up) our own macros even if the tracking registry is ever lost. The dynamicAction name
-- is truncated to fit, leaving room for the marker so it always survives within the cap.
-- The marker is a no-break space (U+00A0): the font renders it as blank (not the
-- missing-glyph box a zero-width space draws), and being non-ASCII it survives
-- CreateMacro and is essentially impossible to collide with a user-named macro.
MM.MACRO_NAME_LIMIT = 64
MM.MACRO_NAME_MARKER = "\194\160"
-- The dynamic "?" macro icon: the bar then shows whatever the macro would cast.
MM.MACRO_DYNAMIC_ICON = 134400

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

function MM:Initialize()
  if self.ready then
    return
  end

  self.DB:Initialize()
  self:CallModules("OnInitialize")
  self.ready = true
  self:Print("loaded. Use /mm to open Muscle Memory.")
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
