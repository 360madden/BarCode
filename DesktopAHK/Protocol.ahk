/*
script name: DesktopAHK/Protocol.ahk
version: 0.1.0
purpose: Implements the BC-Strip/1 profile, static payload, CRC, and module matrix construction.
dependencies: DesktopAHK/Config.ahk
important assumptions: Uses CRC-16/CCITT-FALSE and MSB-first bit packing.
protocol version: BC-Strip/1
framework module role: Protocol definition
character count note: Character count not precomputed; measure with tooling if needed.
*/

class BC_Protocol {
    static GetProfile(profileId := "P720A") {
        if (profileId != "P720A") {
            throw Error("Unsupported profile in phase 1: " profileId)
        }
        return BC_Config.ProfileP720A()
    }

    static GetStaticPayloadBytes() {
        return [
            0x10, 0x11, 0x12, 0x13, 0x20, 0x21, 0x22, 0x23,
            0x30, 0x31, 0x32, 0x33, 0x40, 0x41, 0x42, 0x43,
            0x50, 0x51, 0x52, 0x53, 0x60, 0x61, 0x62, 0x63
        ]
    }

    static GetWitnessBytes() {
        bytes := []
        value := 0xA5
        Loop 32 {
            bytes.Push(value)
            value := (value = 0xA5) ? 0x5A : 0xA5
        }
        return bytes
    }

    static BuildStaticFrameBytes() {
        profile := BC_Protocol.GetProfile()
        payload := BC_Protocol.GetStaticPayloadBytes()
        bytes := []

        bytes.Push(0x42)
        bytes.Push(0x43)
        bytes.Push(BC_Config.ProtocolVersion)
        bytes.Push(BC_Config.LayoutId)
        bytes.Push(profile.NumericId)
        bytes.Push(BC_Config.SchemaId)
        bytes.Push(BC_Config.StaticSequence)
        bytes.Push(0x00)
        bytes.Push(BC_Config.StaticPayloadLength)
        bytes.Push(0x00)

        headerCrc := BC_Protocol.Crc16(bytes, 1, 10)
        bytes.Push((headerCrc >> 8) & 0xFF)
        bytes.Push(headerCrc & 0xFF)

        for _, value in payload {
            bytes.Push(value)
        }

        payloadCrc := BC_Protocol.Crc16(payload, 1, payload.Length)
        bytes.Push((payloadCrc >> 8) & 0xFF)
        bytes.Push(payloadCrc & 0xFF)
        bytes.Push(0x42)
        bytes.Push(0x43)
        bytes.Push(BC_Config.ProtocolVersion)
        bytes.Push(BC_Config.StaticSequence)
        bytes.Push(BC_Config.StaticPayloadLength)
        bytes.Push(0xC3)

        for _, value in BC_Protocol.GetWitnessBytes() {
            bytes.Push(value)
        }

        return bytes
    }

    static BytesToBits(bytes) {
        bits := []
        for _, value in bytes {
            shift := 7
            while (shift >= 0) {
                bits.Push((value >> shift) & 0x1)
                shift -= 1
            }
        }
        return bits
    }

    static BuildModuleMatrix(profile, frameBytes) {
        matrix := []
        bits := BC_Protocol.BytesToBits(frameBytes)
        bitCursor := 1

        Loop profile.GridRows {
            row := []
            Loop profile.GridColumns {
                row.Push(0)
            }
            matrix.Push(row)
        }

        Loop profile.GridColumns {
            column := A_Index
            matrix[1][column] := 1
            if (Mod(column - 1, 2) = 0) {
                matrix[profile.GridRows][column] := 1
            }
        }

        Loop profile.GridRows {
            row := A_Index
            matrix[row][1] := 1
            if (Mod(row - 1, 2) = 0) {
                matrix[row][profile.GridColumns] := 1
            }
        }

        rowIndex := 2
        while (rowIndex <= profile.GridRows - 1) {
            columnIndex := 2
            while (columnIndex <= profile.GridColumns - 1) {
                matrix[rowIndex][columnIndex] := bits[bitCursor]
                bitCursor += 1
                columnIndex += 1
            }
            rowIndex += 1
        }

        return matrix
    }

    static Crc16(bytes, startIndex, endIndex) {
        crc := 0xFFFF
        index := startIndex
        while (index <= endIndex) {
            crc := crc ^ (bytes[index] << 8)
            Loop 8 {
                if (crc & 0x8000) {
                    crc := ((crc << 1) ^ 0x1021) & 0xFFFF
                } else {
                    crc := (crc << 1) & 0xFFFF
                }
            }
            index += 1
        }
        return crc
    }
}

; end-of-script marker comment
