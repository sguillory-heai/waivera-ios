#if canImport(UIKit)
    import SwiftUI

    public extension Path {
        /// The commands of a vector path, scaled from its viewport into `rect`.
        init(commands: [PathCommand], viewport: CGSize, in rect: CGRect) {
            self.init()
            let scaleX = viewport.width > 0 ? rect.width / viewport.width : 1
            let scaleY = viewport.height > 0 ? rect.height / viewport.height : 1
            func point(_ x: Double, _ y: Double) -> CGPoint {
                CGPoint(x: rect.minX + CGFloat(x) * scaleX, y: rect.minY + CGFloat(y) * scaleY)
            }
            for command in commands {
                switch command {
                case .move(let x, let y):
                    move(to: point(x, y))
                case .line(let x, let y):
                    addLine(to: point(x, y))
                case .quad(let controlX, let controlY, let x, let y):
                    addQuadCurve(to: point(x, y), control: point(controlX, controlY))
                case .cubic(let control1X, let control1Y, let control2X, let control2Y, let x, let y):
                    addCurve(
                        to: point(x, y),
                        control1: point(control1X, control1Y),
                        control2: point(control2X, control2Y)
                    )
                case .close:
                    closeSubpath()
                }
            }
        }
    }

    /// Draws a `VectorArt` at its aspect ratio: `ink` paths in `ink`, gradient paths in the logo's
    /// brand gradient. Decorative.
    public struct VectorArtView: View {
        private let art: VectorArt
        private let ink: Color

        public init(_ art: VectorArt, ink: Color) {
            self.art = art
            self.ink = ink
        }

        public var body: some View {
            let drawn = art
            let inkColor = ink
            Canvas { context, size in
                drawVectorArt(drawn, ink: inkColor, in: &context, size: size)
            }
            .aspectRatio(art.aspectRatio, contentMode: .fit)
            .accessibilityHidden(true)
        }
    }

    /// Free functions, so the canvas renderer can call them from any isolation.
    private func drawVectorArt(_ art: VectorArt, ink: Color, in context: inout GraphicsContext, size: CGSize) {
        let viewport = CGSize(width: art.viewportWidth, height: art.viewportHeight)
        let rect = CGRect(origin: .zero, size: size)
        let scale = art.viewportWidth > 0 ? size.width / CGFloat(art.viewportWidth) : 1
        for vector in art.paths {
            let path = Path(commands: vector.commands, viewport: viewport, in: rect)
            let shading = vectorShading(vector.paint, ink: ink, viewport: viewport, rect: rect)
            switch vector.style {
            case .fill(let alpha):
                context.opacity = alpha
                context.fill(path, with: shading)
            case .stroke(let width, let alpha, let cap, let join):
                context.opacity = alpha
                context.stroke(
                    path,
                    with: shading,
                    style: StrokeStyle(
                        lineWidth: CGFloat(width) * scale,
                        lineCap: cap.cgLineCap,
                        lineJoin: join.cgLineJoin
                    )
                )
            }
        }
    }

    private func vectorShading(
        _ paint: VectorPath.Paint,
        ink: Color,
        viewport: CGSize,
        rect: CGRect
    ) -> GraphicsContext.Shading {
        switch paint {
        case .ink:
            return .color(ink)
        case .brandGradient:
            let scaleY = viewport.height > 0 ? rect.height / viewport.height : 1
            let scaleX = viewport.width > 0 ? rect.width / viewport.width : 1
            // The first colour holds from the top until its stop, as in the drawable.
            let first = LogoGradient.stops.first.map { [Gradient.Stop(color: Color(rgb: $0.color), location: 0)] } ?? []
            let stops =
                first + LogoGradient.stops.map { Gradient.Stop(color: Color(rgb: $0.color), location: $0.location) }
            return .linearGradient(
                Gradient(stops: stops),
                startPoint: CGPoint(
                    x: CGFloat(LogoGradient.start.x) * scaleX,
                    y: CGFloat(LogoGradient.start.y) * scaleY
                ),
                endPoint: CGPoint(x: CGFloat(LogoGradient.end.x) * scaleX, y: CGFloat(LogoGradient.end.y) * scaleY)
            )
        }
    }

    extension VectorPath.LineCap {
        var cgLineCap: CGLineCap {
            switch self {
            case .butt: .butt
            case .round: .round
            case .square: .square
            }
        }
    }

    extension VectorPath.LineJoin {
        var cgLineJoin: CGLineJoin {
            switch self {
            case .miter: .miter
            case .round: .round
            case .bevel: .bevel
            }
        }
    }

    /// The Waivera logo: the gradient loop with base lines in `ink` (the text colour, or white on
    /// the hero). Never recoloured beyond the ink. Spoken as "Waivera" unless `decorative`.
    public struct WaiveraLogo: View {
        public enum Style: Sendable {
            /// The looped "W" alone.
            case mark
            /// The mark with the "waivera" wordmark.
            case lockup
            /// The mark in one ink, for places a gradient cannot go.
            case mono
        }

        private let style: Style
        private let ink: Color
        private let decorative: Bool

        public init(style: Style = .lockup, ink: Color = Palette.text, decorative: Bool = false) {
            self.style = style
            self.ink = ink
            self.decorative = decorative
        }

        public var body: some View {
            ZStack {
                switch style {
                case .mark:
                    VectorArtView(VectorLibrary.markInk, ink: ink)
                    VectorArtView(VectorLibrary.markLoop, ink: ink)
                case .lockup:
                    VectorArtView(VectorLibrary.lockupInk, ink: ink)
                    VectorArtView(VectorLibrary.lockupLoop, ink: ink)
                case .mono:
                    VectorArtView(VectorLibrary.markMono, ink: ink)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: decorative ? "" : DesignStrings.appName))
            .accessibilityHidden(decorative)
        }
    }

    /// Empty-state drawings: abstract, no people, one violet ink on a lilac disc.
    public enum Illustration: Sendable, CaseIterable {
        case chats
        case schedule
        case caughtUp
        case search
        case bookmarks
        case activity
        case connections

        public var art: VectorArt {
            switch self {
            case .chats: VectorLibrary.illustrationChats
            case .schedule: VectorLibrary.illustrationSchedule
            case .caughtUp: VectorLibrary.illustrationCaughtUp
            case .search: VectorLibrary.illustrationSearch
            case .bookmarks: VectorLibrary.illustrationBookmarks
            case .activity: VectorLibrary.illustrationActivity
            case .connections: VectorLibrary.illustrationConnections
            }
        }
    }

    /// An illustration in the accent violet over the lilac tonal disc (58 radius on a 120 frame).
    /// The drawing is one ink with its own alpha steps, so it stays a duotone with no gradient.
    public struct IllustrationView: View {
        private let illustration: Illustration
        private let size: CGFloat

        public init(_ illustration: Illustration, size: CGFloat = ControlSize.illustration) {
            self.illustration = illustration
            self.size = size
        }

        public var body: some View {
            ZStack {
                Circle()
                    .fill(Palette.accentSoft)
                    .frame(width: size * 116 / 120, height: size * 116 / 120)
                VectorArtView(illustration.art, ink: Palette.accent)
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
        }
    }

    private struct VectorGallery: View {
        var body: some View {
            ScrollView {
                VStack(spacing: Spacing.large) {
                    WaiveraLogo()
                        .frame(height: ControlSize.brandLockupHero)
                    HStack {
                        WaiveraLogo(style: .mark).frame(height: ControlSize.brandMark)
                        WaiveraLogo(style: .mono, ink: Palette.accent).frame(height: ControlSize.brandMark)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: ControlSize.illustration))]) {
                        ForEach(Illustration.allCases, id: \.self) { IllustrationView($0) }
                    }
                }
                .padding(Spacing.medium)
            }
            .background(Palette.background)
        }
    }

    #Preview("Light") { VectorGallery() }
    #Preview("Dark") { VectorGallery().preferredColorScheme(.dark) }
    #Preview("AX5") { VectorGallery().dynamicTypeSize(.accessibility5) }
#endif
