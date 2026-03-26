/*
script name: DesktopAHK/Tests.ahk
version: 0.1.0
purpose: Runs the phase 1 synthetic BC-Strip/1 fixture smoke test end to end.
dependencies: DesktopAHK/Config.ahk, DesktopAHK/Protocol.ahk, DesktopAHK/Detect.ahk, DesktopAHK/Decode.ahk, DesktopAHK/Validate.ahk, DesktopAHK/State.ahk, DesktopAHK/Debug.ahk
important assumptions: Uses exact-profile synthetic fixtures with crisp module edges.
protocol version: BC-Strip/1
framework module role: Test harness
character count note: Character count not precomputed; measure with tooling if needed.
*/

class BC_Tests {
    static Run() {
        BC_Debug.WriteText(BC_Debug.TracePath(), "tests.run:start`r`n")

        profile := BC_Protocol.GetProfile()
        BC_Debug.Trace("tests.run:profile`r`n")

        expectedBytes := BC_Protocol.BuildStaticFrameBytes()
        BC_Debug.Trace("tests.run:bytes`r`n")

        goodMatrix := BC_Protocol.BuildModuleMatrix(profile, expectedBytes)
        BC_Debug.Trace("tests.run:matrix-good`r`n")

        goodPixels := Buffer(profile.BandWidth * profile.BandHeight * 3, 0)
        row := 0
        while (row < profile.BandHeight) {
            column := 0
            while (column < profile.BandWidth) {
                pixelOffset := ((row * profile.BandWidth) + column) * 3
                NumPut("UChar", BC_Config.BandLight.B, goodPixels, pixelOffset)
                NumPut("UChar", BC_Config.BandLight.G, goodPixels, pixelOffset + 1)
                NumPut("UChar", BC_Config.BandLight.R, goodPixels, pixelOffset + 2)
                column += 1
            }
            row += 1
        }
        BC_Debug.Trace("tests.run:good-background`r`n")

        gridRow := 1
        while (gridRow <= profile.GridRows) {
            gridColumn := 1
            while (gridColumn <= profile.GridColumns) {
                if (goodMatrix[gridRow][gridColumn] == 1) {
                    startX := profile.QuietLeft + ((gridColumn - 1) * profile.Pitch)
                    startY := profile.QuietTop + ((gridRow - 1) * profile.Pitch)
                    y := startY
                    while (y < startY + profile.Pitch) {
                        x := startX
                        while (x < startX + profile.Pitch) {
                            pixelOffset := ((y * profile.BandWidth) + x) * 3
                            NumPut("UChar", BC_Config.ModuleDark.B, goodPixels, pixelOffset)
                            NumPut("UChar", BC_Config.ModuleDark.G, goodPixels, pixelOffset + 1)
                            NumPut("UChar", BC_Config.ModuleDark.R, goodPixels, pixelOffset + 2)
                            x += 1
                        }
                        y += 1
                    }
                }
                gridColumn += 1
            }
            gridRow += 1
        }
        BC_Debug.Trace("tests.run:good-modules`r`n")

        BC_Debug.WriteBmp24(BC_Config.GoodFixturePath, profile.BandWidth, profile.BandHeight, goodPixels)
        BC_Debug.Trace("tests.run:good-fixture-written`r`n")

        goodImage := BC_Debug.ReadBmp24(BC_Config.GoodFixturePath)
        goodDetection := BC_Detect.LocateBand(goodImage, profile)
        goodDecoded := BC_Decode.Decode(goodImage, goodDetection)
        goodValidation := BC_Validate.Validate(goodDetection, goodDecoded)
        BC_State.Update(goodValidation)
        BC_Debug.Trace("tests.run:good-decoded`r`n")

        corruptMatrix := BC_Protocol.BuildModuleMatrix(profile, expectedBytes)
        if (corruptMatrix[2][2] == 1) {
            corruptMatrix[2][2] := 0
        } else {
            corruptMatrix[2][2] := 1
        }

        corruptPixels := Buffer(profile.BandWidth * profile.BandHeight * 3, 0)
        row := 0
        while (row < profile.BandHeight) {
            column := 0
            while (column < profile.BandWidth) {
                pixelOffset := ((row * profile.BandWidth) + column) * 3
                NumPut("UChar", BC_Config.BandLight.B, corruptPixels, pixelOffset)
                NumPut("UChar", BC_Config.BandLight.G, corruptPixels, pixelOffset + 1)
                NumPut("UChar", BC_Config.BandLight.R, corruptPixels, pixelOffset + 2)
                column += 1
            }
            row += 1
        }

        gridRow := 1
        while (gridRow <= profile.GridRows) {
            gridColumn := 1
            while (gridColumn <= profile.GridColumns) {
                if (corruptMatrix[gridRow][gridColumn] == 1) {
                    startX := profile.QuietLeft + ((gridColumn - 1) * profile.Pitch)
                    startY := profile.QuietTop + ((gridRow - 1) * profile.Pitch)
                    y := startY
                    while (y < startY + profile.Pitch) {
                        x := startX
                        while (x < startX + profile.Pitch) {
                            pixelOffset := ((y * profile.BandWidth) + x) * 3
                            NumPut("UChar", BC_Config.ModuleDark.B, corruptPixels, pixelOffset)
                            NumPut("UChar", BC_Config.ModuleDark.G, corruptPixels, pixelOffset + 1)
                            NumPut("UChar", BC_Config.ModuleDark.R, corruptPixels, pixelOffset + 2)
                            x += 1
                        }
                        y += 1
                    }
                }
                gridColumn += 1
            }
            gridRow += 1
        }
        BC_Debug.Trace("tests.run:corrupt-modules`r`n")

        BC_Debug.WriteBmp24(BC_Config.CorruptFixturePath, profile.BandWidth, profile.BandHeight, corruptPixels)
        BC_Debug.Trace("tests.run:corrupt-fixture-written`r`n")

        corruptImage := BC_Debug.ReadBmp24(BC_Config.CorruptFixturePath)
        corruptDetection := BC_Detect.LocateBand(corruptImage, profile)
        corruptDecoded := BC_Decode.Decode(corruptImage, corruptDetection)
        corruptValidation := BC_Validate.Validate(corruptDetection, corruptDecoded)
        BC_State.Update(corruptValidation)
        BC_Debug.Trace("tests.run:corrupt-decoded`r`n")

        success := goodValidation.IsAccepted
        if (success) {
            success := !corruptValidation.IsAccepted
        }

        reportLines := []
        reportLines.Push("BarCode phase 1 smoke report")
        reportLines.Push("Success: " (success ? "true" : "false"))
        reportLines.Push("Good fixture: " BC_Config.GoodFixturePath)
        reportLines.Push("Corrupt fixture: " BC_Config.CorruptFixturePath)
        reportLines.Push("")
        reportLines.Push("Expected bytes[1..16]: " BC_Debug.Hex(expectedBytes, 1, 16))
        reportLines.Push("Good decode accepted: " (goodValidation.IsAccepted ? "true" : "false"))
        reportLines.Push("Good decode reason: " goodValidation.Reason)
        reportLines.Push("Good border errors: " goodDetection.BorderErrors)
        reportLines.Push("Good threshold: " goodDetection.Threshold)
        reportLines.Push("Good contrast: " Round(goodValidation.Details.Contrast, 2))
        reportLines.Push("Good confidence: " goodValidation.Confidence)
        reportLines.Push("Good decoded bytes[1..16]: " BC_Debug.Hex(goodDecoded.Bytes, 1, 16))
        reportLines.Push("")
        reportLines.Push("Corrupt decode accepted: " (corruptValidation.IsAccepted ? "true" : "false"))
        reportLines.Push("Corrupt decode reason: " corruptValidation.Reason)
        reportLines.Push("Corrupt border errors: " corruptDetection.BorderErrors)
        reportLines.Push("Corrupt decoded bytes[1..16]: " BC_Debug.Hex(corruptDecoded.Bytes, 1, 16))
        report := BC_Debug.Join(reportLines, "`r`n")
        BC_Debug.WriteText(BC_Config.GoodReportPath, report)
        BC_Debug.Trace("tests.run:report-written`r`n")

        result := {}
        result.Success := success
        result.ReportPath := BC_Config.GoodReportPath
        result.GoodFixturePath := BC_Config.GoodFixturePath
        result.CorruptFixturePath := BC_Config.CorruptFixturePath
        return result
    }
}

; end-of-script marker comment
