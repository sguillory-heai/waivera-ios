#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    /// One layout for every request card (Android `RequestCard`): who (or what) on the left, a
    /// kicker with the kind and when, the person or the change, and the task. Your own requests
    /// carry their status.
    struct RequestCard: View {
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize
        let item: RequestItem
        /// Waiting on you: the requester's avatar and name lead. Otherwise it is your own request.
        let waiting: Bool
        let onOpen: () -> Void

        var body: some View {
            Button(action: onOpen) {
                HStack(alignment: .top, spacing: Spacing.mediumSmall) {
                    if waiting {
                        AvatarView(name: item.request.requesterName, size: ControlSize.avatarMedium)
                            .accessibilityHidden(true)
                    } else {
                        IconTile(systemImage: icon, tone: .brand, size: ControlSize.avatarMedium)
                    }
                    VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                        Text(kicker)
                            .waiveraTextStyle(.kicker)
                            .foregroundStyle(Palette.textSecondary)
                        Text(headline)
                            .waiveraTextStyle(.titleSmall)
                            .foregroundStyle(Palette.text)
                        if waiting, let change = item.change.text {
                            Text(change)
                                .waiveraTextStyle(.bodyMedium)
                                .foregroundStyle(Palette.text)
                        }
                        if let task = item.request.taskTitle {
                            Text(task)
                                .waiveraTextStyle(.bodySmall)
                                .foregroundStyle(Palette.textSecondary)
                                .lineLimit(large ? 3 : 1)
                        }
                        if !waiting {
                            StatusBadge(item.statusLabel, tone: statusTone)
                                .padding(.top, Spacing.xxSmall)
                        }
                    }
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Color.clear.frame(width: ControlSize.iconSmall, height: Spacing.hairline)
                }
                .overlay(alignment: .trailing) {
                    TaskChevron(systemImage: opensWeb ? "arrow.up.right.square" : "chevron.right")
                }
                .padding(Spacing.mediumSmall)
                .frame(maxWidth: .infinity, alignment: .leading)
                .sheetCard()
                .contentShape(Rectangle())
            }
            .buttonStyle(.press(.card))
            .accessibilityElement(children: .combine)
            .accessibilityHint(
                Text(
                    TasksStrings.text(
                        item.request.kind.reviewableHere || !waiting ? "tasks.request.review" : "tasks.request.openWeb"
                    )
                )
            )
        }

        /// A request waiting on you that the phone cannot review opens on the web.
        private var opensWeb: Bool { waiting && !item.request.kind.reviewableHere }

        private var large: Bool { dynamicTypeSize >= .accessibility1 }

        /// "DELAY · TODAY, 12:15 AM": the kind in amber when it waits on you, violet for your own.
        private var kicker: AttributedString {
            var kind = AttributedString(item.kindLabel.uppercased())
            kind.foregroundColor = waiting ? Palette.warningText : Palette.accent
            guard let asked = item.asked?.text else { return kind }
            return kind + AttributedString((large ? "\n" : "\u{00A0}· ") + asked.uppercased())
        }

        private var headline: String {
            let name = item.request.requesterName
            return waiting && !name.isEmpty ? name : (item.change.text ?? item.kindLabel)
        }

        private var icon: String {
            switch item.request.kind {
            case .moreTime: "clock"
            case .delay: "exclamationmark.triangle"
            case .closure: "archivebox"
            case .other: "calendar"
            }
        }

        private var statusTone: BadgeTone {
            switch item.request.status {
            case .approved: .success
            case .rejected: .danger
            case .pending: .warning
            case .other: .neutral
            }
        }
    }
#endif
