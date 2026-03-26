/*
script name: DesktopAHK/Interfaces.ahk
version: 0.2.0
purpose: Defines the shared result shapes used by the BarCode AHK harness.
dependencies: AutoHotkey v2.0+
important assumptions: Uses plain AHK objects as lightweight interface carriers.
protocol version: BC-Strip/1
framework module role: Shared contracts
character count note: Character count not precomputed; measure with tooling if needed.
*/

class BC_Interfaces {
    static DetectionResult(profile, threshold, blackMean, whiteMean, borderErrors, notes := "", originX := 0, originY := 0, pitch := 0, bandWidth := 0, bandHeight := 0, contrast := 0, searchMode := "exact") {
        return {
            Profile: profile,
            Threshold: threshold,
            BlackMean: blackMean,
            WhiteMean: whiteMean,
            BorderErrors: borderErrors,
            Notes: notes,
            OriginX: originX,
            OriginY: originY,
            Pitch: pitch,
            BandWidth: bandWidth,
            BandHeight: bandHeight,
            Contrast: contrast,
            SearchMode: searchMode
        }
    }

    static DecodeResult(bytes, bitErrors, minMargin, cellCount) {
        return {
            Bytes: bytes,
            BitErrors: bitErrors,
            MinMargin: minMargin,
            CellCount: cellCount
        }
    }

    static ValidationResult(isAccepted, reason, confidence, details) {
        return {
            IsAccepted: isAccepted,
            Reason: reason,
            Confidence: confidence,
            Details: details
        }
    }
}

; end-of-script marker comment
