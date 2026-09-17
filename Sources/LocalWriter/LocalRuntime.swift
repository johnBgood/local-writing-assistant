import Foundation

@MainActor
final class LocalRuntime {
    enum StartupError: LocalizedError {
        case missingOllama, missingModel, serverFailed, warmupFailed
        var errorDescription: String? {
            switch self {
            case .missingOllama: return "Install Ollama, then choose Start Local Model."
            case .missingModel: return "Download the model first: ollama pull qwen3:4b"
            case .serverFailed: return "Ollama could not start. Choose Start Local Model to retry."
            case .warmupFailed: return "Qwen3 could not load. Choose Start Local Model to retry."
            }
        }
    }
    struct Installation {
        let executable: URL
        let models: URL?
    }
    private var process: Process?
    private let session: URLSession
    private let installations: [Installation]
    init(session: URLSession = .shared, installations: [Installation]? = nil) {
        self.session = session
        let root = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
        let runtime = root.appendingPathComponent(".local-runtime")
        let home = FileManager.default.homeDirectoryForCurrentUser
        let paths = ["/Applications/Ollama.app/Contents/Resources/ollama",
                     home.appendingPathComponent("Applications/Ollama.app/Contents/Resources/ollama").path,
                     "/opt/homebrew/bin/ollama", "/usr/local/bin/ollama"]
            + (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map { "\($0)/ollama" }
        self.installations = installations ?? [Installation(executable: runtime.appendingPathComponent("ollama"), models: runtime.appendingPathComponent("models"))]
            + paths.map { Installation(executable: URL(fileURLWithPath: $0), models: nil) }
    }
    private func availableModels() async -> [String]? {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:11434/api/tags")!)
        request.timeoutInterval = 2
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        struct Tags: Decodable { struct Model: Decodable { let name: String }; let models: [Model] }
        return (try? JSONDecoder().decode(Tags.self, from: data))?.models.map(\.name)
    }
    func start(progress: (String) -> Void = { _ in }) async throws {
        progress("Connecting to local model…")
        var models = await availableModels()
        try Task.checkCancellation()
        if models == nil {
            progress("Starting Ollama…")
            if process?.isRunning != true {
                guard let installation = installations.first(where: { FileManager.default.isExecutableFile(atPath: $0.executable.path) }) else {
                    throw StartupError.missingOllama
                }
                let child = Process(); child.executableURL = installation.executable; child.arguments = ["serve"]
                var env = ProcessInfo.processInfo.environment
                if let models = installation.models { env["OLLAMA_MODELS"] = models.path }
                env["OLLAMA_HOST"] = "127.0.0.1:11434"
                env["OLLAMA_NO_CLOUD"] = "1"; env["OLLAMA_NOHISTORY"] = "1"
                child.environment = env
                child.standardOutput = FileHandle.nullDevice; child.standardError = FileHandle.nullDevice
                do { try child.run() } catch { throw StartupError.serverFailed }
                process = child
            }
            for _ in 0..<40 {
                try await Task.sleep(nanoseconds: 250_000_000)
                models = await availableModels()
                if models != nil { break }
                if process?.isRunning == false { break }
            }
        }
        try Task.checkCancellation()
        guard let models else { throw StartupError.serverFailed }
        guard models.contains("qwen3:4b") else { throw StartupError.missingModel }
        progress("Loading Qwen3…")
        var request = URLRequest(url: URL(string: "http://127.0.0.1:11434/api/generate")!)
        request.httpMethod = "POST"; request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // An empty prompt preloads the model without sending any editor text.
        request.httpBody = try JSONSerialization.data(withJSONObject: ["model": "qwen3:4b", "prompt": "", "stream": false, "keep_alive": "5m", "options": ["num_ctx": 8192]])
        do {
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let result = try JSONSerialization.jsonObject(with: data) as? [String: Any], result["done"] as? Bool == true else { throw StartupError.warmupFailed }
        } catch {
            try Task.checkCancellation()
            throw StartupError.warmupFailed
        }
        try Task.checkCancellation()
    }
    // Never terminate a server that was already running before this app started.
    func stop() { if process?.isRunning == true { process?.terminate() } }
}
