/*
script name: DesktopAHK/Tests.ahk
version: 0.2.0
purpose: Runs the minimum schema-2 reader smoke for BC-Strip/1 using synthetic and fixed-BMP inputs.
dependencies: DesktopAHK/Config.ahk, DesktopAHK/Capture.ahk, DesktopAHK/Protocol.ahk, DesktopAHK/Detect.ahk, DesktopAHK/Decode.ahk, DesktopAHK/Validate.ahk, DesktopAHK/State.ahk, DesktopAHK/Debug.ahk
important assumptions: Uses exact-profile synthetic fixtures with crisp module edges and fixed-geometry BMP decode for the minimum smoke pass.
protocol version: BC-Strip/1
framework module role: Test harness
character count note: Character count not precomputed; measure with tooling if needed.
*/

class BC_Tests {
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
        reportLines.Push("BarCode phase 2 reader smoke report")
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
        reportLines.Push("Good health: " goodResult.Validation.Details.HotPage.HealthCurrent "/" goodResult.Validation.Details.HotPage.HealthMax)
        reportLines.Push("Good resource: " goodResult.Validation.Details.HotPage.ResourceCurrent "/" goodResult.Validation.Details.HotPage.ResourceMax)
        reportLines.Push("Good cast progress q15: " goodResult.Validation.Details.HotPage.CastProgressQ15)
        reportLines.Push("Good sample mask: 0x" Format("{:04X}", goodResult.Validation.Details.HotPage.SampleMask))
        reportLines.Push("Good state flags: 0x" Format("{:04X}", goodResult.Validation.Details.HotPage.StateFlags))
        reportLines.Push("Good confidence: " goodResult.Validation.Confidence)
        reportLines.Push("")
        reportLines.Push("Corrupt accepted: " BC_Tests.BoolText(corruptResult.Validation.IsAccepted))
        reportLines.Push("Corrupt reason: " corruptResult.Validation.Reason)
        reportLines.Push("Corrupt decoded bytes[1..16]: " BC_Debug.Hex(corruptResult.Decode.Bytes, 1, 16))

        report := BC_Debug.Join(reportLines, "`r`n")
        BC_Debug.WriteText(BC_Config.SmokeReportPath, report)

