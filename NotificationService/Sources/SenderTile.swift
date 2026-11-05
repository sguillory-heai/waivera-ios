import CoreGraphics
import CoreText
import Foundation
import WaiveraDesignTokens

/// The person's tile for someone without a photo: the same gradient pair, sheen and white
/// initials the app draws (`AvatarView`, Android `AvatarTiles`). Square, because iOS masks
/// notification sender images itself. Core Graphics only, so it is safe off the main thread.
enum SenderTile {
    static let side = 240

    static func image(name: String) -> Data? {
        let side = CGFloat(Self.side)
        guard
            let canvas = CGContext(
                data: nil,
                width: Self.side,
                height: Self.side,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            )
        else { return nil }
        let pair = AvatarTiles.pair(for: name)
        // Core Graphics counts y from the bottom: the gradient runs top leading to bottom trailing.
        if let fill = gradient([color(pair.start), color(pair.end)]) {
            canvas.drawLinearGradient(fill, start: CGPoint(x: 0, y: side), end: CGPoint(x: side, y: 0), options: [])
        }
        let white = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: AvatarTiles.sheenOpacity)
        if let sheen = gradient([white, white.copy(alpha: 0) ?? white]) {
            let center = CGPoint(x: side / 2, y: side + side * AvatarTiles.sheenCenter)
            canvas.drawRadialGradient(
                sheen,
                startCenter: center,
                startRadius: 0,
                endCenter: center,
                endRadius: side * AvatarTiles.sheenRadius,
                options: []
            )
        }
        drawInitials(AvatarGeometry.initials(for: name), on: canvas, side: side)
        return canvas.makeImage().flatMap(PNGEncoding.data)
    }

    private static func drawInitials(_ initials: String, on canvas: CGContext, side: CGFloat) {
        guard !initials.isEmpty,
            let font = CTFontCreateUIFontForLanguage(
                .emphasizedSystem,
                AvatarGeometry.initialsFontSize(size: side),
                nil
            )
        else { return }
        let text = NSAttributedString(
            string: initials,
            attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(
                    srgbRed: 1,
                    green: 1,
                    blue: 1,
                    alpha: 1
                ),
            ]
        )
        let line = CTLineCreateWithAttributedString(text)
        let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        // Capitals sit centred on their cap height, as the app's initials do.
        let baseline = (side - CTFontGetCapHeight(font)) / 2
        canvas.setShadow(
            offset: CGSize(width: 0, height: -side * AvatarTiles.shadowDrop),
            blur: side * AvatarTiles.shadowBlur,
            color: color(AvatarTiles.shadow)
        )
        canvas.textMatrix = .identity
        canvas.textPosition = CGPoint(x: (side - width) / 2, y: baseline)
        CTLineDraw(line, canvas)
    }

    private static func gradient(_ colors: [CGColor]) -> CGGradient? {
        CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
            colors: colors as CFArray,
            locations: [0, 1]
        )
    }

    private static func color(_ rgb: RGBColor) -> CGColor {
        CGColor(srgbRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: rgb.alpha)
    }
}
