#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    /// The action as the headline, at most two lines. On your own entries the "You" tag sits at
    /// the end of the last line when it fits there, and drops to its own line only when it does
    /// not: the inline version is measured uncapped, and used only if it needs no more lines.
    struct ActivityHeadline: View {
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
#endif
