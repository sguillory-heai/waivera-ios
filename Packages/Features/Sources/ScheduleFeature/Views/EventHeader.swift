#if canImport(UIKit)
    import SwiftUI
    import WaiveraDesign

    struct EventHeader: View {
        let details: EventDetailsUI

        var body: some View {
            VStack(alignment: .leading, spacing: Spacing.small) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.small) {
                    if let color = details.ownerColor {
                        Circle()
                            .fill(Color(serverColor: color))
                            .frame(width: ControlSize.unreadDot, height: ControlSize.unreadDot)
                            .accessibilityHidden(true)
                    }
                    Text(details.title)
                        .font(WaiveraFont.screenTitle)
                        .foregroundStyle(Palette.text)
                        .accessibilityAddTraits(.isHeader)
                }
                if let notice = details.zoneNotice {
                    Label(notice, systemImage: "globe")
                        .font(WaiveraFont.caption)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
        }
    }
#endif
