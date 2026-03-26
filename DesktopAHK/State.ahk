/*
script name: DesktopAHK/State.ahk
version: 0.3.0
purpose: Tracks the latest decoded frame and emits app-facing live state snapshots for local consumers.
dependencies: DesktopAHK/Config.ahk, DesktopAHK/Debug.ahk, DesktopAHK/Validate.ahk
important assumptions: Persists a flat latest-state snapshot for downstream tools rather than serializing the full nested validation object.
protocol version: BC-Strip/1
framework module role: App-facing state
character count note: Character count not precomputed; measure with tooling if needed.
*/

class BC_State {
    static Latest := {}
    static LockedGeometry := {}

    static GetLockedGeometry() {
        return IsObject(BC_State.LockedGeometry) && BC_State.LockedGeometry.HasOwnProp("Pitch")
            ? BC_State.LockedGeometry
            : ""
    }

    static ResetLiveOutputs() {
        BC_State.Latest := {}
        BC_State.WriteSnapshot()
    }

    static Update(validationResult, context := "", persistSnapshot := false) {
        details := validationResult.Details
        transport := details.HasOwnProp("Transport") ? details.Transport : {}
        hotPage := details.HasOwnProp("HotPage") ? details.HotPage : {}
        image := IsObject(context) && context.HasOwnProp("Image") ? context.Image : {}
        timings := IsObject(context) && context.HasOwnProp("Timings") ? context.Timings : {}

        if (validationResult.IsAccepted && details.HasOwnProp("Pitch") && details.Pitch > 0) {
            BC_State.LockedGeometry := {
                OriginX: details.OriginX,
                OriginY: details.OriginY,
                Pitch: details.Pitch
            }
        }

        latest := {
            TimestampUtc: A_NowUTC,
            Accepted: validationResult.IsAccepted,
            Reason: validationResult.Reason,
            Confidence: validationResult.Confidence,
            Sequence: transport.HasOwnProp("Sequence") ? transport.Sequence : "",
            PageId: transport.HasOwnProp("PageId") ? transport.PageId : "",
            PayloadUsedLength: transport.HasOwnProp("PayloadUsedLength") ? transport.PayloadUsedLength : "",
            SampleMask: hotPage.HasOwnProp("SampleMask") ? hotPage.SampleMask : "",
            StateFlags: hotPage.HasOwnProp("StateFlags") ? hotPage.StateFlags : "",
            ResourceKindId: hotPage.HasOwnProp("ResourceKindId") ? hotPage.ResourceKindId : "",
            ResourceKindName: hotPage.HasOwnProp("ResourceKindId") ? BC_State.ResourceKindName(hotPage.ResourceKindId) : "",
            HealthCurrent: hotPage.HasOwnProp("HealthCurrent") ? hotPage.HealthCurrent : "",
            HealthMax: hotPage.HasOwnProp("HealthMax") ? hotPage.HealthMax : "",
            ResourceCurrent: hotPage.HasOwnProp("ResourceCurrent") ? hotPage.ResourceCurrent : "",
            ResourceMax: hotPage.HasOwnProp("ResourceMax") ? hotPage.ResourceMax : "",
            CastFlags: hotPage.HasOwnProp("CastFlags") ? hotPage.CastFlags : "",
            CastProgressQ15: hotPage.HasOwnProp("CastProgressQ15") ? hotPage.CastProgressQ15 : "",
            Level: hotPage.HasOwnProp("Level") ? hotPage.Level : "",
            CallingCode: hotPage.HasOwnProp("CallingCode") ? hotPage.CallingCode : "",
            CallingName: hotPage.HasOwnProp("CallingCode") ? BC_State.CallingName(hotPage.CallingCode) : "",
            RoleCode: hotPage.HasOwnProp("RoleCode") ? hotPage.RoleCode : "",
            RoleName: hotPage.HasOwnProp("RoleCode") ? BC_State.RoleName(hotPage.RoleCode) : "",
            SearchMode: details.HasOwnProp("SearchMode") ? details.SearchMode : "",
            BorderErrors: details.HasOwnProp("BorderErrors") ? details.BorderErrors : "",
            OriginX: details.HasOwnProp("OriginX") ? details.OriginX : "",
            OriginY: details.HasOwnProp("OriginY") ? details.OriginY : "",
            Pitch: details.HasOwnProp("Pitch") ? details.Pitch : "",
            BandWidth: details.HasOwnProp("BandWidth") ? details.BandWidth : "",
            BandHeight: details.HasOwnProp("BandHeight") ? details.BandHeight : "",
            CaptureSource: IsObject(image) && image.HasOwnProp("SourceKind") ? image.SourceKind : "",
            CaptureAttemptsText: IsObject(context) && context.HasOwnProp("CaptureAttempts") ? BC_Debug.Join(context.CaptureAttempts, ",") : "",
            CaptureMs: IsObject(timings) && timings.HasOwnProp("CaptureMs") ? timings.CaptureMs : "",
            PipelineMs: IsObject(timings) && timings.HasOwnProp("PipelineMs") ? timings.PipelineMs : "",
            AttemptCount: IsObject(timings) && timings.HasOwnProp("AttemptCount") ? timings.AttemptCount : "",
            SampleIndex: IsObject(context) && context.HasOwnProp("SampleIndex") ? context.SampleIndex : "",
            WindowTitle: BC_State.ResolveWindowTitle(context, image),
            ProcessName: BC_State.ResolveProcessName(context, image),
            Details: details
        }

        BC_State.Latest := latest
        if (persistSnapshot) {
            BC_State.WriteSnapshot()
        }
        return BC_State.Latest
    }

