#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    /// The task's activity, oldest first so new work lands at the bottom.
    struct ActivitySection: View {
        let activity: Loadable<[ActivityRow]>
        let onRetry: () -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: Spacing.small) {
                HStack {
                    SectionHeader(TasksStrings.text("tasks.activity.title"))
                    Spacer()
                    if let rows = activity.value, !rows.isEmpty {
                        Text(TasksStrings.plural("tasks.activity.count", rows.count))
                            .waiveraTextStyle(.labelMedium)
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
                switch activity {
                case .loading:
                    SkeletonList(rows: 2)
                case .failed:
                    EmptyStateView.error(
                        title: TasksStrings.text("tasks.activity.error"),
                        message: "",
                        onRetry: onRetry
                    )
                case .ready(let rows) where rows.isEmpty:
                    Text(TasksStrings.text("tasks.activity.empty"))
                        .waiveraTextStyle(.bodyMedium)
                        .foregroundStyle(Palette.textSecondary)
                case .ready(let rows):
                    CardGroup {
                        ForEach(rows) { ActivityItemView(row: $0) }
                    }
                }
            }
        }
    }

    /// One logged activity in the original layout: the action leads as the headline beside the
    /// activity tile, then when and who, then the note. Your own entries tag "You" after the
    /// action instead of your name. Time spent is left out, as on the web: it feeds reporting.
    struct ActivityItemView: View {
        let row: ActivityRow

        var body: some View {
            HStack(alignment: .top, spacing: Spacing.mediumSmall) {
                IconTile(
                    systemImage: "checklist",
                    tone: row.isNew ? .teal : .brand,
                    size: ControlSize.fieldTile,
                    glyphSize: ControlSize.fieldTileGlyph
                )
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                    ActivityHeadline(type: row.type, mine: row.byMe)
                    if !meta.isEmpty {
                        // Time first, so a long name is the part that is cut.
                        Text(meta)
                            .waiveraTextStyle(.bodySmall)
                            .foregroundStyle(Palette.textSecondary)
                            .lineLimit(1)
                    }
                    if let description = row.description {
                        ActivityNote(text: description)
                            .padding(.top, Spacing.extraSmall)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, Spacing.gutter)
            .padding(.vertical, Spacing.mediumSmall)
            .frame(minHeight: ControlSize.minHitTarget, alignment: .leading)
        }

        private var meta: String {
            [row.moment?.text, row.byMe ? nil : row.author].compactMap(\.self).joined(separator: " · ")
        }
    }

    /// The action as the headline, at most two lines. On your own entries the "You" tag sits at
    /// the end of the last line when it fits there, and drops to its own line only when it does
    /// not: the inline version is measured uncapped, and used only if it needs no more lines.
    private struct ActivityHeadline: View {
        let type: String
        let mine: Bool

        @State private var cappedHeight: CGFloat = 0
        @State private var fullHeight: CGFloat = 0

        var body: some View {
            if mine {
                let inline = Text(inlineText).waiveraTextStyle(.titleSmall, weight: .semibold)
                Group {
                    if fullHeight > cappedHeight + 1 {
                        VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                            headline
                            StatusBadge(TasksStrings.text("tasks.activity.byYou"), tone: .accent)
                        }
                    } else {
                        inline
                            .foregroundStyle(Palette.text)
                            .lineLimit(Self.lines)
                            .onGeometryChange(for: CGFloat.self, of: \.size.height) { cappedHeight = $0 }
                    }
                }
                .background(alignment: .topLeading) {
                    inline
                        .fixedSize(horizontal: false, vertical: true)
                        .hidden()
                        .onGeometryChange(for: CGFloat.self, of: \.size.height) { fullHeight = $0 }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("\(type), \(TasksStrings.text("tasks.activity.byYou"))"))
            } else {
                headline
            }
        }

        static let lines = 2

        private var headline: some View {
            Text(type)
                .waiveraTextStyle(.titleSmall, weight: .semibold)
                .foregroundStyle(Palette.text)
                .lineLimit(Self.lines)
        }

        /// The tag as a tinted run after a no-break space, so it never wraps away from the action.
        private var inlineText: AttributedString {
            var text = AttributedString(type + "\u{00A0}\u{00A0}")
            var tag = AttributedString("\u{2009}\(TasksStrings.text("tasks.activity.byYou"))\u{2009}")
            tag.backgroundColor = Palette.accentSoft
            tag.foregroundColor = Palette.onAccentSoft
            tag.font = WaiveraFont.badge
            text.append(tag)
            return text
        }
    }

    /// The note, cut at three lines with "Show more" when it runs longer. Opening and closing
    /// animate the height, timed by how far it moves; while it closes the whole note stays laid
    /// out under a shrinking clip and the ellipsis comes back once the height has settled.
    struct ActivityNote: View {
        static let lines = 3

        let text: String

        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var expanded = false
        @State private var showsAll = false
        @State private var fullHeight: CGFloat = 0
        @State private var cutHeight: CGFloat = 0

        private var isCut: Bool { fullHeight > cutHeight + 1 }

        var body: some View {
            VStack(alignment: .leading, spacing: Spacing.extraSmall) {
                Text(text)
                    .waiveraTextStyle(.bodySmall)
                    .foregroundStyle(Palette.text)
                    .lineLimit(showsAll ? nil : Self.lines)
                    .frame(height: shownHeight, alignment: .top)
                    .clipped()
                    .background(alignment: .topLeading) { measures }
                if isCut || expanded {
                    Text(TasksStrings.text(expanded ? "tasks.activity.showLess" : "tasks.activity.showMore"))
                        .waiveraTextStyle(.labelLarge)
                        .foregroundStyle(Palette.accent)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { if isCut || expanded { toggle() } }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(isCut || expanded ? .isButton : [])
            .accessibilityAction { if isCut || expanded { toggle() } }
            .accessibilityValue(
                isCut || expanded
                    ? Text(TasksStrings.text(expanded ? "tasks.activity.expanded" : "tasks.activity.collapsed"))
                    : Text(verbatim: "")
            )
        }

        /// Nil until measured, then the open or closed height the clip animates between.
        private var shownHeight: CGFloat? {
            guard fullHeight > 0, cutHeight > 0, isCut || expanded else { return nil }
            return expanded ? fullHeight : cutHeight
        }

        private var measures: some View {
            ZStack(alignment: .topLeading) {
                Text(text)
                    .waiveraTextStyle(.bodySmall)
                    .fixedSize(horizontal: false, vertical: true)
                    .onGeometryChange(for: CGFloat.self, of: \.size.height) { fullHeight = $0 }
                Text(text)
                    .waiveraTextStyle(.bodySmall)
                    .lineLimit(Self.lines)
                    .fixedSize(horizontal: false, vertical: true)
                    .onGeometryChange(for: CGFloat.self, of: \.size.height) { cutHeight = $0 }
            }
            .hidden()
            .accessibilityHidden(true)
        }

        private func toggle() {
            let animation: Animation? =
                reduceMotion
                ? nil : .easeInOut(duration: NoteMotion.duration(distance: abs(fullHeight - cutHeight)))
            if expanded {
                withAnimation(animation) {
                    expanded = false
                } completion: {
                    if !expanded { showsAll = false }
                }
            } else {
                showsAll = true
                withAnimation(animation) { expanded = true }
            }
        }
    }

    private struct ActivityPreview: View {
        var body: some View {
            let rows = [
                ActivityRow(
                    id: 1,
                    type: "Home visit",
                    moment: nil,
                    byMe: true,
                    author: "Alex Rivera",
                    description: "Jordan was in good spirits. Mom asked to move Thursday's visit to the afternoon. "
                        + "We went over the plan, the signed copy and the next steps for the school meeting.",
                    minutes: 60
                ),
                ActivityRow(
                    id: 2,
                    type: "Phone call with the family about the schedule change",
                    moment: nil,
                    byMe: false,
                    author: "Dana Cole",
                    description: "Confirmed.",
                    minutes: 15
                ),
            ]
            ScrollView { ActivitySection(activity: .ready(rows), onRetry: {}).padding(Spacing.gutter) }
                .background(Palette.background)
        }
    }

    #Preview("Light") { ActivityPreview() }
    #Preview("Dark") { ActivityPreview().preferredColorScheme(.dark) }
    #Preview("AX5") { ActivityPreview().dynamicTypeSize(.accessibility5) }
#endif
