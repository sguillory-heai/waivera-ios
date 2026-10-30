import Foundation
import WaiveraData
import WaiveraDesign

/// Where my own unconfirmed message's line is (Android `FooterPhase`): going out but not saying
/// so yet, going out, waiting for the connection, or not sent.
enum PendingFooterPhase: Hashable, Sendable {
    /// Sending, inside the first beat: the slot keeps its height but shows nothing, so a good
    /// connection goes straight to the sent line without flashing "Sending…" (M1-09).
    case quiet
    case sending
    /// Queued while offline: no quick ack will follow, so it says so at once.
    case queued
    /// "Not sent", with Retry, Edit and Discard.
    case failed

    /// "Sending…" shows only once `MotionTiming.sendingLabelDelay` has passed; a failure and a
    /// queued send show at once.
    init(_ state: OutgoingMessage.State, sendingLabelDue: Bool) {
        switch state {
        case .failed: self = .failed
        case .queued: self = .queued
        case .sending: self = sendingLabelDue ? .sending : .quiet
        }
    }

    /// How long a send stays quiet before it says "Sending…".
    static let sendingLabelDelay = MotionTiming.sendingLabelDelay

    var copyKey: String? {
        switch self {
        case .quiet: nil
        case .sending: "sending"
        case .queued: "queued"
        case .failed: "failed"
        }
    }
}
