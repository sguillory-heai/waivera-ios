#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    /// The pressed message as its bubble, body only. A long one is clamped to the height it is
    /// given and scrolls inside itself, with fades that say there is more. VoiceOver reads it whole.
    struct LiftedBubble: View {
        let model: MessageActionsModel

        private var shape: UnevenRoundedRectangle {
            BubbleShape.make(isMine: model.isMine, previous: false, next: false)
        }

        private var fill: Color { model.isMine ? Palette.myBubble : Palette.surface }

        var body: some View {
            ViewThatFits(in: .vertical) {
                content.fixedSize(horizontal: false, vertical: true)
                FocusScrollingBody(fill: fill) { content }
            }
            .background(fill, in: shape)
            .overlay {
                if !model.isMine { shape.strokeBorder(Palette.border, lineWidth: Spacing.hairline) }
            }
            .clipShape(shape)
            .shadow(
                color: Palette.buttonRaise,
                radius: Elevation.shadow(for: Elevation.overlay).radius,
                x: 0,
                y: Elevation.shadow(for: Elevation.overlay).y
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
        }

        private var content: some View {
            Group {
                if let rich = model.rich {
                    RichTextView(document: rich, inMyBubble: model.isMine)
                } else {
                    PlainMessageText(text: bodyText)
                }
            }
            .frame(minWidth: ChatMetrics.bubbleMinWidth, alignment: .leading)
            .padding(.horizontal, Spacing.mediumSmall - Spacing.hairline)
            .padding(.vertical, Spacing.small)
        }

        private var bodyText: String {
            let text = model.message.copyableText
            guard text.isEmpty, let attachment = model.message.attachment else { return text }
            return ConversationStrings.format(
                "row.attachment",
                AttachmentRules.fileName(attachment, messageId: model.message.id)
            )
        }

        private var accessibilityText: String { bodyText }
    }

    /// `content` top first inside the height it is given, scrolling when it is taller. A fade in
    /// the bubble's own fill covers about two lines at the bottom while there is more, and at the
    /// top once the start has scrolled away. A drag here is the bubble's: it never closes the
    /// overlay. With Reduce Motion the fades switch without fading.
    private struct FocusScrollingBody<Content: View>: View {
        let fill: Color
        @ViewBuilder let content: () -> Content

        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @ScaledMetric(relativeTo: .body) private var lineHeight = TextStyleToken.bodyMedium.spec.lineHeight
        @State private var offset: CGFloat = 0
        @State private var contentHeight: CGFloat = 0
        @State private var viewportHeight: CGFloat = 0

        private static var space: String { "focus-bubble-scroll" }

        private var fades: FocusFades {
            FocusFades(contentHeight: contentHeight, viewportHeight: viewportHeight, offset: offset)
        }

        var body: some View {
            ScrollView(.vertical) {
                content()
                    .fixedSize(horizontal: false, vertical: true)
                    .background {
                        GeometryReader { proxy in
                            Color.clear
                                .onChange(of: proxy.frame(in: .named(Self.space)).minY, initial: true) { _, top in
                                    offset = -top
                                }
                                .onChange(of: proxy.size.height, initial: true) { _, height in
                                    contentHeight = height
                                }
                        }
                    }
            }
            .coordinateSpace(name: Self.space)
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .background {
                GeometryReader { proxy in
                    Color.clear.onChange(of: proxy.size.height, initial: true) { _, height in
                        viewportHeight = height
                    }
                }
            }
            .overlay(alignment: .top) { fade(atTop: true).opacity(fades.top ? 1 : 0) }
            .overlay(alignment: .bottom) { fade(atTop: false).opacity(fades.bottom ? 1 : 0) }
            .animation(reduceMotion ? nil : Motion.animation(.state, reduceMotion: false), value: fades)
        }

        private func fade(atTop: Bool) -> some View {
            let clear = fill.opacity(0)
            let stops: [Gradient.Stop] =
                atTop
                ? [
                    .init(color: fill, location: 0),
                    .init(color: fill, location: ChatMetrics.focusFadeSolidStop),
                    .init(color: clear, location: 1),
                ]
                : [
                    .init(color: clear, location: 0),
                    .init(color: fill, location: 1 - ChatMetrics.focusFadeSolidStop),
                    .init(color: fill, location: 1),
                ]
            return LinearGradient(stops: stops, startPoint: .top, endPoint: .bottom)
                .frame(height: lineHeight * ChatMetrics.focusFadeLines)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
#endif
