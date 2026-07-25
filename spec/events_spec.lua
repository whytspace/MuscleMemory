local addon = require("spec.helpers.addon")

describe("Events", function()
  local MM, stubs
  local prompts, dismissals, previews, applies

  before_each(function()
    MM, stubs = addon.fresh()
    prompts = 0
    dismissals = 0
    previews = 0
    applies = 0
    -- UI is not loaded in the harness; stand in for the apply prompt.
    MM.UI = {
      PromptApply = function()
        prompts = prompts + 1
      end,
      DismissApplyPrompt = function()
        dismissals = dismissals + 1
      end,
    }
    -- Count the print / auto-apply branches without exercising the real plan.
    MM.Applier.PreviewProfile = function()
      previews = previews + 1
    end
    MM.Applier.ApplyProfile = function()
      applies = applies + 1
    end
    stubs:setSpell(1766, { name = "Kick", known = true })
    MM.DB:SetSlot("Core", 10, { type = "spell", id = 1766 })
  end)

  -- SPELLS_CHANGED trailing-debounces through C_Timer, so the reaction lands only
  -- once the queued callback fires. flushTimers stands in for the burst settling.
  it("prompts to apply when the active profile has unapplied changes", function()
    MM.Events:OnEvent("SPELLS_CHANGED")
    stubs:flushTimers()
    assert.equals(1, prompts)
    -- The preview prints alongside the prompt so the trigger reason is captured
    -- even if the diff later settles away.
    assert.equals(1, previews)
  end)

  it("stays silent during combat", function()
    stubs.world.inCombat = true
    MM.Events:OnEvent("SPELLS_CHANGED")
    stubs:flushTimers()
    assert.equals(0, prompts)
  end)

  it("does not prompt when the bars already match", function()
    stubs:setSlot(10, { actionType = "spell", id = 1766 })
    MM.Events:OnEvent("SPELLS_CHANGED")
    stubs:flushTimers()
    assert.equals(0, prompts)
  end)

  it("dismisses a stale prompt when a settled re-eval finds no changes", function()
    -- A settled read with nothing to apply clears a prompt that an earlier,
    -- unsettled read may have raised.
    stubs:setSlot(10, { actionType = "spell", id = 1766 })
    MM.Events:OnEvent("SPELLS_CHANGED")
    stubs:flushTimers()
    assert.equals(0, prompts)
    assert.equals(1, dismissals)
  end)

  it("prints instead of prompting when the response is print", function()
    MM.DB:SetResponse("print")
    MM.Events:OnEvent("SPELLS_CHANGED")
    stubs:flushTimers()
    assert.equals(0, prompts)
    assert.equals(1, previews)
  end)

  it("auto-applies when the response is apply", function()
    MM.DB:SetResponse("apply")
    MM.Events:OnEvent("SPELLS_CHANGED")
    stubs:flushTimers()
    assert.equals(0, prompts)
    assert.equals(1, applies)
  end)

  it("does nothing on changes when the response is ignore", function()
    MM.DB:SetResponse("ignore")
    MM.Events:OnEvent("SPELLS_CHANGED")
    stubs:flushTimers()
    assert.equals(0, prompts)
    assert.equals(0, previews)
    assert.equals(0, applies)
  end)

  it("does not prompt to apply on a bare action bar edit", function()
    MM.Events:OnEvent("ACTIONBAR_SLOT_CHANGED", 1)
    assert.equals(0, prompts)
  end)

  it("registers the re-evaluation events on initialize", function()
    MM.Events:OnInitialize()
    assert.is_true(MM.eventFrame._events["ACTIVE_PLAYER_SPECIALIZATION_CHANGED"])
    assert.is_true(MM.eventFrame._events["SPELLS_CHANGED"])
    assert.is_true(MM.eventFrame._events["ACTIONBAR_SLOT_CHANGED"])
  end)

  describe("trailing debounce", function()
    -- Login and spec swaps stream data in a burst; an early read can misjudge a
    -- slot before item tooltips load, so the reaction is deferred until it settles.
    it("defers the reaction until the timer settles", function()
      MM.Events:OnEvent("SPELLS_CHANGED")
      -- Nothing yet: the read is scheduled, not run inline.
      assert.equals(0, prompts)

      stubs:flushTimers()
      assert.equals(1, prompts)
    end)

    it("collapses a burst of events into a single evaluation", function()
      -- The generation counter means only the last scheduled callback acts; the
      -- earlier ones from the same burst are stale and do nothing.
      MM.Events:OnEvent("SPELLS_CHANGED")
      MM.Events:OnEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED")
      MM.Events:OnEvent("SPELLS_CHANGED")

      stubs:flushTimers()
      assert.equals(1, prompts)
    end)
  end)
end)
