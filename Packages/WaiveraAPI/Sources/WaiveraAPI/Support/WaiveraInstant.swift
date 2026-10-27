import Foundation

/// The one timestamp parser for every sprout_api payload (REST and hub).
///
/// Accepts RFC 3339 with `Z` or a numeric offset, and the zone-less form that
/// `timestamp without time zone` columns produce (`"2026-10-20T14:32:11.482913"`),
/// which is a UTC wall clock and is read as UTC (see `spec/contract/dates.md` §3).
/// Fractional seconds may have 0 to 7 digits. Parsing is hand-rolled so it never
/// depends on the device locale, calendar or zone.
public enum WaiveraInstant {
    public static func parse(_ raw: String) -> Date? {
        var scanner = DigitScanner(raw.trimmingCharacters(in: .whitespaces))
        guard let year = scanner.number(digits: 4), scanner.skip("-"),
            let month = scanner.number(digits: 2), scanner.skip("-"),
            let day = scanner.number(digits: 2)
        else { return nil }
        guard scanner.skip("T") || scanner.skip("t") || scanner.skip(" ") else { return nil }
        guard let hour = scanner.number(digits: 2), scanner.skip(":"),
            let minute = scanner.number(digits: 2), scanner.skip(":"),
            let second = scanner.number(digits: 2)
        else { return nil }
        let fraction = scanner.skip(".") ? scanner.fraction() : 0
        guard let offset = scanner.offsetSeconds(), scanner.isAtEnd else { return nil }
        guard (1...12).contains(month), (1...CalendarDate.daysIn(month: month, year: year)).contains(day),
            hour < 24, minute < 60, second < 61
        else { return nil }
        let days = CalendarDate.daysFromCivil(year: year, month: month, day: day)
        let seconds = Double(days * 86_400 + hour * 3_600 + minute * 60 + second - offset) + fraction
        return Date(timeIntervalSince1970: seconds)
    }

    /// Canonical UTC output with millisecond precision, used for query strings and caches.
    public static func format(_ date: Date) -> String {
        let millis = Int64((date.timeIntervalSince1970 * 1_000).rounded(.down))
        let seconds = Int(millis.quotientAndRemainder(dividingBy: 1_000).quotient)
        var remainder = Int(millis - Int64(seconds) * 1_000)
        var wholeSeconds = seconds
        if remainder < 0 {
            remainder += 1_000
            wholeSeconds -= 1
        }
        let days = Int((Double(wholeSeconds) / 86_400).rounded(.down))
        let secondOfDay = wholeSeconds - days * 86_400
        let civil = CalendarDate.civil(fromDays: days)
        let datePart = "\(pad(civil.year, 4))-\(pad(civil.month, 2))-\(pad(civil.day, 2))"
        let hour = secondOfDay / 3_600
        let minute = secondOfDay % 3_600 / 60
        let second = secondOfDay % 60
        return "\(datePart)T\(pad(hour, 2)):\(pad(minute, 2)):\(pad(second, 2)).\(pad(remainder, 3))Z"
    }
}

func pad(_ value: Int, _ width: Int) -> String {
    let digits = String(value)
    return String(repeating: "0", count: max(0, width - digits.count)) + digits
}

/// Minimal cursor over ASCII digits for the fixed-width ISO shapes.
struct DigitScanner {
    private let scalars: [UInt8]
    private var position = 0

    init(_ text: String) {
        scalars = Array(text.utf8)
    }

    var isAtEnd: Bool { position == scalars.count }

    mutating func skip(_ character: Character) -> Bool {
        guard let ascii = character.asciiValue, position < scalars.count, scalars[position] == ascii else {
            return false
        }
        position += 1
        return true
    }

    mutating func number(digits: Int) -> Int? {
        guard position + digits <= scalars.count else { return nil }
        var value = 0
        for offset in 0..<digits {
            let scalar = scalars[position + offset]
            guard (48...57).contains(scalar) else { return nil }
            value = value * 10 + Int(scalar - 48)
        }
        position += digits
        return value
    }

    mutating func fraction() -> Double {
        var value = 0.0
        var scale = 0.1
        while position < scalars.count, (48...57).contains(scalars[position]) {
            value += Double(scalars[position] - 48) * scale
            scale /= 10
            position += 1
        }
        return value
    }

    /// `nil` only when an offset is malformed; a missing offset means UTC.
    mutating func offsetSeconds() -> Int? {
        if isAtEnd { return 0 }
        if skip("Z") || skip("z") { return 0 }
        let sign: Int
        if skip("+") {
            sign = 1
        } else if skip("-") {
            sign = -1
        } else {
            return nil
        }
        guard let hours = number(digits: 2) else { return nil }
        _ = skip(":")
        guard let minutes = number(digits: 2) else { return nil }
        return sign * (hours * 3_600 + minutes * 60)
    }
}
