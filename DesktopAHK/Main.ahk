/*
script name: DesktopAHK/Main.ahk
version: 0.2.0
purpose: Entry point for the BC-Strip/1 reader smoke, BMP, and bounded live-capture harness.
dependencies: AutoHotkey v2.0+, DesktopAHK modular files
important assumptions: Default mode runs the synthetic schema-2 reader smoke; bmp mode decodes a supplied image; live mode captures the visible RIFT client top region from the desktop.
protocol version: BC-Strip/1
framework module role: Desktop entry point
character count note: Character count not precomputed; measure with tooling if needed.
*/

#Requires AutoHotkey v2.0
#SingleInstance Force
#ErrorStdOut UTF-8

#Include Config.ahk
#Include Interfaces.ahk
#Include Debug.ahk
#Include Capture.ahk
#Include Protocol.ahk
#Include Detect.ahk
#Include Decode.ahk
#Include Validate.ahk
#Include State.ahk
#Include Overlay.ahk
#Include Tests.ahk

try {
    BC_Debug.WriteText(BC_Config.LatestRunPath, "BarCode DesktopAHK run starting")
    mode := A_Args.Length >= 1 ? StrLower(A_Args[1]) : "smoke"

    if (mode = "bmp") {
        if (A_Args.Length < 2) {
            throw Error("bmp mode requires a path argument")
        }
        cropX := A_Args.Length >= 3 ? Integer(A_Args[3]) : 0
        cropY := A_Args.Length >= 4 ? Integer(A_Args[4]) : 0
        result := BC_Tests.RunFixedBmpDecode(A_Args[2], cropX, cropY)
    } else if (mode = "live") {
        sampleCount := A_Args.Length >= 2 ? Integer(A_Args[2]) : 20
        sleepMs := A_Args.Length >= 3 ? Integer(A_Args[3]) : 100
        if (sampleCount <= 0) {
            throw Error("live mode sample count must be positive")
        }
        if (sleepMs < 0) {
            throw Error("live mode sleep must be non-negative")
        }
        result := BC_Tests.RunLiveDecode(sampleCount, sleepMs)
    } else if (mode = "smoke") {
        result := BC_Tests.RunReaderSmoke()
    } else {
        throw Error("Unsupported mode: " mode)
    }

    latestLines := []
    latestLines.Push("BarCode DesktopAHK run complete")
    latestLines.Push("Mode=" mode)
    latestLines.Push("Success=" (result.Success ? "true" : "false"))
    latestLines.Push("Report=" result.ReportPath)
    BC_Debug.WriteText(BC_Config.LatestRunPath, BC_Debug.Join(latestLines, "`r`n"))
    ExitApp(result.Success ? 0 : 1)
} catch as err {
    BC_Debug.WriteText(BC_Config.LatestRunPath, "BarCode DesktopAHK run failed`r`n" err.Message "`r`n" err.Stack)
    ExitApp(1)
}

; end-of-script marker comment
