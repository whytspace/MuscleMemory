local ADDON_NAME, MM = ...

local GroupEditor = {}
MM.ui.GroupEditor = GroupEditor

function GroupEditor:Build(parent, group)
  local title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT")
  title:SetText(group and group.name or "Action Group")
end
