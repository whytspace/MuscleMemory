local addon = require("spec.helpers.addon")

describe("Applier", function()
  local MM, stubs

  -- A layer stacked below Core in the active profile.
  local function addLowerLayer()
    return (MM.DB:CreateLayer("Lower"))
  end

  before_each(function()
    MM, stubs = addon.fresh()
    stubs:setSpell(1766, { name = "Kick", icon = 5, known = true })
    stubs:setSpell(2050, { name = "Heal", icon = 6, known = true })
  end)

  local function setHunterLustSlot(slot)
    local S = MM.SpellIds
    stubs:setCharacter({ class = "HUNTER" })
    stubs:setSpell(S.COMMAND_PET, { name = "Command Pet", known = true })
    stubs:setSpell(S.PRIMAL_RAGE, { name = "Primal Rage", known = true })
    MM.DB:SetSlot("Core", slot, { type = "action", id = "lust" })
    stubs:setSlot(slot, { actionType = "spell", id = S.PRIMAL_RAGE, baseSpellId = S.COMMAND_PET })
  end

  describe("BuildPlan precedence", function()
    it("lets the higher layer win a contested slot", function()
      local lower = addLowerLayer()
      MM.DB:SetSlot("Core", 1, { type = "spell", id = 1766 })
      MM.DB:SetSlot(lower, 1, { type = "spell", id = 2050 })

      local plan = MM.Applier:BuildPlan()
      assert.equals(1766, plan.slots[1].resolved.id)
    end)

    it("keeps a higher layer's unowned item over a lower layer's spell", function()
      -- Regression: an unowned/uncached item must still win its slot, not vanish
      -- and flip to the lower layer (the phantom-prompt non-determinism).
      local lower = addLowerLayer()
      MM.DB:SetSlot("Core", 1, { type = "item", id = 241301 }) -- unowned, uncached
      MM.DB:SetSlot(lower, 1, { type = "spell", id = 1766 })

      local plan = MM.Applier:BuildPlan()
      assert.equals("item", plan.slots[1].resolved.kind)
      assert.equals(241301, plan.slots[1].resolved.id)
      assert.is_true(plan.slots[1].resolved.pickupAvailable)
    end)

    it("falls through an unusable item to a usable one below, ignoring ownership", function()
      -- Unusable item yields to a usable-but-unowned item below; the spell under
      -- that is never reached.
      local mid = MM.DB:CreateLayer("Mid")
      local low = MM.DB:CreateLayer("Low")
      stubs:setItem(40772, { name = "Engineering Item", count = 1, requirement = "Requires Engineering" }) -- can't use
      stubs:setItem(5512, { name = "Healthstone", count = 0, usable = true }) -- usable, unowned
      MM.DB:SetSlot("Core", 1, { type = "item", id = 40772 }) -- highest: unusable -> fall through
      MM.DB:SetSlot(mid, 1, { type = "item", id = 5512 }) -- usable but unowned -> wins (grey)
      MM.DB:SetSlot(low, 1, { type = "spell", id = 1766 }) -- never reached

      local plan = MM.Applier:BuildPlan()
      assert.equals("item", plan.slots[1].resolved.kind)
      assert.equals(5512, plan.slots[1].resolved.id)
      assert.is_true(plan.slots[1].resolved.pickupAvailable)
    end)

    it("skips a layer whose conditions don't match the character", function()
      MM.DB:SetSlot("Core", 1, { type = "spell", id = 1766 })
      MM.DB:GetLayer("Core").conditions = { classes = { "WARRIOR" } }

      local plan = MM.Applier:BuildPlan()
      assert.is_nil(plan.slots[1])

      MM.DB:GetLayer("Core").conditions = { classes = { "MAGE" } }
      plan = MM.Applier:BuildPlan()
      assert.equals(1766, plan.slots[1].resolved.id)
    end)

    it("lets an ignore in the higher layer yield to the lower one", function()
      local lower = addLowerLayer()
      MM.DB:SetSlot("Core", 1, { type = "ignore" })
      MM.DB:SetSlot(lower, 1, { type = "spell", id = 2050 })

      local plan = MM.Applier:BuildPlan()
      assert.equals(2050, plan.slots[1].resolved.id)
    end)

    it("treats an empty assignment as a stopper", function()
      local lower = addLowerLayer()
      MM.DB:SetSlot("Core", 1, { type = "empty" })
      MM.DB:SetSlot(lower, 1, { type = "spell", id = 2050 })

      local plan = MM.Applier:BuildPlan()
      assert.equals("empty", plan.slots[1].resolved.kind)
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
      MM.DB:GetLayer("Core").slots[200] = { type = "empty" }
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

    it("is false when Hunter Lust's Command Pet slot reports Primal Rage", function()
      setHunterLustSlot(10)
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

    it("refuses an action that is not currently available, naming it", function()
      local entry = { slot = 3, resolved = { kind = "spell", id = 1766, label = "Kick", pickupAvailable = false } }
      local ok, reason = MM.Applier:ApplyEntry(entry)
      assert.is_false(ok)
      assert.equals("Kick is not available", reason)
    end)

    it("picks up and places a resolved spell", function()
      local entry = { slot = 3, resolved = { kind = "spell", id = 1766, pickupAvailable = true } }
      assert.is_true(MM.Applier:ApplyEntry(entry))
      assert.equals(1766, stubs.world.slots[3].id)
      assert.is_nil(stubs.world.cursor)
    end)

    it("recreates a restorable macro before placing it", function()
      local entry = {
        slot = 3,
        resolved = {
          kind = "macro",
          restore = { name = "Mine", body = "/cast Mine", scope = "character" },
          label = "Mine",
        },
      }
      assert.is_true(MM.Applier:ApplyEntry(entry))
      assert.equals("Mine", stubs.world.charMacros[1].name)
      assert.equals("macro", stubs.world.slots[3].actionType)
      assert.equals(121, stubs.world.slots[3].id)
    end)

    it("fails a restorable macro when creation fails", function()
      for index = 1, 30 do
        stubs:addCharacterMacro({ name = "M" .. index, body = "/cast " .. index })
      end
      local entry = {
        slot = 3,
        resolved = {
          kind = "macro",
          restore = { name = "Mine", body = "/cast Mine", scope = "character" },
          label = "Mine",
        },
      }
      local ok, reason = MM.Applier:ApplyEntry(entry)
      assert.is_false(ok)
      assert.equals("character macro slots are full", reason)
    end)
  end)

  describe("ApplyProfile", function()
    local function printedMatches(world, pattern)
      for _, line in ipairs(world.printed) do
        if line:match(pattern) then
          return true
        end
      end
      return false
    end

    it("applies a resolved spell into an empty slot", function()
      MM.DB:SetSlot("Core", 10, { type = "spell", id = 1766 })
      assert.is_true(MM.Applier:ApplyProfile())
      assert.equals("spell", stubs.world.slots[10].actionType)
      assert.equals(1766, stubs.world.slots[10].id)
    end)

    it("reports each change as `from → to` with an updated count", function()
      MM.DB:SetSlot("Core", 10, { type = "spell", id = 1766 })
      stubs:setSlot(10, { actionType = "spell", id = 2050 }) -- Heal currently there
      MM.Applier:ApplyProfile()
      assert.is_true(printedMatches(stubs.world, "Heal → Kick"))
      assert.is_true(printedMatches(stubs.world, "1 slot updated"))
    end)

    it("counts unavailable actions separately, not as failures", function()
      stubs:setSpell(4321, { name = "Fetch", known = false })
      MM.DB:SetSlot("Core", 10, { type = "spell", id = 4321 })

      assert.is_true(MM.Applier:ApplyProfile())
      assert.is_true(printedMatches(stubs.world, "Fetch is not available"))
      assert.is_true(printedMatches(stubs.world, "no changes, 1 slot not available"))
      assert.is_false(printedMatches(stubs.world, "failed"))
    end)

    it("does not report a phantom update for an unresolved slot that is already empty", function()
      -- Regression: apply used to "clear" the already-empty slot again and report
      -- "empty → empty, 1 slot updated" forever, while preview said "no changes".
      MM.DB:SetFallback("clear")
      MM.DB:SetSlot("Core", 11, { type = "spell", id = 999 }) -- unresolvable, slot empty

      assert.is_false(MM.Applier:HasUnappliedChanges())
      assert.is_true(MM.Applier:ApplyProfile())
      assert.is_true(printedMatches(stubs.world, "no changes"))
    end)

    it("skips a resolved slot that already matches", function()
      MM.DB:SetSlot("Core", 10, { type = "spell", id = 1766 })
      stubs:setSlot(10, { actionType = "spell", id = 1766 })

      assert.is_true(MM.Applier:ApplyProfile())
      assert.is_true(printedMatches(stubs.world, "no changes"))
    end)

    it("renders a macro for a macro-mode smart action and stays idempotent", function()
      local key = MM.DB:CreateSmartAction("Kick")
      MM.DB:AddCandidate(key, { type = "spell", id = 1766 })
      MM.DB:SetSmartActionMode(key, "macro")
      MM.DB:SetSlot("Core", 10, { type = "action", source = "custom", id = key })

      assert.is_true(MM.Applier:ApplyProfile())

      -- A character macro is placed, not the spell itself.
      assert.equals("macro", stubs.world.slots[10].actionType)
      assert.equals(1, #stubs.world.charMacros)
      assert.equals("#showtooltip\n/use Kick", stubs.world.charMacros[1].body)
      assert.is_false(MM.Applier:HasUnappliedChanges())

      -- The macro carries the owner marker so it can be recognised later.
      assert.is_true(MM.Macros.IsOwned(stubs.world.charMacros[1]))

      -- Re-applying reuses the macro rather than creating a second one.
      assert.is_true(MM.Applier:ApplyProfile())
      assert.equals(1, #stubs.world.charMacros)
    end)

    it("treats a smart action rename as a pending change and updates the macro title", function()
      local key = MM.DB:CreateSmartAction("Kick")
      MM.DB:AddCandidate(key, { type = "spell", id = 1766 })
      MM.DB:SetSmartActionMode(key, "macro")
      MM.DB:SetSlot("Core", 10, { type = "action", source = "custom", id = key })
      assert.is_true(MM.Applier:ApplyProfile())
      local originalName = stubs.world.charMacros[1].name
      assert.is_false(MM.Applier:HasUnappliedChanges())

      MM.DB:RenameSmartAction(key, "Kicker")
      -- The macro title is now stale, so a change is pending.
      assert.is_true(MM.Applier:HasUnappliedChanges())

      assert.is_true(MM.Applier:ApplyProfile())
      assert.equals(1, #stubs.world.charMacros) -- renamed in place, not duplicated
      assert.are_not.equal(originalName, stubs.world.charMacros[1].name)
      assert.is_true(MM.Macros.IsOwned(stubs.world.charMacros[1]))
      assert.is_false(MM.Applier:HasUnappliedChanges())
    end)

    it("sweeps a marked macro the registry no longer tracks", function()
      local key = MM.DB:CreateSmartAction("Kick")
      MM.DB:AddCandidate(key, { type = "spell", id = 1766 })
      MM.DB:SetSmartActionMode(key, "macro")
      MM.DB:SetSlot("Core", 10, { type = "action", source = "custom", id = key })
      assert.is_true(MM.Applier:ApplyProfile())
      assert.equals(1, #stubs.world.charMacros)

      -- Simulate a lost registry: the marked macro is now untracked.
      MM.DB:GetCharacterState().macroRegistry = {}
      MM.DB:SetSlot("Core", 10, { type = "empty" })
      assert.is_true(MM.Applier:ApplyProfile())
      assert.equals(0, #stubs.world.charMacros)
    end)

    it("falls back to placing the action when the macro body is over the limit", function()
      stubs:setSpell(9001, { name = string.rep("Q", 260), icon = 7, known = true })
      local key = MM.DB:CreateSmartAction("Long")
      MM.DB:AddCandidate(key, { type = "spell", id = 9001 })
      MM.DB:SetSmartActionMode(key, "macro")
      MM.DB:SetSlot("Core", 10, { type = "action", source = "custom", id = key })

      assert.is_true(MM.Applier:ApplyProfile())
      -- Too long to be a macro, so the spell is placed directly and no macro made.
      assert.equals("spell", stubs.world.slots[10].actionType)
      assert.equals(9001, stubs.world.slots[10].id)
      assert.equals(0, #stubs.world.charMacros)
    end)

    it("cleans up the generated macro when a smart action leaves macro mode", function()
      local key = MM.DB:CreateSmartAction("Kick")
      MM.DB:AddCandidate(key, { type = "spell", id = 1766 })
      MM.DB:SetSmartActionMode(key, "macro")
      MM.DB:SetSlot("Core", 10, { type = "action", source = "custom", id = key })
      assert.is_true(MM.Applier:ApplyProfile())
      assert.equals(1, #stubs.world.charMacros)

      MM.DB:SetSmartActionMode(key, "normal")
      assert.is_true(MM.Applier:ApplyProfile())
      -- The slot now holds the spell directly and the orphaned macro is gone.
      assert.equals("spell", stubs.world.slots[10].actionType)
      assert.equals(1766, stubs.world.slots[10].id)
      assert.equals(0, #stubs.world.charMacros)
    end)

    it("restores a mount via its summon spell and stays idempotent", function()
      -- Capture stores the id the bar reports for a mount, which is its summon
      -- spellId (253007), not the journal mountId (219). GetInfo maps it back, so
      -- the mount resolves and applies via that spell.
      stubs:setMount(219, { name = "Strider", spellId = 253007, collected = true })
      MM.DB:SetSlot("Core", 10, { type = "mount", id = 253007 })
      assert.is_true(MM.Applier:ApplyProfile())
      assert.equals("spell", stubs.world.slots[10].actionType)
      assert.equals(253007, stubs.world.slots[10].id)
      assert.is_false(MM.Applier:HasUnappliedChanges())
    end)

    it("recognises a mount captured from a companion slot", function()
      -- The bar reports a mount as companion/MOUNT with its summon spellId as the
      -- id; capture stores that id. It must still resolve and read as in-slot
      -- rather than re-applying every time.
      stubs:setMount(219, { name = "Strider", spellId = 253007, collected = true })
      stubs.world.slots[10] = { actionType = "companion", id = 253007, subType = "MOUNT" }
      local assignment = MM.Capture:FromSlot(10)
      assert.same({ type = "mount", id = 253007 }, assignment)
      -- It must resolve (no "mount not found") and read as already in-slot.
      assert.equals("Strider", (MM.Resolver:ResolveAction(assignment)).label)
      MM.DB:SetSlot("Core", 10, assignment)
      assert.is_false(MM.Applier:HasUnappliedChanges())
    end)

    it("restores the Summon Random Favorite Mount button and stays idempotent", function()
      stubs:setSpell(150544, { name = "Summon Random Favorite Mount", icon = 413588, known = true })
      MM.DB:SetSlot("Core", 10, { type = "mount", id = 268435455 })
      assert.is_true(MM.Applier:ApplyProfile())
      assert.equals(268435455, stubs.world.slots[10].id)
      assert.is_false(MM.Applier:HasUnappliedChanges())
    end)

    it("refuses to apply during combat", function()
      MM.DB:SetSlot("Core", 10, { type = "spell", id = 1766 })
      stubs.world.inCombat = true
      assert.is_false(MM.Applier:ApplyProfile())
      assert.is_nil(stubs.world.slots[10])
    end)

    it("refuses to apply when the active layers contain invalid slots", function()
      MM.DB:GetLayer("Core").slots[200] = { type = "empty" }
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
      stubs:setSlot(10, { actionType = "spell", id = 2050 }) -- Heal currently there
      local plan = MM.Applier:PreviewProfile()
      assert.is_table(plan)
      assert.is_true(printedMatches(stubs.world, "Heal → Kick"))
      assert.is_true(printedMatches(stubs.world, "1 slot would change"))
      assert.equals("spell", stubs.world.slots[10].actionType) -- preview never applies
      assert.equals(2050, stubs.world.slots[10].id)
    end)

    it("reports when nothing would change", function()
      MM.DB:SetSlot("Core", 10, { type = "spell", id = 1766 })
      stubs:setSlot(10, { actionType = "spell", id = 1766 })
      MM.Applier:PreviewProfile()
      assert.is_true(printedMatches(stubs.world, "no changes"))
    end)

    it("reports no changes when Hunter Lust's Command Pet slot reports Primal Rage", function()
      setHunterLustSlot(10)
      MM.Applier:PreviewProfile()
      assert.is_true(printedMatches(stubs.world, "no changes"))
    end)

    it("counts unavailable actions in the summary like apply does", function()
      stubs:setSpell(4321, { name = "Fetch", known = false })
      MM.DB:SetSlot("Core", 10, { type = "spell", id = 4321 })

      MM.Applier:PreviewProfile()
      assert.is_true(printedMatches(stubs.world, "Fetch is not available"))
      assert.is_true(printedMatches(stubs.world, "no changes, 1 slot not available"))
    end)

    it("notes that a macro-mode slot will create a macro", function()
      local key = MM.DB:CreateSmartAction("Kick")
      MM.DB:AddCandidate(key, { type = "spell", id = 1766 })
      MM.DB:SetSmartActionMode(key, "macro")
      MM.DB:SetSlot("Core", 10, { type = "action", source = "custom", id = key })

      MM.Applier:PreviewProfile()
      assert.is_true(printedMatches(stubs.world, "Kick %(creates a macro%)"))
    end)

    it("notes that an existing macro will be updated after a rename", function()
      local key = MM.DB:CreateSmartAction("Kick")
      MM.DB:AddCandidate(key, { type = "spell", id = 1766 })
      MM.DB:SetSmartActionMode(key, "macro")
      MM.DB:SetSlot("Core", 10, { type = "action", source = "custom", id = key })
      MM.Applier:ApplyProfile()

      MM.DB:RenameSmartAction(key, "Kicker")
      MM.Applier:PreviewProfile()
      assert.is_true(printedMatches(stubs.world, "Kick %(updates the macro%)"))
    end)
  end)
end)
