#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    struct NoticesActions {
        var open: (String) -> Void = { _ in }
        var setFilter: (NoticeFilter) -> Void = { _ in }
        var markAllRead: () -> Void = {}
        var retry: () -> Void = {}
    }
#endif
