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

  if command == "capture" then
    local root = MM.DB:GetRoot()
    local layoutId = root.ui.selectedLayout or "Core"
    if words[2] and words[2] ~= "all" then
      local slot = tonumber(words[2])
      local ok, reason = MM.ui.CaptureMode:CaptureSlot(layoutId, slot)
      if ok then
        MM:Print("captured " .. MM.Actions.GetSlotLabel(slot) .. " into layout " .. layoutId .. ".")
      else
        MM:Warn(reason or "could not capture slot")
      end
      return
    end

    local captured, _, failed, failures = MM.ui.CaptureMode:CaptureFilledSlots(layoutId)
    MM:Print(string.format("captured %d filled slots into layout %s, failed %d.", captured, layoutId, failed))
    MM.ui.CaptureMode:PrintFailures(failures)
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

  MM:Print(
    "commands: /mm, /mm apply [profile], /mm preview [profile], /mm capture [slot|all], /mm copygroup <standard> [custom]"
  )
end
