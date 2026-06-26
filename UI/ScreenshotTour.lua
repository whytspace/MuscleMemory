local ADDON_NAME, MM = ...

-- An automated marketing-screenshot run: build a self-contained showcase profile,
-- walk the tabs capturing a transparent matte of each, then restore everything.
-- Maintainer tool, driven by /mm shot tour.
local Tour = {}
MM.ScreenshotTour = Tour
MM:RegisterModule("ScreenshotTour", Tour)

-- Let a view settle (tab switch, addon load) before the matte starts capturing.
local SETTLE = 0.3

-- The slot in the showcase layer that holds a dynamic action, so the Layers grid
-- shows real captured spells alongside one purpose-based slot.
local SHOWCASE_SLOT = 1

-- Build a throwaway "Showcase" profile and make it active. Returns a teardown
-- handle describing everything created so Restore can undo it exactly.
local function buildShowcase()
  local handle = {}

  local profileId = MM.DB:CreateProfile("Showcase")
  handle.profileId = profileId
  MM.DB:SetActiveProfile(profileId)

  -- A populated base layer: capture whatever the current character has on its
  -- bars (valid icons, no guessing), then drop a dynamic action into one slot.
  local layerId = MM.DB:CreateLayer("Main")
  handle.layerId = layerId
  MM.Capture:CaptureFilledSlots(layerId)
  MM.DB:SetSlot(layerId, SHOWCASE_SLOT, { type = "dynamicaction", source = "predefined", id = "lust" })

  -- A custom macro-mode dynamic action: copy the predefined Interrupt (already a
  -- focus macro with every class's kick) into an editable profile action.
  local macroId = MM.DB:CopyPredefinedDynamicAction("interrupt", "showcase-macro", "Focus Interrupt")
  if macroId then
    handle.macroId = macroId
    MM.DB:SetDynamicActionMode(macroId, "macro")
    MM.DB:SetDynamicActionTemplate(macroId, "#showtooltip\n/use [@focus,harm][] %name%")

    -- Render the macro for THIS character and write a real macro so Blizzard's
    -- macro window can show the substituted body. Skipped if nothing resolves
    -- (e.g. a class with no interrupt) or macro slots are full.
    local resolved = MM.Resolver:ResolveDynamicActionAssignment({ source = "custom", id = macroId })
    local body = resolved and MM.Macros.ResolvedAsMacro(resolved)
    if body then
      local name = MM.Macros.MacroName(resolved.dynamicAction)
      -- Clear any leftover macro of the same name from an interrupted earlier run,
      -- so we don't accumulate duplicates or select the wrong one.
      local leftover = GetMacroIndexByName(name)
      while leftover and leftover > 0 do
        MM.Macros.Delete(leftover)
        leftover = GetMacroIndexByName(name)
      end
      -- Record the name only if the macro was actually created, so later lookups
      -- and cleanup don't chase a macro that doesn't exist.
      if MM.Macros.Create(name, body) then
        handle.macroName = name
      end
    end
  end

  return handle
end

local function restore(saved, handle)
  -- UI selection state first, then swap off the showcase before deleting it.
  MM.ui.state.tab = saved.tab
  MM.ui.state.dynamicAction = saved.dynamicAction
  MM.ui.state.candidate = saved.candidate

  MM.DB:SetActiveProfile(saved.profile)
  MM.DB:SetSelectedLayerId(saved.layer)
  MM.DB:SetSelectedSlot(saved.slot)

  -- Delete by name (the index can shift), so we always remove our own macro.
  if handle.macroName then
    local macroIndex = GetMacroIndexByName(handle.macroName)
    if macroIndex and macroIndex > 0 then
      MM.Macros.Delete(macroIndex)
    end
  end
  if handle.profileId then
    MM.DB:DeleteProfile(handle.profileId)
  end
  if MacroFrame and HideUIPanel then
    HideUIPanel(MacroFrame)
    -- Put the macro frame's strata back the way we found it.
    if handle.macroStrata then
      MacroFrame:SetFrameStrata(handle.macroStrata)
    end
  end
  local dropdown = MM.ui.ProfilesTab and MM.ui.ProfilesTab.playerDropdown
  if dropdown and dropdown.CloseMenu then
    dropdown:CloseMenu()
  end

  MM.UI:Refresh()
  MM:Print("screenshot tour complete — restored your profile and selections.")
end

-- Open Blizzard's macro window and select the generated macro so its body shows.
-- Returns the frame to capture, or nil if it isn't available. The macro frame
-- corrupts its scroll list if its strata changes after the list is built, so we
-- raise it to TOOLTIP (above the backdrop) FIRST and build at that strata; the
-- capture then leaves its strata alone (raise = false).
local function openMacroFrame(name, handle)
  if C_AddOns and C_AddOns.LoadAddOn then
    C_AddOns.LoadAddOn("Blizzard_MacroUI")
  end
  if not MacroFrame then
    return nil
  end

  handle.macroStrata = handle.macroStrata or MacroFrame:GetFrameStrata()
  -- Raise before showing/building so the list is laid out at the final strata.
  if MacroFrame:IsShown() then
    HideUIPanel(MacroFrame)
  end
  MacroFrame:SetFrameStrata("TOOLTIP")
  ShowUIPanel(MacroFrame)
  MacroFrameTab2:Click()
  if MacroFrame.Update then
    MacroFrame:Update()
  end

  if name then
    C_Timer.After(0.3, function()
      local macroIndex = GetMacroIndexByName(name)
      if macroIndex and macroIndex > 0 then
        -- SelectMacro wants the position within the current tab, not the absolute
        -- macro index. Character macros are offset by MAX_ACCOUNT_MACROS, so map
        -- the absolute index back to its tab-relative position.
        local accountMacros = MAX_ACCOUNT_MACROS or 120
        local tabIndex = macroIndex > accountMacros and (macroIndex - accountMacros) or macroIndex
        MacroFrame:SelectMacro(tabIndex)
        if MacroFrame.Update then
          MacroFrame:Update()
        end
      end
    end)
  end
  return MacroFrame
end

-- Each step arranges a view and returns the frame to capture (nil to skip).
local function buildSteps(handle)
  return {
    {
      key = "layers",
      label = "Layers tab",
      arrange = function()
        MM.DB:SetSelectedLayerId(handle.layerId)
        MM.DB:SetSelectedSlot(SHOWCASE_SLOT)
        MM.UI:SelectTab("layers")
        return MM.UI.frame
      end,
    },
    {
      key = "dynamic-actions",
      label = "Dynamic Actions — Bloodlust",
      arrange = function()
        MM.ui.state.dynamicAction = { source = "predefined", id = "lust" }
        MM.ui.state.candidate = nil
        MM.UI:SelectTab("dynamicActions")
        return MM.UI.frame
      end,
    },
    {
      key = "macro-editor",
      label = "Dynamic Actions — macro editor",
      arrange = function()
        if not handle.macroId then
          return nil
        end
        MM.ui.state.dynamicAction = { source = "custom", id = handle.macroId }
        MM.ui.state.candidate = nil
        MM.UI:SelectTab("dynamicActions")
        return MM.UI.frame
      end,
    },
    {
      key = "macro-window",
      label = "Blizzard macro window — rendered macro",
      -- Extra time for the macro frame to load, build its list, and select.
      settle = 1.4,
      -- openMacroFrame positions the frame itself; the capture must not restrata it.
      raise = false,
      arrange = function()
        if not handle.macroName then
          MM:Warn("no rendered macro to show (nothing resolved or macro slots full) — skipping.")
          return nil
        end
        return openMacroFrame(handle.macroName, handle)
      end,
      -- Hide the macro window before later shots so it doesn't bleed into them.
      after = function()
        if MacroFrame and HideUIPanel then
          HideUIPanel(MacroFrame)
        end
      end,
    },
    {
      key = "profiles",
      label = "Profiles tab",
      arrange = function()
        MM.UI:SelectTab("profiles")
        -- Open the per-character selector so the screenshot shows the override
        -- in action, not just a closed dropdown.
        local dropdown = MM.ui.ProfilesTab and MM.ui.ProfilesTab.playerDropdown
        if dropdown and dropdown.OpenMenu then
          dropdown:OpenMenu()
        end
        return MM.UI.frame
      end,
    },
  }
end

local function runSteps(steps, index, done)
  local step = steps[index]
  if not step then
    done()
    return
  end

  -- Guard the arrange so a failing step still proceeds to the next and, crucially,
  -- reaches restore at the end (otherwise the showcase profile and macro leak).
  local ok, target = pcall(step.arrange)
  if not ok then
    MM:Warn("step '" .. step.label .. "' failed: " .. tostring(target))
    target = nil
  end
  MM:Print(string.format("shot %d/%d: %s", index, #steps, step.label))
  C_Timer.After(step.settle or SETTLE, function()
    local function advance()
      if step.after then
        step.after()
      end
      runSteps(steps, index + 1, done)
    end

    if target then
      MM.Screenshot:CaptureMatte(target, advance, step.raise)
    else
      advance()
    end
  end)
end

-- Build the showcase, capture `steps`, then restore. Shared by the full tour and
-- the single-view command.
local function start(self, steps, intro)
  if self.running then
    MM:Warn("a screenshot tour is already running.")
    return
  end
  if InCombatLockdown and InCombatLockdown() then
    MM:Warn("can't run the screenshot tour in combat.")
    return
  end

  local saved = {
    profile = MM.DB:GetActiveProfileId(),
    layer = MM.DB:GetSelectedLayerId(),
    slot = MM.DB:GetSelectedSlot(),
    tab = MM.ui.state.tab,
    dynamicAction = MM.ui.state.dynamicAction,
    candidate = MM.ui.state.candidate,
  }

  self.running = true
  MM:Open()
  -- Centre the window so every capture is framed the same.
  MM.UI:ResetPosition()
  -- Preload the macro UI now so it's built by the time the macro shot runs,
  -- rather than loading empty on first open.
  if C_AddOns and C_AddOns.LoadAddOn then
    C_AddOns.LoadAddOn("Blizzard_MacroUI")
  end
  local handle = buildShowcase()

  MM:Print(intro)
  runSteps(steps(handle), 1, function()
    restore(saved, handle)
    self.running = false
  end)
end

function Tour:Run()
  start(self, buildSteps, "screenshot tour: building Showcase profile and capturing each view.")
end

-- Capture a single view (faster iteration). Same build/restore, one matte.
function Tour:RunOne(key)
  if not key then
    MM:Warn("usage: /mm shot view <layers|dynamic-actions|macro-editor|macro-window|profiles>")
    return
  end
  start(self, function(handle)
    for _, step in ipairs(buildSteps(handle)) do
      if step.key == key then
        return { step }
      end
    end
    MM:Warn("unknown view '" .. key .. "'.")
    return {}
  end, "screenshot view '" .. key .. "': building Showcase profile.")
end
