local ADDON_NAME, MM = ...

-- Shared condition evaluation for smartAction candidates and layers. A `conditions`
-- table carries optional dimensions — classes / specs / roles / factions / races /
-- professions (lists) and levelMin / levelMax — and every present, non-empty
-- dimension must match the current character. Absent dimensions don't restrict, so
-- an empty (or nil) table always matches.
local Conditions = {}
MM.Conditions = Conditions

local function currentClass()
  return select(2, UnitClass("player"))
end

local function currentSpec()
  if not GetSpecialization then
    return nil
  end
  local index = GetSpecialization()
  if not index then
    return nil
  end
  return GetSpecializationInfo and GetSpecializationInfo(index) or nil
end

local function currentRole()
  if not GetSpecialization then
    return nil
  end
  local index = GetSpecialization()
  if not index then
    return nil
  end
  return GetSpecializationRole and GetSpecializationRole(index) or nil
end

local function currentRace()
  return select(2, UnitRace("player"))
end

local function currentFaction()
  return UnitFactionGroup and UnitFactionGroup("player") or nil
end

-- GetProfessions answers in five fixed positions (two primaries, archaeology,
-- fishing, cooking) and leaves the unlearned ones nil, so read it by position:
-- ipairs over the packed results would stop at the first empty slot and hide
-- everything after it.
local PROFESSION_SLOTS = 5

-- The parent skill line ("Engineering"), not the per-expansion child line
-- ("Midnight Engineering") — GetProfessionInfo's 7th return.
local PROFESSION_SKILL_LINE = 7

local function knownProfessions()
  local known = {}
  if not (GetProfessions and GetProfessionInfo) then
    return known
  end
  local slots = { GetProfessions() }
  for slot = 1, PROFESSION_SLOTS do
    local index = slots[slot]
    local skillLine = index and select(PROFESSION_SKILL_LINE, GetProfessionInfo(index))
    if skillLine then
      known[skillLine] = true
    end
  end
  return known
end

-- Unlike the other dimensions a character holds several values at once, so the
-- condition matches when any listed profession is one of them.
local function professionsOk(list)
  if not (list and #list > 0) then
    return true
  end
  local known = knownProfessions()
  for _, skillLine in ipairs(list) do
    if known[skillLine] then
      return true
    end
  end
  return false
end

local function inList(list, value)
  if value == nil then
    return false
  end
  for _, entry in ipairs(list) do
    if entry == value then
      return true
    end
  end
  return false
end

-- A list dimension matches when it's absent/empty, or it contains the value.
local function dimensionOk(list, value)
  return not (list and #list > 0) or inList(list, value)
end

function Conditions.Match(conditions)
  if not conditions then
    return true
  end

  if not dimensionOk(conditions.classes, currentClass()) then
    return false
  end
  if not dimensionOk(conditions.specs, currentSpec()) then
    return false
  end
  if not dimensionOk(conditions.roles, currentRole()) then
    return false
  end
  if not dimensionOk(conditions.factions, currentFaction()) then
    return false
  end
  if not dimensionOk(conditions.races, currentRace()) then
    return false
  end
  if not professionsOk(conditions.professions) then
    return false
  end

  local level = UnitLevel and UnitLevel("player")
  if level then
    if conditions.levelMin and level < conditions.levelMin then
      return false
    end
    if conditions.levelMax and level > conditions.levelMax then
      return false
    end
  end

  return true
end

-- Whether any dimension is actually set, so the UI can flag a conditioned layer
-- or candidate.
function Conditions.Any(conditions)
  if not conditions then
    return false
  end
  for _, key in ipairs({ "classes", "specs", "roles", "factions", "races", "professions" }) do
    local list = conditions[key]
    if list and #list > 0 then
      return true
    end
  end
  return conditions.levelMin ~= nil or conditions.levelMax ~= nil
end
