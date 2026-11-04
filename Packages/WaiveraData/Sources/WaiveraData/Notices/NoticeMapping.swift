import Foundation
import WaiveraAPI

/// Turns the web's notification rows into `Notice`s. The web renders `{task}`, `{author}` and
/// `{activity}` from the resources as links; the phone fills them as plain text and drops any it
/// cannot fill, so a row never shows braces. Mirrors Android `NoticeMapping` and sprout_api
/// `MobilePushNotificationService.InboxPush`.
public enum NoticeMapping {
    public static func notice(_ dto: EventNotificationResponse) -> Notice? {
        guard !dto.id.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        let resources = dto.notificationResources
        let taskId = resource("task", in: resources).flatMap { taskNumber(in: $0.resourceId) }
        let eventId =
            resource("meeting", in: resources).flatMap { eventQuery(in: $0.resourceId) }
            ?? dto.actionUrl.flatMap { $0.hasPrefix("/calendar") ? eventQuery(in: $0) : nil }
        // Admin requests name their type ("Task Extension Request"); a pending one asks this person to review it.
        let request = isRequestType(dto.type)
        let reviewing = request && dto.status?.caseInsensitiveCompare("PENDING") == .orderedSame
        let kind: NoticeKind =
            if reviewing { .approval } else if request { requestOutcomeKind(dto.type, taskId: taskId) } else {
                kind(type: dto.type, resources: resources)
            }
        return Notice(
            id: dto.id,
            kind: kind,
            title: render(dto.title, resources: resources, author: dto.createdByName),
            message: render(dto.message, resources: resources, author: dto.createdByName),
            createdAt: dto.createdAt,
            isRead: dto.read,
            taskId: taskId,
            eventId: eventId,
            webPath: webPath(dto.actionUrl, resources: resources),
            opensRequests: reviewing
        )
    }

    /// Fills `{task}`, `{author}` and `{activity}` and drops any other `{word}`.
    public static func render(_ template: String?, resources: [NotificationResourceDto], author: String? = nil)
        -> String
    {
        guard let template, !template.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }
        func named(_ type: String) -> String? {
            let name = resource(type, in: resources)?.resourceName?.trimmingCharacters(in: .whitespacesAndNewlines)
            return name?.isEmpty == false ? name : nil
        }
        let tokens: [String: String?] = [
            "task": named("task"), "author": named("user") ?? author, "activity": named("task_action"),
        ]
        var out = ""
        var index = template.startIndex
        while index < template.endIndex {
            if template[index] == "{", let close = template[index...].firstIndex(of: "}") {
                let word = template[template.index(after: index)..<close]
                if !word.isEmpty, word.allSatisfy({ $0.isASCII && $0.isLetter }) {
                    out += (tokens[word.lowercased()] ?? nil) ?? ""
                    index = template.index(after: close)
                    continue
                }
            }
            out.append(template[index])
            index = template.index(after: index)
        }
        return out.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" }).joined(separator: " ")
    }

    // MARK: Private

    private static func resource(_ type: String, in resources: [NotificationResourceDto]) -> NotificationResourceDto? {
        resources.first { $0.resourceType.caseInsensitiveCompare(type) == .orderedSame }
    }

    /// `/task/123…` → `123`.
    static func taskNumber(in path: String) -> String? {
        guard path.hasPrefix("/task/") else { return nil }
        let digits = path.dropFirst("/task/".count).prefix { $0.isASCII && $0.isNumber }
        return digits.isEmpty ? nil : String(digits)
    }

    /// `?eventId=` or `&eventId=` with an id of up to 128 safe characters.
    static func eventQuery(in text: String) -> String? {
        for marker in ["?eventId=", "&eventId="] {
            guard let range = text.range(of: marker) else { continue }
            let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.:-")
            let id = text[range.upperBound...].prefix { allowed.contains($0) }.prefix(128)
            if !id.isEmpty { return String(id) }
        }
        return nil
    }

    private static func isRequestType(_ type: String?) -> Bool {
        guard let raw = type?.trimmingCharacters(in: .whitespaces).lowercased(), !raw.isEmpty else { return false }
        return RequestKind(typeName: raw) != .other || (raw.hasSuffix(" request") && !raw.hasPrefix("task."))
    }

    /// A decided request reads as news about its task, or as time off.
    private static func requestOutcomeKind(_ type: String?, taskId: String?) -> NoticeKind {
        if type?.lowercased().contains("time off") == true { return .timeOff }
        return taskId != nil ? .taskActivity : .other
    }

    /// Only same-site paths, never a full URL, so a row can only open the configured web app.
    private static func webPath(_ actionUrl: String?, resources: [NotificationResourceDto]) -> String? {
        let webTypes: Set<String> = ["task", "task_action", "launchsurvey", "file", "meeting"]
        let candidates =
            [actionUrl].compactMap(\.self)
            + resources.filter { webTypes.contains($0.resourceType.lowercased()) }.map(\.resourceId)
        return candidates.first { $0.hasPrefix("/") && !$0.hasPrefix("//") }
    }

    /// The type names the kind; when it is unknown, the resources it links to do.
    private static func kind(type: String?, resources: [NotificationResourceDto]) -> NoticeKind {
        kindOfType((type ?? "").lowercased()) ?? kindOfResources(resources) ?? .other
    }

    private static func kindOfType(_ type: String) -> NoticeKind? {
        if type == "task.assigned" || type == "participant_assignment" { return .taskAssigned }
        if type == "task.approval_requested" || type.contains("approval") { return .approval }
        if type.hasPrefix("task.") { return .taskActivity }
        if type.contains("signature") || type.contains("esign") { return .signature }
        if type.contains("survey") { return .survey }
        if type == "meeting" { return .meeting }
        if type.contains("time-off") || type.contains("timeoff") || type.contains("leave") { return .timeOff }
        return nil
    }

    private static func kindOfResources(_ resources: [NotificationResourceDto]) -> NoticeKind? {
        func has(_ type: String) -> Bool { resource(type, in: resources) != nil }
        if has("launchsurvey") { return .survey }
        if has("meeting") { return .meeting }
        if has("task") { return .taskActivity }
        return nil
    }
}
