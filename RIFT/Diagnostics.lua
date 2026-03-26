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
BarCode.Diagnostics.probeState = {
  lastSignature = nil,
  logCount = 0
}

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

function BarCode.Diagnostics.BoolText(value)
  if value then
    return "true"
  end

  return "false"
end

function BarCode.Diagnostics.TextOrFallback(value)
  if value == nil then
    return "(nil)"
  end

  local text = tostring(value)
  if text == "" then
    return "(empty)"
  end

  return text
end

function BarCode.Diagnostics.BuildProbeSignature(probe)
  return table.concat({
    BarCode.Diagnostics.TextOrFallback(probe.rawCalling),
    BarCode.Diagnostics.TextOrFallback(probe.rawRole),
    tostring(probe.normalizedCallingCode or 0),
    tostring(probe.normalizedRoleCode or 0),
    tostring(probe.selectedResourceKind or 0),
    BarCode.Diagnostics.TextOrFallback(probe.selectedResourceSource),
    tostring(probe.selectedResourceCurrent or 0),
    tostring(probe.selectedResourceMax or 0),
    BarCode.Diagnostics.BoolText(probe.castActive),
    tostring(probe.castFlags or 0),
    tostring(probe.castProgressQ15 or 0),
    BarCode.Diagnostics.TextOrFallback(probe.castAbilityName)
  }, "|")
end

function BarCode.Diagnostics.IsSuspiciousProbe(probe)
  local rawCalling = probe.rawCalling or ""

  if rawCalling ~= "" and probe.normalizedCallingCode == 0 then
    return true
  end

  if (probe.rawRole or "") ~= "" and probe.normalizedRoleCode == 0 then
    return true
  end

  if (rawCalling == "cleric" or rawCalling == "mage") and probe.selectedResourceKind ~= 1 then
    return true
  end

  if ((probe.castAbilityName or "") ~= "" or (probe.castDurationSeconds or 0) > 0 or (probe.castRemainingSeconds or 0) > 0)
      and not probe.castActive then
    return true
  end

  return false
end

function BarCode.Diagnostics.LogGatherProbe(probe, reason)
  local config = BarCode.Config
  local state = BarCode.Diagnostics.probeState
  local maxEvents = config.probeLoggingMaxEvents or 0
  local signature
  local suspicious

  if not config.probeLoggingEnabled or probe == nil then
    return
  end

  signature = BarCode.Diagnostics.BuildProbeSignature(probe)
  suspicious = BarCode.Diagnostics.IsSuspiciousProbe(probe)

  if state.lastSignature == signature and not suspicious then
    return
  end

  if maxEvents > 0 and state.logCount >= maxEvents and not suspicious then
    state.lastSignature = signature
    return
  end

  state.lastSignature = signature
  state.logCount = state.logCount + 1

  BarCode.Diagnostics.Log(
    "Probe[" .. tostring(reason or "refresh") .. "] "
      .. "calling=" .. BarCode.Diagnostics.TextOrFallback(probe.rawCalling)
      .. " matchedCalling=" .. BarCode.Diagnostics.TextOrFallback(probe.matchedCalling)
      .. " callingCode=" .. tostring(probe.normalizedCallingCode or 0)
      .. " role=" .. BarCode.Diagnostics.TextOrFallback(probe.rawRole)
      .. " matchedRole=" .. BarCode.Diagnostics.TextOrFallback(probe.matchedRole)
      .. " roleCode=" .. tostring(probe.normalizedRoleCode or 0)
      .. " race=" .. BarCode.Diagnostics.TextOrFallback(probe.race)
      .. "/" .. BarCode.Diagnostics.TextOrFallback(probe.raceName)
      .. " mana=" .. tostring(probe.mana or "nil") .. "/" .. tostring(probe.manaMax or "nil")
      .. " energy=" .. tostring(probe.energy or "nil") .. "/" .. tostring(probe.energyMax or "nil")
      .. " charge=" .. tostring(probe.charge or "nil") .. "/" .. tostring(probe.chargeMax or "nil")
      .. " planar=" .. tostring(probe.planar or "nil") .. "/" .. tostring(probe.planarMax or "nil")
      .. " power=" .. tostring(probe.power or "nil")
      .. " selectedResource=" .. tostring(probe.selectedResourceKind or 0) .. ":" .. BarCode.Diagnostics.TextOrFallback(probe.selectedResourceSource)
      .. " selectedValue=" .. tostring(probe.selectedResourceCurrent or 0) .. "/" .. tostring(probe.selectedResourceMax or 0)
      .. " playerUnitId=" .. BarCode.Diagnostics.TextOrFallback(probe.playerUnitId)
      .. " cast=" .. BarCode.Diagnostics.TextOrFallback(probe.castAbilityName)
      .. " castSource=" .. BarCode.Diagnostics.TextOrFallback(probe.castSource)
      .. " active=" .. BarCode.Diagnostics.BoolText(probe.castActive)
      .. " flags=" .. tostring(probe.castFlags or 0)
      .. " remaining=" .. tostring(probe.castRemainingSeconds or 0)
      .. " duration=" .. tostring(probe.castDurationSeconds or 0)
      .. " progress=" .. tostring(probe.castProgressQ15 or 0)
  )
end

-- end-of-script marker comment
