#if canImport(UIKit)
    import SwiftUI
    import WaiveraDesign

    struct EventHeader: View {
        let details: EventDetailsUI

        var body: some View {
            SurfaceCard {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.small) {
                    if let color = details.ownerColor {
                        Circle()
                            .fill(Color(serverColor: color))
                            .frame(width: ControlSize.unreadDot, height: ControlSize.unreadDot)
                            .accessibilityHidden(true)
                    }
                    Text(details.title)
                        .waiveraTextStyle(.headlineSmall)
                        .foregroundStyle(Palette.text)
                        .accessibilityAddTraits(.isHeader)
                }
                if let notice = details.zoneNotice {
                    Label(notice, systemImage: "globe")
                        .waiveraTextStyle(.labelMedium)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
        }
    }
#endif
