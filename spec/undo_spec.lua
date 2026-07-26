local addon = require("spec.helpers.addon")

describe("Undo", function()
  local MM, stubs

  before_each(function()
    MM, stubs = addon.fresh()
    MM.Undo:Reset()
  end)

  it("undoes a single mutation", function()
    local layerId = MM.DB:CreateLayer("Healing")
    assert.is_table(MM.DB:GetLayer(layerId))

    assert.is_true(MM.Undo:Undo())
    assert.is_nil(MM.DB:GetLayer(layerId))
  end)

  it("undoes step by step", function()
    local layerId = MM.DB:CreateLayer("Healing")
    MM.DB:SetSlot(layerId, 5, { type = "spell", id = 1766 })
    MM.DB:RenameLayer(layerId, "Holy")

    assert.is_true(MM.Undo:Undo())
    assert.equals("Healing", MM.DB:GetLayer(layerId).name)
    assert.is_table(MM.DB:GetLayer(layerId).slots[5])

    assert.is_true(MM.Undo:Undo())
    assert.is_nil(MM.DB:GetLayer(layerId).slots[5])

    assert.is_true(MM.Undo:Undo())
    assert.is_nil(MM.DB:GetLayer(layerId))
  end)

  it("redoes an undone change and clears redo on a new mutation", function()
    local layerId = MM.DB:CreateLayer("Healing")
    MM.Undo:Undo()
    assert.is_true(MM.Undo:CanRedo())

    assert.is_true(MM.Undo:Redo())
    assert.is_table(MM.DB:GetLayer(layerId))

    MM.Undo:Undo()
    MM.DB:CreateLayer("Other")
    local ok, reason = MM.Undo:Redo()
    assert.is_false(ok)
    assert.equals("nothing to redo", reason)
  end)

  it("undoes a character profile switch", function()
    local before = MM.DB:GetActiveProfileId()
    local profileId = MM.DB:CreateProfile("Raid")
    MM.DB:SetActiveProfile(profileId)
    assert.equals(profileId, MM.DB:GetActiveProfileId())

    assert.is_true(MM.Undo:Undo())
    assert.equals(before, MM.DB:GetActiveProfileId())
  end)

  it("leaves no step for a failed mutation", function()
    assert.is_false((MM.DB:RenameLayer("nope", "x")))
    local ok, reason = MM.Undo:Undo()
    assert.is_false(ok)
    assert.equals("nothing to undo", reason)
  end)

  it("groups a batch into one step", function()
    MM.Undo:Batch(function()
      local key = MM.DB:CreateSmartAction("Defensives")
      MM.DB:AddCandidate(key, { type = "spell", id = 498 })
      local layerId = MM.DB:CreateLayer("Healing")
      MM.DB:SetSlot(layerId, 5, { type = "action", source = "custom", id = key })
    end)

    assert.is_true(MM.Undo:Undo())
    assert.is_nil(next(MM.DB:SmartActions()))
    assert.is_false(MM.Undo:CanUndo())
  end)

  it("passes batch return values and errors through", function()
    local value = MM.Undo:Batch(function()
      return "result"
    end)
    assert.equals("result", value)

    assert.has_error(function()
      MM.Undo:Batch(function()
        error("boom", 0)
      end)
    end, "boom")
  end)

  it("caps the stack at MAX_STEPS", function()
    for index = 1, MM.Undo.MAX_STEPS + 5 do
      MM.DB:CreateLayer("Layer " .. index)
    end
    local undone = 0
    while MM.Undo:Undo() do
      undone = undone + 1
    end
    assert.equals(MM.Undo.MAX_STEPS, undone)
  end)

  it("makes a whole import one undo step", function()
    MM.DB:CreateLayer("Raid")
    local package = MM.Share:BuildPackage(MM.DB:GetActiveProfileId())
    MM.Undo:Reset()

    local layersBefore = MM.Tables.Count(MM.DB:Layers())
    assert.is_table(MM.Share:Import(package, nil, nil))
    assert.is_true(MM.Tables.Count(MM.DB:Layers()) > layersBefore)

    assert.is_true(MM.Undo:Undo())
    assert.equals(layersBefore, MM.Tables.Count(MM.DB:Layers()))
    assert.is_false(MM.Undo:CanUndo())
  end)

  describe("focus", function()
    before_each(function()
      MM.ui = MM.ui or {}
      MM.ui.state = {}
    end)

    it("jumps to the restored layer and slot", function()
      local layerId = MM.DB:CreateLayer("Healing")
      MM.DB:SetSlot(layerId, 5, { type = "spell", id = 1766 })

      MM.Undo:Undo()
      assert.equals("layers", MM.ui.state.tab)
      assert.equals(layerId, MM.DB:GetSelectedLayerId())
      assert.equals(5, MM.DB:GetSelectedSlot())
    end)

    it("jumps to the affected smart action and candidate", function()
      local key = MM.DB:CreateSmartAction("Defensives")
      MM.DB:AddCandidate(key, { type = "spell", id = 498 })
      MM.DB:AddCandidate(key, { type = "spell", id = 403876 })
      MM.DB:RemoveCandidate(key, 2)

      MM.Undo:Undo()
      assert.equals("actions", MM.ui.state.tab)
      assert.same({ source = "custom", id = key }, MM.ui.state.smartAction)
      assert.equals(2, MM.ui.state.candidate)
    end)

    it("jumps to the profiles tab for a profile switch", function()
      local profileId = MM.DB:CreateProfile("Raid")
      MM.Undo:Reset()
      MM.DB:SetActiveProfile(profileId)

      MM.Undo:Undo()
      assert.equals("profiles", MM.ui.state.tab)
    end)

    it("jumps to settings for a setting change", function()
      MM.DB:SetFallback("clear")

      MM.Undo:Undo()
      assert.equals("settings", MM.ui.state.tab)
    end)
  end)

  describe("labels", function()
    it("describes the next undo and moves the label to redo", function()
      MM.DB:CreateLayer("Healing")
      assert.equals("create layer Healing", MM.Undo:NextUndoLabel())

      MM.Undo:Undo()
      assert.is_nil(MM.Undo:NextUndoLabel())
      assert.equals("create layer Healing", MM.Undo:NextRedoLabel())
    end)

    it("resolves entity names at mutation time", function()
      local layerId = MM.DB:CreateLayer("Healing")
      MM.DB:DeleteLayer(layerId)
      assert.equals("delete layer Healing", MM.Undo:NextUndoLabel())

      stubs:setSpell(1766, { name = "Kick" })
      local key = MM.DB:CreateSmartAction("Defensives")
      MM.DB:AddCandidate(key, { type = "spell", id = 1766 })
      assert.equals("add Kick to Defensives", MM.Undo:NextUndoLabel())
      MM.DB:RemoveCandidate(key, 1)
      assert.equals("remove Kick from Defensives", MM.Undo:NextUndoLabel())
    end)

    it("labels a batch as one phrase", function()
      MM.Undo:Batch(function()
        MM.DB:CreateLayer("A")
        MM.DB:CreateLayer("B")
      end, "do two things")
      assert.equals("do two things", MM.Undo:NextUndoLabel())
    end)

    it("hands a no-op step's label to the next real mutation", function()
      MM.DB:CreateLayer("Healing")
      assert.is_false((MM.DB:RenameLayer("nope", "x")))
      MM.DB:CreateLayer("Other")
      MM.Undo:Undo()
      assert.equals("create layer Healing", MM.Undo:NextUndoLabel())
    end)
  end)

  it("is exposed on the public API", function()
    MM.DB:CreateLayer("Healing")
    assert.is_true(MM.API.undo())
    local ok, reason = MM.API.redo()
    assert.is_true(ok)
    assert.is_nil(reason)
  end)
end)
