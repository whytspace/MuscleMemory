local addon = require("spec.helpers.addon")

describe("Events", function()
  local MM, stubs
  local prompts

  before_each(function()
    MM, stubs = addon.fresh()
    prompts = 0
    -- UI is not loaded in the harness; stand in for the apply prompt.
    MM.UI = {
      PromptApply = function()
        prompts = prompts + 1
      end,
    }
    stubs:setSpell(1766, { name = "Kick", known = true })
    MM.DB:SetSlot("Core", 10, { type = "spell", id = 1766 })
  end)

  it("prompts to apply when the active profile has unapplied changes", function()
    MM.Events:OnEvent("SPELLS_CHANGED")
    assert.equals(1, prompts)
  end)

  it("stays silent during combat", function()
    stubs.world.inCombat = true
    MM.Events:OnEvent("SPELLS_CHANGED")
    assert.equals(0, prompts)
  end)

  it("does not prompt when the bars already match", function()
    stubs:setSlot(10, { actionType = "spell", id = 1766 })
    MM.Events:OnEvent("SPELLS_CHANGED")
    assert.equals(0, prompts)
  end)

  it("does not prompt to apply on a bare action bar edit", function()
    MM.Events:OnEvent("ACTIONBAR_SLOT_CHANGED", 1)
    assert.equals(0, prompts)
  end)

  it("registers the re-evaluation events on initialize", function()
    MM.Events:OnInitialize()
    assert.is_true(MM.eventFrame._events["PLAYER_REGEN_ENABLED"])
    assert.is_true(MM.eventFrame._events["ACTIVE_PLAYER_SPECIALIZATION_CHANGED"])
    assert.is_true(MM.eventFrame._events["SPELLS_CHANGED"])
    assert.is_true(MM.eventFrame._events["ACTIONBAR_SLOT_CHANGED"])
  end)
end)
