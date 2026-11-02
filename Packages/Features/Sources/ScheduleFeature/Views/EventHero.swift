#if canImport(UIKit)
    import SwiftUI
    import WaiveraDesign

    /// The event's title, when and where on one lifted card, the screen's lead block (Android
    /// `EventHero`). An address opens in Maps; an online place does not, since Join covers it.
    struct EventHero: View {
        let details: EventDetailsUI

        @Environment(\.openURL) private var openURL

        var body: some View {
            VStack(alignment: .leading, spacing: Spacing.mediumSmall) {
                Text(details.title)
                    .waiveraTextStyle(.headlineSmall)
                    .foregroundStyle(Palette.text)
                    .accessibilityAddTraits(.isHeader)
                EventDetailRow(
                    systemImage: "clock",
                    iconLabel: nil,
                    primary: details.timePrimary,
                    secondary: details.timeSecondary,
                    tertiary: details.zoneNotice
                )
                if let place = details.location {
                    placeRow(place)
                }
            }
            .padding(Spacing.mediumPlus)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.upNextCard, style: .continuous))
            .shadow(
                color: Palette.liftShadow,
                radius: Elevation.shadow(for: Elevation.card).radius,
                x: 0,
                y: Elevation.shadow(for: Elevation.card).y
            )
        }

        @ViewBuilder private func placeRow(_ place: String) -> some View {
            if details.isOnline {
                EventDetailRow(
                    systemImage: "video",
                    iconLabel: ScheduleStrings.text("schedule.event.online"),
                    primary: place
                )
            } else {
                Button {
                    if let url = Self.mapsURL(for: place) { openURL(url) }
                } label: {
                    EventDetailRow(
                        systemImage: "mappin.and.ellipse",
                        iconLabel: ScheduleStrings.text("schedule.event.location"),
                        primary: place,
                        trailingSystemImage: "arrow.up.right.square"
                    )
                    .frame(minHeight: ControlSize.minHitTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.press(.row))
                .accessibilityHint(Text(ScheduleStrings.text("schedule.event.openInMaps")))
            }
        }

        /// A Maps search for the address. The address is user text, so it only ever goes in the
        /// query, never in the scheme or host.
        private static func mapsURL(for place: String) -> URL? {
            var components = URLComponents()
            components.scheme = "https"
            components.host = "maps.apple.com"
            components.path = "/"
            components.queryItems = [URLQueryItem(name: "q", value: place)]
            return components.url
        }
    }
#endif
