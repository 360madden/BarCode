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
    static Session := {}

    static GetLockedGeometry() {
        return IsObject(BC_State.LockedGeometry) && BC_State.LockedGeometry.HasOwnProp("Pitch")
            ? BC_State.LockedGeometry
            : ""
    }

    static ResetLiveOutputs() {
        BC_State.Latest := {}
        BC_State.Session := BC_State.BuildEmptySession()
        BC_State.WriteSnapshot()
    }

    static Update(validationResult, context := "", persistSnapshot := false) {
        details := validationResult.Details
        transport := details.HasOwnProp("Transport") ? details.Transport : {}
        hotPage := details.HasOwnProp("HotPage") ? details.HotPage : {}
        image := IsObject(context) && context.HasOwnProp("Image") ? context.Image : {}
        timings := IsObject(context) && context.HasOwnProp("Timings") ? context.Timings : {}
        sampleIndex := IsObject(context) && context.HasOwnProp("SampleIndex") ? context.SampleIndex : ""
        sequence := transport.HasOwnProp("Sequence") ? transport.Sequence : ""
        sessionStats := BC_State.UpdateSessionStats(validationResult, sampleIndex, sequence)

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
            Sequence: sequence,
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
            SampleIndex: sampleIndex,
            SessionStartedUtc: sessionStats.SessionStartedUtc,
            SessionSampleCount: sessionStats.SampleCount,
            SessionAcceptedCount: sessionStats.AcceptedCount,
            SessionRejectedCount: sessionStats.RejectedCount,
            AcceptedStreak: sessionStats.AcceptedStreak,
            RejectedStreak: sessionStats.RejectedStreak,
            LastAcceptedTimestampUtc: sessionStats.LastAcceptedTimestampUtc,
            LastRejectedTimestampUtc: sessionStats.LastRejectedTimestampUtc,
            LastAcceptedSequence: sessionStats.LastAcceptedSequence,
            SequenceAdvance: sessionStats.SequenceAdvance,
            SequenceChanged: sessionStats.SequenceChanged,
            FreshFrame: sessionStats.FreshFrame,
            SequenceRepeatedCount: sessionStats.SequenceRepeatedCount,
            SequenceWrapCount: sessionStats.SequenceWrapCount,
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
            sessionStartedUtc: BC_State.GetValue(latest, "SessionStartedUtc", ""),
            sessionSampleCount: BC_State.GetValue(latest, "SessionSampleCount", ""),
            sessionAcceptedCount: BC_State.GetValue(latest, "SessionAcceptedCount", ""),
            sessionRejectedCount: BC_State.GetValue(latest, "SessionRejectedCount", ""),
            acceptedStreak: BC_State.GetValue(latest, "AcceptedStreak", ""),
            rejectedStreak: BC_State.GetValue(latest, "RejectedStreak", ""),
            lastAcceptedTimestampUtc: BC_State.GetValue(latest, "LastAcceptedTimestampUtc", ""),
            lastRejectedTimestampUtc: BC_State.GetValue(latest, "LastRejectedTimestampUtc", ""),
            lastAcceptedSequence: BC_State.GetValue(latest, "LastAcceptedSequence", ""),
            sequenceAdvance: BC_State.GetValue(latest, "SequenceAdvance", ""),
            sequenceChanged: BC_State.GetValue(latest, "SequenceChanged", false),
            freshFrame: BC_State.GetValue(latest, "FreshFrame", false),
            sequenceRepeatedCount: BC_State.GetValue(latest, "SequenceRepeatedCount", ""),
            sequenceWrapCount: BC_State.GetValue(latest, "SequenceWrapCount", ""),
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
        fields.Push(BC_State.JsonStringField("sessionStartedUtc", snapshot.sessionStartedUtc))
        fields.Push(BC_State.JsonNumberField("sessionSampleCount", snapshot.sessionSampleCount))
        fields.Push(BC_State.JsonNumberField("sessionAcceptedCount", snapshot.sessionAcceptedCount))
        fields.Push(BC_State.JsonNumberField("sessionRejectedCount", snapshot.sessionRejectedCount))
        fields.Push(BC_State.JsonNumberField("acceptedStreak", snapshot.acceptedStreak))
        fields.Push(BC_State.JsonNumberField("rejectedStreak", snapshot.rejectedStreak))
        fields.Push(BC_State.JsonStringField("lastAcceptedTimestampUtc", snapshot.lastAcceptedTimestampUtc))
        fields.Push(BC_State.JsonStringField("lastRejectedTimestampUtc", snapshot.lastRejectedTimestampUtc))
        fields.Push(BC_State.JsonNumberField("lastAcceptedSequence", snapshot.lastAcceptedSequence))
        fields.Push(BC_State.JsonNumberField("sequenceAdvance", snapshot.sequenceAdvance))
        fields.Push(BC_State.JsonBoolField("sequenceChanged", snapshot.sequenceChanged))
        fields.Push(BC_State.JsonBoolField("freshFrame", snapshot.freshFrame))
        fields.Push(BC_State.JsonNumberField("sequenceRepeatedCount", snapshot.sequenceRepeatedCount))
        fields.Push(BC_State.JsonNumberField("sequenceWrapCount", snapshot.sequenceWrapCount))
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
        lines.Push("SessionStartedUtc: " snapshot.sessionStartedUtc)
        lines.Push("SessionCounts: " BC_State.NumberText(snapshot.sessionSampleCount) "/" BC_State.NumberText(snapshot.sessionAcceptedCount) "/" BC_State.NumberText(snapshot.sessionRejectedCount))
        lines.Push("AcceptedStreak: " BC_State.NumberText(snapshot.acceptedStreak))
        lines.Push("RejectedStreak: " BC_State.NumberText(snapshot.rejectedStreak))
        lines.Push("LastAcceptedTimestampUtc: " snapshot.lastAcceptedTimestampUtc)
        lines.Push("LastRejectedTimestampUtc: " snapshot.lastRejectedTimestampUtc)
        lines.Push("LastAcceptedSequence: " BC_State.NumberText(snapshot.lastAcceptedSequence))
        lines.Push("SequenceAdvance: " BC_State.NumberText(snapshot.sequenceAdvance))
        lines.Push("SequenceChanged: " BC_State.BoolText(snapshot.sequenceChanged))
        lines.Push("FreshFrame: " BC_State.BoolText(snapshot.freshFrame))
        lines.Push("SequenceRepeatedCount: " BC_State.NumberText(snapshot.sequenceRepeatedCount))
        lines.Push("SequenceWrapCount: " BC_State.NumberText(snapshot.sequenceWrapCount))
        lines.Push("WindowTitle: " snapshot.windowTitle)
        lines.Push("ProcessName: " snapshot.processName)
        return BC_Debug.Join(lines, "`r`n")
    }

    static BuildEmptySession() {
        return {
            SessionStartedUtc: A_NowUTC,
            SampleCount: 0,
            AcceptedCount: 0,
            RejectedCount: 0,
            AcceptedStreak: 0,
            RejectedStreak: 0,
            LastAcceptedTimestampUtc: "",
            LastRejectedTimestampUtc: "",
            LastAcceptedSequence: "",
            SequenceAdvance: "",
            SequenceChanged: false,
            FreshFrame: false,
            SequenceRepeatedCount: 0,
            SequenceWrapCount: 0
        }
    }

    static EnsureSession() {
        if (!IsObject(BC_State.Session) || !BC_State.Session.HasOwnProp("SessionStartedUtc")) {
            BC_State.Session := BC_State.BuildEmptySession()
        }
        return BC_State.Session
    }

    static UpdateSessionStats(validationResult, sampleIndex, sequence) {
        session := BC_State.EnsureSession()

        if (sampleIndex = "") {
            return session
        }

        session.SampleCount := sampleIndex
        session.SequenceAdvance := ""
        session.SequenceChanged := false
        session.FreshFrame := false

        if (validationResult.IsAccepted) {
            session.AcceptedCount += 1
            session.AcceptedStreak += 1
            session.RejectedStreak := 0
            session.LastAcceptedTimestampUtc := A_NowUTC

            if (sequence != "") {
                if (session.LastAcceptedSequence != "") {
                    sequenceAdvance := sequence - session.LastAcceptedSequence
                    if (sequenceAdvance < 0) {
                        sequenceAdvance += 256
                    }
                    session.SequenceAdvance := sequenceAdvance
                    session.SequenceChanged := sequenceAdvance != 0
                    session.FreshFrame := session.SequenceChanged
                    if (sequenceAdvance = 0) {
                        session.SequenceRepeatedCount += 1
                    }
                    if (sequence < session.LastAcceptedSequence) {
                        session.SequenceWrapCount += 1
                    }
                } else {
                    session.SequenceAdvance := ""
                    session.SequenceChanged := true
                    session.FreshFrame := true
                }

                session.LastAcceptedSequence := sequence
            }
        } else {
            session.RejectedCount += 1
            session.RejectedStreak += 1
            session.AcceptedStreak := 0
            session.LastRejectedTimestampUtc := A_NowUTC
        }

        return session
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
