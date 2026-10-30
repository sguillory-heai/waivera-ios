#if canImport(UIKit)
    import SwiftUI
    import WaiveraDesign

    /// Calendar-only sizes, mirroring Android's `CalendarSizes` (feature/calendar `CalendarTokens.kt`).
    /// Only the schedule grid and agenda use them, so they stay in the feature as on Android;
    /// everything else uses shared tokens.
    enum CalendarMetrics {
        /// The event dots under a day number.
        static let dot: CGFloat = 5
        static let dotGap: CGFloat = 3
        /// The celebration diamond, a little larger than a dot so both read at the same weight.
        static let milestoneDot: CGFloat = 6
        /// The selected day's tinted rounded square (v5: 38 in the month grid, 40 in the week strip).
        static let daySquare: CGFloat = 38
        static let daySquareLarge: CGFloat = 40
        /// Today's short dash under its number (v5 decision 4, option C), in its own slot.
        static let todayDashWidth: CGFloat = 14
        static let todayDashHeight: CGFloat = 3
        static let todayDashGap: CGFloat = 2
        static let todayDashInset: CGFloat = 4
        /// The owner-colour bar on the leading edge of an event card.
        static let eventBar: CGFloat = 4
        /// The line of today's "Now" divider.
        static let nowLine: CGFloat = 1.5
        static let eventCardMinHeight: CGFloat = 66
        static let weekCellMinHeight: CGFloat = 76
        /// The Day rail's tone block beside a card, and its short form above a card at large text.
        static let railBlockTall: CGFloat = 28
        static let railBlockShort: CGFloat = 16
        static let railTick: CGFloat = 1
        static let organizerAvatar: CGFloat = 32
        static let attendeeAvatar: CGFloat = 34
    }

    extension Color {
        /// A server-sent owner colour (already validated by `ScheduleCopy.ownerColor`).
        init(serverColor color: RGBColor) {
            self.init(.sRGB, red: color.red, green: color.green, blue: color.blue, opacity: color.alpha)
        }
    }

    extension AgendaRailTone {
        /// Concept B's "Your day" block colours.
        var color: Color {
            switch self {
            case .teal: Color(rgb: RGBColor(hex: BrandPalette.timelineTeal))
            case .gold: Color(rgb: RGBColor(hex: BrandPalette.timelineGold))
            case .violet: Color(rgb: RGBColor(hex: BrandPalette.timelineViolet))
            }
        }
    }
#endif
