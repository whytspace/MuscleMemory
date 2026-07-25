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
    specId = nil, -- GetSpecializationInfo's id for the active spec
    role = "DAMAGER",
    level = 70,
    faction = "Alliance",
    race = "Gnome", -- the raceFile UnitRace returns as its 2nd value
    inCombat = false,
    macroLimit = 120,
    charMacroLimit = 30,

    spells = {}, -- [id] = { name, icon, known }
    items = {}, -- [id] = { name, link, icon, count, equipped }
    mounts = {}, -- [id] = { name, spellId, icon, collected }
    battlePets = {}, -- [guid] = { speciesId, customName, name, icon }
    flyouts = {}, -- 1-based list of { id, name, numSlots, isKnown, slots }
    equipmentSets = {}, -- [name] = id
    outfits = {}, -- [id] = { name, icon }
    globalMacros = {}, -- 1-based list of { name, icon, body }
    charMacros = {}, -- list mapped to indices macroLimit+1 ..
    slots = {}, -- [slot] = { actionType, id, subType, text, texture }
    bindings = {}, -- [bindingAction] = key string, e.g. ACTIONBUTTON1 = "SHIFT-3"

    cursor = nil, -- { type = , id = } or nil
    printed = {}, -- captured MM:Print / print output
    timers = {}, -- pending C_Timer.After callbacks, fired by Stubs:flushTimers

    assistedCombat = { spell = nil, available = false }, -- Single Button Assistant
  }

  local self = setmetatable({ world = world }, Stubs)

  local function macroAt(index)
    if index <= #world.globalMacros then
      return world.globalMacros[index]
    end
    return world.charMacros[index - world.macroLimit]
  end

  self.globals = {
    -- WoW's global string aliases, used by the vendored libraries (LibStub).
    strmatch = string.match,

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
    UnitRace = function(unit)
      if unit ~= "player" then
        return nil
      end
      return world.race, world.race
    end,
    UnitLevel = function(unit)
      return unit == "player" and world.level or nil
    end,
    UnitFactionGroup = function(unit)
      return unit == "player" and world.faction or nil
    end,
    GetSpecialization = function()
      return world.specId and 1 or nil
    end,
    GetSpecializationInfo = function()
      return world.specId
    end,
    GetSpecializationRole = function()
      return world.role
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
    -- Real WoW maps an override id to its base spell and returns other ids
    -- unchanged (verified in 12.0: FindBaseSpellByID(272678) -> 272651).
    FindBaseSpellByID = function(id)
      local spell = world.spells[id]
      return (spell and spell.baseSpellId) or id
    end,
    C_ActionBar = {
      -- Real WoW returns nil (not an empty table) when the spell is on no bar,
      -- and for spells it never indexes such as the Single Button Assistant. An
      -- assistant slot, however, IS indexed under the ability it currently
      -- recommends (the id GetActionInfo reports for it).
      FindSpellActionButtons = function(spellId)
        if spellId == world.assistedCombat.spell then
          return nil
        end
        local slots = {}
        for slot, action in pairs(world.slots) do
          if action.actionType == "spell" and (action.id == spellId or action.baseSpellId == spellId) then
            slots[#slots + 1] = slot
          end
        end
        if #slots == 0 then
          return nil
        end
        table.sort(slots)
        return slots
      end,
      IsAssistedCombatAction = function(slot)
        local action = world.slots[slot]
        return action ~= nil and action.assistedCombat == true
      end,
    },
    C_AssistedCombat = {
      GetActionSpell = function()
        return world.assistedCombat.spell
      end,
      IsAvailable = function()
        return world.assistedCombat.available == true
      end,
    },

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
      IsUsableItem = function(id)
        local item = world.items[id]
        if not item then
          return nil
        end
        return item.usable
      end,
      PickupItem = function(id)
        world.cursor = { type = "item", id = id }
      end,
    },
    -- Structured tooltip data. An unmet requirement (item.requirement) surfaces as
    -- a red left-colored line, mirroring how the client flags "Requires Engineering"
    -- or a level cap the player fails.
    TooltipUtil = {
      SurfaceArgs = function() end,
    },
    C_TooltipInfo = {
      GetItemByID = function(id)
        local item = world.items[id]
        if not item then
          return nil
        end
        local lines = { { leftText = item.name } }
        if item.requirement then
          lines[#lines + 1] = {
            leftText = item.requirement,
            leftColor = {
              GetRGB = function()
                return 1, 0.125, 0.125
              end,
            },
          }
        end
        return { lines = lines }
      end,
    },
    IsEquippedItem = function(id)
      local item = world.items[id]
      return item ~= nil and item.equipped == true
    end,
    PlayerHasToy = function(id)
      local item = world.items[id]
      return item ~= nil and item.isToy == true
    end,
    C_ToyBox = {
      -- Recognises a toy id whether or not it's learned (isToy = learned).
      GetToyInfo = function(id)
        local item = world.items[id]
        if item and item.toy then
          return id
        end
        return nil
      end,
      IsToyUsable = function(id)
        local item = world.items[id]
        return item ~= nil and item.isToy == true and item.toyUsable ~= false
      end,
      PickupToyBoxItem = function(id)
        world.cursor = { type = "item", id = id, fromToyBox = true }
      end,
    },

    -- Mounts ---------------------------------------------------------------
    C_MountJournal = {
      GetMountInfoByID = function(id)
        local mount = world.mounts[id]
        if not mount then
          return nil
        end
        return mount.name, mount.spellId, mount.icon, 1, 1, 1, 1, 1, 1, 1, mount.collected
      end,
      Pickup = function(index)
        -- Index 0 is the "Summon Random Favorite Mount" button, which the client
        -- reports under the sentinel mount id 268435455.
        world.cursor = { type = "mount", id = index == 0 and 268435455 or index }
      end,
      -- Maps a mount's summon spellId back to its mountID, the inverse of
      -- GetMountInfoByID's spellId. A companion/MOUNT slot reports that summon
      -- spellId as its action id, so this is how GetInfo recovers the mount.
      GetMountFromSpell = function(spellId)
        for mountId, mount in pairs(world.mounts) do
          if mount.spellId == spellId then
            return mountId
          end
        end
        return nil
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

    -- Transmog outfits -----------------------------------------------------
    C_TransmogOutfitInfo = {
      GetOutfitInfo = function(id)
        local outfit = world.outfits[id]
        return outfit and { outfitID = id, name = outfit.name, icon = outfit.icon }
      end,
      PickupOutfit = function(id)
        world.cursor = { type = "outfit", id = id }
      end,
    },

    -- Macros ---------------------------------------------------------------
    MAX_ACCOUNT_MACROS = world.macroLimit,
    MAX_CHARACTER_MACROS = world.charMacroLimit,
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
    CreateMacro = function(name, icon, body, perCharacter)
      local list = perCharacter and world.charMacros or world.globalMacros
      list[#list + 1] = { name = name, icon = icon, body = body }
      if perCharacter then
        return world.macroLimit + #list
      end
      return #list
    end,
    EditMacro = function(index, name, icon, body)
      local macro = macroAt(index)
      if macro then
        macro.name = name or macro.name
        macro.icon = icon or macro.icon
        macro.body = body or macro.body
      end
      return index
    end,
    DeleteMacro = function(index)
      if index <= #world.globalMacros then
        table.remove(world.globalMacros, index)
      else
        table.remove(world.charMacros, index - world.macroLimit)
      end
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
      if not cursor then
        return
      end
      -- Observed in 12.0: dropping the ability the assistant currently
      -- recommends onto the assistant's own slot is a no-op — the client thinks
      -- the spell is already there and the assistant stays.
      local occupant = world.slots[slot]
      if occupant and occupant.assistedCombat and cursor.type == "spell" and cursor.id == occupant.id then
        return
      end
      world.slots[slot] = { actionType = cursor.type, id = cursor.id }
    end,

    -- Key bindings ---------------------------------------------------------
    GetBindingKey = function(action)
      return world.bindings[action]
    end,
    -- Real WoW only abbreviates the modifiers here; mouse buttons come back as
    -- their full name ("Middle Mouse"), which is why Actions abbreviates the key
    -- tokens itself. The fake returns each token verbatim — all the fallback path
    -- (letters, F-keys) needs.
    GetBindingText = function(key)
      return key or ""
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
    -- Queues the callback instead of running it; Stubs:flushTimers fires the
    -- burst so tests can drive the trailing-debounce deterministically.
    C_Timer = {
      After = function(delay, fn)
        world.timers[#world.timers + 1] = { delay = delay, fn = fn }
      end,
    },
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

-- Fire every callback queued through C_Timer.After, in schedule order, then
-- clear the queue. Mirrors the trailing timers landing once an event burst
-- settles; a callback that schedules another timer lands in the fresh queue.
function Stubs:flushTimers()
  local pending = self.world.timers
  self.world.timers = {}
  for _, timer in ipairs(pending) do
    timer.fn()
  end
  return self
end

function Stubs:setSpell(id, opts)
  opts = opts or {}
  self.world.spells[id] = {
    name = opts.name or ("Spell " .. tostring(id)),
    icon = opts.icon or (1000 + id),
    known = opts.known == true,
    baseSpellId = opts.baseSpellId,
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
    isToy = opts.isToy == true,
    -- A toy id GetToyInfo recognises; a learned toy (isToy) is always one.
    toy = opts.toy == true or opts.isToy == true,
    toyUsable = opts.toyUsable ~= false,
    usable = opts.usable ~= false,
    requirement = opts.requirement, -- e.g. "Requires Engineering"; shows as a red tooltip line
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

function Stubs:setOutfit(id, outfit)
  self.world.outfits[id] = outfit
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

-- Configure the Single Button Assistant: its stable action spell id and whether
-- the assisted-combat feature is currently available.
function Stubs:setAssistedCombat(opts)
  opts = opts or {}
  self.world.assistedCombat = {
    spell = opts.spell,
    available = opts.available ~= false,
  }
  return self
end

function Stubs:setBinding(action, key)
  self.world.bindings[action] = key
  return self
end

function Stubs:setCursor(cursor)
  self.world.cursor = cursor
  return self
end

function Stubs:setCharacter(fields)
  for key, value in pairs(fields) do
    self.world[key] = value
  end
  return self
end

return Stubs
