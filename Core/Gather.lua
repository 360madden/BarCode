-- script name: Core/Gather.lua
-- version: 0.3.1
-- purpose: Gathers and normalizes the scoped player-target HUD telemetry snapshot for BarCode.
-- dependencies: Core/Config.lua
-- important assumptions: Uses locally precedent-backed Inspect.Unit.Detail/Lookup/Castbar and Inspect.Stat fields; damage-estimate bytes remain reserved until a verified source exists.
-- protocol version: BC-Strip/1
-- framework module role: Core live data gather/normalize
-- character count note: Character count not precomputed; measure with tooling if needed.

BarCode = BarCode or {}
BarCode.Gather = {}
BarCode.Gather.State = {
  playerUnitId = nil,
  targetUnitId = nil,
  lastCastbar = nil,
  lastCastbarSource = nil,
  lastCastbarAt = 0
}

BarCode.Gather.ResourceKind = {
  none = 0,
  mana = 1,
  energy = 2,
  charge = 3,
  planar = 4,
  power = 5
}

BarCode.Gather.SampleBits = {
  playerHealth = 0x0001,
  playerResource = 0x0002,
  playerLevel = 0x0004,
  playerCalling = 0x0008,
  playerRole = 0x0010,
  playerCast = 0x0020,
  playerPowerAttack = 0x0040,
  playerCritAttack = 0x0080,
  playerPowerSpell = 0x0100,
  playerCritSpell = 0x0200,
  playerCritPower = 0x0400,
  playerHit = 0x0800,
  targetHealth = 0x1000,
  targetResource = 0x2000,
  targetLevel = 0x4000,
  targetFlags = 0x8000
}

BarCode.Gather.StateBits = {
  playerAvailable = 0x0001,
  playerAlive = 0x0002,
  playerCombat = 0x0004,
  playerCastActive = 0x0008,
  playerResourceAvailable = 0x0010,
  targetPresent = 0x0020,
  targetAlive = 0x0040,
  targetCombat = 0x0080,
  targetResourceAvailable = 0x0100
}

