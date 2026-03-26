/*
script name: DesktopAHK/Detect.ahk
version: 0.1.0
purpose: Performs phase 1 geometry lock and border-based threshold estimation for BC-Strip/1 fixtures.
dependencies: DesktopAHK/Config.ahk, DesktopAHK/Interfaces.ahk
important assumptions: Phase 1 expects an exact-profile top-band BMP and uses center sampling.
protocol version: BC-Strip/1
framework module role: Detection
character count note: Character count not precomputed; measure with tooling if needed.
*/

class BC_Detect {
    static LocateBand(image, profile) {
        if (image.Width != profile.BandWidth || image.Height != profile.BandHeight) {
            throw Error("Unexpected image dimensions. Expected " profile.BandWidth "x" profile.BandHeight ", got " image.Width "x" image.Height)
        }

        blackSamples := []
        whiteSamples := []

        Loop profile.GridColumns {
            column := A_Index
            blackSamples.Push(BC_Detect.SampleModuleCenter(image, profile, column, 1))
            expectedBottomDark := Mod(column - 1, 2) = 0
            sample := BC_Detect.SampleModuleCenter(image, profile, column, profile.GridRows)
            if expectedBottomDark {
                blackSamples.Push(sample)
            } else {
                whiteSamples.Push(sample)
            }
        }

        rowIndex := 2
        while (rowIndex <= profile.GridRows) {
            blackSamples.Push(BC_Detect.SampleModuleCenter(image, profile, 1, rowIndex))
            sample := BC_Detect.SampleModuleCenter(image, profile, profile.GridColumns, rowIndex)
            if (Mod(rowIndex - 1, 2) = 0) {
                blackSamples.Push(sample)
            } else {
                whiteSamples.Push(sample)
            }
            rowIndex += 1
        }

        quietSampleX := Max(0, profile.QuietLeft // 2)
        quietSampleY := Max(0, profile.QuietTop // 2)
        whiteSamples.Push(BC_Detect.SampleGray(image, quietSampleX, quietSampleY))

        blackMean := BC_Detect.Average(blackSamples)
        whiteMean := BC_Detect.Average(whiteSamples)
        threshold := Floor((blackMean + whiteMean) / 2)
        borderErrors := BC_Detect.CountBorderErrors(image, profile, threshold)

        return BC_Interfaces.DetectionResult(profile, threshold, blackMean, whiteMean, borderErrors)
    }

    static CountBorderErrors(image, profile, threshold) {
        errors := 0

        Loop profile.GridColumns {
            column := A_Index
            if !BC_Detect.IsDark(BC_Detect.SampleModuleCenter(image, profile, column, 1), threshold) {
                errors += 1
            }

            expectedBottomDark := Mod(column - 1, 2) = 0
            bottomIsDark := BC_Detect.IsDark(BC_Detect.SampleModuleCenter(image, profile, column, profile.GridRows), threshold)
            if (bottomIsDark != expectedBottomDark) {
                errors += 1
            }
        }

        Loop profile.GridRows {
            row := A_Index
            if !BC_Detect.IsDark(BC_Detect.SampleModuleCenter(image, profile, 1, row), threshold) {
                errors += 1
            }

            expectedRightDark := Mod(row - 1, 2) = 0
            rightIsDark := BC_Detect.IsDark(BC_Detect.SampleModuleCenter(image, profile, profile.GridColumns, row), threshold)
            if (rightIsDark != expectedRightDark) {
                errors += 1
            }
        }

        return errors
    }

    static SampleModuleCenter(image, profile, gridColumn, gridRow) {
        x := profile.QuietLeft + ((gridColumn - 1) * profile.Pitch) + Floor(profile.Pitch / 2)
        y := profile.QuietTop + ((gridRow - 1) * profile.Pitch) + Floor(profile.Pitch / 2)
        return BC_Detect.SampleGray(image, x, y)
    }

    static SampleGray(image, x, y) {
        if (x < 0 || x >= image.Width || y < 0 || y >= image.Height) {
            throw Error("Sample out of range at " x "," y)
        }
        index := ((y * image.Width) + x) * 3
        b := NumGet(image.Pixels, index, "UChar")
        g := NumGet(image.Pixels, index + 1, "UChar")
        r := NumGet(image.Pixels, index + 2, "UChar")
        return Floor((r * 299 + g * 587 + b * 114) / 1000)
    }

    static Average(values) {
        total := 0
        for _, value in values {
            total += value
        }
        return values.Length ? (total / values.Length) : 0
    }

    static IsDark(value, threshold) {
        return value <= threshold
    }
}

; end-of-script marker comment
