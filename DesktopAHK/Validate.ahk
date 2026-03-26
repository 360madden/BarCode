/*
script name: DesktopAHK/Validate.ahk
version: 0.1.0
purpose: Applies transport integrity checks and confidence gating to decoded BC-Strip/1 frames.
dependencies: DesktopAHK/Config.ahk, DesktopAHK/Interfaces.ahk, DesktopAHK/Protocol.ahk
important assumptions: Rejects on any structural mismatch; phase 1 does not attempt error correction.
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
            MinMargin: decodeResult.MinMargin
        }

        if (bytes.Length != 76) {
            return BC_Interfaces.ValidationResult(false, "Unexpected byte count", 0.0, details)
        }

        if (detection.BorderErrors != 0) {
            return BC_Interfaces.ValidationResult(false, "Border validation failed", 0.0, details)
        }

        if (bytes[1] != 0x42 || bytes[2] != 0x43) {
            return BC_Interfaces.ValidationResult(false, "Sync mismatch", 0.0, details)
        }

        if (bytes[3] != BC_Config.ProtocolVersion || bytes[4] != BC_Config.LayoutId || bytes[5] != BC_Config.ProfileId || bytes[6] != BC_Config.SchemaId) {
            return BC_Interfaces.ValidationResult(false, "Header identity mismatch", 0.0, details)
        }

        if (bytes[7] != BC_Config.StaticSequence || bytes[9] != BC_Config.StaticPayloadLength) {
            return BC_Interfaces.ValidationResult(false, "Header sequence or length mismatch", 0.0, details)
        }

        headerCrc := BC_Protocol.Crc16(bytes, 1, 10)
        observedHeaderCrc := ((bytes[11] << 8) | bytes[12])
        if (headerCrc != observedHeaderCrc) {
            return BC_Interfaces.ValidationResult(false, "Header CRC mismatch", 0.0, details)
        }

        payload := []
        Loop BC_Config.StaticPayloadLength {
            payload.Push(bytes[12 + A_Index])
        }
        payloadCrc := BC_Protocol.Crc16(payload, 1, payload.Length)
        observedPayloadCrc := ((bytes[37] << 8) | bytes[38])
        if (payloadCrc != observedPayloadCrc) {
            return BC_Interfaces.ValidationResult(false, "Payload CRC mismatch", 0.0, details)
        }

        if (bytes[39] != 0x42 || bytes[40] != 0x43 || bytes[41] != BC_Config.ProtocolVersion || bytes[42] != BC_Config.StaticSequence || bytes[43] != BC_Config.StaticPayloadLength) {
            return BC_Interfaces.ValidationResult(false, "Footer duplicate mismatch", 0.0, details)
        }

        witnessOffset := 45
        Loop 32 {
            expected := Mod(A_Index - 1, 2) = 0 ? 0xA5 : 0x5A
            if (bytes[witnessOffset + A_Index - 1] != expected) {
                return BC_Interfaces.ValidationResult(false, "Witness pattern mismatch", 0.0, details)
            }
        }

        contrast := detection.WhiteMean - detection.BlackMean
        confidence := contrast <= 0 ? 0.0 : Min(1.0, Max(0.0, (contrast / 255.0))) * Min(1.0, decodeResult.MinMargin / 32.0)
        details.Contrast := contrast
        return BC_Interfaces.ValidationResult(true, "Accepted", Round(confidence, 4), details)
    }
}

; end-of-script marker comment
