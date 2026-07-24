local addon = require("spec.helpers.addon")

local MM = addon.load()
local Tables = MM.Tables

describe("Tables.DeepCopy", function()
  it("returns non-table values unchanged", function()
    assert.equals(5, Tables.DeepCopy(5))
    assert.equals("x", Tables.DeepCopy("x"))
    assert.equals(true, Tables.DeepCopy(true))
    assert.is_nil(Tables.DeepCopy(nil))
  end)

  it("produces an independent copy", function()
    local source = { a = 1, nested = { b = 2 } }
    local copy = Tables.DeepCopy(source)

    assert.are_not.equal(source, copy)
    assert.are_not.equal(source.nested, copy.nested)
    assert.same(source, copy)
  end)

  it("does not let mutations of the copy leak back", function()
    local source = { nested = { b = 2 }, list = { 1, 2, 3 } }
    local copy = Tables.DeepCopy(source)

    copy.nested.b = 99
    copy.list[1] = 99

    assert.equals(2, source.nested.b)
    assert.equals(1, source.list[1])
  end)
end)

describe("Tables.MergeDefaults", function()
  it("fills in missing keys", function()
    local result = Tables.MergeDefaults({}, { a = 1, b = 2 })
    assert.equals(1, result.a)
    assert.equals(2, result.b)
  end)

  it("keeps existing values, including falsey ones", function()
    local result = Tables.MergeDefaults({ a = "kept", flag = false }, { a = "default", flag = true })
    assert.equals("kept", result.a)
    assert.equals(false, result.flag)
  end)

  it("recurses into nested tables", function()
    local target = { profiles = { Default = { name = "Mine" } } }
    Tables.MergeDefaults(target, { profiles = { Default = { name = "Default", extra = 1 } } })

    assert.equals("Mine", target.profiles.Default.name)
    assert.equals(1, target.profiles.Default.extra)
  end)

  it("replaces a non-table target with a fresh table", function()
    local result = Tables.MergeDefaults("not a table", { a = 1 })
    assert.is_table(result)
    assert.equals(1, result.a)
  end)
end)

describe("Tables.Count", function()
  it("counts map entries", function()
    assert.equals(0, Tables.Count({}))
    assert.equals(0, Tables.Count(nil))
    assert.equals(3, Tables.Count({ a = 1, b = 2, c = 3 }))
    assert.equals(2, Tables.Count({ "x", "y" }))
  end)
end)

describe("Tables.DeepEquals", function()
  it("compares nested structures", function()
    assert.is_true(Tables.DeepEquals({ a = { 1, 2 }, b = "x" }, { a = { 1, 2 }, b = "x" }))
    assert.is_false(Tables.DeepEquals({ a = { 1, 2 } }, { a = { 1, 3 } }))
    assert.is_false(Tables.DeepEquals({ a = 1 }, { a = 1, b = 2 }))
    assert.is_false(Tables.DeepEquals({ a = 1, b = 2 }, { a = 1 }))
  end)

  it("handles non-table values", function()
    assert.is_true(Tables.DeepEquals(5, 5))
    assert.is_false(Tables.DeepEquals(5, "5"))
    assert.is_true(Tables.DeepEquals(nil, nil))
    assert.is_false(Tables.DeepEquals({}, nil))
  end)
end)
