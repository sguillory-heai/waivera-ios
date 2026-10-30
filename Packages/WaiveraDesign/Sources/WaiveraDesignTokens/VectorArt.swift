import Foundation

/// A drawing in its own viewport: the logo layers and the empty-state art, ported from the Android
/// vector drawables so both platforms draw the same shapes. `WaiveraDesign` turns each path into a
/// SwiftUI `Path` and paints it.
public struct VectorArt: Sendable {
    public let viewportWidth: Double
    public let viewportHeight: Double
    public let paths: [VectorPath]

    public init(viewportWidth: Double, viewportHeight: Double, paths: [VectorPath]) {
        self.viewportWidth = viewportWidth
        self.viewportHeight = viewportHeight
        self.paths = paths
    }

    public var aspectRatio: Double { viewportWidth / viewportHeight }
}

public struct VectorPath: Sendable {
    public enum LineCap: Sendable { case butt, round, square }
    public enum LineJoin: Sendable { case miter, round, bevel }

    public enum Style: Sendable {
        case fill(alpha: Double)
        case stroke(width: Double, alpha: Double, cap: LineCap, join: LineJoin)

        public var alpha: Double {
            switch self {
            case .fill(let alpha), .stroke(_, let alpha, _, _): alpha
            }
        }
    }

    /// What a path is painted with. Every art drawable is one white ink with its own alpha steps,
    /// tinted at draw time (violet on the empty-state disc, text or white for the logo); only the
    /// logo's loop carries the brand gradient, which is never tinted.
    public enum Paint: Sendable { case ink, brandGradient }

    /// SVG path data, as in the Android `pathData`.
    public let data: String
    public let style: Style
    public let paint: Paint

    public init(data: String, style: Style, paint: Paint) {
        self.data = data
        self.style = style
        self.paint = paint
    }

    /// The path as absolute commands, or an empty list when the data does not parse.
    public var commands: [PathCommand] { (try? VectorPathParser.parse(data)) ?? [] }
}

/// The logo loop's gradient, in the mark's viewport (Android `logo_mark_loop.xml`): straight down
/// the loop, violet held to 24.5%, then pink, then gold at the base.
public enum LogoGradient {
    public static let start = (x: 24.7288, y: 3.14972)
    public static let end = (x: 24.7288, y: 34.9641)
    public static let stops: [(location: Double, color: RGBColor)] = [
        (0.245234, RGBColor(hex: 0xA640DA)),
        (0.567368, RGBColor(hex: 0xFF6FBC)),
        (1, RGBColor(hex: 0xFFD45C)),
    ]
}

/// One absolute drawing step. Arcs are already converted to cubic curves.
public enum PathCommand: Equatable, Sendable {
    case move(x: Double, y: Double)
    case line(x: Double, y: Double)
    case quad(controlX: Double, controlY: Double, x: Double, y: Double)
    case cubic(control1X: Double, control1Y: Double, control2X: Double, control2Y: Double, x: Double, y: Double)
    case close
}

public enum VectorPathError: Error, Equatable {
    case unexpectedCharacter(Character)
    case missingNumber(command: Character)
}

/// A small SVG path-data parser (M L H V C S Q T A Z, absolute and relative), enough for the
/// Android vector drawables. Smooth curves reflect the previous control point; arcs become cubics.
public enum VectorPathParser {
    public static func parse(_ data: String) throws -> [PathCommand] {
        var reader = PathReader(data)
        return try reader.readAll()
    }
}

/// A point in viewport units.
typealias VectorPoint = (x: Double, y: Double)

/// The parser's running state: the pen position, the open subpath and the control points a
/// smooth curve reflects.
private struct PathReader {
    private var scanner: NumberScanner
    private var commands: [PathCommand] = []
    private var current: VectorPoint = (0, 0)
    private var subpathStart: VectorPoint = (0, 0)
    /// The command letter that repeats while numbers follow it; nil after a close.
    private var command: Character?
    private var active: Character = "M"
    private var lastCubicControl: VectorPoint?
    private var lastQuadControl: VectorPoint?
    private var cubicControl: VectorPoint?
    private var quadControl: VectorPoint?

    init(_ data: String) {
        scanner = NumberScanner(Array(data.unicodeScalars))
    }

    mutating func readAll() throws -> [PathCommand] {
        while let next = try nextCommand() {
            active = next
            cubicControl = nil
            quadControl = nil
            try apply(relative: next.isLowercase)
            lastCubicControl = cubicControl
            lastQuadControl = quadControl
        }
        return commands
    }

    /// The command for the next group of numbers: a new letter, or the previous one repeated.
    private mutating func nextCommand() throws -> Character? {
        scanner.skipSeparators()
        guard let next = scanner.peek else { return nil }
        if next.properties.isAlphabetic {
            command = Character(next)
            scanner.advance()
        } else if command == nil {
            throw VectorPathError.unexpectedCharacter(Character(next))
        }
        return command
    }

