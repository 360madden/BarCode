/*
script name: DesktopAHK/Interfaces.ahk
version: 0.1.0
purpose: Defines the shared result shapes used by the BarCode AHK harness.
dependencies: AutoHotkey v2.0+
important assumptions: Uses plain AHK objects as lightweight interface carriers.
protocol version: BC-Strip/1
framework module role: Shared contracts
character count note: Character count not precomputed; measure with tooling if needed.
*/

class BC_Interfaces {
    static DetectionResult(profile, threshold, blackMean, whiteMean, borderErrors, notes := "") {
        return {
            Profile: profile,
            Threshold: threshold,
            BlackMean: blackMean,
            WhiteMean: whiteMean,
            BorderErrors: borderErrors,
            Notes: notes
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
