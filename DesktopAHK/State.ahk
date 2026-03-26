/*
script name: DesktopAHK/State.ahk
version: 0.1.0
purpose: Normalizes accepted or rejected phase 1 decode results into a simple state object.
dependencies: DesktopAHK/Validate.ahk
important assumptions: Phase 1 tracks a single latest frame state only.
protocol version: BC-Strip/1
framework module role: App-facing state
character count note: Character count not precomputed; measure with tooling if needed.
*/

class BC_State {
    static Latest := {}

    static Update(validationResult) {
        BC_State.Latest := {
            TimestampUtc: A_NowUTC,
            Accepted: validationResult.IsAccepted,
            Reason: validationResult.Reason,
            Confidence: validationResult.Confidence,
            Details: validationResult.Details
        }
        return BC_State.Latest
    }
}

; end-of-script marker comment
