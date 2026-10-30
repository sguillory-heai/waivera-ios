import Foundation

/// Spacing scale in points, matching Android's `WaiveraSpacing` dp for dp. Layouts use these,
/// never literal numbers.
public enum Spacing {
    public static let none: CGFloat = 0
    public static let hairline: CGFloat = 1
    public static let xxSmall: CGFloat = 2
    public static let extraSmall: CGFloat = 4
    public static let small: CGFloat = 8
    /// 12pt. Android's `MediumSmall`.
    public static let smallPlus: CGFloat = 12
    public static let mediumSmall: CGFloat = 12
    public static let medium: CGFloat = 16
    /// 20pt. Android's `MediumLarge`.
    public static let mediumPlus: CGFloat = 20
    public static let large: CGFloat = 24
    public static let extraLarge: CGFloat = 32
    /// 48pt. Android's `XxLarge`.
    public static let huge: CGFloat = 48
    /// Horizontal screen gutter.
    public static let gutter: CGFloat = 16
    /// How far a rejected form moves to each side at the widest swing of its shake.
    public static let shakeAmplitude: CGFloat = 8
    /// How far a leading tile sits below the top of a tall row's content (v7, item 1).
    public static let leadingTileTop: CGFloat = 2
}

/// Corner radii (Android `WaiveraShapes`). iOS draws them with the continuous corner style.
public enum Radius {
    public static let chip: CGFloat = 8
    /// The soft rounded square behind every leading icon.
    public static let tile: CGFloat = 14
    public static let button: CGFloat = 12
    public static let card: CGFloat = 12
    public static let field: CGFloat = 16
    /// The large primary CTA.
    public static let cta: CGFloat = 16
    /// A content card on a tab screen's sheet, and a grouped card of rows.
    public static let sheetCard: CGFloat = 20
    public static let upNextCard: CGFloat = 22
    public static let statTile: CGFloat = 16
    /// The glass summary card on the hero.
    public static let heroCard: CGFloat = 24
    public static let timelinePanel: CGFloat = 18
    public static let timelineTrack: CGFloat = 10
    public static let timelineBlock: CGFloat = 6
    public static let filterChip: CGFloat = 12
    public static let segmentTrack: CGFloat = 16
    public static let segment: CGFloat = 12
    /// A modal sheet's top corners: the tab sheet's 28.
    public static let modalSheet: CGFloat = 28
    public static let snackbar: CGFloat = 16
    public static let countBadge: CGFloat = 8
    public static let listCard: CGFloat = 14
    public static let banner: CGFloat = 16
    public static let composer: CGFloat = 18
    public static let pill: CGFloat = 18
    public static let bubble: CGFloat = 20
    /// Brand moments: the sign-in hero band and celebration cards.
    public static let hero: CGFloat = 24
    public static let sheet: CGFloat = 24
    /// The predictive-back preview's corner on Android; iOS uses the system's own back swipe.
    public static let backPreview: CGFloat = 24
}

