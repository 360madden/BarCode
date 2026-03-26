/*
script name: DesktopAHK/Capture.ahk
version: 0.1.0
purpose: Reserves the capture abstraction for live-client work after the offline decoder spike.
dependencies: AutoHotkey v2.0+
important assumptions: Live capture is intentionally deferred until the synthetic harness is proven.
protocol version: BC-Strip/1
framework module role: Capture abstraction
character count note: Character count not precomputed; measure with tooling if needed.
*/

class BC_Capture {
    static AcquireTopBand() {
        throw Error("Live capture is not implemented in phase 1. Use DesktopAHK/Tests.ahk fixtures instead.")
    }
}

; end-of-script marker comment
