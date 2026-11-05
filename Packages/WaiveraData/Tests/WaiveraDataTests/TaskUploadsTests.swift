import Foundation
import Testing
import WaiveraAPI

@testable import WaiveraData

@Suite("Task uploads")
struct TaskUploadsTests {
    private static let pdf = Data("%PDF-1.7\nhello".utf8)
    private static let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3])
    private static let route = "POST api/file/upload"

    @Test func filesAreKnownByTheirFirstBytes() {
        #expect(UploadChecks.sniff(Self.pdf) == .pdf)
        #expect(UploadChecks.sniff(Self.png) == .png)
        #expect(UploadChecks.sniff(Data([0xFF, 0xD8, 0xFF, 0xE0])) == .jpeg)
        #expect(UploadChecks.sniff(Data("GIF89a".utf8)) == .gif)
        #expect(UploadChecks.sniff(Data([0, 0, 0, 0x18] + Array("ftypheic".utf8))) == .otherImage)
        #expect(UploadChecks.sniff(Data("RIFF\u{0}\u{0}\u{0}\u{0}WEBP".utf8)) == .otherImage)
        #expect(UploadChecks.sniff(Data("PK\u{3}\u{4}".utf8)) == .unknown)
    }

    @Test func plansFollowTheWebsLimits() {
        let over = UploadChecks.maxBytes + 1
        #expect(UploadChecks.plan(.pdf, size: 0) == .refuse(.empty))
        #expect(UploadChecks.plan(.unknown, size: 10) == .refuse(.unsupported))
        #expect(UploadChecks.plan(.otherImage, size: 10) == .reencode)
        #expect(UploadChecks.plan(.jpeg, size: over) == .reencode)
        #expect(UploadChecks.plan(.png, size: over) == .reencode)
        #expect(UploadChecks.plan(.jpeg, size: 10) == .send)
        #expect(UploadChecks.plan(.pdf, size: over) == .refuse(.tooLarge))
        #expect(UploadChecks.plan(.gif, size: over) == .refuse(.tooLarge))
    }

    @Test func namesTakeTheExtensionTheContentHas() {
        #expect(UploadChecks.fileName("scan.jpeg", type: .png, fallback: "upload") == "scan.png")
        #expect(UploadChecks.fileName("scan.JPEG", type: .jpeg, fallback: "upload") == "scan.jpeg")
        #expect(UploadChecks.fileName("dir/a:b?.pdf", type: .pdf, fallback: "upload") == "a-b-.pdf")
        #expect(UploadChecks.fileName("IMG_1.HEIC", type: .jpeg, fallback: "upload") == "IMG_1.jpg")
        #expect(UploadChecks.fileName(nil, type: .jpeg, fallback: "upload") == "upload.jpg")
        #expect(UploadChecks.fileName("...", type: .pdf, fallback: "upload") == "upload.pdf")
        #expect(UploadChecks.templateName("Signed plan", mimeType: "application/pdf") == "Signed plan.pdf")
        #expect(UploadChecks.templateName("Signed plan.PDF", mimeType: "application/pdf") == "Signed plan.PDF")
        #expect(UploadChecks.templateName("Photo", mimeType: "image/jpeg") == "Photo.jpg")
    }

    @Test func aQueuedFileGoesUpWithTheWebsFormFields() async throws {
        let (repository, transport, root) = await make()
        defer { try? FileManager.default.removeItem(at: root) }
        await transport.set(Self.route, .json(#"{"fileId":"f-1","fileName":"Care plan (2).pdf"}"#))
        await repository.add(
            taskId: 12,
            files: [.data(Self.pdf, name: "plan.pdf")],
            target: UploadTarget(requirementId: 5, requirementName: "Care plan", typeId: 3)
        )
        let done = await first(repository) { $0.first?.state == .done }
        #expect(done?.first?.fileName == "Care plan (2).pdf")
        #expect(done?.first?.requirementId == 5)
        let body = try #require(await transport.bodies(Self.route).first)
        let text = String(decoding: body, as: UTF8.self)
        #expect(text.contains(#"name="file.File"; filename="plan.pdf""#))
        #expect(text.contains("name=\"file.FileName\"\r\n\r\nCare plan\r\n"))
        #expect(text.contains("name=\"file.RequiredAttachmentId\"\r\n\r\n5\r\n"))
        #expect(text.contains("name=\"file.TypeId\"\r\n\r\n3\r\n"))
        #expect(text.contains("name=\"file.TaskId\"\r\n\r\n12\r\n"))
        #expect(text.contains("name=\"file.RegionId\"\r\n\r\n2\r\n"))
        #expect(!text.contains("file.DocumentCategoryId"))
    }

    @Test func filesTheWebWouldRefuseAreNeverSent() async {
        let (repository, transport, root) = await make()
        defer { try? FileManager.default.removeItem(at: root) }
        await repository.add(
            taskId: 12,
            files: [.data(Data("PK\u{3}\u{4}".utf8), name: "sheet.xlsx"), .data(Data(), name: "empty.pdf")],
            target: UploadTarget()
        )
        let rows = await first(repository) { $0.count == 2 }
        #expect(rows?.map(\.problem) == [.unsupported, .empty])
        #expect(rows?.map(\.fileName) == ["sheet.xlsx", "empty.pdf"])
        #expect(await transport.count(Self.route) == 0)
    }

    @Test func serverRefusalsGetTheAppsWordsAndTimeoutsThatLandedCountAsDone() async {
        let (repository, transport, root) = await make()
        defer { try? FileManager.default.removeItem(at: root) }
        await transport.enqueue(
            Self.route,
            .json(#"{"errorCode":"FILE_EXTENSION_MISMATCH"}"#, status: 400),
            .status(503),
            .json(#"{"errorCode":"FILE_ALREADY_UPLOADED"}"#, status: 409)
        )
        await repository.add(taskId: 12, files: [.data(Self.pdf, name: "a.pdf")], target: UploadTarget())
        let refused = await first(repository) { $0.first?.state == .failed }
        #expect(refused?.first?.problem == .mismatch)
        if let id = refused?.first?.id { await repository.dismiss(id) }

        // A 503 puts the file back in line; the resend finds the server already has it.
        await repository.add(taskId: 12, files: [.data(Self.pdf, name: "b.pdf")], target: UploadTarget())
        #expect(await eventually { await transport.count(Self.route) == 2 })
        _ = await first(repository) { $0.first?.state == .queued && $0.first?.fileName == "b.pdf" }
        await repository.resume()
        let landed = await first(repository) { $0.first?.state == .done }
        #expect(landed?.first?.fileName == "b.pdf")
    }

    @Test func aLockedTaskIsWorded() {
        #expect(UploadMapping.problem(CodedRefusal(error: .conflict, code: nil)) == .taskLocked)
        #expect(UploadMapping.problem(CodedRefusal(error: .forbidden, code: nil)) == .noAccess)
        #expect(UploadMapping.problem(CodedRefusal(error: .invalidRequest, code: "PDF_ENCRYPTED")) == .pdfLocked)
        #expect(UploadMapping.problem(WaiveraError.server(statusCode: 413)) == .tooLarge)
        #expect(UploadMapping.problem(WaiveraError.offline) == .failed)
    }

    @Test func theQueueSurvivesARestartAndSignOutDropsIt() async throws {
        let (repository, transport, root) = await make()
        defer { try? FileManager.default.removeItem(at: root) }
        await transport.setOffline(true)
        await repository.add(taskId: 12, files: [.data(Self.png, name: "photo.png")], target: UploadTarget())
        #expect(await eventually { await transport.count(Self.route) > 0 })

        let reopened = LiveTaskUploadsRepository(api: makeAPI(transport), clock: TestClock(), root: root)
        let rows = await first(reopened) { !$0.isEmpty }
        #expect(rows?.first?.fileName == "photo.png")
        #expect(rows?.first?.state == .queued || rows?.first?.state == .uploading)

        await reopened.clear()
        #expect(!FileManager.default.fileExists(atPath: root.path))
        let after = await first(reopened) { _ in true }
        #expect(after?.isEmpty == true)
    }

    @Test func anActivitysFileGoesUpUnderItsTemplatesName() async throws {
        let (repository, transport, root) = await make()
        defer { try? FileManager.default.removeItem(at: root) }
        await transport.set(Self.route, .json(#"{"fileId":"f-2","fileName":"Signed plan.pdf"}"#))
        let file = try await repository.prepare(.data(Self.pdf, name: "scan"))
        #expect(file.name == "scan.pdf" && file.mimeType == "application/pdf")
        let template = FileTemplate(id: 7, name: "Signed plan", typeId: 4, categoryId: 2)
        let saved = try await repository.sendNow(taskId: 12, file: file, template: template)
        #expect(saved == "Signed plan.pdf")
        #expect(!FileManager.default.fileExists(atPath: file.path))
        let body = try #require(await transport.bodies(Self.route).first)
        let text = String(decoding: body, as: UTF8.self)
        #expect(text.contains("name=\"file.DocumentCategoryId\"\r\n\r\n2\r\n"))
        #expect(text.contains("name=\"file.TypeId\"\r\n\r\n4\r\n"))

        do {
            _ = try await repository.prepare(.data(Data("hello".utf8), name: "notes.txt"))
            Issue.record("A text file was prepared")
        } catch let refused as UploadRefused {
            #expect(refused.problem == .unsupported && refused.pickedName == "notes.txt")
        }
    }

    private func make() async -> (LiveTaskUploadsRepository, RoutingTransport, URL) {
        let transport = RoutingTransport()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "uploads-\(UUID().uuidString)",
            isDirectory: true
        )
        return (LiveTaskUploadsRepository(api: makeAPI(transport), clock: TestClock(), root: root), transport, root)
    }

    /// The first list a fresh subscription sees that passes `test`, or nil after two seconds. Each
    /// call subscribes again: a cancelled wait ends the stream it read.
    private func first(
        _ repository: LiveTaskUploadsRepository,
        where test: @escaping @Sendable ([TaskUpload]) -> Bool
    ) async -> [TaskUpload]? {
        let stream = repository.uploads(taskId: 12)
        return await withTaskGroup(of: [TaskUpload]?.self) { group in
            group.addTask {
                for await value in stream where test(value) { return value }
                return nil
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(2))
                return nil
            }
            let found = await group.next() ?? nil
            group.cancelAll()
            return found
        }
    }
}
