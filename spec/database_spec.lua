local addon = require("spec.helpers.addon")

describe("DB", function()
  local MM, stubs
  before_each(function()
    MM, stubs = addon.fresh()
  end)

  describe("Initialize", function()
    it("merges defaults into an empty saved-variables table", function()
      local root = MM.DB:GetRoot()
      assert.equals(5, root.schemaVersion)
      assert.is_nil(root.fallback)
      assert.is_nil(root.layers)
      assert.is_nil(root.customSmartActions)

      local default = root.profiles.Default
      assert.is_table(default)
      assert.equals("keep", default.fallback)
      assert.same({ "Core" }, default.layerOrder)
      assert.is_table(default.layers.Core)
      assert.same({}, default.actions)
    end)

    it("migrates a v1 save: layers, smart actions and fallback move into each profile", function()
      local loadedMM, _, env = addon.load()
      -- v1 on-disk shape: the historical key names (muscles / customMemories /
      -- activeMuscles / type = "memory"), which MigrateToV2 reads literally.
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

      assert.equals(5, root.schemaVersion)
      assert.is_nil(root.layers)
      assert.is_nil(root.customSmartActions)
      assert.is_nil(root.fallback)

      local solo = root.profiles.Solo
      assert.equals("clear", solo.fallback)
      -- Full copy of the shared pool into the profile.
      assert.is_table(solo.layers.A)
      assert.is_table(solo.layers.B)
      assert.is_table(solo.layers.C)
      assert.equals("Mine", solo.actions.mine.name)
      -- activeLayers -> layerOrder, enabled carried onto the layer.
      assert.is_nil(solo.activeLayers)
      assert.same({ "A", "B", "C" }, solo.layerOrder)
      assert.is_true(solo.layers.A.enabled)
      assert.is_false(solo.layers.B.enabled)
      -- Layer carried in but not part of this profile stays visible but disabled.
      assert.is_false(solo.layers.C.enabled)
      -- Stored smartAction source rewritten standard -> predefined.
      assert.equals("predefined", solo.layers.A.slots[1].source)

      local duo = root.profiles.Duo
      assert.equals("B", duo.layerOrder[1])
      assert.equals(3, #duo.layerOrder)
      assert.is_true(duo.layers.B.enabled)
      assert.is_false(duo.layers.A.enabled)
      assert.is_false(duo.layers.C.enabled)
    end)

    it("migrates a v2 save: muscles/memories rename to layers/smart actions", function()
      local loadedMM, _, env = addon.load()
      -- v2 on-disk shape: per-profile muscles / memories / muscleOrder and the
      -- "memory" slot discriminator, all renamed in place by MigrateToV3.
      env.MuscleMemoryDB = {
        schemaVersion = 2,
        profile = "Solo",
        profiles = {
          Solo = {
            name = "Solo",
            fallback = "keep",
            muscleOrder = { "A" },
            muscles = {
              A = { name = "A", enabled = true, slots = { [1] = { type = "memory", source = "custom", id = "mine" } } },
            },
            memories = { mine = { name = "Mine", candidates = {} } },
          },
        },
        characterState = {},
      }

      loadedMM.DB:Initialize()
      local solo = loadedMM.DB:GetRoot().profiles.Solo

      assert.equals(5, loadedMM.DB:GetRoot().schemaVersion)
      assert.is_nil(solo.muscles)
      assert.is_nil(solo.memories)
      assert.is_nil(solo.muscleOrder)
      assert.same({ "A" }, solo.layerOrder)
      assert.equals("A", solo.layers.A.name)
      assert.equals("Mine", solo.actions.mine.name)
      -- slot discriminator renamed "memory" -> "action".
      assert.equals("action", solo.layers.A.slots[1].type)
    end)

    it("migrates a v3 save: dynamic actions become the neutral action pool", function()
      local loadedMM, _, env = addon.load()
      -- v3 on-disk shape: per-profile dynamicActions and the "dynamicaction"
      -- slot discriminator, both renamed in place by MigrateToV4.
      env.MuscleMemoryDB = {
        schemaVersion = 3,
        profile = "Solo",
        profiles = {
          Solo = {
            name = "Solo",
            fallback = "keep",
            layerOrder = { "A" },
            layers = {
              A = {
                name = "A",
                enabled = true,
                slots = { [1] = { type = "dynamicaction", source = "custom", id = "mine" } },
              },
            },
            dynamicActions = { mine = { name = "Mine", candidates = {} } },
          },
        },
        characterState = {},
      }

      loadedMM.DB:Initialize()
      local solo = loadedMM.DB:GetRoot().profiles.Solo

      assert.equals(5, loadedMM.DB:GetRoot().schemaVersion)
      assert.is_nil(solo.dynamicActions)
      assert.equals("Mine", solo.actions.mine.name)
      assert.equals("action", solo.layers.A.slots[1].type)
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
    it("remembers that the tutorial has run, account-wide", function()
      assert.is_false(MM.DB:HasSeenTutorial())
      MM.DB:MarkTutorialSeen()
      assert.is_true(MM.DB:HasSeenTutorial())
    end)

    it("creates a profile with one empty starter layer", function()
      local _, profile = MM.DB:CreateProfile("Raid")
      assert.equals("Raid", profile.name)
      assert.equals("keep", profile.fallback)
      assert.same({}, profile.actions)

      assert.equals(1, #profile.layerOrder)
      local layer = profile.layers[profile.layerOrder[1]]
      assert.equals("Core", layer.name)
      assert.is_true(layer.enabled)
      assert.same({}, layer.slots)
    end)

    it("creates a bare profile for imports, which bring their own layers", function()
      local _, profile = MM.DB:CreateProfile("Raid", { bare = true })
      assert.same({}, profile.layerOrder)
      assert.same({}, profile.layers)
    end)

    it("clones a profile 1:1, fully independent of the source", function()
      MM.DB:SetSlot("Core", 1, { type = "spell", id = 42 })
      MM.DB:CreateSmartAction("Mine")

      local id, clone = MM.DB:CloneProfile("Default", "Raid")
      assert.equals("Raid", clone.name)
      assert.same({ "Core" }, clone.layerOrder)
      assert.equals(42, clone.layers.Core.slots[1].id)
      assert.is_table(next(clone.actions) and clone.actions)

      -- Mutating the clone must not touch the source.
      clone.layers.Core.slots[1].id = 99
      assert.equals(42, MM.DB:GetProfile("Default").layers.Core.slots[1].id)
      assert.are_not.equal(MM.DB:GetProfile("Default").layers, clone.layers)
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

    it("scopes layers and smart actions to the active profile", function()
      MM.DB:CreateLayer("Shared")
      local other = MM.DB:CreateProfile("Other")

      -- The new profile only has its own starter layer; "Shared" is not visible.
      MM.DB:SetActiveProfile(other)
      assert.is_nil(MM.DB:FindLayerId("Shared"))
      assert.equals(1, #MM.DB:GetProfileLayers())
      assert.equals("Core", MM.DB:GetProfileLayers()[1].name)
    end)
  end)

  describe("layers", function()
    it("creates a layer and appends it to the active profile order", function()
      local id = MM.DB:CreateLayer("PvP")
      local profile = MM.DB:GetProfile()
      assert.equals(id, profile.layerOrder[#profile.layerOrder])
      assert.is_table(MM.DB:GetLayer(id))
      assert.is_true(MM.DB:GetLayer(id).enabled)
    end)

    it("enables and disables a layer (flag stored on the layer)", function()
      assert.is_true(MM.DB:SetLayerEnabled("Core", false))
      assert.is_false(MM.DB:GetLayer("Core").enabled)
      assert.equals(0, #MM.DB:GetActiveLayers())
      assert.is_true(MM.DB:SetLayerEnabled("Core", true))
      assert.equals(1, #MM.DB:GetActiveLayers())
    end)

    it("reports enabling a layer not in the profile", function()
      local ok, reason = MM.DB:SetLayerEnabled("ghost", true)
      assert.is_false(ok)
      assert.equals("layer is not part of this profile", reason)
    end)

    it("deletes a layer and prunes it from the order", function()
      local id = MM.DB:CreateLayer("PvP")
      assert.is_true(MM.DB:DeleteLayer(id))
      assert.is_nil(MM.DB:GetLayer(id))
      for _, ordered in ipairs(MM.DB:GetProfile().layerOrder) do
        assert.are_not.equal(id, ordered)
      end
    end)

    it("refuses to delete the last layer", function()
      local ok, reason = MM.DB:DeleteLayer("Core")
      assert.is_false(ok)
      assert.equals("cannot delete the last layer", reason)
    end)

    it("creates a layer at a given position, appending without one", function()
      local top = MM.DB:CreateLayer("Top", 1)
      local appended = MM.DB:CreateLayer("Appended")
      assert.same({ top, "Core", appended }, MM.DB:GetProfile().layerOrder)
      -- Out of range appends rather than erroring, like MoveLayer clamps.
      local far = MM.DB:CreateLayer("Far", 99)
      assert.equals(far, MM.DB:GetProfile().layerOrder[4])
    end)

    it("heals a stale selection to the top of the stack", function()
      local top = MM.DB:CreateLayer("Top", 1)
      MM.DB:SetSelectedLayerId("Core")
      assert.equals("Core", MM.DB:GetSelectedLayerId())

      assert.is_true(MM.DB:DeleteLayer("Core"))
      assert.equals(top, MM.DB:GetSelectedLayerId())
    end)

    describe("MoveLayer", function()
      local a, b, c
      before_each(function()
        a, b, c = "Core", MM.DB:CreateLayer("B"), MM.DB:CreateLayer("C")
      end)

      local function order()
        return MM.DB:GetProfile().layerOrder
      end

      it("moves a layer to a new position", function()
        assert.is_true(MM.DB:MoveLayer(c, 1))
        assert.same({ c, a, b }, order())
      end)

      it("clamps the target index into range", function()
        assert.is_true(MM.DB:MoveLayer(a, 99))
        assert.same({ b, c, a }, order())
      end)

      it("rejects moving to its current position", function()
        local ok, reason = MM.DB:MoveLayer(a, 1)
        assert.is_false(ok)
        assert.equals("layer is already at that position", reason)
      end)

      it("rejects a layer that is not in the profile", function()
        local ok, reason = MM.DB:MoveLayer("ghost", 1)
        assert.is_false(ok)
        assert.equals("layer is not part of this profile", reason)
      end)
    end)
  end)

  describe("slots", function()
    it("sets an assignment on a valid slot only", function()
      assert.is_true(MM.DB:SetSlot("Core", 5, { type = "empty" }))
      assert.same({ type = "empty" }, MM.DB:GetLayer("Core").slots[5])
      assert.is_false(MM.DB:SetSlot("Core", 0, { type = "empty" }))
      assert.is_false(MM.DB:SetSlot("ghost", 5, { type = "empty" }))
    end)

    it("fills every slot then clears them all", function()
      assert.is_true(MM.DB:SetAllLayerSlots("Core", true))
      assert.equals(MM.MAX_ACTION_SLOT, MM.Tables.Count(MM.DB:GetLayer("Core").slots))

      assert.is_true(MM.DB:SetAllLayerSlots("Core", false))
      assert.same({}, MM.DB:GetLayer("Core").slots)
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

    it("defaults the suggestion mode to suggest and validates updates", function()
      assert.equals("suggest", MM.DB:GetSuggestMode())
      assert.is_true(MM.DB:SetSuggestMode("auto"))
      assert.equals("auto", MM.DB:GetSuggestMode())

      local ok, reason = MM.DB:SetSuggestMode("sometimes")
      assert.is_false(ok)
      assert.equals("suggestion mode must be never, suggest or auto", reason)

      -- Account-scoped: a profile switch doesn't change it.
      local other = MM.DB:CreateProfile("Other")
      MM.DB:SetActiveProfile(other)
      assert.equals("auto", MM.DB:GetSuggestMode())
    end)
  end)

  describe("actions", function()
    it("copies a predefined smart action into an editable profile one", function()
      local key = MM.DB:CopyPredefinedSmartAction("interrupt")
      local copy = MM.DB:SmartActions()[key]
      assert.equals("Interrupt Copy", copy.name)
      assert.are_not.equal(MM.PredefinedSmartActions.interrupt.candidates, copy.candidates)
      assert.same(MM.PredefinedSmartActions.interrupt.candidates, copy.candidates)
    end)

    it("rejects copying an unknown predefined smart action", function()
      local key, reason = MM.DB:CopyPredefinedSmartAction("ghost")
      assert.is_nil(key)
      assert.equals("unknown predefined smart action", reason)
    end)

    it("resolves predefined smart actions by id and profile ones by source", function()
      local key = MM.DB:CopyPredefinedSmartAction("interrupt", "mine", "Mine")
      assert.equals("Interrupt", MM.DB:ResolveSmartAction({ id = "interrupt" }).name)
      assert.equals("Interrupt", MM.DB:GetPredefinedSmartAction("interrupt").name)
      assert.equals("Mine", MM.DB:ResolveSmartAction({ source = "custom", id = key }).name)
      assert.is_nil(MM.DB:ResolveSmartAction(nil))
    end)

    it("clones a profile smart action into a new profile smart action", function()
      local source = MM.DB:CreateSmartAction("Mine")
      MM.DB:AddCandidate(source, { type = "spell", id = 7 })

      local clone = MM.DB:CloneSmartAction({ source = "custom", id = source })
      local copy = MM.DB:SmartActions()[clone]
      assert.equals("Mine Copy", copy.name)
      assert.are_not.equal(MM.DB:SmartActions()[source].candidates, copy.candidates)
      assert.equals(7, copy.candidates[1].id)
    end)

    it("creates, renames, and deletes a profile smart action", function()
      local key = MM.DB:CreateSmartAction("Cleanse")
      assert.equals("Cleanse", MM.DB:SmartActions()[key].name)

      assert.is_true(MM.DB:RenameSmartAction(key, "Purify"))
      assert.equals("Purify", MM.DB:SmartActions()[key].name)

      assert.is_true(MM.DB:DeleteSmartAction(key))
      assert.is_nil(MM.DB:SmartActions()[key])
    end)

    it("toggles macro mode, seeding and keeping the template", function()
      local key = MM.DB:CreateSmartAction("Kick")

      assert.is_true(MM.DB:SetSmartActionMode(key, "macro"))
      local smartAction = MM.DB:SmartActions()[key]
      assert.equals("macro", smartAction.mode)
      assert.equals(MM.MACRO_TEMPLATE_DEFAULT, smartAction.macroTemplate)

      MM.DB:SetSmartActionTemplate(key, "#showtooltip\n/use [@focus] %name%")
      assert.is_true(MM.DB:SetSmartActionMode(key, "normal"))
      assert.is_nil(smartAction.mode)
      -- The body is preserved across the round-trip so toggling never loses it.
      assert.equals("#showtooltip\n/use [@focus] %name%", smartAction.macroTemplate)
    end)

    it("clamps the template to the limit and rejects bad modes", function()
      local key = MM.DB:CreateSmartAction("Kick")
      local ok, reason = MM.DB:SetSmartActionMode(key, "bogus")
      assert.is_false(ok)
      assert.matches("normal or macro", reason)

      MM.DB:SetSmartActionTemplate(key, string.rep("x", MM.MACRO_TEMPLATE_LIMIT + 50))
      assert.equals(MM.MACRO_TEMPLATE_LIMIT, #MM.DB:SmartActions()[key].macroTemplate)

      assert.is_false((MM.DB:SetSmartActionMode("interrupt", "macro")))
    end)

    it("refuses to edit predefined smart actions", function()
      local ok, reason = MM.DB:RenameSmartAction("interrupt", "Nope")
      assert.is_false(ok)
      assert.equals("only profile smart actions can be renamed", reason)
      assert.is_false(MM.DB:AddCandidate("interrupt", { type = "spell", id = 1 }))
    end)

    it("adds, removes, and reorders candidates", function()
      local key = MM.DB:CreateSmartAction("Custom")
      MM.DB:AddCandidate(key, { type = "spell", id = 11 })
      MM.DB:AddCandidate(key, { type = "spell", id = 22 })
      MM.DB:AddCandidate(key, { type = "spell", id = 33 })

      assert.is_true(MM.DB:MoveCandidate(key, 3, 1))
      local candidates = MM.DB:SmartActions()[key].candidates
      assert.equals(33, candidates[1].id)
      assert.equals(11, candidates[2].id)
      assert.equals(22, candidates[3].id)

      assert.is_true(MM.DB:RemoveCandidate(key, 2))
      candidates = MM.DB:SmartActions()[key].candidates
      assert.equals(2, #candidates)
      assert.equals(33, candidates[1].id)
      assert.equals(22, candidates[2].id)
    end)

    it("rejects bad candidate edits", function()
      local key = MM.DB:CreateSmartAction("Custom")
      local ok = MM.DB:RemoveCandidate(key, 1)
      assert.is_false(ok)
      assert.is_false((MM.DB:AddCandidate(key)))
    end)
  end)

  describe("conditions setters", function()
    it("replaces layer conditions wholesale", function()
      local layerId = MM.DB:CreateLayer("Healing")
      assert.is_true(MM.DB:SetLayerConditions(layerId, { classes = { "PALADIN" } }))
      assert.same({ "PALADIN" }, MM.DB:GetLayer(layerId).conditions.classes)
      assert.is_false((MM.DB:SetLayerConditions("nope", {})))
    end)

    it("replaces candidate conditions wholesale", function()
      local key = MM.DB:CreateSmartAction("Custom")
      MM.DB:AddCandidate(key, { type = "spell", id = 11 })
      assert.is_true(MM.DB:SetCandidateConditions(key, 1, { roles = { "TANK" } }))
      assert.same({ "TANK" }, MM.DB:SmartActions()[key].candidates[1].conditions.roles)
      assert.is_false((MM.DB:SetCandidateConditions(key, 2, {})))
    end)
  end)

  describe("adoption", function()
    it("adopts a smart action under a caller-uniqued key", function()
      local key = MM.DB:AdoptSmartAction(nil, "imported", { name = "Imported", candidates = {} })
      assert.equals("imported", key)
      assert.equals("Imported", MM.DB:SmartActions()["imported"].name)

      local duplicate, reason = MM.DB:AdoptSmartAction(nil, "imported", { name = "Again" })
      assert.is_nil(duplicate)
      assert.equals("smart action already exists", reason)
    end)

    -- A sharing string is untrusted, and everything downstream (the macro namer,
    -- the rail) relies on every smart action having a name.
    it("names an imported smart action that arrives without one", function()
      local missing = MM.DB:AdoptSmartAction(nil, "nameless", { candidates = {} })
      assert.is_string(MM.DB:SmartActions()[missing].name)
      assert.not_equals("", MM.DB:SmartActions()[missing].name)

      local blank = MM.DB:AdoptSmartAction(nil, "blank", { name = "", candidates = {} })
      assert.not_equals("", MM.DB:SmartActions()[blank].name)
    end)

    it("adopts a layer under a fresh key and appends it to the order", function()
      local key = MM.DB:AdoptLayer(nil, { name = "Imported", slots = {}, enabled = true })
      assert.is_string(key)
      local order = MM.DB:GetProfile().layerOrder
      assert.equals(key, order[#order])
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
