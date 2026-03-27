/*
script name: DesktopAHK/Main.ahk
version: 0.3.12
purpose: Entry point for the BC-Strip/1 schema-3 reader smoke, BMP, and bounded live-capture harness.
dependencies: AutoHotkey v2.0+, DesktopAHK modular files
important assumptions: Default mode runs the synthetic schema-3 reader smoke; bmp mode decodes a supplied image; live mode captures the visible RIFT client top region from the desktop.
protocol version: BC-Strip/1
framework module role: Desktop entry point
character count note: Character count not precomputed; measure with tooling if needed.
*/

BC_MainUsageText() {
    lines := []
    lines.Push("BarCode DesktopAHK usage")
    lines.Push("  smoke")
    lines.Push("  bmp <path> [cropX] [cropY]")
    lines.Push("  summary")
    lines.Push("  hud [autoCloseMs]")
    lines.Push("  ui [autoCloseMs]")
    lines.Push("  hudbmp <path> [cropX] [cropY] [autoCloseMs]")
    lines.Push("  uibmp <path> [cropX] [cropY] [autoCloseMs]")
    lines.Push("  live [sampleCount] [sleepMs]")
    lines.Push("  watch [durationSeconds] [sleepMs]")
    lines.Push("  livehud synthetic [intervalMs] [autoCloseMs]")
    lines.Push("  livehud bmp <path> [cropX] [cropY] [intervalMs] [autoCloseMs]")
    lines.Push("  livehud live [intervalMs] [autoCloseMs]")
    lines.Push("  liveui synthetic [intervalMs] [autoCloseMs]")
    lines.Push("  liveui bmp <path> [cropX] [cropY] [intervalMs] [autoCloseMs]")
    lines.Push("  liveui live [intervalMs] [autoCloseMs]")
    lines.Push("  help")
    return BC_Debug.Join(lines, "`r`n")
}

BC_MainWriteStdOut(text) {
    try {
        stdout := FileOpen("*", "w", "UTF-8")
        if IsObject(stdout) {
            stdout.Write(text "`r`n")
            stdout.Close()
            return
        }
    } catch {
    }

    try {
        FileAppend(text "`r`n", "*", "UTF-8")
    } catch {
    }
}

