import Foundation

/// A literal calendar date with no time and no zone: C# `DateOnly`, all-day event
/// bounds, holidays, birthdays and hire dates. It is never converted through an
/// instant, so it cannot drift a day across zones (`spec/contract/dates.md` §1, §3).
public struct CalendarDate: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init?(year: Int, month: Int, day: Int) {
        guard (1...12).contains(month), (1...Self.daysIn(month: month, year: year)).contains(day) else {
            return nil
        }
        self.year = year
        self.month = month
        self.day = day
    }

    private init(unchecked year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// Parses `YYYY-MM-DD`, and also takes the date part of `YYYY-MM-DDT00:00:00`,
    /// which is how `DateTime`-typed birthdays and hire dates arrive.
    public init?(parsing raw: String) {
        var scanner = DigitScanner(raw.trimmingCharacters(in: .whitespaces))
        guard let year = scanner.number(digits: 4), scanner.skip("-"),
            let month = scanner.number(digits: 2), scanner.skip("-"),
            let day = scanner.number(digits: 2),
            scanner.isAtEnd || scanner.skip("T") || scanner.skip(" ")
        else { return nil }
        self.init(year: year, month: month, day: day)
    }

    /// The date a given instant falls on in `timeZone`.
    public init(_ date: Date, in timeZone: TimeZone) {
        let local = date.timeIntervalSince1970 + Double(timeZone.secondsFromGMT(for: date))
        let civil = Self.civil(fromDays: Int((local / 86_400).rounded(.down)))
        self.init(unchecked: civil.year, month: civil.month, day: civil.day)
    }

    public var isoString: String { "\(pad(year, 4))-\(pad(month, 2))-\(pad(day, 2))" }
    public var description: String { isoString }

    /// Days since 1970-01-01.
    public var daysSinceEpoch: Int { Self.daysFromCivil(year: year, month: month, day: day) }

    /// 1 = Sunday … 7 = Saturday, like `Calendar.component(.weekday)` for Gregorian.
    public var weekday: Int {
        // 1970-01-01 was a Thursday (weekday 5).
        let value = (daysSinceEpoch + 4) % 7
        return (value < 0 ? value + 7 : value) + 1
    }

    public func adding(days: Int) -> CalendarDate {
        let civil = Self.civil(fromDays: daysSinceEpoch + days)
        return CalendarDate(unchecked: civil.year, month: civil.month, day: civil.day)
    }

    public func days(until other: CalendarDate) -> Int { other.daysSinceEpoch - daysSinceEpoch }

    /// The Sunday on or before this date (weeks start on Sunday everywhere in Waivera).
    public var startOfWeek: CalendarDate { adding(days: 1 - weekday) }

    public var firstOfMonth: CalendarDate { CalendarDate(unchecked: year, month: month, day: 1) }

    public func addingMonths(_ months: Int) -> CalendarDate {
        let total = year * 12 + (month - 1) + months
        let newYear = Int((Double(total) / 12).rounded(.down))
        let newMonth = total - newYear * 12 + 1
        let newDay = min(day, Self.daysIn(month: newMonth, year: newYear))
        return CalendarDate(unchecked: newYear, month: newMonth, day: newDay)
    }

    /// The first instant of this date in `timeZone`. Local midnight always exists for
    /// the zones Waivera serves; if a zone skips midnight the first valid instant after
    /// it is returned rather than relabelling the wall time.
    public func startInstant(in timeZone: TimeZone) -> Date {
        let utcMidnight = Double(daysSinceEpoch) * 86_400
        var candidate = utcMidnight - Double(timeZone.secondsFromGMT(for: Date(timeIntervalSince1970: utcMidnight)))
        // Re-evaluate once with the offset in force at the candidate itself (DST edges).
        let corrected =
            utcMidnight
            - Double(timeZone.secondsFromGMT(for: Date(timeIntervalSince1970: candidate)))
        if CalendarDate(Date(timeIntervalSince1970: corrected), in: timeZone) == self {
            candidate = corrected
        }
        while CalendarDate(Date(timeIntervalSince1970: candidate), in: timeZone) < self {
            candidate += 1_800
        }
        return Date(timeIntervalSince1970: candidate)
    }

    /// `[start of this date, start of the next date)` in `timeZone`; 23 or 25 hours long on DST days.
    public func interval(in timeZone: TimeZone) -> DateInterval {
        DateInterval(start: startInstant(in: timeZone), end: adding(days: 1).startInstant(in: timeZone))
    }

    public static func < (lhs: CalendarDate, rhs: CalendarDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    public static func isLeapYear(_ year: Int) -> Bool {
        year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
    }

    public static func daysIn(month: Int, year: Int) -> Int {
        switch month {
        case 2: isLeapYear(year) ? 29 : 28
        case 4, 6, 9, 11: 30
        default: 31
        }
    }

    /// Howard Hinnant's days-from-civil, valid for the proleptic Gregorian calendar.
    static func daysFromCivil(year: Int, month: Int, day: Int) -> Int {
        let shiftedYear = month <= 2 ? year - 1 : year
        let era = (shiftedYear >= 0 ? shiftedYear : shiftedYear - 399) / 400
        let yearOfEra = shiftedYear - era * 400
        let dayOfYear = (153 * (month > 2 ? month - 3 : month + 9) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    static func civil(fromDays days: Int) -> (year: Int, month: Int, day: Int) {
        let shifted = days + 719_468
        let era = (shifted >= 0 ? shifted : shifted - 146_096) / 146_097
        let dayOfEra = shifted - era * 146_097
        let yearOfEra = (dayOfEra - dayOfEra / 1_460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let monthPrime = (5 * dayOfYear + 2) / 153
        let day = dayOfYear - (153 * monthPrime + 2) / 5 + 1
        let month = monthPrime < 10 ? monthPrime + 3 : monthPrime - 9
        return (yearOfEra + era * 400 + (month <= 2 ? 1 : 0), month, day)
    }
}

extension CalendarDate: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let value = CalendarDate(parsing: raw) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected YYYY-MM-DD")
        }
        self = value
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(isoString)
    }
}
