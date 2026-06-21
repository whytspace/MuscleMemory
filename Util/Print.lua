local ADDON_NAME, MM = ...

local PREFIX = "|cff7aa2ffMuscle Memory:|r "

function MM:Print(message)
  print(PREFIX .. tostring(message))
end

function MM:Debug(message)
  if self.DB and self.DB:GetRoot().debug then
    self:Print("|cff999999debug:|r " .. tostring(message))
  end
end

function MM:Warn(message)
  self:Print("|cffffcc00" .. tostring(message) .. "|r")
end