/// Fixed control and component sizes (Android `WaiveraSizes`). Text inside them still scales;
/// containers grow where text can wrap. Hit targets never drop below Apple's 44pt even when the
/// drawn shape is smaller.
public enum ControlSize {
    public static let minHitTarget: CGFloat = 44
    public static let buttonHeight: CGFloat = 48
    public static let ctaHeight: CGFloat = 56
    public static let fieldHeight: CGFloat = 56
    public static let fieldHalo: CGFloat = 4
    public static let fieldBorder: CGFloat = 1.5
    public static let icon: CGFloat = 24
    public static let iconSmall: CGFloat = 16
    /// Kept for existing call sites: a 20pt glyph.
    public static let smallIcon: CGFloat = 20
    public static let iconButton: CGFloat = 44
    /// A leading icon tile in rows.
    public static let iconTile: CGFloat = 40
    public static let iconTileSmall: CGFloat = 32
    public static let iconTileSmallGlyph: CGFloat = 20
    public static let fieldTile: CGFloat = 36
    public static let fieldTileGlyph: CGFloat = 18
    public static let fieldTileGap: CGFloat = 14
    public static let fieldDividerInset: CGFloat = fieldTile + fieldTileGap
    public static let emojiInTile: CGFloat = 22
    public static let emojiInTileSmall: CGFloat = 16
    public static let stateIconTile: CGFloat = 56
    public static let stateIconGlyph: CGFloat = 28
    public static let cardTile: CGFloat = 44
    public static let cardTileGlyph: CGFloat = 22
    public static let avatarSmall: CGFloat = 32
    public static let avatarMedium: CGFloat = 44
    public static let avatarLarge: CGFloat = 64
    public static let avatarHero: CGFloat = 96
    public static let brandMark: CGFloat = 48
    public static let brandLockup: CGFloat = 32
    public static let brandLockupHero: CGFloat = 44
    public static let illustration: CGFloat = 120
    public static let illustrationReward: CGFloat = 144
    public static let confettiPiece: CGFloat = 7
    /// Outline of a selected or "mine" pill (reactions).
    public static let selectedOutline: CGFloat = 1.5
    public static let milestoneBadgeMin: CGFloat = 17
    public static let milestoneBadgeBorder: CGFloat = 2
    /// Kept for existing call sites: the milestone badge's cut-out border. Avatars never get a ring.
    public static let milestoneRingWidth: CGFloat = milestoneBadgeBorder
    public static let milestoneYearsMinAvatar: CGFloat = 40
    public static let unreadDot: CGFloat = 10
    public static let badgeMinWidth: CGFloat = 20
    public static let navBadgeMin: CGFloat = 18
    public static let navBadgeRing: CGFloat = 2
    public static let navIndicatorWidth: CGFloat = 56
    public static let navIndicatorHeight: CGFloat = 32
    public static let progressSmall: CGFloat = 20
    public static let progressStroke: CGFloat = 2
    public static let progressLarge: CGFloat = 40
    public static let progressStrokeLarge: CGFloat = 4
    public static let listRowMinHeight: CGFloat = 56
    public static let ring: CGFloat = 96
    public static let ringStroke: CGFloat = 8
    public static let ringCompact: CGFloat = 72
    public static let ringStrokeCompact: CGFloat = 6
    public static let rewardRing: CGFloat = 132
    public static let rewardRingStroke: CGFloat = 12
    public static let rewardHalo: CGFloat = 26
    public static let rewardCheck: CGFloat = 52
    public static let statStackMaxWidth: CGFloat = 480
    public static let countBadgeHeight: CGFloat = 24
    public static let timelineTrack: CGFloat = 30
    public static let timelineBlockInset: CGFloat = 5
    public static let timelineNowLine: CGFloat = 2
    public static let timelineNowDot: CGFloat = 8
    public static let timelineTimeColumn: CGFloat = 68
    public static let timelineRailBlock: CGFloat = 6
    public static let quoteRule: CGFloat = 2
    public static let segmentMinHeight: CGFloat = 48
    /// A filter chip as drawn; its hit target stays at least `minHitTarget`.
    public static let filterChipHeight: CGFloat = 36
    public static let filterChipIcon: CGFloat = 18
    public static let skeletonLine: CGFloat = 14
    public static let sheetMaxWidth: CGFloat = 640
    /// Height of the fade that shows more content scrolls past an edge.
    public static let fadeEdge: CGFloat = 24
}

/// Elevation levels (Android `WaiveraElevation`). The app is mostly flat; borders separate surfaces
/// before shadows do.
public enum Elevation {
    public static let level0: CGFloat = 0
    public static let level1: CGFloat = 1
    public static let level2: CGFloat = 3
    public static let level3: CGFloat = 6
    /// A content card on a tab screen's sheet.
    public static let card: CGFloat = 2
    /// The primary button's violet glow.
    public static let buttonGlow: CGFloat = 6
    /// The raised secondary button's lift.
    public static let buttonRaise: CGFloat = 2
    /// Sheets and floating banners.
    public static let overlay: CGFloat = 8

