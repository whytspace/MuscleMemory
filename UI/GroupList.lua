local ADDON_NAME, MM = ...

local GroupList = {}
MM.ui.GroupList = GroupList

function GroupList:Build(parent)
  local title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT")
  title:SetText("Standard Action Groups")

  local note = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  note:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
  note:SetText("Standard groups are immutable. Copy one if you want to edit it.")

  local y = -48
  for groupId, group in pairs(MM.StandardGroups) do
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(680, 28)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)

    local name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    name:SetPoint("LEFT")
    name:SetText(group.name)

    local count = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    count:SetPoint("LEFT", row, "LEFT", 180, 0)
    count:SetText(tostring(#(group.candidates or {})) .. " candidates")

    local copy = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    copy:SetSize(80, 22)
    copy:SetPoint("RIGHT")
    copy:SetText("Copy")
    copy:SetScript("OnClick", function()
      local copied, reason = MM.DB:CopyStandardGroup(groupId)
      if copied then
        MM:Print("copied " .. group.name .. " to custom groups.")
      else
        MM:Warn(reason)
      end
    end)

    y = y - 30
  end
end
