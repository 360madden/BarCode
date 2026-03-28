/*
script name: DesktopAHK/Protocol.ahk
version: 0.4.0
purpose: Implements BC-Strip/1 schema-4 ops+tactical transport packing, parsing, CRC, and module matrix construction.
dependencies: DesktopAHK/Config.ahk
important assumptions: Uses CRC-16/CCITT-FALSE, fixed P720A geometry, and synthetic ops+tactical samples for reader smoke.
protocol version: BC-Strip/1
framework module role: Protocol definition
character count note: Character count not precomputed; measure with tooling if needed.
*/

class BC_Protocol {
    static ClampUnsigned(value, maxValue) {
        try {
            numeric := Integer(value)
        } catch {
            numeric := 0
        }
        if (numeric < 0) {
            return 0
        }
        if (numeric > maxValue) {
            return maxValue
        }
        return numeric
    }

    static ClampSigned(value, minValue, maxValue) {
        try {
            numeric := Integer(value)
        } catch {
            numeric := 0
        }
        if (numeric < minValue) {
            return minValue
        }
        if (numeric > maxValue) {
            return maxValue
        }
        return numeric
    }

    static GetProfile(profileId := "P720A") {
        if (profileId != "P720A") {
            throw Error("Unsupported profile in reader harness: " profileId)
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

    static BuildSyntheticSnapshot() {
        return {
            PlayerAvailable: true,
            SampleMask: 0xFFFF,
            TacticalMask: 0x07FF,
            StateFlags: 0x01F7,
            PlayerResourceKindId: 1,
            PlayerHealthCurrent: 11770,
            PlayerHealthMax: 11770,
            PlayerResourceCurrent: 4990,
            PlayerResourceMax: 4990,
            PlayerLevel: 47,
            PlayerCallingCode: 1,
            PlayerRoleCode: 1,
            PlayerCastFlags: 0x03,
            PlayerCastProgressQ15: 16384,
            PlayerPowerAttack: 1825,
            PlayerCritAttack: 945,
            PlayerPowerSpell: 2630,
            PlayerCritSpell: 1185,
            PlayerCritPower: 510,
            PlayerHit: 425,
            TargetResourceKindId: 1,
            TargetHealthCurrent: 6320,
            TargetHealthMax: 9110,
            TargetResourceCurrent: 2120,
            TargetResourceMax: 3500,
            TargetLevel: 46,
            TargetFlags: 0x01,
            TargetRelationCode: 2,
            TargetTierCode: 1,
            TargetTaggedCode: 1,
            TargetCallingCode: 4,
            PlayerZoneHash16: 0x1A2B,
            TargetZoneHash16: 0x1A2B,
            PlayerCoordX10: 10452,
            PlayerCoordY10: 122,
            PlayerCoordZ10: 9817,
            TargetCoordX10: 10608,
            TargetCoordY10: 122,
            TargetCoordZ10: 9956,
            TargetRadiusQ10: 18,
            PlayerDamageEstimate: 0,
            TargetDamageEstimate: 0
        }
    }

    static BuildSyntheticHotSnapshot() {
        return BC_Protocol.BuildSyntheticSnapshot()
    }

    static BuildOpsPayloadBytes(snapshot) {
        payload := BC_Protocol.GetWitnessBytes(BC_Config.PayloadBytes)
        index := 1

        index := BC_Protocol.PutUInt16(payload, index, snapshot.SampleMask)
        index := BC_Protocol.PutUInt16(payload, index, snapshot.StateFlags)
        index := BC_Protocol.PutUInt8(payload, index, snapshot.PlayerResourceKindId)
        index := BC_Protocol.PutUInt24(payload, index, snapshot.PlayerHealthCurrent)
        index := BC_Protocol.PutUInt24(payload, index, snapshot.PlayerHealthMax)
        index := BC_Protocol.PutUInt24(payload, index, snapshot.PlayerResourceCurrent)
        index := BC_Protocol.PutUInt24(payload, index, snapshot.PlayerResourceMax)
        index := BC_Protocol.PutUInt8(payload, index, snapshot.PlayerLevel)
        index := BC_Protocol.PutUInt8(payload, index, snapshot.PlayerCallingCode)
        index := BC_Protocol.PutUInt8(payload, index, snapshot.PlayerRoleCode)
        index := BC_Protocol.PutUInt8(payload, index, snapshot.TargetResourceKindId)
        index := BC_Protocol.PutUInt24(payload, index, snapshot.TargetHealthCurrent)
        index := BC_Protocol.PutUInt24(payload, index, snapshot.TargetHealthMax)
        index := BC_Protocol.PutUInt24(payload, index, snapshot.TargetResourceCurrent)
        index := BC_Protocol.PutUInt24(payload, index, snapshot.TargetResourceMax)
        index := BC_Protocol.PutUInt8(payload, index, snapshot.TargetLevel)
        index := BC_Protocol.PutUInt8(payload, index, snapshot.TargetFlags)
        index := BC_Protocol.PutUInt8(payload, index, snapshot.TargetRelationCode)

        return payload
    }

    static BuildTacticalPayloadBytes(snapshot) {
        payload := BC_Protocol.GetWitnessBytes(BC_Config.PayloadBytes)
        index := 1

        index := BC_Protocol.PutUInt16(payload, index, snapshot.TacticalMask)
        index := BC_Protocol.PutUInt16(payload, index, snapshot.StateFlags)
        index := BC_Protocol.PutUInt8(payload, index, snapshot.PlayerCastFlags)
        index := BC_Protocol.PutUInt16(payload, index, snapshot.PlayerCastProgressQ15)
        index := BC_Protocol.PutUInt16(payload, index, snapshot.PlayerPowerAttack)
        index := BC_Protocol.PutUInt16(payload, index, snapshot.PlayerCritAttack)
        index := BC_Protocol.PutUInt16(payload, index, snapshot.PlayerPowerSpell)
        index := BC_Protocol.PutUInt16(payload, index, snapshot.PlayerCritSpell)
        index := BC_Protocol.PutUInt16(payload, index, snapshot.PlayerCritPower)
        index := BC_Protocol.PutUInt16(payload, index, snapshot.PlayerHit)
        index := BC_Protocol.PutUInt16(payload, index, snapshot.PlayerZoneHash16)
        index := BC_Protocol.PutUInt16(payload, index, snapshot.TargetZoneHash16)
        index := BC_Protocol.PutInt24(payload, index, snapshot.PlayerCoordX10)
        index := BC_Protocol.PutInt24(payload, index, snapshot.PlayerCoordY10)
        index := BC_Protocol.PutInt24(payload, index, snapshot.PlayerCoordZ10)
        index := BC_Protocol.PutInt24(payload, index, snapshot.TargetCoordX10)
        index := BC_Protocol.PutInt24(payload, index, snapshot.TargetCoordY10)
        index := BC_Protocol.PutInt24(payload, index, snapshot.TargetCoordZ10)
        index := BC_Protocol.PutUInt8(payload, index, snapshot.TargetRelationCode)
        index := BC_Protocol.PutUInt8(payload, index, snapshot.TargetTierCode)
        index := BC_Protocol.PutUInt8(payload, index, snapshot.TargetTaggedCode)
        index := BC_Protocol.PutUInt8(payload, index, snapshot.TargetCallingCode)
        index := BC_Protocol.PutUInt16(payload, index, snapshot.TargetRadiusQ10)

        return payload
    }

    static GetPayloadUsedLength(pageId) {
        if (pageId = BC_Config.PageIdOpsOverview) {
            return BC_Config.OpsPayloadUsedLength
        }
        if (pageId = BC_Config.PageIdTacticalCombat) {
            return BC_Config.TacticalPayloadUsedLength
        }
        throw Error("Unsupported page id in reader harness: " pageId)
    }

    static BuildPayloadBytesForPage(snapshot, pageId) {
        if (pageId = BC_Config.PageIdOpsOverview) {
            return BC_Protocol.BuildOpsPayloadBytes(snapshot)
        }
        if (pageId = BC_Config.PageIdTacticalCombat) {
            return BC_Protocol.BuildTacticalPayloadBytes(snapshot)
        }
        throw Error("Unsupported page id in reader harness: " pageId)
    }

    static BuildLiveFrameBytes(snapshot := 0, sequence := 42, pageId := -1) {
        profile := BC_Protocol.GetProfile()
        if !IsObject(snapshot) {
            snapshot := BC_Protocol.BuildSyntheticSnapshot()
        }
        if (pageId < 0) {
            pageId := BC_Config.PageIdOpsOverview
        }

        bytes := []
        payload := BC_Protocol.BuildPayloadBytesForPage(snapshot, pageId)
        payloadUsedLength := BC_Protocol.GetPayloadUsedLength(pageId)
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
        bytes.Push(payloadUsedLength)

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

    static ExtractOpsPage(bytes) {
        payloadOffset := 13
        return {
            SampleMask: BC_Protocol.ReadUInt16(bytes, payloadOffset),
            StateFlags: BC_Protocol.ReadUInt16(bytes, payloadOffset + 2),
            PlayerResourceKindId: bytes[payloadOffset + 4],
            PlayerHealthCurrent: BC_Protocol.ReadUInt24(bytes, payloadOffset + 5),
            PlayerHealthMax: BC_Protocol.ReadUInt24(bytes, payloadOffset + 8),
            PlayerResourceCurrent: BC_Protocol.ReadUInt24(bytes, payloadOffset + 11),
            PlayerResourceMax: BC_Protocol.ReadUInt24(bytes, payloadOffset + 14),
            PlayerLevel: bytes[payloadOffset + 17],
            PlayerCallingCode: bytes[payloadOffset + 18],
            PlayerRoleCode: bytes[payloadOffset + 19],
            TargetResourceKindId: bytes[payloadOffset + 20],
            TargetHealthCurrent: BC_Protocol.ReadUInt24(bytes, payloadOffset + 21),
            TargetHealthMax: BC_Protocol.ReadUInt24(bytes, payloadOffset + 24),
            TargetResourceCurrent: BC_Protocol.ReadUInt24(bytes, payloadOffset + 27),
            TargetResourceMax: BC_Protocol.ReadUInt24(bytes, payloadOffset + 30),
            TargetLevel: bytes[payloadOffset + 33],
            TargetFlags: bytes[payloadOffset + 34],
            TargetRelationCode: bytes[payloadOffset + 35]
        }
    }

    static ExtractTacticalPage(bytes) {
        payloadOffset := 13
        return {
            TacticalMask: BC_Protocol.ReadUInt16(bytes, payloadOffset),
            StateFlags: BC_Protocol.ReadUInt16(bytes, payloadOffset + 2),
            PlayerCastFlags: bytes[payloadOffset + 4],
            PlayerCastProgressQ15: BC_Protocol.ReadUInt16(bytes, payloadOffset + 5),
            PlayerPowerAttack: BC_Protocol.ReadUInt16(bytes, payloadOffset + 7),
            PlayerCritAttack: BC_Protocol.ReadUInt16(bytes, payloadOffset + 9),
            PlayerPowerSpell: BC_Protocol.ReadUInt16(bytes, payloadOffset + 11),
            PlayerCritSpell: BC_Protocol.ReadUInt16(bytes, payloadOffset + 13),
            PlayerCritPower: BC_Protocol.ReadUInt16(bytes, payloadOffset + 15),
            PlayerHit: BC_Protocol.ReadUInt16(bytes, payloadOffset + 17),
            PlayerZoneHash16: BC_Protocol.ReadUInt16(bytes, payloadOffset + 19),
            TargetZoneHash16: BC_Protocol.ReadUInt16(bytes, payloadOffset + 21),
            PlayerCoordX: BC_Protocol.ReadInt24(bytes, payloadOffset + 23) / 10.0,
            PlayerCoordY: BC_Protocol.ReadInt24(bytes, payloadOffset + 26) / 10.0,
            PlayerCoordZ: BC_Protocol.ReadInt24(bytes, payloadOffset + 29) / 10.0,
            TargetCoordX: BC_Protocol.ReadInt24(bytes, payloadOffset + 32) / 10.0,
            TargetCoordY: BC_Protocol.ReadInt24(bytes, payloadOffset + 35) / 10.0,
            TargetCoordZ: BC_Protocol.ReadInt24(bytes, payloadOffset + 38) / 10.0,
            TargetRelationCode: bytes[payloadOffset + 41],
            TargetTierCode: bytes[payloadOffset + 42],
            TargetTaggedCode: bytes[payloadOffset + 43],
            TargetCallingCode: bytes[payloadOffset + 44],
            TargetRadius: BC_Protocol.ReadUInt16(bytes, payloadOffset + 45) / 10.0
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
        bytes[index] := BC_Protocol.ClampUnsigned(value, 0xFF) & 0xFF
        return index + 1
    }

    static PutUInt16(bytes, index, value) {
        clamped := BC_Protocol.ClampUnsigned(value, 0xFFFF)
        bytes[index] := (clamped >> 8) & 0xFF
        bytes[index + 1] := clamped & 0xFF
        return index + 2
    }

    static PutUInt24(bytes, index, value) {
        clamped := BC_Protocol.ClampUnsigned(value, 0xFFFFFF)
        bytes[index] := (clamped >> 16) & 0xFF
        bytes[index + 1] := (clamped >> 8) & 0xFF
        bytes[index + 2] := clamped & 0xFF
        return index + 3
    }

    static PutInt24(bytes, index, value) {
        clamped := BC_Protocol.ClampSigned(value, -0x800000, 0x7FFFFF)
        if (clamped < 0) {
            clamped := 0x1000000 + clamped
        }
        return BC_Protocol.PutUInt24(bytes, index, clamped)
    }

    static ReadUInt16(bytes, offset) {
        return ((bytes[offset] << 8) | bytes[offset + 1]) & 0xFFFF
    }

    static ReadUInt24(bytes, offset) {
        return ((bytes[offset] << 16) | (bytes[offset + 1] << 8) | bytes[offset + 2]) & 0xFFFFFF
    }

    static ReadInt24(bytes, offset) {
        value := BC_Protocol.ReadUInt24(bytes, offset)
        if (value & 0x800000) {
            return value - 0x1000000
        }
        return value
    }
}

; end-of-script marker comment