    static WriteSnapshot() {
        snapshot := BC_State.BuildSnapshot()
        BC_Debug.WriteText(BC_Config.LiveStateJsonPath, BC_State.BuildSnapshotJson(snapshot))
        BC_Debug.WriteText(BC_Config.LiveStateTextPath, BC_State.BuildSnapshotText(snapshot))
    }

    static BuildSnapshot() {
        latest := BC_State.Latest
        return {
            timestampUtc: BC_State.GetValue(latest, "TimestampUtc", ""),
            accepted: BC_State.GetValue(latest, "Accepted", false),
            reason: BC_State.GetValue(latest, "Reason", ""),
            confidence: BC_State.GetValue(latest, "Confidence", ""),
            sequence: BC_State.GetValue(latest, "Sequence", ""),
            pageId: BC_State.GetValue(latest, "PageId", ""),
            payloadUsedLength: BC_State.GetValue(latest, "PayloadUsedLength", ""),
            sampleMask: BC_State.GetValue(latest, "SampleMask", ""),
            stateFlags: BC_State.GetValue(latest, "StateFlags", ""),
            resourceKindId: BC_State.GetValue(latest, "ResourceKindId", ""),
            resourceKindName: BC_State.GetValue(latest, "ResourceKindName", ""),
            healthCurrent: BC_State.GetValue(latest, "HealthCurrent", ""),
            healthMax: BC_State.GetValue(latest, "HealthMax", ""),
            resourceCurrent: BC_State.GetValue(latest, "ResourceCurrent", ""),
            resourceMax: BC_State.GetValue(latest, "ResourceMax", ""),
            castFlags: BC_State.GetValue(latest, "CastFlags", ""),
            castProgressQ15: BC_State.GetValue(latest, "CastProgressQ15", ""),
            level: BC_State.GetValue(latest, "Level", ""),
            callingCode: BC_State.GetValue(latest, "CallingCode", ""),
            callingName: BC_State.GetValue(latest, "CallingName", ""),
            roleCode: BC_State.GetValue(latest, "RoleCode", ""),
            roleName: BC_State.GetValue(latest, "RoleName", ""),
            searchMode: BC_State.GetValue(latest, "SearchMode", ""),
            borderErrors: BC_State.GetValue(latest, "BorderErrors", ""),
            originX: BC_State.GetValue(latest, "OriginX", ""),
            originY: BC_State.GetValue(latest, "OriginY", ""),
            pitch: BC_State.GetValue(latest, "Pitch", ""),
            bandWidth: BC_State.GetValue(latest, "BandWidth", ""),
            bandHeight: BC_State.GetValue(latest, "BandHeight", ""),
            captureSource: BC_State.GetValue(latest, "CaptureSource", ""),
            captureAttempts: BC_State.GetValue(latest, "CaptureAttemptsText", ""),
            captureMs: BC_State.GetValue(latest, "CaptureMs", ""),
            pipelineMs: BC_State.GetValue(latest, "PipelineMs", ""),
            attemptCount: BC_State.GetValue(latest, "AttemptCount", ""),
            sampleIndex: BC_State.GetValue(latest, "SampleIndex", ""),
            windowTitle: BC_State.GetValue(latest, "WindowTitle", ""),
            processName: BC_State.GetValue(latest, "ProcessName", "")
        }
    }

