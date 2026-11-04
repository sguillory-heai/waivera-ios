#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    /// The glyph and tint for each kind of notification: one meaning per tint.
    enum NoticeTile {
        static func of(_ kind: NoticeKind) -> (systemImage: String, tone: TileTone) {
            switch kind {
            case .taskAssigned: ("checklist", .brand)
            case .taskActivity: ("text.bubble", .brand)
            case .approval: ("checkmark.seal", .amber)
            case .signature: ("signature", .amber)
            case .survey: ("list.clipboard", .teal)
            case .meeting: ("calendar", .teal)
            case .timeOff: ("sun.max", .teal)
            case .other: ("bell", .neutral)
            }
        }
    }
#endif
