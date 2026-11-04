#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    struct TasksListActions {
        var open: (Int) -> Void = { _ in }
        var setWindow: (TaskWindow) -> Void = { _ in }
        var setAssignedToMe: (Bool) -> Void = { _ in }
        var setDelays: (DelayFilter) -> Void = { _ in }
        var loadMore: () -> Void = {}
        var retry: () -> Void = {}
    }
#endif