    private mutating func apply(relative: Bool) throws {
        switch active.uppercased() {
        case "M":
            try moveTo(relative: relative)
        case "L", "H", "V":
            try lineTo(active.uppercased(), relative: relative)
        case "C", "S":
            try cubicTo(smooth: active.uppercased() == "S", relative: relative)
        case "Q", "T":
            try quadTo(smooth: active.uppercased() == "T", relative: relative)
        case "A":
            try arcTo(relative: relative)
        case "Z":
            commands.append(.close)
            current = subpathStart
            command = nil
        default:
            throw VectorPathError.unexpectedCharacter(active)
        }
    }

    private mutating func number() throws -> Double {
        guard let value = scanner.number() else { throw VectorPathError.missingNumber(command: active) }
        return value
    }

    /// The next coordinate pair, made absolute against the pen position for relative commands.
    private mutating func point(relative: Bool) throws -> VectorPoint {
        let base = relative ? current : (x: 0.0, y: 0.0)
        let x = try number()
        let y = try number()
        return (base.x + x, base.y + y)
    }

    private mutating func moveTo(relative: Bool) throws {
        let target = try point(relative: relative)
        commands.append(.move(x: target.x, y: target.y))
        current = target
        subpathStart = target
        // Further pairs after a move are implicit lines.
        command = relative ? "l" : "L"
    }

    private mutating func lineTo(_ kind: String, relative: Bool) throws {
        var target = current
        switch kind {
        case "H": target.x = try number() + (relative ? current.x : 0)
        case "V": target.y = try number() + (relative ? current.y : 0)
        default: target = try point(relative: relative)
        }
        commands.append(.line(x: target.x, y: target.y))
        current = target
    }

    private mutating func cubicTo(smooth: Bool, relative: Bool) throws {
        let first: VectorPoint
        if smooth {
            first = Self.reflect(lastCubicControl, about: current)
        } else {
            first = try point(relative: relative)
        }
        let second = try point(relative: relative)
        let target = try point(relative: relative)
        commands.append(
            .cubic(
                control1X: first.x,
                control1Y: first.y,
                control2X: second.x,
                control2Y: second.y,
                x: target.x,
                y: target.y
            )
        )
        cubicControl = second
        current = target
    }

    private mutating func quadTo(smooth: Bool, relative: Bool) throws {
        let control: VectorPoint
        if smooth {
            control = Self.reflect(lastQuadControl, about: current)
        } else {
            control = try point(relative: relative)
        }
        let target = try point(relative: relative)
        commands.append(.quad(controlX: control.x, controlY: control.y, x: target.x, y: target.y))
        quadControl = control
        current = target
    }

    private mutating func arcTo(relative: Bool) throws {
        let radiusX = try number()
        let radiusY = try number()
        let rotation = try number()
        let largeArc = try scanner.flag(command: active)
        let sweep = try scanner.flag(command: active)
        let target = try point(relative: relative)
        let arc = ArcShape(
            radiusX: radiusX,
            radiusY: radiusY,
            rotationDegrees: rotation,
            largeArc: largeArc,
            sweep: sweep
        )
        commands += ArcConverter.cubics(from: current, to: target, arc: arc)
        current = target
    }

    private static func reflect(_ control: VectorPoint?, about point: VectorPoint) -> VectorPoint {
        guard let control else { return point }
        return (2 * point.x - control.x, 2 * point.y - control.y)
    }
}

private struct NumberScanner {
    private let scalars: [Unicode.Scalar]
    private var index = 0

    init(_ scalars: [Unicode.Scalar]) {
        self.scalars = scalars
    }

    var peek: Unicode.Scalar? { index < scalars.count ? scalars[index] : nil }

    mutating func advance() { index += 1 }

    mutating func skipSeparators() {
        while let scalar = peek, scalar == "," || scalar.properties.isWhitespace { index += 1 }
    }

    /// An arc flag: a single 0 or 1, which SVG allows with no separator after it.
    mutating func flag(command: Character) throws -> Bool {
        skipSeparators()
        guard let scalar = peek, scalar == "0" || scalar == "1" else {
            throw VectorPathError.missingNumber(command: command)
        }
        index += 1
        return scalar == "1"
    }

    /// A number such as `-1.5e-3`, `.5` or `1.5.5` (two numbers), or nil.
    mutating func number() -> Double? {
        skipSeparators()
        let start = index
        if let sign = peek, sign == "-" || sign == "+" { index += 1 }
        var sawDigit = false
        var sawDot = false
        while let scalar = peek {
            if ("0"..."9").contains(scalar) {
                sawDigit = true
            } else if scalar == ".", !sawDot {
                sawDot = true
            } else {
                break
            }
            index += 1
        }
        guard sawDigit else {
            index = start
            return nil
        }
        if let exponent = peek, exponent == "e" || exponent == "E" {
            let mark = index
            index += 1
            if let sign = peek, sign == "-" || sign == "+" { index += 1 }
            var exponentDigits = false
            while let scalar = peek, ("0"..."9").contains(scalar) {
                exponentDigits = true
                index += 1
            }
            if !exponentDigits { index = mark }
        }
        let text = String(String.UnicodeScalarView(scalars[start..<index]))
        return Double(text)
    }
}
