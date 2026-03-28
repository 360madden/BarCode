-- script name: Core/Protocol.lua
-- version: 0.4.0
-- purpose: Defines the BC-Strip/1 scoped player-target ops+tactical frame layout, payload packing, and module matrix generation.
-- dependencies: Core/Config.lua, Core/Pack.lua, Core/Gather.lua
-- important assumptions: Pass 4 splits the transport into an ops overview page and a tactical combat page while leaving damage-estimate bytes reserved until a verified source exists.
-- protocol version: BC-Strip/1
-- framework module role: Core protocol definition
-- character count note: Character count not precomputed; measure with tooling if needed.

BarCode = BarCode or {}
BarCode.Protocol = {}

BarCode.Protocol.PageIds = {
  opsOverview = 0,
  tacticalCombat = 1
}

BarCode.Protocol.FrameLayout = {
  headerBytes = 12,
  payloadBytes = 56,
  footerBytes = 8,
  totalBytes = 76,
  opsPayloadUsedBytes = 36,
  tacticalPayloadUsedBytes = 47
}

function BarCode.Protocol.GetWitnessBytes(count)
  local bytes = {}
  BarCode.Pack.FillWitness(bytes, 1, count)
  return bytes
end

function BarCode.Protocol.BuildOpsPayloadBytes(snapshot)
  local payloadBytes = {}
  local index = 1

  BarCode.Pack.FillWitness(payloadBytes, 1, BarCode.Protocol.FrameLayout.payloadBytes)

  index = BarCode.Pack.PutUInt16(payloadBytes, index, snapshot.sampleMask or 0)
  index = BarCode.Pack.PutUInt16(payloadBytes, index, snapshot.stateFlags or 0)

  index = BarCode.Pack.PutUInt8(payloadBytes, index, snapshot.playerResourceKindId or 0)
  index = BarCode.Pack.PutUInt24(payloadBytes, index, snapshot.playerHealthCurrent or 0)
  index = BarCode.Pack.PutUInt24(payloadBytes, index, snapshot.playerHealthMax or 0)
  index = BarCode.Pack.PutUInt24(payloadBytes, index, snapshot.playerResourceCurrent or 0)
  index = BarCode.Pack.PutUInt24(payloadBytes, index, snapshot.playerResourceMax or 0)
  index = BarCode.Pack.PutUInt8(payloadBytes, index, snapshot.playerLevel or 0)
  index = BarCode.Pack.PutUInt8(payloadBytes, index, snapshot.playerCallingCode or 0)
  index = BarCode.Pack.PutUInt8(payloadBytes, index, snapshot.playerRoleCode or 0)
  index = BarCode.Pack.PutUInt8(payloadBytes, index, snapshot.playerCastFlags or 0)
  index = BarCode.Pack.PutUInt16(payloadBytes, index, snapshot.playerCastProgressQ15 or 0)
  index = BarCode.Pack.PutUInt16(payloadBytes, index, snapshot.playerPowerAttack or 0)
  index = BarCode.Pack.PutUInt16(payloadBytes, index, snapshot.playerCritAttack or 0)
  index = BarCode.Pack.PutUInt16(payloadBytes, index, snapshot.playerPowerSpell or 0)
  index = BarCode.Pack.PutUInt16(payloadBytes, index, snapshot.playerCritSpell or 0)
  index = BarCode.Pack.PutUInt16(payloadBytes, index, snapshot.playerCritPower or 0)
  index = BarCode.Pack.PutUInt16(payloadBytes, index, snapshot.playerHit or 0)

  index = BarCode.Pack.PutUInt8(payloadBytes, index, snapshot.targetResourceKindId or 0)
  index = BarCode.Pack.PutUInt24(payloadBytes, index, snapshot.targetHealthCurrent or 0)
  index = BarCode.Pack.PutUInt24(payloadBytes, index, snapshot.targetHealthMax or 0)
  index = BarCode.Pack.PutUInt24(payloadBytes, index, snapshot.targetResourceCurrent or 0)
  index = BarCode.Pack.PutUInt24(payloadBytes, index, snapshot.targetResourceMax or 0)
  index = BarCode.Pack.PutUInt8(payloadBytes, index, snapshot.targetLevel or 0)
  index = BarCode.Pack.PutUInt8(payloadBytes, index, snapshot.targetFlags or 0)
  index = BarCode.Pack.PutUInt8(payloadBytes, index, snapshot.targetRelationCode or 0)

  return payloadBytes, BarCode.Protocol.FrameLayout.opsPayloadUsedBytes
end

