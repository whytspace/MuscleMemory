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

    it("resolves an override spell on its base spell (spec renames like Chrono Flames)", function()
      stubs:setSpell(431443, { name = "Chrono Flames", known = false, baseSpellId = 361469 })
      stubs:setSpell(361469, { name = "Living Flame", icon = 7, known = true })
      local resolved = MM.Resolver:ResolveAction({ type = "spell", id = 431443 }, { requireAvailable = true })
      assert.equals(361469, resolved.id)
      assert.equals("Living Flame", resolved.label)
      assert.is_true(resolved.pickupAvailable)
    end)

    it("reports a spell that does not exist at all", function()
      local resolved, reason = MM.Resolver:ResolveAction({ type = "spell", id = 999 })
      assert.is_nil(resolved)
      assert.equals("spell not found", reason)
    end)
  end)

  describe("item / mount / equipmentset", function()
    it("resolves an unowned item as placeable (placed grey, not skipped)", function()
      stubs:setItem(6948, { name = "HS", icon = 134414, count = 0 })
      local resolved = MM.Resolver:ResolveAction({ type = "item", id = 6948 })
      assert.equals("item", resolved.kind)
      assert.equals("HS", resolved.label)
      assert.equals(134414, resolved.icon)
      assert.is_true(resolved.pickupAvailable)
    end)

    it("resolves a not-yet-cached item on its id alone (stable precedence)", function()
      -- Uncached (no setItem) must still resolve placeable, so precedence is stable.
      local resolved, reason = MM.Resolver:ResolveAction({ type = "item", id = 241301 })
      assert.is_nil(reason)
      assert.equals("item", resolved.kind)
      assert.is_true(resolved.pickupAvailable)
    end)

    it("refuses an unowned item when availability is required", function()
      stubs:setItem(6948, { name = "HS", count = 0 })
      local resolved, reason = MM.Resolver:ResolveAction({ type = "item", id = 6948 }, { requireAvailable = true })
      assert.is_nil(resolved)
      assert.equals("item not owned", reason)
    end)

    it("refuses an owned but unusable item (out of level range / wrong profession)", function()
      stubs:setItem(40772, { name = "Gnomish Army Knife", count = 1, requirement = "Requires Level 80" })
      local resolved, reason = MM.Resolver:ResolveAction({ type = "item", id = 40772 }, { requireAvailable = true })
      assert.is_nil(resolved)
      assert.equals("item not usable", reason)
    end)

    it("does not resolve an unusable item (red requirement) so it falls through", function()
      -- Unusable (owned or not) -> nil, so it yields to the layer below.
      stubs:setItem(40772, { name = "Gnomish Army Knife", count = 1, requirement = "Requires Engineering" })
      local resolved, reason = MM.Resolver:ResolveAction({ type = "item", id = 40772 })
      assert.is_nil(resolved)
      assert.equals("item not usable", reason)
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

  describe("macro", function()
    it("returns a restorable resolved action for a missing macro with a stored body", function()
      local resolved = MM.Resolver:ResolveAction({
        type = "macro",
        bodyHash = "deadbeef",
        nameHint = "Gone",
        body = "/cast Gone",
        scope = "character",
      })
      assert.equals("macro", resolved.kind)
      assert.is_nil(resolved.macro)
      assert.equals("Gone", resolved.restore.name)
      assert.equals("/cast Gone", resolved.restore.body)
      assert.equals("character", resolved.restore.scope)
    end)

    it("restores the raw macro icon, not the live display texture", function()
      -- A dynamic-icon macro captures its live resolved texture for display but the
      -- "?" placeholder as its raw icon; restore must use the placeholder so the
      -- recreated macro stays dynamic instead of freezing the resolved texture.
      local resolved = MM.Resolver:ResolveAction({
        type = "macro",
        bodyHash = "deadbeef",
        nameHint = "Gone",
        body = "#showtooltip\n/cast Gone",
        scope = "character",
        iconHint = 249170,
        restoreIcon = MM.MACRO_DYNAMIC_ICON,
      })
      assert.equals(MM.MACRO_DYNAMIC_ICON, resolved.restore.icon)
    end)

    it("falls back to the display icon for captures saved before restoreIcon", function()
      local resolved = MM.Resolver:ResolveAction({
        type = "macro",
        bodyHash = "deadbeef",
        nameHint = "Gone",
        body = "/cast Gone",
        scope = "character",
        iconHint = 132120,
      })
      assert.equals(132120, resolved.restore.icon)
    end)

    it("stays unresolved for a missing macro without a stored body", function()
      local resolved, reason = MM.Resolver:ResolveAction({
        type = "macro",
        bodyHash = "deadbeef",
        nameHint = "Gone",
        scope = "character",
      })
      assert.is_nil(resolved)
      assert.equals('macro "Gone" not found', reason)
    end)

    it("stays unresolved when the name is ambiguous, despite a stored body", function()
      stubs:addGlobalMacro({ name = "Dup", body = "/one" })
      stubs:addGlobalMacro({ name = "Dup", body = "/two" })
      local resolved, reason = MM.Resolver:ResolveAction({
        type = "macro",
        bodyHash = "deadbeef",
        nameHint = "Dup",
        body = "/three",
        scope = "global",
      })
      assert.is_nil(resolved)
      assert.equals('macro name "Dup" is ambiguous', reason)
    end)
  end)

  describe("dynamicAction", function()
    local S, I
    before_each(function()
      S = MM.SpellIds
      I = MM.ItemIds
    end)

    it("resolves to the first usable candidate", function()
      stubs.world.class = "WARRIOR"
      stubs:setSpell(S.PUMMEL, { name = "Pummel", known = true })
      local resolved = MM.Resolver:ResolveAction({ type = "dynamicaction", id = "interrupt" })
      assert.equals("spell", resolved.kind)
      assert.equals(S.PUMMEL, resolved.id)
      assert.equals("Interrupt", resolved.dynamicAction.name)
    end)

    it("falls through to an owned, usable engineering item for a non-rez class", function()
      stubs.world.class = "MAGE"
      stubs:setItem(I.EMERGENCY_SOUL_LINK_Q1, { name = "Emergency Soul Link", count = 1, usable = true })
      local resolved = MM.Resolver:ResolveAction({ type = "dynamicaction", id = "battle_rez" })
      assert.equals("item", resolved.kind)
      assert.equals(I.EMERGENCY_SOUL_LINK_Q1, resolved.id)
      assert.equals("Battle Rez", resolved.dynamicAction.name)
    end)

    it("skips a rez item the player owns but cannot use (out of level range / no engineering)", function()
      stubs.world.class = "MAGE"
      stubs:setItem(
        I.CONVINCINGLY_REALISTIC_JUMPER_CABLES_Q3,
        { name = "Jumper Cables", count = 1, requirement = "Requires Engineering" }
      )
      stubs:setItem(I.EMERGENCY_SOUL_LINK_Q1, { name = "Emergency Soul Link", count = 1, usable = true })
      local resolved = MM.Resolver:ResolveAction({ type = "dynamicaction", id = "battle_rez" })
      assert.equals(I.EMERGENCY_SOUL_LINK_Q1, resolved.id)
    end)

    it("skips a level-capped rez item above its max level (levelMax condition)", function()
      stubs.world.class = "MAGE"
      stubs.world.level = 80 -- above the Reanimator's level-60 cap
      stubs:setItem(I.DISPOSABLE_SPECTROPHASIC_REANIMATOR, { name = "Reanimator", count = 1, usable = true })
      local resolved, reason = MM.Resolver:ResolveAction({ type = "dynamicaction", id = "battle_rez" })
      assert.is_nil(resolved)
      assert.matches("no matching candidate", reason)
    end)

    it("skips candidates whose class requirement does not match", function()
      stubs.world.class = "MAGE"
      stubs:setSpell(S.COMMAND_PET, { name = "Command Pet", known = true })
      local resolved, reason = MM.Resolver:ResolveAction({ type = "dynamicaction", id = "lust" })
      assert.is_nil(resolved)
      assert.matches("no matching candidate", reason)
    end)

    it("resolves a class-gated candidate for the right class", function()
      stubs.world.class = "HUNTER"
      stubs:setSpell(S.COMMAND_PET, { name = "Command Pet", known = true })
      local resolved = MM.Resolver:ResolveAction({ type = "dynamicaction", id = "lust" })
      assert.equals(S.COMMAND_PET, resolved.id)
    end)

    it("resolves a custom dynamic action through the database", function()
      MM.DB:DynamicActions().mine = { name = "Mine", candidates = { { type = "spell", id = 1766 } } }
      stubs:setSpell(1766, { name = "Kick", known = true })

      local resolved = MM.Resolver:ResolveAction({ type = "dynamicaction", source = "custom", id = "mine" })
      assert.equals(1766, resolved.id)
      assert.equals("Mine", resolved.dynamicAction.name)
    end)

    it("reports a missing dynamic action", function()
      local resolved, reason = MM.Resolver:ResolveAction({ type = "dynamicaction", id = "does_not_exist" })
      assert.is_nil(resolved)
      assert.equals("dynamic action not found", reason)
    end)

    it("resolves a per-class racial to the variant this character knows", function()
      stubs:setSpell(S.ARCANE_TORRENT_PRIEST, { name = "Arcane Torrent", known = true })
      local resolved = MM.Resolver:ResolveAction({ type = "dynamicaction", id = "arcane_torrent" })
      assert.equals(S.ARCANE_TORRENT_PRIEST, resolved.id)
    end)

    it("resolves a racial to nothing on a character knowing no variant", function()
      local resolved, reason = MM.Resolver:ResolveAction({ type = "dynamicaction", id = "blood_fury" })
      assert.is_nil(resolved)
      assert.matches("no matching candidate", reason)
    end)
  end)

  describe("FindDynamicActionsResolvingTo", function()
    it("returns nothing for assignments without an id", function()
      assert.same({}, MM.Resolver:FindDynamicActionsResolvingTo({ type = "empty" }))
      assert.same({}, MM.Resolver:FindDynamicActionsResolvingTo(nil))
    end)

    it("finds the predefined dynamic action a spell resolves from", function()
      stubs.world.class = "WARRIOR"
      stubs:setSpell(MM.SpellIds.PUMMEL, { name = "Pummel", known = true })
      local matches = MM.Resolver:FindDynamicActionsResolvingTo({ type = "spell", id = MM.SpellIds.PUMMEL })
      assert.same({ { source = "predefined", id = "interrupt", name = "Interrupt" } }, matches)
    end)

    it("lists predefined and custom matches sorted by name", function()
      stubs.world.class = "WARRIOR"
      stubs:setSpell(MM.SpellIds.PUMMEL, { name = "Pummel", known = true })
      MM.DB:DynamicActions().mine = { name = "Mine", candidates = { { type = "spell", id = MM.SpellIds.PUMMEL } } }
      local matches = MM.Resolver:FindDynamicActionsResolvingTo({ type = "spell", id = MM.SpellIds.PUMMEL })
      assert.same({
        { source = "predefined", id = "interrupt", name = "Interrupt" },
        { source = "custom", id = "mine", name = "Mine" },
      }, matches)
    end)

    it("matches a captured macro generated by a macro-mode dynamic action", function()
      stubs.world.class = "WARRIOR"
      stubs:setSpell(MM.SpellIds.PUMMEL, { name = "Pummel", known = true })
      MM.DB:DynamicActions().mine = {
        name = "Mine",
        mode = "macro",
        macroTemplate = "/use %name%",
        candidates = { { type = "spell", id = MM.SpellIds.PUMMEL } },
      }
      local matches = MM.Resolver:FindDynamicActionsResolvingTo({
        type = "macro",
        bodyHash = MM.Macros.HashBody("/use Pummel"),
      })
      assert.same({ { source = "custom", id = "mine", name = "Mine" } }, matches)
    end)

    it("matches a generated macro by its owner-marked name when the body changed", function()
      stubs.world.class = "WARRIOR"
      stubs:setSpell(MM.SpellIds.PUMMEL, { name = "Pummel", known = true })
      local mine = {
        name = "Mine",
        mode = "macro",
        macroTemplate = "/use %name%",
        candidates = { { type = "spell", id = MM.SpellIds.PUMMEL } },
      }
      MM.DB:DynamicActions().mine = mine
      local matches = MM.Resolver:FindDynamicActionsResolvingTo({
        type = "macro",
        bodyHash = MM.Macros.HashBody("/use Something Else"),
        nameHint = MM.Macros.MacroName(mine),
      })
      assert.same({ { source = "custom", id = "mine", name = "Mine" } }, matches)
    end)

    it("does not match a player macro against a macro-mode dynamic action", function()
      stubs.world.class = "WARRIOR"
      stubs:setSpell(MM.SpellIds.PUMMEL, { name = "Pummel", known = true })
      MM.DB:DynamicActions().mine = {
        name = "Mine",
        mode = "macro",
        macroTemplate = "/use %name%",
        candidates = { { type = "spell", id = MM.SpellIds.PUMMEL } },
      }
      local matches = MM.Resolver:FindDynamicActionsResolvingTo({
        type = "macro",
        bodyHash = MM.Macros.HashBody("/cast Pummel"),
        nameHint = "My own macro",
      })
      assert.same({}, matches)
    end)

    it("does not match a macro against a normal-mode dynamic action", function()
      stubs.world.class = "WARRIOR"
      stubs:setSpell(MM.SpellIds.PUMMEL, { name = "Pummel", known = true })
      local matches = MM.Resolver:FindDynamicActionsResolvingTo({
        type = "macro",
        bodyHash = MM.Macros.HashBody("/use Pummel"),
      })
      assert.same({}, matches)
    end)

    it("does not match a dynamic action resolving to a different action", function()
      stubs.world.class = "WARRIOR"
      stubs:setSpell(MM.SpellIds.PUMMEL, { name = "Pummel", known = true })
      -- Moonfire is a candidate of no dynamic action.
      stubs:setSpell(8921, { name = "Moonfire", known = true })
      local matches = MM.Resolver:FindDynamicActionsResolvingTo({ type = "spell", id = 8921 })
      assert.same({}, matches)
    end)
  end)
end)
