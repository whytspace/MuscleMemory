local addon = require("spec.helpers.addon")

describe("Macros", function()
  local MM, stubs
  before_each(function()
    MM, stubs = addon.load()
  end)

  describe("HashBody", function()
    it("is deterministic and 8 hex chars", function()
      local hash = MM.Macros.HashBody("/cast Fireball")
      assert.equals(hash, MM.Macros.HashBody("/cast Fireball"))
      assert.matches("^%x%x%x%x%x%x%x%x$", hash)
    end)

    it("differs for different bodies", function()
      assert.are_not.equal(MM.Macros.HashBody("/cast A"), MM.Macros.HashBody("/cast B"))
    end)

    it("treats nil as the empty string", function()
      assert.equals(MM.Macros.HashBody(""), MM.Macros.HashBody(nil))
    end)

    it("ignores the trailing newline the client appends on persist", function()
      -- A reloaded macro body comes back with a trailing \n; it must hash the
      -- same as the body we rendered so the slot doesn't read as a pending change.
      local body = "#showtooltip\n/use [@focus,harm][] Mind Freeze"
      assert.equals(MM.Macros.HashBody(body), MM.Macros.HashBody(body .. "\n"))
    end)
  end)

  describe("GetMacroScope", function()
    it("classifies low indices as global and high ones as character", function()
      assert.equals("global", MM.Macros.GetMacroScope(2, 5))
      assert.equals("global", MM.Macros.GetMacroScope(50, 0))
      assert.equals("character", MM.Macros.GetMacroScope(121, 2))
    end)
  end)

  describe("Scan", function()
    it("returns an empty list when the macro API is unavailable", function()
      local _, _, env = addon.load()
      env.GetNumMacros = nil
      assert.same({}, MM.Macros.Scan())
    end)

    it("scans global and character macros with their scopes and indices", function()
      stubs:addGlobalMacro({ name = "A", icon = 1, body = "/cast A" })
      stubs:addGlobalMacro({ name = "B", icon = 2, body = "/cast B" })
      stubs:addCharacterMacro({ name = "C", icon = 3, body = "/cast C" })

      local macros = MM.Macros.Scan()
      assert.equals(3, #macros)
      assert.equals("global", macros[1].scope)
      assert.equals("global", macros[2].scope)
      assert.equals("character", macros[3].scope)
      assert.equals(121, macros[3].index)
      assert.equals(MM.Macros.HashBody("/cast C"), macros[3].bodyHash)
    end)
  end)

  describe("FindUniqueByName", function()
    before_each(function()
      stubs:addGlobalMacro({ name = "Solo", body = "/cast Solo" })
      stubs:addGlobalMacro({ name = "Dup", body = "/one" })
      stubs:addGlobalMacro({ name = "Dup", body = "/two" })
    end)

    it("returns the single match", function()
      local macro = MM.Macros.FindUniqueByName("Solo")
      assert.equals("Solo", macro.name)
    end)

    it("reports ambiguity", function()
      local macro, reason = MM.Macros.FindUniqueByName("Dup")
      assert.is_nil(macro)
      assert.equals("macro name is ambiguous", reason)
    end)

    it("reports a missing name", function()
      local macro, reason = MM.Macros.FindUniqueByName("Nope")
      assert.is_nil(macro)
      assert.equals("macro name not found", reason)
    end)

    it("reports an unavailable name", function()
      local macro, reason = MM.Macros.FindUniqueByName(nil)
      assert.is_nil(macro)
      assert.equals("macro name unavailable", reason)
    end)
  end)

  describe("Resolve", function()
    before_each(function()
      stubs:addGlobalMacro({ name = "A", body = "/cast A" })
      stubs:addGlobalMacro({ name = "B", body = "/cast B" })
      stubs:addCharacterMacro({ name = "C", body = "/cast C" })
    end)

    it("requires a body hash", function()
      local macro, reason = MM.Macros.Resolve({})
      assert.is_nil(macro)
      assert.equals("macro reference has no body hash", reason)
    end)

    it("matches on index hint plus body hash first", function()
      local macro = MM.Macros.Resolve({ indexHint = 2, bodyHash = MM.Macros.HashBody("/cast B"), scope = "global" })
      assert.equals(2, macro.index)
      assert.equals("B", macro.name)
    end)

    it("falls back to scope plus body hash when the index moved", function()
      local macro = MM.Macros.Resolve({ indexHint = 99, bodyHash = MM.Macros.HashBody("/cast A"), scope = "global" })
      assert.equals(1, macro.index)
    end)

    it("falls back to body hash alone when scope no longer matches", function()
      local macro = MM.Macros.Resolve({ bodyHash = MM.Macros.HashBody("/cast A"), scope = "character" })
      assert.equals(1, macro.index)
    end)

    it("reports a miss when no body hash matches", function()
      local macro, reason = MM.Macros.Resolve({ bodyHash = "deadbeef" })
      assert.is_nil(macro)
      assert.equals("macro body hash not found", reason)
    end)
  end)

  describe("CandidatesCompatible / EffectiveMode", function()
    it("accepts dynamic actions whose candidates are all spell/item/mount", function()
      local dynamicAction = { candidates = { { type = "spell" }, { type = "item" }, { type = "mount" } } }
      assert.is_true(MM.Macros.CandidatesCompatible(dynamicAction))
    end)

    it("rejects an empty candidate list", function()
      assert.is_false(MM.Macros.CandidatesCompatible({ candidates = {} }))
    end)

    it("rejects a dynamic action containing a non-family candidate", function()
      local dynamicAction = { candidates = { { type = "spell" }, { type = "battlepet" } } }
      assert.is_false(MM.Macros.CandidatesCompatible(dynamicAction))
    end)

    it("is macro only when opted in and compatible", function()
      local ok = { mode = "macro", candidates = { { type = "spell" } } }
      local incompatible = { mode = "macro", candidates = { { type = "equipmentset" } } }
      local normal = { candidates = { { type = "spell" } } }
      assert.equals("macro", MM.Macros.EffectiveMode(ok))
      assert.equals("normal", MM.Macros.EffectiveMode(incompatible))
      assert.equals("normal", MM.Macros.EffectiveMode(normal))
    end)
  end)

  describe("WorstCaseLength / FitsLimit", function()
    it("measures the candidate whose name renders longest", function()
      stubs:setSpell(1, { name = "Kick" })
      stubs:setSpell(2, { name = string.rep("A", 40) })
      local dynamicAction = {
        macroTemplate = "/use %name%",
        candidates = { { type = "spell", id = 1 }, { type = "spell", id = 2 } },
      }
      assert.equals(#("/use " .. string.rep("A", 40)), MM.Macros.WorstCaseLength(dynamicAction))
      assert.is_true(MM.Macros.FitsLimit(dynamicAction))
    end)

    it("reports over the cap and forces normal mode", function()
      stubs:setSpell(1, { name = string.rep("Z", 260) })
      local dynamicAction =
        { mode = "macro", macroTemplate = "/use %name%", candidates = { { type = "spell", id = 1 } } }
      assert.is_false(MM.Macros.FitsLimit(dynamicAction))
      assert.equals("normal", MM.Macros.EffectiveMode(dynamicAction))
    end)
  end)

  describe("ResolvedAsMacro", function()
    it("returns the rendered body for a macro-mode family action", function()
      stubs:setSpell(1, { name = "Kick" })
      local dynamicAction =
        { mode = "macro", macroTemplate = "/use %name%", candidates = { { type = "spell", id = 1 } } }
      local resolved = { kind = "spell", id = 1, label = "Kick", dynamicAction = dynamicAction }
      assert.equals("/use Kick", MM.Macros.ResolvedAsMacro(resolved))
    end)

    it("returns nil when the dynamic action is not in macro mode", function()
      local resolved =
        { kind = "spell", id = 1, label = "Kick", dynamicAction = { candidates = { { type = "spell", id = 1 } } } }
      assert.is_nil(MM.Macros.ResolvedAsMacro(resolved))
    end)

    it("returns nil when there is no backing dynamic action (a direct assignment)", function()
      assert.is_nil(MM.Macros.ResolvedAsMacro({ kind = "spell", id = 1, label = "Kick" }))
    end)
  end)

  describe("RenderTemplate", function()
    it("substitutes the resolved name and id", function()
      local body = MM.Macros.RenderTemplate("#showtooltip\n/use [@focus] %name%; %name%", { label = "Kick", id = 1766 })
      assert.equals("#showtooltip\n/use [@focus] Kick; Kick", body)
    end)

    it("substitutes %id%", function()
      local body = MM.Macros.RenderTemplate("/use item:%id%", { label = "Healthstone", id = 5512 })
      assert.equals("/use item:5512", body)
    end)

    it("escapes percent signs in the resolved name", function()
      local body = MM.Macros.RenderTemplate("/use %name%", { label = "50%% Off", id = 1 })
      assert.equals("/use 50%% Off", body)
    end)

    it("rejects a body that would exceed the 255 cap", function()
      local body, reason =
        MM.Macros.RenderTemplate("/use " .. string.rep("x", 260) .. "%name%", { label = "A", id = 1 })
      assert.is_nil(body)
      assert.matches("255", reason)
    end)
  end)

  describe("MacroName", function()
    local marker = MM.MACRO_NAME_MARKER

    it("appends the owner marker, truncating to the byte cap", function()
      local long = "Interrupt the Boss Adds"
      local name = MM.Macros.MacroName({ name = long })
      assert.is_true(#name <= MM.MACRO_NAME_LIMIT)
      assert.is_true(MM.Macros.IsOwned({ name = name }))
      -- The visible part stays a prefix of the dynamicAction name.
      local base = name:sub(1, #name - #marker)
      assert.equals(base, long:sub(1, #base))
    end)

    it("falls back to a default for an empty name", function()
      local name = MM.Macros.MacroName({ name = "" })
      assert.is_true(MM.Macros.IsOwned({ name = name }))
      assert.equals("Dynamic Action", name:sub(1, #name - #marker))
    end)

    it("recognises only marked macros as owned", function()
      assert.is_false(MM.Macros.IsOwned({ name = "Kick" }))
      assert.is_true(MM.Macros.IsOwned({ name = "Kick" .. marker }))
    end)
  end)

  describe("EnsureMacro", function()
    it("creates a new character macro when none exists", function()
      local macro, record = MM.Macros.EnsureMacro(nil, "Kick", "/use Kick")
      assert.equals(121, macro.index)
      assert.equals("character", record.scope)
      assert.equals(121, record.indexHint)
      assert.equals(1, #stubs.world.charMacros)
    end)

    it("reuses an existing macro with the same body without creating another", function()
      local _, record = MM.Macros.EnsureMacro(nil, "Kick", "/use Kick")
      local macro = MM.Macros.EnsureMacro(record, "Kick", "/use Kick")
      assert.equals(121, macro.index)
      assert.equals(1, #stubs.world.charMacros) -- still one macro, reused
    end)

    it("renames a reused macro when the desired name changed", function()
      local _, record = MM.Macros.EnsureMacro(nil, "Kick", "/use Kick")
      local macro, newRecord = MM.Macros.EnsureMacro(record, "Kicker", "/use Kick")
      assert.equals(record.indexHint, macro.index) -- same macro, reused
      assert.equals("Kicker", macro.name)
      assert.equals("Kicker", newRecord.name)
      assert.equals(1, #stubs.world.charMacros)
      assert.equals("Kicker", stubs.world.charMacros[1].name)
    end)

    it("edits in place when the body changes", function()
      local _, record = MM.Macros.EnsureMacro(nil, "Kick", "/use Kick")
      local macro = MM.Macros.EnsureMacro(record, "Kick", "/use [@focus] Kick")
      assert.equals(121, macro.index)
      assert.equals(1, #stubs.world.charMacros) -- edited, not duplicated
      assert.equals("/use [@focus] Kick", stubs.world.charMacros[1].body)
    end)

    it("fails softly when character macro slots are full", function()
      for index = 1, stubs.world.charMacroLimit do
        stubs:addCharacterMacro({ name = "M" .. index, body = "/cast " .. index })
      end
      local macro, reason = MM.Macros.EnsureMacro(nil, "Kick", "/use Kick")
      assert.is_nil(macro)
      assert.matches("full", reason)
    end)
  end)

  describe("WouldUpdate", function()
    it("is false when no macro exists yet", function()
      assert.is_false(MM.Macros.WouldUpdate(nil, "/use Kick"))
    end)

    it("is true when a macro already holds the body (e.g. a rename)", function()
      local _, record = MM.Macros.EnsureMacro(nil, "Kick", "/use Kick")
      assert.is_true(MM.Macros.WouldUpdate(record, "/use Kick"))
    end)

    it("is true when our macro exists but the body changed", function()
      local _, record = MM.Macros.EnsureMacro(nil, "Kick", "/use Kick")
      assert.is_true(MM.Macros.WouldUpdate(record, "/use [@focus] Kick"))
    end)
  end)

  describe("DeleteOwned", function()
    it("deletes a macro that still matches the record", function()
      local _, record = MM.Macros.EnsureMacro(nil, "Kick", "/use Kick")
      assert.is_true(MM.Macros.DeleteOwned(record))
      assert.equals(0, #stubs.world.charMacros)
    end)

    it("leaves a macro the player changed alone", function()
      local _, record = MM.Macros.EnsureMacro(nil, "Kick", "/use Kick")
      stubs.world.charMacros[1].body = "/say hijacked"
      assert.is_false(MM.Macros.DeleteOwned(record))
      assert.equals(1, #stubs.world.charMacros)
    end)
  end)
end)
