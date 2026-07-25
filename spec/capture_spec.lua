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

    it("captures an equipment set slot that reports the set name instead of its id", function()
      -- 12.0 action slots put the set NAME in GetActionInfo's id field.
      stubs:setEquipmentSet("Tank", 7)
      stubs:setSlot(1, { actionType = "equipmentset", id = "Tank" })
      assert.same({ type = "equipmentset", name = "Tank" }, MM.Capture:FromSlot(1))
    end)

    it("rejects an equipment set name that does not exist", function()
      stubs:setSlot(1, { actionType = "equipmentset", id = "Healer" })
      local assignment, reason = MM.Capture:FromSlot(1)
      assert.is_nil(assignment)
      assert.equals("equipment set not found", reason)
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
      assert.equals("/cast Heal", assignment.body)
    end)

    it("splits display and restore icons for a dynamic-icon macro", function()
      -- Dynamic "?" macro: GetMacroInfo and the slot both report the live resolved
      -- texture; only GetSelectedMacroIcon still knows the "?" was picked.
      stubs:addGlobalMacro({
        name = "Dyn",
        icon = 249170,
        selectedIcon = MM.MACRO_DYNAMIC_ICON,
        body = "#showtooltip\n/cast Dyn",
      })
      stubs:setSlot(1, { actionType = "macro", id = 1, texture = 249170 })

      local assignment = MM.Capture:FromSlot(1)
      assert.equals(249170, assignment.iconHint)
      assert.equals(MM.MACRO_DYNAMIC_ICON, assignment.restoreIcon)
    end)

    it("keeps a hardcoded icon as the restore icon for a static macro", function()
      stubs:addGlobalMacro({ name = "Belt", icon = 132120, body = "#showtooltip\n/use 10" })
      stubs:setSlot(1, { actionType = "macro", id = 1, texture = 132120 })

      local assignment = MM.Capture:FromSlot(1)
      assert.equals(132120, assignment.iconHint)
      assert.equals(132120, assignment.restoreIcon)
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

    it("captures a flyout by id", function()
      stubs:setSlot(1, { actionType = "flyout", id = 12 })
      assert.same({ type = "flyout", id = 12 }, MM.Capture:FromSlot(1))
    end)

    it("normalises a summoned battle pet to a battlepet assignment", function()
      stubs:setSlot(1, { actionType = "summonpet", id = "BattlePet-0-1" })
      assert.same({ type = "battlepet", id = "BattlePet-0-1" }, MM.Capture:FromSlot(1))
    end)

    it("reports an unsupported action type", function()
      -- Pet-bar abilities ("petaction") are intentionally out of scope.
      stubs:setSlot(1, { actionType = "petaction", id = 1 })
      local assignment, reason = MM.Capture:FromSlot(1)
      assert.is_nil(assignment)
      assert.equals("unsupported action type petaction", reason)
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

    it("captures an override spell from the cursor as its base spell", function()
      stubs:setSpell(431443, { name = "Chrono Flames", baseSpellId = 361469 })
      stubs:setCursor({ type = "spell", id = 431443 })
      assert.same({ type = "spell", id = 361469 }, MM.Capture:FromCursor())
    end)

    it("captures a flyout from the cursor", function()
      stubs:setCursor({ type = "flyout", id = 12 })
      assert.same({ type = "flyout", id = 12 }, MM.Capture:FromCursor())
    end)

    it("captures a battle pet from the cursor", function()
      stubs:setCursor({ type = "battlepet", id = "BattlePet-0-1" })
      assert.same({ type = "battlepet", id = "BattlePet-0-1" }, MM.Capture:FromCursor())
    end)

    it("reports an unsupported cursor type", function()
      stubs:setCursor({ type = "money", id = 1 })
      local assignment, reason = MM.Capture:FromCursor()
      assert.is_nil(assignment)
      assert.equals("unsupported cursor type money", reason)
    end)
  end)

  describe("CaptureSlot / CaptureFilledSlots", function()
    it("writes a captured assignment into the layer", function()
      stubs:setSlot(5, { actionType = "spell", id = 1766 })
      local ok, kind = MM.Capture:CaptureSlot("Core", 5)
      assert.is_true(ok)
      assert.equals("spell", kind)
      assert.same({ type = "spell", id = 1766 }, MM.DB:GetLayer("Core").slots[5])
    end)

    it("captures every filled slot and collects failures", function()
      stubs:setSlot(1, { actionType = "spell", id = 1766 })
      stubs:setSlot(2, { actionType = "item", id = 6948 })
      stubs:setSlot(3, { actionType = "petaction", id = 1 })

      local captured, failures = MM.Capture:CaptureFilledSlots("Core")
      assert.equals(2, captured)
      assert.equals(1, #failures)
      assert.equals(3, failures[1].slot)
    end)
  end)

  describe("HealMacroSnapshots", function()
    it("heals a frozen restore icon from the live macro's saved pick", function()
      -- An old capture stored GetMacroInfo's resolved texture; the macro still
      -- exists, so the real pick is re-read from GetSelectedMacroIcon.
      stubs:addGlobalMacro({
        name = "Dyn",
        icon = 249170,
        selectedIcon = MM.MACRO_DYNAMIC_ICON,
        body = "#showtooltip\n/cast Dyn",
      })
      MM.DB:SetSlot("Core", 1, {
        type = "macro",
        bodyHash = MM.Macros.HashBody("#showtooltip\n/cast Dyn"),
        nameHint = "Dyn",
        scope = "global",
        restoreIcon = 249170,
      })

      MM.Capture:HealMacroSnapshots()

      assert.equals(MM.MACRO_DYNAMIC_ICON, MM.DB:GetLayer("Core").slots[1].restoreIcon)
    end)

    it("syncs an edited body through the name fallback", function()
      stubs:addGlobalMacro({ name = "Burst", icon = 111, body = "/cast New" })
      MM.DB:SetSlot("Core", 1, {
        type = "macro",
        bodyHash = MM.Macros.HashBody("/cast Old"),
        body = "/cast Old",
        nameHint = "Burst",
        scope = "global",
      })

      MM.Capture:HealMacroSnapshots()

      local snapshot = MM.DB:GetLayer("Core").slots[1]
      assert.equals("/cast New", snapshot.body)
      assert.equals(MM.Macros.HashBody("/cast New"), snapshot.bodyHash)
      assert.equals(111, snapshot.restoreIcon)
    end)

    it("does not touch an assignment whose macro no longer exists", function()
      MM.DB:SetSlot("Core", 1, {
        type = "macro",
        bodyHash = "deadbeef",
        body = "/cast Gone",
        nameHint = "Gone",
        scope = "global",
        restoreIcon = 249170,
      })

      MM.Capture:HealMacroSnapshots()

      local snapshot = MM.DB:GetLayer("Core").slots[1]
      assert.equals(249170, snapshot.restoreIcon)
      assert.equals("/cast Gone", snapshot.body)
    end)

    it("debug-logs the macro name only when the snapshot actually changed", function()
      MM.DB:GetRoot().debug = true
      stubs:addGlobalMacro({ name = "Burst", icon = 111, body = "/cast New" })
      MM.DB:SetSlot("Core", 1, {
        type = "macro",
        bodyHash = MM.Macros.HashBody("/cast Old"),
        body = "/cast Old",
        nameHint = "Burst",
        scope = "global",
      })

      MM.Capture:HealMacroSnapshots()
      local first = table.concat(stubs.world.printed, "\n")
      assert.truthy(first:find('"Burst"', 1, true))

      -- A second pass finds nothing new and stays silent.
      stubs.world.printed = {}
      MM.Capture:HealMacroSnapshots()
      assert.equals(0, #stubs.world.printed)
    end)
  end)
end)
