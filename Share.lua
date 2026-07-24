local ADDON_NAME, MM = ...

-- Import/export: pack profiles, layers and dynamic actions into a copyable
-- string (LibSerialize -> LibDeflate -> printable encoding, "!MM:1!" prefix).
-- Importing always creates new entities — never overwrites — so the only fixup
-- is re-keying imported dynamic actions and rewriting the layer slots that
-- reference them.
local Share = {}
MM.Share = Share
MM:RegisterModule("Share", Share)

Share.FORMAT_VERSION = 1
local PREFIX_PATTERN = "^!MM:(%d+)!"

local function libs()
  if not LibStub then
    return nil
  end
  local serializer = LibStub:GetLibrary("LibSerialize", true)
  local deflate = LibStub:GetLibrary("LibDeflate", true)
  if not serializer or not deflate then
    return nil
  end
  return serializer, deflate
end

-- Session-only "imported" markers, keyed by profile id. Never saved: the pills
-- they drive last until the next reload, which is the intended lifetime.
Share.recentImports = { profiles = {}, layers = {}, dynamicActions = {} }

local function markImported(kind, profileId, id)
  local bucket = Share.recentImports[kind]
  bucket[profileId] = bucket[profileId] or {}
  bucket[profileId][id] = true
end

function Share:IsRecentImport(kind, profileId, id)
  local bucket = self.recentImports[kind][profileId]
  return bucket ~= nil and bucket[id] ~= nil
end

function Share:IsImportedProfile(profileId)
  return self.recentImports.profiles[profileId] ~= nil
end

-- The custom dynamic actions a layer's slots reference. Predefined references
-- resolve from add-on data on the importer's side, so only "custom" counts.
function Share:LayerDependencies(layer, into)
  local keys = into or {}
  for _, assignment in pairs((layer or {}).slots or {}) do
    if type(assignment) == "table" and assignment.type == "dynamicaction" and assignment.source == "custom" then
      keys[assignment.id] = true
    end
  end
  return keys
end

