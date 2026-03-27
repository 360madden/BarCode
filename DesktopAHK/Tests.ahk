/*
script name: DesktopAHK/Tests.ahk
version: 0.3.11
purpose: Runs schema-3 player-target HUD reader smoke, BMP, and live decode checks for BC-Strip/1.
dependencies: DesktopAHK/Config.ahk, DesktopAHK/Capture.ahk, DesktopAHK/Protocol.ahk, DesktopAHK/Detect.ahk, DesktopAHK/Decode.ahk, DesktopAHK/Validate.ahk, DesktopAHK/State.ahk, DesktopAHK/Debug.ahk
important assumptions: Uses exact-profile synthetic fixtures with crisp module edges and fixed-geometry BMP decode for the minimum smoke pass.
protocol version: BC-Strip/1
framework module role: Test harness
character count note: Character count not precomputed; measure with tooling if needed.
*/

class BC_Tests {
    static DeleteIfPresent(path) {
        if (path != "" && FileExist(path)) {
            FileDelete(path)
        }
    }

    static BuildUnavailableResult(reason, sourceKind := "unavailable", searchMode := "unavailable") {
        profile := BC_Protocol.GetProfile()
        details := {
            BorderErrors: 0,
            Threshold: 0,
            BlackMean: 0,
            WhiteMean: 0,
            MinMargin: 0,
            OriginX: 0,
            OriginY: 0,
            Pitch: 0,
            BandWidth: profile.BandWidth,
            BandHeight: profile.BandHeight,
            SearchMode: searchMode,
            Contrast: 0
        }
        image := {
            Width: profile.BandWidth,
            Height: profile.BandHeight,
            Pixels: Buffer(profile.BandWidth * profile.BandHeight * 3, 0),
            SourceKind: sourceKind,
            RequestedSource: sourceKind,
            ResolvedSource: sourceKind,
            CaptureRouteReason: sourceKind,
            CaptureFallbackFrom: "",
            HintMode: "none",
            HintPitch: "",
            HintOriginX: "",
            HintOriginY: ""
        }
        detection := BC_Interfaces.DetectionResult(profile, 0, 0, 0, 0, reason, 0, 0, 0, profile.BandWidth, profile.BandHeight, 0, searchMode)
        decodeResult := BC_Interfaces.DecodeResult([], 0, 0, 0)
        validation := BC_Interfaces.ValidationResult(false, reason, 0.0, details)
        context := {
            Image: image,
            Timings: {
                CaptureMs: 0,
                PipelineMs: 0,
                AttemptCount: 0
            },
            CaptureAttempts: [sourceKind]
        }

        BC_State.Update(validation, context)
        BC_State.WriteSnapshot()

        return {
            Image: image,
            Detection: detection,
            Decode: decodeResult,
            Validation: validation,
            Timings: context.Timings,
            CaptureAttempts: context.CaptureAttempts
        }
    }

    static DecodeSyntheticHot(sequence := 42) {
        profile := BC_Protocol.GetProfile()
        snapshot := BC_Protocol.BuildSyntheticHotSnapshot()
        expectedBytes := BC_Protocol.BuildLiveFrameBytes(snapshot, sequence, BC_Config.PageIdPlayerCoreHot)
        matrix := BC_Protocol.BuildModuleMatrix(profile, expectedBytes)
        pixels := BC_Tests.RenderMatrixToPixels(profile, matrix)

        return BC_Tests.DecodeImage({
            Width: profile.BandWidth,
            Height: profile.BandHeight,
            Pixels: pixels,
            SourceKind: "synthetic"
        })
    }

