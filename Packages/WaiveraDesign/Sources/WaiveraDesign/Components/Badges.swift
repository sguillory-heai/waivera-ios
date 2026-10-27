#if canImport(UIKit)
    import SwiftUI

    /// Unread count badge, capped at `99+`. Hidden when the count is zero.
    public struct CountBadge: View {
        private let count: Int

        public init(count: Int) {
            self.count = count
        }

        public var body: some View {
            if let text = BadgeFormatter.text(for: count) {
                Text(text)
                    .font(WaiveraFont.badge)
                    .foregroundStyle(Palette.onDanger)
                    .padding(.horizontal, Spacing.extraSmall)
                    .frame(minWidth: ControlSize.badgeMinWidth, minHeight: ControlSize.badgeMinWidth)
                    .background(Palette.danger, in: Capsule())
                    .accessibilityLabel(Text(DesignStrings.unreadCount(count)))
            }
        }
    }

    public enum BadgeTone: Sendable {
        case accent
        case neutral
        case success
        case warning
        case danger
    }

    /// A small text label such as "Saved" or "Thread reply".
    public struct StatusBadge: View {
        private let title: String
        private let tone: BadgeTone
        private let systemImage: String?

        public init(_ title: String, tone: BadgeTone = .accent, systemImage: String? = nil) {
            self.title = title
            self.tone = tone
            self.systemImage = systemImage
        }

        public var body: some View {
            HStack(spacing: Spacing.extraSmall) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .accessibilityHidden(true)
                }
                Text(title)
            }
            .font(WaiveraFont.badge)
            .foregroundStyle(tint)
            .padding(.horizontal, Spacing.small)
            .padding(.vertical, Spacing.extraSmall)
            .background(tint.opacity(Emphasis.bannerWash), in: Capsule())
            .accessibilityElement(children: .combine)
        }

        private var tint: Color {
            switch tone {
            case .accent: Palette.accent
            case .neutral: Palette.textSecondary
            case .success: Palette.success
            case .warning: Palette.warning
            case .danger: Palette.danger
            }
        }
    }

    /// An unread dot with a spoken label, so unread state is not colour-only.
    public struct UnreadDot: View {
        private let accessibilityText: String

        public init(accessibilityLabel: String) {
            accessibilityText = accessibilityLabel
        }

        public var body: some View {
            Circle()
                .fill(Palette.unread)
                .frame(width: ControlSize.unreadDot, height: ControlSize.unreadDot)
                .accessibilityLabel(Text(accessibilityText))
        }
    }

    /// A 48pt rounded tile holding an SF Symbol, used by rows and state views.
    public struct IconTile: View {
        private let systemImage: String
        private let tint: Color

        public init(systemImage: String, tint: Color = Palette.accent) {
            self.systemImage = systemImage
            self.tint = tint
        }

        public var body: some View {
            Image(systemName: systemImage)
                .font(WaiveraFont.sectionTitle)
                .foregroundStyle(tint)
                .frame(width: ControlSize.iconTile, height: ControlSize.iconTile)
                .background(Palette.accentSoft, in: RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
                .accessibilityHidden(true)
        }
    }

    private struct BadgeGallery: View {
        var body: some View {
            VStack(alignment: .leading, spacing: Spacing.smallPlus) {
                HStack(spacing: Spacing.small) {
                    CountBadge(count: 3)
                    CountBadge(count: 120)
                    UnreadDot(accessibilityLabel: "Unread")
                }
                HStack(spacing: Spacing.small) {
                    StatusBadge("Saved", systemImage: "bookmark.fill")
                    StatusBadge("Thread reply", tone: .neutral)
                    StatusBadge("Pending", tone: .warning)
                }
                IconTile(systemImage: "calendar")
            }
            .padding(Spacing.medium)
            .background(Palette.background)
        }
    }

    #Preview("Light") { BadgeGallery() }
    #Preview("Dark") { BadgeGallery().preferredColorScheme(.dark) }
    #Preview("AX XXXL") { BadgeGallery().dynamicTypeSize(.accessibility5) }
#endif
