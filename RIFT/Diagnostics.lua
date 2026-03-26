-- script name: RIFT/Diagnostics.lua
-- version: 0.1.0
-- purpose: Provides lightweight logging and layout diagnostics for the RIFT integration spike.
-- dependencies: Core/Config.lua
-- important assumptions: Uses print-based logging because richer in-game logging is not yet wired.
-- protocol version: BC-Strip/1
-- framework module role: RIFT diagnostics
-- character count note: Character count not precomputed; measure with tooling if needed.

BarCode = BarCode or {}
BarCode.Diagnostics = {}

function BarCode.Diagnostics.Log(message)
  local formatted = "[BarCode] " .. tostring(message)

  if Command ~= nil and Command.Console ~= nil and Command.Console.Display ~= nil then
    local colorHex = BarCode.Config.chatColorHex or "#4DEAFF"
    local htmlText = "<font color=\"" .. colorHex .. "\">" .. formatted .. "</font>"
    Command.Console.Display("general", true, htmlText, true)
    return
  end

  print(formatted)
end

function BarCode.Diagnostics.DescribeStrataList(frame)
  local list = {}
  local index = 1
  local source = frame:GetStrataList()
  local key
  local value

  if source == nil then
    return "(unavailable)"
  end

  for key, value in pairs(source) do
    if type(value) == "string" then
      list[index] = value
    else
      list[index] = tostring(key)
    end
    index = index + 1
  end

  if #list == 0 then
    return "(empty)"
  end

  return table.concat(list, ", ")
end

function BarCode.Diagnostics.LogLoaded()
  local config = BarCode.Config
  BarCode.Diagnostics.Log(config.addonIdentifier .. " v" .. config.addonVersion .. " loaded.")
end

-- end-of-script marker comment