    static BuildSnapshotJson(snapshot) {
        fields := []
        fields.Push(BC_State.JsonStringField("timestampUtc", snapshot.timestampUtc))
        fields.Push(BC_State.JsonBoolField("accepted", snapshot.accepted))
        fields.Push(BC_State.JsonStringField("reason", snapshot.reason))
        fields.Push(BC_State.JsonNumberField("confidence", snapshot.confidence))
        fields.Push(BC_State.JsonNumberField("sequence", snapshot.sequence))
        fields.Push(BC_State.JsonNumberField("pageId", snapshot.pageId))
        fields.Push(BC_State.JsonNumberField("payloadUsedLength", snapshot.payloadUsedLength))
        fields.Push(BC_State.JsonNumberField("sampleMask", snapshot.sampleMask))
        fields.Push(BC_State.JsonNumberField("stateFlags", snapshot.stateFlags))
        fields.Push(BC_State.JsonNumberField("resourceKindId", snapshot.resourceKindId))
        fields.Push(BC_State.JsonStringField("resourceKindName", snapshot.resourceKindName))
        fields.Push(BC_State.JsonNumberField("healthCurrent", snapshot.healthCurrent))
        fields.Push(BC_State.JsonNumberField("healthMax", snapshot.healthMax))
        fields.Push(BC_State.JsonNumberField("resourceCurrent", snapshot.resourceCurrent))
        fields.Push(BC_State.JsonNumberField("resourceMax", snapshot.resourceMax))
        fields.Push(BC_State.JsonNumberField("castFlags", snapshot.castFlags))
        fields.Push(BC_State.JsonNumberField("castProgressQ15", snapshot.castProgressQ15))
        fields.Push(BC_State.JsonNumberField("level", snapshot.level))
        fields.Push(BC_State.JsonNumberField("callingCode", snapshot.callingCode))
        fields.Push(BC_State.JsonStringField("callingName", snapshot.callingName))
        fields.Push(BC_State.JsonNumberField("roleCode", snapshot.roleCode))
        fields.Push(BC_State.JsonStringField("roleName", snapshot.roleName))
        fields.Push(BC_State.JsonStringField("searchMode", snapshot.searchMode))
        fields.Push(BC_State.JsonNumberField("borderErrors", snapshot.borderErrors))
        fields.Push(BC_State.JsonNumberField("originX", snapshot.originX))
        fields.Push(BC_State.JsonNumberField("originY", snapshot.originY))
        fields.Push(BC_State.JsonNumberField("pitch", snapshot.pitch))
        fields.Push(BC_State.JsonNumberField("bandWidth", snapshot.bandWidth))
        fields.Push(BC_State.JsonNumberField("bandHeight", snapshot.bandHeight))
        fields.Push(BC_State.JsonStringField("captureSource", snapshot.captureSource))
        fields.Push(BC_State.JsonStringField("captureAttempts", snapshot.captureAttempts))
        fields.Push(BC_State.JsonNumberField("captureMs", snapshot.captureMs))
        fields.Push(BC_State.JsonNumberField("pipelineMs", snapshot.pipelineMs))
        fields.Push(BC_State.JsonNumberField("attemptCount", snapshot.attemptCount))
        fields.Push(BC_State.JsonNumberField("sampleIndex", snapshot.sampleIndex))
        fields.Push(BC_State.JsonStringField("windowTitle", snapshot.windowTitle))
        fields.Push(BC_State.JsonStringField("processName", snapshot.processName))
        return "{`r`n  " BC_Debug.Join(fields, ",`r`n  ") "`r`n}"
    }

