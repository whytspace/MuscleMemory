-- A controllable fake of the WoW client API.
--
-- `Stubs.new()` returns an object whose `.globals` table is overlaid onto the
-- addon's environment by spec.helpers.addon, and whose `.world` table is the
-- mutable game state every stub reads from. Tests configure the world (known
-- spells, bag contents, action-bar slots, the cursor, …) and then assert on how
-- the addon reacts. Pickups move things onto the cursor; PlaceAction drops the
-- cursor into a slot, so a capture/apply round-trip is fully simulated.

local Stubs = {}
Stubs.__index = Stubs

local function newFrame()
  local frame = { _events = {}, _scripts = {} }
  function frame:RegisterEvent(event)
    self._events[event] = true
  end
  function frame:UnregisterEvent(event)
    self._events[event] = nil
  end
  function frame:SetScript(name, fn)
    self._scripts[name] = fn
  end
  function frame:GetScript(name)
    return self._scripts[name]
  end
  -- Any other frame method (UI layout calls etc.) is a chainable no-op.
  return setmetatable(frame, {
    __index = function()
      return function(self)
        return self
      end
    end,
  })
end

function Stubs.new()
  local world = {
    playerName = "Tester",
    realm = "TestRealm",
    class = "MAGE", -- the classFile UnitClass returns as its 2nd value
    inCombat = false,
    macroLimit = 120,

    spells = {}, -- [id] = { name, icon, known }
    items = {}, -- [id] = { name, link, icon, count, equipped }
    mounts = {}, -- [id] = { name, spellId, icon, collected }
    battlePets = {}, -- [guid] = { speciesId, customName, name, icon }
    flyouts = {}, -- 1-based list of { id, name, numSlots, isKnown, slots }
    equipmentSets = {}, -- [name] = id
    globalMacros = {}, -- 1-based list of { name, icon, body }
    charMacros = {}, -- list mapped to indices macroLimit+1 ..
    slots = {}, -- [slot] = { actionType, id, subType, text, texture }

    cursor = nil, -- { type = , id = } or nil
    printed = {}, -- captured MM:Print / print output
  }

  local self = setmetatable({ world = world }, Stubs)

  local function macroAt(index)
    if index <= #world.globalMacros then
      return world.globalMacros[index]
    end
    return world.charMacros[index - world.macroLimit]
  end

  self.globals = {
    -- Identity -------------------------------------------------------------
    UnitName = function(unit)
      return unit == "player" and world.playerName or nil
    end,
    GetRealmName = function()
      return world.realm
    end,
    UnitClass = function(unit)
      if unit ~= "player" then
        return nil
      end
      return world.class, world.class
    end,

    -- Spells ---------------------------------------------------------------
    C_Spell = {
      GetSpellInfo = function(id)
        local spell = world.spells[id]
        if not spell then
          return nil
        end
        return { name = spell.name, iconID = spell.icon }
      end,
      PickupSpell = function(id)
        world.cursor = { type = "spell", id = id }
      end,
    },
    IsPlayerSpell = function(id)
      local spell = world.spells[id]
      return spell ~= nil and spell.known == true
    end,

    -- Items ----------------------------------------------------------------
    C_Item = {
      GetItemInfo = function(id)
        local item = world.items[id]
        if not item then
          return nil
        end
        return item.name, item.link, 1, 1, 1, "", "", 1, "", item.icon
      end,
      GetItemCount = function(id)
        local item = world.items[id]
        return item and item.count or 0
      end,
      PickupItem = function(id)
        world.cursor = { type = "item", id = id }
      end,
    },
    IsEquippedItem = function(id)
      local item = world.items[id]
      return item ~= nil and item.equipped == true
    end,

    -- Mounts ---------------------------------------------------------------
    C_MountJournal = {
      GetMountInfoByID = function(id)
        local mount = world.mounts[id]
        if not mount then
          return nil
        end
        return mount.name, mount.spellId, mount.icon, 1, 1, 1, 1, 1, 1, 1, mount.collected
      end,
      Pickup = function(id)
        world.cursor = { type = "mount", id = id }
      end,
    },

    -- Battle pets ----------------------------------------------------------
    C_PetJournal = {
      GetPetInfoByPetID = function(guid)
        local pet = world.battlePets[guid]
        if not pet then
          return nil
        end
        return pet.speciesId, pet.customName, 1, 0, 100, 0, false, pet.name, pet.icon
      end,
      PickupPet = function(guid)
        world.cursor = { type = "battlepet", id = guid }
      end,
    },

    -- Flyouts --------------------------------------------------------------
    Enum = {
      SpellBookSpellBank = { Player = 0, Pet = 1 },
      SpellBookItemType = { Spell = 1, FutureSpell = 2, PetAction = 3, Flyout = 4 },
    },
    GetFlyoutInfo = function(id)
      for _, flyout in ipairs(world.flyouts) do
        if flyout.id == id then
          return flyout.name, "", flyout.numSlots, flyout.isKnown
        end
      end
      return nil
    end,
    GetFlyoutSlotInfo = function(id, slot)
      for _, flyout in ipairs(world.flyouts) do
        if flyout.id == id then
          local spellId = flyout.slots[slot]
          if spellId then
            return spellId, nil, true, nil, nil
          end
        end
      end
      return nil
    end,
    -- A single spellbook skill line holding every known flyout, enough to drive
    -- the slot scan in Flyouts.Pickup.
    C_SpellBook = {
      GetNumSpellBookSkillLines = function()
        return 1
      end,
      GetSpellBookSkillLineInfo = function(line)
        if line ~= 1 then
          return nil
        end
        return { itemIndexOffset = 0, numSpellBookItems = #world.flyouts }
      end,
      GetSpellBookItemType = function(index)
        local flyout = world.flyouts[index]
        if not flyout then
          return nil
        end
        return 4, flyout.id -- 4 == Enum.SpellBookItemType.Flyout
      end,
      PickupSpellBookItem = function(index)
        local flyout = world.flyouts[index]
        if flyout then
          world.cursor = { type = "flyout", id = flyout.id }
        end
      end,
    },

    -- Equipment sets -------------------------------------------------------
    C_EquipmentSet = {
      GetEquipmentSetID = function(name)
        return world.equipmentSets[name]
      end,
      GetEquipmentSetInfo = function(id)
        for name, setId in pairs(world.equipmentSets) do
          if setId == id then
            return name
          end
        end
        return nil
      end,
      PickupEquipmentSet = function(id)
        world.cursor = { type = "equipmentset", id = id }
      end,
    },

    -- Macros ---------------------------------------------------------------
    MAX_ACCOUNT_MACROS = world.macroLimit,
    GetNumMacros = function()
      return #world.globalMacros, #world.charMacros
    end,
    GetMacroInfo = function(index)
      local macro = macroAt(index)
      if not macro then
        return nil
      end
      return macro.name, macro.icon, macro.body
    end,
    PickupMacro = function(index)
      world.cursor = { type = "macro", id = index }
    end,

    -- Action bars ----------------------------------------------------------
    GetActionInfo = function(slot)
      local action = world.slots[slot]
      if not action then
        return nil
      end
      return action.actionType, action.id, action.subType
    end,
    GetActionText = function(slot)
      local action = world.slots[slot]
      return action and action.text or nil
    end,
    GetActionTexture = function(slot)
      local action = world.slots[slot]
      return action and action.texture or nil
    end,
    HasAction = function(slot)
      return world.slots[slot] ~= nil
    end,
    PickupAction = function(slot)
      local action = world.slots[slot]
      if action then
        world.cursor = { type = action.actionType, id = action.id }
        world.slots[slot] = nil
      end
    end,
    PlaceAction = function(slot)
      local cursor = world.cursor
      if cursor then
        world.slots[slot] = { actionType = cursor.type, id = cursor.id }
      end
    end,

    -- Cursor ---------------------------------------------------------------
    GetCursorInfo = function()
      local cursor = world.cursor
      if not cursor then
        return nil
      end
      return cursor.type, cursor.id
    end,
    ClearCursor = function()
      world.cursor = nil
    end,

    -- Misc -----------------------------------------------------------------
    InCombatLockdown = function()
      return world.inCombat
    end,
    CreateFrame = function()
      return newFrame()
    end,
    UIParent = newFrame(),
    SlashCmdList = {},
    StaticPopupDialogs = {},
    StaticPopup_Show = function() end,
    time = function()
      return 0
    end,
    print = function(message)
      world.printed[#world.printed + 1] = message
    end,
  }

  return self
end

-- Configuration helpers -----------------------------------------------------

function Stubs:setSpell(id, opts)
  opts = opts or {}
  self.world.spells[id] = {
    name = opts.name or ("Spell " .. tostring(id)),
    icon = opts.icon or (1000 + id),
    known = opts.known == true,
  }
  return self
end

function Stubs:setItem(id, opts)
  opts = opts or {}
  self.world.items[id] = {
    name = opts.name or ("Item " .. tostring(id)),
    link = opts.link or ("|item:" .. tostring(id) .. "|"),
    icon = opts.icon or (2000 + id),
    count = opts.count or 0,
    equipped = opts.equipped == true,
  }
  return self
end

function Stubs:setMount(id, opts)
  opts = opts or {}
  self.world.mounts[id] = {
    name = opts.name or ("Mount " .. tostring(id)),
    spellId = opts.spellId or (3000 + id),
    icon = opts.icon or (4000 + id),
    collected = opts.collected ~= false,
  }
  return self
end

function Stubs:setBattlePet(guid, opts)
  opts = opts or {}
  self.world.battlePets[guid] = {
    speciesId = opts.speciesId or 100,
    customName = opts.customName,
    name = opts.name or ("Pet " .. tostring(guid)),
    icon = opts.icon or 5000,
  }
  return self
end

function Stubs:setFlyout(id, opts)
  opts = opts or {}
  local list = self.world.flyouts
  list[#list + 1] = {
    id = id,
    name = opts.name or ("Flyout " .. tostring(id)),
    slots = opts.slots or {},
    numSlots = opts.numSlots or (opts.slots and #opts.slots) or 0,
    isKnown = opts.known ~= false,
  }
  return self
end

function Stubs:setEquipmentSet(name, id)
  self.world.equipmentSets[name] = id or (#self.world.equipmentSets + 100)
  return self
end

function Stubs:addGlobalMacro(macro)
  local list = self.world.globalMacros
  list[#list + 1] = macro
  return #list
end

function Stubs:addCharacterMacro(macro)
  local list = self.world.charMacros
  list[#list + 1] = macro
  return self.world.macroLimit + #list
end

function Stubs:setSlot(slot, action)
  self.world.slots[slot] = action
  return self
end

function Stubs:setCursor(cursor)
  self.world.cursor = cursor
  return self
end

return Stubs
