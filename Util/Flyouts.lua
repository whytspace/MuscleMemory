local ADDON_NAME, MM = ...

local Flyouts = {}
MM.Flyouts = Flyouts

-- Modern retail enums, with the documented literal values as a fallback so the
-- module still works if the global table isn't populated (e.g. under test).
local PLAYER_BANK = (Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or 0
local FLYOUT_TYPE = (Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.Flyout) or 4

-- GetFlyoutInfo carries no icon, so borrow the icon of the first slot whose
-- spell we can read — mirrors how the bar button shows a representative spell.
local function flyoutIcon(flyoutId, numSlots)
  if not GetFlyoutSlotInfo then
    return nil
  end

  for slot = 1, numSlots or 0 do
    local spellId = GetFlyoutSlotInfo(flyoutId, slot)
    if spellId then
      local info = MM.Spells.GetInfo(spellId)
      if info and info.icon then
        return info.icon
      end
    end
  end

  return nil
end

function Flyouts.GetInfo(flyoutId)
  if not flyoutId or not GetFlyoutInfo then
    return nil
  end

  local name, _, numSlots, isKnown = GetFlyoutInfo(flyoutId)
  if not name then
    return nil
  end

  return {
    id = flyoutId,
    name = name,
    icon = flyoutIcon(flyoutId, numSlots),
    numSlots = numSlots,
    isKnown = isKnown,
  }
end

function Flyouts.IsKnown(flyoutId)
  local info = Flyouts.GetInfo(flyoutId)
  return info ~= nil and info.isKnown ~= false
end

-- Flyouts have no pickup-by-id API, so find the spellbook slot that holds this
-- flyout and pick it up the way the player would from the spellbook.
function Flyouts.Pickup(flyoutId)
  if not flyoutId or not C_SpellBook or not C_SpellBook.GetNumSpellBookSkillLines then
    return false
  end

  local lineCount = C_SpellBook.GetNumSpellBookSkillLines() or 0
  for line = 1, lineCount do
    local lineInfo = C_SpellBook.GetSpellBookSkillLineInfo(line)
    if lineInfo then
      local offset = lineInfo.itemIndexOffset or 0
      local count = lineInfo.numSpellBookItems or 0
      for index = offset + 1, offset + count do
        local itemType, actionId = C_SpellBook.GetSpellBookItemType(index, PLAYER_BANK)
        if itemType == FLYOUT_TYPE and actionId == flyoutId then
          C_SpellBook.PickupSpellBookItem(index, PLAYER_BANK)
          return true
        end
      end
    end
  end

  return false
end
