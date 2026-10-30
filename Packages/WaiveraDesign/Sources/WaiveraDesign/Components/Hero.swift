#if canImport(UIKit)
    import SwiftUI

    /// The plum hero (Android `WaiveraHeroBackdrop`): the 165° plum gradient, a pink glow in the
    /// top-end corner, a violet glow in the bottom-start corner and the light trails of `trail` at
    /// low opacity. One of the two places a gradient is allowed (v5 rule A); everything on it is
    /// solid. Decorative: the content over it carries the meaning. Extend it under the status bar
    /// with `ignoresSafeArea(edges: .top)`.
    public struct HeroBackdrop: View {
        private let trail: HeroTrail

        public init(trail: HeroTrail = .tab) {
            self.trail = trail
        }

        public var body: some View {
            Canvas { context, size in
                drawHero(trail: trail, in: &context, size: size)
            }
            .accessibilityHidden(true)
        }
    }

    /// A free function so the canvas renderer can call it from any isolation.
    private func drawHero(trail: HeroTrail, in context: inout GraphicsContext, size: CGSize) {
        let rect = CGRect(origin: .zero, size: size)
        let points = HeroMetrics.cssGradientPoints(width: size.width, height: size.height)
        context.fill(
            Path(rect),
            with: .linearGradient(
                Gradient(colors: [HeroPalette.headerTop, HeroPalette.headerBottom]),
                startPoint: CGPoint(x: CGFloat(points.start.x) * size.width, y: CGFloat(points.start.y) * size.height),
                endPoint: CGPoint(x: CGFloat(points.end.x) * size.width, y: CGFloat(points.end.y) * size.height)
            )
        )
        let unit = size.width / CGFloat(HeroMetrics.frameWidth)
        drawGlow(
            HeroPalette.glowPink,
            center: CGPoint(
                x: size.width - CGFloat(HeroMetrics.pinkEndInset) * unit,
                y: CGFloat(HeroMetrics.pinkTop) * unit
            ),
            radius: CGFloat(HeroMetrics.pinkRadius) * unit,
            in: &context
        )
        drawGlow(
            HeroPalette.glowViolet,
            center: CGPoint(
                x: CGFloat(HeroMetrics.violetStart) * unit,
                y: size.height + CGFloat(HeroMetrics.violetBelow) * unit
            ),
            radius: CGFloat(HeroMetrics.violetRadius) * unit,
            in: &context
        )
        if let placement = trail.placement {
            drawTrail(placement, unit: unit, in: &context)
        }
    }

    private func drawGlow(_ color: Color, center: CGPoint, radius: CGFloat, in context: inout GraphicsContext) {
        let box = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        context.fill(
            Path(ellipseIn: box),
            with: .radialGradient(
                Gradient(stops: [
                    .init(color: color, location: 0),
                    .init(color: color.opacity(0), location: HeroMetrics.glowFade),
                ]),
                center: center,
                startRadius: 0,
                endRadius: radius
            )
        )
    }

    /// Fits the 35 x 26 trail into its box ("xMidYMid meet") and strokes it in the brand gradient.
    private func drawTrail(_ placement: HeroTrail.Placement, unit: CGFloat, in context: inout GraphicsContext) {
        let boxWidth = CGFloat(placement.width) * unit
        let boxHeight = CGFloat(placement.height) * unit
        let viewWidth = CGFloat(HeroTrail.viewWidth)
        let viewHeight = CGFloat(HeroTrail.viewHeight)
        let scale = min(boxWidth / viewWidth, boxHeight / viewHeight)
        let left = CGFloat(placement.left) * unit + (boxWidth - viewWidth * scale) / 2
        let top = CGFloat(placement.top) * unit + (boxHeight - viewHeight * scale) / 2
        let viewport = CGSize(width: viewWidth, height: viewHeight)
        let frame = CGRect(x: left, y: top, width: viewWidth * scale, height: viewHeight * scale)
        let shading = GraphicsContext.Shading.linearGradient(
            Gradient(stops: [
                .init(color: Color(rgb: RGBColor(hex: BrandPalette.brandViolet)), location: 0),
                .init(color: Color(rgb: RGBColor(hex: BrandPalette.brandPink)), location: HeroTrail.gradientPinkStop),
                .init(color: Color(rgb: RGBColor(hex: BrandPalette.brandGold)), location: 1),
            ]),
            startPoint: CGPoint(x: left + CGFloat(HeroTrail.gradientStartX) * scale, y: top),
            endPoint: CGPoint(x: left + CGFloat(HeroTrail.gradientEndX) * scale, y: top)
        )
        let main = Path(
            commands: (try? VectorPathParser.parse(HeroTrail.mainPath)) ?? [],
            viewport: viewport,
            in: frame
        )
        var layer = context
        layer.opacity = placement.alpha
        layer.stroke(
            main,
            with: shading,
            style: StrokeStyle(lineWidth: CGFloat(placement.stroke) * scale, lineCap: .round)
        )
        if placement.strand {
            let strand = Path(
                commands: (try? VectorPathParser.parse(HeroTrail.strandPath)) ?? [],
                viewport: viewport,
                in: frame
            )
            layer.opacity = placement.alpha * HeroTrail.strandAlpha
            layer.stroke(
                strand,
                with: shading,
                style: StrokeStyle(lineWidth: CGFloat(HeroTrail.strandStroke) * scale, lineCap: .round)
            )
        }
    }

    /// The top of a tab screen (Android `WaiveraHeroSection`): the plum hero behind the status bar,
    /// holding the hero bar and `content`, ending in the first band of the rounded sheet the rest
    /// of the screen sits on. Put it first in the screen's scroll view on the page colour. Pair
    /// with `.toolbarColorScheme(.dark, for: .navigationBar)` so the status bar reads on the plum.
    public struct HeroSection<TopBar: View, Content: View>: View {
        private let trail: HeroTrail
        private let topBar: TopBar
        private let content: Content
        private let compact: Bool

        public init(
            trail: HeroTrail = .tab,
            compact: Bool = false,
            @ViewBuilder topBar: () -> TopBar,
            @ViewBuilder content: () -> Content
        ) {
            self.trail = trail
            self.compact = compact
            self.topBar = topBar()
            self.content = content()
        }

        public var body: some View {
            let lip = CGFloat(compact ? HeroMetrics.tabSheetLipShort : HeroMetrics.tabSheetLip)
            VStack(spacing: 0) {
                topBar
                content
                Color.clear
                    .frame(height: lip)
            }
            .frame(maxWidth: .infinity)
            .background(alignment: .bottom) {
                HeroBackdrop(trail: trail)
                    .ignoresSafeArea(edges: [.top, .horizontal])
                    .overlay(alignment: .bottom) {
                        UnevenRoundedRectangle(
                            topLeadingRadius: lip,
                            topTrailingRadius: lip,
                            style: .continuous
                        )
                        .fill(Palette.background)
                        .frame(height: lip)
                    }
            }
        }
    }

    /// An icon button in the hero bar, before the avatar (Chats' "+" for a new chat).
    public struct HeroBarAction: Identifiable {
        public let id: String
        public let systemImage: String
        public let accessibilityLabel: String
        public let action: () -> Void

        public init(id: String, systemImage: String, accessibilityLabel: String, action: @escaping () -> Void) {
            self.id = id
            self.systemImage = systemImage
            self.accessibilityLabel = accessibilityLabel
            self.action = action
        }
    }

    /// The hero bar (Android `WaiveraHeroTopBar`): the mark, the screen title (the heading, two
    /// lines at most), any icon actions and the signed-in person's avatar on the glass, which
    /// opens the account menu.
    public struct HeroTopBar: View {
        private let title: String
        private let actions: [HeroBarAction]
        private let accountName: String?
        private let accountImage: Image?
        private let accountLabel: String?
        private let onAccount: (() -> Void)?

        public init(
            title: String,
            actions: [HeroBarAction] = [],
            accountName: String? = nil,
            accountImage: Image? = nil,
            accountLabel: String? = nil,
            onAccount: (() -> Void)? = nil
        ) {
            self.title = title
            self.actions = actions
            self.accountName = accountName
            self.accountImage = accountImage
            self.accountLabel = accountLabel
            self.onAccount = onAccount
        }

        public var body: some View {
            HStack(spacing: Spacing.mediumSmall) {
                WaiveraLogo(style: .mark, ink: HeroPalette.onHeader, decorative: true)
                    .frame(height: CGFloat(HeroMetrics.barMark))
                Text(title)
                    .waiveraTextStyle(.heroBarTitle)
                    .foregroundStyle(HeroPalette.onHeader)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)
                ForEach(actions) { item in
                    Button(action: item.action) {
                        Image(systemName: item.systemImage)
                            .font(.system(size: ControlSize.icon, weight: .semibold))
                            .foregroundStyle(HeroPalette.onHeader)
                            .frame(width: ControlSize.iconButton, height: ControlSize.iconButton)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.press(.compact))
                    .accessibilityLabel(Text(item.accessibilityLabel))
                    .accessibilityIdentifier("heroBar.\(item.id)")
                }
                if let accountName, let onAccount {
                    Button(action: onAccount) {
                        AvatarView(
                            name: accountName,
                            image: accountImage,
                            size: CGFloat(HeroMetrics.barAvatar),
                            fill: .hero
                        )
                        .frame(width: ControlSize.iconButton, height: ControlSize.iconButton)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.press(.compact))
                    .accessibilityLabel(Text(accountLabel ?? DesignStrings.accountMenu))
                }
            }
            .padding(.leading, Spacing.medium + Spacing.xxSmall)
            .padding(.trailing, Spacing.small)
            .frame(minHeight: CGFloat(HeroMetrics.barHeight))
        }
    }

    /// The glass summary card on the hero ("5 of 9 handled"): a faint white fill and hairline.
    public struct HeroCard<Content: View>: View {
        private let compact: Bool
        private let content: Content

        public init(compact: Bool = false, @ViewBuilder content: () -> Content) {
            self.compact = compact
            self.content = content()
        }

        public var body: some View {
            VStack(alignment: .leading, spacing: compact ? Spacing.small : Spacing.mediumSmall) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(compact ? Spacing.mediumSmall : Spacing.medium + Spacing.xxSmall)
            .background(HeroPalette.card, in: RoundedRectangle(cornerRadius: Radius.heroCard, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.heroCard, style: .continuous)
                    .strokeBorder(HeroPalette.cardBorder, lineWidth: Spacing.hairline)
            )
        }
    }

    /// A surface with the soft brand-gradient wash, for celebrations only (a birthday, an
    /// anniversary, a new hire): the other place a gradient is allowed. Text keeps 4.5:1 on every
    /// point of the wash. Once or twice per screen, never for lists of rows.
    public struct BrandSurface<Content: View>: View {
        private let content: Content

        public init(@ViewBuilder content: () -> Content) {
            self.content = content()
        }

        public var body: some View {
            VStack(alignment: .leading, spacing: Spacing.small) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.medium)
            .background {
                RoundedRectangle(cornerRadius: Radius.hero, style: .continuous)
                    .fill(Palette.surface)
                    .overlay(BrandWashFill().clipShape(RoundedRectangle(cornerRadius: Radius.hero, style: .continuous)))
            }
            .overlay(
                RoundedRectangle(cornerRadius: Radius.hero, style: .continuous)
                    .strokeBorder(Palette.border, lineWidth: Spacing.hairline)
            )
        }
    }

    /// The celebration wash, top-leading to bottom-trailing, for the current theme.
    public struct BrandWashFill: View {
        @Environment(\.colorScheme) private var colorScheme

        public init() {}

        public var body: some View {
            LinearGradient(
                stops: BrandWash.stops(isDark: colorScheme == .dark).map {
                    Gradient.Stop(color: Color(rgb: $0.color), location: $0.location)
                },
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .accessibilityHidden(true)
        }
    }

    /// A plain lifted block on the surface with a hairline edge: the solid counterpart of
    /// `BrandSurface` for anything that is not a celebration.
    public struct SurfaceCard<Content: View>: View {
        private let content: Content

        public init(@ViewBuilder content: () -> Content) {
            self.content = content()
        }

        public var body: some View {
            VStack(alignment: .leading, spacing: Spacing.small) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.medium)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.sheetCard, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sheetCard, style: .continuous)
                    .strokeBorder(Palette.border, lineWidth: Spacing.hairline)
            )
            .shadow(
                color: Palette.buttonRaise,
                radius: Elevation.shadow(for: Elevation.card).radius,
                x: 0,
                y: Elevation.shadow(for: Elevation.card).y
            )
        }
    }

    private struct HeroGallery: View {
        var body: some View {
            ScrollView {
                VStack(spacing: 0) {
                    HeroSection {
                        HeroTopBar(title: "Today", accountName: "Priya Raman", onAccount: {})
                    } content: {
                        HeroCard {
                            Text(verbatim: "Good morning, Priya")
                                .waiveraTextStyle(.heroGreeting)
                                .foregroundStyle(HeroPalette.onHeader)
                            Text(verbatim: "3 things need you")
                                .waiveraTextStyle(.heroBody)
                                .foregroundStyle(HeroPalette.onHeaderSecondary)
                        }
                        .padding(.horizontal, Spacing.medium)
                    }
                    VStack(spacing: Spacing.medium) {
                        BrandSurface {
                            Text(verbatim: "Happy birthday, Alex!").waiveraTextStyle(.titleMedium)
                        }
                        SurfaceCard {
                            Text(verbatim: "Team standup").waiveraTextStyle(.titleMedium)
                        }
                    }
                    .foregroundStyle(Palette.text)
                    .padding(Spacing.medium)
                }
            }
            .background(Palette.background)
        }
    }

    #Preview("Light") { HeroGallery() }
    #Preview("Dark") { HeroGallery().preferredColorScheme(.dark) }
    #Preview("AX5") { HeroGallery().dynamicTypeSize(.accessibility5) }
#endif
