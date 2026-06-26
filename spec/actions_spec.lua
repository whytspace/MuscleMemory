local addon = require("spec.helpers.addon")

describe("Actions", function()
  local MM, stubs
  before_each(function()
    MM, stubs = addon.fresh()
  end)

  describe("IsValidSlot", function()
    it("accepts integers in 1..180", function()
      assert.is_true(MM.Actions.IsValidSlot(1))
      assert.is_true(MM.Actions.IsValidSlot(180))
      assert.is_true(MM.Actions.IsValidSlot(60))
    end)

    it("rejects out-of-range, non-integer and non-number slots", function()
      assert.is_false(MM.Actions.IsValidSlot(0))
      assert.is_false(MM.Actions.IsValidSlot(181))
      assert.is_false(MM.Actions.IsValidSlot(-1))
      assert.is_false(MM.Actions.IsValidSlot(1.5))
      assert.is_false(MM.Actions.IsValidSlot("5"))
      assert.is_false(MM.Actions.IsValidSlot(nil))
    end)
  end)

  describe("GetSlotLabel", function()
    it("labels slots by their real (non-linear) action bar", function()
      assert.equals("bar 1 button 1", MM.Actions.GetSlotLabel(1))
      assert.equals("bar 1 button 12", MM.Actions.GetSlotLabel(12))
      assert.equals("bar 2 button 1", MM.Actions.GetSlotLabel(61)) -- bottom left
      assert.equals("bar 3 button 12", MM.Actions.GetSlotLabel(60)) -- bottom right
      assert.equals("bar 8 button 12", MM.Actions.GetSlotLabel(180))
      assert.equals("stance 1 button 1", MM.Actions.GetSlotLabel(73)) -- form/stance page
      assert.equals("skyriding button 1", MM.Actions.GetSlotLabel(121)) -- skyriding page
    end)

    it("labels a slot that isn't on any managed bar", function()
      assert.equals("page 2 button 1", MM.Actions.GetSlotLabel(13))
      assert.equals("slot 133", MM.Actions.GetSlotLabel(133)) -- leftover override range
    end)
  end)

  describe("GetSlotHotkey", function()
    it("abbreviates a slot's bound key in WoW's action-bar style", function()
      stubs:setBinding("ACTIONBUTTON1", "1")
      stubs:setBinding("MULTIACTIONBAR1BUTTON1", "F1") -- bottom left, slots 61-72
      stubs:setBinding("MULTIACTIONBAR1BUTTON2", "ALT-BUTTON4") -- Alt + mouse button 4
      stubs:setBinding("MULTIACTIONBAR1BUTTON3", "BUTTON3") -- middle mouse
      stubs:setBinding("MULTIACTIONBAR1BUTTON4", "BUTTON5") -- mouse button 5
      stubs:setBinding("MULTIACTIONBAR7BUTTON12", "SHIFT-F12") -- bar 8, slot 180
      assert.equals("1", MM.Actions.GetSlotHotkey(1))
      assert.equals("F1", MM.Actions.GetSlotHotkey(61))
      assert.equals("AM4", MM.Actions.GetSlotHotkey(62))
      assert.equals("M3", MM.Actions.GetSlotHotkey(63))
      assert.equals("M5", MM.Actions.GetSlotHotkey(64))
      assert.equals("SF12", MM.Actions.GetSlotHotkey(180))
    end)

    it("shows no key for paged bars (Page 2, stance, Skyriding)", function()
      stubs:setBinding("ACTIONBUTTON1", "1")
      assert.is_nil(MM.Actions.GetSlotHotkey(13)) -- page 2 button 1
      assert.is_nil(MM.Actions.GetSlotHotkey(73)) -- stance 1 button 1
      assert.is_nil(MM.Actions.GetSlotHotkey(121)) -- skyriding button 1
    end)

    it("returns nil when nothing is bound", function()
      assert.is_nil(MM.Actions.GetSlotHotkey(5))
    end)
  end)

  describe("GetAssignmentLabel", function()
    it("labels the structural assignment types", function()
      assert.equals("Ignore", MM.Actions.GetAssignmentLabel(nil))
      assert.equals("Ignore", MM.Actions.GetAssignmentLabel({ type = "ignore" }))
      assert.equals("Empty", MM.Actions.GetAssignmentLabel({ type = "empty" }))
    end)

    it("labels a spell with and without info", function()
      stubs:setSpell(1766, { name = "Kick" })
      assert.equals("Kick (spell 1766)", MM.Actions.GetAssignmentLabel({ type = "spell", id = 1766 }))
      assert.equals("Spell ID: 999", MM.Actions.GetAssignmentLabel({ type = "spell", id = 999 }))
    end)

    it("labels an item, macro and equipment set", function()
      stubs:setItem(6948, { name = "Hearthstone" })
      assert.equals("Hearthstone (item 6948)", MM.Actions.GetAssignmentLabel({ type = "item", id = 6948 }))
      assert.equals("Macro: Heal", MM.Actions.GetAssignmentLabel({ type = "macro", nameHint = "Heal" }))
      assert.equals("Equipment Set: Tank", MM.Actions.GetAssignmentLabel({ type = "equipmentset", name = "Tank" }))
    end)

    it("labels a dynamic action by its display name", function()
      assert.equals("Bloodlust", MM.Actions.GetAssignmentLabel({ type = "dynamicaction", id = "lust" }))
    end)
  end)

  describe("IsAssignmentInSlot", function()
    it("treats a nil assignment as always matching", function()
      assert.is_true(MM.Actions.IsAssignmentInSlot(nil, 1))
    end)

    it("matches an empty assignment against an empty slot only", function()
      assert.is_true(MM.Actions.IsAssignmentInSlot({ type = "empty" }, 1))
      stubs:setSlot(1, { actionType = "spell", id = 5 })
      assert.is_false(MM.Actions.IsAssignmentInSlot({ type = "empty" }, 1))
    end)

    it("matches a spell by id", function()
      stubs:setSlot(3, { actionType = "spell", id = 1766 })
      assert.is_true(MM.Actions.IsAssignmentInSlot({ type = "spell", id = 1766 }, 3))
      assert.is_false(MM.Actions.IsAssignmentInSlot({ type = "spell", id = 5 }, 3))
    end)

    it("matches a base spell when the slot reports its override", function()
      stubs:setSlot(3, { actionType = "spell", id = MM.SpellIds.PRIMAL_RAGE, baseSpellId = MM.SpellIds.COMMAND_PET })
      assert.is_true(MM.Actions.IsAssignmentInSlot({ type = "spell", id = MM.SpellIds.COMMAND_PET }, 3))
    end)

    it("falls back to matching a spell by action text", function()
      stubs:setSpell(1766, { name = "Kick" })
      stubs:setSlot(3, { actionType = "spell", id = 99, text = "Kick" })
      assert.is_true(MM.Actions.IsAssignmentInSlot({ type = "spell", id = 1766 }, 3))
    end)

    it("matches item, mount and equipment-set identities", function()
      stubs:setSlot(4, { actionType = "item", id = 6948 })
      assert.is_true(MM.Actions.IsAssignmentInSlot({ type = "item", id = 6948 }, 4))

      stubs:setSlot(5, { actionType = "summonmount", id = 219 })
      assert.is_true(MM.Actions.IsAssignmentInSlot({ type = "mount", id = 219 }, 5))

      stubs:setEquipmentSet("Tank", 7)
      stubs:setSlot(6, { actionType = "equipmentset", id = 7 })
      assert.is_true(MM.Actions.IsAssignmentInSlot({ type = "equipmentset", name = "Tank" }, 6))
    end)

    it("matches a macro by body hash when the index moved", function()
      stubs:setSlot(7, { actionType = "macro", id = 121 })
      stubs.world.charMacros[1] = { name = "M", body = "/cast M" }
      local assignment = { type = "macro", indexHint = 2, bodyHash = MM.Macros.HashBody("/cast M") }
      assert.is_true(MM.Actions.IsAssignmentInSlot(assignment, 7))
    end)

    it("matches a macro by name and body hash when the slot id isn't a macro index", function()
      stubs:addGlobalMacro({ name = "Foo", icon = 5, body = "/cast Foo" })
      stubs:setSlot(7, { actionType = "macro", id = 999, text = "Foo" })
      local assignment = { type = "macro", indexHint = 1, nameHint = "Foo", bodyHash = MM.Macros.HashBody("/cast Foo") }
      assert.is_true(MM.Actions.IsAssignmentInSlot(assignment, 7))
    end)
  end)

  describe("GetAssignmentIconState", function()
    it("describes structural kinds", function()
      assert.same({ kind = "empty" }, MM.Actions.GetAssignmentIconState({ type = "empty" }, 1))
      assert.same({ kind = "ignore" }, MM.Actions.GetAssignmentIconState({ type = "ignore" }, 1))
    end)

    it("returns the icon texture for a known spell", function()
      stubs:setSpell(1766, { icon = 132219 })
      assert.same(
        { kind = "icon", texture = 132219 },
        MM.Actions.GetAssignmentIconState({ type = "spell", id = 1766 }, 1)
      )
    end)

    it("preserves the slot when an icon cannot be determined", function()
      assert.same({ kind = "preserve" }, MM.Actions.GetAssignmentIconState({ type = "spell", id = 999 }, 1))
    end)

    it("uses the live slot texture for a nil assignment", function()
      stubs:setSlot(2, { actionType = "spell", id = 1, texture = 8888 })
      assert.same({ kind = "icon", texture = 8888 }, MM.Actions.GetAssignmentIconState(nil, 2))
    end)
  end)
end)
