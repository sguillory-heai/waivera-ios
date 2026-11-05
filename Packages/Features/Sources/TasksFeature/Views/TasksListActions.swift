#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    struct TasksListActions {
        var open: (Int) -> Void = { _ in }
        var setWindow: (TaskWindow) -> Void = { _ in }
        var setAssignedToMe: (Bool) -> Void = { _ in }
        var setDelays: (DelayFilter) -> Void = { _ in }
        var showMore: (DueGroup) -> Void = { _ in }
        var showFewer: (DueGroup) -> Void = { _ in }
        var retry: () -> Void = {}
    }
#endif
