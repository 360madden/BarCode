-- script name: RIFT/Bootstrap.lua
-- version: 0.1.0
-- purpose: Initializes the BarCode RIFT integration and renders the static protocol band at startup.
-- dependencies: Core/Config.lua, Core/Protocol.lua, Core/Pack.lua, RIFT/Diagnostics.lua, RIFT/Render.lua
-- important assumptions: Uses Event.Addon.Startup.End and documented frame/layout APIs. The exact highest-safe strata remains unverified.
-- protocol version: BC-Strip/1
-- framework module role: RIFT integration bootstrap
-- character count note: Character count not precomputed; measure with tooling if needed.

BarCode = BarCode or {}
BarCode.Bootstrap = {}

local addonIdentifier = BarCode.Config.addonIdentifier

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

  local renderState = BarCode.Render.DrawStaticBand(root)
  BarCode.Bootstrap.state = {
    context = context,
    root = root,
    render = renderState
  }

  BarCode.Diagnostics.LogLoaded()
  BarCode.Diagnostics.Log("Initialized static BC-Strip/1 spike.")
  BarCode.Diagnostics.Log("Root strata options: " .. BarCode.Diagnostics.DescribeStrataList(root))
  BarCode.Diagnostics.Log("Rendered profile: " .. renderState.plan.profile.id)
end

function BarCode.Bootstrap.OnStartup(_, startedAddonIdentifier)
  if startedAddonIdentifier ~= addonIdentifier then
    return
  end

  if BarCode.Config.showOnStartup then
    BarCode.Bootstrap.Initialize()
  end
end

Command.Event.Attach(
  Event.Addon.Startup.End,
  BarCode.Bootstrap.OnStartup,
  "BarCode.Bootstrap.OnStartup"
)

-- end-of-script marker comment
