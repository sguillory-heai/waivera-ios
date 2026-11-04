#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    /// The note, cut at three lines with "Show more" when it runs longer. Opening and closing
    /// animate only a clip's height, timed by how far it moves. The note itself is always laid
    /// out in full once measured, so opening grows from the three lines already showing instead
    /// of re-laying the text out (which made it collapse and grow again from the top).
    struct ActivityNote: View {
        static let lines = 3

        let text: String

        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var expanded = false
        @State private var fullHeight: CGFloat = 0
        @State private var cutHeight: CGFloat = 0

        private var isCut: Bool { fullHeight > cutHeight + 1 }

        var body: some View {
            VStack(alignment: .leading, spacing: Spacing.extraSmall) {
                Text(text)
                    .waiveraTextStyle(.bodySmall)
                    .foregroundStyle(Palette.text)
                    // Cut by lines only until measured; after that the clip does the cutting.
                    .lineLimit(isMeasured ? nil : Self.lines)
                    .transaction { $0.animation = nil }
                    // Laid out at its own height whatever the clip, so the clip reveals it.
                    .fixedSize(horizontal: false, vertical: true)
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

        private var isMeasured: Bool { fullHeight > 0 && cutHeight > 0 }

        /// Nil until measured, then the open or closed height the clip animates between.
        private var shownHeight: CGFloat? {
            guard isMeasured, isCut || expanded else { return nil }
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
            withAnimation(animation) { expanded.toggle() }
        }
    }
#endif
