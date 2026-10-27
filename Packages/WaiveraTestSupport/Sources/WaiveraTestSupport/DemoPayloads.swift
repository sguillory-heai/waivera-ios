import Foundation

/// Server-shaped payloads that the shared fixtures do not cover, decoded and mapped exactly
/// like live responses. Every name, address and link is fictional.
enum DemoPayloads {
    static let people = """
        [
          {"id":"usr_alex_rivera","firstName":"Alex","lastName":"Rivera","displayName":"Alex Rivera"},
          {"id":"usr_priya_raman","firstName":"Priya","lastName":"Raman","displayName":"Priya Raman"},
          {"id":"usr_jordan_lee","firstName":"Jordan","lastName":"Lee","displayName":"Jordan Lee"},
          {"id":"usr_sam_ortiz","firstName":"Sam","lastName":"Ortiz","displayName":"Sam Ortiz"}
        ]
        """

    /// A group with unread messages and a helpdesk bot with a ticket card.
    static let conversations = """
        [
          {
            "conversationId": 63, "isBotDirect": false, "unreadCount": 2, "isChannel": false,
            "participants": \(people),
            "lastMessage": {"id": 9420, "conversationId": 63, "userId": "usr_jordan_lee",
                            "messageContent": "Van 2 is back at the office", "createDate": "2026-11-01T14:40:00Z"}
          },
          {
            "conversationId": 90, "isBotDirect": true, "unreadCount": 1, "isChannel": false,
            "participants": [{"id":"usr_alex_rivera","firstName":"Alex","lastName":"Rivera"}],
            "lastMessage": \(ticketMessage)
          }
        ]
        """

    static let ticketMessage = """
        {"id": 9500, "conversationId": 90, "botId": "bot:helpdesk", "isBot": true,
         "messageContent": "Ticket T-1042 updated", "createDate": "2026-11-01T14:10:00Z",
         "systemEventType": "ticket.update",
         "systemEventData": "{\\"ticketId\\":\\"T-1042\\",\\"title\\":\\"Replace the badge reader at the north door\\",\
        \\"url\\":\\"https://tickets.example.test/T-1042\\",\\"type\\":\\"Facilities\\",\\"priority\\":\\"high\\",\
        \\"createdBy\\":\\"Priya Raman\\",\\"createdDate\\":\\"10/30/2026\\",\\"dueDateLabel\\":\\"--\\"}"}
        """

    static let groupMessages = """
        [
          {"id": 9418, "conversationId": 63, "userId": "usr_priya_raman", "messageContent": "Who has van 2 today?",
           "createDate": "2026-11-01T14:05:00Z"},
          {"id": 9419, "conversationId": 63, "userId": "usr_alex_rivera", "messageContent": "I do, back by 9",
           "createDate": "2026-11-01T14:07:00Z"},
          {"id": 9420, "conversationId": 63, "userId": "usr_jordan_lee",
           "messageContent": "Van 2 is back at the office", "createDate": "2026-11-01T14:40:00Z",
           "reactions": [{"userId": "usr_alex_rivera", "reactionType": "👍"},
                         {"userId": "usr_sam_ortiz", "reactionType": "👍"}]}
        ]
        """

    /// A finished video call in the 1:1 conversation.
    static let callLog = """
        [
          {"id": 9370, "conversationId": 7, "userId": "usr_priya_raman", "messageType": "SYSTEM", "callRecordId": 77,
           "messageContent": "Video call started", "createDate": "2026-10-31T21:00:00Z"},
          {"id": 9371, "conversationId": 7, "userId": "usr_priya_raman", "messageType": "SYSTEM", "callRecordId": 77,
           "messageContent": "Video call ended", "createDate": "2026-10-31T21:12:00Z"}
        ]
        """

    /// Today in America/Chicago (1 November 2026, the day DST ends): an all-day event, a shift
    /// that crosses the repeated hour, a pending invitation and an accepted meeting.
    static let todaysEvents = """
        [
          {"id": "evt_demo_allday", "title": "Quarterly compliance day", "startTime": "2026-11-01T05:00:00Z",
           "endTime": "2026-11-02T06:00:00Z", "allDayStart": "2026-11-01", "allDayEndExclusive": "2026-11-02",
           "ownerUserID": "usr_priya_raman", "ownerName": "Priya Raman", "attendees": [], "online": false,
           "isSprout": false, "meetingType": "IN_PERSON"},
          {"id": "evt_demo_overnight", "title": "Overnight shift handoff", "startTime": "2026-11-01T05:30:00Z",
           "endTime": "2026-11-01T07:30:00Z", "ownerUserID": "usr_alex_rivera", "ownerName": "Alex Rivera",
           "location": "North house", "attendees": [], "online": false, "isSprout": false,
           "timeZoneId": "America/Chicago"},
          {"id": "evt_demo_invite", "title": "Care plan review", "startTime": "2026-11-01T16:00:00Z",
           "endTime": "2026-11-01T16:30:00Z", "ownerUserID": "usr_priya_raman", "ownerName": "Priya Raman",
           "ownerColor": "#7E57C2", "online": true, "isSprout": true, "meetingType": "ONLINE",
           "attendees": [
             {"attendeeId": "att_d1", "type": "EMPLOYEE", "ref": "usr_alex_rivera", "displayName": "Alex Rivera",
              "inviteStatus": "INVITED"},
             {"attendeeId": "att_d2", "type": "EMPLOYEE", "ref": "usr_jordan_lee", "displayName": "Jordan Lee",
              "inviteStatus": "ACCEPTED"}
           ]},
          {"id": "evt_demo_checkin", "title": "North team check-in", "startTime": "2026-11-01T20:00:00Z",
           "endTime": "2026-11-01T21:00:00Z", "ownerUserID": "usr_alex_rivera", "ownerName": "Alex Rivera",
           "meetingDetails": "https://meet.example.test/north-team", "online": true, "isSprout": false,
           "isInvitationAccept": true, "attendees": []}
        ]
        """

    static let milestones = """
        [
          {"type": "BIRTHDAY", "userId": "usr_jordan_lee", "displayName": "Jordan Lee", "month": 11, "day": 1},
          {"type": "WORK_ANNIVERSARY", "userId": "usr_sam_ortiz", "displayName": "Sam Ortiz", "month": 11, "day": 1,
           "startYear": 2021}
        ]
        """
}
