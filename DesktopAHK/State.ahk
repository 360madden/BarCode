/*
script name: DesktopAHK/State.ahk
version: 0.4.1
purpose: Tracks the latest decoded ops+tactical frames and emits merged live state snapshots for local consumers.
dependencies: DesktopAHK/Config.ahk, DesktopAHK/Debug.ahk, DesktopAHK/Validate.ahk
important assumptions: Persists a flat latest-state snapshot for downstream tools rather than serializing the full nested validation object, and merges alternating ops+tactical pages into one reader-facing state.
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
    static PageAcceptedTicks := { Ops: 0, Tactical: 0 }

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
        BC_State.PageAcceptedTicks := { Ops: 0, Tactical: 0 }
        BC_State.DeleteIfPresent(BC_Config.LiveHistoryJsonPath)
        BC_State.DeleteIfPresent(BC_Config.LiveHistoryJsonlPath)
        BC_State.DeleteIfPresent(BC_Config.LiveSummaryJsonPath)
        BC_State.DeleteIfPresent(BC_Config.LiveSummaryTextPath)
        BC_State.WriteSnapshot()
    }

    static Update(validationResult, context := "", persistSnapshot := false) {
        details := validationResult.Details
        transport := details.HasOwnProp("Transport") ? details.Transport : {}
        pageData := details.HasOwnProp("PageData") ? details.PageData : {}
        pageName := details.HasOwnProp("PageName") ? details.PageName : ""
        image := IsObject(context) && context.HasOwnProp("Image") ? context.Image : {}
        timings := IsObject(context) && context.HasOwnProp("Timings") ? context.Timings : {}
        sampleIndex := IsObject(context) && context.HasOwnProp("SampleIndex") ? context.SampleIndex : ""
        sequence := transport.HasOwnProp("Sequence") ? transport.Sequence : ""
        sessionStats := BC_State.UpdateSessionStats(validationResult, sampleIndex, sequence)
        previousLatest := BC_State.Latest

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

        latest := {}
        for key, value in BC_State.Latest.OwnProps() {
            latest.%key% := value
        }

        latest.TimestampUtc := A_NowUTC
        latest.TimestampTickCount := A_TickCount
        latest.Accepted := validationResult.IsAccepted
        latest.Reason := validationResult.Reason
        latest.Confidence := validationResult.Confidence
        latest.Sequence := sequence
        latest.PageId := transport.HasOwnProp("PageId") ? transport.PageId : ""
        latest.PageName := pageName
        latest.PayloadUsedLength := transport.HasOwnProp("PayloadUsedLength") ? transport.PayloadUsedLength : ""
        latest.SearchMode := details.HasOwnProp("SearchMode") ? details.SearchMode : ""
        latest.BorderErrors := details.HasOwnProp("BorderErrors") ? details.BorderErrors : ""
        latest.OriginX := details.HasOwnProp("OriginX") ? details.OriginX : ""
        latest.OriginY := details.HasOwnProp("OriginY") ? details.OriginY : ""
        latest.Pitch := details.HasOwnProp("Pitch") ? details.Pitch : ""
        latest.BandWidth := details.HasOwnProp("BandWidth") ? details.BandWidth : ""
        latest.BandHeight := details.HasOwnProp("BandHeight") ? details.BandHeight : ""
        latest.CaptureSource := IsObject(image) && image.HasOwnProp("SourceKind") ? image.SourceKind : ""
        latest.CaptureRequestedSource := IsObject(image) && image.HasOwnProp("RequestedSource") ? image.RequestedSource : ""
        latest.CaptureResolvedSource := IsObject(image) && image.HasOwnProp("ResolvedSource") ? image.ResolvedSource : ""
        latest.CaptureRouteReason := IsObject(image) && image.HasOwnProp("CaptureRouteReason") ? image.CaptureRouteReason : ""
        latest.CaptureFallbackFrom := IsObject(image) && image.HasOwnProp("CaptureFallbackFrom") ? image.CaptureFallbackFrom : ""
        latest.CaptureHintMode := IsObject(image) && image.HasOwnProp("HintMode") ? image.HintMode : ""
        latest.CaptureHintPitch := IsObject(image) && image.HasOwnProp("HintPitch") ? image.HintPitch : ""
        latest.ClientX := IsObject(image) && image.HasOwnProp("ClientRect") ? image.ClientRect.x : ""
        latest.ClientY := IsObject(image) && image.HasOwnProp("ClientRect") ? image.ClientRect.y : ""
        latest.ClientWidth := IsObject(image) && image.HasOwnProp("ClientRect") ? image.ClientRect.width : ""
        latest.ClientHeight := IsObject(image) && image.HasOwnProp("ClientRect") ? image.ClientRect.height : ""
        latest.CaptureLeft := IsObject(image) && image.HasOwnProp("SourceLeft") ? image.SourceLeft : ""
        latest.CaptureTop := IsObject(image) && image.HasOwnProp("SourceTop") ? image.SourceTop : ""
        latest.CaptureWidth := IsObject(image) && image.HasOwnProp("SourceWidth") ? image.SourceWidth : ""
        latest.CaptureHeight := IsObject(image) && image.HasOwnProp("SourceHeight") ? image.SourceHeight : ""
        latest.CaptureAttemptsText := IsObject(context) && context.HasOwnProp("CaptureAttempts") ? BC_Debug.Join(context.CaptureAttempts, ",") : ""
        latest.CaptureMs := IsObject(timings) && timings.HasOwnProp("CaptureMs") ? timings.CaptureMs : ""
        latest.PipelineMs := IsObject(timings) && timings.HasOwnProp("PipelineMs") ? timings.PipelineMs : ""
        latest.AttemptCount := IsObject(timings) && timings.HasOwnProp("AttemptCount") ? timings.AttemptCount : ""
        latest.SampleIndex := sampleIndex
        latest.SessionStartedUtc := sessionStats.SessionStartedUtc
        latest.SessionSampleCount := sessionStats.SampleCount
        latest.SessionAcceptedCount := sessionStats.AcceptedCount
        latest.SessionRejectedCount := sessionStats.RejectedCount
        latest.AcceptedStreak := sessionStats.AcceptedStreak
        latest.RejectedStreak := sessionStats.RejectedStreak
        latest.LastAcceptedTimestampUtc := sessionStats.LastAcceptedTimestampUtc
        latest.LastRejectedTimestampUtc := sessionStats.LastRejectedTimestampUtc
        latest.LastAcceptedSequence := sessionStats.LastAcceptedSequence
        latest.SequenceAdvance := sessionStats.SequenceAdvance
        latest.SequenceChanged := sessionStats.SequenceChanged
        latest.FreshFrame := sessionStats.FreshFrame
        latest.SequenceRepeatedCount := sessionStats.SequenceRepeatedCount
        latest.SequenceWrapCount := sessionStats.SequenceWrapCount
        latest.WindowTitle := BC_State.ResolveWindowTitle(context, image)
        latest.ProcessName := BC_State.ResolveProcessName(context, image)
        latest.Details := details

        if (validationResult.IsAccepted && IsObject(pageData)) {
            if (pageName = "ops-overview") {
                BC_State.PageAcceptedTicks.Ops := A_TickCount
                BC_State.ApplyOpsPage(latest, pageData)
            } else if (pageName = "tactical-combat") {
                BC_State.PageAcceptedTicks.Tactical := A_TickCount
                BC_State.ApplyTacticalPage(latest, pageData)
                BC_State.ApplyTacticalDynamics(latest, previousLatest)
            }
        }

        latest.OpsPageAgeMs := BC_State.PageAcceptedTicks.Ops > 0 ? (A_TickCount - BC_State.PageAcceptedTicks.Ops) : ""
        latest.TacticalPageAgeMs := BC_State.PageAcceptedTicks.Tactical > 0 ? (A_TickCount - BC_State.PageAcceptedTicks.Tactical) : ""

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

    static ApplyOpsPage(latest, pageData) {
        latest.SampleMask := BC_State.GetValue(pageData, "SampleMask", BC_State.GetValue(latest, "SampleMask", ""))
        latest.StateFlags := BC_State.GetValue(pageData, "StateFlags", BC_State.GetValue(latest, "StateFlags", ""))
        latest.PlayerResourceKindId := BC_State.GetValue(pageData, "PlayerResourceKindId", BC_State.GetValue(latest, "PlayerResourceKindId", ""))
        latest.PlayerResourceKindName := BC_State.ResourceKindName(latest.PlayerResourceKindId)
        latest.PlayerHealthCurrent := BC_State.GetValue(pageData, "PlayerHealthCurrent", BC_State.GetValue(latest, "PlayerHealthCurrent", ""))
        latest.PlayerHealthMax := BC_State.GetValue(pageData, "PlayerHealthMax", BC_State.GetValue(latest, "PlayerHealthMax", ""))
        latest.PlayerResourceCurrent := BC_State.GetValue(pageData, "PlayerResourceCurrent", BC_State.GetValue(latest, "PlayerResourceCurrent", ""))
        latest.PlayerResourceMax := BC_State.GetValue(pageData, "PlayerResourceMax", BC_State.GetValue(latest, "PlayerResourceMax", ""))
        latest.PlayerLevel := BC_State.GetValue(pageData, "PlayerLevel", BC_State.GetValue(latest, "PlayerLevel", ""))
        latest.PlayerCallingCode := BC_State.GetValue(pageData, "PlayerCallingCode", BC_State.GetValue(latest, "PlayerCallingCode", ""))
        latest.PlayerCallingName := BC_State.CallingName(latest.PlayerCallingCode)
        latest.PlayerRoleCode := BC_State.GetValue(pageData, "PlayerRoleCode", BC_State.GetValue(latest, "PlayerRoleCode", ""))
        latest.PlayerRoleName := BC_State.RoleName(latest.PlayerRoleCode)
        latest.TargetResourceKindId := BC_State.GetValue(pageData, "TargetResourceKindId", BC_State.GetValue(latest, "TargetResourceKindId", ""))
        latest.TargetResourceKindName := BC_State.ResourceKindName(latest.TargetResourceKindId)
        latest.TargetHealthCurrent := BC_State.GetValue(pageData, "TargetHealthCurrent", BC_State.GetValue(latest, "TargetHealthCurrent", ""))
        latest.TargetHealthMax := BC_State.GetValue(pageData, "TargetHealthMax", BC_State.GetValue(latest, "TargetHealthMax", ""))
        latest.TargetResourceCurrent := BC_State.GetValue(pageData, "TargetResourceCurrent", BC_State.GetValue(latest, "TargetResourceCurrent", ""))
        latest.TargetResourceMax := BC_State.GetValue(pageData, "TargetResourceMax", BC_State.GetValue(latest, "TargetResourceMax", ""))
        latest.TargetLevel := BC_State.GetValue(pageData, "TargetLevel", BC_State.GetValue(latest, "TargetLevel", ""))
        latest.TargetFlags := BC_State.GetValue(pageData, "TargetFlags", BC_State.GetValue(latest, "TargetFlags", ""))
        latest.TargetRelationCode := BC_State.GetValue(pageData, "TargetRelationCode", BC_State.GetValue(latest, "TargetRelationCode", ""))
        latest.TargetRelationName := BC_State.RelationName(latest.TargetRelationCode)
    }

    static ApplyTacticalPage(latest, pageData) {
        latest.TacticalMask := BC_State.GetValue(pageData, "TacticalMask", BC_State.GetValue(latest, "TacticalMask", ""))
        latest.StateFlags := BC_State.GetValue(pageData, "StateFlags", BC_State.GetValue(latest, "StateFlags", ""))
        latest.PlayerCastFlags := BC_State.GetValue(pageData, "PlayerCastFlags", BC_State.GetValue(latest, "PlayerCastFlags", ""))
        latest.PlayerCastProgressQ15 := BC_State.GetValue(pageData, "PlayerCastProgressQ15", BC_State.GetValue(latest, "PlayerCastProgressQ15", ""))
        latest.PlayerPowerAttack := BC_State.GetValue(pageData, "PlayerPowerAttack", BC_State.GetValue(latest, "PlayerPowerAttack", ""))
        latest.PlayerCritAttack := BC_State.GetValue(pageData, "PlayerCritAttack", BC_State.GetValue(latest, "PlayerCritAttack", ""))
        latest.PlayerPowerSpell := BC_State.GetValue(pageData, "PlayerPowerSpell", BC_State.GetValue(latest, "PlayerPowerSpell", ""))
        latest.PlayerCritSpell := BC_State.GetValue(pageData, "PlayerCritSpell", BC_State.GetValue(latest, "PlayerCritSpell", ""))
        latest.PlayerCritPower := BC_State.GetValue(pageData, "PlayerCritPower", BC_State.GetValue(latest, "PlayerCritPower", ""))
        latest.PlayerHit := BC_State.GetValue(pageData, "PlayerHit", BC_State.GetValue(latest, "PlayerHit", ""))
        latest.PlayerZoneHash16 := BC_State.GetValue(pageData, "PlayerZoneHash16", BC_State.GetValue(latest, "PlayerZoneHash16", ""))
        latest.TargetZoneHash16 := BC_State.GetValue(pageData, "TargetZoneHash16", BC_State.GetValue(latest, "TargetZoneHash16", ""))
        latest.PlayerCoordX := BC_State.RoundTenths(BC_State.GetValue(pageData, "PlayerCoordX", BC_State.GetValue(latest, "PlayerCoordX", "")))
        latest.PlayerCoordY := BC_State.RoundTenths(BC_State.GetValue(pageData, "PlayerCoordY", BC_State.GetValue(latest, "PlayerCoordY", "")))
        latest.PlayerCoordZ := BC_State.RoundTenths(BC_State.GetValue(pageData, "PlayerCoordZ", BC_State.GetValue(latest, "PlayerCoordZ", "")))
        latest.TargetCoordX := BC_State.RoundTenths(BC_State.GetValue(pageData, "TargetCoordX", BC_State.GetValue(latest, "TargetCoordX", "")))
        latest.TargetCoordY := BC_State.RoundTenths(BC_State.GetValue(pageData, "TargetCoordY", BC_State.GetValue(latest, "TargetCoordY", "")))
        latest.TargetCoordZ := BC_State.RoundTenths(BC_State.GetValue(pageData, "TargetCoordZ", BC_State.GetValue(latest, "TargetCoordZ", "")))
        latest.TargetRelationCode := BC_State.GetValue(pageData, "TargetRelationCode", BC_State.GetValue(latest, "TargetRelationCode", ""))
        latest.TargetRelationName := BC_State.RelationName(latest.TargetRelationCode)
        latest.TargetTierCode := BC_State.GetValue(pageData, "TargetTierCode", BC_State.GetValue(latest, "TargetTierCode", ""))
        latest.TargetTierName := BC_State.TierName(latest.TargetTierCode)
        latest.TargetTaggedCode := BC_State.GetValue(pageData, "TargetTaggedCode", BC_State.GetValue(latest, "TargetTaggedCode", ""))
        latest.TargetTaggedName := BC_State.TaggedName(latest.TargetTaggedCode)
        latest.TargetCallingCode := BC_State.GetValue(pageData, "TargetCallingCode", BC_State.GetValue(latest, "TargetCallingCode", ""))
        latest.TargetCallingName := BC_State.CallingName(latest.TargetCallingCode)
        latest.TargetRadius := BC_State.RoundTenths(BC_State.GetValue(pageData, "TargetRadius", BC_State.GetValue(latest, "TargetRadius", "")))
    }

    static ApplyTacticalDynamics(latest, previousLatest) {
        if !IsObject(previousLatest) {
            latest.PlayerMoveDeltaXZ := ""
            latest.PlayerMoveState := "unknown"
            latest.TargetMoveDeltaXZ := ""
            latest.TargetMoveState := "unknown"
            latest.DistanceDeltaXZ := ""
            latest.RangeTrendText := "unknown"
            return
        }

        latest.PlayerMoveDeltaXZ := BC_State.MovementDeltaXZ(
            BC_State.GetValue(latest, "PlayerZoneHash16", ""),
            BC_State.GetValue(latest, "PlayerCoordX", ""),
            BC_State.GetValue(latest, "PlayerCoordZ", ""),
            BC_State.GetValue(previousLatest, "PlayerZoneHash16", ""),
            BC_State.GetValue(previousLatest, "PlayerCoordX", ""),
            BC_State.GetValue(previousLatest, "PlayerCoordZ", "")
        )
        latest.PlayerMoveState := BC_State.MovementStateText(latest.PlayerMoveDeltaXZ)

        latest.TargetMoveDeltaXZ := BC_State.MovementDeltaXZ(
            BC_State.GetValue(latest, "TargetZoneHash16", ""),
            BC_State.GetValue(latest, "TargetCoordX", ""),
            BC_State.GetValue(latest, "TargetCoordZ", ""),
            BC_State.GetValue(previousLatest, "TargetZoneHash16", ""),
            BC_State.GetValue(previousLatest, "TargetCoordX", ""),
            BC_State.GetValue(previousLatest, "TargetCoordZ", "")
        )
        latest.TargetMoveState := BC_State.MovementStateText(latest.TargetMoveDeltaXZ)

        currentDistance := BC_State.DistanceXZ({
            playerZoneHash16: BC_State.GetValue(latest, "PlayerZoneHash16", ""),
            targetZoneHash16: BC_State.GetValue(latest, "TargetZoneHash16", ""),
            playerCoordX: BC_State.GetValue(latest, "PlayerCoordX", ""),
            playerCoordZ: BC_State.GetValue(latest, "PlayerCoordZ", ""),
            targetCoordX: BC_State.GetValue(latest, "TargetCoordX", ""),
            targetCoordZ: BC_State.GetValue(latest, "TargetCoordZ", "")
        })
        previousDistance := BC_State.DistanceXZ({
            playerZoneHash16: BC_State.GetValue(previousLatest, "PlayerZoneHash16", ""),
            targetZoneHash16: BC_State.GetValue(previousLatest, "TargetZoneHash16", ""),
            playerCoordX: BC_State.GetValue(previousLatest, "PlayerCoordX", ""),
            playerCoordZ: BC_State.GetValue(previousLatest, "PlayerCoordZ", ""),
            targetCoordX: BC_State.GetValue(previousLatest, "TargetCoordX", ""),
            targetCoordZ: BC_State.GetValue(previousLatest, "TargetCoordZ", "")
        })

        latest.DistanceDeltaXZ := ""
        latest.RangeTrendText := "unknown"
        if (currentDistance != "" && previousDistance != "") {
            latest.DistanceDeltaXZ := Round(currentDistance - previousDistance, 1)
            latest.RangeTrendText := BC_State.RangeTrendText(latest.DistanceDeltaXZ)
        }
    }

    static BuildSnapshot() {
        latest := BC_State.Latest
        snapshot := {
            timestampUtc: BC_State.GetValue(latest, "TimestampUtc", ""),
            timestampTickCount: BC_State.GetValue(latest, "TimestampTickCount", ""),
            accepted: BC_State.GetValue(latest, "Accepted", false),
            reason: BC_State.GetValue(latest, "Reason", ""),
            confidence: BC_State.GetValue(latest, "Confidence", ""),
            sequence: BC_State.GetValue(latest, "Sequence", ""),
            pageId: BC_State.GetValue(latest, "PageId", ""),
            pageName: BC_State.GetValue(latest, "PageName", ""),
            payloadUsedLength: BC_State.GetValue(latest, "PayloadUsedLength", ""),
            sampleMask: BC_State.GetValue(latest, "SampleMask", ""),
            tacticalMask: BC_State.GetValue(latest, "TacticalMask", ""),
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
            targetRelationCode: BC_State.GetValue(latest, "TargetRelationCode", ""),
            targetRelationName: BC_State.GetValue(latest, "TargetRelationName", ""),
            targetTierCode: BC_State.GetValue(latest, "TargetTierCode", ""),
            targetTierName: BC_State.GetValue(latest, "TargetTierName", ""),
            targetTaggedCode: BC_State.GetValue(latest, "TargetTaggedCode", ""),
            targetTaggedName: BC_State.GetValue(latest, "TargetTaggedName", ""),
            targetCallingCode: BC_State.GetValue(latest, "TargetCallingCode", ""),
            targetCallingName: BC_State.GetValue(latest, "TargetCallingName", ""),
            targetRadius: BC_State.GetValue(latest, "TargetRadius", ""),
            playerZoneHash16: BC_State.GetValue(latest, "PlayerZoneHash16", ""),
            targetZoneHash16: BC_State.GetValue(latest, "TargetZoneHash16", ""),
            playerCoordX: BC_State.GetValue(latest, "PlayerCoordX", ""),
            playerCoordY: BC_State.GetValue(latest, "PlayerCoordY", ""),
            playerCoordZ: BC_State.GetValue(latest, "PlayerCoordZ", ""),
            targetCoordX: BC_State.GetValue(latest, "TargetCoordX", ""),
            targetCoordY: BC_State.GetValue(latest, "TargetCoordY", ""),
            targetCoordZ: BC_State.GetValue(latest, "TargetCoordZ", ""),
            playerMoveDeltaXZ: BC_State.GetValue(latest, "PlayerMoveDeltaXZ", ""),
            playerMoveState: BC_State.GetValue(latest, "PlayerMoveState", "unknown"),
            targetMoveDeltaXZ: BC_State.GetValue(latest, "TargetMoveDeltaXZ", ""),
            targetMoveState: BC_State.GetValue(latest, "TargetMoveState", "unknown"),
            distanceDeltaXZ: BC_State.GetValue(latest, "DistanceDeltaXZ", ""),
            rangeTrendText: BC_State.GetValue(latest, "RangeTrendText", "unknown"),
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
            captureRequestedSource: BC_State.GetValue(latest, "CaptureRequestedSource", ""),
            captureResolvedSource: BC_State.GetValue(latest, "CaptureResolvedSource", ""),
            captureRouteReason: BC_State.GetValue(latest, "CaptureRouteReason", ""),
            captureFallbackFrom: BC_State.GetValue(latest, "CaptureFallbackFrom", ""),
            captureHintMode: BC_State.GetValue(latest, "CaptureHintMode", ""),
            captureHintPitch: BC_State.GetValue(latest, "CaptureHintPitch", ""),
            clientX: BC_State.GetValue(latest, "ClientX", ""),
            clientY: BC_State.GetValue(latest, "ClientY", ""),
            clientWidth: BC_State.GetValue(latest, "ClientWidth", ""),
            clientHeight: BC_State.GetValue(latest, "ClientHeight", ""),
            captureLeft: BC_State.GetValue(latest, "CaptureLeft", ""),
            captureTop: BC_State.GetValue(latest, "CaptureTop", ""),
            captureWidth: BC_State.GetValue(latest, "CaptureWidth", ""),
            captureHeight: BC_State.GetValue(latest, "CaptureHeight", ""),
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
            opsPageAgeMs: BC_State.GetValue(latest, "OpsPageAgeMs", ""),
            tacticalPageAgeMs: BC_State.GetValue(latest, "TacticalPageAgeMs", ""),
            windowTitle: BC_State.GetValue(latest, "WindowTitle", ""),
            processName: BC_State.GetValue(latest, "ProcessName", "")
        }
        snapshot.sameZone := BC_State.SameZone(snapshot)
        snapshot.distanceXZ := BC_State.DistanceXZ(snapshot)
        snapshot.distanceBucket := BC_State.DistanceBucket(snapshot.distanceXZ)
        snapshot.distanceBucketText := BC_State.DistanceBucketName(snapshot.distanceBucket)
        return snapshot
    }

    static BuildSnapshotJson(snapshot, pretty := true) {
        fields := []
        fields.Push(BC_State.JsonStringField("timestampUtc", snapshot.timestampUtc))
        fields.Push(BC_State.JsonBoolField("accepted", snapshot.accepted))
        fields.Push(BC_State.JsonStringField("reason", snapshot.reason))
        fields.Push(BC_State.JsonNumberField("confidence", snapshot.confidence))
        fields.Push(BC_State.JsonNumberField("sequence", snapshot.sequence))
        fields.Push(BC_State.JsonNumberField("pageId", snapshot.pageId))
        fields.Push(BC_State.JsonStringField("pageName", snapshot.pageName))
        fields.Push(BC_State.JsonNumberField("payloadUsedLength", snapshot.payloadUsedLength))
        fields.Push(BC_State.JsonNumberField("sampleMask", snapshot.sampleMask))
        fields.Push(BC_State.JsonNumberField("tacticalMask", snapshot.tacticalMask))
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
        fields.Push(BC_State.JsonNumberField("targetRelationCode", snapshot.targetRelationCode))
        fields.Push(BC_State.JsonStringField("targetRelationName", snapshot.targetRelationName))
        fields.Push(BC_State.JsonNumberField("targetTierCode", snapshot.targetTierCode))
        fields.Push(BC_State.JsonStringField("targetTierName", snapshot.targetTierName))
        fields.Push(BC_State.JsonNumberField("targetTaggedCode", snapshot.targetTaggedCode))
        fields.Push(BC_State.JsonStringField("targetTaggedName", snapshot.targetTaggedName))
        fields.Push(BC_State.JsonNumberField("targetCallingCode", snapshot.targetCallingCode))
        fields.Push(BC_State.JsonStringField("targetCallingName", snapshot.targetCallingName))
        fields.Push(BC_State.JsonNumberField("targetRadius", snapshot.targetRadius))
        fields.Push(BC_State.JsonNumberField("playerZoneHash16", snapshot.playerZoneHash16))
        fields.Push(BC_State.JsonNumberField("targetZoneHash16", snapshot.targetZoneHash16))
        fields.Push(BC_State.JsonNumberField("playerCoordX", snapshot.playerCoordX))
        fields.Push(BC_State.JsonNumberField("playerCoordY", snapshot.playerCoordY))
        fields.Push(BC_State.JsonNumberField("playerCoordZ", snapshot.playerCoordZ))
        fields.Push(BC_State.JsonNumberField("targetCoordX", snapshot.targetCoordX))
        fields.Push(BC_State.JsonNumberField("targetCoordY", snapshot.targetCoordY))
        fields.Push(BC_State.JsonNumberField("targetCoordZ", snapshot.targetCoordZ))
        fields.Push(BC_State.JsonNumberField("playerMoveDeltaXZ", snapshot.playerMoveDeltaXZ))
        fields.Push(BC_State.JsonStringField("playerMoveState", snapshot.playerMoveState))
        fields.Push(BC_State.JsonNumberField("targetMoveDeltaXZ", snapshot.targetMoveDeltaXZ))
        fields.Push(BC_State.JsonStringField("targetMoveState", snapshot.targetMoveState))
        fields.Push(BC_State.JsonNumberField("distanceDeltaXZ", snapshot.distanceDeltaXZ))
        fields.Push(BC_State.JsonStringField("rangeTrendText", snapshot.rangeTrendText))
        fields.Push(BC_State.JsonBoolField("sameZone", snapshot.sameZone))
        fields.Push(BC_State.JsonNumberField("distanceXZ", snapshot.distanceXZ))
        fields.Push(BC_State.JsonStringField("distanceBucketText", snapshot.distanceBucketText))
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
        fields.Push(BC_State.JsonStringField("captureRequestedSource", snapshot.captureRequestedSource))
        fields.Push(BC_State.JsonStringField("captureResolvedSource", snapshot.captureResolvedSource))
        fields.Push(BC_State.JsonStringField("captureRouteReason", snapshot.captureRouteReason))
        fields.Push(BC_State.JsonStringField("captureFallbackFrom", snapshot.captureFallbackFrom))
        fields.Push(BC_State.JsonStringField("captureHintMode", snapshot.captureHintMode))
        fields.Push(BC_State.JsonNumberField("captureHintPitch", snapshot.captureHintPitch))
        fields.Push(BC_State.JsonNumberField("clientX", snapshot.clientX))
        fields.Push(BC_State.JsonNumberField("clientY", snapshot.clientY))
        fields.Push(BC_State.JsonNumberField("clientWidth", snapshot.clientWidth))
        fields.Push(BC_State.JsonNumberField("clientHeight", snapshot.clientHeight))
        fields.Push(BC_State.JsonNumberField("captureLeft", snapshot.captureLeft))
        fields.Push(BC_State.JsonNumberField("captureTop", snapshot.captureTop))
        fields.Push(BC_State.JsonNumberField("captureWidth", snapshot.captureWidth))
        fields.Push(BC_State.JsonNumberField("captureHeight", snapshot.captureHeight))
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
        fields.Push(BC_State.JsonNumberField("opsPageAgeMs", snapshot.opsPageAgeMs))
        fields.Push(BC_State.JsonNumberField("tacticalPageAgeMs", snapshot.tacticalPageAgeMs))
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
        clientRectText := BC_State.RectText(snapshot.clientX, snapshot.clientY, snapshot.clientWidth, snapshot.clientHeight)
        captureRectText := BC_State.RectText(snapshot.captureLeft, snapshot.captureTop, snapshot.captureWidth, snapshot.captureHeight)
        lines.Push("BarCode live state snapshot")
        lines.Push("TimestampUtc: " snapshot.timestampUtc)
        lines.Push("SampleAgeMs: " BC_State.AgeText(snapshot))
        lines.Push("Accepted: " BC_State.BoolText(snapshot.accepted))
        lines.Push("Reason: " snapshot.reason)
        lines.Push("Confidence: " BC_State.NumberText(snapshot.confidence))
        lines.Push("Sequence: " BC_State.NumberText(snapshot.sequence))
        lines.Push("PageId: " BC_State.NumberText(snapshot.pageId))
        lines.Push("PageName: " snapshot.pageName)
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
        lines.Push("TargetRelation: " BC_State.DefaultText(snapshot.targetRelationName, "unknown") " (" BC_State.NumberText(snapshot.targetRelationCode) ")")
        lines.Push("TargetTier: " BC_State.DefaultText(snapshot.targetTierName, "normal") " (" BC_State.NumberText(snapshot.targetTierCode) ")")
        lines.Push("TargetTagged: " BC_State.DefaultText(snapshot.targetTaggedName, "none") " (" BC_State.NumberText(snapshot.targetTaggedCode) ")")
        lines.Push("TargetCalling: " BC_State.DefaultText(snapshot.targetCallingName, "unknown") " (" BC_State.NumberText(snapshot.targetCallingCode) ")")
        lines.Push("TargetRadius: " BC_State.NumberText(snapshot.targetRadius))
        lines.Push("PlayerZoneHash16: " BC_State.HexText(snapshot.playerZoneHash16, 4))
        lines.Push("TargetZoneHash16: " BC_State.HexText(snapshot.targetZoneHash16, 4))
        lines.Push("PlayerCoord: " BC_State.NumberText(snapshot.playerCoordX) ", " BC_State.NumberText(snapshot.playerCoordY) ", " BC_State.NumberText(snapshot.playerCoordZ))
        lines.Push("TargetCoord: " BC_State.NumberText(snapshot.targetCoordX) ", " BC_State.NumberText(snapshot.targetCoordY) ", " BC_State.NumberText(snapshot.targetCoordZ))
        lines.Push("PlayerMove: " BC_State.DefaultText(snapshot.playerMoveState, "unknown") " (" BC_State.NumberText(snapshot.playerMoveDeltaXZ) ")")
        lines.Push("TargetMove: " BC_State.DefaultText(snapshot.targetMoveState, "unknown") " (" BC_State.NumberText(snapshot.targetMoveDeltaXZ) ")")
        lines.Push("SameZone: " BC_State.BoolText(snapshot.sameZone))
        lines.Push("DistanceXZ: " BC_State.NumberText(snapshot.distanceXZ))
        lines.Push("DistanceDeltaXZ: " BC_State.NumberText(snapshot.distanceDeltaXZ))
        lines.Push("RangeTrend: " BC_State.DefaultText(snapshot.rangeTrendText, "unknown"))
        lines.Push("DistanceBucket: " snapshot.distanceBucketText)
        lines.Push("PlayerDamageEstimate: " BC_State.NumberText(snapshot.playerDamageEstimate))
        lines.Push("TargetDamageEstimate: " BC_State.NumberText(snapshot.targetDamageEstimate))
        lines.Push("SearchMode: " snapshot.searchMode)
        lines.Push("BorderErrors: " BC_State.NumberText(snapshot.borderErrors))
        lines.Push("Origin: " originText)
        lines.Push("Pitch: " BC_State.NumberText(snapshot.pitch))
        lines.Push("BandSize: " bandSizeText)
        lines.Push("CaptureSource: " snapshot.captureSource)
        lines.Push("CaptureRequestedSource: " snapshot.captureRequestedSource)
        lines.Push("CaptureResolvedSource: " snapshot.captureResolvedSource)
        lines.Push("CaptureRouteReason: " snapshot.captureRouteReason)
        lines.Push("CaptureFallbackFrom: " snapshot.captureFallbackFrom)
        lines.Push("CaptureHintMode: " snapshot.captureHintMode)
        lines.Push("CaptureHintPitch: " BC_State.NumberText(snapshot.captureHintPitch))
        lines.Push("ClientRect: " clientRectText)
        lines.Push("CaptureRect: " captureRectText)
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
        lines.Push("OpsPageAgeMs: " BC_State.NumberText(snapshot.opsPageAgeMs))
        lines.Push("TacticalPageAgeMs: " BC_State.NumberText(snapshot.tacticalPageAgeMs))
        lines.Push("WindowTitle: " snapshot.windowTitle)
        lines.Push("ProcessName: " snapshot.processName)
        return BC_Debug.Join(lines, "`r`n")
    }

    static BuildOperatorSummaryText(snapshot) {
        lines := []
        freshnessText := StrUpper(BC_State.FreshnessLabel(snapshot))
        ageText := BC_State.AgeText(snapshot)
        lines.Push("BarCode HUD summary")
        lines.Push(
            "Status: "
            (snapshot.accepted ? "ACCEPTED" : "REJECTED")
            " | " freshnessText
            " | sample " ageText
            " | seq " BC_State.DefaultText(snapshot.sequence, "-")
            " | conf " BC_State.DefaultText(snapshot.confidence, "-")
        )
        lines.Push(
            "Player: L" BC_State.DefaultText(snapshot.playerLevel, "-")
            " | " BC_State.DefaultText(snapshot.playerCallingName, "unknown")
            " | " BC_State.DefaultText(snapshot.playerRoleName, "unknown")
            " | HP " BC_State.PairOrDefaultText(snapshot.playerHealthCurrent, snapshot.playerHealthMax)
            " (" BC_State.PercentText(snapshot.playerHealthCurrent, snapshot.playerHealthMax) ")"
            " | " BC_State.DefaultText(snapshot.playerResourceKindName, "none")
            " " BC_State.PairOrDefaultText(snapshot.playerResourceCurrent, snapshot.playerResourceMax)
            " (" BC_State.PercentText(snapshot.playerResourceCurrent, snapshot.playerResourceMax) ")"
        )
        lines.Push("Player state: " BC_State.JoinTags(BC_State.BuildPlayerStateTags(snapshot)))
        lines.Push("Ops page age: " BC_State.DefaultText(snapshot.opsPageAgeMs, "-") " ms | Tactical page age: " BC_State.DefaultText(snapshot.tacticalPageAgeMs, "-") " ms")

        if BC_State.HasTarget(snapshot) {
            lines.Push(
                "Target: L" BC_State.DefaultText(snapshot.targetLevel, "-")
                " | HP " BC_State.PairOrDefaultText(snapshot.targetHealthCurrent, snapshot.targetHealthMax)
                " (" BC_State.PercentText(snapshot.targetHealthCurrent, snapshot.targetHealthMax) ")"
                " | " BC_State.DefaultText(snapshot.targetResourceKindName, "none")
                " " BC_State.PairOrDefaultText(snapshot.targetResourceCurrent, snapshot.targetResourceMax)
                " (" BC_State.PercentText(snapshot.targetResourceCurrent, snapshot.targetResourceMax) ")"
                " | " BC_State.DefaultText(snapshot.targetRelationName, "unknown")
                " | flags " BC_State.HexText(snapshot.targetFlags, 2)
            )
            lines.Push("Target state: " BC_State.JoinTags(BC_State.BuildTargetStateTags(snapshot)))
            lines.Push(
                "Tactical: dist " BC_State.DefaultText(snapshot.distanceXZ, "-")
                " | bucket " BC_State.DefaultText(snapshot.distanceBucketText, "-")
                " | sameZone " BC_State.BoolText(snapshot.sameZone)
                " | trend " BC_State.DefaultText(snapshot.rangeTrendText, "unknown")
                " | targetCalling " BC_State.DefaultText(snapshot.targetCallingName, "unknown")
            )
            lines.Push(
                "Motion: player " BC_State.DefaultText(snapshot.playerMoveState, "unknown")
                " (" BC_State.DefaultText(snapshot.playerMoveDeltaXZ, "-") ")"
                " | target " BC_State.DefaultText(snapshot.targetMoveState, "unknown")
                " (" BC_State.DefaultText(snapshot.targetMoveDeltaXZ, "-") ")"
            )
        } else {
            lines.Push("Target: none")
        }

        lines.Push(
            "Reader: " BC_State.DefaultText(snapshot.searchMode, "-")
            " | " BC_State.DefaultText(snapshot.captureSource, "-")
            " | route " BC_State.DefaultText(snapshot.captureRouteReason, "-")
            " | hint " BC_State.DefaultText(snapshot.captureHintMode, "-")
            " | capture " BC_State.DefaultText(snapshot.captureMs, "-") " ms"
            " | pipeline " BC_State.DefaultText(snapshot.pipelineMs, "-") " ms"
            " | reason " BC_State.DefaultText(snapshot.reason, "-")
        )
        lines.Push(
            "Rects: client " BC_State.RectText(snapshot.clientX, snapshot.clientY, snapshot.clientWidth, snapshot.clientHeight)
            " | capture " BC_State.RectText(snapshot.captureLeft, snapshot.captureTop, snapshot.captureWidth, snapshot.captureHeight)
        )
        lines.Push(
            "Session: " BC_State.DefaultText(snapshot.sessionSampleCount, "0")
            " samples | accepted " BC_State.DefaultText(snapshot.sessionAcceptedCount, "0")
            " | rejected " BC_State.DefaultText(snapshot.sessionRejectedCount, "0")
            " | streak " BC_State.DefaultText(snapshot.acceptedStreak, "0")
            "/" BC_State.DefaultText(snapshot.rejectedStreak, "0")
            " | repeats " BC_State.DefaultText(snapshot.sequenceRepeatedCount, "0")
            " | wraps " BC_State.DefaultText(snapshot.sequenceWrapCount, "0")
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
        fields.Push(BC_State.JsonNumberField("sampleAgeMs", BC_State.AgeMs(snapshot)))
        fields.Push(BC_State.JsonNumberField("sequence", snapshot.sequence))
        fields.Push(BC_State.JsonStringField("pageName", snapshot.pageName))
        fields.Push(BC_State.JsonBoolField("targetPresent", BC_State.HasTarget(snapshot)))
        fields.Push(BC_State.JsonStringField("playerStateText", BC_State.JoinTags(BC_State.BuildPlayerStateTags(snapshot))))
        fields.Push(BC_State.JsonStringField("targetStateText", BC_State.JoinTags(BC_State.BuildTargetStateTags(snapshot))))
        fields.Push(BC_State.JsonStringField("comparisonText", BC_State.BuildComparisonText(snapshot)))
        fields.Push(BC_State.JsonStringField("comparisonDeltaText", BC_State.BuildComparisonDeltaText(snapshot)))
        fields.Push(BC_State.JsonStringField("playerCallingName", snapshot.playerCallingName))
        fields.Push(BC_State.JsonStringField("playerRoleName", snapshot.playerRoleName))
        fields.Push(BC_State.JsonNumberField("playerLevel", snapshot.playerLevel))
        fields.Push(BC_State.JsonStringField("playerResourceKindName", snapshot.playerResourceKindName))
        fields.Push(BC_State.JsonNumberField("playerHealthCurrent", snapshot.playerHealthCurrent))
        fields.Push(BC_State.JsonNumberField("playerHealthMax", snapshot.playerHealthMax))
        fields.Push(BC_State.JsonNumberField("playerHealthPercent", BC_State.Percent(snapshot.playerHealthCurrent, snapshot.playerHealthMax)))
        fields.Push(BC_State.JsonNumberField("playerResourceCurrent", snapshot.playerResourceCurrent))
        fields.Push(BC_State.JsonNumberField("playerResourceMax", snapshot.playerResourceMax))
        fields.Push(BC_State.JsonNumberField("playerResourcePercent", BC_State.Percent(snapshot.playerResourceCurrent, snapshot.playerResourceMax)))
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
        fields.Push(BC_State.JsonNumberField("targetHealthPercent", BC_State.Percent(snapshot.targetHealthCurrent, snapshot.targetHealthMax)))
        fields.Push(BC_State.JsonNumberField("targetResourceCurrent", snapshot.targetResourceCurrent))
        fields.Push(BC_State.JsonNumberField("targetResourceMax", snapshot.targetResourceMax))
        fields.Push(BC_State.JsonNumberField("targetResourcePercent", BC_State.Percent(snapshot.targetResourceCurrent, snapshot.targetResourceMax)))
        fields.Push(BC_State.JsonNumberField("targetFlags", snapshot.targetFlags))
        fields.Push(BC_State.JsonStringField("targetRelationName", snapshot.targetRelationName))
        fields.Push(BC_State.JsonStringField("targetTierName", snapshot.targetTierName))
        fields.Push(BC_State.JsonStringField("targetTaggedName", snapshot.targetTaggedName))
        fields.Push(BC_State.JsonStringField("targetCallingName", snapshot.targetCallingName))
        fields.Push(BC_State.JsonStringField("playerMoveState", snapshot.playerMoveState))
        fields.Push(BC_State.JsonNumberField("playerMoveDeltaXZ", snapshot.playerMoveDeltaXZ))
        fields.Push(BC_State.JsonStringField("targetMoveState", snapshot.targetMoveState))
        fields.Push(BC_State.JsonNumberField("targetMoveDeltaXZ", snapshot.targetMoveDeltaXZ))
        fields.Push(BC_State.JsonBoolField("sameZone", snapshot.sameZone))
        fields.Push(BC_State.JsonNumberField("distanceXZ", snapshot.distanceXZ))
        fields.Push(BC_State.JsonNumberField("distanceDeltaXZ", snapshot.distanceDeltaXZ))
        fields.Push(BC_State.JsonStringField("distanceBucketText", snapshot.distanceBucketText))
        fields.Push(BC_State.JsonStringField("rangeTrendText", snapshot.rangeTrendText))
        fields.Push(BC_State.JsonStringField("searchMode", snapshot.searchMode))
        fields.Push(BC_State.JsonStringField("captureSource", snapshot.captureSource))
        fields.Push(BC_State.JsonStringField("captureRouteReason", snapshot.captureRouteReason))
        fields.Push(BC_State.JsonStringField("captureHintMode", snapshot.captureHintMode))
        fields.Push(BC_State.JsonNumberField("captureHintPitch", snapshot.captureHintPitch))
        fields.Push(BC_State.JsonNumberField("clientX", snapshot.clientX))
        fields.Push(BC_State.JsonNumberField("clientY", snapshot.clientY))
        fields.Push(BC_State.JsonNumberField("clientWidth", snapshot.clientWidth))
        fields.Push(BC_State.JsonNumberField("clientHeight", snapshot.clientHeight))
        fields.Push(BC_State.JsonNumberField("captureLeft", snapshot.captureLeft))
        fields.Push(BC_State.JsonNumberField("captureTop", snapshot.captureTop))
        fields.Push(BC_State.JsonNumberField("captureWidth", snapshot.captureWidth))
        fields.Push(BC_State.JsonNumberField("captureHeight", snapshot.captureHeight))
        fields.Push(BC_State.JsonNumberField("captureMs", snapshot.captureMs))
        fields.Push(BC_State.JsonNumberField("pipelineMs", snapshot.pipelineMs))
        fields.Push(BC_State.JsonNumberField("sessionSampleCount", snapshot.sessionSampleCount))
        fields.Push(BC_State.JsonNumberField("sessionAcceptedCount", snapshot.sessionAcceptedCount))
        fields.Push(BC_State.JsonNumberField("sessionRejectedCount", snapshot.sessionRejectedCount))
        fields.Push(BC_State.JsonNumberField("acceptedStreak", snapshot.acceptedStreak))
        fields.Push(BC_State.JsonNumberField("rejectedStreak", snapshot.rejectedStreak))
        fields.Push(BC_State.JsonNumberField("opsPageAgeMs", snapshot.opsPageAgeMs))
        fields.Push(BC_State.JsonNumberField("tacticalPageAgeMs", snapshot.tacticalPageAgeMs))
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
        ageText := BC_State.AgeText(snapshot, "")
        return (
            snapshot.timestampUtc
            " | " acceptedText
            " | seq " sequenceText
            " | conf " confidenceText
            (ageText = "" ? "" : (" | age " ageText))
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

    static BuildPlayerStateTags(snapshot) {
        tags := []
        stateFlags := Integer(snapshot.stateFlags || 0)
        castFlags := Integer(snapshot.playerCastFlags || 0)

        if BC_State.HasBit(stateFlags, 0x0001) {
            tags.Push("ready")
        }
        if BC_State.HasBit(stateFlags, 0x0002) {
            tags.Push("alive")
        }
        if BC_State.HasBit(stateFlags, 0x0004) {
            tags.Push("combat")
        }
        if BC_State.HasBit(stateFlags, 0x0008) {
            tags.Push("casting")
        }
        if BC_State.HasBit(stateFlags, 0x0010) {
            tags.Push("resource")
        }
        if BC_State.HasBit(castFlags, 0x02) {
            tags.Push("channel")
        }
        if BC_State.HasBit(castFlags, 0x04) {
            tags.Push("locked")
        }

        return tags
    }

    static BuildTargetStateTags(snapshot) {
        tags := []
        stateFlags := Integer(snapshot.stateFlags || 0)
        targetFlags := Integer(snapshot.targetFlags || 0)

        if BC_State.HasBit(stateFlags, 0x0020) {
            tags.Push("present")
        }
        if BC_State.HasBit(stateFlags, 0x0040) {
            tags.Push("alive")
        }
        if BC_State.HasBit(stateFlags, 0x0080) {
            tags.Push("combat")
        }
        if BC_State.HasBit(stateFlags, 0x0100) {
            tags.Push("resource")
        }
        if BC_State.HasBit(targetFlags, 0x01) {
            tags.Push("player")
        }
        if BC_State.HasBit(targetFlags, 0x02) {
            tags.Push("pet")
        }
        if (snapshot.targetRelationName != "" && snapshot.targetRelationName != "unknown") {
            tags.Push(snapshot.targetRelationName)
        }
        if (snapshot.targetTierName != "" && snapshot.targetTierName != "normal") {
            tags.Push(snapshot.targetTierName)
        }
        if (snapshot.targetTaggedName != "" && snapshot.targetTaggedName != "none") {
            tags.Push("tag:" snapshot.targetTaggedName)
        }

        return tags
    }

    static BuildComparisonText(snapshot) {
        if !BC_State.HasTarget(snapshot) {
            return "player-only"
        }

        playerResourceLabel := BC_State.DefaultText(snapshot.playerResourceKindName, "resource")
        targetResourceLabel := BC_State.DefaultText(snapshot.targetResourceKindName, "resource")
        resourceText := (playerResourceLabel = targetResourceLabel)
            ? (
                playerResourceLabel
                " "
                BC_State.PercentText(snapshot.playerResourceCurrent, snapshot.playerResourceMax)
                " vs "
                BC_State.PercentText(snapshot.targetResourceCurrent, snapshot.targetResourceMax)
            )
            : (
                playerResourceLabel
                " "
                BC_State.PercentText(snapshot.playerResourceCurrent, snapshot.playerResourceMax)
                " vs "
                targetResourceLabel
                " "
                BC_State.PercentText(snapshot.targetResourceCurrent, snapshot.targetResourceMax)
            )

        levelText := ""
        if (snapshot.playerLevel != "" || snapshot.targetLevel != "") {
            levelText := (
                " | L "
                BC_State.DefaultText(snapshot.playerLevel, "-")
                " vs "
                BC_State.DefaultText(snapshot.targetLevel, "-")
            )
        }

        distanceText := ""
        if (snapshot.distanceXZ != "") {
            distanceText := " | dist " snapshot.distanceXZ " (" BC_State.DefaultText(snapshot.distanceBucketText, "?") ")"
        }

        return (
            "HP "
            BC_State.PercentText(snapshot.playerHealthCurrent, snapshot.playerHealthMax)
            " vs "
            BC_State.PercentText(snapshot.targetHealthCurrent, snapshot.targetHealthMax)
            " | "
            resourceText
            levelText
            distanceText
        )
    }

    static BuildComparisonDeltaText(snapshot) {
        if !BC_State.HasTarget(snapshot) {
            return "player-only"
        }

        parts := []
        hpDelta := BC_State.PercentDeltaText(
            snapshot.playerHealthCurrent,
            snapshot.playerHealthMax,
            snapshot.targetHealthCurrent,
            snapshot.targetHealthMax
        )
        if (hpDelta != "") {
            parts.Push("HP " hpDelta)
        }

        resourceDelta := BC_State.PercentDeltaText(
            snapshot.playerResourceCurrent,
            snapshot.playerResourceMax,
            snapshot.targetResourceCurrent,
            snapshot.targetResourceMax
        )
        if (resourceDelta != "") {
            resourceLabel := BC_State.DefaultText(snapshot.playerResourceKindName, "resource")
            targetResourceLabel := BC_State.DefaultText(snapshot.targetResourceKindName, "resource")
            if (resourceLabel = targetResourceLabel) {
                parts.Push(resourceLabel " " resourceDelta)
            } else {
                parts.Push(resourceLabel " " resourceDelta " vs " targetResourceLabel)
            }
        }

        levelDelta := BC_State.SignedDeltaText(snapshot.playerLevel, snapshot.targetLevel)
        if (levelDelta != "") {
            parts.Push("L " levelDelta)
        }

        return parts.Length > 0 ? BC_Debug.Join(parts, " | ") : "unavailable"
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

    static RelationName(code) {
        if (code = 1) {
            return "friendly"
        }
        if (code = 2) {
            return "hostile"
        }
        if (code = 3) {
            return "neutral"
        }
        return "unknown"
    }

    static TierName(code) {
        if (code = 1) {
            return "group"
        }
        if (code = 2) {
            return "raid"
        }
        return "normal"
    }

    static TaggedName(code) {
        if (code = 1) {
            return "self"
        }
        if (code = 2) {
            return "other"
        }
        return "none"
    }

    static SameZone(snapshot) {
        return snapshot.playerZoneHash16 != "" && snapshot.targetZoneHash16 != "" && snapshot.playerZoneHash16 != 0 && snapshot.playerZoneHash16 = snapshot.targetZoneHash16
    }

    static DistanceXZ(snapshot) {
        if !BC_State.SameZone(snapshot) {
            return ""
        }
        if (snapshot.playerCoordX = "" || snapshot.playerCoordZ = "" || snapshot.targetCoordX = "" || snapshot.targetCoordZ = "") {
            return ""
        }

        dx := Number(snapshot.targetCoordX) - Number(snapshot.playerCoordX)
        dz := Number(snapshot.targetCoordZ) - Number(snapshot.playerCoordZ)
        return Round(Sqrt((dx * dx) + (dz * dz)), 1)
    }

    static MovementDeltaXZ(currentZoneHash, currentX, currentZ, previousZoneHash, previousX, previousZ) {
        if (currentZoneHash = "" || previousZoneHash = "" || currentZoneHash = 0 || currentZoneHash != previousZoneHash) {
            return ""
        }
        if (currentX = "" || currentZ = "" || previousX = "" || previousZ = "") {
            return ""
        }

        dx := Number(currentX) - Number(previousX)
        dz := Number(currentZ) - Number(previousZ)
        return Round(Sqrt((dx * dx) + (dz * dz)), 1)
    }

    static MovementStateText(deltaXZ) {
        if (deltaXZ = "") {
            return "unknown"
        }
        return deltaXZ >= 0.5 ? "moving" : "steady"
    }

    static RangeTrendText(distanceDeltaXZ) {
        if (distanceDeltaXZ = "") {
            return "unknown"
        }
        if (distanceDeltaXZ <= -0.5) {
            return "closing"
        }
        if (distanceDeltaXZ >= 0.5) {
            return "opening"
        }
        return "stable"
    }

    static DistanceBucket(distance) {
        if (distance = "") {
            return 0
        }
        if (distance <= 4.0) {
            return 1
        }
        if (distance <= 10.0) {
            return 2
        }
        if (distance <= 20.0) {
            return 3
        }
        if (distance <= 35.0) {
            return 4
        }
        return 5
    }

    static DistanceBucketName(bucket) {
        if (bucket = 1) {
            return "melee"
        }
        if (bucket = 2) {
            return "close"
        }
        if (bucket = 3) {
            return "near"
        }
        if (bucket = 4) {
            return "mid"
        }
        if (bucket = 5) {
            return "far"
        }
        return "unknown"
    }

    static RoundTenths(value) {
        if (value = "") {
            return ""
        }
        return Round(Number(value), 1)
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

    static JoinTags(tags, fallback := "-") {
        return IsObject(tags) && tags.Length > 0 ? BC_Debug.Join(tags, " ") : fallback
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

    static RectText(left, top, width, height, fallback := "-") {
        leftText := BC_State.NumberText(left)
        topText := BC_State.NumberText(top)
        widthText := BC_State.NumberText(width)
        heightText := BC_State.NumberText(height)
        if (leftText = "" || topText = "" || widthText = "" || heightText = "") {
            return fallback
        }
        return leftText "," topText " " widthText "x" heightText
    }

    static AgeMs(snapshot) {
        if !IsObject(snapshot) || !snapshot.HasOwnProp("timestampTickCount") || snapshot.timestampTickCount = "" {
            return ""
        }

        ageMs := A_TickCount - Integer(snapshot.timestampTickCount)
        return ageMs < 0 ? "" : ageMs
    }

    static AgeText(snapshot, fallback := "-") {
        ageMs := BC_State.AgeMs(snapshot)
        return ageMs = "" ? fallback : (ageMs " ms")
    }

    static Percent(current, maximum) {
        numericCurrent := Integer(current || 0)
        numericMaximum := Integer(maximum || 0)
        if (numericMaximum <= 0) {
            return ""
        }

        pct := Floor((numericCurrent * 100.0) / numericMaximum)
        if (pct < 0) {
            return 0
        }
        if (pct > 100) {
            return 100
        }
        return pct
    }

    static PercentText(current, maximum, fallback := "-") {
        pct := BC_State.Percent(current, maximum)
        return pct = "" ? fallback : (pct "%")
    }

    static PercentDeltaText(leftCurrent, leftMaximum, rightCurrent, rightMaximum) {
        leftPct := BC_State.Percent(leftCurrent, leftMaximum)
        rightPct := BC_State.Percent(rightCurrent, rightMaximum)
        if (leftPct = "" || rightPct = "") {
            return ""
        }

        return BC_State.SignedNumberText(leftPct - rightPct)
    }

    static SignedDeltaText(leftValue, rightValue) {
        if (leftValue = "" || rightValue = "") {
            return ""
        }
        return BC_State.SignedNumberText(Integer(leftValue) - Integer(rightValue))
    }

    static SignedNumberText(value) {
        numericValue := Integer(value)
        return (numericValue >= 0 ? "+" : "") numericValue
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

    static HasBit(value, mask) {
        return (Integer(value || 0) & mask) != 0
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
