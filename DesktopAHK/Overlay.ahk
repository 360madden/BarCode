/*
script name: DesktopAHK/Overlay.ahk
version: 0.3.14
purpose: Provides a compact reader dashboard UI skeleton for synthetic, BMP, and future live BarCode decode views.
dependencies: AutoHotkey v2.0+, DesktopAHK/State.ahk, DesktopAHK/Tests.ahk
important assumptions: This is a local diagnostics UI, not an in-game overlay, and it reads from the existing BarCode state model rather than creating a second UI-specific data path.
protocol version: BC-Strip/1
framework module role: Diagnostics overlay
character count note: Character count not precomputed; measure with tooling if needed.
*/

class BC_Overlay {
    static Palette := {
        WindowBack: "10151B",
        Header: "89DDFF",
        StatusOk: "C3E88D",
        StatusWarn: "FFCB6B",
        StatusBad: "F07178",
        Mode: "C792EA",
        SectionPlayer: "82AAFF",
        SectionTarget: "FFCB6B",
        SectionReader: "C792EA",
        BodyText: "D6DEEB",
        MutedText: "7F8C98",
        CaptureText: "F78C6C",
        DetailText: "A6ACCD",
        HistoryText: "A6E22E",
        Footer: "637777",
        PanelBack: "151A20"
    }
    static Window := ""
    static Controls := {}
    static CurrentTitle := "BarCode Reader Dashboard"
    static SurfaceMode := "dashboard"
    static LastSnapshot := ""
    static LiveUiMode := "synthetic"
    static LiveUiSourceLabel := "synthetic"
    static LiveUiProvider := ""
    static LiveUiRefreshCallback := ""
    static LiveUiAutoCloseCallback := ""
    static LiveUiIntervalMs := 250
    static LiveUiAutoCloseMs := 0
    static LiveUiTickCount := 0
    static LiveUiStartTick := 0
    static LiveUiLastSnapshot := ""
    static LiveUiLastAcceptedSnapshot := ""
    static LiveUiHistory := []
    static LiveUiHistoryLimit := 8

    static DiscardWindow() {
        if IsObject(BC_Overlay.Window) {
            try {
                BC_Overlay.Window.Destroy()
            } catch {
            }
        }

        BC_Overlay.Window := ""
        BC_Overlay.Controls := {}
    }

    static EnsureWindow(title := "BarCode Reader Dashboard") {
        if IsObject(BC_Overlay.Window) {
            if (BC_Overlay.SurfaceMode = "dashboard") {
                try {
                    BC_Overlay.Window.Title := title
                    return BC_Overlay.Window
                } catch {
                }
            }

            BC_Overlay.DiscardWindow()
        }

        BC_Overlay.SurfaceMode := "dashboard"

        window := Gui("+AlwaysOnTop +ToolWindow +MinSize740x790", title)
        window.BackColor := BC_Overlay.Palette.WindowBack
        window.MarginX := 12
        window.MarginY := 12
        window.SetFont("s11 c" BC_Overlay.Palette.BodyText, "Segoe UI")

        window.SetFont("s14 Bold c" BC_Overlay.Palette.Header, "Consolas")
        header := window.AddText("xm ym w700", "BarCode Reader Dashboard")
        window.SetFont("s10 c" BC_Overlay.Palette.StatusOk, "Consolas")
        status := window.AddText("xm y+8 w700", "Status: waiting")
        window.SetFont("s10 c" BC_Overlay.Palette.Mode, "Consolas")
        liveMode := window.AddText("xm y+4 w700", "Mode: idle")

        window.SetFont("s9 c" BC_Overlay.Palette.BodyText, "Segoe UI")
        refreshButton := window.AddButton("x+m yp-2 w80", "Refresh")
        copyPathButton := window.AddButton("x+m yp w110", "Copy State Path")
        copySummaryButton := window.AddButton("x+m yp w120", "Copy Summary")
        closeButton := window.AddButton("x+m yp w70", "Close")

        window.SetFont("s10 Bold c" BC_Overlay.Palette.SectionPlayer, "Consolas")
        playerGroup := window.AddGroupBox("xm y+14 w340 h205", "Player")
        window.SetFont("s10 c" BC_Overlay.Palette.BodyText, "Consolas")
        playerHealthLabel := window.AddText("xp+14 yp+24 w300", "Health: ")
        playerHealthBar := window.AddProgress("xp yp+22 w300 h16 c4CAF50 Background202020", 0)
        playerResourceLabel := window.AddText("xp yp+28 w300", "Resource: ")
        playerResourceBar := window.AddProgress("xp yp+22 w300 h16 c2AA1D3 Background202020", 0)
        window.SetFont("s10 c" BC_Overlay.Palette.MutedText, "Consolas")
        playerMeta := window.AddText("xp yp+28 w300", "Level / Calling / Role")
        window.SetFont("s9 c" BC_Overlay.Palette.StatusOk, "Consolas")
        playerOffense := window.AddEdit("xp yp+24 w300 r4 ReadOnly WantCtrlA Background" BC_Overlay.Palette.PanelBack, "")

        window.SetFont("s10 Bold c" BC_Overlay.Palette.SectionTarget, "Consolas")
        targetGroup := window.AddGroupBox("x+m yp w340 h205", "Target")
        window.SetFont("s10 c" BC_Overlay.Palette.BodyText, "Consolas")
        targetHealthLabel := window.AddText("xp+14 yp+24 w300", "Health: ")
        targetHealthBar := window.AddProgress("xp yp+22 w300 h16 cE57373 Background202020", 0)
        targetResourceLabel := window.AddText("xp yp+28 w300", "Resource: ")
        targetResourceBar := window.AddProgress("xp yp+22 w300 h16 cFFB74D Background202020", 0)
        window.SetFont("s10 c" BC_Overlay.Palette.MutedText, "Consolas")
        targetMeta := window.AddText("xp yp+28 w300", "Level / Flags")
        window.SetFont("s9 c" BC_Overlay.Palette.SectionTarget, "Consolas")
        targetExtras := window.AddEdit("xp yp+24 w300 r4 ReadOnly WantCtrlA Background" BC_Overlay.Palette.PanelBack, "")

        window.SetFont("s10 Bold c" BC_Overlay.Palette.SectionReader, "Consolas")
        readerGroup := window.AddGroupBox("xm y+16 w700 h155", "Reader")
        window.SetFont("s10 c" BC_Overlay.Palette.Header, "Consolas")
        transportText := window.AddText("xp+14 yp+24 w320 h96", "")
        window.SetFont("s10 c" BC_Overlay.Palette.CaptureText, "Consolas")
        captureText := window.AddText("x+m yp w330 h96", "")
        window.SetFont("s10 c" BC_Overlay.Palette.Mode, "Consolas")
        sessionText := window.AddText("xp yp+100 w670 h32", "")

        window.SetFont("s10 Bold c" BC_Overlay.Palette.Header, "Consolas")
        detailsGroup := window.AddGroupBox("xm y+16 w700 h210", "Snapshot Details")
        window.SetFont("s9 c" BC_Overlay.Palette.DetailText, "Consolas")
        detailsBody := window.AddEdit("xp+14 yp+24 w670 r8 ReadOnly WantCtrlA Background" BC_Overlay.Palette.PanelBack, "")

        window.SetFont("s10 Bold c" BC_Overlay.Palette.Header, "Consolas")
        historyGroup := window.AddGroupBox("xm y+16 w700 h120", "Recent Frames")
        window.SetFont("s9 c" BC_Overlay.Palette.HistoryText, "Consolas")
        historyBody := window.AddEdit("xp+14 yp+24 w670 r4 ReadOnly WantCtrlA Background" BC_Overlay.Palette.PanelBack, "")

        window.SetFont("s9 c" BC_Overlay.Palette.Footer, "Consolas")
        footer := window.AddText("xm y+10 w700", "Close the window to exit this reader preview.")

        window.OnEvent("Close", BC_Overlay.OnWindowClosed)
        window.OnEvent("Escape", BC_Overlay.OnWindowClosed)
        refreshButton.OnEvent("Click", BC_Overlay.OnRefreshClicked)
        copyPathButton.OnEvent("Click", BC_Overlay.OnCopyStatePathClicked)
        copySummaryButton.OnEvent("Click", BC_Overlay.OnCopySummaryClicked)
        closeButton.OnEvent("Click", BC_Overlay.OnCloseClicked)

        BC_Overlay.Window := window
        BC_Overlay.Controls := {
            Header: header,
            Status: status,
            LiveMode: liveMode,
            RefreshButton: refreshButton,
            CopyPathButton: copyPathButton,
            CopySummaryButton: copySummaryButton,
            CloseButton: closeButton,
            PlayerHealthLabel: playerHealthLabel,
            PlayerHealthBar: playerHealthBar,
            PlayerResourceLabel: playerResourceLabel,
            PlayerResourceBar: playerResourceBar,
            PlayerMeta: playerMeta,
            PlayerOffense: playerOffense,
            TargetHealthLabel: targetHealthLabel,
            TargetHealthBar: targetHealthBar,
            TargetResourceLabel: targetResourceLabel,
            TargetResourceBar: targetResourceBar,
            TargetMeta: targetMeta,
            TargetExtras: targetExtras,
            TransportText: transportText,
            CaptureText: captureText,
            SessionText: sessionText,
            DetailsBody: detailsBody,
            HistoryBody: historyBody,
            Footer: footer
        }

        return window
    }

