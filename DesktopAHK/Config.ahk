/*
script name: DesktopAHK/Config.ahk
version: 0.1.0
purpose: Defines shared configuration values for the BarCode AHK phase 1 harness.
dependencies: AutoHotkey v2.0+
important assumptions: Phase 1 works against synthetic 24-bit BMP fixtures and the P720A profile only.
protocol version: BC-Strip/1
framework module role: Desktop configuration
character count note: Character count not precomputed; measure with tooling if needed.
*/

class BC_Config {
    static AppName := "BarCode"
    static AppVersion := "0.1.0"
    static ProtocolVersion := 1
    static LayoutId := 1
    static ProfileId := 1
    static SchemaId := 1
    static StaticSequence := 42
    static StaticPayloadLength := 24
    static ReportDir := A_ScriptDir "\out"
    static FixtureDir := A_ScriptDir "\fixtures"
    static GoodFixturePath := A_ScriptDir "\fixtures\bc_strip_p720a_static.bmp"
    static CorruptFixturePath := A_ScriptDir "\fixtures\bc_strip_p720a_corrupt.bmp"
    static GoodReportPath := A_ScriptDir "\out\phase1-smoke.txt"

    static BandLight := { R: 245, G: 245, B: 245 }
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
