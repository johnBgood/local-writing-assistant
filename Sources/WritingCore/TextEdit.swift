import Foundation

public struct TextEdit: Equatable, Sendable {
    public let range: NSRange
    public let original: String
    public let replacement: String
    public init(range: NSRange, original: String, replacement: String) {
        self.range = range; self.original = original; self.replacement = replacement
    }
    public func applying(to current: String, snapshot: String) -> String? {
        guard current == snapshot, range.location >= 0, range.length > 0,
              range.location <= (current as NSString).length,
              range.length <= (current as NSString).length - range.location,
              let swiftRange = Range(range, in: current),
              String(current[swiftRange]) == original else { return nil }
        return current.replacingCharacters(in: swiftRange, with: replacement)
    }
}

public enum SentenceRanges {
    public static func inText(_ text: String) -> [NSRange] {
        var ranges: [NSRange] = []
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: .bySentences) { _, range, _, _ in
            let sentence = String(text[range])
            let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, let inner = sentence.range(of: trimmed) {
                let outer = NSRange(range, in: text)
                let offset = NSRange(inner, in: sentence)
                ranges.append(NSRange(location: outer.location + offset.location, length: offset.length))
            }
        }
        return ranges
    }
}