    static EnsureHudWindow(title := "BarCode Reader HUD") {
        if IsObject(BC_Overlay.Window) {
            if (BC_Overlay.SurfaceMode = "hud") {
                try {
                    BC_Overlay.Window.Title := title
                    return BC_Overlay.Window
                } catch {
                }
            }

            BC_Overlay.DiscardWindow()
        }

        BC_Overlay.SurfaceMode := "hud"
        window := Gui("+AlwaysOnTop +ToolWindow +MinSize760x540", title)
        window.BackColor := BC_Overlay.Palette.WindowBack
        window.MarginX := 12
        window.MarginY := 12
        window.SetFont("s11 c" BC_Overlay.Palette.BodyText, "Segoe UI")

        window.SetFont("s14 Bold c" BC_Overlay.Palette.Header, "Consolas")
        header := window.AddText("xm ym w720", "BarCode Reader HUD")
        window.SetFont("s10 c" BC_Overlay.Palette.StatusOk, "Consolas")
        status := window.AddText("xm y+8 w720", "Status: waiting")
        window.SetFont("s10 c" BC_Overlay.Palette.Mode, "Consolas")
        liveMode := window.AddText("xm y+4 w720", "Mode: idle")

        window.SetFont("s9 c" BC_Overlay.Palette.BodyText, "Segoe UI")
        refreshButton := window.AddButton("x+m yp-2 w80", "Refresh")
        copyPathButton := window.AddButton("x+m yp w110", "Copy State Path")
        copySummaryButton := window.AddButton("x+m yp w120", "Copy Summary")
        closeButton := window.AddButton("x+m yp w70", "Close")

        window.SetFont("s10 Bold c" BC_Overlay.Palette.Header, "Consolas")
        compareText := window.AddText("xm y+16 w720", "Compare: waiting")

        window.SetFont("s10 Bold c" BC_Overlay.Palette.SectionPlayer, "Consolas")
        playerGroup := window.AddGroupBox("xm y+14 w350 h225", "Player")
        window.SetFont("s10 c" BC_Overlay.Palette.BodyText, "Consolas")
        playerHealthLabel := window.AddText("xp+14 yp+24 w312", "Health: -")
        playerHealthBar := window.AddProgress("xp yp+22 w312 h18 c4CAF50 Background202020", 0)
        playerResourceLabel := window.AddText("xp yp+28 w312", "Resource: -")
        playerResourceBar := window.AddProgress("xp yp+22 w312 h18 c2AA1D3 Background202020", 0)
        window.SetFont("s10 c" BC_Overlay.Palette.MutedText, "Consolas")
        playerMeta := window.AddText("xp yp+28 w312", "Level / Calling / Role")
        window.SetFont("s9 c" BC_Overlay.Palette.StatusOk, "Consolas")
        playerStatus := window.AddText("xp yp+24 w312", "State: -")
        window.SetFont("s9 c" BC_Overlay.Palette.BodyText, "Consolas")
        playerOffense := window.AddEdit("xp yp+24 w312 r4 ReadOnly WantCtrlA Background" BC_Overlay.Palette.PanelBack, "")

        window.SetFont("s10 Bold c" BC_Overlay.Palette.SectionTarget, "Consolas")
        targetGroup := window.AddGroupBox("x+m yp w350 h225", "Target")
        window.SetFont("s10 c" BC_Overlay.Palette.BodyText, "Consolas")
        targetHealthLabel := window.AddText("xp+14 yp+24 w312", "Health: -")
        targetHealthBar := window.AddProgress("xp yp+22 w312 h18 cE57373 Background202020", 0)
        targetResourceLabel := window.AddText("xp yp+28 w312", "Resource: -")
        targetResourceBar := window.AddProgress("xp yp+22 w312 h18 cFFB74D Background202020", 0)
        window.SetFont("s10 c" BC_Overlay.Palette.MutedText, "Consolas")
        targetMeta := window.AddText("xp yp+28 w312", "Level / Flags")
        window.SetFont("s9 c" BC_Overlay.Palette.SectionTarget, "Consolas")
        targetStatus := window.AddText("xp yp+24 w312", "State: -")
        window.SetFont("s9 c" BC_Overlay.Palette.BodyText, "Consolas")
        targetExtras := window.AddEdit("xp yp+24 w312 r4 ReadOnly WantCtrlA Background" BC_Overlay.Palette.PanelBack, "")

        window.SetFont("s10 Bold c" BC_Overlay.Palette.SectionReader, "Consolas")
        readerGroup := window.AddGroupBox("xm y+16 w720 h190", "Reader")
        window.SetFont("s10 c" BC_Overlay.Palette.Header, "Consolas")
        transportText := window.AddText("xp+14 yp+24 w340 h48", "")
        window.SetFont("s10 c" BC_Overlay.Palette.CaptureText, "Consolas")
        captureText := window.AddText("x+m yp w340 h48", "")
        window.SetFont("s9 c" BC_Overlay.Palette.HistoryText, "Consolas")
        sessionText := window.AddText("xp yp+52 w694 h32", "")
        historyText := window.AddEdit("xp yp+34 w694 r3 ReadOnly WantCtrlA Background" BC_Overlay.Palette.PanelBack, "")
        window.SetFont("s9 c" BC_Overlay.Palette.Footer, "Consolas")
        footer := window.AddText("xp yp+52 w694", "Close the window to exit this HUD preview.")

        window.OnEvent("Close", BC_Overlay.OnWindowClosed)
        window.OnEvent("Escape", BC_Overlay.OnWindowClosed)
        refreshButton.OnEvent("Click", BC_Overlay.OnRefreshClicked)
        copyPathButton.OnEvent("Click", BC_Overlay.OnCopyStatePathClicked)
        copySummaryButton.OnEvent("Click", BC_Overlay.OnCopySummaryClicked)
        closeButton.OnEvent("Click", BC_Overlay.OnCloseClicked)

        BC_Overlay.Window := window
        BC_Overlay.Controls := {
            Header: header,
            Status: status,
            LiveMode: liveMode,
            RefreshButton: refreshButton,
            CopyPathButton: copyPathButton,
            CopySummaryButton: copySummaryButton,
            CloseButton: closeButton,
            CompareText: compareText,
            PlayerHealthLabel: playerHealthLabel,
            PlayerHealthBar: playerHealthBar,
            PlayerResourceLabel: playerResourceLabel,
            PlayerResourceBar: playerResourceBar,
            PlayerMeta: playerMeta,
            PlayerStatus: playerStatus,
            PlayerOffense: playerOffense,
            TargetHealthLabel: targetHealthLabel,
            TargetHealthBar: targetHealthBar,
            TargetResourceLabel: targetResourceLabel,
            TargetResourceBar: targetResourceBar,
            TargetMeta: targetMeta,
            TargetStatus: targetStatus,
            TargetExtras: targetExtras,
            TransportText: transportText,
            CaptureText: captureText,
            SessionText: sessionText,
            HistoryText: historyText,
            Footer: footer
        }

        return window
    }

