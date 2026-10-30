import Testing

@testable import WaiveraDesignTokens

struct VectorArtTests {
    @Test func parsesAbsoluteAndRelativeCommands() throws {
        let commands = try VectorPathParser.parse("M10,10 l5,0 h5 v5 H10 Z m2 2 L4 4")
        #expect(
            commands == [
                .move(x: 10, y: 10), .line(x: 15, y: 10), .line(x: 20, y: 10), .line(x: 20, y: 15),
                .line(x: 10, y: 15), .close, .move(x: 12, y: 12), .line(x: 4, y: 4),
            ]
        )
    }

    @Test func implicitLinesAfterAMoveAndPackedNumbers() throws {
        let commands = try VectorPathParser.parse("m1-2.5.5.5l1e1,1")
        #expect(commands == [.move(x: 1, y: -2.5), .line(x: 1.5, y: -2), .line(x: 11.5, y: -1)])
    }

    @Test func smoothCurvesReflectThePreviousControl() throws {
        let commands = try VectorPathParser.parse("M0 0 C0 10 10 10 10 0 S20 -10 20 0")
        #expect(commands.last == .cubic(control1X: 10, control1Y: -10, control2X: 20, control2Y: -10, x: 20, y: 0))
    }

    @Test func arcsBecomeCubicsThatEndOnTheTarget() throws {
        let commands = try VectorPathParser.parse("M0 10 A10 10 0 0 1 20 10")
        #expect(commands.count == 3)
        guard case .cubic(_, _, _, _, let x, let y) = commands.last else {
            Issue.record("expected a cubic")
            return
        }
        #expect(x == 20)
        #expect(y == 10)
        // A half circle above the chord passes through (10, 0).
        guard case .cubic(_, _, _, _, let midX, let midY) = commands[1] else { return }
        #expect(abs(midX - 10) < 1e-9)
        #expect(abs(midY) < 1e-9)
    }

    @Test func packedArcFlags() throws {
        let commands = try VectorPathParser.parse("M0 0a5 5 0 1020 0")
        #expect(commands.count >= 2)
    }

    @Test func rejectsGarbage() {
        #expect(throws: VectorPathError.self) { try VectorPathParser.parse("10 10") }
        #expect(throws: VectorPathError.self) { try VectorPathParser.parse("M10") }
    }

    @Test func everyBundledDrawingParses() throws {
        let library: [VectorArt] = [
            VectorLibrary.markLoop, VectorLibrary.markInk, VectorLibrary.lockupLoop, VectorLibrary.lockupInk,
            VectorLibrary.markMono, VectorLibrary.illustrationChats, VectorLibrary.illustrationSchedule,
            VectorLibrary.illustrationCaughtUp, VectorLibrary.illustrationSearch, VectorLibrary.illustrationBookmarks,
            VectorLibrary.illustrationActivity, VectorLibrary.illustrationConnections,
        ]
        for art in library {
            #expect(!art.paths.isEmpty)
            for path in art.paths {
                let commands = try VectorPathParser.parse(path.data)
                #expect(!commands.isEmpty)
                if case .move = commands.first {} else { Issue.record("path does not start with a move") }
            }
        }
        #expect(VectorLibrary.illustrationChats.viewportWidth == 120)
        #expect(VectorLibrary.markLoop.paths.allSatisfy { $0.paint == .brandGradient })
    }
}