function BarCode.Protocol.BuildPayloadBytesForPage(pageId, snapshot)
  if pageId == BarCode.Protocol.PageIds.opsOverview then
    return BarCode.Protocol.BuildOpsPayloadBytes(snapshot)
  end

  if pageId == BarCode.Protocol.PageIds.tacticalCombat then
    local payloadBytes = {}
    local index = 1

    BarCode.Pack.FillWitness(payloadBytes, 1, BarCode.Protocol.FrameLayout.payloadBytes)

    index = BarCode.Pack.PutUInt16(payloadBytes, index, snapshot.tacticalMask or 0)
    index = BarCode.Pack.PutUInt16(payloadBytes, index, snapshot.stateFlags or 0)
    index = BarCode.Pack.PutUInt8(payloadBytes, index, snapshot.playerCastFlags or 0)
    index = BarCode.Pack.PutUInt16(payloadBytes, index, snapshot.playerCastProgressQ15 or 0)
    index = BarCode.Pack.PutUInt16(payloadBytes, index, snapshot.playerPowerAttack or 0)
    index = BarCode.Pack.PutUInt16(payloadBytes, index, snapshot.playerCritAttack or 0)
    index = BarCode.Pack.PutUInt16(payloadBytes, index, snapshot.playerPowerSpell or 0)
    index = BarCode.Pack.PutUInt16(payloadBytes, index, snapshot.playerCritSpell or 0)
    index = BarCode.Pack.PutUInt16(payloadBytes, index, snapshot.playerCritPower or 0)
    index = BarCode.Pack.PutUInt16(payloadBytes, index, snapshot.playerHit or 0)
    index = BarCode.Pack.PutUInt16(payloadBytes, index, snapshot.playerZoneHash16 or 0)
    index = BarCode.Pack.PutUInt16(payloadBytes, index, snapshot.targetZoneHash16 or 0)
    index = BarCode.Pack.PutInt24(payloadBytes, index, snapshot.playerCoordX10 or 0)
    index = BarCode.Pack.PutInt24(payloadBytes, index, snapshot.playerCoordY10 or 0)
    index = BarCode.Pack.PutInt24(payloadBytes, index, snapshot.playerCoordZ10 or 0)
    index = BarCode.Pack.PutInt24(payloadBytes, index, snapshot.targetCoordX10 or 0)
    index = BarCode.Pack.PutInt24(payloadBytes, index, snapshot.targetCoordY10 or 0)
    index = BarCode.Pack.PutInt24(payloadBytes, index, snapshot.targetCoordZ10 or 0)
    index = BarCode.Pack.PutUInt8(payloadBytes, index, snapshot.targetRelationCode or 0)
    index = BarCode.Pack.PutUInt8(payloadBytes, index, snapshot.targetTierCode or 0)
    index = BarCode.Pack.PutUInt8(payloadBytes, index, snapshot.targetTaggedCode or 0)
    index = BarCode.Pack.PutUInt8(payloadBytes, index, snapshot.targetCallingCode or 0)
    index = BarCode.Pack.PutUInt16(payloadBytes, index, snapshot.targetRadiusQ10 or 0)

    return payloadBytes, BarCode.Protocol.FrameLayout.tacticalPayloadUsedBytes
  end

  error("Unsupported page id for current BarCode pass: " .. tostring(pageId))
end

function BarCode.Protocol.BuildLiveFrameBytes(snapshot, scheduleEntry)
  local config = BarCode.Config
  local profile = config.GetActiveProfile(snapshot.clientWidth, snapshot.clientHeight)
  local pageId = scheduleEntry.pageId or BarCode.Protocol.PageIds.opsOverview
  local sequence = scheduleEntry.sequence or 0
  local flags0 = snapshot.playerAvailable and 0x01 or 0x00
  local payloadBytes, payloadUsedLength = BarCode.Protocol.BuildPayloadBytesForPage(pageId, snapshot)
  local bytes = {}
  local index

  bytes[1] = 0x42
  bytes[2] = 0x43
  bytes[3] = config.protocolVersion
  bytes[4] = config.layoutId
  bytes[5] = profile.numericId
  bytes[6] = config.schemaId
  bytes[7] = pageId
  bytes[8] = sequence
  bytes[9] = flags0
  bytes[10] = payloadUsedLength

  local headerCrc = BarCode.Pack.Crc16(bytes, 1, 10)
  bytes[11] = math.floor(headerCrc / 0x100)
  bytes[12] = math.fmod(headerCrc, 0x100)

  for index = 1, BarCode.Protocol.FrameLayout.payloadBytes do
    bytes[12 + index] = payloadBytes[index]
  end

  local payloadCrc = BarCode.Pack.Crc16(bytes, 13, 68)
  bytes[69] = math.floor(payloadCrc / 0x100)
  bytes[70] = math.fmod(payloadCrc, 0x100)
  bytes[71] = sequence
  bytes[72] = pageId
  bytes[73] = config.protocolVersion
  bytes[74] = profile.numericId
  bytes[75] = 0xC3
  bytes[76] = 0x5A

  return bytes, {
    profile = profile,
    pageId = pageId,
    sequence = sequence,
    payloadUsedLength = payloadUsedLength,
    flags0 = flags0
  }
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
