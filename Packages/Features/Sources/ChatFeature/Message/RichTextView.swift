#if canImport(UIKit)
    import SwiftUI
    import WaiveraDesign

    /// Draws a parsed TipTap document: paragraphs, headings, quotes, lists, code, rules and
    /// tables (03 §7; Android `RichText`). Links open through the environment's `openURL`, which
    /// the screen routes through `SafeLinks`. Inside my own tinted bubble a mention is underlined
    /// instead of washed, since the wash would not show on the tint.
    struct RichTextView: View {
        let document: RichDocument
        var inMyBubble = false

        var body: some View {
            VStack(alignment: .leading, spacing: Spacing.extraSmall) {
                ForEach(Array(document.blocks.enumerated()), id: \.offset) { _, block in
                    RichBlockView(block: block, color: Palette.text, inMyBubble: inMyBubble)
                }
            }
        }
    }

    /// Plain message text with the same styling as a paragraph.
    struct PlainMessageText: View {
        let text: String

        var body: some View {
            Text(text)
                .waiveraTextStyle(.bodyMedium)
                .foregroundStyle(Palette.text)
                .textSelection(.disabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private struct RichBlockView: View {
        let block: RichBlock
        let color: Color
        let inMyBubble: Bool

        var body: some View {
            switch block {
            case .paragraph(let inlines):
                inline(inlines, style: .bodyMedium)
            case .heading(let level, let inlines):
                inline(inlines, style: Self.headingStyle(level), weight: .extraBold)
                    .padding(.top, Spacing.xxSmall)
                    .accessibilityAddTraits(.isHeader)
            case .blockquote(let blocks):
                // The rule runs the quote's full height; quoted text steps back to secondary.
                VStack(alignment: .leading, spacing: Spacing.extraSmall) {
                    ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                        RichBlockView(block: block, color: Palette.textSecondary, inMyBubble: inMyBubble)
                    }
                }
                .padding(.leading, ChatMetrics.quoteBar + Spacing.mediumSmall - Spacing.xxSmall)
                .overlay(alignment: .leading) {
                    Rectangle().fill(Palette.accent).frame(width: ChatMetrics.quoteBar)
                }
                .padding(.vertical, Spacing.xxSmall)
            case .list(let ordered, let items):
                VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                    ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                        HStack(alignment: .firstTextBaseline, spacing: 0) {
                            Text(verbatim: ordered ? "\(index + 1)." : "•")
                                .waiveraTextStyle(.bodyMedium)
                                .foregroundStyle(Palette.textSecondary)
                                .frame(minWidth: ChatMetrics.listMarkerGutter, alignment: .trailing)
                                .padding(.trailing, Spacing.extraSmall)
                                .accessibilityHidden(true)
                            nested(item, spacing: Spacing.xxSmall)
                        }
                    }
                }
            case .codeBlock(let code):
                // The brand face has no monospaced cut; code takes the system's, as Android's
                // bodySmall in `FontFamily.Monospace` does.
                Text(code)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(color)
                    .padding(Spacing.small)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
                            .strokeBorder(Palette.borderStrong, lineWidth: Spacing.hairline)
                    )
            case .horizontalRule:
                Rectangle()
                    .fill(Palette.borderStrong)
                    .frame(height: Spacing.hairline)
                    .padding(.vertical, Spacing.small)
                    .accessibilityHidden(true)
            case .table(let rows):
                RichTableView(rows: rows, color: color, inMyBubble: inMyBubble)
            case .group(let blocks):
                nested(blocks, spacing: Spacing.extraSmall)
            }
        }

        /// Levels 1 and 2 are the large title, 3 the medium one, deeper ones the small one.
        static func headingStyle(_ level: Int) -> TextStyleToken {
            switch level {
            case ...2: .titleLarge
            case 3: .titleMedium
            default: .titleSmall
            }
        }

        private func inline(
            _ inlines: [RichInline],
            style: TextStyleToken,
            weight: FontWeightToken? = nil
        ) -> some View {
            Text(RichTextStyler.styled(inlines, inMyBubble: inMyBubble))
                .waiveraTextStyle(style, weight: weight)
                .foregroundStyle(color)
                .tint(Palette.accent)
                .fixedSize(horizontal: false, vertical: true)
        }

        private func nested(_ blocks: [RichBlock], spacing: CGFloat) -> some View {
            VStack(alignment: .leading, spacing: spacing) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    RichBlockView(block: block, color: color, inMyBubble: inMyBubble)
                }
            }
        }
    }

    /// Cells of a fixed width on strong hairlines, scrolling sideways when the table is wider than
    /// the bubble (Android `RichTable`).
    private struct RichTableView: View {
        let rows: [[[RichBlock]]]
        let color: Color
        let inMyBubble: Bool

        var body: some View {
            ScrollView(.horizontal) {
                Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        GridRow {
                            ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                                VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                                    ForEach(Array(cell.enumerated()), id: \.offset) { _, block in
                                        RichBlockView(block: block, color: color, inMyBubble: inMyBubble)
                                    }
                                }
                                .padding(Spacing.small)
                                .frame(
                                    width: ChatMetrics.tableCellWidth,
                                    alignment: .leading
                                )
                                .frame(minHeight: ChatMetrics.tableCellMinHeight, maxHeight: .infinity)
                                .overlay(
                                    Rectangle().strokeBorder(Palette.borderStrong, lineWidth: Spacing.hairline)
                                )
                            }
                        }
                    }
                }
                .frame(minWidth: ChatMetrics.tableMinWidth, alignment: .leading)
            }
            .scrollIndicators(.hidden)
        }
    }

    /// Turns the platform-neutral rich text attributes into SwiftUI styling.
    enum RichTextStyler {
        static func styled(_ inlines: [RichInline], inMyBubble: Bool = false) -> AttributedString {
            var text = RichTextAttributes.attributed(inlines)
            for run in text.runs {
                let range = run.range
                if let marks = run[RichMarksAttribute.self] {
                    var intent: InlinePresentationIntent = []
                    if marks.contains(.bold) { intent.insert(.stronglyEmphasized) }
                    if marks.contains(.italic) { intent.insert(.emphasized) }
                    if marks.contains(.code) { intent.insert(.code) }
                    if marks.contains(.strike) { intent.insert(.strikethrough) }
                    text[range].inlinePresentationIntent = intent
                    if marks.contains(.underline) { text[range].underlineStyle = .single }
                }
                if run[RichMentionAttribute.self] != nil {
                    text[range].inlinePresentationIntent = .stronglyEmphasized
                    text[range].foregroundColor = Palette.accent
                    if inMyBubble {
                        text[range].underlineStyle = .single
                    } else {
                        text[range].backgroundColor = Palette.accentWash
                    }
                }
                if run.link != nil {
                    text[range].foregroundColor = Palette.accent
                }
                if run.link != nil {
                    text[range].underlineStyle = .single
                }
            }
            return text
        }
    }
#endif
