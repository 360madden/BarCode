/*
script name: DesktopAHK/State.ahk
version: 0.2.0
purpose: Normalizes accepted or rejected reader-smoke decode results into a simple latest-frame state object.
dependencies: DesktopAHK/Validate.ahk
important assumptions: Tracks one latest frame only and surfaces parsed transport/page details when validation accepts.
protocol version: BC-Strip/1
framework module role: App-facing state
character count note: Character count not precomputed; measure with tooling if needed.
*/

class BC_State {
    static Latest := {}

    static Update(validationResult) {
        details := validationResult.Details
        transport := details.HasOwnProp("Transport") ? details.Transport : {}
        hotPage := details.HasOwnProp("HotPage") ? details.HotPage : {}

        BC_State.Latest := {
            TimestampUtc: A_NowUTC,
            Accepted: validationResult.IsAccepted,
            Reason: validationResult.Reason,
            Confidence: validationResult.Confidence,
            Sequence: transport.HasOwnProp("Sequence") ? transport.Sequence : "",
            PageId: transport.HasOwnProp("PageId") ? transport.PageId : "",
            PayloadUsedLength: transport.HasOwnProp("PayloadUsedLength") ? transport.PayloadUsedLength : "",
            HealthCurrent: hotPage.HasOwnProp("HealthCurrent") ? hotPage.HealthCurrent : "",
            HealthMax: hotPage.HasOwnProp("HealthMax") ? hotPage.HealthMax : "",
            ResourceCurrent: hotPage.HasOwnProp("ResourceCurrent") ? hotPage.ResourceCurrent : "",
            ResourceMax: hotPage.HasOwnProp("ResourceMax") ? hotPage.ResourceMax : "",
            CastProgressQ15: hotPage.HasOwnProp("CastProgressQ15") ? hotPage.CastProgressQ15 : "",
            Details: details
        }
        return BC_State.Latest
    }
}

; end-of-script marker comment