    static RunReaderSmoke() {
        BC_Debug.WriteText(BC_Debug.TracePath(), "tests.run:start`r`n")

        profile := BC_Protocol.GetProfile()
        snapshot := BC_Protocol.BuildSyntheticHotSnapshot()
        expectedBytes := BC_Protocol.BuildLiveFrameBytes(snapshot, 42, BC_Config.PageIdPlayerCoreHot)
        BC_Debug.Trace("tests.run:bytes`r`n")

        goodMatrix := BC_Protocol.BuildModuleMatrix(profile, expectedBytes)
        goodPixels := BC_Tests.RenderMatrixToPixels(profile, goodMatrix)
        BC_Debug.WriteBmp24(BC_Config.GoodFixturePath, profile.BandWidth, profile.BandHeight, goodPixels)
        BC_Debug.Trace("tests.run:good-fixture`r`n")

        goodResult := BC_Tests.DecodeBmp(BC_Config.GoodFixturePath)

        corruptMatrix := BC_Protocol.BuildModuleMatrix(profile, expectedBytes)
        corruptMatrix[2][2] := (corruptMatrix[2][2] = 1) ? 0 : 1
        corruptPixels := BC_Tests.RenderMatrixToPixels(profile, corruptMatrix)
        BC_Debug.WriteBmp24(BC_Config.CorruptFixturePath, profile.BandWidth, profile.BandHeight, corruptPixels)
        BC_Debug.Trace("tests.run:corrupt-fixture`r`n")

        corruptResult := BC_Tests.DecodeBmp(BC_Config.CorruptFixturePath)

        success := goodResult.Validation.IsAccepted && !corruptResult.Validation.IsAccepted
        reportLines := []
        reportLines.Push("BarCode schema-3 reader smoke report")
        reportLines.Push("Success: " BC_Tests.BoolText(success))
        reportLines.Push("Good fixture: " BC_Config.GoodFixturePath)
        reportLines.Push("Corrupt fixture: " BC_Config.CorruptFixturePath)
        reportLines.Push("")
        reportLines.Push("Expected bytes[1..16]: " BC_Debug.Hex(expectedBytes, 1, 16))
        reportLines.Push("Good accepted: " BC_Tests.BoolText(goodResult.Validation.IsAccepted))
        reportLines.Push("Good reason: " goodResult.Validation.Reason)
        reportLines.Push("Good sequence: " goodResult.Validation.Details.Transport.Sequence)
        reportLines.Push("Good page id: " goodResult.Validation.Details.Transport.PageId)
        reportLines.Push("Good payload length: " goodResult.Validation.Details.Transport.PayloadUsedLength)
        reportLines.Push("Good player health: " goodResult.Validation.Details.HotPage.PlayerHealthCurrent "/" goodResult.Validation.Details.HotPage.PlayerHealthMax)
        reportLines.Push("Good player resource: " goodResult.Validation.Details.HotPage.PlayerResourceCurrent "/" goodResult.Validation.Details.HotPage.PlayerResourceMax)
        reportLines.Push("Good player cast progress q15: " goodResult.Validation.Details.HotPage.PlayerCastProgressQ15)
        reportLines.Push("Good player level/calling/role: " goodResult.Validation.Details.HotPage.PlayerLevel "/" goodResult.Validation.Details.HotPage.PlayerCallingCode "/" goodResult.Validation.Details.HotPage.PlayerRoleCode)
        reportLines.Push("Good player offense: atk=" goodResult.Validation.Details.HotPage.PlayerPowerAttack " critAtk=" goodResult.Validation.Details.HotPage.PlayerCritAttack " spell=" goodResult.Validation.Details.HotPage.PlayerPowerSpell " critSpell=" goodResult.Validation.Details.HotPage.PlayerCritSpell " critPower=" goodResult.Validation.Details.HotPage.PlayerCritPower " hit=" goodResult.Validation.Details.HotPage.PlayerHit)
        reportLines.Push("Good target health: " goodResult.Validation.Details.HotPage.TargetHealthCurrent "/" goodResult.Validation.Details.HotPage.TargetHealthMax)
        reportLines.Push("Good target resource: " goodResult.Validation.Details.HotPage.TargetResourceCurrent "/" goodResult.Validation.Details.HotPage.TargetResourceMax)
        reportLines.Push("Good target level/flags: " goodResult.Validation.Details.HotPage.TargetLevel "/" goodResult.Validation.Details.HotPage.TargetFlags)
        reportLines.Push("Good sample mask: 0x" Format("{:04X}", goodResult.Validation.Details.HotPage.SampleMask))
        reportLines.Push("Good state flags: 0x" Format("{:04X}", goodResult.Validation.Details.HotPage.StateFlags))
        reportLines.Push("Good confidence: " goodResult.Validation.Confidence)
        reportLines.Push("")
        reportLines.Push("Corrupt accepted: " BC_Tests.BoolText(corruptResult.Validation.IsAccepted))
        reportLines.Push("Corrupt reason: " corruptResult.Validation.Reason)
        reportLines.Push("Corrupt decoded bytes[1..16]: " BC_Debug.Hex(corruptResult.Decode.Bytes, 1, 16))

        report := BC_Debug.Join(reportLines, "`r`n")
        BC_Debug.WriteText(BC_Config.SmokeReportPath, report)
        BC_State.Update(goodResult.Validation, {
            Image: goodResult.Image,
            Timings: {
                CaptureMs: 0,
                PipelineMs: 0,
                AttemptCount: 1
            },
            CaptureAttempts: [goodResult.Image.SourceKind],
            SampleIndex: 1
        }, true)

        return {
            Success: success,
            ReportPath: BC_Config.SmokeReportPath,
            GoodFixturePath: BC_Config.GoodFixturePath,
            CorruptFixturePath: BC_Config.CorruptFixturePath,
            Summary: {
                Mode: "smoke",
                Success: success,
                GoodAccepted: goodResult.Validation.IsAccepted,
                GoodReason: goodResult.Validation.Reason,
                CorruptAccepted: corruptResult.Validation.IsAccepted,
                CorruptReason: corruptResult.Validation.Reason
            }
        }
    }

