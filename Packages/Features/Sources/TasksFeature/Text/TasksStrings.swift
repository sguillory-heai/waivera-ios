import Foundation

/// User-facing copy for Tasks and Requests. Values live in `Localizable.strings`; this file is
/// Foundation-only so the copy rules are unit tested on Linux.
enum TasksStrings {
    static func text(_ key: String) -> String {
        NSLocalizedString(key, bundle: .module, comment: "")
    }

    /// Fills `%@` and positional `%1$@` placeholders in order. Arguments are passed as text so
    /// the same code runs where `String` is not a `CVarArg`.
    static func format(_ key: String, _ arguments: String...) -> String {
        fill(text(key), arguments)
    }

    /// Keys end in `.one` and `.other`; the count is the first argument.
    static func plural(_ key: String, _ count: Int, _ more: String...) -> String {
        fill(text(count == 1 ? "\(key).one" : "\(key).other"), [String(count)] + more)
    }

    static func fill(_ template: String, _ arguments: [String]) -> String {
        var result = ""
        var index = template.startIndex
        var next = 0
        while index < template.endIndex {
            let character = template[index]
            guard character == "%", let (argument, end) = placeholder(in: template, at: index, next: &next) else {
                result.append(character)
                index = template.index(after: index)
                continue
            }
            if let argument {
                result += argument < arguments.count ? arguments[argument] : ""
            } else {
                result.append("%")
            }
            index = end
        }
        return result
    }

    private static func placeholder(
        in template: String,
        at start: String.Index,
        next: inout Int
    ) -> (Int?, String.Index)? {
        var cursor = template.index(after: start)
        guard cursor < template.endIndex else { return nil }
        if template[cursor] == "%" { return (nil, template.index(after: cursor)) }
        var digits = ""
        while cursor < template.endIndex, let digit = template[cursor].wholeNumberValue {
            digits.append(String(digit))
            cursor = template.index(after: cursor)
        }
        var position: Int?
        if !digits.isEmpty {
            guard cursor < template.endIndex, template[cursor] == "$", let number = Int(digits) else { return nil }
            position = number - 1
            cursor = template.index(after: cursor)
        }
        for specifier in ["@", "ld", "d"] where template[cursor...].hasPrefix(specifier) {
            let end = template.index(cursor, offsetBy: specifier.count)
            let argument = position ?? next
            next = argument + 1
            return (argument, end)
        }
        return nil
    }
}
