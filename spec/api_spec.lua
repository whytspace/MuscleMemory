local addon = require("spec.helpers.addon")

describe("API", function()
  local MM, env

  before_each(function()
    local _
    MM, _, env = addon.fresh()
  end)

  it("exposes the versioned facade as the global MuscleMemory", function()
    assert.equals(MM.API, env.MuscleMemory)
    assert.equals(1, MM.API.apiVersion)
  end)

  describe("profiles", function()
    it("creates a profile and lists it with active/default flags", function()
      local profileId = MM.API.profiles.create("Raid")
      assert.is_string(profileId)

      local byId = {}
      for _, entry in ipairs(MM.API.profiles.list()) do
        byId[entry.profileId] = entry
      end
      assert.equals("Raid", byId[profileId].name)
      assert.is_false(byId[profileId].active)
    end)

    it("copies a profile under a new name", function()
      local sourceId = MM.API.profiles.create("Raid")
      local profileId = MM.API.profiles.copy(sourceId, "Mythic")
      assert.equals("Mythic", MM.API.profiles.get(profileId).name)
    end)

    it("returns copies, not live storage", function()
      local profileId = MM.API.profiles.create("Raid")
      MM.API.profiles.get(profileId).name = "mutated"
      assert.equals("Raid", MM.API.profiles.get(profileId).name)
    end)

    it("sets and inherits the character profile", function()
      local profileId = MM.API.profiles.create("Raid")
      assert.is_true(MM.API.profiles.setCharacter(profileId))
      assert.equals(profileId, MM.API.profiles.getActiveId())
      assert.equals("Raid", MM.API.profiles.get(MM.API.profiles.getActiveId()).name)

      assert.is_true(MM.API.profiles.setCharacter(false))
      assert.equals(MM.DB:GetGlobalProfileId(), MM.DB:GetActiveProfileId())
    end)

    it("rejects nil for setCharacter", function()
      local ok, reason = MM.API.profiles.setCharacter(nil)
      assert.is_false(ok)
      assert.matches("false to inherit", reason)
    end)

    it("surfaces DB reasons", function()
      local ok, reason = MM.API.profiles.delete(MM.DB:GetActiveProfileId())
      assert.is_false(ok)
      assert.equals("cannot delete the last profile", reason)
    end)
  end)

  describe("layers", function()
    it("creates, lists, renames and deletes", function()
      local before = #MM.API.layers.list()
      local layerId = MM.API.layers.create("Healing")

      local byId = {}
      for _, entry in ipairs(MM.API.layers.list()) do
        byId[entry.layerId] = entry
      end
      assert.equals("Healing", byId[layerId].name)

      assert.is_true(MM.API.layers.rename(layerId, "Holy"))
      assert.equals("Holy", MM.API.layers.get(layerId).name)

      assert.is_true(MM.API.layers.delete(layerId))
      assert.equals(before, #MM.API.layers.list())
    end)

    it("treats a no-op move as success", function()
      local layerId = MM.API.layers.create("Healing")
      assert.is_true(MM.API.layers.move(layerId, 1))
    end)

    it("validates setEnabled input", function()
      local layerId = MM.API.layers.create("Healing")
      local ok, reason = MM.API.layers.setEnabled(layerId, "yes")
      assert.is_false(ok)
      assert.matches("true or false", reason)
    end)

    it("sets and rejects conditions", function()
      local layerId = MM.API.layers.create("Healing")
      assert.is_true(MM.API.layers.setConditions(layerId, { classes = { "PALADIN" }, levelMin = 10 }))
      assert.same({ "PALADIN" }, MM.API.layers.get(layerId).conditions.classes)

      local ok, reason = MM.API.layers.setConditions(layerId, { class = { "PALADIN" } })
      assert.is_false(ok)
      assert.matches("unknown condition", reason)
    end)

    it("sets, reads and unmanages slots", function()
      local layerId = MM.API.layers.create("Healing")
      assert.is_true(MM.API.layers.setSlot(layerId, 5, { type = "spell", id = 1766 }))
      assert.same({ type = "spell", id = 1766 }, MM.API.layers.getSlot(layerId, 5))

      assert.is_true(MM.API.layers.setSlot(layerId, 5, nil))
      assert.is_nil(MM.API.layers.getSlot(layerId, 5))
    end)

    it("rejects malformed assignments", function()
      local layerId = MM.API.layers.create("Healing")
      local ok, reason = MM.API.layers.setSlot(layerId, 5, { type = "wand", id = 1 })
      assert.is_false(ok)
      assert.matches("unknown assignment type", reason)

      ok, reason = MM.API.layers.setSlot(layerId, 5, { type = "spell" })
      assert.is_false(ok)
      assert.matches("numeric 'id'", reason)

      ok, reason = MM.API.layers.setSlot(layerId, 5, { type = "dynamicaction", source = "custom", id = "nope" })
      assert.is_false(ok)
      assert.matches("unknown dynamic action", reason)
    end)

    it("rejects out-of-range slots", function()
      local layerId = MM.API.layers.create("Healing")
      local ok, reason = MM.API.layers.setSlot(layerId, 999, { type = "empty" })
      assert.is_false(ok)
      assert.matches("slot must be", reason)
    end)

    it("reports unknown layers on capture", function()
      local captured, reason = MM.API.layers.captureAll("nope")
      assert.is_nil(captured)
      assert.equals("unknown layer", reason)
    end)
  end)

  describe("actions", function()
    it("creates an action and manages candidates positionally", function()
      local actionId = MM.API.actions.create("Defensives")

      assert.is_true(MM.API.actions.addCandidate(actionId, { type = "spell", id = 498 }))
      assert.is_true(
        MM.API.actions.addCandidate(actionId, { type = "spell", id = 403876, conditions = { specs = { 70 } } })
      )
      assert.is_true(MM.API.actions.addCandidate(actionId, { type = "item", id = 6948 }, 1))

      local candidates = MM.API.actions.get(actionId).candidates
      assert.equals("item", candidates[1].type)
      assert.equals(498, candidates[2].id)

      assert.is_true(MM.API.actions.moveCandidate(actionId, 1, 3))
      assert.is_true(MM.API.actions.removeCandidate(actionId, 3))
      candidates = MM.API.actions.get(actionId).candidates
      assert.equals(2, #candidates)
      assert.equals(498, candidates[1].id)
    end)

    it("rejects invalid candidates", function()
      local actionId = MM.API.actions.create("Defensives")

      local ok, reason =
        MM.API.actions.addCandidate(actionId, { type = "dynamicaction", source = "predefined", id = "lust" })
      assert.is_false(ok)
      assert.matches("cannot be a candidate", reason)

      ok, reason = MM.API.actions.addCandidate(actionId, { type = "spell" })
      assert.is_false(ok)
      assert.matches("numeric 'id'", reason)

      ok, reason =
        MM.API.actions.addCandidate(actionId, { type = "spell", id = 1, conditions = { classes = "PALADIN" } })
      assert.is_false(ok)
      assert.matches("must be a list", reason)
    end)

    it("copies a predefined action into a named custom one", function()
      local actionId = MM.API.actions.copy("lust", "My Lust")
      local action = MM.API.actions.get(actionId)
      assert.equals("custom", action.source)
      assert.equals("My Lust", action.name)
      assert.is_true(#action.candidates > 0)
    end)

    it("resolves custom before predefined and honors explicit source", function()
      local actionId = MM.API.actions.copy("lust")
      assert.equals("custom", MM.API.actions.get(actionId).source)
      assert.equals("predefined", MM.API.actions.get("lust", "predefined").source)
    end)

    it("returns candidate copies, not live storage", function()
      local definition = MM.API.actions.get("lust", "predefined")
      definition.candidates[1].id = 12345
      assert.is_not.equals(12345, MM.API.actions.get("lust", "predefined").candidates[1].id)
    end)

    it("guards macro mode and template", function()
      local actionId = MM.API.actions.create("Defensives")
      assert.is_true(MM.API.actions.setMacroMode(actionId, true))
      assert.equals("macro", MM.DB:DynamicActions()[actionId].mode)

      local ok, reason = MM.API.actions.setMacroTemplate(actionId, string.rep("x", MM.MACRO_TEMPLATE_LIMIT + 1))
      assert.is_false(ok)
      assert.matches("exceeds", reason)

      assert.is_true(MM.API.actions.setMacroTemplate(actionId, "#showtooltip\n/use %name%"))
    end)
  end)

  describe("config", function()
    it("reads and writes settings", function()
      assert.equals("keep", MM.API.config.get("fallback"))
      assert.is_true(MM.API.config.set("fallback", "clear"))
      assert.equals("clear", MM.API.config.get("fallback"))
    end)

    it("passes value validation through", function()
      local ok, reason = MM.API.config.set("response", "sometimes")
      assert.is_false(ok)
      assert.matches("response must be", reason)
    end)

    it("rejects unknown settings", function()
      local value, reason = MM.API.config.get("volume")
      assert.is_nil(value)
      assert.matches("unknown setting", reason)
    end)
  end)

  describe("apply cycle", function()
    it("previews an empty profile as no changes", function()
      assert.same({}, MM.API.preview())
    end)
  end)
end)
