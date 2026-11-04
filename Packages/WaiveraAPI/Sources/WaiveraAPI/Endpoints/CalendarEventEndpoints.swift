import Foundation

/// The quick event writes (`CalendarEventController.cs`): create, update and cancel one-off
/// events, and the invite directory. Each write can answer 200 with `success: false`.
extension APIClient {
    public func createCalendarEvent(_ body: CalendarEventDto) async throws {
        try await checkEnvelope(try .json(.post, "api/CalendarEvent/CreateEvent", body: body))
    }

    /// No `scope`: the phone only edits one-off events.
    public func updateCalendarEvent(id: String, _ body: CalendarEventDto) async throws {
        try await checkEnvelope(try .json(.put, "api/CalendarEvent/UpdateEventbyId/\(escape(id))", body: body))
    }

    public func deleteCalendarEvent(id: String) async throws {
        try await checkEnvelope(
            APIRequest(
                .delete,
                "api/CalendarEvent/DeleteEvent/\(escape(id))",
                query: [URLQueryItem(name: "deleteScope", value: "single")]
            )
        )
    }

    /// Coworkers and participants the employee can invite; `mode=edit` with the event id keeps
    /// the people already invited in the list.
    public func attendeeOptions(eventId: String?) async throws -> CalendarDirectoryOptionsDto {
        var query = [URLQueryItem(name: "mode", value: eventId == nil ? "create" : "edit")]
        if let eventId { query.append(URLQueryItem(name: "eventId", value: eventId)) }
        let options: CalendarDirectoryOptionsDto? = try await envelopedIfPresent(
            APIRequest(.get, "api/CalendarEvent/attendee-options", query: query)
        )
        return options ?? CalendarDirectoryOptionsDto(people: [])
    }
}
