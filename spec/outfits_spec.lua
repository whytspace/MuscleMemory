local addon = require("spec.helpers.addon")

describe("Outfits", function()
  local MM, stubs
  before_each(function()
    MM, stubs = addon.fresh()
  end)

  it("returns name and icon for a known outfit", function()
    stubs:setOutfit(2, { name = "Outfit 1", icon = 134400 })
    assert.same({ name = "Outfit 1", icon = 134400 }, MM.Outfits.GetInfo(2))
    assert.is_true(MM.Outfits.IsKnown(2))
    assert.is_nil(MM.Outfits.GetInfo(9))
    assert.is_false(MM.Outfits.IsKnown(9))
  end)

  it("picks up a known outfit and rejects unknown ones", function()
    stubs:setOutfit(2, { name = "Outfit 1", icon = 134400 })
    assert.is_true(MM.Outfits.Pickup(2))
    assert.same({ type = "outfit", id = 2 }, stubs.world.cursor)

    stubs.world.cursor = nil
    assert.is_false(MM.Outfits.Pickup(9))
    assert.is_nil(stubs.world.cursor)
  end)

  it("captures an outfit slot with a name hint", function()
    stubs:setOutfit(2, { name = "Outfit 1", icon = 134400 })
    stubs:setSlot(1, { actionType = "outfit", id = 2 })
    assert.same({ type = "outfit", id = 2, nameHint = "Outfit 1" }, MM.Capture:FromSlot(1))
  end)

  it("rejects capturing an unknown outfit", function()
    stubs:setSlot(1, { actionType = "outfit", id = 9 })
    local assignment, reason = MM.Capture:FromSlot(1)
    assert.is_nil(assignment)
    assert.equals("outfit not found", reason)
  end)

  it("resolves an outfit assignment to its live name and icon", function()
    stubs:setOutfit(2, { name = "Outfit 1", icon = 134400 })
    local resolved = MM.Resolver:ResolveAction({ type = "outfit", id = 2, nameHint = "Stale Name" })
    assert.same({ kind = "outfit", id = 2, label = "Outfit 1", icon = 134400, pickupAvailable = true }, resolved)

    local missing, reason = MM.Resolver:ResolveAction({ type = "outfit", id = 9 })
    assert.is_nil(missing)
    assert.equals("outfit not found", reason)
  end)
end)
