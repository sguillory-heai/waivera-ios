import Foundation
import Testing
import WaiveraFixtures

@testable import WaiveraAPI

struct ErrorMappingTests {
    @Test func recognisesAllSixBodyShapes() throws {
        #expect(APIErrorBody(data: Data()).shape == .empty)
        #expect(APIErrorBody(data: Data(#""No uid found in HttpContext.""#.utf8)).shape == .jsonString)
        #expect(APIErrorBody(data: Data("Session expired. Logged in from another device.".utf8)).shape == .plainText)
        let camel = APIErrorBody(data: try Fixture.data("rest-error-apiresponse-unauthorized"))
        #expect(camel.shape == .apiResponse)
        #expect(camel.errorCode == "USER_CONTEXT_MISSING")
        let pascal = APIErrorBody(data: try Fixture.data("rest-error-exception-middleware-500"))
        #expect(pascal.shape == .pascalCaseApiResponse)
        #expect(pascal.serverMessage == "Something went wrong. Please try again later.")
        #expect(APIErrorBody(data: try Fixture.data("rest-mobile-push-register-error")).shape == .successMessage)
    }

    @Test(arguments: [
        (400, WaiveraError.invalidRequest), (401, .unauthorized), (403, .forbidden), (404, .notFound),
        (409, .conflict), (423, .attachmentBlocked), (500, .server(statusCode: 500)), (502, .server(statusCode: 502)),
    ])
    func statusDecidesTheCase(status: Int, expected: WaiveraError) {
        #expect(APIErrorMapper.map(statusCode: status, body: Data()) == expected)
    }

    @Test func channelPermissionErrorsAreClassifiedFromTheBody() {
        #expect(
            APIErrorMapper.map(statusCode: 403, body: Data(#""This channel is archived.""#.utf8)) == .channelArchived
        )
        let readOnly = Data(#""This channel is read-only for your account.""#.utf8)
        #expect(APIErrorMapper.map(statusCode: 403, body: readOnly) == .channelReadOnly)
    }

    @Test func serverTextNeverBecomesTheUserMessage() throws {
        let leaked = try Fixture.data("rest-error-controller-500")
        let error = APIErrorMapper.map(statusCode: 500, body: leaked)
        #expect(!error.userMessage.contains("Npgsql"))
        #expect(error.userMessage == WaiveraError.server(statusCode: 503).userMessage)
    }

    @Test func everyCaseHasLocalizedCopy() {
        let cases: [WaiveraError] = [
            .offline, .signedOut, .unauthorized, .forbidden, .notFound, .conflict, .invalidRequest,
            .server(statusCode: 500), .invalidResponse, .configurationMissing, .channelArchived, .channelReadOnly,
            .realtimeUnavailable, .attachmentBlocked, .attachmentPending, .attachmentUploadFailed,
            .auth(.invalidCredentials), .auth(.invalidEmail), .auth(.userDisabled), .auth(.tooManyAttempts),
            .auth(.weakPassword), .auth(.requiresRecentLogin), .auth(.sessionExpired), .auth(.unknown),
        ]
        for error in cases {
            #expect(!error.userMessage.hasPrefix("error."), "missing copy for \(error)")
        }
    }

    @Test func foreignErrorsAreWrapped() {
        #expect(WaiveraError.from(URLError(.notConnectedToInternet)) == .offline)
        #expect(WaiveraError.from(URLError(.timedOut)) == .offline)
        struct Strange: Error {}
        #expect(WaiveraError.from(Strange()) == .invalidResponse)
        #expect(WaiveraError.server(statusCode: 503).isTransient)
        #expect(!WaiveraError.forbidden.isTransient)
    }

    @Test func pascalCaseKeysCanonicaliseLikeDotNet() {
        #expect(WaiveraJSON.camelCase("MessageId") == "messageId")
        #expect(WaiveraJSON.camelCase("AvatarURL") == "avatarURL")
        #expect(WaiveraJSON.camelCase("OwnerUserID") == "ownerUserID")
        #expect(WaiveraJSON.camelCase("ID") == "id")
        #expect(WaiveraJSON.camelCase("URLValue") == "urlValue")
        #expect(WaiveraJSON.camelCase("createdby") == "createdby")
        #expect(WaiveraJSON.camelCase("avatarURL") == "avatarURL")
    }

    @Test func openEnumsAcceptStringsIntsAndUnknowns() throws {
        let decoder = WaiveraJSON.decoder()
        let values = try decoder.decode([ChannelDto.ChannelType].self, from: Data(#"["TEAM",1,"custom",7,"NEW"]"#.utf8))
        #expect(values == [.team, .team, .custom, .unknown, .unknown])
        let status = try decoder.decode([CallRecordStatus].self, from: Data(#"["End","Active","ended",""]"#.utf8))
        #expect(status.map(\.isLive) == [false, true, false, false])
    }
}
