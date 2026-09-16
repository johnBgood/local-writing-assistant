import Foundation
import WritingCore
func XCTAssertEqual<T: Equatable>(_ lhs: T, _ rhs: T) { precondition(lhs == rhs, "Expected \(rhs), got \(lhs)") }
func XCTAssertNil<T>(_ value: T?) { precondition(value == nil, "Expected nil") }
final class TextEditTests {
    func testHighlightRangesAndContainerFocus() {
        XCTAssertEqual(TextLeafRanges.align(["Hello", "👋 wrong words"], in: "Hello\n\n👋 wrong words\n"), [NSRange(location: 0, length: 5), NSRange(location: 7, length: 14)])
        XCTAssertEqual(TextLeafRanges.align(["same", "same"], in: "same\nsame"), [NSRange(location: 0, length: 4), NSRange(location: 5, length: 4)])
        XCTAssertNil(TextLeafRanges.align(["wrong"], in: "Unrelated wrong"))
        XCTAssertNil(TextLeafRanges.align(["Hello"], in: "Hello extra"))
        let text = "Hello\n\nwrong words\n"
        let ranges = HighlightRanges.words(in: NSRange(location: 0, length: text.utf16.count), text: text)
        XCTAssertEqual(ranges.map { (text as NSString).substring(with: $0) }, ["Hello", "wrong", "words"])
        XCTAssertEqual(HighlightRanges.words(in: NSRange(location: 5, length: 2), text: text), [])
        struct Node { let id: Int; var children: [Node] = []; var editor = false; var focused = false; var secure = false }
        func resolve(_ root: Node) -> Int? {
            EditorSearch.resolve(root: root, children: { $0.children }, isEditor: { $0.editor }, isTextArea: { $0.editor }, isFocused: { $0.focused }, isSecure: { $0.secure })?.id
        }
        let composer = Node(id: 2, editor: true)
        XCTAssertEqual(resolve(Node(id: 0, children: [Node(id: 1, children: [composer])])), 2)
        XCTAssertNil(resolve(Node(id: 0, children: [composer, Node(id: 3, editor: true)])))
        XCTAssertEqual(resolve(Node(id: 0, children: [composer, Node(id: 3, editor: true, focused: true)])), 3)
        XCTAssertNil(resolve(Node(id: 0, children: [Node(id: 1, children: [composer], secure: true)])))
        // A bounded traversal must not mistake a partial tree for a unique editor.
        XCTAssertNil(resolve(Node(id: 0, children: [composer] + (3...260).map { Node(id: $0) } + [Node(id: 261, editor: true)])))
    }
    func testBlankLinesAreNotCorrections() {
        let edits = ModelEdits.difference(from: "A speling mistake.\n\n", to: "A spelling mistake.")
        XCTAssertEqual(edits.count, 1)
        XCTAssertEqual(edits.first?.original, "speling")
        XCTAssertEqual(ModelEdits.difference(from: "Hello.\n\n", to: "Hello.").count, 0)
    }
    func testModelEditValidation() {
        let text = "👋 A speling mistake. She go yesterday."
        let corrected = "👋 A spelling mistake. She went yesterday."
        let edits = ModelEdits.difference(from: text, to: corrected)
        XCTAssertEqual(edits.count, 2)
        XCTAssertEqual(edits[0].range, (text as NSString).range(of: "speling"))
        for (old, new) in [
            (text, corrected), ("This is test.", "This is a test."),
            ("This is a a test.", "This is a test."), ("Hello", "Hello!"),
            ("go go", "went go"), ("hello", "Well, hello"),
            ("Hello 👋 there", "Hello there"), ("Hello!", "Hello"),
            ("This is correct.", "This is correct.")
        ] {
            var actual = old as NSString
            for edit in ModelEdits.difference(from: old, to: new).reversed() {
                actual = actual.replacingCharacters(in: edit.range, with: edit.replacement) as NSString
            }
            XCTAssertEqual(actual as String, new)
        }
    }
    func testAppMenuState() {
        var state = AppAvailability()
        XCTAssertEqual(state.actionTitle, "Select an app to enable or disable")
        state.toggle()
        XCTAssertEqual(state.excluded, [])
        state.capture(.init(id: "codex", name: "Codex"))
        XCTAssertEqual(state.actionTitle, "Disable for Codex")
        state.toggle()
        XCTAssertEqual(state.actionTitle, "Enable for Codex")
        XCTAssertEqual(state.statusTitle, "Disabled for Codex")
        state.capture(.init(id: "slack", name: "Slack"))
        XCTAssertEqual(state.actionTitle, "Disable for Slack")
        state.toggle()
        XCTAssertEqual(state.excluded, ["codex", "slack"])
        state.capture(.init(id: "codex", name: "Codex"))
        state.toggle()
        XCTAssertEqual(state.statusTitle, "Enabled for Codex")
        XCTAssertEqual(state.excluded, ["slack"])
        let restored = AppAvailability(excluded: state.excluded)
        XCTAssertEqual(restored.excluded, ["slack"])
    }
    func testUnicodeReplacementAndStaleRejection() {
        let text = "👋 This is teh draft."
        let range = (text as NSString).range(of: "teh")
        let edit = TextEdit(range: range, original: "teh", replacement: "the")
        XCTAssertEqual(edit.applying(to: text, snapshot: text), "👋 This is the draft.")
        XCTAssertNil(edit.applying(to: text + " More", snapshot: text))
        XCTAssertNil(TextEdit(range: range, original: "bad", replacement: "the").applying(to: text, snapshot: text))
    }
    func testInvalidRanges() {
        for range in [NSRange(location: NSNotFound, length: 1), NSRange(location: 0, length: Int.max), NSRange(location: 0, length: 1)] {
            XCTAssertNil(TextEdit(range: range, original: "👋", replacement: "Hi").applying(to: "👋", snapshot: "👋"))
        }
    }
    func testSentenceRangesPreserveUnicodeOffsets() {
        let text = "👋 Hello there. This is next!"
        let sentences = SentenceRanges.inText(text).map { (text as NSString).substring(with: $0) }
        XCTAssertEqual(sentences, ["👋 Hello there.", "This is next!"])
    }
}

@main struct CoreChecks {
    static func main() {
        let tests = TextEditTests()
        tests.testHighlightRangesAndContainerFocus()
        tests.testBlankLinesAreNotCorrections()
        tests.testModelEditValidation()
        tests.testAppMenuState()
        tests.testUnicodeReplacementAndStaleRejection()
        tests.testInvalidRanges()
        tests.testSentenceRangesPreserveUnicodeOffsets()
        print("PASS: model-edit validation, app menu states, Unicode replacements, stale edits, invalid ranges, sentence offsets")
    }
}
