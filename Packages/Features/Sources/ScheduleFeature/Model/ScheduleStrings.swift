import Foundation

/// User-facing schedule copy. Values live in `Resources/en.lproj/Localizable.strings`.
enum ScheduleStrings {
    static func text(_ key: String) -> String {
        NSLocalizedString(key, bundle: .module, comment: "")
    }

    static func format(_ key: String, _ arguments: any CVarArg...) -> String {
        String(format: text(key), locale: Locale.current, arguments: arguments)
    }

    /// "1 event" / "3 events" without a stringsdict, so the copy also resolves on Linux.
    static func count(_ key: String, _ count: Int) -> String {
        count == 1 ? text("\(key).one") : format("\(key).other", count)
    }

    static var title: String { text("schedule.title") }
    static var subtitle: String { text("schedule.subtitle") }
    static var untitledEvent: String { text("schedule.event.untitled") }
    static var eventTitle: String { text("schedule.event.title") }
}
