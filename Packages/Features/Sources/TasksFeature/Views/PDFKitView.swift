#if canImport(UIKit)
    import ImageIO
    import PDFKit
    import SwiftUI
    import UIKit
    import WaiveraData
    import WaiveraDesign

    /// PDFKit's own view: continuous pages, pinch to zoom, VoiceOver reads the text layer.
    struct PDFKitView: UIViewRepresentable {
        let data: Data

        func makeUIView(context: Context) -> PDFView {
            let view = PDFView()
            view.autoScales = true
            view.displayMode = .singlePageContinuous
            view.displayDirection = .vertical
            view.backgroundColor = UIColor(Palette.background)
            view.document = PDFDocument(data: data)
            return view
        }

        func updateUIView(_ view: PDFView, context: Context) {}
    }
#endif
