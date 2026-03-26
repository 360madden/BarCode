/*
script name: DesktopAHK/Detect.ahk
version: 0.2.0
purpose: Locks BC-Strip/1 geometry using either exact-profile sampling or a scaled top-left panel solve for larger BMP screenshots.
dependencies: DesktopAHK/Config.ahk, DesktopAHK/Interfaces.ahk
important assumptions: The first live screenshot path still assumes the symbol panel is near the top-left of the cropped image and keeps uniform X/Y scale.
protocol version: BC-Strip/1
framework module role: Detection
character count note: Character count not precomputed; measure with tooling if needed.
*/

class BC_Detect {
    static LocateBand(image, profile) {
        if (image.Width = profile.BandWidth && image.Height = profile.BandHeight) {
            return BC_Detect.BuildDetectionResult(BC_Detect.EvaluateCandidate(image, profile, 0, 0, profile.Pitch, 1, 1, "exact"), profile)
        }

        bestCandidate := BC_Detect.SearchScaledBand(image, profile)
        if !IsObject(bestCandidate) {
            throw Error("Could not locate a scaled BC-Strip/1 panel in the BMP input")
        }

        return BC_Detect.BuildDetectionResult(bestCandidate, profile)
    }

    static SearchScaledBand(image, profile) {
        seed := BC_Detect.EstimatePanelSeed(image, profile)
        if !IsObject(seed) {
            return ""
        }

        bestCandidate := ""
        pitch := seed.PitchStart
        while (pitch <= (seed.PitchEnd + 0.0001)) {
            originY := seed.OriginYStart
            while (originY <= seed.OriginYEnd) {
                originX := seed.OriginXStart
                while (originX <= seed.OriginXEnd) {
                    candidate := BC_Detect.EvaluateCandidate(image, profile, originX, originY, pitch, 2, 1, "scaled-seeded")
                    if (IsObject(candidate) && BC_Detect.IsBetterCandidate(candidate, bestCandidate)) {
                        bestCandidate := candidate
                    }
                    originX += 1
                }
                originY += 1
            }
            pitch := Round(pitch + 0.10, 4)
        }

        if !IsObject(bestCandidate) {
            return ""
        }

        return BC_Detect.RefineCandidate(image, profile, bestCandidate)
    }

    static RefineCandidate(image, profile, seed) {
        bestCandidate := seed
        pitchStart := Max(BC_Config.SearchMinPitch, seed.Pitch - BC_Config.SearchCoarsePitchStep)
        pitchEnd := Min(BC_Config.SearchMaxPitch, seed.Pitch + BC_Config.SearchCoarsePitchStep)
        originXStart := Max(0, seed.OriginX - BC_Config.SearchCoarseXStep)
        originXEnd := Min(BC_Config.SearchMaxOriginX, seed.OriginX + BC_Config.SearchCoarseXStep)
        originYStart := Max(0, seed.OriginY - BC_Config.SearchCoarseYStep)
        originYEnd := Min(BC_Config.SearchMaxOriginY, seed.OriginY + BC_Config.SearchCoarseYStep)
        pitch := pitchStart

        while (pitch <= (pitchEnd + 0.0001)) {
            originY := originYStart
            while (originY <= originYEnd) {
                originX := originXStart
                while (originX <= originXEnd) {
                    candidate := BC_Detect.EvaluateCandidate(image, profile, originX, originY, pitch, 1, 1, "scaled-refine")
                    if (IsObject(candidate) && BC_Detect.IsBetterCandidate(candidate, bestCandidate)) {
                        bestCandidate := candidate
                    }
                    originX += 1
                }
                originY += 1
            }
            pitch := Round(pitch + BC_Config.SearchFinePitchStep, 4)
        }

        return bestCandidate
    }

    static EstimatePanelSeed(image, profile) {
        bestSpan := ""
        maxRow := Min(BC_Config.SearchMaxOriginY, image.Height - 1)
        rowIndex := 0

        while (rowIndex <= maxRow) {
            span := BC_Detect.MeasureBrightSpan(image, rowIndex, 215)
            if (IsObject(span) && span.Width >= 200) {
                if (!IsObject(bestSpan) || span.Width > bestSpan.Width || (span.Width = bestSpan.Width && rowIndex < bestSpan.Row)) {
                    span.Row := rowIndex
                    bestSpan := span
                }
            }
            rowIndex += 1
        }

        if !IsObject(bestSpan) {
            return ""
        }

        estimatedPitch := (bestSpan.Width / profile.BandWidth) * profile.Pitch
        estimatedPitch := Max(BC_Config.SearchMinPitch, Min(BC_Config.SearchMaxPitch, estimatedPitch))
        estimatedOriginX := Max(0, bestSpan.StartX)
        estimatedOriginY := Max(0, bestSpan.Row)

        return {
            OriginXStart: Max(0, estimatedOriginX - 4),
            OriginXEnd: Min(BC_Config.SearchMaxOriginX, estimatedOriginX + 4),
            OriginYStart: Max(0, estimatedOriginY - 2),
            OriginYEnd: Min(BC_Config.SearchMaxOriginY, estimatedOriginY + 6),
            PitchStart: Max(BC_Config.SearchMinPitch, estimatedPitch - 0.60),
            PitchEnd: Min(BC_Config.SearchMaxPitch, estimatedPitch + 0.60)
        }
    }

