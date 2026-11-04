#if canImport(UIKit)
    import ImageIO
    import PDFKit
    import SwiftUI
    import UIKit
    import WaiveraData
    import WaiveraDesign

    /// The image, decoded at most 2048 pixels on its long side so a phone photo never runs memory
    /// out, in a scroll view that zooms by pinch and double tap.
    struct ZoomableImageView: UIViewRepresentable {
        static let maxPixels = 2_048
        static let maxZoom: CGFloat = 5

        let data: Data

        func makeCoordinator() -> Coordinator { Coordinator() }

        func makeUIView(context: Context) -> UIScrollView {
            let scroll = UIScrollView()
            scroll.minimumZoomScale = 1
            scroll.maximumZoomScale = Self.maxZoom
            scroll.showsHorizontalScrollIndicator = false
            scroll.showsVerticalScrollIndicator = false
            scroll.delegate = context.coordinator
            let imageView = UIImageView(image: Self.decode(data))
            imageView.contentMode = .scaleAspectFit
            imageView.isAccessibilityElement = true
            imageView.accessibilityTraits = .image
            imageView.frame = scroll.bounds
            imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            scroll.addSubview(imageView)
            context.coordinator.imageView = imageView
            let doubleTap = UITapGestureRecognizer(
                target: context.coordinator,
                action: #selector(Coordinator.toggleZoom)
            )
            doubleTap.numberOfTapsRequired = 2
            scroll.addGestureRecognizer(doubleTap)
            return scroll
        }

        func updateUIView(_ view: UIScrollView, context: Context) {}

        static func decode(_ data: Data) -> UIImage? {
            let options = [kCGImageSourceShouldCache: false] as CFDictionary
            guard let source = CGImageSourceCreateWithData(data as CFData, options) else { return nil }
            let thumbnail =
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: maxPixels,
                ] as CFDictionary
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnail) else { return nil }
            return UIImage(cgImage: image)
        }

        @MainActor
        final class Coordinator: NSObject, UIScrollViewDelegate {
            weak var imageView: UIImageView?

            func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

            @objc func toggleZoom(_ gesture: UITapGestureRecognizer) {
                guard let scroll = gesture.view as? UIScrollView else { return }
                if scroll.zoomScale > scroll.minimumZoomScale {
                    scroll.setZoomScale(scroll.minimumZoomScale, animated: !UIAccessibility.isReduceMotionEnabled)
                } else {
                    let point = gesture.location(in: imageView)
                    let size = CGSize(width: scroll.bounds.width / 2.5, height: scroll.bounds.height / 2.5)
                    let rect = CGRect(
                        origin: CGPoint(x: point.x - size.width / 2, y: point.y - size.height / 2),
                        size: size
                    )
                    scroll.zoom(to: rect, animated: !UIAccessibility.isReduceMotionEnabled)
                }
            }
        }
    }
#endif
