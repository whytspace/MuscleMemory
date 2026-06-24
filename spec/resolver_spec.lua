local addon = require("spec.helpers.addon")

describe("Resolver", function()
  local MM, stubs
  before_each(function()
    MM, stubs = addon.fresh()
  end)

  describe("ResolveAction guards", function()
    it("rejects a missing assignment", function()
      local resolved, reason = MM.Resolver:ResolveAction(nil)
      assert.is_nil(resolved)
      assert.equals("missing assignment", reason)
    end)

    it("rejects an unsupported type", function()
      local resolved, reason = MM.Resolver:ResolveAction({ type = "bogus" })
      assert.is_nil(resolved)
      assert.matches("unsupported assignment type", reason)
    end)
  end)

  it("resolves structural ignore and empty", function()
    assert.equals("ignore", MM.Resolver:ResolveAction({ type = "ignore" }).kind)
    assert.equals("empty", MM.Resolver:ResolveAction({ type = "empty" }).kind)
  end)

  describe("spell", function()
    it("resolves a known spell with availability", function()
      stubs:setSpell(1766, { name = "Kick", icon = 5, known = true })
      local resolved = MM.Resolver:ResolveAction({ type = "spell", id = 1766 })
      assert.equals("spell", resolved.kind)
      assert.equals("Kick", resolved.label)
      assert.equals(5, resolved.icon)
      assert.is_true(resolved.pickupAvailable)
    end)

    it("refuses an unavailable spell when availability is required", function()
      stubs:setSpell(1766, { name = "Kick", known = false })
      local resolved, reason = MM.Resolver:ResolveAction({ type = "spell", id = 1766 }, { requireAvailable = true })
      assert.is_nil(resolved)
      assert.equals("spell not known", reason)
    end)

    it("resolves a known-but-unavailable spell when availability is not required", function()
      stubs:setSpell(1766, { name = "Kick", known = false })
      local resolved = MM.Resolver:ResolveAction({ type = "spell", id = 1766 })
      assert.equals("spell", resolved.kind)
      assert.is_false(resolved.pickupAvailable)
    end)

    it("reports a spell that does not exist at all", function()
      local resolved, reason = MM.Resolver:ResolveAction({ type = "spell", id = 999 })
      assert.is_nil(resolved)
      assert.equals("spell not found", reason)
    end)
  end)

  describe("item / mount / equipmentset", function()
    it("resolves an existing but unowned item as unavailable", function()
      stubs:setItem(6948, { name = "HS", icon = 134414, count = 0 })
      local resolved = MM.Resolver:ResolveAction({ type = "item", id = 6948 })
      assert.equals("item", resolved.kind)
      assert.equals("HS", resolved.label)
      assert.equals(134414, resolved.icon)
      assert.is_false(resolved.pickupAvailable)
    end)

    it("refuses an unowned item when availability is required", function()
      stubs:setItem(6948, { name = "HS", count = 0 })
      local resolved, reason = MM.Resolver:ResolveAction({ type = "item", id = 6948 }, { requireAvailable = true })
      assert.is_nil(resolved)
      assert.equals("item not owned", reason)
    end)

    it("refuses an owned but unusable item (out of level range / wrong profession)", function()
      stubs:setItem(40772, { name = "Gnomish Army Knife", count = 1, usable = false })
      local resolved, reason = MM.Resolver:ResolveAction({ type = "item", id = 40772 }, { requireAvailable = true })
      assert.is_nil(resolved)
      assert.equals("item not usable", reason)
    end)

    it("marks an owned but unusable item as unavailable for pickup", function()
      stubs:setItem(40772, { name = "Gnomish Army Knife", count = 1, usable = false })
      local resolved = MM.Resolver:ResolveAction({ type = "item", id = 40772 })
      assert.equals("item", resolved.kind)
      assert.is_false(resolved.pickupAvailable)
    end)

    it("resolves an uncollected mount as unavailable", function()
      stubs:setMount(219, { name = "Strider", icon = 132248, collected = false })
      local resolved = MM.Resolver:ResolveAction({ type = "mount", id = 219 })
      assert.equals("mount", resolved.kind)
      assert.equals("Strider", resolved.label)
      assert.equals(132248, resolved.icon)
      assert.is_false(resolved.pickupAvailable)
    end)

    it("refuses an uncollected mount when availability is required", function()
      stubs:setMount(219, { name = "Strider", collected = false })
      local resolved, reason = MM.Resolver:ResolveAction({ type = "mount", id = 219 }, { requireAvailable = true })
      assert.is_nil(resolved)
      assert.equals("mount not known", reason)
    end)

    it("resolves an existing equipment set and rejects a missing one", function()
      stubs:setEquipmentSet("Tank", 7)
      assert.equals("equipmentset", MM.Resolver:ResolveAction({ type = "equipmentset", name = "Tank" }).kind)

      local resolved, reason = MM.Resolver:ResolveAction({ type = "equipmentset", name = "Healer" })
      assert.is_nil(resolved)
      assert.equals("equipment set not found", reason)
    end)
  end)

  describe("memory", function()
    local S, I
    before_each(function()
      S = MM.SpellIds
      I = MM.ItemIds
    end)

    it("resolves to the first usable candidate", function()
      stubs.world.class = "WARRIOR"
      stubs:setSpell(S.PUMMEL, { name = "Pummel", known = true })
      local resolved = MM.Resolver:ResolveAction({ type = "memory", id = "interrupt" })
      assert.equals("spell", resolved.kind)
      assert.equals(S.PUMMEL, resolved.id)
      assert.equals("Kick / Interrupt", resolved.memory.name)
    end)

    it("falls through to an owned, usable engineering item for a non-rez class", function()
      stubs.world.class = "MAGE"
      stubs:setItem(I.EMERGENCY_SOUL_LINK_Q1, { name = "Emergency Soul Link", count = 1, usable = true })
      local resolved = MM.Resolver:ResolveAction({ type = "memory", id = "battle_rez" })
      assert.equals("item", resolved.kind)
      assert.equals(I.EMERGENCY_SOUL_LINK_Q1, resolved.id)
      assert.equals("Battle Rez", resolved.memory.name)
    end)

    it("skips a rez item the player owns but cannot use (out of level range / no engineering)", function()
      stubs.world.class = "MAGE"
      stubs:setItem(I.CONVINCINGLY_REALISTIC_JUMPER_CABLES_Q3, { name = "Jumper Cables", count = 1, usable = false })
      stubs:setItem(I.EMERGENCY_SOUL_LINK_Q1, { name = "Emergency Soul Link", count = 1, usable = true })
      local resolved = MM.Resolver:ResolveAction({ type = "memory", id = "battle_rez" })
      assert.equals(I.EMERGENCY_SOUL_LINK_Q1, resolved.id)
    end)

    it("skips a level-capped rez item above its max level (levelMax condition)", function()
      stubs.world.class = "MAGE"
      stubs.world.level = 80 -- above the Reanimator's level-60 cap
      stubs:setItem(I.DISPOSABLE_SPECTROPHASIC_REANIMATOR, { name = "Reanimator", count = 1, usable = true })
      local resolved, reason = MM.Resolver:ResolveAction({ type = "memory", id = "battle_rez" })
      assert.is_nil(resolved)
      assert.matches("no matching candidate", reason)
    end)

    it("skips candidates whose class requirement does not match", function()
      stubs.world.class = "MAGE"
      stubs:setSpell(S.COMMAND_PET, { name = "Command Pet", known = true })
      local resolved, reason = MM.Resolver:ResolveAction({ type = "memory", id = "lust" })
      assert.is_nil(resolved)
      assert.matches("no matching candidate", reason)
    end)

    it("resolves a class-gated candidate for the right class", function()
      stubs.world.class = "HUNTER"
      stubs:setSpell(S.COMMAND_PET, { name = "Command Pet", known = true })
      local resolved = MM.Resolver:ResolveAction({ type = "memory", id = "lust" })
      assert.equals(S.COMMAND_PET, resolved.id)
    end)

    it("resolves a custom memory through the database", function()
      MM.DB:Memories().mine = { name = "Mine", candidates = { { type = "spell", id = 1766 } } }
      stubs:setSpell(1766, { name = "Kick", known = true })

      local resolved = MM.Resolver:ResolveAction({ type = "memory", source = "custom", id = "mine" })
      assert.equals(1766, resolved.id)
      assert.equals("Mine", resolved.memory.name)
    end)

    it("reports a missing memory", function()
      local resolved, reason = MM.Resolver:ResolveAction({ type = "memory", id = "does_not_exist" })
      assert.is_nil(resolved)
      assert.equals("memory not found", reason)
    end)
  end)
end)
