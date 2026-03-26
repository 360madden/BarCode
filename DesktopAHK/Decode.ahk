/*
script name: DesktopAHK/Decode.ahk
version: 0.2.0
purpose: Samples BC-Strip/1 cells and reconstructs the transport bytes from a detected band using exact or scaled geometry.
dependencies: DesktopAHK/Detect.ahk, DesktopAHK/Interfaces.ahk, DesktopAHK/Protocol.ahk
important assumptions: Uses center-point kernel sampling and depends on the detection layer to solve any scaled top-left panel geometry.
protocol version: BC-Strip/1
framework module role: Decode
character count note: Character count not precomputed; measure with tooling if needed.
*/

class BC_Decode {
    static Decode(image, detection) {
        profile := detection.Profile
        threshold := detection.Threshold
        originX := detection.OriginX
        originY := detection.OriginY
        pitch := detection.Pitch > 0 ? detection.Pitch : profile.Pitch
        bits := []
        minMargin := 999999

        row := 2
        while (row <= profile.GridRows - 1) {
            column := 2
            while (column <= profile.GridColumns - 1) {
                value := BC_Detect.SampleModuleCenter(image, profile, column, row, originX, originY, pitch)
                margin := Abs(value - threshold)
                if (margin < minMargin) {
                    minMargin := margin
                }
                bits.Push(BC_Detect.IsDark(value, threshold) ? 1 : 0)
                column += 1
            }
            row += 1
        }

        bytes := []
        byteValue := 0
        bitCount := 0

        for _, bit in bits {
            byteValue := (byteValue << 1) | bit
            bitCount += 1
            if (bitCount = 8) {
                bytes.Push(byteValue & 0xFF)
                byteValue := 0
                bitCount := 0
            }
        }

        if (bitCount != 0) {
            bytes.Push((byteValue << (8 - bitCount)) & 0xFF)
        }

        return BC_Interfaces.DecodeResult(bytes, 0, minMargin, bits.Length)
    }
}

; end-of-script marker comment
