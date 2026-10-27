import Foundation
import Testing
import WaiveraAPI
import WaiveraData

@testable import ChatFeature

/// One test per rich-text rule in 03 §7, mirroring the Android parser tests.
@Suite("Rich text parser")
struct RichTextTests {
    private func blocks(_ doc: JSONValue) -> [RichBlock] { TipTapParser.parse(doc).blocks }

    private func inlines(_ doc: JSONValue) -> [RichInline] {
        guard case .paragraph(let inlines) = blocks(doc).first else { return [] }
        return inlines
    }

    @Test func paragraphWithPlainText() {
        #expect(blocks(Fixture.doc(Fixture.paragraph(Fixture.text("Hello")))) == [.paragraph([.text("Hello")])])
    }

    @Test func everyMarkIsRead() {
        let marks = #"{"type":"bold"},{"type":"italic"},{"type":"strike"},{"type":"underline"},{"type":"code"}"#
        let result = inlines(Fixture.doc(Fixture.paragraph(Fixture.text("x", marks: marks))))
        #expect(result == [.text("x", marks: Set(RichMark.allCases))])
    }

    @Test func unknownMarksAreIgnored() {
        let result = inlines(Fixture.doc(Fixture.paragraph(Fixture.text("x", marks: #"{"type":"highlight"}"#))))
        #expect(result == [.text("x")])
    }

    @Test func safeLinkKeepsItsHref() {
        let link = #"{"type":"link","attrs":{"href":"https://waivera.example/plan"}}"#
        let result = inlines(Fixture.doc(Fixture.paragraph(Fixture.text("plan", marks: link))))
        #expect(result == [.text("plan", href: URL(string: "https://waivera.example/plan"))])
    }

    @Test func unsafeLinkRendersAsPlainText() {
        let link = #"{"type":"link","attrs":{"href":"javascript:alert(1)"}}"#
        #expect(inlines(Fixture.doc(Fixture.paragraph(Fixture.text("click", marks: link)))) == [.text("click")])
    }

    @Test func mentionUsesLabelThenIdThenFallback() {
        let labelled = #"{"type":"mention","attrs":{"id":"usr_1","label":"Priya Raman"}}"#
        let idOnly = #"{"type":"mention","attrs":{"id":"usr_2"}}"#
        let bare = #"{"type":"mention"}"#
        let result = inlines(Fixture.doc(Fixture.paragraph(labelled, idOnly, bare)))
        #expect(result == [.mention("Priya Raman"), .mention("usr_2"), .mention("mention")])
    }

    @Test func hardBreakIsKept() {
        let result = inlines(
            Fixture.doc(Fixture.paragraph(Fixture.text("a"), #"{"type":"hardBreak"}"#, Fixture.text("b")))
        )
        #expect(result == [.text("a"), .hardBreak, .text("b")])
    }

    @Test func headingLevelDefaultsToTwo() {
        let withLevel = blocks(
            Fixture.doc(#"{"type":"heading","attrs":{"level":1},"content":["# + Fixture.text("A") + "]}")
        )
        let withoutLevel = blocks(Fixture.doc(#"{"type":"heading","content":["# + Fixture.text("B") + "]}"))
        #expect(withLevel == [.heading(level: 1, [.text("A")])])
        #expect(withoutLevel == [.heading(level: 2, [.text("B")])])
    }

    @Test func blockquoteHoldsBlocks() {
        let quote = blocks(
            Fixture.doc(#"{"type":"blockquote","content":["# + Fixture.paragraph(Fixture.text("q")) + "]}")
        )
        #expect(quote == [.blockquote([.paragraph([.text("q")])])])
    }

    @Test func bulletAndOrderedLists() {
        let item = #"{"type":"listItem","content":["# + Fixture.paragraph(Fixture.text("one")) + "]}"
        let bullet = blocks(Fixture.doc(#"{"type":"bulletList","content":["# + item + "," + item + "]}"))
        let ordered = blocks(Fixture.doc(#"{"type":"orderedList","content":["# + item + "]}"))
        guard case .list(let isOrdered, let items) = bullet.first, case .list(let secondOrdered, _) = ordered.first
        else {
            Issue.record("Expected lists")
            return
        }
        #expect(!isOrdered)
        #expect(items.count == 2)
        #expect(secondOrdered)
    }

    @Test func codeBlockJoinsItsText() {
        let code = blocks(Fixture.doc(#"{"type":"codeBlock","content":["# + Fixture.text("val a = 1") + "]}"))
        #expect(code == [.codeBlock("val a = 1")])
    }

    @Test func horizontalRule() {
        #expect(blocks(Fixture.doc(#"{"type":"horizontalRule"}"#)) == [.horizontalRule])
    }

    @Test func tableRowsAndCells() {
        let cell = #"{"type":"tableCell","content":["# + Fixture.paragraph(Fixture.text("c")) + "]}"
        let row = #"{"type":"tableRow","content":["# + cell + "," + cell + "]}"
        let table = blocks(
            Fixture.doc(#"{"type":"table","content":["# + [row, row, row].joined(separator: ",") + "]}")
        )
        guard case .table(let rows) = table.first else {
            Issue.record("Expected a table")
            return
        }
        #expect(rows.count == 3)
        #expect(rows.first?.count == 2)
    }

    @Test func unknownNodeWithContentRendersItsChildren() {
        let group = blocks(
            Fixture.doc(#"{"type":"callout","content":["# + Fixture.paragraph(Fixture.text("inside")) + "]}")
        )
        #expect(group == [.group([.paragraph([.text("inside")])])])
    }

    @Test func unknownLeafNodeIsDropped() {
        #expect(blocks(Fixture.doc(#"{"type":"image","attrs":{"src":"x"}}"#)).isEmpty)
    }

    @Test func looseInlineNodesAtTheTopBecomeAParagraph() {
        #expect(blocks(Fixture.doc(Fixture.text("loose"))) == [.paragraph([.text("loose")])])
    }

    @Test func emptyTextNodesAreSkipped() {
        #expect(blocks(Fixture.doc(Fixture.paragraph(Fixture.text("")))) == [.paragraph([])])
    }

    @Test func extractFindsADocWrappedInAnEnvelope() {
        let doc = Fixture.doc(Fixture.paragraph(Fixture.text("hi")))
        let wrapped = JSONValue.object(["messageDoc": .object(["doc": doc])])
        #expect(TipTapParser.extractDoc(wrapped, text: nil)?["type"]?.stringValue == "doc")
    }

    @Test func extractFindsAStringifiedDoc() throws {
        let raw = #"{"type":"doc","content":["# + Fixture.paragraph(Fixture.text("hi")) + "]}"
        let once = JSONValue.string(raw)
        let encodedTwice = String(decoding: try JSONEncoder().encode(raw), as: UTF8.self)
        let twice = JSONValue.string(encodedTwice)
        #expect(TipTapParser.extractDoc(once, text: nil).map(TipTapParser.plainText) == "hi")
        #expect(TipTapParser.extractDoc(twice, text: nil).map(TipTapParser.plainText) == "hi")
    }

    @Test func textIsReadAsADocOnlyWhenItMentionsAnEditor() {
        let docJSON = #"{"type":"doc","content":["# + Fixture.paragraph(Fixture.text("from text")) + "]}"
        let editorPayload = #"{"editor":"tiptap","doc":"# + docJSON + "}"
        #expect(TipTapParser.extractDoc(nil, text: editorPayload).map(TipTapParser.plainText) == "from text")
        #expect(TipTapParser.extractDoc(nil, text: docJSON) == nil)
    }

    @Test func deepNestingStopsAtTheDepthLimit() {
        var payload = Fixture.doc(Fixture.paragraph(Fixture.text("deep")))
        for _ in 0..<12 { payload = .object(["data": payload]) }
        #expect(TipTapParser.extractDoc(payload, text: nil) == nil)
    }

    @Test func plainTextProjection() {
        let doc = Fixture.doc(
            Fixture.paragraph(Fixture.text("Hi "), #"{"type":"mention","attrs":{"label":"Priya"}}"#),
            Fixture.paragraph(),
            Fixture.paragraph(),
            Fixture.paragraph(Fixture.text("line"), #"{"type":"hardBreak"}"#, Fixture.text("two"))
        )
        #expect(TipTapParser.plainText(doc) == "Hi @Priya\n\nline\ntwo")
    }

    @Test func copyableTextPrefersTheDocAndIsEmptyWhenDeleted() {
        var message = Fixture.message(1, text: "stored")
        message.doc = Fixture.doc(Fixture.paragraph(Fixture.text("rich")))
        #expect(message.copyableText == "rich")
        message.doc = nil
        #expect(message.copyableText == "stored")
        message.isDeleted = true
        #expect(message.copyableText.isEmpty)
    }

    @Test func documentForAMessageWithoutDocIsNil() {
        #expect(TipTapParser.document(for: Fixture.message(1, text: "just text")) == nil)
    }

    @Test func onlyHttpAndHttpsLinksWithAHostOpen() {
        #expect(SafeLinks.url("https://waivera.example/a") != nil)
        #expect(SafeLinks.url("HTTP://waivera.example") != nil)
        for unsafe in ["javascript:alert(1)", "file:///etc/hosts", "waivera://chat/7", "https:///nohost", "", nil] {
            #expect(SafeLinks.url(unsafe) == nil)
        }
    }
}

/// How inline marks, links and mentions become attributed text (03 §7).
@Suite("Rich text attributes")
struct RichTextAttributeTests {
    @Test func marksAreCarriedAsOneAttribute() {
        let all = Set(RichMark.allCases)
        let text = RichTextAttributes.attributed([.text("x", marks: all)])
        #expect(text.runs.count == 1)
        #expect(text.runs.first?[RichMarksAttribute.self] == all)
    }

    @Test func linkKeepsItsMarks() {
        let url = URL(string: "https://waivera.example/plan")
        let text = RichTextAttributes.attributed([.text("plan", marks: [.bold], href: url)])
        #expect(text.runs.first?.link == url)
        #expect(text.runs.first?[RichMarksAttribute.self] == [.bold])
    }

    @Test func textWithoutHrefHasNoLink() {
        let text = RichTextAttributes.attributed([.text("plain")])
        #expect(text.runs.allSatisfy { $0.link == nil })
    }

    @Test func mentionIsAtPrefixedAndTagged() {
        let text = RichTextAttributes.attributed([.mention("Priya Raman")])
        #expect(String(text.characters) == "@Priya Raman")
        #expect(text.runs.first?[RichMentionAttribute.self] == "Priya Raman")
    }

    @Test func hardBreakIsANewline() {
        let text = RichTextAttributes.attributed([.text("a"), .hardBreak, .text("b")])
        #expect(String(text.characters) == "a\nb")
    }
}