    static BuildSnapshotText(snapshot) {
        lines := []
        originText := BC_State.NumberText(snapshot.originX) "," BC_State.NumberText(snapshot.originY)
        bandSizeText := BC_State.NumberText(snapshot.bandWidth) "x" BC_State.NumberText(snapshot.bandHeight)
        lines.Push("BarCode live state snapshot")
        lines.Push("TimestampUtc: " snapshot.timestampUtc)
        lines.Push("Accepted: " BC_State.BoolText(snapshot.accepted))
        lines.Push("Reason: " snapshot.reason)
        lines.Push("Confidence: " BC_State.NumberText(snapshot.confidence))
        lines.Push("Sequence: " BC_State.NumberText(snapshot.sequence))
        lines.Push("PageId: " BC_State.NumberText(snapshot.pageId))
        lines.Push("Health: " BC_State.PairText(snapshot.healthCurrent, snapshot.healthMax))
        lines.Push("Resource: " BC_State.PairText(snapshot.resourceCurrent, snapshot.resourceMax))
        lines.Push("ResourceKind: " snapshot.resourceKindName)
        lines.Push("CastProgressQ15: " BC_State.NumberText(snapshot.castProgressQ15))
        lines.Push("Level: " BC_State.NumberText(snapshot.level))
        lines.Push("CallingCode: " BC_State.NumberText(snapshot.callingCode))
        lines.Push("CallingName: " snapshot.callingName)
        lines.Push("RoleCode: " BC_State.NumberText(snapshot.roleCode))
        lines.Push("RoleName: " snapshot.roleName)
        lines.Push("SearchMode: " snapshot.searchMode)
        lines.Push("BorderErrors: " BC_State.NumberText(snapshot.borderErrors))
        lines.Push("Origin: " originText)
        lines.Push("Pitch: " BC_State.NumberText(snapshot.pitch))
        lines.Push("BandSize: " bandSizeText)
        lines.Push("CaptureSource: " snapshot.captureSource)
        lines.Push("CaptureAttempts: " snapshot.captureAttempts)
        lines.Push("CaptureMs: " BC_State.NumberText(snapshot.captureMs))
        lines.Push("PipelineMs: " BC_State.NumberText(snapshot.pipelineMs))
        lines.Push("AttemptCount: " BC_State.NumberText(snapshot.attemptCount))
        lines.Push("SampleIndex: " BC_State.NumberText(snapshot.sampleIndex))
        lines.Push("WindowTitle: " snapshot.windowTitle)
        lines.Push("ProcessName: " snapshot.processName)
        return BC_Debug.Join(lines, "`r`n")
    }

    static ResolveWindowTitle(context, image) {
        if (IsObject(context) && context.HasOwnProp("WindowTitle")) {
            return context.WindowTitle
        }
        if (IsObject(image) && image.HasOwnProp("Hwnd")) {
            try {
                return WinGetTitle("ahk_id " image.Hwnd)
            } catch {
                return ""
            }
        }
        return ""
    }

    static ResolveProcessName(context, image) {
        if (IsObject(context) && context.HasOwnProp("ProcessName")) {
            return context.ProcessName
        }
        if (IsObject(image) && image.HasOwnProp("Hwnd")) {
            try {
                return WinGetProcessName("ahk_id " image.Hwnd)
            } catch {
                return ""
            }
        }
        return ""
    }

    static ResourceKindName(kindId) {
        if (kindId = 1) {
            return "mana"
        }
        if (kindId = 2) {
            return "energy"
        }
        if (kindId = 3) {
            return "charge"
        }
        if (kindId = 4) {
            return "planar"
        }
        return "none"
    }

    static CallingName(code) {
        if (code = 1) {
            return "mage"
        }
        if (code = 2) {
            return "rogue"
        }
        if (code = 3) {
            return "cleric"
        }
        if (code = 4) {
            return "warrior"
        }
        return "unknown"
    }

    static RoleName(code) {
        if (code = 1) {
            return "dps"
        }
        if (code = 2) {
            return "heal"
        }
        if (code = 3) {
            return "tank"
        }
        if (code = 4) {
            return "support"
        }
        return "unknown"
    }

    static JsonStringField(name, value) {
        return Chr(34) name Chr(34) ": " BC_State.JsonStringValue(value)
    }

    static JsonNumberField(name, value) {
        return Chr(34) name Chr(34) ": " BC_State.JsonNumberValue(value)
    }

    static JsonBoolField(name, value) {
        return Chr(34) name Chr(34) ": " (value ? "true" : "false")
    }

    static JsonStringValue(value) {
        text := BC_State.JsonEscape(BC_State.TextValue(value))
        return Chr(34) text Chr(34)
    }

    static JsonNumberValue(value) {
        if (value = "") {
            return "null"
        }
        return "" value
    }

    static JsonEscape(value) {
        text := "" value
        text := StrReplace(text, "\", "\\")
        text := StrReplace(text, Chr(34), "\" Chr(34))
        text := StrReplace(text, "`r", "\r")
        text := StrReplace(text, "`n", "\n")
        text := StrReplace(text, "`t", "\t")
        return text
    }

    static BoolText(value) {
        return value ? "true" : "false"
    }

    static PairText(left, right) {
        return BC_State.NumberText(left) "/" BC_State.NumberText(right)
    }

    static NumberText(value) {
        return value = "" ? "" : ("" value)
    }

    static TextValue(value) {
        return value = "" ? "" : ("" value)
    }

    static GetValue(map, key, defaultValue := "") {
        if (IsObject(map) && map.HasOwnProp(key)) {
            return map.%key%
        }
        return defaultValue
    }
}

; end-of-script marker comment
