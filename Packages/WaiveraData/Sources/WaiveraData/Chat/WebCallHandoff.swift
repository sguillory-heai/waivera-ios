import Foundation
import WaiveraAPI

/// Builds the web lobby URL for calls and Waivera meetings (03 §19, 07 §7). There is no native
/// calling; the encoding is the web contract, including the `calenderEventId` spelling.
public struct WebCallHandoff: Sendable {
    public let webBaseURL: URL?
    private let api: APIClient

    public init(webBaseURL: URL?, api: APIClient) {
        self.webBaseURL = webBaseURL
        self.api = api
    }

    /// Joins the conversation's live room, or creates one as the publisher.
    public func url(for conversation: Conversation) async throws -> URL {
        guard let webBaseURL else { throw WaiveraError.configurationMissing }
        let roomId: String
        let calendarEventId: String?
        let isPublisher: Bool
        if let room = conversation.activeCall {
            (roomId, calendarEventId, isPublisher) = (room.roomId, room.calendarEventId, false)
        } else {
            let meeting = try await api.createMeetingRoom(
                CreateMeetingRoomRequest(calendarEventId: nil, conversationId: conversation.id)
            )
            guard let room = meeting.roomId else { throw WaiveraError.invalidResponse }
            (roomId, calendarEventId, isPublisher) = (room, meeting.calendarEventId, meeting.isPublisher ?? false)
        }
        let state = LobbyState(
            calendarEventId: calendarEventId,
            conversationId: String(conversation.id),
            isPublisher: isPublisher,
            isOneToOneCall: conversation.participants.count == 2
        )
        guard let url = Self.lobbyURL(base: webBaseURL, roomId: roomId, state: state) else {
            throw WaiveraError.invalidResponse
        }
        return url
    }

    /// A Waivera meeting from the calendar always creates or fetches the room.
    public func url(for event: CalendarEvent) async throws -> URL {
        guard let webBaseURL else { throw WaiveraError.configurationMissing }
        let meeting = try await api.createMeetingRoom(
            CreateMeetingRoomRequest(calendarEventId: event.id, conversationId: nil)
        )
        guard let roomId = meeting.roomId else { throw WaiveraError.invalidResponse }
        let state = LobbyState(
            calendarEventId: event.id,
            conversationId: nil,
            isPublisher: meeting.isPublisher ?? false,
            isOneToOneCall: false
        )
        guard let url = Self.lobbyURL(base: webBaseURL, roomId: roomId, state: state) else {
            throw WaiveraError.invalidResponse
        }
        return url
    }

    public struct LobbyState: Sendable, Equatable {
        public var calendarEventId: String?
        public var conversationId: String?
        public var isPublisher: Bool
        public var isOneToOneCall: Bool

        /// `JSON.stringify` of the web's state object, keys in the web's order.
        var json: String {
            "{\"calenderEventId\":\(Self.literal(calendarEventId)),"
                + "\"relatedChatConversationId\":\(Self.literal(conversationId)),"
                + "\"isPublisher\":\(isPublisher),\"isOneToOneCall\":\(isOneToOneCall)}"
        }

        private static func literal(_ value: String?) -> String {
            guard let value, let data = try? JSONEncoder().encode(value), let text = String(data: data, encoding: .utf8)
            else { return "null" }
            return text
        }
    }

    /// `{web}/lobby/{encodeURIComponent(roomId)}?state={encodeURIComponent(base64(encodeURIComponent(json)))}`.
    public static func lobbyURL(base: URL, roomId: String, state: LobbyState) -> URL? {
        let encodedState = Data(encodeURIComponent(state.json).utf8).base64EncodedString()
        let path = "lobby/\(encodeURIComponent(roomId))?state=\(encodeURIComponent(encodedState))"
        let root = base.absoluteString.hasSuffix("/") ? base.absoluteString : base.absoluteString + "/"
        return URL(string: root + path)
    }

    /// JavaScript `encodeURIComponent`.
    static func encodeURIComponent(_ value: String) -> String {
        var allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        allowed.insert(charactersIn: "-_.!~*'()")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}
