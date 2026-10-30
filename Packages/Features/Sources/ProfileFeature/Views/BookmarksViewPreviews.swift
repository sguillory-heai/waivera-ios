#if DEBUG && canImport(UIKit)
    import SwiftUI
    import WaiveraAPI
    import WaiveraData
    import WaiveraDesign
    import WaiveraTestSupport

    @MainActor private func bookmarksPreview() -> BookmarksDisplayState {
        var state = BookmarksDisplayState()
        state.rows = BookmarkRules.rows(DemoData.make().bookmarks)
        state.totalCount = state.rows.count
        state.phase = state.rows.isEmpty ? .empty : .content
        state.now = DemoData.now
        return state
    }

    #Preview("Light") {
        NavigationStack { BookmarksView(onOpenMessage: { _, _, _ in }) }.fakeDataEnvironment()
    }
    #Preview("Dark") {
        NavigationStack { BookmarksContentView(state: bookmarksPreview(), actions: BookmarksActions()) }
            .preferredColorScheme(.dark)
    }
    #Preview("AX XXXL") {
        NavigationStack { BookmarksContentView(state: bookmarksPreview(), actions: BookmarksActions()) }
            .dynamicTypeSize(.accessibility5)
    }
    #Preview("Empty") {
        NavigationStack { BookmarksView(onOpenMessage: { _, _, _ in }) }.fakeDataEnvironment(.empty)
    }
#endif
