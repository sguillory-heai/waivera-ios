#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    struct TaskDetailActions {
        var log: () -> Void = {}
        var ask: () -> Void = {}
        var openWeb: () -> Void = {}
        var retry: () -> Void = {}
        var retryActivity: () -> Void = {}
        var openFile: (FileRow) -> Void = { _ in }
        var retryFiles: () -> Void = {}
        var uploads = UploadActions()
        var review = ReviewBarActions()
    }
#endif
