-- script name: Core/Pack.lua
-- version: 0.1.0
-- purpose: Supplies deterministic bit packing and CRC helpers for BC-Strip/1.
-- dependencies: Core/Config.lua
-- important assumptions: Uses CRC-16/CCITT-FALSE semantics with big-endian byte emission.
-- protocol version: BC-Strip/1
-- framework module role: Core packing and validation primitives
-- character count note: Character count not precomputed; measure with tooling if needed.

BarCode = BarCode or {}
BarCode.Pack = {}

function BarCode.Pack.BitXor(leftValue, rightValue)
  local result = 0
  local bitWeight = 1
  local left = leftValue
  local right = rightValue

  while left > 0 or right > 0 do
    local leftBit = math.fmod(left, 2)
    local rightBit = math.fmod(right, 2)
    if leftBit ~= rightBit then
      result = result + bitWeight
    end
    left = math.floor(left / 2)
    right = math.floor(right / 2)
    bitWeight = bitWeight * 2
  end

  return result
end

function BarCode.Pack.BytesToBits(bytes)
  local bits = {}
  local byteIndex
  local bitIndex
  local cursor = 1

  for byteIndex = 1, #bytes do
    local value = bytes[byteIndex]
    for bitIndex = 7, 0, -1 do
      local bitValue = math.floor(value / (2 ^ bitIndex))
      bits[cursor] = math.fmod(bitValue, 2)
      cursor = cursor + 1
    end
  end

  return bits
end

function BarCode.Pack.Crc16(bytes, startIndex, endIndex)
  local crc = 0xFFFF
  local byteIndex
  local bitIndex

  for byteIndex = startIndex, endIndex do
    local value = bytes[byteIndex] or 0
    crc = BarCode.Pack.BitXor(crc, (value * 256))
    for bitIndex = 1, 8 do
      if crc >= 0x8000 then
        crc = BarCode.Pack.BitXor((crc * 2), 0x1021)
      else
        crc = crc * 2
      end
      crc = math.fmod(crc, 0x10000)
    end
  end

  return crc
end

-- end-of-script marker comment
