import Foundation
import Testing
import WaiveraAPI
import WaiveraData
import WaiveraTestSupport

@testable import TasksFeature

@MainActor
struct TaskUploadsModelTests {
    private static let pdf = Data("%PDF-1.7".utf8)

    @Test func requiredFilesLoadAndAnUploadShowsOnItsRowThenSettles() async {
        let fakes = FakeDataEnvironment.make()
        let model = TaskDetailModel(taskId: 12, environment: fakes.environment)
        let run = Task { await model.run() }
        defer { run.cancel() }
        #expect(await eventually { model.uploads.state.required.value?.count == 2 })
        let rows = model.uploads.state.required.value ?? []
        #expect(rows.map(\.isForm) == [false, true])

        // A form is filled on the web; it never opens the sheet.
        model.uploads.startRequired(42)
        #expect(model.uploads.state.sheet == nil)
        model.uploads.startRequired(41)
        let sheet = model.uploads.state.sheet
        #expect(sheet?.single == true && sheet?.target.requirementName == "Signed care plan")

        fakes.uploads.holds.update { $0 = true }
        model.uploads.picked(
            [.data(Self.pdf, name: "a.pdf"), .data(Self.pdf, name: "b.pdf")],
            target: sheet?.target ?? UploadTarget(),
            single: true
        )
        #expect(model.uploads.state.sheet == nil)
        #expect(await eventually { model.uploads.state.required.value?.first?.upload?.state == .uploading })
        // A required file takes one file; its upload is on its row, not in the extra list.
        #expect(model.uploads.state.uploads.isEmpty)

        fakes.uploads.required.update { $0[12] = [FakeTaskUploadsRepository.demoRequired[1]] }
        fakes.uploads.holds.update { $0 = false }
        #expect(await eventually(timeout: .seconds(6)) { model.uploads.state.required.value?.count == 1 })
        #expect(await eventually(timeout: .seconds(2)) { model.uploads.state.uploads.isEmpty })
    }

    @Test func anExtraFileOnAnEmployeeTaskIsFiledUnderACategoryFirst() async {
        let fakes = FakeDataEnvironment.make()
        let model = TaskDetailModel(taskId: 12, environment: fakes.environment)
        let run = Task { await model.run() }
        defer { run.cancel() }
        model.uploads.startExtra(employeeTask: true)
        #expect(model.uploads.state.sheet?.ready == false)
        #expect(await eventually { model.uploads.state.sheet?.categories.value?.count == 2 })
        model.uploads.pickCategory(2)
        #expect(model.uploads.state.sheet?.ready == true)
        #expect(model.uploads.state.sheet?.target.categoryId == 2)

        model.uploads.startExtra(employeeTask: false)
        #expect(model.uploads.state.sheet?.ready == true && model.uploads.state.sheet?.single == false)
    }

    @Test func aRefusedExtraFileSaysWhyAndCanBeDismissed() async {
        let fakes = FakeDataEnvironment.make()
        let model = TaskDetailModel(taskId: 12, environment: fakes.environment)
        let run = Task { await model.run() }
        defer { run.cancel() }
        #expect(await eventually { model.uploads.state.required.value != nil })
        fakes.uploads.nextProblem.update { $0 = .tooLarge }
        model.uploads.picked([.data(Self.pdf, name: "big.pdf")], target: UploadTarget(), single: false)
        #expect(await eventually { model.uploads.state.uploads.first?.problem == .tooLarge })
        let row = model.uploads.state.uploads.first
        #expect(row.map { UploadText.note($0).tone } == .danger)
        #expect(row.map { UploadText.note($0).text } == "Couldn't upload · it's over 10 MB")
        if let id = row?.id { model.uploads.dismiss(id) }
        #expect(await eventually { model.uploads.state.uploads.isEmpty })
    }

    @Test func aFinishedOrDeletedTaskTakesNoFiles() {
        var state = TaskDetailScreenState()
        #expect(!state.canUpload)
        state.task = task(.inProgress)
        #expect(state.canUpload)
        state.task = task(.other("Deleted"))
        #expect(!state.canUpload)
        state.task = task(.completed)
        #expect(!state.canUpload)
    }

    @Test func anActivityThatNeedsAFileUploadsItUnderTheTemplateThenLogs() async {
        let fakes = FakeDataEnvironment.make()
        let model = TaskDetailModel(taskId: 12, environment: fakes.environment)
        let run = Task { await model.run() }
        defer { run.cancel() }
        #expect(await eventually { model.state.phase == .content })
        model.startLog()
        #expect(await eventually { model.state.log?.types.value != nil })
        model.chooseType(4)
        #expect(model.state.log?.needsFile == true)
        #expect(model.state.log?.minutesLocked == true)
        model.setDescription("Signed plan came back")
        model.submitLog()
        #expect(model.state.log?.showErrors == true && model.state.log?.fileMissing == true)
        #expect(fakes.tasks.logged.get().isEmpty)

        model.pickLogFile(.data(Self.pdf, name: "scan.pdf"))
        #expect(await eventually { model.state.log?.file != nil })
        #expect(model.state.log?.fileSavedName == "Signed plan.pdf")
        model.submitLog()
        #expect(await eventually { model.state.log == nil })
        #expect(fakes.uploads.sentNow.get() == ["Signed plan.pdf"])
        // The server sets the time from the type, as on the web.
        #expect(fakes.tasks.logged.get().first?.minutes == 10)
    }

    @Test func aFileTheServerRefusesIsDroppedSoAnotherCanBePicked() async {
        let fakes = FakeDataEnvironment.make()
        let model = TaskDetailModel(taskId: 12, environment: fakes.environment)
        let run = Task { await model.run() }
        defer { run.cancel() }
        model.startLog()
        #expect(await eventually { model.state.log?.types.value != nil })
        model.chooseType(4)
        fakes.uploads.nextProblem.update { $0 = .unsupported }
        model.pickLogFile(.data(Data("hello".utf8), name: "notes.txt"))
        #expect(await eventually { model.state.log?.fileProblem == .unsupported })
        #expect(model.state.log?.file == nil)

        model.pickLogFile(.data(Self.pdf, name: "scan.pdf"))
        #expect(await eventually { model.state.log?.file != nil && model.state.log?.fileProblem == nil })
        // Switching to a type without a file drops the picked one.
        model.chooseType(1)
        #expect(model.state.log?.file == nil)
        #expect(await eventually { fakes.uploads.discarded.get().count == 1 })
    }

    private func task(_ state: TaskState) -> TaskDetail {
        TaskDetail(id: 1, key: "HEA-1", title: "Plan", state: state, webPath: "/tasks/1")
    }
}