    static RunFixedBmpDecode(path, cropX := 0, cropY := 0) {
        result := BC_Tests.DecodeBmp(path, cropX, cropY)
        validation := result.Validation
        details := validation.Details
        BC_State.Update(validation, {
            Image: result.Image,
            Timings: {
                CaptureMs: 0,
                PipelineMs: 0,
                AttemptCount: 1
            },
            CaptureAttempts: [result.Image.SourceKind],
            SampleIndex: 1
        }, true)
        reportLines := []
        reportLines.Push("BarCode fixed BMP decode report")
        reportLines.Push("Input: " path)
        reportLines.Push("CropOrigin: " cropX "," cropY)
        reportLines.Push("Accepted: " BC_Tests.BoolText(validation.IsAccepted))
        reportLines.Push("Reason: " validation.Reason)
        reportLines.Push("SearchMode: " details.SearchMode)
        reportLines.Push("Origin: " details.OriginX "," details.OriginY)
        reportLines.Push("Pitch: " Round(details.Pitch, 3))
        reportLines.Push("BandSize: " Round(details.BandWidth, 3) "x" Round(details.BandHeight, 3))
        reportLines.Push("BorderErrors: " details.BorderErrors)
        reportLines.Push("Threshold: " details.Threshold)
        reportLines.Push("BlackMean: " Round(details.BlackMean, 3))
        reportLines.Push("WhiteMean: " Round(details.WhiteMean, 3))

        if (details.HasOwnProp("Transport")) {
            reportLines.Push("Sequence: " details.Transport.Sequence)
            reportLines.Push("PageId: " details.Transport.PageId)
            reportLines.Push("PayloadUsedLength: " details.Transport.PayloadUsedLength)
        }

        if (details.HasOwnProp("HotPage")) {
            reportLines.Push("PlayerHealth: " details.HotPage.PlayerHealthCurrent "/" details.HotPage.PlayerHealthMax)
            reportLines.Push("PlayerResource: " details.HotPage.PlayerResourceCurrent "/" details.HotPage.PlayerResourceMax)
            reportLines.Push("PlayerCastProgressQ15: " details.HotPage.PlayerCastProgressQ15)
            reportLines.Push("PlayerLevel: " details.HotPage.PlayerLevel)
            reportLines.Push("PlayerCallingCode: " details.HotPage.PlayerCallingCode)
            reportLines.Push("PlayerRoleCode: " details.HotPage.PlayerRoleCode)
            reportLines.Push("PlayerOffense: atk=" details.HotPage.PlayerPowerAttack " critAtk=" details.HotPage.PlayerCritAttack " spell=" details.HotPage.PlayerPowerSpell " critSpell=" details.HotPage.PlayerCritSpell " critPower=" details.HotPage.PlayerCritPower " hit=" details.HotPage.PlayerHit)
            reportLines.Push("TargetHealth: " details.HotPage.TargetHealthCurrent "/" details.HotPage.TargetHealthMax)
            reportLines.Push("TargetResource: " details.HotPage.TargetResourceCurrent "/" details.HotPage.TargetResourceMax)
            reportLines.Push("TargetLevel: " details.HotPage.TargetLevel)
            reportLines.Push("TargetFlags: " details.HotPage.TargetFlags)
        }

        reportLines.Push("Confidence: " validation.Confidence)
        reportLines.Push("Decoded bytes[1..16]: " BC_Debug.Hex(result.Decode.Bytes, 1, 16))
        BC_Debug.WriteText(BC_Config.FixedBmpReportPath, BC_Debug.Join(reportLines, "`r`n"))

        return {
            Success: validation.IsAccepted,
            ReportPath: BC_Config.FixedBmpReportPath,
            Summary: {
                Mode: "bmp",
                Accepted: validation.IsAccepted,
                Reason: validation.Reason,
                SearchMode: details.SearchMode,
                Sequence: details.HasOwnProp("Transport") ? details.Transport.Sequence : "",
                PageId: details.HasOwnProp("Transport") ? details.Transport.PageId : ""
            }
        }
    }

