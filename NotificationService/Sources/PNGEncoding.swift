import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// PNG bytes for the sender image handed to the notification.
enum PNGEncoding {
    static func data(_ image: CGImage) -> Data? {
        let output = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                output as CFMutableData,
                UTType.png.identifier as CFString,
                1,
                nil
            )
        else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }
}