    static OnWindowClosed(guiObj := "", *) {
        BC_Overlay.StopLiveUiTimers()
        BC_Overlay.ResetLiveUiState()
        try {
            if IsObject(guiObj) {
                guiObj.Destroy()
            }
        } catch {
        }

        BC_Overlay.Window := ""
        BC_Overlay.Controls := {}
        BC_Overlay.SurfaceMode := "dashboard"
        BC_Overlay.LastSnapshot := ""
    }

    static CloseWindow(*) {
        BC_Overlay.StopLiveUiTimers()
        BC_Overlay.ResetLiveUiState()
        if IsObject(BC_Overlay.Window) {
            try {
                BC_Overlay.Window.Destroy()
            } catch {
            }
        }

        BC_Overlay.Window := ""
        BC_Overlay.Controls := {}
        BC_Overlay.SurfaceMode := "dashboard"
        BC_Overlay.LastSnapshot := ""
    }

    static StopLiveUiTimers() {
        if IsObject(BC_Overlay.LiveUiRefreshCallback) {
            try {
                SetTimer(BC_Overlay.LiveUiRefreshCallback, 0)
            } catch {
            }
            BC_Overlay.LiveUiRefreshCallback := ""
        }

        if IsObject(BC_Overlay.LiveUiAutoCloseCallback) {
            try {
                SetTimer(BC_Overlay.LiveUiAutoCloseCallback, 0)
            } catch {
            }
            BC_Overlay.LiveUiAutoCloseCallback := ""
        }
    }

    static ResetLiveUiState() {
        BC_Overlay.LiveUiMode := "synthetic"
        BC_Overlay.LiveUiSourceLabel := "synthetic"
        BC_Overlay.LiveUiProvider := ""
        BC_Overlay.LiveUiIntervalMs := 250
        BC_Overlay.LiveUiAutoCloseMs := 0
        BC_Overlay.LiveUiTickCount := 0
        BC_Overlay.LiveUiStartTick := 0
        BC_Overlay.SurfaceMode := "dashboard"
        BC_Overlay.ResetLiveUiHistory()
    }

    static HasLiveUiProvider() {
        try {
            return BC_Overlay.LiveUiProvider != "" && HasMethod(BC_Overlay.LiveUiProvider, "Call")
        } catch {
            return false
        }
    }

    static OnRefreshClicked(*) {
        if BC_Overlay.HasLiveUiProvider() {
            BC_Overlay.LiveUiTick()
            return
        }

        BC_Overlay.RenderSnapshot(BC_State.BuildSnapshot(), BC_Overlay.CurrentTitle)
    }

    static OnCopyStatePathClicked(*) {
        A_Clipboard := BC_Config.LiveStateTextPath
        BC_Overlay.SetFooter("State path copied: " BC_Config.LiveStateTextPath)
    }

    static OnCopySummaryClicked(*) {
        if IsObject(BC_Overlay.LastSnapshot) {
            A_Clipboard := BC_State.BuildOperatorSummaryText(BC_Overlay.LastSnapshot)
            BC_Overlay.SetFooter("Summary text copied to clipboard.")
        }
    }

    static OnCloseClicked(*) {
        BC_Overlay.CloseWindow()
    }

    static HistoryLine(snapshot) {
        verdict := BC_Overlay.IsHeldFrame(snapshot) ? "HELD" : (snapshot.accepted ? "ACCEPT" : "REJECT")
        seq := BC_Overlay.SafeText(snapshot.sequence, "-")
        confidence := BC_Overlay.SafeText(snapshot.confidence, "-")
        reason := BC_Overlay.SafeText(snapshot.reason, "-")
        freshness := BC_Overlay.FreshnessLabel(snapshot)
        searchMode := BC_Overlay.SafeText(snapshot.searchMode, "-")
        pipelineMs := BC_Overlay.SafeText(snapshot.pipelineMs, "-")
        return verdict " | " freshness " | " searchMode " | seq=" seq " | ms=" pipelineMs " | conf=" confidence " | " reason
    }

    static ResetLiveUiHistory() {
        BC_Overlay.LiveUiHistory := []
    }

    static PushLiveUiHistory(snapshot) {
        line := BC_Overlay.HistoryLine(snapshot)
        BC_Overlay.LiveUiHistory.Push(line)
        while (BC_Overlay.LiveUiHistory.Length > BC_Overlay.LiveUiHistoryLimit) {
            BC_Overlay.LiveUiHistory.RemoveAt(1)
        }
    }

    static RenderLiveUiHistory() {
        try {
            helperText := BC_State.BuildRecentHistoryText(BC_Overlay.LiveUiHistoryLimit)
            if (helperText != "") {
                return helperText
            }
        } catch {
        }

        if !IsObject(BC_Overlay.LiveUiHistory) || (BC_Overlay.LiveUiHistory.Length = 0) {
            return "No samples yet."
        }

        lines := []
        index := 1
        while (index <= BC_Overlay.LiveUiHistory.Length) {
            lines.Push(BC_Overlay.LiveUiHistory[index])
            index += 1
        }
        return BC_Debug.Join(lines, "`r`n")
    }

    static SetFooter(text) {
        if (IsObject(BC_Overlay.Controls) && BC_Overlay.Controls.HasOwnProp("Footer")) {
            BC_Overlay.Controls.Footer.Text := text
            try {
                BC_Overlay.Controls.Footer.SetFont("c" BC_Overlay.Palette.Footer, "Consolas")
            } catch {
            }
        }
    }

    static SafeText(value, fallback := "") {
        return value = "" ? fallback : ("" value)
    }

