local addon = require("spec.helpers.addon")

describe("EquipmentSets", function()
  local MM, stubs
  before_each(function()
    MM, stubs = addon.load()
  end)

  it("resolves an id by name", function()
    stubs:setEquipmentSet("Tank", 7)
    assert.equals(7, MM.EquipmentSets.GetId("Tank"))
    assert.is_nil(MM.EquipmentSets.GetId("Healer"))
    assert.is_nil(MM.EquipmentSets.GetId(nil))
  end)

  it("reports existence", function()
    stubs:setEquipmentSet("Tank", 7)
    assert.is_true(MM.EquipmentSets.Exists("Tank"))
    assert.is_false(MM.EquipmentSets.Exists("Healer"))
  end)

  describe("Pickup", function()
    it("picks an existing set up onto the cursor", function()
      stubs:setEquipmentSet("Tank", 7)
      assert.is_true(MM.EquipmentSets.Pickup("Tank"))
      assert.same({ type = "equipmentset", id = 7 }, stubs.world.cursor)
    end)

    it("returns false for an unknown set", function()
      assert.is_false(MM.EquipmentSets.Pickup("Healer"))
      assert.is_nil(stubs.world.cursor)
    end)
  end)
end)
