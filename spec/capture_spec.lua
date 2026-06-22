local addon = require("spec.helpers.addon")

describe("Capture", function()
  local MM, stubs, env
  before_each(function()
    MM, stubs, env = addon.fresh()
  end)

  describe("FromSlot", function()
    it("rejects an invalid slot", function()
      local assignment, reason = MM.Capture:FromSlot(0)
      assert.is_nil(assignment)
      assert.equals("invalid action slot", reason)
    end)

    it("captures an empty slot", function()
      assert.same({ type = "empty" }, MM.Capture:FromSlot(5))
    end)

    it("captures spells and items by id", function()
      stubs:setSlot(1, { actionType = "spell", id = 1766 })
      assert.same({ type = "spell", id = 1766 }, MM.Capture:FromSlot(1))

      stubs:setSlot(2, { actionType = "item", id = 6948 })
      assert.same({ type = "item", id = 6948 }, MM.Capture:FromSlot(2))
    end)

    it("normalises mount variants to a mount assignment", function()
      stubs:setSlot(1, { actionType = "summonmount", id = 219 })
      assert.same({ type = "mount", id = 219 }, MM.Capture:FromSlot(1))

      stubs:setSlot(2, { actionType = "companion", subType = "MOUNT", id = 220 })
      assert.same({ type = "mount", id = 220 }, MM.Capture:FromSlot(2))
    end)

    it("captures an equipment set by name", function()
      stubs:setEquipmentSet("Tank", 7)
      stubs:setSlot(1, { actionType = "equipmentset", id = 7 })
      assert.same({ type = "equipmentset", name = "Tank" }, MM.Capture:FromSlot(1))
    end)

    it("captures a macro with body hash and hints", function()
      stubs:addGlobalMacro({ name = "Heal", icon = 9, body = "/cast Heal" })
      stubs:setSlot(1, { actionType = "macro", id = 1 })

      local assignment = MM.Capture:FromSlot(1)
      assert.equals("macro", assignment.type)
      assert.equals(1, assignment.indexHint)
      assert.equals("global", assignment.scope)
      assert.equals("Heal", assignment.nameHint)
      assert.equals(MM.Macros.HashBody("/cast Heal"), assignment.bodyHash)
    end)

    it("captures a slot macro by name and icon when the action id isn't a macro index", function()
      stubs:addGlobalMacro({ name = "Dup", icon = 11, body = "/one" })
      stubs:addGlobalMacro({ name = "Dup", icon = 22, body = "/two" })
      -- A bogus action id that GetMacroInfo can't resolve, so capture falls back
      -- to the slot's name + icon.
      stubs:setSlot(7, { actionType = "macro", id = 999, text = "Dup", texture = 22 })

      local assignment = MM.Capture:FromSlot(7)
      assert.equals("macro", assignment.type)
      assert.equals("Dup", assignment.nameHint)
      assert.equals(MM.Macros.HashBody("/two"), assignment.bodyHash)
    end)

    it("treats a flyout as ignore", function()
      stubs:setSlot(1, { actionType = "flyout", id = 1 })
      assert.same({ type = "ignore" }, MM.Capture:FromSlot(1))
    end)

    it("reports an unsupported action type", function()
      stubs:setSlot(1, { actionType = "battlepet", id = 1 })
      local assignment, reason = MM.Capture:FromSlot(1)
      assert.is_nil(assignment)
      assert.equals("unsupported action type battlepet", reason)
    end)
  end)

  describe("FromCursor", function()
    it("reports an unavailable cursor API", function()
      env.GetCursorInfo = nil
      local assignment, reason = MM.Capture:FromCursor()
      assert.is_nil(assignment)
      assert.equals("cursor API unavailable", reason)
    end)

    it("reports an empty cursor", function()
      local assignment, reason = MM.Capture:FromCursor()
      assert.is_nil(assignment)
      assert.equals("cursor is empty", reason)
    end)

    it("captures a spell from the cursor", function()
      stubs:setCursor({ type = "spell", id = 1766 })
      assert.same({ type = "spell", id = 1766 }, MM.Capture:FromCursor())
    end)

    it("reports an unsupported cursor type", function()
      stubs:setCursor({ type = "battlepet", id = 1 })
      local assignment, reason = MM.Capture:FromCursor()
      assert.is_nil(assignment)
      assert.equals("unsupported cursor type battlepet", reason)
    end)
  end)

  describe("CaptureSlot / CaptureFilledSlots", function()
    it("writes a captured assignment into the muscle", function()
      stubs:setSlot(5, { actionType = "spell", id = 1766 })
      local ok, kind = MM.Capture:CaptureSlot("Core", 5)
      assert.is_true(ok)
      assert.equals("spell", kind)
      assert.same({ type = "spell", id = 1766 }, MM.DB:GetMuscle("Core").slots[5])
    end)

    it("captures every filled slot and collects failures", function()
      stubs:setSlot(1, { actionType = "spell", id = 1766 })
      stubs:setSlot(2, { actionType = "item", id = 6948 })
      stubs:setSlot(3, { actionType = "battlepet", id = 1 })

      local captured, failures = MM.Capture:CaptureFilledSlots("Core")
      assert.equals(2, captured)
      assert.equals(1, #failures)
      assert.equals(3, failures[1].slot)
    end)
  end)
end)
