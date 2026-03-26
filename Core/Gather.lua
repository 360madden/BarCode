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
  local lower = string.lower(tostring(value or ""))

  if string.find(lower, "mage", 1, true) then
    return 1
  end

  if string.find(lower, "rogue", 1, true) then
    return 2
  end

  if string.find(lower, "cleric", 1, true) then
    return 3
  end

  if string.find(lower, "warrior", 1, true) then
    return 4
  end

  return 0
end

function BarCode.Gather.EncodeRoleCode(value)
  local lower = string.lower(tostring(value or ""))

  if string.find(lower, "dps", 1, true) or string.find(lower, "damage", 1, true) then
    return 1
  end

  if string.find(lower, "heal", 1, true) then
    return 2
  end

  if string.find(lower, "tank", 1, true) then
    return 3
  end

  if string.find(lower, "support", 1, true) then
    return 4
  end

  return 0
end

function BarCode.Gather.SelectPrimaryResource(player)
  local candidates = {
    { kindId = BarCode.Gather.ResourceKind.mana, current = player.mana, maximum = player.manaMax },
    { kindId = BarCode.Gather.ResourceKind.energy, current = player.energy, maximum = player.energyMax },
    { kindId = BarCode.Gather.ResourceKind.charge, current = player.charge, maximum = player.chargeMax },
    { kindId = BarCode.Gather.ResourceKind.planar, current = player.planar, maximum = player.planarMax }
  }
  local index

  for index = 1, #candidates do
    local candidate = candidates[index]
    if candidate.current ~= nil or candidate.maximum ~= nil then
      return {
        kindId = candidate.kindId,
        current = ClampUnsigned24(candidate.current),
        maximum = ClampUnsigned24(candidate.maximum),
        available = true
      }
    end
  end

  return {
    kindId = BarCode.Gather.ResourceKind.none,
    current = 0,
    maximum = 0,
    available = false
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
    progressQ15 = ClampUnsigned16(progress)
  }
end

function BarCode.Gather.BuildPlayerSnapshot()
  local player = {}
  if Inspect ~= nil and Inspect.Unit ~= nil and Inspect.Unit.Detail ~= nil then
    player = Inspect.Unit.Detail("player") or {}
  end

  local cast = BarCode.Gather.BuildCastbarSnapshot()
  local resource = BarCode.Gather.SelectPrimaryResource(player)
  local clientWidth, clientHeight = BarCode.Gather.GetClientSize()
  local playerAvailable = next(player) ~= nil
  local healthCurrent = ClampUnsigned24(player.health)
  local healthMaximum = ClampUnsigned24(player.healthMax)
  local level = ClampUnsigned8(player.level)
  local callingCode = BarCode.Gather.EncodeCallingCode(player.calling)
  local roleCode = BarCode.Gather.EncodeRoleCode(player.role)
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
    castActive = cast.active
  }
end

-- end-of-script marker comment
