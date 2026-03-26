/*
script name: DesktopAHK/Overlay.ahk
version: 0.1.0
purpose: Holds the optional diagnostics overlay boundary for later phases.
dependencies: AutoHotkey v2.0+
important assumptions: No GUI overlay is required in phase 1.
protocol version: BC-Strip/1
framework module role: Diagnostics overlay
character count note: Character count not precomputed; measure with tooling if needed.
*/

class BC_Overlay {
    static ShowPlaceholder() {
        return false
    }
}

; end-of-script marker comment
