/*
script name: DesktopAHK/Overlay.ahk
version: 0.4.1
purpose: Provides ops, tactical, and compact HUD reader surfaces for synthetic, BMP, and live BarCode decode views.
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
    static WindowNoActivate := false
    static ActiveWindowNoActivate := false
    static LastSnapshot := ""
    static LiveUiMode := "synthetic"
    static LiveUiSourceLabel := "synthetic"
    static LiveUiProvider := ""
    static LiveUiRefreshCallback := ""
    static LiveUiAutoCloseCallback := ""
    static LiveUiIntervalMs := 125
    static LiveUiRenderIntervalMs := 250
    static LiveUiAutoCloseMs := 0
    static LiveUiTickCount := 0
    static LiveUiStartTick := 0
    static LiveUiLastSnapshot := ""
    static LiveUiLastAcceptedSnapshot := ""
    static LiveUiLastRenderedSnapshot := ""
    static LiveUiLastRenderTick := 0
    static LiveUiHistory := []
    static LiveUiHistoryLimit := 8
    static WindowShown := false
    static ControlTextCache := {}
    static ControlValueCache := {}
    static ControlFontCache := {}
    static WindowShowOptions := ""

    static DiscardWindow() {
        if IsObject(BC_Overlay.Window) {
            try {
                BC_Overlay.Window.Destroy()
            } catch {
            }
        }

        BC_Overlay.Window := ""
        BC_Overlay.Controls := {}
        BC_Overlay.ActiveWindowNoActivate := false
        BC_Overlay.ResetRenderCaches()
    }

    static ResetRenderCaches() {
        BC_Overlay.WindowShown := false
        BC_Overlay.ControlTextCache := {}
        BC_Overlay.ControlValueCache := {}
        BC_Overlay.ControlFontCache := {}
        BC_Overlay.WindowShowOptions := ""
    }

    static EnsureWindow(title := "BarCode Reader Dashboard") {
        if IsObject(BC_Overlay.Window) {
            if ((BC_Overlay.SurfaceMode = "dashboard" || BC_Overlay.SurfaceMode = "tactical") && BC_Overlay.ActiveWindowNoActivate = BC_Overlay.WindowNoActivate) {
                try {
                    BC_Overlay.Window.Title := title
                    BC_Overlay.WindowShowOptions := "w1152 h864"
                    return BC_Overlay.Window
                } catch {
                }
            }

            BC_Overlay.DiscardWindow()
        }

        options := BC_Overlay.WindowNoActivate
            ? "+AlwaysOnTop +ToolWindow +MinSize1152x864 +E0x08000000"
            : "+AlwaysOnTop +ToolWindow +MinSize1152x864"
        window := Gui(options, title)
        window.BackColor := BC_Overlay.Palette.WindowBack
        window.MarginX := 12
        window.MarginY := 12
        window.SetFont("s11 c" BC_Overlay.Palette.BodyText, "Segoe UI")

        contentX := 12
        contentWidth := 1120
        buttonY := 64
        buttonGap := 8
        refreshWidth := 78
        copyPathWidth := 96
        copySummaryWidth := 104
        copyHistoryWidth := 90
        closeWidth := 70
        totalButtonWidth := refreshWidth + copyPathWidth + copySummaryWidth + copyHistoryWidth + closeWidth + (buttonGap * 4)
        refreshX := contentX + contentWidth - totalButtonWidth
        copyPathX := refreshX + refreshWidth + buttonGap
        copySummaryX := copyPathX + copyPathWidth + buttonGap
        copyHistoryX := copySummaryX + copySummaryWidth + buttonGap
        closeX := copyHistoryX + copyHistoryWidth + buttonGap
        compareY := 96
        topGroupY := 126
        groupGap := 18
        topGroupWidth := Floor((contentWidth - groupGap) / 2)
        playerGroupX := contentX
        targetGroupX := playerGroupX + topGroupWidth + groupGap
        topGroupHeight := 272
        innerXOffset := 14
        innerWidth := topGroupWidth - 30
        readerY := topGroupY + topGroupHeight + 16
        readerHeight := 214
        readerInnerWidth := contentWidth - 30
        readerHalfWidth := Floor((readerInnerWidth - 18) / 2)
        bottomY := readerY + readerHeight + 16
        bottomGroupWidth := topGroupWidth
        detailsX := contentX
        historyX := detailsX + bottomGroupWidth + groupGap
        bottomHeight := 188
        footerY := bottomY + bottomHeight + 12

        window.SetFont("s14 Bold c" BC_Overlay.Palette.Header, "Consolas")
        header := window.AddText(Format("x{} y12 w{}", contentX, contentWidth), "BarCode Reader Dashboard")
        window.SetFont("s10 c" BC_Overlay.Palette.StatusOk, "Consolas")
        status := window.AddText(Format("x{} y44 w{}", contentX, contentWidth), "Status: waiting")
        window.SetFont("s10 c" BC_Overlay.Palette.Mode, "Consolas")
        liveMode := window.AddText(Format("x{} y68 w220", contentX), "Mode: idle")
        window.SetFont("s10 Bold c" BC_Overlay.Palette.Header, "Consolas")
        compareText := window.AddText(Format("x{} y{} w{}", contentX, compareY, contentWidth), "Compare: waiting")

        window.SetFont("s9 c" BC_Overlay.Palette.BodyText, "Segoe UI")
        refreshButton := window.AddButton(Format("x{} y{} w{}", refreshX, buttonY, refreshWidth), "Refresh")
        copyPathButton := window.AddButton(Format("x{} y{} w{}", copyPathX, buttonY, copyPathWidth), "State Path")
        copySummaryButton := window.AddButton(Format("x{} y{} w{}", copySummaryX, buttonY, copySummaryWidth), "Copy Summary")
        copyHistoryButton := window.AddButton(Format("x{} y{} w{}", copyHistoryX, buttonY, copyHistoryWidth), "Copy History")
        closeButton := window.AddButton(Format("x{} y{} w{}", closeX, buttonY, closeWidth), "Close")

        window.SetFont("s10 Bold c" BC_Overlay.Palette.SectionPlayer, "Consolas")
        playerGroup := window.AddGroupBox(Format("x{} y{} w{} h{}", playerGroupX, topGroupY, topGroupWidth, topGroupHeight), "Player")
        window.SetFont("s10 c" BC_Overlay.Palette.BodyText, "Consolas")
        playerHealthLabel := window.AddText(Format("x{} y{} w{}", playerGroupX + innerXOffset, topGroupY + 24, innerWidth), "Health: ")
        playerHealthBar := window.AddProgress(Format("x{} y{} w{} h16 c4CAF50 Background202020", playerGroupX + innerXOffset, topGroupY + 46, innerWidth), 0)
        playerResourceLabel := window.AddText(Format("x{} y{} w{}", playerGroupX + innerXOffset, topGroupY + 74, innerWidth), "Resource: ")
        playerResourceBar := window.AddProgress(Format("x{} y{} w{} h16 c2AA1D3 Background202020", playerGroupX + innerXOffset, topGroupY + 96, innerWidth), 0)
        window.SetFont("s10 c" BC_Overlay.Palette.MutedText, "Consolas")
        playerMeta := window.AddText(Format("x{} y{} w{}", playerGroupX + innerXOffset, topGroupY + 124, innerWidth), "Level / Calling / Role")
        window.SetFont("s9 c" BC_Overlay.Palette.StatusOk, "Consolas")
        playerStatus := window.AddText(Format("x{} y{} w{}", playerGroupX + innerXOffset, topGroupY + 148, innerWidth), "State: -")
        window.SetFont("s9 c" BC_Overlay.Palette.StatusOk, "Consolas")
        playerOffense := window.AddEdit(Format("x{} y{} w{} r6 ReadOnly WantCtrlA Background{}", playerGroupX + innerXOffset, topGroupY + 172, innerWidth, BC_Overlay.Palette.PanelBack), "")

        window.SetFont("s10 Bold c" BC_Overlay.Palette.SectionTarget, "Consolas")
        targetGroup := window.AddGroupBox(Format("x{} y{} w{} h{}", targetGroupX, topGroupY, topGroupWidth, topGroupHeight), "Target")
        window.SetFont("s10 c" BC_Overlay.Palette.BodyText, "Consolas")
        targetHealthLabel := window.AddText(Format("x{} y{} w{}", targetGroupX + innerXOffset, topGroupY + 24, innerWidth), "Health: ")
        targetHealthBar := window.AddProgress(Format("x{} y{} w{} h16 cE57373 Background202020", targetGroupX + innerXOffset, topGroupY + 46, innerWidth), 0)
        targetResourceLabel := window.AddText(Format("x{} y{} w{}", targetGroupX + innerXOffset, topGroupY + 74, innerWidth), "Resource: ")
        targetResourceBar := window.AddProgress(Format("x{} y{} w{} h16 cFFB74D Background202020", targetGroupX + innerXOffset, topGroupY + 96, innerWidth), 0)
        window.SetFont("s10 c" BC_Overlay.Palette.MutedText, "Consolas")
        targetMeta := window.AddText(Format("x{} y{} w{}", targetGroupX + innerXOffset, topGroupY + 124, innerWidth), "Level / Flags")
        window.SetFont("s9 c" BC_Overlay.Palette.SectionTarget, "Consolas")
        targetStatus := window.AddText(Format("x{} y{} w{}", targetGroupX + innerXOffset, topGroupY + 148, innerWidth), "State: -")
        window.SetFont("s9 c" BC_Overlay.Palette.SectionTarget, "Consolas")
        targetExtras := window.AddEdit(Format("x{} y{} w{} r6 ReadOnly WantCtrlA Background{}", targetGroupX + innerXOffset, topGroupY + 172, innerWidth, BC_Overlay.Palette.PanelBack), "")

        window.SetFont("s10 Bold c" BC_Overlay.Palette.SectionReader, "Consolas")
        readerGroup := window.AddGroupBox(Format("x{} y{} w{} h{}", contentX, readerY, contentWidth, readerHeight), "Reader")
        window.SetFont("s10 c" BC_Overlay.Palette.Header, "Consolas")
        transportText := window.AddText(Format("x{} y{} w{} h98", contentX + innerXOffset, readerY + 24, readerHalfWidth), "")
        window.SetFont("s10 c" BC_Overlay.Palette.CaptureText, "Consolas")
        captureText := window.AddText(Format("x{} y{} w{} h98", contentX + innerXOffset + readerHalfWidth + 18, readerY + 24, readerHalfWidth), "")
        window.SetFont("s10 c" BC_Overlay.Palette.Mode, "Consolas")
        sessionText := window.AddText(Format("x{} y{} w{} h68", contentX + innerXOffset, readerY + 130, readerInnerWidth), "")

        window.SetFont("s10 Bold c" BC_Overlay.Palette.Header, "Consolas")
        detailsY := bottomY
        historyY := bottomY
        detailsGroup := window.AddGroupBox(Format("x{} y{} w{} h{}", detailsX, detailsY, bottomGroupWidth, bottomHeight), "Snapshot Details")
        window.SetFont("s9 c" BC_Overlay.Palette.DetailText, "Consolas")
        detailsBodyHeight := bottomHeight - 48
        detailsBody := window.AddEdit(Format("x{} y{} w{} h{} ReadOnly WantCtrlA Background{}", detailsX + innerXOffset, detailsY + 24, innerWidth, detailsBodyHeight, BC_Overlay.Palette.PanelBack), "")

        window.SetFont("s10 Bold c" BC_Overlay.Palette.Header, "Consolas")
        historyGroup := window.AddGroupBox(Format("x{} y{} w{} h{}", historyX, historyY, bottomGroupWidth, bottomHeight), "Recent Frames")
        window.SetFont("s9 c" BC_Overlay.Palette.HistoryText, "Consolas")
        historyBodyHeight := bottomHeight - 48
        historyBody := window.AddEdit(Format("x{} y{} w{} h{} ReadOnly WantCtrlA Background{}", historyX + innerXOffset, historyY + 24, innerWidth, historyBodyHeight, BC_Overlay.Palette.PanelBack), "")

        window.SetFont("s9 c" BC_Overlay.Palette.Footer, "Consolas")
        footer := window.AddText(Format("x{} y{} w{}", contentX, footerY, contentWidth), "Close the window to exit this reader preview.")

        window.OnEvent("Close", BC_Overlay.OnWindowClosed)
        window.OnEvent("Escape", BC_Overlay.OnWindowClosed)
        refreshButton.OnEvent("Click", BC_Overlay.OnRefreshClicked)
        copyPathButton.OnEvent("Click", BC_Overlay.OnCopyStatePathClicked)
        copySummaryButton.OnEvent("Click", BC_Overlay.OnCopySummaryClicked)
        copyHistoryButton.OnEvent("Click", BC_Overlay.OnCopyHistoryClicked)
        closeButton.OnEvent("Click", BC_Overlay.OnCloseClicked)

        BC_Overlay.Window := window
        BC_Overlay.ActiveWindowNoActivate := BC_Overlay.WindowNoActivate
        BC_Overlay.Controls := {
            Header: header,
            Status: status,
            LiveMode: liveMode,
            RefreshButton: refreshButton,
            CopyPathButton: copyPathButton,
            CopySummaryButton: copySummaryButton,
            CopyHistoryButton: copyHistoryButton,
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
            DetailsBody: detailsBody,
            HistoryBody: historyBody,
            Footer: footer
        }
        BC_Overlay.ResetRenderCaches()

        return window
    }

    static EnsureHudWindow(title := "BarCode Reader HUD") {
        if IsObject(BC_Overlay.Window) {
            if (BC_Overlay.SurfaceMode = "hud" && BC_Overlay.ActiveWindowNoActivate = BC_Overlay.WindowNoActivate) {
                try {
                    BC_Overlay.Window.Title := title
                    BC_Overlay.WindowShowOptions := ""
                    return BC_Overlay.Window
                } catch {
                }
            }

            BC_Overlay.DiscardWindow()
        }

        BC_Overlay.SurfaceMode := "hud"
        BC_Overlay.WindowShowOptions := ""
        options := BC_Overlay.WindowNoActivate
            ? "+AlwaysOnTop +ToolWindow +MinSize760x800 +E0x08000000"
            : "+AlwaysOnTop +ToolWindow +MinSize760x800"
        window := Gui(options, title)
        window.BackColor := BC_Overlay.Palette.WindowBack
        window.MarginX := 12
        window.MarginY := 12
        window.SetFont("s11 c" BC_Overlay.Palette.BodyText, "Segoe UI")

        contentX := 12
        contentWidth := 720
        buttonY := 78
        buttonGap := 10
        refreshX := 492
        copyPathX := refreshX + 78 + buttonGap
        copySummaryX := copyPathX + 98 + buttonGap
        copyHistoryX := copySummaryX + 110 + buttonGap
        closeX := copyHistoryX + 104 + buttonGap
        compareY := 116
        topGroupY := 150
        topGroupHeight := 270
        groupGap := 16
        groupWidth := Floor((contentWidth - groupGap) / 2)
        playerGroupX := contentX
        targetGroupX := playerGroupX + groupWidth + groupGap
        groupInnerXOffset := 14
        groupInnerWidth := groupWidth - 38
        readerY := topGroupY + topGroupHeight + 18
        readerHeight := 212
        footerY := readerY + readerHeight + 16

        window.SetFont("s14 Bold c" BC_Overlay.Palette.Header, "Consolas")
        header := window.AddText(Format("x{} y12 w{}", contentX, contentWidth), "BarCode Reader HUD")
        window.SetFont("s10 c" BC_Overlay.Palette.StatusOk, "Consolas")
        status := window.AddText(Format("x{} y44 w{}", contentX, contentWidth), "Status: waiting")
        window.SetFont("s10 c" BC_Overlay.Palette.Mode, "Consolas")
        liveMode := window.AddText(Format("x{} y70 w220", contentX), "Mode: idle")

        window.SetFont("s9 c" BC_Overlay.Palette.BodyText, "Segoe UI")
        refreshButton := window.AddButton(Format("x{} y{} w78", refreshX, buttonY), "Refresh")
        copyPathButton := window.AddButton(Format("x{} y{} w98", copyPathX, buttonY), "State Path")
        copySummaryButton := window.AddButton(Format("x{} y{} w110", copySummaryX, buttonY), "Copy Summary")
        copyHistoryButton := window.AddButton(Format("x{} y{} w104", copyHistoryX, buttonY), "Copy History")
        closeButton := window.AddButton(Format("x{} y{} w70", closeX, buttonY), "Close")

        window.SetFont("s10 Bold c" BC_Overlay.Palette.Header, "Consolas")
        compareText := window.AddText(Format("x{} y{} w{}", contentX, compareY, contentWidth), "Compare: waiting")

        window.SetFont("s10 Bold c" BC_Overlay.Palette.SectionPlayer, "Consolas")
        playerGroup := window.AddGroupBox(Format("x{} y{} w{} h{}", playerGroupX, topGroupY, groupWidth, topGroupHeight), "Player")
        window.SetFont("s10 c" BC_Overlay.Palette.BodyText, "Consolas")
        playerHealthLabel := window.AddText(Format("x{} y{} w{}", playerGroupX + groupInnerXOffset, topGroupY + 24, groupInnerWidth), "Health: -")
        playerHealthBar := window.AddProgress(Format("x{} y{} w{} h18 c4CAF50 Background202020", playerGroupX + groupInnerXOffset, topGroupY + 48, groupInnerWidth), 0)
        playerResourceLabel := window.AddText(Format("x{} y{} w{}", playerGroupX + groupInnerXOffset, topGroupY + 84, groupInnerWidth), "Resource: -")
        playerResourceBar := window.AddProgress(Format("x{} y{} w{} h18 c2AA1D3 Background202020", playerGroupX + groupInnerXOffset, topGroupY + 108, groupInnerWidth), 0)
        window.SetFont("s10 c" BC_Overlay.Palette.MutedText, "Consolas")
        playerMeta := window.AddText(Format("x{} y{} w{}", playerGroupX + groupInnerXOffset, topGroupY + 144, groupInnerWidth), "Level / Calling / Role")
        window.SetFont("s9 c" BC_Overlay.Palette.StatusOk, "Consolas")
        playerStatus := window.AddText(Format("x{} y{} w{}", playerGroupX + groupInnerXOffset, topGroupY + 170, groupInnerWidth), "State: -")
        window.SetFont("s9 c" BC_Overlay.Palette.BodyText, "Consolas")
        playerOffense := window.AddEdit(Format("x{} y{} w{} r4 ReadOnly WantCtrlA Background{}", playerGroupX + groupInnerXOffset, topGroupY + 194, groupInnerWidth, BC_Overlay.Palette.PanelBack), "")

        window.SetFont("s10 Bold c" BC_Overlay.Palette.SectionTarget, "Consolas")
        targetGroup := window.AddGroupBox(Format("x{} y{} w{} h{}", targetGroupX, topGroupY, groupWidth, topGroupHeight), "Target")
        window.SetFont("s10 c" BC_Overlay.Palette.BodyText, "Consolas")
        targetHealthLabel := window.AddText(Format("x{} y{} w{}", targetGroupX + groupInnerXOffset, topGroupY + 24, groupInnerWidth), "Health: -")
        targetHealthBar := window.AddProgress(Format("x{} y{} w{} h18 cE57373 Background202020", targetGroupX + groupInnerXOffset, topGroupY + 48, groupInnerWidth), 0)
        targetResourceLabel := window.AddText(Format("x{} y{} w{}", targetGroupX + groupInnerXOffset, topGroupY + 84, groupInnerWidth), "Resource: -")
        targetResourceBar := window.AddProgress(Format("x{} y{} w{} h18 cFFB74D Background202020", targetGroupX + groupInnerXOffset, topGroupY + 108, groupInnerWidth), 0)
        window.SetFont("s10 c" BC_Overlay.Palette.MutedText, "Consolas")
        targetMeta := window.AddText(Format("x{} y{} w{}", targetGroupX + groupInnerXOffset, topGroupY + 144, groupInnerWidth), "Level / Flags")
        window.SetFont("s9 c" BC_Overlay.Palette.SectionTarget, "Consolas")
        targetStatus := window.AddText(Format("x{} y{} w{}", targetGroupX + groupInnerXOffset, topGroupY + 170, groupInnerWidth), "State: -")
        window.SetFont("s9 c" BC_Overlay.Palette.BodyText, "Consolas")
        targetExtras := window.AddEdit(Format("x{} y{} w{} r4 ReadOnly WantCtrlA Background{}", targetGroupX + groupInnerXOffset, topGroupY + 194, groupInnerWidth, BC_Overlay.Palette.PanelBack), "")

        window.SetFont("s10 Bold c" BC_Overlay.Palette.SectionReader, "Consolas")
        readerGroup := window.AddGroupBox(Format("x{} y{} w{} h{}", contentX, readerY, contentWidth, readerHeight), "Reader")
        window.SetFont("s10 c" BC_Overlay.Palette.Header, "Consolas")
        transportText := window.AddText(Format("x{} y{} w340 h72", contentX + 14, readerY + 24), "")
        window.SetFont("s10 c" BC_Overlay.Palette.CaptureText, "Consolas")
        captureText := window.AddText(Format("x{} y{} w340 h72", contentX + 366, readerY + 24), "")
        window.SetFont("s9 c" BC_Overlay.Palette.HistoryText, "Consolas")
        sessionText := window.AddText(Format("x{} y{} w694 h48", contentX + 14, readerY + 104), "")
        historyText := window.AddEdit(Format("x{} y{} w694 r3 ReadOnly WantCtrlA Background{}", contentX + 14, readerY + 154, BC_Overlay.Palette.PanelBack), "")
        window.SetFont("s9 c" BC_Overlay.Palette.Footer, "Consolas")
        footer := window.AddText(Format("x{} y{} w{}", contentX + 14, footerY, contentWidth - 14), "Close the window to exit this HUD preview.")

        window.OnEvent("Close", BC_Overlay.OnWindowClosed)
        window.OnEvent("Escape", BC_Overlay.OnWindowClosed)
        refreshButton.OnEvent("Click", BC_Overlay.OnRefreshClicked)
        copyPathButton.OnEvent("Click", BC_Overlay.OnCopyStatePathClicked)
        copySummaryButton.OnEvent("Click", BC_Overlay.OnCopySummaryClicked)
        copyHistoryButton.OnEvent("Click", BC_Overlay.OnCopyHistoryClicked)
        closeButton.OnEvent("Click", BC_Overlay.OnCloseClicked)

        BC_Overlay.Window := window
        BC_Overlay.ActiveWindowNoActivate := BC_Overlay.WindowNoActivate
        BC_Overlay.Controls := {
            Header: header,
            Status: status,
            LiveMode: liveMode,
            RefreshButton: refreshButton,
            CopyPathButton: copyPathButton,
            CopySummaryButton: copySummaryButton,
            CopyHistoryButton: copyHistoryButton,
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
        BC_Overlay.ResetRenderCaches()

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
        BC_Overlay.ResetRenderCaches()
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
        BC_Overlay.ResetRenderCaches()
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
        BC_Overlay.LiveUiIntervalMs := BC_Config.LiveSurfaceDefaultSampleMs
        BC_Overlay.LiveUiRenderIntervalMs := BC_Config.LiveSurfaceDefaultRenderMs
        BC_Overlay.LiveUiAutoCloseMs := 0
        BC_Overlay.LiveUiTickCount := 0
        BC_Overlay.LiveUiStartTick := 0
        BC_Overlay.LiveUiLastRenderTick := 0
        BC_Overlay.LiveUiLastRenderedSnapshot := ""
        BC_Overlay.WindowNoActivate := false
        BC_Overlay.SurfaceMode := "dashboard"
        BC_Overlay.ResetLiveUiHistory()
    }

    static SetControlText(controlName, text) {
        if !(IsObject(BC_Overlay.Controls) && BC_Overlay.Controls.HasOwnProp(controlName)) {
            return
        }

        normalized := text = "" ? "" : ("" text)
        if !BC_Overlay.ControlTextCache.HasOwnProp(controlName) || BC_Overlay.ControlTextCache.%controlName% != normalized {
            BC_Overlay.Controls.%controlName%.Text := normalized
            BC_Overlay.ControlTextCache.%controlName% := normalized
        }
    }

    static SetControlValue(controlName, value) {
        if !(IsObject(BC_Overlay.Controls) && BC_Overlay.Controls.HasOwnProp(controlName)) {
            return
        }

        normalized := value = "" ? "" : ("" value)
        if !BC_Overlay.ControlValueCache.HasOwnProp(controlName) || BC_Overlay.ControlValueCache.%controlName% != normalized {
            BC_Overlay.Controls.%controlName%.Value := normalized
            BC_Overlay.ControlValueCache.%controlName% := normalized
        }
    }

    static SetControlFontColor(controlName, color, fontName := "Consolas") {
        if !(IsObject(BC_Overlay.Controls) && BC_Overlay.Controls.HasOwnProp(controlName)) {
            return
        }

        spec := "c" color "|" fontName
        if !BC_Overlay.ControlFontCache.HasOwnProp(controlName) || BC_Overlay.ControlFontCache.%controlName% != spec {
            try {
                BC_Overlay.Controls.%controlName%.SetFont("c" color, fontName)
            } catch {
                return
            }
            BC_Overlay.ControlFontCache.%controlName% := spec
        }
    }

    static ShowWindow(window) {
        if BC_Overlay.WindowShown {
            return
        }

        options := BC_Overlay.WindowShowOptions
        if BC_Overlay.WindowNoActivate {
            showArgs := options = "" ? "NA" : "NA " options
            window.Show(showArgs)
        } else {
            window.Show(options)
        }
        BC_Overlay.WindowShown := true
    }

    static CloneSnapshot(snapshot) {
        copy := {}
        for key, value in snapshot.OwnProps() {
            copy.%key% := value
        }
        return copy
    }

    static ShouldRenderLiveSnapshot(snapshot) {
        now := A_TickCount

        if !BC_Overlay.WindowShown {
            return true
        }

        if !IsObject(BC_Overlay.LiveUiLastRenderedSnapshot) {
            return true
        }

        previous := BC_Overlay.LiveUiLastRenderedSnapshot
        if (snapshot.accepted != previous.accepted) {
            return true
        }
        if (BC_Overlay.IsHeldFrame(snapshot) != BC_Overlay.IsHeldFrame(previous)) {
            return true
        }
        if (BC_Overlay.SafeText(snapshot.reason, "-") != BC_Overlay.SafeText(previous.reason, "-")) {
            return true
        }
        if (BC_Overlay.SafeText(snapshot.searchMode, "-") != BC_Overlay.SafeText(previous.searchMode, "-")) {
            return true
        }
        if (BC_Overlay.SafeText(snapshot.captureSource, "-") != BC_Overlay.SafeText(previous.captureSource, "-")) {
            return true
        }
        if (BC_Overlay.SafeText(snapshot.captureRouteReason, "-") != BC_Overlay.SafeText(previous.captureRouteReason, "-")) {
            return true
        }

        return (now - BC_Overlay.LiveUiLastRenderTick) >= BC_Overlay.LiveUiRenderIntervalMs
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
            BC_Overlay.LiveUiLastRenderTick := 0
            BC_Overlay.LiveUiLastRenderedSnapshot := ""
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

    static OnCopyHistoryClicked(*) {
        A_Clipboard := BC_Overlay.RenderLiveUiHistory()
        BC_Overlay.SetFooter("Recent history copied to clipboard.")
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
        ageText := BC_State.AgeText(snapshot)
        return verdict " | " freshness " | " searchMode " | seq=" seq " | age=" ageText " | ms=" pipelineMs " | conf=" confidence " | " reason
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
            BC_Overlay.SetControlText("Footer", text)
            BC_Overlay.SetControlFontColor("Footer", BC_Overlay.Palette.Footer)
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

    static CompareColor(snapshot) {
        if !BC_Overlay.HasTarget(snapshot) {
            return BC_Overlay.Palette.MutedText
        }

        hpDelta := BC_State.PercentDeltaText(
            snapshot.playerHealthCurrent,
            snapshot.playerHealthMax,
            snapshot.targetHealthCurrent,
            snapshot.targetHealthMax
        )
        if (hpDelta = "") {
            return BC_Overlay.Palette.Header
        }

        return Integer(hpDelta) >= 0 ? BC_Overlay.Palette.StatusOk : BC_Overlay.Palette.StatusBad
    }

    static SessionColor(snapshot) {
        if BC_Overlay.IsHeldFrame(snapshot) {
            return BC_Overlay.Palette.StatusWarn
        }
        if !snapshot.accepted {
            return BC_Overlay.Palette.StatusBad
        }
        return snapshot.freshFrame ? BC_Overlay.Palette.HistoryText : BC_Overlay.Palette.StatusWarn
    }

    static CaptureColor(snapshot) {
        if BC_Overlay.IsHeldFrame(snapshot) {
            return BC_Overlay.Palette.StatusWarn
        }
        if !snapshot.accepted {
            return BC_Overlay.Palette.StatusBad
        }
        if (snapshot.attemptCount != "" && Integer(snapshot.attemptCount) > 1) {
            return BC_Overlay.Palette.StatusWarn
        }
        return BC_Overlay.Palette.CaptureText
    }

    static PlayerStatusColor(snapshot) {
        if !snapshot.accepted && !BC_Overlay.IsHeldFrame(snapshot) {
            return BC_Overlay.Palette.StatusBad
        }
        return BC_State.HasBit(snapshot.stateFlags, 0x0002)
            ? BC_Overlay.Palette.StatusOk
            : BC_Overlay.Palette.SectionPlayer
    }

    static TargetStatusColor(snapshot) {
        if !BC_Overlay.HasTarget(snapshot) {
            return BC_Overlay.Palette.MutedText
        }
        if !snapshot.accepted && !BC_Overlay.IsHeldFrame(snapshot) {
            return BC_Overlay.Palette.StatusBad
        }
        return BC_State.HasBit(snapshot.stateFlags, 0x0040)
            ? BC_Overlay.Palette.SectionTarget
            : BC_Overlay.Palette.StatusWarn
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
        lines.Push("Frame / Age: " BC_Overlay.FreshnessLabel(snapshot) " / " BC_State.AgeText(snapshot))
        lines.Push("Advance / Confidence: " BC_Overlay.SafeText(snapshot.sequenceAdvance, "-") " / " BC_Overlay.SafeText(snapshot.confidence, "-"))
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
        if !BC_Overlay.IsTacticalSurface() {
            return (
                "Session " BC_Overlay.SafeText(snapshot.sessionSampleCount, "0")
                " samples | accepted " BC_Overlay.SafeText(snapshot.sessionAcceptedCount, "0")
                " | rejected " BC_Overlay.SafeText(snapshot.sessionRejectedCount, "0")
                " | streak " BC_Overlay.SafeText(snapshot.acceptedStreak, "0")
                "/" BC_Overlay.SafeText(snapshot.rejectedStreak, "0")
                " | repeats " BC_Overlay.SafeText(snapshot.sequenceRepeatedCount, "0")
                " | wraps " BC_Overlay.SafeText(snapshot.sequenceWrapCount, "0")
                "`r`nPages last=" BC_Overlay.SafeText(snapshot.pageName, "-")
                " | ops " BC_Overlay.SafeText(snapshot.opsPageAgeMs, "-") " ms"
                " | tactical " BC_Overlay.SafeText(snapshot.tacticalPageAgeMs, "-") " ms"
                "`r`nTarget " (BC_State.HasTarget(snapshot) ? "present" : "none")
                " | relation " BC_Overlay.SafeText(snapshot.targetRelationName, "unknown")
                " | dist " BC_Overlay.SafeText(snapshot.distanceXZ, "-")
                " | bucket " BC_Overlay.SafeText(snapshot.distanceBucketText, "-")
            )
        }

        line := (
            "Session " BC_Overlay.SafeText(snapshot.sessionSampleCount, "0")
            " samples | accepted " BC_Overlay.SafeText(snapshot.sessionAcceptedCount, "0")
            " | rejected " BC_Overlay.SafeText(snapshot.sessionRejectedCount, "0")
            " | streak " BC_Overlay.SafeText(snapshot.acceptedStreak, "0")
            "/" BC_Overlay.SafeText(snapshot.rejectedStreak, "0")
            " | repeats " BC_Overlay.SafeText(snapshot.sequenceRepeatedCount, "0")
            " | wraps " BC_Overlay.SafeText(snapshot.sequenceWrapCount, "0")
            " | age " BC_State.AgeText(snapshot)
        )
        if BC_State.HasTarget(snapshot) {
            line .= "`r`nCompare " BC_State.BuildComparisonText(snapshot)
            line .= "`r`nEdge " BC_State.BuildComparisonDeltaText(snapshot)
        } else {
            line .= "`r`nCompare player-only"
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

    static FormatOpsCompareText(snapshot) {
        return (
            "Ops: page " BC_Overlay.SafeText(snapshot.pageName, "-")
            " | ops age " BC_Overlay.SafeText(snapshot.opsPageAgeMs, "-") " ms"
            " | tactical age " BC_Overlay.SafeText(snapshot.tacticalPageAgeMs, "-") " ms"
            " | target " (BC_State.HasTarget(snapshot) ? "present" : "none")
            " | reader " BC_Overlay.SafeText(snapshot.searchMode, "-")
        )
    }

    static FormatOpsPlayerDetails(snapshot) {
        lines := []
        lines.Push("Health: " BC_State.PairOrDefaultText(snapshot.playerHealthCurrent, snapshot.playerHealthMax) " (" BC_State.PercentText(snapshot.playerHealthCurrent, snapshot.playerHealthMax) ")")
        lines.Push("Resource: " BC_State.PairOrDefaultText(snapshot.playerResourceCurrent, snapshot.playerResourceMax) " (" BC_State.PercentText(snapshot.playerResourceCurrent, snapshot.playerResourceMax) ") " BC_Overlay.SafeText(snapshot.playerResourceKindName, "none"))
        lines.Push("Sample/state: 0x" Format("{:04X}", Integer(snapshot.sampleMask || 0)) " / 0x" Format("{:04X}", Integer(snapshot.stateFlags || 0)))
        lines.Push("Pages: ops " BC_Overlay.SafeText(snapshot.opsPageAgeMs, "-") " ms | tactical " BC_Overlay.SafeText(snapshot.tacticalPageAgeMs, "-") " ms")
        return BC_Debug.Join(lines, "`r`n")
    }

    static FormatPlayerOffense(snapshot) {
        if !BC_Overlay.IsTacticalSurface() {
            return BC_Overlay.FormatOpsPlayerDetails(snapshot)
        }

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
        lines.Push("Cast: " BC_Overlay.SafeText(snapshot.playerCastProgressQ15, "0") " q15   Zone: " BC_State.HexText(snapshot.playerZoneHash16, 4))
        lines.Push("Coord: " BC_Overlay.SafeText(snapshot.playerCoordX, "-") ", " BC_Overlay.SafeText(snapshot.playerCoordY, "-") ", " BC_Overlay.SafeText(snapshot.playerCoordZ, "-"))
        return BC_Debug.Join(lines, "`r`n")
    }

    static HasTarget(snapshot) {
        return BC_State.HasTarget(snapshot)
    }

    static FormatTargetMeta(snapshot) {
        if !BC_Overlay.HasTarget(snapshot) {
            return "No target selected"
        }

        if !BC_Overlay.IsTacticalSurface() {
            return (
                "Level " BC_Overlay.SafeText(snapshot.targetLevel, "-")
                " | " BC_Overlay.SafeText(snapshot.targetRelationName, "unknown")
                " | Flags " BC_State.HexText(snapshot.targetFlags, 2)
                " | Resource " BC_Overlay.SafeText(snapshot.targetResourceKindName, "none")
            )
        }

        return (
            "Level " BC_Overlay.SafeText(snapshot.targetLevel, "-")
            " | Flags " BC_State.HexText(snapshot.targetFlags, 2)
            " | Resource " BC_Overlay.SafeText(snapshot.targetResourceKindName, "none")
            " | " BC_State.JoinTags(BC_State.BuildTargetStateTags(snapshot))
        )
    }

    static FormatOpsTargetDetails(snapshot) {
        if !BC_Overlay.HasTarget(snapshot) {
            return "Target telemetry unavailable."
        }

        lines := []
        lines.Push("Health: " BC_State.PairOrDefaultText(snapshot.targetHealthCurrent, snapshot.targetHealthMax) " (" BC_State.PercentText(snapshot.targetHealthCurrent, snapshot.targetHealthMax) ")")
        lines.Push("Resource: " BC_State.PairOrDefaultText(snapshot.targetResourceCurrent, snapshot.targetResourceMax) " (" BC_State.PercentText(snapshot.targetResourceCurrent, snapshot.targetResourceMax) ") " BC_Overlay.SafeText(snapshot.targetResourceKindName, "none"))
        lines.Push("Relation/tier/tag: " BC_Overlay.SafeText(snapshot.targetRelationName, "unknown") " / " BC_Overlay.SafeText(snapshot.targetTierName, "normal") " / " BC_Overlay.SafeText(snapshot.targetTaggedName, "none"))
        lines.Push("Zone/dist: " BC_State.BoolText(snapshot.sameZone) " / " BC_Overlay.SafeText(snapshot.distanceXZ, "-") " (" BC_Overlay.SafeText(snapshot.distanceBucketText, "-") ")")
        return BC_Debug.Join(lines, "`r`n")
    }

    static FormatTargetExtras(snapshot) {
        if !BC_Overlay.IsTacticalSurface() {
            return BC_Overlay.FormatOpsTargetDetails(snapshot)
        }

        if !BC_Overlay.HasTarget(snapshot) {
            return "Target telemetry unavailable."
        }

        lines := []
        lines.Push("Health: " BC_State.PairOrDefaultText(snapshot.targetHealthCurrent, snapshot.targetHealthMax) " (" BC_State.PercentText(snapshot.targetHealthCurrent, snapshot.targetHealthMax) ")")
        lines.Push("Resource: " BC_State.PairOrDefaultText(snapshot.targetResourceCurrent, snapshot.targetResourceMax) " (" BC_State.PercentText(snapshot.targetResourceCurrent, snapshot.targetResourceMax) ")")
        lines.Push("State: " BC_State.JoinTags(BC_State.BuildTargetStateTags(snapshot)))
        lines.Push("Relation/tier/tag/calling: " BC_Overlay.SafeText(snapshot.targetRelationName, "unknown") " / " BC_Overlay.SafeText(snapshot.targetTierName, "normal") " / " BC_Overlay.SafeText(snapshot.targetTaggedName, "none") " / " BC_Overlay.SafeText(snapshot.targetCallingName, "unknown"))
        lines.Push("Zone/radius: " BC_State.HexText(snapshot.targetZoneHash16, 4) " / " BC_Overlay.SafeText(snapshot.targetRadius, "-"))
        lines.Push("Coord: " BC_Overlay.SafeText(snapshot.targetCoordX, "-") ", " BC_Overlay.SafeText(snapshot.targetCoordY, "-") ", " BC_Overlay.SafeText(snapshot.targetCoordZ, "-"))
        lines.Push("Compare: " BC_State.BuildComparisonText(snapshot))
        lines.Push("Edge: " BC_State.BuildComparisonDeltaText(snapshot))
        return BC_Debug.Join(lines, "`r`n")
    }

    static FormatHudCompareText(snapshot) {
        if !BC_Overlay.HasTarget(snapshot) {
            return "Compare: player-only"
        }
        return "Compare: " BC_State.BuildComparisonText(snapshot) " | Edge: " BC_State.BuildComparisonDeltaText(snapshot)
    }

    static IsTacticalSurface() {
        return BC_Overlay.SurfaceMode = "hud" || BC_Overlay.SurfaceMode = "tactical"
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
            StrUpper(BC_Overlay.FreshnessLabel(snapshot))
            " | "
            BC_Overlay.SafeText(snapshot.searchMode, "-")
            " | "
            BC_Overlay.SafeText(snapshot.captureSource, "-")
            " | "
            BC_Overlay.SafeText(snapshot.captureRouteReason, "-")
            " | age "
            BC_State.AgeText(snapshot)
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
        tactical := BC_Overlay.IsTacticalSurface()
        acceptedText := BC_Overlay.StatusVerdict(snapshot)
        freshnessText := (snapshot.accepted || BC_Overlay.IsHeldFrame(snapshot)) ? (" | " StrUpper(BC_Overlay.FreshnessLabel(snapshot))) : ""
        searchText := snapshot.searchMode = "" ? "" : (" | " StrUpper(snapshot.searchMode))
        statusColor := BC_Overlay.StatusColor(snapshot)
        ageText := BC_State.AgeText(snapshot, "")
        sequenceText := snapshot.sequence = "" ? "" : (" | Seq " snapshot.sequence)
        confidenceText := snapshot.confidence = "" ? "" : (" | Confidence " snapshot.confidence)
        reasonText := snapshot.reason = "" ? "" : (" | " snapshot.reason)
        BC_Overlay.CurrentTitle := title
        BC_Overlay.LastSnapshot := snapshot

        BC_Overlay.SetControlText("Header", title)
        BC_Overlay.SetControlFontColor("Status", statusColor)
        BC_Overlay.SetControlFontColor("CompareText", BC_Overlay.CompareColor(snapshot))
        BC_Overlay.SetControlFontColor("PlayerStatus", BC_Overlay.PlayerStatusColor(snapshot))
        BC_Overlay.SetControlFontColor("TargetStatus", BC_Overlay.TargetStatusColor(snapshot))
        BC_Overlay.SetControlFontColor("CaptureText", BC_Overlay.CaptureColor(snapshot))
        BC_Overlay.SetControlFontColor("SessionText", BC_Overlay.SessionColor(snapshot))
        BC_Overlay.SetControlText("Status", "Status: " acceptedText freshnessText searchText (ageText = "" ? "" : (" | Age " ageText)) reasonText sequenceText confidenceText)
        BC_Overlay.SetControlText("CompareText", tactical ? BC_Overlay.FormatHudCompareText(snapshot) : BC_Overlay.FormatOpsCompareText(snapshot))
        BC_Overlay.SetControlText("PlayerHealthLabel", "Health: " BC_State.PairOrDefaultText(snapshot.playerHealthCurrent, snapshot.playerHealthMax) " (" BC_State.PercentText(snapshot.playerHealthCurrent, snapshot.playerHealthMax) ")")
        BC_Overlay.SetControlValue("PlayerHealthBar", BC_Overlay.Percent(snapshot.playerHealthCurrent, snapshot.playerHealthMax))
        BC_Overlay.SetControlText("PlayerResourceLabel", "Resource: " BC_State.PairOrDefaultText(snapshot.playerResourceCurrent, snapshot.playerResourceMax) " (" BC_State.PercentText(snapshot.playerResourceCurrent, snapshot.playerResourceMax) ") " BC_Overlay.SafeText(snapshot.playerResourceKindName, "none"))
        BC_Overlay.SetControlValue("PlayerResourceBar", BC_Overlay.Percent(snapshot.playerResourceCurrent, snapshot.playerResourceMax))
        BC_Overlay.SetControlText("PlayerMeta", BC_Overlay.FormatPlayerMeta(snapshot))
        BC_Overlay.SetControlText("PlayerStatus", BC_Overlay.FormatPlayerHudStatus(snapshot))
        BC_Overlay.SetControlValue("PlayerOffense", BC_Overlay.FormatPlayerOffense(snapshot))

        hasTarget := BC_Overlay.HasTarget(snapshot)
        BC_Overlay.SetControlText("TargetHealthLabel", hasTarget ? ("Health: " BC_State.PairOrDefaultText(snapshot.targetHealthCurrent, snapshot.targetHealthMax) " (" BC_State.PercentText(snapshot.targetHealthCurrent, snapshot.targetHealthMax) ")") : "Health: -")
        BC_Overlay.SetControlValue("TargetHealthBar", hasTarget ? BC_Overlay.Percent(snapshot.targetHealthCurrent, snapshot.targetHealthMax) : 0)
        BC_Overlay.SetControlText("TargetResourceLabel", hasTarget
            ? ("Resource: " BC_State.PairOrDefaultText(snapshot.targetResourceCurrent, snapshot.targetResourceMax) " (" BC_State.PercentText(snapshot.targetResourceCurrent, snapshot.targetResourceMax) ") " BC_Overlay.SafeText(snapshot.targetResourceKindName, "none"))
            : "Resource: -")
        BC_Overlay.SetControlValue("TargetResourceBar", hasTarget ? BC_Overlay.Percent(snapshot.targetResourceCurrent, snapshot.targetResourceMax) : 0)
        BC_Overlay.SetControlText("TargetMeta", BC_Overlay.FormatTargetMeta(snapshot))
        BC_Overlay.SetControlText("TargetStatus", BC_Overlay.FormatTargetHudStatus(snapshot))
        BC_Overlay.SetControlValue("TargetExtras", BC_Overlay.FormatTargetExtras(snapshot))

        BC_Overlay.SetControlText("TransportText", BC_Overlay.FormatTransportText(snapshot))
        BC_Overlay.SetControlText("CaptureText", BC_Overlay.FormatCaptureText(snapshot))
        BC_Overlay.SetControlText("SessionText", BC_Overlay.FormatSessionText(snapshot))
        BC_Overlay.SetControlValue("DetailsBody", BC_State.BuildOperatorSummaryText(snapshot) "`r`n`r`n" BC_State.BuildSnapshotText(snapshot))
        BC_Overlay.SetControlValue("HistoryBody", BC_Overlay.RenderLiveUiHistory())
        BC_Overlay.SetControlText("Footer", "Summary: " BC_Config.LiveSummaryTextPath " | State: " BC_Config.LiveStateTextPath)

        BC_Overlay.ShowWindow(window)
        return window
    }

    static UpdateHudFromSnapshot(snapshot, title := "BarCode Reader HUD") {
        window := BC_Overlay.EnsureHudWindow(title)
        controls := BC_Overlay.Controls
        acceptedText := BC_Overlay.StatusVerdict(snapshot)
        freshnessText := (snapshot.accepted || BC_Overlay.IsHeldFrame(snapshot)) ? (" | " StrUpper(BC_Overlay.FreshnessLabel(snapshot))) : ""
        searchText := snapshot.searchMode = "" ? "" : (" | " StrUpper(snapshot.searchMode))
        statusColor := BC_Overlay.StatusColor(snapshot)
        ageText := BC_State.AgeText(snapshot, "")
        sequenceText := snapshot.sequence = "" ? "" : (" | Seq " snapshot.sequence)
        confidenceText := snapshot.confidence = "" ? "" : (" | Confidence " snapshot.confidence)
        reasonText := snapshot.reason = "" ? "" : (" | " snapshot.reason)
        BC_Overlay.CurrentTitle := title
        BC_Overlay.LastSnapshot := snapshot

        BC_Overlay.SetControlText("Header", title)
        BC_Overlay.SetControlFontColor("Status", statusColor)
        BC_Overlay.SetControlFontColor("CompareText", BC_Overlay.CompareColor(snapshot))
        BC_Overlay.SetControlFontColor("PlayerStatus", BC_Overlay.PlayerStatusColor(snapshot))
        BC_Overlay.SetControlFontColor("TargetStatus", BC_Overlay.TargetStatusColor(snapshot))
        BC_Overlay.SetControlFontColor("CaptureText", BC_Overlay.CaptureColor(snapshot))
        BC_Overlay.SetControlFontColor("SessionText", BC_Overlay.SessionColor(snapshot))
        BC_Overlay.SetControlFontColor("Footer", BC_Overlay.SessionColor(snapshot))

        BC_Overlay.SetControlText("Status", "Status: " acceptedText freshnessText searchText (ageText = "" ? "" : (" | Age " ageText)) reasonText sequenceText confidenceText)
        BC_Overlay.SetControlText("CompareText", BC_Overlay.FormatHudCompareText(snapshot))
        BC_Overlay.SetControlText("PlayerHealthLabel", "Health: " BC_State.PairOrDefaultText(snapshot.playerHealthCurrent, snapshot.playerHealthMax) " (" BC_State.PercentText(snapshot.playerHealthCurrent, snapshot.playerHealthMax) ")")
        BC_Overlay.SetControlValue("PlayerHealthBar", BC_Overlay.Percent(snapshot.playerHealthCurrent, snapshot.playerHealthMax))
        BC_Overlay.SetControlText("PlayerResourceLabel", "Resource: " BC_State.PairOrDefaultText(snapshot.playerResourceCurrent, snapshot.playerResourceMax) " (" BC_State.PercentText(snapshot.playerResourceCurrent, snapshot.playerResourceMax) ") " BC_Overlay.SafeText(snapshot.playerResourceKindName, "none"))
        BC_Overlay.SetControlValue("PlayerResourceBar", BC_Overlay.Percent(snapshot.playerResourceCurrent, snapshot.playerResourceMax))
        BC_Overlay.SetControlText("PlayerMeta", BC_Overlay.FormatPlayerMeta(snapshot))
        BC_Overlay.SetControlText("PlayerStatus", BC_Overlay.FormatPlayerHudStatus(snapshot))
        BC_Overlay.SetControlValue("PlayerOffense", BC_Overlay.FormatPlayerOffense(snapshot))

        hasTarget := BC_Overlay.HasTarget(snapshot)
        BC_Overlay.SetControlText("TargetHealthLabel", hasTarget ? ("Health: " BC_State.PairOrDefaultText(snapshot.targetHealthCurrent, snapshot.targetHealthMax) " (" BC_State.PercentText(snapshot.targetHealthCurrent, snapshot.targetHealthMax) ")") : "Health: -")
        BC_Overlay.SetControlValue("TargetHealthBar", hasTarget ? BC_Overlay.Percent(snapshot.targetHealthCurrent, snapshot.targetHealthMax) : 0)
        BC_Overlay.SetControlText("TargetResourceLabel", hasTarget
            ? ("Resource: " BC_State.PairOrDefaultText(snapshot.targetResourceCurrent, snapshot.targetResourceMax) " (" BC_State.PercentText(snapshot.targetResourceCurrent, snapshot.targetResourceMax) ") " BC_Overlay.SafeText(snapshot.targetResourceKindName, "none"))
            : "Resource: -")
        BC_Overlay.SetControlValue("TargetResourceBar", hasTarget ? BC_Overlay.Percent(snapshot.targetResourceCurrent, snapshot.targetResourceMax) : 0)
        BC_Overlay.SetControlText("TargetMeta", BC_Overlay.FormatTargetMeta(snapshot))
        BC_Overlay.SetControlText("TargetStatus", BC_Overlay.FormatTargetHudStatus(snapshot))
        BC_Overlay.SetControlValue("TargetExtras", BC_Overlay.FormatTargetExtras(snapshot))

        BC_Overlay.SetControlText("TransportText", BC_Overlay.FormatTransportText(snapshot))
        BC_Overlay.SetControlText("CaptureText", BC_Overlay.FormatCaptureText(snapshot))
        BC_Overlay.SetControlText("SessionText", BC_Overlay.FormatSessionText(snapshot))
        BC_Overlay.SetControlValue("HistoryText", BC_Overlay.RenderLiveUiHistory())
        BC_Overlay.SetControlText("Footer", BC_Overlay.FormatReaderFooter(snapshot))

        BC_Overlay.ShowWindow(window)
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
        BC_Overlay.WindowNoActivate := false
        BC_Overlay.SurfaceMode := "dashboard"
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
        BC_Overlay.WindowNoActivate := false
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

    static ShowCurrentTactical(title := "BarCode Tactical Dashboard", autoCloseMs := 0) {
        BC_Overlay.StopLiveUiTimers()
        BC_Overlay.ResetLiveUiState()
        BC_Overlay.WindowNoActivate := false
        BC_Overlay.SurfaceMode := "tactical"
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
                Mode: "tacticalui",
                Accepted: snapshot.accepted,
                Reason: snapshot.reason,
                Sequence: snapshot.sequence,
                SearchMode: snapshot.searchMode
            }
        }
    }

    static PrimeStaticSnapshot(result) {
        if !IsObject(result) || !result.HasOwnProp("Validation") {
            throw Error("Static HUD/dashboard preview requires a decoded result.")
        }

        BC_Tests.ApplyStaticResult(result, 1, true)
    }

    static PrimeSyntheticState() {
        BC_State.ResetLiveOutputs()
        BC_Tests.ApplyStaticResult(BC_Tests.DecodeSyntheticOps(42), 1, false)
        BC_Tests.ApplyStaticResult(BC_Tests.DecodeSyntheticTactical(43), 2, true)
    }

    static WaitUntilClosed() {
        while IsObject(BC_Overlay.Window) {
            Sleep 50
        }
    }

    static BuildSyntheticProvider() {
        state := {
            Sequence: 0,
            Pattern: [
                BC_Config.PageIdOpsOverview,
                BC_Config.PageIdTacticalCombat,
                BC_Config.PageIdTacticalCombat,
                BC_Config.PageIdTacticalCombat
            ]
        }
        return (*) => BC_Overlay.PollSyntheticProvider(state)
    }

    static PollSyntheticProvider(state) {
        state.Sequence += 1
        pageIndex := Mod(state.Sequence - 1, state.Pattern.Length) + 1
        pageId := state.Pattern[pageIndex]
        return (pageId = BC_Config.PageIdOpsOverview)
            ? BC_Tests.DecodeSyntheticOps(state.Sequence)
            : BC_Tests.DecodeSyntheticTactical(state.Sequence)
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
            if BC_Overlay.ShouldRenderLiveSnapshot(displaySnapshot) {
                BC_Overlay.RenderSnapshot(displaySnapshot, BC_Overlay.CurrentTitle)
                BC_Overlay.SetControlText("LiveMode", "Mode: " BC_Overlay.LiveUiMode " | Source: " BC_Overlay.LiveUiSourceLabel " | Tick " BC_Overlay.LiveUiTickCount " | Sample " BC_Overlay.LiveUiIntervalMs "ms | Paint " BC_Overlay.LiveUiRenderIntervalMs "ms | " StrUpper(BC_Overlay.FreshnessLabel(displaySnapshot)) " | Age " BC_State.AgeText(displaySnapshot))
                BC_Overlay.LiveUiLastRenderTick := A_TickCount
                BC_Overlay.LiveUiLastRenderedSnapshot := BC_Overlay.CloneSnapshot(displaySnapshot)
            }
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
        BC_Overlay.WindowNoActivate := true
        BC_State.ResetLiveOutputs()
        BC_Overlay.SurfaceMode := surfaceMode
        BC_Overlay.LiveUiMode := StrLower(source)
        BC_Overlay.LiveUiSourceLabel := BC_Overlay.LiveUiMode
        BC_Overlay.LiveUiIntervalMs := Max(25, Integer(intervalMs))
        BC_Overlay.LiveUiRenderIntervalMs := Max(BC_Config.LiveSurfaceDefaultRenderMs, BC_Overlay.LiveUiIntervalMs)
        BC_Overlay.LiveUiAutoCloseMs := Max(0, Integer(autoCloseMs))
        BC_Overlay.LiveUiTickCount := 0
        BC_Overlay.LiveUiStartTick := A_TickCount
        BC_Overlay.LiveUiLastRenderTick := 0
        BC_Overlay.LiveUiLastSnapshot := ""
        BC_Overlay.LiveUiLastAcceptedSnapshot := ""
        BC_Overlay.LiveUiLastRenderedSnapshot := ""
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
                : (surfaceMode = "tactical"
                    ? ("BarCode Tactical Dashboard | LiveTacticalUI | " BC_Overlay.LiveUiSourceLabel)
                    : ("BarCode Reader Dashboard | LiveUI | " BC_Overlay.LiveUiSourceLabel)))
        if (surfaceMode = "hud") {
            BC_Overlay.EnsureHudWindow(windowTitle)
        } else {
            BC_Overlay.EnsureWindow(windowTitle)
        }
        BC_Overlay.SetControlText("LiveMode", "Mode: " BC_Overlay.LiveUiMode " | Source: " BC_Overlay.LiveUiSourceLabel " | Tick 0 | Sample " BC_Overlay.LiveUiIntervalMs "ms | Paint " BC_Overlay.LiveUiRenderIntervalMs "ms")

        BC_Overlay.LiveUiTick()
        BC_Overlay.WaitUntilLiveUiComplete()

        return {
            Success: IsObject(BC_Overlay.LiveUiLastSnapshot) ? BC_Overlay.LiveUiLastSnapshot.accepted : false,
            ReportPath: surfaceMode = "hud" ? BC_Config.LiveSummaryTextPath : BC_Config.LiveStateTextPath,
            Summary: {
                Mode: surfaceMode = "hud" ? "livehud" : (surfaceMode = "tactical" ? "livetacticalui" : "liveui"),
                Accepted: IsObject(BC_Overlay.LiveUiLastSnapshot) ? BC_Overlay.LiveUiLastSnapshot.accepted : false,
                Reason: IsObject(BC_Overlay.LiveUiLastSnapshot) ? BC_Overlay.LiveUiLastSnapshot.reason : "",
                Sequence: IsObject(BC_Overlay.LiveUiLastSnapshot) ? BC_Overlay.LiveUiLastSnapshot.sequence : "",
                SearchMode: IsObject(BC_Overlay.LiveUiLastSnapshot) ? BC_Overlay.LiveUiLastSnapshot.searchMode : ""
            }
        }
    }

    static RunSyntheticDashboard(autoCloseMs := 0) {
        BC_Overlay.PrimeSyntheticState()
        return BC_Overlay.ShowCurrentState("BarCode Reader Dashboard | Synthetic", autoCloseMs)
    }

    static RunBmpDashboard(path, cropX := 0, cropY := 0, autoCloseMs := 0) {
        BC_Overlay.PrimeStaticSnapshot(BC_Tests.DecodeBmp(path, cropX, cropY))
        return BC_Overlay.ShowCurrentState("BarCode Reader Dashboard | BMP", autoCloseMs)
    }

    static RunSyntheticTacticalDashboard(autoCloseMs := 0) {
        BC_Overlay.PrimeSyntheticState()
        return BC_Overlay.ShowCurrentTactical("BarCode Tactical Dashboard | Synthetic", autoCloseMs)
    }

    static RunBmpTacticalDashboard(path, cropX := 0, cropY := 0, autoCloseMs := 0) {
        BC_Overlay.PrimeStaticSnapshot(BC_Tests.DecodeBmp(path, cropX, cropY))
        return BC_Overlay.ShowCurrentTactical("BarCode Tactical Dashboard | BMP", autoCloseMs)
    }

    static RunSyntheticHud(autoCloseMs := 0) {
        BC_Overlay.PrimeSyntheticState()
        return BC_Overlay.ShowCurrentHud("BarCode Reader HUD | Synthetic", autoCloseMs)
    }

    static RunBmpHud(path, cropX := 0, cropY := 0, autoCloseMs := 0) {
        BC_Overlay.PrimeStaticSnapshot(BC_Tests.DecodeBmp(path, cropX, cropY))
        return BC_Overlay.ShowCurrentHud("BarCode Reader HUD | BMP", autoCloseMs)
    }

    static RunLiveUiSynthetic(intervalMs := 125, autoCloseMs := 0, title := "") {
        return BC_Overlay.StartLiveUi("synthetic", "", 0, 0, intervalMs, autoCloseMs, title)
    }

    static RunLiveUiBmp(path, cropX := 0, cropY := 0, intervalMs := 125, autoCloseMs := 0, title := "") {
        return BC_Overlay.StartLiveUi("bmp", path, cropX, cropY, intervalMs, autoCloseMs, title)
    }

    static RunLiveUiLive(intervalMs := 125, autoCloseMs := 0, title := "") {
        return BC_Overlay.StartLiveUi("live", "", 0, 0, intervalMs, autoCloseMs, title)
    }

    static RunLiveTacticalUiSynthetic(intervalMs := 125, autoCloseMs := 0, title := "") {
        return BC_Overlay.StartLiveSurface("tactical", "synthetic", "", 0, 0, intervalMs, autoCloseMs, title)
    }

    static RunLiveTacticalUiBmp(path, cropX := 0, cropY := 0, intervalMs := 125, autoCloseMs := 0, title := "") {
        return BC_Overlay.StartLiveSurface("tactical", "bmp", path, cropX, cropY, intervalMs, autoCloseMs, title)
    }

    static RunLiveTacticalUiLive(intervalMs := 125, autoCloseMs := 0, title := "") {
        return BC_Overlay.StartLiveSurface("tactical", "live", "", 0, 0, intervalMs, autoCloseMs, title)
    }

    static RunLiveHudSynthetic(intervalMs := 125, autoCloseMs := 0, title := "") {
        return BC_Overlay.StartLiveSurface("hud", "synthetic", "", 0, 0, intervalMs, autoCloseMs, title)
    }

    static RunLiveHudBmp(path, cropX := 0, cropY := 0, intervalMs := 125, autoCloseMs := 0, title := "") {
        return BC_Overlay.StartLiveSurface("hud", "bmp", path, cropX, cropY, intervalMs, autoCloseMs, title)
    }

    static RunLiveHudLive(intervalMs := 125, autoCloseMs := 0, title := "") {
        return BC_Overlay.StartLiveSurface("hud", "live", "", 0, 0, intervalMs, autoCloseMs, title)
    }
}

; end-of-script marker comment
