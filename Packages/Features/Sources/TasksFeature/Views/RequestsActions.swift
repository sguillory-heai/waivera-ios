#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    struct RequestsActions {
        var review: (RequestItem) -> Void = { _ in }
        /// One of your own: opens its task, or the web when it has none.
        var openOwn: (RequestItem) -> Void = { _ in }
        var openMine: () -> Void = {}
        var openWeb: () -> Void = {}
        var retryWaiting: () -> Void = {}
        var retryMine: () -> Void = {}
    }
#endif