    static MeasureBrightSpan(image, y, threshold := 215) {
        bestStart := -1
        bestEnd := -1
        currentStart := -1
        gapCount := 0
        maxGap := 2
        x := 0

        while (x < image.Width) {
            gray := BC_Detect.SampleGray(image, x, y)
            if (gray >= threshold) {
                if (currentStart < 0) {
                    currentStart := x
                }
                gapCount := 0
            } else if (currentStart >= 0) {
                gapCount += 1
                if (gapCount > maxGap) {
                    currentEnd := x - gapCount
                    if ((currentEnd - currentStart) > (bestEnd - bestStart)) {
                        bestStart := currentStart
                        bestEnd := currentEnd
                    }
                    currentStart := -1
                    gapCount := 0
                }
            }
            x += 1
        }

        if (currentStart >= 0) {
            currentEnd := image.Width - 1
            if ((currentEnd - currentStart) > (bestEnd - bestStart)) {
                bestStart := currentStart
                bestEnd := currentEnd
            }
        }

        if (bestStart < 0 || bestEnd < bestStart) {
            return ""
        }

        return {
            StartX: bestStart,
            EndX: bestEnd,
            Width: (bestEnd - bestStart + 1)
        }
    }

    static EvaluateCandidate(image, profile, originX, originY, pitch, columnStride := 1, rowStride := 1, searchMode := "scaled") {
        scale := pitch / profile.Pitch
        bandWidth := profile.BandWidth * scale
        bandHeight := profile.BandHeight * scale
        if ((originX + bandWidth) > image.Width || (originY + bandHeight) > image.Height) {
            return ""
        }

        blackSamples := []
        whiteSamples := []
        columnIndices := BC_Detect.BuildIndexList(profile.GridColumns, columnStride)
        rowIndices := BC_Detect.BuildIndexList(profile.GridRows, rowStride)

        for _, column in columnIndices {
            blackSamples.Push(BC_Detect.SampleModuleCenter(image, profile, column, 1, originX, originY, pitch))
            expectedBottomDark := Mod(column - 1, 2) = 0
            sample := BC_Detect.SampleModuleCenter(image, profile, column, profile.GridRows, originX, originY, pitch)
            if expectedBottomDark {
                blackSamples.Push(sample)
            } else {
                whiteSamples.Push(sample)
            }
        }

        for _, rowIndex in rowIndices {
            blackSamples.Push(BC_Detect.SampleModuleCenter(image, profile, 1, rowIndex, originX, originY, pitch))
            sample := BC_Detect.SampleModuleCenter(image, profile, profile.GridColumns, rowIndex, originX, originY, pitch)
            if (Mod(rowIndex - 1, 2) = 0) {
                blackSamples.Push(sample)
            } else {
                whiteSamples.Push(sample)
            }
        }

        quietLeft := profile.QuietLeft * scale
        quietRight := profile.QuietRight * scale
        quietTop := profile.QuietTop * scale
        quietBottom := profile.QuietBottom * scale
        radius := BC_Detect.KernelRadius(pitch)
        whiteSamples.Push(BC_Detect.SampleGrayKernel(image, originX + (quietLeft / 2.0), originY + (quietTop / 2.0), radius))
        whiteSamples.Push(BC_Detect.SampleGrayKernel(image, originX + bandWidth - (quietRight / 2.0), originY + (quietTop / 2.0), radius))
        whiteSamples.Push(BC_Detect.SampleGrayKernel(image, originX + (quietLeft / 2.0), originY + bandHeight - (quietBottom / 2.0), radius))

        blackMean := BC_Detect.Average(blackSamples)
        whiteMean := BC_Detect.Average(whiteSamples)
        contrast := whiteMean - blackMean
        if (contrast <= 20) {
            return ""
        }

        threshold := Floor((blackMean + whiteMean) / 2)
        borderErrors := BC_Detect.CountBorderErrors(image, profile, threshold, originX, originY, pitch, columnStride, rowStride)

        return {
            Threshold: threshold,
            BlackMean: blackMean,
            WhiteMean: whiteMean,
            BorderErrors: borderErrors,
            Notes: "origin=" originX "," originY " pitch=" Round(pitch, 3),
            OriginX: originX,
            OriginY: originY,
            Pitch: pitch,
            BandWidth: Round(bandWidth, 3),
            BandHeight: Round(bandHeight, 3),
            Contrast: contrast,
            SearchMode: searchMode
        }
    }

