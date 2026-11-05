import Foundation
import Testing
import WaiveraAPI
import WaiveraData
import WaiveraTestSupport

@testable import TasksFeature

@MainActor
@Suite("Task file actions")
struct TaskFileActionsModelTests {
    private let pdf = TaskAttachment(
        attachmentId: 41,
        fileId: "f41",
        name: "Care plan 2026.pdf",
        sizeBytes: 182_000,
        addedAt: nil,
        addedBy: nil,
        kind: .pdf
    )

    private func row(_ attachment: TaskAttachment) -> FileRow {
        FileRow.make(attachment, zone: .gmt, today: DemoData.today)
    }

    @Test("Without the web's Download permission a tap just opens the file")
    func noPermission() {
        let fakes = FakeDataEnvironment.make()
        let model = TaskFileActionsModel(taskId: 12, environment: fakes.environment, feedback: TasksFeedback())
        #expect(!model.choose(row(pdf), attachment: pdf, access: RequestAccess(loaded: true)))
        #expect(model.sheet == nil)
        // An employee file needs the employee permission, not the case file one.
        var employee = pdf
        employee.employeeFile = true
        #expect(!model.choose(row(employee), attachment: employee, access: RequestAccess(canDownloadCaseFiles: true)))
        // Too big to copy to the phone: it opens as before.
        var huge = pdf
        huge.sizeBytes = TaskAttachment.maxExportBytes + 1
        #expect(!model.choose(row(huge), attachment: huge, access: RequestAccess(canDownloadCaseFiles: true)))
        // Without the file's details the tap still opens it.
        #expect(!model.choose(row(pdf), attachment: nil, access: RequestAccess(canDownloadCaseFiles: true)))
    }

    @Test("Share downloads one copy under the file's name, and closing removes the sheet")
    func share() async throws {
        let fakes = FakeDataEnvironment.make()
        let model = TaskFileActionsModel(taskId: 12, environment: fakes.environment, feedback: TasksFeedback())
        #expect(model.choose(row(pdf), attachment: pdf, access: RequestAccess(canDownloadCaseFiles: true)))
        model.run(.share)
        #expect(model.sheet?.busy == .share)
        // A second tap while one runs does nothing.
        model.run(.save)
        #expect(await eventually { model.handoff != nil })
        let handoff = try #require(model.handoff)
        #expect(handoff.action == .share)
        #expect(handoff.url.lastPathComponent == "Care plan 2026.pdf")
        #expect(FileManager.default.fileExists(atPath: handoff.url.path))
        #expect(fakes.tasks.calls.all.filter { $0.hasPrefix("fileExport:") } == ["fileExport:12:41"])
        model.handoffClosed()
        #expect(model.sheet == nil && model.handoff == nil)
        TaskFileActionsModel.remove(handoff.url)
    }

    @Test("Save removes its copy when the picker closes and says so only when saved")
    func save() async throws {
        let fakes = FakeDataEnvironment.make()
        let feedback = TasksFeedback()
        let model = TaskFileActionsModel(taskId: 12, environment: fakes.environment, feedback: feedback)
        _ = model.choose(row(pdf), attachment: pdf, access: RequestAccess(canDownloadCaseFiles: true))
        model.run(.save)
        #expect(await eventually { model.handoff != nil })
        let url = try #require(model.handoff?.url)
        model.saved(true)
        #expect(feedback.toast?.message == TasksStrings.text("tasks.file.saved"))
        model.handoffClosed()
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test("A failed download keeps the sheet open and says why")
    func failure() async {
        let fakes = FakeDataEnvironment.make()
        let feedback = TasksFeedback()
        let model = TaskFileActionsModel(taskId: 12, environment: fakes.environment, feedback: feedback)
        _ = model.choose(row(pdf), attachment: pdf, access: RequestAccess(canDownloadCaseFiles: true))
        fakes.tasks.failure.update { $0 = .offline }
        model.run(.share)
        #expect(await eventually { model.sheet?.busy == nil })
        #expect(model.sheet != nil && model.handoff == nil)
        #expect(feedback.toast?.message == TasksStrings.text("tasks.file.downloadFailed"))
    }
}
