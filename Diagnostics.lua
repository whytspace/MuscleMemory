local ADDON_NAME, MM = ...

-- Debug reports: pack the *state* the active profile is checked against — the
-- live action bars, the client's answers for every referenced spell, item and
-- macro, the character — into one copyable string ("!MMDBG:1!" prefix), next to
-- a copy of the profile itself. The spec harness hydrates its WoW fake from a
-- decoded report (spec/helpers/report.lua), so a user's in-game situation can
-- be replayed offline and turned into a regression test.
--
-- The report records answers, not derivations: for each id it stores what the
-- live client actually returned (IsPlayerSpell, FindSpellActionButtons, …), so
-- a replay reproduces client quirks a synthetic fake would never model.

local Diagnostics = {}
MM.Diagnostics = Diagnostics
MM:RegisterModule("Diagnostics", Diagnostics)

Diagnostics.FORMAT_VERSION = 1
local PREFIX_PATTERN = "^!MMDBG:(%d+)!"

-- Capture -----------------------------------------------------------------

-- Spells record every probe Spells.IsKnown consults separately (a pet-granted
-- spell answers false to IsPlayerSpell but true to IsSpellKnown(id, true)),
-- plus the FindSpellActionButtons verdict that slot matching relies on.
local function captureSpell(report, id)
  if type(id) ~= "number" or report.spells[id] then
    return
  end

  local info = MM.Spells.GetInfo(id)
  local knownPet = false
  if IsSpellKnown then
    local ok, known = pcall(IsSpellKnown, id, true)
    knownPet = ok and known == true
  end

  local buttons
  if C_ActionBar and C_ActionBar.FindSpellActionButtons then
    local found = C_ActionBar.FindSpellActionButtons(id)
    if type(found) == "table" then
      buttons = {}
      for index, slot in ipairs(found) do
        buttons[index] = slot
      end
    end
  end

  report.spells[id] = {
    name = info and info.name,
    icon = info and info.icon,
    base = MM.Spells.GetBaseSpell(id),
    known = MM.Spells.IsKnown(id),
    knownPlayer = IsPlayerSpell ~= nil and IsPlayerSpell(id) == true,
    knownBook = C_SpellBook ~= nil and C_SpellBook.IsSpellKnown ~= nil and C_SpellBook.IsSpellKnown(id) == true,
    knownSpell = IsSpellKnown ~= nil and IsSpellKnown(id) == true,
    knownPet = knownPet,
    buttons = buttons,
  }

  -- Resolution normalises to the base spell, so capture it too.
  local base = report.spells[id].base
  if base ~= id then
    captureSpell(report, base)
  end
end

local function captureItem(report, id)
  if type(id) ~= "number" or report.items[id] then
    return
  end

  local info = MM.Items.GetInfo(id)
  report.items[id] = {
    name = info and info.name,
    icon = info and info.icon,
    count = MM.Items.GetCount(id),
    equipped = MM.Items.IsEquipped(id),
    -- toy = the Toy Box recognises the id at all; toyKnown = actually learned.
    toy = C_ToyBox ~= nil and C_ToyBox.GetToyInfo ~= nil and C_ToyBox.GetToyInfo(id) ~= nil,
    toyKnown = MM.Items.IsToy(id),
    toyUsable = C_ToyBox ~= nil and C_ToyBox.IsToyUsable ~= nil and C_ToyBox.IsToyUsable(id) ~= false,
    usable = MM.Items.IsUsable(id),
    owned = MM.Items.IsOwned(id),
  }
end

-- Keyed by the journal id GetInfo normalises to, never the queried id: a bar
-- references a mount by its summon spell, and a replay journal holding that
-- spell id as a first-class entry would skip the spell->mount normalisation
-- the real client performs, making the mount mismatch its own slot.
local function captureMount(report, id)
  if type(id) ~= "number" then
    return
  end

  local info = MM.Mounts.GetInfo(id)
  if not info or report.mounts[info.id] then
    return
  end
  report.mounts[info.id] = {
    name = info.name,
    spellId = info.spellId,
    icon = info.icon,
    collected = info.isCollected ~= false,
  }
  captureSpell(report, info.spellId)
end

local function captureBattlePet(report, guid)
  if guid == nil or report.battlePets[tostring(guid)] then
    return
  end

  local info = MM.BattlePets.GetInfo(guid)
  if info then
    -- GUID keys stringified: LibSerialize round-trips them, but string keys
    -- keep the report shape uniform for hand inspection.
    report.battlePets[tostring(guid)] = { name = info.name, icon = info.icon }
  end
