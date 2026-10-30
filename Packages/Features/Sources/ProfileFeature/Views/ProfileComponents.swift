#if canImport(UIKit)
    import SwiftUI
    import UIKit
    import WaiveraData
    import WaiveraDesign

    /// A titled card holding detail rows.
    struct SectionCard<Content: View>: View {
        let title: String
        @ViewBuilder let content: Content

        var body: some View {
            VStack(alignment: .leading, spacing: Spacing.small) {
                Text(title)
                    .font(WaiveraFont.sectionTitle)
                    .foregroundStyle(Palette.text)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.horizontal, Spacing.medium)
                VStack(alignment: .leading, spacing: 0) {
                    content
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                        .strokeBorder(Palette.border, lineWidth: Spacing.hairline)
                )
            }
        }
    }

    /// An uppercase label over a value. A missing value shows "—" and is spoken as "not provided".
    struct DetailRow: View {
        let label: String
        let value: String?

        var body: some View {
            VStack(alignment: .leading, spacing: Spacing.extraSmall) {
                Text(label.uppercased())
                    .font(WaiveraFont.eyebrow)
                    .tracking(TypographyMetrics.eyebrowTracking)
                    .foregroundStyle(Palette.textSecondary)
                Text(value ?? ProfileStrings.missing)
                    .font(WaiveraFont.body)
                    .foregroundStyle(value == nil ? Palette.textSecondary : Palette.text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, Spacing.smallPlus)
            .padding(.horizontal, Spacing.medium)
            .frame(minHeight: ControlSize.minHitTarget)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(label))
            .accessibilityValue(Text(value ?? ProfileStrings.missingSpoken))
        }
    }

    /// A hairline between rows inside a `SectionCard`.
    struct RowDivider: View {
        var body: some View {
            Divider()
                .overlay(Palette.border)
                .padding(.leading, Spacing.medium)
        }
    }

    /// A person's avatar loaded through the avatar cache, with the milestone ring when they are
    /// celebrating today. Initials show until (or instead of) the image.
    struct PersonAvatar: View {
        @Environment(\.dataEnvironment) private var data
        let userID: String?
        let name: String
        var size: CGFloat = ControlSize.avatarMedium
        var celebration: Celebration?

        @State private var image: Image?

        var body: some View {
            AvatarView(
                name: name,
                image: image,
                size: size,
                milestoneLabel: celebration.map(ProfileStrings.celebrationCompact)
            )
            .task(id: userID) {
                guard let userID, let data else { return }
                guard let bytes = await data.avatars.avatar(userId: userID), let uiImage = UIImage(data: bytes) else {
                    return
                }
                image = Image(uiImage: uiImage)
            }
        }
    }

    /// The inline "showing saved data" notice after a failed refresh; the content stays.
    struct RefreshFailedNotice: View {
        let message: String
        let onRetry: () -> Void

        var body: some View {
            BannerView(.error, message: message, actionTitle: ProfileStrings.tryAgain, action: onRetry)
        }
    }

    /// A time off or files card in its own load state: a skeleton while it loads, a Retry card
    /// when it failed with nothing to show, else the card itself.
    struct ProfileSectionSlot<Content: View>: View {
        let display: ProfileSections.Display
        let title: String
        let onRetry: () -> Void
        @ViewBuilder let content: () -> Content

        var body: some View {
            switch display {
            case .hidden:
                EmptyView()
            case .loading:
                SectionCard(title: title) {
                    VStack(alignment: .leading, spacing: Spacing.smallPlus) {
                        SkeletonBlock()
                        SkeletonBlock().padding(.trailing, Spacing.huge)
                    }
                    .padding(Spacing.medium)
                    .accessibilityElement()
                    .accessibilityLabel(Text(ProfileStrings.refreshing))
                }
            case .failed:
                SectionCard(title: title) {
                    BannerView(
                        .error,
                        message: ProfileStrings.sectionFailed,
                        actionTitle: ProfileStrings.tryAgain,
                        action: onRetry
                    )
                    .padding(Spacing.small)
                }
            case .content:
                content()
            }
        }
    }

    /// A toolbar refresh button that turns into a spinner while a refresh runs.
    struct RefreshToolbarButton: View {
        let title: String
        let busyTitle: String
        let isRefreshing: Bool
        let action: () -> Void

        var body: some View {
            if isRefreshing {
                ProgressView()
                    .tint(Palette.accent)
                    .frame(width: ControlSize.minHitTarget, height: ControlSize.minHitTarget)
                    .accessibilityLabel(Text(busyTitle))
            } else {
                Button(action: action) {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: ControlSize.minHitTarget, height: ControlSize.minHitTarget)
                        .contentShape(Rectangle())
                }
                .foregroundStyle(Palette.accent)
                .accessibilityLabel(Text(title))
            }
        }
    }

    /// The skeleton for the profile and person screens: a hero block and two cards.
    struct ProfileSkeleton: View {
        var body: some View {
            VStack(alignment: .leading, spacing: Spacing.large) {
                HStack(spacing: Spacing.medium) {
                    SkeletonBlock(
                        width: ControlSize.avatarLarge,
                        height: ControlSize.avatarLarge,
                        cornerRadius: ControlSize.avatarLarge / 2
                    )
                    VStack(alignment: .leading, spacing: Spacing.small) {
                        SkeletonBlock()
                        SkeletonBlock().padding(.trailing, Spacing.huge)
                    }
                }
                ForEach(0..<2, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: Spacing.smallPlus) {
                        SkeletonBlock().padding(.trailing, Spacing.huge * 2)
                        SkeletonBlock(height: ControlSize.buttonHeight * 2, cornerRadius: Radius.card)
                    }
                }
            }
            .padding(Spacing.medium)
            .accessibilityElement()
            .accessibilityLabel(Text(ProfileStrings.refreshing))
        }
    }

    extension TimeOffRules.Tone {
        var badgeTone: BadgeTone {
            switch self {
            case .warning: .warning
            case .danger: .danger
            case .success: .success
            }
        }
    }
#endif
