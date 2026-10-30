import Testing

@testable import WaiveraDesignTokens

/// The Today ring: count only, with the waiting kinds underneath.
struct RingTests {
    @Test func fractionIsClamped() {
        #expect(RingMath.fraction(done: 0, total: 0) == 0)
        #expect(RingMath.fraction(done: 3, total: 4) == 0.75)
        #expect(RingMath.fraction(done: 12, total: 9) == 1)
    }

    @Test func twoDigitsOrTheCompactRingUseTheSmallNumeral() {
        #expect(!RingMath.usesSmallNumeral(done: 5, total: 9, compact: false))
        #expect(RingMath.usesSmallNumeral(done: 5, total: 12, compact: false))
        #expect(RingMath.usesSmallNumeral(done: 10, total: 10, compact: false))
        #expect(RingMath.usesSmallNumeral(done: 1, total: 2, compact: true))
    }

    @Test func checkDrawsInOverTheLastThirty() {
        #expect(RingMath.checkReveal(progress: 0.5) == 0)
        #expect(abs(RingMath.checkReveal(progress: 0.85) - 0.5) < 1e-9)
        #expect(RingMath.checkReveal(progress: 1) == 1)
    }

    @Test func sublineListsKindsInOrderAndDropsZeros() {
        let text = RingSubline.text([.ticket: 1, .message: 2, .mention: 0, .invitation: 1, .notSent: 3])
        #expect(
            text
                == "3\u{00A0}not\u{00A0}sent\u{00A0}· 2\u{00A0}messages\u{00A0}· 1\u{00A0}invite\u{00A0}· 1\u{00A0}ticket"
        )
    }

    @Test func singularAndPlural() {
        #expect(RingSubline.text([.mention: 1]) == "1\u{00A0}mention")
        #expect(RingSubline.text([.invitation: 2]) == "2\u{00A0}invites")
    }

    @Test func nothingWaitingHasNoLine() {
        #expect(RingSubline.text([:]) == nil)
        #expect(RingSubline.text([.message: 0]) == nil)
    }

    @Test func sublineTakesLocalizedPhrases() {
        let text = RingSubline.text([.message: 2, .ticket: 1]) { kind, count in "\(kind.rawValue)=\(count)" }
        #expect(text == "message=2\u{00A0}· ticket=1")
    }

    @Test func confettiIsSeededAndOnlyDrawsMidBurst() {
        let pieces = Confetti.pieces(seed: 20_261_030)
        #expect(pieces.count == 36)
        #expect(pieces == Confetti.pieces(seed: 20_261_030))
        #expect(pieces != Confetti.pieces(seed: 1))
        #expect(!Confetti.isVisible(reduceMotion: false, progress: 0))
        #expect(Confetti.isVisible(reduceMotion: false, progress: 0.5))
        #expect(!Confetti.isVisible(reduceMotion: true, progress: 0.5))
        #expect(!Confetti.isVisible(reduceMotion: false, progress: 1))
        for piece in pieces {
            #expect(Confetti.frame(piece, progress: 1).alpha == 0)
        }
    }
}
