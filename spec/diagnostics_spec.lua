local addon = require("spec.helpers.addon")
local report = require("spec.helpers.report")

describe("Diagnostics", function()
  local MM, stubs, env

  -- A world with one of everything the report captures: a profile whose layer
  -- references a spell, an item, a macro-mode smart action and a captured
  -- macro; bars holding some of it; macros in both scopes; a registry record.
  local function seedWorld()
    stubs
      :setCharacter({ class = "WARLOCK", level = 85, race = "Orc", faction = "Horde", specId = 267, role = "DAMAGER" })
      :setSpell(686, { name = "Shadow Bolt", known = true })
      :setSpell(1766, { name = "Kick", known = false })
      :setSpell(19647, { name = "Spell Lock", known = false })
      :setItem(5512, { name = "Healthstone", count = 2 })
      :setItem(127770, { name = "Sad Potion", count = 1, usable = false, requirement = "Requires Alchemy" })
      :setMount(1792, { name = "Swift Wolf", spellId = 33660 })
      :setFlyout(10, { name = "Demons", slots = { 688, 697 } })
      :setEquipmentSet("Raid", 3)
      :setSlot(1, { actionType = "spell", id = 686, texture = 1686 })
      :setSlot(27, { actionType = "macro", id = 121, text = "Kick\194\160", texture = 134400 })

    stubs:addGlobalMacro({ name = "Hearth", icon = 134414, body = "/use Hearthstone" })
    stubs:addCharacterMacro({ name = "Kick\194\160", icon = 134400, body = "#showtooltip\n/use Spell Lock" })

    local profileId = MM.DB:GetActiveProfileId()
    local profile = MM.DB:GetProfile(profileId)
    profile.actions = {
      kick = {
        name = "Kick",
        mode = "macro",
        macroTemplate = "#showtooltip\n/use %name%",
        candidates = { { type = "spell", id = 1766 }, { type = "spell", id = 19647 } },
      },
    }
    profile.layers.Core.slots = {
      [1] = { type = "spell", id = 686 },
      [2] = { type = "item", id = 5512 },
      [3] = { type = "item", id = 127770 },
      [27] = { type = "action", source = "custom", id = "kick" },
    }
    MM.DB:SetMacroRecord("Core", 27, {
      name = "Kick\194\160",
      scope = "character",
      bodyHash = MM.Macros.HashBody("#showtooltip\n/use Spell Lock"),
      indexHint = 121,
    })
    return profileId
  end

  before_each(function()
    MM, stubs, env = addon.fresh()
  end)

  describe("BuildReport", function()
    it("captures character, settings, bars, macros and the raw profile", function()
      local profileId = seedWorld()
      local built = MM.Diagnostics:BuildReport()

      assert.equals("WARLOCK", built.character.class)
      assert.equals(267, built.character.specId)
      assert.equals(profileId, built.settings.profileId)
      assert.equals("spell", built.bars[1].type)
      assert.equals(686, built.bars[1].id)
      assert.equals("Kick\194\160", built.bars[27].text)
      assert.same(built.profile.data.layers.Core.slots[1], { type = "spell", id = 686 })
      assert.equals(121, built.macroRegistry.Core[27].indexHint)

      local names = {}
      for _, macro in ipairs(built.macros.list) do
        names[macro.name] = macro.scope
      end
      assert.equals("global", names["Hearth"])
      assert.equals("character", names["Kick\194\160"])
    end)

    it("captures every referenced id with the client's own answers", function()
      seedWorld()
      local built = MM.Diagnostics:BuildReport()

      -- Referenced through layer slots and smart-action candidates.
      assert.is_true(built.spells[686].known)
      assert.is_false(built.spells[1766].known)
      assert.is_false(built.spells[19647].known)
      assert.equals(2, built.items[5512].count)
      assert.is_false(built.items[127770].usable)
      -- The bar slot is the FindSpellActionButtons answer for the placed spell.
      assert.same({ 1 }, built.spells[686].buttons)
    end)
  end)

  describe("Report and Decode", function()
    it("round-trips through the encoded string", function()
      seedWorld()
      local text = MM.Diagnostics:Report()
      assert.is_string(text)
      assert.matches("^!MMDBG:1!", text)

      local decoded = MM.Diagnostics:Decode(text)
      assert.equals("WARLOCK", decoded.character.class)
      assert.same(MM.Diagnostics:BuildReport(), decoded)
    end)

    it("rejects strings that are not debug reports", function()
      local decoded, reason = MM.Diagnostics:Decode("!MM:2!notareport")
      assert.is_nil(decoded)
      assert.equals("not a Muscle Memory debug report", reason)
    end)
  end)

  describe("replay through spec.helpers.report", function()
    it("reproduces the plan the reporter saw", function()
      seedWorld()
      local replayed = report.load(MM.Diagnostics:Report())

      -- Slot 1 already holds Shadow Bolt (no change); slot 2's Healthstone is
      -- owned but not placed (a change); slot 27's smart action has no known
      -- candidate (kept). Same verdicts as the original world.
      local plan = replayed.Applier:BuildPlan()
      assert.is_nil(replayed.Applier:ClassifyEntry(plan.slots[1]))
      assert.equals("place", replayed.Applier:ClassifyEntry(plan.slots[2]))
      assert.equals("keep", replayed.Applier:ClassifyEntry(plan.slots[27]))
      assert.is_true(replayed.Applier:HasUnappliedChanges())
    end)

    it("replays captured client quirks verbatim", function()
      seedWorld()

      -- The felhunter quirk: Spell Lock is known only through the pet-spell
      -- probe, and the client doesn't index the placed spell on any button.
      env.IsSpellKnown = function(id, pet)
        return id == 19647 and pet == true
      end
      env.C_ActionBar.FindSpellActionButtons = function()
        return nil
      end

      local built = MM.Diagnostics:BuildReport()
      assert.is_true(built.spells[19647].known)
      assert.is_false(built.spells[19647].knownPlayer)
      assert.is_true(built.spells[19647].knownPet)
      assert.is_nil(built.spells[686].buttons)

      local replayed, _, replayedEnv = report.load(built)
      assert.is_true(replayed.Spells.IsKnown(19647))
      assert.is_false(replayedEnv.IsPlayerSpell(19647))
      assert.is_true(replayedEnv.IsSpellKnown(19647, true))
      assert.is_false(replayedEnv.IsSpellKnown(19647))
      -- Shadow Bolt sits on slot 1, yet the oracle answers nil — exactly what
      -- the client said, so the mismatch the reporter saw reproduces.
      assert.is_nil(replayedEnv.C_ActionBar.FindSpellActionButtons(686))
      assert.equals("place", replayed.Applier:ClassifyEntry(replayed.Applier:BuildPlan().slots[1]))
    end)

    it("normalises a mount captured through its summon spell", function()
      seedWorld()
      -- A companion/MOUNT slot reports the summon spell id, not the journal id.
      stubs:setSpell(417888, { name = "Swift Wolf", known = true })
      stubs.world.mounts[1792].spellId = 417888
      stubs:setSlot(9, { actionType = "companion", id = 417888, subType = "MOUNT" })
      MM.DB:GetProfile(MM.DB:GetActiveProfileId()).layers.Core.slots[9] = { type = "mount", id = 1792 }

      local built = MM.Diagnostics:BuildReport()
      assert.is_table(built.mounts[1792])
      -- No first-class journal entry under the spell id, or the replay would
      -- skip the spell->mount normalisation and the mount would mismatch itself.
      assert.is_nil(built.mounts[417888])

      local replayed = report.load(built)
      assert.is_nil(replayed.Applier:ClassifyEntry(replayed.Applier:BuildPlan().slots[9]))
    end)

    it("replays macros and the registry so macro matching reproduces", function()
      seedWorld()
      local replayed = report.load(MM.Diagnostics:Report())

      local found = replayed.Macros.FindUniqueByName("Kick\194\160")
      assert.equals(121, found.index)
      assert.equals("character", found.scope)
      assert.equals(MM.Macros.HashBody("#showtooltip\n/use Spell Lock"), found.bodyHash)
      assert.equals(121, replayed.DB:GetMacroRecord("Core", 27).indexHint)
    end)
  end)
end)
