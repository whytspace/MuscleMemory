local addon = require("spec.helpers.addon")

describe("Share", function()
  local MM

  -- A profile with two layers and two custom dynamic actions; the "Raid" layer
  -- references one of them plus a predefined one and an inline macro.
  local function seedContent()
    local profileId = MM.DB:GetActiveProfileId()
    local profile = MM.DB:GetProfile(profileId)
    profile.dynamicActions = {
      burst = { name = "Burst", candidates = { { type = "spell", id = 100 } } },
      heal = { name = "Heal", candidates = { { type = "item", id = 200 } } },
    }
    profile.layers.Core.slots = {
      [1] = { type = "spell", id = 1766 },
      [2] = { type = "dynamicaction", source = "custom", id = "burst" },
    }
    profile.layers.Raid = {
      name = "Raid",
      enabled = true,
      slots = {
        [1] = { type = "dynamicaction", source = "custom", id = "heal" },
        [2] = { type = "dynamicaction", source = "predefined", id = "interrupt" },
        [3] = { type = "macro", bodyHash = "h", body = "/use 13", scope = "global", nameHint = "Trinket" },
      },
    }
    profile.layerOrder = { "Core", "Raid" }
    return profileId, profile
  end

  before_each(function()
    MM = addon.fresh()
  end)

  describe("BuildPackage", function()
    it("packs the whole profile including settings when no selection is given", function()
      local profileId = seedContent()
      local package = MM.Share:BuildPackage(profileId)

      assert.equals(MM.SCHEMA_VERSION, package.schemaVersion)
      assert.equals("Default", package.profileName)
      assert.equals(2, #package.layers)
      assert.equals("Core", package.layers[1].key)
      assert.equals("Raid", package.layers[2].key)
      assert.is_table(package.dynamicActions.burst)
      assert.is_table(package.dynamicActions.heal)
      assert.same({ fallback = "keep", response = "popup" }, package.settings)
    end)

    it("always bundles the custom dynamic actions a selected layer references", function()
      local profileId = seedContent()
      local package = MM.Share:BuildPackage(profileId, { layers = { Raid = true } })

      assert.equals(1, #package.layers)
      assert.equals("Raid", package.layers[1].key)
      assert.is_table(package.dynamicActions.heal)
      assert.is_nil(package.dynamicActions.burst)
      assert.is_nil(package.settings)
    end)

    it("exports dynamic actions on their own", function()
      local profileId = seedContent()
      local package = MM.Share:BuildPackage(profileId, { dynamicActions = { burst = true } })

      assert.equals(0, #package.layers)
      assert.is_table(package.dynamicActions.burst)
      assert.is_nil(package.dynamicActions.heal)
    end)

    it("rejects an empty selection", function()
      local profileId = seedContent()
      local package, reason = MM.Share:BuildPackage(profileId, {})
      assert.is_nil(package)
      assert.equals("nothing selected to export", reason)
    end)

    it("copies data instead of referencing profile tables", function()
      local profileId, profile = seedContent()
      local package = MM.Share:BuildPackage(profileId)
      package.dynamicActions.burst.name = "Changed"
      assert.equals("Burst", profile.dynamicActions.burst.name)
    end)
  end)

  describe("Encode/Decode", function()
    it("round-trips a package through the printable string", function()
      local profileId = seedContent()
      local package = MM.Share:BuildPackage(profileId)

      local text = MM.Share:Encode(package)
      assert.is_string(text)
      assert.truthy(text:match("^!MM:1!"))
      assert.truthy(text:match("^!MM:1![%w%(%)]*$"))

      local decoded = MM.Share:Decode(text)
      assert.same(package, decoded)
    end)

    it("tolerates whitespace and line breaks pasted around the string", function()
      local profileId = seedContent()
      local text = MM.Share:Encode(MM.Share:BuildPackage(profileId))
      local mangled = "  " .. text:sub(1, 20) .. "\n" .. text:sub(21) .. " \n"
      assert.is_table(MM.Share:Decode(mangled))
    end)

    it("rejects strings that are not exports", function()
      local decoded, reason = MM.Share:Decode("hello there")
      assert.is_nil(decoded)
      assert.equals("not a Muscle Memory sharing string", reason)
    end)

    it("rejects a damaged payload", function()
      local profileId = seedContent()
      local text = MM.Share:Encode(MM.Share:BuildPackage(profileId))
      local decoded, reason = MM.Share:Decode(text:sub(1, #text - 10))
      assert.is_nil(decoded)
      assert.equals("the string is damaged or incomplete", reason)
    end)

    it("rejects exports from a newer format or schema", function()
      local decoded, reason = MM.Share:Decode("!MM:99!AAAA")
      assert.is_nil(decoded)
      assert.equals("this export needs a newer Muscle Memory version", reason)

      local profileId = seedContent()
      local package = MM.Share:BuildPackage(profileId)
      package.schemaVersion = MM.SCHEMA_VERSION + 1
      decoded, reason = MM.Share:Decode(MM.Share:Encode(package))
      assert.is_nil(decoded)
      assert.equals("this export needs a newer Muscle Memory version", reason)
    end)
  end)

  describe("Import", function()
    it("imports everything into the current profile with fresh keys", function()
      local profileId = seedContent()
      local package = MM.Share:BuildPackage(profileId)

      local result = MM.Share:Import(package, nil, { profileId = profileId })

      -- Existing entities untouched, imports created alongside with new keys.
      -- (Slugs are lowercase, so "Core" imports as "core", "burst" as "burst_2".)
      local profile = MM.DB:GetProfile(profileId)
      assert.equals("Burst", profile.dynamicActions.burst.name)
      assert.equals("Burst", profile.dynamicActions.burst_2.name)
      assert.equals("Heal", profile.dynamicActions.heal_2.name)
      assert.is_table(profile.layers.core)
      assert.is_table(profile.layers.raid)
      -- Imports append below the existing layers, keeping their own order.
      assert.same({ "Core", "Raid", "core", "raid" }, profile.layerOrder)
      assert.same({ profileId = profileId, layers = { "core", "raid" }, dynamicActions = { "burst_2", "heal_2" } }, {
        profileId = result.profileId,
        layers = result.layers,
        dynamicActions = result.dynamicActions,
      })
    end)

    it("rewrites imported layer slots to the re-keyed dynamic actions", function()
      local profileId = seedContent()
      local package = MM.Share:BuildPackage(profileId)
      MM.Share:Import(package, nil, { profileId = profileId })

      local profile = MM.DB:GetProfile(profileId)
      assert.same({ type = "dynamicaction", source = "custom", id = "burst_2" }, profile.layers.core.slots[2])
      assert.same({ type = "dynamicaction", source = "custom", id = "heal_2" }, profile.layers.raid.slots[1])
      -- Predefined references and macros pass through untouched.
      assert.same({ type = "dynamicaction", source = "predefined", id = "interrupt" }, profile.layers.raid.slots[2])
      assert.equals("/use 13", profile.layers.raid.slots[3].body)
    end)

    it("imports a partial selection and keeps layer dependencies", function()
      local profileId = seedContent()
      local package = MM.Share:BuildPackage(profileId)

      -- Only the Raid layer: heal must come along, burst must not.
      MM.Share:Import(package, { layers = { Raid = true }, dynamicActions = {} }, { profileId = profileId })

      local profile = MM.DB:GetProfile(profileId)
      assert.is_table(profile.layers.raid)
      assert.is_nil(profile.layers.core)
      assert.is_table(profile.dynamicActions.heal_2)
      assert.is_nil(profile.dynamicActions.burst_2)
    end)

    it("imports into a new profile with the package settings", function()
      local profileId = seedContent()
      local profile = MM.DB:GetProfile(profileId)
      profile.fallback = "clear"
      profile.response = "apply"
      local package = MM.Share:BuildPackage(profileId)

      local result = MM.Share:Import(package, nil, { newProfile = "From Guildie" })

      assert.is_not_equal(profileId, result.profileId)
      local imported = MM.DB:GetProfile(result.profileId)
      assert.equals("From Guildie", imported.name)
      assert.equals("clear", imported.fallback)
      assert.equals("apply", imported.response)
      -- Fresh profile, so the original keys are free again.
      assert.is_table(imported.layers.core)
      assert.is_table(imported.layers.raid)
      assert.same({ "core", "raid" }, imported.layerOrder)
      assert.same({ type = "dynamicaction", source = "custom", id = "heal" }, imported.layers.raid.slots[1])
    end)

    it("falls back to the exported profile name for a new profile", function()
      local profileId = seedContent()
      local package = MM.Share:BuildPackage(profileId)
      local result = MM.Share:Import(package, nil, { newProfile = "" })
      assert.equals("Default", MM.DB:GetProfile(result.profileId).name)
    end)

    it("rejects an empty selection", function()
      local profileId = seedContent()
      local package = MM.Share:BuildPackage(profileId)
      local result, reason = MM.Share:Import(package, { layers = {}, dynamicActions = {} }, { profileId = profileId })
      assert.is_nil(result)
      assert.equals("nothing selected to import", reason)
    end)

    it("marks imported entities for the session pills", function()
      local profileId = seedContent()
      local package = MM.Share:BuildPackage(profileId)
      local result = MM.Share:Import(package, nil, { newProfile = "Shared" })

      assert.is_true(MM.Share:IsImportedProfile(result.profileId))
      assert.is_false(MM.Share:IsImportedProfile(profileId))
      assert.is_true(MM.Share:IsRecentImport("layers", result.profileId, "raid"))
      assert.is_true(MM.Share:IsRecentImport("dynamicActions", result.profileId, "burst"))
      assert.is_false(MM.Share:IsRecentImport("layers", profileId, "Core"))
    end)
  end)
end)