    static Percent(current, maximum) {
        numericCurrent := Integer(current || 0)
        numericMaximum := Integer(maximum || 0)
        if (numericMaximum <= 0) {
            return 0
        }

        pct := Floor((numericCurrent * 100.0) / numericMaximum)
        if (pct < 0) {
            return 0
        }
        if (pct > 100) {
            return 100
        }
        return pct
    }

    static PairText(current, maximum) {
        return BC_Overlay.SafeText(current, "0") "/" BC_Overlay.SafeText(maximum, "0")
    }

    static CloneSnapshot(snapshot) {
        copy := {}
        for key, value in snapshot.OwnProps() {
            copy.%key% := value
        }
        return copy
    }

    static IsHeldFrame(snapshot) {
        return snapshot.HasOwnProp("heldFrame") && snapshot.heldFrame
    }

    static BuildHeldDisplaySnapshot(snapshot) {
        if BC_Overlay.IsHeldFrame(snapshot) {
            return BC_Overlay.CloneSnapshot(snapshot)
        }

        if !IsObject(BC_Overlay.LiveUiLastAcceptedSnapshot) {
            return snapshot
        }

        base := BC_Overlay.CloneSnapshot(BC_Overlay.LiveUiLastAcceptedSnapshot)
        base.accepted := false
        base.heldFrame := true
        base.freshFrame := false
        base.sequenceChanged := false
        base.reason := snapshot.reason = ""
            ? "Holding last accepted frame"
            : "Holding last accepted frame | " snapshot.reason
        base.confidence := snapshot.confidence
        base.searchMode := snapshot.searchMode
        base.borderErrors := snapshot.borderErrors
        base.originX := snapshot.originX
        base.originY := snapshot.originY
        base.pitch := snapshot.pitch
        base.bandWidth := snapshot.bandWidth
        base.bandHeight := snapshot.bandHeight
        base.captureSource := snapshot.captureSource
        base.captureRequestedSource := snapshot.captureRequestedSource
        base.captureResolvedSource := snapshot.captureResolvedSource
        base.captureRouteReason := snapshot.captureRouteReason
        base.captureFallbackFrom := snapshot.captureFallbackFrom
        base.captureHintMode := snapshot.captureHintMode
        base.captureHintPitch := snapshot.captureHintPitch
        base.clientX := snapshot.clientX
        base.clientY := snapshot.clientY
        base.clientWidth := snapshot.clientWidth
        base.clientHeight := snapshot.clientHeight
        base.captureLeft := snapshot.captureLeft
        base.captureTop := snapshot.captureTop
        base.captureWidth := snapshot.captureWidth
        base.captureHeight := snapshot.captureHeight
        base.captureAttempts := snapshot.captureAttempts
        base.captureMs := snapshot.captureMs
        base.pipelineMs := snapshot.pipelineMs
        base.attemptCount := snapshot.attemptCount
        base.sampleIndex := snapshot.sampleIndex
        base.sessionStartedUtc := snapshot.sessionStartedUtc
        base.sessionSampleCount := snapshot.sessionSampleCount
        base.sessionAcceptedCount := snapshot.sessionAcceptedCount
        base.sessionRejectedCount := snapshot.sessionRejectedCount
        base.acceptedStreak := snapshot.acceptedStreak
        base.rejectedStreak := snapshot.rejectedStreak
        base.lastAcceptedTimestampUtc := snapshot.lastAcceptedTimestampUtc
        base.lastRejectedTimestampUtc := snapshot.lastRejectedTimestampUtc
        base.lastAcceptedSequence := snapshot.lastAcceptedSequence
        base.sequenceAdvance := snapshot.sequenceAdvance
        base.sequenceRepeatedCount := snapshot.sequenceRepeatedCount
        base.sequenceWrapCount := snapshot.sequenceWrapCount
        base.windowTitle := snapshot.windowTitle
        base.processName := snapshot.processName
        base.timestampUtc := snapshot.timestampUtc
        return base
    }

    static StatusVerdict(snapshot) {
        if BC_Overlay.IsHeldFrame(snapshot) {
            return "HELD"
        }
        return snapshot.accepted ? "ACCEPTED" : "REJECTED"
    }

    static StatusColor(snapshot) {
        if BC_Overlay.IsHeldFrame(snapshot) {
            return BC_Overlay.Palette.StatusWarn
        }
        return snapshot.accepted
            ? (snapshot.freshFrame ? BC_Overlay.Palette.StatusOk : BC_Overlay.Palette.StatusWarn)
            : BC_Overlay.Palette.StatusBad
    }

    static FreshnessLabel(snapshot) {
        if BC_Overlay.IsHeldFrame(snapshot) {
            return "held"
        }

        if !snapshot.accepted {
            return "bad"
        }

        if (snapshot.sequenceChanged = "") {
            return "unknown"
        }

        return snapshot.freshFrame ? "fresh" : "repeat"
    }

    static FormatTransportText(snapshot) {
        lines := []
        lines.Push("Sequence: " BC_Overlay.SafeText(snapshot.sequence, "-"))
        lines.Push("Page / Payload: " BC_Overlay.SafeText(snapshot.pageId, "-") " / " BC_Overlay.SafeText(snapshot.payloadUsedLength, "-"))
        lines.Push("Frame / Advance: " BC_Overlay.FreshnessLabel(snapshot) " / " BC_Overlay.SafeText(snapshot.sequenceAdvance, "-"))
        lines.Push("Confidence: " BC_Overlay.SafeText(snapshot.confidence, "-"))
        lines.Push("Reason: " BC_Overlay.SafeText(snapshot.reason, "-"))
        lines.Push("Search: " BC_Overlay.SafeText(snapshot.searchMode, "-"))
        lines.Push("Pitch / Band: " BC_Overlay.SafeText(snapshot.pitch, "-") " / " BC_Overlay.SafeText(snapshot.bandWidth, "-") "x" BC_Overlay.SafeText(snapshot.bandHeight, "-"))
        return BC_Debug.Join(lines, "`r`n")
    }

    static FormatCaptureText(snapshot) {
        lines := []
        capturePath := (snapshot.attemptCount != "" && Integer(snapshot.attemptCount) > 1) ? "fallback" : "direct"
        lines.Push("Window: " BC_Overlay.SafeText(snapshot.windowTitle, "-"))
        lines.Push("Process: " BC_Overlay.SafeText(snapshot.processName, "-"))
        lines.Push("Capture: " BC_Overlay.SafeText(snapshot.captureSource, "-") " (" capturePath ")")
        lines.Push("Route / Hint: " BC_Overlay.SafeText(snapshot.captureRouteReason, "-") " / " BC_Overlay.SafeText(snapshot.captureHintMode, "-"))
        lines.Push("Requested / Resolved: " BC_Overlay.SafeText(snapshot.captureRequestedSource, "-") " / " BC_Overlay.SafeText(snapshot.captureResolvedSource, "-"))
        lines.Push("Client / Capture: " BC_State.RectText(snapshot.clientX, snapshot.clientY, snapshot.clientWidth, snapshot.clientHeight) " / " BC_State.RectText(snapshot.captureLeft, snapshot.captureTop, snapshot.captureWidth, snapshot.captureHeight))
        lines.Push("Attempts: " BC_Overlay.SafeText(snapshot.captureAttempts, "-"))
        lines.Push("Capture / Pipeline ms: " BC_Overlay.SafeText(snapshot.captureMs, "-") " / " BC_Overlay.SafeText(snapshot.pipelineMs, "-"))
        lines.Push("Origin / Border: " BC_Overlay.SafeText(snapshot.originX, "-") "," BC_Overlay.SafeText(snapshot.originY, "-") " / " BC_Overlay.SafeText(snapshot.borderErrors, "-"))
        return BC_Debug.Join(lines, "`r`n")
    }

