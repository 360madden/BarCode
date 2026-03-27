/*
script name: DesktopAHK/State.ahk
version: 0.3.4
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
    static LockedGeometryLoaded := false
    static Session := {}
    static History := []

    static GetLockedGeometry() {
        BC_State.EnsureLockedGeometryLoaded()
        return IsObject(BC_State.LockedGeometry) && BC_State.LockedGeometry.HasOwnProp("Pitch")
            ? BC_State.LockedGeometry
            : ""
    }

    static GetLockedGeometryForClient(client := "") {
        geometry := BC_State.GetLockedGeometry()
        if !IsObject(geometry) {
            return ""
        }

        if !IsObject(client) || !client.HasOwnProp("width") || !client.HasOwnProp("height") {
            return geometry
        }

        if (geometry.ClientWidth = "" || geometry.ClientHeight = "") {
            return geometry
        }

        return (geometry.ClientWidth = client.width && geometry.ClientHeight = client.height)
            ? geometry
            : ""
    }

    static GetLockedGeometryForImage(image := "") {
        if !IsObject(image) || !image.HasOwnProp("ClientRect") {
            return BC_State.GetLockedGeometry()
        }

        return BC_State.GetLockedGeometryForClient(image.ClientRect)
    }

    static ResetLiveOutputs() {
        BC_State.Latest := {}
        BC_State.Session := BC_State.BuildEmptySession()
        BC_State.History := []
        BC_State.DeleteIfPresent(BC_Config.LiveHistoryJsonPath)
        BC_State.DeleteIfPresent(BC_Config.LiveHistoryJsonlPath)
        BC_State.DeleteIfPresent(BC_Config.LiveSummaryJsonPath)
        BC_State.DeleteIfPresent(BC_Config.LiveSummaryTextPath)
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

        if (validationResult.IsAccepted && details.HasOwnProp("Pitch") && details.Pitch > 0 && BC_State.ShouldUpdateLockedGeometry(image)) {
            BC_State.LockedGeometry := {
                OriginX: details.OriginX,
                OriginY: details.OriginY,
                Pitch: details.Pitch,
                ClientWidth: IsObject(image) && image.HasOwnProp("ClientRect") ? image.ClientRect.width : "",
                ClientHeight: IsObject(image) && image.HasOwnProp("ClientRect") ? image.ClientRect.height : ""
            }
            BC_State.PersistLockedGeometry()
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
            PlayerResourceKindId: hotPage.HasOwnProp("PlayerResourceKindId") ? hotPage.PlayerResourceKindId : "",
            PlayerResourceKindName: hotPage.HasOwnProp("PlayerResourceKindId") ? BC_State.ResourceKindName(hotPage.PlayerResourceKindId) : "",
            PlayerHealthCurrent: hotPage.HasOwnProp("PlayerHealthCurrent") ? hotPage.PlayerHealthCurrent : "",
            PlayerHealthMax: hotPage.HasOwnProp("PlayerHealthMax") ? hotPage.PlayerHealthMax : "",
            PlayerResourceCurrent: hotPage.HasOwnProp("PlayerResourceCurrent") ? hotPage.PlayerResourceCurrent : "",
            PlayerResourceMax: hotPage.HasOwnProp("PlayerResourceMax") ? hotPage.PlayerResourceMax : "",
            PlayerCastFlags: hotPage.HasOwnProp("PlayerCastFlags") ? hotPage.PlayerCastFlags : "",
            PlayerCastProgressQ15: hotPage.HasOwnProp("PlayerCastProgressQ15") ? hotPage.PlayerCastProgressQ15 : "",
            PlayerLevel: hotPage.HasOwnProp("PlayerLevel") ? hotPage.PlayerLevel : "",
            PlayerCallingCode: hotPage.HasOwnProp("PlayerCallingCode") ? hotPage.PlayerCallingCode : "",
            PlayerCallingName: hotPage.HasOwnProp("PlayerCallingCode") ? BC_State.CallingName(hotPage.PlayerCallingCode) : "",
            PlayerRoleCode: hotPage.HasOwnProp("PlayerRoleCode") ? hotPage.PlayerRoleCode : "",
            PlayerRoleName: hotPage.HasOwnProp("PlayerRoleCode") ? BC_State.RoleName(hotPage.PlayerRoleCode) : "",
            PlayerPowerAttack: hotPage.HasOwnProp("PlayerPowerAttack") ? hotPage.PlayerPowerAttack : "",
            PlayerCritAttack: hotPage.HasOwnProp("PlayerCritAttack") ? hotPage.PlayerCritAttack : "",
            PlayerPowerSpell: hotPage.HasOwnProp("PlayerPowerSpell") ? hotPage.PlayerPowerSpell : "",
            PlayerCritSpell: hotPage.HasOwnProp("PlayerCritSpell") ? hotPage.PlayerCritSpell : "",
            PlayerCritPower: hotPage.HasOwnProp("PlayerCritPower") ? hotPage.PlayerCritPower : "",
            PlayerHit: hotPage.HasOwnProp("PlayerHit") ? hotPage.PlayerHit : "",
            TargetResourceKindId: hotPage.HasOwnProp("TargetResourceKindId") ? hotPage.TargetResourceKindId : "",
            TargetResourceKindName: hotPage.HasOwnProp("TargetResourceKindId") ? BC_State.ResourceKindName(hotPage.TargetResourceKindId) : "",
            TargetHealthCurrent: hotPage.HasOwnProp("TargetHealthCurrent") ? hotPage.TargetHealthCurrent : "",
            TargetHealthMax: hotPage.HasOwnProp("TargetHealthMax") ? hotPage.TargetHealthMax : "",
            TargetResourceCurrent: hotPage.HasOwnProp("TargetResourceCurrent") ? hotPage.TargetResourceCurrent : "",
            TargetResourceMax: hotPage.HasOwnProp("TargetResourceMax") ? hotPage.TargetResourceMax : "",
            TargetLevel: hotPage.HasOwnProp("TargetLevel") ? hotPage.TargetLevel : "",
            TargetFlags: hotPage.HasOwnProp("TargetFlags") ? hotPage.TargetFlags : "",
            PlayerDamageEstimate: hotPage.HasOwnProp("PlayerDamageEstimate") ? hotPage.PlayerDamageEstimate : "",
            TargetDamageEstimate: hotPage.HasOwnProp("TargetDamageEstimate") ? hotPage.TargetDamageEstimate : "",
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
        BC_Debug.WriteText(BC_Config.LiveStateJsonPath, BC_State.BuildSnapshotJson(snapshot, true))
        BC_Debug.WriteText(BC_Config.LiveStateTextPath, BC_State.BuildSnapshotText(snapshot))
        BC_Debug.WriteText(BC_Config.LiveSummaryJsonPath, BC_State.BuildOperatorSummaryJson(snapshot, true))
        BC_Debug.WriteText(BC_Config.LiveSummaryTextPath, BC_State.BuildOperatorSummaryText(snapshot))
        if (snapshot.timestampUtc != "") {
            BC_State.AppendHistorySnapshot(snapshot)
        }
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
            playerResourceKindId: BC_State.GetValue(latest, "PlayerResourceKindId", ""),
            playerResourceKindName: BC_State.GetValue(latest, "PlayerResourceKindName", ""),
            playerHealthCurrent: BC_State.GetValue(latest, "PlayerHealthCurrent", ""),
            playerHealthMax: BC_State.GetValue(latest, "PlayerHealthMax", ""),
            playerResourceCurrent: BC_State.GetValue(latest, "PlayerResourceCurrent", ""),
            playerResourceMax: BC_State.GetValue(latest, "PlayerResourceMax", ""),
            playerCastFlags: BC_State.GetValue(latest, "PlayerCastFlags", ""),
            playerCastProgressQ15: BC_State.GetValue(latest, "PlayerCastProgressQ15", ""),
            playerLevel: BC_State.GetValue(latest, "PlayerLevel", ""),
            playerCallingCode: BC_State.GetValue(latest, "PlayerCallingCode", ""),
            playerCallingName: BC_State.GetValue(latest, "PlayerCallingName", ""),
            playerRoleCode: BC_State.GetValue(latest, "PlayerRoleCode", ""),
            playerRoleName: BC_State.GetValue(latest, "PlayerRoleName", ""),
            playerPowerAttack: BC_State.GetValue(latest, "PlayerPowerAttack", ""),
            playerCritAttack: BC_State.GetValue(latest, "PlayerCritAttack", ""),
            playerPowerSpell: BC_State.GetValue(latest, "PlayerPowerSpell", ""),
            playerCritSpell: BC_State.GetValue(latest, "PlayerCritSpell", ""),
            playerCritPower: BC_State.GetValue(latest, "PlayerCritPower", ""),
            playerHit: BC_State.GetValue(latest, "PlayerHit", ""),
            targetResourceKindId: BC_State.GetValue(latest, "TargetResourceKindId", ""),
            targetResourceKindName: BC_State.GetValue(latest, "TargetResourceKindName", ""),
            targetHealthCurrent: BC_State.GetValue(latest, "TargetHealthCurrent", ""),
            targetHealthMax: BC_State.GetValue(latest, "TargetHealthMax", ""),
            targetResourceCurrent: BC_State.GetValue(latest, "TargetResourceCurrent", ""),
            targetResourceMax: BC_State.GetValue(latest, "TargetResourceMax", ""),
            targetLevel: BC_State.GetValue(latest, "TargetLevel", ""),
            targetFlags: BC_State.GetValue(latest, "TargetFlags", ""),
            playerDamageEstimate: BC_State.GetValue(latest, "PlayerDamageEstimate", ""),
            targetDamageEstimate: BC_State.GetValue(latest, "TargetDamageEstimate", ""),
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

    static BuildSnapshotJson(snapshot, pretty := true) {
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
        fields.Push(BC_State.JsonNumberField("playerResourceKindId", snapshot.playerResourceKindId))
        fields.Push(BC_State.JsonStringField("playerResourceKindName", snapshot.playerResourceKindName))
        fields.Push(BC_State.JsonNumberField("playerHealthCurrent", snapshot.playerHealthCurrent))
        fields.Push(BC_State.JsonNumberField("playerHealthMax", snapshot.playerHealthMax))
        fields.Push(BC_State.JsonNumberField("playerResourceCurrent", snapshot.playerResourceCurrent))
        fields.Push(BC_State.JsonNumberField("playerResourceMax", snapshot.playerResourceMax))
        fields.Push(BC_State.JsonNumberField("playerCastFlags", snapshot.playerCastFlags))
        fields.Push(BC_State.JsonNumberField("playerCastProgressQ15", snapshot.playerCastProgressQ15))
        fields.Push(BC_State.JsonNumberField("playerLevel", snapshot.playerLevel))
        fields.Push(BC_State.JsonNumberField("playerCallingCode", snapshot.playerCallingCode))
        fields.Push(BC_State.JsonStringField("playerCallingName", snapshot.playerCallingName))
        fields.Push(BC_State.JsonNumberField("playerRoleCode", snapshot.playerRoleCode))
        fields.Push(BC_State.JsonStringField("playerRoleName", snapshot.playerRoleName))
        fields.Push(BC_State.JsonNumberField("playerPowerAttack", snapshot.playerPowerAttack))
        fields.Push(BC_State.JsonNumberField("playerCritAttack", snapshot.playerCritAttack))
        fields.Push(BC_State.JsonNumberField("playerPowerSpell", snapshot.playerPowerSpell))
        fields.Push(BC_State.JsonNumberField("playerCritSpell", snapshot.playerCritSpell))
        fields.Push(BC_State.JsonNumberField("playerCritPower", snapshot.playerCritPower))
        fields.Push(BC_State.JsonNumberField("playerHit", snapshot.playerHit))
        fields.Push(BC_State.JsonNumberField("targetResourceKindId", snapshot.targetResourceKindId))
        fields.Push(BC_State.JsonStringField("targetResourceKindName", snapshot.targetResourceKindName))
        fields.Push(BC_State.JsonNumberField("targetHealthCurrent", snapshot.targetHealthCurrent))
        fields.Push(BC_State.JsonNumberField("targetHealthMax", snapshot.targetHealthMax))
        fields.Push(BC_State.JsonNumberField("targetResourceCurrent", snapshot.targetResourceCurrent))
        fields.Push(BC_State.JsonNumberField("targetResourceMax", snapshot.targetResourceMax))
        fields.Push(BC_State.JsonNumberField("targetLevel", snapshot.targetLevel))
        fields.Push(BC_State.JsonNumberField("targetFlags", snapshot.targetFlags))
        fields.Push(BC_State.JsonNumberField("playerDamageEstimate", snapshot.playerDamageEstimate))
        fields.Push(BC_State.JsonNumberField("targetDamageEstimate", snapshot.targetDamageEstimate))
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
        if (pretty) {
            return "{`r`n  " BC_Debug.Join(fields, ",`r`n  ") "`r`n}"
        }
        return "{" BC_Debug.Join(fields, ",") "}"
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
        lines.Push("PlayerHealth: " BC_State.PairText(snapshot.playerHealthCurrent, snapshot.playerHealthMax))
        lines.Push("PlayerResource: " BC_State.PairText(snapshot.playerResourceCurrent, snapshot.playerResourceMax))
        lines.Push("PlayerResourceKind: " snapshot.playerResourceKindName)
        lines.Push("PlayerCastProgressQ15: " BC_State.NumberText(snapshot.playerCastProgressQ15))
        lines.Push("PlayerLevel: " BC_State.NumberText(snapshot.playerLevel))
        lines.Push("PlayerCallingCode: " BC_State.NumberText(snapshot.playerCallingCode))
        lines.Push("PlayerCallingName: " snapshot.playerCallingName)
        lines.Push("PlayerRoleCode: " BC_State.NumberText(snapshot.playerRoleCode))
        lines.Push("PlayerRoleName: " snapshot.playerRoleName)
        lines.Push("PlayerOffense: atk=" BC_State.NumberText(snapshot.playerPowerAttack) " critAtk=" BC_State.NumberText(snapshot.playerCritAttack) " spell=" BC_State.NumberText(snapshot.playerPowerSpell) " critSpell=" BC_State.NumberText(snapshot.playerCritSpell) " critPower=" BC_State.NumberText(snapshot.playerCritPower) " hit=" BC_State.NumberText(snapshot.playerHit))
        lines.Push("TargetHealth: " BC_State.PairText(snapshot.targetHealthCurrent, snapshot.targetHealthMax))
        lines.Push("TargetResource: " BC_State.PairText(snapshot.targetResourceCurrent, snapshot.targetResourceMax))
        lines.Push("TargetResourceKind: " snapshot.targetResourceKindName)
        lines.Push("TargetLevel: " BC_State.NumberText(snapshot.targetLevel))
        lines.Push("TargetFlags: " BC_State.NumberText(snapshot.targetFlags))
        lines.Push("PlayerDamageEstimate: " BC_State.NumberText(snapshot.playerDamageEstimate))
        lines.Push("TargetDamageEstimate: " BC_State.NumberText(snapshot.targetDamageEstimate))
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

    static BuildOperatorSummaryText(snapshot) {
        lines := []
        freshnessText := StrUpper(BC_State.FreshnessLabel(snapshot))
        lines.Push("BarCode HUD summary")
        lines.Push(
            "Status: "
            (snapshot.accepted ? "ACCEPTED" : "REJECTED")
            " | " freshnessText
            " | seq " BC_State.DefaultText(snapshot.sequence, "-")
            " | conf " BC_State.DefaultText(snapshot.confidence, "-")
        )
        lines.Push(
            "Player: L" BC_State.DefaultText(snapshot.playerLevel, "-")
            " | " BC_State.DefaultText(snapshot.playerCallingName, "unknown")
            " | " BC_State.DefaultText(snapshot.playerRoleName, "unknown")
            " | HP " BC_State.PairOrDefaultText(snapshot.playerHealthCurrent, snapshot.playerHealthMax)
            " | " BC_State.DefaultText(snapshot.playerResourceKindName, "none")
            " " BC_State.PairOrDefaultText(snapshot.playerResourceCurrent, snapshot.playerResourceMax)
        )
        lines.Push(
            "Player offense: atk " BC_State.DefaultText(snapshot.playerPowerAttack, "0")
            " | critAtk " BC_State.DefaultText(snapshot.playerCritAttack, "0")
            " | spell " BC_State.DefaultText(snapshot.playerPowerSpell, "0")
            " | critSpell " BC_State.DefaultText(snapshot.playerCritSpell, "0")
            " | critPower " BC_State.DefaultText(snapshot.playerCritPower, "0")
            " | hit " BC_State.DefaultText(snapshot.playerHit, "0")
        )

        if BC_State.HasTarget(snapshot) {
            lines.Push(
                "Target: L" BC_State.DefaultText(snapshot.targetLevel, "-")
                " | HP " BC_State.PairOrDefaultText(snapshot.targetHealthCurrent, snapshot.targetHealthMax)
                " | " BC_State.DefaultText(snapshot.targetResourceKindName, "none")
                " " BC_State.PairOrDefaultText(snapshot.targetResourceCurrent, snapshot.targetResourceMax)
                " | flags " BC_State.HexText(snapshot.targetFlags, 2)
            )
        } else {
            lines.Push("Target: none")
        }

        lines.Push(
            "Reader: " BC_State.DefaultText(snapshot.searchMode, "-")
            " | " BC_State.DefaultText(snapshot.captureSource, "-")
            " | capture " BC_State.DefaultText(snapshot.captureMs, "-") " ms"
            " | pipeline " BC_State.DefaultText(snapshot.pipelineMs, "-") " ms"
            " | reason " BC_State.DefaultText(snapshot.reason, "-")
        )
        lines.Push(
            "Session: " BC_State.DefaultText(snapshot.sessionSampleCount, "0")
            " samples | accepted " BC_State.DefaultText(snapshot.sessionAcceptedCount, "0")
            " | rejected " BC_State.DefaultText(snapshot.sessionRejectedCount, "0")
            " | streak " BC_State.DefaultText(snapshot.acceptedStreak, "0")
            "/" BC_State.DefaultText(snapshot.rejectedStreak, "0")
        )
        return BC_Debug.Join(lines, "`r`n")
    }

    static BuildOperatorSummaryJson(snapshot, pretty := true) {
        fields := []
        fields.Push(BC_State.JsonStringField("timestampUtc", snapshot.timestampUtc))
        fields.Push(BC_State.JsonBoolField("accepted", snapshot.accepted))
        fields.Push(BC_State.JsonStringField("freshness", BC_State.FreshnessLabel(snapshot)))
        fields.Push(BC_State.JsonStringField("reason", snapshot.reason))
        fields.Push(BC_State.JsonNumberField("confidence", snapshot.confidence))
        fields.Push(BC_State.JsonNumberField("sequence", snapshot.sequence))
        fields.Push(BC_State.JsonBoolField("targetPresent", BC_State.HasTarget(snapshot)))
        fields.Push(BC_State.JsonStringField("playerCallingName", snapshot.playerCallingName))
        fields.Push(BC_State.JsonStringField("playerRoleName", snapshot.playerRoleName))
        fields.Push(BC_State.JsonNumberField("playerLevel", snapshot.playerLevel))
        fields.Push(BC_State.JsonStringField("playerResourceKindName", snapshot.playerResourceKindName))
        fields.Push(BC_State.JsonNumberField("playerHealthCurrent", snapshot.playerHealthCurrent))
        fields.Push(BC_State.JsonNumberField("playerHealthMax", snapshot.playerHealthMax))
        fields.Push(BC_State.JsonNumberField("playerResourceCurrent", snapshot.playerResourceCurrent))
        fields.Push(BC_State.JsonNumberField("playerResourceMax", snapshot.playerResourceMax))
        fields.Push(BC_State.JsonNumberField("playerPowerAttack", snapshot.playerPowerAttack))
        fields.Push(BC_State.JsonNumberField("playerCritAttack", snapshot.playerCritAttack))
        fields.Push(BC_State.JsonNumberField("playerPowerSpell", snapshot.playerPowerSpell))
        fields.Push(BC_State.JsonNumberField("playerCritSpell", snapshot.playerCritSpell))
        fields.Push(BC_State.JsonNumberField("playerCritPower", snapshot.playerCritPower))
        fields.Push(BC_State.JsonNumberField("playerHit", snapshot.playerHit))
        fields.Push(BC_State.JsonNumberField("targetLevel", snapshot.targetLevel))
        fields.Push(BC_State.JsonStringField("targetResourceKindName", snapshot.targetResourceKindName))
        fields.Push(BC_State.JsonNumberField("targetHealthCurrent", snapshot.targetHealthCurrent))
        fields.Push(BC_State.JsonNumberField("targetHealthMax", snapshot.targetHealthMax))
        fields.Push(BC_State.JsonNumberField("targetResourceCurrent", snapshot.targetResourceCurrent))
        fields.Push(BC_State.JsonNumberField("targetResourceMax", snapshot.targetResourceMax))
        fields.Push(BC_State.JsonNumberField("targetFlags", snapshot.targetFlags))
        fields.Push(BC_State.JsonStringField("searchMode", snapshot.searchMode))
        fields.Push(BC_State.JsonStringField("captureSource", snapshot.captureSource))
        fields.Push(BC_State.JsonNumberField("captureMs", snapshot.captureMs))
        fields.Push(BC_State.JsonNumberField("pipelineMs", snapshot.pipelineMs))
        fields.Push(BC_State.JsonNumberField("sessionSampleCount", snapshot.sessionSampleCount))
        fields.Push(BC_State.JsonNumberField("sessionAcceptedCount", snapshot.sessionAcceptedCount))
        fields.Push(BC_State.JsonNumberField("sessionRejectedCount", snapshot.sessionRejectedCount))
        fields.Push(BC_State.JsonNumberField("acceptedStreak", snapshot.acceptedStreak))
        fields.Push(BC_State.JsonNumberField("rejectedStreak", snapshot.rejectedStreak))
        if (pretty) {
            return "{`r`n  " BC_Debug.Join(fields, ",`r`n  ") "`r`n}"
        }
        return "{" BC_Debug.Join(fields, ",") "}"
    }

    static BuildSnapshotSummary(snapshot) {
        acceptedText := snapshot.accepted ? "OK" : "BAD"
        sequenceText := BC_State.NumberText(snapshot.sequence)
        if (sequenceText = "") {
            sequenceText := "-"
        }

        confidenceText := BC_State.NumberText(snapshot.confidence)
        if (confidenceText = "") {
            confidenceText := "-"
        }

        reasonText := snapshot.reason != "" ? snapshot.reason : "-"
        return (
            snapshot.timestampUtc
            " | " acceptedText
            " | seq " sequenceText
            " | conf " confidenceText
            " | " reasonText
        )
    }

    static HasTarget(snapshot) {
        if (snapshot.targetHealthMax != "" && Integer(snapshot.targetHealthMax) > 0) {
            return true
        }
        if (snapshot.targetLevel != "" && Integer(snapshot.targetLevel) > 0) {
            return true
        }
        if (snapshot.targetFlags != "" && Integer(snapshot.targetFlags) > 0) {
            return true
        }
        return false
    }

    static FreshnessLabel(snapshot) {
        if !snapshot.accepted {
            return "bad"
        }
        if (snapshot.sequenceChanged = "") {
            return "unknown"
        }
        return snapshot.freshFrame ? "fresh" : "repeat"
    }

    static GetRecentHistory(limit := 8) {
        history := BC_State.EnsureHistory()
        items := []
        if (limit <= 0) {
            return items
        }

        startIndex := history.Length - limit + 1
        if (startIndex < 1) {
            startIndex := 1
        }

        index := startIndex
        while (index <= history.Length) {
            items.Push(history[index])
            index += 1
        }

        return items
    }

    static BuildRecentHistoryText(limit := 8) {
        entries := BC_State.GetRecentHistory(limit)
        if (entries.Length = 0) {
            return "No recent samples."
        }

        lines := []
        for _, snapshot in entries {
            lines.Push(BC_State.BuildSnapshotSummary(snapshot))
        }
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

    static AppendHistorySnapshot(snapshot) {
        history := BC_State.EnsureHistory()
        history.Push(snapshot)
        while (history.Length > BC_Config.LiveHistoryLimit) {
            history.RemoveAt(1)
        }
        BC_Debug.AppendText(BC_Config.LiveHistoryJsonlPath, BC_State.BuildSnapshotJson(snapshot, false) "`r`n")
        BC_Debug.WriteText(BC_Config.LiveHistoryJsonPath, BC_State.BuildHistoryJson(history))
    }

    static BuildHistoryJson(history) {
        items := []
        for _, snapshot in history {
            items.Push(BC_State.BuildSnapshotJson(snapshot, false))
        }
        if (items.Length = 0) {
            return "[]"
        }
        return "[`r`n  " BC_Debug.Join(items, ",`r`n  ") "`r`n]"
    }

    static EnsureSession() {
        if (!IsObject(BC_State.Session) || !BC_State.Session.HasOwnProp("SessionStartedUtc")) {
            BC_State.Session := BC_State.BuildEmptySession()
        }
        return BC_State.Session
    }

    static EnsureHistory() {
        if (!IsObject(BC_State.History)) {
            BC_State.History := []
        }
        return BC_State.History
    }

    static EnsureLockedGeometryLoaded() {
        if BC_State.LockedGeometryLoaded {
            return
        }

        BC_State.LockedGeometryLoaded := true
        if !FileExist(BC_Config.LockedGeometryPath) {
            return
        }

        try {
            content := FileRead(BC_Config.LockedGeometryPath, "UTF-8")
            originX := ""
            originY := ""
            pitch := ""
            clientWidth := ""
            clientHeight := ""

            if RegExMatch(content, "i)OriginX:\s*(-?\d+)", &originXMatch) {
                originX := Integer(originXMatch[1])
            }
            if RegExMatch(content, "i)OriginY:\s*(-?\d+)", &originYMatch) {
                originY := Integer(originYMatch[1])
            }
            if RegExMatch(content, "i)Pitch:\s*([0-9]+(?:\.[0-9]+)?)", &pitchMatch) {
                pitch := Number(pitchMatch[1])
            }
            if RegExMatch(content, "i)ClientWidth:\s*(\d+)", &clientWidthMatch) {
                clientWidth := Integer(clientWidthMatch[1])
            }
            if RegExMatch(content, "i)ClientHeight:\s*(\d+)", &clientHeightMatch) {
                clientHeight := Integer(clientHeightMatch[1])
            }

            if (pitch != "" && pitch > 0) {
                BC_State.LockedGeometry := {
                    OriginX: originX = "" ? 0 : originX,
                    OriginY: originY = "" ? 0 : originY,
                    Pitch: pitch,
                    ClientWidth: clientWidth,
                    ClientHeight: clientHeight
                }
            }
        } catch {
        }
    }

    static PersistLockedGeometry() {
        if !IsObject(BC_State.LockedGeometry) || !BC_State.LockedGeometry.HasOwnProp("Pitch") || (BC_State.LockedGeometry.Pitch <= 0) {
            return
        }

        lines := []
        lines.Push("OriginX: " BC_State.LockedGeometry.OriginX)
        lines.Push("OriginY: " BC_State.LockedGeometry.OriginY)
        lines.Push("Pitch: " BC_State.LockedGeometry.Pitch)
        if (BC_State.LockedGeometry.HasOwnProp("ClientWidth") && BC_State.LockedGeometry.ClientWidth != "") {
            lines.Push("ClientWidth: " BC_State.LockedGeometry.ClientWidth)
        }
        if (BC_State.LockedGeometry.HasOwnProp("ClientHeight") && BC_State.LockedGeometry.ClientHeight != "") {
            lines.Push("ClientHeight: " BC_State.LockedGeometry.ClientHeight)
        }
        BC_Debug.WriteText(BC_Config.LockedGeometryPath, BC_Debug.Join(lines, "`r`n"))
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

    static ShouldUpdateLockedGeometry(image) {
        if (!IsObject(image) || !image.HasOwnProp("SourceKind")) {
            return true
        }

        sourceKind := image.SourceKind
        return sourceKind != "synthetic" && sourceKind != "unavailable" && sourceKind != "live-window-missing"
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
        if (kindId = 5) {
            return "power"
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
        if (code = 5) {
            return "primalist"
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

    static DefaultText(value, fallback := "-") {
        text := BC_State.TextValue(value)
        return text = "" ? fallback : text
    }

    static PairText(left, right) {
        return BC_State.NumberText(left) "/" BC_State.NumberText(right)
    }

    static PairOrDefaultText(left, right, fallback := "-/-") {
        leftText := BC_State.NumberText(left)
        rightText := BC_State.NumberText(right)
        if (leftText = "" && rightText = "") {
            return fallback
        }
        return leftText "/" rightText
    }

    static HexText(value, minDigits := 0) {
        if (value = "") {
            return ""
        }

        integerValue := Integer(value)
        if (minDigits > 0) {
            return "0x" Format("{:0" minDigits "X}", integerValue)
        }
        return "0x" Format("{:X}", integerValue)
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

    static DeleteIfPresent(path) {
        if FileExist(path) {
            FileDelete(path)
        }
    }
}

; end-of-script marker comment
