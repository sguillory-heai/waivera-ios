#if canImport(UIKit)
    import SwiftUI
    import WaiveraDesign

    /// Draws a parsed TipTap document: paragraphs, headings, quotes, lists, code, rules and
    /// tables (03 §7). Links open through the environment's `openURL`, which the screen routes
    /// through `SafeLinks`.
    struct RichTextView: View {
        let document: RichDocument

        var body: some View {
            VStack(alignment: .leading, spacing: Spacing.extraSmall) {
                ForEach(Array(document.blocks.enumerated()), id: \.offset) { _, block in
                    RichBlockView(block: block)
                }
            }
        }
    }

    /// Plain message text with the same styling as a paragraph.
    struct PlainMessageText: View {
        let text: String

        var body: some View {
            Text(text)
                .font(WaiveraFont.body)
                .foregroundStyle(Palette.text)
                .textSelection(.disabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private struct RichBlockView: View {
        let block: RichBlock

        private var textColor: Color { Palette.text }

        var body: some View {
            switch block {
            case .paragraph(let inlines):
                inline(inlines, font: WaiveraFont.body)
            case .heading(let level, let inlines):
                inline(inlines, font: level <= 1 ? WaiveraFont.screenTitle : WaiveraFont.sectionTitle)
                    .accessibilityAddTraits(.isHeader)
            case .blockquote(let blocks):
                nested(blocks)
                    .padding(.leading, Spacing.smallPlus)
                    .overlay(alignment: .leading) {
                        Rectangle().fill(Palette.accent).frame(width: Spacing.extraSmall)
                    }
            case .list(let ordered, let items):
                VStack(alignment: .leading, spacing: Spacing.extraSmall) {
                    ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                        HStack(alignment: .firstTextBaseline, spacing: Spacing.small) {
                            Text(ordered ? "\(index + 1)." : "•")
                                .font(WaiveraFont.body)
                                .foregroundStyle(textColor)
                                .accessibilityHidden(true)
                            nested(item)
                        }
                    }
                }
            case .codeBlock(let code):
                Text(code)
                    .font(WaiveraFont.caption.monospaced())
                    .foregroundStyle(Palette.text)
                    .padding(Spacing.small)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        Palette.surfaceMuted,
                        in: RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
                    )
            case .horizontalRule:
                Rectangle()
                    .fill(Palette.border)
                    .frame(height: Spacing.hairline)
                    .padding(.vertical, Spacing.extraSmall)
                    .accessibilityHidden(true)
            case .table(let rows):
                RichTableView(rows: rows)
            case .group(let blocks):
                nested(blocks)
            }
        }

        private func inline(_ inlines: [RichInline], font: Font) -> some View {
            Text(RichTextStyler.styled(inlines))
                .font(font)
                .foregroundStyle(textColor)
                .tint(Palette.accent)
                .fixedSize(horizontal: false, vertical: true)
        }

        private func nested(_ blocks: [RichBlock]) -> some View {
            VStack(alignment: .leading, spacing: Spacing.extraSmall) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    RichBlockView(block: block)
                }
            }
        }
    }

    private struct RichTableView: View {
        let rows: [[[RichBlock]]]

        var body: some View {
            ScrollView(.horizontal) {
                Grid(alignment: .leading, horizontalSpacing: Spacing.small, verticalSpacing: Spacing.extraSmall) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        GridRow {
                            ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                                VStack(alignment: .leading, spacing: Spacing.extraSmall) {
                                    ForEach(Array(cell.enumerated()), id: \.offset) { _, block in
                                        RichBlockView(block: block)
                                    }
                                }
                                .padding(Spacing.extraSmall)
                                .overlay(
                                    Rectangle().strokeBorder(Palette.border, lineWidth: Spacing.hairline)
                                )
                            }
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    /// Turns the platform-neutral rich text attributes into SwiftUI styling.
    enum RichTextStyler {
        static func styled(_ inlines: [RichInline]) -> AttributedString {
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
                    text[range].backgroundColor = Palette.accentWash
                }
                if run.link != nil {
                    text[range].underlineStyle = .single
                }
            }
            return text
        }
    }
#endif
