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

    it("reports ambiguity naming the macro", function()
      local macro, reason = MM.Macros.FindUniqueByName("Dup")
      assert.is_nil(macro)
      assert.equals('macro name "Dup" is ambiguous', reason)
    end)

    it("reports a missing name naming the macro", function()
      local macro, reason = MM.Macros.FindUniqueByName("Nope")
      assert.is_nil(macro)
      assert.equals('macro "Nope" not found', reason)
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

    it("yields a body match to the uniquely-named macro when bodies collide", function()
      -- Auto-updated inventory macros: Drink was emptied to the shared stub
      -- body an alt's sync left in Health's reference; the body match on Drink
      -- must not steal the reference while a macro named Health still exists.
      stubs:addGlobalMacro({ name = "Drink", body = "#showtooltip" })
      stubs:addGlobalMacro({ name = "Health", body = "#showtooltip\n/use item:241305" })
      local macro = MM.Macros.Resolve({
        indexHint = 4,
        bodyHash = MM.Macros.HashBody("#showtooltip"),
        nameHint = "Health",
        scope = "global",
      })
      assert.equals("Health", macro.name)
    end)

    it("still follows a body match when the captured name is gone (rename)", function()
      local macro = MM.Macros.Resolve({
        indexHint = 1,
        bodyHash = MM.Macros.HashBody("/cast A"),
        nameHint = "OldName",
        scope = "global",
      })
      assert.equals("A", macro.name)
    end)

    it("reports a miss when no body hash matches", function()
      local macro, reason, state = MM.Macros.Resolve({ bodyHash = "deadbeef" })
      assert.is_nil(macro)
      assert.equals("macro body hash not found", reason)
      assert.equals("missing", state)
    end)

    it("falls back to the name when the body changed", function()
      local macro = MM.Macros.Resolve({ bodyHash = "deadbeef", nameHint = "C", scope = "character" })
      assert.equals("C", macro.name)
      assert.equals("character", macro.scope)
    end)

    it("prefers the captured scope when the name exists in both", function()
      stubs:addGlobalMacro({ name = "C", body = "/cast global C" })
      local macro = MM.Macros.Resolve({ bodyHash = "deadbeef", nameHint = "C", scope = "character" })
      assert.equals("character", macro.scope)
    end)

    it("refuses an ambiguous name, naming it", function()
      stubs:addGlobalMacro({ name = "A", body = "/other A" })
      local macro, reason = MM.Macros.Resolve({ bodyHash = "deadbeef", nameHint = "A", scope = "global" })
      assert.is_nil(macro)
      assert.equals('macro name "A" is ambiguous', reason)
    end)

    it("reports a missing named macro as restorable", function()
      local macro, reason, state = MM.Macros.Resolve({ bodyHash = "deadbeef", nameHint = "Gone", scope = "character" })
      assert.is_nil(macro)
      assert.equals('macro "Gone" not found', reason)
      assert.equals("missing", state)
    end)
  end)

  describe("RestoreUserMacro", function()
    it("recreates a character macro in character scope", function()
      local macro = MM.Macros.RestoreUserMacro({ name = "Mine", body = "/cast Mine", scope = "character" })
      assert.equals("character", macro.scope)
      assert.equals(121, macro.index)
      assert.equals(MM.Macros.HashBody("/cast Mine"), macro.bodyHash)
      assert.equals("Mine", stubs.world.charMacros[1].name)
    end)

    it("recreates a global macro in global scope", function()
      local macro = MM.Macros.RestoreUserMacro({ name = "Mine", body = "/cast Mine", scope = "global" })
      assert.equals("global", macro.scope)
      assert.equals("Mine", stubs.world.globalMacros[1].name)
    end)

    it("fails when the character macro slots are full", function()
      for index = 1, 30 do
        stubs:addCharacterMacro({ name = "M" .. index, body = "/cast " .. index })
      end
      local macro, reason = MM.Macros.RestoreUserMacro({ name = "Mine", body = "/x", scope = "character" })
      assert.is_nil(macro)
      assert.equals("character macro slots are full", reason)
    end)

    it("requires a stored body", function()
      local macro, reason = MM.Macros.RestoreUserMacro({ name = "Mine", scope = "character" })
      assert.is_nil(macro)
      assert.equals("no stored macro body to restore", reason)
    end)

    it("recreates a dynamic macro with the dynamic icon placeholder", function()
      MM.Macros.RestoreUserMacro({
        name = "Mine",
        body = "#showtooltip\n/cast Mine",
        scope = "character",
        icon = MM.MACRO_DYNAMIC_ICON,
      })
      assert.equals(MM.MACRO_DYNAMIC_ICON, stubs.world.charMacros[1].icon)
    end)

    it("preserves a hardcoded icon", function()
      MM.Macros.RestoreUserMacro({
        name = "Mine",
        body = "#showtooltip\n/use 10",
        scope = "character",
        icon = 132120,
      })
      assert.equals(132120, stubs.world.charMacros[1].icon)
    end)
  end)

  describe("CandidatesCompatible / EffectiveMode", function()
    it("accepts smart actions whose candidates are all spell/item/mount", function()
      local smartAction = { candidates = { { type = "spell" }, { type = "item" }, { type = "mount" } } }
      assert.is_true(MM.Macros.CandidatesCompatible(smartAction))
    end)

    it("rejects an empty candidate list", function()
      assert.is_false(MM.Macros.CandidatesCompatible({ candidates = {} }))
    end)

    it("rejects a smart action containing a non-family candidate", function()
      local smartAction = { candidates = { { type = "spell" }, { type = "battlepet" } } }
      assert.is_false(MM.Macros.CandidatesCompatible(smartAction))
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
      local smartAction = {
        macroTemplate = "/use %name%",
        candidates = { { type = "spell", id = 1 }, { type = "spell", id = 2 } },
      }
      assert.equals(#("/use " .. string.rep("A", 40)), MM.Macros.WorstCaseLength(smartAction))
      assert.is_true(MM.Macros.FitsLimit(smartAction))
    end)

    it("reports over the cap and forces normal mode", function()
      stubs:setSpell(1, { name = string.rep("Z", 260) })
      local smartAction = { mode = "macro", macroTemplate = "/use %name%", candidates = { { type = "spell", id = 1 } } }
      assert.is_false(MM.Macros.FitsLimit(smartAction))
      assert.equals("normal", MM.Macros.EffectiveMode(smartAction))
    end)
  end)

  describe("ResolvedAsMacro", function()
    it("returns the rendered body for a macro-mode family action", function()
      stubs:setSpell(1, { name = "Kick" })
      local smartAction = { mode = "macro", macroTemplate = "/use %name%", candidates = { { type = "spell", id = 1 } } }
      local resolved = { kind = "spell", id = 1, label = "Kick", smartAction = smartAction }
      assert.equals("/use Kick", MM.Macros.ResolvedAsMacro(resolved))
    end)

    it("returns nil when the smart action is not in macro mode", function()
      local resolved =
        { kind = "spell", id = 1, label = "Kick", smartAction = { candidates = { { type = "spell", id = 1 } } } }
      assert.is_nil(MM.Macros.ResolvedAsMacro(resolved))
    end)

    it("returns nil when there is no backing smart action (a direct assignment)", function()
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
      -- The visible part stays a prefix of the smartAction name.
      local base = name:sub(1, #name - #marker)
      assert.equals(base, long:sub(1, #base))
    end)

    it("refuses to name a macro for a smart action with no name", function()
      local name, reason = MM.Macros.MacroName({ name = "" })
      assert.is_nil(name)
      assert.equals("smart action has no name", reason)
      assert.is_nil(MM.Macros.MacroName({}))
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