BarCode.Gather.TargetBits = {
  player = 0x01,
  pet = 0x02
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
  { token = "warrior", code = 4 },
  { token = "primalist", code = 5 }
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

function BarCode.Gather.GetRealtimeNow()
  if Inspect ~= nil and Inspect.Time ~= nil and Inspect.Time.Real ~= nil then
    return Inspect.Time.Real()
  end

  return 0
end

function BarCode.Gather.GetPlayerUnitId()
  local state = BarCode.Gather.State

  if state.playerUnitId ~= nil and state.playerUnitId ~= false then
    return state.playerUnitId
  end

  if Inspect ~= nil and Inspect.Unit ~= nil and Inspect.Unit.Lookup ~= nil then
    state.playerUnitId = Inspect.Unit.Lookup("player") or nil
    return state.playerUnitId
  end

  return nil
end

function BarCode.Gather.GetTargetUnitId()
  if Inspect ~= nil and Inspect.Unit ~= nil and Inspect.Unit.Lookup ~= nil then
    BarCode.Gather.State.targetUnitId = Inspect.Unit.Lookup("player.target") or nil
    return BarCode.Gather.State.targetUnitId
  end

  return nil
end

function BarCode.Gather.InspectUnitDetail(unit)
  if unit == nil or unit == false or unit == "" or Inspect == nil or Inspect.Unit == nil or Inspect.Unit.Detail == nil then
    return {}
  end

  local ok, detail = pcall(function()
    return Inspect.Unit.Detail(unit)
  end)

  if not ok or type(detail) ~= "table" then
    return {}
  end

  return detail
end

function BarCode.Gather.InspectCastbar(unit)
  if unit == nil or unit == false or unit == "" or Inspect == nil or Inspect.Unit == nil or Inspect.Unit.Castbar == nil then
    return nil
  end

  local ok, castbar = pcall(function()
    return Inspect.Unit.Castbar(unit)
  end)

  if not ok then
    return nil
  end

  return castbar
end

function BarCode.Gather.RefreshCastbarCache(unitHint, reason)
  local state = BarCode.Gather.State
  local playerUnitId = BarCode.Gather.GetPlayerUnitId()
  local candidates = {}
  local index

  if unitHint ~= nil and unitHint ~= false then
    candidates[#candidates + 1] = {
      unit = unitHint,
      source = "hint"
    }
  end

  if playerUnitId ~= nil and playerUnitId ~= false then
    candidates[#candidates + 1] = {
      unit = playerUnitId,
      source = "player-unit-id"
    }
  end

  candidates[#candidates + 1] = {
    unit = "player",
    source = "player-specifier"
  }

  for index = 1, #candidates do
    local candidate = candidates[index]
    local detail = BarCode.Gather.InspectCastbar(candidate.unit)
    if detail ~= nil and next(detail) ~= nil then
      state.lastCastbar = detail
      state.lastCastbarSource = candidate.source
      state.lastCastbarAt = BarCode.Gather.GetRealtimeNow()
      return detail, candidate.source
    end
  end

  if reason == "castbar-cleared" then
    state.lastCastbar = nil
    state.lastCastbarSource = nil
    state.lastCastbarAt = BarCode.Gather.GetRealtimeNow()
  end

  return nil, "none"
end

function BarCode.Gather.GetCachedCastbar()
  local state = BarCode.Gather.State
  local maxAge = BarCode.Config.castbarCacheSeconds or 0
  local now = BarCode.Gather.GetRealtimeNow()

  if state.lastCastbar == nil then
    return nil, "none"
  end

  if maxAge <= 0 or now <= 0 or (now - (state.lastCastbarAt or 0)) <= maxAge then
    return state.lastCastbar, state.lastCastbarSource or "cache"
  end

  return nil, "expired"
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

function BarCode.Gather.GetTemporaryRole()
  if Inspect == nil or Inspect.TEMPORARY == nil or Inspect.TEMPORARY.Role == nil then
    return nil
  end

  local ok, value = pcall(function()
    return Inspect.TEMPORARY.Role()
  end)

  if not ok then
    return nil
  end

  return value
end

function BarCode.Gather.GetPreferredResourceKind(callingCode)
  if callingCode == 1 or callingCode == 3 then
    return BarCode.Gather.ResourceKind.mana
  end

  if callingCode == 2 or callingCode == 4 then
    return BarCode.Gather.ResourceKind.energy
  end

  if callingCode == 5 then
    return BarCode.Gather.ResourceKind.power
  end

  return BarCode.Gather.ResourceKind.none
end

function BarCode.Gather.SelectPrimaryResource(player, callingCode)
  local powerMaximum = player.powerMax
  if powerMaximum == nil and player.power ~= nil then
    powerMaximum = 100
  end

  local candidates = {
    BuildResourceCandidate(BarCode.Gather.ResourceKind.mana, player.mana, player.manaMax, "mana", 0),
    BuildResourceCandidate(BarCode.Gather.ResourceKind.energy, player.energy, player.energyMax, "energy", 0),
    BuildResourceCandidate(BarCode.Gather.ResourceKind.charge, player.charge, player.chargeMax, "charge", 0),
    BuildResourceCandidate(BarCode.Gather.ResourceKind.planar, player.planar, player.planarMax, "planar", 0),
    BuildResourceCandidate(BarCode.Gather.ResourceKind.power, player.power, powerMaximum, "power", player.power ~= nil and 1 or 0)
  }
  local preferredKind = BarCode.Gather.GetPreferredResourceKind(callingCode)
  local bestCandidate = nil
  local index

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
  local castbarSource = "none"

  if castbarAvailable then
    castbar, castbarSource = BarCode.Gather.RefreshCastbarCache(nil, "poll")
    if castbar == nil then
      castbar, castbarSource = BarCode.Gather.GetCachedCastbar()
    end
    castbar = castbar or {}
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
    source = castbarSource,
    remainingSeconds = remaining,
    durationSeconds = duration,
    expiredSeconds = expired
  }
end

function BarCode.Gather.SafeInspectStat(statName)
  if statName == nil or Inspect == nil or Inspect.Stat == nil then
    return nil
  end

  local ok, value = pcall(function()
    return Inspect.Stat(statName)
  end)

  if not ok then
    return nil
  end

  return value
end

function BarCode.Gather.BuildCombatStatsSnapshot()
  local function BuildStatField(statName)
    local value = BarCode.Gather.SafeInspectStat(statName)
    return {
      value = ClampUnsigned16(value),
      available = value ~= nil
    }
  end

  return {
    powerAttack = BuildStatField("powerAttack"),
    critAttack = BuildStatField("critAttack"),
    powerSpell = BuildStatField("powerSpell"),
    critSpell = BuildStatField("critSpell"),
    critPower = BuildStatField("critPower"),
    hit = BuildStatField("hit")
  }
