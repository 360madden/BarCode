/*
script name: DesktopAHK/Validate.ahk
version: 0.2.0
purpose: Applies transport integrity checks and schema-2 hot-page extraction to decoded BC-Strip/1 frames.
dependencies: DesktopAHK/Config.ahk, DesktopAHK/Interfaces.ahk, DesktopAHK/Protocol.ahk
important assumptions: Rejects on any structural mismatch; this smoke harness does not attempt error correction or auto-detect profile changes.
protocol version: BC-Strip/1
framework module role: Validation
character count note: Character count not precomputed; measure with tooling if needed.
*/

class BC_Validate {
    static Validate(detection, decodeResult) {
        bytes := decodeResult.Bytes
        details := {
            BorderErrors: detection.BorderErrors,
            Threshold: detection.Threshold,
            BlackMean: detection.BlackMean,
            WhiteMean: detection.WhiteMean,
            MinMargin: decodeResult.MinMargin,
            OriginX: detection.OriginX,
            OriginY: detection.OriginY,
            Pitch: detection.Pitch,
            BandWidth: detection.BandWidth,
            BandHeight: detection.BandHeight,
            SearchMode: detection.SearchMode,
            Contrast: detection.Contrast
        }

        if (bytes.Length != BC_Config.TransportBytes) {
            return BC_Interfaces.ValidationResult(false, "Unexpected byte count", 0.0, details)
        }

        if (detection.BorderErrors > BC_Config.MaxBorderErrors) {
            return BC_Interfaces.ValidationResult(false, "Border validation failed", 0.0, details)
        }

        transport := BC_Protocol.ParseTransport(bytes)
        details.Transport := transport

        if (transport.Sync0 != 0x42 || transport.Sync1 != 0x43) {
            return BC_Interfaces.ValidationResult(false, "Sync mismatch", 0.0, details)
        }

        if (transport.ProtocolVersion != BC_Config.ProtocolVersion || transport.LayoutId != BC_Config.LayoutId || transport.ProfileId != BC_Config.ProfileId || transport.SchemaId != BC_Config.SchemaId) {
            return BC_Interfaces.ValidationResult(false, "Header identity mismatch", 0.0, details)
        }

        if (transport.PageId != BC_Config.PageIdPlayerCoreHot) {
            return BC_Interfaces.ValidationResult(false, "Unsupported page id", 0.0, details)
        }

        if (transport.PayloadUsedLength != BC_Config.HotPayloadUsedLength) {
            return BC_Interfaces.ValidationResult(false, "Unexpected payload length", 0.0, details)
        }

        headerCrc := BC_Protocol.Crc16(bytes, 1, 10)
        if (headerCrc != transport.HeaderCrc) {
            return BC_Interfaces.ValidationResult(false, "Header CRC mismatch", 0.0, details)
        }

        payloadCrc := BC_Protocol.Crc16(bytes, 13, 68)
        if (payloadCrc != transport.PayloadCrc) {
            return BC_Interfaces.ValidationResult(false, "Payload CRC mismatch", 0.0, details)
        }

        if (transport.SequenceEcho != transport.Sequence || transport.PageIdEcho != transport.PageId || transport.ProtocolEcho != transport.ProtocolVersion || transport.ProfileEcho != transport.ProfileId) {
            return BC_Interfaces.ValidationResult(false, "Footer echo mismatch", 0.0, details)
        }

        if (transport.TailMagic != 0xC3 || transport.TailWitness != 0x5A) {
            return BC_Interfaces.ValidationResult(false, "Footer tail mismatch", 0.0, details)
        }

        payloadByteIndex := transport.PayloadUsedLength + 1
        while (payloadByteIndex <= BC_Config.PayloadBytes) {
            expected := Mod(payloadByteIndex - 1, 2) = 0 ? 0xA5 : 0x5A
            actual := bytes[12 + payloadByteIndex]
            if (actual != expected) {
                return BC_Interfaces.ValidationResult(false, "Witness pattern mismatch", 0.0, details)
            }
            payloadByteIndex += 1
        }

        if ((transport.Flags0 & 0x01) = 0) {
            return BC_Interfaces.ValidationResult(false, "Player availability flag missing", 0.0, details)
        }

        details.HotPage := BC_Protocol.ExtractHotPage(bytes)
        contrast := detection.Contrast > 0 ? detection.Contrast : (detection.WhiteMean - detection.BlackMean)
        borderScore := Max(0.0, 1.0 - (detection.BorderErrors / Max(1, BC_Config.MaxBorderErrors)))
        contrastScore := Min(1.0, Max(0.0, contrast / 200.0))
        marginScore := Min(1.0, Max(0.0, decodeResult.MinMargin / 32.0))
        confidence := borderScore * contrastScore * marginScore
        details.Contrast := contrast

        return BC_Interfaces.ValidationResult(true, "Accepted", Round(confidence, 4), details)
    }
}

; end-of-script marker comment
