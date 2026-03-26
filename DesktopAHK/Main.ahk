/*
script name: DesktopAHK/Main.ahk
version: 0.1.0
purpose: Self-contained phase 1 BC-Strip/1 offline harness that generates synthetic BMP fixtures and decodes them.
dependencies: AutoHotkey v2.0+
important assumptions: Uses exact-profile synthetic 24-bit BMP fixtures and a fixed P720A protocol layout.
protocol version: BC-Strip/1
framework module role: Desktop entry point and executable smoke harness
character count note: Character count not precomputed; measure with tooling if needed.
*/

#Requires AutoHotkey v2.0
#SingleInstance Force

try {
    reportDir := A_ScriptDir "\out"
    fixtureDir := A_ScriptDir "\fixtures"
    tracePath := reportDir "\trace.txt"
    reportPath := reportDir "\phase1-smoke.txt"
    latestPath := reportDir "\latest-run.txt"
    goodFixturePath := fixtureDir "\bc_strip_p720a_static.bmp"
    corruptFixturePath := fixtureDir "\bc_strip_p720a_corrupt.bmp"

    BC_WriteText(tracePath, "main:start`r`n")

    profile := {
        Id: "P720A",
        NumericId: 1,
        BandWidth: 1280,
        BandHeight: 64,
        QuietLeft: 24,
        QuietTop: 8,
        Pitch: 8,
        GridColumns: 154,
        GridRows: 6
    }
    protocolVersion := 1
    layoutId := 1
    schemaId := 1
    staticSequence := 42
    staticPayloadLength := 24
    bandLight := { R: 245, G: 245, B: 245 }
    moduleDark := { R: 16, G: 16, B: 16 }

    payload := [
        0x10, 0x11, 0x12, 0x13, 0x20, 0x21, 0x22, 0x23,
        0x30, 0x31, 0x32, 0x33, 0x40, 0x41, 0x42, 0x43,
        0x50, 0x51, 0x52, 0x53, 0x60, 0x61, 0x62, 0x63
    ]
    witness := []
    witnessValue := 0xA5
    Loop 32 {
        witness.Push(witnessValue)
        witnessValue := (witnessValue == 0xA5) ? 0x5A : 0xA5
    }

    expectedBytes := []
    expectedBytes.Push(0x42)
    expectedBytes.Push(0x43)
    expectedBytes.Push(protocolVersion)
    expectedBytes.Push(layoutId)
    expectedBytes.Push(profile.NumericId)
    expectedBytes.Push(schemaId)
    expectedBytes.Push(staticSequence)
    expectedBytes.Push(0x00)
    expectedBytes.Push(staticPayloadLength)
    expectedBytes.Push(0x00)
    headerCrc := BC_Crc16(expectedBytes, 1, 10)
    expectedBytes.Push((headerCrc >> 8) & 0xFF)
    expectedBytes.Push(headerCrc & 0xFF)
    for _, value in payload {
        expectedBytes.Push(value)
    }
    payloadCrc := BC_Crc16(payload, 1, payload.Length)
    expectedBytes.Push((payloadCrc >> 8) & 0xFF)
    expectedBytes.Push(payloadCrc & 0xFF)
    expectedBytes.Push(0x42)
    expectedBytes.Push(0x43)
    expectedBytes.Push(protocolVersion)
    expectedBytes.Push(staticSequence)
    expectedBytes.Push(staticPayloadLength)
    expectedBytes.Push(0xC3)
    for _, value in witness {
        expectedBytes.Push(value)
    }
    BC_AppendText(tracePath, "main:bytes`r`n")

    goodMatrix := BC_BuildMatrix(profile, expectedBytes)
    BC_AppendText(tracePath, "main:good-matrix`r`n")
    goodPixels := BC_RenderMatrixToPixels(profile, goodMatrix, bandLight, moduleDark)
    BC_WriteBmp24(goodFixturePath, profile.BandWidth, profile.BandHeight, goodPixels)
    BC_AppendText(tracePath, "main:good-fixture`r`n")

    goodImage := BC_ReadBmp24(goodFixturePath)
    goodDetection := BC_LocateBand(goodImage, profile)
    goodDecoded := BC_DecodeBytes(goodImage, goodDetection)
    goodValidation := BC_ValidateTransport(goodDetection, goodDecoded, protocolVersion, layoutId, profile.NumericId, schemaId, staticSequence, staticPayloadLength)
    BC_AppendText(tracePath, "main:good-decoded`r`n")

    corruptMatrix := BC_BuildMatrix(profile, expectedBytes)
    corruptMatrix[2][2] := corruptMatrix[2][2] == 1 ? 0 : 1
    corruptPixels := BC_RenderMatrixToPixels(profile, corruptMatrix, bandLight, moduleDark)
    BC_WriteBmp24(corruptFixturePath, profile.BandWidth, profile.BandHeight, corruptPixels)
    BC_AppendText(tracePath, "main:corrupt-fixture`r`n")

    corruptImage := BC_ReadBmp24(corruptFixturePath)
    corruptDetection := BC_LocateBand(corruptImage, profile)
    corruptDecoded := BC_DecodeBytes(corruptImage, corruptDetection)
    corruptValidation := BC_ValidateTransport(corruptDetection, corruptDecoded, protocolVersion, layoutId, profile.NumericId, schemaId, staticSequence, staticPayloadLength)
    BC_AppendText(tracePath, "main:corrupt-decoded`r`n")

    success := goodValidation.IsAccepted
    if (success) {
        success := !corruptValidation.IsAccepted
    }

    reportLines := []
    reportLines.Push("BarCode phase 1 smoke report")
    reportLines.Push("Success: " BC_BoolText(success))
    reportLines.Push("Good fixture: " goodFixturePath)
    reportLines.Push("Corrupt fixture: " corruptFixturePath)
    reportLines.Push("")
    reportLines.Push("Expected bytes[1..16]: " BC_Hex(expectedBytes, 1, 16))
    reportLines.Push("Good decode accepted: " BC_BoolText(goodValidation.IsAccepted))
    reportLines.Push("Good decode reason: " goodValidation.Reason)
    reportLines.Push("Good border errors: " goodDetection.BorderErrors)
    reportLines.Push("Good threshold: " goodDetection.Threshold)
    reportLines.Push("Good contrast: " Round(goodValidation.Details.Contrast, 2))
    reportLines.Push("Good confidence: " goodValidation.Confidence)
    reportLines.Push("Good decoded bytes[1..16]: " BC_Hex(goodDecoded.Bytes, 1, 16))
    reportLines.Push("")
    reportLines.Push("Corrupt decode accepted: " BC_BoolText(corruptValidation.IsAccepted))
    reportLines.Push("Corrupt decode reason: " corruptValidation.Reason)
    reportLines.Push("Corrupt border errors: " corruptDetection.BorderErrors)
    reportLines.Push("Corrupt decoded bytes[1..16]: " BC_Hex(corruptDecoded.Bytes, 1, 16))
    report := BC_Join(reportLines, "`r`n")

    BC_WriteText(reportPath, report)
    BC_WriteText(latestPath, "BarCode phase 1 harness completed. Success=" BC_BoolText(success) "`r`nReport=" reportPath)
    BC_AppendText(tracePath, "main:report-written`r`n")
    ExitApp(success ? 0 : 1)
} catch error {
    BC_WriteText(A_ScriptDir "\out\latest-run.txt", "BarCode phase 1 harness failed.`r`n" error.Message "`r`n" error.Stack)
    ExitApp(1)
}

