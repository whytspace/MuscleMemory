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