        return {
            Success: success,
            ReportPath: BC_Config.SmokeReportPath,
            GoodFixturePath: BC_Config.GoodFixturePath,
            CorruptFixturePath: BC_Config.CorruptFixturePath
        }
    }

    static RunFixedBmpDecode(path, cropX := 0, cropY := 0) {
        result := BC_Tests.DecodeBmp(path, cropX, cropY)
        validation := result.Validation
        details := validation.Details
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
            reportLines.Push("Health: " details.HotPage.HealthCurrent "/" details.HotPage.HealthMax)
            reportLines.Push("Resource: " details.HotPage.ResourceCurrent "/" details.HotPage.ResourceMax)
            reportLines.Push("CastProgressQ15: " details.HotPage.CastProgressQ15)
            reportLines.Push("Level: " details.HotPage.Level)
            reportLines.Push("CallingCode: " details.HotPage.CallingCode)
            reportLines.Push("RoleCode: " details.HotPage.RoleCode)
        }

        reportLines.Push("Confidence: " validation.Confidence)
        reportLines.Push("Decoded bytes[1..16]: " BC_Debug.Hex(result.Decode.Bytes, 1, 16))
        BC_Debug.WriteText(BC_Config.FixedBmpReportPath, BC_Debug.Join(reportLines, "`r`n"))

        return {
            Success: validation.IsAccepted,
            ReportPath: BC_Config.FixedBmpReportPath
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
        lockedCount := 0
        searchedCount := 0
        sampleIndex := 1
        title := WinGetTitle("ahk_id " hwnd)
        processName := WinGetProcessName("ahk_id " hwnd)

        BC_State.ResetLiveOutputs()

        while (sampleIndex <= sampleCount) {
            result := BC_Tests.DecodeLiveFrame(hwnd)
            BC_Tests.ApplyLiveFrameState(result, sampleIndex, title, processName, true)
            validation := result.Validation
            totalCaptureMs += result.Timings.CaptureMs
            totalPipelineMs += result.Timings.PipelineMs
            if (validation.IsAccepted) {
                acceptedCount += 1
                if (firstAcceptedSequence = "" && validation.Details.HasOwnProp("Transport")) {
                    firstAcceptedSequence := validation.Details.Transport.Sequence
                }
            } else {
                rejectedCount += 1
            }

            lastResult := result
            if (result.Detection.SearchMode = "locked") {
                lockedCount += 1
            } else {
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
        reportLines.Push("CaptureAttempts: " (lastResult.HasOwnProp("CaptureAttempts") ? BC_Debug.Join(lastResult.CaptureAttempts, ",") : ""))
        reportLines.Push("AverageCaptureMs: " Round(totalCaptureMs / sampleCount, 2))
        reportLines.Push("AveragePipelineMs: " Round(totalPipelineMs / sampleCount, 2))
        reportLines.Push("FirstAcceptedSequence: " firstAcceptedSequence)
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
        if (hotPage.HasOwnProp("HealthCurrent")) {
            reportLines.Push("Health: " hotPage.HealthCurrent "/" hotPage.HealthMax)
            reportLines.Push("Resource: " hotPage.ResourceCurrent "/" hotPage.ResourceMax)
            reportLines.Push("CastProgressQ15: " hotPage.CastProgressQ15)
            reportLines.Push("Level: " hotPage.Level)
            reportLines.Push("CallingCode: " hotPage.CallingCode)
            reportLines.Push("RoleCode: " hotPage.RoleCode)
        }
        reportLines.Push("Decoded bytes[1..16]: " BC_Debug.Hex(lastResult.Decode.Bytes, 1, 16))
        reportLines.Push("LastCaptureBmp: " BC_Config.LiveCaptureBmpPath)

        BC_Debug.WriteText(BC_Config.LiveReportPath, BC_Debug.Join(reportLines, "`r`n"))

        return {
            Success: acceptedCount > 0,
            ReportPath: BC_Config.LiveReportPath
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
        acceptedCount := 0
        rejectedCount := 0
        lastResult := ""
        totalCaptureMs := 0
        totalPipelineMs := 0
        lockedCount := 0
        searchedCount := 0

        BC_State.ResetLiveOutputs()

        while (durationSeconds <= 0 || (A_TickCount - startedAt) < (durationSeconds * 1000)) {
            result := BC_Tests.DecodeLiveFrame(hwnd)
            BC_Tests.ApplyLiveFrameState(result, sampleIndex, title, processName, true)
            validation := result.Validation
            totalCaptureMs += result.Timings.CaptureMs
            totalPipelineMs += result.Timings.PipelineMs
            if (validation.IsAccepted) {
                acceptedCount += 1
            } else {
                rejectedCount += 1
            }

            if (result.Detection.SearchMode = "locked") {
                lockedCount += 1
            } else {
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
        reportLines.Push("CaptureAttempts: " (lastResult.HasOwnProp("CaptureAttempts") ? BC_Debug.Join(lastResult.CaptureAttempts, ",") : ""))
        reportLines.Push("AverageCaptureMs: " Round(totalCaptureMs / Max(1, sampleCount), 2))
        reportLines.Push("AveragePipelineMs: " Round(totalPipelineMs / Max(1, sampleCount), 2))
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
        BC_Debug.WriteText(BC_Config.LiveWatchReportPath, BC_Debug.Join(reportLines, "`r`n"))

        return {
            Success: acceptedCount > 0,
            ReportPath: BC_Config.LiveWatchReportPath
        }
    }

    static DecodeBmp(path, cropX := 0, cropY := 0) {
        profile := BC_Protocol.GetProfile()
        image := BC_Capture.AcquireFromBmp(path, cropX, cropY)
        return BC_Tests.DecodeImage(image)
    }

    static DecodeLiveFrame(hwnd, cropX := 0, cropY := 0) {
        totalCaptureMs := 0
        totalPipelineMs := 0
        attemptSources := []

        captureStarted := A_TickCount
        primaryImage := BC_Capture.AcquireFromWindow(hwnd, cropX, cropY)
        totalCaptureMs += A_TickCount - captureStarted
        attemptSources.Push(primaryImage.SourceKind)

        pipelineStarted := A_TickCount
        bestResult := BC_Tests.TryDecodeImage(primaryImage)
        totalPipelineMs += A_TickCount - pipelineStarted

        if !bestResult.Validation.IsAccepted {
            fallbackSource := primaryImage.SourceKind = "printwindow-client" ? "screen" : "printwindow"
            BC_Debug.Trace("tests.live:fallback=" fallbackSource "`r`n")
            captureStarted := A_TickCount
            fallbackImage := BC_Capture.AcquireFromWindow(hwnd, cropX, cropY, fallbackSource)
            totalCaptureMs += A_TickCount - captureStarted
            attemptSources.Push(fallbackImage.SourceKind)

            pipelineStarted := A_TickCount
            fallbackResult := BC_Tests.TryDecodeImage(fallbackImage)
            totalPipelineMs += A_TickCount - pipelineStarted

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
        return bestResult
    }

    static DecodeImage(image) {
        profile := BC_Protocol.GetProfile()
        detection := BC_Detect.LocateBand(image, profile, BC_State.GetLockedGeometry())
        decodeResult := BC_Decode.Decode(image, detection)
        validation := BC_Validate.Validate(detection, decodeResult)
        BC_State.Update(validation)

        return {
            Image: image,
            Detection: detection,
            Decode: decodeResult,
            Validation: validation
        }
    }

    static TryDecodeImage(image) {
        profile := BC_Protocol.GetProfile()

        try {
            return BC_Tests.DecodeImage(image)
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
            BC_State.Update(validation)

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