BC_BuildMatrix(profile, frameBytes) {
    bits := []
    for _, value in frameBytes {
        shift := 7
        while (shift >= 0) {
            bits.Push((value >> shift) & 0x1)
            shift -= 1
        }
    }

    matrix := []
    Loop profile.GridRows {
        row := []
        Loop profile.GridColumns {
            row.Push(0)
        }
        matrix.Push(row)
    }

    Loop profile.GridColumns {
        column := A_Index
        matrix[1][column] := 1
        if (Mod(column - 1, 2) == 0) {
            matrix[profile.GridRows][column] := 1
        }
    }

    Loop profile.GridRows {
        row := A_Index
        matrix[row][1] := 1
        if (Mod(row - 1, 2) == 0) {
            matrix[row][profile.GridColumns] := 1
        }
    }

    bitCursor := 1
    row := 2
    while (row <= profile.GridRows - 1) {
        column := 2
        while (column <= profile.GridColumns - 1) {
            matrix[row][column] := bits[bitCursor]
            bitCursor += 1
            column += 1
        }
        row += 1
    }

    return matrix
}

BC_RenderMatrixToPixels(profile, matrix, bandLight, moduleDark) {
    pixels := Buffer(profile.BandWidth * profile.BandHeight * 3, 0)

    row := 0
    while (row < profile.BandHeight) {
        column := 0
        while (column < profile.BandWidth) {
            pixelOffset := ((row * profile.BandWidth) + column) * 3
            NumPut("UChar", bandLight.B, pixels, pixelOffset)
            NumPut("UChar", bandLight.G, pixels, pixelOffset + 1)
            NumPut("UChar", bandLight.R, pixels, pixelOffset + 2)
            column += 1
        }
        row += 1
    }

    gridRow := 1
    while (gridRow <= profile.GridRows) {
        gridColumn := 1
        while (gridColumn <= profile.GridColumns) {
            if (matrix[gridRow][gridColumn] == 1) {
                startX := profile.QuietLeft + ((gridColumn - 1) * profile.Pitch)
                startY := profile.QuietTop + ((gridRow - 1) * profile.Pitch)
                y := startY
                while (y < startY + profile.Pitch) {
                    x := startX
                    while (x < startX + profile.Pitch) {
                        pixelOffset := ((y * profile.BandWidth) + x) * 3
                        NumPut("UChar", moduleDark.B, pixels, pixelOffset)
                        NumPut("UChar", moduleDark.G, pixels, pixelOffset + 1)
                        NumPut("UChar", moduleDark.R, pixels, pixelOffset + 2)
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

BC_WriteBmp24(path, width, height, pixelsBgrTopDown) {
    rowStride := width * 3
    paddedStride := rowStride + Mod(4 - Mod(rowStride, 4), 4)
    pixelBytes := paddedStride * height
    fileSize := 54 + pixelBytes
    buffer := Buffer(fileSize, 0)

    NumPut("UChar", Asc("B"), buffer, 0)
    NumPut("UChar", Asc("M"), buffer, 1)
    NumPut("UInt", fileSize, buffer, 2)
    NumPut("UInt", 54, buffer, 10)
    NumPut("UInt", 40, buffer, 14)
    NumPut("Int", width, buffer, 18)
    NumPut("Int", height, buffer, 22)
    NumPut("UShort", 1, buffer, 26)
    NumPut("UShort", 24, buffer, 28)
    NumPut("UInt", 0, buffer, 30)
    NumPut("UInt", pixelBytes, buffer, 34)

    destOffset := 54
    row := 0
    while (row < height) {
        sourceRow := height - 1 - row
        sourceOffset := sourceRow * rowStride
        columnOffset := 0
        while (columnOffset < rowStride) {
            value := NumGet(pixelsBgrTopDown, sourceOffset + columnOffset, "UChar")
            NumPut("UChar", value, buffer, destOffset + columnOffset)
            columnOffset += 1
        }
        destOffset += paddedStride
        row += 1
    }

    BC_EnsureDir(path)
    file := FileOpen(path, "w")
    file.RawWrite(buffer, fileSize)
    file.Close()
}

BC_ReadBmp24(path) {
    raw := FileRead(path, "RAW")
    pixelOffset := NumGet(raw, 10, "UInt")
    width := NumGet(raw, 18, "Int")
    height := NumGet(raw, 22, "Int")
    absHeight := Abs(height)
    rowStride := width * 3
    paddedStride := rowStride + Mod(4 - Mod(rowStride, 4), 4)
    pixels := Buffer(rowStride * absHeight, 0)

    row := 0
    while (row < absHeight) {
        sourceRow := absHeight - 1 - row
        sourceOffset := pixelOffset + (sourceRow * paddedStride)
        destOffset := row * rowStride
        columnOffset := 0
        while (columnOffset < rowStride) {
            value := NumGet(raw, sourceOffset + columnOffset, "UChar")
            NumPut("UChar", value, pixels, destOffset + columnOffset)
            columnOffset += 1
        }
        row += 1
    }

    return { Width: width, Height: absHeight, Pixels: pixels }
}

BC_LocateBand(image, profile) {
    blackSamples := []
    whiteSamples := []

    Loop profile.GridColumns {
        column := A_Index
        blackSamples.Push(BC_SampleModuleCenter(image, profile, column, 1))
        sample := BC_SampleModuleCenter(image, profile, column, profile.GridRows)
        if (Mod(column - 1, 2) == 0) {
            blackSamples.Push(sample)
        } else {
            whiteSamples.Push(sample)
        }
    }

    row := 2
    while (row <= profile.GridRows) {
        blackSamples.Push(BC_SampleModuleCenter(image, profile, 1, row))
        sample := BC_SampleModuleCenter(image, profile, profile.GridColumns, row)
        if (Mod(row - 1, 2) == 0) {
            blackSamples.Push(sample)
        } else {
            whiteSamples.Push(sample)
        }
        row += 1
    }

    whiteSamples.Push(BC_SampleGray(image, profile.QuietLeft // 2, profile.QuietTop // 2))
    blackMean := BC_Average(blackSamples)
    whiteMean := BC_Average(whiteSamples)
    threshold := Floor((blackMean + whiteMean) / 2)

    borderErrors := 0
    Loop profile.GridColumns {
        column := A_Index
        if !BC_IsDark(BC_SampleModuleCenter(image, profile, column, 1), threshold) {
            borderErrors += 1
        }
        bottomDark := BC_IsDark(BC_SampleModuleCenter(image, profile, column, profile.GridRows), threshold)
        if (bottomDark != (Mod(column - 1, 2) == 0)) {
            borderErrors += 1
        }
    }

    Loop profile.GridRows {
        row := A_Index
        if !BC_IsDark(BC_SampleModuleCenter(image, profile, 1, row), threshold) {
            borderErrors += 1
        }
        rightDark := BC_IsDark(BC_SampleModuleCenter(image, profile, profile.GridColumns, row), threshold)
        if (rightDark != (Mod(row - 1, 2) == 0)) {
            borderErrors += 1
        }
    }

    return {
        Profile: profile,
        Threshold: threshold,
        BlackMean: blackMean,
        WhiteMean: whiteMean,
        BorderErrors: borderErrors
    }
}

BC_DecodeBytes(image, detection) {
    profile := detection.Profile
    threshold := detection.Threshold
    bits := []
    minMargin := 999999

    row := 2
    while (row <= profile.GridRows - 1) {
        column := 2
        while (column <= profile.GridColumns - 1) {
            value := BC_SampleModuleCenter(image, profile, column, row)
            margin := Abs(value - threshold)
            if (margin < minMargin) {
                minMargin := margin
            }
            bits.Push(BC_IsDark(value, threshold) ? 1 : 0)
            column += 1
        }
        row += 1
    }

    bytes := []
    byteValue := 0
    bitCount := 0
    for _, bit in bits {
        byteValue := (byteValue << 1) | bit
        bitCount += 1
        if (bitCount == 8) {
            bytes.Push(byteValue & 0xFF)
            byteValue := 0
            bitCount := 0
        }
    }

    return {
        Bytes: bytes,
        MinMargin: minMargin
    }
}

BC_ValidateTransport(detection, decoded, protocolVersion, layoutId, profileId, schemaId, staticSequence, staticPayloadLength) {
    bytes := decoded.Bytes
    details := {
        Contrast: detection.WhiteMean - detection.BlackMean
    }

    if (bytes.Length != 76) {
        return { IsAccepted: false, Reason: "Unexpected byte count", Confidence: 0.0, Details: details }
    }

    if (detection.BorderErrors != 0) {
        return { IsAccepted: false, Reason: "Border validation failed", Confidence: 0.0, Details: details }
    }

    if (bytes[1] != 0x42 || bytes[2] != 0x43) {
        return { IsAccepted: false, Reason: "Sync mismatch", Confidence: 0.0, Details: details }
    }

    if (bytes[3] != protocolVersion || bytes[4] != layoutId || bytes[5] != profileId || bytes[6] != schemaId) {
        return { IsAccepted: false, Reason: "Header identity mismatch", Confidence: 0.0, Details: details }
    }

    if (bytes[7] != staticSequence || bytes[9] != staticPayloadLength) {
        return { IsAccepted: false, Reason: "Header sequence or length mismatch", Confidence: 0.0, Details: details }
    }

    headerCrc := BC_Crc16(bytes, 1, 10)
    if (headerCrc != (((bytes[11] << 8) | bytes[12]) & 0xFFFF)) {
        return { IsAccepted: false, Reason: "Header CRC mismatch", Confidence: 0.0, Details: details }
    }

    payload := []
    Loop staticPayloadLength {
        payload.Push(bytes[12 + A_Index])
    }
    payloadCrc := BC_Crc16(payload, 1, payload.Length)
    if (payloadCrc != (((bytes[37] << 8) | bytes[38]) & 0xFFFF)) {
        return { IsAccepted: false, Reason: "Payload CRC mismatch", Confidence: 0.0, Details: details }
    }

    if (bytes[39] != 0x42 || bytes[40] != 0x43 || bytes[41] != protocolVersion || bytes[42] != staticSequence || bytes[43] != staticPayloadLength) {
        return { IsAccepted: false, Reason: "Footer duplicate mismatch", Confidence: 0.0, Details: details }
    }

    witnessIndex := 45
    Loop 32 {
        expected := Mod(A_Index - 1, 2) == 0 ? 0xA5 : 0x5A
        if (bytes[witnessIndex + A_Index - 1] != expected) {
            return { IsAccepted: false, Reason: "Witness pattern mismatch", Confidence: 0.0, Details: details }
        }
    }

    confidence := Min(1.0, Max(0.0, details.Contrast / 255.0)) * Min(1.0, decoded.MinMargin / 32.0)
    return { IsAccepted: true, Reason: "Accepted", Confidence: Round(confidence, 4), Details: details }
}

BC_SampleModuleCenter(image, profile, gridColumn, gridRow) {
    x := profile.QuietLeft + ((gridColumn - 1) * profile.Pitch) + Floor(profile.Pitch / 2)
    y := profile.QuietTop + ((gridRow - 1) * profile.Pitch) + Floor(profile.Pitch / 2)
    return BC_SampleGray(image, x, y)
}

BC_SampleGray(image, x, y) {
    index := ((y * image.Width) + x) * 3
    b := NumGet(image.Pixels, index, "UChar")
    g := NumGet(image.Pixels, index + 1, "UChar")
    r := NumGet(image.Pixels, index + 2, "UChar")
    return Floor((r * 299 + g * 587 + b * 114) / 1000)
}

BC_IsDark(value, threshold) {
    return value <= threshold
}

BC_Average(values) {
    total := 0
    for _, value in values {
        total += value
    }
    return values.Length ? (total / values.Length) : 0
}

BC_Crc16(bytes, startIndex, endIndex) {
    crc := 0xFFFF
    index := startIndex
    while (index <= endIndex) {
        crc := crc ^ (bytes[index] << 8)
        Loop 8 {
            if (crc & 0x8000) {
                crc := ((crc << 1) ^ 0x1021) & 0xFFFF
            } else {
                crc := (crc << 1) & 0xFFFF
            }
        }
        index += 1
    }
    return crc
}

BC_EnsureDir(path) {
    lastSlash := InStr(path, "\", , -1)
    if (lastSlash > 0) {
        dir := SubStr(path, 1, lastSlash - 1)
        if (dir != "") {
            DirCreate(dir)
        }
    }
}

BC_WriteText(path, text) {
    BC_EnsureDir(path)
    if FileExist(path) {
        FileDelete(path)
    }
    FileAppend(text, path, "UTF-8")
}

BC_AppendText(path, text) {
    BC_EnsureDir(path)
    FileAppend(text, path, "UTF-8")
}

BC_Join(parts, delimiter := "") {
    output := ""
    for index, part in parts {
        if (index > 1) {
            output .= delimiter
        }
        output .= part
    }
    return output
}

BC_Hex(bytes, startIndex := 1, count := 0) {
    parts := []
    limit := count > 0 ? Min(bytes.Length, startIndex + count - 1) : bytes.Length
    index := startIndex
    while (index <= limit) {
        parts.Push(Format("{:02X}", bytes[index]))
        index += 1
    }
    return BC_Join(parts, " ")
}

BC_BoolText(value) {
    return value ? "true" : "false"
}

; end-of-script marker comment
