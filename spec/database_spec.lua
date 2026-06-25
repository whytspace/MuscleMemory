local addon = require("spec.helpers.addon")

describe("DB", function()
  local MM, stubs
  before_each(function()
    MM, stubs = addon.fresh()
  end)

  describe("Initialize", function()
    it("merges defaults into an empty saved-variables table", function()
      local root = MM.DB:GetRoot()
      assert.equals(2, root.schemaVersion)
      assert.is_nil(root.fallback)
      assert.is_nil(root.muscles)
      assert.is_nil(root.customMemories)

      local default = root.profiles.Default
      assert.is_table(default)
      assert.equals("keep", default.fallback)
      assert.same({ "Core" }, default.muscleOrder)
      assert.is_table(default.muscles.Core)
      assert.same({}, default.memories)
    end)

    it("migrates a v1 save: muscles, memories and fallback move into each profile", function()
      local loadedMM, _, env = addon.load()
      env.MuscleMemoryDB = {
        schemaVersion = 1,
        fallback = "clear",
        profile = "Solo",
        profiles = {
          Solo = { name = "Solo", activeMuscles = { { id = "A", enabled = true }, { id = "B", enabled = false } } },
          Duo = { name = "Duo", activeMuscles = { { id = "B", enabled = true } } },
        },
        muscles = {
          A = { name = "A", slots = { [1] = { type = "memory", source = "standard", id = "interrupt" } } },
          B = { name = "B", slots = {} },
          C = { name = "C", slots = {} }, -- in no profile's activeMuscles
        },
        customMemories = { mine = { name = "Mine", candidates = {} } },
        characterState = {},
      }

      loadedMM.DB:Initialize()
      local root = loadedMM.DB:GetRoot()

      assert.equals(2, root.schemaVersion)
      assert.is_nil(root.muscles)
      assert.is_nil(root.customMemories)
      assert.is_nil(root.fallback)

      local solo = root.profiles.Solo
      assert.equals("clear", solo.fallback)
      -- Full copy of the shared pool into the profile.
      assert.is_table(solo.muscles.A)
      assert.is_table(solo.muscles.B)
      assert.is_table(solo.muscles.C)
      assert.equals("Mine", solo.memories.mine.name)
      -- activeMuscles -> muscleOrder, enabled carried onto the muscle.
      assert.is_nil(solo.activeMuscles)
      assert.same({ "A", "B", "C" }, solo.muscleOrder)
      assert.is_true(solo.muscles.A.enabled)
      assert.is_false(solo.muscles.B.enabled)
      -- Muscle carried in but not part of this profile stays visible but disabled.
      assert.is_false(solo.muscles.C.enabled)
      -- Stored memory source rewritten standard -> predefined.
      assert.equals("predefined", solo.muscles.A.slots[1].source)

      local duo = root.profiles.Duo
      assert.equals("B", duo.muscleOrder[1])
      assert.equals(3, #duo.muscleOrder)
      assert.is_true(duo.muscles.B.enabled)
      assert.is_false(duo.muscles.A.enabled)
      assert.is_false(duo.muscles.C.enabled)
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

  describe("global profile", function()
    it("reads and validates the account default", function()
      local id = MM.DB:CreateProfile("Raid")
      assert.equals("Default", MM.DB:GetGlobalProfileId())
      assert.is_true(MM.DB:SetGlobalProfile(id))
      assert.equals(id, MM.DB:GetGlobalProfileId())

      local ok, reason = MM.DB:SetGlobalProfile("ghost")
      assert.is_false(ok)
      assert.equals("unknown profile", reason)
    end)

    it("repairs the global default and character overrides when a profile is deleted", function()
      local id = MM.DB:CreateProfile("Raid")
      MM.DB:SetGlobalProfile(id)
      MM.DB:SetActiveProfile(id)

      assert.is_true(MM.DB:DeleteProfile(id))
      assert.are_not.equal(id, MM.DB:GetRoot().profile)
      assert.is_nil(MM.DB:GetCharacterState().profile)
    end)
  end)

  describe("profiles", function()
    it("creates an empty profile", function()
      local _, profile = MM.DB:CreateProfile("Raid")
      assert.equals("Raid", profile.name)
      assert.equals("keep", profile.fallback)
      assert.same({}, profile.muscleOrder)
      assert.same({}, profile.muscles)
      assert.same({}, profile.memories)
    end)

    it("clones a profile 1:1, fully independent of the source", function()
      MM.DB:SetSlot("Core", 1, { type = "spell", id = 42 })
      MM.DB:CreateMemory("Mine")

      local id, clone = MM.DB:CloneProfile("Default", "Raid")
      assert.equals("Raid", clone.name)
      assert.same({ "Core" }, clone.muscleOrder)
      assert.equals(42, clone.muscles.Core.slots[1].id)
      assert.is_table(next(clone.memories) and clone.memories)

      -- Mutating the clone must not touch the source.
      clone.muscles.Core.slots[1].id = 99
      assert.equals(42, MM.DB:GetProfile("Default").muscles.Core.slots[1].id)
      assert.are_not.equal(MM.DB:GetProfile("Default").muscles, clone.muscles)
      assert.is_string(id)
    end)

    it("rejects cloning an unknown profile", function()
      local id, reason = MM.DB:CloneProfile("ghost", "Raid")
      assert.is_nil(id)
      assert.equals("unknown profile", reason)
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

    it("scopes muscles and memories to the active profile", function()
      MM.DB:CreateMuscle("Shared")
      local other = MM.DB:CreateProfile("Other")

      -- The new profile starts empty; the active profile's muscle is not visible.
      MM.DB:SetActiveProfile(other)
      assert.is_nil(MM.DB:FindMuscleId("Shared"))
      assert.equals(0, #MM.DB:GetProfileMuscles())
    end)
  end)

  describe("muscles", function()
    it("creates a muscle and appends it to the active profile order", function()
      local id = MM.DB:CreateMuscle("PvP")
      local profile = MM.DB:GetProfile()
      assert.equals(id, profile.muscleOrder[#profile.muscleOrder])
      assert.is_table(MM.DB:GetMuscle(id))
      assert.is_true(MM.DB:GetMuscle(id).enabled)
    end)

    it("enables and disables a muscle (flag stored on the muscle)", function()
      assert.is_true(MM.DB:SetMuscleEnabled("Core", false))
      assert.is_false(MM.DB:GetMuscle("Core").enabled)
      assert.equals(0, #MM.DB:GetActiveMuscles())
      assert.is_true(MM.DB:SetMuscleEnabled("Core", true))
      assert.equals(1, #MM.DB:GetActiveMuscles())
    end)

    it("reports enabling a muscle not in the profile", function()
      local ok, reason = MM.DB:SetMuscleEnabled("ghost", true)
      assert.is_false(ok)
      assert.equals("muscle is not part of this profile", reason)
    end)

    it("deletes a muscle and prunes it from the order", function()
      local id = MM.DB:CreateMuscle("PvP")
      assert.is_true(MM.DB:DeleteMuscle(id))
      assert.is_nil(MM.DB:GetMuscle(id))
      for _, ordered in ipairs(MM.DB:GetProfile().muscleOrder) do
        assert.are_not.equal(id, ordered)
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
        return MM.DB:GetProfile().muscleOrder
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

    it("scopes fallback to the active profile", function()
      MM.DB:SetFallback("clear")
      local other = MM.DB:CreateProfile("Other")
      MM.DB:SetActiveProfile(other)
      assert.equals("keep", MM.DB:GetFallback())
    end)
  end)

  describe("memories", function()
    it("copies a predefined memory into an editable profile one", function()
      local key = MM.DB:CopyPredefinedMemory("interrupt")
      local copy = MM.DB:Memories()[key]
      assert.equals("Interrupt Copy", copy.name)
      assert.are_not.equal(MM.PredefinedMemories.interrupt.candidates, copy.candidates)
      assert.same(MM.PredefinedMemories.interrupt.candidates, copy.candidates)
    end)

    it("rejects copying an unknown predefined memory", function()
      local key, reason = MM.DB:CopyPredefinedMemory("ghost")
      assert.is_nil(key)
      assert.equals("unknown predefined memory", reason)
    end)

    it("resolves predefined memories by id and profile ones by source", function()
      local key = MM.DB:CopyPredefinedMemory("interrupt", "mine", "Mine")
      assert.equals("Interrupt", MM.DB:ResolveMemory({ id = "interrupt" }).name)
      assert.equals("Interrupt", MM.DB:GetPredefinedMemory("interrupt").name)
      assert.equals("Mine", MM.DB:ResolveMemory({ source = "custom", id = key }).name)
      assert.is_nil(MM.DB:ResolveMemory(nil))
    end)

    it("clones a profile memory into a new profile memory", function()
      local source = MM.DB:CreateMemory("Mine")
      MM.DB:AddCandidate(source, { type = "spell", id = 7 })

      local clone = MM.DB:CloneMemory({ source = "custom", id = source })
      local copy = MM.DB:Memories()[clone]
      assert.equals("Mine Copy", copy.name)
      assert.are_not.equal(MM.DB:Memories()[source].candidates, copy.candidates)
      assert.equals(7, copy.candidates[1].id)
    end)

    it("creates, renames, and deletes a profile memory", function()
      local key = MM.DB:CreateMemory("Cleanse")
      assert.equals("Cleanse", MM.DB:Memories()[key].name)

      assert.is_true(MM.DB:RenameMemory(key, "Purify"))
      assert.equals("Purify", MM.DB:Memories()[key].name)

      assert.is_true(MM.DB:DeleteMemory(key))
      assert.is_nil(MM.DB:Memories()[key])
    end)

    it("toggles macro mode, seeding and keeping the template", function()
      local key = MM.DB:CreateMemory("Kick")

      assert.is_true(MM.DB:SetMemoryMode(key, "macro"))
      local memory = MM.DB:Memories()[key]
      assert.equals("macro", memory.mode)
      assert.equals(MM.MACRO_TEMPLATE_DEFAULT, memory.macroTemplate)

      MM.DB:SetMemoryTemplate(key, "#showtooltip\n/use [@focus] %name%")
      assert.is_true(MM.DB:SetMemoryMode(key, "normal"))
      assert.is_nil(memory.mode)
      -- The body is preserved across the round-trip so toggling never loses it.
      assert.equals("#showtooltip\n/use [@focus] %name%", memory.macroTemplate)
    end)

    it("clamps the template to the limit and rejects bad modes", function()
      local key = MM.DB:CreateMemory("Kick")
      local ok, reason = MM.DB:SetMemoryMode(key, "bogus")
      assert.is_false(ok)
      assert.matches("normal or macro", reason)

      MM.DB:SetMemoryTemplate(key, string.rep("x", MM.MACRO_TEMPLATE_LIMIT + 50))
      assert.equals(MM.MACRO_TEMPLATE_LIMIT, #MM.DB:Memories()[key].macroTemplate)

      assert.is_false((MM.DB:SetMemoryMode("interrupt", "macro")))
    end)

    it("refuses to edit predefined memories", function()
      local ok, reason = MM.DB:RenameMemory("interrupt", "Nope")
      assert.is_false(ok)
      assert.equals("only profile memories can be renamed", reason)
      assert.is_false(MM.DB:AddCandidate("interrupt", { type = "spell", id = 1 }))
    end)

    it("adds, removes, and reorders candidates", function()
      local key = MM.DB:CreateMemory("Custom")
      MM.DB:AddCandidate(key, { type = "spell", id = 11 })
      MM.DB:AddCandidate(key, { type = "spell", id = 22 })
      MM.DB:AddCandidate(key, { type = "spell", id = 33 })

      assert.is_true(MM.DB:MoveCandidate(key, 3, 1))
      local candidates = MM.DB:Memories()[key].candidates
      assert.equals(33, candidates[1].id)
      assert.equals(11, candidates[2].id)
      assert.equals(22, candidates[3].id)

      assert.is_true(MM.DB:RemoveCandidate(key, 2))
      candidates = MM.DB:Memories()[key].candidates
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
