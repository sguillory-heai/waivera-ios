#if canImport(UIKit)
    import SwiftUI
    import WaiveraDesign

    /// A birthday or anniversary on the day: a small brand moment on the celebration wash. The
    /// person's plain avatar, the sentence (the name keeps to two lines), and the emoji once, in
    /// its own tile. "Send wishes" opens a direct chat; it is hidden on your own card and sits on
    /// a row of its own, on one line, so the two words never wrap inside the button (UI10-05).
    /// At large text the avatar goes above the sentence, which takes the full width.
    struct MilestoneCard: View {
        let row: AgendaRow
        let celebration: ScheduleCelebration
        let showsWishes: Bool
        let isOpening: Bool
        let onSendWishes: () -> Void

        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        var body: some View {
            BrandSurface {
                VStack(alignment: .leading, spacing: Spacing.mediumSmall) {
                    Group {
                        if dynamicTypeSize.isLargeText {
                            VStack(alignment: .leading, spacing: Spacing.mediumSmall) {
                                HStack(alignment: .top) {
                                    avatar
                                    Spacer(minLength: Spacing.small)
                                    emoji
                                }
                                sentence
                            }
                        } else {
                            LeadingPinLayout(
                                spacing: Spacing.mediumSmall,
                                standardHeight: LeadingPinLayout.standardHeight(
                                    title: .titleSmall,
                                    subtitle: .titleSmall,
                                    dynamicTypeSize: dynamicTypeSize
                                )
                            ) {
                                avatar
                                HStack(spacing: Spacing.mediumSmall) {
                                    sentence
                                    emoji
                                }
                                .leadingPinContent()
                            }
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(row.title))
                    if showsWishes {
                        WaiveraButton(
                            ScheduleStrings.text("schedule.sendWishes"),
                            variant: .tonalOnWash,
                            systemImage: "bubble.left",
                            isLoading: isOpening,
                            loadingTitle: ScheduleStrings.text("schedule.openingChat"),
                            fillsWidth: false,
                            action: onSendWishes
                        )
                        .lineLimit(1)
                        .accessibilityLabel(Text(ScheduleStrings.format("schedule.sendWishes.a11y", name)))
                    }
                }
            }
        }

        private var name: String {
            ScheduleCopy.nonBlank(celebration.displayName)
                ?? ScheduleStrings.text("schedule.celebration.nameFallback")
        }

        private var avatar: some View {
            MilestoneAvatarView(
                name: name,
                userId: celebration.userId,
                celebration: nil,
                size: ControlSize.avatarMedium
            )
            .accessibilityHidden(true)
        }

        private var sentence: some View {
            NameText(row.title, style: .titleSmall, lines: NameLines.celebration)
                .foregroundStyle(Palette.text)
                .frame(maxWidth: .infinity, alignment: .leading)
        }

        @ViewBuilder private var emoji: some View {
            if let emoji = row.emoji {
                EmojiTile(emoji).accessibilityHidden(true)
            }
        }
    }
#endif
