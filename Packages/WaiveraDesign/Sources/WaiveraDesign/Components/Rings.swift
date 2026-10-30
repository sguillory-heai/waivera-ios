#if canImport(UIKit)
    import SwiftUI

    /// The hero's progress ring (Android `WaiveraProgressRing`, owner's pick A): a faint track
    /// with a solid lilac-violet arc for `done` of `total` from twelve o'clock, and only the count
    /// in the middle, a big "5" with a small "/9". The arc grows from empty on first show on the
    /// celebrate spring and follows changes; under Reduce Motion it simply shows the value.
    /// VoiceOver reads `accessibilityText` ("5 of 9 handled today") once, never the numbers apart.
    /// A two-digit count or total sets the numeral a size down; the count stops growing at 130%
    /// text (the compact ring never grows), so it never reaches the arc.
    public struct ProgressRing: View {
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        private let done: Int
        private let total: Int
        private let accessibilityText: String
        private let compact: Bool
        @State private var shown: Double = 0

        public init(done: Int, total: Int, accessibilityText: String, compact: Bool = false) {
            self.done = done
            self.total = total
            self.accessibilityText = accessibilityText
            self.compact = compact
        }

        public var body: some View {
            let small = RingMath.usesSmallNumeral(done: done, total: total, compact: compact)
            ZStack {
                RingArc(progress: shown, lineWidth: compact ? ControlSize.ringStrokeCompact : ControlSize.ringStroke)
                HStack(alignment: .lastTextBaseline, spacing: 0) {
                    Text(verbatim: "\(done)")
                        .waiveraTextStyle(small ? .ringNumeralSmall : .ringNumeral)
                        .foregroundStyle(HeroPalette.onHeader)
                    Text(verbatim: "/\(total)")
                        .waiveraTextStyle(small ? .ringDenominatorSmall : .ringDenominator)
                        .foregroundStyle(HeroPalette.onHeaderSecondary)
                }
                .lineLimit(1)
                .fixedSize()
                .dynamicTypeSize(...RingMath.maximumCategory(compact: compact).dynamicTypeSize)
            }
            .frame(
                width: compact ? ControlSize.ringCompact : ControlSize.ring,
                height: compact ? ControlSize.ringCompact : ControlSize.ring
            )
            .onAppear { follow() }
            .onChange(of: target) { follow() }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(accessibilityText))
            .accessibilityValue(Text(verbatim: "\(Int((target * 100).rounded()))%"))
        }

        private var target: Double { RingMath.fraction(done: done, total: total) }

        private func follow() {
            withAnimation(Motion.animation(.celebrate, reduceMotion: reduceMotion)) { shown = target }
        }
    }

    /// Track and solid arc, inset by half the stroke so the ring fits its box.
    private struct RingArc: View {
        let progress: Double
        let lineWidth: CGFloat

        var body: some View {
            ZStack {
                Circle()
                    .stroke(HeroPalette.ringTrack, lineWidth: lineWidth)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(HeroPalette.ringArc, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(RingMath.startAngleDegrees))
                    .opacity(progress > 0 ? 1 : 0)
            }
            .padding(lineWidth / 2)
        }
    }

    /// All caught up (Android `WaiveraRewardRing`): the big full ring in the same solid arc on a
    /// soft lilac halo, a white check in the middle and two sparkles in gold and pink. The ring
    /// closes and the check draws in on first show; under Reduce Motion both are simply there.
    /// Decorative apart from `accessibilityText`.
    public struct RewardRing: View {
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        private let accessibilityText: String?
        @State private var shown: Double = 0
        @State private var checkShown = false

        public init(accessibilityText: String?) {
            self.accessibilityText = accessibilityText
        }

        public var body: some View {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            stops: [
                                .init(color: HeroPalette.ringArc.opacity(RingMath.haloAlpha), location: 0),
                                .init(color: HeroPalette.ringArc.opacity(0), location: RingMath.haloFade),
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: (ControlSize.rewardRing + ControlSize.rewardHalo * 2) / 2
                        )
                    )
                RingArc(progress: shown, lineWidth: ControlSize.rewardRingStroke)
                    .frame(width: ControlSize.rewardRing, height: ControlSize.rewardRing)
                RewardCheck()
                    .stroke(
                        HeroPalette.onHeader,
                        style: StrokeStyle(
                            lineWidth: ControlSize.rewardCheck * CGFloat(RingMath.checkStrokeShare),
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
                    .frame(width: ControlSize.rewardCheck, height: ControlSize.rewardCheck)
                    .scaleEffect(checkShown ? 1 : CGFloat(RingMath.checkMinScale))
                    .opacity(checkShown ? 1 : 0)
                Sparkle(large: true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                Sparkle(large: false)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
            .frame(
                width: ControlSize.rewardRing + ControlSize.rewardHalo * 2,
                height: ControlSize.rewardRing + ControlSize.rewardHalo * 2
            )
            .task { await play() }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(accessibilityText ?? ""))
            .accessibilityHidden(accessibilityText == nil)
        }

        /// The ring closes on the celebrate spring; the check follows once the ring is about
        /// `RingMath.checkFrom` of the way round.
        private func play() async {
            guard !reduceMotion else {
                shown = 1
                checkShown = true
                return
            }
            withAnimation(Motion.animation(MotionSpec.celebrate)) { shown = 1 }
            try? await Task.sleep(for: .seconds(Self.checkDelay))
            guard !Task.isCancelled else { return }
            withAnimation(Motion.animation(MotionSpec.celebrate)) { checkShown = true }
        }

        /// When the celebrate spring has carried the arc to `RingMath.checkFrom`.
        private static let checkDelay = 0.2
    }

    private struct RewardCheck: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            func point(_ share: (x: Double, y: Double)) -> CGPoint {
                CGPoint(x: rect.minX + rect.width * CGFloat(share.x), y: rect.minY + rect.height * CGFloat(share.y))
            }
            path.move(to: point(RingMath.checkStart))
            path.addLine(to: point(RingMath.checkKnee))
            path.addLine(to: point(RingMath.checkEnd))
            return path
        }
    }

    /// A four-point sparkle: gold and larger, or pink and smaller.
    private struct Sparkle: View {
        let large: Bool

        var body: some View {
            SparkleShape()
                .fill(Color(rgb: RGBColor(hex: large ? BrandPalette.brandGold : BrandPalette.sparklePink)))
                .frame(
                    width: ControlSize.iconSmall * CGFloat(large ? RingMath.sparkleLarge : RingMath.sparkleSmall),
                    height: ControlSize.iconSmall * CGFloat(large ? RingMath.sparkleLarge : RingMath.sparkleSmall)
                )
                .padding(ControlSize.rewardHalo / 2)
        }
    }

    private struct SparkleShape: Shape {
        func path(in rect: CGRect) -> Path {
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let radius = min(rect.width, rect.height) / 2
            let waist = radius * CGFloat(RingMath.sparkleWaist)
            var path = Path()
            path.move(to: CGPoint(x: center.x, y: center.y - radius))
            path.addQuadCurve(
                to: CGPoint(x: center.x + radius, y: center.y),
                control: CGPoint(x: center.x + waist, y: center.y - waist)
            )
            path.addQuadCurve(
                to: CGPoint(x: center.x, y: center.y + radius),
                control: CGPoint(x: center.x + waist, y: center.y + waist)
            )
            path.addQuadCurve(
                to: CGPoint(x: center.x - radius, y: center.y),
                control: CGPoint(x: center.x - waist, y: center.y + waist)
            )
            path.addQuadCurve(
                to: CGPoint(x: center.x, y: center.y - radius),
                control: CGPoint(x: center.x - waist, y: center.y - waist)
            )
            path.closeSubpath()
            return path
        }
    }

    /// The celebrate moment (Android `WaiveraCelebrationBurst`): a one-shot burst of brand
    /// confetti rising from the top centre, spreading and falling away over 1.4s. Lay it over the
    /// thing being celebrated; it never takes touches or focus. It plays once per `trigger`
    /// (pass something that changes only when there is something new, such as today's date for
    /// the 9/9 reward) and draws nothing under Reduce Motion.
    public struct CelebrationBurst: View {
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        private let trigger: String?
        private let seed: UInt64
        @State private var startedAt: Date?
        @State private var playedTrigger: String?

        public init(trigger: String?, seed: UInt64 = 0) {
            self.trigger = trigger
            self.seed = seed
        }

        public var body: some View {
            Group {
                if let startedAt, MotionPolicy.celebrationBursts(reduceMotion: reduceMotion) {
                    BurstCanvas(startedAt: startedAt, pieces: Confetti.pieces(seed: seed))
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .task(id: trigger) { await play() }
        }

        private func play() async {
            guard let trigger, trigger != playedTrigger, !reduceMotion else { return }
            playedTrigger = trigger
            startedAt = Date()
            try? await Task.sleep(for: .seconds(MotionSpec.celebrateBurst.duration))
            guard !Task.isCancelled else { return }
            startedAt = nil
        }
    }

    private struct BurstCanvas: View {
        let startedAt: Date
        let pieces: [Confetti.Piece]

        var body: some View {
            let start = startedAt
            let burst = pieces
            TimelineView(.animation) { timeline in
                let progress = timeline.date.timeIntervalSince(start) / MotionSpec.celebrateBurst.duration
                Canvas { context, size in
                    drawConfetti(burst, progress: progress, in: &context, size: size)
                }
            }
        }
    }

    private func drawConfetti(
        _ pieces: [Confetti.Piece],
        progress: Double,
        in context: inout GraphicsContext,
        size: CGSize
    ) {
        guard Confetti.isVisible(reduceMotion: false, progress: progress) else { return }
        let palette = BrandWash.confettiColors.map { Color(rgb: $0) } + [Palette.accent]
        let origin = CGPoint(x: size.width / 2, y: size.height * CGFloat(Confetti.originHeightFraction))
        let radius = min(size.width, size.height * 2) / 2
        let piece = ControlSize.confettiPiece
        for item in pieces {
            let frame = Confetti.frame(item, progress: progress)
            guard frame.alpha > 0 else { continue }
            var layer = context
            layer.opacity = frame.alpha
            layer.translateBy(x: origin.x + CGFloat(frame.x) * radius, y: origin.y + CGFloat(frame.y) * radius)
            layer.rotate(by: .degrees(frame.rotationDegrees))
            let color = palette[item.colorIndex % palette.count]
            if item.round {
                layer.fill(
                    Path(ellipseIn: CGRect(x: -piece / 2, y: -piece / 2, width: piece, height: piece)),
                    with: .color(color)
                )
            } else {
                let height = piece * CGFloat(Confetti.stripAspect)
                layer.fill(
                    Path(CGRect(x: -piece / 2, y: -height / 2, width: piece, height: height)),
                    with: .color(color)
                )
            }
        }
    }

    private struct RingGallery: View {
        var body: some View {
            VStack(spacing: Spacing.large) {
                HStack(spacing: Spacing.large) {
                    ProgressRing(done: 5, total: 9, accessibilityText: "5 of 9 handled today")
                    ProgressRing(done: 12, total: 14, accessibilityText: "12 of 14 handled today")
                    ProgressRing(done: 1, total: 3, accessibilityText: "1 of 3 handled today", compact: true)
                }
                ZStack {
                    RewardRing(accessibilityText: "All 9 handled today")
                    CelebrationBurst(trigger: "2026-10-30", seed: 20_261_030)
                }
            }
            .padding(Spacing.large)
            .background(HeroBackdrop())
        }
    }

    #Preview("Light") { RingGallery() }
    #Preview("Dark") { RingGallery().preferredColorScheme(.dark) }
    #Preview("AX5") { RingGallery().dynamicTypeSize(.accessibility5) }
#endif
