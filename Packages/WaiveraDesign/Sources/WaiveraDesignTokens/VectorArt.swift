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
    case quad(x1: Double, y1: Double, x: Double, y: Double)
    case cubic(x1: Double, y1: Double, x2: Double, y2: Double, x: Double, y: Double)
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
        var scanner = NumberScanner(Array(data.unicodeScalars))
        var commands: [PathCommand] = []
        var current = (x: 0.0, y: 0.0)
        var subpathStart = (x: 0.0, y: 0.0)
        var lastCubicControl: (x: Double, y: Double)?
        var lastQuadControl: (x: Double, y: Double)?
        var command: Character?

        while true {
            scanner.skipSeparators()
            guard let next = scanner.peek else { break }
            if next.properties.isAlphabetic {
                command = Character(next)
                scanner.advance()
            } else if command == nil {
                throw VectorPathError.unexpectedCharacter(Character(next))
            }
            guard let active = command else { break }
            let relative = active.isLowercase
            let base = relative ? current : (x: 0.0, y: 0.0)
            func number() throws -> Double {
                guard let value = scanner.number() else { throw VectorPathError.missingNumber(command: active) }
                return value
            }
            func point() throws -> (x: Double, y: Double) {
                let x = try number()
                let y = try number()
                return (base.x + x, base.y + y)
            }
            var cubicControl: (x: Double, y: Double)?
            var quadControl: (x: Double, y: Double)?

            switch active.uppercased() {
            case "M":
                let target = try point()
                commands.append(.move(x: target.x, y: target.y))
                current = target
                subpathStart = target
                // Further pairs after a move are implicit lines.
                command = relative ? "l" : "L"
            case "L":
                let target = try point()
                commands.append(.line(x: target.x, y: target.y))
                current = target
            case "H":
                let x = try number() + (relative ? current.x : 0)
                commands.append(.line(x: x, y: current.y))
                current.x = x
            case "V":
                let y = try number() + (relative ? current.y : 0)
                commands.append(.line(x: current.x, y: y))
                current.y = y
            case "C":
                let first = try point()
                let second = try point()
                let target = try point()
                commands.append(.cubic(x1: first.x, y1: first.y, x2: second.x, y2: second.y, x: target.x, y: target.y))
                cubicControl = second
                current = target
            case "S":
                let first = reflect(lastCubicControl, about: current)
                let second = try point()
                let target = try point()
                commands.append(.cubic(x1: first.x, y1: first.y, x2: second.x, y2: second.y, x: target.x, y: target.y))
                cubicControl = second
                current = target
            case "Q":
                let control = try point()
                let target = try point()
                commands.append(.quad(x1: control.x, y1: control.y, x: target.x, y: target.y))
                quadControl = control
                current = target
            case "T":
                let control = reflect(lastQuadControl, about: current)
                let target = try point()
                commands.append(.quad(x1: control.x, y1: control.y, x: target.x, y: target.y))
                quadControl = control
                current = target
            case "A":
                let radiusX = try number()
                let radiusY = try number()
                let rotation = try number()
                let largeArc = try scanner.flag(command: active)
                let sweep = try scanner.flag(command: active)
                let target = try point()
                commands += ArcConverter.cubics(
                    from: current,
                    to: target,
                    radiusX: radiusX,
                    radiusY: radiusY,
                    rotationDegrees: rotation,
                    largeArc: largeArc,
                    sweep: sweep
                )
                current = target
            case "Z":
                commands.append(.close)
                current = subpathStart
                command = nil
            default:
                throw VectorPathError.unexpectedCharacter(active)
            }
            lastCubicControl = cubicControl
            lastQuadControl = quadControl
        }
        return commands
    }

    private static func reflect(
        _ control: (x: Double, y: Double)?,
        about point: (x: Double, y: Double)
    ) -> (x: Double, y: Double) {
        guard let control else { return point }
        return (2 * point.x - control.x, 2 * point.y - control.y)
    }
}

/// Endpoint-parameterised SVG arcs to cubic Béziers (SVG 1.1 appendix F.6), one curve per
/// quarter turn or less.
enum ArcConverter {
    static func cubics(
        from start: (x: Double, y: Double),
        to end: (x: Double, y: Double),
        radiusX: Double,
        radiusY: Double,
        rotationDegrees: Double,
        largeArc: Bool,
        sweep: Bool
    ) -> [PathCommand] {
        if start == end { return [] }
        var rx = abs(radiusX)
        var ry = abs(radiusY)
        if rx == 0 || ry == 0 { return [.line(x: end.x, y: end.y)] }
        let phi = rotationDegrees * .pi / 180
        let cosPhi = cos(phi)
        let sinPhi = sin(phi)
        let dx = (start.x - end.x) / 2
        let dy = (start.y - end.y) / 2
        let x1p = cosPhi * dx + sinPhi * dy
        let y1p = -sinPhi * dx + cosPhi * dy
        let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
        if lambda > 1 {
            rx *= lambda.squareRoot()
            ry *= lambda.squareRoot()
        }
        let numerator = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p
        let denominator = rx * rx * y1p * y1p + ry * ry * x1p * x1p
        var factor = (max(0, numerator) / denominator).squareRoot()
        if largeArc == sweep { factor = -factor }
        let cxp = factor * rx * y1p / ry
        let cyp = -factor * ry * x1p / rx
        let cx = cosPhi * cxp - sinPhi * cyp + (start.x + end.x) / 2
        let cy = sinPhi * cxp + cosPhi * cyp + (start.y + end.y) / 2

        func angle(_ ux: Double, _ uy: Double, _ vx: Double, _ vy: Double) -> Double {
            atan2(ux * vy - uy * vx, ux * vx + uy * vy)
        }
        let theta1 = angle(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
        var delta = angle((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry)
        if !sweep && delta > 0 { delta -= 2 * .pi }
        if sweep && delta < 0 { delta += 2 * .pi }

        let segments = max(1, Int((abs(delta) / (.pi / 2)).rounded(.up)))
        let step = delta / Double(segments)
        let handle = 4.0 / 3.0 * tan(step / 4)
        func point(_ theta: Double) -> (x: Double, y: Double) {
            let x = rx * cos(theta)
            let y = ry * sin(theta)
            return (cosPhi * x - sinPhi * y + cx, sinPhi * x + cosPhi * y + cy)
        }
        func derivative(_ theta: Double) -> (x: Double, y: Double) {
            let x = -rx * sin(theta)
            let y = ry * cos(theta)
            return (cosPhi * x - sinPhi * y, sinPhi * x + cosPhi * y)
        }
        var result: [PathCommand] = []
        var theta = theta1
        for index in 0..<segments {
            let next = theta + step
            let from = point(theta)
            let to = index == segments - 1 ? end : point(next)
            let d1 = derivative(theta)
            let d2 = derivative(next)
            result.append(
                .cubic(
                    x1: from.x + handle * d1.x,
                    y1: from.y + handle * d1.y,
                    x2: to.x - handle * d2.x,
                    y2: to.y - handle * d2.y,
                    x: to.x,
                    y: to.y
                )
            )
            theta = next
        }
        return result
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