-- Build a package from `selection`: { settings = bool, layers = { [layerId] = true },
-- dynamicActions = { [key] = true } }. Nil selects the whole profile including
-- settings. Custom dynamic actions referenced by a selected layer are always
-- included, so a package never contains a broken reference.
function Share:BuildPackage(profileId, selection)
  local profile = MM.DB:GetProfile(profileId)
  if not profile then
    return nil, "unknown profile"
  end

  local layers = profile.layers or {}
  local dynamicActions = profile.dynamicActions or {}

  local wantLayers, wantActions, wantSettings
  if selection then
    wantLayers = selection.layers or {}
    wantActions = selection.dynamicActions or {}
    wantSettings = selection.settings and true or false
  else
    wantLayers, wantActions, wantSettings = {}, {}, true
    for id in pairs(layers) do
      wantLayers[id] = true
    end
    for key in pairs(dynamicActions) do
      wantActions[key] = true
    end
  end

  local package = {
    version = self.FORMAT_VERSION,
    schemaVersion = MM.SCHEMA_VERSION,
    profileName = profile.name,
    layers = {},
    dynamicActions = {},
  }

  -- Layers in profile order, so importing recreates the same stacking.
  local required = {}
  for _, layerId in ipairs(profile.layerOrder or {}) do
    if wantLayers[layerId] and layers[layerId] then
      local layer = MM.Tables.DeepCopy(layers[layerId])
      package.layers[#package.layers + 1] = { key = layerId, layer = layer }
      self:LayerDependencies(layer, required)
    end
  end

  for key in pairs(wantActions) do
    required[key] = true
  end
  for key in pairs(required) do
    if dynamicActions[key] then
      package.dynamicActions[key] = MM.Tables.DeepCopy(dynamicActions[key])
    end
  end

  if wantSettings then
    package.settings = { fallback = profile.fallback, response = profile.response }
  end

  if not package.settings and #package.layers == 0 and not next(package.dynamicActions) then
    return nil, "nothing selected to export"
  end
  return package
end

function Share:Encode(package)
  local serializer, deflate = libs()
  if not serializer then
    return nil, "serialization libraries are not loaded"
  end

  local serialized = serializer:Serialize(package)
  local compressed = deflate:CompressDeflate(serialized, { level = 9 })
  return "!MM:" .. self.FORMAT_VERSION .. "!" .. deflate:EncodeForPrint(compressed)
end

function Share:Decode(text)
  local serializer, deflate = libs()
  if not serializer then
    return nil, "serialization libraries are not loaded"
  end

  text = string.gsub(text or "", "%s+", "")
  local version = string.match(text, PREFIX_PATTERN)
  if not version then
    return nil, "not a Muscle Memory sharing string"
  end
  if tonumber(version) > self.FORMAT_VERSION then
    return nil, "this export needs a newer Muscle Memory version"
  end

  local body = string.sub(text, #("!MM:" .. version .. "!") + 1)
  local compressed = deflate:DecodeForPrint(body)
  if not compressed then
    return nil, "the string is damaged or incomplete"
  end
  local serialized = deflate:DecompressDeflate(compressed)
  if not serialized then
    return nil, "the string is damaged or incomplete"
  end
  local ok, package = serializer:Deserialize(serialized)
  if not ok or type(package) ~= "table" then
    return nil, "the string is damaged or incomplete"
  end

  if type(package.schemaVersion) ~= "number" or package.schemaVersion > MM.SCHEMA_VERSION then
    return nil, "this export needs a newer Muscle Memory version"
  end
  package.layers = package.layers or {}
  package.dynamicActions = package.dynamicActions or {}
  return package
end

-- Rewrite re-keyed custom dynamic action references inside one slot/candidate
-- assignment. References to actions that stayed outside the package keep their
-- key and simply may not resolve — same behavior as deleting a dynamic action.
local function rewriteReference(assignment, keyMap)
  if
    type(assignment) == "table"
    and assignment.type == "dynamicaction"
    and assignment.source == "custom"
    and keyMap[assignment.id]
  then
    assignment.id = keyMap[assignment.id]
  end
end

-- Import `selection` from a decoded package: { layers = { [packageKey] = true },
-- dynamicActions = { [packageKey] = true } }, nil for everything. `target` is
-- { profileId = id } for an existing profile or { newProfile = name } to create
-- one (package settings apply only there). Everything imported is created new.
function Share:Import(package, selection, target)
  -- One undo step for the whole import, however many entries it creates.
  return MM.Undo:Batch(function()
    return self:ImportSelection(package, selection, target)
  end, "import a sharing string")
end

function Share:ImportSelection(package, selection, target)
  if type(package) ~= "table" then
    return nil, "nothing to import"
  end

  local wantLayers = selection and (selection.layers or {}) or nil
  local wantActions = selection and (selection.dynamicActions or {}) or nil

  -- Collect the layers to import first: their dependencies are always imported
  -- with them, regardless of the dynamic action checkboxes.
  local layerEntries, required = {}, {}
  for _, entry in ipairs(package.layers) do
    if type(entry) == "table" and type(entry.layer) == "table" and (not wantLayers or wantLayers[entry.key]) then
      layerEntries[#layerEntries + 1] = entry
      self:LayerDependencies(entry.layer, required)
    end
  end

  local actionKeys = {}
  for key, action in pairs(package.dynamicActions) do
    if type(action) == "table" and (required[key] or not wantActions or wantActions[key]) then
      actionKeys[#actionKeys + 1] = key
    end
  end
  table.sort(actionKeys)

  if #layerEntries == 0 and #actionKeys == 0 and not (target and target.newProfile) then
    return nil, "nothing selected to import"
  end

  local profileId
  if target and target.newProfile then
    local name = target.newProfile ~= "" and target.newProfile or package.profileName
    profileId = MM.DB:CreateProfile(name)
    if package.settings then
      -- Invalid or absent values are simply rejected by the setters.
      MM.DB:SetFallback(package.settings.fallback, profileId)
      MM.DB:SetResponse(package.settings.response, profileId)
    end
    markImported("profiles", profileId, profileId)
  else
    profileId = target and target.profileId or MM.DB:GetActiveProfileId()
    if not MM.DB:GetProfile(profileId) then
      return nil, "unknown profile"
    end
  end

  local result = { profileId = profileId, layers = {}, dynamicActions = {} }

  -- Pass 1: allocate a fresh key for every dynamic action up front (against a
  -- shadow `taken` set), rewrite cross-references on the copies, and only then
  -- adopt the finished tables into the profile.
  local keyMap = {}
  local adopted = {}
  local taken = {}
  for key in pairs(MM.DB:DynamicActions(profileId)) do
    taken[key] = true
  end
  for _, key in ipairs(actionKeys) do
    local action = MM.Tables.DeepCopy(package.dynamicActions[key])
    local newKey = MM.DB:UniqueId(action.name, "dynamicaction", taken)
    taken[newKey] = true
    keyMap[key] = newKey
    adopted[#adopted + 1] = { key = newKey, action = action }
  end
  for _, entry in ipairs(adopted) do
    for _, candidate in ipairs(entry.action.candidates or {}) do
      rewriteReference(candidate, keyMap)
    end
    MM.DB:AdoptDynamicAction(profileId, entry.key, entry.action)
    markImported("dynamicActions", profileId, entry.key)
    result.dynamicActions[#result.dynamicActions + 1] = entry.key
  end

  -- Pass 2: layers follow the key map; their slots are rewritten before the
  -- layer is adopted (appended below the existing layers, keeping their order).
  for _, entry in ipairs(layerEntries) do
    local layer = MM.Tables.DeepCopy(entry.layer)
    for _, assignment in pairs(layer.slots or {}) do
      rewriteReference(assignment, keyMap)
    end
    local newKey = MM.DB:AdoptLayer(profileId, layer)
    markImported("layers", profileId, newKey)
    result.layers[#result.layers + 1] = newKey
  end

  return result
end
