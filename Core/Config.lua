-- script name: Core/Config.lua
-- version: 0.1.0
-- purpose: Defines shared BarCode constants, colors, profiles, and startup options.
-- dependencies: None. Loaded before other BarCode Lua modules.
-- important assumptions: Phase 1 targets a 1280x720 baseline band and does not yet query the live client size.
-- protocol version: BC-Strip/1
-- framework module role: Core configuration
-- character count note: Character count not precomputed; measure with tooling if needed.

BarCode = BarCode or {}
BarCode.Config = {
  addonIdentifier = "BarCode",
  addonVersion = "0.1.0",
  protocolVersion = 1,
  layoutId = 1,
  profileId = 1,
  schemaId = 1,
  staticSequence = 42,
  staticPayloadLength = 24,
  requestedStrata = nil,
  requestedLayer = 100000,
  showOnStartup = true,
  colors = {
    bandLight = { 0.96, 0.96, 0.96, 1.0 },
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

function BarCode.Config.GetActiveProfile()
  return BarCode.Config.profiles.P720A
end

-- end-of-script marker comment
