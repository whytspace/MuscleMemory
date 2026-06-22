local addon = require("spec.helpers.addon")

describe("Spells", function()
  local MM, stubs, env
  before_each(function()
    MM, stubs, env = addon.load()
  end)

  describe("GetInfo", function()
    it("returns nil for a nil id", function()
      assert.is_nil(MM.Spells.GetInfo(nil))
    end)

    it("reads name and icon from C_Spell", function()
      stubs:setSpell(1766, { name = "Kick", icon = 132219 })
      local info = MM.Spells.GetInfo(1766)
      assert.equals("Kick", info.name)
      assert.equals(132219, info.icon)
      assert.equals(1766, info.spellId)
    end)

    it("returns nil for an unknown spell", function()
      assert.is_nil(MM.Spells.GetInfo(999999))
    end)

    it("falls back to the legacy GetSpellInfo global", function()
      env.C_Spell = nil
      env.GetSpellInfo = function(id)
        if id == 42 then
          return "Legacy", nil, 555
        end
      end
      local info = MM.Spells.GetInfo(42)
      assert.equals("Legacy", info.name)
      assert.equals(555, info.icon)
    end)
  end)

  describe("IsKnown", function()
    it("is false for nil", function()
      assert.is_false(MM.Spells.IsKnown(nil))
    end)

    it("is true for a known player spell", function()
      stubs:setSpell(1766, { known = true })
      assert.is_true(MM.Spells.IsKnown(1766))
    end)

    it("is false for a spell that exists but is not known", function()
      stubs:setSpell(1766, { known = false })
      assert.is_false(MM.Spells.IsKnown(1766))
    end)
  end)

  describe("Pickup", function()
    it("picks the spell up onto the cursor", function()
      assert.is_true(MM.Spells.Pickup(1766))
      assert.same({ type = "spell", id = 1766 }, stubs.world.cursor)
    end)

    it("returns false when no pickup API is available", function()
      env.C_Spell = nil
      env.PickupSpell = nil
      assert.is_false(MM.Spells.Pickup(1766))
    end)
  end)
end)
