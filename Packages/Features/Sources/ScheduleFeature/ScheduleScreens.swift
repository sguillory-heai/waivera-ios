import SwiftUI
import WaiveraDesign

/// The Schedule tab root: day, week and month calendar with the day agenda.
public struct ScheduleView: View {
    let onOpenEvent: (_ eventID: String) -> Void

    public init(
        onOpenEvent: @escaping (_ eventID: String) -> Void
    ) {
        self.onOpenEvent = onOpenEvent
    }

    public var body: some View {
        FeaturePlaceholder(
            title: String(localized: "schedule.title", bundle: .module),
            systemImage: "calendar"
        )
    }
}

/// One calendar event: time, place, attendees, Accept/Decline or Join.
public struct CalendarEventView: View {
    let eventID: String
    let onOpenConversation: (_ conversationID: Int) -> Void

    public init(
        eventID: String,
        onOpenConversation: @escaping (_ conversationID: Int) -> Void
    ) {
        self.eventID = eventID
        self.onOpenConversation = onOpenConversation
    }

    public var body: some View {
        FeaturePlaceholder(
            title: String(localized: "schedule.event.title", bundle: .module),
            systemImage: "calendar.badge.clock",
            details: ["eventId \(eventID)"]
        )
    }
}

#Preview("Light") { NavigationStack { ScheduleView(onOpenEvent: { _ in }) } }
#Preview("Dark") {
    NavigationStack { CalendarEventView(eventID: "evt_8f2b19c4", onOpenConversation: { _ in }) }.preferredColorScheme(
        .dark
    )
}
#Preview("AX XXXL") {
    NavigationStack { CalendarEventView(eventID: "evt_8f2b19c4", onOpenConversation: { _ in }) }.dynamicTypeSize(
        .accessibility5
    )
}
