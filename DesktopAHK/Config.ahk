/*
script name: DesktopAHK/Config.ahk
version: 0.2.0
purpose: Defines shared configuration values for the BarCode AHK reader smoke harness.
dependencies: AutoHotkey v2.0+
important assumptions: The minimum reader smoke uses fixed-profile BC-Strip/1 geometry, but BMP decoding may need to solve a scaled top-left symbol panel inside a larger screenshot.
protocol version: BC-Strip/1
framework module role: Desktop configuration
character count note: Character count not precomputed; measure with tooling if needed.
*/

class BC_Config {
    static AppName := "BarCode"
    static AppVersion := "0.2.0"
    static ProtocolVersion := 1
    static LayoutId := 1
    static ProfileId := 1
    static SchemaId := 2
    static PageIdPlayerCoreHot := 0
    static PageIdPlayerCoreCold := 1
    static TransportBytes := 76
    static HeaderBytes := 12
    static PayloadBytes := 56
    static FooterBytes := 8
    static HotPayloadUsedLength := 24
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
    static ReportDir := A_ScriptDir "\out"
    static FixtureDir := A_ScriptDir "\fixtures"
    static GoodFixturePath := A_ScriptDir "\fixtures\bc_strip_p720a_hot.bmp"
    static CorruptFixturePath := A_ScriptDir "\fixtures\bc_strip_p720a_hot_corrupt.bmp"
    static SmokeReportPath := A_ScriptDir "\out\phase2-reader-smoke.txt"
    static FixedBmpReportPath := A_ScriptDir "\out\phase2-fixed-bmp.txt"
    static LiveReportPath := A_ScriptDir "\out\phase2-live.txt"
    static LiveCaptureBmpPath := A_ScriptDir "\out\phase2-live-last-capture.bmp"
    static LatestRunPath := A_ScriptDir "\out\latest-run.txt"

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
