local addon = require("spec.helpers.addon")

describe("Applier", function()
  local MM, stubs

  -- A muscle stacked below Core in the active profile.
  local function addLowerMuscle()
    return (MM.DB:CreateMuscle("Lower"))
  end

  before_each(function()
    MM, stubs = addon.fresh()
    stubs:setSpell(1766, { name = "Kick", icon = 5, known = true })
    stubs:setSpell(2050, { name = "Heal", icon = 6, known = true })
  end)

  describe("BuildPlan precedence", function()
    it("lets the higher muscle win a contested slot", function()
      local lower = addLowerMuscle()
      MM.DB:SetSlot("Core", 1, { type = "spell", id = 1766 })
      MM.DB:SetSlot(lower, 1, { type = "spell", id = 2050 })

      local plan = MM.Applier:BuildPlan()
      assert.equals(1766, plan.slots[1].resolved.id)
    end)

    it("skips a muscle whose conditions don't match the character", function()
      MM.DB:SetSlot("Core", 1, { type = "spell", id = 1766 })
      MM.DB:GetMuscle("Core").conditions = { classes = { "WARRIOR" } }

      local plan = MM.Applier:BuildPlan()
      assert.is_nil(plan.slots[1])

      MM.DB:GetMuscle("Core").conditions = { classes = { "MAGE" } }
      plan = MM.Applier:BuildPlan()
      assert.equals(1766, plan.slots[1].resolved.id)
    end)

    it("lets an ignore in the higher muscle yield to the lower one", function()
      local lower = addLowerMuscle()
      MM.DB:SetSlot("Core", 1, { type = "ignore" })
      MM.DB:SetSlot(lower, 1, { type = "spell", id = 2050 })

      local plan = MM.Applier:BuildPlan()
      assert.equals(2050, plan.slots[1].resolved.id)
    end)

    it("lets a real action in the lower muscle override an empty above it", function()
      local lower = addLowerMuscle()
      MM.DB:SetSlot("Core", 1, { type = "empty" })
      MM.DB:SetSlot(lower, 1, { type = "spell", id = 2050 })

      local plan = MM.Applier:BuildPlan()
      assert.equals(2050, plan.slots[1].resolved.id)
    end)

    it("keeps an empty assignment when nothing else claims the slot", function()
      MM.DB:SetSlot("Core", 1, { type = "empty" })
      local plan = MM.Applier:BuildPlan()
      assert.equals("empty", plan.slots[1].resolved.kind)
    end)

    it("records an unresolved slot with its reason", function()
      MM.DB:SetSlot("Core", 1, { type = "spell", id = 999 })
      local plan = MM.Applier:BuildPlan()
      assert.is_nil(plan.slots[1].resolved)
      assert.equals("spell not found", plan.slots[1].unresolvedReason)
    end)

    it("flags invalid slot keys as conflicts", function()
      MM.DB:GetMuscle("Core").slots[200] = { type = "empty" }
      local plan = MM.Applier:BuildPlan()
      assert.equals(1, #plan.conflicts)
      assert.equals("200", plan.conflicts[1].slot)
    end)
  end)

  describe("HasUnappliedChanges", function()
    it("is true when a resolved action differs from the live slot", function()
      MM.DB:SetSlot("Core", 10, { type = "spell", id = 1766 })
      assert.is_true(MM.Applier:HasUnappliedChanges())
    end)

    it("is false when the live slot already matches", function()
      MM.DB:SetSlot("Core", 10, { type = "spell", id = 1766 })
      stubs:setSlot(10, { actionType = "spell", id = 1766 })
      assert.is_false(MM.Applier:HasUnappliedChanges())
    end)

    it("is true for an unresolved slot the clear fallback would empty", function()
      MM.DB:SetFallback("clear")
      MM.DB:SetSlot("Core", 11, { type = "spell", id = 999 })
      stubs:setSlot(11, { actionType = "spell", id = 5 })
      assert.is_true(MM.Applier:HasUnappliedChanges())
    end)
  end)

  describe("CanApply", function()
    it("refuses during combat lockdown", function()
      stubs.world.inCombat = true
      local ok, reason = MM.Applier:CanApply()
      assert.is_false(ok)
      assert.equals("combat lockdown", reason)
    end)

    it("refuses while the cursor is holding something", function()
      stubs:setCursor({ type = "spell", id = 1 })
      local ok, reason = MM.Applier:CanApply()
      assert.is_false(ok)
      assert.equals("cursor is not empty", reason)
    end)

    it("allows when out of combat with an empty cursor", function()
      assert.is_true(MM.Applier:CanApply())
    end)
  end)

  describe("ApplyEntry", function()
    it("clears the slot for an empty assignment", function()
      stubs:setSlot(3, { actionType = "spell", id = 5 })
      local ok = MM.Applier:ApplyEntry({ slot = 3, resolved = { kind = "empty" } })
      assert.is_true(ok)
      assert.is_nil(stubs.world.slots[3])
    end)

    it("leaves an unresolved slot unchanged under the keep fallback", function()
      local ok, reason = MM.Applier:ApplyEntry({ slot = 3, resolved = nil, fallback = "keep" })
      assert.is_true(ok)
      assert.equals("left unresolved slot unchanged", reason)
    end)

    it("refuses an action that is not currently available", function()
      local entry = { slot = 3, resolved = { kind = "spell", id = 1766, pickupAvailable = false } }
      local ok, reason = MM.Applier:ApplyEntry(entry)
      assert.is_false(ok)
      assert.equals("action is not currently available", reason)
    end)

    it("picks up and places a resolved spell", function()
      local entry = { slot = 3, resolved = { kind = "spell", id = 1766, pickupAvailable = true } }
      assert.is_true(MM.Applier:ApplyEntry(entry))
      assert.equals(1766, stubs.world.slots[3].id)
      assert.is_nil(stubs.world.cursor)
    end)
  end)

  describe("ApplyProfile", function()
    it("applies a resolved spell into an empty slot", function()
      MM.DB:SetSlot("Core", 10, { type = "spell", id = 1766 })
      assert.is_true(MM.Applier:ApplyProfile())
      assert.equals("spell", stubs.world.slots[10].actionType)
      assert.equals(1766, stubs.world.slots[10].id)
    end)

    it("refuses to apply during combat", function()
      MM.DB:SetSlot("Core", 10, { type = "spell", id = 1766 })
      stubs.world.inCombat = true
      assert.is_false(MM.Applier:ApplyProfile())
      assert.is_nil(stubs.world.slots[10])
    end)

    it("refuses to apply when the active muscles contain invalid slots", function()
      MM.DB:GetMuscle("Core").slots[200] = { type = "empty" }
      assert.is_false(MM.Applier:ApplyProfile())
    end)
  end)

  describe("PreviewProfile", function()
    local function printedMatches(world, pattern)
      for _, line in ipairs(world.printed) do
        if line:match(pattern) then
          return true
        end
      end
      return false
    end

    it("reports slots that would change without touching the bars", function()
      MM.DB:SetSlot("Core", 10, { type = "spell", id = 1766 })
      local plan = MM.Applier:PreviewProfile()
      assert.is_table(plan)
      assert.is_true(printedMatches(stubs.world, "would change"))
      assert.is_nil(stubs.world.slots[10]) -- preview never applies
    end)

    it("reports when nothing would change", function()
      MM.DB:SetSlot("Core", 10, { type = "spell", id = 1766 })
      stubs:setSlot(10, { actionType = "spell", id = 1766 })
      MM.Applier:PreviewProfile()
      assert.is_true(printedMatches(stubs.world, "no changes"))
    end)
  end)
end)