end

function BarCode.Gather.BuildTargetFlags(target)
  local flags = 0

  if target.player then
    flags = flags + BarCode.Gather.TargetBits.player
  end

  if target.isPet then
    flags = flags + BarCode.Gather.TargetBits.pet
  end

  return ClampUnsigned8(flags)
end

function BarCode.Gather.BuildDebugProbe(player, target, cast, playerResource, targetResource, combatStats, callingCode, callingRaw, roleCode, roleRaw, targetCallingCode, targetCallingRaw, targetUnitId)
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
    selectedResourceKind = playerResource.kindId or 0,
    selectedResourceSource = playerResource.source or "none",
    selectedResourceCurrent = playerResource.current or 0,
    selectedResourceMax = playerResource.maximum or 0,
    playerUnitId = BarCode.Gather.GetPlayerUnitId(),
    targetUnitId = targetUnitId,
    targetName = NormalizeText(target.name),
    targetCalling = NormalizeText(target.calling),
    targetMatchedCalling = targetCallingRaw or "",
    targetCallingCode = targetCallingCode or 0,
    targetHealth = target.health,
    targetHealthMax = target.healthMax,
    targetPower = target.power,
    targetMana = target.mana,
    targetManaMax = target.manaMax,
    targetEnergy = target.energy,
    targetEnergyMax = target.energyMax,
    targetResourceKind = targetResource.kindId or 0,
    targetResourceSource = targetResource.source or "none",
    targetResourceCurrent = targetResource.current or 0,
    targetResourceMax = targetResource.maximum or 0,
    powerAttack = combatStats.powerAttack.value or 0,
    critAttack = combatStats.critAttack.value or 0,
    powerSpell = combatStats.powerSpell.value or 0,
    critSpell = combatStats.critSpell.value or 0,
    critPower = combatStats.critPower.value or 0,
    hit = combatStats.hit.value or 0,
    castAbility = NormalizeText(cast.ability),
    castAbilityName = NormalizeText(cast.abilityName),
    castSource = cast.source or "none",
    castDurationSeconds = cast.durationSeconds or 0,
    castRemainingSeconds = cast.remainingSeconds or 0,
    castExpiredSeconds = cast.expiredSeconds or 0,
    castActive = cast.active and true or false,
    castFlags = cast.flags or 0,
    castProgressQ15 = cast.progressQ15 or 0
  }
end

