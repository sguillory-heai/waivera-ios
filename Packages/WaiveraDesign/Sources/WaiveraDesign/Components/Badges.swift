#if canImport(UIKit)
    import SwiftUI

    /// A count pill, capped at `99+` and hidden at zero. `attention` (the default) is something
    /// waiting on the person, solid rose with white; `info` is a plain total, a neutral chip. It
    /// pops in when a count arrives, pops on each change and shrinks away at zero.
    public struct CountBadge: View {
        private let count: Int
        private let tone: CountTone

        public init(count: Int, tone: CountTone = .attention) {
            self.count = count
            self.tone = tone
        }

        public var body: some View {
            PopVisibility(isVisible: count > 0) {
                CountPill(
                    text: BadgeFormatter.text(for: count) ?? "",
                    accessibilityText: DesignStrings.unreadCount(count),
                    tone: tone
                )
            }
        }
    }

    /// The count pill with caller-made copy ("30+" when only part of a feed is loaded).
    public struct CountPill: View {
        private let text: String
        private let accessibilityText: String
        private let tone: CountTone

        public init(text: String, accessibilityText: String, tone: CountTone = .attention) {
            self.text = text
            self.accessibilityText = accessibilityText
            self.tone = tone
        }

        public var body: some View {
            Text(text)
                .waiveraTextStyle(.badge)
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(tone.inkColor)
                .padding(.horizontal, Spacing.extraSmall + Spacing.xxSmall)
                .frame(minWidth: ControlSize.badgeMinWidth, minHeight: ControlSize.badgeMinWidth)
                .background(tone.fillColor, in: Capsule())
                .popOnChange(of: text)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(accessibilityText))
        }
    }

    public enum BadgeTone: Sendable {
        case accent
        case neutral
        case success
        case warning
        case danger

        var status: StatusTone {
            switch self {
            case .accent: .accent
            case .neutral: .neutral
            case .success: .success
            case .warning: .warning
            case .danger: .danger
            }
        }
    }

    /// A short status label such as "Saved" or "Thread reply". Always one line; place several in
    /// a wrapping layout so whole labels wrap. Free text that can be wider than its row ends in "…".
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
                        .imageScale(.small)
                        .accessibilityHidden(true)
                }
                Text(title)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .waiveraTextStyle(.badge)
            .foregroundStyle(tone.status.inkColor)
            .padding(.horizontal, Spacing.small)
            .padding(.vertical, Spacing.xxSmall)
            .background(tone.status.containerColor, in: RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
            .accessibilityElement(children: .combine)
        }
    }

    /// An unread dot in the attention rose, with a spoken label so unread is not colour-only.
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

    private struct BadgeGallery: View {
        var body: some View {
            VStack(alignment: .leading, spacing: Spacing.mediumSmall) {
                HStack(spacing: Spacing.small) {
                    CountBadge(count: 3)
                    CountBadge(count: 120)
                    CountBadge(count: 14, tone: .info)
                    UnreadDot(accessibilityLabel: "Unread")
                }
                HStack(spacing: Spacing.small) {
                    StatusBadge("Saved", systemImage: "bookmark.fill")
                    StatusBadge("Thread reply", tone: .neutral)
                    StatusBadge("Pending", tone: .warning)
                    StatusBadge("Failed", tone: .danger)
                }
            }
            .padding(Spacing.medium)
            .background(Palette.background)
        }
    }

    #Preview("Light") { BadgeGallery() }
    #Preview("Dark") { BadgeGallery().preferredColorScheme(.dark) }
    #Preview("AX5") { BadgeGallery().dynamicTypeSize(.accessibility5) }
#endif