    static RunLiveDecode(sampleCount := 20, sleepMs := 100) {
        hwnd := BC_Capture.FindRiftWindow()
        if !hwnd {
            throw Error("No likely RIFT window was found for live capture.")
        }

        acceptedCount := 0
        rejectedCount := 0
        firstAcceptedSequence := ""
        lastResult := ""
        totalCaptureMs := 0
        totalPipelineMs := 0
        lockedPipelineMs := 0
        searchedPipelineMs := 0
        fallbackSampleCount := 0
        maxCaptureMs := 0
        maxPipelineMs := 0
        lockedCount := 0
        searchedCount := 0
        captureSources := Map()
        captureRoutes := Map()
        captureHints := Map()
        rejectReasons := Map()
        firstSampleCaptureMs := ""
        firstSamplePipelineMs := ""
        firstRejectedReason := ""
        firstRejectedResult := ""
        sampleIndex := 1
        sourcePreference := "auto"
        title := WinGetTitle("ahk_id " hwnd)
        processName := WinGetProcessName("ahk_id " hwnd)

        BC_State.ResetLiveOutputs()
        BC_Tests.DeleteIfPresent(BC_Config.LiveRejectBmpPath)
        BC_Tests.DeleteIfPresent(BC_Config.LiveCaptureBmpPath)

        while (sampleIndex <= sampleCount) {
            result := BC_Tests.DecodeLiveFrame(hwnd, 0, 0, sourcePreference)
            sourcePreference := result.HasOwnProp("PreferredSource") ? result.PreferredSource : "auto"
            BC_Tests.ApplyLiveFrameState(result, sampleIndex, title, processName, true)
            validation := result.Validation
            totalCaptureMs += result.Timings.CaptureMs
            totalPipelineMs += result.Timings.PipelineMs
            if (sampleIndex = 1) {
                firstSampleCaptureMs := result.Timings.CaptureMs
                firstSamplePipelineMs := result.Timings.PipelineMs
            }
            if (result.Timings.CaptureMs > maxCaptureMs) {
                maxCaptureMs := result.Timings.CaptureMs
            }
            if (result.Timings.PipelineMs > maxPipelineMs) {
                maxPipelineMs := result.Timings.PipelineMs
            }
            if (result.Timings.AttemptCount > 1) {
                fallbackSampleCount += 1
            }
            BC_Tests.IncrementCount(captureSources, result.Image.HasOwnProp("SourceKind") ? result.Image.SourceKind : "unknown")
            BC_Tests.IncrementCount(captureRoutes, result.Image.HasOwnProp("CaptureRouteReason") ? result.Image.CaptureRouteReason : "unknown")
            BC_Tests.IncrementCount(captureHints, result.Image.HasOwnProp("HintMode") ? result.Image.HintMode : "unknown")
            if (validation.IsAccepted) {
                acceptedCount += 1
                if (firstAcceptedSequence = "" && validation.Details.HasOwnProp("Transport")) {
                    firstAcceptedSequence := validation.Details.Transport.Sequence
                }
            } else {
                rejectedCount += 1
                if (firstRejectedReason = "") {
                    firstRejectedReason := validation.Reason
                }
                if !IsObject(firstRejectedResult) {
                    firstRejectedResult := result
                }
                BC_Tests.IncrementCount(rejectReasons, validation.Reason)
            }

            lastResult := result
            if (result.Detection.SearchMode = "locked") {
                lockedPipelineMs += result.Timings.PipelineMs
                lockedCount += 1
            } else {
                searchedPipelineMs += result.Timings.PipelineMs
                searchedCount += 1
            }
            if (sampleIndex < sampleCount && sleepMs > 0) {
                Sleep sleepMs
            }
            sampleIndex += 1
        }

        if !IsObject(lastResult) {
            throw Error("Live decode produced no samples.")
        }

        client := lastResult.Image.ClientRect
        validation := lastResult.Validation
        details := validation.Details
        hotPage := details.HasOwnProp("HotPage") ? details.HotPage : {}
        transport := details.HasOwnProp("Transport") ? details.Transport : {}

        BC_Debug.WriteBmp24(BC_Config.LiveCaptureBmpPath, lastResult.Image.Width, lastResult.Image.Height, lastResult.Image.Pixels)
        if IsObject(firstRejectedResult) {
            BC_Debug.WriteBmp24(BC_Config.LiveRejectBmpPath, firstRejectedResult.Image.Width, firstRejectedResult.Image.Height, firstRejectedResult.Image.Pixels)
        }

        reportLines := []
        reportLines.Push("BarCode live decode report")
        reportLines.Push("WindowTitle: " title)
        reportLines.Push("ProcessName: " processName)
        reportLines.Push("ClientRect: " client.x "," client.y " " client.width "x" client.height)
        reportLines.Push("Samples: " sampleCount)
        reportLines.Push("SleepMs: " sleepMs)
        reportLines.Push("AcceptedSamples: " acceptedCount)
        reportLines.Push("RejectedSamples: " rejectedCount)
        reportLines.Push("LockedSamples: " lockedCount)
        reportLines.Push("SearchedSamples: " searchedCount)
        reportLines.Push("CaptureSource: " (lastResult.Image.HasOwnProp("SourceKind") ? lastResult.Image.SourceKind : ""))
        reportLines.Push("CaptureRequestedSource: " (lastResult.Image.HasOwnProp("RequestedSource") ? lastResult.Image.RequestedSource : ""))
        reportLines.Push("CaptureResolvedSource: " (lastResult.Image.HasOwnProp("ResolvedSource") ? lastResult.Image.ResolvedSource : ""))
        reportLines.Push("CaptureRouteReason: " (lastResult.Image.HasOwnProp("CaptureRouteReason") ? lastResult.Image.CaptureRouteReason : ""))
        reportLines.Push("CaptureHintMode: " (lastResult.Image.HasOwnProp("HintMode") ? lastResult.Image.HintMode : ""))
        reportLines.Push("CaptureHintPitch: " (lastResult.Image.HasOwnProp("HintPitch") ? lastResult.Image.HintPitch : ""))
        reportLines.Push("CaptureRect: " lastResult.Image.SourceLeft "," lastResult.Image.SourceTop " " lastResult.Image.SourceWidth "x" lastResult.Image.SourceHeight)
        reportLines.Push("CaptureAttempts: " (lastResult.HasOwnProp("CaptureAttempts") ? BC_Debug.Join(lastResult.CaptureAttempts, ",") : ""))
        reportLines.Push("FallbackSamples: " fallbackSampleCount)
        reportLines.Push("CaptureSourceCounts: " BC_Tests.FormatCountMap(captureSources))
        reportLines.Push("CaptureRouteCounts: " BC_Tests.FormatCountMap(captureRoutes))
        reportLines.Push("CaptureHintCounts: " BC_Tests.FormatCountMap(captureHints))
        reportLines.Push("AverageCaptureMs: " Round(totalCaptureMs / sampleCount, 2))
        reportLines.Push("AveragePipelineMs: " Round(totalPipelineMs / sampleCount, 2))
        reportLines.Push("FirstSampleCaptureMs: " firstSampleCaptureMs)
        reportLines.Push("FirstSamplePipelineMs: " firstSamplePipelineMs)
        reportLines.Push("AverageLockedPipelineMs: " (lockedCount ? Round(lockedPipelineMs / lockedCount, 2) : 0))
        reportLines.Push("AverageSearchedPipelineMs: " (searchedCount ? Round(searchedPipelineMs / searchedCount, 2) : 0))
        reportLines.Push("MaxCaptureMs: " maxCaptureMs)
        reportLines.Push("MaxPipelineMs: " maxPipelineMs)
        reportLines.Push("FirstAcceptedSequence: " firstAcceptedSequence)
        reportLines.Push("FirstRejectedReason: " firstRejectedReason)
        reportLines.Push("RejectReasonCounts: " BC_Tests.FormatCountMap(rejectReasons))
        reportLines.Push("FirstRejectedBmp: " (IsObject(firstRejectedResult) ? BC_Config.LiveRejectBmpPath : "-"))
        reportLines.Push("LastAccepted: " BC_Tests.BoolText(validation.IsAccepted))
        reportLines.Push("LastReason: " validation.Reason)
        reportLines.Push("LastConfidence: " validation.Confidence)
        reportLines.Push("SearchMode: " details.SearchMode)
        reportLines.Push("Origin: " details.OriginX "," details.OriginY)
        reportLines.Push("Pitch: " Round(details.Pitch, 3))
        reportLines.Push("BandSize: " Round(details.BandWidth, 3) "x" Round(details.BandHeight, 3))
        reportLines.Push("BorderErrors: " details.BorderErrors)
        if (transport.HasOwnProp("Sequence")) {
            reportLines.Push("LastSequence: " transport.Sequence)
            reportLines.Push("LastPageId: " transport.PageId)
        }
        if (hotPage.HasOwnProp("PlayerHealthCurrent")) {
            reportLines.Push("PlayerHealth: " hotPage.PlayerHealthCurrent "/" hotPage.PlayerHealthMax)
            reportLines.Push("PlayerResource: " hotPage.PlayerResourceCurrent "/" hotPage.PlayerResourceMax)
            reportLines.Push("PlayerCastProgressQ15: " hotPage.PlayerCastProgressQ15)
            reportLines.Push("PlayerLevel: " hotPage.PlayerLevel)
            reportLines.Push("PlayerCallingCode: " hotPage.PlayerCallingCode)
            reportLines.Push("PlayerRoleCode: " hotPage.PlayerRoleCode)
            reportLines.Push("PlayerOffense: atk=" hotPage.PlayerPowerAttack " critAtk=" hotPage.PlayerCritAttack " spell=" hotPage.PlayerPowerSpell " critSpell=" hotPage.PlayerCritSpell " critPower=" hotPage.PlayerCritPower " hit=" hotPage.PlayerHit)
            reportLines.Push("TargetHealth: " hotPage.TargetHealthCurrent "/" hotPage.TargetHealthMax)
            reportLines.Push("TargetResource: " hotPage.TargetResourceCurrent "/" hotPage.TargetResourceMax)
            reportLines.Push("TargetLevel: " hotPage.TargetLevel)
            reportLines.Push("TargetFlags: " hotPage.TargetFlags)
        }
        reportLines.Push("Decoded bytes[1..16]: " BC_Debug.Hex(lastResult.Decode.Bytes, 1, 16))
        reportLines.Push("LastCaptureBmp: " BC_Config.LiveCaptureBmpPath)
        reportLines.Push("StateHistoryJson: " BC_Config.LiveHistoryJsonPath)
        reportLines.Push("StateHistoryJsonl: " BC_Config.LiveHistoryJsonlPath)

        BC_Debug.WriteText(BC_Config.LiveReportPath, BC_Debug.Join(reportLines, "`r`n"))

        return {
            Success: acceptedCount > 0,
            ReportPath: BC_Config.LiveReportPath,
            Summary: {
                Mode: "live",
                AcceptedSamples: acceptedCount,
                RejectedSamples: rejectedCount,
                LockedSamples: lockedCount,
                SearchedSamples: searchedCount,
                CaptureSource: lastResult.Image.HasOwnProp("SourceKind") ? lastResult.Image.SourceKind : "",
                CaptureRouteReason: lastResult.Image.HasOwnProp("CaptureRouteReason") ? lastResult.Image.CaptureRouteReason : "",
                CaptureHintMode: lastResult.Image.HasOwnProp("HintMode") ? lastResult.Image.HintMode : "",
                FallbackSamples: fallbackSampleCount,
                LastReason: validation.Reason
            }
        }
    }

