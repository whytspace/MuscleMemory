local addon = require("spec.helpers.addon")

describe("Conditions", function()
  local MM, stubs
  before_each(function()
    MM, stubs = addon.fresh()
    stubs:setCharacter({
      class = "DRUID",
      specId = 103,
      role = "DAMAGER",
      level = 70,
      faction = "Horde",
      race = "Tauren",
    })
  end)

  it("matches when there are no conditions", function()
    assert.is_true(MM.Conditions.Match(nil))
    assert.is_true(MM.Conditions.Match({}))
  end)

  it("checks class membership", function()
    assert.is_true(MM.Conditions.Match({ classes = { "DRUID", "HUNTER" } }))
    assert.is_false(MM.Conditions.Match({ classes = { "MAGE" } }))
  end)

  it("checks spec, role, faction and race", function()
    assert.is_true(
      MM.Conditions.Match({ specs = { 103 }, roles = { "DAMAGER" }, factions = { "Horde" }, races = { "Tauren" } })
    )
    assert.is_false(MM.Conditions.Match({ specs = { 104 } }))
    assert.is_false(MM.Conditions.Match({ roles = { "TANK" } }))
    assert.is_false(MM.Conditions.Match({ factions = { "Alliance" } }))
    assert.is_false(MM.Conditions.Match({ races = { "Worgen" } }))
  end)

  it("checks professions, matching any of the listed ones", function()
    stubs:setCharacter({ professions = { 202, 186 } })
    assert.is_true(MM.Conditions.Match({ professions = { 202 } }))
    assert.is_true(MM.Conditions.Match({ professions = { 171, 186 } }))
    assert.is_false(MM.Conditions.Match({ professions = { 171 } }))
  end)

  it("finds a profession that sits in a later slot", function()
    -- GetProfessions leaves the unlearned slots nil; cooking alone answers
    -- nil,nil,nil,nil,index, which a packed iteration would never reach.
    stubs:setCharacter({ professions = { 185 } })
    assert.is_true(MM.Conditions.Match({ professions = { 185 } }))
  end)

  it("matches no profession when the character has none", function()
    stubs:setCharacter({ professions = {} })
    assert.is_false(MM.Conditions.Match({ professions = { 202 } }))
    assert.is_true(MM.Conditions.Match({ professions = {} }))
  end)

  it("checks the level range", function()
    assert.is_true(MM.Conditions.Match({ levelMin = 60, levelMax = 80 }))
    assert.is_false(MM.Conditions.Match({ levelMin = 71 }))
    assert.is_false(MM.Conditions.Match({ levelMax = 69 }))
  end)

  it("reports whether any condition is set", function()
    assert.is_false(MM.Conditions.Any(nil))
    assert.is_false(MM.Conditions.Any({}))
    assert.is_true(MM.Conditions.Any({ roles = { "TANK" } }))
    assert.is_true(MM.Conditions.Any({ levelMin = 10 }))
    assert.is_true(MM.Conditions.Any({ professions = { 202 } }))
  end)
end)
