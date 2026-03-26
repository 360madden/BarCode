-- script name: RIFT/Render.lua
-- version: 0.3.0
-- purpose: Creates and updates the live BC-Strip/1 protocol band with a full-width reserved top band.
-- dependencies: Core/Config.lua, Core/Protocol.lua, Core/Pack.lua, Core/Gather.lua, RIFT/Diagnostics.lua
-- important assumptions: Assumes Frame:SetPoint, Frame:SetBackgroundColor, and Frame:SetVisible behave per current documented RIFT UI API.
-- protocol version: BC-Strip/1
-- framework module role: RIFT renderer
-- character count note: Character count not precomputed; measure with tooling if needed.

BarCode = BarCode or {}
BarCode.Render = {}

function BarCode.Render.ApplyColor(frame, color)
  frame:SetBackgroundColor(color[1], color[2], color[3], color[4])
end

function BarCode.Render.CreateBlock(parent, name, x, y, width, height, color, layer)
  local frame = UI.CreateFrame("Frame", name, parent)
  frame:SetWidth(width)
  frame:SetHeight(height)
  frame:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  frame:SetLayer(layer)
  BarCode.Render.ApplyColor(frame, color)
  return frame
end

function BarCode.Render.CreateModuleFrame(parent, name, x, y, size, color, layer)
  local frame = UI.CreateFrame("Frame", name, parent)
  frame:SetWidth(size)
  frame:SetHeight(size)
  frame:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  frame:SetLayer(layer)
  BarCode.Render.ApplyColor(frame, color)
  return frame
end

function BarCode.Render.BuildStaticBorderPositions(profile)
  local positions = {}
  local rowIndex
  local colIndex
  local key

  for colIndex = 1, profile.gridColumns do
    key = "1:" .. tostring(colIndex)
    positions[key] = { row = 1, column = colIndex }

    if math.fmod(colIndex - 1, 2) == 0 then
      key = tostring(profile.gridRows) .. ":" .. tostring(colIndex)
      positions[key] = { row = profile.gridRows, column = colIndex }
    end
  end

  for rowIndex = 1, profile.gridRows do
    key = tostring(rowIndex) .. ":1"
    positions[key] = { row = rowIndex, column = 1 }

    if math.fmod(rowIndex - 1, 2) == 0 then
      key = tostring(rowIndex) .. ":" .. tostring(profile.gridColumns)
      positions[key] = { row = rowIndex, column = profile.gridColumns }
    end
  end

  return positions
end

function BarCode.Render.FrameBytesEqual(leftBytes, rightBytes)
  local index

  if leftBytes == nil or rightBytes == nil or #leftBytes ~= #rightBytes then
    return false
  end

  for index = 1, #leftBytes do
    if leftBytes[index] ~= rightBytes[index] then
      return false
    end
  end

  return true
end

function BarCode.Render.CopyFrameBytes(bytes)
  local copy = {}
  local index

  for index = 1, #bytes do
    copy[index] = bytes[index]
  end

  return copy
end

function BarCode.Render.InitializeLiveBand(rootFrame)
  local config = BarCode.Config
  local profile = config.GetActiveProfile()
  local clientWidth = select(1, BarCode.Gather.GetClientSize())
  local reservedBandWidth = clientWidth
  local borderPositions = BarCode.Render.BuildStaticBorderPositions(profile)
  local band
  local panel
  local borderFrames = {}
  local dataFrames = {}
  local lastBits = {}
  local dataIndex = 1
  local borderIndex = 1
  local rowIndex
  local colIndex
  local key

  if reservedBandWidth < profile.bandWidth then
    reservedBandWidth = profile.bandWidth
  end

  band = BarCode.Render.CreateBlock(
    rootFrame,
    "BarCode_Band",
    0,
    0,
    reservedBandWidth,
    profile.bandHeight,
    config.colors.bandReservedDark,
    config.requestedLayer
  )

  panel = BarCode.Render.CreateBlock(
    band,
    "BarCode_SymbolPanel",
    0,
    0,
    profile.bandWidth,
    profile.bandHeight,
    config.colors.symbolPanelLight,
    config.requestedLayer + 1
  )

  for key, position in pairs(borderPositions) do
    borderFrames[borderIndex] = BarCode.Render.CreateModuleFrame(
      panel,
      "BarCode_Border_" .. tostring(borderIndex),
      profile.quietLeft + ((position.column - 1) * profile.pitch),
      profile.quietTop + ((position.row - 1) * profile.pitch),
      profile.pitch,
      config.colors.moduleDark,
      config.requestedLayer + 2
    )
    borderIndex = borderIndex + 1
  end

  for rowIndex = 2, profile.gridRows - 1 do
    for colIndex = 2, profile.gridColumns - 1 do
      dataFrames[dataIndex] = BarCode.Render.CreateModuleFrame(
        panel,
        "BarCode_Data_" .. tostring(dataIndex),
        profile.quietLeft + ((colIndex - 1) * profile.pitch),
        profile.quietTop + ((rowIndex - 1) * profile.pitch),
        profile.pitch,
        config.colors.moduleDark,
        config.requestedLayer + 3
      )
      dataFrames[dataIndex]:SetVisible(false)
      lastBits[dataIndex] = 0
      dataIndex = dataIndex + 1
    end
  end

  return {
    profile = profile,
    band = band,
    panel = panel,
    borderFrames = borderFrames,
    dataFrames = dataFrames,
    lastBits = lastBits,
    lastFrameBytes = nil,
    currentBandWidth = reservedBandWidth
  }
end

function BarCode.Render.ApplyReservedBandWidth(renderState, clientWidth)
  local width = clientWidth or 0

  if width < renderState.profile.bandWidth then
    width = renderState.profile.bandWidth
  end

  if width ~= renderState.currentBandWidth then
    renderState.band:SetWidth(width)
    renderState.currentBandWidth = width
  end
end

function BarCode.Render.UpdateLiveBand(renderState, snapshot, frameBytes)
  BarCode.Render.ApplyReservedBandWidth(renderState, snapshot.clientWidth)

  if BarCode.Render.FrameBytesEqual(renderState.lastFrameBytes, frameBytes) then
    return {
      changedCount = 0,
      bitCount = #renderState.dataFrames,
      bandWidth = renderState.currentBandWidth,
      bytesUnchanged = true
    }
  end

  local bits = BarCode.Pack.BytesToBits(frameBytes)
  local changedCount = 0
  local index

  for index = 1, #renderState.dataFrames do
    local bit = bits[index] or 0
    if renderState.lastBits[index] ~= bit then
      renderState.dataFrames[index]:SetVisible(bit == 1)
      renderState.lastBits[index] = bit
      changedCount = changedCount + 1
    end
  end

  renderState.lastFrameBytes = BarCode.Render.CopyFrameBytes(frameBytes)

  return {
    changedCount = changedCount,
    bitCount = #renderState.dataFrames,
    bandWidth = renderState.currentBandWidth,
    bytesUnchanged = false
  }
end

-- end-of-script marker comment