    static FormatSessionText(snapshot) {
        line := (
            "Session " BC_Overlay.SafeText(snapshot.sessionSampleCount, "0")
            " samples | accepted " BC_Overlay.SafeText(snapshot.sessionAcceptedCount, "0")
            " | rejected " BC_Overlay.SafeText(snapshot.sessionRejectedCount, "0")
            " | streak " BC_Overlay.SafeText(snapshot.acceptedStreak, "0")
            "/" BC_Overlay.SafeText(snapshot.rejectedStreak, "0")
            " | repeats " BC_Overlay.SafeText(snapshot.sequenceRepeatedCount, "0")
            " | wraps " BC_Overlay.SafeText(snapshot.sequenceWrapCount, "0")
        )
        if BC_State.HasTarget(snapshot) {
            line .= "`r`nCompare " BC_State.BuildComparisonText(snapshot)
        }
        return line
    }

    static FormatPlayerMeta(snapshot) {
        return (
            "Level " BC_Overlay.SafeText(snapshot.playerLevel, "-")
            " | " BC_Overlay.SafeText(snapshot.playerCallingName, "unknown")
            " | " BC_Overlay.SafeText(snapshot.playerRoleName, "unknown")
            " | " BC_State.JoinTags(BC_State.BuildPlayerStateTags(snapshot))
        )
    }

    static FormatPlayerOffense(snapshot) {
        lines := []
        lines.Push(
            "HP: "
            BC_State.PairOrDefaultText(snapshot.playerHealthCurrent, snapshot.playerHealthMax)
            " (" BC_State.PercentText(snapshot.playerHealthCurrent, snapshot.playerHealthMax) ")"
            "   "
            BC_Overlay.SafeText(snapshot.playerResourceKindName, "resource")
            ": "
            BC_State.PairOrDefaultText(snapshot.playerResourceCurrent, snapshot.playerResourceMax)
            " (" BC_State.PercentText(snapshot.playerResourceCurrent, snapshot.playerResourceMax) ")"
        )
        lines.Push("Attack Power: " BC_Overlay.SafeText(snapshot.playerPowerAttack, "0") "   Crit Attack: " BC_Overlay.SafeText(snapshot.playerCritAttack, "0"))
        lines.Push("Spell Power: " BC_Overlay.SafeText(snapshot.playerPowerSpell, "0") "   Crit Spell: " BC_Overlay.SafeText(snapshot.playerCritSpell, "0"))
        lines.Push("Crit Power: " BC_Overlay.SafeText(snapshot.playerCritPower, "0") "   Hit: " BC_Overlay.SafeText(snapshot.playerHit, "0"))
        lines.Push("Flags: " BC_State.JoinTags(BC_State.BuildPlayerStateTags(snapshot)) "   Damage Estimate: " BC_Overlay.SafeText(snapshot.playerDamageEstimate, "0"))
        return BC_Debug.Join(lines, "`r`n")
    }

    static HasTarget(snapshot) {
        return BC_State.HasTarget(snapshot)
    }

    static FormatTargetMeta(snapshot) {
        if !BC_Overlay.HasTarget(snapshot) {
            return "No target selected"
        }

        return (
            "Level " BC_Overlay.SafeText(snapshot.targetLevel, "-")
            " | Flags " BC_State.HexText(snapshot.targetFlags, 2)
            " | Resource " BC_Overlay.SafeText(snapshot.targetResourceKindName, "none")
            " | " BC_State.JoinTags(BC_State.BuildTargetStateTags(snapshot))
        )
    }

    static FormatTargetExtras(snapshot) {
        if !BC_Overlay.HasTarget(snapshot) {
            return "Target telemetry unavailable."
        }

        lines := []
        lines.Push("Health: " BC_State.PairOrDefaultText(snapshot.targetHealthCurrent, snapshot.targetHealthMax) " (" BC_State.PercentText(snapshot.targetHealthCurrent, snapshot.targetHealthMax) ")")
        lines.Push("Resource: " BC_State.PairOrDefaultText(snapshot.targetResourceCurrent, snapshot.targetResourceMax) " (" BC_State.PercentText(snapshot.targetResourceCurrent, snapshot.targetResourceMax) ")")
        lines.Push("State: " BC_State.JoinTags(BC_State.BuildTargetStateTags(snapshot)))
        lines.Push("Compare: " BC_State.BuildComparisonText(snapshot))
        return BC_Debug.Join(lines, "`r`n")
    }

    static FormatHudCompareText(snapshot) {
        return "Compare: " BC_State.BuildComparisonText(snapshot)
    }

    static FormatPlayerHudStatus(snapshot) {
        return "State: " BC_State.JoinTags(BC_State.BuildPlayerStateTags(snapshot))
    }

    static FormatTargetHudStatus(snapshot) {
        if !BC_Overlay.HasTarget(snapshot) {
            return "State: none"
        }
        return "State: " BC_State.JoinTags(BC_State.BuildTargetStateTags(snapshot))
    }

    static FormatReaderFooter(snapshot) {
        return (
            "Seq "
            BC_Overlay.SafeText(snapshot.sequence, "-")
            " | "
            BC_Overlay.SafeText(snapshot.searchMode, "-")
            " | "
            BC_Overlay.SafeText(snapshot.captureSource, "-")
            " | capture "
            BC_Overlay.SafeText(snapshot.captureMs, "-")
            " ms | pipeline "
            BC_Overlay.SafeText(snapshot.pipelineMs, "-")
            " ms"
        )
    }

