import Foundation
import WritingCore
func XCTAssertEqual<T: Equatable>(_ lhs: T, _ rhs: T) { precondition(lhs == rhs, "Expected \(rhs), got \(lhs)") }
func XCTAssertNil<T>(_ value: T?) { precondition(value == nil, "Expected nil") }
final class TextEditTests {
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
        tests.testUnicodeReplacementAndStaleRejection()
        tests.testInvalidRanges()
        tests.testSentenceRangesPreserveUnicodeOffsets()
        print("PASS: Unicode replacements, stale edits, invalid ranges, sentence offsets")
    }
}
