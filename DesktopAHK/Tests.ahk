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

    static DecodeBmp(path, cropX := 0, cropY := 0) {
        profile := BC_Protocol.GetProfile()
        image := BC_Capture.AcquireFromBmp(path, cropX, cropY)
        detection := BC_Detect.LocateBand(image, profile)
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
}

; end-of-script marker comment