    static UpdateFromSnapshot(snapshot, title := "BarCode Reader Dashboard") {
        window := BC_Overlay.EnsureWindow(title)
        controls := BC_Overlay.Controls
        acceptedText := BC_Overlay.StatusVerdict(snapshot)
        freshnessText := (snapshot.accepted || BC_Overlay.IsHeldFrame(snapshot)) ? (" | " StrUpper(BC_Overlay.FreshnessLabel(snapshot))) : ""
        searchText := snapshot.searchMode = "" ? "" : (" | " StrUpper(snapshot.searchMode))
        statusColor := BC_Overlay.StatusColor(snapshot)
        sequenceText := snapshot.sequence = "" ? "" : (" | Seq " snapshot.sequence)
        confidenceText := snapshot.confidence = "" ? "" : (" | Confidence " snapshot.confidence)
        reasonText := snapshot.reason = "" ? "" : (" | " snapshot.reason)
        BC_Overlay.CurrentTitle := title
        BC_Overlay.LastSnapshot := snapshot

        controls.Header.Text := title
        try {
            controls.Status.SetFont("c" statusColor, "Consolas")
            controls.LiveMode.SetFont("c" BC_Overlay.Palette.Mode, "Consolas")
        } catch {
        }
        controls.Status.Text := "Status: " acceptedText freshnessText searchText reasonText sequenceText confidenceText
        controls.PlayerHealthLabel.Text := "Health: " BC_State.PairOrDefaultText(snapshot.playerHealthCurrent, snapshot.playerHealthMax) " (" BC_State.PercentText(snapshot.playerHealthCurrent, snapshot.playerHealthMax) ")"
        controls.PlayerHealthBar.Value := BC_Overlay.Percent(snapshot.playerHealthCurrent, snapshot.playerHealthMax)
        controls.PlayerResourceLabel.Text := "Resource: " BC_State.PairOrDefaultText(snapshot.playerResourceCurrent, snapshot.playerResourceMax) " (" BC_State.PercentText(snapshot.playerResourceCurrent, snapshot.playerResourceMax) ") " BC_Overlay.SafeText(snapshot.playerResourceKindName, "none")
        controls.PlayerResourceBar.Value := BC_Overlay.Percent(snapshot.playerResourceCurrent, snapshot.playerResourceMax)
        controls.PlayerMeta.Text := BC_Overlay.FormatPlayerMeta(snapshot)
        controls.PlayerOffense.Value := BC_Overlay.FormatPlayerOffense(snapshot)

        hasTarget := BC_Overlay.HasTarget(snapshot)
        controls.TargetHealthLabel.Text := hasTarget ? ("Health: " BC_State.PairOrDefaultText(snapshot.targetHealthCurrent, snapshot.targetHealthMax) " (" BC_State.PercentText(snapshot.targetHealthCurrent, snapshot.targetHealthMax) ")") : "Health: -"
        controls.TargetHealthBar.Value := hasTarget ? BC_Overlay.Percent(snapshot.targetHealthCurrent, snapshot.targetHealthMax) : 0
        controls.TargetResourceLabel.Text := hasTarget
            ? ("Resource: " BC_State.PairOrDefaultText(snapshot.targetResourceCurrent, snapshot.targetResourceMax) " (" BC_State.PercentText(snapshot.targetResourceCurrent, snapshot.targetResourceMax) ") " BC_Overlay.SafeText(snapshot.targetResourceKindName, "none"))
            : "Resource: -"
        controls.TargetResourceBar.Value := hasTarget ? BC_Overlay.Percent(snapshot.targetResourceCurrent, snapshot.targetResourceMax) : 0
        controls.TargetMeta.Text := BC_Overlay.FormatTargetMeta(snapshot)
        controls.TargetExtras.Value := BC_Overlay.FormatTargetExtras(snapshot)

        controls.TransportText.Text := BC_Overlay.FormatTransportText(snapshot)
        controls.CaptureText.Text := BC_Overlay.FormatCaptureText(snapshot)
        controls.SessionText.Text := BC_Overlay.FormatSessionText(snapshot)
        controls.DetailsBody.Value := BC_State.BuildOperatorSummaryText(snapshot) "`r`n`r`n" BC_State.BuildSnapshotText(snapshot)
        controls.HistoryBody.Value := BC_Overlay.RenderLiveUiHistory()
        controls.Footer.Text := "Summary: " BC_Config.LiveSummaryTextPath " | State: " BC_Config.LiveStateTextPath

        window.Show()
        return window
    }

    static UpdateHudFromSnapshot(snapshot, title := "BarCode Reader HUD") {
        window := BC_Overlay.EnsureHudWindow(title)
        controls := BC_Overlay.Controls
        acceptedText := BC_Overlay.StatusVerdict(snapshot)
        freshnessText := (snapshot.accepted || BC_Overlay.IsHeldFrame(snapshot)) ? (" | " StrUpper(BC_Overlay.FreshnessLabel(snapshot))) : ""
        searchText := snapshot.searchMode = "" ? "" : (" | " StrUpper(snapshot.searchMode))
        statusColor := BC_Overlay.StatusColor(snapshot)
        sequenceText := snapshot.sequence = "" ? "" : (" | Seq " snapshot.sequence)
        confidenceText := snapshot.confidence = "" ? "" : (" | Confidence " snapshot.confidence)
        reasonText := snapshot.reason = "" ? "" : (" | " snapshot.reason)
        BC_Overlay.CurrentTitle := title
        BC_Overlay.LastSnapshot := snapshot

        controls.Header.Text := title
        try {
            controls.Status.SetFont("c" statusColor, "Consolas")
            controls.LiveMode.SetFont("c" BC_Overlay.Palette.Mode, "Consolas")
        } catch {
        }

        controls.Status.Text := "Status: " acceptedText freshnessText searchText reasonText sequenceText confidenceText
        controls.CompareText.Text := BC_Overlay.FormatHudCompareText(snapshot)
        controls.PlayerHealthLabel.Text := "Health: " BC_State.PairOrDefaultText(snapshot.playerHealthCurrent, snapshot.playerHealthMax) " (" BC_State.PercentText(snapshot.playerHealthCurrent, snapshot.playerHealthMax) ")"
        controls.PlayerHealthBar.Value := BC_Overlay.Percent(snapshot.playerHealthCurrent, snapshot.playerHealthMax)
        controls.PlayerResourceLabel.Text := "Resource: " BC_State.PairOrDefaultText(snapshot.playerResourceCurrent, snapshot.playerResourceMax) " (" BC_State.PercentText(snapshot.playerResourceCurrent, snapshot.playerResourceMax) ") " BC_Overlay.SafeText(snapshot.playerResourceKindName, "none")
        controls.PlayerResourceBar.Value := BC_Overlay.Percent(snapshot.playerResourceCurrent, snapshot.playerResourceMax)
        controls.PlayerMeta.Text := BC_Overlay.FormatPlayerMeta(snapshot)
        controls.PlayerStatus.Text := BC_Overlay.FormatPlayerHudStatus(snapshot)
        controls.PlayerOffense.Value := BC_Overlay.FormatPlayerOffense(snapshot)

        hasTarget := BC_Overlay.HasTarget(snapshot)
        controls.TargetHealthLabel.Text := hasTarget ? ("Health: " BC_State.PairOrDefaultText(snapshot.targetHealthCurrent, snapshot.targetHealthMax) " (" BC_State.PercentText(snapshot.targetHealthCurrent, snapshot.targetHealthMax) ")") : "Health: -"
        controls.TargetHealthBar.Value := hasTarget ? BC_Overlay.Percent(snapshot.targetHealthCurrent, snapshot.targetHealthMax) : 0
        controls.TargetResourceLabel.Text := hasTarget
            ? ("Resource: " BC_State.PairOrDefaultText(snapshot.targetResourceCurrent, snapshot.targetResourceMax) " (" BC_State.PercentText(snapshot.targetResourceCurrent, snapshot.targetResourceMax) ") " BC_Overlay.SafeText(snapshot.targetResourceKindName, "none"))
            : "Resource: -"
        controls.TargetResourceBar.Value := hasTarget ? BC_Overlay.Percent(snapshot.targetResourceCurrent, snapshot.targetResourceMax) : 0
        controls.TargetMeta.Text := BC_Overlay.FormatTargetMeta(snapshot)
        controls.TargetStatus.Text := BC_Overlay.FormatTargetHudStatus(snapshot)
        controls.TargetExtras.Value := BC_Overlay.FormatTargetExtras(snapshot)

        controls.TransportText.Text := BC_Overlay.FormatTransportText(snapshot)
        controls.CaptureText.Text := BC_Overlay.FormatCaptureText(snapshot)
        controls.SessionText.Text := BC_Overlay.FormatSessionText(snapshot)
        controls.HistoryText.Value := BC_Overlay.RenderLiveUiHistory()
        controls.Footer.Text := BC_Overlay.FormatReaderFooter(snapshot)

        window.Show()
        return window
    }

