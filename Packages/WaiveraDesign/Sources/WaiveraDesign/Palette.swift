#if canImport(UIKit)
    import SwiftUI
    import UIKit

    public extension Color {
        /// A colour token that resolves for the current light or dark appearance.
        init(token: ColorToken) {
            self.init(light: token.light, dark: token.dark)
        }

        /// A hero colour; the hero is plum in both themes, so most of these do not change.
        init(hero token: HeroColorToken) {
            self.init(light: token.value(isDark: false), dark: token.value(isDark: true))
        }

        /// A raw value that is the same in both themes (gradient stops, confetti).
        init(rgb: RGBColor) {
            self.init(uiColor: UIColor(rgb: rgb))
        }

        init(light: RGBColor, dark: RGBColor) {
            self.init(
                uiColor: UIColor { traits in
                    UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
                }
            )
        }
    }

    /// Colour roles for views. Feature code uses these, never literal colours. Names mirror
    /// Android's `WaiveraColors`; see `ColorToken` for what each is for.
    public enum Palette {
        public static let background = Color(token: .background)
        public static let surface = Color(token: .surface)
        public static let surfaceMuted = Color(token: .surfaceMuted)
        public static let raised = Color(token: .raised)
        public static let field = Color(token: .field)
        public static let fieldBorder = Color(token: .fieldBorder)
        public static let border = Color(token: .border)
        public static let borderStrong = Color(token: .borderStrong)
        public static let text = Color(token: .text)
        public static let textSecondary = Color(token: .textSecondary)
        public static let textTertiary = Color(token: .textTertiary)
        public static let link = Color(token: .link)
        public static let accent = Color(token: .accent)
        public static let accentFill = Color(token: .accentFill)
        public static let accentSoft = Color(token: .accentSoft)
        public static let onAccentSoft = Color(token: .onAccentSoft)
        public static let accentWash = Color(token: .accentWash)
        public static let accentBorder = Color(token: .accentBorder)
        public static let accentBorderStrong = Color(token: .accentBorderStrong)
        public static let inverseAccent = Color(token: .inverseAccent)
        public static let onAccent = Color(token: .onAccent)
        public static let selectedFill = Color(token: .selectedFill)
        public static let onSelectedFill = Color(token: .onSelectedFill)
        public static let chipNeutral = Color(token: .chipNeutral)
        public static let tonalOnWash = Color(token: .tonalOnWash)
        public static let myBubble = Color(token: .myBubble)
        public static let myBubbleLink = Color(token: .myBubbleLink)
        public static let myBubbleDangerText = Color(token: .myBubbleDangerText)
        /// Kept for existing call sites: the danger fill's ink.
        public static let onDanger = Color(token: .onDanger)
        /// Kept for existing call sites: a danger glyph or mark. Text uses `dangerText`.
        public static let danger = Color(token: .danger)
        public static let dangerText = Color(token: .dangerText)
        public static let dangerFill = Color(token: .dangerFill)
        public static let onDangerFill = Color(token: .onDangerFill)
        public static let dangerContainer = Color(token: .dangerContainer)
        public static let onDangerContainer = Color(token: .onDangerContainer)
        public static let success = Color(token: .success)
        public static let successText = Color(token: .successText)
        public static let warning = Color(token: .warning)
        public static let warningText = Color(token: .warningText)
        public static let warningContainer = Color(token: .warningContainer)
        public static let onWarningContainer = Color(token: .onWarningContainer)
        public static let multipleContainer = Color(token: .multipleContainer)
        public static let onMultipleContainer = Color(token: .onMultipleContainer)
        /// The attention rose: unread counts and the Needs you count.
        public static let unread = Color(token: .unread)
        public static let navBadge = Color(token: .navBadge)
        public static let navBar = Color(token: .navBar)
        public static let navBarBorder = Color(token: .navBarBorder)
        public static let scrim = Color(token: .scrim)
        /// The long-press focus overlay's scrim: 70% light, 76% dark.
        public static let focusScrim = Color(token: .focusScrim)
        /// Behind a full-screen image preview: black at 94%.
        public static let previewScrim = Color(token: .previewScrim)
        public static let thumb = Color(token: .thumb)
        public static let milestone = Color(token: .milestone)
        public static let holiday = Color(token: .holiday)
        public static let skeletonBase = Color(token: .skeletonBase)
        public static let skeletonHighlight = Color(token: .skeletonHighlight)
        public static let avatarFill = Color(token: .avatarFill)
        public static let dayTint = Color(token: .dayTint)
        public static let onDayTint = Color(token: .onDayTint)
        public static let todayMark = Color(token: .todayMark)
        public static let snackbar = Color(token: .snackbar)
        public static let onSnackbar = Color(token: .onSnackbar)
        public static let snackbarAction = Color(token: .snackbarAction)
        public static let buttonSheen = Color(token: .buttonSheen)
        public static let buttonEdge = Color(token: .buttonEdge)
        public static let buttonGlow = Color(token: .buttonGlow)
        public static let buttonRaise = Color(token: .buttonRaise)
    }

    /// The plum hero's colours.
    public enum HeroPalette {
        public static let headerTop = Color(hero: .headerTop)
        public static let headerBottom = Color(hero: .headerBottom)
        public static let glowPink = Color(hero: .glowPink)
        public static let glowViolet = Color(hero: .glowViolet)
        public static let onHeader = Color(hero: .onHeader)
        public static let onHeaderSecondary = Color(hero: .onHeaderSecondary)
        public static let card = Color(hero: .card)
        public static let cardBorder = Color(hero: .cardBorder)
        public static let tile = Color(hero: .tile)
        public static let tileBorder = Color(hero: .tileBorder)
        public static let ringTrack = Color(hero: .ringTrack)
        public static let ringArc = Color(hero: .ringArc)
        public static let accountFill = Color(hero: .accountFill)
        public static let chip = Color(hero: .chip)
        public static let onChip = Color(hero: .onChip)
        public static let nextIcon = Color(hero: .nextIcon)
        public static let sheet = Color(hero: .sheet)
    }

    public extension TileTone {
        var containerColor: Color { Color(light: container(isDark: false), dark: container(isDark: true)) }
        var contentColor: Color { Color(light: content(isDark: false), dark: content(isDark: true)) }
    }

    public extension StatusTone {
        var containerColor: Color { Color(token: container) }
        var inkColor: Color { Color(token: ink) }
    }

    public extension CountTone {
        var fillColor: Color { Color(token: fill) }
        var inkColor: Color { Color(token: ink) }
    }

    extension UIColor {
        convenience init(rgb: RGBColor) {
            self.init(red: rgb.red, green: rgb.green, blue: rgb.blue, alpha: rgb.alpha)
        }
    }
#endif
