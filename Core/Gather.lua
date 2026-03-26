-- script name: Core/Gather.lua
-- version: 0.2.0
-- purpose: Gathers and normalizes live player telemetry into a fixed hot-page snapshot contract.
-- dependencies: Core/Config.lua
-- important assumptions: Uses Inspect.Unit.Detail("player") and Inspect.Unit.Castbar("player"), both locally precedent-backed and listed in the RIFT API index.
-- protocol version: BC-Strip/1
-- framework module role: Core live data gather/normalize
-- character count note: Character count not precomputed; measure with tooling if needed.

BarCode = BarCode or {}
BarCode.Gather = {}

BarCode.Gather.ResourceKind = {
  none = 0,
  mana = 1,
  energy = 2,
  charge = 3,
  planar = 4
}

BarCode.Gather.SampleBits = {
  health = 0x0001,
  resource = 0x0002,
  cast = 0x0004,
  level = 0x0008,
  calling = 0x0010,
  role = 0x0020
}

BarCode.Gather.StateBits = {
  playerAvailable = 0x0001,
  alive = 0x0002,
  combat = 0x0004,
  resourceAvailable = 0x0008,
  castActive = 0x0010
}

BarCode.Gather.CastBits = {
  active = 0x01,
  channeled = 0x02,
  uninterruptible = 0x04
}

BarCode.Gather.CallingTokens = {
  { token = "mage", code = 1 },
  { token = "rogue", code = 2 },
  { token = "cleric", code = 3 },
  { token = "warrior", code = 4 }
}

BarCode.Gather.RoleTokens = {
  { token = "dps", code = 1 },
  { token = "damage", code = 1 },
  { token = "heal", code = 2 },
  { token = "tank", code = 3 },
  { token = "support", code = 4 }
}

local function ClampUnsigned24(value)
  local number = math.floor(tonumber(value) or 0)

  if number < 0 then
    return 0
  end

  if number > 0xFFFFFF then
    return 0xFFFFFF
  end

  return number
end

local function ClampUnsigned16(value)
  local number = math.floor(tonumber(value) or 0)

  if number < 0 then
    return 0
  end

  if number > 0xFFFF then
    return 0xFFFF
  end

  return number
end

local function ClampUnsigned8(value)
  local number = math.floor(tonumber(value) or 0)

  if number < 0 then
    return 0
  end

  if number > 0xFF then
    return 0xFF
  end

  return number
end

local function NormalizeText(value)
  if value == nil then
    return ""
  end

  return string.lower(tostring(value))
end

