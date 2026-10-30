import Foundation

/// An SVG arc's radii, x-axis rotation and flags.
struct ArcShape {
    var radiusX: Double
    var radiusY: Double
    var rotationDegrees: Double
    var largeArc: Bool
    var sweep: Bool
}

/// Endpoint-parameterised SVG arcs to cubic Béziers (SVG 1.1 appendix F.6), one curve per
/// quarter turn or less.
enum ArcConverter {
    static func cubics(from start: VectorPoint, to end: VectorPoint, arc: ArcShape) -> [PathCommand] {
        if start == end { return [] }
        if arc.radiusX == 0 || arc.radiusY == 0 { return [.line(x: end.x, y: end.y)] }
        let ellipse = ArcEllipse(from: start, to: end, arc: arc)
        let segments = max(1, Int((abs(ellipse.sweepAngle) / (.pi / 2)).rounded(.up)))
        let step = ellipse.sweepAngle / Double(segments)
        let handle = 4.0 / 3.0 * tan(step / 4)
        var result: [PathCommand] = []
        var theta = ellipse.startAngle
        for index in 0..<segments {
            let next = theta + step
            let from = ellipse.point(at: theta)
            let target = index == segments - 1 ? end : ellipse.point(at: next)
            let startTangent = ellipse.derivative(at: theta)
            let endTangent = ellipse.derivative(at: next)
            result.append(
                .cubic(
                    control1X: from.x + handle * startTangent.x,
                    control1Y: from.y + handle * startTangent.y,
                    control2X: target.x - handle * endTangent.x,
                    control2Y: target.y - handle * endTangent.y,
                    x: target.x,
                    y: target.y
                )
            )
            theta = next
        }
        return result
    }
}

/// The centre parameterisation of an endpoint arc (SVG 1.1 F.6.5 and F.6.6): the corrected
/// radii, the centre, and the start angle and signed sweep on the unit circle.
private struct ArcEllipse {
    let radiusX: Double
    let radiusY: Double
    let cosPhi: Double
    let sinPhi: Double
    let center: VectorPoint
    let startAngle: Double
    let sweepAngle: Double

    init(from start: VectorPoint, to end: VectorPoint, arc: ArcShape) {
        var radiusX = abs(arc.radiusX)
        var radiusY = abs(arc.radiusY)
        let phi = arc.rotationDegrees * .pi / 180
        let cosPhi = cos(phi)
        let sinPhi = sin(phi)
        let halfDeltaX = (start.x - end.x) / 2
        let halfDeltaY = (start.y - end.y) / 2
        let x1p = cosPhi * halfDeltaX + sinPhi * halfDeltaY
        let y1p = -sinPhi * halfDeltaX + cosPhi * halfDeltaY
        let lambda = (x1p * x1p) / (radiusX * radiusX) + (y1p * y1p) / (radiusY * radiusY)
        if lambda > 1 {
            radiusX *= lambda.squareRoot()
            radiusY *= lambda.squareRoot()
        }
        let squaredX = radiusX * radiusX
        let squaredY = radiusY * radiusY
        let numerator = squaredX * squaredY - squaredX * y1p * y1p - squaredY * x1p * x1p
        let denominator = squaredX * y1p * y1p + squaredY * x1p * x1p
        var factor = (max(0, numerator) / denominator).squareRoot()
        if arc.largeArc == arc.sweep { factor = -factor }
        let cxp = factor * radiusX * y1p / radiusY
        let cyp = -factor * radiusY * x1p / radiusX
        self.radiusX = radiusX
        self.radiusY = radiusY
        self.cosPhi = cosPhi
        self.sinPhi = sinPhi
        center = (
            cosPhi * cxp - sinPhi * cyp + (start.x + end.x) / 2,
            sinPhi * cxp + cosPhi * cyp + (start.y + end.y) / 2
        )
        let startVector = ((x1p - cxp) / radiusX, (y1p - cyp) / radiusY)
        let endVector = ((-x1p - cxp) / radiusX, (-y1p - cyp) / radiusY)
        startAngle = Self.angle(from: (1, 0), to: startVector)
        var delta = Self.angle(from: startVector, to: endVector)
        if !arc.sweep && delta > 0 { delta -= 2 * .pi }
        if arc.sweep && delta < 0 { delta += 2 * .pi }
        sweepAngle = delta
    }

    func point(at theta: Double) -> VectorPoint {
        let x = radiusX * cos(theta)
        let y = radiusY * sin(theta)
        return (cosPhi * x - sinPhi * y + center.x, sinPhi * x + cosPhi * y + center.y)
    }

    func derivative(at theta: Double) -> VectorPoint {
        let x = -radiusX * sin(theta)
        let y = radiusY * cos(theta)
        return (cosPhi * x - sinPhi * y, sinPhi * x + cosPhi * y)
    }

    /// The signed angle that turns `first` onto `second`.
    private static func angle(from first: VectorPoint, to second: VectorPoint) -> Double {
        atan2(first.x * second.y - first.y * second.x, first.x * second.x + first.y * second.y)
    }
}