    static RunLiveWatch(durationSeconds := 0, sleepMs := 100) {
        hwnd := BC_Capture.FindRiftWindow()
        if !hwnd {
            throw Error("No likely RIFT window was found for live capture.")
        }

        title := WinGetTitle("ahk_id " hwnd)
        processName := WinGetProcessName("ahk_id " hwnd)
        startedAt := A_TickCount
        sampleIndex := 1
        sourcePreference := "auto"
        acceptedCount := 0
        rejectedCount := 0
        lastResult := ""
        totalCaptureMs := 0
        totalPipelineMs := 0
        lockedPipelineMs := 0
        searchedPipelineMs := 0
        fallbackSampleCount := 0
        maxCaptureMs := 0
        maxPipelineMs := 0
        lockedCount := 0
        searchedCount := 0
        captureSources := Map()
        captureRoutes := Map()
        captureHints := Map()
        rejectReasons := Map()
        firstRejectedReason := ""
        firstRejectedResult := ""

        BC_State.ResetLiveOutputs()
        BC_Tests.DeleteIfPresent(BC_Config.LiveWatchRejectBmpPath)

        while (durationSeconds <= 0 || (A_TickCount - startedAt) < (durationSeconds * 1000)) {
            result := BC_Tests.DecodeLiveFrame(hwnd, 0, 0, sourcePreference)
            sourcePreference := result.HasOwnProp("PreferredSource") ? result.PreferredSource : "auto"
            BC_Tests.ApplyLiveFrameState(result, sampleIndex, title, processName, true)
            validation := result.Validation
            totalCaptureMs += result.Timings.CaptureMs
            totalPipelineMs += result.Timings.PipelineMs
            if (result.Timings.CaptureMs > maxCaptureMs) {
                maxCaptureMs := result.Timings.CaptureMs
            }
            if (result.Timings.PipelineMs > maxPipelineMs) {
                maxPipelineMs := result.Timings.PipelineMs
            }
            if (result.Timings.AttemptCount > 1) {
                fallbackSampleCount += 1
            }
            BC_Tests.IncrementCount(captureSources, result.Image.HasOwnProp("SourceKind") ? result.Image.SourceKind : "unknown")
            BC_Tests.IncrementCount(captureRoutes, result.Image.HasOwnProp("CaptureRouteReason") ? result.Image.CaptureRouteReason : "unknown")
            BC_Tests.IncrementCount(captureHints, result.Image.HasOwnProp("HintMode") ? result.Image.HintMode : "unknown")
            if (validation.IsAccepted) {
                acceptedCount += 1
            } else {
                rejectedCount += 1
                if (firstRejectedReason = "") {
                    firstRejectedReason := validation.Reason
                }
                if !IsObject(firstRejectedResult) {
                    firstRejectedResult := result
                }
                BC_Tests.IncrementCount(rejectReasons, validation.Reason)
            }

            if (result.Detection.SearchMode = "locked") {
                lockedPipelineMs += result.Timings.PipelineMs
                lockedCount += 1
            } else {
                searchedPipelineMs += result.Timings.PipelineMs
                searchedCount += 1
            }

            lastResult := result
            if (sleepMs > 0) {
                Sleep sleepMs
            }
            sampleIndex += 1
        }

        if !IsObject(lastResult) {
            throw Error("Live watch produced no samples.")
        }

        sampleCount := sampleIndex - 1
        client := lastResult.Image.ClientRect
        validation := lastResult.Validation
        details := validation.Details
        if IsObject(firstRejectedResult) {
            BC_Debug.WriteBmp24(BC_Config.LiveWatchRejectBmpPath, firstRejectedResult.Image.Width, firstRejectedResult.Image.Height, firstRejectedResult.Image.Pixels)
        }
        reportLines := []
        reportLines.Push("BarCode live watch report")
        reportLines.Push("WindowTitle: " title)
        reportLines.Push("ProcessName: " processName)
        reportLines.Push("ClientRect: " client.x "," client.y " " client.width "x" client.height)
        reportLines.Push("DurationSeconds: " durationSeconds)
        reportLines.Push("SleepMs: " sleepMs)
        reportLines.Push("Samples: " sampleCount)
        reportLines.Push("AcceptedSamples: " acceptedCount)
        reportLines.Push("RejectedSamples: " rejectedCount)
        reportLines.Push("LockedSamples: " lockedCount)
        reportLines.Push("SearchedSamples: " searchedCount)
        reportLines.Push("CaptureSource: " (lastResult.Image.HasOwnProp("SourceKind") ? lastResult.Image.SourceKind : ""))
        reportLines.Push("CaptureRequestedSource: " (lastResult.Image.HasOwnProp("RequestedSource") ? lastResult.Image.RequestedSource : ""))
        reportLines.Push("CaptureResolvedSource: " (lastResult.Image.HasOwnProp("ResolvedSource") ? lastResult.Image.ResolvedSource : ""))
        reportLines.Push("CaptureRouteReason: " (lastResult.Image.HasOwnProp("CaptureRouteReason") ? lastResult.Image.CaptureRouteReason : ""))
        reportLines.Push("CaptureHintMode: " (lastResult.Image.HasOwnProp("HintMode") ? lastResult.Image.HintMode : ""))
        reportLines.Push("CaptureHintPitch: " (lastResult.Image.HasOwnProp("HintPitch") ? lastResult.Image.HintPitch : ""))
        reportLines.Push("CaptureRect: " lastResult.Image.SourceLeft "," lastResult.Image.SourceTop " " lastResult.Image.SourceWidth "x" lastResult.Image.SourceHeight)
        reportLines.Push("CaptureAttempts: " (lastResult.HasOwnProp("CaptureAttempts") ? BC_Debug.Join(lastResult.CaptureAttempts, ",") : ""))
        reportLines.Push("FallbackSamples: " fallbackSampleCount)
        reportLines.Push("CaptureSourceCounts: " BC_Tests.FormatCountMap(captureSources))
        reportLines.Push("CaptureRouteCounts: " BC_Tests.FormatCountMap(captureRoutes))
        reportLines.Push("CaptureHintCounts: " BC_Tests.FormatCountMap(captureHints))
        reportLines.Push("AverageCaptureMs: " Round(totalCaptureMs / Max(1, sampleCount), 2))
        reportLines.Push("AveragePipelineMs: " Round(totalPipelineMs / Max(1, sampleCount), 2))
        reportLines.Push("AverageLockedPipelineMs: " (lockedCount ? Round(lockedPipelineMs / lockedCount, 2) : 0))
        reportLines.Push("AverageSearchedPipelineMs: " (searchedCount ? Round(searchedPipelineMs / searchedCount, 2) : 0))
        reportLines.Push("MaxCaptureMs: " maxCaptureMs)
        reportLines.Push("MaxPipelineMs: " maxPipelineMs)
        reportLines.Push("FirstRejectedReason: " firstRejectedReason)
        reportLines.Push("RejectReasonCounts: " BC_Tests.FormatCountMap(rejectReasons))
        reportLines.Push("FirstRejectedBmp: " (IsObject(firstRejectedResult) ? BC_Config.LiveWatchRejectBmpPath : "-"))
        reportLines.Push("LastAccepted: " BC_Tests.BoolText(validation.IsAccepted))
        reportLines.Push("LastReason: " validation.Reason)
        reportLines.Push("LastConfidence: " validation.Confidence)
        reportLines.Push("SearchMode: " details.SearchMode)
        reportLines.Push("Origin: " details.OriginX "," details.OriginY)
        reportLines.Push("Pitch: " Round(details.Pitch, 3))
        reportLines.Push("BandSize: " Round(details.BandWidth, 3) "x" Round(details.BandHeight, 3))
        reportLines.Push("BorderErrors: " details.BorderErrors)
        reportLines.Push("StateJson: " BC_Config.LiveStateJsonPath)
        reportLines.Push("StateText: " BC_Config.LiveStateTextPath)
        reportLines.Push("StateHistoryJson: " BC_Config.LiveHistoryJsonPath)
        reportLines.Push("StateHistoryJsonl: " BC_Config.LiveHistoryJsonlPath)
        BC_Debug.WriteText(BC_Config.LiveWatchReportPath, BC_Debug.Join(reportLines, "`r`n"))

        return {
            Success: acceptedCount > 0,
            ReportPath: BC_Config.LiveWatchReportPath,
            Summary: {
                Mode: "watch",
                AcceptedSamples: acceptedCount,
                RejectedSamples: rejectedCount,
                LockedSamples: lockedCount,
                SearchedSamples: searchedCount,
                CaptureSource: lastResult.Image.HasOwnProp("SourceKind") ? lastResult.Image.SourceKind : "",
                CaptureRouteReason: lastResult.Image.HasOwnProp("CaptureRouteReason") ? lastResult.Image.CaptureRouteReason : "",
                CaptureHintMode: lastResult.Image.HasOwnProp("HintMode") ? lastResult.Image.HintMode : "",
                FallbackSamples: fallbackSampleCount,
                LastReason: validation.Reason
            }
        }
    }