local function CollectCandidateTexts(target, value, depth)
  local valueType = type(value)
  local key
  local innerValue

  depth = depth or 0
  if value == nil then
    return
  end

  if valueType == "string" or valueType == "number" or valueType == "boolean" then
    local text = NormalizeText(value)
    if text ~= "" then
      target[#target + 1] = text
    end
    return
  end

  if valueType ~= "table" or depth >= 2 then
    return
  end

  for key, innerValue in pairs(value) do
    if type(key) == "string" then
      local keyText = NormalizeText(key)
      if keyText ~= "" then
        target[#target + 1] = keyText
      end
    end

    CollectCandidateTexts(target, innerValue, depth + 1)
  end
end

local function MatchTokenCode(tokenList, ...)
  local texts = {}
  local argIndex
  local argCount = select("#", ...)
  local textIndex
  local tokenIndex

  for argIndex = 1, argCount do
    CollectCandidateTexts(texts, select(argIndex, ...), 0)
  end

  for textIndex = 1, #texts do
    local text = texts[textIndex]
    for tokenIndex = 1, #tokenList do
      local tokenEntry = tokenList[tokenIndex]
      if string.find(text, tokenEntry.token, 1, true) then
        return tokenEntry.code, text
      end
    end
  end

  return 0, ""
end

local function ScoreResourceCandidate(current, maximum)
  local score = -1
  local currentNumber = tonumber(current)
  local maximumNumber = tonumber(maximum)

  if current ~= nil or maximum ~= nil then
    score = 1
  end

  if maximumNumber ~= nil and maximumNumber > 0 then
    score = score + 4
  end

  if currentNumber ~= nil and currentNumber > 0 then
    score = score + 2
  end

  return score
end

local function BuildResourceCandidate(kindId, current, maximum, source, bonus)
  return {
    kindId = kindId,
    current = current,
    maximum = maximum,
    source = source,
    score = ScoreResourceCandidate(current, maximum) + (bonus or 0)
  }
end

function BarCode.Gather.GetClientSize()
  if UIParent == nil or UIParent.GetWidth == nil or UIParent.GetHeight == nil then
    return 0, 0
  end

  local ok, width, height = pcall(function()
    return UIParent:GetWidth(), UIParent:GetHeight()
  end)

  if not ok then
    return 0, 0
  end

  return math.floor((tonumber(width) or 0) + 0.5), math.floor((tonumber(height) or 0) + 0.5)
end

function BarCode.Gather.EncodeCallingCode(value)
  local code = MatchTokenCode(BarCode.Gather.CallingTokens, value)
  return code
end

function BarCode.Gather.EncodeRoleCode(value)
  local code = MatchTokenCode(BarCode.Gather.RoleTokens, value)
  return code
end

function BarCode.Gather.ResolveCalling(player)
  return MatchTokenCode(
    BarCode.Gather.CallingTokens,
    player.calling,
    player.callingName,
    player.class,
    player.className,
    player.career,
    player.careerName
  )
end

function BarCode.Gather.ResolveRole(player)
  return MatchTokenCode(
    BarCode.Gather.RoleTokens,
    player.role,
    player.roleName
  )
end

function BarCode.Gather.GetPreferredResourceKind(callingCode)
  if callingCode == 1 or callingCode == 3 then
    return BarCode.Gather.ResourceKind.mana
  end

  if callingCode == 2 or callingCode == 4 then
    return BarCode.Gather.ResourceKind.energy
  end

  return BarCode.Gather.ResourceKind.none
end

function BarCode.Gather.SelectPrimaryResource(player, callingCode)
  local candidates = {
    BuildResourceCandidate(BarCode.Gather.ResourceKind.mana, player.mana, player.manaMax, "mana", 0),
    BuildResourceCandidate(BarCode.Gather.ResourceKind.energy, player.energy, player.energyMax, "energy", 0),
    BuildResourceCandidate(BarCode.Gather.ResourceKind.charge, player.charge, player.chargeMax, "charge", 0),
    BuildResourceCandidate(BarCode.Gather.ResourceKind.planar, player.planar, player.planarMax, "planar", 0)
  }
  local preferredKind = BarCode.Gather.GetPreferredResourceKind(callingCode)
  local bestCandidate = nil
  local index

  if preferredKind ~= BarCode.Gather.ResourceKind.none and player.power ~= nil then
    candidates[#candidates + 1] = BuildResourceCandidate(preferredKind, player.power, 100, "power-fallback", 1)
  end

  for index = 1, #candidates do
    local candidate = candidates[index]
    if candidate.kindId == preferredKind then
      candidate.score = candidate.score + 3
    end

    if candidate.score >= 0 and (bestCandidate == nil or candidate.score > bestCandidate.score) then
      bestCandidate = candidate
    end
  end

  if bestCandidate ~= nil then
    return {
      kindId = bestCandidate.kindId,
      current = ClampUnsigned24(bestCandidate.current),
      maximum = ClampUnsigned24(bestCandidate.maximum),
      available = true,
      source = bestCandidate.source
    }
  end

  return {
    kindId = BarCode.Gather.ResourceKind.none,
    current = 0,
    maximum = 0,
    available = false,
    source = "none"
  }
end

function BarCode.Gather.BuildCastbarSnapshot()
  local castbarAvailable = Inspect ~= nil and Inspect.Unit ~= nil and Inspect.Unit.Castbar ~= nil
  local castbar = {}

  if castbarAvailable then
    castbar = Inspect.Unit.Castbar("player") or {}
  end

  local ability = tostring(castbar.ability or "")
  local abilityName = tostring(castbar.abilityName or "")
  local remaining = tonumber(castbar.remaining or 0) or 0
  local duration = tonumber(castbar.duration or 0) or 0
  local expired = tonumber(castbar.expired or 0) or 0
  local active = remaining > 0 or duration > 0 or expired > 0 or ability ~= "" or abilityName ~= ""
  local flags = 0
  local progress = 0

  if active then
    flags = flags + BarCode.Gather.CastBits.active
  end

  if castbar.channeled then
    flags = flags + BarCode.Gather.CastBits.channeled
  end

  if castbar.uninterruptible then
    flags = flags + BarCode.Gather.CastBits.uninterruptible
  end

  if duration > 0 then
    local completed = duration - remaining
    if completed < 0 then
      completed = 0
    end
    if completed > duration then
      completed = duration
    end
    progress = math.floor(((completed / duration) * 0x7FFF) + 0.5)
  end

  return {
    available = castbarAvailable,
    active = active,
    flags = ClampUnsigned8(flags),
    progressQ15 = ClampUnsigned16(progress),
    ability = ability,
    abilityName = abilityName,
    remainingSeconds = remaining,
    durationSeconds = duration,
    expiredSeconds = expired
  }
end

function BarCode.Gather.BuildDebugProbe(player, cast, resource, callingCode, callingRaw, roleCode, roleRaw)
  return {
    availability = NormalizeText(player.availability),
    rawCalling = NormalizeText(player.calling),
    matchedCalling = callingRaw or "",
    normalizedCallingCode = callingCode or 0,
    rawRole = NormalizeText(player.role),
    matchedRole = roleRaw or "",
    normalizedRoleCode = roleCode or 0,
    race = NormalizeText(player.race),
    raceName = NormalizeText(player.raceName),
    mana = player.mana,
    manaMax = player.manaMax,
    energy = player.energy,
    energyMax = player.energyMax,
    charge = player.charge,
    chargeMax = player.chargeMax,
    planar = player.planar,
    planarMax = player.planarMax,
    power = player.power,
    selectedResourceKind = resource.kindId or 0,
    selectedResourceSource = resource.source or "none",
    selectedResourceCurrent = resource.current or 0,
    selectedResourceMax = resource.maximum or 0,
    castAbility = NormalizeText(cast.ability),
    castAbilityName = NormalizeText(cast.abilityName),
    castDurationSeconds = cast.durationSeconds or 0,
    castRemainingSeconds = cast.remainingSeconds or 0,
    castExpiredSeconds = cast.expiredSeconds or 0,
    castActive = cast.active and true or false,
    castFlags = cast.flags or 0,
    castProgressQ15 = cast.progressQ15 or 0
  }
end

function BarCode.Gather.BuildPlayerSnapshot()
  local player = {}
  if Inspect ~= nil and Inspect.Unit ~= nil and Inspect.Unit.Detail ~= nil then
    player = Inspect.Unit.Detail("player") or {}
  end

  local cast = BarCode.Gather.BuildCastbarSnapshot()
  local callingCode, callingRaw = BarCode.Gather.ResolveCalling(player)
  local roleCode, roleRaw = BarCode.Gather.ResolveRole(player)
  local resource = BarCode.Gather.SelectPrimaryResource(player, callingCode)
  local clientWidth, clientHeight = BarCode.Gather.GetClientSize()
  local playerAvailable = next(player) ~= nil
  local healthCurrent = ClampUnsigned24(player.health)
  local healthMaximum = ClampUnsigned24(player.healthMax)
  local level = ClampUnsigned8(player.level)
  local sampleMask = 0
  local stateFlags = 0

  if playerAvailable then
    stateFlags = stateFlags + BarCode.Gather.StateBits.playerAvailable
  end

  if player.health ~= nil or player.healthMax ~= nil then
    sampleMask = sampleMask + BarCode.Gather.SampleBits.health
  end

  if healthCurrent > 0 then
    stateFlags = stateFlags + BarCode.Gather.StateBits.alive
  end

  if player.combat then
    stateFlags = stateFlags + BarCode.Gather.StateBits.combat
  end

  if resource.available then
    sampleMask = sampleMask + BarCode.Gather.SampleBits.resource
    stateFlags = stateFlags + BarCode.Gather.StateBits.resourceAvailable
  end

  if cast.available then
    sampleMask = sampleMask + BarCode.Gather.SampleBits.cast
  end

  if cast.active then
    stateFlags = stateFlags + BarCode.Gather.StateBits.castActive
  end

  if player.level ~= nil then
    sampleMask = sampleMask + BarCode.Gather.SampleBits.level
  end

  if callingCode > 0 then
    sampleMask = sampleMask + BarCode.Gather.SampleBits.calling
  end

  if roleCode > 0 then
    sampleMask = sampleMask + BarCode.Gather.SampleBits.role
  end

  return {
    clientWidth = clientWidth,
    clientHeight = clientHeight,
    playerAvailable = playerAvailable,
    sampleMask = ClampUnsigned16(sampleMask),
    stateFlags = ClampUnsigned16(stateFlags),
    resourceKindId = resource.kindId,
    healthCurrent = healthCurrent,
    healthMax = healthMaximum,
    resourceCurrent = resource.current,
    resourceMax = resource.maximum,
    castFlags = cast.flags,
    castProgressQ15 = cast.progressQ15,
    level = level,
    callingCode = callingCode,
    roleCode = roleCode,
    castActive = cast.active,
    resourceSource = resource.source,
    debugProbe = BarCode.Gather.BuildDebugProbe(player, cast, resource, callingCode, callingRaw, roleCode, roleRaw)
  }
end

-- end-of-script marker comment
