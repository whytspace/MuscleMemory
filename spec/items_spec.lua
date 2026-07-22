local addon = require("spec.helpers.addon")

describe("Items", function()
  local MM, stubs
  before_each(function()
    MM, stubs = addon.load()
  end)

  describe("GetInfo", function()
    it("returns nil for a nil id", function()
      assert.is_nil(MM.Items.GetInfo(nil))
    end)

    it("reads name, link and icon", function()
      stubs:setItem(6948, { name = "Hearthstone", link = "|hearth|", icon = 134414 })
      local info = MM.Items.GetInfo(6948)
      assert.equals("Hearthstone", info.name)
      assert.equals("|hearth|", info.link)
      assert.equals(134414, info.icon)
      assert.equals(6948, info.id)
    end)

    it("returns nil for an unknown item", function()
      assert.is_nil(MM.Items.GetInfo(123))
    end)
  end)

  describe("GetCount", function()
    it("returns 0 for nil or unknown items", function()
      assert.equals(0, MM.Items.GetCount(nil))
      assert.equals(0, MM.Items.GetCount(6948))
    end)

    it("returns the configured count", function()
      stubs:setItem(6948, { count = 3 })
      assert.equals(3, MM.Items.GetCount(6948))
    end)
  end)

  describe("IsOwned", function()
    it("is true when at least one is in bags", function()
      stubs:setItem(6948, { count = 1 })
      assert.is_true(MM.Items.IsOwned(6948))
    end)

    it("is true when equipped even with a zero bag count", function()
      stubs:setItem(6948, { count = 0, equipped = true })
      assert.is_true(MM.Items.IsOwned(6948))
    end)

    it("is true for a learned toy with a zero bag count", function()
      stubs:setItem(119210, { count = 0, isToy = true })
      assert.is_true(MM.Items.IsOwned(119210))
    end)

    it("is false when neither in bags, equipped nor a known toy", function()
      stubs:setItem(6948, { count = 0 })
      assert.is_false(MM.Items.IsOwned(6948))
    end)
  end)

  describe("IsUsable", function()
    it("is false for a nil id", function()
      assert.is_false(MM.Items.IsUsable(nil))
    end)

    it("is true when the item meets its use requirements", function()
      stubs:setItem(6948, { usable = true })
      assert.is_true(MM.Items.IsUsable(6948))
    end)

    it("is false when the tooltip shows an unmet level or class requirement", function()
      stubs:setItem(40772, { requirement = "Requires Level 80" })
      assert.is_false(MM.Items.IsUsable(40772))
    end)

    it("is true for an item the player doesn't own but has no unmet requirement", function()
      -- Ownership ignored: a usable item you're out of still counts.
      stubs:setItem(21215, { name = "Fruitcake", count = 0 })
      assert.is_true(MM.Items.IsUsable(21215))
    end)

    it("is false for a profession the player lacks, despite IsUsableItem (the red tooltip line)", function()
      -- IsUsableItem ignores profession requirements, so this is the case it misses.
      stubs:setItem(184308, { usable = true, requirement = "Requires Engineering" })
      assert.is_false(MM.Items.IsUsable(184308))
    end)

    it("treats an uncached item as usable", function()
      assert.is_true(MM.Items.IsUsable(123))
    end)

    it("is true for a learned toy although IsUsableItem reports it unusable outside the bags", function()
      stubs:setItem(212500, { count = 0, isToy = true, usable = false })
      assert.is_true(MM.Items.IsUsable(212500))
    end)

    it("is false for a learned toy the Toy Box reports unusable", function()
      stubs:setItem(212500, { count = 0, isToy = true, toyUsable = false })
      assert.is_false(MM.Items.IsUsable(212500))
    end)

    it("is false for an unlearned toy (recognised as a toy, but not in the Toy Box)", function()
      -- A toy must be learned to place; unlearned -> falls through.
      stubs:setItem(182694, { count = 0, toy = true })
      assert.is_false(MM.Items.IsUsable(182694))
    end)
  end)

  describe("GetQualityMarkup", function()
    it("returns nil for an item whose link has no quality crystal", function()
      stubs:setItem(6948, {})
      assert.is_nil(MM.Items.GetQualityMarkup(6948))
    end)

    it("lifts the quality crystal markup out of the item link", function()
      local markup = "|A:Professions-ChatIcon-Quality-12-Tier1:17:15::1|a"
      stubs:setItem(248486, {
        link = "|cnIQ1:|Hitem:248486::::|h[Emergency Soul Link " .. markup .. "]|h|r",
      })
      assert.equals(markup, MM.Items.GetQualityMarkup(248486))
    end)
  end)

  describe("Pickup", function()
    it("picks the item up onto the cursor", function()
      assert.is_true(MM.Items.Pickup(6948))
      assert.same({ type = "item", id = 6948 }, stubs.world.cursor)
    end)

    it("picks a learned toy up through the Toy Box", function()
      stubs:setItem(212500, { count = 0, isToy = true })
      assert.is_true(MM.Items.Pickup(212500))
      assert.same({ type = "item", id = 212500, fromToyBox = true }, stubs.world.cursor)
    end)
  end)
end)
