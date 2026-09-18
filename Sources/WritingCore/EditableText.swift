import Foundation

/// Some rich editors expose a private-use list glyph in AXValue, even though
/// it is not editable text. Child leaves can add a space after the same glyph.
/// Keep an exact UTF-16 map; never allow an edit to cross a removed decoration.
public struct EditableText {
    public let text: String
    private let offsets: [Int]
    public init(_ source: String) {
        let ns = source as NSString
        let pattern = try! NSRegularExpression(pattern: "(?m)^[\\t ]*\u{E506}[\\t ]*")
        let removed = pattern.matches(in: source, range: NSRange(location: 0, length: ns.length)).map(\.range)
        var text = "", offsets: [Int] = [], start = 0
        for range in removed + [NSRange(location: ns.length, length: 0)] {
            text += ns.substring(with: NSRange(location: start, length: range.location - start))
            offsets.append(contentsOf: start..<range.location)
            start = NSMaxRange(range)
        }
        self.text = text; self.offsets = offsets
    }
    public func sourceRange(_ range: NSRange) -> NSRange? {
        guard range.location >= 0, range.length > 0, range.location < offsets.count,
              range.length <= offsets.count - range.location else { return nil }
        let start = offsets[range.location], end = offsets[NSMaxRange(range) - 1] + 1
        guard end - start == range.length else { return nil }
        return NSRange(location: start, length: range.length)
    }
}
