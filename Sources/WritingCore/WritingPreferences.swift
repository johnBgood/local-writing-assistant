import Foundation
import Darwin

public struct WritingPreferences: Codable, Equatable {
    public var language = "auto"
    public var words: [String] = []
    public init() {}
    public static let languages = ["auto", "en", "fr", "de"]
    public var instruction: String {
        switch language {
        case "en": return "The writing language is English."
        case "fr": return "The writing language is French."
        case "de": return "The writing language is German."
        default: return "Detect English, French or German independently for each sentence. Preserve the original language, including mixed-language passages."
        }
    }
}

public enum PreferenceStore {
    public static func read() throws -> WritingPreferences { try update { _ in } }
    // A lock file serializes updates across the Mac app and one-shot Chrome hosts.
    @discardableResult public static func update(_ mutation: (inout WritingPreferences) throws -> Void) throws -> WritingPreferences {
        let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/LocalWriter")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let lock = open(folder.appendingPathComponent("preferences.lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard lock >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        defer { flock(lock, LOCK_UN); close(lock) }
        guard flock(lock, LOCK_EX) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        let file = folder.appendingPathComponent("preferences.json")
        let old = FileManager.default.fileExists(atPath: file.path) ? try Data(contentsOf: file) : nil
        var prefs = try old.map { try JSONDecoder().decode(WritingPreferences.self, from: $0) } ?? WritingPreferences()
        try mutation(&prefs)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(prefs)
        if old != data { try data.write(to: file, options: [.atomic]); try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path) }
        return prefs
    }
    public static func word(at range: NSRange, in text: String) -> String? {
        let regex = try! NSRegularExpression(pattern: "[\\p{L}\\p{M}\\p{N}]+(?:['’\\-][\\p{L}\\p{M}\\p{N}]+)*")
        let source = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: source.length))
            .first { NSIntersectionRange($0.range, range).length > 0 }.map { source.substring(with: $0.range) }
    }
    public static func validWord(_ word: String) -> Bool {
        !word.isEmpty && word.count <= 80 && word.range(of: "^[\\p{L}\\p{M}\\p{N}]+(?:['’\\-][\\p{L}\\p{M}\\p{N}]+)*$", options: .regularExpression) != nil
    }
    public static func add(_ word: String) throws {
        guard validWord(word) else { throw NSError(domain: "LocalWriter", code: 1, userInfo: [NSLocalizedDescriptionKey: "Enter one word, up to 80 characters."]) }
        try update { prefs in
            if !prefs.words.contains(word) {
                guard prefs.words.count < 1000 else { throw NSError(domain: "LocalWriter", code: 2, userInfo: [NSLocalizedDescriptionKey: "Dictionary limit: 1,000 words."]) }
                prefs.words.append(word); prefs.words.sort()
            }
        }
    }
}

public struct ProtectedWords {
    public let text: String
    private let originals: [(String, String)]
    public init(_ text: String, words: [String]) {
        let allowed = Set(words.map { $0.precomposedStringWithCanonicalMapping.lowercased() })
        let regex = try! NSRegularExpression(pattern: "[\\p{L}\\p{M}\\p{N}]+(?:['’\\-][\\p{L}\\p{M}\\p{N}]+)*")
        let source = text as NSString
        var prefix = "LWTERM"
        while text.contains(prefix) { prefix += "X" }
        var output = text, entries: [(String, String)] = []
        for match in regex.matches(in: text, range: NSRange(location: 0, length: source.length)).reversed() {
            let word = source.substring(with: match.range)
            if allowed.contains(word.precomposedStringWithCanonicalMapping.lowercased()) {
                let marker = prefix + "\(entries.count)"
                output = (output as NSString).replacingCharacters(in: match.range, with: marker)
                entries.append((marker, word))
            }
        }
        self.text = output; self.originals = entries
    }
    public func restore(_ output: String) throws -> String {
        var result = output
        for (marker, word) in originals.sorted(by: { $0.0.count > $1.0.count }) {
            guard result.components(separatedBy: marker).count == 2 else {
                throw NSError(domain: "LocalWriter", code: 3, userInfo: [NSLocalizedDescriptionKey: "The model changed a protected dictionary word. Please try again."])
            }
            result = result.replacingOccurrences(of: marker, with: word)
        }
        return result
    }
}
