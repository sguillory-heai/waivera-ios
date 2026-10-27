#if canImport(UIKit)
    import SwiftUI
    import UIKit
    import WaiveraData
    import WaiveraDesign

    /// The round badge: cake, award (with the years on larger avatars) or party popper.
    struct MilestoneBadgeView: View {
        let badge: MilestoneBadge

        var body: some View {
            let size = CGFloat(badge.size)
            ZStack {
                Circle().fill(fill)
                glyph(size: size)
            }
            .frame(width: size, height: size)
            .overlay(Circle().strokeBorder(Palette.background, lineWidth: ControlSize.milestoneRingWidth))
            .accessibilityHidden(true)
        }

        @ViewBuilder private func glyph(size: CGFloat) -> some View {
            switch badge.glyph {
            case .cake:
                Text(verbatim: "🎂")
                    .font(.system(size: max(9, (size * 0.52).rounded())))
            case .award:
                HStack(spacing: 0) {
                    Image(systemName: "rosette")
                        .font(.system(size: max(9, size * 0.5), weight: .bold))
                    if let years = badge.years {
                        Text(verbatim: "\(years)")
                            .font(.system(size: max(7, size * 0.3), weight: .heavy))
                    }
                }
                .foregroundStyle(Color(token: .milestoneBadgeAnniversaryText))
                .minimumScaleFactor(0.5)
            case .party:
                Image(systemName: "party.popper.fill")
                    .font(.system(size: max(10, size * 0.56), weight: .bold))
                    .foregroundStyle(Color(token: .milestoneBadgeWelcomeText))
            }
        }

        private var fill: Color {
            switch badge.glyph {
            case .cake: Color(token: .milestoneBadgeBirthday)
            case .award: Color(token: .milestoneBadgeAnniversary)
            case .party: Color(token: .milestoneBadgeWelcome)
            }
        }
    }
#endif
