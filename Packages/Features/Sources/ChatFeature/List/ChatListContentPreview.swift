#if DEBUG && canImport(UIKit)
    import SwiftUI

    struct ChatListContentPreview: View {
        let state: ChatListState
        var showsSkeleton = false
        @State private var query = ""
        @State private var filter = ChatListFilter.all

        var body: some View {
            NavigationStack {
                ChatListContentView(
                    state: state,
                    query: $query,
                    filter: $filter,
                    account: ChatListAccount(name: "Alex Rivera", onOpen: {}),
                    showsSkeletonImmediately: showsSkeleton,
                    showsConnectingPillImmediately: true
                )
                .toolbar(.hidden, for: .navigationBar)
            }
        }
    }

    #Preview("Light, rows") { ChatListContentPreview(state: ChatListPreviewData.state) }
    #Preview("Dark, caught up, connecting") {
        ChatListContentPreview(state: ChatListPreviewData.state(.empty(.allCaughtUp), connection: .connecting))
            .preferredColorScheme(.dark)
    }
    #Preview("AX5, long names") {
        ChatListContentPreview(state: ChatListPreviewData.longNames)
            .dynamicTypeSize(.accessibility5)
    }
    #Preview("Light, skeleton") {
        ChatListContentPreview(state: ChatListPreviewData.state(.loading), showsSkeleton: true)
    }
    #Preview("Light, error") {
        ChatListContentPreview(state: ChatListPreviewData.state(.error(.offline), connection: .offline))
    }
#endif
