/*
script name: DesktopAHK/Config.ahk
version: 0.3.1
purpose: Defines shared configuration values for the scoped BarCode player-target HUD reader harness.
dependencies: AutoHotkey v2.0+
important assumptions: The scoped BarCode reader uses fixed-profile BC-Strip/1 geometry, but BMP/live decoding may need to solve a scaled top-left symbol panel inside a larger screenshot.
protocol version: BC-Strip/1
framework module role: Desktop configuration
character count note: Character count not precomputed; measure with tooling if needed.
*/

BC_ConfigResolveDataRoot() {
    baseDir := EnvGet("LOCALAPPDATA")
    if (baseDir = "") {
        baseDir := A_Temp
    }

    return baseDir "\BarCode\DesktopAHK"
}

class BC_Config {
    static AppName := "BarCode"
    static AppVersion := "0.3.1"
    static ProtocolVersion := 1
    static LayoutId := 1
    static ProfileId := 1
    static SchemaId := 3
    static PageIdPlayerCoreHot := 0
    static PageIdPlayerCoreCold := 1
    static TransportBytes := 76
    static HeaderBytes := 12
    static PayloadBytes := 56
    static FooterBytes := 8
    static HotPayloadUsedLength := 54
    static MaxBorderErrors := 12
    static SearchMinPitch := 4.00
    static SearchMaxPitch := 8.00
    static SearchCoarsePitchStep := 0.25
    static SearchFinePitchStep := 0.05
    static SearchMaxOriginX := 80
    static SearchMaxOriginY := 80
    static SearchCoarseXStep := 2
    static SearchCoarseYStep := 1
    static SearchCaptureHeight := 160
    static LockedCapturePaddingPixels := 8
    static LockedCaptureMinHeight := 64
    static DataRoot := BC_ConfigResolveDataRoot()
    static ReportDir := BC_Config.DataRoot "\out"
    static FixtureDir := BC_Config.DataRoot "\fixtures"
    static StateDir := BC_Config.DataRoot "\state"
    static LiveHistoryLimit := 64
    static GoodFixturePath := BC_Config.FixtureDir "\bc_strip_p720a_hot.bmp"
    static CorruptFixturePath := BC_Config.FixtureDir "\bc_strip_p720a_hot_corrupt.bmp"
    static SmokeReportPath := BC_Config.ReportDir "\phase2-reader-smoke.txt"
    static FixedBmpReportPath := BC_Config.ReportDir "\phase2-fixed-bmp.txt"
    static LiveReportPath := BC_Config.ReportDir "\phase2-live.txt"
    static LiveWatchReportPath := BC_Config.ReportDir "\phase2-watch.txt"
    static LiveCaptureBmpPath := BC_Config.ReportDir "\phase2-live-last-capture.bmp"
    static LiveRejectBmpPath := BC_Config.ReportDir "\phase2-live-first-reject.bmp"
    static LiveWatchRejectBmpPath := BC_Config.ReportDir "\phase2-watch-first-reject.bmp"
    static LatestRunPath := BC_Config.ReportDir "\latest-run.txt"
    static LiveStateJsonPath := BC_Config.StateDir "\latest-state.json"
    static LiveStateTextPath := BC_Config.StateDir "\latest-state.txt"
    static LockedGeometryPath := BC_Config.StateDir "\locked-geometry.txt"
    static LiveHistoryJsonPath := BC_Config.StateDir "\recent-history.json"
    static LiveHistoryJsonlPath := BC_Config.StateDir "\recent-history.jsonl"

    static SymbolPanelLight := { R: 245, G: 245, B: 245 }
    static ModuleDark := { R: 16, G: 16, B: 16 }

    static ProfileP720A() {
        return {
            Id: "P720A",
            NumericId: 1,
            WindowWidth: 1280,
            WindowHeight: 720,
            BandWidth: 1280,
            BandHeight: 64,
            QuietLeft: 24,
            QuietRight: 24,
            QuietTop: 8,
            QuietBottom: 8,
            Pitch: 8,
            GridColumns: 154,
            GridRows: 6,
            DataColumns: 152,
            DataRows: 4,
            SymbolWidth: 1232,
            SymbolHeight: 48
        }
    }
}

; end-of-script marker comment
