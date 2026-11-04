import Foundation
import WaiveraAPI
import WaiveraData

/// Edit and Cancel for your own one-off event; everything else is changed on the web calendar.
extension CalendarEventModel {
    static let webCalendarPath = "/calendar"

    /// The event the Edit sheet opens on; nil unless the phone may edit it.
    public var editableEvent: CalendarEvent? {
        guard case .loaded(let details) = state, details.manage == .edit else { return nil }
        return found
    }

    /// The web calendar on the configured web app's own host; nil when this build has none.
    public var webCalendarURL: URL? {
        guard let base = webBaseURL, let url = URL(string: Self.webCalendarPath, relativeTo: base)?.absoluteURL,
            url.host == base.host, WebLinks.isWebURL(url)
        else { return nil }
        return url
    }

    /// The confirmation sheet's Cancel event. The screen closes once the server agrees; a failure
    /// keeps the event and says so.
    public func cancelEvent() {
        guard case .loaded(let details) = state, details.manage == .edit, !interaction.cancelling else { return }
        interaction.cancelling = true
        interaction.cancelFailed = false
        rebuild()
        let calendar = calendar
        let eventID = eventID
        cancelTask?.cancel()
        cancelTask = Task {
            do {
                try await calendar.cancelEvent(id: eventID)
                self.cancelFinished(failed: false)
            } catch {
                self.cancelFinished(failed: true)
            }
        }
    }

    public func dismissCancelFailure() {
        interaction.cancelFailed = false
        rebuild()
    }

    public func closeHandled() { closeRequest = nil }

    private func cancelFinished(failed: Bool) {
        interaction.cancelling = false
        interaction.cancelFailed = failed
        if failed {
            failureTicks += 1
        } else {
            closeRequest = UUID()
        }
        rebuild()
    }
}