    static DecodeBmp(path, cropX := 0, cropY := 0) {
        profile := BC_Protocol.GetProfile()
        image := BC_Capture.AcquireFromBmp(path, cropX, cropY)
        return BC_Tests.DecodeImage(image)
    }

    static DecodeLiveFrame(hwnd, cropX := 0, cropY := 0, sourcePreference := "auto") {
        totalCaptureMs := 0
        totalPipelineMs := 0
        attemptSources := []
        geometryHint := BC_State.GetLockedGeometryForClient(BC_Capture.GetClientRectOnScreen(hwnd))

        captureStarted := A_TickCount
        primaryImage := BC_Capture.AcquireFromWindow(hwnd, cropX, cropY, sourcePreference, geometryHint)
        totalCaptureMs += A_TickCount - captureStarted
        attemptSources.Push(primaryImage.SourceKind)

        pipelineStarted := A_TickCount
        bestResult := BC_Tests.TryDecodeImage(primaryImage, geometryHint)
        totalPipelineMs += A_TickCount - pipelineStarted

        if (!bestResult.Validation.IsAccepted && IsObject(geometryHint) && bestResult.Detection.SearchMode = "locked") {
            BC_Debug.Trace("tests.live:relock-search=primary`r`n")
            pipelineStarted := A_TickCount
            relockResult := BC_Tests.TryDecodeImage(primaryImage, "", false)
            totalPipelineMs += A_TickCount - pipelineStarted

            if (BC_Tests.IsPreferredLiveResult(relockResult, bestResult)) {
                bestResult := relockResult
            }
        }

        if !bestResult.Validation.IsAccepted {
            fallbackSource := primaryImage.SourceKind = "printwindow-client" ? "screen" : "printwindow"
            BC_Debug.Trace("tests.live:fallback=" fallbackSource "`r`n")
            captureStarted := A_TickCount
            fallbackImage := BC_Capture.AcquireFromWindow(hwnd, cropX, cropY, fallbackSource, geometryHint)
            totalCaptureMs += A_TickCount - captureStarted
            attemptSources.Push(fallbackImage.SourceKind)

            pipelineStarted := A_TickCount
            fallbackResult := BC_Tests.TryDecodeImage(fallbackImage, geometryHint)
            totalPipelineMs += A_TickCount - pipelineStarted

            if (!fallbackResult.Validation.IsAccepted && IsObject(geometryHint) && fallbackResult.Detection.SearchMode = "locked") {
                BC_Debug.Trace("tests.live:relock-search=fallback`r`n")
                pipelineStarted := A_TickCount
                fallbackSearchResult := BC_Tests.TryDecodeImage(fallbackImage, "", false)
                totalPipelineMs += A_TickCount - pipelineStarted

                if (BC_Tests.IsPreferredLiveResult(fallbackSearchResult, fallbackResult)) {
                    fallbackResult := fallbackSearchResult
                }
            }

            if (BC_Tests.IsPreferredLiveResult(fallbackResult, bestResult)) {
                bestResult := fallbackResult
            }
        }

        bestResult.Timings := {
            CaptureMs: totalCaptureMs,
            PipelineMs: totalPipelineMs,
            AttemptCount: attemptSources.Length
        }
        bestResult.CaptureAttempts := attemptSources
        bestResult.PreferredSource := BC_Tests.PreferredSourceFromResult(bestResult)
        return bestResult
    }