    static RenderSnapshot(snapshot, title := "") {
        if (BC_Overlay.SurfaceMode = "hud") {
            return BC_Overlay.UpdateHudFromSnapshot(snapshot, title = "" ? "BarCode Reader HUD" : title)
        }
        return BC_Overlay.UpdateFromSnapshot(snapshot, title = "" ? "BarCode Reader Dashboard" : title)
    }

    static ShowCurrentState(title := "BarCode Reader Dashboard", autoCloseMs := 0) {
        BC_Overlay.StopLiveUiTimers()
        BC_Overlay.ResetLiveUiState()
        BC_Overlay.LiveUiLastSnapshot := ""
        BC_Overlay.LiveUiLastAcceptedSnapshot := ""
        snapshot := BC_State.BuildSnapshot()
        BC_State.WriteSnapshot()
        window := BC_Overlay.UpdateFromSnapshot(snapshot, title)

        if (autoCloseMs > 0) {
            SetTimer((*) => BC_Overlay.CloseWindow(), -autoCloseMs)
        }

        BC_Overlay.WaitUntilClosed()

        return {
            Success: snapshot.accepted,
            ReportPath: BC_Config.LiveStateTextPath,
            Summary: {
                Mode: "ui",
                Accepted: snapshot.accepted,
                Reason: snapshot.reason,
                Sequence: snapshot.sequence,
                SearchMode: snapshot.searchMode
            }
        }
    }

    static ShowCurrentHud(title := "BarCode Reader HUD", autoCloseMs := 0) {
        BC_Overlay.StopLiveUiTimers()
        BC_Overlay.ResetLiveUiState()
        BC_Overlay.SurfaceMode := "hud"
        BC_Overlay.LiveUiLastSnapshot := ""
        BC_Overlay.LiveUiLastAcceptedSnapshot := ""
        snapshot := BC_State.BuildSnapshot()
        BC_State.WriteSnapshot()
        window := BC_Overlay.UpdateHudFromSnapshot(snapshot, title)

        if (autoCloseMs > 0) {
            SetTimer((*) => BC_Overlay.CloseWindow(), -autoCloseMs)
        }

        BC_Overlay.WaitUntilClosed()

        return {
            Success: snapshot.accepted,
            ReportPath: BC_Config.LiveSummaryTextPath,
            Summary: {
                Mode: "hud",
                Accepted: snapshot.accepted,
                Reason: snapshot.reason,
                Sequence: snapshot.sequence,
                SearchMode: snapshot.searchMode
            }
        }
    }

    static WaitUntilClosed() {
        while IsObject(BC_Overlay.Window) {
            Sleep 50
        }
    }

    static BuildSyntheticProvider() {
        sequence := 0
        return (*) => BC_Tests.DecodeSyntheticHot(++sequence)
    }

    static BuildBmpProvider(path, cropX := 0, cropY := 0) {
        return (*) => BC_Tests.DecodeBmp(path, cropX, cropY)
    }

    static PollLiveProvider(liveState) {
        if IsObject(liveState) {
            hwnd := liveState.HasOwnProp("Hwnd") ? liveState.Hwnd : 0
            if (hwnd && WinExist("ahk_id " hwnd) && BC_Capture.IsWindowUsable(hwnd)) {
                result := BC_Tests.DecodeLiveFrame(hwnd, 0, 0, liveState.HasOwnProp("SourcePreference") ? liveState.SourcePreference : "auto")
                liveState.SourcePreference := result.HasOwnProp("PreferredSource") ? result.PreferredSource : "auto"
                return result
            }

            liveState.Hwnd := BC_Capture.FindRiftWindow()
            if liveState.Hwnd {
                liveState.SourcePreference := "auto"
                result := BC_Tests.DecodeLiveFrame(liveState.Hwnd, 0, 0, liveState.SourcePreference)
                liveState.SourcePreference := result.HasOwnProp("PreferredSource") ? result.PreferredSource : "auto"
                return result
            }
        }

        return BC_Tests.BuildUnavailableResult(
            "No likely RIFT window was found for liveui live source.",
            "live-window-missing",
            "window-missing"
        )
    }

    static BuildLiveProvider() {
        liveState := { Hwnd: BC_Capture.FindRiftWindow(), SourcePreference: "auto" }
        if !liveState.Hwnd {
            BC_Tests.BuildUnavailableResult(
                "No likely RIFT window was found for liveui live source.",
                "live-window-missing",
                "window-missing"
            )
        }
        return (*) => BC_Overlay.PollLiveProvider(liveState)
    }

    static CommitLiveUiResult(result) {
        if !IsObject(result) || !result.HasOwnProp("Validation") {
            throw Error("Live UI provider returned an invalid result.")
        }

        context := {
            Image: result.HasOwnProp("Image") ? result.Image : {},
            Timings: result.HasOwnProp("Timings") ? result.Timings : {},
            SampleIndex: BC_Overlay.LiveUiTickCount,
            CaptureAttempts: result.HasOwnProp("CaptureAttempts") ? result.CaptureAttempts : []
        }

        if result.HasOwnProp("WindowTitle") {
            context.WindowTitle := result.WindowTitle
        }
        if result.HasOwnProp("ProcessName") {
            context.ProcessName := result.ProcessName
        }

        BC_State.Update(result.Validation, context, true)
    }

    static LiveUiTick() {
        if !IsObject(BC_Overlay.Window) {
            BC_Overlay.StopLiveUiTimers()
            return
        }

        try {
            if !BC_Overlay.HasLiveUiProvider() {
                throw Error("Live UI provider is not configured.")
            }

            BC_Overlay.LiveUiTickCount += 1
            result := BC_Overlay.LiveUiProvider.Call()
            BC_Overlay.CommitLiveUiResult(result)
            snapshot := BC_State.BuildSnapshot()
            if (snapshot.accepted) {
                BC_Overlay.LiveUiLastAcceptedSnapshot := BC_Overlay.CloneSnapshot(snapshot)
            }
            displaySnapshot := snapshot.accepted ? snapshot : BC_Overlay.BuildHeldDisplaySnapshot(snapshot)
            BC_Overlay.LiveUiLastSnapshot := displaySnapshot
            BC_Overlay.PushLiveUiHistory(snapshot)
            BC_Overlay.RenderSnapshot(displaySnapshot, BC_Overlay.CurrentTitle)
            BC_Overlay.Controls.LiveMode.Text := "Mode: " BC_Overlay.LiveUiMode " | Source: " BC_Overlay.LiveUiSourceLabel " | Tick " BC_Overlay.LiveUiTickCount " | Interval " BC_Overlay.LiveUiIntervalMs "ms | " StrUpper(BC_Overlay.FreshnessLabel(displaySnapshot))
        } catch as err {
            BC_Overlay.SetFooter("Live UI error: " err.Message)
            BC_Debug.WriteText(BC_Config.LatestRunPath, "BarCode liveui error`r`n" err.Message "`r`n" err.Stack)
            BC_Overlay.CloseWindow()
        }
    }

