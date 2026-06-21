local ADDON_NAME, MM = ...

local Slash = {}
MM.Slash = Slash
MM:RegisterModule("Slash", Slash)

local function splitWords(text)
  local words = {}
  for word in string.gmatch(text or "", "%S+") do
    words[#words + 1] = word
  end
  return words
end

function Slash:OnInitialize()
  SLASH_MUSCLEMEMORY1 = "/mm"
  SLASH_MUSCLEMEMORY2 = "/musclememory"
  SlashCmdList.MUSCLEMEMORY = function(message)
    self:Handle(message)
  end
end

function Slash:Handle(message)
  local words = splitWords(message)
  local command = words[1]

  if not command or command == "" or command == "open" then
    MM:Open()
    return
  end

  if command == "apply" then
    MM.Applier:ApplyProfile(words[2] or MM.DB:GetActiveProfileId())
    return
  end

  if command == "preview" then
    MM.Applier:PreviewProfile(words[2] or MM.DB:GetActiveProfileId())
    return
  end

  if command == "copygroup" then
    local sourceId = words[2]
    local targetId = words[3]
    local group, reason = MM.DB:CopyStandardGroup(sourceId, targetId)
    if group then
      MM:Print("copied standard group " .. sourceId .. " to custom group " .. group.id .. ".")
    else
      MM:Warn(reason or "could not copy group")
    end
    return
  end

  if command == "debug" then
    local root = MM.DB:GetRoot()
    root.debug = not root.debug
    MM:Print("debug " .. (root.debug and "enabled" or "disabled") .. ".")
    return
  end

  MM:Print("commands: /mm, /mm apply [profile], /mm preview [profile], /mm copygroup <standard> [custom]")
end
