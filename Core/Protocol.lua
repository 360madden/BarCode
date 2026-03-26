-- script name: Core/Protocol.lua
-- version: 0.1.0
-- purpose: Defines the BC-Strip/1 static frame layout, payload map, and module matrix generation.
-- dependencies: Core/Config.lua
-- important assumptions: Phase 1 uses a fixed static payload and the P720A profile only.
-- protocol version: BC-Strip/1
-- framework module role: Core protocol definition
-- character count note: Character count not precomputed; measure with tooling if needed.

BarCode = BarCode or {}
BarCode.Protocol = {}

function BarCode.Protocol.GetStaticPayloadBytes()
  return {
    0x10, 0x11, 0x12, 0x13, 0x20, 0x21, 0x22, 0x23,
    0x30, 0x31, 0x32, 0x33, 0x40, 0x41, 0x42, 0x43,
    0x50, 0x51, 0x52, 0x53, 0x60, 0x61, 0x62, 0x63
  }
end

function BarCode.Protocol.GetWitnessBytes()
  local bytes = {}
  local value = 0xA5
  local index
  for index = 1, 32 do
    bytes[index] = value
    if value == 0xA5 then
      value = 0x5A
    else
      value = 0xA5
    end
  end
  return bytes
end

function BarCode.Protocol.BuildStaticFrameBytes()
  local config = BarCode.Config
  local profile = BarCode.Config.GetActiveProfile()
  local payload = BarCode.Protocol.GetStaticPayloadBytes()
  local bytes = {}
  local index

  bytes[1] = 0x42
  bytes[2] = 0x43
  bytes[3] = config.protocolVersion
  bytes[4] = config.layoutId
  bytes[5] = profile.numericId
  bytes[6] = config.schemaId
  bytes[7] = config.staticSequence
  bytes[8] = 0x00
  bytes[9] = config.staticPayloadLength
  bytes[10] = 0x00

  local headerCrc = BarCode.Pack.Crc16(bytes, 1, 10)
  bytes[11] = math.floor(headerCrc / 256)
  bytes[12] = math.floor(headerCrc % 256)

  for index = 1, #payload do
    bytes[12 + index] = payload[index]
  end

  local payloadCrc = BarCode.Pack.Crc16(payload, 1, #payload)
  bytes[37] = math.floor(payloadCrc / 256)
  bytes[38] = math.floor(payloadCrc % 256)
  bytes[39] = 0x42
  bytes[40] = 0x43
  bytes[41] = config.protocolVersion
  bytes[42] = config.staticSequence
  bytes[43] = config.staticPayloadLength
  bytes[44] = 0xC3

  local witness = BarCode.Protocol.GetWitnessBytes()
  for index = 1, #witness do
    bytes[44 + index] = witness[index]
  end

  return bytes
end

function BarCode.Protocol.BuildModuleMatrix(profile, frameBytes)
  local rows = {}
  local rowIndex
  local colIndex
  local bits = BarCode.Pack.BytesToBits(frameBytes)
  local bitCursor = 1

  for rowIndex = 1, profile.gridRows do
    rows[rowIndex] = {}
    for colIndex = 1, profile.gridColumns do
      rows[rowIndex][colIndex] = 0
    end
  end

  for colIndex = 1, profile.gridColumns do
    rows[1][colIndex] = 1
    if math.fmod(colIndex - 1, 2) == 0 then
      rows[profile.gridRows][colIndex] = 1
    end
  end

  for rowIndex = 1, profile.gridRows do
    rows[rowIndex][1] = 1
    if math.fmod(rowIndex - 1, 2) == 0 then
      rows[rowIndex][profile.gridColumns] = 1
    end
  end

  for rowIndex = 2, profile.gridRows - 1 do
    for colIndex = 2, profile.gridColumns - 1 do
      rows[rowIndex][colIndex] = bits[bitCursor] or 0
      bitCursor = bitCursor + 1
    end
  end

  return rows
end

-- end-of-script marker comment
