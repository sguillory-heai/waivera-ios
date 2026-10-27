import Testing

@testable import ChatFeature

struct PreviewPlainTextTests {
    @Test("Plain text is returned unchanged")
    func plain() {
        #expect(PreviewPlainText.plainText("see you {at} 5") == "see you {at} 5")
    }

    @Test("A document under a wrapper key or encoded twice is found")
    func wrappedAndDoubleEncoded() {
        let wrapped =
            #"{"editor": {"type": "doc", "content": [{"type": "paragraph", "content": [{"type": "text", "text": "Wrapped"}]}]}}"#
        #expect(PreviewPlainText.plainText(wrapped) == "Wrapped")
        let inner =
            #"{\"type\":\"doc\",\"content\":[{\"type\":\"paragraph\",\"content\":[{\"type\":\"text\",\"text\":\"Twice\"}]}]}"#
        let twice = #"{"type": "wrapper", "doc": ""# + inner + #""}"#
        #expect(PreviewPlainText.plainText(twice) == "Twice")
    }

    @Test("Broken JSON falls back to the raw string")
    func brokenJSON() {
        let raw = #"{"type": "doc", "content": ["#
        #expect(PreviewPlainText.plainText(raw) == raw)
    }

    @Test("Timestamp tokens are removed from system text")
    func systemToken() {
        #expect(SystemText.clean("Call started {[TIMESTAMP- 8/1/2026 2:20:12]} - ") == "Call started")
    }
}
