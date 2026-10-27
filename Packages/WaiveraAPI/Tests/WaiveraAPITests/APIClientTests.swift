import Foundation
import Testing

@testable import WaiveraAPI

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

struct APIClientTests {
    @Test func sendsTheBearerTokenAndJSONBody() async throws {
        let transport = StubTransport([.json(#"{"success":true}"#)])
        try await makeClient(transport).unregisterFromPush(deviceID: "device-1")

        let request = try #require(await transport.requests.first)
        #expect(request.url?.absoluteString == "https://api.example.test/api/mobile-push/unregister")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer cached")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.httpBody == Data(#"{"deviceId":"device-1"}"#.utf8))
    }

    @Test func retriesExactlyOnceWithAForceRefreshedTokenAfter401() async throws {
        let transport = StubTransport([.empty(401), .json(#"{"success":true}"#)])
        try await makeClient(transport).unregisterFromPush(deviceID: "device-1")
        let tokens = await transport.requests.map { $0.value(forHTTPHeaderField: "Authorization") }
        #expect(tokens == ["Bearer cached", "Bearer refreshed"])
    }

    @Test func aSecond401SurfacesAsUnauthorized() async throws {
        let transport = StubTransport([.empty(401), .empty(401)])
        await #expect(throws: WaiveraError.unauthorized) {
            try await makeClient(transport).unregisterFromPush(deviceID: "device-1")
        }
        #expect(await transport.requests.count == 2)
    }

    @Test func signedOutFailsLocallyWithoutANetworkRequest() async throws {
        let transport = StubTransport()
        await #expect(throws: WaiveraError.signedOut) {
            try await makeClient(transport, tokens: FakeTokens(signedIn: false)).login()
        }
        #expect(await transport.requests.isEmpty)
    }

    @Test func mapsServerErrorsWithoutLeakingTheBody() async throws {
        let transport = StubTransport([try .fixture("rest-error-controller-500", status: 500)])
        await #expect(throws: WaiveraError.server(statusCode: 500)) {
            try await makeClient(transport).allConversations()
        }
    }

    @Test func transportFailuresBecomeOffline() async throws {
        let transport = StubTransport(failure: URLError(.notConnectedToInternet))
        await #expect(throws: WaiveraError.offline) { try await makeClient(transport).login() }
    }

    @Test func envelopedNullDataIsAFailure() async throws {
        let transport = StubTransport([.json(#"{"statusCode":200,"message":"OK","success":true}"#)])
        await #expect(throws: WaiveraError.invalidResponse) {
            try await makeClient(transport).privateConversation(with: "usr_jordan_lee")
        }
    }

    @Test func noContentListsAreEmpty() async throws {
        let transport = StubTransport([.empty(204)])
        #expect(try await makeClient(transport).usernameList().isEmpty)
    }

    @Test func emptyOrganizationListIsA404AndMapsToEmpty() async throws {
        let transport = StubTransport([.json(#"{"statusCode":404,"message":"none","success":false}"#, status: 404)])
        #expect(try await makeClient(transport).organizationDetails().isEmpty)
    }

    @Test func requestsTheFixedPageSizeAndCursor() async throws {
        let transport = StubTransport([try .fixture("rest-chat-get-messages-pagination")])
        let page = try await makeClient(transport).messagesPage(conversationId: 7, beforeMessageId: 9310)
        #expect(page.count == 3)
        let url = try #require(await transport.requests.first?.url)
        #expect(url.path == "/api/chat/7/messages/pagination")
        #expect(url.query?.contains("pageSize=50") == true)
        #expect(url.query?.contains("beforeMessageId=9310") == true)
    }

    @Test func listEndpointsSendBothFlagsExplicitly() async throws {
        let transport = StubTransport([try .fixture("rest-chat-get-all")])
        _ = try await makeClient(transport).allConversations()
        let query = try #require(await transport.requests.first?.url?.query)
        #expect(query.contains("includeMeetings=false"))
        #expect(query.contains("includeArchived=false"))
    }

    @Test func multipartUploadUsesTheFilePartAndItsOwnBoundary() async throws {
        let transport = StubTransport([try .fixture("rest-chat-upload-attachment")])
        let file = MultipartFile(data: Data([1, 2, 3]), fileName: "roster.pdf", mimeType: "application/pdf")
        let upload = try await makeClient(transport).uploadAttachment(file)
        #expect(upload.documentUrl.hasPrefix("chat/2026/10/"))
        let request = try #require(await transport.requests.first)
        let contentType = try #require(request.value(forHTTPHeaderField: "Content-Type"))
        #expect(contentType.hasPrefix("multipart/form-data; boundary="))
        let body = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
        #expect(body.contains(#"name="file"; filename="roster.pdf""#))
    }

    @Test func blockedAttachmentsMapTo423() async throws {
        let transport = StubTransport([.json("Attachment was rejected by security validation.", status: 423)])
        await #expect(throws: WaiveraError.attachmentBlocked) {
            try await makeClient(transport).attachmentData(messageId: 9320)
        }
    }

    @Test func calendarQueriesUseCanonicalUTC() async throws {
        let transport = StubTransport([try .fixture("rest-calendar-get-all-event")])
        let feed = try await makeClient(transport).calendarFeed(start: utc(2026, 10, 18, 5), end: utc(2026, 10, 25, 5))
        #expect(feed.events.count == 2)
        let query = try #require(await transport.requests.first?.url?.query)
        #expect(query.contains("startTime=2026-10-18T05:00:00.000Z"))
    }

    @Test func pushRegistrationRejectionIsAnError() async throws {
        let transport = StubTransport([try .fixture("rest-mobile-push-register-error", status: 400)])
        let registration = MobilePushRegistrationRequest(
            deviceID: "dev",
            pushToken: "token",
            pushEnabled: true,
            chatMessagesEnabled: true,
            mentionsEnabled: true,
            reactionsEnabled: true,
            activeCallsEnabled: true,
            soundEnabled: true,
            vibrationEnabled: true,
            previewContentEnabled: true
        )
        await #expect(throws: WaiveraError.invalidRequest) {
            try await makeClient(transport).registerForPush(registration)
        }
    }

    @Test func resolvesRelativeAttachmentPaths() throws {
        let client = try makeClient(StubTransport())
        #expect(
            client.url(for: "/api/chat/message/9320/attachment").absoluteString
                == "https://api.example.test/api/chat/message/9320/attachment"
        )
    }
}
