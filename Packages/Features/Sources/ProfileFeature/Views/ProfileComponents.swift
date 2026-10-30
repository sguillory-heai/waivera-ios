#if canImport(UIKit)
    import SwiftUI
    import UIKit
    import WaiveraData
    import WaiveraDesign

    /// A titled group, as every grouped list is set: the section header above one surface card.
    struct SectionCard<Content: View>: View {
        let title: String?
        @ViewBuilder let content: Content

        init(title: String? = nil, @ViewBuilder content: () -> Content) {
            self.title = title
            self.content = content()
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                if let title { SectionHeader(title) }
                CardGroup {
                    VStack(alignment: .leading, spacing: 0) {
                        content
                    }
                    .padding(.vertical, Spacing.extraSmall)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    /// One read-only field on its leading brand tile: a muted label over a bold value, so the
    /// value carries the row. A missing value shows "—" and is spoken as "not provided"; the
    /// tile is decoration. The tile centres on a two-line row and pins to the first line once
    /// the value wraps.
    struct DetailRow: View {
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize
        let label: String
        let value: String?
        let systemImage: String

        var body: some View {
            let shown = value?.nonBlank
            LeadingPinLayout(spacing: ControlSize.fieldTileGap, standardHeight: standardHeight) {
                IconTile(
                    systemImage: systemImage,
                    tone: .brand,
                    size: ControlSize.fieldTile,
                    glyphSize: ControlSize.fieldTileGlyph
                )
                VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                    Text(label)
                        .waiveraTextStyle(.fieldLabel)
                        .foregroundStyle(Palette.textSecondary)
                    Text(shown ?? ProfileStrings.missing)
                        .waiveraTextStyle(.fieldValue)
                        .foregroundStyle(Palette.text)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .leadingPinContent()
            }
            .padding(.vertical, Spacing.small)
            .padding(.horizontal, Spacing.medium)
            .frame(minHeight: ControlSize.minHitTarget)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(label))
            .accessibilityValue(Text(shown ?? ProfileStrings.missingSpoken))
        }

        private var standardHeight: CGFloat {
            LeadingPinLayout.standardHeight(
                title: .fieldLabel,
                subtitle: .fieldValue,
                gap: Spacing.xxSmall,
                dynamicTypeSize: dynamicTypeSize
            )
        }
    }

    /// A hairline between rows inside a `SectionCard`. Between field rows it starts under the
    /// label, not under the tile.
    struct RowDivider: View {
        var underTile = false

        var body: some View {
            Divider()
                .overlay(Palette.border)
                .padding(.leading, Spacing.medium + (underTile ? ControlSize.fieldDividerInset : 0))
                .padding(.trailing, underTile ? Spacing.medium : 0)
        }
    }

    /// Today's celebration on a profile hero (Android `WaiveraHeroCelebration`): the emoji beside
    /// the sentence on the hero's glass tile, in the hero inks. The sentence keeps to two lines.
    struct HeroCelebrationNote: View {
        let emoji: String
        let text: String

        var body: some View {
            HStack(spacing: Spacing.small) {
                Text(emoji)
                    .waiveraTextStyle(.heroTitle)
                    .accessibilityHidden(true)
                NameText(text, style: .titleSmall, lines: NameLines.celebration)
                    .foregroundStyle(HeroPalette.onHeader)
            }
            .padding(.horizontal, Spacing.mediumSmall)
            .padding(.vertical, Spacing.small)
            .background(HeroPalette.tile, in: RoundedRectangle(cornerRadius: Radius.statTile, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.statTile, style: .continuous)
                    .strokeBorder(HeroPalette.tileBorder, lineWidth: Spacing.hairline)
            )
            .accessibilityElement(children: .combine)
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
                    // The same soft square as the avatar it stands in for, never a circle.
                    SkeletonBlock(
                        width: ControlSize.avatarLarge,
                        height: ControlSize.avatarLarge,
                        cornerRadius: AvatarGeometry.cornerRadius(size: ControlSize.avatarLarge)
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
