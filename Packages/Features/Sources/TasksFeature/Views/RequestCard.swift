#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    /// One request: its kind, the task, what changes and who asked when.
    struct RequestCard: View {
        let item: RequestItem
        let showsStatus: Bool
        let onOpen: () -> Void

        var body: some View {
            Button(action: onOpen) {
                HStack(alignment: .top, spacing: ControlSize.fieldTileGap) {
                    IconTile(
                        systemImage: icon,
                        tone: tone,
                        size: ControlSize.fieldTile,
                        glyphSize: ControlSize.fieldTileGlyph
                    )
                    VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                        HStack(spacing: Spacing.small) {
                            Text(item.kindLabel)
                                .waiveraTextStyle(.labelMedium, weight: .bold)
                                .foregroundStyle(Palette.accent)
                            if showsStatus {
                                StatusBadge(item.statusLabel, tone: statusTone)
                            }
                        }
                        Text(item.request.taskTitle ?? item.request.typeName)
                            .waiveraTextStyle(.titleSmall, weight: .semibold)
                            .foregroundStyle(Palette.text)
                            .lineLimit(2)
                        if let change = item.change.text {
                            Text(change)
                                .waiveraTextStyle(.bodySmall, weight: .semibold)
                                .foregroundStyle(Palette.text)
                        }
                        Text(byLine)
                            .waiveraTextStyle(.bodySmall)
                            .foregroundStyle(Palette.textSecondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(Spacing.medium)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.listCard))
                .overlay(RoundedRectangle(cornerRadius: Radius.listCard).stroke(Palette.border))
                .contentShape(Rectangle())
            }
            .buttonStyle(.press(.card))
            .accessibilityElement(children: .combine)
            .accessibilityHint(
                Text(
                    TasksStrings.text(
                        item.request.kind.reviewableHere ? "tasks.request.review" : "tasks.request.openWeb"
                    )
                )
            )
        }

        private var byLine: String {
            [item.request.requesterName.isEmpty ? nil : item.request.requesterName, item.asked?.text]
                .compactMap(\.self)
                .joined(separator: " · ")
        }

        private var icon: String {
            switch item.request.kind {
            case .moreTime: "calendar.badge.clock"
            case .delay: "clock.badge.exclamationmark"
            case .closure: "xmark.circle"
            case .other: "doc.text"
            }
        }

        private var tone: TileTone {
            switch item.request.kind {
            case .moreTime: .brand
            case .delay: .amber
            case .closure: .rose
            case .other: .neutral
            }
        }

        private var statusTone: BadgeTone {
            switch item.request.status {
            case .approved: .success
            case .rejected: .danger
            case .pending, .other: .warning
            }
        }
    }
#endif
