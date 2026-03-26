-- script name: Core/Scheduler.lua
-- version: 0.2.0
-- purpose: Provides deterministic page and sequence scheduling for live telemetry frames.
-- dependencies: Core/Config.lua
-- important assumptions: This pass transmits the hot player page only; cold-page rotation is reserved for the next pass.
-- protocol version: BC-Strip/1
-- framework module role: Core frame scheduling
-- character count note: Character count not precomputed; measure with tooling if needed.

BarCode = BarCode or {}
BarCode.Scheduler = {}

function BarCode.Scheduler.NewState()
  return {
    sequence = 0,
    frameIndex = 0
  }
end

function BarCode.Scheduler.NextFrame(state)
  local schedulerState = state or BarCode.Scheduler.NewState()
  local sequence = schedulerState.sequence or 0
  local entry = {
    pageId = BarCode.Config.pageIds.playerCoreHot,
    sequence = sequence
  }

  schedulerState.sequence = math.fmod(sequence + 1, 0x100)
  schedulerState.frameIndex = (schedulerState.frameIndex or 0) + 1

  return entry
end

-- end-of-script marker comment
