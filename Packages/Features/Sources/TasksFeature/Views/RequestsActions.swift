#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    struct RequestsActions {
        var review: (RequestItem) -> Void = { _ in }
        var openWeb: () -> Void = {}
        var retryWaiting: () -> Void = {}
        var retryMine: () -> Void = {}
    }
#endif
