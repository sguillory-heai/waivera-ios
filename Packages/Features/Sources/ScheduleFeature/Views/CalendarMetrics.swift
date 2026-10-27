#if canImport(UIKit)
    import SwiftUI
    import WaiveraDesign

    /// Calendar-only sizes from 07 §1 and §3 that the design system has no token for yet
    /// (docs/requests/schedule.md item 5 asks to promote them). Everything else uses shared tokens.
    enum CalendarMetrics {
        /// The event and celebration dots under a day number.
        static let dot: CGFloat = 5
        static let dotGap: CGFloat = 3
        /// The "today" ring; present but clear on other days so selection never shifts layout.
        static let todayBorder: CGFloat = 1.5
        /// The owner-colour bar on an event card.
        static let eventBar: CGFloat = 4
        static let eventCardMinHeight: CGFloat = 66
        static let weekCellMinHeight: CGFloat = 76
        /// Avatar sizes from the 07 §4 usage list.
        static let agendaAvatar: CGFloat = 40
        static let organizerAvatar: CGFloat = 32
        static let attendeeAvatar: CGFloat = 34
        /// Month cells stop growing past this text size so seven columns still fit; the agenda
        /// and each cell's spoken label carry the same information at every size.
        static let gridMaxTypeSize: DynamicTypeSize = .accessibility1
    }

    extension Color {
        /// A server-sent owner colour (already validated by `ScheduleCopy.ownerColor`).
        init(serverColor color: RGBColor) {
            self.init(.sRGB, red: color.red, green: color.green, blue: color.blue, opacity: color.alpha)
        }
    }
#endif
