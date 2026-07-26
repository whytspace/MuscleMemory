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

  describe("plurals", function()
    it("uses the two English forms when the locale has no table", function()
      assert.equals("1 slot", MM.L:Plural(1, "%d slot", "%d slots"))
      assert.equals("0 slots", MM.L:Plural(0, "%d slot", "%d slots"))
      assert.equals("5 slots", MM.L:Plural(5, "%d slot", "%d slots"))
    end)

    it("splits one/other by default for a locale that defines no rule", function()
      MM.Locales.zzTEST = { ["%d slot#one"] = "%d Slot", ["%d slot#other"] = "%d Slots" }
      MM.locale = "zzTEST"
      assert.equals("1 Slot", MM.L:Plural(1, "%d slot", "%d slots"))
      assert.equals("0 Slots", MM.L:Plural(0, "%d slot", "%d slots"))
    end)

    it("follows a locale's own rule", function()
      -- Russian: 1/21/31 one, 2-4 few, 5-20 many.
      MM.Locales.zzTEST = {
        plural = function(n)
          if n % 10 == 1 and n % 100 ~= 11 then
            return "one"
          elseif n % 10 >= 2 and n % 10 <= 4 and (n % 100 < 12 or n % 100 > 14) then
            return "few"
          end
          return "many"
        end,
        ["%d slot#one"] = "%d слот",
        ["%d slot#few"] = "%d слота",
        ["%d slot#many"] = "%d слотов",
      }
      MM.locale = "zzTEST"
      assert.equals("1 слот", MM.L:Plural(1, "%d slot", "%d slots"))
      assert.equals("3 слота", MM.L:Plural(3, "%d slot", "%d slots"))
      assert.equals("11 слотов", MM.L:Plural(11, "%d slot", "%d slots"))
      assert.equals("21 слот", MM.L:Plural(21, "%d slot", "%d slots"))
    end)

    it("lets a locale count zero as singular", function()
      -- French treats 0 like 1.
      MM.Locales.zzTEST = {
        plural = function(n)
          return n < 2 and "one" or "other"
        end,
        ["%d slot#one"] = "%d emplacement",
        ["%d slot#other"] = "%d emplacements",
      }
      MM.locale = "zzTEST"
      assert.equals("0 emplacement", MM.L:Plural(0, "%d slot", "%d slots"))
      assert.equals("2 emplacements", MM.L:Plural(2, "%d slot", "%d slots"))
    end)

    it("falls back to English when a form is untranslated", function()
      MM.Locales.zzTEST = { ["%d slot#one"] = "%d Slot" }
      MM.locale = "zzTEST"
      assert.equals("1 Slot", MM.L:Plural(1, "%d slot", "%d slots"))
      assert.equals("7 slots", MM.L:Plural(7, "%d slot", "%d slots"))
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