    static DecodeImage(image, geometryHint := "", allowStoredHint := true) {
        profile := BC_Protocol.GetProfile()
        resolvedHint := IsObject(geometryHint) ? geometryHint : (allowStoredHint ? BC_State.GetLockedGeometryForImage(image) : "")
        detection := BC_Detect.LocateBand(image, profile, resolvedHint)
        decodeResult := BC_Decode.Decode(image, detection)
        validation := BC_Validate.Validate(detection, decodeResult)
        BC_State.Update(validation, { Image: image })

        return {
            Image: image,
            Detection: detection,
            Decode: decodeResult,
            Validation: validation
        }
    }

    static TryDecodeImage(image, geometryHint := "", allowStoredHint := true) {
        profile := BC_Protocol.GetProfile()

        try {
            return BC_Tests.DecodeImage(image, geometryHint, allowStoredHint)
        } catch as err {
            details := {
                BorderErrors: 999,
                Threshold: 0,
                BlackMean: 0,
                WhiteMean: 0,
                MinMargin: 0,
                OriginX: 0,
                OriginY: 0,
                Pitch: 0,
                BandWidth: image.Width,
                BandHeight: image.Height,
                SearchMode: "decode-exception",
                Contrast: 0,
                Failure: err.Message
            }
            detection := BC_Interfaces.DetectionResult(profile, 0, 0, 0, 999, err.Message, 0, 0, 0, image.Width, image.Height, 0, "decode-exception")
            decodeResult := BC_Interfaces.DecodeResult([], 0, 0, 0)
            validation := BC_Interfaces.ValidationResult(false, err.Message, 0.0, details)
            BC_State.Update(validation, { Image: image })

            return {
                Image: image,
                Detection: detection,
                Decode: decodeResult,
                Validation: validation
            }
        }
    }

