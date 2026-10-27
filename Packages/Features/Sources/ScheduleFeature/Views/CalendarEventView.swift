#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    #if DEBUG
        import WaiveraTestSupport
    #endif

    /// One calendar event (07 §7): time in the schedule zone, invitation answer with Undo,
    /// the join window and meeting handoff, and the attendees.
    public struct CalendarEventView: View {
        let eventID: String
        let onOpenConversation: (_ conversationId: Int) -> Void

        @Environment(\.dataEnvironment) private var data
        @State private var model: CalendarEventModel?

        public init(
            eventID: String,
            onOpenConversation: @escaping (_ conversationId: Int) -> Void
        ) {
            self.eventID = eventID
            self.onOpenConversation = onOpenConversation
        }

        public var body: some View {
            ZStack {
                Palette.background.ignoresSafeArea()
                if let model {
                    CalendarEventModelView(model: model, onOpenConversation: onOpenConversation)
                }
            }
            .navigationTitle(ScheduleStrings.text("schedule.event.title"))
            .navigationBarTitleDisplayMode(.inline)
            .task(id: eventID) {
                if model?.eventID != eventID, let data {
                    model = CalendarEventModel(eventID: eventID, data: data)
                }
            }
        }
    }

    #if DEBUG
        #Preview("Light") {
            NavigationStack { CalendarEventView(eventID: "evt_demo_invite", onOpenConversation: { _ in }) }
                .fakeDataEnvironment()
        }
        #Preview("Dark") {
            NavigationStack { CalendarEventView(eventID: "evt_demo_invite", onOpenConversation: { _ in }) }
                .fakeDataEnvironment()
                .preferredColorScheme(.dark)
        }
        #Preview("AX XXXL") {
            NavigationStack { CalendarEventView(eventID: "evt_demo_checkin", onOpenConversation: { _ in }) }
                .fakeDataEnvironment()
                .dynamicTypeSize(.accessibility5)
        }
    #endif
#endif
