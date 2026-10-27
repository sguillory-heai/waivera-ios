import Foundation
import Testing
import WaiveraFixtures

@testable import WaiveraAPI

/// Every REST fixture decodes into its DTO with the shared decoder.
struct FixtureDecodingTests {
    @Test func loginIsEnvelopedAndReadFromData() throws {
        let login = try decodeFixture(ApiResponse<UserLoginResponseDto>.self, "rest-auth-login").data
        #expect(
            login
                == UserLoginResponseDto(
                    requiresPasswordChange: false,
                    userId: "usr_alex_rivera",
                    requiresOnboarding: false
                )
        )
        let gate = try decodeFixture(ApiResponse<UserLoginResponseDto>.self, "rest-auth-login-requires-password-change")
        #expect(gate.data?.requiresPasswordChange == true)
    }

    @Test func loginToleratesPascalCaseStringAndNumericFlags() throws {
        let json = #"{"Data":{"RequiresPasswordChange":"true","UserId":42,"RequiresOnboarding":1},"StatusCode":200}"#
        let login = try WaiveraJSON.decoder().decode(ApiResponse<UserLoginResponseDto>.self, from: Data(json.utf8))
        #expect(
            login.data == UserLoginResponseDto(requiresPasswordChange: true, userId: "42", requiresOnboarding: true)
        )
    }

    @Test func userDetailsKeepsDateOnlyBirthdayAndZone() throws {
        let user = try #require(try decodeFixture(ApiResponse<UserWithRoleDto>.self, "rest-auth-get-user-details").data)
        #expect(user.timezone == "America/Chicago")
        #expect(user.birthday == CalendarDate(year: 1991, month: 6, day: 14))
        #expect(user.avatarURL == "avatars/usr_alex_rivera.png")
        #expect(user.regions?.first?.regionName == "North")
    }

    @Test func directoriesAndOrganizations() throws {
        let names = try decodeFixture(ApiResponse<[GetUserNameResponseVM]>.self, "rest-auth-get-username-list").data
        #expect(names?.map(\.userId) == ["usr_alex_rivera", "usr_priya_raman", "usr_jordan_lee"])
        let combined = try decodeFixture(
            ApiResponse<[GetUserNameResponseDBVM]>.self,
            "rest-auth-get-combined-user-list"
        )
        #expect(combined.data?.last?.type == "PARTICIPANT")
        let details = try decodeFixture(ApiResponse<[OrganizationDto]>.self, "rest-auth-organization-details")
        #expect(details.data?.first?.id == 12)
        let organization = try decodeFixture(OrganizationResponse.self, "rest-users-organization")
        #expect(organization.abbreviation == "NSS")
        #expect(organization.defaultPtoDays == 15)
        let update = try decodeFixture(ApiResponse<String>.self, "rest-auth-update-contact-and-timezone")
        #expect(update.success == true)
    }

    @Test func allConversationsMapsConversationIdAndStringifiedDocs() throws {
        let rows = try #require(try decodeFixture(ApiResponse<[ConversationResponse]>.self, "rest-chat-get-all").data)
        #expect(rows.map(\.id) == [7, 41, 58])
        #expect(rows[0].lastMessage?.authorId == "usr_alex_rivera")
        #expect(rows[1].channel?.channelType == .team)
        #expect(rows[1].lastMessage?.attachmentType == "file")
        #expect(rows[2].channel?.isArchived == true)
        #expect(rows[2].lastMessage == nil)
    }

    @Test func myConversationsCoverCallsMeetingsBotsAndEmptyRows() throws {
        let rows = try decodeFixture([ConversationResponse].self, "rest-chat-get-my-conversations")
        #expect(rows.count >= 3)
        #expect(rows[1].ongoingCall?.status == .active)
        #expect(rows[1].ongoingCall?.status?.isLive == true)
        #expect(rows[2].isBotDirect == true)
        let meeting = try decodeFixture([ConversationResponse].self, "rest-chat-get-my-conversations-with-meeting")
        #expect(meeting.first?.activeMeeting?.roomId == "room_7f3c91")
        let empty = try decodeFixture([ConversationResponse].self, "rest-chat-get-my-conversations-null-last-message")
        #expect(empty.first?.lastMessage == nil)
    }

    @Test func conversationDetailToleratesTheFatAuthor() throws {
        let detail = try decodeFixture(ConversationResponse.self, "rest-chat-get-conversation")
        #expect(detail.lastMessage?.author?.displayName == "Alex Rivera")
        let channel = try decodeFixture(ConversationResponse.self, "rest-chat-get-conversation-channel")
        #expect(channel.channel?.name == "north-team")
    }

    @Test(arguments: [
        "rest-chat-get-messages-pagination", "rest-chat-get-messages-pagination-deleted",
        "rest-chat-get-messages-pagination-empty", "rest-chat-get-messages-pagination-reply",
        "rest-chat-get-messages-pagination-richtext", "rest-chat-get-messages-pagination-system-message",
        "rest-chat-get-messages-pagination-with-attachment", "rest-chat-get-messages-pagination-with-reaction",
        "rest-chat-get-thread",
    ])
    func messagePagesDecode(name: String) throws {
        let raw = try JSONSerialization.jsonObject(with: Fixture.data(name)) as? [Any]
        let messages = try decodeFixture([MessageSendResponse].self, name)
        #expect(messages.count == raw?.count)
        #expect(messages.allSatisfy { $0.createDate != nil })
    }

    @Test func messageVariantsKeepTheirSpecialFields() throws {
        let rich = try decodeFixture([MessageSendResponse].self, "rest-chat-get-messages-pagination-richtext")[0]
        #expect(rich.contentFormat == 1)
        #expect(rich.parsedMessageDoc?["content"]?[0]?["content"]?[0]?["type"]?.stringValue == "mention")
        let system = try decodeFixture([MessageSendResponse].self, "rest-chat-get-messages-pagination-system-message")[
            0
        ]
        #expect(system.messageType == .channelEvent)
        #expect(system.systemEventData?["channelId"]?.stringValue == "41")
        let deleted = try decodeFixture([MessageSendResponse].self, "rest-chat-get-messages-pagination-deleted")[0]
        #expect(deleted.isDeleted == true)
        #expect(deleted.deletedAt != nil)
        let reacted = try decodeFixture([MessageSendResponse].self, "rest-chat-get-messages-pagination-with-reaction")[
            0
        ]
        #expect(reacted.reactions?.map(\.reactionType) == ["👍", "🎉"])
    }

    @Test func singleChatResponses() throws {
        let sent = try decodeFixture(MessageSendResponse.self, "rest-chat-send-message")
        #expect(sent.clientMessageId == "6f1d4c8a-7b2e-4a1f-9c33-2f7b6d5e4a01")
        let created = try decodeFixture(ApiResponse<ConversationResponse>.self, "rest-chat-create-conversation")
        #expect(created.data?.id == 97)
        let existing = try decodeFixture(
            ApiResponse<ConversationResponse>.self,
            "rest-chat-create-conversation-existing"
        )
        #expect(existing.message == "Conversation already exists.")
        let edited = try decodeFixture(ApiResponse<MessageSendResponse>.self, "rest-chat-edit-message")
        #expect(edited.data?.isEdited == true)
        let removed = try decodeFixture(ApiResponse<MessageSendResponse>.self, "rest-chat-delete-message")
        #expect(removed.data?.isDeleted == true)
        let toggled = try decodeFixture(ApiResponse<Bool>.self, "rest-chat-toggle-bookmark")
        #expect(toggled.data == true)
        let upload = try decodeFixture(ChatAttachmentUploadResponse.self, "rest-chat-upload-attachment")
        #expect(upload.documentUrl.hasPrefix("chat/"))
        let left = try decodeFixture(ApiResponse<String>.self, "rest-chat-leave-conversation")
        #expect(left.data == "Conversation removed.")
        for name in ["rest-chat-get-private-conversation", "rest-chat-getorcreate-conversation-for-event"] {
            #expect(try decodeFixture(ApiResponse<ConversationResponse>.self, name).data != nil)
        }
    }

    @Test func readStateActivityBookmarksAndSearch() throws {
        let read = try decodeFixture(ChatReadState.self, "rest-chat-read-through")
        #expect(read.threadRootMessageId == nil)
        #expect(read.readActivityIds == [4411, 4412])
        let thread = try decodeFixture(ChatReadState.self, "rest-chat-read-through-thread")
        #expect(thread.threadRootMessageId == 9330)
        let activity = try decodeFixture([ChatActivityResponse].self, "rest-chat-recent-activity")
        #expect(activity.map(\.activityType) == [.mention, .threadReply, .reaction])
        let bookmarks = try decodeFixture(ApiResponse<[MessageSendResponse]>.self, "rest-chat-get-bookmarks")
        #expect(bookmarks.data?.first?.isBookmarked == true)
        let search = try decodeFixture(ApiResponse<[MessageSendResponse]>.self, "rest-chat-search-conversation")
        #expect(search.data?.first?.attachmentOriginalName == "north-roster-wk43.pdf")
    }

    @Test func calendarFeedKeepsInstantsAndDateOnlyValuesApart() throws {
        let feed = try #require(
            try decodeFixture(ApiResponse<CalendarFeedResponseDto>.self, "rest-calendar-get-all-event")
                .data
        )
        let checkIn = feed.events[0]
        #expect(checkIn.startTime == utc(2026, 10, 20, 15))
        #expect(checkIn.attendees?.map(\.inviteStatus) == [.accepted, .invited, .tentative])
        #expect(checkIn.attendees?.last?.type == .external)
        let allDay = feed.events[1]
        #expect(allDay.allDayStart == CalendarDate(year: 2026, month: 11, day: 5))
        #expect(allDay.allDayEndExclusive == CalendarDate(year: 2026, month: 11, day: 6))
        #expect(allDay.cancelledAllDayDates == [CalendarDate(year: 2026, month: 11, day: 26)].compactMap { $0 })
        #expect(feed.timeOff.first?.startTime == utc(2026, 10, 23, 5))
        #expect(feed.holidays.first?.startDate == CalendarDate(year: 2026, month: 11, day: 26))
        let milestones = try decodeFixture(
            ApiResponse<[CalendarEmployeeMilestoneResponseDto]>.self,
            "rest-calendar-get-milestones"
        )
        #expect(milestones.data?.map(\.type) == [.birthday, .workAnniversary])
        #expect(milestones.data?.last?.startYear == 2024)
        let invitation = try decodeFixture(ApiResponse<Bool>.self, "rest-invitation-accept-deny-meeting")
        #expect(invitation.data == true)
    }

    @Test func employeeProfileTimeOffFilesAvatarAndVideo() throws {
        let profile = try decodeFixture(ApiResponse<GetEmployeeProfileDto>.self, "rest-employee-get-profile").data
        #expect(profile?.timezone == "America/Chicago")
        #expect(profile?.hireDate == CalendarDate(year: 2024, month: 3, day: 4))
        let timeOff = try decodeFixture(ApiResponse<[TimeOffProfileItemDto]>.self, "rest-timeoff-get-for-user-profile")
        #expect(timeOff.data?.first?.remainingLeaveDays == 11)
        let files = try decodeFixture(ApiResponse<ItemsPage<EmployeeFileDto>>.self, "rest-employee-get-employee-files")
        #expect(files.data?.items.first?.fileName == "cpr-certificate.pdf")
        let avatar = try decodeFixture(Base64AvatarResultDto.self, "rest-file-avatar-base64")
        #expect(avatar.imageData?.isEmpty == false)
        let room = try decodeFixture(ApiResponse<CreateMeetingRoomResponse>.self, "rest-video-create-meeting-room")
        #expect(room.data?.roomId == "room_7f3c91")
        #expect(room.data?.isPublisher == true)
    }

    @Test func pushRegistrationBodiesMatchTheFixtures() throws {
        for name in ["rest-mobile-push-register-request-android", "rest-mobile-push-register-request-ios"] {
            let request = try decodeFixture(MobilePushRegistrationRequest.self, name)
            #expect(request.provider == "fcm")
            let encoded = try JSONSerialization.jsonObject(with: WaiveraJSON.encoder().encode(request)) as? NSDictionary
            let original = try JSONSerialization.jsonObject(with: Fixture.data(name)) as? NSDictionary
            #expect(encoded == original)
        }
        #expect(try decodeFixture(SuccessResponse.self, "rest-mobile-push-register").success)
        #expect(try decodeFixture(SuccessResponse.self, "rest-mobile-push-unregister").success)
        #expect(try decodeFixture(SuccessResponse.self, "rest-mobile-push-register-error").success == false)
    }
}