    static ApplyLiveFrameState(result, sampleIndex, title, processName, persistSnapshot := false) {
        result.SampleIndex := sampleIndex
        result.WindowTitle := title
        result.ProcessName := processName
        BC_State.Update(result.Validation, result, persistSnapshot)
    }

    static IncrementCount(counterMap, key) {
        normalizedKey := key = "" ? "<empty>" : ("" key)
        currentValue := counterMap.Has(normalizedKey) ? counterMap[normalizedKey] : 0
        counterMap[normalizedKey] := currentValue + 1
    }

    static PreferredSourceFromResult(result) {
        if !IsObject(result) || !result.HasOwnProp("Image") {
            return "auto"
        }

        if (result.Image.HasOwnProp("SourceKind") && result.Image.SourceKind = "printwindow-client") {
            return "printwindow"
        }

        if (result.Image.HasOwnProp("SourceKind") && result.Image.SourceKind = "screen-bitblt") {
            return "screen"
        }

        return "auto"
    }

    static FormatCountMap(counterMap) {
        if !IsObject(counterMap) || counterMap.Count = 0 {
            return "-"
        }

        parts := []
        for key, value in counterMap {
            parts.Push(key "=" value)
        }
        return BC_Debug.Join(parts, ", ")
    }

    static RenderMatrixToPixels(profile, matrix) {
        pixels := Buffer(profile.BandWidth * profile.BandHeight * 3, 0)

        row := 0
        while (row < profile.BandHeight) {
            column := 0
            while (column < profile.BandWidth) {
                pixelOffset := ((row * profile.BandWidth) + column) * 3
                NumPut("UChar", BC_Config.SymbolPanelLight.B, pixels, pixelOffset)
                NumPut("UChar", BC_Config.SymbolPanelLight.G, pixels, pixelOffset + 1)
                NumPut("UChar", BC_Config.SymbolPanelLight.R, pixels, pixelOffset + 2)
                column += 1
            }
            row += 1
        }

        gridRow := 1
        while (gridRow <= profile.GridRows) {
            gridColumn := 1
            while (gridColumn <= profile.GridColumns) {
                if (matrix[gridRow][gridColumn] = 1) {
                    startX := profile.QuietLeft + ((gridColumn - 1) * profile.Pitch)
                    startY := profile.QuietTop + ((gridRow - 1) * profile.Pitch)
                    y := startY
                    while (y < startY + profile.Pitch) {
                        x := startX
                        while (x < startX + profile.Pitch) {
                            pixelOffset := ((y * profile.BandWidth) + x) * 3
                            NumPut("UChar", BC_Config.ModuleDark.B, pixels, pixelOffset)
                            NumPut("UChar", BC_Config.ModuleDark.G, pixels, pixelOffset + 1)
                            NumPut("UChar", BC_Config.ModuleDark.R, pixels, pixelOffset + 2)
                            x += 1
                        }
                        y += 1
                    }
                }
                gridColumn += 1
            }
            gridRow += 1
        }

        return pixels
    }

    static BoolText(value) {
        return value ? "true" : "false"
    }

    static IsPreferredLiveResult(candidate, baseline) {
        if !IsObject(baseline) {
            return true
        }

        if (candidate.Validation.IsAccepted != baseline.Validation.IsAccepted) {
            return candidate.Validation.IsAccepted
        }

        if (candidate.Detection.BorderErrors != baseline.Detection.BorderErrors) {
            return candidate.Detection.BorderErrors < baseline.Detection.BorderErrors
        }

        if (Abs(candidate.Validation.Confidence - baseline.Validation.Confidence) > 0.0001) {
            return candidate.Validation.Confidence > baseline.Validation.Confidence
        }

        if (Abs(candidate.Detection.Contrast - baseline.Detection.Contrast) > 0.5) {
            return candidate.Detection.Contrast > baseline.Detection.Contrast
        }

        return false
    }
}

; end-of-script marker comment
