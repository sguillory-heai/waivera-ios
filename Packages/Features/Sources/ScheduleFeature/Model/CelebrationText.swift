import Foundation
import WaiveraDesign

/// The three labels a celebration has (07 §4 table). `name` falls back to "This employee".
public struct CelebrationText: Sendable, Hashable {
    public let compact: String
    public let full: String
    public let accessible: String

    public init(_ celebration: ScheduleCelebration, name: String? = nil) {
        let resolved = (name ?? celebration.displayName)?.trimmingCharacters(in: .whitespaces)
        let who =
            resolved.flatMap { $0.isEmpty ? nil : $0 } ?? ScheduleStrings.text("schedule.celebration.nameFallback")
        let years = celebration.years ?? 0
        switch celebration.kind {
        case .both:
            compact = ScheduleStrings.format("schedule.celebration.compact.both", years)
            full = ScheduleStrings.format("schedule.celebration.full.both", who, years)
            accessible = ScheduleStrings.format("schedule.celebration.a11y.both", who, years)
        case .birthday:
            compact = ScheduleStrings.text("schedule.celebration.compact.birthday")
            full = ScheduleStrings.format("schedule.celebration.full.birthday", who)
            accessible = ScheduleStrings.format("schedule.celebration.a11y.birthday", who)
        case .anniversary:
            compact = ScheduleStrings.format("schedule.celebration.compact.anniversary", years)
            full = ScheduleStrings.format("schedule.celebration.full.anniversary", who, years)
            accessible = ScheduleStrings.format("schedule.celebration.a11y.anniversary", who, years)
        }
    }

    /// Your own card: to you by first name, in the second person, as Today and Profile say it
    /// (Android `CelebrationText.self`, UI9-05). The first name is the display name's first word.
    public static func selfSentence(_ celebration: ScheduleCelebration) -> String {
        let first = celebration.displayName?
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .first
            .map(String.init)
        let years = celebration.years ?? 0
        switch (celebration.kind, first) {
        case (.both, let name?): return ScheduleStrings.format("schedule.celebration.self.both", name)
        case (.both, nil): return ScheduleStrings.text("schedule.celebration.self.unnamed.both")
        case (.birthday, let name?): return ScheduleStrings.format("schedule.celebration.self.birthday", name)
        case (.birthday, nil): return ScheduleStrings.text("schedule.celebration.self.unnamed.birthday")
        case (.anniversary, let name?):
            return ScheduleStrings.format("schedule.celebration.self.anniversary", name, years)
        case (.anniversary, nil):
            return ScheduleStrings.format("schedule.celebration.self.unnamed.anniversary", years)
        }
    }

    /// The emoji in the celebration card's own tile; the sentence carries none.
    public static func emoji(_ celebration: ScheduleCelebration) -> String {
        switch celebration.kind {
        case .birthday: ScheduleStrings.text("schedule.celebration.emoji.birthday")
        case .anniversary: ScheduleStrings.text("schedule.celebration.emoji.anniversary")
        case .both: ScheduleStrings.text("schedule.celebration.emoji.both")
        }
    }

    /// The agenda card's subtitle: "Birthday" or "5-year work anniversary".
    public static func kindLabel(_ celebration: ScheduleCelebration) -> String {
        let years = celebration.years ?? 0
        switch celebration.kind {
        case .birthday: return ScheduleStrings.text("schedule.milestone.birthday")
        case .anniversary: return ScheduleStrings.format("schedule.milestone.anniversary", years)
        case .both: return ScheduleStrings.format("schedule.milestone.both", years)
        }
    }
}

/// What the milestone badge on an avatar draws (07 §4 `MilestoneAvatar`).
public struct MilestoneBadge: Sendable, Hashable {
    public enum Glyph: Sendable, Hashable {
        case cake, award, party
    }

    public let glyph: Glyph
    /// Shown inside the anniversary badge only on avatars of 40pt or more.
    public let years: Int?
    public let size: Double
    public let accessibilityLabel: String

    public init(celebration: ScheduleCelebration, avatarSize: Double, name: String? = nil) {
        glyph =
            switch celebration.kind {
            case .birthday: .cake
            case .anniversary: .award
            case .both: .party
            }
        years =
            celebration.kind == .anniversary && avatarSize >= Double(ControlSize.milestoneYearsMinAvatar)
            ? celebration.years : nil
        size = Self.size(forAvatar: avatarSize)
        accessibilityLabel = CelebrationText(celebration, name: name).accessible
    }

    /// The badge's edge, as a share of the avatar's (Android `BADGE_RATIO`).
    public static let edgeRatio = 0.43
    /// The glyph, as a share of the badge's edge.
    public static let glyphRatio = 0.52
    /// The anniversary's year count, as a share of the badge's edge.
    public static let yearsRatio = 0.42
    /// How far the badge sits out past the avatar's top trailing corner, as shares of its edge.
    public static let offsetXRatio = 0.28
    public static let offsetYRatio = 0.25

    /// `max(17, round(size * 0.43))`.
    public static func size(forAvatar avatarSize: Double) -> Double {
        max(Double(ControlSize.milestoneBadgeMin), (avatarSize * edgeRatio).rounded())
    }

    /// The glyph's size inside the badge.
    public var glyphSize: Double { size * Self.glyphRatio }
    /// The year count's font size: fixed from the badge, since the badge is a fixed-size image.
    public var yearsFontSize: Double { size * Self.yearsRatio }
    /// The badge's offset from the avatar's top trailing corner, in whole points.
    public var offset: (x: Double, y: Double) {
        ((size * Self.offsetXRatio).rounded(), -(size * Self.offsetYRatio).rounded())
    }
}
