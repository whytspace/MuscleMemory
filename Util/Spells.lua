local ADDON_NAME, MM = ...

local Spells = {}
MM.Spells = Spells

function Spells.GetInfo(spellId)
  if not spellId then
    return nil
  end

  if C_Spell and C_Spell.GetSpellInfo then
    local info = C_Spell.GetSpellInfo(spellId)
    if info then
      return {
        name = info.name,
        icon = info.iconID,
        spellId = spellId,
      }
    end
  end

  if GetSpellInfo then
    local name, _, icon = GetSpellInfo(spellId)
    if name then
      return {
        name = name,
        icon = icon,
        spellId = spellId,
      }
    end
  end

  return nil
end

-- Spec/talent overrides (e.g. Chrono Flames replacing Living Flame) drag from
-- the spellbook with the override id, but only the base spell is "known" and
-- placeable. Map an override back to its base; other ids return unchanged.
function Spells.GetBaseSpell(spellId)
  if not spellId then
    return nil
  end
  if FindBaseSpellByID then
    local ok, base = pcall(FindBaseSpellByID, spellId)
    if ok and type(base) == "number" and base > 0 then
      return base
    end
  end
  return spellId
end

function Spells.IsKnown(spellId)
  if not spellId then
    return false
  end

  if IsPlayerSpell and IsPlayerSpell(spellId) then
    return true
  end

  if C_SpellBook and C_SpellBook.IsSpellKnown and C_SpellBook.IsSpellKnown(spellId) then
    return true
  end

  if IsSpellKnown and IsSpellKnown(spellId) then
    return true
  end

  if IsSpellKnown then
    local ok, known = pcall(IsSpellKnown, spellId, true)
    if ok and known then
      return true
    end
  end

  local base = Spells.GetBaseSpell(spellId)
  if base ~= spellId then
    return Spells.IsKnown(base)
  end

  return false
end

function Spells.IsOnActionSlot(spellId, slot)
  if not spellId or not slot then
    return false
  end

  if not (C_ActionBar and C_ActionBar.FindSpellActionButtons) then
    return false
  end

  -- Returns nil (not an empty table) when the spell isn't on any bar, and for
  -- spells it doesn't index at all (e.g. the Single Button Assistant action).
  local slots = C_ActionBar.FindSpellActionButtons(spellId)
  if type(slots) ~= "table" then
    return false
  end

  for _, actionSlot in ipairs(slots) do
    if actionSlot == slot then
      return true
    end
  end

  return false
end

-- The Single Button Assistant ("Assisted Combat") is a real, castable spell
-- whose id stays stable while its icon/tooltip track the recommended ability.
-- The bar doesn't expose it through FindSpellActionButtons and IsPlayerSpell
-- doesn't report it, so it needs the dedicated C_AssistedCombat queries.
function Spells.GetAssistedCombatActionSpell()
  if C_AssistedCombat and C_AssistedCombat.GetActionSpell then
    return C_AssistedCombat.GetActionSpell()
  end
  return nil
end

function Spells.IsAssistedCombatActionSpell(spellId)
  if not spellId then
    return false
  end
  return Spells.GetAssistedCombatActionSpell() == spellId
end

function Spells.IsAssistedCombatAvailable()
  if C_AssistedCombat and C_AssistedCombat.IsAvailable then
    return C_AssistedCombat.IsAvailable() == true
  end
  return false
end

function Spells.IsAssistedCombatSlot(slot)
  if not slot then
    return false
  end
  if C_ActionBar and C_ActionBar.IsAssistedCombatAction then
    return C_ActionBar.IsAssistedCombatAction(slot) == true
  end
  return false
end

function Spells.Pickup(spellId)
  if C_Spell and C_Spell.PickupSpell then
    C_Spell.PickupSpell(spellId)
    return true
  end

  if PickupSpell then
    PickupSpell(spellId)
    return true
  end

  return false
end