end

local function captureFlyout(report, id)
  if type(id) ~= "number" or report.flyouts[id] then
    return
  end

  local info = MM.Flyouts.GetInfo(id)
  if not info then
    return
  end
  local slots = {}
  if GetFlyoutSlotInfo then
    for index = 1, info.numSlots or 0 do
      local spellId = GetFlyoutSlotInfo(id, index)
      slots[index] = spellId
    end
  end
  report.flyouts[id] = {
    name = info.name,
    numSlots = info.numSlots,
    known = MM.Flyouts.IsKnown(id),
    slots = slots,
  }
end

local function captureEquipmentSet(report, name)
  if type(name) ~= "string" or report.equipmentSets[name] ~= nil then
    return
  end
  report.equipmentSets[name] = MM.EquipmentSets.GetId(name) or false
end

local function captureOutfit(report, id)
  if type(id) ~= "number" or report.outfits[id] then
    return
  end
  local info = MM.Outfits.GetInfo(id)
  if info then
    report.outfits[id] = { name = info.name, icon = info.icon }
  end
end

-- One assignment (a layer slot or a smart-action candidate) contributes the
-- ids it references; smart-action references contribute nothing themselves —
-- the candidate walk below covers every action's candidates wholesale.
local function captureAssignment(report, assignment)
  if type(assignment) ~= "table" then
    return
  end

  local kind = assignment.type
  if kind == "spell" then
    captureSpell(report, assignment.id)
  elseif kind == "item" then
    captureItem(report, assignment.id)
  elseif kind == "mount" then
    captureMount(report, assignment.id)
  elseif kind == "battlepet" then
    captureBattlePet(report, assignment.id)
  elseif kind == "flyout" then
    captureFlyout(report, assignment.id)
  elseif kind == "equipmentset" then
    captureEquipmentSet(report, assignment.name)
  elseif kind == "outfit" then
    captureOutfit(report, assignment.id)
  end

  if assignment.requiresKnownSpell then
    captureSpell(report, assignment.requiresKnownSpell)
  end
  if assignment.requiresItem then
    captureItem(report, assignment.requiresItem)
  end
end

local function captureSmartAction(report, smartAction)
  for _, candidate in ipairs((smartAction or {}).candidates or {}) do
    captureAssignment(report, candidate)
  end
end

-- The live bars: what each slot holds is the "from" side of every change the
-- applier reports, and macro/mount matching reads text and texture too.
local function captureBars(report)
  for slot = 1, MM.MAX_ACTION_SLOT do
    local info = MM.Actions.GetInfo(slot)
    local has = HasAction ~= nil and HasAction(slot) == true
    if has or (info and info.actionType) then
      report.bars[slot] = {
        has = has,
        type = info and info.actionType,
        id = info and info.id,
        subType = info and info.subType,
        text = GetActionText and GetActionText(slot) or nil,
        texture = GetActionTexture and GetActionTexture(slot) or nil,
        assisted = MM.Spells.IsAssistedCombatSlot(slot) or nil,
      }
    end
  end
end

-- Whatever sits on the bars is match material: capture those ids too, so the
-- replay can answer "is the target already in this slot?" exactly like the
-- client did. A mount can land as its summon spell, so both forms are covered.
local function captureBarReferences(report)
  for _, entry in pairs(report.bars) do
    local kind = entry.type
    if kind == "spell" then
      captureSpell(report, entry.id)
    elseif kind == "item" then
      captureItem(report, entry.id)
    elseif kind == "flyout" then
      captureFlyout(report, entry.id)
    elseif kind == "summonpet" or kind == "battlepet" then
      captureBattlePet(report, entry.id)
    elseif kind == "outfit" then
      captureOutfit(report, entry.id)
    elseif kind == "equipmentset" and type(entry.id) == "string" then
      captureEquipmentSet(report, entry.id)
    elseif kind == "mount" or kind == "summonmount" or (kind == "companion" and entry.subType == "MOUNT") then
      captureMount(report, entry.id)
      if C_MountJournal and C_MountJournal.GetMountFromSpell then
        captureMount(report, C_MountJournal.GetMountFromSpell(entry.id))
      end
    end
  end
end

local function captureMacros(report)
  local list = {}
  for _, macro in ipairs(MM.Macros.Scan()) do
    list[#list + 1] = {
      index = macro.index,
      scope = macro.scope,
      name = macro.name,
      icon = macro.icon,
      selectedIcon = C_Macro and C_Macro.GetSelectedMacroIcon and C_Macro.GetSelectedMacroIcon(macro.index) or nil,
      body = macro.body,
    }
  end
  report.macros = {
    accountLimit = MAX_ACCOUNT_MACROS or 120,
    characterLimit = MAX_CHARACTER_MACROS or 30,
    list = list,
  }
