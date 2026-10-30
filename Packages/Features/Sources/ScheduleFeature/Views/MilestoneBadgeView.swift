#if canImport(UIKit)
    import SwiftUI
    import UIKit
    import WaiveraData
    import WaiveraDesign

    /// The corner badge on a milestone avatar (Android `MilestoneCornerBadge`): a tinted cake,
    /// award (with the years on avatars of 40pt and up) or party popper on its container, cut out
    /// of the page by a ring of the background. The glyph and the years are sized from the badge,
    /// not from Dynamic Type, since the badge is a fixed-size image. Decorative: the avatar speaks
    /// the celebration.
    struct MilestoneBadgeView: View {
        let badge: MilestoneBadge

        var body: some View {
            let edge = CGFloat(badge.size)
            HStack(spacing: 0) {
                Image(systemName: symbol)
                    .resizable()
                    .scaledToFit()
                    .fontWeight(.bold)
                    .frame(width: CGFloat(badge.glyphSize), height: CGFloat(badge.glyphSize))
                if let years = badge.years {
                    Text(verbatim: "\(years)")
                        .font(.custom(FontWeightToken.extraBold.postScriptName, fixedSize: CGFloat(badge.yearsFontSize)))
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .foregroundStyle(ink)
            .padding(.horizontal, badge.years == nil ? 0 : Spacing.xxSmall)
            .frame(minWidth: edge - 2 * ControlSize.milestoneBadgeBorder, minHeight: edge - 2 * ControlSize.milestoneBadgeBorder)
            .background(fill, in: Capsule())
            .padding(ControlSize.milestoneBadgeBorder)
            .background(Palette.background, in: Capsule())
            .accessibilityHidden(true)
        }

        private var symbol: String {
            switch badge.glyph {
            case .cake: "birthday.cake.fill"
            case .award: "rosette"
            case .party: "party.popper.fill"
            }
        }

        private var fill: Color {
            switch badge.glyph {
            case .cake: Color(token: .milestoneBadgeBirthday)
            case .award: Color(token: .milestoneBadgeAnniversary)
            case .party: Palette.multipleContainer
            }
        }

        private var ink: Color {
            switch badge.glyph {
            case .cake: Color(token: .milestoneBadgeBirthdayText)
            case .award: Color(token: .milestoneBadgeAnniversaryText)
            case .party: Palette.onMultipleContainer
            }
        }
    }
#endif
