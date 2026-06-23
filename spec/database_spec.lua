local addon = require("spec.helpers.addon")

describe("DB", function()
  local MM, stubs
  before_each(function()
    MM, stubs = addon.fresh()
  end)

  describe("Initialize", function()
    it("merges defaults into an empty saved-variables table", function()
      local root = MM.DB:GetRoot()
      assert.equals(1, root.schemaVersion)
      assert.equals("keep", root.fallback)
      assert.is_table(root.profiles.Default)
      assert.is_table(root.muscles.Core)
      assert.same({}, root.customMemories)
    end)

    it("stamps existing saved variables with the current schema version", function()
      local loadedMM, _, env = addon.load()
      env.MuscleMemoryDB = {
        fallback = "clear",
        profile = "Solo",
        profiles = {
          Solo = { name = "Solo", activeMuscles = {} },
        },
        muscles = {
          Solo = { name = "Solo", slots = {} },
        },
        customMemories = {},
        characterState = {},
      }

      loadedMM.DB:Initialize()
      local root = loadedMM.DB:GetRoot()

      assert.equals(1, root.schemaVersion)
      assert.equals("clear", root.fallback)
      assert.is_nil(root.profiles.Default)
    end)
  end)

  describe("active profile selection", function()
    it("defaults to the account profile", function()
      assert.equals("Default", MM.DB:GetActiveProfileId())
    end)

    it("honours a character-specific choice", function()
      local id = MM.DB:CreateProfile("Alt")
      assert.is_true(MM.DB:SetActiveProfile(id))
      assert.equals(id, MM.DB:GetActiveProfileId())
    end)

    it("self-heals a stale character choice back to the account default", function()
      local id = MM.DB:CreateProfile("Alt")
      MM.DB:SetActiveProfile(id)
      MM.DB:DeleteProfile(id)
      assert.equals("Default", MM.DB:GetActiveProfileId())
    end)

    it("rejects selecting an unknown profile", function()
      local ok, reason = MM.DB:SetActiveProfile("ghost")
      assert.is_false(ok)
      assert.equals("unknown profile", reason)
    end)
  end)

  describe("profiles", function()
    it("creates a profile that copies the active muscle selection", function()
      local _, profile = MM.DB:CreateProfile("Raid")
      assert.equals("Raid", profile.name)
      assert.same({ { id = "Core", enabled = true } }, profile.activeMuscles)
      assert.are_not.equal(MM.DB:GetProfile("Default").activeMuscles, profile.activeMuscles)
    end)

    it("derives unique ids from names that slugify the same", function()
      local first = MM.DB:CreateProfile("My Raid")
      local second = MM.DB:CreateProfile("My Raid")
      assert.equals("my_raid", first)
      assert.are_not.equal(first, second)
    end)

    it("renames with trimming and rejects empty names", function()
      local id = MM.DB:CreateProfile("Raid")
      assert.is_true(MM.DB:RenameProfile(id, "  Mythic  "))
      assert.equals("Mythic", MM.DB:GetProfile(id).name)

      local ok, reason = MM.DB:RenameProfile(id, "   ")
      assert.is_false(ok)
      assert.equals("profile name cannot be empty", reason)
    end)

    it("refuses to delete the last profile", function()
      local ok, reason = MM.DB:DeleteProfile("Default")
      assert.is_false(ok)
      assert.equals("cannot delete the last profile", reason)
    end)

    it("finds a profile by id or case-insensitive name", function()
      local id = MM.DB:CreateProfile("Raid")
      assert.equals(id, MM.DB:FindProfileId("raid"))
      assert.equals("Default", MM.DB:FindProfileId("Default"))
      assert.is_nil(MM.DB:FindProfileId("nope"))
    end)
  end)

  describe("muscles", function()
    it("creates a muscle and appends it to the active profile", function()
      local id = MM.DB:CreateMuscle("PvP")
      local profile = MM.DB:GetProfile()
      assert.equals(id, profile.activeMuscles[#profile.activeMuscles].id)
      assert.is_table(MM.DB:GetMuscle(id))
    end)

    it("enables and disables a muscle within the profile", function()
      assert.is_true(MM.DB:SetMuscleEnabled("Core", false))
      assert.equals(0, #MM.DB:GetActiveMuscles())
      assert.is_true(MM.DB:SetMuscleEnabled("Core", true))
      assert.equals(1, #MM.DB:GetActiveMuscles())
    end)

    it("reports enabling a muscle not in the profile", function()
      local ok, reason = MM.DB:SetMuscleEnabled("ghost", true)
      assert.is_false(ok)
      assert.equals("muscle is not part of this profile", reason)
    end)

    it("deletes a muscle and prunes it from every profile", function()
      local id = MM.DB:CreateMuscle("PvP")
      assert.is_true(MM.DB:DeleteMuscle(id))
      assert.is_nil(MM.DB:GetMuscle(id))
      for _, entry in ipairs(MM.DB:GetProfile().activeMuscles) do
        assert.are_not.equal(id, entry.id)
      end
    end)

    it("refuses to delete the last muscle", function()
      local ok, reason = MM.DB:DeleteMuscle("Core")
      assert.is_false(ok)
      assert.equals("cannot delete the last muscle", reason)
    end)

    describe("MoveMuscle", function()
      local a, b, c
      before_each(function()
        a, b, c = "Core", MM.DB:CreateMuscle("B"), MM.DB:CreateMuscle("C")
      end)

      local function order()
        local ids = {}
        for _, entry in ipairs(MM.DB:GetProfile().activeMuscles) do
          ids[#ids + 1] = entry.id
        end
        return ids
      end

      it("moves a muscle to a new position", function()
        assert.is_true(MM.DB:MoveMuscle(c, 1))
        assert.same({ c, a, b }, order())
      end)

      it("clamps the target index into range", function()
        assert.is_true(MM.DB:MoveMuscle(a, 99))
        assert.same({ b, c, a }, order())
      end)

      it("rejects moving to its current position", function()
        local ok, reason = MM.DB:MoveMuscle(a, 1)
        assert.is_false(ok)
        assert.equals("muscle is already at that position", reason)
      end)

      it("rejects a muscle that is not in the profile", function()
        local ok, reason = MM.DB:MoveMuscle("ghost", 1)
        assert.is_false(ok)
        assert.equals("muscle is not part of this profile", reason)
      end)
    end)
  end)

  describe("slots", function()
    it("sets an assignment on a valid slot only", function()
      assert.is_true(MM.DB:SetSlot("Core", 5, { type = "empty" }))
      assert.same({ type = "empty" }, MM.DB:GetMuscle("Core").slots[5])
      assert.is_false(MM.DB:SetSlot("Core", 0, { type = "empty" }))
      assert.is_false(MM.DB:SetSlot("ghost", 5, { type = "empty" }))
    end)

    it("fills every slot then clears them all", function()
      assert.is_true(MM.DB:SetAllMuscleSlots("Core", true))
      assert.equals(MM.MAX_ACTION_SLOT, MM.Tables.Count(MM.DB:GetMuscle("Core").slots))

      assert.is_true(MM.DB:SetAllMuscleSlots("Core", false))
      assert.same({}, MM.DB:GetMuscle("Core").slots)
    end)
  end)

  describe("settings", function()
    it("defaults fallback to keep and validates updates", function()
      assert.equals("keep", MM.DB:GetFallback())
      assert.is_true(MM.DB:SetFallback("clear"))
      assert.equals("clear", MM.DB:GetFallback())

      local ok, reason = MM.DB:SetFallback("burn")
      assert.is_false(ok)
      assert.equals("fallback must be keep or clear", reason)
    end)
  end)

  describe("memories", function()
    it("copies a standard memory into an editable custom one", function()
      local key = MM.DB:CopyStandardMemory("interrupt")
      local copy = MM.DB:GetCustomMemory(key)
      assert.equals("Kick / Interrupt Copy", copy.name)
      assert.are_not.equal(MM.StandardMemories.interrupt.candidates, copy.candidates)
      assert.same(MM.StandardMemories.interrupt.candidates, copy.candidates)
    end)

    it("rejects copying an unknown standard memory", function()
      local key, reason = MM.DB:CopyStandardMemory("ghost")
      assert.is_nil(key)
      assert.equals("unknown standard memory", reason)
    end)

    it("resolves standard memories by id and custom ones by source", function()
      local key = MM.DB:CopyStandardMemory("interrupt", "mine", "Mine")
      assert.equals("Kick / Interrupt", MM.DB:GetMemory({ id = "interrupt" }).name)
      assert.equals("Mine", MM.DB:GetMemory({ source = "custom", id = key }).name)
      assert.is_nil(MM.DB:GetMemory(nil))
    end)

    it("clones a custom memory into a new custom memory", function()
      local source = MM.DB:CreateMemory("Mine")
      MM.DB:AddCandidate(source, { type = "spell", id = 7 })

      local clone = MM.DB:CloneMemory({ source = "custom", id = source })
      local copy = MM.DB:GetCustomMemory(clone)
      assert.equals("Mine Copy", copy.name)
      assert.are_not.equal(MM.DB:GetCustomMemory(source).candidates, copy.candidates)
      assert.equals(7, copy.candidates[1].id)
    end)

    it("creates, renames, and deletes a custom memory", function()
      local key = MM.DB:CreateMemory("Cleanse")
      assert.equals("Cleanse", MM.DB:GetCustomMemory(key).name)

      assert.is_true(MM.DB:RenameMemory(key, "Purify"))
      assert.equals("Purify", MM.DB:GetCustomMemory(key).name)

      assert.is_true(MM.DB:DeleteMemory(key))
      assert.is_nil(MM.DB:GetCustomMemory(key))
    end)

    it("refuses to edit standard memories", function()
      local ok, reason = MM.DB:RenameMemory("interrupt", "Nope")
      assert.is_false(ok)
      assert.equals("only custom memories can be renamed", reason)
      assert.is_false(MM.DB:AddCandidate("interrupt", { type = "spell", id = 1 }))
    end)

    it("adds, removes, and reorders candidates", function()
      local key = MM.DB:CreateMemory("Custom")
      MM.DB:AddCandidate(key, { type = "spell", id = 11 })
      MM.DB:AddCandidate(key, { type = "spell", id = 22 })
      MM.DB:AddCandidate(key, { type = "spell", id = 33 })

      assert.is_true(MM.DB:MoveCandidate(key, 3, 1))
      local candidates = MM.DB:GetCustomMemory(key).candidates
      assert.equals(33, candidates[1].id)
      assert.equals(11, candidates[2].id)
      assert.equals(22, candidates[3].id)

      assert.is_true(MM.DB:RemoveCandidate(key, 2))
      candidates = MM.DB:GetCustomMemory(key).candidates
      assert.equals(2, #candidates)
      assert.equals(33, candidates[1].id)
      assert.equals(22, candidates[2].id)
    end)

    it("rejects bad candidate edits", function()
      local key = MM.DB:CreateMemory("Custom")
      local ok = MM.DB:RemoveCandidate(key, 1)
      assert.is_false(ok)
      assert.is_false((MM.DB:AddCandidate(key)))
    end)
  end)

  describe("character state", function()
    it("keys character state by realm and name", function()
      stubs.world.realm = "Ragnaros"
      stubs.world.playerName = "Thrall"
      assert.equals("Ragnaros-Thrall", MM.DB:GetCharacterKey())
      assert.is_table(MM.DB:GetCharacterState())
      assert.is_table(MM.DB:GetRoot().characterState["Ragnaros-Thrall"])
    end)
  end)
end)