end

-- The same character facts Conditions.Match consults.
local function captureCharacter(report)
  local specIndex = GetSpecialization and GetSpecialization() or nil
  report.character = {
    class = select(2, UnitClass("player")),
    race = select(2, UnitRace("player")),
    faction = UnitFactionGroup and UnitFactionGroup("player") or nil,
    level = UnitLevel and UnitLevel("player") or nil,
    specId = specIndex and GetSpecializationInfo and GetSpecializationInfo(specIndex) or nil,
    role = specIndex and GetSpecializationRole and GetSpecializationRole(specIndex) or nil,
  }
end

function Diagnostics:BuildReport()
  local profileId = MM.DB:GetActiveProfileId()
  local profile = MM.DB:GetProfile(profileId)
  if not profile then
    return nil, "no active profile"
  end

  local report = {
    format = Diagnostics.FORMAT_VERSION,
    meta = {
      addon = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version") or nil,
      client = GetBuildInfo and { GetBuildInfo() } or nil,
      locale = GetLocale and GetLocale() or nil,
      date = date and date("%Y-%m-%d %H:%M:%S") or nil,
      schema = MM.SCHEMA_VERSION,
    },
    settings = {
      profileId = profileId,
      fallback = MM.DB:GetFallback(),
      response = MM.DB:GetResponse(),
      debug = MM.DB:GetRoot().debug or false,
    },
    bars = {},
    spells = {},
    items = {},
    mounts = {},
    battlePets = {},
    flyouts = {},
    equipmentSets = {},
    outfits = {},
    assistedCombat = {
      spell = MM.Spells.GetAssistedCombatActionSpell(),
      available = MM.Spells.IsAssistedCombatAvailable(),
    },
    -- The raw profile, not a sharing package: replays need the original layer
    -- ids so the macro registry's layer keys still line up.
    profile = { id = profileId, data = MM.Tables.DeepCopy(profile) },
    macroRegistry = MM.Tables.DeepCopy(MM.DB:GetMacroRegistry()),
  }

  captureCharacter(report)
  captureBars(report)
  captureBarReferences(report)
  captureMacros(report)

  for _, layer in pairs(profile.layers or {}) do
    for _, assignment in pairs(layer.slots or {}) do
      captureAssignment(report, assignment)
    end
  end
  for _, smartAction in pairs(MM.DB:SmartActions(profileId)) do
    captureSmartAction(report, smartAction)
  end
  for _, smartAction in pairs(MM.PredefinedSmartActions or {}) do
    captureSmartAction(report, smartAction)
  end

  return report
end

-- Encode / decode -----------------------------------------------------------

function Diagnostics:Encode(report)
  local serializer, deflate = MM.Share.Libs()
  if not serializer then
    return nil, "serialization libraries are not loaded"
  end

  local serialized = serializer:SerializeEx({ stable = true }, report)
  local compressed = deflate:CompressDeflate(serialized, { level = 9 })
  return "!MMDBG:" .. Diagnostics.FORMAT_VERSION .. "!" .. deflate:EncodeForPrint(compressed)
end

-- One report string, ready to copy. The public entry point behind the About
-- tab's button and MuscleMemory.debug.report().
function Diagnostics:Report()
  local report, reason = self:BuildReport()
  if not report then
    return nil, reason
  end
  return self:Encode(report)
end

function Diagnostics:Decode(text)
  local serializer, deflate = MM.Share.Libs()
  if not serializer then
    return nil, "serialization libraries are not loaded"
  end

  text = string.gsub(text or "", "%s+", "")
  local version = string.match(text, PREFIX_PATTERN)
  if not version then
    return nil, "not a Muscle Memory debug report"
  end
  if tonumber(version) > Diagnostics.FORMAT_VERSION then
    return nil, "this report needs a newer Muscle Memory version"
  end

  local body = string.sub(text, #("!MMDBG:" .. version .. "!") + 1)
  local compressed = deflate:DecodeForPrint(body)
  if not compressed then
    return nil, "the report is damaged or incomplete"
  end
  local serialized = deflate:DecompressDeflate(compressed)
  if not serialized then
    return nil, "the report is damaged or incomplete"
  end
  local ok, report = serializer:Deserialize(serialized)
  if not ok or type(report) ~= "table" then
    return nil, "the report is damaged or incomplete"
  end
  return report
end