    static BuildDetectionResult(candidate, profile) {
        if !IsObject(candidate) {
            throw Error("Detection candidate missing")
        }

        return BC_Interfaces.DetectionResult(
            profile,
            candidate.Threshold,
            candidate.BlackMean,
            candidate.WhiteMean,
            candidate.BorderErrors,
            candidate.Notes,
            candidate.OriginX,
            candidate.OriginY,
            candidate.Pitch,
            candidate.BandWidth,
            candidate.BandHeight,
            candidate.Contrast,
            candidate.SearchMode
        )
    }

    static BuildIndexList(maxValue, stride) {
        indices := []
        actualStride := Max(1, stride)
        value := 1

        while (value <= maxValue) {
            indices.Push(value)
            value += actualStride
        }

        if (indices.Length = 0 || indices[indices.Length] != maxValue) {
            indices.Push(maxValue)
        }

        return indices
    }

    static IsBetterCandidate(candidate, bestCandidate) {
        if !IsObject(bestCandidate) {
            return true
        }

        if (candidate.BorderErrors != bestCandidate.BorderErrors) {
            return candidate.BorderErrors < bestCandidate.BorderErrors
        }

        if (Abs(candidate.Contrast - bestCandidate.Contrast) > 0.5) {
            return candidate.Contrast > bestCandidate.Contrast
        }

        if (Abs(candidate.WhiteMean - bestCandidate.WhiteMean) > 0.5) {
            return candidate.WhiteMean > bestCandidate.WhiteMean
        }

        if (Abs(candidate.BlackMean - bestCandidate.BlackMean) > 0.5) {
            return candidate.BlackMean < bestCandidate.BlackMean
        }

        return candidate.Pitch > bestCandidate.Pitch
    }

    static CountBorderErrors(image, profile, threshold, originX := 0, originY := 0, pitch := 0, columnStride := 1, rowStride := 1) {
        errors := 0
        if (pitch <= 0) {
            pitch := profile.Pitch
        }

        columnIndices := BC_Detect.BuildIndexList(profile.GridColumns, columnStride)
        rowIndices := BC_Detect.BuildIndexList(profile.GridRows, rowStride)

        for _, column in columnIndices {
            if !BC_Detect.IsDark(BC_Detect.SampleModuleCenter(image, profile, column, 1, originX, originY, pitch), threshold) {
                errors += 1
            }

            expectedBottomDark := Mod(column - 1, 2) = 0
            bottomIsDark := BC_Detect.IsDark(BC_Detect.SampleModuleCenter(image, profile, column, profile.GridRows, originX, originY, pitch), threshold)
            if (bottomIsDark != expectedBottomDark) {
                errors += 1
            }
        }

        for _, rowIndex in rowIndices {
            if !BC_Detect.IsDark(BC_Detect.SampleModuleCenter(image, profile, 1, rowIndex, originX, originY, pitch), threshold) {
                errors += 1
            }

            expectedRightDark := Mod(rowIndex - 1, 2) = 0
            rightIsDark := BC_Detect.IsDark(BC_Detect.SampleModuleCenter(image, profile, profile.GridColumns, rowIndex, originX, originY, pitch), threshold)
            if (rightIsDark != expectedRightDark) {
                errors += 1
            }
        }

        return errors
    }

    static SampleModuleCenter(image, profile, gridColumn, gridRow, originX := 0, originY := 0, pitch := 0) {
        if (pitch <= 0) {
            pitch := profile.Pitch
        }

        scale := pitch / profile.Pitch
        centerX := originX + (profile.QuietLeft * scale) + ((gridColumn - 1) * pitch) + (pitch / 2.0)
        centerY := originY + (profile.QuietTop * scale) + ((gridRow - 1) * pitch) + (pitch / 2.0)
        return BC_Detect.SampleGrayKernel(image, centerX, centerY, BC_Detect.KernelRadius(pitch))
    }

    static KernelRadius(pitch) {
        return pitch >= 5 ? 1 : 0
    }

    static SampleGrayKernel(image, x, y, radius := 0) {
        if (radius <= 0) {
            return BC_Detect.SampleGray(image, Round(x), Round(y))
        }

        sum := 0
        count := 0
        yOffset := -radius
        while (yOffset <= radius) {
            xOffset := -radius
            while (xOffset <= radius) {
                sum += BC_Detect.SampleGray(image, Round(x) + xOffset, Round(y) + yOffset)
                count += 1
                xOffset += 1
            }
            yOffset += 1
        }

        return count > 0 ? (sum / count) : 0
    }

    static SampleGray(image, x, y) {
        sampleX := BC_Detect.Clamp(x, 0, image.Width - 1)
        sampleY := BC_Detect.Clamp(y, 0, image.Height - 1)
        index := ((sampleY * image.Width) + sampleX) * 3
        b := NumGet(image.Pixels, index, "UChar")
        g := NumGet(image.Pixels, index + 1, "UChar")
        r := NumGet(image.Pixels, index + 2, "UChar")
        return Floor((r * 299 + g * 587 + b * 114) / 1000)
    }

    static Clamp(value, minValue, maxValue) {
        if (value < minValue) {
            return minValue
        }
        if (value > maxValue) {
            return maxValue
        }
        return value
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
