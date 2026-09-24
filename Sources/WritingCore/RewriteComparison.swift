import Foundation

public enum RewriteComparison {
    /// A style suggestion must do more than alter whitespace, case or punctuation.
    public static func hasWordingChange(from source: String, to result: String) -> Bool {
        func words(_ text: String) -> [String] {
            let normalized = text.precomposedStringWithCanonicalMapping.lowercased()
            let regex = try! NSRegularExpression(pattern: #"[\p{L}\p{M}\p{N}]+"#)
            let ns = normalized as NSString
            return regex.matches(in: normalized, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) }
        }
        return words(source) != words(result)
    }
}
