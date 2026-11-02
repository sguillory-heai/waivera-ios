import Foundation
import Testing

@testable import WaiveraAPI

/// Payloads shaped like sprout_api's C# types as production sends them (Android
/// `ProdShapeResilienceTest`): nulls where the C# type is a non-nullable reference, omitted
/// fields, zone-less `DateTime`s, `DateOnly` values, `DateTime.MinValue`, enum names the app does
/// not know, and string-encoded documents. Each must decode, never fail the screen.
@Suite("Production-shaped payloads")
struct ProdShapeResilienceTests {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try WaiveraJSON.decoder().decode(type, from: Data(json.utf8))
    }

    @Test func myConversationsWithNullsAndMissingFieldsDecode() throws {
        let json = #"""
            [
              {
                "id": 7,
                "isBotDirect": false,
                "participants": [
                  {"id": "usr_1", "firstName": null, "lastName": null, "email": null,
                   "avatarUrl": null, "isParticipant": false, "isExternal": false, "deactivated": false,
                   "joinDate": "0001-01-01T00:00:00", "organization": null, "roles": null, "regions": null,
                   "participantCount": 0},
                  {"id": null, "displayName": "Former staff"},
                  {"id": "bot:3"}
                ],
                "lastMessage": {
                  "id": 9312, "conversationId": 7, "userId": "usr_1", "author": null,
                  "messageContent": null, "createDate": "2026-10-20T14:32:11.4829133",
                  "messageType": "SYSTEM", "reactions": null, "contentFormat": 1,
                  "messageDoc": "{\"type\":\"doc\",\"content\":[]}", "attachmentScanStatus": "Legacy",
                  "systemEventType": "ticket.updated", "systemEventData": {"ticketId": 12},
                  "threadReplyCount": 0
                },
                "unreadCount": 2,
                "channel": null,
                "activeMeeting": {"id": null, "roomId": null, "calendarEventId": "evt_1",
                  "createdAt": "2026-10-20T14:00:00", "startDate": null, "title": null},
                "ongoingCall": {"roomId": "room_1", "startTime": "2026-10-20T14:30:00Z",
                  "status": "Active", "callRecordId": 55}
              },
              {"id": 8, "participants": null, "lastMessage": null, "lastReadAt": null}
            ]
            """#
        let list = try decode([ConversationResponse].self, json)
        #expect(list.map(\.id) == [7, 8])
        let last = try #require(list[0].lastMessage)
        #expect(last.messageType == .system)
        #expect(last.createDate == WaiveraInstant.parse("2026-10-20T14:32:11.4829133Z"))
        #expect(last.messageDoc != nil, "a string-encoded document is parsed")
        #expect(list[0].ongoingCall?.status == .active)
        #expect((list[1].participants ?? []).isEmpty)
    }

    @Test func allConversationsWithAnUnknownChannelTypeDecode() throws {
        let json = #"""
            {"data": [
              {"conversationId": 41, "isChannel": true, "participants": [], "unreadCount": 0,
               "channel": {"channelId": "ch_1", "conversationId": 41, "name": null, "topic": null,
                           "channelType": "ANNOUNCEMENT", "ownerId": null, "isArchived": false, "canWrite": true},
               "activeMeeting": null, "ongoingCall": null, "lastMessage": null}
            ], "statusCode": 200, "message": "OK", "success": true}
            """#
        let response = try decode(ApiResponse<[ConversationResponse]>.self, json)
        #expect(response.data?.single?.id == 41)
        #expect(response.data?.single?.channel?.channelType == .unknown)
    }

    @Test func userDetailsWithNullListsAndMinValueDatesDecode() throws {
        let json = #"""
            {"data": {"id": "usr_1", "firstName": null, "lastName": "Rivera", "email": null,
              "displayName": null, "deactivated": false, "joinDate": "0001-01-01T00:00:00",
              "hireDate": null, "organizationId": 3, "organizationName": null, "organization": null,
              "organizationRole": null, "roles": null, "regions": null, "teams": null,
              "waiverFamilyIds": null, "timezone": null, "birthday": "1990-02-28T00:00:00"},
             "statusCode": 200, "success": true}
            """#
        let user = try #require(try decode(ApiResponse<UserWithRoleDto>.self, json).data)
        #expect(user.id == "usr_1")
        #expect((user.roles ?? []).isEmpty)
        #expect(user.timezone == nil)
        #expect(user.birthday == CalendarDate(year: 1990, month: 2, day: 28))
    }

    @Test func employeeProfileWithNullListsDecodes() throws {
        let json = #"""
            {"data": {"employeeId": "usr_1", "firstName": "Alex", "positions": null, "reporters": null,
              "regions": null, "agencyNames": null, "joinDate": "2024-01-08T00:00:00", "timezone": null},
             "statusCode": 200, "success": true}
            """#
        let profile = try #require(try decode(ApiResponse<GetEmployeeProfileDto>.self, json).data)
        #expect((profile.positions ?? []).isEmpty)
        #expect((profile.reporters ?? []).isEmpty)
    }

    @Test func calendarFeedWithAllDayEventsAndNullListsDecodes() throws {
        let json = #"""
            {"data": {
              "events": [
                {"cancelledAllDayDates": [], "id": "evt_1", "title": null,
                 "startTime": "2026-11-26T00:00:00", "endTime": "2026-11-27T00:00:00",
                 "ownerUserID": "usr_1", "createdby": null, "attendees": null, "ownerColor": null,
                 "timeOffEmpData": null, "allDayStart": "2026-11-26", "allDayEndExclusive": "2026-11-27",
                 "isInvitationAccept": null, "holidays": null, "meetingType": null, "crossesMidnight": false},
                {"id": "evt_2", "startTime": "2026-11-02T15:00:00Z", "endTime": "2026-11-02T16:00:00Z",
                 "attendees": [{"attendeeId": "att_1", "type": "WAIVER_PARTICIPANT", "ref": null,
                   "inviteStatus": "NEEDS_ACTION", "respondedAt": null}]}
              ],
              "timeOff": null,
              "holidays": [{"id": 4, "title": "Thanksgiving", "description": null,
                "startDate": "2026-11-26T00:00:00", "endDate": "2026-11-27T00:00:00"}]
            }, "statusCode": 200, "success": true}
            """#
        let feed = try #require(try decode(ApiResponse<CalendarFeedResponseDto>.self, json).data)
        #expect(feed.events.count == 2)
        #expect(feed.events[0].allDayStart == CalendarDate(year: 2026, month: 11, day: 26))
        #expect((feed.events[0].attendees ?? []).isEmpty)
        #expect(feed.events[1].attendees?.single?.inviteStatus == .unknown)
        #expect(feed.timeOff.isEmpty)
        #expect(feed.holidays.single?.startDate == CalendarDate(year: 2026, month: 11, day: 26))
    }

    @Test func recentActivityWithAnUnknownTypeDecodes() throws {
        let json = #"""
            [{"id": 900, "activityType": "chat.call_missed", "actorUserId": "usr_2",
              "actorDisplayName": "Someone", "conversationId": 7, "messageId": 9312,
              "threadRootMessageId": null, "reactionType": null, "summary": "",
              "createdAt": "2026-10-20T14:32:11.48", "read": false}]
            """#
        let items = try decode([ChatActivityResponse].self, json)
        #expect(items.single?.activityType == .unknown)
    }
}

extension Array {
    fileprivate var single: Element? { count == 1 ? first : nil }
}
