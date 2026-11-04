#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    /// The glyph and tint for each kind of notification, the same as Android's `NoticeKind.style`.
    enum NoticeTile {
        static func of(_ kind: NoticeKind) -> (systemImage: String, tone: TileTone) {
            switch kind {
            case .taskAssigned: ("list.clipboard", .amber)
            case .taskActivity: ("waveform.path.ecg", .amber)
            case .approval: ("list.clipboard", .rose)
            case .meeting: ("calendar", .brand)
            case .signature: ("signature", .rose)
            case .survey: ("megaphone", .danger)
            case .timeOff: ("checkmark", .teal)
            case .other: ("bell", .brand)
            }
        }
    }
#endif
