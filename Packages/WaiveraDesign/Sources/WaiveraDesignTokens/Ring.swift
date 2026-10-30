import Foundation

/// The hero's count-only progress ring (owner's v6 pick A, "just the number"): a big count with a
/// small "/total", no caption. TalkBack and VoiceOver read "5 of 9 handled today" instead.
public enum RingMath {
    /// The share of the ring to fill for `done` of `total`: 0 when there is nothing, never past full.
    public static func fraction(done: Int, total: Int) -> Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, Double(done) / Double(total)))
    }

    /// Whether the count is set a size down: in the compact ring, or for a two-digit count or total.
    public static func usesSmallNumeral(done: Int, total: Int, compact: Bool) -> Bool {
        compact || done >= 10 || total >= 10
    }

    /// The largest text size the ring's count follows: 130% for the regular ring, the default for
    /// the compact one, so the count never reaches the arc.
    public static func maximumCategory(compact: Bool) -> TextSizeCategory {
        compact ? .large : TypeScale.cap(atScale: TypeScale.ringMaxScale)
    }

    /// The arc starts at twelve o'clock and runs clockwise.
    public static let startAngleDegrees = -90.0

    /// The reward ring's halo: one hue fading out (`ringArc` at 30% to 0 at 68% of the radius).
    public static let haloAlpha = 0.3
    public static let haloFade = 0.68
    /// The reward check draws in once the ring is this far round.
    public static let checkFrom = 0.7
    public static let checkMinScale = 0.6
    /// The check's points as shares of its 52pt box, and its stroke (3 on a 24 viewport).
    public static let checkStart = (x: 0.2, y: 0.52)
    public static let checkKnee = (x: 0.41, y: 0.72)
    public static let checkEnd = (x: 0.8, y: 0.3)
    public static let checkStrokeShare = 3.0 / 24.0
    /// The sparkles beside the reward ring: gold large (1.25 x 16pt), pink small (0.85 x 16pt).
    public static let sparkleLarge = 1.25
    public static let sparkleSmall = 0.85
    public static let sparkleWaist = 0.18

    /// How far the check has drawn in for the ring's progress (0 until `checkFrom`, 1 when closed).
    public static func checkReveal(progress: Double) -> Double {
        min(1, max(0, (progress - checkFrom) / (1 - checkFrom)))
    }
}

/// What is waiting, by kind, under the ring's headline ("2 messages · 1 invite · 1 ticket").
/// Kinds with none are left out, and with nothing waiting there is no line at all.
public enum RingSubline {
    /// The Needs you kinds in the order the line lists them.
    public enum Kind: String, CaseIterable, Sendable {
        case notSent
        case message
        case mention
        case invitation
        case ticket
    }

    /// Each count is joined to its noun by a no-break space, and the separator keeps its dot with
    /// the kind before it, so a wrap never strands "1" over "ticket" (wave 30 R1).
    public static let separator = "\u{00A0}· "
    public static let nounGap = "\u{00A0}"

    /// The kinds with at least one item, in `Kind` order.
    public static func parts(_ counts: [Kind: Int]) -> [(kind: Kind, count: Int)] {
        Kind.allCases.compactMap { kind in
            guard let count = counts[kind], count > 0 else { return nil }
            return (kind, count)
        }
    }

    /// The whole line, or nil when nothing is waiting. `phrase` names a kind with its count;
    /// the default is the English copy, and the app passes its localized plurals.
    public static func text(
        _ counts: [Kind: Int],
        phrase: (Kind, Int) -> String = englishPhrase
    ) -> String? {
        let parts = parts(counts)
        guard !parts.isEmpty else { return nil }
        return parts.map { phrase($0.kind, $0.count) }.joined(separator: separator)
    }

    /// "1 message", "2 messages", "3 not sent", with a no-break space after the count.
    public static func englishPhrase(_ kind: Kind, _ count: Int) -> String {
        let one = count == 1
        let noun: String =
            switch kind {
            case .notSent: "not\u{00A0}sent"
            case .message: one ? "message" : "messages"
            case .mention: one ? "mention" : "mentions"
            case .invitation: one ? "invite" : "invites"
            case .ticket: one ? "ticket" : "tickets"
            }
        return "\(count)\(nounGap)\(noun)"
    }
}

/// The celebrate moment's confetti, as deterministic physics so it can be tested and snapshotted.
public enum Confetti {
    public static let pieces = 36
    public static let originHeightFraction = 0.35
    public static let stripAspect = 0.45
    private static let maxDelay = 0.15
    private static let minReach = 0.45
    private static let reachRange = 0.55
    private static let maxSpin = 3.0
    private static let gravity = 0.9
    private static let fadeFrom = 0.65
    private static let spread = 2.4
    private static let up = -Double.pi / 2

    public struct Piece: Equatable, Sendable {
        /// Launch direction in radians; 0 points right, -π/2 straight up.
        public let angle: Double
        /// How far it travels, as a share of the burst radius.
        public let reach: Double
        /// Turns over the whole burst; negative spins the other way.
        public let spin: Double
        public let colorIndex: Int
        /// Share of the timeline before this piece launches, so the burst ripples.
        public let delay: Double
        /// Round dots and paper strips mix.
        public let round: Bool
    }

    public struct Frame: Equatable, Sendable {
        /// Offsets from the burst origin, in burst radii.
        public let x: Double
        public let y: Double
        public let rotationDegrees: Double
        public let alpha: Double
    }

    public static func pieces(seed: UInt64, count: Int = pieces) -> [Piece] {
        var random = SeededRandom(seed: seed)
        return (0..<count).map { index in
            Piece(
                angle: up + (random.nextUnit() - 0.5) * 2 * spread,
                reach: minReach + random.nextUnit() * reachRange,
                spin: (random.nextUnit() - 0.5) * 2 * maxSpin,
                colorIndex: index,
                delay: random.nextUnit() * maxDelay,
                round: index % 3 == 0
            )
        }
    }

    /// Nothing is drawn before launch, after the end, or ever under Reduce Motion.
    public static func isVisible(reduceMotion: Bool, progress: Double) -> Bool {
        !reduceMotion && progress > 0 && progress < 1
    }

    public static func frame(_ piece: Piece, progress: Double) -> Frame {
        let local = min(1, max(0, (progress - piece.delay) / (1 - piece.delay)))
        guard local > 0 else { return Frame(x: 0, y: 0, rotationDegrees: 0, alpha: 0) }
        // Ease out from the origin, then gravity pulls it down.
        let travel = 1 - (1 - local) * (1 - local)
        let x = cos(piece.angle) * piece.reach * travel
        let y = sin(piece.angle) * piece.reach * travel + gravity * local * local
        let alpha = local < fadeFrom ? 1 : min(1, max(0, (1 - local) / (1 - fadeFrom)))
        return Frame(x: x, y: y, rotationDegrees: piece.spin * 360 * local, alpha: alpha)
    }
}

/// SplitMix64: a tiny deterministic generator, so a seed always draws the same burst.
struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }

    /// A value in 0..<1.
    mutating func nextUnit() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }
}
