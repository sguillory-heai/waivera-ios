#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    /// A bubble's link previews (Android `BodyWithAttachedLinks`, style F): on the surface colour
    /// whatever the bubble's tint, edge to edge under the body, with a hairline above each. The
    /// bubble gives them at least a file card's width, so every preview in a chat lines up.
    struct LinkSections: View {
        let links: [MessageLink]
        /// The bubble's side padding, which the sections reach into so text keeps one left edge.
        let inset: CGFloat
        let onOpen: @MainActor (_ href: String) -> Void

        var body: some View {
            VStack(spacing: 0) {
                ForEach(Array(links.enumerated()), id: \.offset) { _, link in
                    Rectangle()
                        .fill(Palette.border)
                        .frame(height: Spacing.hairline)
                    LinkSection(preview: link.preview, inset: inset) { onOpen(link.href) }
                }
            }
            .background(Palette.surface)
        }
    }

    /// One preview: the kind and a glyph on a quiet line with the open mark at its end, the
    /// title in bold, then one line of detail. Tasks open in the app (chevron), resources and
    /// FAQs on the web (external arrow).
    private struct LinkSection: View {
        let preview: LinkPreview
        let inset: CGFloat
        let onOpen: () -> Void

        var body: some View {
            if preview.opens {
                Button(action: onOpen) { content }
                    .buttonStyle(.plain)
                    .accessibilityHint(LinkPreviewText.accessibilityHint(preview) ?? "")
            } else {
                content
            }
        }

        private var content: some View {
            VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                kicker
                details
            }
            .padding(.horizontal, inset)
            .padding(.vertical, Spacing.small)
            .frame(maxWidth: .infinity, minHeight: ControlSize.minHitTarget, alignment: .leading)
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(LinkPreviewText.accessibilityLabel(preview))
            .accessibilityAddTraits(preview.opens ? .isLink : [])
        }

        private var kicker: some View {
            HStack(spacing: Spacing.extraSmall + Spacing.xxSmall) {
                Image(systemName: glyph)
                    .imageScale(.small)
                    .foregroundStyle(Palette.textSecondary)
                Text(LinkPreviewText.kicker(preview))
                    .waiveraTextStyle(.labelSmall)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if preview.opens {
                    Image(systemName: preview.kind == .task ? "chevron.right" : "arrow.up.right.square")
                        .imageScale(.small)
                        .foregroundStyle(Palette.accent)
                }
            }
        }

        @ViewBuilder private var details: some View {
            if case .loading = preview {
                SkeletonBlock(width: ChatMetrics.linkSkeletonWidth)
            } else {
                if let title = LinkPreviewText.title(preview) {
                    Text(title)
                        .waiveraTextStyle(.titleSmall)
                        .fontWeight(.bold)
                        .foregroundStyle(Palette.text)
                        .lineLimit(1)
                }
                HStack(spacing: Spacing.small) {
                    if case .task(_, _, _, let state, _, _) = preview {
                        StatusBadge(LinkPreviewText.state(state), tone: tone(LinkPreviewText.tone(state)))
                    }
                    if let meta = LinkPreviewText.meta(preview) {
                        Text(meta)
                            .waiveraTextStyle(.bodySmall)
                            .foregroundStyle(Palette.textSecondary)
                            .lineLimit(1)
                    }
                }
            }
        }

        private var glyph: String {
            if case .unavailable = preview { return "lock" }
            switch preview.kind {
            case .task: return "checkmark.circle"
            case .resource: return "mappin.and.ellipse"
            case .faq: return "info.circle"
            }
        }

        private func tone(_ tone: LinkPreviewText.Tone) -> BadgeTone {
            switch tone {
            case .accent: .accent
            case .neutral: .neutral
            case .success: .success
            case .warning: .warning
            }
        }
    }
#endif
