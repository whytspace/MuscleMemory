local addon = require("spec.helpers.addon")

-- The stable action spell id WoW reports for the Single Button Assistant.
local SBA = 1229376

describe("Single Button Assistant", function()
  local MM, stubs
  before_each(function()
    MM, stubs = addon.fresh()
  end)

  it("does not crash matching a spell the bar never indexes", function()
    -- FindSpellActionButtons returns nil for the assisted-combat spell (and any
    -- spell on no bar); IsOnActionSlot must tolerate that rather than ipairs(nil).
    assert.is_false(MM.Spells.IsOnActionSlot(SBA, 59))
  end)

  it("captures the assistant, not the ability it currently recommends", function()
    -- A live assistant slot reports its recommended ability (here 1766) through
    -- GetActionInfo; capture must store the assistant's own stable spell instead.
    stubs:setAssistedCombat({ spell = SBA, available = true })
    stubs:setSlot(59, { actionType = "spell", id = 1766, assistedCombat = true })
    assert.same({ type = "spell", id = SBA }, MM.Capture:FromSlot(59))
  end)

  it("resolves availability from the feature, not IsKnown", function()
    stubs:setSpell(SBA, { name = "Single Button Assist", icon = 7, known = false })
    stubs:setAssistedCombat({ spell = SBA, available = true })

    local resolved = MM.Resolver:ResolveAction({ type = "spell", id = SBA })
    assert.equals("spell", resolved.kind)
    assert.equals("Single Button Assist", resolved.label)
    assert.is_true(resolved.pickupAvailable)

    stubs:setAssistedCombat({ spell = SBA, available = false })
    assert.is_false(MM.Resolver:ResolveAction({ type = "spell", id = SBA }).pickupAvailable)
  end)

  it("matches an assistant assignment against an assistant slot only", function()
    stubs:setAssistedCombat({ spell = SBA, available = true })
    stubs:setSlot(59, { actionType = "spell", id = SBA, assistedCombat = true })
    stubs:setSlot(60, { actionType = "spell", id = 1766 })

    assert.is_true(MM.Actions.IsAssignmentInSlot({ type = "spell", id = SBA }, 59))
    assert.is_false(MM.Actions.IsAssignmentInSlot({ type = "spell", id = SBA }, 60))
  end)

  it("treats an already-placed assistant as unchanged (no re-apply loop)", function()
    stubs:setSpell(SBA, { name = "Single Button Assist", known = false })
    stubs:setAssistedCombat({ spell = SBA, available = true })
    stubs:setSlot(59, { actionType = "spell", id = SBA, assistedCombat = true })

    local resolved = MM.Resolver:ResolveAction({ type = "spell", id = SBA })
    assert.is_true(MM.Actions.IsResolvedInSlot(resolved, 59))
  end)
end)
