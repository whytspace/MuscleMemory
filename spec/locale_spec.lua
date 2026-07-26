local addon = require("spec.helpers.addon")

describe("Locales", function()
  local MM

  before_each(function()
    MM = addon.fresh()
  end)

  describe("the L proxy", function()
    it("falls back to the key when no locale table has it", function()
      assert.equals("no changes", MM.L["no changes"])
      assert.equals("a string nobody translated", MM.L["a string nobody translated"])
    end)

    it("returns the active locale's translation", function()
      MM.Locales.zzTEST = { ["no changes"] = "keine" }
      MM.locale = "zzTEST"
      assert.equals("keine", MM.L["no changes"])
      -- Untranslated keys still fall through to English.
      assert.equals("failed", MM.L["failed"])
    end)

    it("resolves at read time, so a captured reference follows the switch", function()
      local L = MM.L
      MM.Locales.zzTEST = { ["failed"] = "fehlgeschlagen" }
      MM.locale = "zzTEST"
      assert.equals("fehlgeschlagen", L["failed"])
    end)
  end)

  describe("translated output", function()
    it("localizes slot labels through the active locale", function()
      MM.Locales.zzTEST = { ["%s button %d"] = "%s Knopf %d", ["Bar 1"] = "Leiste 1" }
      MM.locale = "zzTEST"
      assert.equals("Leiste 1 Knopf 3", MM.Actions.GetSlotLabel(3))
    end)

    it("localizes undo labels through the active locale", function()
      MM.Locales.zzTEST = { ["create a layer"] = "eine Ebene erstellen" }
      MM.locale = "zzTEST"
      MM.DB:CreateLayer()
      assert.equals("eine Ebene erstellen", MM.Undo:NextUndoLabel())
    end)
  end)

  -- Each locale file gates on MM.locale, so only the client's language loads.
  it("registers a locale table only when MM.locale matches", function()
    local other = addon.loadFile("Locales/deDE.lua", { Locales = {}, locale = "enUS" })
    assert.is_nil(other.Locales.deDE)

    local german = addon.loadFile("Locales/deDE.lua", { Locales = {}, locale = "deDE" })
    assert.is_table(german.Locales.deDE)
  end)

  -- A lookup at file scope would bake whichever language was active at load.
  it("never resolves a translation at file scope", function()
    local found = addon.fileScopeLookups()
    assert.same({}, found)
  end)
end)
