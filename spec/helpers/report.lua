-- Replays a Muscle Memory debug report ("!MMDBG:1!" string) inside the test
-- harness: decodes it, hydrates a wow_stubs world from the captured state, and
-- loads the addon against that world with the captured profile installed — so
-- a user's in-game situation runs offline:
--
--   local report = require("spec.helpers.report")
--   local MM = report.load(io.open("bug.txt"):read("*a"))
--   assert.is_true(MM.Applier:HasUnappliedChanges())
--
-- Faithfulness rule: probes the report captured verbatim (the IsKnown variants,
-- FindSpellActionButtons) are answered straight from the report, never derived
-- from the stub world — reproducing client quirks is the whole point.

local Stubs = require("spec.helpers.wow_stubs")
local addon = require("spec.helpers.addon")

local M = {}

-- Decode `text` through the addon's own vendored libraries; a throwaway addon
-- instance is the cheapest way to have them loaded.
function M.decode(text)
  local MM = addon.fresh()
  return MM.Diagnostics:Decode(text)
end

-- A Stubs instance whose world mirrors the report's captured state.
function M.stubs(report)
  local stubs = Stubs.new()
  local world = stubs.world

  local character = report.character or {}
  world.class = character.class or world.class
  world.race = character.race or world.race
  world.faction = character.faction or world.faction
  world.level = character.level or world.level
  world.specId = character.specId
  world.role = character.role

  for slot, entry in pairs(report.bars or {}) do
    if entry.type then
      world.slots[slot] = {
        actionType = entry.type,
        id = entry.id,
        subType = entry.subType,
        text = entry.text,
        texture = entry.texture,
        assistedCombat = entry.assisted,
      }
    end
  end

  for id, spell in pairs(report.spells or {}) do
    world.spells[id] = {
      name = spell.name,
      icon = spell.icon,
      known = spell.known == true,
      baseSpellId = spell.base ~= id and spell.base or nil,
    }
  end

  for id, item in pairs(report.items or {}) do
    world.items[id] = {
      name = item.name,
      icon = item.icon,
      link = "|item:" .. tostring(id) .. "|",
      count = item.count or 0,
      equipped = item.equipped == true,
      isToy = item.toyKnown == true,
      toy = item.toy == true,
      toyUsable = item.toyUsable ~= false,
      usable = item.usable ~= false,
      -- Items.IsUsable reads unusability from a red tooltip line for non-toys;
      -- plant one so the captured verdict reproduces.
      requirement = (item.usable == false and item.toy ~= true) and "Requires higher level" or nil,
    }
  end

  for id, mount in pairs(report.mounts or {}) do
    world.mounts[id] = {
      name = mount.name,
      spellId = mount.spellId,
      icon = mount.icon,
      collected = mount.collected == true,
    }
  end

  for guid, pet in pairs(report.battlePets or {}) do
    world.battlePets[guid] = { speciesId = 0, name = pet.name, icon = pet.icon }
  end

  for id, flyout in pairs(report.flyouts or {}) do
    world.flyouts[#world.flyouts + 1] = {
      id = id,
      name = flyout.name,
      numSlots = flyout.numSlots,
      isKnown = flyout.known == true,
      slots = flyout.slots or {},
    }
  end

  -- `false` marks a set the report looked up but the client didn't have.
  for name, setId in pairs(report.equipmentSets or {}) do
    if setId then
      world.equipmentSets[name] = setId
    end
  end

  for id, outfit in pairs(report.outfits or {}) do
    world.outfits[id] = { name = outfit.name, icon = outfit.icon }
  end

  local macros = report.macros or {}
  world.macroLimit = macros.accountLimit or world.macroLimit
  world.charMacroLimit = macros.characterLimit or world.charMacroLimit
  stubs.globals.MAX_ACCOUNT_MACROS = world.macroLimit
  stubs.globals.MAX_CHARACTER_MACROS = world.charMacroLimit
  -- Client macro indices are contiguous per scope, so index math is safe.
  for _, macro in ipairs(macros.list or {}) do
    local entry = { name = macro.name, icon = macro.icon, selectedIcon = macro.selectedIcon, body = macro.body }
    if macro.scope == "global" then
      world.globalMacros[macro.index] = entry
    else
      world.charMacros[macro.index - world.macroLimit] = entry
    end
  end

  local assisted = report.assistedCombat or {}
  world.assistedCombat = { spell = assisted.spell, available = assisted.available == true }

  -- The faithful oracles: answer exactly what the client answered at capture
  -- time, quirks included (a pet spell that IsPlayerSpell denies, a placed
  -- spell FindSpellActionButtons doesn't index, ...).
  local spells = report.spells or {}
  stubs.globals.IsPlayerSpell = function(id)
    local spell = spells[id]
    return spell ~= nil and spell.knownPlayer == true
  end
  stubs.globals.IsSpellKnown = function(id, pet)
    local spell = spells[id]
    if not spell then
      return false
    end
    if pet then
      return spell.knownPet == true
    end
    return spell.knownSpell == true
  end
  stubs.globals.C_SpellBook.IsSpellKnown = function(id)
    local spell = spells[id]
    return spell ~= nil and spell.knownBook == true
  end
  stubs.globals.C_ActionBar.FindSpellActionButtons = function(id)
    local spell = spells[id]
    if not spell or not spell.buttons then
      return nil
    end
    local copy = {}
    for index, slot in ipairs(spell.buttons) do
      copy[index] = slot
    end
    return copy
  end

  return stubs
end

-- Decode (if needed), hydrate, load the addon, and install the captured
-- profile and macro registry. Returns (MM, stubs, env, report).
function M.load(textOrReport)
  local report = textOrReport
  if type(report) ~= "table" then
    report = assert(M.decode(textOrReport))
  end

  local stubs = M.stubs(report)
  local MM, _, env = addon.load({ stubs = stubs })
  MM.DB:Initialize()

  local root = MM.DB:GetRoot()
  root.profiles = { [report.profile.id] = MM.Tables.DeepCopy(report.profile.data) }
  root.profile = report.profile.id
  root.debug = report.settings and report.settings.debug or false
  MM.DB:GetCharacterState().macroRegistry = MM.Tables.DeepCopy(report.macroRegistry or {})

  return MM, stubs, env, report
end

return M
