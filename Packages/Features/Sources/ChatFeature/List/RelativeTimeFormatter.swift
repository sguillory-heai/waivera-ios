import Foundation

/// Inbox time labels (02 §4 "Timestamp"): Now, minutes, a 12-hour clock for today
/// (11-pitfalls #39), Yesterday, then a short date. Calendar days are taken in the employee's
/// saved zone so the label agrees with the rest of the app, never the device zone. Labels are
/// rebuilt on a shared 30-second clock; the Expo list never ticked.
@MainActor
final class RelativeTimeFormatter {
    /// How often relative labels refresh.
    static let tickInterval: Duration = .seconds(30)

    private let text: any ChatListText
    private let clockFormatter: DateFormatter
    private let dateFormatter: DateFormatter
    private var calendar = Calendar(identifier: .gregorian)

    init(text: any ChatListText, locale: Locale = .current) {
        self.text = text
        clockFormatter = DateFormatter()
        clockFormatter.locale = locale
        clockFormatter.dateFormat = "h:mm a"
        dateFormatter = DateFormatter()
        dateFormatter.locale = locale
        dateFormatter.setLocalizedDateFormatFromTemplate("MMMd")
        calendar.locale = locale
    }

    func label(for date: Date?, now: Date, timeZone: TimeZone) -> String {
        guard let date else { return "" }
        let minutes = max(0, Int(now.timeIntervalSince(date) / 60))
        if minutes < 1 { return text.now }
        if minutes < 60 { return text.minutesAgo(minutes) }
        calendar.timeZone = timeZone
        if calendar.isDate(date, inSameDayAs: now) {
            clockFormatter.timeZone = timeZone
            return clockFormatter.string(from: date)
        }
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)
        if let yesterday, calendar.isDate(date, inSameDayAs: yesterday) {
            return text.yesterday
        }
        dateFormatter.timeZone = timeZone
        return dateFormatter.string(from: date)
    }
}
