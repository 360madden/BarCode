-- script name: Core/Config.lua
-- version: 0.3.2
-- purpose: Defines shared BarCode constants, colors, profiles, transport sizes, and scoped player-target HUD telemetry options.
-- dependencies: None. Loaded before other BarCode Lua modules.
-- important assumptions: Pass 3 keeps BC-Strip/1 geometry fixed while narrowing the product scope to player/target HUD telemetry.
-- protocol version: BC-Strip/1
-- framework module role: Core configuration
-- character count note: Character count not precomputed; measure with tooling if needed.

BarCode = BarCode or {}
BarCode.Config = {
  addonIdentifier = "BarCode",
  addonVersion = "0.3.2",
  protocolVersion = 1,
  layoutId = 1,
  schemaId = 3,
  requestedStrata = nil,
  requestedLayer = 100000,
  showOnStartup = true,
  chatColorHex = "#4DEAFF",
  probeLoggingEnabled = true,
  probeLoggingMaxEvents = 16,
  validationLoggingEnabled = true,
  validationLogMaxEvents = 16,
  validationSummaryMaxIssues = 4,
  castbarCacheSeconds = 0.75,
  refreshIntervalSeconds = 0.10,
  refreshIntervalCastingSeconds = 0.05,
  transportBytes = 76,
  headerBytes = 12,
  payloadBytes = 56,
  footerBytes = 8,
  pageIds = {
    playerCoreHot = 0,
    playerCoreCold = 1
  },
  colors = {
    bandReservedDark = { 0.03, 0.03, 0.03, 1.0 },
    symbolPanelLight = { 0.96, 0.96, 0.96, 1.0 },
    moduleDark = { 0.06, 0.06, 0.06, 1.0 },
    debugAccent = { 0.16, 0.38, 0.86, 1.0 }
  },
  profiles = {
    P720A = {
      id = "P720A",
      numericId = 1,
      windowWidth = 1280,
      windowHeight = 720,
      bandWidth = 1280,
      bandHeight = 64,
      quietLeft = 24,
      quietRight = 24,
      quietTop = 8,
      quietBottom = 8,
      pitch = 8,
      gridColumns = 154,
      gridRows = 6,
      dataColumns = 152,
      dataRows = 4,
      symbolWidth = 1232,
      symbolHeight = 48
    }
  }
}

function BarCode.Config.GetActiveProfile(clientWidth, clientHeight)
  return BarCode.Config.profiles.P720A
end

-- end-of-script marker comment
