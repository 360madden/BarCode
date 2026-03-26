/*
script name: DesktopAHK/Protocol.ahk
version: 0.2.0
purpose: Implements BC-Strip/1 schema-2 transport packing, parsing, CRC, and module matrix construction for the reader smoke harness.
dependencies: DesktopAHK/Config.ahk
important assumptions: Uses CRC-16/CCITT-FALSE, fixed P720A geometry, and a synthetic PlayerCoreHot sample for the minimum reader smoke.
protocol version: BC-Strip/1
framework module role: Protocol definition
character count note: Character count not precomputed; measure with tooling if needed.
*/

class BC_Protocol {
    static GetProfile(profileId := "P720A") {
        if (profileId != "P720A") {
            throw Error("Unsupported profile in reader smoke: " profileId)
        }
        return BC_Config.ProfileP720A()
    }

    static GetWitnessBytes(count := 56) {
        bytes := []
        value := 0xA5
        Loop count {
            bytes.Push(value)
            value := (value = 0xA5) ? 0x5A : 0xA5
        }
        return bytes
    }

    static BuildSyntheticHotSnapshot() {
        return {
            PlayerAvailable: true,
            SampleMask: 0x003F,
            StateFlags: 0x001F,
            ResourceKindId: 1,
            HealthCurrent: 11770,
            HealthMax: 11770,
            ResourceCurrent: 4990,
            ResourceMax: 4990,
            CastFlags: 0x03,
            CastProgressQ15: 16384,
            Level: 47,
            CallingCode: 1,
            RoleCode: 1
        }
    }

    static BuildHotPayloadBytes(snapshot) {
        payload := BC_Protocol.GetWitnessBytes(BC_Config.PayloadBytes)
        index := 1

        index := BC_Protocol.PutUInt16(payload, index, snapshot.SampleMask)
        index := BC_Protocol.PutUInt16(payload, index, snapshot.StateFlags)
        index := BC_Protocol.PutUInt8(payload, index, snapshot.ResourceKindId)
        index := BC_Protocol.PutUInt24(payload, index, snapshot.HealthCurrent)
        index := BC_Protocol.PutUInt24(payload, index, snapshot.HealthMax)
        index := BC_Protocol.PutUInt24(payload, index, snapshot.ResourceCurrent)
        index := BC_Protocol.PutUInt24(payload, index, snapshot.ResourceMax)
        index := BC_Protocol.PutUInt8(payload, index, snapshot.CastFlags)
        index := BC_Protocol.PutUInt16(payload, index, snapshot.CastProgressQ15)
        index := BC_Protocol.PutUInt8(payload, index, snapshot.Level)
        index := BC_Protocol.PutUInt8(payload, index, snapshot.CallingCode)
        index := BC_Protocol.PutUInt8(payload, index, snapshot.RoleCode)
        index := BC_Protocol.PutUInt8(payload, index, 0)

        return payload
    }

    static BuildLiveFrameBytes(snapshot := 0, sequence := 42, pageId := -1) {
        profile := BC_Protocol.GetProfile()
        if !IsObject(snapshot) {
            snapshot := BC_Protocol.BuildSyntheticHotSnapshot()
        }
        if (pageId < 0) {
            pageId := BC_Config.PageIdPlayerCoreHot
        }

        bytes := []
        payload := BC_Protocol.BuildHotPayloadBytes(snapshot)
        flags0 := snapshot.PlayerAvailable ? 0x01 : 0x00

        bytes.Push(0x42)
        bytes.Push(0x43)
        bytes.Push(BC_Config.ProtocolVersion)
        bytes.Push(BC_Config.LayoutId)
        bytes.Push(profile.NumericId)
        bytes.Push(BC_Config.SchemaId)
        bytes.Push(pageId)
        bytes.Push(sequence & 0xFF)
        bytes.Push(flags0)
        bytes.Push(BC_Config.HotPayloadUsedLength)

        headerCrc := BC_Protocol.Crc16(bytes, 1, 10)
        bytes.Push((headerCrc >> 8) & 0xFF)
        bytes.Push(headerCrc & 0xFF)

        for _, value in payload {
            bytes.Push(value)
        }

        payloadCrc := BC_Protocol.Crc16(bytes, 13, 68)
        bytes.Push((payloadCrc >> 8) & 0xFF)
        bytes.Push(payloadCrc & 0xFF)
        bytes.Push(sequence & 0xFF)
        bytes.Push(pageId)
        bytes.Push(BC_Config.ProtocolVersion)
        bytes.Push(profile.NumericId)
        bytes.Push(0xC3)
        bytes.Push(0x5A)

        return bytes
    }

    static ParseTransport(bytes) {
        return {
            Sync0: bytes[1],
            Sync1: bytes[2],
            ProtocolVersion: bytes[3],
            LayoutId: bytes[4],
            ProfileId: bytes[5],
            SchemaId: bytes[6],
            PageId: bytes[7],
            Sequence: bytes[8],
            Flags0: bytes[9],
            PayloadUsedLength: bytes[10],
            HeaderCrc: ((bytes[11] << 8) | bytes[12]) & 0xFFFF,
            PayloadCrc: ((bytes[69] << 8) | bytes[70]) & 0xFFFF,
            SequenceEcho: bytes[71],
            PageIdEcho: bytes[72],
            ProtocolEcho: bytes[73],
            ProfileEcho: bytes[74],
            TailMagic: bytes[75],
            TailWitness: bytes[76]
        }
    }

    static ExtractHotPage(bytes) {
        payloadOffset := 13
        return {
            SampleMask: BC_Protocol.ReadUInt16(bytes, payloadOffset),
            StateFlags: BC_Protocol.ReadUInt16(bytes, payloadOffset + 2),
            ResourceKindId: bytes[payloadOffset + 4],
            HealthCurrent: BC_Protocol.ReadUInt24(bytes, payloadOffset + 5),
            HealthMax: BC_Protocol.ReadUInt24(bytes, payloadOffset + 8),
            ResourceCurrent: BC_Protocol.ReadUInt24(bytes, payloadOffset + 11),
            ResourceMax: BC_Protocol.ReadUInt24(bytes, payloadOffset + 14),
            CastFlags: bytes[payloadOffset + 17],
            CastProgressQ15: BC_Protocol.ReadUInt16(bytes, payloadOffset + 18),
            Level: bytes[payloadOffset + 20],
            CallingCode: bytes[payloadOffset + 21],
            RoleCode: bytes[payloadOffset + 22]
        }
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

    static PutUInt8(bytes, index, value) {
        bytes[index] := value & 0xFF
        return index + 1
    }

    static PutUInt16(bytes, index, value) {
        bytes[index] := (value >> 8) & 0xFF
        bytes[index + 1] := value & 0xFF
        return index + 2
    }

    static PutUInt24(bytes, index, value) {
        bytes[index] := (value >> 16) & 0xFF
        bytes[index + 1] := (value >> 8) & 0xFF
        bytes[index + 2] := value & 0xFF
        return index + 3
    }

    static ReadUInt16(bytes, offset) {
        return ((bytes[offset] << 8) | bytes[offset + 1]) & 0xFFFF
    }

    static ReadUInt24(bytes, offset) {
        return ((bytes[offset] << 16) | (bytes[offset + 1] << 8) | bytes[offset + 2]) & 0xFFFFFF
    }
}

; end-of-script marker comment