    static WaitUntilLiveUiComplete() {
        nextTickAt := A_TickCount + BC_Overlay.LiveUiIntervalMs

        while IsObject(BC_Overlay.Window) {
            now := A_TickCount

            if (BC_Overlay.LiveUiAutoCloseMs > 0 && (now - BC_Overlay.LiveUiStartTick) >= BC_Overlay.LiveUiAutoCloseMs) {
                BC_Overlay.CloseWindow()
                continue
            }

            if BC_Overlay.HasLiveUiProvider() && now >= nextTickAt {
                BC_Overlay.LiveUiTick()
                nextTickAt := A_TickCount + BC_Overlay.LiveUiIntervalMs
                continue
            }

            Sleep 25
        }
    }

    static StartLiveUi(source := "synthetic", path := "", cropX := 0, cropY := 0, intervalMs := 250, autoCloseMs := 0, title := "") {
        return BC_Overlay.StartLiveSurface("dashboard", source, path, cropX, cropY, intervalMs, autoCloseMs, title)
    }

    static StartLiveSurface(surfaceMode := "dashboard", source := "synthetic", path := "", cropX := 0, cropY := 0, intervalMs := 250, autoCloseMs := 0, title := "") {
        BC_Overlay.StopLiveUiTimers()
        BC_Overlay.ResetLiveUiState()
        BC_State.ResetLiveOutputs()
        BC_Overlay.SurfaceMode := surfaceMode
        BC_Overlay.LiveUiMode := StrLower(source)
        BC_Overlay.LiveUiSourceLabel := BC_Overlay.LiveUiMode
        BC_Overlay.LiveUiIntervalMs := Max(25, Integer(intervalMs))
        BC_Overlay.LiveUiAutoCloseMs := Max(0, Integer(autoCloseMs))
        BC_Overlay.LiveUiTickCount := 0
        BC_Overlay.LiveUiStartTick := A_TickCount
        BC_Overlay.LiveUiLastSnapshot := ""
        BC_Overlay.LiveUiLastAcceptedSnapshot := ""
        BC_Overlay.ResetLiveUiHistory()

        if (BC_Overlay.LiveUiMode = "synthetic") {
            BC_Overlay.LiveUiProvider := BC_Overlay.BuildSyntheticProvider()
            BC_Overlay.LiveUiSourceLabel := "synthetic"
        } else if (BC_Overlay.LiveUiMode = "bmp") {
            if (path = "") {
                throw Error("liveui bmp mode requires an image path.")
            }
            BC_Overlay.LiveUiProvider := BC_Overlay.BuildBmpProvider(path, cropX, cropY)
            BC_Overlay.LiveUiSourceLabel := "bmp:" path
        } else if (BC_Overlay.LiveUiMode = "live") {
            BC_Overlay.LiveUiProvider := BC_Overlay.BuildLiveProvider()
            BC_Overlay.LiveUiSourceLabel := "live"
        } else {
            throw Error("Unsupported liveui source: " source)
        }

        windowTitle := title != ""
            ? title
            : (surfaceMode = "hud"
                ? ("BarCode Reader HUD | LiveHUD | " BC_Overlay.LiveUiSourceLabel)
                : ("BarCode Reader Dashboard | LiveUI | " BC_Overlay.LiveUiSourceLabel))
        if (surfaceMode = "hud") {
            BC_Overlay.EnsureHudWindow(windowTitle)
        } else {
            BC_Overlay.EnsureWindow(windowTitle)
        }
        BC_Overlay.Controls.LiveMode.Text := "Mode: " BC_Overlay.LiveUiMode " | Source: " BC_Overlay.LiveUiSourceLabel " | Tick 0 | Interval " BC_Overlay.LiveUiIntervalMs "ms"

        BC_Overlay.LiveUiTick()
        BC_Overlay.WaitUntilLiveUiComplete()

        return {
            Success: IsObject(BC_Overlay.LiveUiLastSnapshot) ? BC_Overlay.LiveUiLastSnapshot.accepted : false,
            ReportPath: surfaceMode = "hud" ? BC_Config.LiveSummaryTextPath : BC_Config.LiveStateTextPath,
            Summary: {
                Mode: surfaceMode = "hud" ? "livehud" : "liveui",
                Accepted: IsObject(BC_Overlay.LiveUiLastSnapshot) ? BC_Overlay.LiveUiLastSnapshot.accepted : false,
                Reason: IsObject(BC_Overlay.LiveUiLastSnapshot) ? BC_Overlay.LiveUiLastSnapshot.reason : "",
                Sequence: IsObject(BC_Overlay.LiveUiLastSnapshot) ? BC_Overlay.LiveUiLastSnapshot.sequence : "",
                SearchMode: IsObject(BC_Overlay.LiveUiLastSnapshot) ? BC_Overlay.LiveUiLastSnapshot.searchMode : ""
            }
        }
    }

    static RunSyntheticDashboard(autoCloseMs := 0) {
        BC_Tests.DecodeSyntheticHot()
        return BC_Overlay.ShowCurrentState("BarCode Reader Dashboard | Synthetic", autoCloseMs)
    }

    static RunBmpDashboard(path, cropX := 0, cropY := 0, autoCloseMs := 0) {
        BC_Tests.DecodeBmp(path, cropX, cropY)
        return BC_Overlay.ShowCurrentState("BarCode Reader Dashboard | BMP", autoCloseMs)
    }

    static RunSyntheticHud(autoCloseMs := 0) {
        BC_Tests.DecodeSyntheticHot()
        return BC_Overlay.ShowCurrentHud("BarCode Reader HUD | Synthetic", autoCloseMs)
    }

    static RunBmpHud(path, cropX := 0, cropY := 0, autoCloseMs := 0) {
        BC_Tests.DecodeBmp(path, cropX, cropY)
        return BC_Overlay.ShowCurrentHud("BarCode Reader HUD | BMP", autoCloseMs)
    }

    static RunLiveUiSynthetic(intervalMs := 250, autoCloseMs := 0, title := "") {
        return BC_Overlay.StartLiveUi("synthetic", "", 0, 0, intervalMs, autoCloseMs, title)
    }

    static RunLiveUiBmp(path, cropX := 0, cropY := 0, intervalMs := 250, autoCloseMs := 0, title := "") {
        return BC_Overlay.StartLiveUi("bmp", path, cropX, cropY, intervalMs, autoCloseMs, title)
    }

    static RunLiveUiLive(intervalMs := 250, autoCloseMs := 0, title := "") {
        return BC_Overlay.StartLiveUi("live", "", 0, 0, intervalMs, autoCloseMs, title)
    }

    static RunLiveHudSynthetic(intervalMs := 250, autoCloseMs := 0, title := "") {
        return BC_Overlay.StartLiveSurface("hud", "synthetic", "", 0, 0, intervalMs, autoCloseMs, title)
    }

    static RunLiveHudBmp(path, cropX := 0, cropY := 0, intervalMs := 250, autoCloseMs := 0, title := "") {
        return BC_Overlay.StartLiveSurface("hud", "bmp", path, cropX, cropY, intervalMs, autoCloseMs, title)
    }

    static RunLiveHudLive(intervalMs := 250, autoCloseMs := 0, title := "") {
        return BC_Overlay.StartLiveSurface("hud", "live", "", 0, 0, intervalMs, autoCloseMs, title)
    }
}

; end-of-script marker comment
