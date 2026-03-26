-- script name: RIFT/Render.lua
-- version: 0.1.0
-- purpose: Creates and draws the static BC-Strip/1 protocol band for the phase 1 RIFT spike.
-- dependencies: Core/Config.lua, Core/Protocol.lua, Core/Pack.lua, RIFT/Diagnostics.lua
-- important assumptions: Assumes Frame:SetPoint and Frame:SetBackgroundColor behave per current documented RIFT UI API.
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

function BarCode.Render.BuildStaticPlan()
  local config = BarCode.Config
  local profile = config.GetActiveProfile()
  local frameBytes = BarCode.Protocol.BuildStaticFrameBytes()
  local matrix = BarCode.Protocol.BuildModuleMatrix(profile, frameBytes)
  local cells = {}
  local rowIndex
  local colIndex
  local cellIndex = 1

  for rowIndex = 1, profile.gridRows do
    for colIndex = 1, profile.gridColumns do
      if matrix[rowIndex][colIndex] == 1 then
        cells[cellIndex] = {
          x = profile.quietLeft + ((colIndex - 1) * profile.pitch),
          y = profile.quietTop + ((rowIndex - 1) * profile.pitch),
          width = profile.pitch,
          height = profile.pitch
        }
        cellIndex = cellIndex + 1
      end
    end
  end

  return {
    profile = profile,
    frameBytes = frameBytes,
    cells = cells
  }
end

function BarCode.Render.DrawStaticBand(rootFrame)
  local config = BarCode.Config
  local plan = BarCode.Render.BuildStaticPlan()
  local profile = plan.profile
  local cells = plan.cells
  local band = BarCode.Render.CreateBlock(
    rootFrame,
    "BarCode_Band",
    0,
    0,
    profile.bandWidth,
    profile.bandHeight,
    config.colors.bandLight,
    config.requestedLayer
  )
  local index

  for index = 1, #cells do
    local cell = cells[index]
    BarCode.Render.CreateBlock(
      band,
      "BarCode_Cell_" .. tostring(index),
      cell.x,
      cell.y,
      cell.width,
      cell.height,
      config.colors.moduleDark,
      config.requestedLayer + 1
    )
  end

  return {
    band = band,
    plan = plan
  }
end

-- end-of-script marker comment
