import SwiftUI
import WaiveraDesign

/// The Today tab root: what needs me now, then the next three schedule items.
public struct TodayView: View {
    let onOpenConversation: (_ conversationID: Int, _ targetMessageID: Int?) -> Void
    let onOpenThread: (_ rootMessageID: Int, _ conversationID: Int?, _ targetMessageID: Int?) -> Void
    let onOpenEvent: (_ eventID: String) -> Void
    let onOpenSchedule: () -> Void
    let onOpenActivity: () -> Void

    public init(
        onOpenConversation: @escaping (_ conversationID: Int, _ targetMessageID: Int?) -> Void,
        onOpenThread: @escaping (_ rootMessageID: Int, _ conversationID: Int?, _ targetMessageID: Int?) -> Void,
        onOpenEvent: @escaping (_ eventID: String) -> Void,
        onOpenSchedule: @escaping () -> Void,
        onOpenActivity: @escaping () -> Void
    ) {
        self.onOpenConversation = onOpenConversation
        self.onOpenThread = onOpenThread
        self.onOpenEvent = onOpenEvent
        self.onOpenSchedule = onOpenSchedule
        self.onOpenActivity = onOpenActivity
    }

    public var body: some View {
        FeaturePlaceholder(
            title: String(localized: "today.title", bundle: .module),
            systemImage: "sun.max"
        )
    }
}

/// Full chat activity feed (mentions, replies, reactions), reached from Today.
public struct ActivityView: View {
    let onOpenConversation: (_ conversationID: Int, _ targetMessageID: Int?) -> Void
    let onOpenThread: (_ rootMessageID: Int, _ conversationID: Int?, _ targetMessageID: Int?) -> Void

    public init(
        onOpenConversation: @escaping (_ conversationID: Int, _ targetMessageID: Int?) -> Void,
        onOpenThread: @escaping (_ rootMessageID: Int, _ conversationID: Int?, _ targetMessageID: Int?) -> Void
    ) {
        self.onOpenConversation = onOpenConversation
        self.onOpenThread = onOpenThread
    }

    public var body: some View {
        FeaturePlaceholder(
            title: String(localized: "activity.title", bundle: .module),
            systemImage: "bell.badge"
        )
    }
}

#Preview("Light") {
    NavigationStack {
        TodayView(
            onOpenConversation: { _, _ in },
            onOpenThread: { _, _, _ in },
            onOpenEvent: { _ in },
            onOpenSchedule: {},
            onOpenActivity: {}
        )
    }
}
#Preview("Dark") {
    NavigationStack { ActivityView(onOpenConversation: { _, _ in }, onOpenThread: { _, _, _ in }) }
        .preferredColorScheme(.dark)
}
#Preview("AX XXXL") {
    NavigationStack { ActivityView(onOpenConversation: { _, _ in }, onOpenThread: { _, _, _ in }) }.dynamicTypeSize(
        .accessibility5
    )
}
