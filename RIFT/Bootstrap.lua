-- script name: RIFT/Bootstrap.lua
-- version: 0.2.0
-- purpose: Initializes the BarCode RIFT integration, schedules live player telemetry frames, and updates the protocol band.
-- dependencies: Core/Config.lua, Core/Gather.lua, Core/Scheduler.lua, Core/Protocol.lua, Core/Pack.lua, RIFT/Diagnostics.lua, RIFT/Render.lua
-- important assumptions: Uses Event.Addon.Load.End, Event.System.Update.Begin, and Event.Unit.Castbar. Exact highest-safe strata remains unverified.
-- protocol version: BC-Strip/1
-- framework module role: RIFT integration bootstrap
-- character count note: Character count not precomputed; measure with tooling if needed.

BarCode = BarCode or {}
BarCode.Bootstrap = {}

local addonIdentifier = BarCode.Config.addonIdentifier

function BarCode.Bootstrap.GetRealtimeNow()
  if Inspect ~= nil and Inspect.Time ~= nil and Inspect.Time.Real ~= nil then
    return Inspect.Time.Real()
  end

  return 0
end

function BarCode.Bootstrap.GetRefreshInterval()
  local state = BarCode.Bootstrap.state
  if state ~= nil and state.currentCastActive then
    return BarCode.Config.refreshIntervalCastingSeconds
  end

  return BarCode.Config.refreshIntervalSeconds
end

function BarCode.Bootstrap.RefreshTelemetry(forceRefresh, refreshReason)
  local state = BarCode.Bootstrap.state
  local now = BarCode.Bootstrap.GetRealtimeNow()
  local refreshInterval = BarCode.Bootstrap.GetRefreshInterval()

  if state == nil then
    return
  end

  if not forceRefresh and now > 0 and (now - (state.lastRefreshAt or 0)) < refreshInterval then
    return
  end

  local snapshot = BarCode.Gather.BuildPlayerSnapshot()
  local scheduleEntry = BarCode.Scheduler.NextFrame(state.scheduler)
  local frameBytes, frameMeta = BarCode.Protocol.BuildLiveFrameBytes(snapshot, scheduleEntry)
  local renderMetrics = BarCode.Render.UpdateLiveBand(state.render, snapshot, frameBytes)

  state.lastRefreshAt = now
  state.currentCastActive = snapshot.castActive and true or false
  state.lastSnapshot = snapshot
  state.lastFrameMeta = frameMeta
  state.lastRenderMetrics = renderMetrics

  if snapshot.debugProbe ~= nil then
    BarCode.Diagnostics.LogGatherProbe(snapshot.debugProbe, refreshReason)
  end
end

function BarCode.Bootstrap.SafeRefreshTelemetry(forceRefresh, refreshReason)
  local state = BarCode.Bootstrap.state
  local ok, failureMessage = pcall(function()
    BarCode.Bootstrap.RefreshTelemetry(forceRefresh, refreshReason)
  end)

  if ok then
    if state ~= nil then
      state.lastRefreshError = nil
    end
    return
  end

  if state ~= nil and state.lastRefreshError == failureMessage then
    return
  end

  if state ~= nil then
    state.lastRefreshError = failureMessage
  end

  BarCode.Diagnostics.Log("Telemetry refresh failed: " .. tostring(failureMessage))
end

function BarCode.Bootstrap.Initialize()
  if BarCode.Bootstrap.state ~= nil then
    return
  end

  local context = UI.CreateContext("BarCodeContext")
  local root = UI.CreateFrame("Frame", "BarCodeRoot", context)
  root:SetAllPoints(context)
  root:SetVisible(true)
  root:SetLayer(BarCode.Config.requestedLayer)

  if BarCode.Config.requestedStrata ~= nil then
    root:SetStrata(BarCode.Config.requestedStrata)
  end

  local renderState = BarCode.Render.InitializeLiveBand(root)
  BarCode.Bootstrap.state = {
    context = context,
    root = root,
    render = renderState,
    scheduler = BarCode.Scheduler.NewState(),
    lastRefreshAt = 0,
    currentCastActive = false,
    lastSnapshot = nil,
    lastFrameMeta = nil,
    lastRenderMetrics = nil,
    lastRefreshError = nil
  }

  BarCode.Diagnostics.LogLoaded()
  BarCode.Diagnostics.Log("Initialized live schema-2 PlayerCoreHot telemetry.")
  BarCode.Diagnostics.Log("Root strata options: " .. BarCode.Diagnostics.DescribeStrataList(root))
  BarCode.Diagnostics.Log("Rendered profile: " .. renderState.profile.id)
  BarCode.Diagnostics.Log("Refresh cadence: " .. tostring(BarCode.Config.refreshIntervalSeconds) .. "s base / " .. tostring(BarCode.Config.refreshIntervalCastingSeconds) .. "s casting.")

  BarCode.Bootstrap.SafeRefreshTelemetry(true, "initialize")
end

function BarCode.Bootstrap.OnLoadEnd(_, loadedAddonIdentifier)
  if loadedAddonIdentifier ~= addonIdentifier then
    return
  end

  if BarCode.Config.showOnStartup then
    BarCode.Diagnostics.Log("Load event received for v" .. BarCode.Config.addonVersion .. ".")

    local ok, failureMessage = pcall(BarCode.Bootstrap.Initialize)
    if not ok then
      BarCode.Diagnostics.Log("Initialization failed: " .. tostring(failureMessage))
    end
  end
end

function BarCode.Bootstrap.OnUpdateBegin()
  if BarCode.Bootstrap.state == nil then
    return
  end

  BarCode.Bootstrap.SafeRefreshTelemetry(false, "update")
end

function BarCode.Bootstrap.OnCastbarChanged()
  if BarCode.Bootstrap.state == nil then
    return
  end

  BarCode.Bootstrap.state.lastRefreshAt = 0
  BarCode.Bootstrap.SafeRefreshTelemetry(true, "castbar")
end

Command.Event.Attach(
  Event.Addon.Load.End,
  BarCode.Bootstrap.OnLoadEnd,
  "BarCode.Bootstrap.OnLoadEnd"
)

Command.Event.Attach(
  Event.System.Update.Begin,
  BarCode.Bootstrap.OnUpdateBegin,
  "BarCode.Bootstrap.OnUpdateBegin"
)

Command.Event.Attach(
  Event.Unit.Castbar,
  BarCode.Bootstrap.OnCastbarChanged,
  "BarCode.Bootstrap.OnCastbarChanged"
)

-- end-of-script marker comment
