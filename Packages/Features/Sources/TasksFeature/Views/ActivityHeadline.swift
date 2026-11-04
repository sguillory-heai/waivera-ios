#if canImport(UIKit)
    import SwiftUI
    import UIKit
    import WaiveraData
    import WaiveraDesign

    /// The action as the headline, at most two lines. On your own entries the "You" pill (the
    /// shared `StatusBadge`, Android `WaiveraStatusBadge`) sits 8pt after the end of the last line
    /// when it fits there, centred on that line, and drops to its own line only when it does not:
    /// the inline version is measured uncapped, and used only if it needs no more lines.
    struct ActivityHeadline: View {
        let type: String
        let mine: Bool

        @Environment(\.displayScale) private var displayScale
        @Environment(\.colorScheme) private var colorScheme
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize
        @State private var cappedHeight: CGFloat = 0
        @State private var fullHeight: CGFloat = 0
        @State private var pill: UIImage?

        var body: some View {
            if mine {
                let inline = inlineText.waiveraTextStyle(.titleSmall, weight: .semibold)
                Group {
                    if pill == nil || fullHeight > cappedHeight + 1 {
                        VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                            headline
                            badge
                        }
                    } else {
                        inline
                            .foregroundStyle(Palette.text)
                            .lineLimit(Self.lines)
                    }
                }
                .background(alignment: .topLeading) {
                    // Both measured off screen whichever version shows, so the choice can change.
                    ZStack(alignment: .topLeading) {
                        inline
                            .lineLimit(Self.lines)
                            .fixedSize(horizontal: false, vertical: true)
                            .onGeometryChange(for: CGFloat.self, of: \.size.height) { cappedHeight = $0 }
                        inline
                            .fixedSize(horizontal: false, vertical: true)
                            .onGeometryChange(for: CGFloat.self, of: \.size.height) { fullHeight = $0 }
                    }
                    .hidden()
                    .accessibilityHidden(true)
                }
                .task(id: PillKey(scheme: colorScheme, size: dynamicTypeSize, scale: displayScale)) {
                    pill = renderPill()
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

        private var badge: some View {
            StatusBadge(TasksStrings.text("tasks.activity.byYou"), tone: .accent)
        }

        /// The action, a no-break space, then the pill as one inline image, so the pill wraps as a
        /// whole and never splits from the action's last word.
        private var inlineText: Text {
            guard let pill else { return Text(type) }
            let font = TextStyleToken.titleSmall.uiFont()
            // Centre the pill on the line: its middle at the middle of the capitals.
            let offset = (font.capHeight - pill.size.height) / 2
            let tag = Text(Image(uiImage: pill)).baselineOffset(offset)
            return Text("\(type)\u{00A0}\(tag)")
        }

        /// The pill drawn once per colour scheme and text size, with the 8pt gap on its leading
        /// side, as an image the headline can carry inline.
        @MainActor private func renderPill() -> UIImage? {
            let renderer = ImageRenderer(
                content: badge
                    .padding(.leading, Spacing.small - Spacing.extraSmall)
                    .environment(\.colorScheme, colorScheme)
                    .environment(\.dynamicTypeSize, dynamicTypeSize)
            )
            renderer.scale = displayScale
            return renderer.uiImage
        }
    }

    private struct PillKey: Equatable {
        let scheme: ColorScheme
        let size: DynamicTypeSize
        let scale: CGFloat
    }
#endif
