#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    /// "Activity" with the unread count across every loaded page, Mark all read and, on Today,
    /// See all.
    struct ActivityHeader: View {
        let section: ActivitySection
        var title: String = TodayStrings.text("today.section.activity")
        var onSeeAll: (() -> Void)?
        let onMarkAllRead: () -> Void

        var body: some View {
            TodaySectionHeader(title: title) {
                if section.unreadCount > 0 {
                    StatusBadge(
                        section.unreadIsLowerBound
                            ? TodayStrings.format("today.activity.lowerBound", String(section.unreadCount))
                            : BadgeFormatter.text(for: section.unreadCount) ?? "",
                        tone: .accent
                    )
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(
                        Text(TodayStrings.unreadUpdates(section.unreadCount, lowerBound: section.unreadIsLowerBound))
                    )
                }
                if section.unreadCount > 0 || section.isMarkingAllRead {
                    TodayTextButton(
                        title: TodayStrings.text("today.activity.markAllRead"),
                        systemImage: "checkmark.circle",
                        isLoading: section.isMarkingAllRead,
                        action: onMarkAllRead
                    )
                    .accessibilityIdentifier("today.activity.markAllRead")
                }
                if let onSeeAll {
                    TodayTextButton(
                        title: TodayStrings.text("today.seeAllActivity"),
                        hint: TodayStrings.text("today.seeAllActivity.hint"),
                        action: onSeeAll
                    )
                    .accessibilityIdentifier("today.activity.seeAll")
                }
            }
        }
    }

    /// Type chips (All, Mentions, Replies, Reactions) and the Unread toggle; they combine with AND.
    struct ActivityFilterBar: View {
        let filter: ActivityFilter
        let unreadOnly: Bool
        let onFilter: (ActivityFilter) -> Void
        let onToggleUnread: () -> Void

        var body: some View {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.small) {
                    ForEach(ActivityFilter.allCases, id: \.self) { option in
                        ChipView(TodayStrings.filter(option), isSelected: option == filter) {
                            onFilter(option)
                        }
                    }
                    ChipView(TodayStrings.text("today.filter.unread"), isSelected: unreadOnly, action: onToggleUnread)
                        .accessibilityAddTraits(.isToggle)
                        .accessibilityIdentifier("today.activity.unreadToggle")
                }
                .padding(.horizontal, Spacing.medium)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text(TodayStrings.text("today.filter.label")))
            .waiveraHaptic(.selection, trigger: filter)
            .waiveraHaptic(.toggle, trigger: unreadOnly)
        }
    }

    /// One activity: icon by type (reply icon for unknown types), summary, kind and time, and an
    /// unread dot. Swipe or the accessibility action marks it read without opening it.
    struct ActivityItemRow: View {
        let row: ActivityRow
        let formatter: TodayFormatter
        let onOpen: () -> Void
        let onMarkRead: () -> Void

        var body: some View {
            let summary = TodayStrings.summary(row.summary)
            let kind = TodayStrings.kind(row.kind)
            let spoken = TodayStrings.spoken(kind, summary, row.when.map(formatter.pastSpoken))
            TodayRow(
                headline: summary,
                supporting: TodayStrings.joined(kind, row.when.map(formatter.past)),
                emphasized: !row.isRead,
                showsChevron: true,
                accessibilityText: row.isRead ? spoken : TodayStrings.format("today.activity.unreadPrefix", spoken),
                accessibilityHintText: TodayStrings.text("today.hint.openMessage"),
                action: onOpen,
                leading: {
                    IconTile(
                        systemImage: Self.icon(row.kind),
                        tint: row.isRead ? Palette.textSecondary : Palette.accent
                    )
                },
                trailing: {
                    if !row.isRead {
                        UnreadDot(accessibilityLabel: TodayStrings.text("today.activity.unread"))
                    }
                }
            )
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                if !row.isRead {
                    Button(action: onMarkRead) {
                        Label(TodayStrings.text("today.activity.markRead"), systemImage: "checkmark.circle")
                    }
                    .tint(Palette.accent)
                }
            }
            .accessibilityActions {
                if !row.isRead {
                    Button(TodayStrings.text("today.activity.markRead"), action: onMarkRead)
                }
            }
        }

        static func icon(_ kind: ActivityItem.Kind) -> String {
            switch kind {
            case .mention: "at"
            case .reaction: "face.smiling"
            case .threadReply, .unknown: "arrowshape.turn.up.left"
            }
        }
    }

    /// Under the feed: a spinner while the next page loads, an inline Retry when it failed, and
    /// the trigger that asks for the next page when it scrolls into view.
    struct ActivityFooter: View {
        let section: ActivitySection
        let onLoadMore: () -> Void
        let onRetry: () -> Void

        var body: some View {
            Group {
                if section.loadMoreFailed {
                    BannerView(
                        .error,
                        message: TodayStrings.text("today.activity.moreFailed"),
                        actionTitle: TodayStrings.text("today.retry"),
                        action: onRetry
                    )
                    .padding(.horizontal, Spacing.medium)
                } else if section.isLoadingMore {
                    ProgressView()
                        .tint(Palette.accent)
                        .frame(maxWidth: .infinity, minHeight: ControlSize.minHitTarget)
                        .accessibilityLabel(Text(TodayStrings.text("today.activity.loadingMore")))
                } else {
                    Color.clear.frame(height: Spacing.hairline)
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, Spacing.small)
            .onAppear {
                if section.hasMore { onLoadMore() }
            }
            // A page that did not fill the screen leaves the footer visible: ask for the next one.
            .onChange(of: section.totalCount) {
                if section.hasMore { onLoadMore() }
            }
        }
    }
#endif
