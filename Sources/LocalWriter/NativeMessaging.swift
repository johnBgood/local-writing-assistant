import Foundation

/// Chrome's framed stdin/stdout protocol. No document text is logged or persisted.
enum NativeMessaging {
    struct Request: Decodable { let method: String; let text: String? }
    static func readExactly(_ count: Int) -> Data? {
        var data = Data()
        while data.count < count {
            let chunk = FileHandle.standardInput.readData(ofLength: count - data.count)
            if chunk.isEmpty { return nil }
            data.append(chunk)
        }
        return data
    }
    static func run() {
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            defer { done.signal() }
            guard let header = readExactly(4) else { return }
            let length = header.enumerated().reduce(0) { $0 | (Int($1.element) << ($1.offset * 8)) }
            guard length > 0, length <= 65536, let data = readExactly(length) else { return }
            var response: [String: Any]
            do {
                let request = try JSONDecoder().decode(Request.self, from: data)
                if request.method == "ping" {
                    response = ["ok": true, "version": 1]
                } else {
                    guard let text = request.text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.utf16.count <= 4000 else {
                        throw NativeError.invalidText
                    }
                    switch request.method {
                    case "analyze":
                        let edits = try await LocalModel().analyze(text)
                        response = ["ok": true, "edits": edits.map { ["start": $0.range.location, "length": $0.range.length, "original": $0.original, "replacement": $0.replacement] as [String: Any] }]
                    case "rewrite": response = ["ok": true, "rewrite": try await LocalModel().rewrite(text)]
                    default: throw NativeError.invalidMethod
                    }
                }
            } catch { response = ["ok": false, "error": error.localizedDescription] }
            guard let output = try? JSONSerialization.data(withJSONObject: response) else { return }
            var size = UInt32(output.count).littleEndian
            FileHandle.standardOutput.write(Data(bytes: &size, count: 4))
            FileHandle.standardOutput.write(output)
        }
        done.wait()
    }
    enum NativeError: LocalizedError {
        case invalidText, invalidMethod
        var errorDescription: String? {
            self == .invalidText ? "Select or enter 1–4,000 characters." : "Unsupported request."
        }
    }
}