function BarCode.Gather.BuildPlayerSnapshot()
  local player = BarCode.Gather.InspectUnitDetail("player")
  local targetUnitId = BarCode.Gather.GetTargetUnitId()
  local target = BarCode.Gather.InspectUnitDetail(targetUnitId)
  local cast = BarCode.Gather.BuildCastbarSnapshot()
  local callingCode, callingRaw = BarCode.Gather.ResolveCalling(player)
  local roleCode, roleRaw = BarCode.Gather.ResolveRole(player)
  if roleCode == 0 then
    roleCode, roleRaw = MatchTokenCode(BarCode.Gather.RoleTokens, BarCode.Gather.GetTemporaryRole())
  end
  local targetCallingCode, targetCallingRaw = BarCode.Gather.ResolveCalling(target)
  local playerResource = BarCode.Gather.SelectPrimaryResource(player, callingCode)
  local targetResource = BarCode.Gather.SelectPrimaryResource(target, targetCallingCode)
  local combatStats = BarCode.Gather.BuildCombatStatsSnapshot()
  local clientWidth, clientHeight = BarCode.Gather.GetClientSize()
  local playerAvailable = next(player) ~= nil
  local targetAvailable = next(target) ~= nil
  local playerHealthCurrent = ClampUnsigned24(player.health)
  local playerHealthMaximum = ClampUnsigned24(player.healthMax)
  local playerLevel = ClampUnsigned8(player.level)
  local targetHealthCurrent = ClampUnsigned24(target.health)
  local targetHealthMaximum = ClampUnsigned24(target.healthMax)
  local targetLevel = ClampUnsigned8(target.level)
  local targetFlags = BarCode.Gather.BuildTargetFlags(target)
  local sampleMask = 0
  local stateFlags = 0

  if playerAvailable then
    stateFlags = stateFlags + BarCode.Gather.StateBits.playerAvailable
  end

  if player.health ~= nil or player.healthMax ~= nil then
    sampleMask = sampleMask + BarCode.Gather.SampleBits.playerHealth
  end

  if playerHealthCurrent > 0 then
    stateFlags = stateFlags + BarCode.Gather.StateBits.playerAlive
  end

  if player.combat then
    stateFlags = stateFlags + BarCode.Gather.StateBits.playerCombat
  end

  if playerResource.available then
    sampleMask = sampleMask + BarCode.Gather.SampleBits.playerResource
    stateFlags = stateFlags + BarCode.Gather.StateBits.playerResourceAvailable
  end

  if cast.available then
    sampleMask = sampleMask + BarCode.Gather.SampleBits.playerCast
  end

  if cast.active then
    stateFlags = stateFlags + BarCode.Gather.StateBits.playerCastActive
  end

  if player.level ~= nil then
    sampleMask = sampleMask + BarCode.Gather.SampleBits.playerLevel
  end

  if callingCode > 0 then
    sampleMask = sampleMask + BarCode.Gather.SampleBits.playerCalling
  end

  if roleCode > 0 then
    sampleMask = sampleMask + BarCode.Gather.SampleBits.playerRole
  end

  if combatStats.powerAttack.available then
    sampleMask = sampleMask + BarCode.Gather.SampleBits.playerPowerAttack
  end

  if combatStats.critAttack.available then
    sampleMask = sampleMask + BarCode.Gather.SampleBits.playerCritAttack
  end

  if combatStats.powerSpell.available then
    sampleMask = sampleMask + BarCode.Gather.SampleBits.playerPowerSpell
  end

  if combatStats.critSpell.available then
    sampleMask = sampleMask + BarCode.Gather.SampleBits.playerCritSpell
  end

  if combatStats.critPower.available then
    sampleMask = sampleMask + BarCode.Gather.SampleBits.playerCritPower
  end

  if combatStats.hit.available then
    sampleMask = sampleMask + BarCode.Gather.SampleBits.playerHit
  end

  if targetAvailable then
    stateFlags = stateFlags + BarCode.Gather.StateBits.targetPresent
  end

  if target.health ~= nil or target.healthMax ~= nil then
    sampleMask = sampleMask + BarCode.Gather.SampleBits.targetHealth
  end

  if targetHealthCurrent > 0 then
    stateFlags = stateFlags + BarCode.Gather.StateBits.targetAlive
  end

  if target.combat then
    stateFlags = stateFlags + BarCode.Gather.StateBits.targetCombat
  end

  if targetResource.available then
    sampleMask = sampleMask + BarCode.Gather.SampleBits.targetResource
    stateFlags = stateFlags + BarCode.Gather.StateBits.targetResourceAvailable
  end

  if target.level ~= nil then
    sampleMask = sampleMask + BarCode.Gather.SampleBits.targetLevel
  end

  if targetAvailable then
    sampleMask = sampleMask + BarCode.Gather.SampleBits.targetFlags
  end

  return {
    clientWidth = clientWidth,
    clientHeight = clientHeight,
    playerAvailable = playerAvailable,
    sampleMask = ClampUnsigned16(sampleMask),
    stateFlags = ClampUnsigned16(stateFlags),
    playerResourceKindId = playerResource.kindId,
    playerHealthCurrent = playerHealthCurrent,
    playerHealthMax = playerHealthMaximum,
    playerResourceCurrent = playerResource.current,
    playerResourceMax = playerResource.maximum,
    playerLevel = playerLevel,
    playerCallingCode = callingCode,
    playerRoleCode = roleCode,
    playerCastFlags = cast.flags,
    playerCastProgressQ15 = cast.progressQ15,
    playerPowerAttack = combatStats.powerAttack.value,
    playerCritAttack = combatStats.critAttack.value,
    playerPowerSpell = combatStats.powerSpell.value,
    playerCritSpell = combatStats.critSpell.value,
    playerCritPower = combatStats.critPower.value,
    playerHit = combatStats.hit.value,
    targetResourceKindId = targetResource.kindId,
    targetHealthCurrent = targetHealthCurrent,
    targetHealthMax = targetHealthMaximum,
    targetResourceCurrent = targetResource.current,
    targetResourceMax = targetResource.maximum,
    targetLevel = targetLevel,
    targetFlags = targetFlags,
    playerDamageEstimate = 0,
    targetDamageEstimate = 0,
    castActive = cast.active,
    resourceSource = playerResource.source,
    debugProbe = BarCode.Gather.BuildDebugProbe(
      player,
      target,
      cast,
      playerResource,
      targetResource,
      combatStats,
      callingCode,
      callingRaw,
      roleCode,
      roleRaw,
      targetCallingCode,
      targetCallingRaw,
      targetUnitId
    )
  }