    /// A SwiftUI shadow that reads like an Android elevation of `level`: blur radius equal to the
    /// elevation and the light from above, so the shadow falls half the elevation below.
    public static func shadow(for level: CGFloat) -> (radius: CGFloat, y: CGFloat) {
        (radius: level, y: level / 2)
    }
}

/// Opacity steps.
public enum Emphasis {
    public static let disabled: Double = 0.5
    /// Kept for existing call sites.
    public static let pressed: Double = 0.82
    /// Under Reduce Motion a press answers with a tint instead of a scale (Android M1-12).
    public static let pressedTint: Double = 0.10
    /// The tint while a long press arms under Reduce Motion.
    public static let longPressTint: Double = 0.16
    /// With motion on, rows and cards also tint lightly on touch-down (Android M3-08).
    public static let standardPressedTint: Double = 0.06
    public static let disabledSupporting: Double = 0.8
    public static let disabledCheckedTrack: Double = 0.38
    /// The busy spinner's track inside a filled button, as a share of the label's ink.
    public static let busyTrack: Double = 0.35
    /// The still ring that replaces the spinner under Reduce Motion.
    public static let staticRing: Double = 0.4
    /// Border alpha for tinted banners.
    public static let bannerBorder: Double = 0.4
    /// Fill alpha for tinted banners.
    public static let bannerWash: Double = 0.1
}

/// Avatar geometry. Every avatar is the same soft rounded square, never a circle and never bordered
/// (the owner's rule): corners are `max(8, round(size * 0.24))`.
public enum AvatarGeometry {
    public static let initialsRatio: CGFloat = 0.4
    public static let fallbackIconRatio: CGFloat = 0.5

    public static func cornerRadius(size: CGFloat) -> CGFloat {
        max(8, (size * 0.24).rounded())
    }

    public static func fallbackGlyphSize(size: CGFloat) -> CGFloat {
        (size * fallbackIconRatio).rounded()
    }

    public static func initialsFontSize(size: CGFloat) -> CGFloat {
        size * initialsRatio
    }

    /// Up to two initials: the first letter or digit of the first and last word, uppercased.
    /// Empty when the name has no letters or digits, and the view then shows a person glyph.
    public static func initials(for name: String) -> String {
        let words = name.split(whereSeparator: \.isWhitespace)
            .filter { word in word.contains { $0.isLetter || $0.isNumber } }
        guard let first = words.first else { return "" }
        let picked = words.count == 1 ? [first] : [first, words[words.count - 1]]
        return picked.compactMap { word in word.first { $0.isLetter || $0.isNumber } }
            .map { String($0).uppercased() }
            .joined()
    }
}

/// Count badges cap at `99+`.
public enum BadgeFormatter {
    public static let cap = 99

    /// `nil` hides the badge.
    public static func text(for count: Int) -> String? {
        guard count > 0 else { return nil }
        return count > cap ? "\(cap)+" : String(count)
    }
}

/// Typography details that are not a text style.
public enum TypographyMetrics {
    /// Letter spacing for uppercase eyebrow labels, in points at the eyebrow's 10.5pt size.
    public static let eyebrowTracking: CGFloat = 1
}

/// Durations for transient feedback.
public enum FeedbackTiming {
    /// Undo snackbar lifetime.
    public static let undoToast: Double = 4
    /// Undo snackbar lifetime while VoiceOver runs, so the action can be reached.
    public static let undoToastAccessible: Double = 10
    /// In-app message banner lifetime.
    public static let inAppBanner: Double = 4.5
    /// Short confirmation pill such as "Bookmark saved".
    public static let confirmationPill: Double = 1.8
}

extension SkeletonTiming {
    /// Time a shown skeleton must still stay up after loading ended, given how long it has been visible.
    public func remainingVisible(shownFor: Double) -> Double {
        max(0, minimumVisible - shownFor)
    }
}

/// Send/sync state of an optimistic item (message, status change).
public enum SyncState: Equatable, Sendable {
    case synced
    case pending
    case failed
}
