import Foundation
import Testing
import WaiveraAPI
import WaiveraData
import WaiveraTestSupport

@testable import TasksFeature

@Suite("Task files")
struct TaskFilesTests {
    private func bytes(_ base64: String) -> Data { Data(base64Encoded: base64) ?? Data() }

    @Test("Inflate reads stored, fixed and dynamic blocks and stops at the limit")
    func inflate() throws {
        #expect(try Inflate.decompress(bytes("AQUA+v9oZWxsbw=="), limit: 100) == Data("hello".utf8))
        #expect(try Inflate.decompress(bytes("S0xKToQhAA=="), limit: 100) == Data("abcabcabcabc".utf8))
        let words = [
            "visit", "care", "plan", "Jordan", "Mom", "Thursday", "North", "house", "follow", "up",
            "signed", "2:30", "PM", "notes", "é", "→",
        ]
        var picked: [String] = []
        for index in 0..<3_000 {
            let slot: Int = (index * index * 7 + index * 3) % 16
            picked.append(words[slot])
        }
        let expected = picked.joined(separator: " ")
        let dynamic = bytes(
            "7cztCYMwEADQVW4hS1cotNZAakQlzuQcLtYq2aB/HxzHfb6alrTGkt7j6xlTfozRl5zLFvcujv2MX9FG17qd1uuvK5+4lXkdWj77SiQSiUQikUgkEolEIpFIJBKJRCKRSCQSiUQikUgkEolEIpFIJBKJRCKRSCQSiUQikUgkEv8Wvw=="
        )
        #expect(try Inflate.decompress(dynamic, limit: 1_000_000) == Data(expected.utf8))
        #expect(throws: Inflate.Failure.tooLarge) { try Inflate.decompress(dynamic, limit: 1_000) }
        #expect(throws: (any Error).self) { try Inflate.decompress(Data([0xFF, 0xFF, 0xFF]), limit: 100) }
    }

    @Test("A .docx reads as headings, paragraphs and list items; links keep their text")
    func word() throws {
        let blocks = try DocxReader.blocks(from: Data(base64Encoded: DemoFiles.intakePacket) ?? Data())
        #expect(
            blocks == [
                WordBlock(kind: .heading(1), text: "Intake packet"),
                WordBlock(kind: .heading(2), text: "Household"),
                WordBlock(kind: .paragraph, text: "Jordan lives with Mom at the North house."),
                WordBlock(kind: .listItem, text: "Weekly visit\tThursdays"),
                WordBlock(kind: .paragraph, text: "Line one\nLine two"),
            ]
        )
        #expect(throws: (any Error).self) { try DocxReader.blocks(from: Data("not a zip".utf8)) }
    }

    @Test("Text stops at 512 KB without splitting a character")
    func textCut() {
        let short = TaskFileModel.text(Data("Visit notes".utf8))
        #expect(short == .text("Visit notes", cut: false))
        // 'é' is two bytes; put one across the limit.
        var long = Data(repeating: UInt8(ascii: "a"), count: TaskFileModel.maxTextBytes - 1)
        long.append(contentsOf: Array("é and more".utf8))
        guard case .text(let text, let cut) = TaskFileModel.text(long) else {
            Issue.record("not text")
            return
        }
        #expect(cut)
        #expect(text.utf8.count == TaskFileModel.maxTextBytes - 1)
        #expect(!text.contains("\u{FFFD}"))
    }

    @Test("Note motion takes longer for a longer move, within 180 to 480 ms")
    func noteMotion() {
        #expect(NoteMotion.duration(distance: 0) == 0.18)
        #expect(NoteMotion.duration(distance: 200) == 0.28)
        #expect(NoteMotion.duration(distance: 5_000) == 0.48)
    }

    @MainActor
    @Test("The Files section words each file; a file the phone can't show opens the web")
    func filesSection() async {
        let fakes = FakeDataEnvironment.make(webBaseURL: URL(string: "https://app.waivera.com"))
        await fakes.environment.launch()
        let model = TaskDetailModel(taskId: 12, environment: fakes.environment)
        let task = Task { await model.run() }
        defer { task.cancel() }
        #expect(await eventually { model.state.files.value?.count == 5 && model.state.task != nil })
        let rows = model.state.files.value ?? []
        #expect(rows.map(\.short) == ["PDF", "IMG", "TXT", "DOC", "FILE"])
        #expect(rows.first?.meta.hasPrefix("PDF · ") == true)
        #expect(rows.first?.addedBy == "Dana Cole")
        #expect(rows.last?.webNote == "Opens on the web")
        #expect(rows.first?.webNote == nil)
        if let pdf = rows.first { #expect(model.open(file: pdf) == .viewer(attachmentId: 41)) }
        if let sheet = rows.last, case .web(let url) = model.open(file: sheet) {
            #expect(url.host == "app.waivera.com")
        } else {
            Issue.record("expected the web")
        }
    }

    @MainActor
    @Test("The viewer opens text, Word, PDF and image files; another type fails over to the web")
    func viewer() async {
        let fakes = FakeDataEnvironment.make(webBaseURL: URL(string: "https://app.waivera.com"))
        await fakes.environment.launch()
        let text = TaskFileModel(taskId: 12, attachmentId: 43, environment: fakes.environment)
        await text.load()
        guard case .ready(.text(let body, cut: false)) = text.phase else {
            Issue.record("text did not load")
            return
        }
        #expect(body.hasPrefix("Oct 21 visit"))
        #expect(text.name == "Visit notes.txt")
        let word = TaskFileModel(taskId: 12, attachmentId: 44, environment: fakes.environment)
        await word.load()
        if case .ready(.word(let blocks)) = word.phase { #expect(blocks.count == 5) } else { Issue.record("word") }
        let pdf = TaskFileModel(taskId: 12, attachmentId: 41, environment: fakes.environment)
        await pdf.load()
        if case .ready(.pdf) = pdf.phase {} else { Issue.record("pdf") }
        let image = TaskFileModel(taskId: 12, attachmentId: 42, environment: fakes.environment)
        await image.load()
        if case .ready(.image) = image.phase {} else { Issue.record("image") }
        let other = TaskFileModel(taskId: 12, attachmentId: 45, environment: fakes.environment)
        await other.load()
        #expect(other.phase == .failed)
        #expect(other.webURL?.host == "app.waivera.com")
        let missing = TaskFileModel(taskId: 12, attachmentId: 99, environment: fakes.environment)
        await missing.load()
        #expect(missing.phase == .failed)
    }

    @MainActor
    @Test("A failed download fails, and a retry after the network returns opens the file")
    func viewerRetry() async {
        let fakes = FakeDataEnvironment.make()
        await fakes.environment.launch()
        fakes.tasks.failure.update { $0 = .offline }
        let model = TaskFileModel(taskId: 12, attachmentId: 43, environment: fakes.environment)
        await model.load()
        #expect(model.phase == .failed)
        fakes.tasks.failure.update { $0 = nil }
        await model.load()
        if case .ready = model.phase {} else { Issue.record("retry did not load") }
    }
}