end

local function IsFilledText(value)
  return value ~= nil and tostring(value) ~= ""
end

local function HasFlag(value, flag)
  local number = math.floor(tonumber(value) or 0)
  local divisor = math.floor(flag or 0)

  if divisor <= 0 then
    return false
  end

  return math.fmod(math.floor(number / divisor), 2) == 1
end

local function AddValidationIssue(report, severity, code, field, message, value)
  local issue = {
    severity = severity,
    code = code,
    field = field,
    message = message,
    value = value
  }

  report.issues[#report.issues + 1] = issue
  report.issueCount = report.issueCount + 1

  if severity == "error" then
    report.errorCount = report.errorCount + 1
  else
    report.warningCount = report.warningCount + 1
    report.suspicious = true
  end
end

local function AddError(report, code, field, message, value)
  AddValidationIssue(report, "error", code, field, message, value)
end

local function AddWarning(report, code, field, message, value)
  AddValidationIssue(report, "warning", code, field, message, value)
end

local function EmptyTargetData(snapshot)
  local debugProbe = snapshot.debugProbe or {}

  return not (
    (tonumber(snapshot.targetHealthCurrent) or 0) > 0
    or (tonumber(snapshot.targetHealthMax) or 0) > 0
    or (tonumber(snapshot.targetResourceCurrent) or 0) > 0
    or (tonumber(snapshot.targetResourceMax) or 0) > 0
    or (tonumber(snapshot.targetLevel) or 0) > 0
    or (tonumber(snapshot.targetFlags) or 0) > 0
    or (tonumber(snapshot.targetResourceKindId) or 0) > 0
    or IsFilledText(debugProbe.targetName)
    or IsFilledText(debugProbe.targetUnitId)
  )
end

function BarCode.Gather.ValidateSnapshot(snapshot)
  local report = {
    valid = true,
    suspicious = false,
    errorCount = 0,
    warningCount = 0,
    issueCount = 0,
    issues = {},
    summary = ""
  }

  local debugProbe = {}
  local stateFlags = 0
  local playerAvailable = false
  local playerHealthCurrent = 0
  local playerHealthMax = 0
  local playerResourceKindId = 0
  local playerResourceCurrent = 0
  local playerResourceMax = 0
  local playerCastFlags = 0
  local playerCastProgressQ15 = 0
  local playerCallingCode = 0
  local playerRoleCode = 0
  local targetHealthCurrent = 0
  local targetHealthMax = 0
  local targetResourceKindId = 0
  local targetResourceCurrent = 0
  local targetResourceMax = 0
  local targetLevel = 0
  local targetFlags = 0
  local castActive = false

  if type(snapshot) ~= "table" then
    AddError(report, "snapshot-type", "snapshot", "Snapshot was not a table.", type(snapshot))
    report.valid = false
    report.suspicious = true
    report.summary = "errors=1 warnings=0"
    return report
  end

  debugProbe = snapshot.debugProbe or {}
  stateFlags = math.floor(tonumber(snapshot.stateFlags) or 0)
  playerAvailable = snapshot.playerAvailable and true or false
  playerHealthCurrent = math.floor(tonumber(snapshot.playerHealthCurrent) or 0)
  playerHealthMax = math.floor(tonumber(snapshot.playerHealthMax) or 0)
  playerResourceKindId = math.floor(tonumber(snapshot.playerResourceKindId) or 0)
  playerResourceCurrent = math.floor(tonumber(snapshot.playerResourceCurrent) or 0)
  playerResourceMax = math.floor(tonumber(snapshot.playerResourceMax) or 0)
  playerCastFlags = math.floor(tonumber(snapshot.playerCastFlags) or 0)
  playerCastProgressQ15 = math.floor(tonumber(snapshot.playerCastProgressQ15) or 0)
  playerCallingCode = math.floor(tonumber(snapshot.playerCallingCode) or 0)
  playerRoleCode = math.floor(tonumber(snapshot.playerRoleCode) or 0)
  targetHealthCurrent = math.floor(tonumber(snapshot.targetHealthCurrent) or 0)
  targetHealthMax = math.floor(tonumber(snapshot.targetHealthMax) or 0)
  targetResourceKindId = math.floor(tonumber(snapshot.targetResourceKindId) or 0)
  targetResourceCurrent = math.floor(tonumber(snapshot.targetResourceCurrent) or 0)
  targetResourceMax = math.floor(tonumber(snapshot.targetResourceMax) or 0)
  targetLevel = math.floor(tonumber(snapshot.targetLevel) or 0)
  targetFlags = math.floor(tonumber(snapshot.targetFlags) or 0)
  castActive = snapshot.castActive and true or false

  if playerAvailable ~= HasFlag(stateFlags, BarCode.Gather.StateBits.playerAvailable) then
    AddError(report, "player-available-bit", "stateFlags", "Player availability bit disagrees with the snapshot flag.", stateFlags)
  end

  if HasFlag(stateFlags, BarCode.Gather.StateBits.playerAlive) and playerHealthCurrent <= 0 then
    AddWarning(report, "player-alive-empty-health", "playerHealthCurrent", "Player is flagged alive but has no health value.", playerHealthCurrent)
  end

  if playerHealthCurrent > playerHealthMax and playerHealthMax > 0 then
    AddError(report, "player-health-order", "playerHealthCurrent", "Player health current exceeds max.", playerHealthCurrent .. "/" .. playerHealthMax)
  end

  if playerHealthCurrent > 0 and playerHealthMax <= 0 then
    AddError(report, "player-health-max-missing", "playerHealthMax", "Player health current is present but max is missing or zero.", playerHealthCurrent .. "/" .. playerHealthMax)
  end

  if playerResourceCurrent > playerResourceMax and playerResourceMax > 0 then
    AddError(report, "player-resource-order", "playerResourceCurrent", "Player resource current exceeds max.", playerResourceCurrent .. "/" .. playerResourceMax)
  end

  if playerResourceCurrent > 0 and playerResourceMax <= 0 then
    AddError(report, "player-resource-max-missing", "playerResourceMax", "Player resource current is present but max is missing or zero.", playerResourceCurrent .. "/" .. playerResourceMax)
  end

  if playerResourceKindId == BarCode.Gather.ResourceKind.none and HasFlag(stateFlags, BarCode.Gather.StateBits.playerResourceAvailable) then
    AddError(report, "player-resource-bit", "playerResourceKindId", "Player resource bit is set but no resource kind was selected.", playerResourceKindId)
  end

  if playerResourceKindId ~= BarCode.Gather.ResourceKind.none and not HasFlag(stateFlags, BarCode.Gather.StateBits.playerResourceAvailable) and (playerResourceCurrent > 0 or playerResourceMax > 0) then
    AddWarning(report, "player-resource-mismatch", "playerResourceKindId", "Player resource exists but the resource-available flag is clear.", playerResourceKindId)
  end

  if playerCallingCode < 0 or playerCallingCode > 5 then
    AddWarning(report, "player-calling-range", "playerCallingCode", "Player calling code is outside the current narrow range.", playerCallingCode)
  end

  if playerRoleCode < 0 or playerRoleCode > 4 then
    AddWarning(report, "player-role-range", "playerRoleCode", "Player role code is outside the current narrow range.", playerRoleCode)
  end

  if playerCallingCode == 1 or playerCallingCode == 3 then
    if playerResourceKindId ~= BarCode.Gather.ResourceKind.mana and (playerResourceCurrent > 0 or playerResourceMax > 0) then
      AddWarning(report, "player-resource-calling", "playerResourceKindId", "Mage/cleric resource kind does not look like mana.", playerResourceKindId)
    end
  elseif playerCallingCode == 2 or playerCallingCode == 4 then
    if playerResourceKindId ~= BarCode.Gather.ResourceKind.energy and (playerResourceCurrent > 0 or playerResourceMax > 0) then
      AddWarning(report, "player-resource-calling", "playerResourceKindId", "Rogue/warrior resource kind does not look like energy.", playerResourceKindId)
    end
  elseif playerCallingCode == 5 then
    if playerResourceKindId ~= BarCode.Gather.ResourceKind.power and (playerResourceCurrent > 0 or playerResourceMax > 0) then
      AddWarning(report, "player-resource-calling", "playerResourceKindId", "Primalist resource kind does not look like power.", playerResourceKindId)
    end
  end

  if playerHealthCurrent > 0 and not playerAvailable then
    AddWarning(report, "player-unavailable-health", "playerAvailable", "Player snapshot has health while availability is false.", playerHealthCurrent)
  end

  if castActive and playerCastFlags == 0 then
    AddError(report, "cast-active-flags", "playerCastFlags", "Cast is active but the cast flag field is empty.", playerCastFlags)
  end

  if not castActive and (playerCastFlags > 0 or playerCastProgressQ15 > 0 or IsFilledText(debugProbe.castAbilityName)) then
    AddWarning(report, "cast-stale", "playerCastFlags", "Cast snapshot still contains active-looking data after cast deactivation.", playerCastFlags .. "/" .. playerCastProgressQ15)
  end

  if targetHealthCurrent > targetHealthMax and targetHealthMax > 0 then
    AddError(report, "target-health-order", "targetHealthCurrent", "Target health current exceeds max.", targetHealthCurrent .. "/" .. targetHealthMax)
  end

  if targetHealthCurrent > 0 and targetHealthMax <= 0 then
    AddError(report, "target-health-max-missing", "targetHealthMax", "Target health current is present but max is missing or zero.", targetHealthCurrent .. "/" .. targetHealthMax)
  end

  if targetResourceCurrent > targetResourceMax and targetResourceMax > 0 then
    AddError(report, "target-resource-order", "targetResourceCurrent", "Target resource current exceeds max.", targetResourceCurrent .. "/" .. targetResourceMax)
  end

  if targetResourceCurrent > 0 and targetResourceMax <= 0 then
    AddError(report, "target-resource-max-missing", "targetResourceMax", "Target resource current is present but max is missing or zero.", targetResourceCurrent .. "/" .. targetResourceMax)
  end

  if targetFlags > 0 and not HasFlag(stateFlags, BarCode.Gather.StateBits.targetPresent) then
    AddError(report, "target-flag-without-target", "targetFlags", "Target flags are present but the target-present bit is clear.", targetFlags)
  end

  if HasFlag(stateFlags, BarCode.Gather.StateBits.targetPresent) and EmptyTargetData(snapshot) then
    AddWarning(report, "target-present-empty", "target", "Target is present but the snapshot has no usable target data.", debugProbe.targetUnitId or targetFlags)
  end

  if targetResourceKindId == BarCode.Gather.ResourceKind.none and (targetResourceCurrent > 0 or targetResourceMax > 0) then
    AddError(report, "target-resource-kind", "targetResourceKindId", "Target resource values exist but no resource kind was selected.", targetResourceKindId)
  end

  if HasFlag(stateFlags, BarCode.Gather.StateBits.targetPresent) and not HasFlag(stateFlags, BarCode.Gather.StateBits.targetAlive) and targetHealthCurrent > 0 then
    AddWarning(report, "target-alive-flag", "stateFlags", "Target has health but is not marked alive.", stateFlags)
  end

  if HasFlag(stateFlags, BarCode.Gather.StateBits.targetPresent) and targetHealthCurrent <= 0 and targetHealthMax <= 0 and targetLevel <= 0 and targetFlags == 0 then
    AddWarning(report, "target-empty", "target", "Target is present but has no health, level, or flags.", debugProbe.targetUnitId or "unknown")
  end

  if not HasFlag(stateFlags, BarCode.Gather.StateBits.targetPresent) and (targetHealthCurrent > 0 or targetHealthMax > 0 or targetLevel > 0 or targetFlags > 0 or targetResourceCurrent > 0 or targetResourceMax > 0) then
    AddWarning(report, "target-data-without-bit", "stateFlags", "Target data exists even though the target-present bit is clear.", stateFlags)
  end

  report.valid = report.errorCount == 0
  report.suspicious = report.suspicious or report.errorCount > 0
  report.summary = "errors=" .. tostring(report.errorCount) .. " warnings=" .. tostring(report.warningCount)

  return report
end

-- end-of-script marker comment