BC_MainBuildSummaryText(mode, result) {
    lines := []
    summary := IsObject(result) && result.HasOwnProp("Summary") ? result.Summary : ""

    lines.Push("BarCode DesktopAHK")
    lines.Push("Mode: " mode)
    lines.Push("Success: " ((IsObject(result) && result.HasOwnProp("Success") && result.Success) ? "true" : "false"))
    if (IsObject(result) && result.HasOwnProp("ReportPath")) {
        lines.Push("Report: " result.ReportPath)
    }

    if !IsObject(summary) {
        return BC_Debug.Join(lines, "`r`n")
    }

    if (summary.HasOwnProp("Mode") && summary.Mode = "smoke") {
        lines.Push("GoodAccepted: " (summary.GoodAccepted ? "true" : "false"))
        lines.Push("CorruptAccepted: " (summary.CorruptAccepted ? "true" : "false"))
        lines.Push("CorruptReason: " summary.CorruptReason)
        return BC_Debug.Join(lines, "`r`n")
    }

    if (summary.HasOwnProp("Mode") && summary.Mode = "bmp") {
        lines.Push("Accepted: " (summary.Accepted ? "true" : "false"))
        lines.Push("Reason: " summary.Reason)
        lines.Push("SearchMode: " summary.SearchMode)
        if (summary.Sequence != "") {
            lines.Push("Sequence: " summary.Sequence)
        }
        if (summary.PageId != "") {
            lines.Push("PageId: " summary.PageId)
        }
        return BC_Debug.Join(lines, "`r`n")
    }

    if (summary.HasOwnProp("Mode") && summary.Mode = "summary") {
        if (summary.HasOwnProp("Text") && summary.Text != "") {
            return summary.Text
        }
        lines.Push("Summary: unavailable")
        return BC_Debug.Join(lines, "`r`n")
    }

    if (summary.HasOwnProp("Mode") && (summary.Mode = "live" || summary.Mode = "watch")) {
        lines.Push("AcceptedSamples: " summary.AcceptedSamples)
        lines.Push("RejectedSamples: " summary.RejectedSamples)
        lines.Push("LockedSamples: " summary.LockedSamples)
        lines.Push("SearchedSamples: " summary.SearchedSamples)
        lines.Push("CaptureSource: " summary.CaptureSource)
        if (summary.HasOwnProp("ClientRectText")) {
            lines.Push("ClientRect: " summary.ClientRectText)
        }
        if (summary.HasOwnProp("CaptureRectText")) {
            lines.Push("CaptureRect: " summary.CaptureRectText)
        }
        if (summary.HasOwnProp("CaptureRouteReason")) {
            lines.Push("CaptureRouteReason: " summary.CaptureRouteReason)
        }
        if (summary.HasOwnProp("CaptureHintMode")) {
            lines.Push("CaptureHintMode: " summary.CaptureHintMode)
        }
        if (summary.HasOwnProp("AverageCaptureMs")) {
            lines.Push("AverageCaptureMs: " summary.AverageCaptureMs)
        }
        if (summary.HasOwnProp("AveragePipelineMs")) {
            lines.Push("AveragePipelineMs: " summary.AveragePipelineMs)
        }
        lines.Push("FallbackSamples: " summary.FallbackSamples)
        lines.Push("LastReason: " summary.LastReason)
        return BC_Debug.Join(lines, "`r`n")
    }

    if (summary.HasOwnProp("Mode") && (summary.Mode = "ui" || summary.Mode = "liveui" || summary.Mode = "hud" || summary.Mode = "livehud")) {
        lines.Push("Accepted: " (summary.Accepted ? "true" : "false"))
        lines.Push("Reason: " summary.Reason)
        if (summary.Sequence != "") {
            lines.Push("Sequence: " summary.Sequence)
        }
        if (summary.SearchMode != "") {
            lines.Push("SearchMode: " summary.SearchMode)
        }
        return BC_Debug.Join(lines, "`r`n")
    }

    return BC_Debug.Join(lines, "`r`n")
}

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

    if (mode = "help" || mode = "--help" || mode = "-h") {
        BC_Debug.WriteText(BC_Config.LatestRunPath, BC_MainUsageText())
        result := {
            Success: true,
            ReportPath: BC_Config.LatestRunPath
        }
    } else if (mode = "summary") {
        if !FileExist(BC_Config.LiveSummaryTextPath) {
            throw Error("No summary has been written yet. Run smoke, bmp, live, or watch first.")
        }
        result := {
            Success: true,
            ReportPath: BC_Config.LiveSummaryTextPath,
            Summary: {
                Mode: "summary",
                Text: FileRead(BC_Config.LiveSummaryTextPath, "UTF-8")
            }
        }
    } else if (mode = "bmp") {
        if (A_Args.Length < 2) {
            throw Error("bmp mode requires a path argument`r`n`r`n" BC_MainUsageText())
        }
        cropX := A_Args.Length >= 3 ? Integer(A_Args[3]) : 0
        cropY := A_Args.Length >= 4 ? Integer(A_Args[4]) : 0
        result := BC_Tests.RunFixedBmpDecode(A_Args[2], cropX, cropY)
    } else if (mode = "ui") {
        autoCloseMs := A_Args.Length >= 2 ? Integer(A_Args[2]) : 0
        if (autoCloseMs < 0) {
            throw Error("ui mode auto-close must be non-negative")
        }
        result := BC_Overlay.RunSyntheticDashboard(autoCloseMs)
    } else if (mode = "hud") {
        autoCloseMs := A_Args.Length >= 2 ? Integer(A_Args[2]) : 0
        if (autoCloseMs < 0) {
            throw Error("hud mode auto-close must be non-negative")
        }
        result := BC_Overlay.RunSyntheticHud(autoCloseMs)
    } else if (mode = "uibmp") {
        if (A_Args.Length < 2) {
            throw Error("uibmp mode requires a path argument`r`n`r`n" BC_MainUsageText())
        }
        cropX := A_Args.Length >= 3 ? Integer(A_Args[3]) : 0
        cropY := A_Args.Length >= 4 ? Integer(A_Args[4]) : 0
        autoCloseMs := A_Args.Length >= 5 ? Integer(A_Args[5]) : 0
        if (autoCloseMs < 0) {
            throw Error("uibmp mode auto-close must be non-negative")
        }
        result := BC_Overlay.RunBmpDashboard(A_Args[2], cropX, cropY, autoCloseMs)
    } else if (mode = "hudbmp") {
        if (A_Args.Length < 2) {
            throw Error("hudbmp mode requires a path argument`r`n`r`n" BC_MainUsageText())
        }
        cropX := A_Args.Length >= 3 ? Integer(A_Args[3]) : 0
        cropY := A_Args.Length >= 4 ? Integer(A_Args[4]) : 0
        autoCloseMs := A_Args.Length >= 5 ? Integer(A_Args[5]) : 0
        if (autoCloseMs < 0) {
            throw Error("hudbmp mode auto-close must be non-negative")
        }
        result := BC_Overlay.RunBmpHud(A_Args[2], cropX, cropY, autoCloseMs)
    } else if (mode = "liveui") {
        source := A_Args.Length >= 2 ? StrLower(A_Args[2]) : "synthetic"
        if (source = "synthetic") {
            intervalMs := A_Args.Length >= 3 ? Integer(A_Args[3]) : 250
            autoCloseMs := A_Args.Length >= 4 ? Integer(A_Args[4]) : 0
            if (intervalMs < 25) {
                throw Error("liveui synthetic interval must be at least 25ms")
            }
            if (autoCloseMs < 0) {
                throw Error("liveui synthetic auto-close must be non-negative")
            }
            result := BC_Overlay.RunLiveUiSynthetic(intervalMs, autoCloseMs)
        } else if (source = "bmp") {
            if (A_Args.Length < 3) {
                throw Error("liveui bmp mode requires a path argument`r`n`r`n" BC_MainUsageText())
            }
            cropX := A_Args.Length >= 4 ? Integer(A_Args[4]) : 0
            cropY := A_Args.Length >= 5 ? Integer(A_Args[5]) : 0
            intervalMs := A_Args.Length >= 6 ? Integer(A_Args[6]) : 250
            autoCloseMs := A_Args.Length >= 7 ? Integer(A_Args[7]) : 0
            if (intervalMs < 25) {
                throw Error("liveui bmp interval must be at least 25ms")
            }
            if (autoCloseMs < 0) {
                throw Error("liveui bmp auto-close must be non-negative")
            }
            result := BC_Overlay.RunLiveUiBmp(A_Args[3], cropX, cropY, intervalMs, autoCloseMs)
        } else if (source = "live") {
            intervalMs := A_Args.Length >= 3 ? Integer(A_Args[3]) : 250
            autoCloseMs := A_Args.Length >= 4 ? Integer(A_Args[4]) : 0
            if (intervalMs < 25) {
                throw Error("liveui live interval must be at least 25ms")
            }
            if (autoCloseMs < 0) {
                throw Error("liveui live auto-close must be non-negative")
            }
            result := BC_Overlay.RunLiveUiLive(intervalMs, autoCloseMs)
        } else {
            throw Error("Unsupported liveui source: " source "`r`n`r`n" BC_MainUsageText())
        }
    } else if (mode = "livehud") {
        source := A_Args.Length >= 2 ? StrLower(A_Args[2]) : "synthetic"
        if (source = "synthetic") {
            intervalMs := A_Args.Length >= 3 ? Integer(A_Args[3]) : 250
            autoCloseMs := A_Args.Length >= 4 ? Integer(A_Args[4]) : 0
            if (intervalMs < 25) {
                throw Error("livehud synthetic interval must be at least 25ms")
            }
            if (autoCloseMs < 0) {
                throw Error("livehud synthetic auto-close must be non-negative")
            }
            result := BC_Overlay.RunLiveHudSynthetic(intervalMs, autoCloseMs)
        } else if (source = "bmp") {
            if (A_Args.Length < 3) {
                throw Error("livehud bmp mode requires a path argument`r`n`r`n" BC_MainUsageText())
            }
            cropX := A_Args.Length >= 4 ? Integer(A_Args[4]) : 0
            cropY := A_Args.Length >= 5 ? Integer(A_Args[5]) : 0
            intervalMs := A_Args.Length >= 6 ? Integer(A_Args[6]) : 250
            autoCloseMs := A_Args.Length >= 7 ? Integer(A_Args[7]) : 0
            if (intervalMs < 25) {
                throw Error("livehud bmp interval must be at least 25ms")
            }
            if (autoCloseMs < 0) {
                throw Error("livehud bmp auto-close must be non-negative")
            }
            result := BC_Overlay.RunLiveHudBmp(A_Args[3], cropX, cropY, intervalMs, autoCloseMs)
        } else if (source = "live") {
            intervalMs := A_Args.Length >= 3 ? Integer(A_Args[3]) : 250
            autoCloseMs := A_Args.Length >= 4 ? Integer(A_Args[4]) : 0
            if (intervalMs < 25) {
                throw Error("livehud live interval must be at least 25ms")
            }
            if (autoCloseMs < 0) {
                throw Error("livehud live auto-close must be non-negative")
            }
            result := BC_Overlay.RunLiveHudLive(intervalMs, autoCloseMs)
        } else {
            throw Error("Unsupported livehud source: " source "`r`n`r`n" BC_MainUsageText())
        }
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
    } else if (mode = "watch") {
        durationSeconds := A_Args.Length >= 2 ? Integer(A_Args[2]) : 0
        sleepMs := A_Args.Length >= 3 ? Integer(A_Args[3]) : 100
        if (durationSeconds < 0) {
            throw Error("watch mode duration must be non-negative")
        }
        if (sleepMs < 0) {
            throw Error("watch mode sleep must be non-negative")
        }
        result := BC_Tests.RunLiveWatch(durationSeconds, sleepMs)
    } else if (mode = "smoke") {
        result := BC_Tests.RunReaderSmoke()
    } else {
        throw Error("Unsupported mode: " mode "`r`n`r`n" BC_MainUsageText())
    }

    latestLines := []
    latestLines.Push("BarCode DesktopAHK run complete")
    latestLines.Push("Mode=" mode)
    latestLines.Push("Success=" (result.Success ? "true" : "false"))
    latestLines.Push("Report=" result.ReportPath)
    BC_Debug.WriteText(BC_Config.LatestRunPath, BC_Debug.Join(latestLines, "`r`n"))
    BC_MainWriteStdOut(BC_MainBuildSummaryText(mode, result))
    ExitApp(result.Success ? 0 : 1)
} catch as err {
    BC_Debug.WriteText(BC_Config.LatestRunPath, "BarCode DesktopAHK run failed`r`n" err.Message "`r`n" err.Stack)
    BC_MainWriteStdOut("BarCode DesktopAHK`r`nMode: failed`r`nSuccess: false`r`nError: " err.Message)
    ExitApp(1)
}

; end-of-script marker comment
