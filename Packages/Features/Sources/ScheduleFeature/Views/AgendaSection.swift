#if canImport(UIKit)
    import SwiftUI
    import WaiveraDesign

    /// The selected day's agenda in its fixed order, with today's "Now" line, or its loading and
    /// empty states. A failed first load is the banner above the grid, where it is seen without
    /// scrolling, so nothing shows here. The Day view reads as a timeline (concept B); Week and
    /// Month keep the plain list. Cards join and leave on the layout spring; a leaving card fades
    /// on the quick exit before its neighbours close up through its place (M1-06).
    struct AgendaSection: View {
        let state: ScheduleUIState
        let canSendWishes: Bool
        let actions: ScheduleActions

        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            LoadingContent(isLoading: state.agenda == .loading) {
                content
            } skeleton: {
                AgendaSkeleton()
            }
        }

        @ViewBuilder private var content: some View {
            switch state.agenda {
            case .loading, .error:
                EmptyView()
            case .empty:
                EmptyStateView(
                    illustration: .schedule,
                    title: ScheduleStrings.text("schedule.empty.title"),
                    message: ScheduleStrings.text("schedule.empty.message")
                )
                .transition(Motion.enterAfterExit(reduceMotion: reduceMotion))
            case .content(let rows):
                list(rows)
            }
        }

        private func list(_ rows: [AgendaRow]) -> some View {
            let now = state.agendaNow
            return VStack(spacing: Spacing.small) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    if let now, now.beforeID == row.id {
                        NowDivider(time: now.time).transition(itemTransition)
                    }
                    entry(row, isLast: index == rows.count - 1, ended: now?.endedIDs.contains(row.id) ?? false)
                        .transition(itemTransition)
                }
                if let now, now.beforeID == nil {
                    NowDivider(time: now.time).transition(itemTransition)
                }
            }
            .animation(Motion.animation(.layout, reduceMotion: reduceMotion), value: rows.map(\.id))
            .animation(Motion.animation(.layout, reduceMotion: reduceMotion), value: now)
        }

        @ViewBuilder private func entry(_ row: AgendaRow, isLast: Bool, ended: Bool) -> some View {
            let card = AgendaCard(
                row: row,
                ended: ended,
                openingWishes: isOpening(row),
                canSendWishes: canSendWishes,
                onOpenEvent: { actions.openEvent($0) },
                onSendWishes: { actions.sendWishes($0) }
            )
            if state.view == .day {
                AgendaRailEntry(rail: row.rail, tone: AgendaRailTone.of(row.kind, ended: ended), isLast: isLast) {
                    card
                }
            } else {
                card
            }
        }

        private func isOpening(_ row: AgendaRow) -> Bool {
            guard case .celebration(let celebration) = row.kind else { return false }
            return state.openingWishesFor == celebration.userId
        }

        private var itemTransition: AnyTransition {
            let enter = Motion.animation(.state, reduceMotion: reduceMotion)
            let exit = Motion.animation(MotionPolicy.exit(reduceMotion: reduceMotion))
            return .asymmetric(insertion: .opacity.animation(enter), removal: .opacity.animation(exit))
        }
    }
#endif
